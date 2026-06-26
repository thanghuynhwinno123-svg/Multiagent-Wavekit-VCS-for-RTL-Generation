"""
agents/functional_agent.py
Functional Agent:
  1. Đọc port list của RTL + TB
  2. Sinh top_sim_<module>.sv wrapper kết nối RTL + TB
  3. Gọi VCS compile+run (-R)
  4. FAIL → lưu memory (TB được lock, chỉ RTL bị sửa)

Pipeline mới: xử lý DUY NHẤT 1 module tại một thời điểm.
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
TB_DIR   = RTL_DIR
SIM_DIR  = RTL_DIR

_llm = ChatOpenAI(model=MODEL_NAME, temperature=0)

_WRAPPER_PROMPT = """\
You are a SystemVerilog expert. Generate a simulation wrapper (top_sim.sv) that connects a DUT (RTL module) and a testbench module (TB module with ports).

=== RTL MODULE CODE ===
```systemverilog
{rtl_code}
```

=== TESTBENCH MODULE CODE ===
```systemverilog
{tb_code}
```

=== WRAPPER RULES ===
1. The wrapper is a top-level module with NO ports: `module top_sim_{dut_name};`
2. Declare ALL shared signals as `logic` inside the wrapper.
3. Instantiate the RTL DUT and connect its ports to the shared signals.
4. Instantiate the TB module and connect its ports to the SAME shared signals.
   - TB OUTPUT ports → connect to DUT INPUT signals (TB drives DUT inputs)
   - TB INPUT ports  → connect to DUT OUTPUT signals (TB reads DUT outputs)
5. Include `timescale 1ns/1ps at the top.
6. Import any packages used by the RTL module.
7. Add an `initial` block to dump waveforms to a file named "sim.vcd":
   ```systemverilog
   initial begin
     $dumpfile("sim.vcd");
     $dumpvars(0, top_sim_{dut_name});
   end
   ```

=== OUTPUT FORMAT ===
===== FILE: top_sim_{dut_name}.sv =====
<SystemVerilog wrapper code>

Output ONLY the wrapper file. No explanation.
"""

_wrapper_chain = ChatPromptTemplate.from_template(_WRAPPER_PROMPT) | _llm | StrOutputParser()


def _safe_call(chain, inputs: dict, label: str, max_retries: int = 5) -> str:
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
                print(f"[{label}] API error. Waiting 30s ({retries}/{max_retries})...")
                time.sleep(30)
            else:
                raise
    raise RuntimeError(f"[{label}] Failed after {max_retries} retries.")

def _read_file(path: str) -> str:
    if not os.path.exists(path):
        return ""
    with open(path, "r", errors="ignore") as f:
        return f.read()


def _parse_wrapper_file(text: str) -> dict:
    files = {}
    parts = text.split("===== FILE:")
    for part in parts[1:]:
        try:
            name, code = part.split("=====", 1)
            files[name.strip()] = code.strip()
        except ValueError:
            continue
    return files


def _get_dependencies(target_file: str, folder: str, all_files: list, found: set = None) -> set:
    """Tìm file phụ thuộc bằng cách quét instance trong nội dung file."""
    if found is None:
        found = set()
    if target_file in found:
        return found
    found.add(target_file)
    path = os.path.join(folder, target_file)
    if not os.path.exists(path):
        return found
    try:
        with open(path, "r", errors="ignore") as f:
            content = f.read()
        instances = re.findall(r'\b([a-zA-Z_][a-zA-Z0-9_]*)\s+[a-zA-Z_][a-zA-Z0-9_]*\s*\(', content)
        for inst in instances:
            candidate = f"{inst}.sv"
            matched_file = None
            for af in all_files:
                if af.lower() == candidate.lower():
                    matched_file = af
                    break
            if matched_file and matched_file not in found:
                _get_dependencies(matched_file, folder, all_files, found)
    except Exception:
        pass
    return found


def _scan_rtl_files():
    pkg_files, rtl_files = [], []
    if not os.path.isdir(RTL_DIR):
        return pkg_files, rtl_files
    for f in sorted(os.listdir(RTL_DIR)):
        if not f.endswith(".sv"):
            continue
        name = f.lower()
        if name.startswith("top_sim_") or name.startswith("tb_") or "testbench" in name:
            continue
        if "pkg" in name or "package" in name:
            pkg_files.append(f)
        else:
            rtl_files.append(f)
    return pkg_files, rtl_files


def clean_systemverilog_code(text: str) -> str:
    match = re.search(r"```(?:systemverilog|sv|v|verilog)?\s*(.*?)\s*```", text, re.DOTALL | re.IGNORECASE)
    if match:
        code = match.group(1).strip()
    else:
        code = text.strip()
    lines = code.splitlines()
    cleaned_lines = []
    for line in lines:
        cleaned_line = line.strip()
        if "===== FILE" in cleaned_line or "=====" in cleaned_line:
            continue
        if cleaned_line.startswith("```"):
            continue
        cleaned_lines.append(line)
    return "\n".join(cleaned_lines).strip()


async def create_wrapper(dut_name: str, rtl_code: str, tb_code: str) -> str:
    print(f"\n[FUNC_AGENT] Creating wrapper: top_sim_{dut_name}.sv")
    result_text = _safe_call(
        _wrapper_chain,
        {"rtl_code": rtl_code, "tb_code": tb_code, "dut_name": dut_name},
        label="FUNC_AGENT_WRAPPER"
    )

    wrapper_code = clean_systemverilog_code(result_text)
    
    if "$dumpfile" in wrapper_code:
        import re
        wrapper_code = re.sub(r'\$dumpfile\s*\(\s*"[^"]+"\s*\)', f'$dumpfile("sim.vcd")', wrapper_code)
        print(f"[FUNC_AGENT] Ensured $dumpfile uses sim.vcd in top_sim_{dut_name}.sv")
    else:
        # Chèn khối mới nếu chưa có
        match = list(re.finditer(r'\bendmodule\b', wrapper_code, re.IGNORECASE))
        if match:
            last_match = match[-1]
            start_idx = last_match.start()
            dump_block = f"""
  initial begin
    $dumpfile("sim.vcd");
    $dumpvars(0, top_sim_{dut_name});
  end
"""
            wrapper_code = wrapper_code[:start_idx] + dump_block + wrapper_code[start_idx:]
            print(f"[FUNC_AGENT] Programmatically injected VCD dump block into top_sim_{dut_name}.sv")

    wrapper_filename = f"top_sim_{dut_name}.sv"
    path = os.path.join(SIM_DIR, wrapper_filename)
    with open(path, "w", encoding="utf-8") as f:
        f.write(wrapper_code)
    print(f"[FUNC_AGENT] Wrapper saved: {path}")
    return wrapper_filename


async def run_single(vcs_client, target_module: str, iteration: int = 1) -> dict:
    """
    Chạy functional simulation cho DUY NHẤT 1 module.

    Args:
        vcs_client:     MCP VCS client đang kết nối
        target_module:  tên module DUT (ví dụ 'alu')
        iteration:      số lần lặp hiện tại

    Returns:
        dict: {"module": str, "passed": bool, "log": str,
               "reasons": list, "rtl_code": str,
               "failed_testcases": list, "wrapper_file": str}
    """
    from tools.vcs_tool import compile_and_run

    print(f"\n[FUNC_AGENT] Running functional simulation "
          f"(target={target_module}, iter={iteration})...")

    pkg_files, rtl_files = _scan_rtl_files()
    rtl_abs = os.path.abspath(RTL_DIR)
    sim_abs = os.path.abspath(SIM_DIR)
    os.makedirs(sim_abs, exist_ok=True)

    tb_file = f"tb_{target_module}.sv"
    tb_path = os.path.join(TB_DIR, tb_file)

    if not os.path.exists(tb_path):
        print(f"[FUNC_AGENT] ⚠️  TB file not found: {tb_file}")
        return {
            "module": target_module,
            "passed": False,
            "log": f"TB file not found: {tb_file}",
            "reasons": ["TB file not found"],
            "rtl_code": "",
            "failed_testcases": [],
            "wrapper_file": ""
        }

    # Tìm RTL file của module
    rtl_file = None
    for rf in rtl_files:
        if rf.replace(".sv", "") == target_module:
            rtl_file = rf
            break

    rtl_code = ""
    if rtl_file:
        rtl_code = _read_file(os.path.join(RTL_DIR, rtl_file))
    else:
        print(f"[FUNC_AGENT] ⚠️  RTL file not found for module '{target_module}'")

    tb_code = _read_file(tb_path)

    # Sinh wrapper
    try:
        wrapper_filename = await create_wrapper(target_module, rtl_code, tb_code)
    except Exception as e:
        print(f"[FUNC_AGENT] ⚠️  Wrapper creation failed for '{target_module}': {e}")
        return {
            "module": target_module,
            "passed": False,
            "log": f"Wrapper creation failed: {e}",
            "reasons": ["Wrapper creation failed"],
            "rtl_code": rtl_code,
            "failed_testcases": [],
            "wrapper_file": ""
        }

    # Tập hợp file phụ thuộc của module này
    all_candidates = []
    if os.path.isdir(RTL_DIR):
        for f in os.listdir(RTL_DIR):
            if f.endswith(".sv") and not f.startswith("top_sim_"):
                all_candidates.append(f)

    dep_set = set()
    if rtl_file:
        _get_dependencies(rtl_file, RTL_DIR, all_candidates, dep_set)

    dep_rtl = [
        dep for dep in sorted(dep_set)
        if not dep.lower().startswith("tb_")
        and "testbench" not in dep.lower()
        and "pkg" not in dep.lower()
        and "package" not in dep.lower()
    ]

    compile_files = []
    # 1. Package files
    for pf in pkg_files:
        compile_files.append(os.path.join(rtl_abs, pf))
    # 2. RTL phụ thuộc (sub-modules đã được verify trước đó)
    for rf in dep_rtl:
        compile_files.append(os.path.join(rtl_abs, rf))
    # 3. TB file
    compile_files.append(os.path.join(rtl_abs, tb_file))
    # 4. Wrapper file
    compile_files.append(os.path.join(sim_abs, wrapper_filename))

    result = await compile_and_run(
        vcs_client, rtl_abs, compile_files,
        log_name=f"func_{target_module}_iter{iteration}.log"
    )
    result["module"]           = target_module
    result["rtl_code"]         = rtl_code
    result["wrapper_file"]     = wrapper_filename
    result["failed_testcases"] = result.get("failed_testcases", [])

    status = "✅ PASS" if result["passed"] else "❌ FAIL"
    print(f"[FUNC_AGENT] '{target_module}': {status}")
    if not result["passed"]:
        print(f"  Reasons: {', '.join(result.get('reasons', []))}")
        print(f"  Log snippet:\n{result.get('log', '')[-2000:]}")
        sim_log = result.get("log", "")

        # Kiểm tra VCD để quyết định có cần wavekit không
        from tools.wavekit_tool import _parse_vcd_signals, _detect_has_clock, \
            _extract_failed_signals_from_log, run_wavekit_analysis

        vcd_path = os.path.join(rtl_abs, "sim.vcd")
        # Tìm vcd_path trong workspace_copy nếu có
        import re as _re
        ws_match = _re.search(r"^workspace_copy=(/.+)", sim_log, _re.MULTILINE)
        if ws_match:
            candidate = os.path.join(ws_match.group(1).strip(), "sim.vcd")
            if os.path.exists(candidate):
                vcd_path = candidate

        is_sequential = False
        if os.path.exists(vcd_path):
            try:
                _sig_data   = _parse_vcd_signals(vcd_path)
                is_sequential = _detect_has_clock(_sig_data)
            except Exception:
                is_sequential = False

        if not is_sequential:
            # Combinational: chỉ trích xuất got/expected từ log, không cần MCP/VCD
            print(f"[FUNC_AGENT] Combinational design — skipping Wavekit, extracting got/expected from log.")
            failed = _extract_failed_signals_from_log(sim_log)
            if failed:
                lines = ["=== COMBINATIONAL DESIGN: FAIL SUMMARY ===",
                         "(No VCD/waveform analysis — fix logic directly)", ""]
                for item in failed:
                    lines.append(f"  [FAIL] TC={item['tc']} | Signal='{item['signal']}'"
                                 f"  got={item['got']}  expected={item['expected']}")
                lines.append("\nFix: Find the case branch for the failing TC, compare the"
                             " computed expression vs expected value, and correct the RTL logic.")
                result["wavekit_analysis"] = "\n".join(lines)
            else:
                result["wavekit_analysis"] = "[FUNC_AGENT] Combinational — no FAIL markers found in log."
        else:
            # Sequential: chạy wavekit đầy đủ (clock-sampled data có giá trị thực)
            try:
                print(f"[FUNC_AGENT] Sequential design — running Wavekit Waveform Analysis...")
                analysis = await run_wavekit_analysis(vcs_client, rtl_abs, target_module, sim_log=sim_log)
                result["wavekit_analysis"] = analysis
            except Exception as e:
                result["wavekit_analysis"] = f"Error running wavekit: {e}"
    else:
        result["wavekit_analysis"] = ""

    return result


# ── Compatibility wrapper ─────────────────────────────────────────────────────
async def run(vcs_client, iteration: int = 1) -> list:
    """
    Compatibility wrapper — giữ lại để không phá vỡ code cũ.
    Trong pipeline mới, main.py gọi run_single() trực tiếp.
    """
    print(f"\n[FUNC_AGENT] Running functional simulation (iter={iteration})...")

    tb_files = []
    if os.path.isdir(TB_DIR):
        for f in sorted(os.listdir(TB_DIR)):
            if f.endswith(".sv") and f.lower().startswith("tb_"):
                tb_files.append(f)

    if not tb_files:
        print("[FUNC_AGENT] No TB files found.")
        return []

    results = []
    for tb_file in tb_files:
        dut_name = tb_file.replace(".sv", "").replace("tb_", "", 1)
        result = await run_single(vcs_client, target_module=dut_name, iteration=iteration)
        results.append(result)

    return results
