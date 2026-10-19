"""Daily spending limit (ADR-0007): a counter in a small JSON file, reset at midnight UTC. The limit itself comes from
the env (LLM_SERVER_DAILY_BUDGET_USD) until the game sets one (session.set_budget, 0.13.0): that one is kept in
`limit_path` and wins over the env from then on."""

import json
import threading
from datetime import UTC, datetime
from pathlib import Path


class DailyBudget:
    def __init__(self, path: Path, limit_usd: float | None, limit_path: Path | None = None):
        self.path = path
        self.limit_usd = limit_usd
        self.limit_path = limit_path
        self._lock = threading.Lock()
        if limit_path is not None:
            try:
                data = json.loads(limit_path.read_text(encoding="utf-8"))
                self.limit_usd = None if data.get("limit_usd") is None else float(data["limit_usd"])
            except (OSError, ValueError, TypeError):
                pass  # no limit set from the game yet: the env one stays

    def set_limit(self, limit_usd: float | None) -> None:
        """The limit from the game's settings; None = no limit. Kept across restarts when limit_path is set."""
        with self._lock:
            self.limit_usd = limit_usd
            if self.limit_path is not None:
                self.limit_path.parent.mkdir(parents=True, exist_ok=True)
                self.limit_path.write_text(json.dumps({"limit_usd": limit_usd}), encoding="utf-8")

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
