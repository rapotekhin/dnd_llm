"""Turn and summary handlers.

- `agent_turn`: one Pydantic AI run over OpenRouter per turn (ADR-0009), tools → engine.*.
- `stub_turn`: no LLM — protocol tests and UI work without money (LLM_SERVER_TURN_HANDLER=stub).
"""

import asyncio
import contextlib
import logging
import re
import time
from collections.abc import Awaitable, Callable, Iterator
from typing import Any, TypeVar, get_args

from pydantic_ai import capture_run_messages
from pydantic_ai.exceptions import ModelAPIError, ModelHTTPError, UnexpectedModelBehavior, UsageLimitExceeded
from pydantic_ai.models import Model
from pydantic_ai.usage import RunUsage, UsageLimits

from . import prompts, router
from .llm.catalog import REQUEST_COSTS
from .llm.providers import PICKER, PINNED, pinned_for
from .agents import (TurnContext, TurnOutput, agent_for, build_summary_agent, prepare_head, retry_max_tokens, scene_npc, system_prompt_for,
                     turn_kind, turn_user_prompt)
from .protocol import (
    DcTier,
    OptionCheck,
    CoinsEffect,
    ConditionEffect,
    DamageEffect,
    Effect,
    EngineFindNpcsParams,
    EngineFindQuestsParams,
    EngineValidateParams,
    EngineValidateResult,
    CreateQuestEffect,
    FurnishEffect,
    PropSpec,
    QuestAct,
    QuestNpc,
    ActStep,
    LetterReplyEffect,
    QuestActEffect,
    HealEffect,
    EngineCheckParams,
    EngineCheckResult,
    ErrorCode,
    NextMode,
    SummaryParams,
    SummaryResult,
    TurnRequestParams,
    TurnResult,
    Usage,
)
from .session import RpcError, Session

log = logging.getLogger("llm_server.turns")

T = TypeVar("T")
# Model requests per turn: tool round trips plus output retries.
TURN_USAGE_LIMITS = UsageLimits(request_limit=12)  # a place, its person and the way in take ~8 (v0.7.22.25.1)
RETRYABLE_HTTP = {408, 409, 425, 429, 500, 502, 503, 504}
_sleep = asyncio.sleep  # tests replace it to skip the pauses


async def stub_turn(session: Session, params: TurnRequestParams) -> TurnResult:
    usage = Usage(model="stub")
    if params.kind == "quest_act":
        return await _stub_act(session, params, usage)
    if params.kind == "letter":
        return await _stub_letter(session, params, usage)
    if params.kind == "prepare":
        return await _stub_prepare(session, params, usage)
    if params.kind in ("deal", "quest", "ability", "downed", "combat_start", "combat_round", "death", "law"):
        return TurnResult(turn_id=params.turn_id, narration=f"Готово. ({params.input})", usage=usage)
    if params.kind != "action":
        return TurnResult(turn_id=params.turn_id, narration="Вы осматриваетесь.", usage=usage)

    raw = await session.call_engine(
        "engine.check",
        EngineCheckParams(turn_id=params.turn_id, skill="perception", dc_tier="medium"),
    )
    check = EngineCheckResult.model_validate(raw)
    outcome = "замечаете" if check.success else "не замечаете"
    # Every few turns the stub proposes an effect too, so a bot player exercises the engine without a model.
    effect_ids: list[str] = []
    n = int(params.turn_id.split("-")[1])
    effect = STUB_EFFECTS[n % len(STUB_EFFECTS)]
    if effect is not None:
        v = EngineValidateResult.model_validate(await session.call_engine(
            "engine.validate", EngineValidateParams(turn_id=params.turn_id, effect=effect)))
        if v.accepted and v.effect_id:
            effect_ids.append(v.effect_id)
    return TurnResult(
        turn_id=params.turn_id,
        narration=f"Вы {outcome} что-то необычное ({check.total} против {check.dc}).",
        options=["Осмотреться ещё раз", "Взобраться на балку под потолком"],
        option_checks=[None, OptionCheck(skill="athletics", dc_tier="medium")],
        check_ids=[check.check_id],
        effect_ids=effect_ids,
        usage=usage,
    )


_FRAME_HEAD = re.compile(r"^\[quest (\S+) \| act (\d+) \| giver (\S*) \| here (\S*) \| near (\S*)\]")


async def _stub_act(session: Session, params: TurnRequestParams, usage: Usage) -> TurnResult:
    """The stub designer (v0.7.39.6): one talk with the giver (one's own deed — a walk to the next place), by the
    frame's first line; enough for an easy quest of the bot and the playtests."""
    m = _FRAME_HEAD.match(params.input)
    if m is None:
        return TurnResult(turn_id=params.turn_id, narration="Сценарий не собран.", usage=usage)
    quest_id, act, giver, _here, near = m.groups()
    step = ActStep(text="Доложить заказчику", kind="talk", target=giver) if giver else ActStep(text="Осмотреть окрестности", kind="visit", target=near)
    effect = QuestActEffect(quest_id=quest_id, act=int(act), steps=[step])
    v = EngineValidateResult.model_validate(await session.call_engine(
        "engine.validate", EngineValidateParams(turn_id=params.turn_id, effect=effect)))
    if not v.accepted or not v.effect_id:
        return TurnResult(turn_id=params.turn_id, narration=f"Сценарий не собран: {v.reason}", usage=usage)
    return TurnResult(turn_id=params.turn_id, narration="Дело движется дальше.", effect_ids=[v.effect_id], usage=usage)


async def _stub_letter(session: Session, params: TurnRequestParams, usage: Usage) -> TurnResult:
    """The stub answer to a letter (v0.7.48): yes where the engine allows it, else no, else words only."""
    m = re.match(r"\[letter:([^\]]+)\]", params.input)
    if m is None:
        return TurnResult(turn_id=params.turn_id, narration="Ответа нет.", usage=usage)
    for answer in ("yes", "no"):
        v = EngineValidateResult.model_validate(await session.call_engine(
            "engine.validate", EngineValidateParams(turn_id=params.turn_id, effect=LetterReplyEffect(letter_id=m.group(1), answer=answer))))
        if v.accepted and v.effect_id:
            return TurnResult(turn_id=params.turn_id, narration=f"Получил твоё письмо. Ответ: {'да' if answer == 'yes' else 'нет'}.",
                              effect_ids=[v.effect_id], usage=usage)
    return TurnResult(turn_id=params.turn_id, narration="Получил твоё письмо — спасибо, что написал.", usage=usage)


_CANDIDATE = re.compile(r"^- (\S+) — ", re.M)


async def _stub_prepare(session: Session, params: TurnRequestParams, usage: Usage) -> TurnResult:
    """The stub of the second line (0.106.0): a table, a bench and the first two candidates of the frame for a room; an easy
    order with a new giver for a board; an easy quest of the person for a quest."""
    head = prepare_head(params)
    effect: Effect
    if head["subject"] == "furnish":
        props = [PropSpec(name="Стол", body="table"), PropSpec(name="Скамья", body="bench")]
        props += [PropSpec(name=f"Вещь {i + 1}", item_id=item) for i, item in enumerate(_CANDIDATE.findall(params.input)[:2])]
        effect = FurnishEffect(props=props)
    else:
        await session.call_engine("engine.find_quests", EngineFindQuestsParams(turn_id=params.turn_id, query="работа"))
        await session.call_engine("engine.find_npcs", EngineFindNpcsParams(turn_id=params.turn_id, query="заказчик"))
        board = head["subject"] == "board"
        effect = CreateQuestEffect(
            giver="" if board else head.get("giver", ""), board_prop_id=head.get("prop") if board else None,
            title="Пропавшая коза" if board else "Посылка соседу", description="Нужно помочь.", offer_text="Выручишь — не обижу.",
            difficulty="easy", acts=[QuestAct(title="Дело", goal="Сделать, о чём просят")],
            new_npcs=[QuestNpc(key="giver", name="Ольга Козья", role="пастушка", gender="female", faction="brod_folk")] if board else [])
    v = EngineValidateResult.model_validate(await session.call_engine(
        "engine.validate", EngineValidateParams(turn_id=params.turn_id, effect=effect)))
    if not v.accepted or not v.effect_id:
        return TurnResult(turn_id=params.turn_id, narration=f"Не подготовлено: {v.reason}", usage=usage)
    told = "Комната ждёт: стол, скамья и **заготовленные** вещи на своих местах." if head["subject"] == "furnish" else "Подготовлено."
    return TurnResult(turn_id=params.turn_id, narration=told, effect_ids=[v.effect_id], usage=usage)


STUB_EFFECTS: list[Effect | None] = [  # by turn number; the first turns stay plain (protocol tests rely on that)
    HealEffect(tier="minor", reason="заглушка"),
    None,
    None,
    DamageEffect(severity="dangerous", damage_type="колющий", reason="заглушка"),
    CoinsEffect(delta_cp=5, reason="заглушка"),
    ConditionEffect(condition="poisoned", duration="short_rest", reason="заглушка", save={"ability": "con", "dc_tier": "easy"}, tag="poison"),
    DamageEffect(severity="deadly", damage_type="дробящий", reason="заглушка"),
]


def _model_id(session: Session, requested: str | None) -> str:
    model = session.services.models.resolve(requested)
    if model is None:
        raise RpcError(ErrorCode.INVALID_PARAMS, f"model {requested} is not offered by this server")
    if session.services.budget.exhausted():
        raise RpcError(ErrorCode.BUDGET_EXCEEDED)
    return model


async def _with_retries(attempt: Callable[[], Awaitable[T]], retries: int, can_retry: Callable[[], bool]) -> T:
    """OpenRouter 429/5xx and connection errors: up to `retries` repeats with a growing pause (ADR-0009 §6).
    A failed attempt is repeated only while it has not touched the engine yet (no checks or reserved effects),
    so a retry never rerolls a check."""
    for n in range(retries + 1):
        try:
            return await attempt()
        except ModelHTTPError as exc:
            if exc.status_code not in RETRYABLE_HTTP or n == retries or not can_retry():
                log.warning("OpenRouter HTTP %s, giving up", exc.status_code)
                raise RpcError(ErrorCode.LLM_UNAVAILABLE, f"model HTTP {exc.status_code}") from None
            log.info("OpenRouter HTTP %s, retry %d", exc.status_code, n + 1)
        except ModelAPIError as exc:
            if n == retries or not can_retry():
                raise RpcError(ErrorCode.LLM_UNAVAILABLE, str(exc)[:200]) from None
            log.info("OpenRouter unavailable (%s), retry %d", type(exc).__name__, n + 1)
        except (UnexpectedModelBehavior, UsageLimitExceeded) as exc:
            log.warning("invalid model output: %s", str(exc)[:300])
            raise RpcError(ErrorCode.LLM_INVALID_OUTPUT, str(exc)[:200]) from None
        await _sleep(2**n)
    raise AssertionError("unreachable")


def _usage(session: Session, model: str, run_usage: RunUsage, billed: list[float] | None = None) -> Usage:
    """Tokens and cost of a run; the cost goes to the daily budget. `billed` — what OpenRouter charged for each request
    (v0.7.14.5: the real price of the provider that answered); without it, the catalog price of the model."""
    services = session.services
    cost = sum(billed or []) or services.models.cost_usd(model, run_usage.input_tokens, run_usage.output_tokens)
    services.budget.add(cost)
    return Usage(input_tokens=run_usage.input_tokens, output_tokens=run_usage.output_tokens, cost_usd=round(cost, 6),
                 model=model)


@contextlib.contextmanager
def pinned(session: Session, params: TurnRequestParams | SummaryParams | Any) -> Iterator[None]:
    """The provider the player pinned in the settings for this call (v0.7.20.5), for the turn, a summary and an image alike."""
    token = PINNED.set(pinned_for(_model_id(session, params.model), params.provider))
    try:
        yield
    finally:
        PINNED.reset(token)


@contextlib.contextmanager
def bills(session: Session) -> Iterator[list[float]]:
    """What OpenRouter charges for each request inside (v0.7.14.5); on a failure they go to the day's budget all the same
    (v0.8.4.29.7: one place for the turn, a summary and an image's frame)."""
    billed: list[float] = []
    token = REQUEST_COSTS.set(billed)
    try:
        yield billed
    except Exception:
        session.services.budget.add(sum(billed))
        raise
    finally:
        REQUEST_COSTS.reset(token)


async def metered_run(session: Session, model: str, run: Callable[[], Awaitable[Any]]) -> tuple[Any, Usage]:
    """One run of a model as every call of the server pays for it: a repeat on 429/5xx, the bills, the budget; (result, usage)."""
    with bills(session) as billed:
        result = await _with_retries(run, session.services.settings.llm_retries, lambda: True)
    return result, _usage(session, model, result.usage, billed)


def _served_by(result: object) -> str:
    """The OpenRouter provider that answered the last request of the run ("" when unknown), for the trace."""
    try:
        messages = result.all_messages()  # type: ignore[attr-defined]
    except AttributeError:
        return ""
    for m in reversed(messages):  # the last answer of the model (a tool's return comes after it)
        details = getattr(m, "provider_details", None)
        if details:
            return str(details.get("downstream_provider", ""))
    return ""


async def _pick_providers(model: Model) -> None:
    """The cheapest fast OpenRouter providers of the model, refreshed now and then (v0.7.14.4)."""
    if getattr(model, "system", "") == "openrouter":
        await PICKER.refresh(model.model_name)


async def run_agent(model: Model, params: TurnRequestParams, new_ctx: Callable[[], TurnContext]) -> tuple[Any, TurnContext]:
    """One run of the turn's agent (v0.8.4.29.7: the game and the goldens on one road): a fresh context, the usage limits
    of a turn; out of output tokens — it goes on from where it stopped at the agent's raised ceiling (v0.7.4, v0.7.38.1),
    the checks and accepted effects of the turn kept. (result, the context that ran)."""
    agent = agent_for(model, params)
    ctx = new_ctx()
    user_prompt = turn_user_prompt(params)
    with capture_run_messages() as messages:
        try:
            return await agent.run(user_prompt, deps=ctx, usage_limits=TURN_USAGE_LIMITS), ctx
        except UnexpectedModelBehavior as exc:
            if "token limit" not in str(exc).lower():
                raise
    tokens = retry_max_tokens(params)
    log.warning("turn %s ran out of output tokens, going on with %d", params.turn_id, tokens)
    return await agent_for(model, params, tokens).run(None, message_history=messages, deps=ctx, usage_limits=TURN_USAGE_LIMITS), ctx


def next_mode_of(params: TurnRequestParams, out: TurnOutput) -> NextMode | None:
    """The change of mode the master asked: none when it stays where it is (the same mode with the same partner)."""
    if not out.next_mode or (out.next_mode == params.mode and out.npc_id == params.npc_id):
        return None
    return NextMode(mode=out.next_mode, npc_id=out.npc_id if out.next_mode != "exploration" else None)


def picked_options(out: TurnOutput) -> list[tuple[str, int, OptionCheck | None]]:
    """The options the player sees: non-empty, at most three, each with its cost and its check."""
    return [(o.strip(), out.option_costs[i] if i < len(out.option_costs) else 0, _option_check(out.option_checks, i))
            for i, o in enumerate(out.options) if o.strip()][:3]


async def agent_turn(session: Session, params: TurnRequestParams) -> TurnResult:
    with pinned(session, params):
        return await _agent_turn(session, params)


async def _agent_turn(session: Session, params: TurnRequestParams) -> TurnResult:
    services = session.services
    assert services.model_factory is not None
    model = _model_id(session, params.model)
    if params.mode in ("social", "trade") and scene_npc(params, params.npc_id) is None:
        raise RpcError(ErrorCode.INVALID_PARAMS, f"mode {params.mode} needs npc_id of an NPC in the scene")
    system = system_prompt_for(params)
    llm = services.model_factory(model)
    await _pick_providers(llm)
    user_prompt = turn_user_prompt(params)
    checker = llm if services.settings.made_check else None
    ctx = TurnContext(session, params, services.library, model=checker)

    def fresh() -> TurnContext:  # each attempt anew; the last one is the turn's (its checks decide a repeat)
        nonlocal ctx
        ctx = TurnContext(session, params, services.library, model=checker)
        return ctx

    async def attempt():
        return (await run_agent(llm, params, fresh))[0]

    started = time.monotonic()
    trace = {"what": "turn", "turn_id": params.turn_id, "mode": params.mode, "kind": params.kind, "input": params.input,
             "npc_id": params.npc_id, "model": model, "pinned": PINNED.get(), "system": system, "user": user_prompt}
    before = RunUsage()  # the router and a short attempt, paid on top of the full run (v0.7.20.4)
    result = None
    with bills(session) as billed:
        try:
            if not services.settings.router or not turn_kind(params).router:
                raise _NoRouter
            short, before, trace["route"] = await _short_turn(llm, params, user_prompt, trace)
        except _NoRouter:
            short, trace["route"] = None, "full: router off"
        except Exception as exc:  # noqa: BLE001 — the router is a saving, never a failure: the full turn goes on
            log.warning("turn %s: the router failed (%s), the full prompt", params.turn_id, exc)
            short, trace["route"] = None, "full: router error"
        if short is None:
            try:
                result = await _with_retries(attempt, services.settings.llm_retries, lambda: not ctx.check_ids and not ctx.accepted)
            except Exception as exc:
                if services.trace:
                    services.trace.write({**trace, "error": f"{type(exc).__name__}: {exc}", "checks": ctx.check_ids,
                                          "accepted": ctx.accepted, "billed_usd": round(sum(billed), 6), "seconds": round(time.monotonic() - started, 2)})
                raise
    if result is None:
        return _finish(session, params, model, short, before, billed, ctx, trace, started, None)
    return _finish(session, params, model, result.output, before + result.usage + ctx.side_usage, billed, ctx, trace, started, result)


class _NoRouter(Exception):
    pass


async def _short_turn(model: Model, params: TurnRequestParams, user_prompt: str, trace: dict) -> tuple[TurnOutput | None, RunUsage, str]:
    """The router's way (v0.7.20.4): the master's answer with the short prompt, or None — the full prompt is needed."""
    usage = RunUsage()
    route = router.by_kind(params)
    if route == "full":
        return None, usage, "full: kind"
    why = "kind"
    if not route:
        r = await router.build_router_agent(model).run(router.router_prompt(params))
        usage = usage + r.usage
        why = "router"
        if r.output.full:
            return None, usage, "full: router"
    system = router.short_system(params)
    trace["short_system"] = system
    sr = await router.build_short_agent(model, system).run(user_prompt)
    usage = usage + sr.usage
    trace["provider"] = _served_by(sr)
    if not router.short_ok(params, sr.output):
        return None, usage, "full: the short master asked"
    trace["system"] = system  # the prompt that answered
    return router.to_turn_output(sr.output), usage, f"short: {why}"


def _option_check(checks: list[str], i: int) -> OptionCheck | None:
    """«persuasion:medium» of the master into an OptionCheck; a malformed one is dropped (the client checks the skill)."""
    raw = checks[i].strip().lower() if i < len(checks) else ""
    skill, _, tier = raw.partition(":")
    if not re.fullmatch(r"[a-z_]+", skill) or tier not in get_args(DcTier):
        return None
    return OptionCheck(skill=skill, dc_tier=tier)  # type: ignore[arg-type]


def _finish(session: Session, params: TurnRequestParams, model: str, out: TurnOutput, run_usage: RunUsage, billed: list[float],
            ctx: TurnContext, trace: dict, started: float, result: object | None) -> TurnResult:
    services = session.services
    usage = _usage(session, model, run_usage, billed)
    if services.trace:
        services.trace.write({**trace, "messages": services.trace.messages(result) if result is not None else [],
                              "output": out.model_dump(mode="json"), "checks": ctx.check_ids, "accepted": ctx.accepted,
                              "usage": usage.model_dump(mode="json"), "cached_tokens": run_usage.cache_read_tokens,
                              "provider": _served_by(result) if result is not None else trace.get("provider", ""),
                              "seconds": round(time.monotonic() - started, 2)})
    log.info("turn %s mode=%s model=%s tokens=%d/%d cost=$%.5f checks=%d effects=%d/%d %.1fs",
             params.turn_id, params.mode, model, usage.input_tokens, usage.output_tokens, usage.cost_usd,
             len(ctx.check_ids), len(out.effect_ids), len(ctx.accepted), time.monotonic() - started)
    next_mode = next_mode_of(params, out)
    picked = picked_options(out)
    return TurnResult(
        turn_id=params.turn_id,
        narration=out.narration.strip(),
        options=[o for o, _, _ in picked],
        option_costs=[max(0, min(int(c), 100000)) for _, c, _ in picked],
        option_checks=[ch for _, _, ch in picked] if any(ch for _, _, ch in picked) else [],
        effect_ids=[e for e in dict.fromkeys(out.effect_ids) if e in ctx.accepted],
        check_ids=ctx.check_ids,
        next_mode=next_mode,
        usage=usage,
        missing_concept=(out.missing_concept or "").strip()[:200],
    )


async def stub_summary(session: Session, params: SummaryParams) -> SummaryResult:
    return SummaryResult(summary=" ".join(params.events)[:500], usage=Usage(model="stub"))


async def agent_summary(session: Session, params: SummaryParams) -> SummaryResult:
    with pinned(session, params):
        return await _agent_summary(session, params)


async def _agent_summary(session: Session, params: SummaryParams) -> SummaryResult:
    services = session.services
    assert services.model_factory is not None
    model = _model_id(session, params.model)
    await _pick_providers(services.model_factory(model))
    agent = build_summary_agent(services.model_factory(model), params.kind)
    prompt = prompts.summary_prompt(params.kind, params.subject_id, params.previous, params.events)
    result, usage = await metered_run(session, model, lambda: agent.run(prompt))
    if services.trace:
        services.trace.write({"what": "summary", "kind": params.kind, "subject": params.subject_id, "model": model, "prompt": prompt,
                              "summary": result.output.summary, "usage": usage.model_dump(mode="json"),
                              "cached_tokens": result.usage.cache_read_tokens, "provider": _served_by(result)})
    return SummaryResult(summary=result.output.summary.strip(), usage=usage)
