"""
core/reporter.py
Ghi kết quả từng bước vào thư mục reports/.
"""
import os
import json
from datetime import datetime

BASE_DIR    = os.path.dirname(os.path.abspath(__file__))
REPORTS_DIR = os.path.join(BASE_DIR, "..", "reports")


def _ts() -> str:
    return datetime.now().strftime("%Y-%m-%d %H:%M:%S")


def _write(filename: str, content: str):
    os.makedirs(REPORTS_DIR, exist_ok=True)
    path = os.path.join(REPORTS_DIR, filename)
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    print(f"[REPORTER] Saved: {path}")


class Reporter:

    def save_rag(self, rag_context: dict):
        lines = [f"# RAG Context Report\n_Generated: {_ts()}_\n"]
        lines.append(f"## Summary\n{rag_context.get('summary', 'N/A')}\n")
        modules = rag_context.get("modules", [])
        lines.append(f"## Detected Modules ({len(modules)})\n")
        for m in modules:
            lines.append(f"- `{m}`")
        analysis = rag_context.get("module_analysis", {})
        if analysis:
            lines.append("\n## Module Analysis & Inferred Test Cases\n")
            for mod, info in analysis.items():
                desc = info.get("description", "")
                tcs  = info.get("inferred_testcases", [])
                lines.append(f"### `{mod}`")
                lines.append(f"**Description:** {desc}\n")
                lines.append(f"**Inferred Test Cases ({len(tcs)}):**")
                for tc in tcs:
                    lines.append(f"- {tc}")
                lines.append("")
        lines.append("\n## Raw Context\n```\n" + rag_context.get("raw_context", "") + "\n```")
        _write("01_rag_context.md", "\n".join(lines))

    def save_plan(self, plan: dict):
        _write("02_plan.json", json.dumps(plan, indent=2, ensure_ascii=False))

    def save_rtl_list(self, files: dict, iteration: int = 1):
        lines = [f"# RTL Generation Report (Iteration {iteration})\n_Generated: {_ts()}_\n"]
        lines.append(f"## Files Generated ({len(files)})\n")
        for fname in files:
            lines.append(f"- `{fname}`")
        _write("03_rtl_generated.md", "\n".join(lines))

    def save_tb_list(self, files: dict, iteration: int = 1):
        lines = [f"# Testbench Generation Report (Iteration {iteration})\n_Generated: {_ts()}_\n"]
        lines.append(f"## Files Generated ({len(files)})\n")
        for fname in files:
            lines.append(f"- `{fname}`")
        _write("04_tb_generated.md", "\n".join(lines))

    def save_syntax_result(self, mode: str, results: list, iteration: int = 1):
        num   = "05" if mode == "rtl" else "06"
        label = "RTL" if mode == "rtl" else "Testbench"
        lines = [f"# {label} Syntax Check Report (Iteration {iteration})\n_Generated: {_ts()}_\n"]
        passed_list = [r for r in results if r.get("passed")]
        failed_list = [r for r in results if not r.get("passed")]
        lines.append(f"## Summary\n- ✅ PASS: {len(passed_list)}\n- ❌ FAIL: {len(failed_list)}\n")
        if failed_list:
            lines.append("## Failed Modules\n")
            for r in failed_list:
                lines.append(f"### ❌ `{r['module']}`")
                lines.append(f"**Reasons:** {', '.join(r.get('reasons', []))}\n")
                lines.append("**Log excerpt:**\n```\n" + r.get("log", "")[:2000] + "\n```\n")
        if passed_list:
            lines.append("## Passed Modules\n")
            for r in passed_list:
                lines.append(f"- ✅ `{r['module']}`")
        _write(f"{num}_syntax_{mode}.md", "\n".join(lines))

    def save_testcase_result(self, coverage: dict, iteration: int = 1):
        lines = [f"# TestCase Coverage Report (Iteration {iteration})\n_Generated: {_ts()}_\n"]
        overall_pass = all(v.get("passed", False) for v in coverage.values())
        lines.append(f"## Overall: {'✅ PASS' if overall_pass else '❌ FAIL'}\n")
        for module, info in coverage.items():
            passed  = info.get("passed", False)
            covered = info.get("covered", [])
            missing = info.get("missing", [])
            pct     = info.get("coverage_percent", 0)
            lines.append(f"### `{module}` — {'✅ PASS' if passed else '❌ FAIL'} ({pct}% coverage)")
            for c in covered:
                lines.append(f"  - ✅ {c}")
            for m in missing:
                lines.append(f"  - ❌ MISSING: {m}")
            for s in info.get("style_issues", []):
                lines.append(f"  - ⚠️ STYLE: {s}")
            lines.append("")
        _write("07_testcase_coverage.md", "\n".join(lines))

    def save_functional_result(self, results: list, iteration: int = 1):
        lines = [f"# Functional Simulation Report (Iteration {iteration})\n_Generated: {_ts()}_\n"]
        passed_list = [r for r in results if r.get("passed")]
        failed_list = [r for r in results if not r.get("passed")]
        lines.append(f"## Summary\n- ✅ PASS: {len(passed_list)}\n- ❌ FAIL: {len(failed_list)}\n")
        if failed_list:
            lines.append("## Failed\n")
            for r in failed_list:
                lines.append(f"### ❌ `{r['module']}`")
                lines.append(f"**Reasons:** {', '.join(r.get('reasons', []))}\n")
                lines.append("```\n" + r.get("log", "")[:3000] + "\n```\n")
        if passed_list:
            lines.append("## Passed\n")
            for r in passed_list:
                lines.append(f"- ✅ `{r['module']}`")
        _write("08_functional.md", "\n".join(lines))
