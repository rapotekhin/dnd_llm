"""Daily spending limit (ADR-0007): a counter in a small JSON file, reset at midnight UTC."""

import json
import threading
from datetime import UTC, datetime
from pathlib import Path


class DailyBudget:
    def __init__(self, path: Path, limit_usd: float | None):
        self.path = path
        self.limit_usd = limit_usd
        self._lock = threading.Lock()

    @staticmethod
    def _today() -> str:
        return datetime.now(UTC).date().isoformat()

    def spent_today(self) -> float:
        with self._lock:
            return self._read()

    def left(self) -> float | None:
        if self.limit_usd is None:
            return None
        return max(0.0, self.limit_usd - self.spent_today())

    def exhausted(self) -> bool:
        return self.limit_usd is not None and self.spent_today() >= self.limit_usd

    def add(self, usd: float) -> None:
        if usd <= 0:
            return
        with self._lock:
            spent = self._read() + usd
            self.path.parent.mkdir(parents=True, exist_ok=True)
            tmp = self.path.with_suffix(".tmp")
            tmp.write_text(json.dumps({"date": self._today(), "spent_usd": round(spent, 6)}), encoding="utf-8")
            tmp.replace(self.path)

    def _read(self) -> float:
        try:
            data = json.loads(self.path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return 0.0
        return float(data.get("spent_usd", 0.0)) if data.get("date") == self._today() else 0.0
