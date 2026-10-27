"""Turn and summary handlers.

- `agent_turn`: one Pydantic AI run over OpenRouter per turn (ADR-0009), tools → engine.*.
- `stub_turn`: no LLM — protocol tests and UI work without money (LLM_SERVER_TURN_HANDLER=stub).
"""

import asyncio
import logging
import re
import time
from collections.abc import Awaitable, Callable
from typing import TypeVar, get_args

from pydantic_ai.exceptions import ModelAPIError, ModelHTTPError, UnexpectedModelBehavior, UsageLimitExceeded
from pydantic_ai.models import Model
from pydantic_ai.usage import RunUsage, UsageLimits

from . import prompts, router
from .llm.catalog import REQUEST_COSTS
from .llm.providers import PICKER, PINNED, pinned_for
from .agents import RETRY_MAX_TOKENS, TurnContext, TurnOutput, build_summary_agent, build_turn_agent, is_entry, scene_npc, system_prompt_for, turn_user_prompt
from .protocol import (
    DcTier,
    OptionCheck,
    CoinsEffect,
    ConditionEffect,
    DamageEffect,
    Effect,
    EngineValidateParams,
    EngineValidateResult,
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
    if params.kind in ("deal", "haggle", "quest", "ability", "downed", "combat_start", "combat_round", "death", "law"):
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


async def agent_turn(session: Session, params: TurnRequestParams) -> TurnResult:
    token = PINNED.set(pinned_for(_model_id(session, params.model), params.provider))  # v0.7.20.5
    try:
        return await _agent_turn(session, params)
    finally:
        PINNED.reset(token)


async def _agent_turn(session: Session, params: TurnRequestParams) -> TurnResult:
    services = session.services
    assert services.model_factory is not None
    model = _model_id(session, params.model)
    if params.mode in ("social", "trade") and scene_npc(params, params.npc_id) is None:
        raise RpcError(ErrorCode.INVALID_PARAMS, f"mode {params.mode} needs npc_id of an NPC in the scene")
    system = system_prompt_for(params)
    await _pick_providers(services.model_factory(model))
    agent = build_turn_agent(services.model_factory(model), system, entry=is_entry(params))
    user_prompt = turn_user_prompt(params)
    ctx = TurnContext(session, params, services.library)

    async def attempt():
        nonlocal ctx, agent
        ctx = TurnContext(session, params, services.library)
        try:
            return await agent.run(user_prompt, deps=ctx, usage_limits=TURN_USAGE_LIMITS)
        except UnexpectedModelBehavior as exc:
            # Out of output tokens (v0.7.4: the fight start in the burrow failed at 1500): once more with room to
            # spare, while the engine is untouched — the player sees no error.
            if "token limit" not in str(exc).lower() or ctx.check_ids or ctx.accepted:
                raise
            log.warning("turn %s ran out of output tokens, retrying with %d", params.turn_id, RETRY_MAX_TOKENS)
            agent = build_turn_agent(services.model_factory(model), system, RETRY_MAX_TOKENS, entry=is_entry(params))
            ctx = TurnContext(session, params, services.library)
            return await agent.run(user_prompt, deps=ctx, usage_limits=TURN_USAGE_LIMITS)

    started = time.monotonic()
    trace = {"what": "turn", "turn_id": params.turn_id, "mode": params.mode, "kind": params.kind, "input": params.input,
             "npc_id": params.npc_id, "model": model, "pinned": PINNED.get(), "system": system, "user": user_prompt}
    billed: list[float] = []
    token = REQUEST_COSTS.set(billed)
    before = RunUsage()  # the router and a short attempt, paid on top of the full run (v0.7.20.4)
    try:
        if not services.settings.router:
            raise _NoRouter
        short, before, trace["route"] = await _short_turn(services.model_factory(model), params, user_prompt, trace)
    except _NoRouter:
        short, trace["route"] = None, "full: router off"
    except Exception as exc:  # noqa: BLE001 — the router is a saving, never a failure: the full turn goes on
        log.warning("turn %s: the router failed (%s), the full prompt", params.turn_id, exc)
        short, trace["route"] = None, "full: router error"
    if short is not None:
        REQUEST_COSTS.reset(token)
        return _finish(session, params, model, short, before, billed, ctx, trace, started, None)
    try:
        result = await _with_retries(attempt, services.settings.llm_retries, lambda: not ctx.check_ids and not ctx.accepted)
    except Exception as exc:
        services.budget.add(sum(billed))  # the requests before the failure are paid all the same
        if services.trace:
            services.trace.write({**trace, "error": f"{type(exc).__name__}: {exc}", "checks": ctx.check_ids,
                                  "accepted": ctx.accepted, "billed_usd": round(sum(billed), 6), "seconds": round(time.monotonic() - started, 2)})
        raise
    finally:
        REQUEST_COSTS.reset(token)
    return _finish(session, params, model, result.output, before + result.usage, billed, ctx, trace, started, result)


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
                              "usage": usage.model_dump(mode="json"), "provider": _served_by(result) if result is not None else "",
                              "seconds": round(time.monotonic() - started, 2)})
    log.info("turn %s mode=%s model=%s tokens=%d/%d cost=$%.5f checks=%d effects=%d/%d %.1fs",
             params.turn_id, params.mode, model, usage.input_tokens, usage.output_tokens, usage.cost_usd,
             len(ctx.check_ids), len(out.effect_ids), len(ctx.accepted), time.monotonic() - started)
    next_mode = None
    if out.next_mode and not (out.next_mode == params.mode and out.npc_id == params.npc_id):
        next_mode = NextMode(mode=out.next_mode, npc_id=out.npc_id if out.next_mode != "exploration" else None)
    picked = [(o.strip(), out.option_costs[i] if i < len(out.option_costs) else 0, _option_check(out.option_checks, i))
              for i, o in enumerate(out.options) if o.strip()][:3]
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
    token = PINNED.set(pinned_for(_model_id(session, params.model), params.provider))  # v0.7.20.5
    try:
        return await _agent_summary(session, params)
    finally:
        PINNED.reset(token)


async def _agent_summary(session: Session, params: SummaryParams) -> SummaryResult:
    services = session.services
    assert services.model_factory is not None
    model = _model_id(session, params.model)
    await _pick_providers(services.model_factory(model))
    agent = build_summary_agent(services.model_factory(model), params.kind)
    prompt = prompts.summary_prompt(params.kind, params.subject_id, params.previous, params.events)
    billed: list[float] = []
    token = REQUEST_COSTS.set(billed)
    try:
        result = await _with_retries(lambda: agent.run(prompt), services.settings.llm_retries, lambda: True)
    except Exception:
        services.budget.add(sum(billed))
        raise
    finally:
        REQUEST_COSTS.reset(token)
    usage = _usage(session, model, result.usage, billed)
    if services.trace:
        services.trace.write({"what": "summary", "kind": params.kind, "subject": params.subject_id, "model": model, "prompt": prompt,
                              "summary": result.output.summary, "usage": usage.model_dump(mode="json")})
    return SummaryResult(summary=result.output.summary.strip(), usage=usage)
