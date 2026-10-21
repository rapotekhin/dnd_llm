"""Which OpenRouter providers serve a model (the author's wish after a slow day, v0.7.14.4): the `top` cheapest of a
typical turn that support tools and were up in the last 30 minutes. A request goes only to them, cheapest first, and
OpenRouter moves the ones slower than `min_tps` (p50, its own 5-minute stats) to the end — a slow cheap provider is
skipped for a fast one of the three, never for an expensive one. The list is refreshed every `ttl` seconds; when
OpenRouter cannot be reached the old list stays (or none: plain price sorting)."""

import logging
import os
import time

import httpx

log = logging.getLogger("llm_server.providers")

ENDPOINTS_URL = "https://openrouter.ai/api/v1/models/{model}/endpoints"
TURN_INPUT_TOKENS = 20_000  # a typical turn of the master (traces: 14–45k in, 1–2k out)
TURN_OUTPUT_TOKENS = 1_500
NEEDS = ("tools", "tool_choice")
MIN_UPTIME = 90.0


def top() -> int:
    return int(os.environ.get("LLM_SERVER_PROVIDER_TOP", "3") or 3)


def min_tps() -> float:
    return float(os.environ.get("LLM_SERVER_MIN_TPS", "30") or 0)


def cheapest(endpoints: list[dict], n: int) -> list[str]:
    """Tags of the `n` cheapest endpoints for a typical turn that support tools and are up."""
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
            ok.append((cost, tag))
    ok.sort()
    return [tag for _, tag in ok[:n]]


class ProviderPicker:
    def __init__(self, ttl: float = 900.0):
        self.ttl = ttl
        self._lists: dict[str, list[str]] = {}
        self._at: dict[str, float] = {}

    def providers(self, model: str) -> list[str]:
        return self._lists.get(model, [])

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
        picked = cheapest(endpoints, top())
        if picked:
            if picked != self._lists.get(model):
                log.info("providers of %s: %s (min %s tok/s)", model, ", ".join(picked), min_tps())
            self._lists[model] = picked
        return self.providers(model)


PICKER = ProviderPicker()
