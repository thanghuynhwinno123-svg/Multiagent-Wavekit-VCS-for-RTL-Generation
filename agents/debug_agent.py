"""
agents/debug_agent.py
Debug Agent: Chuyên phân tích lỗi functional simulation và đưa ra chỉ dẫn sửa RTL.

Luồng hoạt động:
  1. Nhận: RTL code lỗi + failed testcases + wavekit_analysis + sim_log + plan + rag_context
  2. Phân tích logic lỗi, tìm root cause cụ thể (FSM state, datapath, timing)
  3. Xuất ra bản chỉ dẫn (debug instructions) chi tiết cho RTL Agent thực thi

Nguyên tắc thiết kế:
  - Agent này KHÔNG viết lại RTL code
  - Agent này CHỈ phân tích và chỉ dẫn — như một Senior Designer review lỗi
  - Nếu có previous_strategies, cần tránh lặp lại các hướng sửa đã thất bại
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

_llm = ChatOpenAI(model=MODEL_NAME, temperature=0)

# ─────────────────────────────────────────────────────────────────────────────
# PROMPT: Phân tích lỗi sequential (có clock — FSM, pipeline, state machine)
# ─────────────────────────────────────────────────────────────────────────────
_SEQ_DEBUG_PROMPT = """\
You are a world-class hardware verification expert and RTL debug specialist.
Your ONLY job is to analyze a failing RTL simulation and produce a concise, \
actionable fix instruction document for the RTL engineer.
You do NOT write RTL code. You ONLY diagnose and prescribe fixes.

=== MODULE UNDER DEBUG ===
Module name: {target_module}
Design type: Sequential (has clock — FSM / pipeline / register-based logic)

=== DESIGN PLAN (ground truth specification) ===
{plan}

=== RAG REFERENCE CONTEXT ===
{rag_context}

=== FAILED RTL CODE (line-numbered) ===
```systemverilog
{rtl_code}
```

=== FAILED TESTCASES ===
{failed_testcases}

=== WAVEFORM ANALYSIS (from Wavekit) ===
{wavekit_analysis}

=== SIMULATION LOG (raw) ===
{sim_log}

=== PREVIOUSLY TRIED FIX STRATEGIES (DO NOT repeat these) ===
{previous_strategies}

═══════════════════════════════════════════════════════════════
ANALYSIS METHODOLOGY — FOLLOW THIS STEP BY STEP:
═══════════════════════════════════════════════════════════════

STEP 0 — CHECK FOR CONSTANT/ADDRESS MISMATCH BETWEEN TESTBENCH AND DESIGN:
  • Look at the Testbench definitions or the testcase descriptions in the log to identify the values driven to address/size ports (e.g., `start_addr_i = 32'h0000_0000`).
  • Check the corresponding constants imported or used in the RTL (e.g., `IRAM_START_ADDR`, `IRAM_END_ADDR`, `IRAM_BYTES` imported from package `rv32ec_zmmul_pkg`).
  • Verify if they match: if the testbench drives `0x0` but the package defines `IRAM_START_ADDR` differently, the RTL policy checks (`addr_ok`, `policy_ok`) will fail.
  • If a mismatch is found, DO NOT try to fix the FSM transitions or outputs. Instead, instruct the RTL Agent to write a workaround in the RTL (e.g., check against explicit values like `32'h0000_0000` or ignore package constants if they clash with Testbench stimulus).

STEP 1 — IDENTIFY THE PRIMARY ROOT CAUSE:
For each failed testcase, answer:
  • Which FSM state should drive the failing output signal?
  • Does the waveform show that state is ever reached?
    - If NOT reached → the state TRANSITION CONDITION is wrong.
    - If reached but output still wrong → the OUTPUT ASSIGNMENT in that state is wrong.
  • Is the signal STUCK (never driven after reset)?
    → The state that drives it is UNREACHABLE — trace back state transition logic.
  • Is the signal MOMENTARILY correct then wrong?
    → The state exits too early or re-enters wrong state.

STEP 2 — CROSS-REFERENCE WITH RTL CODE:
  • Find the exact always_comb block and case branch responsible.
  • Find the exact line(s) where the bug lives.
  • Compare with the design plan to understand the INTENDED behavior.

STEP 3 — FORMULATE THE FIX:
  • Be extremely specific: which line(s) to change, what to change TO.
  • Do NOT suggest rewriting entire blocks — surgical fixes only.
  • If multiple testcases fail from the same root cause, group them.

═══════════════════════════════════════════════════════════════
OUTPUT FORMAT — STRICTLY FOLLOW THIS STRUCTURE:
═══════════════════════════════════════════════════════════════

## RTL DEBUG REPORT: {target_module}

### 1. BUG SUMMARY
[One paragraph: what is failing and why, in plain English. If there is a constant/address mismatch between the testbench and design, highlight it here immediately.]

### 2. ROOT CAUSE ANALYSIS
For each group of related failures:

#### Bug #N: [Short descriptive title]
- **Failing signals**: [list signals]
- **Failing testcases**: [list TCs]
- **Waveform evidence**: [what the waveform shows — transition times, stuck signals, etc.]
- **Root cause**: [exact logical explanation — e.g., constant mismatch on address range checks vs testbench stimulus]
- **RTL location**: Line ~[N] inside `[always_block]` → `case [state]` → `[specific branch]`

### 3. ACTIONABLE FIX INSTRUCTIONS FOR RTL ENGINEER
[This section is what the RTL Agent will use directly]

#### Fix #N: [What to fix]
- **Where**: `[block name]` → state `[ST_NAME]` or line ~[N]
- **Current (wrong) code**:
  ```
  [paste wrong code snippet from the RTL above]
  ```
- **Change to**:
  [Describe or pseudo-code the correct logic — do not write full SV, just the logic. E.g., if there is a mismatch, write a workaround to compare against explicit testbench values instead of conflicting package constants]
- **Reason**: [Why this change makes it correct per the design spec and testbench behavior]

### 4. PRIORITY ORDER
[List the fix order if multiple bugs exist — fix most fundamental bug first]

### 5. WARNINGS
[Any patterns to AVOID — e.g., "do NOT add a registered version of boot_done_o, keep it combinational"]

Output ONLY the debug report above. No preamble, no trailing remarks.
"""

# ─────────────────────────────────────────────────────────────────────────────
# PROMPT: Phân tích lỗi combinational (không có clock — ALU, decoder, mux)
# ─────────────────────────────────────────────────────────────────────────────
_COMB_DEBUG_PROMPT = """\
You are a world-class hardware verification expert and RTL debug specialist.
Your ONLY job is to analyze a failing RTL simulation and produce a concise, \
actionable fix instruction document for the RTL engineer.
You do NOT write RTL code. You ONLY diagnose and prescribe fixes.

=== MODULE UNDER DEBUG ===
Module name: {target_module}
Design type: Combinational (no clock — ALU / decoder / MUX logic)

=== DESIGN PLAN (ground truth specification) ===
{plan}

=== RAG REFERENCE CONTEXT ===
{rag_context}

=== FAILED RTL CODE (line-numbered) ===
```systemverilog
{rtl_code}
```

=== FAILED TESTCASES (with got vs expected) ===
{failed_testcases}

=== SIMULATION LOG (raw) ===
{sim_log}

=== PREVIOUSLY TRIED FIX STRATEGIES (DO NOT repeat these) ===
{previous_strategies}

═══════════════════════════════════════════════════════════════
ANALYSIS METHODOLOGY — FOLLOW THIS STEP BY STEP:
═══════════════════════════════════════════════════════════════

STEP 0 — CHECK FOR CONSTANT/ADDRESS MISMATCH BETWEEN TESTBENCH AND DESIGN:
  • Inspect Testbench signals/values (constants and boundaries) driven to inputs from the logs.
  • Check if these match the constants used in the RTL code or package imports.
  • If there is a mismatch causing incorrect combinational evaluations (e.g., width mismatches, bound mismatches), instruct the RTL Agent to implement a direct workaround for the testbench stimulus values instead of colliding package parameters.

STEP 1 — MAP EACH FAILURE TO A CASE/BRANCH:
  • The testcase name (TC) encodes the operation being tested.
  • Find the `case` branch in the RTL that handles that operation opcode.
  • Compare: what the RTL computes vs what `expected` says it should be.

STEP 2 — FIND THE LOGIC ERROR:
  • Is the operator wrong? (e.g., subtraction instead of addition)
  • Is the operand order wrong? (e.g., a - b instead of b - a for SUB)
  • Is a sign-extension or bit-width handling wrong?
  • Is an intermediate signal wrong?

STEP 3 — GROUP FAILURES BY ROOT CAUSE:
  • Multiple TCs may fail from one mis-implemented opcode.

═══════════════════════════════════════════════════════════════
OUTPUT FORMAT — STRICTLY FOLLOW THIS STRUCTURE:
═══════════════════════════════════════════════════════════════

## RTL DEBUG REPORT: {target_module}

### 1. BUG SUMMARY
[One paragraph: what is failing and why. If there is a constant/address mismatch between the testbench and design, highlight it here immediately.]

### 2. ROOT CAUSE ANALYSIS

#### Bug #N: [Short title — e.g., "Constant mismatch on ALU bounds"]
- **Failing signals**: [list signals]
- **Failing testcases**: [list TCs with got vs expected]
- **Root cause**: [exact logic error — e.g. mismatch between design parameters and testbench expectations]
- **RTL location**: Line ~[N] inside `always_comb` → `case` → opcode `[OP_XXX]`

### 3. ACTIONABLE FIX INSTRUCTIONS FOR RTL ENGINEER

#### Fix #N: [What to fix]
- **Where**: `always_comb` → `case(op)` → case `[OP_XXX]` at line ~[N]
- **Current (wrong) expression**:
  ```
  [paste wrong line from RTL]
  ```
- **Correct logic**:
  [Describe the correct computation — formula or pseudo-code. E.g., if there is a mismatch, write a workaround to compare against explicit testbench values instead of conflicting package constants]
- **Reason**: [Why this is correct per the testcase expected value and design spec]

### 4. PRIORITY ORDER
[Fix order if multiple bugs]

### 5. WARNINGS
[Patterns to avoid]

Output ONLY the debug report above. No preamble, no trailing remarks.
"""

_seq_debug_chain  = ChatPromptTemplate.from_template(_SEQ_DEBUG_PROMPT)  | _llm | StrOutputParser()
_comb_debug_chain = ChatPromptTemplate.from_template(_COMB_DEBUG_PROMPT) | _llm | StrOutputParser()


# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

def _safe_call(chain, inputs: dict, max_retries: int = 5) -> str:
    """Gọi LLM chain với xử lý rate-limit và timeout tự động."""
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
                print(f"[DEBUG_AGENT] Empty/streamless response. Retry ({retries}/{max_retries})...")
                time.sleep(5)
                continue
            return result
        except Exception as e:
            err = str(e)
            if "No generation chunks were returned" in err:
                retries += 1
                print(f"[DEBUG_AGENT] Stream returned no chunks. Retry ({retries}/{max_retries})...")
                time.sleep(5)
            elif any(k in err for k in ["Rate limit", "429", "rate_limit_error", "Concurrency"]):
                retries += 1
                print(f"[DEBUG_AGENT] Rate limit/Concurrency. Waiting 30s ({retries}/{max_retries})...")
                time.sleep(30)
            elif any(k in err for k in ["524", "timeout", "5xx", "503", "502", "500",
                                         "stream_read_error", "APIError", "InternalServerError",
                                         "Upstream request failed", "Upstream service temporarily unavailable", "temporarily unavailable", "Connection error", "APIConnectionError"]):
                retries += 1
                print(f"[DEBUG_AGENT] API error: {err}. Waiting 30s ({retries}/{max_retries})...")
                time.sleep(30)
            else:
                raise
    raise RuntimeError("[DEBUG_AGENT] Failed after max retries.")

def _add_line_numbers(code: str) -> str:
    """Thêm số dòng vào code RTL để LLM tham chiếu chính xác."""
    lines = code.splitlines()
    return "\n".join(f"{i+1:4d}: {line}" for i, line in enumerate(lines))


def _detect_is_sequential(wavekit_analysis: str) -> bool:
    """
    Xác định thiết kế là sequential hay combinational dựa trên
    nội dung wavekit_analysis đã được tạo trước đó.
    """
    wk_lower = wavekit_analysis.lower()
    if "sequential" in wk_lower or "clock detected" in wk_lower or "clk" in wk_lower:
        return True
    if "combinational" in wk_lower:
        return False
    return True  # default: treat as sequential to be safe


def _extract_previous_strategies(functional_history: list) -> str:
    """
    Trích xuất các chiến thuật sửa lỗi đã thất bại từ lịch sử memory
    để tránh lặp lại trong lần debug tiếp theo.

    Mỗi entry trong functional_history là một dict chứa:
      - iter, status, error_block, wavekit_analysis, ...
      - Nếu có trường 'debug_instructions' thì đó là chiến thuật cũ.
    """
    strategies = []
    for entry in functional_history:
        if entry.get("status") == "fail" and entry.get("debug_instructions"):
            it = entry.get("iter", "?")
            strategies.append(
                f"--- Strategy attempted at iteration {it} (FAILED) ---\n"
                f"{entry['debug_instructions']}"
            )
    if not strategies:
        return "None — this is the first debug attempt for this module."
    return "\n\n".join(strategies)


def _format_failed_testcases(failed_testcases: list) -> str:
    """Format danh sách testcase fail cho dễ đọc trong prompt."""
    if not failed_testcases:
        return "None specified."
    lines = []
    for tc in failed_testcases:
        lines.append(f"  • {tc}")
    return "\n".join(lines)


# ─────────────────────────────────────────────────────────────────────────────
# Main API
# ─────────────────────────────────────────────────────────────────────────────

def run_single(
    target_module:      str,
    rtl_code:           str,
    failed_testcases:   list,
    wavekit_analysis:   str,
    sim_log:            str,
    plan:               dict,
    rag_context:        dict,
    functional_history: list = None,
) -> str:
    """
    Phân tích lỗi functional simulation và xuất ra bản chỉ dẫn sửa RTL.

    Args:
        target_module:      Tên module đang bị lỗi (e.g. 'alu')
        rtl_code:           Nội dung file RTL bị lỗi (string)
        failed_testcases:   Danh sách testcase fail (list of strings)
        wavekit_analysis:   Kết quả phân tích waveform từ wavekit_tool
        sim_log:            Log mô phỏng thô
        plan:               Design plan (dict từ plan_agent)
        rag_context:        Context tham chiếu từ rag_agent (dict)
        functional_history: Lịch sử các lần fail trước (list of dicts từ memory)
                           Dùng để trích xuất previous_strategies và tránh lặp.

    Returns:
        str: Bản chỉ dẫn debug chi tiết (Markdown) để truyền cho RTL Agent.
    """
    print(f"\n[DEBUG_AGENT] Analyzing functional failure for module: '{target_module}'")
    print(f"[DEBUG_AGENT] Failed testcases: {len(failed_testcases)}")

    plan_str     = json.dumps(plan, indent=2, ensure_ascii=False)
    rag_str      = json.dumps(rag_context, indent=2, ensure_ascii=False)
    rtl_numbered = _add_line_numbers(rtl_code)

    is_sequential = _detect_is_sequential(wavekit_analysis)
    design_type   = "Sequential" if is_sequential else "Combinational"
    print(f"[DEBUG_AGENT] Detected design type: {design_type}")

    prev_strategies = _extract_previous_strategies(functional_history or [])
    has_prev = prev_strategies != "None — this is the first debug attempt for this module."
    if has_prev:
        count = prev_strategies.count("--- Strategy attempted at iteration")
        print(f"[DEBUG_AGENT] Found {count} previous failed strategy(ies) — will instruct to avoid.")

    tc_formatted = _format_failed_testcases(failed_testcases)

    # Cắt log nếu quá dài (giữ 3000 ký tự cuối — phần quan trọng nhất)
    sim_log_trimmed = sim_log[-15000:] if len(sim_log) > 15000 else sim_log

    inputs = {
        "target_module":      target_module,
        "plan":               plan_str,
        "rag_context":        rag_str,
        "rtl_code":           rtl_numbered,
        "failed_testcases":   tc_formatted,
        "wavekit_analysis":   wavekit_analysis,
        "sim_log":            sim_log_trimmed,
        "previous_strategies": prev_strategies,
    }

    chain = _seq_debug_chain if is_sequential else _comb_debug_chain
    label = "sequential" if is_sequential else "combinational"
    print(f"[DEBUG_AGENT] Calling LLM with {label} debug prompt...")

    instructions = _safe_call(chain, inputs)

    # Trim output nếu quá dài (bảo vệ context window của RTL Agent)
    if len(instructions) > 8000:
        instructions = instructions[:8000] + "\n\n[DEBUG_AGENT: Output truncated to 8000 chars]"

    print(f"[DEBUG_AGENT] ✅ Debug instructions generated ({len(instructions)} chars)")
    _print_instructions_preview(instructions)
    return instructions


def _print_instructions_preview(instructions: str):
    """In xem trước 10 dòng đầu của debug instructions ra console."""
    lines = instructions.splitlines()
    preview_lines = lines[:12]
    print("[DEBUG_AGENT] ── Instructions Preview ──")
    for line in preview_lines:
        print(f"  {line}")
    if len(lines) > 12:
        print(f"  ... ({len(lines) - 12} more lines)")
    print("[DEBUG_AGENT] ──────────────────────────")
