"""Protocol messages (ADR-0009). These models are the source of contract/schema/*.json.

Incoming models ignore unknown fields: a newer minor client may send optional fields this server does not know yet.
"""

from enum import IntEnum
from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field

# Semver. While major is 0, a minor bump is breaking too (semver §4), so the handshake compares major.minor.
PROTOCOL_VERSION = "0.4.0"


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


class ModelInfo(_Out):
    id: str
    name: str
    input_usd_per_mtok: float = 0.0
    output_usd_per_mtok: float = 0.0


class Budget(_Out):
    daily_usd: float | None  # None = no limit
    spent_today_usd: float


class HelloResult(_Out):
    protocol_version: str
    server_version: str
    model: str  # the server default
    models: list[ModelInfo] = Field(default_factory=list)  # what the player may pick (server whitelist)
    limits: Limits


class StatusResult(_Out):
    server_version: str
    model: str
    models: list[ModelInfo]
    budget: Budget


# --- snapshot (ADR-0009 §4) ------------------------------------------------------

Mode = Literal["exploration", "social", "trade"]
# deal / haggle (0.4.0): the engine already made the deal or rolled the haggle; `input` holds its fact lines.
TurnKind = Literal["enter", "resume", "action", "rest", "deal", "haggle"]
Gender = Literal["male", "female", "other"]


class Exit(_In):
    room_id: str
    name: str


class SceneNpc(_In):
    npc_id: str
    name: str
    role: str = ""
    race: str = ""
    gender: Gender = "other"
    description: str = ""
    attitude: int = 0  # -3 hostile … 0 neutral … +3 friendly
    personality: str = ""


class Scene(_In):
    location_id: str
    location_name: str
    location_description: str = ""
    room_id: str
    room_name: str
    room_description: str = ""
    exits: list[Exit] = Field(default_factory=list)
    npcs: list[SceneNpc] = Field(default_factory=list)
    hooks: list[str] = Field(default_factory=list)  # hints of hidden things, never the hidden things themselves
    flags: list[str] = Field(default_factory=list)
    found: list[str] = Field(default_factory=list)  # hidden things the player noticed or found here (0.3.0)
    time_of_day: str = ""


class InventoryLine(_In):
    item_id: str
    name: str
    qty: int = 1


class SpellSlots(_In):
    level: int
    left: int
    max: int


class CharacterSheet(_In):
    """The sheet in final numbers (ADR-0009 §4). Fields after `features` came in 0.2.1 (the 5e character, v0.5.0);
    a feature's or spell's text is behind engine.lookup."""

    name: str
    gender: Gender = "other"
    race: str = ""
    class_name: str = ""
    level: int = 1
    hp: int
    max_hp: int
    ac: int
    conditions: list[str] = Field(default_factory=list)
    skills: dict[str, int] = Field(default_factory=dict)  # total bonuses
    saves: dict[str, int] = Field(default_factory=dict)
    gold_cp: int = 0
    inventory: list[InventoryLine] = Field(default_factory=list)
    features: list[str] = Field(default_factory=list)
    background: str = ""
    abilities: dict[str, int] = Field(default_factory=dict)  # scores, str..cha
    proficiency_bonus: int = 2
    skill_proficiencies: list[str] = Field(default_factory=list)
    speed: int = 30
    equipped: list[str] = Field(default_factory=list)  # names of worn armor and wielded items
    cantrips: list[str] = Field(default_factory=list)
    spells: list[str] = Field(default_factory=list)  # prepared (or known) spells of circle 1+, by name
    spell_slots: list[SpellSlots] = Field(default_factory=list)
    spell_save_dc: int | None = None
    backstory: str = ""  # the player's or the ready-made character's story (0.2.2)


class HistoryLine(_In):
    role: Literal["player", "dm", "npc"]
    text: str


class TurnLimits(_In):
    max_checks: int = 1
    max_effects: int = 3


DmStyle = Literal["classic", "literary", "dry", "ironic"]
Violence = Literal["mild", "medium", "graphic"]


class WorldInfo(_In):
    """The world pack and the master settings of the game (0.2.2, ADR-0010 §1, §3)."""

    name: str = ""
    lore: str = ""
    tone: str = ""
    magic: str = ""
    dm_style: DmStyle = "classic"
    violence: Violence = "medium"
    lines: list[str] = Field(default_factory=list)  # never in the game
    veils: list[str] = Field(default_factory=list)  # may happen, off screen


class TradeLine(_In):
    item_id: str
    name: str
    qty: int
    price_cp: int  # per item, already with attitude and haggling


class TradeInfo(_In):
    """Trade mode (0.4.0): the merchant's state as the engine keeps it. Deals go through the player's deal panel."""

    npc_id: str
    purse_cp: int = 0
    haggle_pct: int = 0  # won for this visit: −pct on buying, +pct on selling
    haggle_locked: bool = False  # a haggle failed today
    stock: list[TradeLine] = Field(default_factory=list)  # what the merchant sells
    buys: list[TradeLine] = Field(default_factory=list)  # the player's things and what the merchant pays


class Snapshot(_In):
    world: WorldInfo | None = None
    scene: Scene | None = None
    character: CharacterSheet | None = None
    history: list[HistoryLine] = Field(default_factory=list)
    summaries: dict[str, str] = Field(default_factory=dict)  # "location", "dialogue:<npc_id>"
    limits: TurnLimits = Field(default_factory=TurnLimits)
    trade: TradeInfo | None = None  # only in trade mode (0.4.0)


# --- turn.* -----------------------------------------------------------------


class TurnRequestParams(_In):
    turn_id: str = Field(pattern=r"^t-\d+$")
    mode: Mode
    kind: TurnKind
    input: str = ""
    npc_id: str | None = None  # the conversation partner in social / trade
    model: str | None = None  # the player's pick from HelloResult.models; None = server default
    snapshot: Snapshot = Field(default_factory=Snapshot)


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


# --- summary.* ------------------------------------------------------------------


class SummaryParams(_In):
    kind: Literal["location", "dialogue", "npc_memory"]
    subject_id: str
    previous: str = ""
    events: list[str] = Field(min_length=1)
    model: str | None = None


class SummaryResult(_Out):
    summary: str
    usage: Usage


# --- effects (ADR-0008 §3) ------------------------------------------------------

DamageSeverity = Literal["unpleasant", "dangerous", "deadly"]
HealTier = Literal["minor", "moderate", "major"]
Rarity = Literal["common", "uncommon", "rare", "very_rare", "legendary"]
ItemType = Literal["weapon", "armor", "gear", "consumable", "treasure"]
# Mechanical properties the engine understands (ADR-0008 §6); free text never carries mechanics.
# Keep in sync with game/data/items.json "properties" (a test checks it).
ItemProperty = Literal[
    "finesse", "light", "heavy", "two_handed", "versatile", "thrown", "reach", "ammunition",
    "silvered", "magic_plus1", "magic_plus2", "magic_plus3",
    "fire_damage", "cold_damage", "lightning_damage", "radiant_damage", "necrotic_damage", "poison_damage",
    "resist_fire", "resist_cold", "resist_poison", "ac_plus1", "ac_plus2",
    "light_source", "healing", "cursed",
]


class GeneratedItem(_Out):
    name: str
    item_type: ItemType
    base: str | None = None  # catalog item_id it is based on
    rarity: Rarity
    value_cp: int = Field(ge=0)
    properties: list[ItemProperty] = Field(default_factory=list)
    description: str = ""


class MoveEffect(_Out):
    kind: Literal["move"] = "move"
    room_id: str


class DamageEffect(_Out):
    kind: Literal["damage"] = "damage"
    severity: DamageSeverity
    damage_type: str
    reason: str


class HealEffect(_Out):
    kind: Literal["heal"] = "heal"
    tier: HealTier
    reason: str


class CoinsEffect(_Out):
    kind: Literal["coins"] = "coins"
    delta_cp: int  # + reward, - payment
    reason: str


class GiveItemEffect(_Out):
    kind: Literal["give_item"] = "give_item"
    item_id: str | None = None  # an existing catalog/library item
    item: GeneratedItem | None = None  # or a new one (only after engine.find_items in the same turn)
    qty: int = Field(default=1, ge=1, le=20)


class TakeItemEffect(_Out):
    kind: Literal["take_item"] = "take_item"
    item_id: str
    qty: int = Field(default=1, ge=1, le=20)


class NpcAttitudeEffect(_Out):
    kind: Literal["npc_attitude"] = "npc_attitude"
    npc_id: str
    delta: int = Field(ge=-2, le=2)
    reason: str


class FlagEffect(_Out):
    kind: Literal["flag"] = "flag"
    flag: str = Field(pattern=r"^[a-z][a-z0-9_]{1,40}$")
    value: bool = True


Effect = Annotated[
    MoveEffect | DamageEffect | HealEffect | CoinsEffect | GiveItemEffect | TakeItemEffect | NpcAttitudeEffect | FlagEffect,
    Field(discriminator="kind"),
]


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
    revealed: list[str] = Field(default_factory=list)  # hidden things this successful search found (0.3.0)
    note: str = ""  # engine facts for the master, e.g. the outcome of a haggle (0.4.0)


class EngineValidateParams(_Out):
    turn_id: str
    effect: Effect


class EngineValidateResult(_In):
    accepted: bool
    effect_id: str | None = None
    reason: str = ""  # why rejected, for the model
    summary: str = ""  # what was reserved, e.g. "−7 HP (2d10 колющий)"
    item_id: str | None = None  # id the engine gave a newly created item


LookupKind = Literal["rule", "spell", "feature", "condition", "item", "npc"]


class EngineLookupParams(_Out):
    turn_id: str
    kind: LookupKind
    id: str


class EngineLookupResult(_In):
    found: bool
    data: dict[str, object] = Field(default_factory=dict)


class EngineFindItemsParams(_Out):
    turn_id: str
    query: str
    base: str | None = None
    properties: list[ItemProperty] = Field(default_factory=list)


class FoundItem(_In):
    item_id: str
    name: str
    item_type: str = ""
    rarity: str = "common"
    value_cp: int = 0
    properties: list[str] = Field(default_factory=list)
    source: str = "catalog"  # catalog | library


class EngineFindItemsResult(_In):
    items: list[FoundItem] = Field(default_factory=list)


# Schemas exported to contract/ (name -> model).
CONTRACT_MODELS: dict[str, type[BaseModel]] = {
    "error_data": ErrorData,
    "session.hello.params": HelloParams,
    "session.hello.result": HelloResult,
    "session.status.result": StatusResult,
    "turn.request.params": TurnRequestParams,
    "turn.request.result": TurnResult,
    "turn.cancel.params": TurnCancelParams,
    "turn.cancel.result": OkResult,
    "summary.request.params": SummaryParams,
    "summary.request.result": SummaryResult,
    "engine.check.params": EngineCheckParams,
    "engine.check.result": EngineCheckResult,
    "engine.validate.params": EngineValidateParams,
    "engine.validate.result": EngineValidateResult,
    "engine.lookup.params": EngineLookupParams,
    "engine.lookup.result": EngineLookupResult,
    "engine.find_items.params": EngineFindItemsParams,
    "engine.find_items.result": EngineFindItemsResult,
}
