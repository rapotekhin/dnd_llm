"""tools/trace_report.py on a synthetic client trace (v0.7.1)."""

import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("trace_report", ROOT / "tools" / "trace_report.py")
trace_report = importlib.util.module_from_spec(spec)
spec.loader.exec_module(trace_report)


def test_report_has_summary_route_anomalies_and_turns(tmp_path, monkeypatch):
    monkeypatch.setattr(trace_report, "OUT", tmp_path / "out")
    monkeypatch.setattr(trace_report, "BACKEND_TRACES", tmp_path / "none")
    ts = 1_700_000_000_000
    ev = [
        {"ts": ts, "ev": "session", "what": "start", "character": {"name": "Айра"}, "version": "0.7.1"},
        {"ts": ts, "ev": "state", "state": {"room": "a", "level": 1, "xp": 0, "gold_cp": 100, "hp": 10, "max_hp": 10, "day": 1}},
        {"ts": ts + 1, "ev": "click", "text": "→ B", "screen": "SidePanel", "room": "a"},
        {"ts": ts + 2, "ev": "rpc", "dir": ">", "msg": {"id": 1, "method": "turn.request", "params": {"turn_id": "t-1", "kind": "enter", "mode": "exploration", "input": ""}}},
        {"ts": ts + 3, "ev": "rpc", "dir": "<", "msg": {"id": "b1", "method": "engine.validate", "params": {"turn_id": "t-1", "effect": {"kind": "move"}}}},
        {"ts": ts + 3, "ev": "rpc", "dir": ">", "msg": {"id": "b1", "result": {"accepted": False, "reason": "нет выхода"}}},
        {"ts": ts + 4, "ev": "rpc", "dir": "<", "msg": {"id": 1, "result": {"narration": "Горм сгребает монеты со стойки.", "usage": {"cost_usd": 0.001}}}},
        {"ts": ts + 5, "ev": "state", "state": {"room": "b", "level": 1, "xp": 0, "gold_cp": 100, "hp": 10, "max_hp": 10, "day": 1}},
    ]
    src = tmp_path / "trace.jsonl"
    src.write_text("\n".join(json.dumps(e, ensure_ascii=False) for e in ev), encoding="utf-8")
    text = trace_report.report(src).read_text(encoding="utf-8")
    assert "Айра" in text and "Ходов мастера: 1" in text
    assert "a[a] -->|1| b[b]" in text
    assert "отклонено `move`" in text and "деньги, а эффекта монет нет" in text
    assert "### `t-1` enter" in text
