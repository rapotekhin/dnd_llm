"""Which OpenRouter providers serve a model (the author's wish after a slow day, v0.7.14.5): the `top` cheapest of a
typical turn that support tools and were up in the last 30 minutes. A request goes only to them, cheapest first, and
OpenRouter moves the ones slower than `min_tps` (p50, its own 5-minute stats) to the end. Its stats come from short
requests, so they missed a provider crawling at 14 tok/s on our 40k-token turns: every request of ours is timed too
(`observe`), and a provider slower than `min_turn_tps` in the last `SPEED_WINDOW` seconds leaves the three until
then — a slow cheap provider is skipped for a fast one of the three, never for an expensive one; when all three are
slow, all three stay. The price list is refreshed every `ttl` seconds; when OpenRouter cannot be reached the old list
stays (or none: plain price sorting)."""

import logging
import os
import statistics
import time
from collections import deque
from contextvars import ContextVar

import httpx

log = logging.getLogger("llm_server.providers")

ENDPOINTS_URL = "https://openrouter.ai/api/v1/models/{model}/endpoints"
TURN_INPUT_TOKENS = 20_000  # a typical turn of the master (traces: 14–45k in, 1–2k out)
TURN_OUTPUT_TOKENS = 1_500
NEEDS = ("tools", "tool_choice")
MIN_UPTIME = 90.0
SPEED_WINDOW = 1800.0  # seconds an observed speed counts
MIN_SAMPLE_TOKENS = 150  # shorter answers say little about the speed


def top() -> int:
    return int(os.environ.get("LLM_SERVER_PROVIDER_TOP", "3") or 3)


def min_tps() -> float:
    return float(os.environ.get("LLM_SERVER_MIN_TPS", "30") or 0)


def min_turn_tps() -> float:
    return float(os.environ.get("LLM_SERVER_MIN_TURN_TPS", "20") or 0)


def cheapest(endpoints: list[dict], n: int) -> list[str]:
    """Tags of the `n` cheapest endpoints for a typical turn that support tools and are up."""
    return [tag for tag, _ in ranked(endpoints)[:n]]


def ranked(endpoints: list[dict]) -> list[tuple[str, str]]:
    """(tag, provider name) of the endpoints that support tools and are up, cheapest for a typical turn first."""
    ok = []
    for e in endpoints:
        params = e.get("supported_parameters") or []
        uptime = e.get("uptime_last_30m")
        if not all(p in params for p in NEEDS) or (uptime is not None and float(uptime) < MIN_UPTIME):
            continue
        price = e.get("pricing") or {}
        try:
            cost = float(price.get("prompt", 0)) * TURN_INPUT_TOKENS + float(price.get("completion", 0)) * TURN_OUTPUT_TOKENS
        except (TypeError, ValueError):
            continue
        tag = str(e.get("tag") or "")
        if tag:
            ok.append((cost, tag, str(e.get("provider_name") or "")))
    ok.sort()
    return [(tag, name) for _, tag, name in ok]


class ProviderPicker:
    def __init__(self, ttl: float = 900.0):
        self.ttl = ttl
        self._ranked: dict[str, list[tuple[str, str]]] = {}
        self._at: dict[str, float] = {}
        self._speed: dict[str, deque[tuple[float, float]]] = {}

    def providers(self, model: str) -> list[str]:
        """The `top` cheapest, without the ones observed slow (all of them when every one is slow)."""
        three = self._ranked.get(model, [])[:top()]
        fast = [tag for tag, name in three if not self.slow(name)]
        return fast or [tag for tag, _ in three]

    def observe(self, provider: str, output_tokens: int, seconds: float) -> None:
        """One request of ours: who answered, how many tokens, how long (the prompt's reading included)."""
        if not provider or output_tokens < MIN_SAMPLE_TOKENS or seconds <= 0:
            return
        was_slow = self.slow(provider)
        self._speed.setdefault(provider, deque(maxlen=8)).append((time.monotonic(), output_tokens / seconds))
        if self.slow(provider) and not was_slow:
            log.warning("provider %s is slow now (%.1f tok/s < %s): left out for %d min", provider,
                        output_tokens / seconds, min_turn_tps(), SPEED_WINDOW // 60)

    def slow(self, provider: str) -> bool:
        now = time.monotonic()
        recent = [tps for at, tps in self._speed.get(provider, ()) if now - at < SPEED_WINDOW]
        return bool(recent) and min_turn_tps() > 0 and statistics.median(recent) < min_turn_tps()

    async def refresh(self, model: str, client: httpx.AsyncClient | None = None) -> list[str]:
        """The current list, fetched again when older than `ttl`."""
        if time.monotonic() - self._at.get(model, -1e9) < self.ttl:
            return self.providers(model)
        self._at[model] = time.monotonic()  # one try per ttl, even a failed one
        try:
            if client is not None:  # the caller's client stays open
                resp = await client.get(ENDPOINTS_URL.format(model=model))
            else:
                async with httpx.AsyncClient(timeout=10) as c:
                    resp = await c.get(ENDPOINTS_URL.format(model=model))
            resp.raise_for_status()
            endpoints = resp.json()["data"]["endpoints"]
        except (httpx.HTTPError, KeyError, ValueError, TypeError) as exc:
            log.warning("cannot load OpenRouter providers of %s: %s", model, exc)
            return self.providers(model)
        order = ranked(endpoints)
        if order:
            if order[:top()] != self._ranked.get(model, [])[:top()]:
                log.info("providers of %s: %s (min %s tok/s)", model, ", ".join(tag for tag, _ in order[:top()]), min_tps())
            self._ranked[model] = order
        return self.providers(model)


PICKER = ProviderPicker()

# The provider the player pinned for this turn or summary (v0.7.20.5): set by turns.py, read by agents.settings_for.
PINNED: ContextVar[str | None] = ContextVar("pinned_provider", default=None)


def pinned_for(model_id: str, wish: str | None) -> str | None:
    """The player's provider when it is one of the model's list (another model was picked since — None)."""
    from ..config import PROVIDERS

    return wish if wish and any(tag == wish for tag, _ in PROVIDERS.get(model_id, ())) else None
