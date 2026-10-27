"""The cheapest OpenRouter provider for the master's model on our real token sizes.

Takes input / output tokens per turn from the backend traces (`llm_server/var/traces/*.jsonl`) or a golden report
(`build/evals/*.json`), the providers' prices from OpenRouter's public API, and ranks the providers by the cost of
1000 turns, the cached share of the input at the cache price. Marks the server's own picks (`llm/providers.py`: the
same ranking, corrected by our bills) and checks each request's bill in the traces against the list price.

    python tools/provider_cost.py                                  # DeepSeek, the traces of the last 7 days
    python tools/provider_cost.py --source golden                  # the newest golden report of the model
    python tools/provider_cost.py --since 2026-10-20 --cache 0.5   # own cached share instead of the estimate
    python tools/provider_cost.py --seed-bills                     # the traces' bills and speeds into the server's provider_bills.json
    python tools/provider_cost.py --model google/gemini-3.8-flash --md build/provider_cost.md
"""

from __future__ import annotations

import argparse
import datetime as dt
import glob
import json
import os
import statistics
import sys
import urllib.request
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "llm_server" / "src"))
from llm_server.llm.providers import BILLS_DAYS, ProviderPicker, request_cost, top  # noqa: E402

DEFAULT_MODEL = "deepseek/deepseek-v4.1-flash-1017"
TRACES = ROOT / "llm_server" / "var" / "traces"
BILLS = ROOT / "llm_server" / "var" / "provider_bills.json"
API = "https://openrouter.ai/api/v1/models/{model}/endpoints"


@dataclass
class Turn:
    input_tokens: int
    output_tokens: int
    billed: float  # what OpenRouter charged; 0 when unknown
    provider: str  # provider name, "" when unknown
    at: float = 0.0  # unix time; 0 when unknown
    seconds: float = 0.0


@dataclass
class Request:
    at: float  # unix time
    provider: str
    input_tokens: int
    cached: int
    output_tokens: int
    billed: float


@dataclass
class Endpoint:
    tag: str
    name: str
    prompt: float  # $ per token
    completion: float
    cache_read: float | None
    discount: float
    uptime_1d: float | None
    tools: bool
    structured: bool
    quantization: str

    @property
    def prices(self) -> tuple[float, float, float | None]:
        return self.prompt, self.completion, self.cache_read


def _trace_lines(since: dt.date):
    for path in sorted(TRACES.glob("*.jsonl")):
        try:
            if dt.date.fromisoformat(path.name[:10]) < since:
                continue
        except ValueError:
            continue
        with open(path, encoding="utf-8") as f:
            for line in f:
                try:
                    yield json.loads(line)
                except json.JSONDecodeError:
                    continue


def load_traces(model: str, since: dt.date) -> tuple[list[Turn], list[Request]]:
    turns, requests = [], []
    for d in _trace_lines(since):
        u = d.get("usage") or {}
        if d.get("model") != model or not u.get("input_tokens"):
            continue
        turns.append(Turn(u["input_tokens"], u.get("output_tokens", 0), u.get("cost_usd", 0.0), d.get("provider") or "",
                          float(d.get("ts") or 0) / 1000, float(d.get("seconds") or 0)))
        for m in d.get("messages") or []:
            det, mu = m.get("provider_details") or {}, m.get("usage") or {}
            if m.get("kind") != "response" or not det.get("cost") or not mu.get("input_tokens"):
                continue
            try:
                at = dt.datetime.fromisoformat(str(m.get("timestamp")).replace("Z", "+00:00")).timestamp()
            except ValueError:
                continue
            requests.append(Request(at, str(det.get("downstream_provider") or ""), mu["input_tokens"], mu.get("cache_read_tokens") or 0,
                                    mu.get("output_tokens") or 0, float(det["cost"])))
    return turns, requests


def load_golden(model: str, path: str | None) -> list[Turn]:
    if not path:
        found = sorted(glob.glob(str(ROOT / "build" / "evals" / f"*-{model.replace('/', '_')}.json")))
        if not found:
            sys.exit(f"no golden report for {model} in build/evals")
        path = found[-1]
    print(f"golden report: {os.path.relpath(path, ROOT)}")
    with open(path, encoding="utf-8") as f:
        rows = json.load(f)
    # reports before v0.7.34.1 do not say who answered: those runs went to Relace
    return [Turn(r["input_tokens"], r.get("output_tokens", 0), r.get("cost_usd", 0.0), r.get("provider") or "Relace")
            for r in rows if r.get("input_tokens")]


def fetch_endpoints(model: str) -> list[dict]:
    req = urllib.request.Request(API.format(model=model), headers={"User-Agent": "between-the-rolls/provider_cost"})
    for attempt in range(3):  # OpenRouter drops a TLS handshake now and then
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                return json.load(resp)["data"]["endpoints"]
        except OSError:
            if attempt == 2:
                raise
    return []


def parse(raw: list[dict]) -> list[Endpoint]:
    out = []
    for e in raw:
        p = e.get("pricing") or {}
        cr = p.get("input_cache_read")
        params = e.get("supported_parameters") or []
        out.append(Endpoint(
            tag=e.get("tag") or e.get("provider_name", "?"), name=e.get("provider_name", "?"),
            prompt=float(p.get("prompt") or 0), completion=float(p.get("completion") or 0),
            cache_read=float(cr) if cr not in (None, "") else None, discount=float(p.get("discount") or 0),
            uptime_1d=e.get("uptime_last_1d"), tools="tools" in params, structured="structured_outputs" in params,
            quantization=e.get("quantization") or ""))
    return out


def estimate_cache_share(turns: list[Turn], endpoints: list[Endpoint], provider: str) -> float | None:
    """The cached share of the input that explains what `provider` billed at its list prices."""
    prices = [e for e in endpoints if e.name.lower() == provider.lower() and e.cache_read is not None]
    if not prices:
        return None
    e = min(prices, key=lambda x: x.prompt)
    num = den = 0.0
    for t in turns:
        if t.provider.lower() != provider.lower() or not t.billed or e.prompt <= (e.cache_read or 0):
            continue
        num += t.input_tokens * e.prompt + t.output_tokens * e.completion - t.billed  # the saving the cache brought
        den += t.input_tokens * (e.prompt - (e.cache_read or 0))
    return min(1.0, max(0.0, num / den)) if den > 0 else None


def bill_check(requests: list[Request], endpoints: list[Endpoint]) -> list[str]:
    """Each request's bill against today's list price with its real cached tokens."""
    groups: dict[str, list[Request]] = {}
    for r in requests:
        groups.setdefault(r.provider, []).append(r)
    if not groups:
        return []
    out = ["", "## Bill check: each request against today's list price", "",
           "| Provider | Requests | Last | Cached share | Billed $ | List $ | Billed ÷ list |", "|---|---|---|---|---|---|---|"]
    for name, rs in sorted(groups.items(), key=lambda kv: -len(kv[1])):
        prices = [e.prices for e in endpoints if e.name == name]
        billed = sum(r.billed for r in rs)
        cached = sum(r.cached for r in rs) / max(1, sum(r.input_tokens for r in rs))
        last = dt.datetime.fromtimestamp(max(r.at for r in rs)).strftime("%Y-%m-%d")
        if not prices:
            out.append(f"| {name} | {len(rs)} | {last} | {cached:.0%} | {billed:.4f} | — | not listed now |")
            continue
        listed = sum(min(request_cost(p, r.input_tokens, r.cached, r.output_tokens) for p in prices) for r in rs)
        out.append(f"| {name} | {len(rs)} | {last} | {cached:.0%} | {billed:.4f} | {listed:.4f} | {billed / listed if listed else 0:.1f} |")
    out += ["", "Billed ÷ list far from 1: the list price is not what this provider charges us (changed since, or a hidden cost). "
            f"The server ranks a provider by its own bills of the last {BILLS_DAYS:g} days."]
    return out


def seed_bills(model: str, requests: list[Request], turns: list[Turn], raw: list[dict]) -> None:
    picker = ProviderPicker()
    picker.bind(BILLS)
    picker._endpoints[model] = raw
    newest = {name: max(at for at, _, _ in bills) for name, bills in picker._bills.items() if bills}
    added = 0
    for r in sorted(requests, key=lambda r: r.at):
        if r.at <= newest.get(r.provider, 0.0):  # kept already: a rerun adds nothing
            continue
        picker.observe_bill(model, r.provider, r.input_tokens, r.cached, r.output_tokens, r.billed, at=r.at)
        added += 1
    fastest = {name: max(at for at, _ in v) for name, v in picker._speed.items() if v}
    timed = 0
    for t in sorted(turns, key=lambda t: t.at):
        # a turn's whole time (several requests and the engine's answers): a lower bound of the provider's speed
        if t.provider and t.at > fastest.get(t.provider, 0.0) and t.seconds > 0:
            picker.observe(t.provider, t.output_tokens, t.seconds, at=t.at)
            timed += 1
    print(f"{timed} turn speeds added")
    print(f"{added} bills added to {os.path.relpath(BILLS, ROOT)}; factors now: "
          + (", ".join(f"{n} {f:.1f}×" for n, f in sorted(picker.factors().items())) or "none"))


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--model", default=DEFAULT_MODEL)
    ap.add_argument("--source", choices=("traces", "golden"), default="traces")
    ap.add_argument("--report", help="golden report path (default: the newest one of the model)")
    ap.add_argument("--since", type=dt.date.fromisoformat, default=dt.date.today() - dt.timedelta(days=7))
    ap.add_argument("--cache", type=float, help="cached share of the input, 0..1 (default: estimated from the bill)")
    ap.add_argument("--all", action="store_true", help="also endpoints without tool calls")
    ap.add_argument("--seed-bills", action="store_true", help=f"add the traces' bills of the last {BILLS_DAYS:g} days to the server's file")
    ap.add_argument("--md", help="also write the table as Markdown here")
    a = ap.parse_args()

    raw = fetch_endpoints(a.model)
    endpoints = parse(raw)
    if a.seed_bills:
        turns, requests = load_traces(a.model, dt.date.today() - dt.timedelta(days=int(BILLS_DAYS)))
        seed_bills(a.model, requests, turns, raw)
        return
    if a.source == "golden":
        turns, requests = load_golden(a.model, a.report), []
    else:
        turns, requests = load_traces(a.model, a.since)
    if not turns:
        sys.exit(f"no turns of {a.model} (source {a.source}, since {a.since})")

    picker = ProviderPicker()
    picker.bind(BILLS)
    picker._endpoints[a.model] = raw
    picker._rank(a.model)
    picked = picker.providers(a.model)[:top()]
    factors = picker.factors()

    used = statistics.mode([t.provider for t in turns if t.provider and t.billed] or [""])
    share = a.cache if a.cache is not None else estimate_cache_share(turns, endpoints, used)
    share_note = "given" if a.cache is not None else f"estimated from {used or '?'}'s bill"
    if share is None:
        share, share_note = 0.0, "unknown: no billed turns of a listed provider, counted as 0"
    inp = statistics.mean(t.input_tokens for t in turns)
    out = statistics.mean(t.output_tokens for t in turns)
    billed = [t.billed for t in turns if t.billed]

    def cost(e: Endpoint) -> float:
        return request_cost(e.prices, inp, inp * share, out)

    rows = sorted((e for e in endpoints if e.tools or a.all), key=cost)
    cheapest = cost(rows[0]) if rows else 0.0
    lines = [
        f"# Providers of `{a.model}` on our turns ({dt.date.today()})",
        "",
        f"- Turns: {len(turns)} ({a.source}{'' if a.source == 'golden' else f' since {a.since}'}); "
        f"input {inp:,.0f} / output {out:,.0f} tokens per turn on average, "
        f"median input {statistics.median(t.input_tokens for t in turns):,.0f}",
        f"- Cached share of the input: {share:.0%} ({share_note})",
        f"- Billed on average: ${statistics.mean(billed) * 1000:.3f} per 1000 turns" if billed else "- Billed: unknown",
        f"- The server's picks now (◀; cache share {os.environ.get('LLM_SERVER_CACHE_SHARE', '0.7')}, "
        f"{os.path.relpath(BILLS, ROOT)}): {', '.join(f'`{t}`' for t in picked) or 'none'}",
        "- Prices are OpenRouter's list prices per 1M tokens; `discount` is shown as OpenRouter gives it, not applied; "
        "«Bills» — billed ÷ list price of the server's last days, the ranking of the server multiplies by it",
        "",
        "| # | Provider | Tag | $ / 1000 turns | × cheapest | Bills | In | Out | Cache read | Discount | Uptime 1d | Quant | Struct. out |",
        "|---|---|---|---|---|---|---|---|---|---|---|---|---|",
    ]
    for i, e in enumerate(rows, 1):
        c = cost(e)
        cr = f"{e.cache_read * 1e6:.4f}" if e.cache_read is not None else "—"
        up = f"{e.uptime_1d:.1f}%" if e.uptime_1d is not None else "—"
        f = f"{factors[e.name]:.1f}×" if e.name in factors else "—"
        lines.append(
            f"| {i} | {e.name}{' ◀' if e.tag in picked else ''} | `{e.tag}` | {c * 1000:.3f} | {c / cheapest if cheapest else 0:.1f} | {f} | "
            f"{e.prompt * 1e6:.4f} | {e.completion * 1e6:.4f} | {cr} | {e.discount:g} | {up} | {e.quantization} | "
            f"{'yes' if e.structured else 'no'} |")
    lines += bill_check(requests, endpoints)
    text = "\n".join(lines)
    print(text)
    if a.md:
        Path(a.md).parent.mkdir(parents=True, exist_ok=True)
        Path(a.md).write_text(text + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
