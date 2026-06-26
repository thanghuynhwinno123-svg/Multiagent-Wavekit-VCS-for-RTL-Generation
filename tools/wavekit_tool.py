"""
tools/wavekit_tool.py
Phân tích sâu file waveform (VCD) bằng wavekit MCP server hoặc phân tích VCD nội bộ.
Trích xuất:
  - Tín hiệu có thay đổi bất thường
  - Thời điểm (timestamp) xảy ra lỗi
  - Giá trị got vs expected từ log
  - Các transition cuối cùng của tín hiệu output trước khi FAIL
"""
import os
import re


# ── Phân tích VCD nội bộ (không cần thư viện ngoài) ─────────────────────────

def _parse_vcd_signals(vcd_path: str) -> dict:
    """
    Parse file VCD để lấy toàn bộ tín hiệu và các lần thay đổi giá trị.
    Trả về:
        {
          signal_name: [(timestamp, value), ...],
          ...
        }
    """
    signal_map   = {}  # wire_id -> signal_name
    signal_data  = {}  # signal_name -> [(timestamp, value)]
    current_time = 0

    scope_stack  = []
    in_dumpvars  = False

    with open(vcd_path, "r", errors="ignore") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue

            # Xác định thời gian hiện tại
            if line.startswith("#"):
                try:
                    current_time = int(line[1:])
                except ValueError:
                    pass
                continue

            # Phần header: khai báo tín hiệu
            if line.startswith("$var"):
                # Ví dụ: $var wire 1 ! clk $end
                parts = line.split()
                if len(parts) >= 5:
                    wire_id   = parts[3]
                    sig_name  = parts[4]
                    full_name = ".".join(scope_stack + [sig_name]) if scope_stack else sig_name
                    signal_map[wire_id] = full_name
                    signal_data[full_name] = []
                continue

            if "$scope" in line:
                parts = line.split()
                if len(parts) >= 3:
                    scope_stack.append(parts[2])
                continue

            if "$upscope" in line:
                if scope_stack:
                    scope_stack.pop()
                continue

            if "$dumpvars" in line:
                in_dumpvars = True
                continue

            if "$end" in line:
                in_dumpvars = False
                continue

            # Phần dữ liệu: thay đổi giá trị
            # Dạng scalar: 0! hoặc 1!
            scalar_match = re.match(r'^([01xzXZ])(\S+)$', line)
            if scalar_match:
                val, wire_id = scalar_match.group(1), scalar_match.group(2)
                if wire_id in signal_map:
                    sig = signal_map[wire_id]
                    signal_data[sig].append((current_time, val))
                continue

            # Dạng vector: b0101 !
            vector_match = re.match(r'^[bB](\S+)\s+(\S+)$', line)
            if vector_match:
                val, wire_id = vector_match.group(1), vector_match.group(2)
                if wire_id in signal_map:
                    sig = signal_map[wire_id]
                    signal_data[sig].append((current_time, val))
                continue

    return signal_data


def _extract_failed_signals_from_log(log_text: str) -> list:
    """
    Trích xuất đầy đủ các tín hiệu bị FAIL từ log mô phỏng, KHÔNG dedup sớm.
    Ví dụ: [TESTCASE_RESULT] FAIL: TC001_RESET.trap_vector_o | got=00000100 expected=00000000 | cycle=2 time=16000
    Trả về list các record, mỗi record gắn testcase, signal, cycle/time nếu có.
    """
    failed_signals = []
    pattern = re.compile(
        r'\[TESTCASE_RESULT\]\s*FAIL:\s*(\S+)\s*\|\s*got=(\S+)\s*expected=(\S+)(?:\s*\|\s*cycle=(\d+))?(?:\s*time=(\d+))?',
        re.IGNORECASE
    )
    for idx, match in enumerate(pattern.finditer(log_text), start=1):
        full_name = match.group(1)
        got = match.group(2)
        expected = match.group(3)
        cycle = int(match.group(4)) if match.group(4) is not None else None
        time_ps = int(match.group(5)) if match.group(5) is not None else None

        parts = full_name.rsplit('.', 1)
        if len(parts) == 2:
            tc_name = parts[0]
            sig_name = parts[1]
        else:
            tc_name = full_name
            sig_name = '?'

        failed_signals.append({
            'index': idx,
            'full_name': full_name,
            'tc': tc_name,
            'signal': sig_name,
            'got': got,
            'expected': expected,
            'cycle': cycle,
            'time_ps': time_ps,
        })
    return failed_signals


def _find_signal_matches(signal_data: dict, signal_name: str) -> list:
    """Tìm tất cả candidate khớp với signal_name, ưu tiên exact/top-level trước."""
    if signal_name == '?':
        return []

    exact = []
    top_level = []
    suffix = []
    partial = []
    for key in signal_data:
        short = key.split('.')[-1]
        if key == signal_name or short == signal_name:
            exact.append(key)
        elif key.endswith(f'.{signal_name}') and key.count('.') == 1:
            top_level.append(key)
        elif key.endswith(f'.{signal_name}'):
            suffix.append(key)
        elif signal_name in key:
            partial.append(key)
    return exact + top_level + suffix + partial


def _analyze_signal_transitions(signal_data: dict, failed_signals: list, max_transitions: int = 8) -> str:
    """
    Với mỗi FAIL record, lấy transition cuối của tín hiệu tương ứng.
    Giữ mapping testcase-to-signal đầy đủ để tránh mất ngữ cảnh khi cùng signal fail ở nhiều testcase.
    """
    if not failed_signals:
        return ''

    report_parts = []

    for item in failed_signals:
        sig = item['signal']
        got = item['got']
        exp = item['expected']
        tc = item['tc']
        cycle = item.get('cycle')
        time_ps = item.get('time_ps')

        matches = _find_signal_matches(signal_data, sig)
        matched_key = matches[0] if matches else None

        header = [f"  [FAIL #{item.get('index', '?')}] TC={tc} | Signal='{sig}'"]
        header.append(f"    got={got}  expected={exp}")
        if cycle is not None or time_ps is not None:
            meta = []
            if cycle is not None:
                meta.append(f"cycle={cycle}")
            if time_ps is not None:
                meta.append(f"time={time_ps}ps")
            header.append(f"    sample: {'  '.join(meta)}")
        if matched_key:
            header.append(f"    matched_vcd_signal={matched_key}")
        elif sig == '?':
            header.append('    matched_vcd_signal=(signal name not specified in log)')
        else:
            header.append('    matched_vcd_signal=(signal not found in VCD — may not be dumped)')

        transitions_str = '    waveform_detail=(unavailable)'
        if matched_key and signal_data[matched_key]:
            transitions = signal_data[matched_key]
            recent = transitions[-max_transitions:]
            t_lines = "\n".join(
                f"      t={ts}ps → value={val}"
                for ts, val in recent
            )
            last_val = recent[-1][1] if recent else '?'
            last_ts = recent[-1][0] if recent else '?'
            transitions_str = (
                f"    Last {len(recent)} transitions:\n{t_lines}\n"
                f"    Value at simulation end (t={last_ts}ps): {last_val} "
                f"(expected during failure sample: {exp})"
            )

        report_parts.append("\n".join(header + [transitions_str]))

    return "\n\n".join(report_parts)


def _detect_has_clock(signal_data: dict) -> bool:
    """
    Phát hiện xem VCD có tín hiệu clock hay không.
    Dùng để phân biệt combinational (không clock) vs sequential (có clock).
    """
    for sig in signal_data:
        sname = sig.split(".")[-1].lower()
        if sname in ("clk", "clock", "clk_i"):
            return True
        if "clk" in sname or "clock" in sname:
            return True
    return False


def _analyze_output_signals(signal_data: dict, is_sequential: bool = True) -> str:
    """
    Tóm tắt tất cả tín hiệu output (tên kết thúc bằng _o) với giá trị cuối cùng của chúng.
    Chỉ gắn nhãn POSSIBLY UNDRIVEN khi là sequential (có clock),
    vì với combinational thì tín hiệu không đổi là hoàn toàn bình thường.
    """
    # Chỉ giữ tín hiệu top-level (count(".")==1) để tránh duplicate từ các sub-hierarchy
    output_sigs = {
        k: v for k, v in signal_data.items()
        if k.endswith("_o") and v and k.count(".") == 1
    }
    if not output_sigs:
        return ""
    parts = ["Output signals final values:"]
    for sig, transitions in sorted(output_sigs.items()):
        last_ts, last_val = transitions[-1]
        # Chỉ cảnh báo POSSIBLY UNDRIVEN cho sequential design
        if is_sequential and len(transitions) == 1:
            flag = "  ⚠️  [POSSIBLY UNDRIVEN — only 1 transition, stuck at reset value]"
        else:
            flag = ""
        parts.append(f"  {sig}: last_value={last_val} @ t={last_ts}ps ({len(transitions)} transitions total){flag}")
    return "\n".join(parts)


def _group_failed_signals_by_testcase(failed_signals: list) -> dict:
    grouped = {}
    for item in failed_signals:
        grouped.setdefault(item.get('tc', '?'), []).append(item)
    return grouped


def _looks_nonzero(value: str) -> bool:
    value = (value or '').lower().strip()
    if not value:
        return False
    if all(ch in '0xz' for ch in value):
        return False
    return any(ch not in '0xz' for ch in value)


def _detect_tb_expectation_mismatch(signal_data: dict, failed_signals: list, is_sequential: bool) -> str:
    """
    Cảnh báo mềm khi waveform + fail pattern gợi ý checker/TB expectation có thể lệch.
    Không kết luận TB sai; chỉ nêu khả năng để pipeline cân nhắc reopen TB.
    """
    if not is_sequential or not failed_signals:
        return ''

    warnings = []
    grouped = _group_failed_signals_by_testcase(failed_signals)

    qualifier_keywords = ('taken', 'valid', 'done', 'ready', 'pending', 'req', 'we', 'hit', 'accept')
    payload_keywords = ('target', 'addr', 'data', 'result', 'pc', 'vector', 'cause', 'entry')

    for tc, items in grouped.items():
        qualifier_fails = [
            item for item in items
            if item.get('signal', '?') != '?' and any(k in item['signal'].lower() for k in qualifier_keywords)
            and str(item.get('got', '')).lower() in ('0', '00', '00000000')
            and _looks_nonzero(item.get('expected', ''))
        ]
        payload_fails = [
            item for item in items
            if item.get('signal', '?') != '?' and any(k in item['signal'].lower() for k in payload_keywords)
            and _looks_nonzero(item.get('expected', ''))
        ]
        if qualifier_fails and payload_fails:
            q_names = ', '.join(sorted({q['signal'] for q in qualifier_fails}))
            p_names = ', '.join(sorted({p['signal'] for p in payload_fails}))
            warnings.append(
                f"  - TC={tc}: qualifier signal(s) [{q_names}] are low while payload/data signal(s) [{p_names}] are expected nonzero. "
                "This may indicate the TB is checking payload values in a cycle where their qualifier is not asserted."
            )

    by_signal = {}
    for item in failed_signals:
        sig = item.get('signal', '?')
        if sig == '?':
            continue
        by_signal.setdefault(sig, []).append(item)

    for sig, items in sorted(by_signal.items()):
        expected_values = {item.get('expected') for item in items}
        tc_names = {item.get('tc') for item in items}
        if len(items) >= 2 and len(expected_values) >= 2:
            matches = _find_signal_matches(signal_data, sig)
            matched_key = matches[0] if matches else None
            transition_count = len(signal_data.get(matched_key, [])) if matched_key else 0
            warnings.append(
                f"  - Signal '{sig}' fails across multiple testcases {sorted(tc_names)} with different expected values {sorted(expected_values)}. "
                f"Waveform candidate={matched_key or '(not found)'} transition_count={transition_count}. "
                "Review whether the TB is assuming stale retained state or sampling in the wrong cycle."
            )

    if not warnings:
        return ''

    header = '--- ⚠️  POSSIBLE TB EXPECTATION MISMATCH (advisory only) ---'
    footer = 'Advisory: use this as a hint for TB/golden-model review, not as proof that RTL is correct.'
    return "\n".join([header] + warnings + [footer])


def _analyze_recent_transitions(signal_data: dict, n: int = 5) -> str:
    """
    In N transitions gần nhất của mỗi output signal để LLM thấy hoạt động cuối simulation.
    Chỉ in cho các tín hiệu có >1 transition (tín hiệu active).
    """
    output_keywords = ("_o", "_done", "_fail", "_valid", "_ready", "_taken", "_we", "result")
    output_sigs = {
        k: v for k, v in signal_data.items()
        if any(k.endswith(kw) or (f".{kw}" in k) for kw in output_keywords)
        and len(v) > 1
        and k.count(".") == 1  # chỉ lấy tín hiệu top-level, tránh duplicate từ u_dut/u_tb
    }
    if not output_sigs:
        return ""
    parts = [f"Recent signal transitions (last {n} per signal — for active outputs only):"]
    for sig, transitions in sorted(output_sigs.items()):
        recent = transitions[-n:]
        short_name = sig.split(".")[-1]
        t_lines = "  ".join(f"t={ts}ps→{val}" for ts, val in recent)
        parts.append(f"  {short_name}: {t_lines}")
    return "\n".join(parts)


def analyze_vcd_locally(vcd_path: str, sim_log: str = "") -> str:
    """
    Phân tích sâu file VCD nội bộ không cần thư viện bên ngoài.
    Với combinational design (không có clock), chỉ báo cáo got/expected — không có
    cảnh báo STUCK/UNDRIVEN vì chúng gây nhiễu cho LLM.
    Trả về báo cáo chi tiết bằng văn bản để LLM sử dụng làm context.
    """
    if not os.path.exists(vcd_path):
        return f"[WAVEKIT] VCD file not found at: {vcd_path}"

    try:
        signal_data = _parse_vcd_signals(vcd_path)
    except Exception as e:
        return f"[WAVEKIT] VCD parse error: {e}"

    is_sequential     = _detect_has_clock(signal_data)
    total_signals     = len(signal_data)
    active_signals    = sum(1 for v in signal_data.values() if len(v) > 1)
    failed_signals    = _extract_failed_signals_from_log(sim_log) if sim_log else []
    transition_report = _analyze_signal_transitions(signal_data, failed_signals)
    mismatch_warning = _detect_tb_expectation_mismatch(signal_data, failed_signals, is_sequential)

    sections = [
        f"=== WAVEFORM ANALYSIS REPORT: {os.path.basename(vcd_path)} ===",
        f"Design type: {'Sequential (clock detected)' if is_sequential else 'Combinational (no clock)'}",
        f"Total signals captured: {total_signals}",
        f"Signals with activity (>1 transition): {active_signals}",
    ]

    if failed_signals:
        sections.append(
            f"\n--- FAILED SIGNAL DETAILS ({len(failed_signals)} signals) ---\n"
            f"{transition_report}"
        )
    else:
        sections.append("\n[INFO] No FAIL markers found in simulation log.")

    # Output signal summary — chỉ hiển thị khi là sequential
    if is_sequential:
        output_report = _analyze_output_signals(signal_data, is_sequential=True)
        recent_report = _analyze_recent_transitions(signal_data)
        if output_report:
            sections.append(f"\n--- OUTPUT SIGNAL SUMMARY ---\n{output_report}")
        if recent_report:
            sections.append(f"\n--- RECENT TRANSITIONS ---\n{recent_report}")
        if mismatch_warning:
            sections.append(f"\n{mismatch_warning}")

        # Tín hiệu bị stuck: CHỈ báo cáo cho sequential designs
        stuck_sigs = [sig for sig, trans in signal_data.items() if len(trans) == 1]
        if stuck_sigs:
            output_stuck   = [s for s in stuck_sigs if s.endswith("_o") and ".dut." not in s and ".tb." not in s]
            internal_stuck = [s for s in stuck_sigs if s not in output_stuck]

            if output_stuck:
                shown_out = output_stuck[:8]
                rest_out  = len(output_stuck) - len(shown_out)
                rest_note = f" (+{rest_out} more output signals)" if rest_out > 0 else ""
                sections.append(
                    f"\n--- ⚠️  STUCK OUTPUT SIGNALS (critical — never driven after reset){rest_note} ---\n"
                    + "\n".join(f"  {s}" for s in shown_out)
                )
            if internal_stuck:
                shown_int = internal_stuck[:5]
                rest_int  = len(internal_stuck) - len(shown_int)
                rest_note = f" (+{rest_int} more)" if rest_int > 0 else ""
                sections.append(
                    f"\n--- STUCK INTERNAL SIGNALS (possibly undriven state/data regs){rest_note} ---\n"
                    + "  " + ", ".join(s.split(".")[-1] for s in shown_int)
                )
    else:
        # Combinational: chỉ in transitions của signal bị fail, không có gì thêm
        sections.append(
            "\n[NOTE] Combinational design — STUCK/UNDRIVEN warnings suppressed."
            " Focus on got vs expected values above to fix RTL logic."
        )

    return "\n".join(sections)


# ── Entry point chính ────────────────────────────────────────────────────────

async def run_wavekit_analysis(vcs_client, working_directory: str, module_name: str,
                                sim_log: str = "") -> str:
    """
    Thực hiện phân tích waveform với độ sâu cao.
    - Với COMBINATIONAL design (không có clock): chỉ trích xuất got/expected từ log,
      KHÔNG phân tích VCD (tránh nhiễu cảnh báo STUCK/UNDRIVEN sai).
    - Với SEQUENTIAL design (có clock): chạy full VCD analysis.
    Ưu tiên: wavekit-mcp (port 5001) → phân tích VCD nội bộ (fallback).
    """
    vcd_path = os.path.join(working_directory, "sim.vcd")
    
    # Extract workspace_copy from sim_log if the simulation ran in a temporary directory
    if sim_log:
        workspace_match = re.search(r"^workspace_copy=(/.+)", sim_log, re.MULTILINE)
        if workspace_match:
            temp_dir = workspace_match.group(1).strip()
            temp_vcd_path = os.path.join(temp_dir, "sim.vcd")
            if os.path.exists(temp_vcd_path):
                vcd_path = temp_vcd_path
                print(f"[WAVEKIT] Found sim.vcd in workspace_copy: {vcd_path}")

    # ── Bước 0: Kiểm tra xem là combinational hay sequential ─────────────────
    # Nếu combinational: bỏ qua toàn bộ VCD analysis, chỉ dùng log got/expected.
    # Lý do: VCD analysis cho combinational gây nhiễu (cảnh báo STUCK sai).
    is_sequential = False
    if os.path.exists(vcd_path):
        try:
            quick_sig_data = _parse_vcd_signals(vcd_path)
            is_sequential  = _detect_has_clock(quick_sig_data)
        except Exception:
            is_sequential = False
    
    if not is_sequential:
        print(f"[WAVEKIT] Combinational design detected — skipping VCD analysis. "
              f"Extracting got/expected from sim log only.")
        failed_signals = _extract_failed_signals_from_log(sim_log) if sim_log else []
        if not failed_signals:
            return "[WAVEKIT] Combinational design — no FAIL markers found in log."
        lines = ["=== COMBINATIONAL DESIGN: FAIL SUMMARY ===",
                 "(VCD waveform analysis skipped — focus on fixing logic directly)",
                 ""]
        for item in failed_signals:
            meta = []
            if item.get('cycle') is not None:
                meta.append(f"cycle={item['cycle']}")
            if item.get('time_ps') is not None:
                meta.append(f"time={item['time_ps']}ps")
            suffix = f" | {' '.join(meta)}" if meta else ""
            lines.append(f"  [FAIL #{item.get('index', '?')}] TC={item['tc']} | Signal='{item['signal']}'"
                         f"  got={item['got']}  expected={item['expected']}{suffix}")
        lines.append("\nFix: Compare the combinational logic expression for each failed signal "
                     "against the expected value. Check operator, operand order, and case opcode mapping.")
        return "\n".join(lines)

    # ── Bước 1: Kết nối wavekit-mcp server ở port 5001 ──────────────────────
    try:
        from fastmcp import Client
        import json
        wavekit_url = os.environ.get("WAVEKIT_MCP_URL", "http://127.0.0.1:5001/mcp")
        print(f"[WAVEKIT] Connecting to wavekit-mcp server at {wavekit_url}...")
        async with Client(wavekit_url, timeout=120.0) as wk_client:
            tools = await wk_client.list_tools()
            tool_names = [t.name for t in tools]
            print(f"[WAVEKIT] Available tools: {tool_names}")

            if "open_session" in tool_names and "run" in tool_names:
                # 1. Open Session
                print("[WAVEKIT] Opening wavekit-mcp session...")
                res = await wk_client.call_tool("open_session", {"description": f"Simulation analysis for {module_name}"})
                
                sid = None
                try:
                    if hasattr(res, "content") and res.content:
                        text = res.content[0].text.strip()
                        try:
                            parsed = json.loads(text)
                            if isinstance(parsed, dict):
                                sid = parsed.get("session_id") or parsed.get("sid") or text
                            else:
                                sid = text
                        except Exception:
                            sid = text
                    
                    if sid:
                        sid = re.sub(r'[\'"{}]', '', sid).strip()
                        print(f"[WAVEKIT] Successfully opened session: {sid}")
                        
                        # 2a. Get API docs VcdReader + Reader (Disabled to prevent log truncation)
                        # print("[WAVEKIT] Fetching VcdReader + Reader API docs...")
                        # if "get_api_docs" in tool_names:
                        #     for topic in ["VcdReader", "Reader", "Scope"]:
                        #         api_res = await wk_client.call_tool("get_api_docs", {"topic": topic})
                        #         if hasattr(api_res, "content") and api_res.content:
                        #             print(f"[WAVEKIT] {topic} API:\n{api_res.content[0].text[:600]}\n")

                        # 2c. Run analysis code in session
                        abs_vcd_path = os.path.abspath(vcd_path)
                        failed_signals = _extract_failed_signals_from_log(sim_log) if sim_log else []
                        
                        try:
                            local_sig_data = _parse_vcd_signals(abs_vcd_path)
                            local_sig_list = list(local_sig_data.keys())
                        except Exception:
                            local_sig_list = []
                        
                        code = """
vcd_path = %s
failed_signals = %s
all_signals = %s

print("=== Wavekit MCP Session Analysis ===")
try:
    r = VcdReader(vcd_path)
    print(f"Successfully loaded VCD file: {vcd_path}")
    print(f"Total signals provided: {len(all_signals)}")
    
    # Tự detect clock (tìm tín hiệu tên chứa 'clk' hoặc 'clock')
    clk_sig = None
    for s in all_signals:
        sname = s.split(".")[-1].lower()
        if sname in ("clk", "clock", "clk_i"):
            clk_sig = s
            break
    if not clk_sig:
        for s in all_signals:
            if "clk" in s.lower() or "clock" in s.lower():
                clk_sig = s
                break
    
    if clk_sig:
        print(f"Detected clock signal: {clk_sig}")
        if failed_signals:
            for fs in failed_signals:
                sig_name = fs["signal"]
                got      = fs["got"]
                expected = fs["expected"]
                print(f"\\n--- Analyzing Signal: {sig_name} ---")
                
                matched_sig = None
                for s in all_signals:
                    if s.endswith("." + sig_name) or s == sig_name:
                        matched_sig = s
                        break
                if not matched_sig:
                    if sig_name == "?":
                        print("  (Signal name not specified in log. Skipping specific waveform load.)")
                    else:
                        print(f"  Signal '{sig_name}' not found in VCD scope.")
                    continue
                
                try:
                    data = r.load_waveform(matched_sig, clk_sig)
                    print(f"  Signal '{sig_name}' (matched: '{matched_sig}'):")
                    print(f"  Got: {got} | Expected: {expected}")
                    if hasattr(data, 'value') and len(data.value) > 0:
                        print(f"  Total samples: {len(data.value)}")
                        recent_vals  = list(data.value)[-8:]
                        recent_times = list(data.time)[-8:] if hasattr(data, 'time') else list(range(len(recent_vals)))
                        print("  Last transitions:")
                        for t, v in zip(recent_times, recent_vals):
                            print(f"    t={t} -> value={v}")
                    else:
                        print(f"  No value data.")
                except Exception as sig_err:
                    print(f"  Error loading signal '{sig_name}': {sig_err}")
    else:
        print("INFO: No clock signal detected in VCD (combinational design). Skipping Wavekit analysis — will use local VCD fallback.")
    
    r.close()

except Exception as e:
    print(f"Error during wavekit processing: {e}")
""" % (repr(abs_vcd_path), repr(failed_signals), repr(local_sig_list))
                        print("[WAVEKIT] Executing Python analysis code on MCP...")
                        run_res = await wk_client.call_tool("run", {"session_id": sid, "code": code})
                        
                        mcp_result = ""
                        if hasattr(run_res, "content") and run_res.content:
                            mcp_result = run_res.content[0].text
                        
                        local_detail = analyze_vcd_locally(vcd_path, sim_log)
                        return f"{mcp_result}\n\n{local_detail}"
                finally:
                    if sid and "close_session" in tool_names:
                        print("[WAVEKIT] Closing session in finally block...")
                        try:
                            await wk_client.call_tool("close_session", {"session_id": sid})
                        except Exception as close_err:
                            print(f"[WAVEKIT] Failed to close session {sid}: {close_err}")
            else:
                print("[WAVEKIT] Required tools (open_session, run) not found on MCP server. Falling back to local analysis.")
    except Exception as e:
        print(f"[WAVEKIT] MCP connection/execution failed: {e}. Falling back to local VCD analysis.")

    # ── Bước 2: Phân tích VCD nội bộ (fallback sâu) ─────────────────────────
    print(f"[WAVEKIT] Running deep local VCD analysis on: {vcd_path}")
    return analyze_vcd_locally(vcd_path, sim_log)
