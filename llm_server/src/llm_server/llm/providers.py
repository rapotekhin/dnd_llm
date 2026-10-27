"""Which OpenRouter providers serve a model (the author's wish after a slow day, v0.7.14.5): the `top` cheapest of a
typical turn that support tools and were up in the last 30 minutes. A request goes only to them, cheapest first, and
OpenRouter moves the ones slower than `min_tps` (p50, its own 5-minute stats) to the end. Its stats come from short
requests, so they missed a provider crawling at 14 tok/s on our 40k-token turns: every request of ours is timed too
(`observe`), and a provider slower than `min_turn_tps` in the last `SPEED_WINDOW` seconds leaves the three until
then — a slow cheap provider is skipped for a fast one of the three, never for an expensive one; when all three are
slow, all three stay. The price list is refreshed every `ttl` seconds; when OpenRouter cannot be reached the old list
stays (or none: plain price sorting).

v0.7.34.1: the price of a turn counts the cached share of the input at the cache price and is corrected by what the
provider really billed us (OpenInference charged 4.8× its list price, so the list alone sent us to the dearest one);
the bills are kept in `<data_dir>/provider_bills.json`. No provider is pinned first any more."""

import json
import logging
import os
import statistics
import time
from collections import deque
from contextvars import ContextVar
from pathlib import Path

import httpx

log = logging.getLogger("llm_server.providers")

ENDPOINTS_URL = "https://openrouter.ai/api/v1/models/{model}/endpoints"
TURN_INPUT_TOKENS = 20_000  # a typical turn of the master (traces of 2026-10: 21k in, 0.6–1k out; tools/provider_cost.py)
TURN_OUTPUT_TOKENS = 1_000
BILLS_KEPT = 30  # requests per provider the bill factor is taken from
MIN_BILLS = 3  # fewer say little: the list price stands
BILLS_DAYS = 7.0  # prices change (OpenInference's did within days): an old bill is forgotten and the provider tried again
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


def cache_share() -> float:
    """The cached share of a turn's input (traces of 2026-10: 69% at Relace)."""
    return min(1.0, max(0.0, float(os.environ.get("LLM_SERVER_CACHE_SHARE", "0.7") or 0)))


def _prices(e: dict) -> tuple[float, float, float | None]:
    p = e.get("pricing") or {}
    cr = p.get("input_cache_read")
    return float(p.get("prompt", 0)), float(p.get("completion", 0)), float(cr) if cr not in (None, "") else None


def request_cost(prices: tuple[float, float, float | None], input_tokens: float, cached: float, output_tokens: float) -> float:
    prompt, completion, cache_read = prices
    if cache_read is None:  # no cache price: the whole input at the full one
        cached = 0.0
    return (input_tokens - cached) * prompt + cached * (cache_read or 0.0) + output_tokens * completion


def cheapest(endpoints: list[dict], n: int, factors: dict[str, float] | None = None) -> list[str]:
    """Tags of the `n` cheapest endpoints for a typical turn that support tools and are up."""
    return [tag for tag, _ in ranked(endpoints, factors)[:n]]


def ranked(endpoints: list[dict], factors: dict[str, float] | None = None) -> list[tuple[str, str]]:
    """(tag, provider name) of the endpoints that support tools and are up, cheapest for a typical turn first;
    `factors` — billed ÷ list price by provider name."""
    ok = []
    for e in endpoints:
        params = e.get("supported_parameters") or []
        uptime = e.get("uptime_last_30m")
        if not all(p in params for p in NEEDS) or (uptime is not None and float(uptime) < MIN_UPTIME):
            continue
        try:
            cost = request_cost(_prices(e), TURN_INPUT_TOKENS, TURN_INPUT_TOKENS * cache_share(), TURN_OUTPUT_TOKENS)
        except (TypeError, ValueError):
            continue
        tag, name = str(e.get("tag") or ""), str(e.get("provider_name") or "")
        if tag:
            ok.append((cost * (factors or {}).get(name, 1.0), tag, name))
    ok.sort()
    return [(tag, name) for _, tag, name in ok]


def _distinct(order: list[tuple[str, str]]) -> list[tuple[str, str]]:
    """The cheapest tag of each provider: two tags of one provider are slow or down together."""
    seen: set[str] = set()
    return [(tag, name) for tag, name in order if not (name in seen or seen.add(name))]


class ProviderPicker:
    def __init__(self, ttl: float = 900.0):
        self.ttl = ttl
        self._ranked: dict[str, list[tuple[str, str]]] = {}
        self._endpoints: dict[str, list[dict]] = {}
        self._at: dict[str, float] = {}
        self._speed: dict[str, deque[tuple[float, float]]] = {}  # provider name → (unix time, tok/s)
        self._bills: dict[str, deque[tuple[float, float, float]]] = {}  # provider name → (unix time, billed, list price)
        self._bills_path: Path | None = None

    def bind(self, path: Path) -> None:
        """Keep the bills and speeds in `path` (and read the ones kept there): a restart must not forget a dear provider."""
        self._bills_path = path
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            bills, speed = (data.get("bills", {}), data.get("speed", {})) if "bills" in data else (data, {})
            self._bills = {n: deque((tuple(x) for x in v if len(x) == 3), maxlen=BILLS_KEPT) for n, v in bills.items()}  # type: ignore[misc]
            self._speed = {n: deque((tuple(x) for x in v if len(x) == 2), maxlen=BILLS_KEPT) for n, v in speed.items()}  # type: ignore[misc]
        except (OSError, ValueError, TypeError, AttributeError):
            self._bills, self._speed = {}, {}

    def _save(self) -> None:
        if self._bills_path is None:
            return
        try:
            self._bills_path.parent.mkdir(parents=True, exist_ok=True)
            self._bills_path.write_text(json.dumps({"bills": {n: list(v) for n, v in self._bills.items()},
                                                    "speed": {n: list(v) for n, v in self._speed.items()}}), encoding="utf-8")
        except OSError as exc:
            log.warning("cannot keep provider bills: %s", exc)

    def factors(self) -> dict[str, float]:
        """Billed ÷ list price of each provider with enough bills."""
        out = {}
        since = time.time() - BILLS_DAYS * 86400
        for name, bills in self._bills.items():
            recent = [(b, x) for at, b, x in bills if at >= since]
            listed = sum(x for _, x in recent)
            if len(recent) >= MIN_BILLS and listed > 0:
                out[name] = min(10.0, max(0.5, sum(b for b, _ in recent) / listed))
        return out

    def observe_bill(self, model: str, provider: str, input_tokens: int, cached: int, output_tokens: int, billed: float,
                     at: float | None = None) -> None:
        """What OpenRouter billed for one request against the provider's list price (`at` — when, for old bills)."""
        if not provider or billed <= 0:
            return
        # a name may have several tags (DeepInfra flex / fp8 / priority): the cheapest one is the yardstick
        prices = [_prices(e) for e in self._endpoints.get(model, []) if e.get("provider_name") == provider]
        if not prices:
            return
        listed = min(request_cost(p, input_tokens, cached, output_tokens) for p in prices)
        if listed <= 0:
            return
        before = self.factors().get(provider)
        self._bills.setdefault(provider, deque(maxlen=BILLS_KEPT)).append((time.time() if at is None else at, billed, listed))
        after = self.factors().get(provider)
        if after is not None and (before is None or abs(after - before) > 0.2):
            log.info("provider %s bills %.1f× its list price", provider, after)
            self._rank(model)
        self._save()

    def _rank(self, model: str) -> None:
        order = ranked(self._endpoints.get(model, []), self.factors())
        if order:
            if _distinct(order)[:top()] != _distinct(self._ranked.get(model, []))[:top()]:
                log.info("providers of %s: %s (min %s tok/s)", model, ", ".join(tag for tag, _ in _distinct(order)[:top()]), min_tps())
            self._ranked[model] = order

    def providers(self, model: str) -> list[str]:
        """The `top` cheapest, one tag per provider, without the ones observed slow (all of them when every one is slow)."""
        three = _distinct(self._ranked.get(model, []))[:top()]
        fast = [tag for tag, name in three if not self.slow(name)]
        return fast or [tag for tag, _ in three]

    def observe(self, provider: str, output_tokens: int, seconds: float, at: float | None = None) -> None:
        """One request of ours: who answered, how many tokens, how long (the prompt's reading included)."""
        if not provider or output_tokens < MIN_SAMPLE_TOKENS or seconds <= 0:
            return
        was_slow = self.slow(provider)
        self._speed.setdefault(provider, deque(maxlen=BILLS_KEPT)).append((time.time() if at is None else at, output_tokens / seconds))
        if self.slow(provider) and not was_slow:
            log.warning("provider %s is slow now (%.1f tok/s < %s): left out for %d min", provider,
                        output_tokens / seconds, min_turn_tps(), SPEED_WINDOW // 60)
        self._save()

    def _speeds(self, provider: str, window: float) -> list[float]:
        since = time.time() - window
        return [tps for at, tps in self._speed.get(provider, ()) if at >= since]

    def slow(self, provider: str) -> bool:
        recent = self._speeds(provider, SPEED_WINDOW)
        return bool(recent) and min_turn_tps() > 0 and statistics.median(recent) < min_turn_tps()

    def speed(self, provider: str) -> float:
        """The median tok/s of our requests to the provider in the last days; 0 — not measured."""
        recent = self._speeds(provider, BILLS_DAYS * 86400)
        return statistics.median(recent) if recent else 0.0

    def infos(self, model: str) -> list[dict]:
        """Every endpoint of the model the master can use, cheapest for our turn first: what the settings list shows."""
        factors, picked = self.factors(), set(self.providers(model))
        out = []
        for tag, name in self._ranked.get(model, []):
            e = next((x for x in self._endpoints.get(model, []) if x.get("tag") == tag), {})
            prompt, completion, cache_read = _prices(e)
            factor = factors.get(name, 1.0)
            turn = request_cost((prompt, completion, cache_read), TURN_INPUT_TOKENS, TURN_INPUT_TOKENS * cache_share(), TURN_OUTPUT_TOKENS)
            uptime = e.get("uptime_last_1d")
            out.append({"tag": tag, "name": name, "input_usd_per_mtok": prompt * 1e6, "output_usd_per_mtok": completion * 1e6,
                        "cache_usd_per_mtok": None if cache_read is None else cache_read * 1e6,
                        "usd_per_1000_turns": round(turn * factor * 1000, 4), "bill_factor": round(factor, 2),
                        "tokens_per_s": round(self.speed(name), 1), "uptime": None if uptime is None else round(float(uptime), 1),
                        "quantization": str(e.get("quantization") or ""), "picked": tag in picked})
        return out

    def knows(self, model: str, tag: str) -> bool:
        return any(t == tag for t, _ in self._ranked.get(model, []))

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
        self._endpoints[model] = endpoints
        self._rank(model)
        return self.providers(model)


PICKER = ProviderPicker()

# The provider the player pinned for this turn or summary (v0.7.20.5): set by turns.py, read by agents.settings_for.
PINNED: ContextVar[str | None] = ContextVar("pinned_provider", default=None)


def pinned_for(model_id: str, wish: str | None) -> str | None:
    """The player's provider when the model has it (another model was picked since — None): any endpoint of the model
    with tools (v0.7.34.1), or one of the config's short list before OpenRouter's list is loaded."""
    from ..config import PROVIDERS

    if not wish:
        return None
    return wish if PICKER.knows(model_id, wish) or any(tag == wish for tag, _ in PROVIDERS.get(model_id, ())) else None
