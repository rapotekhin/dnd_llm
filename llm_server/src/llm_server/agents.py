"""The turn agent (one LLM call per turn, ADR-0009) and the summary agent.

The model never changes the world: its tools go to Godot as engine.* calls (ADR-0008) and the turn result
lists only effect ids the engine reserved this turn.
"""

from __future__ import annotations

import json
import os
from dataclasses import dataclass, field
from typing import TYPE_CHECKING, Annotated, Any, Literal

from pydantic import BaseModel, BeforeValidator, Field, TypeAdapter, ValidationError
from pydantic_ai import Agent, ModelRetry, RunContext, Tool
from pydantic_ai.models import Model
from pydantic_ai.settings import ModelSettings

from . import prompts
from .llm.providers import PICKER, PINNED, min_tps
from .protocol import (
    DcTier,
    Effect,
    EngineCheckParams,
    EngineCheckResult,
    EngineFindItemsParams,
    EngineFindNpcsParams,
    EngineFindQuestsParams,
    EngineFindQuestsResult,
    CreateQuestEffect,
    EngineFindPlacesParams,
    EngineFindPlacesResult,
    CreatePlaceEffect,
    EngineFindNpcsResult,
    CreateNpcEffect,
    EngineFindItemsResult,
    EngineLookupParams,
    EngineLookupResult,
    EngineValidateParams,
    EngineValidateResult,
    GiveItemEffect,
    ItemProperty,
    LookupKind,
    SceneNpc,
    TurnRequestParams,
)

if TYPE_CHECKING:
    from .llm.library import ItemLibrary
    from .session import Session

MODEL_SETTINGS: ModelSettings = {"temperature": 0.8, "max_tokens": 2500}
# Models whose OpenRouter endpoints take no `temperature` (Claude 5): it is not sent to them.
NO_TEMPERATURE = ("anthropic/",)
# A turn that ran out of output tokens (a long fight start, a model that reasons first) is tried once more with this.
RETRY_MAX_TOKENS = 6000


def _json_object(value: Any) -> Any:
    # Some models (Qwen 3.x, DeepSeek) send a nested object argument as a JSON string, at times with a stray bracket
    # after it (`{…}]`): the first JSON value of the string is taken, what follows it is dropped.
    if isinstance(value, str):
        try:
            return json.JSONDecoder().raw_decode(value.strip())[0]
        except ValueError:
            return value
    return value


EffectArg = Annotated[Effect, BeforeValidator(_json_object)]


def settings_for(model: Model, base: ModelSettings = MODEL_SETTINGS) -> ModelSettings:
    """Per-model tweaks. Qwen 3.x answers in thinking mode by default, and thinking mode rejects the forced
    tool choice that structured output needs (HTTP 400), so reasoning is switched off for it. On OpenRouter the
    cheapest provider of the model that supports every parameter of the request is taken (v0.7.4, the author's
    wish); LLM_SERVER_PROVIDER_SORT = price (default) | throughput | latency | off. With price, v0.7.14.4: only the
    `LLM_SERVER_PROVIDER_TOP` cheapest providers (llm.providers.PICKER, refreshed before a turn), and those slower than
    `LLM_SERVER_MIN_TPS` tokens/s go last — the cheapest fast one of them serves."""
    settings: dict = dict(base)
    if "qwen/" in model.model_name or "nvidia/nemotron" in model.model_name:
        # v0.7.20.2: Nemotron thinks the whole max_tokens away before answering — the same switch
        settings["openrouter_reasoning"] = {"enabled": False}
    if model.model_name.startswith(NO_TEMPERATURE):
        # Their endpoints reject `temperature`: with require_parameters no provider is left (HTTP 404, v0.7.7).
        settings.pop("temperature", None)
    pinned = PINNED.get()
    if pinned and getattr(model, "system", "") == "openrouter":  # the player's provider and no other (v0.7.20.5)
        settings["openrouter_provider"] = {"only": [pinned], "order": [pinned], "allow_fallbacks": False, "require_parameters": True}
        return settings  # type: ignore[return-value]
    sort = os.environ.get("LLM_SERVER_PROVIDER_SORT", "price").strip().lower()
    if getattr(model, "system", "") == "openrouter" and sort in ("price", "throughput", "latency"):
        settings["openrouter_provider"] = {"sort": sort, "require_parameters": True}
        picked = PICKER.providers(model.model_name)
        if sort == "price" and picked:
            settings["openrouter_provider"].update({"only": picked, "allow_fallbacks": True})
            if min_tps() > 0:
                settings["openrouter_provider"]["preferred_min_throughput"] = {"p50": min_tps()}
    return settings  # type: ignore[return-value]


class TurnOutput(BaseModel):
    """What the master returns at the end of a turn."""

    narration: str = Field(description="Текст для игрока: описание мастера или реплика NPC. Не пустой.")
    options: list[str] = Field(default_factory=list, max_length=3, description="1–3 коротких варианта действий игрока от первого лица.")
    option_costs: list[int] = Field(default_factory=list, max_length=3, description=(
        "Цена каждого варианта в медных (мм), по порядку options: 0 — бесплатно. Вариант «Заплатить пять серебряных и выслушать» — 50. "
        "Движок спишет монеты, когда игрок выберет вариант."))
    effect_ids: list[str] = Field(default_factory=list, description="effect_id принятых движком эффектов, которые надо применить.")
    next_mode: Literal["exploration", "social", "trade", "combat"] | None = Field(
        default=None, description="Смена режима: social/trade — разговор/торговля с NPC (нужен npc_id), combat — игрок нападает на NPC сцены "
                                  "(нужен npc_id), exploration — вернуться в общую сцену.")
    npc_id: str | None = Field(default=None, description="NPC для social/trade/combat, из списка NPC сцены.")
    changes: list[str] = Field(default_factory=list, description=(
        "Что по твоему тексту изменилось у игрока или в мире: получено, потеряно, заплачено, отдано, украдено, ранен, вылечен, перешёл, прошло время. "
        "Пусто — ничего не изменилось. Каждое изменение должно быть принятым эффектом из effect_ids."))
    missing_concept: str | None = Field(default=None, description=(
        "Только когда замысел игрока нечем собрать из того, что умеет движок (проверки, эффекты, вещи, отношение, память, "
        "задания, тайны), и ты отказал в мире: коротко, по-русски, чего хотел игрок («стать матерью драконов», "
        "«основать свою деревню»). Это заметка автору игры, игрок её не видит. Иначе не заполняй."))


class SummaryOutput(BaseModel):
    summary: str = Field(description="2–4 предложения.")


@dataclass
class TurnContext:
    session: Session
    params: TurnRequestParams
    library: ItemLibrary | None = None
    check_ids: list[str] = field(default_factory=list)
    accepted: dict[str, str] = field(default_factory=dict)  # effect_id -> summary
    searched_items: bool = False
    searched_npcs: bool = False  # find_npcs this turn (v0.7.20: before create_npc)
    searched_places: bool = False  # find_places this turn (v0.7.20.1: before create_place)
    searched_quests: bool = False  # find_quests this turn (v0.7.21: before create_quest)
    proposed: set[str] = field(default_factory=set)  # effects accepted this turn (proposing one again is refused)
    empty_gives: int = 0  # give_item with neither item_id nor item
    topics: set[str] = field(default_factory=set)  # rule topics the master has: in the prompt or read with `rules` (v0.7.20.4)

    def __post_init__(self) -> None:
        self.topics |= set(prompts.auto_topics(self.params.mode, self.params.snapshot))

    @property
    def limits(self):
        return self.params.snapshot.limits


def scene_npc(params: TurnRequestParams, npc_id: str | None) -> SceneNpc | None:
    scene = params.snapshot.scene
    if scene is None or not npc_id:
        return None
    return next((n for n in scene.npcs if n.npc_id == npc_id), None)


# --- tools --------------------------------------------------------------------


async def request_check(
    ctx: RunContext[TurnContext],
    dc_tier: DcTier,
    reason: str,
    skill: str | None = None,
    save: str | None = None,
    target_id: str | None = None,
    advantage_reason: str | None = None,
    sense: Literal["sight", "hearing"] | None = None,
    tool: str | None = None,
) -> str:
    """Попросить движок о проверке навыка (skill: perception, persuasion, stealth, …) или спасброске
    (save: str, dex, con, int, wis, cha). dc_tier — ступень сложности. reason — что проверяем, одной фразой.
    advantage_reason — только если в ситуации есть явная причина для преимущества. sense — sight, если
    проверке нужно зрение (разглядеть), hearing — если слух (подслушать): ослеплённый или оглохший её провалит.
    tool — инструмент, которым герой действует (thieves_tools — вскрыть замок, herbalism_kit — травы, disguise_kit…):
    владение им и его наличие учитывает движок; замок без воровских инструментов не вскрыть."""
    t = ctx.deps
    if len(t.check_ids) >= t.limits.max_checks:
        return "Отказ: лимит проверок на этот ход исчерпан. Опиши исход без новой проверки."
    if (skill is None) == (save is None):
        raise ModelRetry("Укажи ровно одно: skill или save.")
    raw = await t.session.call_engine("engine.check", EngineCheckParams(
        turn_id=t.params.turn_id, skill=skill, save=save, dc_tier=dc_tier, target_id=target_id,
        advantage_reason=advantage_reason, sense=sense, tool=tool))
    r = EngineCheckResult.model_validate(raw)
    t.check_ids.append(r.check_id)
    if r.note:
        return f"{'Повтор' if r.blocked else 'Проверка'}: {r.note} Отыграй это и ничего не меняй эффектами."
    if r.blocked:
        if r.success:
            return "Повтор той же проверки: итог прежний — успех."
        return ("Повтор той же проверки без изменений заблокирован: итог прежний — ПРОВАЛ. Не описывай находку или удачу; "
                "подскажи, что изменит ситуацию: инструмент, другой навык, помощь, долгий отдых.")
    nat = " (натуральная 20)" if r.nat == 20 else " (натуральная 1)" if r.nat == 1 else ""
    if r.success:
        found = (" Движок открыл скрытое — опиши именно это и ничего сверх: " + "; ".join(r.revealed) + ".") if r.revealed else ""
        return (f"Успех: {r.total} против DC {r.dc}{nat}. Игрок добился своего — опиши это как удачу, а не отказ: "
                "если просьба невозможна целиком, он получает лучшее возможное (расположение, услугу, наводку, аудиенцию)." + found)
    return f"Провал: {r.total} против DC {r.dc}{nat}. Опиши неудачу и её последствия."


async def propose_effect(ctx: RunContext[TurnContext], effect: EffectArg) -> str:
    """Предложить движку последствие: move, damage, heal, coins, give_item, take_item, npc_attitude, flag,
    cast (игрок колдует: spell, slot_level, on_self — на себя), condition (наложить/снять состояние: reason,
    save {ability, dc_tier}, tag, duration, cause, by, repeat_save, ends_on_damage), use_feature (умение с
    ограниченными использованиями), use_item (выпить зелье и т. п.), advance_time (прошло время),
    furnish (обставить комнату при первом входе), take_prop (взять вещь комнаты), prop_state (вещь открыта,
    сломана, сожжена, сдвинута), note (память о событии короткой фразой по-русски), equip (игрок надевает или
    снимает снаряжение: slot, item_id или пусто; slot=all — раздеться).
    Движок проверит и зарезервирует его; верни effect_id в effect_ids итога, чтобы он применился."""
    t = ctx.deps
    # DeepSeek sometimes repeats one effect or an empty give_item many times in a row (v0.7.4 goldens): stop it early
    key = effect.model_dump_json()
    if key in t.proposed:
        return "Отказ: этот эффект уже принят в этом ходе — не повторяй его; если всё нужное сделано, заверши ход."
    if len(t.accepted) >= t.limits.max_effects:
        return "Отказ: лимит эффектов на этот ход исчерпан."
    if isinstance(effect, GiveItemEffect):
        if (effect.item_id is None) == (effect.item is None):
            # a refusal, not ModelRetry: three of those failed the whole turn (v0.7.4 goldens)
            t.empty_gives += 1
            if t.empty_gives >= 2:
                return "Отказ: выдавать здесь нечего — give_item не нужен. Если герой пострадал — damage; иначе заверши ход."
            return "Отказ: give_item — укажи либо item_id существующего предмета, либо item для нового; если давать нечего — не предлагай эффект."
        if effect.item is not None and not t.searched_items:
            return "Отказ: перед созданием нового предмета найди похожие через find_items."
    topic = prompts.topic_for(effect.kind)
    if topic and topic not in t.topics:
        return f"Отказ: сначала прочитай правила темы — rules(\"{topic}\"), потом предложи эффект снова."
    if isinstance(effect, CreateQuestEffect) and not t.searched_quests:
        return "Отказ: перед созданием задания поищи похожие через find_quests."
    if isinstance(effect, CreateNpcEffect) and not t.searched_npcs:
        return "Отказ: перед созданием человека поищи его через find_npcs."
    if isinstance(effect, CreatePlaceEffect) and not t.searched_places:
        return "Отказ: перед созданием места поищи его через find_places."
    raw = await t.session.call_engine("engine.validate", EngineValidateParams(turn_id=t.params.turn_id, effect=effect))
    r = EngineValidateResult.model_validate(raw)
    if not r.accepted or not r.effect_id:
        return f"Отклонено движком: {r.reason or 'без причины'}. Перепиши описание с учётом отказа."
    t.accepted[r.effect_id] = r.summary
    t.proposed.add(key)
    if isinstance(effect, GiveItemEffect) and effect.item is not None and t.library is not None and r.item_id:
        t.library.add(r.item_id, effect.item)
    hint = " Что заклинание сделало в мире — по правилам rules(\"spells\")." if effect.kind == "cast" and "spells" not in t.topics else ""
    return f"Принято: effect_id={r.effect_id}. {r.summary}{hint}"


# Google rejects the whole request when a tool's schema is too complex (v0.7.21: all 33 effect kinds in one union —
# Gemini 3.8 Flash failed every turn with «invalid argument»). For such models `propose_effect` takes a plain object, its
# description lists every kind with its fields, and the effect is checked here against the same schema. A JSON string,
# not an object: an object without a schema came from Gemini flattened («props_1_name»).
LOOSE_EFFECT_MODELS = ("google/",)
_EFFECT = TypeAdapter(Effect)


def _shape(ann: Any, depth: int = 0) -> str:
    """A field's type in a few characters: nested objects with their fields, choices with their values."""
    import types
    import typing

    args = [a for a in typing.get_args(ann) if a is not type(None)]
    origin = typing.get_origin(ann)
    if origin is typing.Annotated:
        return _shape(args[0], depth)
    if origin in (typing.Union, types.UnionType) and len(args) == 1:
        return _shape(args[0], depth)
    if origin is typing.Literal:
        return "|".join(map(str, typing.get_args(ann)))
    if origin is list and args:
        return f"[{_shape(args[0], depth)}]"
    if isinstance(ann, type) and issubclass(ann, BaseModel) and depth < 3:
        return "{" + ", ".join(f"{n}{'' if f.is_required() else '?'}: {_shape(f.annotation, depth + 1)}"
                               for n, f in ann.model_fields.items()) + "}"
    return getattr(ann, "__name__", "…") if depth else ""


def _effect_kinds() -> str:
    import typing

    lines = []
    for cls in typing.get_args(typing.get_args(Effect)[0]):
        fields = []
        for n, f in cls.model_fields.items():
            if n == "kind":
                continue
            shape = _shape(f.annotation, 1)
            fields.append(f"{n}{'' if f.is_required() else '?'}" + (f": {shape}" if shape and shape not in ("str", "int", "bool") else ""))
        lines.append(f"{cls.model_fields['kind'].default}({', '.join(fields)})")
    return "; ".join(lines)


async def propose_effect_loose(ctx: RunContext[TurnContext], effect: str) -> str:
    try:
        checked = _EFFECT.validate_python(_json_object(effect))
    except ValidationError as exc:
        raise ModelRetry("Эффект не по схеме: " + "; ".join(f"{'.'.join(map(str, e['loc']))}: {e['msg']}" for e in exc.errors()[:4]))
    return await propose_effect(ctx, checked)


def propose_effect_tool(model: Model) -> Tool | object:
    if not model.model_name.startswith(LOOSE_EFFECT_MODELS):
        return propose_effect
    return Tool(propose_effect_loose, name="propose_effect",
                description=(propose_effect.__doc__ or "") + "\nЭффект — JSON-объект строкой, с полем kind; виды и поля (? — необязательное): " + _effect_kinds())


RuleTopic = Literal[tuple(prompts.TOPICS)]  # type: ignore[valid-type]


async def rules(ctx: RunContext[TurnContext], topic: RuleTopic) -> str:
    """Подробные правила темы из оглавления в системном промпте: прочитай, прежде чем действовать по ней."""
    ctx.deps.topics.add(topic)
    return prompts.topic_text(topic)


async def lookup(ctx: RunContext[TurnContext], kind: LookupKind, id: str) -> str:
    """Справка движка: kind = rule | spell | feature | condition | item | npc; id — идентификатор или русское
    название (заклинания и умения — как в листе персонажа). Только сцена и SRD."""
    t = ctx.deps
    raw = await t.session.call_engine("engine.lookup", EngineLookupParams(turn_id=t.params.turn_id, kind=kind, id=id))
    r = EngineLookupResult.model_validate(raw)
    return json.dumps(r.data, ensure_ascii=False) if r.found else "Не найдено."


async def find_npcs(ctx: RunContext[TurnContext], query: str) -> str:
    """Найти людей мира (пакет и созданные в этой игре): query — имя, роль или место по-русски. Обязательно перед
    create_npc: может, такой человек уже есть."""
    t = ctx.deps
    t.searched_npcs = True
    raw = await t.session.call_engine("engine.find_npcs", EngineFindNpcsParams(turn_id=t.params.turn_id, query=query))
    found = EngineFindNpcsResult.model_validate(raw).npcs
    if not found:
        return "Никого похожего. Если человек нужен по сцене или замыслу игрока — create_npc."
    return "\n".join(f"[{n.npc_id}] {n.name} — {n.role}, {n.location}{' (мёртв)' if n.dead else ''}" for n in found)


async def find_quests(ctx: RunContext[TurnContext], query: str) -> str:
    """Найти задания мира (пакет и созданные в этой игре): query — суть дела, заказчик или место по-русски. Обязательно
    перед create_quest: может, такое дело уже есть."""
    t = ctx.deps
    t.searched_quests = True
    raw = await t.session.call_engine("engine.find_quests", EngineFindQuestsParams(turn_id=t.params.turn_id, query=query))
    r = EngineFindQuestsResult.model_validate(raw)
    head = f"Созданных заданий открыто: {r.open_made} из {r.max_open}."
    if not r.quests:
        return head + " Похожих нет. Если дело нужно — create_quest."
    status = {"offered": "предлагается", "taken": "взято", "done": "сделано", "failed": "провалено"}
    return head + "\n" + "\n".join(f"[{q.quest_id}] «{q.title}» — {q.giver}, {status.get(q.status, q.status)}" for q in r.quests)


async def find_places(ctx: RunContext[TurnContext], query: str) -> str:
    """Найти места мира (комнаты и локации пакета и созданные в этой игре): query — название по-русски. Обязательно
    перед create_place: может, такое место уже есть."""
    t = ctx.deps
    t.searched_places = True
    raw = await t.session.call_engine("engine.find_places", EngineFindPlacesParams(turn_id=t.params.turn_id, query=query))
    found = EngineFindPlacesResult.model_validate(raw).places
    if not found:
        return "Ничего похожего. Если место нужно и в сцене есть открытый край — create_place."
    return "\n".join(f"[{p.room_id}] {p.name} — {p.location}" for p in found)


async def find_items(ctx: RunContext[TurnContext], query: str, base: str | None = None,
                     properties: list[ItemProperty] | None = None) -> str:
    """Найти предметы в каталоге игры и библиотеке созданных: query — название или тип по-русски или id,
    base — id базового предмета, properties — нужные свойства."""
    t = ctx.deps
    t.searched_items = True
    raw = await t.session.call_engine("engine.find_items", EngineFindItemsParams(
        turn_id=t.params.turn_id, query=query, base=base, properties=properties or []))
    found = EngineFindItemsResult.model_validate(raw).items
    if t.library is not None:
        found += t.library.search(query, base, list(properties or []))
    if not found:
        return "Ничего похожего. Можно создать новый предмет через give_item.item."
    return "\n".join(f"[{i.item_id}] {i.name} — {i.item_type}, {i.rarity}, {i.value_cp} мм, свойства: {', '.join(i.properties) or 'нет'} ({i.source})"
                     for i in found[:8])


# --- agents ---------------------------------------------------------------------


def build_turn_agent(model: Model, system: str, max_tokens: int | None = None) -> Agent[TurnContext, TurnOutput]:
    base: ModelSettings = {**MODEL_SETTINGS, "max_tokens": max_tokens} if max_tokens else MODEL_SETTINGS  # type: ignore[typeddict-item]
    agent: Agent[TurnContext, TurnOutput] = Agent(
        model,
        output_type=TurnOutput,
        deps_type=TurnContext,
        instructions=system,
        tools=[request_check, propose_effect_tool(model), rules, lookup, find_items, find_npcs, find_places, find_quests],
        retries=2,
        model_settings=settings_for(model, base),
    )

    @agent.output_validator
    def _validate(ctx: RunContext[TurnContext], out: TurnOutput) -> TurnOutput:
        t = ctx.deps
        if not out.narration.strip():
            raise ModelRetry("narration не может быть пустым.")
        if out.changes and not out.effect_ids and t.accepted:
            # v0.7.20: the model proposed the effects (the engine accepted them) and forgot to list them — they are this
            # turn's, take them all instead of a retry the model tends to repeat until the turn fails
            out.effect_ids = list(t.accepted)
        if out.changes and not out.effect_ids:
            raise ModelRetry(f"В тексте есть изменения {out.changes}, но нет эффектов. Предложи их через propose_effect "
                             "и верни effect_ids, или перепиши текст так, чтобы ничего не менялось.")
        unknown = [e for e in out.effect_ids if e not in t.accepted]
        if unknown:
            raise ModelRetry(f"effect_ids {unknown} не принимались движком в этом ходе. Используй только id из ответов propose_effect.")
        if out.next_mode in ("social", "trade", "combat") and t.params.mode != "combat" and scene_npc(t.params, out.npc_id) is None:
            raise ModelRetry("Для social/trade/combat укажи npc_id из списка NPC сцены.")
        return out

    return agent


def build_summary_agent(model: Model, kind: str) -> Agent[None, SummaryOutput]:
    return Agent(model, output_type=SummaryOutput, retries=2, model_settings=settings_for(model, {"temperature": 0.3, "max_tokens": 400}),
                 instructions="Ты пишешь краткие записи по-русски для памяти мастера игры.", name=f"summary_{kind}")


def system_prompt_for(params: TurnRequestParams) -> str:
    return prompts.system_prompt(params.mode, params.snapshot, scene_npc(params, params.npc_id))


def turn_user_prompt(params: TurnRequestParams) -> str:
    return prompts.turn_prompt(params.mode, params.kind, params.input, params.snapshot, scene_npc(params, params.npc_id))
