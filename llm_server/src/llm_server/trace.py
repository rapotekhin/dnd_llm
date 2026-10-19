"""The model side of a play session's trace (v0.7.1): one JSON line per turn or summary in
<data_dir>/traces/<date>.jsonl — the system and user prompts, every model message with its tool calls and the
engine's answers, the typed output, usage and timing; a failed turn with its error. The client writes its own trace
(game/autoload/trace.gd); tools/trace_report.py joins them by turn_id and time. Off with LLM_SERVER_TRACE=0.
Never holds keys: they live only in the settings, never in messages."""

import json
import logging
import time
from datetime import datetime
from pathlib import Path
from typing import Any

from pydantic_ai.messages import ModelMessagesTypeAdapter

log = logging.getLogger("llm_server.trace")


class TraceWriter:
    def __init__(self, folder: Path, enabled: bool = True):
        self.folder = folder
        self.enabled = enabled

    def path(self) -> Path:
        return self.folder / f"{datetime.now():%Y-%m-%d}.jsonl"

    def write(self, record: dict[str, Any]) -> None:
        if not self.enabled:
            return
        try:
            self.folder.mkdir(parents=True, exist_ok=True)
            line = json.dumps({"ts": int(time.time() * 1000), **record}, ensure_ascii=False, default=str)
            with self.path().open("a", encoding="utf-8") as f:
                f.write(line + "\n")
        except OSError as exc:  # a trace never breaks a turn
            log.warning("trace not written: %s", exc)

    @staticmethod
    def messages(result: Any) -> list[Any]:
        """The run's model messages as JSON (prompts, tool calls and returns, the final output)."""
        try:
            return ModelMessagesTypeAdapter.dump_python(result.all_messages(), mode="json")
        except Exception as exc:  # noqa: BLE001 — a trace never breaks a turn
            return [{"error": f"messages not serialized: {exc}"}]
