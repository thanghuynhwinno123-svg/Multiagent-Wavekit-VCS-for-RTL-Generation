"""
agents/testcase_agent.py
TestCase Agent: dùng LLM đọc TB code và đối chiếu với inferred_testcases từ RAG.
Pipeline mới: đánh giá coverage cho DUY NHẤT 1 module tại một thời điểm.
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

_llm = ChatOpenAI(model=MODEL_NAME, temperature=0)

_TC_PROMPT = """\
You are a senior verification engineer reviewing a SystemVerilog testbench.

Your task is to check whether the testbench covers the FUNCTIONAL OPERATIONS of the given module.

Special handling for top-level integration modules:
- If the module is a CPU top, pipeline top, integration wrapper, or its name ends with _top, evaluate coverage as OBSERVABLE INTEGRATION COVERAGE.
- For those top-level modules, count a required operation as covered when the TB stimulates the intended flow and checks the externally visible top-level outputs or side effects that the interface actually exposes.
- Do NOT require proof of hidden internal datapath values, hidden regfile contents, hidden ALU result buses, or hidden CSR state unless the TB can observe them through top-level ports.
- For datapath-class flows such as ADD/SUB/AND/OR/XOR/shifts/SLT/MUL/compressed ALU forms, a top-level testcase may still count as covered if it clearly exercises that instruction/flow and verifies the correct observable integration behavior (for example no unexpected trap/fail, correct request behavior, correct redirect, or other visible effect required by the spec/plan).

=== MODULE ANALYSIS (from spec) ===
Module: {module_name}
Description: {description}

Required Operations to Test (one testcase per operation):
{required_testcases}

=== TESTBENCH CODE ===
```systemverilog
{tb_code}
```

=== EVALUATION CRITERIA ===
The testbench PASSES if it:
1. Has at least ONE test stimulus for EACH required operation listed above.
   - The stimulus must apply concrete input values and check the correct observable behavior for that operation.
   - For normal leaf/submodules, this usually means checking the direct functional output value.
   - For top-level integration modules, this means checking the relevant externally visible top-level behavior rather than hidden internal values.
   - It does NOT need to test the same operation multiple times.
2. Prints PASS or FAIL for each test (using $display).
3. Uses fail_count to count failures (does NOT use $fatal on test failure).
4. Prints a summary line at the end (e.g., "SUMMARY: X PASS, Y FAIL").
5. Calls $finish at the end.

DO NOT penalize the testbench for:
- Not testing boundary values (all-zero, all-ones, MSB-only, etc.).
- Not testing commutativity, associativity, or other mathematical properties.
- Not testing stability or glitch behavior.
- Not testing signal transitions.
- Missing reset/clock testcases IF the module is purely combinational (no clock/reset ports).
- Having fewer testcases than the number of input combinations.

=== RESPONSE FORMAT ===
Return ONLY valid JSON:
{{
  "module": "{module_name}",
  "passed": true | false,
  "coverage_percent": <0-100>,
  "covered": [
    "<operation that IS tested>"
  ],
  "missing": [
    "<operation that is NOT tested or incorrectly tested>"
  ],
  "style_issues": [
    "<only flag: uses $fatal on fail, no summary line, or no $finish>"
  ],
  "verdict": "<one-line summary>"
}}

Set "passed": true if all required operations are tested.
For top-level integration modules, treat an operation as tested if the TB exercises that intended flow and verifies the correct observable top-level behavior, even when internal datapath values are not directly visible.
Set "passed": false ONLY if one or more required operations are completely missing from the testbench.
Return ONLY the JSON.
"""

_tc_chain = ChatPromptTemplate.from_template(_TC_PROMPT) | _llm | StrOutputParser()


def _safe_call(inputs: dict, max_retries: int = 5) -> str:
    retries = 0
    while retries < max_retries:
        try:
            result = ""
            try:
                for chunk in _tc_chain.stream(inputs):
                    result += chunk
            except ValueError as e:
                if "No generation chunks were returned" in str(e):
                    result = ""
                else:
                    raise

            if not result.strip():
                try:
                    fallback = _tc_chain.invoke(inputs)
                    result = fallback if isinstance(fallback, str) else str(fallback)
                except Exception:
                    pass

            if not result.strip():
                retries += 1
                print(f"[TC_AGENT] Empty/streamless response. Retry ({retries}/{max_retries})...")
                time.sleep(5)
                continue
            return result
        except Exception as e:
            err = str(e)
            if "No generation chunks were returned" in err:
                retries += 1
                print(f"[TC_AGENT] Stream returned no chunks. Retry ({retries}/{max_retries})...")
                time.sleep(5)
            elif "Rate limit" in err or "429" in err or "rate_limit_error" in err or "Concurrency" in err:
                retries += 1
                print(f"[TC_AGENT] Rate limit/Concurrency. Waiting 30s ({retries}/{max_retries})...")
                time.sleep(30)
            elif any(k in err for k in ["524", "timeout", "5xx", "503", "502", "500", "stream_read_error", "APIError", "InternalServerError", "Upstream request failed", "Upstream service temporarily unavailable", "temporarily unavailable", "Connection error", "APIConnectionError"]):
                retries += 1
                print(f"[TC_AGENT] API error. Waiting 30s ({retries}/{max_retries})...")
                time.sleep(30)
            else:
                raise
    raise RuntimeError("[TC_AGENT] Failed after max retries.")

def _parse_json(text: str) -> dict:
    text = text.strip()
    match = re.search(r"```(?:json)?\s*(.*?)\s*```", text, re.DOTALL)
    if match:
        text = match.group(1).strip()
    else:
        start, end = text.find("{"), text.rfind("}")
        if start != -1 and end > start:
            text = text[start:end+1]
    try:
        return json.loads(text)
    except Exception:
        print("[TC_AGENT] JSON parse failed.")
        return {}


def _read_tb_file(tb_filename: str) -> str:
    path = os.path.join(TB_DIR, tb_filename)
    if not os.path.exists(path):
        return ""
    with open(path, "r", errors="ignore") as f:
        return f.read()


def run_single(
    target_module: str,
    rag_context: dict,
    tb_code: str = None,
    iteration: int = 1
) -> dict:
    """
    Đánh giá testcase coverage cho DUY NHẤT 1 module.

    Args:
        target_module: tên module (ví dụ 'alu')
        rag_context:   context từ rag_agent (chứa module_analysis)
        tb_code:       code TB nếu đã có sẵn, nếu None sẽ đọc từ file
        iteration:     iteration hiện tại

    Returns:
        dict chứa kết quả coverage
    """
    print(f"\n[TC_AGENT] Checking testcase coverage for '{target_module}' (iter={iteration})...")

    module_analysis = rag_context.get("module_analysis", {})

    # Tìm analysis cho target_module
    analysis = module_analysis.get(target_module, {})
    if not analysis:
        # Fallback: tìm theo tên gần nhất
        for key in module_analysis:
            if target_module.lower() in key.lower() or key.lower() in target_module.lower():
                analysis = module_analysis[key]
                break

    if not analysis:
        print(f"[TC_AGENT] ⚠️  No analysis found for '{target_module}' in rag_context.")
        analysis = {"description": "", "inferred_testcases": []}

    # Đọc TB code nếu chưa có
    if tb_code is None:
        tb_filename = f"tb_{target_module}.sv"
        tb_code = _read_tb_file(tb_filename)

    if not tb_code:
        print(f"[TC_AGENT] ⚠️  No TB code found for '{target_module}'.")
        return {
            "module": target_module,
            "passed": False,
            "covered": [],
            "missing": analysis.get("inferred_testcases", []),
            "style_issues": ["TB file not found"],
            "verdict": "TB file not found"
        }

    description = analysis.get("description", "")
    required_tcs = analysis.get("inferred_testcases", [])
    required_str = "\n".join(f"  {i+1}. {tc}" for i, tc in enumerate(required_tcs))

    print(f"[TC_AGENT] Module '{target_module}': {len(required_tcs)} required testcases")

    result_text = _safe_call({
        "module_name": target_module,
        "description": description,
        "required_testcases": required_str,
        "tb_code": tb_code
    })

    result = _parse_json(result_text)
    if not result:
        result = {
            "module": target_module,
            "passed": False,
            "covered": [],
            "missing": required_tcs,
            "style_issues": ["LLM parse failed"],
            "verdict": "Analysis failed"
        }

    status = "✅ PASS" if result.get("passed") else "❌ FAIL"
    pct = result.get("coverage_percent", 0)
    print(f"[TC_AGENT] '{target_module}': {status} ({pct}% coverage)")
    if result.get("missing"):
        for m in result["missing"]:
            print(f"  Missing: {m}")

    return result


# ── Compatibility wrapper ─────────────────────────────────────────────────────
def run(tb_files: dict, rag_context: dict, iteration: int = 1) -> dict:
    """
    Compatibility wrapper — giữ lại để không phá vỡ code cũ.
    Trong pipeline mới, main.py gọi run_single() trực tiếp.
    """
    print(f"\n[TC_AGENT] Checking testcase coverage (iter={iteration})...")

    module_analysis = rag_context.get("module_analysis", {})
    coverage = {}

    for module_name, analysis in module_analysis.items():
        tb_filename = f"tb_{module_name}.sv"
        tb_code = _read_tb_file(tb_filename)

        if not tb_code:
            for fname in tb_files:
                if module_name in fname.lower():
                    tb_code = tb_files[fname]
                    break

        result = run_single(
            target_module=module_name,
            rag_context=rag_context,
            tb_code=tb_code if tb_code else None,
            iteration=iteration
        )
        coverage[module_name] = result

    overall = all(v.get("passed", False) for v in coverage.values())
    print(f"[TC_AGENT] Overall: {'✅ ALL PASS' if overall else '❌ SOME FAIL'}")
    return coverage
