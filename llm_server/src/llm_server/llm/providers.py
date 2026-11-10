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
the bills are kept in `<data_dir>/provider_bills.json`. No provider is pinned first any more.

2026-11-01, the author's game: our order did not reach OpenRouter. `only` is a set there and `sort: price` is its own
ranking, so OpenInference served 126 requests of 174 while Morph stood first here and is 10-19% cheaper on the same game.
The request now carries `order`, and a provider is priced on our mean request, the cached share it really gave us
included (`Call`, kept with the bills); one provider serving in a row also keeps its cache warm."""

import json
import logging
import os
import statistics
import time
from collections import deque
from contextvars import ContextVar
from pathlib import Path
from typing import NamedTuple

import httpx

log = logging.getLogger("llm_server.providers")

ENDPOINTS_URL = "https://openrouter.ai/api/v1/models/{model}/endpoints"


class Call(NamedTuple):
    """One request of ours, the means: a request's cost is linear in them, so the mean one prices the whole game."""

    input_tokens: float
    cached_share: float
    output_tokens: float


# The author's game of 2026-10-31…11-01, 304 requests: full turns 13k in / 550 out at 47% cached, short ones 3.5k / 220,
# summaries 2.5k / 570 with no cache seen in their bills.
OUR_CALL = Call(8_900, 0.4, 430)
TURN_CALLS = 1.5  # requests of a turn: the settings list prices a turn, the ranking a request
CALLS_KEPT = 500  # requests of a model the mean is taken from
MIN_CALLS = 10  # fewer say little: `OUR_CALL` and the common cached share stand
BILLS_KEPT = 30  # requests per provider the bill factor is taken from
MIN_BILLS = 3  # fewer say little: the list price stands
BILLS_DAYS = 7.0  # prices change (OpenInference's did within days): an old bill is forgotten and the provider tried again
NEEDS = ("tools", "tool_choice")
MIN_UPTIME = 90.0
SPEED_WINDOW = 1800.0  # seconds an observed speed counts
MIN_SAMPLE_TOKENS = 150  # shorter answers say little about the speed
SLOW_SAMPLES = 2  # one slow answer may be a cold start, and leaving the first provider loses its cache


def top() -> int:
    return int(os.environ.get("LLM_SERVER_PROVIDER_TOP", "3") or 3)


def min_tps() -> float:
    return float(os.environ.get("LLM_SERVER_MIN_TPS", "30") or 0)


def min_turn_tps() -> float:
    return float(os.environ.get("LLM_SERVER_MIN_TURN_TPS", "20") or 0)


def cache_share() -> float | None:
    """A fixed cached share of the input in place of the measured one; None — measure."""
    raw = os.environ.get("LLM_SERVER_CACHE_SHARE", "").strip()
    return min(1.0, max(0.0, float(raw))) if raw else None


def _prices(e: dict) -> tuple[float, float, float | None]:
    p = e.get("pricing") or {}
    cr = p.get("input_cache_read")
    return float(p.get("prompt", 0)), float(p.get("completion", 0)), float(cr) if cr not in (None, "") else None


def request_cost(prices: tuple[float, float, float | None], input_tokens: float, cached: float, output_tokens: float) -> float:
    prompt, completion, cache_read = prices
    if cache_read is None:  # no cache price: the whole input at the full one
        cached = 0.0
    return (input_tokens - cached) * prompt + cached * (cache_read or 0.0) + output_tokens * completion


def call_cost(prices: tuple[float, float, float | None], call: Call, share: float | None = None) -> float:
    """The list price of our mean request; `share` — the provider's own cached share."""
    forced = cache_share()
    share = forced if forced is not None else call.cached_share if share is None else share
    return request_cost(prices, call.input_tokens, call.input_tokens * share, call.output_tokens)


def cheapest(endpoints: list[dict], n: int, factors: dict[str, float] | None = None) -> list[str]:
    """Tags of the `n` cheapest endpoints for our request that support tools and are up."""
    return [tag for tag, _ in ranked(endpoints, factors)[:n]]


def ranked(endpoints: list[dict], factors: dict[str, float] | None = None, call: Call = OUR_CALL,
           shares: dict[str, float] | None = None) -> list[tuple[str, str]]:
    """(tag, provider name) of the endpoints that support tools and are up, cheapest for `call` first;
    `factors` — billed ÷ list price by provider name, `shares` — the cached share each provider gave us."""
    ok = []
    for e in endpoints:
        params = e.get("supported_parameters") or []
        uptime = e.get("uptime_last_30m")
        if not all(p in params for p in NEEDS) or (uptime is not None and float(uptime) < MIN_UPTIME):
            continue
        tag, name = str(e.get("tag") or ""), str(e.get("provider_name") or "")
        try:
            cost = call_cost(_prices(e), call, (shares or {}).get(name))
        except (TypeError, ValueError):
            continue
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
        self._calls: dict[str, deque[tuple[float, str, int, int, int]]] = {}  # model → (unix time, provider, input, cached, output)
        self._bills_path: Path | None = None

    def bind(self, path: Path) -> None:
        """Keep the bills and speeds in `path` (and read the ones kept there): a restart must not forget a dear provider."""
        self._bills_path = path
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            bills, speed = (data.get("bills", {}), data.get("speed", {})) if "bills" in data else (data, {})
            self._bills = {n: deque((tuple(x) for x in v if len(x) == 3), maxlen=BILLS_KEPT) for n, v in bills.items()}  # type: ignore[misc]
            self._speed = {n: deque((tuple(x) for x in v if len(x) == 2), maxlen=BILLS_KEPT) for n, v in speed.items()}  # type: ignore[misc]
            self._calls = {m: deque((tuple(x) for x in v if len(x) == 5), maxlen=CALLS_KEPT) for m, v in data.get("calls", {}).items()}  # type: ignore[misc]
        except (OSError, ValueError, TypeError, AttributeError):
            self._bills, self._speed, self._calls = {}, {}, {}

    def _save(self) -> None:
        if self._bills_path is None:
            return
        try:
            self._bills_path.parent.mkdir(parents=True, exist_ok=True)
            self._bills_path.write_text(json.dumps({"bills": {n: list(v) for n, v in self._bills.items()},
                                                    "speed": {n: list(v) for n, v in self._speed.items()},
                                                    "calls": {m: list(v) for m, v in self._calls.items()}}), encoding="utf-8")
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

    def _recent_calls(self, model: str, provider: str = "") -> list[tuple[float, str, int, int, int]]:
        since = time.time() - BILLS_DAYS * 86400
        return [c for c in self._calls.get(model, ()) if c[0] >= since and (not provider or c[1] == provider)]

    @staticmethod
    def _share(calls: list[tuple[float, str, int, int, int]]) -> float:
        return sum(c[3] for c in calls) / max(1, sum(c[2] for c in calls))

    def call(self, model: str) -> Call:
        """Our mean request to the model lately: the prompts change, the numbers follow them."""
        calls = self._recent_calls(model)
        if len(calls) < MIN_CALLS:
            return OUR_CALL
        return Call(sum(c[2] for c in calls) / len(calls), self._share(calls), sum(c[4] for c in calls) / len(calls))

    def shares(self, model: str) -> dict[str, float]:
        """The cached share each provider really gave us: a cheap cache is worth nothing where it misses."""
        out = {}
        for name in {c[1] for c in self._recent_calls(model)}:
            calls = self._recent_calls(model, name)
            if len(calls) >= MIN_CALLS:
                out[name] = self._share(calls)
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
        when = time.time() if at is None else at
        self._bills.setdefault(provider, deque(maxlen=BILLS_KEPT)).append((when, billed, listed))
        self._calls.setdefault(model, deque(maxlen=CALLS_KEPT)).append((when, provider, input_tokens, cached, output_tokens))
        after = self.factors().get(provider)
        if after is not None and (before is None or abs(after - before) > 0.2):
            log.info("provider %s bills %.1f× its list price", provider, after)
            self._rank(model)
        self._save()

    def _rank(self, model: str) -> None:
        order = ranked(self._endpoints.get(model, []), self.factors(), self.call(model), self.shares(model))
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
        return len(recent) >= SLOW_SAMPLES and min_turn_tps() > 0 and statistics.median(recent) < min_turn_tps()

    def speed(self, provider: str) -> float:
        """The median tok/s of our requests to the provider in the last days; 0 — not measured."""
        recent = self._speeds(provider, BILLS_DAYS * 86400)
        return statistics.median(recent) if recent else 0.0

    def infos(self, model: str) -> list[dict]:
        """Every endpoint of the model the master can use, cheapest for our turn first: what the settings list shows."""
        factors, picked = self.factors(), set(self.providers(model))
        call, shares = self.call(model), self.shares(model)
        out = []
        for tag, name in self._ranked.get(model, []):
            e = next((x for x in self._endpoints.get(model, []) if x.get("tag") == tag), {})
            prompt, completion, cache_read = _prices(e)
            factor = factors.get(name, 1.0)
            turn = call_cost((prompt, completion, cache_read), call, shares.get(name)) * TURN_CALLS
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
    with tools (v0.7.34.1), or one of the config's short list before OpenRouter's list is loaded; `auto` — the picker."""
    from ..config import AUTO_PROVIDER, PROVIDERS

    if not wish:
        return None
    if wish == AUTO_PROVIDER:
        return AUTO_PROVIDER
    return wish if PICKER.knows(model_id, wish) or any(tag == wish for tag, _ in PROVIDERS.get(model_id, ())) else None


def default_pin(model_id: str) -> str | None:
    """The provider a request of `model_id` goes to when nobody pinned one (v0.8.4.42.25): config.DEFAULT_PROVIDER or
    `LLM_SERVER_PROVIDER`, if the model has it; None — the picker (`auto`, or a model without it)."""
    import os

    from ..config import AUTO_PROVIDER, DEFAULT_PROVIDER

    wish = os.environ.get("LLM_SERVER_PROVIDER", DEFAULT_PROVIDER).strip() or DEFAULT_PROVIDER
    pin = pinned_for(model_id, wish)
    return None if pin == AUTO_PROVIDER else pin

