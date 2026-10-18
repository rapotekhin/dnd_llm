"""Turn and summary handlers.

- `agent_turn`: one Pydantic AI run over OpenRouter per turn (ADR-0009), tools → engine.*.
- `stub_turn`: no LLM — protocol tests and UI work without money (LLM_SERVER_TURN_HANDLER=stub).
"""

import asyncio
import logging
import time
from collections.abc import Awaitable, Callable
from typing import TypeVar

from pydantic_ai.exceptions import ModelAPIError, ModelHTTPError, UnexpectedModelBehavior, UsageLimitExceeded
from pydantic_ai.usage import RunUsage, UsageLimits

from . import prompts
from .agents import TurnContext, build_summary_agent, build_turn_agent, scene_npc, system_prompt_for, turn_user_prompt
from .protocol import (
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
TURN_USAGE_LIMITS = UsageLimits(request_limit=10)
RETRYABLE_HTTP = {408, 409, 425, 429, 500, 502, 503, 504}
_sleep = asyncio.sleep  # tests replace it to skip the pauses


async def stub_turn(session: Session, params: TurnRequestParams) -> TurnResult:
    usage = Usage(model="stub")
    if params.kind in ("deal", "haggle", "quest"):
        return TurnResult(turn_id=params.turn_id, narration=f"Готово. ({params.input})", usage=usage)
    if params.kind != "action":
        return TurnResult(turn_id=params.turn_id, narration="Вы осматриваетесь.", usage=usage)

    raw = await session.call_engine(
        "engine.check",
        EngineCheckParams(turn_id=params.turn_id, skill="perception", dc_tier="medium"),
    )
    check = EngineCheckResult.model_validate(raw)
    outcome = "замечаете" if check.success else "не замечаете"
    return TurnResult(
        turn_id=params.turn_id,
        narration=f"Вы {outcome} что-то необычное ({check.total} против {check.dc}).",
        options=["Осмотреться ещё раз"],
        check_ids=[check.check_id],
        usage=usage,
    )


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


def _usage(session: Session, model: str, run_usage: RunUsage) -> Usage:
    services = session.services
    cost = float(getattr(run_usage, "cost", 0) or 0) or services.models.cost_usd(model, run_usage.input_tokens, run_usage.output_tokens)
    services.budget.add(cost)
    return Usage(input_tokens=run_usage.input_tokens, output_tokens=run_usage.output_tokens, cost_usd=round(cost, 6),
                 model=model, daily_budget_left_usd=services.budget.left())


async def agent_turn(session: Session, params: TurnRequestParams) -> TurnResult:
    services = session.services
    assert services.model_factory is not None
    model = _model_id(session, params.model)
    if params.mode != "exploration" and scene_npc(params, params.npc_id) is None:
        raise RpcError(ErrorCode.INVALID_PARAMS, f"mode {params.mode} needs npc_id of an NPC in the scene")
    agent = build_turn_agent(services.model_factory(model), system_prompt_for(params))
    user_prompt = turn_user_prompt(params)
    ctx = TurnContext(session, params, services.library)

    async def attempt():
        nonlocal ctx
        ctx = TurnContext(session, params, services.library)
        return await agent.run(user_prompt, deps=ctx, usage_limits=TURN_USAGE_LIMITS)

    started = time.monotonic()
    result = await _with_retries(attempt, services.settings.llm_retries, lambda: not ctx.check_ids and not ctx.accepted)
    out = result.output
    usage = _usage(session, model, result.usage)
    log.info("turn %s mode=%s model=%s tokens=%d/%d cost=$%.5f checks=%d effects=%d/%d %.1fs",
             params.turn_id, params.mode, model, usage.input_tokens, usage.output_tokens, usage.cost_usd,
             len(ctx.check_ids), len(out.effect_ids), len(ctx.accepted), time.monotonic() - started)
    next_mode = None
    if out.next_mode and not (out.next_mode == params.mode and out.npc_id == params.npc_id):
        next_mode = NextMode(mode=out.next_mode, npc_id=out.npc_id if out.next_mode != "exploration" else None)
    return TurnResult(
        turn_id=params.turn_id,
        narration=out.narration.strip(),
        options=[o.strip() for o in out.options if o.strip()][:3],
        effect_ids=[e for e in dict.fromkeys(out.effect_ids) if e in ctx.accepted],
        check_ids=ctx.check_ids,
        next_mode=next_mode,
        usage=usage,
    )


async def stub_summary(session: Session, params: SummaryParams) -> SummaryResult:
    return SummaryResult(summary=" ".join(params.events)[:500], usage=Usage(model="stub"))


async def agent_summary(session: Session, params: SummaryParams) -> SummaryResult:
    services = session.services
    assert services.model_factory is not None
    model = _model_id(session, params.model)
    agent = build_summary_agent(services.model_factory(model), params.kind)
    prompt = prompts.summary_prompt(params.kind, params.subject_id, params.previous, params.events)
    result = await _with_retries(lambda: agent.run(prompt), services.settings.llm_retries, lambda: True)
    return SummaryResult(summary=result.output.summary.strip(), usage=_usage(session, model, result.usage))
