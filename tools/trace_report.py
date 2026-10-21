"""A readable report of a play session from its traces (v0.7.1).

    python tools/trace_report.py                     # the newest trace of the author's games (not the agent profile)
    python tools/trace_report.py path/to/trace.jsonl # a given one
    python tools/trace_report.py --list              # the client traces found

The client trace (game/autoload/trace.gd, <profile>/traces/*.jsonl in Godot's user dir) holds clicks, chat, state
digests and every JSON-RPC message; the backend trace (llm_server/var/traces/<date>.jsonl) holds the model side —
prompts, tool calls, output — and is joined by turn_id within the session's time span. The report goes to
build/traces/<name>.md: summary, the graph of rooms (mermaid), the timeline step by step, every master turn with
its tool calls, and the anomalies (rejected effects, failed turns, money or things in the narration without an
effect, slow turns).
"""

import argparse
import json
import os
import re
import sys
from collections import Counter, defaultdict
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BACKEND_TRACES = ROOT / "llm_server" / "var" / "traces"
OUT = ROOT / "build" / "traces"
USER_DIR = Path(os.environ.get("APPDATA", Path.home())) / "Godot" / "app_userdata" / "Between the Rolls"
# money or a thing changing hands in the narration — checked against the effects of the turn
MONEY = re.compile(r"(ты (платишь|отсчитываешь|выкладываешь|отдаёшь|кладёшь) [^.]{0,30}(монет|медяк|серебр|золот)|"
                   r"(сгребает|забирает|прячет|берёт|смахивает) [^.]{0,30}(монет|медяк|серебр|золот|плату)|"
                   r"(протягивает|отсчитывает|бросает) тебе [^.]{0,30}(монет|медяк|серебр|золот|кошел))", re.I)
REPEAT = 3  # the same click this many times in a row
PAUSE_MS = 180_000  # no click or input this long
COIN_WINDOW_MS = 15_000  # coins moved by the engine this long before a turn belong to it (a paid option)
TAKE = re.compile(r"(ты (берёшь|забираешь|прячешь|кладёшь в (сумку|мешок|карман))|протягивает тебе|вручает тебе|отдаёт тебе)", re.I)


def load(path: Path) -> list[dict]:
    out = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line:
            try:
                out.append(json.loads(line))
            except json.JSONDecodeError:
                pass
    return out


def client_traces() -> list[Path]:
    return sorted(USER_DIR.rglob("traces/*.jsonl"), key=lambda p: p.stat().st_mtime)


def is_agent(path: Path) -> bool:
    """Traces of the scripted playtests (profile «agent»), not of the author's own games."""
    return "profiles" in path.parts and "agent" in path.parts


def when(ts: int) -> str:
    return datetime.fromtimestamp(ts / 1000).strftime("%H:%M:%S")


def short(text: str, n: int = 220) -> str:
    text = " ".join(str(text).split())
    return text if len(text) <= n else text[: n - 1] + "…"


def backend_turns(start: int, end: int) -> dict[str, list[dict]]:
    by_turn: dict[str, list[dict]] = defaultdict(list)
    if not BACKEND_TRACES.exists():
        return by_turn
    for f in sorted(BACKEND_TRACES.glob("*.jsonl")):
        for r in load(f):
            if start - 60_000 <= int(r.get("ts", 0)) <= end + 120_000 and r.get("what") == "turn":
                by_turn[str(r.get("turn_id"))].append(r)
    return by_turn


def tool_calls(messages: list[dict]) -> list[str]:
    calls = []
    returns = {}
    for m in messages:
        for p in m.get("parts", []):
            if p.get("part_kind") == "tool-return":
                returns[p.get("tool_call_id")] = p.get("content")
    for m in messages:
        for p in m.get("parts", []):
            if p.get("part_kind") == "tool-call" and p.get("tool_name") != "final_result":
                args = p.get("args")
                if isinstance(args, str):
                    try:
                        args = json.loads(args)
                    except json.JSONDecodeError:
                        pass
                calls.append(f"`{p.get('tool_name')}` {short(json.dumps(args, ensure_ascii=False), 160)} → {short(str(returns.get(p.get('tool_call_id'), '')), 160)}")
    return calls


def report(path: Path) -> Path:
    ev = load(path)
    if not ev:
        sys.exit(f"empty trace: {path}")
    start, end = int(ev[0]["ts"]), int(ev[-1]["ts"])
    model = backend_turns(start, end)
    states = [e["state"] for e in ev if e.get("ev") == "state"]
    # when the engine moved coins (a paid option, a deal): money in the narration around then is no anomaly
    coin_moves, gold = [], None
    for e in ev:
        if e.get("ev") == "state":
            g = e["state"].get("gold_cp")
            if gold is not None and g != gold:
                coin_moves.append(int(e["ts"]))
            gold = g
    session = next((e for e in ev if e.get("ev") == "session"), {})

    # turns from the protocol: requests, results, engine calls in between
    turns: dict[str, dict] = {}
    pending_engine: dict[str, dict] = {}
    for e in ev:
        if e.get("ev") != "rpc" or not isinstance(e.get("msg"), dict):
            continue
        m = e["msg"]
        method = m.get("method")
        if e["dir"] == ">" and method == "turn.request":
            p = m.get("params", {})
            turns[p.get("turn_id")] = {"ts": e["ts"], "kind": p.get("kind"), "mode": p.get("mode"), "input": p.get("input", ""),
                                      "room": e.get("room"), "rpc_id": m.get("id"), "checks": [], "validate": [], "result": None, "error": None}
        elif e["dir"] == "<" and method in ("engine.check", "engine.validate", "engine.lookup", "engine.find_items"):
            pending_engine[str(m.get("id"))] = {"method": method, "params": m.get("params", {})}
        elif e["dir"] == ">" and "result" in m and str(m.get("id")) in pending_engine:
            call = pending_engine.pop(str(m.get("id")))
            t = turns.get(call["params"].get("turn_id"))
            if t is None:
                continue
            if call["method"] == "engine.check":
                r = m["result"]
                t["checks"].append(f"{call['params'].get('skill') or call['params'].get('save')} {r.get('total')} vs {r.get('dc')} {'✓' if r.get('success') else '✗'}"
                                   + (" (повтор)" if r.get("blocked") else "") + (f" — {short(r.get('note', ''), 120)}" if r.get("note") else ""))
            elif call["method"] == "engine.validate":
                r = m["result"]
                kind = call["params"].get("effect", {}).get("kind")
                t["validate"].append((kind, r.get("accepted"), r.get("summary") or r.get("reason", "")))
        elif e["dir"] == "<" and ("result" in m or "error" in m):
            for t in turns.values():
                if t["rpc_id"] == m.get("id") and t["result"] is None and t["error"] is None:
                    if "result" in m:
                        t["result"] = m["result"]
                    else:
                        t["error"] = m["error"]
                    t["done_ts"] = e["ts"]

    # summary
    cost = sum(float((t["result"] or {}).get("usage", {}).get("cost_usd", 0) or 0) for t in turns.values())
    tokens = sum(int((t["result"] or {}).get("usage", {}).get("input_tokens", 0) or 0) + int((t["result"] or {}).get("usage", {}).get("output_tokens", 0) or 0) for t in turns.values())
    checks = [c for t in turns.values() for c in t["checks"]]
    rejected = [(tid, k, why) for tid, t in turns.items() for k, ok, why in t["validate"] if not ok]
    clicks = Counter(e.get("text") or e.get("node") for e in ev if e.get("ev") == "click")
    first, last = (states[0] if states else {}), (states[-1] if states else {})
    lines = [f"# Трейс сессии: {session.get('character', {}).get('name', '?')} — {path.stem}", "",
             f"- Файл: `{path}`",
             f"- Время: {when(start)} → {when(end)} ({(end - start) / 60000:.0f} мин), версия {session.get('version', '?')}, мир {session.get('world', '?')}, сид {session.get('seed', '?')}",
             f"- Герой: {session.get('character', {})}",
             f"- Уровень {first.get('level')} → {last.get('level')}, опыт {first.get('xp')} → {last.get('xp')}, монеты {first.get('gold_cp')} → {last.get('gold_cp')} мм, HP {last.get('hp')}/{last.get('max_hp')}, день {last.get('day')}",
             f"- Ходов мастера: {len(turns)} (ошибок {sum(1 for t in turns.values() if t['error'])}), токенов {tokens}, цена ${cost:.4f}",
             f"- Проверок: {len(checks)} (успехов {sum(1 for c in checks if '✓' in c)}), эффектов принято {sum(1 for t in turns.values() for _, ok, _ in t['validate'] if ok)}, отклонено {len(rejected)}",
             f"- Нажатия: {', '.join(f'{k} ×{v}' for k, v in clicks.most_common(15))}", ""]

    # the graph of rooms
    edges: Counter = Counter()
    rooms: list[str] = []
    for s in states:
        if not rooms or rooms[-1] != s.get("room"):
            if rooms:
                edges[(rooms[-1], s.get("room"))] += 1
            rooms.append(s.get("room"))
    if edges:
        lines += ["## Маршрут", "", "```mermaid", "flowchart LR"]
        for (a, b), n in edges.items():
            lines.append(f"  {a.replace('-', '_')}[{a}] -->|{n}| {b.replace('-', '_')}[{b}]")
        lines += ["```", "", "Порядок: " + " → ".join(rooms), ""]

    # anomalies
    anomalies = [f"- `{tid}` отклонено `{k}`: {short(why, 200)}" for tid, k, why in rejected]
    for tid, t in turns.items():
        res = t["result"] or {}
        kinds = {k for k, ok, _ in t["validate"] if ok}
        text = res.get("narration", "")
        if t["error"]:
            anomalies.append(f"- `{tid}` ход не удался: {short(json.dumps(t['error'], ensure_ascii=False), 200)}")
        paid = any(t["ts"] - COIN_WINDOW_MS <= m <= t.get("done_ts", t["ts"]) for m in coin_moves)
        if text and MONEY.search(text) and not paid and not kinds & {"coins", "give_item", "take_item"} and t["kind"] not in ("deal", "theft", "quest"):
            anomalies.append(f"- `{tid}` в тексте деньги, а эффекта монет нет: «{short(text, 160)}»")
        if text and TAKE.search(text) and not kinds & {"give_item", "take_prop", "coins"} and t["kind"] not in ("deal", "theft", "quest"):
            anomalies.append(f"- `{tid}` в тексте передача вещи без эффекта: «{short(text, 160)}»")
        if t.get("done_ts") and t["done_ts"] - t["ts"] > 25_000:
            anomalies.append(f"- `{tid}` долгий ход: {(t['done_ts'] - t['ts']) / 1000:.0f} с")
    toasts = Counter(e.get("text") for e in ev if e.get("ev") == "toast")
    anomalies += [f"- подсказка игроку «{k}» ×{v}" for k, v in toasts.most_common(10)]
    # the same button again and again (it did not do what the player expected) and long pauses (stuck or away)
    acts = [e for e in ev if e.get("ev") in ("click", "input")]
    run, prev = 0, None
    for i, e in enumerate(acts + [{}]):
        key = (e.get("ev"), e.get("text") or e.get("node"), e.get("room"))
        if key == prev:
            run += 1
            continue
        if prev is not None and prev[0] == "click" and run >= REPEAT:
            anomalies.append(f"- `{when(acts[i - 1]['ts'])}` «{short(prev[1], 60)}» нажато {run} раз подряд ({prev[2]})")
        run, prev = 1, key
    for a, b in zip(acts, acts[1:]):
        if b["ts"] - a["ts"] > PAUSE_MS:
            anomalies.append(f"- `{when(a['ts'])}` пауза {(b['ts'] - a['ts']) / 60000:.0f} мин после «{short(a.get('text') or a.get('node'), 60)}» ({a.get('room')})")
    lines += ["## Что настораживает", ""] + (anomalies or ["- ничего"]) + [""]

    # v0.7.16, pillar 6: what the players wanted and the engine has no concepts for — what to add first
    missing = [(tid, t) for tid, t in turns.items() if (t["result"] or {}).get("missing_concept")]
    lines += ["## Недостающие понятия", ""] + ([f"- `{tid}` {t['room']}: **{short(t['result']['missing_concept'], 160)}** — ввод «{short(t['input'], 160)}»"
                                               for tid, t in missing] or ["- нет"]) + [""]

    # the timeline
    lines += ["## Ход игры", ""]
    for e in ev:
        kind = e.get("ev")
        head = f"`{when(e['ts'])}` {e.get('day', '')}д {e.get('clock', '')} · {e.get('room', '')}"
        if kind == "click":
            lines.append(f"- {head} — **нажато** «{short(e.get('text') or e.get('node'), 80)}» ({e.get('screen', '')})")
        elif kind == "input":
            lines.append(f"- {head} — **ввод** «{short(e.get('text'), 200)}»")
        elif kind == "nav":
            lines.append(f"- {head} — экран {e.get('screen')}")
        elif kind == "combat":
            lines.append(f"- {head} — бой: " + " · ".join(short(x, 120) for x in e.get("lines", [])))
        elif kind == "chat":
            c = e.get("entry", {})
            k = c.get("kind")
            if k == "dm":
                lines.append(f"  - мастер: {short(c.get('text', ''), 400)}")
            elif k == "npc":
                lines.append(f"  - {c.get('name', 'NPC')}: {short(c.get('text', ''), 400)}")
            elif k == "effect":
                lines.append(f"  - движок: {short(' · '.join(c.get('lines', [])), 300)}")
            elif k == "check":
                lines.append(f"  - бросок: {c.get('skill') or c.get('save')} {c.get('total')} против {c.get('dc')} {'✓' if c.get('success') else '✗'}")
            elif k == "system":
                lines.append(f"  - система: {c.get('key')}")
        elif kind == "session":
            lines.append(f"- {head} — сессия: {e.get('what')}")
    lines.append("")

    # the turns of the master with the model side
    lines += ["## Ходы мастера", ""]
    for tid, t in turns.items():
        res = t["result"] or {}
        lines.append(f"### `{tid}` {t['kind']} · {t['mode']} · {t['room']}")
        if t["input"]:
            lines.append(f"- ввод: {short(t['input'], 300)}")
        for c in t["checks"]:
            lines.append(f"- проверка: {c}")
        for k, ok, why in t["validate"]:
            lines.append(f"- эффект `{k}`: {'принят' if ok else 'отклонён'} — {short(why, 200)}")
        if res:
            u = res.get("usage", {})
            lines.append(f"- итог: {short(res.get('narration', ''), 500)}")
            lines.append(f"- варианты: {res.get('options', [])} · цены {[int(c) for c in res.get('option_costs', [])]} · режим {res.get('next_mode')} · "
                         f"{int(u.get('input_tokens', 0) or 0)}+{int(u.get('output_tokens', 0) or 0)} ток., ${float(u.get('cost_usd', 0) or 0):.4f}")
        if t["error"]:
            lines.append(f"- ошибка: {short(json.dumps(t['error'], ensure_ascii=False), 300)}")
        for r in model.get(tid, [])[-1:]:
            calls = tool_calls(r.get("messages", []))
            if calls:
                lines.append("- вызовы модели: " + "; ".join(calls))
            if r.get("output", {}).get("changes"):
                lines.append(f"- изменения по словам мастера: {r['output']['changes']}")
        lines.append("")

    OUT.mkdir(parents=True, exist_ok=True)
    out = OUT / f"{path.stem}.md"
    out.write_text("\n".join(lines), encoding="utf-8")
    return out


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    ap = argparse.ArgumentParser()
    ap.add_argument("trace", nargs="?")
    ap.add_argument("--list", action="store_true")
    opts = ap.parse_args()
    found = client_traces()
    if opts.list:
        for p in found:
            print(p, f"{p.stat().st_size // 1024} КБ", "(агент)" if is_agent(p) else "")
        return 0
    mine = [p for p in found if not is_agent(p)]
    path = Path(opts.trace) if opts.trace else (mine[-1] if mine else None)
    if path is None:
        print(f"no traces of the author's games under {USER_DIR} (--list shows the agent's too)")
        return 2
    print(report(path))
    return 0


if __name__ == "__main__":
    sys.exit(main())
