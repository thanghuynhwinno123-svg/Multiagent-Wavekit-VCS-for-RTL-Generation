"""
main.py
Entry point cho toàn bộ multi-agent RTL verification pipeline.

Chiến lược: Module-by-Module Bottom-Up
  Với mỗi module theo thứ tự generation_order (topological sort):
    Loop RTL:  Sinh RTL → RTL Syntax check
    Loop TB:   Sinh TB  → TB Syntax check → TestCase Coverage check
    Loop Func: Functional Simulation → nếu fail → sửa RTL (TB locked)
  Module N chỉ bắt đầu khi Module N-1 đã PASS hoàn toàn.
"""
import asyncio
import hashlib
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from dotenv import load_dotenv
from fastmcp import Client

import agents.rag_agent        as rag_agent
import agents.plan_agent       as plan_agent
import agents.rtl_agent        as rtl_agent
import agents.tb_agent         as tb_agent
import agents.syntax_agent     as syntax_agent
import agents.testcase_agent   as testcase_agent
import agents.functional_agent as functional_agent
import agents.debug_agent      as debug_agent

from core.memory_manager import MemoryManager
from core.reporter       import Reporter

load_dotenv()

MCP_URL             = "http://127.0.0.1:5000/mcp"
MAX_SYNTAX_RETRIES  = 10
MAX_TC_RETRIES      = 5
MAX_FUNC_RETRIES    = 10
MAX_RTL_RESETS      = 2
MAX_TB_REOPENS      = 2

BASE_DIR            = os.path.dirname(os.path.abspath(__file__))
PIPELINE_CACHE_DIR  = os.path.join(BASE_DIR, "cache", "pipeline_state")
CACHE_SCHEMA_VER    = 1


def _json_stable_dumps(obj) -> str:
    return json.dumps(obj, sort_keys=True, ensure_ascii=False, separators=(",", ":"))


def _sha1_text(text: str) -> str:
    return hashlib.sha1(text.encode("utf-8")).hexdigest()


def _file_digest(path: str) -> str:
    try:
        with open(path, "rb") as f:
            return hashlib.sha1(f.read()).hexdigest()
    except Exception:
        return "missing"


def _tree_fingerprint(root: str) -> str:
    if not os.path.exists(root):
        return "missing"
    entries = []
    for dirpath, _, filenames in os.walk(root):
        for fname in sorted(filenames):
            full = os.path.join(dirpath, fname)
            try:
                st = os.stat(full)
                rel = os.path.relpath(full, root)
                entries.append(f"{rel}|{st.st_size}|{int(st.st_mtime)}")
            except OSError:
                continue
    return _sha1_text("\n".join(entries))


def _build_rag_cache_meta(user_prompt: str) -> dict:
    return {
        "schema_version": CACHE_SCHEMA_VER,
        "prompt": user_prompt,
        "model": os.environ.get("OPENAI_MODEL", "gpt-5.4"),
        "base_url": os.environ.get("OPENAI_BASE_URL", ""),
        "spec_fingerprint": _tree_fingerprint(rag_agent.SPEC_DIR),
        "faiss_cache_fingerprint": _tree_fingerprint(rag_agent.FAISS_CACHE),
        "rag_agent_digest": _file_digest(rag_agent.__file__),
    }


def _build_plan_cache_meta(user_prompt: str, rag_context: dict) -> dict:
    return {
        "schema_version": CACHE_SCHEMA_VER,
        "prompt": user_prompt,
        "model": os.environ.get("OPENAI_MODEL", "gpt-5.4"),
        "base_url": os.environ.get("OPENAI_BASE_URL", ""),
        "rag_context_digest": _sha1_text(_json_stable_dumps(rag_context)),
        "rag_agent_digest": _file_digest(rag_agent.__file__),
        "plan_agent_digest": _file_digest(plan_agent.__file__),
    }


def _cache_key(prefix: str, meta: dict) -> str:
    return f"{prefix}_{_sha1_text(_json_stable_dumps(meta))[:20]}"


def _cache_path(key: str) -> str:
    os.makedirs(PIPELINE_CACHE_DIR, exist_ok=True)
    return os.path.join(PIPELINE_CACHE_DIR, f"{key}.json")


def _load_cache(key: str, expected_meta: dict):
    path = _cache_path(key)
    if not os.path.exists(path):
        return None
    try:
        with open(path, "r", encoding="utf-8") as f:
            blob = json.load(f)
    except Exception as e:
        print(f"[CACHE] Failed to read {path}: {e}")
        return None

    if not isinstance(blob, dict):
        return None
    meta = blob.get("meta")
    payload = blob.get("payload")
    if meta != expected_meta or not isinstance(payload, dict):
        print(f"[CACHE] Stale cache ignored: {path}")
        return None
    print(f"[CACHE] Hit: {path}")
    return payload


def _save_cache(key: str, meta: dict, payload: dict):
    path = _cache_path(key)
    blob = {"meta": meta, "payload": payload}
    with open(path, "w", encoding="utf-8") as f:
        json.dump(blob, f, indent=2, ensure_ascii=False)
    print(f"[CACHE] Saved: {path}")


def _get_cached_or_run_rag(user_prompt: str, reporter: Reporter) -> dict:
    disable_cache = os.environ.get("PIPELINE_DISABLE_CACHE", "").strip().lower() in {"1", "true", "yes", "y"}
    meta = _build_rag_cache_meta(user_prompt)
    key = _cache_key("rag", meta)
    rag_context = None if disable_cache else _load_cache(key, meta)
    if rag_context is None:
        rag_context = rag_agent.run(user_prompt)
        _save_cache(key, meta, rag_context)
    else:
        print("[MAIN] Using cached RAG context.")
    reporter.save_rag(rag_context)
    return rag_context


def _get_cached_or_run_plan(user_prompt: str, rag_context: dict, reporter: Reporter) -> dict:
    disable_cache = os.environ.get("PIPELINE_DISABLE_CACHE", "").strip().lower() in {"1", "true", "yes", "y"}
    meta = _build_plan_cache_meta(user_prompt, rag_context)
    key = _cache_key("plan", meta)
    plan = None if disable_cache else _load_cache(key, meta)
    if plan is None:
        plan = plan_agent.run(user_prompt, rag_context)
        _save_cache(key, meta, plan)
    else:
        print("[MAIN] Using cached plan.")
    reporter.save_plan(plan)
    return plan


def _print_banner(title: str):
    print(f"\n{'='*60}")
    print(f"  {title}")
    print(f"{'='*60}")


def _all_passed(results: list) -> bool:
    return bool(results) and all(r.get("passed", False) for r in results)


def _ask_user_reset() -> bool:
    """Hỏi user có muốn reset RTL và sinh lại không."""
    print("\n" + "!"*60)
    print("  RTL đã fail quá nhiều lần.")
    print("  Bạn có muốn RESET và sinh RTL hoàn toàn mới không?")
    print("  (TB sẽ được giữ nguyên)")
    print("!"*60)
    try:
        answer = input("  Nhập 'y' để reset, bất kỳ phím khác để dừng: ").strip().lower()
        return answer == "y"
    except (EOFError, KeyboardInterrupt):
        return False


def _get_module_info(plan: dict, target_file: str):
    """
    Tìm thông tin module/package từ plan dựa trên tên file.
    Trả về (module_name, is_package).
    """
    # Kiểm tra packages
    for pkg in plan.get("packages", []):
        if pkg.get("file", "") == target_file:
            return pkg.get("name", target_file.replace(".sv", "")), True

    # Kiểm tra modules
    for m in plan.get("modules", []):
        if m.get("file", f"{m.get('name')}.sv") == target_file:
            return m.get("name"), False

    # Fallback: đoán từ tên file
    name = target_file.replace(".sv", "")
    is_pkg = "pkg" in name.lower() or "package" in name.lower()
    return name, is_pkg


def _get_memory_for_module(mem: MemoryManager, module_name: str) -> str:
    """Lấy context memory về các lỗi trước đó của 1 module cụ thể (bao gồm cả lịch sử và code lỗi)."""
    parts = []

    # 1. RTL Syntax Error History
    if module_name in mem._rtl_syntax and mem._rtl_syntax[module_name].get("history"):
        for entry in mem._rtl_syntax[module_name]["history"]:
            if entry.get("status") == "fail":
                it = entry.get("iter", 1)
                parts.append(
                    f"### RTL SYNTAX ERROR (Attempt {it}):\n"
                    f"{entry.get('error_block', '')}\n"
                    f"--- RTL CODE THAT FAILED SYNTAX CHECK ---\n"
                    f"```systemverilog\n{entry.get('failed_code', '')}\n```"
                )

    # 2. Functional Simulation Error History
    if module_name in mem._functional and mem._functional[module_name].get("history"):
        for entry in mem._functional[module_name]["history"]:
            if entry.get("status") == "fail":
                it = entry.get("iter", 1)
                failed_tcs = entry.get("failed_testcases", [])
                tc_str = "\n".join(f"  - {tc}" for tc in failed_tcs) if failed_tcs else "  (None)"
                wk_analysis = entry.get("wavekit_analysis", "")
                wk_section = f"Wavekit Waveform Analysis:\n{wk_analysis}\n" if wk_analysis else ""
                parts.append(
                    f"### FUNCTIONAL SIMULATION ERROR (Attempt {it}):\n"
                    f"Failed testcases:\n{tc_str}\n"
                    f"{wk_section}"
                    f"Error log:\n{entry.get('error_block', '')}\n"
                    f"--- RTL CODE THAT FAILED FUNCTIONAL TESTS ---\n"
                    f"```systemverilog\n{entry.get('failed_code', '')}\n```"
                )

    # Giới hạn số lượng entries lưu lại tối đa 1 gần nhất.
    # Lý do: Nếu giữ nhiều entry (4), LLM đọc quá nhiều phân tích cũ và bị lẫn lộn
    # giữa các giải pháp thất bại của nhiều iteration — dẫn đến lặp lại vết xe đổ.
    # Chỉ cần biết lần NGAY TRƯỚC fail như thế nào là đủ.
    if len(parts) > 1:
        parts = parts[-1:]

    return "\n\n".join(parts) if parts else "None"


def _get_tb_memory_for_module(mem: MemoryManager, module_name: str) -> str:
    """Lấy context memory về lỗi TB của 1 module (bao gồm cả lịch sử và code lỗi)."""
    parts = []

    # 1. TB Syntax Error History
    if module_name in mem._tb_syntax and mem._tb_syntax[module_name].get("history"):
        history = mem._tb_syntax[module_name]["history"][-2:]
        for entry in history:
            if entry.get("status") == "fail":
                it = entry.get("iter", 1)
                parts.append(
                    f"### TB SYNTAX ERROR (Attempt {it}):\n"
                    f"{entry.get('error_block', '')}\n"
                    f"--- TB CODE THAT FAILED SYNTAX CHECK ---\n"
                    f"```systemverilog\n{entry.get('failed_code', '')}\n```"
                )

    # 2. Testcase Coverage Missing History
    if module_name in mem._testcase and mem._testcase[module_name].get("history"):
        history = mem._testcase[module_name]["history"][-2:]
        for entry in history:
            it = entry.get("iter", 1)
            missing = entry.get("missing_cases", [])
            if missing:
                missing_str = "\n".join(f"  - {tc}" for tc in missing)
                parts.append(
                    f"### MISSING TEST CASES (Attempt {it}):\n"
                    f"You MUST implement these testcases:\n{missing_str}\n"
                    f"--- TB CODE SNAPSHOT ---\n"
                    f"```systemverilog\n{entry.get('tb_code_snapshot', '')}\n```"
                )

    # 3. Functional mismatch history để TB có thể tự sửa golden model / timing
    if module_name in mem._functional and mem._functional[module_name].get("history"):
        history = [h for h in mem._functional[module_name]["history"] if h.get("status") == "fail"][-2:]
        for entry in history:
            it = entry.get("iter", 1)
            failed_tcs = entry.get("failed_testcases", [])
            tc_str = "\n".join(f"  - {tc}" for tc in failed_tcs) if failed_tcs else "  (None)"
            wk_analysis = entry.get("wavekit_analysis", "")
            wk_section = (
                f"--- WAVEKIT / WAVEFORM ANALYSIS ---\n{wk_analysis}\n"
                if wk_analysis else ""
            )
            parts.append(
                f"### FUNCTIONAL MISMATCH FEEDBACK (Attempt {it}):\n"
                f"The TB may contain wrong golden-model assumptions, wrong signal sampling time, or a stale expectation.\n"
                f"Failed checks observed in simulation:\n{tc_str}\n"
                f"--- RAW FUNCTIONAL LOG EXCERPT ---\n"
                f"{entry.get('error_block', '')}\n"
                f"{wk_section}"
                f"--- RTL SNAPSHOT USED DURING THIS FAILURE ---\n"
                f"```systemverilog\n{entry.get('failed_code', '')}\n```"
            )

    return "\n\n".join(parts) if parts else "None"


def _normalize_failed_testcases(failed_testcases: list) -> tuple:
    normalized = []
    for tc in failed_testcases or []:
        item = tc.strip()
        if not item:
            continue
        normalized.append(item)
    return tuple(sorted(normalized))


def _extract_failure_signature(items: list) -> tuple:
    """
    Chuẩn hóa fail records về chữ ký mềm hơn để phát hiện root-cause lặp lại
    dù cycle/time hoặc got/expected có thay đổi nhẹ.
    """
    signatures = []
    for item in items or []:
        text = item.strip()
        if not text:
            continue
        core = text.split("|", 1)[0].strip()
        core = re.sub(r"\s+", " ", core)
        signatures.append(core)
    return tuple(sorted(set(signatures)))


def _extract_signal_signature(items: list) -> tuple:
    signals = []
    for item in items or []:
        text = item.strip()
        if not text:
            continue
        left = text.split("|", 1)[0].strip()
        if "." in left:
            tc_name, signal_name = left.rsplit(".", 1)
            signals.append(f"{tc_name.strip()}::{signal_name.strip()}")
        else:
            signals.append(left)
    return tuple(sorted(set(signals)))


def _has_tb_mismatch_advisory(entry: dict) -> bool:
    wk = (entry.get("wavekit_analysis", "") or "").lower()
    return "possible tb expectation mismatch" in wk or "tb is checking payload values" in wk


def _should_reopen_tb(mem: MemoryManager, module_name: str) -> bool:
    """
    Mở lại TB nếu functional failures lặp lại mà gần như không đổi,
    hoặc waveform analysis đã gợi ý rõ khả năng checker/TB bị lệch.
    """
    history = mem._functional.get(module_name, {}).get("history", [])
    failed_history = [h for h in history if h.get("status") == "fail"]
    if len(failed_history) < 2:
        return False

    latest = failed_history[-1]
    previous = failed_history[-2]

    if _has_tb_mismatch_advisory(latest) and _has_tb_mismatch_advisory(previous):
        return True

    latest_tcs = _normalize_failed_testcases(latest.get("failed_testcases", []))
    previous_tcs = _normalize_failed_testcases(previous.get("failed_testcases", []))
    if latest_tcs and latest_tcs == previous_tcs:
        return True

    latest_sig = _extract_failure_signature(latest.get("failed_testcases", []))
    previous_sig = _extract_failure_signature(previous.get("failed_testcases", []))
    if latest_sig and latest_sig == previous_sig:
        return True

    latest_signal_map = _extract_signal_signature(latest.get("failed_testcases", []))
    previous_signal_map = _extract_signal_signature(previous.get("failed_testcases", []))
    if latest_signal_map and latest_signal_map == previous_signal_map:
        return True

    latest_errors = tuple(latest.get("errors", []))
    previous_errors = tuple(previous.get("errors", []))
    if latest_errors and latest_errors == previous_errors:
        return True

    latest_error_sig = _extract_failure_signature(latest.get("errors", []))
    previous_error_sig = _extract_failure_signature(previous.get("errors", []))
    return bool(latest_error_sig) and latest_error_sig == previous_error_sig

async def process_package(
    vcs_client, mem: MemoryManager, reporter: Reporter,
    pkg_name: str, pkg_file: str,
    plan: dict, rag_context: dict,
    verified_files: list
) -> bool:
    """
    Xử lý 1 package file: sinh RTL → syntax check.
    Trả về True nếu pass.
    """
    _print_banner(f"PACKAGE: {pkg_file}")

    for rtl_iter in range(1, MAX_SYNTAX_RETRIES + 1):
        print(f"\n[MAIN] Package syntax iteration {rtl_iter}/{MAX_SYNTAX_RETRIES}")

        memory_ctx = _get_memory_for_module(mem, pkg_name)

        rtl_agent.run_single(
            target_module=pkg_name,
            target_file=pkg_file,
            plan=plan,
            rag_context=rag_context,
            memory_context=memory_ctx,
            verified_files=list(verified_files),
            is_package=True
        )

        # Syntax check cho package
        syntax_results = await syntax_agent.run(
            vcs_client, mode="rtl", iteration=rtl_iter,
            target_module=pkg_file.replace(".sv", "")
        )
        reporter.save_syntax_result("rtl", syntax_results, rtl_iter)

        if _all_passed(syntax_results):
            print(f"[MAIN] ✅ Package '{pkg_file}' syntax PASS at iteration {rtl_iter}")
            return True

        for r in syntax_results:
            if not r.get("passed"):
                mem.save_syntax_error("rtl", pkg_name, rtl_iter,
                                      r.get("log", ""), r.get("code", ""))

    print(f"[MAIN] ❌ Package '{pkg_file}' syntax FAILED after max retries.")
    return False


async def process_module(
    vcs_client, mem: MemoryManager, reporter: Reporter,
    module_name: str, module_file: str,
    plan: dict, rag_context: dict,
    verified_files: list
) -> bool:
    """
    Xử lý 1 module hoàn chỉnh theo chuỗi:
    RTL Syntax → TB Syntax + Coverage → Functional Sim.
    Trả về True nếu module PASS toàn bộ.
    """
    _print_banner(f"MODULE: {module_name} ({module_file})")

    # ──────────────────────────────────────
    # LOOP A: RTL Syntax
    # ──────────────────────────────────────
    print(f"\n[MAIN] ── LOOP RTL: Sinh và kiểm tra syntax RTL cho '{module_name}' ──")
    rtl_syntax_ok = False

    for rtl_iter in range(1, MAX_SYNTAX_RETRIES + 1):
        print(f"\n[MAIN] RTL iteration {rtl_iter}/{MAX_SYNTAX_RETRIES}")

        memory_ctx = _get_memory_for_module(mem, module_name)

        rtl_agent.run_single(
            target_module=module_name,
            target_file=module_file,
            plan=plan,
            rag_context=rag_context,
            memory_context=memory_ctx,
            verified_files=list(verified_files),
        )

        syntax_results = await syntax_agent.run(
            vcs_client, mode="rtl", iteration=rtl_iter,
            target_module=module_name
        )
        reporter.save_syntax_result("rtl", syntax_results, rtl_iter)

        if _all_passed(syntax_results):
            print(f"[MAIN] ✅ RTL '{module_name}' syntax PASS at iteration {rtl_iter}")
            rtl_syntax_ok = True
            break

        for r in syntax_results:
            if not r.get("passed"):
                mem.save_syntax_error("rtl", module_name, rtl_iter,
                                      r.get("log", ""), r.get("code", ""))

    if not rtl_syntax_ok:
        print(f"[MAIN] ❌ RTL '{module_name}' syntax FAILED after max retries.")
        return False

    # ──────────────────────────────────────
    # LOOP B: TB Syntax + TestCase Coverage
    # ──────────────────────────────────────
    print(f"\n[MAIN] ── LOOP TB: Sinh và kiểm tra TB cho '{module_name}' ──")
    tb_locked = False

    for tc_iter in range(1, MAX_TC_RETRIES + 1):
        print(f"\n[MAIN] TB/TestCase iteration {tc_iter}/{MAX_TC_RETRIES}")

        tb_mem_ctx = _get_tb_memory_for_module(mem, module_name)

        tb_agent.run_single(
            target_module=module_name,
            plan=plan,
            rag_context=rag_context,
            memory_context=tb_mem_ctx
        )

        # TB Syntax check
        tb_syntax_ok = False
        for tb_syn_iter in range(1, MAX_SYNTAX_RETRIES + 1):
            print(f"[MAIN]   TB Syntax check {tb_syn_iter}/{MAX_SYNTAX_RETRIES}")

            tb_syntax_results = await syntax_agent.run(
                vcs_client, mode="tb", iteration=tb_syn_iter,
                target_module=module_name
            )
            reporter.save_syntax_result("tb", tb_syntax_results, tb_syn_iter)

            if _all_passed(tb_syntax_results):
                print(f"[MAIN]   ✅ TB '{module_name}' syntax PASS")
                tb_syntax_ok = True
                break

            for r in tb_syntax_results:
                if not r.get("passed"):
                    mem.save_syntax_error("tb", module_name, tb_syn_iter,
                                          r.get("log", ""), r.get("code", ""))

            if tb_syn_iter < MAX_SYNTAX_RETRIES:
                print("[MAIN]   Regenerating TB with syntax error context...")
                tb_mem_ctx = _get_tb_memory_for_module(mem, module_name)
                tb_agent.run_single(
                    target_module=module_name,
                    plan=plan,
                    rag_context=rag_context,
                    memory_context=tb_mem_ctx
                )

        if not tb_syntax_ok:
            print(f"[MAIN] ❌ TB '{module_name}' syntax failed at iteration {tc_iter}. Trying next TC iteration...")
            continue

        # TestCase Coverage check
        print(f"[MAIN]   Checking testcase coverage for '{module_name}'...")
        coverage = testcase_agent.run_single(
            target_module=module_name,
            rag_context=rag_context,
            iteration=tc_iter
        )
        reporter.save_testcase_result({module_name: coverage}, tc_iter)

        if coverage.get("passed", False):
            print(f"[MAIN] ✅ TestCase Coverage PASS for '{module_name}' at iteration {tc_iter}")
            tb_locked = True
            break

        # Lưu missing testcases vào memory
        missing = coverage.get("missing", [])
        if missing:
            tb_path = os.path.join(
                os.path.dirname(os.path.abspath(__file__)),
                "generated_rtl", f"tb_{module_name}.sv"
            )
            tb_code = ""
            if os.path.exists(tb_path):
                with open(tb_path, "r", errors="ignore") as f:
                    tb_code = f.read()
            mem.save_testcase_miss(module_name, tc_iter, missing, tb_code)

    if not tb_locked:
        # Kiểm tra lần coverage cuối cùng — nếu >= 50% thì vẫn chấp nhận TB
        last_pct = coverage.get("coverage_percent", 0) if coverage else 0
        if last_pct >= 50:
            print(f"[MAIN] ⚠️  TestCase Coverage không đạt 100% sau {MAX_TC_RETRIES} vòng.")
            print(f"[MAIN] ✅ Coverage = {last_pct}% (≥ 50%) — chấp nhận TB hiện tại và tiếp tục.")
            tb_locked = True
        else:
            print(f"[MAIN] ❌ TestCase Coverage FAILED for '{module_name}' after max retries.")
            print(f"[MAIN]    Coverage cuối = {last_pct}% (< 50%) — dừng pipeline.")
            return False

    print(f"\n[MAIN] 🔒 TB '{module_name}' is LOCKED — will not be modified in functional loop.")

    # ──────────────────────────────────────
    # LOOP C: Functional Simulation
    # ──────────────────────────────────────
    print(f"\n[MAIN] ── LOOP FUNC: Mô phỏng chức năng cho '{module_name}' ──")
    func_iter    = 0
    func_passed  = False
    reset_count  = 0
    tb_reopen_count = 0

    while True:
        func_iter += 1
        print(f"\n[MAIN] Functional iteration {func_iter} for '{module_name}'")

        func_result = await functional_agent.run_single(
            vcs_client, target_module=module_name, iteration=func_iter
        )
        reporter.save_functional_result([func_result], func_iter)

        if func_result.get("passed"):
            print(f"\n[MAIN] 🎉 '{module_name}' FUNCTIONAL SIMULATION PASSED at iteration {func_iter}!")
            func_passed = True
            break

        # ─── Lưu lỗi functional vào memory (chưa có debug_instructions) ────────
        mem.save_functional_error(
            module_name, func_iter,
            func_result.get("log", ""),
            func_result.get("rtl_code", ""),
            failed_testcases=func_result.get("failed_testcases", []),
            wavekit_analysis=func_result.get("wavekit_analysis", ""),
            debug_instructions="",   # sẽ được cập nhật bên dưới sau khi chạy debug_agent
        )

        if tb_locked and tb_reopen_count < MAX_TB_REOPENS and _should_reopen_tb(mem, module_name):
            tb_reopen_count += 1
            tb_locked = False
            print(f"\n[MAIN] Re-opening TB for '{module_name}' (attempt {tb_reopen_count}/{MAX_TB_REOPENS})")
            print("[MAIN] Functional failures repeated with the same pattern; treating this as a possible TB/golden-model mismatch.")

            tb_mem_ctx = _get_tb_memory_for_module(mem, module_name)
            tb_agent.run_single(
                target_module=module_name,
                plan=plan,
                rag_context=rag_context,
                memory_context=tb_mem_ctx
            )

            tb_syntax_ok = False
            for tb_syn_iter in range(1, MAX_SYNTAX_RETRIES + 1):
                tb_syntax_results = await syntax_agent.run(
                    vcs_client, mode="tb", iteration=tb_syn_iter,
                    target_module=module_name
                )
                reporter.save_syntax_result("tb", tb_syntax_results, tb_syn_iter)
                if _all_passed(tb_syntax_results):
                    tb_syntax_ok = True
                    break
                for r in tb_syntax_results:
                    if not r.get("passed"):
                        mem.save_syntax_error("tb", module_name, tb_syn_iter,
                                              r.get("log", ""), r.get("code", ""))
                if tb_syn_iter < MAX_SYNTAX_RETRIES:
                    tb_mem_ctx = _get_tb_memory_for_module(mem, module_name)
                    tb_agent.run_single(
                        target_module=module_name,
                        plan=plan,
                        rag_context=rag_context,
                        memory_context=tb_mem_ctx
                    )

            if not tb_syntax_ok:
                print(f"[MAIN] Re-generated TB for '{module_name}' still has syntax errors. Continuing with RTL debug.")
            else:
                coverage = testcase_agent.run_single(
                    target_module=module_name,
                    rag_context=rag_context,
                    iteration=tb_reopen_count
                )
                reporter.save_testcase_result({module_name: coverage}, tb_reopen_count)

                if coverage.get("passed", False) or coverage.get("coverage_percent", 0) >= 50:
                    tb_locked = True
                    func_iter = 0
                    print(f"[MAIN] TB '{module_name}' re-locked after regeneration. Restarting functional loop with refreshed TB.")
                    continue

                missing = coverage.get("missing", [])
                if missing:
                    tb_path = os.path.join(
                        os.path.dirname(os.path.abspath(__file__)),
                        "generated_rtl", f"tb_{module_name}.sv"
                    )
                    tb_code = ""
                    if os.path.exists(tb_path):
                        with open(tb_path, "r", errors="ignore") as f:
                            tb_code = f.read()
                    mem.save_testcase_miss(module_name, tb_reopen_count, missing, tb_code)

                print(f"[MAIN] Re-generated TB for '{module_name}' still lacks sufficient coverage. Falling back to RTL debug.")

        if func_iter >= MAX_FUNC_RETRIES:
            if reset_count < MAX_RTL_RESETS:
                do_reset = _ask_user_reset()
                if do_reset:
                    mem.reset_functional(module_name)
                    reset_count += 1
                    func_iter = 0
                    print(f"[MAIN] RTL reset #{reset_count} for '{module_name}'. Generating fresh RTL...")

                    rtl_agent.run_single(
                        target_module=module_name,
                        target_file=module_file,
                        plan=plan,
                        rag_context=rag_context,
                        memory_context="None",
                        verified_files=list(verified_files),
                    )

                    for syn_i in range(1, MAX_SYNTAX_RETRIES + 1):
                        syn_res = await syntax_agent.run(
                            vcs_client, mode="rtl", iteration=syn_i,
                            target_module=module_name
                        )
                        reporter.save_syntax_result("rtl", syn_res, syn_i)
                        if _all_passed(syn_res):
                            break
                        for r in syn_res:
                            if not r.get("passed"):
                                mem.save_syntax_error("rtl", module_name, syn_i, r.get("log", ""))
                    continue
                else:
                    print(f"[MAIN] User chose not to reset '{module_name}'. Stopping.")
                    break
            else:
                print(f"[MAIN] Max resets ({MAX_RTL_RESETS}) reached for '{module_name}'. Stopping.")
                break

        # ─── 🔍 Gọi DEBUG AGENT để phân tích lỗi và tạo chỉ dẫn sửa lỗi ────────────
        print(f"\n[MAIN] 🔎 Invoking Debug Agent for '{module_name}' (iter {func_iter})...")

        # Lấy toàn bộ lịch sử functional fail của module này (để debug_agent biết tránh lặp chiến thuật)
        func_history = []
        if module_name in mem._functional and mem._functional[module_name].get("history"):
            func_history = mem._functional[module_name]["history"]

        db_instructions = debug_agent.run_single(
            target_module=module_name,
            rtl_code=func_result.get("rtl_code", ""),
            failed_testcases=func_result.get("failed_testcases", []),
            wavekit_analysis=func_result.get("wavekit_analysis", ""),
            sim_log=func_result.get("log", ""),
            plan=plan,
            rag_context=rag_context,
            functional_history=func_history,
        )

        # Cập nhật debug_instructions vào entry memory vừa lưu (entry cuối cùng)
        if module_name in mem._functional and mem._functional[module_name].get("history"):
            last_entry = mem._functional[module_name]["history"][-1]
            last_entry["debug_instructions"] = db_instructions
            # Ghi lại vào đĩa dể persist
            import os as _os
            module_dir = _os.path.join(
                _os.path.dirname(_os.path.abspath(__file__)), "memory", module_name
            )
            func_path = _os.path.join(module_dir, "functional.json")
            import json as _json
            _os.makedirs(module_dir, exist_ok=True)
            with open(func_path, "w", encoding="utf-8") as _f:
                _json.dump(mem._functional[module_name], _f, indent=2, ensure_ascii=False)
            print(f"[MAIN] 💾 Debug instructions saved to memory for '{module_name}'.")

        # Sửa RTL dựa trên chỉ dẫn từ Debug Agent
        print(f"[MAIN] 🔧 Fixing RTL for '{module_name}' guided by Debug Agent instructions...")
        # KHÔNG truyền raw memory cho RTL Agent khi đã có debug_instructions
        # (Debug Agent đã chưng cất toàn bộ thông tin cần thiết — truyền thêm memory sẽ gây nhiễu)

        rtl_agent.run_single(
            target_module=module_name,
            target_file=module_file,
            plan=plan,
            rag_context=rag_context,
            memory_context="None",
            verified_files=list(verified_files),
            debug_instructions=db_instructions,
        )

        # Quick syntax check on fixed RTL
        print(f"[MAIN] Quick RTL syntax check on fixed '{module_name}'...")
        for syn_i in range(1, MAX_SYNTAX_RETRIES + 1):
            syn_res = await syntax_agent.run(
                vcs_client, mode="rtl", iteration=syn_i,
                target_module=module_name
            )
            if _all_passed(syn_res):
                print(f"[MAIN] ✅ Fixed RTL passed syntax check.")
                break
            for r in syn_res:
                if not r.get("passed"):
                    mem.save_syntax_error("rtl", module_name, syn_i,
                                          r.get("log", ""), r.get("code", ""))
            if syn_i < MAX_SYNTAX_RETRIES:
                rtl_memory = _get_memory_for_module(mem, module_name)
                rtl_agent.run_single(
                    target_module=module_name,
                    target_file=module_file,
                    plan=plan,
                    rag_context=rag_context,
                    memory_context=rtl_memory,
                    verified_files=list(verified_files),
                    # Khi fix syntax thì không dùng debug_instructions (chỉ sửa syntax)
                    debug_instructions=None,
                )

    return func_passed


async def run_pipeline(user_prompt: str):
    mem      = MemoryManager()
    reporter = Reporter()

    # ── STEP 1: RAG ──────────────────────────────────────
    _print_banner("STEP 1: RAG AGENT")
    rag_context = _get_cached_or_run_rag(user_prompt, reporter)

    # ── STEP 2: PLAN ─────────────────────────────────────
    _print_banner("STEP 2: PLAN AGENT")
    plan = _get_cached_or_run_plan(user_prompt, rag_context, reporter)
    mem.set_plan_context(plan)

    generation_order = plan.get("generation_order", [])
    if not generation_order:
        print("[MAIN] ❌ generation_order is empty in plan. Cannot proceed.")
        return

    print(f"\n[MAIN] Bottom-up generation order ({len(generation_order)} items):")
    for i, fname in enumerate(generation_order):
        print(f"  [{i+1}/{len(generation_order)}] {fname}")

    async with Client(MCP_URL, timeout=600.0) as vcs_client:
        print("\n[MAIN] Connected to MCP VCS server.")
        try:
            tools = await vcs_client.list_tools()
            print(f"[MAIN] Registered MCP tools: {[t.name for t in tools]}")
        except Exception as e:
            print(f"[MAIN] Failed to list MCP tools: {e}")

        # Danh sách các file đã được verify thành công
        # (dùng để cung cấp context port cho các module cấp cao hơn)
        verified_files = []

        # ── LOOP CHÍNH: từng file trong generation_order ──
        for idx, target_file in enumerate(generation_order):
            module_name, is_package = _get_module_info(plan, target_file)

            _print_banner(
                f"[{idx+1}/{len(generation_order)}] "
                f"{'PACKAGE' if is_package else 'MODULE'}: {target_file}"
            )

            if is_package:
                ok = await process_package(
                    vcs_client=vcs_client,
                    mem=mem,
                    reporter=reporter,
                    pkg_name=module_name,
                    pkg_file=target_file,
                    plan=plan,
                    rag_context=rag_context,
                    verified_files=verified_files
                )
            else:
                ok = await process_module(
                    vcs_client=vcs_client,
                    mem=mem,
                    reporter=reporter,
                    module_name=module_name,
                    module_file=target_file,
                    plan=plan,
                    rag_context=rag_context,
                    verified_files=verified_files
                )

            if ok:
                verified_files.append(target_file)
                print(f"\n[MAIN] ✅ '{target_file}' is now VERIFIED and added to verified pool.")
                print(f"[MAIN]    Verified so far: {verified_files}")
            else:
                print(f"\n[MAIN] ❌ PIPELINE STOPPED: '{target_file}' failed to pass all checks.")
                print(f"[MAIN]    Check reports/ for details.")
                return

        # ── PIPELINE COMPLETE ─────────────────────────────
        _print_banner("PIPELINE COMPLETE")
        print(f"  ✅ SUCCESS: All {len(generation_order)} modules/packages verified!")
        print(f"  RTL files: generated_rtl/")
        print(f"  Reports:   reports/")
        print(f"\n  Verified modules in order:")
        for i, f in enumerate(verified_files):
            print(f"    [{i+1}] {f}")


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Multi-Agent RTL Verification System (Module-by-Module Bottom-up)")
    parser.add_argument("prompt", nargs="?", default=None, help="Design prompt")
    parser.add_argument("--reset-memory", action="store_true", help="Clear all memory before starting")
    args = parser.parse_args()

    if args.reset_memory:
        mem = MemoryManager()
        mem.reset_all()
        print("[MAIN] All memory cleared.")

    if args.prompt:
        user_prompt = args.prompt
    else:
        print("Multi-Agent RTL Verification System")
        print("Strategy: Module-by-Module Bottom-Up")
        print("─" * 40)
        user_prompt = input("Nhập design prompt: ").strip()
        if not user_prompt:
            print("No prompt provided. Exiting.")
            sys.exit(1)

    asyncio.run(run_pipeline(user_prompt))
