"""The model side of the session trace (v0.7.1)."""

import json

from llm_server.trace import TraceWriter


def test_a_trace_line_per_record_and_off_when_disabled(tmp_path):
    w = TraceWriter(tmp_path / "traces")
    w.write({"what": "turn", "turn_id": "t-1", "system": "…", "user": "Осматриваюсь"})
    w.write({"what": "summary", "kind": "location"})
    lines = w.path().read_text(encoding="utf-8").splitlines()
    assert [json.loads(x)["what"] for x in lines] == ["turn", "summary"]
    assert json.loads(lines[0])["user"] == "Осматриваюсь" and "ts" in json.loads(lines[0])
    off = TraceWriter(tmp_path / "off", enabled=False)
    off.write({"what": "turn"})
    assert not (tmp_path / "off").exists()


def test_messages_of_a_failed_serialization_do_not_break_a_turn():
    assert "error" in TraceWriter.messages(object())[0]
