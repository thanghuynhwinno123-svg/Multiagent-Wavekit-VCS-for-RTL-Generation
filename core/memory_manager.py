"""
core/memory_manager.py
Quản lý 4 loại memory riêng biệt:
  - memory_rtl_syntax.json  : lỗi syntax RTL
  - memory_tb_syntax.json   : lỗi syntax TB
  - memory_testcase.json    : testcase bị thiếu
  - memory_functional.json  : lỗi functional simulation
"""
import hashlib
import json
import os

BASE_DIR     = os.path.dirname(os.path.abspath(__file__))
MEMORY_DIR   = os.path.join(BASE_DIR, "..", "memory")

class MemoryManager:
    def __init__(self):
        os.makedirs(MEMORY_DIR, exist_ok=True)
        self._rtl_syntax = {}
        self._tb_syntax  = {}
        self._testcase   = {}
        self._functional = {}
        self._load_all()

    def _load_all(self):
        if not os.path.exists(MEMORY_DIR):
            return
        for item in os.listdir(MEMORY_DIR):
            item_path = os.path.join(MEMORY_DIR, item)
            if os.path.isdir(item_path):
                module = item
                rtl_path = os.path.join(item_path, "rtl_syntax.json")
                tb_path  = os.path.join(item_path, "tb_syntax.json")
                tc_path  = os.path.join(item_path, "testcase.json")
                func_path = os.path.join(item_path, "functional.json")

                if os.path.exists(rtl_path):
                    self._rtl_syntax[module] = self._load(rtl_path)
                if os.path.exists(tb_path):
                    self._tb_syntax[module] = self._load(tb_path)
                if os.path.exists(tc_path):
                    self._testcase[module] = self._load(tc_path)
                if os.path.exists(func_path):
                    self._functional[module] = self._load(func_path)

    def _load(self, path: str) -> dict:
        if os.path.exists(path):
            try:
                with open(path, "r", encoding="utf-8") as f:
                    data = json.load(f)
                    return data if isinstance(data, dict) else {}
            except Exception:
                pass
        return {}

    @staticmethod
    def _ensure_history_store(store: dict, module: str) -> dict:
        info = store.get(module)
        if not isinstance(info, dict):
            info = {}
            store[module] = info
        history = info.get("history")
        if not isinstance(history, list):
            info["history"] = []
        return info

    def _save(self, data: dict, path: str):
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)



    def _module_signature_from_plan(self, plan: dict, module: str) -> str:
        modules = plan.get("modules", []) if isinstance(plan, dict) else []
        target = next((m for m in modules if m.get("name") == module), {})
        testcase_entry = next((tc for tc in plan.get("testcase_plan", []) if tc.get("module") == module), {}) if isinstance(plan, dict) else {}
        dep_graph = plan.get("dependency_graph", {}) if isinstance(plan, dict) else {}
        payload = {
            "design_summary": plan.get("design_summary", {}) if isinstance(plan, dict) else {},
            "module": target,
            "testcase_plan": testcase_entry,
            "dependencies": dep_graph.get(module, []),
        }
        raw = json.dumps(payload, sort_keys=True, ensure_ascii=False)
        return hashlib.sha1(raw.encode("utf-8")).hexdigest()[:16]

    def _filter_store_for_context(self, store: dict, module: str, context_id: str, label: str):
        info = store.get(module)
        if not info or not info.get("history"):
            return

        history = info.get("history", [])
        matching = [h for h in history if h.get("context_id") == context_id]
        if matching:
            if len(matching) != len(history):
                print(f"[MEMORY] Context filter kept {len(matching)}/{len(history)} {label} entries for '{module}'.")
            info["history"] = matching
            return

        if any("context_id" in h for h in history):
            print(f"[MEMORY] Context filter cleared incompatible {label} history for '{module}'.")
            info["history"] = []

    def set_plan_context(self, plan: dict):
        modules = [m.get("name") for m in plan.get("modules", [])] if isinstance(plan, dict) else []
        self._context_ids = {}
        for module in modules:
            if not module:
                continue
            context_id = self._module_signature_from_plan(plan, module)
            self._context_ids[module] = context_id
            self._filter_store_for_context(self._rtl_syntax, module, context_id, "rtl_syntax")
            self._filter_store_for_context(self._tb_syntax, module, context_id, "tb_syntax")
            self._filter_store_for_context(self._testcase, module, context_id, "testcase")
            self._filter_store_for_context(self._functional, module, context_id, "functional")

    def _active_context_id(self, module: str) -> str:
        return getattr(self, "_context_ids", {}).get(module, "")

    @staticmethod
    def extract_error_block(log_text: str) -> str:
        lines = log_text.splitlines()
        start = None
        for i, line in enumerate(lines):
            if any(kw in line for kw in ["Error-", "Error [", "Error[", "Fatal:", "FAIL"]):
                start = i
                break
        if start is None:
            return "\n".join(lines[-200:])
        return "\n".join(lines[start:])

    @staticmethod
    def extract_errors(log_text: str) -> list:
        errors = []
        for line in log_text.splitlines():
            if any(kw in line for kw in [
                "Error-", "Error [", "error:", "Fatal:",
                "FAIL", "[TESTCASE_RESULT] FAIL",
                "$error", "$fatal", "UVM_ERROR", "UVM_FATAL"
            ]):
                errors.append(line.strip())
        return errors

    # ── Save ──────────────────────────────────
    def save_syntax_error(self, mode: str, module: str, iteration: int,
                          log_text: str, code: str = ""):
        error_block = self.extract_error_block(log_text)
        errors = self.extract_errors(log_text)
        entry = {
            "iter": iteration,
            "status": "fail",
            "error_block": error_block,
            "errors": errors,
            "failed_code": code,
            "context_id": self._active_context_id(module),
        }
        module_dir = os.path.join(MEMORY_DIR, module)
        os.makedirs(module_dir, exist_ok=True)
        
        filename = "rtl_syntax.json" if mode == "rtl" else "tb_syntax.json"
        path = os.path.join(module_dir, filename)

        store = self._rtl_syntax if mode == "rtl" else self._tb_syntax
        info = self._ensure_history_store(store, module)
        info["history"].append(entry)
        self._save(store[module], path)
        print(f"[MEMORY] Saved {mode} syntax error for '{module}' (iter {iteration})")

    def save_testcase_miss(self, module: str, iteration: int,
                           missing_cases: list, tb_code: str = ""):
        entry = {
            "iter": iteration,
            "missing_cases": missing_cases,
            "tb_code_snapshot": tb_code[:3000],
            "context_id": self._active_context_id(module),
        }
        module_dir = os.path.join(MEMORY_DIR, module)
        os.makedirs(module_dir, exist_ok=True)
        path = os.path.join(module_dir, "testcase.json")

        info = self._ensure_history_store(self._testcase, module)
        info["history"].append(entry)
        self._save(self._testcase[module], path)
        print(f"[MEMORY] Saved {len(missing_cases)} missing testcases for '{module}' (iter {iteration})")

    def save_functional_error(self, module: str, iteration: int,
                               log_text: str, code: str = "",
                               failed_testcases: list = None,
                               wavekit_analysis: str = "",
                               debug_instructions: str = ""):
        """
        Lưu lỗi functional simulation vào memory.
        failed_testcases:   danh sách tên testcase bị FAIL (từ parse_status).
        debug_instructions: bản chỉ dẫn sửa lỗi từ debug_agent (nếu có), lưu lại
                            để vòng sau biết tránh lặp chiến thuật đã thất bại.
        """
        error_block = self.extract_error_block(log_text)
        errors = self.extract_errors(log_text)
        entry = {
            "iter": iteration,
            "status": "fail",
            "error_block": error_block,
            "errors": errors,
            "failed_testcases": failed_testcases or [],
            "failed_code": code,
            "wavekit_analysis": wavekit_analysis,
            "debug_instructions": debug_instructions or "",
            "context_id": self._active_context_id(module),
        }
        module_dir = os.path.join(MEMORY_DIR, module)
        os.makedirs(module_dir, exist_ok=True)
        path = os.path.join(module_dir, "functional.json")

        info = self._ensure_history_store(self._functional, module)
        info["history"].append(entry)
        self._save(self._functional[module], path)
        tc_count = len(failed_testcases) if failed_testcases else 0
        print(f"[MEMORY] Saved functional error for '{module}' "
              f"(iter {iteration}, {tc_count} failed TCs)")

    # ── Context builders ──────────────────────
    def get_rtl_context(self) -> str:
        parts = []
        if self._rtl_syntax:
            parts.append("=== RTL SYNTAX ERRORS (previous iterations) ===")
            for module, info in self._rtl_syntax.items():
                if not info.get("history"):
                    continue
                last = info["history"][-1]
                code_lines = "\n".join(
                    f"{i+1}: {l}"
                    for i, l in enumerate(last.get("failed_code", "").splitlines())
                )
                parts.append(
                    f"### MODULE: {module}\nERROR:\n{last['error_block']}\n"
                    f"FAILED CODE:\n```systemverilog\n{code_lines}\n```"
                )
        if self._functional:
            parts.append("=== FUNCTIONAL SIMULATION ERRORS (previous iterations) ===")
            for module, info in self._functional.items():
                if not info.get("history"):
                    continue
                last = info["history"][-1]
                failed_tcs = last.get("failed_testcases", [])
                if failed_tcs:
                    tc_str = "\n".join(f"  - {tc}" for tc in failed_tcs)
                    tc_section = f"FAILED TESTCASES (fix RTL so these PASS):\n{tc_str}\n"
                else:
                    tc_section = ""
                wk_analysis = last.get("wavekit_analysis", "")
                wk_section = f"WAVEKIT WAVEFORM ANALYSIS:\n{wk_analysis}\n" if wk_analysis else ""
                code_lines = "\n".join(
                    f"{i+1}: {l}"
                    for i, l in enumerate(last.get("failed_code", "").splitlines())
                )
                parts.append(
                    f"### MODULE: {module}\n"
                    f"{tc_section}"
                    f"{wk_section}"
                    f"SIM ERROR LOG:\n{last['error_block']}\n"
                    f"FAILED RTL CODE:\n```systemverilog\n{code_lines}\n```"
                )
        return "\n\n".join(parts) if parts else "None"

    def get_tb_context(self) -> str:
        parts = []
        if self._tb_syntax:
            parts.append("=== TB SYNTAX ERRORS (previous iterations) ===")
            for module, info in self._tb_syntax.items():
                if not info.get("history"):
                    continue
                last = info["history"][-1]
                code_lines = "\n".join(
                    f"{i+1}: {l}"
                    for i, l in enumerate(last.get("failed_code", "").splitlines())
                )
                parts.append(
                    f"### TB MODULE: {module}\nERROR:\n{last['error_block']}\n"
                    f"FAILED CODE:\n```systemverilog\n{code_lines}\n```"
                )
        if self._testcase:
            parts.append("=== MISSING TESTCASES (from TestCase Agent) ===")
            for module, info in self._testcase.items():
                if not info.get("history"):
                    continue
                last = info["history"][-1]
                missing = "\n".join(f"  - {tc}" for tc in last.get("missing_cases", []))
                parts.append(
                    f"### MODULE: {module}\n"
                    f"MISSING TEST CASES (you MUST add these):\n{missing}"
                )
        return "\n\n".join(parts) if parts else "None"

    # ── Reset ─────────────────────────────────
    def reset_functional(self, module: str = None):
        if module:
            if module in self._functional:
                self._functional[module] = {}
            module_dir = os.path.join(MEMORY_DIR, module)
            path = os.path.join(module_dir, "functional.json")
            if os.path.exists(path):
                os.remove(path)
            print(f"[MEMORY] Functional memory for module '{module}' reset.")
        else:
            self._functional = {}
            if os.path.exists(MEMORY_DIR):
                for item in os.listdir(MEMORY_DIR):
                    item_path = os.path.join(MEMORY_DIR, item)
                    if os.path.isdir(item_path):
                        path = os.path.join(item_path, "functional.json")
                        if os.path.exists(path):
                            os.remove(path)
            print("[MEMORY] Functional memory reset for all modules.")

    def reset_all(self):
        import shutil
        if os.path.exists(MEMORY_DIR):
            shutil.rmtree(MEMORY_DIR)
        os.makedirs(MEMORY_DIR, exist_ok=True)
        self._rtl_syntax = {}
        self._tb_syntax  = {}
        self._testcase   = {}
        self._functional = {}
        print("[MEMORY] All memory cleared.")

    def get_total_functional_fail_count(self) -> int:
        total = 0
        for module in self._functional:
            history = self._functional[module].get("history", [])
            total += sum(1 for h in history if h.get("status") == "fail")
        return total
