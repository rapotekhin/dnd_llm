"""Golden LLM scenarios runner (docs/tech/golden-scenarios.md): `uv run python -m llm_server.golden`.

Each scenario is one turn of the real agent against a mock engine whose answers come from the scenario, so
the result depends only on the model and the prompts. Hard checks (`expect`) are automatic, soft criteria
(`rubric`) go to an LLM judge. Real OpenRouter calls: run by hand, never in CI. Report → build/evals/.

Scenarios use format v1 (M0, before protocol 0.2.0); `to_turn_params` adapts them. Expectations the protocol
cannot express yet (combat mode, contests, DM style / content settings) are reported as unsupported.
"""

from __future__ import annotations

import argparse
import asyncio
import copy
import json
import re
import sys
import time
from dataclasses import dataclass, field
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

import yaml
from pydantic import BaseModel, Field
from pydantic_ai import Agent
from pydantic_ai.exceptions import UnexpectedModelBehavior
from pydantic_ai.usage import RunUsage
from pydantic_ai.messages import ToolCallPart
from pydantic_ai.models import Model

from . import REPO_ROOT
from .llm.catalog import REQUEST_COSTS
from .llm.providers import PICKER, PINNED
from .agents import RETRY_MAX_TOKENS, TurnContext, build_turn_agent, is_entry, settings_for, system_prompt_for, turn_user_prompt
from .protocol import TurnRequestParams

SCENARIOS = REPO_ROOT / "evals" / "golden" / "scenarios.yaml"
OUT_DIR = REPO_ROOT / "build" / "evals"

ATTITUDE = {"hostile": -3, "unfriendly": -1, "indifferent": 0, "neutral": 0, "friendly": 1, "helpful": 2}
SEVERITY_ALIASES = {"setback": "unpleasant"}  # format v1 used the DMG word «setback»
HISTORY_ROLES = {"ИГРОК": "player", "МАСТЕР": "dm", "NPC": "npc"}


# --- loading and adapting ------------------------------------------------------------


def deep_merge(base: Any, over: Any) -> Any:
    if isinstance(base, dict) and isinstance(over, dict):
        out = copy.deepcopy(base)
        for k, v in over.items():
            out[k] = deep_merge(out.get(k), v) if k in out else copy.deepcopy(v)
        return out
    return copy.deepcopy(over)


def load_scenarios(path: Path = SCENARIOS) -> list[dict[str, Any]]:
    data = yaml.safe_load(path.read_text(encoding="utf-8"))
    out = []
    for sc in data["scenarios"]:
        base = data["bases"].get(sc.get("extends", ""), {})
        merged = deep_merge(base, {k: v for k, v in sc.items() if k != "extends"})
        out.append(merged)
    return out


def unsupported(sc: dict[str, Any]) -> str:
    """Why protocol 0.2.0 cannot run this scenario fairly, or ""."""
    return ""


def to_turn_params(sc: dict[str, Any]) -> TurnRequestParams:
    snap = sc.get("snapshot", {})
    scene = snap.get("scene", {})
    room = scene.get("room", {})
    loc = scene.get("location", {})
    description = room.get("description", "")
    visible = scene.get("items_visible", [])
    if visible:
        names = [f"{i['name']}" + (f" ({i['contents_cp']} мм внутри)" if "contents_cp" in i else "") for i in visible]
        description += " На виду: " + "; ".join(names) + "."
    npcs = [{"npc_id": n["id"], "name": n["name"], "role": n.get("role", ""), "trader": bool(n.get("trader", False)),
             "attitude": ATTITUDE.get(str(n.get("attitude", "indifferent")), 0),
             **{k: n[k] for k in ("race", "speaks", "understands_hero", "tie", "memory", "services", "deal", "secrets", "refuses", "eager", "follows", "under", "body") if k in n}} for n in scene.get("npcs", [])]
    ch = snap.get("character", {})
    hp = ch.get("hp", {})
    history = []
    for line in snap.get("history", []):
        prefix, _, text = str(line).partition(":")
        role = HISTORY_ROLES.get(prefix.strip(), "dm")
        history.append({"role": role, "text": text.strip() if role != "dm" or prefix.strip() == "МАСТЕР" else str(line)})
    summaries = {}
    if snap.get("summaries", {}).get("location"):
        summaries["location"] = snap["summaries"]["location"]
    for npc_id, text in snap.get("summaries", {}).get("npcs", {}).items():
        summaries[f"dialogue:{npc_id}"] = text
    mode = sc.get("mode", "exploration")
    settings = sc.get("settings", {})
    world = None
    if settings:
        content = settings.get("content", {})
        world = {"dm_style": settings.get("dm_style", "classic"), "violence": content.get("violence", "medium"),
                 "lines": content.get("lines", []), "veils": content.get("veils", []), "wishes": content.get("wishes", [])}
    params = {
        "turn_id": "t-1",
        "mode": mode,
        "kind": sc.get("kind", "action"),
        "input": sc.get("input") or "",
        "pinned_check": sc.get("pinned_check", ""),  # v0.7.38
        "npc_id": npcs[0]["npc_id"] if mode in ("social", "trade") and npcs else None,
        "snapshot": {
            "world": world,
            "scene": {
                "location_name": loc.get("name", ""),
                "room_id": room.get("id", ""), "room_name": room.get("name", ""), "room_description": description,
                "exits": [{"room_id": e["id"], "name": e["name"], "door": e.get("door", "")} for e in scene.get("exits", [])],
                "npcs": npcs, "hooks": [h["text"] if isinstance(h, dict) else str(h) for h in scene.get("hooks", [])],
                "time_of_day": scene.get("time", ""),
                "props": scene.get("props", []),  # already in the protocol shape (SceneProp, 0.11.0)
                "creatures": scene.get("creatures", []),  # the foes a fight left (0.45.0)
                "sneaking": bool(scene.get("sneaking", False)),
                "furnish": bool(scene.get("furnish", False)),
                "closed_exits": scene.get("closed_exits", []),  # (0.14.0)
                "notes": scene.get("notes", []),
                "chronicle": scene.get("chronicle", []),
                "reputation": scene.get("reputation", ""),
                "open_edges": scene.get("open_edges", []),
            },
            "character": {
                "name": ch.get("name", ""), "gender": ch.get("gender", "other"), "class_name": ch.get("class", ""),
                "level": ch.get("level", 1), "hp": hp.get("current", 10), "max_hp": hp.get("max", 10),
                "ac": ch.get("ac", 10), "conditions": ch.get("conditions", []), "skills": ch.get("skills", {}),
                "saves": ch.get("saves", {}), "features": ch.get("features", []), "gold_cp": ch.get("gold_cp", 1000),
                **{k: ch[k] for k in ("cantrips", "spells", "spell_slots", "spell_save_dc", "resources", "equipped", "inventory",
                                      "background", "background_feature", "languages", "tools", "attuned", "reward_left_cp", "bags", "development", "goal", "craft", "jobs", "property", "bank", "shop", "study", "bonds", "family", "underworld", "office",
                                      "race", "body") if k in ch},
            },
            "history": history,
            "summaries": summaries,
            "limits": {k: v for k, v in snap.get("limits", {}).items() if k in ("max_checks", "max_effects")},
            "trade": snap.get("trade"),  # already in the protocol shape (TradeInfo)
            "combat": snap.get("combat"),  # already in the protocol shape (CombatInfo)
            "quests": snap.get("quests", []),  # already in the protocol shape (QuestInfo; offered_by 0.12.0)
            "crimes": snap.get("crimes"),  # already in the protocol shape (HeroCrimes, 0.19.0)
        },
    }
    return TurnRequestParams.model_validate(params)


# --- mock engine -----------------------------------------------------------------------


@dataclass
class MockEngine:
    """Answers engine.* from the scenario's `engine` block and records every call."""

    engine: dict[str, Any]
    scene: dict[str, Any] = field(default_factory=dict)
    calls: list[tuple[str, dict[str, Any]]] = field(default_factory=list)
    _n: int = 0

    def _scene_edges(self) -> list[dict[str, Any]]:
        """The hero's own room's open edges first, as the engine's reach lists them; "[N] text (terrain, …)" in the scene."""
        room = self.scene.get("room", {})
        out = []
        for line in self.scene.get("open_edges", []):
            m = re.match(r"\[(\d+)\]\s*(.*?)(?:\s*\(([^)]*)\))?$", str(line))
            if m:
                out.append({"room_id": room.get("id", ""), "room": room.get("name", ""), "edge": int(m[1]), "text": m[2],
                            "terrain": [x.strip() for x in (m[3] or "").split(",") if x.strip()]})
        return out

    async def call_engine(self, method: str, params: BaseModel) -> Any:
        p = params.model_dump(mode="json", exclude_none=True)
        self.calls.append((method, p))
        self._n += 1
        if method == "engine.check":
            c = self.engine.get("check", {})
            d20 = list(c.get("d20") or [])
            nat = c.get("nat") or (d20[0] if d20 else 0)
            return {"check_id": f"c-{self._n}", "rolls": d20 or [max(1, int(c.get("total", 10)) - int(c.get("bonus", 0)))],
                    "bonus": c.get("bonus", 0), "total": c.get("total", 10), "dc": c.get("dc", 15),
                    "success": bool(c.get("success")), "nat": nat or 0, "blocked": bool(c.get("blocked")),
                    "note": c.get("note", ""), "revealed": list(c.get("revealed") or []), "rolled_as": c.get("rolled_as", "")}
        if method == "engine.validate":
            rule = self.engine.get("validate", "accept")
            kind = p["effect"]["kind"]
            summary = kind
            if isinstance(rule, list):
                for r in rule:
                    if r.get("kind") == kind and r.get("status") == "reject":
                        return {"accepted": False, "reason": r.get("reason", "отклонено")}
                    if r.get("kind") == kind and r.get("summary"):  # what the engine says back (a save rolled, v0.7.8)
                        summary = r["summary"]
            return {"accepted": True, "effect_id": f"e-{self._n}", "summary": summary,
                    "item_id": "gen_item" if p["effect"].get("item") else None}
        if method == "engine.lookup":
            data = self.engine.get("lookup", {}).get(p["id"])
            return {"found": data is not None, "data": data or {}}
        if method == "engine.find_places":  # v0.7.20.1
            return {"places": [{"room_id": p.get("id", ""), "name": p.get("name", ""), "location": p.get("location", "")}
                               for p in self.engine.get("find_places", [])],
                    "edges": self._scene_edges() + list(self.engine.get("find_edges", []))}  # 0.48.0: the open edges of the known world
        if method == "engine.find_quests":  # v0.7.21
            return {"quests": [{"quest_id": q.get("id", ""), "title": q.get("title", ""), "giver": q.get("giver", ""),
                                "status": q.get("status", "offered")} for q in self.engine.get("find_quests", [])]}
        if method == "engine.find_npcs":  # v0.7.20
            return {"npcs": [{"npc_id": n.get("id", ""), "name": n.get("name", ""), "role": n.get("role", ""), "location": n.get("location", "")}
                             for n in self.engine.get("find_npcs", [])]}
        if method == "engine.find_items":
            items = [{"item_id": i.get("id", ""), "name": i.get("name", ""), "rarity": i.get("rarity", "common"),
                      "item_type": i.get("item_type", "weapon"), "properties": i.get("properties", [])}
                     for i in self.engine.get("find_items", [])]
            return {"items": items}
        raise ValueError(method)

    def effects(self) -> list[dict[str, Any]]:
        return [p["effect"] for m, p in self.calls if m == "engine.validate"]

    def checks(self) -> list[dict[str, Any]]:
        return [p for m, p in self.calls if m == "engine.check"]


# --- hard checks -------------------------------------------------------------------------


def sentences(text: str) -> int:
    return len([s for s in re.split(r"[.!?…]+", text) if s.strip()])


def _path(x: Any, dotted: str) -> Any:
    for k in dotted.split("."):
        x = x.get(k) if isinstance(x, dict) else None
    return x


def check_expect(expect: dict[str, Any], out: dict[str, Any], engine: MockEngine, tools: list[str]) -> list[str]:
    """Failed hard checks as human-readable strings ([] = all passed)."""
    fails: list[str] = []
    checks = engine.checks()
    effects = engine.effects()
    kinds = [e["kind"] for e in effects]
    narration = out.get("narration", "")

    c = expect.get("check", {})
    if "required" in c and bool(checks) != c["required"]:
        fails.append(f"check.required={c['required']}, проверок: {len(checks)}")
    if checks and c.get("skill_in") and not any(ch.get("skill") in c["skill_in"] or ch.get("save") in c["skill_in"] for ch in checks):
        fails.append(f"навык {[ch.get('skill') or ch.get('save') for ch in checks]} не из {c['skill_in']}")
    if checks and c.get("dc_tier_in") and not any(ch["dc_tier"] in c["dc_tier_in"] for ch in checks):
        fails.append(f"сложность {[ch['dc_tier'] for ch in checks]} не из {c['dc_tier_in']}")
    if checks and c.get("contest_npc") and not any(ch.get("target_id") == c["contest_npc"] for ch in checks):
        # v0.7.15.1: the engine contests a social check with the NPC of its target_id (SocialRules)
        fails.append(f"проверка не против {c['contest_npc']}: target_id {[ch.get('target_id') for ch in checks]}")
    if checks and c.get("tool_in") and not any(ch.get("tool") in c["tool_in"] for ch in checks):
        fails.append(f"инструмент {[ch.get('tool') for ch in checks]} не из {c['tool_in']}")
    if "max_checks" in expect and len(checks) > expect["max_checks"]:
        fails.append(f"проверок {len(checks)} > {expect['max_checks']}")

    e = expect.get("effects", {})
    if e.get("required_kinds_any") and not set(kinds) & set(e["required_kinds_any"]):
        fails.append(f"нет эффекта из {e['required_kinds_any']} (были {kinds})")
    if e.get("required_kinds_all") and set(e["required_kinds_all"]) - set(kinds):
        fails.append(f"нет эффектов {sorted(set(e['required_kinds_all']) - set(kinds))} (были {kinds})")
    if e.get("forbidden_kinds") and set(kinds) & set(e["forbidden_kinds"]):
        fails.append(f"запрещённые эффекты {sorted(set(kinds) & set(e['forbidden_kinds']))}")
    if "max_count" in e and len(effects) > e["max_count"]:
        fails.append(f"эффектов {len(effects)} > {e['max_count']}")
    if "coins_max" in e:
        gained = sum(x.get("delta_cp", 0) for x in effects if x["kind"] == "coins" and x.get("delta_cp", 0) > 0)
        if gained > e["coins_max"]:
            fails.append(f"монет {gained} > {e['coins_max']}")
    if e.get("damage_severity_in"):
        allowed = {SEVERITY_ALIASES.get(s, s) for s in e["damage_severity_in"]}
        bad = [x.get("severity") for x in effects if x["kind"] == "damage" and x.get("severity") not in allowed]
        if bad:
            fails.append(f"тяжесть урона {bad} не из {sorted(allowed)}")
    for f in e.get("forbidden_fields", []):
        if any(f in x for x in effects):
            fails.append(f"поле {f} в эффекте")
    for f in e.get("required_fields", []):  # v0.7.34.5: a dotted path with a true value, e.g. quest_item.from_giver
        if not any(_path(x, f) for x in effects):
            fails.append(f"нет поля {f} в эффектах")
    if e.get("condition_save"):  # v0.7.8: a condition on the hero by the rules — a reason, a save with a tag, or the hero's own cause
        mine = [x for x in effects if x["kind"] == "condition" and x.get("on", True) and not x.get("target_id")]
        for x in mine:
            if not str(x.get("reason") or "").strip():
                fails.append(f"состояние {x.get('condition')} без причины")
            if e["condition_save"] == "save" and not x.get("save"):
                fails.append(f"состояние {x.get('condition')} без спасброска")
            if e["condition_save"] == "save_or_player" and not x.get("save") and x.get("cause") != "player":
                fails.append(f"состояние {x.get('condition')} без спасброска и без cause=player")
            if x.get("save") and e.get("condition_tag_in") and x.get("tag") not in e["condition_tag_in"]:
                fails.append(f"тег {x.get('tag')} не из {e['condition_tag_in']}")
            if e.get("condition_in") and x.get("condition") not in e["condition_in"]:
                fails.append(f"состояние {x.get('condition')} не из {e['condition_in']}")

    if "missing_concept" in expect and bool(out.get("missing_concept")) != expect["missing_concept"]:  # v0.7.16
        fails.append(f"missing_concept={out.get('missing_concept')!r}, ожидалось {'заполнено' if expect['missing_concept'] else 'пусто'}")
    if "next_mode" in expect:
        want = expect["next_mode"]
        got = out.get("next_mode")
        if want is None and got is not None:
            fails.append(f"лишняя смена режима {got}")
        elif isinstance(want, dict):
            if got is None or got.get("mode") != want.get("mode") or ("npc_id" in want and got.get("npc_id") != want["npc_id"]):
                fails.append(f"режим {got}, ожидался {want}")

    n = expect.get("narration", {})
    for pat in n.get("must_match", []):
        if not re.search(pat, narration, re.IGNORECASE):
            fails.append(f"в тексте нет /{pat}/")
    for pat in n.get("must_not_match", []):
        m = re.search(pat, narration, re.IGNORECASE | re.MULTILINE)
        if m:
            fails.append(f"в тексте есть /{pat}/: «{m.group(0)}»")
    if "max_sentences" in n and sentences(narration) > n["max_sentences"]:
        fails.append(f"предложений {sentences(narration)} > {n['max_sentences']}")

    o = expect.get("options", {})
    count = len(out.get("options", []))
    if "min" in o and count < o["min"]:
        fails.append(f"вариантов {count} < {o['min']}")
    if "max" in o and count > o["max"]:
        fails.append(f"вариантов {count} > {o['max']}")
    if "checked_min" in o:  # v0.7.22.28: options the master tagged «skill:tier»
        from .turns import _option_check
        tags = out.get("option_checks", [])
        checked = sum(1 for i in range(count) if _option_check(tags, i) is not None)
        if checked < o["checked_min"]:
            fails.append(f"вариантов с проверкой {checked} < {o['checked_min']} ({tags})")
    for pattern in o.get("must_not_match", []):
        for opt in out.get("options", []):
            if re.search(pattern, opt, re.IGNORECASE):
                fails.append(f"вариант «{opt}» похож на /{pattern}/")

    created = any(x["kind"] == "give_item" and x.get("item") for x in effects)
    for t in expect.get("tools_required", []):
        if t not in tools:
            fails.append(f"не вызван {t}")
    for t in expect.get("tools_forbidden", []):
        if t in tools or (t == "create_item" and created):
            fails.append(f"вызван запрещённый {t}")
    return fails


# --- judge ---------------------------------------------------------------------------------


class Verdict(BaseModel):
    criterion: str
    passed: bool
    comment: str = Field(description="Одно предложение: почему.")


class JudgeOutput(BaseModel):
    verdicts: list[Verdict]


JUDGE_INSTRUCTIONS = (
    "Ты строгий редактор настольной ролевой игры D&D 5e. Тебе дают ситуацию, ход мастера (текст, проверки, эффекты) "
    "и критерии. Оцени каждый критерий отдельно: passed=true, только если ход явно ему соответствует. По-русски."
)


def _tagged(out: dict[str, Any]) -> list[str]:
    """The options as the player sees them: «[stealth:medium] Прокрасться…» when the master tagged a check (v0.7.22.28)."""
    tags = out.get("option_checks", [])
    return [f"[{tags[i]}] {o}" if i < len(tags) and tags[i] else o for i, o in enumerate(out.get("options", []))]


async def judge(model: Model, sc: dict[str, Any], out: dict[str, Any], engine: MockEngine) -> list[Verdict]:
    agent = Agent(model, output_type=JudgeOutput, instructions=JUDGE_INSTRUCTIONS, model_settings=settings_for(model, {"temperature": 0}))
    prompt = (
        f"Ситуация: {sc.get('title')}\nВвод игрока: {sc.get('input') or '(нет: ' + sc.get('kind', '') + ')'}\n"
        f"Ответ движка на проверку (если была): {json.dumps(sc.get('engine', {}).get('check', {}), ensure_ascii=False)}\n\n"
        f"Текст мастера:\n{out.get('narration', '')}\n\nВарианты: {_tagged(out)}\n"
        f"Проверки: {json.dumps(engine.checks(), ensure_ascii=False)}\nЭффекты: {json.dumps(engine.effects(), ensure_ascii=False)}\n"
        f"Смена режима: {out.get('next_mode')}\nНедостающее понятие (заметка автору): {out.get('missing_concept')}\n\nКритерии:\n" + "\n".join(f"- {r}" for r in sc.get("rubric", []))
    )
    result = await agent.run(prompt)
    return result.output.verdicts


# --- running ---------------------------------------------------------------------------------


@dataclass
class Outcome:
    id: str
    category: str
    status: str  # pass | fail | error | unsupported
    fails: list[str] = field(default_factory=list)
    verdicts: list[dict[str, Any]] = field(default_factory=list)
    narration: str = ""
    options: list[str] = field(default_factory=list)
    checks: list[dict[str, Any]] = field(default_factory=list)
    effects: list[dict[str, Any]] = field(default_factory=list)
    next_mode: dict[str, Any] | None = None
    tools: list[str] = field(default_factory=list)
    seconds: float = 0.0
    input_tokens: int = 0
    output_tokens: int = 0
    cost_usd: float = 0.0
    note: str = ""
    route: str = ""  # --route: the router's way (v0.7.20.4)
    provider: str = ""  # who answered the last request (v0.7.34.1, for tools/provider_cost.py)


class _ShortResult:
    """A short answer of the router's way in the shape the runner reads."""

    def __init__(self, out: Any, usage: RunUsage) -> None:
        self.output, self.usage = out, usage

    def all_messages(self) -> list[Any]:
        return []


async def run_one(sc: dict[str, Any], model: Model, model_id: str, judge_model: Model | None,
                  prices: dict[str, tuple[float, float]], route: bool = False) -> Outcome:
    o = Outcome(id=sc["id"], category=sc.get("category", ""), status="pass")
    reason = unsupported(sc)
    if reason:
        o.status, o.note = "unsupported", reason
        return o
    params = to_turn_params(sc)
    engine = MockEngine(sc.get("engine", {}), sc.get("snapshot", {}).get("scene", {}))
    ctx = TurnContext(session=engine, params=params)  # type: ignore[arg-type]
    if getattr(model, "system", "") == "openrouter":  # the same providers as the game (v0.7.14.4)
        await PICKER.refresh(model.model_name)
    agent = build_turn_agent(model, system_prompt_for(params), entry=is_entry(params))
    started = time.monotonic()
    billed: list[float] = []  # what OpenRouter charged for each request (v0.7.14.5)
    token = REQUEST_COSTS.set(billed)
    short = None
    before = RunUsage()
    try:
        if route:  # v0.7.20.4: the way of the game — the router, the short prompt, the full one when needed
            from .turns import _short_turn
            short, before, o.route = await _short_turn(model, params, turn_user_prompt(params), {})
        if short is not None:
            result = _ShortResult(short, before)
        else:
            try:
                result = await agent.run(turn_user_prompt(params), deps=ctx)
            except UnexpectedModelBehavior as exc:  # as the game does: once more with room to spare (turns.py)
                if "token limit" not in str(exc).lower() or engine.checks() or engine.effects():  # searches do not count, as in turns.py
                    raise
                agent = build_turn_agent(model, system_prompt_for(params), RETRY_MAX_TOKENS, entry=is_entry(params))
                ctx = TurnContext(session=engine, params=params)  # type: ignore[arg-type]
                result = await agent.run(turn_user_prompt(params), deps=ctx)
    except Exception as exc:  # noqa: BLE001 — a failed model run is a result, not a crash of the runner
        o.status, o.note = "error", f"{type(exc).__name__}: {str(exc)[:300]}"
        o.seconds = time.monotonic() - started
        o.cost_usd = sum(billed)
        return o
    finally:
        REQUEST_COSTS.reset(token)
    o.seconds = time.monotonic() - started
    out = result.output
    o.narration, o.options = out.narration, out.options
    o.next_mode = {"mode": out.next_mode, "npc_id": out.npc_id} if out.next_mode and out.next_mode != params.mode else None
    o.checks, o.effects = engine.checks(), engine.effects()
    o.tools = [p.tool_name for m in result.all_messages() for p in getattr(m, "parts", []) if isinstance(p, ToolCallPart)]
    usage = result.usage if short is not None else before + result.usage
    o.input_tokens, o.output_tokens = usage.input_tokens, usage.output_tokens
    from .turns import _served_by
    o.provider = _served_by(result)
    price_in, price_out = prices.get(model_id, (0.0, 0.0))
    o.cost_usd = sum(billed) or (usage.input_tokens * price_in + usage.output_tokens * price_out) / 1e6
    o.fails = check_expect(sc.get("expect", {}), {"narration": out.narration, "options": out.options, "option_checks": out.option_checks,
                                                 "next_mode": o.next_mode,
                                                 "missing_concept": out.missing_concept}, engine, o.tools)
    if judge_model is not None and sc.get("rubric"):
        try:
            o.verdicts = [v.model_dump() for v in await judge(judge_model, sc, {"narration": out.narration, "options": out.options, "option_checks": out.option_checks,
                                                                              "next_mode": o.next_mode, "missing_concept": out.missing_concept}, engine)]
        except Exception as exc:  # noqa: BLE001
            o.note = f"судья упал: {type(exc).__name__}"
    if o.fails or any(not v["passed"] for v in o.verdicts):
        o.status = "fail"
    return o


def report_markdown(model_id: str, judge_id: str | None, outcomes: list[Outcome]) -> str:
    ran = [o for o in outcomes if o.status in ("pass", "fail")]
    hard_ok = sum(1 for o in ran if not o.fails)
    rubric = [v for o in ran for v in o.verdicts]
    lines = [
        f"# Golden scenarios — {model_id}",
        "",
        f"{datetime.now(UTC).strftime('%Y-%m-%d %H:%M')} UTC · судья: {judge_id or 'нет'}",
        "",
        f"- Жёсткие проверки: **{hard_ok}/{len(ran)}** сценариев без нарушений",
        f"- Рубрика: **{sum(v['passed'] for v in rubric)}/{len(rubric)}** критериев",
        f"- Ошибки модели: {sum(o.status == 'error' for o in outcomes)}, не поддерживается протоколом: {sum(o.status == 'unsupported' for o in outcomes)}",
        f"- Цена: ${sum(o.cost_usd for o in outcomes):.4f} за {len(ran)} ходов, средняя задержка {sum(o.seconds for o in ran) / max(1, len(ran)):.1f} с",
        "",
        "| Сценарий | Итог | Жёсткие | Рубрика | Время | $ |",
        "|---|---|---|---|---|---|",
    ]
    for o in outcomes:
        rub = f"{sum(v['passed'] for v in o.verdicts)}/{len(o.verdicts)}" if o.verdicts else "—"
        hard = "✓" if o.status in ("pass", "fail") and not o.fails else ("—" if o.status != "fail" else f"✗ {len(o.fails)}")
        lines.append(f"| `{o.id}` | {o.status} | {hard} | {rub} | {o.seconds:.1f} с | {o.cost_usd:.4f} |")
    lines += ["", "## Подробности", ""]
    for o in outcomes:
        lines.append(f"### `{o.id}` — {o.status}")
        if o.note:
            lines.append(f"_{o.note}_")
        for f in o.fails:
            lines.append(f"- ✗ {f}")
        for v in o.verdicts:
            lines.append(f"- {'✓' if v['passed'] else '✗'} {v['criterion']} — {v['comment']}")
        if o.narration:
            lines.append(f"\n> {o.narration}\n")
            lines.append(f"проверки: {o.checks} · эффекты: {o.effects} · режим: {o.next_mode} · варианты: {o.options}")
        lines.append("")
    return "\n".join(lines)


async def run_all(model_id: str, judge_id: str | None, only: set[str] | None, repeat: int = 1,
                  route: bool = False, provider: str = "") -> tuple[list[Outcome], Path]:
    import os

    from dotenv import load_dotenv

    from .llm.catalog import ModelCatalog, openrouter_factory

    load_dotenv(REPO_ROOT / ".env", override=False)
    key = os.environ.get("OPENROUTER_API_KEY", "")
    if not key:
        sys.exit("OPENROUTER_API_KEY is not set (env or the root .env)")
    make = openrouter_factory(key)
    PICKER.bind(Path(os.environ.get("LLM_SERVER_DATA_DIR", str(REPO_ROOT / "llm_server" / "var"))) / "provider_bills.json")
    catalog = ModelCatalog(tuple(dict.fromkeys([model_id, *([judge_id] if judge_id else [])])), model_id)
    await catalog.load_prices()
    prices = {i.id: (i.input_usd_per_mtok, i.output_usd_per_mtok) for i in catalog.infos()}
    if provider:  # one provider for runs to compare (v0.7.34.3): the picker's choice drifts between them
        PINNED.set(provider)
    model = make(model_id)
    judge_model = make(judge_id) if judge_id else None
    outcomes = []
    for n in range(repeat):
        for sc in load_scenarios():
            if only and sc["id"] not in only:
                continue
            o = await run_one(sc, model, model_id, judge_model, prices, route)
            if repeat > 1:
                o.id = f"{o.id}#{n + 1}"
            print(f"{o.status:12} {o.id:34} {o.seconds:5.1f}s  ${o.cost_usd:.4f}  {o.route + '  ' if o.route else ''}{'; '.join(o.fails)[:120]}", flush=True)
            outcomes.append(o)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    stem = f"{datetime.now(UTC).strftime('%Y%m%d-%H%M%S')}-{re.sub(r'[^A-Za-z0-9._-]+', '_', model_id)}"
    (OUT_DIR / f"{stem}.json").write_text(json.dumps([o.__dict__ for o in outcomes], ensure_ascii=False, indent=2), encoding="utf-8")
    md = OUT_DIR / f"{stem}.md"
    md.write_text(report_markdown(model_id, judge_id, outcomes), encoding="utf-8")
    return outcomes, md


def main() -> None:
    import logging
    import os

    os.environ.setdefault("PYDANTIC_AI_NO_BANNER", "1")
    logging.basicConfig(level=logging.WARNING)
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--model", default=None, help="OpenRouter model id (default: LLM_SERVER_MODEL or the server default)")
    parser.add_argument("--judge", default="google/gemini-3.8-flash", help="judge model id")
    parser.add_argument("--no-judge", action="store_true")
    parser.add_argument("--only", default="", help="comma-separated scenario ids")
    parser.add_argument("--route", action="store_true", help="the game's way: the router and the short prompt (v0.7.20.4)")
    parser.add_argument("--repeat", type=int, default=1, help="run every scenario N times (models are not deterministic)")
    parser.add_argument("--provider", default="", help="pin the OpenRouter provider tag (e.g. relace); needs --no-judge")
    opts = parser.parse_args()
    if opts.provider and not opts.no_judge:
        parser.error("--provider pins every request, the judge's as well: run it with --no-judge")
    from .config import DEFAULT_MODEL

    model_id = opts.model or os.environ.get("LLM_SERVER_MODEL") or DEFAULT_MODEL
    only = {s.strip() for s in opts.only.split(",") if s.strip()} or None
    outcomes, md = asyncio.run(run_all(model_id, None if opts.no_judge else opts.judge, only, opts.repeat, opts.route, opts.provider))
    print(f"\nreport: {md}")
    sys.exit(1 if any(o.status in ("fail", "error") for o in outcomes) else 0)


if __name__ == "__main__":
    main()
