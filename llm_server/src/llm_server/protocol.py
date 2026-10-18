"""Protocol messages (ADR-0009). These models are the source of contract/schema/*.json.

Incoming models ignore unknown fields: a newer minor client may send optional fields this server does not know yet.
"""

from enum import IntEnum
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field

# Semver. While major is 0, a minor bump is breaking too (semver §4), so the handshake compares major.minor.
PROTOCOL_VERSION = "0.1.0"


def protocol_compatible(client: str, server: str = PROTOCOL_VERSION) -> bool:
    try:
        c_major, c_minor, *_ = (int(p) for p in client.split("."))
        s_major, s_minor, *_ = (int(p) for p in server.split("."))
    except ValueError:
        return False
    if c_major != s_major:
        return False
    return c_major != 0 or c_minor == s_minor


class ErrorCode(IntEnum):
    PARSE_ERROR = -32700
    INVALID_REQUEST = -32600
    METHOD_NOT_FOUND = -32601
    INVALID_PARAMS = -32602
    INTERNAL_ERROR = -32603
    VERSION_MISMATCH = -32001
    NOT_INITIALIZED = -32002
    TURN_IN_PROGRESS = -32010
    TURN_CANCELLED = -32011
    TURN_TIMEOUT = -32012
    LLM_UNAVAILABLE = -32020
    LLM_INVALID_OUTPUT = -32021
    BUDGET_EXCEEDED = -32030
    SERVER_BUSY = -32031
    ENGINE_TIMEOUT = -32040
    ENGINE_ERROR = -32041


RETRYABLE = {
    ErrorCode.TURN_IN_PROGRESS,
    ErrorCode.TURN_CANCELLED,
    ErrorCode.TURN_TIMEOUT,
    ErrorCode.LLM_UNAVAILABLE,
    ErrorCode.LLM_INVALID_OUTPUT,
    ErrorCode.SERVER_BUSY,
    ErrorCode.ENGINE_TIMEOUT,
}


class _In(BaseModel):
    model_config = ConfigDict(extra="ignore")


class _Out(BaseModel):
    model_config = ConfigDict(extra="forbid")


class ErrorData(_Out):
    reason: str
    retryable: bool


# --- session.* ---------------------------------------------------------------


class HelloParams(_In):
    protocol_version: str
    client_version: str


class Limits(_Out):
    max_message_bytes: int
    turn_timeout_s: float
    engine_timeout_s: float
    hello_timeout_s: float
    max_checks_per_turn: int = 1  # ADR-0008 §4
    max_effects_per_turn: int = 3


class HelloResult(_Out):
    protocol_version: str
    server_version: str
    model: str
    limits: Limits


# --- turn.* -----------------------------------------------------------------

Mode = Literal["exploration", "social", "trade"]
TurnKind = Literal["enter", "resume", "action"]


class TurnRequestParams(_In):
    turn_id: str = Field(pattern=r"^t-\d+$")
    mode: Mode
    kind: TurnKind
    input: str = ""
    snapshot: dict[str, Any] = Field(default_factory=dict)  # typed snapshot comes with v0.4.1


class TurnCancelParams(_In):
    turn_id: str


class NextMode(_Out):
    mode: Mode
    npc_id: str | None = None


class Usage(_Out):
    input_tokens: int = 0
    output_tokens: int = 0
    cost_usd: float = 0.0
    model: str
    daily_budget_left_usd: float | None = None


class TurnResult(_Out):
    turn_id: str
    narration: str
    options: list[str] = Field(default_factory=list, max_length=3)
    effect_ids: list[str] = Field(default_factory=list)
    check_ids: list[str] = Field(default_factory=list)
    next_mode: NextMode | None = None
    usage: Usage


class OkResult(_Out):
    ok: bool = True


# --- engine.* (backend -> Godot) ---------------------------------------------

DcTier = Literal["very_easy", "easy", "medium", "hard", "very_hard", "nearly_impossible"]


class EngineCheckParams(_Out):
    turn_id: str
    skill: str | None = None
    save: str | None = None
    dc_tier: DcTier
    target_id: str | None = None
    advantage_reason: str | None = None


class EngineCheckResult(_In):
    check_id: str
    rolls: list[int]
    bonus: int
    total: int
    dc: int
    success: bool
    nat: int
    blocked: bool = False


# Schemas exported to contract/ (name -> model).
CONTRACT_MODELS: dict[str, type[BaseModel]] = {
    "error_data": ErrorData,
    "session.hello.params": HelloParams,
    "session.hello.result": HelloResult,
    "turn.request.params": TurnRequestParams,
    "turn.request.result": TurnResult,
    "turn.cancel.params": TurnCancelParams,
    "turn.cancel.result": OkResult,
    "engine.check.params": EngineCheckParams,
    "engine.check.result": EngineCheckResult,
}
