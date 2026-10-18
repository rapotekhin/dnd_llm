"""Turn handlers. Until the Pydantic AI agents land (v0.4.1), the only one is a stub without the LLM.

The stub exercises the full turn path: one active turn, an engine.check callback into Godot, turn.result.
"""

from .protocol import EngineCheckParams, EngineCheckResult, TurnRequestParams, TurnResult, Usage
from .session import Session


async def stub_turn(session: Session, params: TurnRequestParams) -> TurnResult:
    usage = Usage(model=session.settings.model)
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
