"""
agents/syntax_agent.py
Syntax Agent: dùng VCS compile-only để kiểm tra syntax.
  mode='rtl' → check 1 RTL module + các file phụ thuộc của nó
  mode='tb'  → check 1 TB module + RTL của nó + các file phụ thuộc

Pipeline mới: mỗi lần chỉ check DUY NHẤT 1 module (target_module).
"""
import os
import re
import asyncio
from dotenv import load_dotenv

load_dotenv()

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
RTL_DIR  = os.path.join(BASE_DIR, "..", "generated_rtl")
TB_DIR   = RTL_DIR


def _scan_folder(folder: str):
    """Phân loại file .sv trong folder."""
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
            if candidate in all_files and candidate not in found:
                _get_dependencies(candidate, folder, all_files, found)
    except Exception:
        pass
    return found


def _build_compile_list_for_module(target_file: str, pkg_files: list, all_rtl: list) -> list:
    """
    Xây dựng danh sách file cần compile để check syntax cho target_file.
    Bao gồm: tất cả packages + target file + các RTL mà target file phụ thuộc.
    """
    working_dir = os.path.abspath(RTL_DIR)
    all_candidates = all_rtl[:]

    dep_set = set()
    _get_dependencies(target_file, working_dir, all_candidates, dep_set)

    # Lọc bỏ TB files và packages khỏi dep list
    dep_rtl = []
    for dep in sorted(dep_set):
        dep_lower = dep.lower()
        if dep_lower.startswith("tb_") or "testbench" in dep_lower:
            continue
        if "pkg" in dep_lower or "package" in dep_lower:
            continue
        if dep_lower.startswith("top_sim_"):
            continue
        dep_rtl.append(dep)

    compile_files = []
    # 1. Packages trước
    for pf in pkg_files:
        compile_files.append(os.path.join(working_dir, pf))
    # 2. RTL phụ thuộc (trừ chính nó, sẽ thêm sau)
    for rf in dep_rtl:
        full = os.path.join(working_dir, rf)
        if full not in compile_files:
            compile_files.append(full)

    return compile_files


async def run(vcs_client, mode: str, iteration: int = 1,
              target_module: str = None) -> list:
    """
    Chạy syntax check cho 1 module cụ thể (target_module).

    Args:
        mode:          'rtl' hoặc 'tb'
        iteration:     số lần lặp hiện tại (dùng cho tên log file)
        target_module: tên module (ví dụ 'alu') hoặc None để check tất cả (backward compat)

    Returns:
        list of {"module": str, "passed": bool, "log": str, "reasons": list, "code": str}
    """
    from tools.vcs_tool import compile_only

    print(f"\n[SYNTAX_AGENT] Running syntax check "
          f"(mode={mode}, target={target_module or 'ALL'}, iter={iteration})...")

    pkg_rtl, rtl_files, _ = _scan_folder(RTL_DIR)
    all_pkg  = list(dict.fromkeys(pkg_rtl))
    all_rtl  = rtl_files

    working_dir = os.path.abspath(RTL_DIR)
    results = []

    if mode == "rtl":
        if target_module is None:
            # Backward compat: compile tất cả RTL (dùng khi không có target)
            compile_files = [os.path.join(working_dir, f) for f in (all_pkg + all_rtl)]
            if not compile_files:
                print("[SYNTAX_AGENT] No RTL files found.")
                return []
            result = await compile_only(
                vcs_client, working_dir, compile_files,
                log_name=f"syn_rtl_iter{iteration}.log"
            )
            result["module"] = "all_rtl"
            result["code"] = ""
            result["files"] = all_pkg + all_rtl
            results.append(result)
        else:
            # Mode mới: chỉ compile target_module + dependencies
            target_file = f"{target_module}.sv"

            # Kiểm tra xem file có tồn tại không
            if not os.path.exists(os.path.join(working_dir, target_file)):
                print(f"[SYNTAX_AGENT] ⚠️  File not found: {target_file}")
                return [{"module": target_module, "passed": False,
                         "log": f"File not found: {target_file}",
                         "reasons": ["File not found"], "code": ""}]

            compile_files = _build_compile_list_for_module(target_file, all_pkg, all_rtl)

            # Đảm bảo target file ở cuối (sau dependencies)
            target_full = os.path.join(working_dir, target_file)
            if target_full in compile_files:
                compile_files.remove(target_full)
            compile_files.append(target_full)

            log_name = f"syn_rtl_{target_module}_iter{iteration}.log"
            result = await compile_only(
                vcs_client, working_dir, compile_files, log_name=log_name
            )
            result["module"] = target_module
            result["files"] = [os.path.basename(f) for f in compile_files]

            # Đọc code RTL để lưu vào memory nếu cần
            rtl_code = ""
            if os.path.exists(os.path.join(working_dir, target_file)):
                with open(os.path.join(working_dir, target_file), "r", errors="ignore") as f:
                    rtl_code = f.read()
            result["code"] = rtl_code
            results.append(result)

    elif mode == "tb":
        if target_module is None:
            # Backward compat: compile tất cả TB files
            _, tb_all_tb, tb_files = _scan_folder(TB_DIR)
            tb_dir_abs = os.path.abspath(TB_DIR)
            for tb_file in tb_files:
                module_name = tb_file.replace(".sv", "").replace("tb_", "")
                all_candidates = all_pkg + all_rtl
                dep_set = set()
                _get_dependencies(tb_file, TB_DIR, all_candidates, dep_set)
                rtl_file = f"{module_name}.sv"
                if rtl_file in all_rtl:
                    _get_dependencies(rtl_file, RTL_DIR, all_candidates, dep_set)
                dep_rtl = [
                    dep for dep in sorted(dep_set)
                    if not dep.lower().startswith("tb_")
                    and "testbench" not in dep.lower()
                    and "pkg" not in dep.lower()
                    and "package" not in dep.lower()
                ]
                compile_files = all_pkg[:]
                for rf in dep_rtl:
                    if rf not in compile_files:
                        compile_files.append(rf)
                tb_full = os.path.join(tb_dir_abs, tb_file)
                compile_files_full = [os.path.join(working_dir, f) for f in compile_files]
                compile_files_full.append(tb_full)
                await asyncio.sleep(0.5)
                result = await compile_only(
                    vcs_client, working_dir, compile_files_full,
                    log_name=f"syn_tb_{module_name}_iter{iteration}.log"
                )
                result["module"] = tb_file.replace(".sv", "")
                tb_path = os.path.join(TB_DIR, tb_file)
                tb_code = ""
                if os.path.exists(tb_path):
                    with open(tb_path, "r", errors="ignore") as f:
                        tb_code = f.read()
                result["code"] = tb_code
                results.append(result)
        else:
            # Mode mới: chỉ compile tb_<target_module>.sv + RTL của nó + dependencies
            tb_file = f"tb_{target_module}.sv"
            tb_path = os.path.join(working_dir, tb_file)

            if not os.path.exists(tb_path):
                print(f"[SYNTAX_AGENT] ⚠️  TB file not found: {tb_file}")
                return [{"module": f"tb_{target_module}", "passed": False,
                         "log": f"TB file not found: {tb_file}",
                         "reasons": ["TB file not found"], "code": ""}]

            # Dependencies của RTL module
            rtl_file = f"{target_module}.sv"
            all_candidates = all_pkg + all_rtl
            dep_set = set()

            if rtl_file in all_rtl:
                _get_dependencies(rtl_file, RTL_DIR, all_candidates, dep_set)

            dep_rtl = [
                dep for dep in sorted(dep_set)
                if not dep.lower().startswith("tb_")
                and "testbench" not in dep.lower()
                and "pkg" not in dep.lower()
                and "package" not in dep.lower()
                and not dep.lower().startswith("top_sim_")
            ]

            compile_files = all_pkg[:]
            for rf in dep_rtl:
                full = os.path.join(working_dir, rf)
                if full not in compile_files:
                    compile_files.append(full)

            # Thêm TB file cuối cùng
            compile_files_full = [
                f if os.path.isabs(f) else os.path.join(working_dir, f)
                for f in compile_files
            ]
            compile_files_full.append(tb_path)

            await asyncio.sleep(0.5)
            log_name = f"syn_tb_{target_module}_iter{iteration}.log"
            result = await compile_only(
                vcs_client, working_dir, compile_files_full, log_name=log_name
            )
            result["module"] = f"tb_{target_module}"

            tb_code = ""
            if os.path.exists(tb_path):
                with open(tb_path, "r", errors="ignore") as f:
                    tb_code = f.read()
            result["code"] = tb_code
            results.append(result)

    passed = [r for r in results if r["passed"]]
    failed = [r for r in results if not r["passed"]]
    print(f"[SYNTAX_AGENT] Results: {len(passed)} PASS, {len(failed)} FAIL")
    for r in failed:
        print(f"  ❌ {r['module']}: {', '.join(r.get('reasons', []))}")

    return results
