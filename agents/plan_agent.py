"""
agents/plan_agent.py
Plan Agent: nhận prompt + rag_context, tạo kế hoạch thiết kế đầy đủ.
Đảm bảo generation_order được sắp xếp theo Topological Sort (bottom-up).
"""
import os
import json
import re
import time
from dotenv import load_dotenv
from langchain_openai import ChatOpenAI
from langchain_core.prompts import ChatPromptTemplate
from langchain_core.output_parsers import StrOutputParser

load_dotenv()

MODEL_NAME = os.environ.get("OPENAI_MODEL", "gpt-5.4")

_llm = ChatOpenAI(model=MODEL_NAME, temperature=0)

_PLAN_STAGE1_PROMPT = """\
You are a senior RTL architect.

Create PHASE 1 of an implementation plan for both RTL and Testbench.
This phase must stay compact and focus on architecture only.

User Request:
{prompt}

RAG Context (modules, ports, inferred testcases):
{rag_context}

Return ONLY valid JSON:
{{
  "design_summary": {{
    "name": "",
    "type": "",
    "description": "",
    "clock_frequency_mhz": 0
  }},
  "modules": [
    {{
      "name": "",
      "description": "",
      "file": "<name>.sv",
      "implementation_style": "combinational|sequential|fsm|pipeline|storage|controller",
      "signals": [
        {{"name": "", "direction": "input|output", "width": 0, "description": ""}}
      ]
    }}
  ],
  "packages": [
    {{
      "name": "",
      "file": "<name>_pkg.sv",
      "description": "Global constants/enums/typedefs"
    }}
  ],
  "generation_order": ["<pkg>.sv", "<leaf_sub_module>.sv", "<mid_module>.sv", "<top>.sv"],
  "dependency_graph": {{
    "<top_module>": ["<sub1>", "<sub2>"]
  }},
  "rtl_rules": {{
    "synthesizable": true,
    "use_always_ff_comb": true,
    "async_reset": true,
    "no_delays": true,
    "no_latches": true,
    "bit_width_must_match": true,
    "each_module_own_file": true,
    "timescale": "`timescale 1ns/1ps"
  }},
  "tb_rules": {{
    "style": "module_with_ports",
    "tb_does_not_instantiate_dut": true,
    "no_fatal_on_test_fail": true,
    "use_fail_count_not_fatal": true,
    "print_pass_fail_each_case": true,
    "print_summary_at_end": true,
    "continue_after_fail": true,
    "watchdog_timeout": 1000000,
    "test_reset_behavior": true,
    "test_boundary_values": true
  }},
  "external_interfaces": []
}}

Rules:
1. generation_order MUST be a STRICT TOPOLOGICAL SORT (bottom-up dependency order).
2. Top module MUST instantiate ALL sub-modules.
3. For top-level integration modules (for example names ending in _top or CPU/pipeline integration wrappers), preserve enough port/interface structure to support OBSERVABLE integration verification in phase 2.
4. Keep this phase compact: do NOT include behavior_contract and do NOT include testcase_plan yet.
5. Preserve enough module/port structure so a second phase can enrich semantics and testcases.
6. TB style = "module_with_ports" — TB does NOT instantiate DUT.

Return ONLY the JSON.
"""

_PLAN_STAGE2_PROMPT = """\
You are a senior RTL architect.

Create PHASE 2 of the implementation plan by enriching the phase-1 scaffold.
Do not redesign the module hierarchy. Reuse the exact module names/files from phase 1.

User Request:
{prompt}

RAG Context (modules, ports, inferred testcases):
{rag_context}

Phase 1 Plan Scaffold:
{stage1_plan}

Return ONLY valid JSON:
{{
  "module_details": [
    {{
      "name": "",
      "behavior_contract": {{
        "module_kind": "combinational|sequential",
        "clocked_inputs": [],
        "reset_behavior": "",
        "state_elements": [],
        "handshake_protocol": "",
        "output_timing": "",
        "retention_rules": "",
        "completion_semantics": "",
        "forbidden_assumptions": []
      }}
    }}
  ],
  "testcase_plan": [
    {{
      "module": "<module_name>",
      "tb_file": "tb_<module_name>.sv",
      "testcases": [
        {{
          "id": "TC001",
          "operation": "<operation name, e.g. ADD / SUB / RESET>",
          "stimulus": "<concrete input values for every port>",
          "expected": "<expected output value(s)>",
          "checks": [
            {{
              "signal": "<exact DUT output name>",
              "value": "<expected value>",
              "condition": "<when this check is meaningful>"
            }}
          ],
          "timing_contract": {{
            "sample_event": "combinational_after_settle|posedge_plus_1|negedge_plus_1",
            "same_cycle_response_allowed": true,
            "latency_cycles": 0,
            "output_persistence": "pulse|level|hold_until_next_request",
            "notes": ""
          }}
        }}
      ]
    }}
  ]
}}

Rules:
1. testcase_plan MUST include ALL inferred testcases from rag_context for EVERY module.
   - ONE testcase per distinct operation/function — exactly matching the inferred_testcases list.
   - Do NOT add extra testcases for boundary values, commutativity, stability, transitions,
     or output-range checking. Those are NOT required.
   - For combinational modules with no clock/reset, do NOT add reset or clock testcases.
2. For EVERY module, fill behavior_contract with explicit timing/semantic rules that an RTL engineer and a TB engineer can both implement consistently.
3. For top-level integration modules (for example names ending in _top or CPU/pipeline integration wrappers):
   - verification scope MUST be observable integration behavior, not hidden internal datapath proof.
   - testcase checks MUST prefer top-level outputs and externally visible side effects only.
   - datapath-class operations such as ADD/SUB/logic/shift/MUL/compressed ALU forms should be represented as observable execution/no-trap/request-flow scenarios unless a concrete result is actually exposed at the top interface.
   - branch/jump/load/store/interrupt/trap/boot/MRET/externally visible CSR routing should use explicit observable checks.
4. For EVERY testcase, fill timing_contract so the checker knows when outputs should be sampled.
5. Reuse exact module names from phase 1. Do not add new modules or rename any module.
6. Keep this phase focused on semantics and tests only.

Return ONLY the JSON.
"""

_plan_stage1_chain = ChatPromptTemplate.from_template(_PLAN_STAGE1_PROMPT) | _llm | StrOutputParser()
_plan_stage2_chain = ChatPromptTemplate.from_template(_PLAN_STAGE2_PROMPT) | _llm | StrOutputParser()


def _safe_call(chain, inputs: dict, label: str = "PLAN_AGENT", max_retries: int = 5) -> str:
    retries = 0
    while retries < max_retries:
        try:
            result = ""
            try:
                for chunk in chain.stream(inputs):
                    result += chunk
            except ValueError as e:
                if "No generation chunks were returned" in str(e):
                    result = ""
                else:
                    raise

            if not result.strip():
                try:
                    fallback = chain.invoke(inputs)
                    result = fallback if isinstance(fallback, str) else str(fallback)
                except Exception:
                    pass

            if not result.strip():
                retries += 1
                print(f"[{label}] Empty/streamless response. Retry ({retries}/{max_retries})...")
                time.sleep(5)
                continue
            return result
        except Exception as e:
            err = str(e)
            if "No generation chunks were returned" in err:
                retries += 1
                print(f"[{label}] Stream returned no chunks. Retry ({retries}/{max_retries})...")
                time.sleep(5)
            elif "Rate limit" in err or "429" in err or "rate_limit_error" in err or "Concurrency" in err:
                retries += 1
                print(f"[{label}] Rate limit/Concurrency. Waiting 30s ({retries}/{max_retries})...")
                time.sleep(30)
            elif any(k in err for k in ["524", "timeout", "5xx", "503", "502", "500", "stream_read_error", "APIError", "InternalServerError", "Upstream request failed", "Upstream service temporarily unavailable", "temporarily unavailable", "Connection error", "APIConnectionError"]):
                retries += 1
                print(f"[{label}] API error: {err}. Waiting 30s ({retries}/{max_retries})...")
                time.sleep(30)
            else:
                raise
    raise RuntimeError(f"[{label}] Failed after max retries.")


def _parse_json(text: str) -> dict:
    text = text.strip()
    match = re.search(r"```(?:json)?\s*(.*?)\s*```", text, re.DOTALL)
    if match:
        text = match.group(1).strip()
    else:
        s, e = text.find("{"), text.rfind("}")
        if s != -1 and e > s:
            text = text[s:e+1]
    try:
        return json.loads(text)
    except Exception:
        print("[PLAN_AGENT] JSON parse failed.")
        return {}


def _validate_topological_order(plan: dict) -> list:
    """
    Kiểm tra và đảm bảo generation_order đúng thứ tự topological.
    Nếu LLM sinh sai thứ tự, tự tính lại dựa trên dependency_graph.
    Trả về danh sách file đã sắp xếp đúng.
    """
    gen_order = plan.get("generation_order", [])
    dep_graph = plan.get("dependency_graph", {})
    packages = [p.get("file", "") for p in plan.get("packages", [])]
    modules = {m.get("name"): m.get("file", f"{m.get('name')}.sv")
               for m in plan.get("modules", [])}

    file_to_name = {v: k for k, v in modules.items()}

    visited = set()
    order = []

    def dfs(fname: str):
        if fname in visited:
            return
        visited.add(fname)
        name = file_to_name.get(fname, fname.replace(".sv", ""))
        deps = dep_graph.get(name, [])
        for dep_name in deps:
            dep_file = modules.get(dep_name, f"{dep_name}.sv")
            dfs(dep_file)
        if fname not in packages:
            order.append(fname)

    result = list(packages)
    visited.update(packages)

    for fname in gen_order:
        if fname not in packages:
            dfs(fname)

    for name, fname in modules.items():
        if fname not in visited:
            dfs(fname)

    result.extend(order)

    if result != gen_order:
        print("[PLAN_AGENT] ⚠️  generation_order từ LLM không đúng Topological Sort.")
        print(f"[PLAN_AGENT]    LLM order: {gen_order}")
        print(f"[PLAN_AGENT]    Corrected: {result}")
    else:
        print(f"[PLAN_AGENT] ✅ generation_order hợp lệ: {result}")

    return result


def _is_top_like_module(module: dict) -> bool:
    name = (module.get("name") or "").lower()
    style = (module.get("implementation_style") or "").lower()
    return name.endswith("_top") or "cpu_top" in name or style in {"pipeline", "integration"}


def _normalize_plan_contracts(plan: dict) -> dict:
    """Bổ sung contract tối thiểu để RTL/TB agents có context rõ ràng hơn ở lần sinh đầu."""
    modules = plan.get("modules", [])
    tc_map = {entry.get("module"): entry for entry in plan.get("testcase_plan", [])}

    for module in modules:
        signals = module.get("signals", []) or []
        signal_names = {sig.get("name", "") for sig in signals}
        has_clk = "clk" in signal_names
        has_rst = any(name in signal_names for name in ("rst_n", "rst", "reset_n", "reset"))

        impl_style = module.get("implementation_style")
        if not impl_style:
            impl_style = "sequential" if has_clk or has_rst else "combinational"
            module["implementation_style"] = impl_style

        contract = module.get("behavior_contract") or {}
        contract.setdefault("module_kind", "sequential" if has_clk or has_rst else "combinational")
        contract.setdefault("clocked_inputs", [name for name in ("clk", "rst_n", "rst", "reset_n", "reset") if name in signal_names])
        contract.setdefault("reset_behavior", "Use asynchronous reset semantics." if has_rst else "No reset behavior.")
        contract.setdefault("state_elements", [])
        contract.setdefault("handshake_protocol", "None specified.")
        contract.setdefault("output_timing", "Outputs must follow the testcase timing contract.")
        contract.setdefault("retention_rules", "Do not assume stale output retention unless explicitly required.")
        contract.setdefault("completion_semantics", "None specified.")
        contract.setdefault("forbidden_assumptions", [
            "Do not assume same-cycle or next-cycle response unless stated in testcase timing_contract or module behavior_contract.",
            "Do not assume payload outputs retain prior nonzero values when their qualifier is low unless explicitly required."
        ])

        if _is_top_like_module(module):
            contract.setdefault("integration_scope", "observable_top_level_only")
            if contract.get("handshake_protocol") in (None, "", "None specified."):
                contract["handshake_protocol"] = "Verify only externally observable top-level request/response, redirect, boot, trap, and fail-stop behavior."
            if contract.get("output_timing") in (None, "", "Outputs must follow the testcase timing contract."):
                contract["output_timing"] = "For top-level integration modules, sample only architecturally visible or externally exposed outputs according to testcase timing_contract."
            if contract.get("retention_rules") in (None, "", "Do not assume stale output retention unless explicitly required."):
                contract["retention_rules"] = "Do not infer hidden internal datapath state from top-level tests unless an external output explicitly exposes it."
            forbidden = contract.get("forbidden_assumptions") or []
            extras = [
                "Do not require proof of hidden regfile contents, hidden ALU result buses, or hidden CSR state at top level unless exposed by a port.",
                "Treat datapath-class top-level tests as observable integration flows unless the final value is visible at the top interface."
            ]
            for item in extras:
                if item not in forbidden:
                    forbidden.append(item)
            contract["forbidden_assumptions"] = forbidden

        module["behavior_contract"] = contract

        tc_entry = tc_map.get(module.get("name"))
        if not tc_entry:
            continue
        for tc in tc_entry.get("testcases", []) or []:
            tc.setdefault("checks", [])
            timing = tc.get("timing_contract") or {}
            timing.setdefault(
                "sample_event",
                "posedge_plus_1" if contract["module_kind"] == "sequential" else "combinational_after_settle"
            )
            timing.setdefault("same_cycle_response_allowed", False if contract["module_kind"] == "sequential" else True)
            timing.setdefault("latency_cycles", 0)
            timing.setdefault("output_persistence", "level")
            timing.setdefault("notes", "")
            tc["timing_contract"] = timing

    return plan


def _merge_two_phase_plan(stage1: dict, stage2: dict) -> dict:
    plan = dict(stage1 or {})
    modules = plan.get("modules", []) or []
    detail_map = {
        entry.get("name"): entry
        for entry in (stage2.get("module_details", []) or [])
        if entry.get("name")
    }

    for module in modules:
        details = detail_map.get(module.get("name"), {})
        if details.get("behavior_contract"):
            module["behavior_contract"] = details["behavior_contract"]

    plan["modules"] = modules
    plan["testcase_plan"] = stage2.get("testcase_plan", []) or []
    return plan


def run(user_prompt: str, rag_context: dict) -> dict:
    print("\n[PLAN_AGENT] Creating design plan...")
    rag_str = json.dumps(rag_context, indent=2, ensure_ascii=False)

    stage1_text = _safe_call(
        _plan_stage1_chain,
        {"prompt": user_prompt, "rag_context": rag_str},
        label="PLAN_AGENT:STAGE1",
    )
    stage1 = _parse_json(stage1_text)

    if not stage1:
        return stage1

    stage1_str = json.dumps(stage1, indent=2, ensure_ascii=False)
    stage2_text = _safe_call(
        _plan_stage2_chain,
        {
            "prompt": user_prompt,
            "rag_context": rag_str,
            "stage1_plan": stage1_str,
        },
        label="PLAN_AGENT:STAGE2",
    )
    stage2 = _parse_json(stage2_text)
    plan = _merge_two_phase_plan(stage1, stage2)

    if not plan:
        return plan

    plan = _normalize_plan_contracts(plan)

    corrected_order = _validate_topological_order(plan)
    plan["generation_order"] = corrected_order

    modules = plan.get("modules", [])
    tc_plan = plan.get("testcase_plan", [])
    total_tc = sum(len(m.get("testcases", [])) for m in tc_plan)
    print(f"[PLAN_AGENT] Plan: {len(modules)} modules, {total_tc} test cases planned.")
    print(f"[PLAN_AGENT] Bottom-up generation order:")
    for i, fname in enumerate(corrected_order):
        print(f"  [{i+1}] {fname}")
    return plan
