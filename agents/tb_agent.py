"""
agents/tb_agent.py
Testbench Agent: sinh TB cho DUY NHẤT 1 module (TB Isolation Pattern).
TB KHÔNG instantiate DUT — Functional Agent sẽ tạo wrapper top_sim.sv kết nối.
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
TB_DIR   = os.path.join(BASE_DIR, "..", "generated_rtl")
RUNLOG_DIR = os.path.join(BASE_DIR, "..", "runlog")
MEMORY_DIR = os.path.join(BASE_DIR, "..", "memory")

_llm = ChatOpenAI(model=MODEL_NAME, temperature=0)

_TB_PROMPT = """\
You are a senior verification engineer specializing in SystemVerilog testbenches.

Generate the TESTBENCH file for the module: {target_module}

=== TB GENERATION STRATEGY ===
{tb_strategy}

=== MODULE-SCOPED DESIGN PLAN ===
{plan}

=== MODULE-SCOPED RAG CONTEXT & INFERRED TEST CASES ===
{rag_context}

=== PROVEN SUBMODULE FLOW SEEDS (for integration/top modules) ===
{submodule_seeds}

=== MEMORY / PREVIOUS ERRORS & MISSING TESTCASES FOR THIS MODULE ===
{memory}

If the memory contains "FUNCTIONAL MISMATCH FEEDBACK", treat it as HIGH PRIORITY:
- The previous TB may have had a wrong golden model, wrong retention assumption, or wrong sampling cycle.
- In that case, revise the TB expectations first instead of forcing RTL to match a likely-bad checker.
- Use the provided RTL snapshot and simulation mismatches to align the TB with the real module contract from the plan/spec.

If proven submodule flow seeds are provided and the target module is top-level/integration-like:
- Treat those seeds as trusted evidence for legal instruction classes and externally observable flow patterns.
- Reuse the seed intent and, when helpful, the instruction encoding family; but DO NOT copy hidden leaf-module checkers directly.
- Convert each seed into a top-level testcase that verifies only observable integration behavior at the top interface.

=== CRITICAL TB STYLE: MODULE WITH PORTS (TB Isolation Pattern) ===

The testbench MUST be written as a MODULE WITH PORTS, NOT as a traditional top-level testbench.
The TB module will be connected to the DUT by a separate wrapper file (top_sim.sv).
The TB module itself does NOT instantiate the DUT.

TB Port Mapping Logic:
- DUT input  → TB OUTPUT (TB drives it)
- DUT output → TB INPUT  (TB reads/asserts it)

Example:
  module tb_alu (
    output logic [7:0] a,
    output logic [7:0] b,
    output logic [2:0] op,
    input  logic [7:0] result
  );
    // test stimuli
  endmodule

=== FIRST-PASS TB CONTRACT RULE ===
Before writing the checker, derive the contract from the target module's behavior_contract and each testcase timing_contract.
Do NOT invent an extra FSM phase, retention rule, or sampling convention unless the scoped plan explicitly requires it.
If testcase timing_contract says same-cycle response is allowed, the checker must permit it.
If a payload signal is meaningful only when a qualifier is asserted, compare it only under that condition.

=== TOP-MODULE COMPACTNESS RULE ===
If the target module is a top-level CPU/pipeline/integration module or has a large testcase plan, keep the TB compact:
- Prefer reusable helper tasks, compact instruction/data scenario tables, and short scenario runners instead of writing one long custom procedural block per testcase.
- Reuse reset/setup helpers rather than re-declaring large repeated stimulus blocks.
- Minimize repeated signal-by-signal boilerplate when a helper can check a scenario consistently.
- Keep testcase coverage complete, but compress the implementation structure.
- Avoid inflating PASS counts by repeatedly re-running the same reset-idle testcase unless the reset check is itself a required testcase.
- Prefer MANY small observable flow cases over a few giant end-to-end cases.
- Each top-level testcase should have ONE primary assertion and at most two secondary assertions.
- Prefer event-window checks (signal seen within N cycles) over exact fixed-cycle equality when the pipeline may continue advancing after the event.

=== TB REQUIREMENTS ===
1. Generate tb_{target_module}.sv for the {target_module} module defined in the plan.
2. The TB module has PORTS (not `reg`/`wire` for DUT connections — those are ports).
3. DO NOT instantiate the DUT inside the TB module.
4. Internal logic uses `logic` type.
5. Clock generation and Cycle Counting:
   - For sequential designs (modules that have a `clk` port in the plan): Use `initial forever #5 clk = ~clk;` inside the TB. `clk` must be a PORT. Also maintain a cycle counter `integer cycle_count = 0;` inside the TB that increments on every `@(posedge clk)` so you can log the exact cycle count of failures.
   - For combinational designs (no `clk` port): Do NOT generate a clock, and do NOT declare a clock port. Simply declare a local variable `integer cycle_count = 0;` set to 0.
6. MINIMAL FUNCTIONAL TESTING: Only implement the core functional testcases specified in the design plan's testcase_plan. Keep the test scenarios focused on the main operation of the module (typically 6 to 15 high-quality testcases). Avoid generating excessive redundant stimuli or extreme corner cases that are outside the module's primary specification.
7. Use `task automatic` for ALL tasks (check tasks, golden model tasks).
8. Watchdog timer: initial begin #1_000_000; $display("TIMEOUT"); $finish; end
9. The file MUST start with `timescale 1ns/1ps
10. AVOID MULTIPLE DRIVERS (ICPD Errors): Any variable or output port assigned inside a combinational block (e.g., `always_comb` or `assign`) MUST NOT be written to inside any procedural process (such as `initial` blocks, `always_ff` blocks, or procedural `task`s like `init_defaults` or `run_all_tests`).
11. CRITICAL TIMING RULE (#1 delay):
    - For sequential designs (with clock): Before performing any assertions/checks against the golden model output values after a clock edge, you MUST wait `#1;` (1 time-unit delay) to allow the combinational path and state transitions of the DUT to settle.
      Example: ` @(posedge clk); #1; // Check outputs here`
    - For combinational designs (no clock): After driving new stimulus inputs in your stimulus block, you MUST wait `#1;` (or `#5;`) before checking the outputs to let the simulator update the combinational logic.
      Example: ` a = 8'h05; b = 8'h02; #1; // Check outputs here`

12. When regenerating from functional mismatch feedback:
    - Re-check whether each expected value really follows from the design plan and RTL interface.
    - Do NOT assume an output must retain its previous nonzero value unless the plan/spec explicitly requires retention.
    - For sequential CSRs/stateful blocks, be careful not to hardcode stale values from earlier testcases if the current stimulus does not write or latch them in the DUT.
    - If a signal is only meaningful when a qualifier is asserted (for example trap target valid only when trap_taken is high), model that contract correctly in the golden checker.
13. For top-level integration modules specifically:
    - Prefer helper tasks like wait-for-event-within-window, request-handshake checkers, redirect-seen checkers, and no-trap/no-fail windows.
    - Avoid asserting that an address/output must equal a target at one exact late cycle if the event may have already happened and the pipeline can legally continue.
    - Use submodule-proven seeds to choose legal/meaningful instruction classes and externally visible flow scenarios.
    - Do NOT require exact proof of hidden internal state transitions unless the plan explicitly exposes them through top-level outputs.

=== UNIFIED LOG FORMAT (MANDATORY) ===
ALL testbench output MUST use these EXACT tag formats so the Python parser can detect results:

  // For PASS — use testcase operation name only:
  $display("[TESTCASE_RESULT] PASS: %0s", tc_name);

  // For FAIL — MUST include the signal name being checked, separated by a dot:
  // Format: TC_NAME.signal_name — where signal_name is the EXACT RTL output port being checked
  // Also, you MUST log the cycle count and simulation time at the end of the FAIL line (for combinational design, cycle_count is 0):
  $display("[TESTCASE_RESULT] FAIL: %0s.%0s | got=%h expected=%h | cycle=%0d time=%0t",
           tc_name, signal_name, got_val, exp_val, cycle_count, $time);

  // At the very end — use [TEST_SUMMARY] tag:
  $display("[TEST_SUMMARY] PASS=%0d FAIL=%0d", pass_count, fail_count);
  $finish;

CRITICAL RULES FOR FAIL FORMAT:
  1. tc_name must be a SHORT operation name, e.g., "TC001_RESET", "TC002_ADD", "TC003_BEQ_TAKEN".
     DO NOT encode the signal name inside tc_name (bad: "TC001_BOOT_FAIL" — "BOOT_FAIL" is a signal!).
  2. signal_name must be the EXACT RTL output port name, e.g., "boot_fail_o", "entry_pc_o", "taken_o".
  3. The dot (.) separator between tc_name and signal_name is MANDATORY.
     Without it, the waveform analysis tool CANNOT identify which signal to analyze → RTL repair fails.

Example of CORRECT format:
  $display("[TESTCASE_RESULT] FAIL: TC001_HEADER_VALIDATION.boot_fail_o | got=%0h expected=%0h | cycle=%0d time=%0t",
           boot_fail_o, 1'b0, cycle_count, $time);
  $display("[TESTCASE_RESULT] FAIL: TC006_BOOT_COMPLETE.entry_pc_o | got=%0h expected=%0h | cycle=%0d time=%0t",
           entry_pc_o, 32'h40, cycle_count, $time);

DO NOT use any other pass/fail format. These tags are REQUIRED for the Python agent to function.

=== GOLDEN MODEL PRINCIPLE (MANDATORY — NO HARDCODED EXPECTED VALUES) ===
NEVER compute expected values mentally and hardcode them as literals.
Instead, write a Golden Model using SystemVerilog operators to compute expected
values at simulation time. Choose the pattern matching {target_module}'s behavior:

── TYPE 1: Combinational Datapath (ALU, Adder, Multiplier, Shifter...) ──
  Write a task automatic or always_comb that computes expected output using SV operators:

    task automatic golden_compute(
      input  [31:0] a, b,
      input  [3:0]  op,
      output [31:0] exp_result
    );
      case (op)
        4'd0: exp_result = a + b;
        4'd1: exp_result = a - b;
        default: exp_result = 32'hx;
      endcase
    endtask

── TYPE 2: Sequential Storage (Regfile, RAM, FIFO...) ──
  Maintain a shadow array in the testbench that mirrors expected state:

    logic [31:0] golden_regs [0:15];
    // On write: golden_regs[rd] = wdata;
    // On read:  compare rdata with golden_regs[rs]

── TYPE 3: Decoder / Controller ──
  Write a task that maps input encoding to expected control signals using case/casez.

── TYPE 4: PC / Fetch Unit (Sequential with branching state) ──
  Track expected PC as a variable updated with the same logic as spec.

APPLY THE APPROPRIATE TYPE (or combine types) for {target_module}.

=== OUTPUT FORMAT ===
===== FILE: tb_{target_module}.sv =====
<SystemVerilog testbench code>
"""

_tb_chain = ChatPromptTemplate.from_template(_TB_PROMPT) | _llm | StrOutputParser()


def _build_module_scope_plan(plan: dict, target_module: str) -> dict:
    """Thu hẹp plan xuống module hiện tại để TB bám đúng contract khi sinh lần đầu."""
    modules = plan.get("modules", [])
    target = next((m for m in modules if m.get("name") == target_module), None)
    deps = plan.get("dependency_graph", {}).get(target_module, [])
    dep_modules = [m for m in modules if m.get("name") in deps]
    testcase_entry = next((tc for tc in plan.get("testcase_plan", []) if tc.get("module") == target_module), {})
    return {
        "design_summary": plan.get("design_summary", {}),
        "tb_rules": plan.get("tb_rules", {}),
        "rtl_rules": plan.get("rtl_rules", {}),
        "target_module": target,
        "dependency_modules": dep_modules,
        "dependency_graph": {target_module: deps},
        "testcase_plan": testcase_entry,
    }


def _build_module_scope_rag(rag_context: dict, target_module: str) -> dict:
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


def _extract_pass_names_from_log_text(log_text: str) -> list:
    return re.findall(r"\[TESTCASE_RESULT\] PASS: ([^\n\r]+)", log_text or "")


def _extract_case_names_from_tb_code(tb_code: str) -> list:
    names = re.findall(r'tc\s*=\s*"([^"]+)"', tb_code or "")
    if names:
        return names
    task_names = re.findall(r"task automatic (tc\d+_[a-zA-Z0-9_]+)", tb_code or "")
    return task_names


def _load_latest_runlog_passes(module_name: str) -> list:
    if not os.path.isdir(RUNLOG_DIR):
        return []
    prefix = f"func_{module_name}_iter"
    candidates = []
    for fname in os.listdir(RUNLOG_DIR):
        if fname.startswith(prefix) and fname.endswith('.log'):
            candidates.append(os.path.join(RUNLOG_DIR, fname))
    for path in sorted(candidates, reverse=True):
        try:
            text = Path(path).read_text(encoding='utf-8', errors='ignore')
        except Exception:
            continue
        passes = _extract_pass_names_from_log_text(text)
        if passes:
            return passes
    return []


def _load_tb_case_names(module_name: str) -> list:
    tb_path = os.path.join(TB_DIR, f"tb_{module_name}.sv")
    if not os.path.exists(tb_path):
        return []
    try:
        tb_code = Path(tb_path).read_text(encoding='utf-8', errors='ignore')
    except Exception:
        return []
    return _extract_case_names_from_tb_code(tb_code)


def _summarize_seed_cases(case_names: list) -> dict:
    summary = {
        "fetch": [],
        "redirect": [],
        "lsu": [],
        "trap": [],
        "boot": [],
        "datapath": [],
        "other": [],
    }
    for name in case_names:
        upper = name.upper()
        if any(k in upper for k in ["FETCH", "RESET", "STALL", "FLUSH"]):
            summary["fetch"].append(name)
        elif any(k in upper for k in ["BRANCH", "JAL", "JALR", "REDIRECT", "MRET"]):
            summary["redirect"].append(name)
        elif any(k in upper for k in ["LOAD", "STORE", "LSU", "DATA_REQ"]):
            summary["lsu"].append(name)
        elif any(k in upper for k in ["TRAP", "ILLEGAL", "IRQ", "INTERRUPT", "EBREAK", "DIV", "REM"]):
            summary["trap"].append(name)
        elif any(k in upper for k in ["BOOT", "SPI", "HEADER", "VALIDATION", "SIZE", "FAIL_STOP"]):
            summary["boot"].append(name)
        elif any(k in upper for k in ["ADD", "SUB", "AND", "OR", "XOR", "SLL", "SRL", "SRA", "SLT", "MUL", "COMPRESSED", "C_"]):
            summary["datapath"].append(name)
        else:
            summary["other"].append(name)
    return {k: v[:8] for k, v in summary.items() if v}


def _build_submodule_seed_context(plan: dict, target_module: str) -> dict:
    modules = plan.get("modules", [])
    target = next((m for m in modules if m.get("name") == target_module), {})
    name = (target_module or "").lower()
    style = (target.get("implementation_style") or "").lower()
    is_top_like = name.endswith("_top") or "cpu_top" in name or style in {"pipeline", "integration"}
    if not is_top_like:
        return {"mode": "not_top_like"}

    deps = plan.get("dependency_graph", {}).get(target_module, [])
    seed_modules = []
    for dep in deps:
        runlog_passes = _load_latest_runlog_passes(dep)
        tb_cases = _load_tb_case_names(dep)
        chosen = runlog_passes or tb_cases
        if not chosen:
            continue
        seed_modules.append({
            "module": dep,
            "seed_cases": chosen[:12],
            "seed_summary": _summarize_seed_cases(chosen),
        })

    return {
        "mode": "top_like",
        "target_module": target_module,
        "guidance": [
            "Use dependency seed cases as trusted evidence for legal instruction/flow families.",
            "Convert seed intent into top-level observable checks only.",
            "Prefer event-window flow checks over exact late-cycle equality for continuing pipelines.",
            "Split giant integration goals into multiple small cases with one main observable assertion each."
        ],
        "dependency_seeds": seed_modules,
    }


def _build_tb_strategy(plan: dict, target_module: str) -> str:
    testcase_entry = next((tc for tc in plan.get("testcase_plan", []) if tc.get("module") == target_module), {})
    testcase_count = len(testcase_entry.get("testcases", []) or [])
    modules = plan.get("modules", [])
    target = next((m for m in modules if m.get("name") == target_module), {})
    style = (target.get("implementation_style") or "").lower()
    name = (target_module or "").lower()

    is_top_like = (
        testcase_count >= 24 or
        "cpu_top" in name or
        name.endswith("_top") or
        style in {"pipeline", "integration"}
    )

    if is_top_like:
        return (
            "TOP_MODULE_COMPACT: Use compact reusable helpers and scenario tables. "
            "Favor grouped micro-scenarios that still explicitly exercise every required operation. "
            "Do not duplicate long reset-idle or boilerplate blocks between operations. "
            "Keep the TB shorter and structurally regular so regeneration remains stable."
        )

    return (
        "STANDARD_MODULE: Use straightforward per-operation tasks/testcases, but still avoid unnecessary duplication."
    )


def _clean_code(code: str) -> str:
    code = code.strip()
    code = re.sub(r'^```[a-zA-Z0-9_]*\s*\n', '', code)
    if code.endswith("```"):
        code = code[:-3].strip()
    return code


def _parse_tb_file(text: str, expected_fname: str) -> str:
    """Parse ra code của đúng tb file từ output LLM."""
    if "===== FILE:" in text:
        for part in text.split("===== FILE:")[1:]:
            try:
                name, code = part.split("=====", 1)
                fname = name.strip()
                if fname.lower() == expected_fname.lower():
                    return _clean_code(code)
            except ValueError:
                continue
        # Fallback: lấy file tb_ đầu tiên
        for part in text.split("===== FILE:")[1:]:
            try:
                name, code = part.split("=====", 1)
                if name.strip().lower().startswith("tb_"):
                    return _clean_code(code)
            except ValueError:
                continue
    return _clean_code(text)


def _safe_call(inputs: dict, max_retries: int = 5) -> str:
    retries = 0
    while retries < max_retries:
        try:
            result = ""
            try:
                for chunk in _tb_chain.stream(inputs):
                    result += chunk
            except ValueError as e:
                if "No generation chunks were returned" in str(e):
                    result = ""
                else:
                    raise

            if not result.strip():
                try:
                    fallback = _tb_chain.invoke(inputs)
                    result = fallback if isinstance(fallback, str) else str(fallback)
                except Exception:
                    pass

            if not result.strip():
                retries += 1
                print(f"[TB_AGENT] Empty/streamless response. Retry ({retries}/{max_retries})...")
                time.sleep(5)
                continue
            return result
        except Exception as e:
            err = str(e)
            if "No generation chunks were returned" in err:
                retries += 1
                print(f"[TB_AGENT] Stream returned no chunks. Retry ({retries}/{max_retries})...")
                time.sleep(5)
            elif "Rate limit" in err or "429" in err or "rate_limit_error" in err or "Concurrency" in err:
                retries += 1
                print(f"[TB_AGENT] Rate limit/Concurrency. Waiting 30s ({retries}/{max_retries})...")
                time.sleep(30)
            elif any(k in err for k in ["524", "timeout", "5xx", "503", "502", "500", "stream_read_error", "APIError", "InternalServerError", "Upstream request failed", "Upstream service temporarily unavailable", "temporarily unavailable", "Connection error", "APIConnectionError"]):
                retries += 1
                print(f"[TB_AGENT] API error. Waiting 30s ({retries}/{max_retries})...")
                time.sleep(30)
            else:
                raise
    raise RuntimeError("[TB_AGENT] Failed after max retries.")

def run_single(
    target_module: str,
    plan: dict,
    rag_context: dict,
    memory_context: str = "None"
) -> str:
    """
    Sinh testbench cho DUY NHẤT 1 module.

    Args:
        target_module: tên module (ví dụ: "alu")
        plan:          design plan từ plan_agent
        rag_context:   context từ rag_agent
        memory_context: lỗi cũ + missing testcases từ memory_manager

    Returns:
        Nội dung code của tb_<target_module>.sv (str)
    """
    from core.memory_manager import MemoryManager
    mem = MemoryManager()

    tb_filename = f"tb_{target_module}.sv"
    tb_path = os.path.join(TB_DIR, tb_filename)
    os.makedirs(TB_DIR, exist_ok=True)

    # Kiểm tra xem có thể reuse TB cũ không
    if os.path.exists(tb_path) and memory_context == "None":
        has_syntax_err = (
            target_module in mem._tb_syntax and
            bool(mem._tb_syntax[target_module].get("history"))
        )
        has_missing_tc = (
            target_module in mem._testcase and
            bool(mem._testcase[target_module].get("history")) and
            bool(mem._testcase[target_module]["history"][-1].get("missing_cases"))
        )
        if not has_syntax_err and not has_missing_tc:
            print(f"[TB_AGENT] Reusing existing verified testbench: {tb_filename}")
            with open(tb_path, "r", encoding="utf-8") as f:
                return f.read()

    scoped_plan = _build_module_scope_plan(plan, target_module)
    scoped_rag = _build_module_scope_rag(rag_context, target_module)
    submodule_seed_context = _build_submodule_seed_context(plan, target_module)
    plan_str = json.dumps(scoped_plan, indent=2, ensure_ascii=False)
    rag_str  = json.dumps(scoped_rag, indent=2, ensure_ascii=False)
    seed_str = json.dumps(submodule_seed_context, indent=2, ensure_ascii=False)

    print(f"\n[TB_AGENT] Generating testbench for module: {target_module}")
    mem_status = "empty" if (not memory_context or memory_context == "None") else f"{len(memory_context)} characters"
    print(f"[TB_AGENT] Memory context status: {mem_status}")
    if memory_context and memory_context != "None":
        preview = memory_context.replace('\n', ' ')[:150]
        print(f"[TB_AGENT] Memory preview: {preview}...")

    tb_strategy = _build_tb_strategy(plan, target_module)

    result_text = _safe_call({
        "plan": plan_str,
        "rag_context": rag_str,
        "submodule_seeds": seed_str,
        "memory": memory_context or "None",
        "target_module": target_module,
        "tb_strategy": tb_strategy
    })

    code = _parse_tb_file(result_text, tb_filename)

    # Lưu file
    with open(tb_path, "w", encoding="utf-8") as f:
        f.write(code)
    print(f"[TB_AGENT] ✅ Saved: {tb_path}")
    return code


# ── Compatibility wrapper ─────────────────────────────────────────────────────
def run(plan: dict, rag_context: dict, memory_context: str = "None") -> dict:
    """
    Compatibility wrapper: giữ lại để không phá vỡ code cũ.
    Trong pipeline mới, main.py gọi run_single() trực tiếp.
    """
    from core.memory_manager import MemoryManager
    mem = MemoryManager()

    print("\n[TB_AGENT] Generating testbench code (Module-by-Module)...")
    modules  = plan.get("modules", [])
    files    = {}

    for m in modules:
        module_name = m.get("name")
        tb_filename = f"tb_{module_name}.sv"

        specific_mem_parts = []
        if module_name in mem._tb_syntax and mem._tb_syntax[module_name]["history"]:
            last = mem._tb_syntax[module_name]["history"][-1]
            if last.get("status") == "fail":
                specific_mem_parts.append(f"### TB SYNTAX ERROR:\n{last.get('error_block', '')}")
        if module_name in mem._testcase and mem._testcase[module_name]["history"]:
            last = mem._testcase[module_name]["history"][-1]
            missing = last.get("missing_cases", [])
            if missing:
                missing_str = "\n".join(f"  - {tc}" for tc in missing)
                specific_mem_parts.append(f"### MISSING TEST CASES (you MUST add these):\n{missing_str}")
        specific_mem = "\n\n".join(specific_mem_parts) if specific_mem_parts else "None"

        code = run_single(
            target_module=module_name,
            plan=plan,
            rag_context=rag_context,
            memory_context=specific_mem
        )
        files[tb_filename] = code

    print(f"[TB_AGENT] Completed TB step. Files: {list(files.keys())}")
    return files
