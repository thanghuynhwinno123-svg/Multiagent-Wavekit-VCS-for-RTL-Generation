"""
agents/rtl_agent.py
RTL Agent: sinh synthesizable SystemVerilog RTL cho từng module riêng biệt.
Chiến lược Module-by-Module Bottom-up: mỗi lần gọi chỉ sinh DUY NHẤT 1 module.
"""
import os
import re
import json
import time
from dotenv import load_dotenv
from langchain_openai import ChatOpenAI
from langchain_core.prompts import ChatPromptTemplate
from langchain_core.output_parsers import StrOutputParser

load_dotenv()

MODEL_NAME = os.environ.get("OPENAI_MODEL", "gpt-5.4")

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
RTL_DIR  = os.path.join(BASE_DIR, "..", "generated_rtl")

_llm = ChatOpenAI(model=MODEL_NAME, temperature=0)

_SINGLE_RTL_PROMPT = """\
You are a senior RTL engineer specializing in SystemVerilog hardware design.

Generate the synthesizable SystemVerilog RTL code for ONLY the module: {target_module}
File to generate: {target_file}

=== MODULE-SCOPED DESIGN PLAN ===
{plan}

=== MODULE-SCOPED RAG CONTEXT ===
{rag_context}

=== ALREADY VERIFIED SUB-MODULES (do NOT regenerate these) ===
{verified_context}

=== ⚡ DEBUG INSTRUCTIONS FROM SPECIALIST AGENT (HIGHEST PRIORITY — FOLLOW EXACTLY) ===
{debug_instructions}

=== PRE-RTL SELF-REVIEW SUMMARY ===
{self_review}

[IMPORTANT]: If debug instructions are provided above (not "None"), you MUST follow them precisely.
The specialist agent has already identified the root cause and prescribed the exact fix.
Do NOT deviate from these instructions. Do NOT rewrite parts that are not mentioned.
Only modify what the debug instructions explicitly tell you to modify.
If a self-review summary is provided, use it only as a consistency checklist; debug instructions still take absolute priority.

=== MEMORY / PREVIOUS ERRORS FOR THIS MODULE ===
{memory}

=== FIRST-PASS CORRECTNESS STRATEGY ===
Before writing code, internally reconcile ONLY these sources in priority order:
1. The target module's testcase_plan and timing_contract
2. The target module's behavior_contract
3. The target module interface/signals
4. Relevant verified sub-module declarations
5. Remaining RAG prose
If there is any conflict, prefer the explicit testcase_plan + behavior_contract over generic narrative text.
Treat qualifier/data semantics carefully: if a payload is meaningful only when a qualifier is asserted, implement that contract explicitly rather than assuming stale retention.
For sequential modules, decide deliberately whether outputs are same-cycle combinational reactions or registered next-cycle observables based on the module behavior_contract and testcase timing_contract.

=== RTL REQUIREMENTS ===
- Synthesizable SystemVerilog ONLY
- Use always_ff / always_comb
- Asynchronous reset
- NO delays (#) in RTL
- NO latches (drive all outputs in every always_comb branch)
- Bit-widths must match exactly (decimal 4 needs 3 bits minimum)
- Import the design package (e.g., wildcard package import) at the top of the file. Do NOT redefine package constants as localparam inside modules.
- Every file MUST start with `timescale 1ns/1ps
- Do NOT generate any testbench (tb_*) file
- If this module instantiates sub-modules, use ONLY the already-verified sub-modules listed above.
  Do NOT modify or regenerate those sub-modules.
- FOR SEQUENTIAL DESIGNS ONLY (FSM, pipeline, designs with clk/rst):
  * CRITICAL FSM TIMING RULE: If the testbench expects control signals (like `done_o`, `fail_stop_o`, `spi_req_o`, or write enables) to reflect state changes immediately in the same cycle as a transition (e.g., same cycle as `spi_ready_i` or `spi_error_i`), these outputs MUST be driven combinationally (e.g., decoded directly in `always_comb` based on the next state `state_d` or current conditions) rather than solely relying on the registered state `state_q` (which delays outputs by 1 clock cycle).
  * Address/data output registers must not increment one word past the last valid index on the final transfer beat, and must hold their last copied values when the FSM exits the active copy phase.
- FOR COMBINATIONAL DESIGNS ONLY (no clock/reset, e.g., ALU, branch/jump units):
  * Do NOT add FSMs, clocks, resets, or sequential registers. Keep the design purely combinational using `always_comb` or continuous assignments.

=== HOW TO USE WAVEFORM / ERROR ANALYSIS (when no debug instructions provided) ===
Only use this section if debug instructions above are "None".

  FOR COMBINATIONAL DESIGN (no clock — alu, branch_jump_unit, etc.):
    The memory shows: [FAIL] TC=<name> | Signal='<sig>'  got=<X>  expected=<Y>
    Fix strategy:
      1. Look at the failing testcase name (TC) to identify the operation (e.g. BEQ, JALR).
      2. Find the `case` branch for that operation in the RTL.
      3. Compare the computed expression with the expected value Y.
      4. Fix only the logic for that specific case — do NOT rewrite other branches.

  FOR SEQUENTIAL DESIGN (has clock — FSM, pipeline stages, etc.):
    The memory may show STUCK signals, POSSIBLY UNDRIVEN signals, and waveform transitions.
    Fix strategy:
      - STUCK OUTPUT (never changes): the FSM state driving it is never reached.
        Trace the FSM state transition condition and fix it.
      - POSSIBLY UNDRIVEN (1 transition): signal assigned only in an unreachable state.
        Find which state should drive it and verify the FSM can enter that state.
      - MISMATCH (got=X expected=Y): compare transition timeline to expected behavior.
        If signal changes once and stays wrong → wrong value computed.
        If signal never changes → triggering condition is unreachable.

=== OUTPUT FORMAT ===
===== FILE: {target_file} =====
<SystemVerilog code>

Output ONLY this one file. No explanation.
"""

_SELF_REVIEW_PROMPT = """\
You are a senior RTL reviewer performing a pre-implementation design sanity check.

Review ONLY the target module: {target_module}

=== MODULE-SCOPED DESIGN PLAN ===
{plan}

=== MODULE-SCOPED RAG CONTEXT ===
{rag_context}

=== VERIFIED SUB-MODULE CONTEXT ===
{verified_context}

=== PREVIOUS MEMORY FOR THIS MODULE ===
{memory}

Your task is to catch likely first-pass RTL mistakes BEFORE code generation.
Focus especially on:
- reset semantics
- same-cycle vs next-cycle observability
- qualifier/payload coupling
- pulse vs level outputs
- address/data/counter advance timing
- forbidden stale-retention assumptions
- testcases that imply exact sampling cycles

Return ONLY valid JSON with this shape:
{{
  "risk_level": "low|medium|high",
  "module_kind": "combinational|sequential",
  "critical_contract_points": [
    "short bullet"
  ],
  "likely_failure_modes": [
    "short bullet"
  ],
  "implementation_checklist": [
    "short imperative item"
  ],
  "tb_alignment_notes": [
    "short note"
  ]
}}

Rules:
- Be concise.
- Mention only module-specific contract/timing issues.
- Do NOT write RTL code.
- Do NOT restate generic synthesizable coding rules unless they are directly relevant to this module.
"""

_SINGLE_PKG_PROMPT = """\
You are a senior RTL engineer specializing in SystemVerilog hardware design.

Generate the SystemVerilog PACKAGE file: {target_file}
This package contains global constants, typedefs, and enums used by all modules.

=== DESIGN PLAN ===
{plan}

=== RAG CONTEXT ===
{rag_context}

=== MEMORY / PREVIOUS ERRORS ===
{memory}

=== REQUIREMENTS ===
- Start with `timescale 1ns/1ps
- Define ALL global constants, typedefs, and enums for this design
- Use `package ... endpackage` syntax
- Do NOT include any module or testbench code

=== OUTPUT FORMAT ===
===== FILE: {target_file} =====
<SystemVerilog package code>

Output ONLY this one file. No explanation.
"""

_single_rtl_chain = ChatPromptTemplate.from_template(_SINGLE_RTL_PROMPT) | _llm | StrOutputParser()
_self_review_chain = ChatPromptTemplate.from_template(_SELF_REVIEW_PROMPT) | _llm | StrOutputParser()
_single_pkg_chain = ChatPromptTemplate.from_template(_SINGLE_PKG_PROMPT) | _llm | StrOutputParser()

# Sentinel value để phân biệt "không có debug instructions" vs empty string
_NO_DEBUG = "None"


def _clean_code(code: str) -> str:
    """Xoá markdown code fence nếu LLM bọc code trong ```systemverilog ... ```."""
    code = code.strip()
    code = re.sub(r'^```[a-zA-Z0-9_]*\s*\n', '', code)
    if code.endswith("```"):
        code = code[:-3].strip()
    return code


def _parse_json_loose(text: str) -> dict:
    text = (text or "").strip()
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
        return {}


def _build_self_review_summary(review: dict) -> str:
    if not review:
        return "None"

    parts = [f"risk_level={review.get('risk_level', 'unknown')}", f"module_kind={review.get('module_kind', 'unknown')}"]
    for key in ("critical_contract_points", "likely_failure_modes", "implementation_checklist", "tb_alignment_notes"):
        values = review.get(key) or []
        if values:
            joined = " | ".join(str(v).strip() for v in values if str(v).strip())
            if joined:
                parts.append(f"{key}: {joined}")
    return "\n".join(parts) if parts else "None"


def _run_self_review(inputs: dict) -> dict:
    try:
        result_text = _safe_call(_self_review_chain, inputs, max_retries=3)
        return _parse_json_loose(result_text)
    except Exception as e:
        print(f"[RTL_AGENT] Self-review skipped due to error: {e}")
        return {}


def _parse_single_file(text: str, expected_fname: str) -> str:
    """Parse ra code của đúng file expected_fname từ output LLM."""
    if "===== FILE:" in text:
        for part in text.split("===== FILE:")[1:]:
            try:
                name, code = part.split("=====", 1)
                if name.strip().lower() == expected_fname.lower():
                    return _clean_code(code)
            except ValueError:
                continue
        # Nếu không khớp tên, lấy file đầu tiên tìm thấy
        for part in text.split("===== FILE:")[1:]:
            try:
                _, code = part.split("=====", 1)
                return _clean_code(code)
            except ValueError:
                continue

    # Không có header, lấy toàn bộ output
    return _clean_code(text)


def _safe_call(chain, inputs: dict, max_retries: int = 5) -> str:
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
                print(f"[RTL_AGENT] Empty/streamless response. Retry ({retries}/{max_retries})...")
                time.sleep(5)
                continue
            return result
        except Exception as e:
            err = str(e)
            if "No generation chunks were returned" in err:
                retries += 1
                print(f"[RTL_AGENT] Stream returned no chunks. Retry ({retries}/{max_retries})...")
                time.sleep(5)
            elif "Rate limit" in err or "429" in err or "rate_limit_error" in err or "Concurrency" in err:
                retries += 1
                print(f"[RTL_AGENT] Rate limit/Concurrency. Waiting 30s ({retries}/{max_retries})...")
                time.sleep(30)
            elif any(k in err for k in ["524", "timeout", "5xx", "503", "502", "500", "stream_read_error", "APIError", "InternalServerError", "Upstream request failed", "Upstream service temporarily unavailable", "temporarily unavailable", "Connection error", "APIConnectionError"]):
                retries += 1
                print(f"[RTL_AGENT] API error: {err}. Waiting 30s ({retries}/{max_retries})...")
                time.sleep(30)
            else:
                raise
    raise RuntimeError("[RTL_AGENT] Failed after max retries.")

def _build_module_scope_plan(plan: dict, target_module: str, target_file: str, is_package: bool) -> dict:
    """Thu hẹp plan xuống đúng package/module hiện tại để giảm nhiễu khi sinh lần đầu."""
    scoped = {
        "design_summary": plan.get("design_summary", {}),
        "rtl_rules": plan.get("rtl_rules", {}),
        "packages": plan.get("packages", []),
    }

    if is_package:
        scoped["target_package"] = next(
            (pkg for pkg in plan.get("packages", []) if pkg.get("file") == target_file or pkg.get("name") == target_module),
            {"name": target_module, "file": target_file}
        )
        scoped["modules"] = plan.get("modules", [])
        scoped["generation_order"] = plan.get("generation_order", [])
        return scoped

    modules = plan.get("modules", [])
    target = next((m for m in modules if m.get("name") == target_module), None)
    deps = plan.get("dependency_graph", {}).get(target_module, [])
    dep_modules = [m for m in modules if m.get("name") in deps]
    testcase_entry = next((tc for tc in plan.get("testcase_plan", []) if tc.get("module") == target_module), {})

    scoped.update({
        "target_module": target,
        "dependency_modules": dep_modules,
        "dependency_graph": {target_module: deps},
        "testcase_plan": testcase_entry,
    })
    return scoped


def _build_module_scope_rag(rag_context: dict, target_module: str) -> dict:
    """Thu hẹp RAG context theo target module để LLM tập trung đúng interface/hành vi."""
    if not isinstance(rag_context, dict):
        return {"raw_context": rag_context}

    scoped = {}
    inferred = rag_context.get("inferred_testcases")
    if isinstance(inferred, dict):
        scoped["inferred_testcases"] = inferred.get(target_module, inferred)
    elif inferred is not None:
        scoped["inferred_testcases"] = inferred

    for key in ("module_specs", "ports", "interfaces", "constraints", "assumptions", "notes"):
        value = rag_context.get(key)
        if isinstance(value, dict):
            scoped[key] = value.get(target_module, value)
        elif value is not None:
            scoped[key] = value

    if not scoped:
        scoped = rag_context
    return scoped


def _build_verified_context(verified_files: list) -> str:
    """
    Tạo context về các module đã được verify để LLM biết
    chỉ cần instantiate mà không cần sinh lại.
    """
    if not verified_files:
        return "None — this is the first module being generated."

    parts = ["The following sub-modules have already been generated and verified (DO NOT regenerate):"]
    rtl_dir_abs = os.path.abspath(RTL_DIR)
    for fname in verified_files:
        fpath = os.path.join(rtl_dir_abs, fname)
        if os.path.exists(fpath):
            try:
                with open(fpath, "r", encoding="utf-8") as f:
                    code = f.read()
                # Chỉ lấy phần header (module declaration) để tiết kiệm token
                lines = code.splitlines()
                header_lines = []
                in_module = False
                paren_depth = 0
                for line in lines:
                    header_lines.append(line)
                    if "module " in line and not line.strip().startswith("//"):
                        in_module = True
                    if in_module:
                        paren_depth += line.count("(") - line.count(")")
                        if paren_depth <= 0 and ");" in line:
                            break
                parts.append(f"\n--- {fname} (module declaration) ---")
                parts.append("\n".join(header_lines[:40]))
            except Exception:
                parts.append(f"\n--- {fname} (file exists, verified) ---")
        else:
            parts.append(f"\n--- {fname} (verified) ---")

    return "\n".join(parts)


def run_single(
    target_module: str,
    target_file: str,
    plan: dict,
    rag_context: dict,
    memory_context: str = "None",
    verified_files: list = None,
    is_package: bool = False,
    debug_instructions: str = None,
) -> str:
    """
    Sinh RTL code cho DUY NHẤT 1 module/package.

    Args:
        target_module:      tên module (ví dụ: "alu")
        target_file:        tên file  (ví dụ: "alu.sv" hoặc "rv32_pkg.sv")
        plan:               design plan từ plan_agent
        rag_context:        context từ rag_agent
        memory_context:     lỗi cũ từ memory_manager
        verified_files:     danh sách file đã được verify thành công (để LLM tham khảo port)
        is_package:         True nếu đây là file _pkg.sv
        debug_instructions: Bản chỉ dẫn sửa lỗi chi tiết từ debug_agent (nếu có).
                            Khi được cung cấp, RTL Agent sẽ ưu tiên tuân theo tuyệt đối.

    Returns:
        Nội dung code của file đó (str)
    """
    os.makedirs(RTL_DIR, exist_ok=True)
    scoped_plan = _build_module_scope_plan(plan, target_module, target_file, is_package)
    scoped_rag = _build_module_scope_rag(rag_context, target_module)
    plan_str     = json.dumps(scoped_plan, indent=2, ensure_ascii=False)
    rag_str      = json.dumps(scoped_rag, indent=2, ensure_ascii=False)
    verified_ctx = _build_verified_context(verified_files or [])

    # Chuẩn hóa debug_instructions
    dbg_str = debug_instructions.strip() if debug_instructions and debug_instructions.strip() else _NO_DEBUG
    has_debug = dbg_str != _NO_DEBUG
    self_review_summary = "None"

    print(f"\n[RTL_AGENT] Generating {'package' if is_package else 'RTL module'}: {target_file}")
    if has_debug:
        print(f"[RTL_AGENT] 🎯 Debug instructions provided ({len(dbg_str)} chars) — will follow precisely.")
    else:
        mem_status = "empty" if (not memory_context or memory_context == "None") else f"{len(memory_context)} characters"
        print(f"[RTL_AGENT] Memory context status: {mem_status}")
        if memory_context and memory_context != "None":
            preview = memory_context.replace('\n', ' ')[:150]
            print(f"[RTL_AGENT] Memory preview: {preview}...")

    if is_package:
        result_text = _safe_call(_single_pkg_chain, {
            "plan": plan_str,
            "rag_context": rag_str,
            "memory": memory_context or "None",
            "target_file": target_file
        })
    else:
        if not has_debug:
            print(f"[RTL_AGENT] Running pre-RTL self-review gate for '{target_module}'...")
            review = _run_self_review({
                "plan": plan_str,
                "rag_context": rag_str,
                "memory": memory_context or "None",
                "verified_context": verified_ctx,
                "target_module": target_module,
            })
            self_review_summary = _build_self_review_summary(review)
            if self_review_summary != "None":
                print(f"[RTL_AGENT] Self-review summary prepared ({len(self_review_summary)} chars).")

        result_text = _safe_call(_single_rtl_chain, {
            "plan": plan_str,
            "rag_context": rag_str,
            "memory": memory_context or "None",
            "verified_context": verified_ctx,
            "target_module": target_module,
            "target_file": target_file,
            "debug_instructions": dbg_str,
            "self_review": self_review_summary,
        })

    code = _parse_single_file(result_text, target_file)

    # Lưu file
    fpath = os.path.join(RTL_DIR, target_file)
    with open(fpath, "w", encoding="utf-8") as f:
        f.write(code)
    print(f"[RTL_AGENT] ✅ Saved: {fpath}")
    return code


# ── Hàm run() tương thích ngược nếu có code cũ vẫn gọi ──────────────────────
def run(plan: dict, rag_context: dict, memory_context: str = "None",
        failed_modules: list = None) -> dict:
    """
    Compatibility wrapper: được giữ lại để không phá vỡ code cũ.
    Trong pipeline mới, main.py sẽ gọi run_single() trực tiếp.
    Hàm này chỉ dùng khi cần sinh lại một số module bị fail.
    """
    from core.memory_manager import MemoryManager
    mem = MemoryManager()

    os.makedirs(RTL_DIR, exist_ok=True)
    plan_str = json.dumps(plan, indent=2, ensure_ascii=False)
    rag_str  = json.dumps(rag_context, indent=2, ensure_ascii=False)
    modules  = plan.get("modules", [])
    pkg_list = plan.get("packages", [])
    files    = {}

    target_modules = set(failed_modules) if failed_modules else {m.get("name") for m in modules}

    # Sinh packages nếu cần
    for pkg in pkg_list:
        pfile = pkg.get("file", "")
        ppath = os.path.join(RTL_DIR, pfile)
        if not os.path.exists(ppath) or any(
            m in pfile for m in target_modules
        ):
            code = run_single(
                target_module=pfile.replace(".sv", ""),
                target_file=pfile,
                plan=plan,
                rag_context=rag_context,
                memory_context=memory_context,
                is_package=True
            )
            files[pfile] = code

    # Sinh từng module bị fail
    for m in modules:
        m_name = m.get("name")
        m_file = m.get("file", f"{m_name}.sv")
        if m_name not in target_modules:
            # Reuse existing
            mpath = os.path.join(RTL_DIR, m_file)
            if os.path.exists(mpath):
                with open(mpath, "r", encoding="utf-8") as f:
                    files[m_file] = f.read()
            continue

        # Lấy memory cho module này
        specific_mem_parts = []
        if m_name in mem._rtl_syntax and mem._rtl_syntax[m_name]["history"]:
            last = mem._rtl_syntax[m_name]["history"][-1]
            if last.get("status") == "fail":
                specific_mem_parts.append(f"### RTL SYNTAX ERROR:\n{last.get('error_block', '')}")
        if m_name in mem._functional and mem._functional[m_name]["history"]:
            last = mem._functional[m_name]["history"][-1]
            if last.get("status") == "fail":
                specific_mem_parts.append(f"### FUNCTIONAL SIMULATION ERROR:\n{last.get('error_block', '')}")
        specific_mem = "\n\n".join(specific_mem_parts) if specific_mem_parts else "None"

        code = run_single(
            target_module=m_name,
            target_file=m_file,
            plan=plan,
            rag_context=rag_context,
            memory_context=specific_mem,
            verified_files=list(files.keys()),
        )
        files[m_file] = code

    print(f"[RTL_AGENT] Completed RTL step. Files: {list(files.keys())}")
    return files
