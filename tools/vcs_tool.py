"""
tools/vcs_tool.py
Wrapper gọi MCP VCS server.
- compile_only(): kiểm tra syntax, không chạy simulation
- compile_and_run(): compile + chạy simulation (-R)
"""
import os
import re
import json
from fastmcp import Client

MCP_URL = "http://127.0.0.1:5000/mcp"
client = Client(MCP_URL, timeout=600.0)


def get_dependencies(target_file: str, folder: str, all_rtl_files: list, found: set = None) -> set:
    if found is None:
        found = set()
    if target_file in found:
        return found
    found.add(target_file)
    file_path = os.path.join(folder, target_file)
    if not os.path.exists(file_path):
        return found
    try:
        with open(file_path, "r", errors="ignore") as f:
            content = f.read()
        instances = re.findall(r"\b([a-zA-Z_][a-zA-Z0-9_]*)\s+[a-zA-Z_][a-zA-Z0-9_]*\s*\(", content)
        for inst_name in instances:
            potential_file = f"{inst_name}.sv"
            if potential_file in all_rtl_files and potential_file not in found:
                get_dependencies(potential_file, folder, all_rtl_files, found)
    except Exception as e:
        print(f"[VCS_TOOL] Warning reading {target_file}: {e}")
    return found


def scan_sv_files(folder: str):
    pkg_files, rtl_files, tb_files = [], [], []
    if not os.path.isdir(folder):
        return pkg_files, rtl_files, tb_files
    for f in sorted(os.listdir(folder)):
        if not f.endswith(".sv"):
            continue
        name = f.lower()
        if name.startswith("top_sim_"):
            continue
        if "pkg" in name or "package" in name:
            pkg_files.append(f)
        elif name.startswith("tb_") or "testbench" in name:
            tb_files.append(f)
        else:
            rtl_files.append(f)
    return pkg_files, rtl_files, tb_files


def extract_log_text(raw_result: str) -> str:
    raw = raw_result.strip()
    try:
        data = json.loads(raw)
        if isinstance(data, dict):
            if "run_log" in data:
                log_file = data["run_log"]
                if os.path.exists(log_file):
                    with open(log_file, "r", errors="ignore") as f:
                        return f.read()
            if "stdout" in data:
                return data["stdout"]
            if "stderr" in data:
                return data["stderr"]
    except Exception:
        pass
    return raw


def _get_error_check_log(log_text: str) -> str:
    """
    Loại bỏ phần prelude và script setup ở đầu log trước khi quét lỗi
    để tránh nhận diện nhầm các từ khóa như 'ERROR:' hay 'No module found'
    nằm trong phần định nghĩa lệnh bash của MCP server.
    """
    cleaned_lines = []
    for line in log_text.splitlines():
        stripped = line.strip()
        if (
            stripped.startswith("source_directory=") or
            stripped.startswith("workspace_copy=") or
            stripped.startswith("prelude=") or
            stripped.startswith("command=") or
            stripped.startswith("tool_module=") or
            stripped.startswith("if [") or
            stripped.startswith("echo \"ERROR:") or
            stripped.startswith("exit ") or
            stripped == "fi" or
            stripped.startswith("echo \"selected_module=") or
            stripped.startswith("module load") or
            stripped.startswith("module list") or
            stripped.startswith("srun -p") or
            stripped.startswith("module avail")
        ):
            continue
        cleaned_lines.append(line)
    return "\n".join(cleaned_lines)


def parse_status(log_text: str) -> dict:
    """
    Phân tích log mô phỏng theo chuẩn thống nhất:
    - Ưu tiên đọc tag [TEST_SUMMARY] PASS=X FAIL=Y (chuẩn mới)
    - Fallback về quét PASS/FAIL text nếu không có tag (backward compat)
    - Quét tất cả các dạng lỗi: $error, $fatal, UVM_ERROR, UVM_FATAL, VCS Error
    - Bóc tách danh sách từng testcase bị FAIL từ tag [TESTCASE_RESULT]
    """
    log_text = _get_error_check_log(log_text)
    # ── 1. Đọc [TEST_SUMMARY] chuẩn hoá (format mới) ──────────────────────
    summary_match = re.search(
        r"\[TEST_SUMMARY\]\s*PASS\s*=\s*(\d+)\s*FAIL\s*=\s*(\d+)",
        log_text, re.IGNORECASE
    )
    if summary_match:
        n_pass = int(summary_match.group(1))
        n_fail = int(summary_match.group(2))
        has_pass = n_pass > 0
        has_fail = n_fail > 0
    else:
        # ── Fallback: quét PASS/FAIL text (backward compatible) ────────────
        pass_matches = re.finditer(r"\bPASS(ED)?\b", log_text, re.IGNORECASE)
        has_pass = False
        for match in pass_matches:
            start_idx = match.start()
            prefix = log_text[max(0, start_idx - 10):start_idx].lower()
            if re.search(r"\b(0|no|zero)\s*$", prefix):
                continue
            has_pass = True
            break

        fail_matches = re.finditer(r"\bFAIL(ED)?\b", log_text, re.IGNORECASE)
        has_fail = False
        for match in fail_matches:
            start_idx = match.start()
            prefix = log_text[max(0, start_idx - 10):start_idx].lower()
            if re.search(r"\b(0|no|zero)\s*$", prefix):
                continue
            has_fail = True
            break
        n_pass = -1  # unknown
        n_fail = -1  # unknown

    # ── 2. Bóc tách từng testcase bị FAIL (từ tag [TESTCASE_RESULT]) ───────
    failed_testcases = re.findall(
        r"\[TESTCASE_RESULT\]\s*FAIL:\s*(.+)", log_text
    )
    # Trim mỗi entry
    failed_testcases = [tc.strip() for tc in failed_testcases]

    # ── 3. Quét TẤT CẢ các dạng lỗi hệ thống ─────────────────────────────
    has_sys_error = False
    for line in log_text.splitlines():
        # Bỏ qua các dòng chứa báo cáo 0 errors (ví dụ: "Error count: 0", "errors: 0", "0 errors")
        if re.search(r"\b(0|no|zero)\s*errors?\b", line, re.IGNORECASE):
            continue
        if re.search(r"\berrors?\s*(count)?\s*[:=]\s*(0|no|zero)\b", line, re.IGNORECASE):
            continue
        if re.search(r"(\$error|\$fatal|UVM_ERROR|UVM_FATAL|Error-|Error\s*\[|Fatal:|ERROR:)", line, re.IGNORECASE):
            has_sys_error = True
            break

    # ── 4. Xây dựng reasons ────────────────────────────────────────────────
    reasons = []
    if has_fail:
        tc_list = ", ".join(failed_testcases[:5]) if failed_testcases else "(unknown TCs)"
        reasons.append(f"FAIL testcases: {tc_list}")
    if has_sys_error:
        reasons.append("System/compiler error ($error/$fatal/UVM_ERROR/VCS Error)")
    if not has_pass:
        reasons.append("No PASS found in log")

    passed = has_pass and not has_fail and not has_sys_error
    return {
        "passed": passed,
        "pass_count": n_pass,
        "fail_count": n_fail,
        "failed_testcases": failed_testcases,
        "has_sys_error": has_sys_error,
        "reasons": reasons
    }


def extract_failed_files(log_text: str, all_files: list) -> list:
    found = set()
    matches = re.findall(r'"([a-zA-Z0-9_\-.]+\.sv)"', log_text)
    for m in matches:
        if m in all_files:
            found.add(m.replace(".sv", ""))
    return list(found)


async def _run_vcs(vcs_client, working_directory: str, files: list, run_sim: bool) -> str:
    # Keep working_directory as absolute path so the remote server can locate it
    # Deduplicate the files list while preserving compilation order to avoid redefinition errors
    dedup_files = list(dict.fromkeys(files))
    rel_files = [os.path.basename(f) for f in dedup_files]
    
    args = ["-full64", "-sverilog", "-debug_access+all"] + rel_files
    if run_sim:
        args.append("-R")
        
    try:
        result = await vcs_client.call_tool(
            "call_vcs",
            {"working_directory": working_directory, "args": args},
            timeout=600.0
        )
        if hasattr(result, "content") and result.content:
            raw = result.content[0].text
        else:
            raw = str(result)
        return extract_log_text(raw)
    except Exception as e:
        print(f"[VCS_TOOL] MCP call_vcs failed: {e}. Falling back to LOCAL execution...")
        
        import asyncio
        cmd_args = " ".join(args)
        bash_command = f"""source /etc/profile >/dev/null 2>&1 || true
tool_module=$(module -t avail vcs 2>&1 | grep -E '^vcs/' | tail -n 1)
if [ ! -z "$tool_module" ]; then
  module load "$tool_module" >/dev/null 2>&1 || true
fi
srun -p ai_partition -w bos-eda-node vcs {cmd_args} 2>&1"""

        process = await asyncio.create_subprocess_shell(
            bash_command,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            cwd=working_directory
        )
        stdout, _ = await process.communicate()
        raw_log = stdout.decode(errors="ignore")
        print(f"[VCS_TOOL] Local execution finished.")
        return raw_log


RUNLOG_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "runlog"))


async def compile_only(vcs_client, working_directory: str, files: list, log_name: str = None) -> dict:
    """Chỉ compile, không chạy simulation — dùng để check syntax."""
    print(f"[VCS] compile_only: {' '.join(os.path.basename(f) for f in files)}")
    log = await _run_vcs(vcs_client, working_directory, files, run_sim=False)
    
    if log_name:
        os.makedirs(RUNLOG_DIR, exist_ok=True)
        log_path = os.path.join(RUNLOG_DIR, log_name)
        with open(log_path, "w", encoding="utf-8") as f:
            f.write(log)
        print(f"[VCS] Saved run log to: {log_path}")

    # Quét tất cả các dạng lỗi compile + lỗi môi trường
    clean_log = _get_error_check_log(log)
    has_compile_error = bool(re.search(
        r"(Error[-\s\[]|Error\[|Fatal:|UVM_FATAL|\$fatal|ERROR:|No module found)",
        clean_log, re.IGNORECASE
    ))
    reasons = []
    if has_compile_error:
        reasons.append("Compile/environment error found")
    return {
        "passed": not has_compile_error,
        "reasons": reasons,
        "log": log
    }


async def compile_and_run(vcs_client, working_directory: str, files: list, log_name: str = None) -> dict:
    """Compile + chạy simulation (-R)."""
    print(f"[VCS] compile_and_run: {' '.join(os.path.basename(f) for f in files)}")
    log = await _run_vcs(vcs_client, working_directory, files, run_sim=True)
    
    if log_name:
        os.makedirs(RUNLOG_DIR, exist_ok=True)
        log_path = os.path.join(RUNLOG_DIR, log_name)
        with open(log_path, "w", encoding="utf-8") as f:
            f.write(log)
        print(f"[VCS] Saved run log to: {log_path}")

    status = parse_status(log)
    status["log"] = log
    return status
