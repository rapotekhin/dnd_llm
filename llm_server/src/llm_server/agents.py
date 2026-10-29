"""The turn agent (one LLM call per turn, ADR-0009) and the summary agent.

The model never changes the world: its tools go to Godot as engine.* calls (ADR-0008) and the turn result
lists only effect ids the engine reserved this turn.
"""

from __future__ import annotations

import json
import os
from dataclasses import dataclass, field
from typing import TYPE_CHECKING, Annotated, Any, Literal
from typing import get_args as typing_get_args

from pydantic import BaseModel, BeforeValidator, Field, TypeAdapter, ValidationError
from pydantic_ai import Agent, ModelRetry, PromptedOutput, RunContext, Tool
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
    EngineFindTeachersParams,
    EngineFindTeachersResult,
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


# An effect that does not fit the schema still reaches the tool (as a plain object) and is refused there with the
# reason: a refusal lets the master fix it or end the turn in words, where a validation retry spent the turn's retries
# and failed it whole (v0.7.21.2: a board order with its people and place was mistyped five times in a row).
EffectArg = Annotated[Effect | dict[str, Any], BeforeValidator(_json_object)]
BAD_EFFECTS_MAX = 3


def _schema_refusal(t: "TurnContext", exc: ValidationError) -> str:
    t.bad_effects += 1
    why = "; ".join(f"{'.'.join(map(str, e['loc']))}: {e['msg']}" for e in exc.errors()[:4])
    if t.bad_effects >= BAD_EFFECTS_MAX:
        return f"Отказ: эффект снова не по схеме ({why}). Больше не пробуй — заверши ход словами, без этого эффекта."
    return f"Отказ: эффект не по схеме — {why}. Исправь и предложи снова."


def settings_for(model: Model, base: ModelSettings = MODEL_SETTINGS) -> ModelSettings:
    """Per-model tweaks. Qwen 3.x answers in thinking mode by default, and thinking mode rejects the forced
    tool choice that structured output needs (HTTP 400), so reasoning is switched off for it. On OpenRouter the
    cheapest provider of the model that supports every parameter of the request is taken (v0.7.4, the author's
    wish); LLM_SERVER_PROVIDER_SORT = price (default) | throughput | latency | off. With price, v0.7.14.4: only the
    `LLM_SERVER_PROVIDER_TOP` cheapest providers (llm.providers.PICKER, refreshed before a turn), and those slower than
    `LLM_SERVER_MIN_TPS` tokens/s go last — the cheapest fast one of them serves. v0.7.34.1: the cheapest by the real
    cost of our turn (cache, the providers' bills), no provider pinned first."""
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
    option_checks: list[str] = Field(default_factory=list, max_length=3, description=(
        "Проверка каждого варианта по порядку options: «навык:сложность» (persuasion:medium, athletics:hard) — когда исход "
        "варианта решает бросок, иначе пустая строка. Движок ставит Сл, показывает шанс и сам бросит, когда игрок выберет вариант."))
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
    item_searches: int = 0  # find_items this turn (v0.7.34.4: past FIND_ITEMS_MAX the master makes the thing)
    searched_npcs: bool = False  # find_npcs this turn (v0.7.20: before create_npc)
    searched_places: bool = False  # find_places this turn (v0.7.20.1: before create_place)
    searched_quests: bool = False  # find_quests this turn (v0.7.21: before create_quest)
    proposed: set[str] = field(default_factory=set)  # effects accepted this turn (proposing one again is refused)
    empty_gives: int = 0  # give_item with neither item_id nor item
    bad_effects: int = 0  # effects refused for their shape this turn (v0.7.21.2)
    topics: set[str] = field(default_factory=set)  # rule topics the master has: in the prompt or read with `rules` (v0.7.20.4)
    made_npcs: list[str] = field(default_factory=list)  # create_npc accepted this turn: in the world only after the turn

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


def _with_topic(t: TurnContext, topic: str, text: str) -> str:
    """A search before a creation answers with the topic's rules at once: a refusal «read rules first» cost a request."""
    if topic in t.topics:
        return text
    t.topics.add(topic)
    return f"{text}\n\nПравила темы «{topic}» (читать rules(\"{topic}\") уже не нужно):\n{prompts.topic_text(topic)}"


def _library_stock(effect: CreateNpcEffect, library: ItemLibrary) -> CreateNpcEffect:
    """Goods of the library (made in other games) go to `stock_new` by their schema: the engine knows only this game."""
    npc = effect.npc
    moved = [(i, item) for i in npc.stock if i.startswith("gen_") and (item := library.get(i)) is not None]
    if not moved:
        return effect
    ids = {i for i, _ in moved}
    npc = npc.model_copy(update={"stock": [i for i in npc.stock if i not in ids],
                                 "stock_new": [*npc.stock_new, *(m for _, m in moved)][:5]})
    return effect.model_copy(update={"npc": npc})


# --- tools --------------------------------------------------------------------


async def request_check(
    ctx: RunContext[TurnContext],
    dc_tier: str,
    reason: str,
    skill: str | None = None,
    save: str | None = None,
    target_id: str | None = None,
    advantage_reason: str | None = None,
    sense: str | None = None,
    tool: str | None = None,
    argument: str | None = None,
) -> str:
    """Попросить движок о проверке навыка (skill: perception, persuasion, stealth, …) или спасброске
    (save: str, dex, con, int, wis, cha). dc_tier — ступень сложности: very_easy, easy, medium, hard, very_hard,
    nearly_impossible. reason — что проверяем, одной фразой.
    advantage_reason — только если в ситуации есть явная причина для преимущества. sense — sight, если
    проверке нужно зрение (разглядеть), hearing — если слух (подслушать): ослеплённый или оглохший её провалит.
    tool — инструмент, которым герой действует (thieves_tools — вскрыть замок, herbalism_kit — травы, disguise_kit…):
    владение им и его наличие учитывает движок; замок без воровских инструментов не вскрыть.
    argument — для Убеждения, Обмана, Запугивания: довод игрока в нескольких словах; повтор у того же NPC
    бросается заново только с новым доводом или после перемены (заклинание, подарок, отношение)."""
    t = ctx.deps
    if len(t.check_ids) >= t.limits.max_checks:
        return "Отказ: лимит проверок на этот ход исчерпан. Опиши исход без новой проверки."
    # A wrong value is a refusal with the reason, not a schema error: the tool's retries failed the whole turn
    # (v0.7.22.16, the author's trace: three turns in a row lost on request_check).
    if dc_tier not in DC_TIERS:
        return f"Отказ: dc_tier — одно из {', '.join(DC_TIERS)}; вызови снова."
    if sense not in (None, "sight", "hearing"):
        sense = None
    if not skill:
        skill = None
    if not save:
        save = None
    if (skill is None) == (save is None):
        # a refusal, not ModelRetry: three of those failed the whole turn (v0.7.22.16, the author's trace)
        return "Отказ: укажи ровно одно — skill (навык) или save (спасбросок) — и вызови снова; или заверши ход без проверки."
    from .protocol import ErrorCode
    from .session import RpcError  # local: session imports this module
    try:
        raw = await t.session.call_engine("engine.check", EngineCheckParams(
            turn_id=t.params.turn_id, skill=skill, save=save, dc_tier=dc_tier, target_id=target_id,
            advantage_reason=advantage_reason, sense=sense, tool=tool, argument=argument))
    except RpcError as err:
        if err.code != ErrorCode.ENGINE_ERROR or err.engine_code != ErrorCode.INVALID_PARAMS:
            raise
        # the engine refused the check's values (an unknown skill…): a refusal the model can mend, not a failed turn
        # (v0.7.39.8, live playtest: ENGINE_ERROR lost the whole turn)
        return f"Отказ движка: {err}. Поправь skill / save по списку навыков и спасбросков и вызови снова; или заверши ход без проверки."
    r = EngineCheckResult.model_validate(raw)
    t.check_ids.append(r.check_id)
    if r.note:
        return f"{'Повтор' if r.blocked else 'Проверка'}: {r.note} Отыграй это и ничего не меняй эффектами."
    if r.blocked:
        if r.success:
            return "Повтор той же проверки: итог прежний — успех."
        return ("Повтор той же проверки без изменений заблокирован: итог прежний — ПРОВАЛ. Не описывай находку или удачу; "
                "подскажи, что изменит ситуацию: новый довод, инструмент, другой навык, помощь, заклинание, долгий отдых.")
    nat = " (натуральная 20)" if r.nat == 20 else " (натуральная 1)" if r.nat == 1 else ""
    if r.rolled_as:
        nat += f" — бросок по выбору игрока: {r.rolled_as}; описывай действие через это"
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
    furnish (обставить комнату при первом входе; в обставленную — только с cause), take_prop (взять вещь комнаты), prop_state (вещь открыта,
    сломана, сожжена, сдвинута), note (память о событии короткой фразой по-русски), equip (игрок надевает или
    снимает снаряжение: slot, item_id или пусто; slot=all — раздеться), stock (торговцу сцены — вещь его ремесла, которой
    нет в товаре); create_npc, create_place, create_quest,
    door, owner, upgrade (улучшение своего места), world_item (вещь NPC или контейнера по причине в мире) и другие — по своей теме правил (все виды и поля — в схеме effect).
    Движок проверит и зарезервирует его; верни effect_id в effect_ids итога, чтобы он применился."""
    t = ctx.deps
    if isinstance(effect, dict):
        try:
            effect = _EFFECT.validate_python(effect)
        except ValidationError as exc:
            return _schema_refusal(t, exc)
    if (effect.kind == "letter_reply") != (t.params.kind == "letter") and effect.kind != "note":  # v0.7.48: the answer to a letter
        return ("Отказ: в ответе на письмо — только letter_reply (и note)." if t.params.kind == "letter" else
                "Отказ: letter_reply — только в ответе на письмо героя.")
    if (effect.kind == "quest_act") != (t.params.kind == "quest_act"):  # v0.7.39.6: the designer builds acts, only acts
        return ("Отказ: в ходе сценария — только quest_act." if t.params.kind == "quest_act" else
                "Отказ: акт задания собирает сценарист, когда герой до него дойдёт; новое задание — create_quest.")
    # DeepSeek sometimes repeats one effect or an empty give_item many times in a row (v0.7.4 goldens): stop it early
    if t.params.kind in ENTRY_KINDS and effect.kind not in ENTRY_EFFECTS:
        return ("Отклонено движком: игрок только вошёл и ещё ничего не сделал — в этом ходе мир не меняется "
                f"(можно лишь {', '.join(sorted(ENTRY_EFFECTS))}). Опиши место без подарков, монет и перемен.")
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
    if topic and topic not in t.topics and t.params.kind != "quest_act":  # the rules come with the refusal: no extra call (v0.7.34.3)
        t.topics.add(topic)
        return f"Отказ: эффект темы «{topic}» — по её правилам. Вот они:\n{prompts.topic_text(topic)}\nПредложи эффект снова по ним."
    if isinstance(effect, CreateNpcEffect) and t.library is not None:
        effect = _library_stock(effect, t.library)
    if isinstance(effect, CreateQuestEffect) and not t.searched_quests:
        return "Отказ: перед созданием задания поищи похожие через find_quests."
    if isinstance(effect, CreateNpcEffect) and not t.searched_npcs:
        return "Отказ: перед созданием человека поищи его через find_npcs."
    if isinstance(effect, CreatePlaceEffect) and not t.searched_places:
        return "Отказ: перед созданием места поищи его через find_places."
    raw = await t.session.call_engine("engine.validate", EngineValidateParams(turn_id=t.params.turn_id, effect=effect))
    r = EngineValidateResult.model_validate(raw)
    made = (t.library.get(effect.item_id) if not r.accepted and isinstance(effect, GiveItemEffect) and effect.item_id
            and t.library is not None else None)
    if made is not None:  # a thing of the library, not yet in this game: the engine makes it by its schema
        effect = effect.model_copy(update={"item_id": None, "item": made})
        raw = await t.session.call_engine("engine.validate", EngineValidateParams(turn_id=t.params.turn_id, effect=effect))
        r = EngineValidateResult.model_validate(raw)
    if not r.accepted or not r.effect_id:
        return f"Отклонено движком: {r.reason or 'без причины'}. Перепиши описание с учётом отказа."
    t.accepted[r.effect_id] = r.summary
    t.proposed.add(key)
    if isinstance(effect, CreateNpcEffect):
        t.made_npcs.append(effect.npc.name)
    if isinstance(effect, GiveItemEffect) and effect.item is not None and t.library is not None and r.item_id:
        t.library.add(r.item_id, effect.item)
    hint = " Что заклинание сделало в мире — по правилам rules(\"spells\")." if effect.kind == "cast" and "spells" not in t.topics else ""
    return f"Принято: effect_id={r.effect_id}. {r.summary}{hint}"


# `propose_effect` takes the effect as a JSON string for every model: its description lists every kind with its fields
# (~9k characters instead of the ~51k JSON schema of the union) and the effect is checked here against the same schema.
# Gemini needed it from v0.7.21 (a too complex schema, a flattened object); DeepSeek did as well with half the input on
# the golden subset (2026-10-26, docs/tech/prompt-experiments-2026-10-26.md).
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


def _effect_kinds(only: set[str] | None = None) -> str:
    import typing

    lines = []
    for cls in typing.get_args(typing.get_args(Effect)[0]):
        if only is not None and cls.model_fields["kind"].default not in only:
            continue
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
        return _schema_refusal(ctx.deps, exc)
    return await propose_effect(ctx, checked)


# The entry turn wandered in searches: 30 find_items, 116 s (the author's trace 2026-10-27, t-17) — one wave of
# parallel calls, then the master makes what is missing.
FIND_ITEMS_MAX = 6

# The entry turn (v0.7.34.3, the author's trace t-10: a gift and a flag on walking into the square): the player did
# nothing yet — only the room's furnishing and the master's memory.
ENTRY_KINDS = {"enter", "resume"}
ENTRY_EFFECTS = {"furnish", "note"}

DC_TIERS: tuple[str, ...] = typing_get_args(DcTier)
EFFECT_RETRIES = 4  # a big effect (a quest with its people and place) is often mistyped once or twice (v0.7.21.2 goldens)


def propose_effect_tool(only: set[str] | None = None) -> Tool:
    head = (propose_effect.__doc__ or "") if only is None else "Предложить движку последствие: он проверит и зарезервирует его; верни effect_id в effect_ids итога."
    return Tool(propose_effect_loose, name="propose_effect", max_retries=EFFECT_RETRIES,
                description=head + "\nЭффект — JSON-объект строкой, с полем kind; виды и поля (? — необязательное): " + _effect_kinds(only))


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
    # v0.7.38.1 (the author's trace): a board quest's giver made by create_npc was not found here, the master went
    # round in circles until the token limit; such a giver goes in the quest's own new_npcs
    made = (f"\n\nСозданные в этом ходу ({', '.join(t.made_npcs)}) появятся в мире после хода: искать их и давать им "
            "задание этим ходом нельзя; заказчик-новичок — в new_npcs самого create_quest (giver new:<key>).") if t.made_npcs else ""
    if not found:
        return _with_topic(t, "people", "Никого похожего. Если человек нужен по сцене или замыслу игрока — create_npc." + made)
    return _with_topic(t, "people", "\n".join(f"[{n.npc_id}] {n.name} — {n.role}, {n.location}{' (мёртв)' if n.dead else ''}" for n in found) + made)


async def find_quests(ctx: RunContext[TurnContext], query: str) -> str:
    """Найти задания мира (пакет и созданные в этой игре): query — суть дела, заказчик или место по-русски. Обязательно
    перед create_quest: может, такое дело уже есть."""
    t = ctx.deps
    t.searched_quests = True
    raw = await t.session.call_engine("engine.find_quests", EngineFindQuestsParams(turn_id=t.params.turn_id, query=query))
    r = EngineFindQuestsResult.model_validate(raw)
    head = f"Созданных заданий открыто: {r.open_made} из {r.max_open}."
    if not r.quests:
        return _with_topic(t, "quests", head + " Похожих нет. Если дело нужно — create_quest.")
    status = {"offered": "предлагается", "taken": "взято", "done": "сделано", "failed": "провалено"}
    return _with_topic(t, "quests", head + "\n" + "\n".join(
        f"[{q.quest_id}] «{q.title}» — {q.giver}, {status.get(q.status, q.status)}" for q in r.quests))


async def find_teachers(ctx: RunContext[TurnContext], kind: Literal["skill", "tool", "language", "spell", "recipe"], what: str) -> str:
    """Кто в мире учит этому: kind — spell | recipe | tool | skill | language, what — id или русское название
    («Огненный шар», «секира»). Обязательно, когда игрок спрашивает, у кого научиться, и перед курсом заклинания или
    курсом у учителя не из сцены."""
    t = ctx.deps
    raw = await t.session.call_engine("engine.find_teachers", EngineFindTeachersParams(turn_id=t.params.turn_id, kind=kind, what=what))
    r = EngineFindTeachersResult.model_validate(raw)
    if r.reason:
        return r.reason
    if not r.teachers:
        return _with_topic(t, "study", f"Никто в мире не учит {what} [{r.what}]. Не отсылай словами к выдуманному учителю и не "
                           "создавай место или человека просто так: дай задание найти учителя — create_quest (своё дело own: "
                           "true или от NPC сцены, кто слышал о таком), учителя приведёт сценарист в акте задания с курсом (teaches).")
    lines = []
    for x in r.teachers:
        state = "здесь" if x.here else f"не здесь: {x.place}"
        course = (f"; курс уже есть [{x.course}] — просто укажи на него" if x.course
                  else f"; курса ещё нет — course {{npc_id: {x.npc_id}, teach_kind: {kind}, teach_id: {r.what}}}")
        lines.append(f"[{x.npc_id}] {x.name} — {x.role} ({state}); учит: {x.teaches}{course}")
    return _with_topic(t, "study", f"Учат {what} [{r.what}]:\n" + "\n".join(lines) +
                       "\nВ рассказе назови игроку ближайшего учителя и где его найти — это и есть ответ на вопрос; задание не "
                       "нужно. Занятия, плату и условия курса заклинания ставит движок — в рассказе только то, что вернул course.")


async def find_places(ctx: RunContext[TurnContext], query: str) -> str:
    """Найти места мира (комнаты и локации пакета и созданные в этой игре): query — название или локация по-русски.
    Обязательно перед create_place: может, такое место уже есть. В ответе — и открытые края известного мира, где можно
    дорисовать новое место (не только здесь)."""
    t = ctx.deps
    t.searched_places = True
    raw = await t.session.call_engine("engine.find_places", EngineFindPlacesParams(turn_id=t.params.turn_id, query=query))
    r = EngineFindPlacesResult.model_validate(raw)
    out = ["\n".join(f"[{p.room_id}] {p.name} — {p.location}" for p in r.places) if r.places else "Похожих мест нет."]
    if r.edges:  # 0.48.0: where a new place may grow — this room, its location, the neighbours, where the hero has been
        out.append("Открытые края, где можно дорисовать место (create_place с room_id и edge; герой туда не переходит):\n" + "\n".join(
            f"[{e.room_id}] {e.room} ({e.location}), край {e.edge}: {e.text}; местность {', '.join(e.terrain)}"
            f"{'; можно новую локацию' if e.new_location else ''}" for e in r.edges))
    else:
        out.append("Открытых краёв поблизости нет — за пределами известного мест не создать; объект внутри локации можно (inside).")
    return _with_topic(t, "places", "\n\n".join(out))


async def find_items(ctx: RunContext[TurnContext], query: str, base: str | None = None,
                     properties: list[ItemProperty] | None = None) -> str:
    """Найти предметы в каталоге игры и библиотеке созданных: query — название или тип по-русски или id,
    base — id базового предмета, properties — нужные свойства."""
    t = ctx.deps
    t.searched_items = True
    t.item_searches += 1
    if t.item_searches > FIND_ITEMS_MAX:
        return ("Отказ: поиск вещей на этот ход исчерпан — больше не ищи. Чего не нашлось, создай сам: переносную — поле "
                "`item` (у вещи обстановки, в `contents`, в `give_item`), неподвижную — просто вещь обстановки без `item_id`.")
    raw = await t.session.call_engine("engine.find_items", EngineFindItemsParams(
        turn_id=t.params.turn_id, query=query, base=base, properties=properties or []))
    found = EngineFindItemsResult.model_validate(raw).items
    if t.library is not None:
        found += t.library.search(query, base, list(properties or []))
    if not found:
        return ("Ничего похожего — не ищи это снова. Переносную вещь создай сам: поле `item` (у вещи обстановки, в `contents`, "
                "в `give_item`); неподвижную (мебель, очаг) опиши вещью обстановки без `item_id`.")
    return "\n".join(f"[{i.item_id}] {i.name} — {i.item_type}, {i.rarity}, {i.value_cp} мм, свойства: {', '.join(i.properties) or 'нет'} ({i.source})"
                     for i in found[:8])


# --- agents ---------------------------------------------------------------------


def no_thinking(settings: ModelSettings) -> ModelSettings:
    """Reasoning off: a short request needs none — DeepSeek thought the router's whole budget away (v0.7.21 `--route`
    goldens) and the entry turn's last answer for 40 s (v0.7.34.4, the author's trace t-17)."""
    out = dict(settings)
    out["openrouter_reasoning"] = {"enabled": False}
    return out  # type: ignore[return-value]


def build_turn_agent(model: Model, system: str, max_tokens: int | None = None, entry: bool = False) -> Agent[TurnContext, TurnOutput]:
    base: ModelSettings = {**MODEL_SETTINGS, "max_tokens": max_tokens} if max_tokens else MODEL_SETTINGS  # type: ignore[typeddict-item]
    settings = settings_for(model, base)
    agent: Agent[TurnContext, TurnOutput] = Agent(
        model,
        output_type=TurnOutput,
        deps_type=TurnContext,
        instructions=system,
        tools=([propose_effect_tool(ENTRY_EFFECTS), find_items] if entry else
               [Tool(request_check, max_retries=EFFECT_RETRIES), propose_effect_tool(), rules, lookup, find_items, find_npcs, find_places, find_quests, find_teachers]),
        retries=2,
        model_settings=no_thinking(settings) if entry else settings,
    )

    @agent.output_validator
    def _validate(ctx: RunContext[TurnContext], out: TurnOutput) -> TurnOutput:
        t = ctx.deps
        if not out.narration.strip():
            raise ModelRetry("narration не может быть пустым.")
        if t.params.pinned_check and not t.check_ids and t.params.mode != "combat":
            raise ModelRetry(f"Игрок сам выбрал проверку «{t.params.pinned_check}» — она обязательна: вызови request_check "
                             "(движок бросит этим навыком) со сложностью по действию — при твёрдом отказе NPC или почти "
                             "невозможном деле nearly_impossible — и опиши итог по броску.")
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
        if (out.next_mode == "social" and out.npc_id
                and any(f"[{out.npc_id}]" in c for c in t.params.snapshot.scene.creatures)):
            out.next_mode = None  # 0.45.0: a creature a fight left is no NPC — the talk goes on in the narration
            out.npc_id = None
        if out.next_mode in ("social", "trade", "combat") and t.params.mode != "combat" and scene_npc(t.params, out.npc_id) is None:
            raise ModelRetry("Для social/trade/combat укажи npc_id из списка NPC сцены (существа после боя — не NPC: "
                             "за них отвечай прямо в рассказе, без next_mode).")
        return out

    return agent


def is_quest_act(params: TurnRequestParams) -> bool:
    """The designer's turn (v0.7.39.6): an act of a taken quest opened."""
    return params.kind == "quest_act"


DESIGNER_MAX_TOKENS = 8000  # a whole act in one effect: steps, people, places, fights


def build_designer_agent(model: Model, system: str) -> Agent[TurnContext, TurnOutput]:
    """The quest designer (v0.7.39.6): builds the act that opened by the engine's frame, one `quest_act`; it searches
    the world (people, places, things, rules of the SRD) and fixes what the engine refuses, part by part."""
    agent: Agent[TurnContext, TurnOutput] = Agent(
        model,
        output_type=TurnOutput,
        deps_type=TurnContext,
        instructions=system,
        tools=[propose_effect_tool({"quest_act"}), lookup, find_items, find_npcs, find_places, find_teachers],
        retries=2,
        model_settings=settings_for(model, {**MODEL_SETTINGS, "temperature": 0.7, "max_tokens": DESIGNER_MAX_TOKENS}),  # type: ignore[typeddict-item]
        name="quest_designer",
    )

    @agent.output_validator
    def _validate(ctx: RunContext[TurnContext], out: TurnOutput) -> TurnOutput:
        t = ctx.deps
        if not t.accepted:
            raise ModelRetry("Акт не собран: предложи quest_act через propose_effect и исправь то, в чём движок отказал.")
        out.effect_ids = list(t.accepted)
        out.options, out.option_costs, out.option_checks, out.next_mode, out.npc_id, out.changes = [], [], [], None, None, []
        if not out.narration.strip():
            out.narration = "Дело движется дальше."
        return out

    return agent


def build_summary_agent(model: Model, kind: str) -> Agent[None, SummaryOutput]:
    return Agent(model, output_type=SummaryOutput, retries=2, model_settings=settings_for(model, {"temperature": 0.3, "max_tokens": 400}),
                 instructions="Ты пишешь краткие записи по-русски для памяти мастера игры.", name=f"summary_{kind}")


class ImagePrompt(BaseModel):
    """The frame of an event for an image model (v0.7.35): the scene in English, and what to keep out of it."""

    scene: str = Field(min_length=10, max_length=1500)
    negative: str = Field(default="", max_length=500)


def build_image_agent(model: Model, instructions: str) -> Agent[None, ImagePrompt]:
    # Reasoning off: a frame needs no thinking, and DeepSeek would spend the seconds the player waits.
    # JSON in the text, not an output tool: the author reads the tags in the OpenRouter log (v0.7.38.3).
    return Agent(model, output_type=PromptedOutput(ImagePrompt), retries=2, name="image_prompt", instructions=instructions,
                 model_settings=no_thinking(settings_for(model, {"temperature": 0.7, "max_tokens": 700})))


def is_entry(params: TurnRequestParams) -> bool:
    """A turn of walking in: its own short prompt and tools (v0.7.34.3)."""
    return params.kind == "enter" and params.mode == "exploration"


def system_prompt_for(params: TurnRequestParams) -> str:
    if is_quest_act(params):
        return prompts.quest_act_prompt(params.snapshot)
    if is_entry(params):
        return prompts.entry_prompt(params.snapshot)
    return prompts.system_prompt(params.mode, params.snapshot, scene_npc(params, params.npc_id), said=params.input)


def turn_user_prompt(params: TurnRequestParams) -> str:
    if is_quest_act(params):
        return params.input  # the engine's frame of the act
    return prompts.turn_prompt(params.mode, params.kind, params.input, params.snapshot, scene_npc(params, params.npc_id))
