"""Protocol messages (ADR-0009). These models are the source of contract/schema/*.json.

Incoming models ignore unknown fields: a newer minor client may send optional fields this server does not know yet.
"""

from enum import IntEnum
from typing import Annotated, Literal

from pydantic import AfterValidator, BeforeValidator, BaseModel, ConfigDict, Field, model_validator

# Semver. While major is 0, a minor bump is breaking too (semver §4), so the handshake compares major.minor.
PROTOCOL_VERSION = "0.70.0"


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


class ProviderInfo(_Out):
    """An OpenRouter provider the player may pin the model to (0.35.0); every one of the model with its prices and our
    measured speed (0.67.0)."""

    tag: str
    name: str
    input_usd_per_mtok: float = 0.0
    output_usd_per_mtok: float = 0.0
    cache_usd_per_mtok: float | None = None  # None — no cache price
    usd_per_1000_turns: float = 0.0  # a typical turn of ours, with the cache and our bills; 0 — not known
    bill_factor: float = 1.0  # billed ÷ list price over our last days
    tokens_per_s: float = 0.0  # median of our own requests; 0 — not measured
    uptime: float | None = None  # % of the last day
    quantization: str = ""
    picked: bool = False  # among the server's picks for «Авто» now


class ModelInfo(_Out):
    id: str
    name: str
    input_usd_per_mtok: float = 0.0
    output_usd_per_mtok: float = 0.0
    providers: list[ProviderInfo] = Field(default_factory=list)  # empty — OpenRouter picks (0.35.0)


class Budget(_Out):
    daily_usd: float | None  # None = no limit
    spent_today_usd: float


class HelloResult(_Out):
    protocol_version: str
    server_version: str
    model: str  # the server default
    models: list[ModelInfo] = Field(default_factory=list)  # what the player may pick (server whitelist)
    limits: Limits


class SetBudgetParams(_In):
    """The daily spending limit from the game's settings (0.13.0); None = no limit. Answered with the status."""

    daily_usd: float | None = Field(default=None, gt=0, le=1000)


class StatusResult(_Out):
    server_version: str
    model: str
    models: list[ModelInfo]
    budget: Budget


# --- snapshot (ADR-0009 §4) ------------------------------------------------------

Mode = Literal["exploration", "social", "trade", "combat"]
# deal / haggle (0.4.0): the engine already made the deal or rolled the haggle; `input` holds its fact lines.
# quest (0.5.0): the engine completed a pack quest and gave the reward; `input` is what happened and the reward.
# ability (0.6.0): the player cast a spell, used a feature or an item by a button — the engine applied it.
# downed (0.6.0): the character dropped to 0 HP outside combat and came to with 1 HP; the master tells the cost.
# combat_start / combat_round / death (0.7.0): the engine started the fight, played a round (or ended it), the hero died;
# `input` holds the engine lines. trap (0.9.0): the player disarmed a found trap (or it went off); the engine lines.
# wait (0.10.0): the player waited by the button — the engine moved the time; `input` holds the lines.
# theft (0.11.0): the player picked a pocket in the theft window — the engine rolled and applied it; `input` holds the lines.
TurnKind = Literal["enter", "resume", "action", "rest", "deal", "haggle", "quest", "ability", "downed",
                   "combat_start", "combat_round", "death", "trap", "wait", "theft", "law", "goal", "shift"]
Gender = Literal["male", "female", "other"]


class Exit(_In):
    room_id: str
    name: str
    door: str = ""  # 0.51.0: «дверь (дерево) · заперта до 08:00 — часы объекта»; empty — no door


class SceneNpc(_In):
    npc_id: str
    name: str
    role: str = ""
    race: str = ""
    body: str = ""  # 0.43.0: «средних лет, коренастый, невысокий»
    gender: Gender = "other"
    description: str = ""
    attitude: int = 0  # -3 hostile … 0 neutral … +3 friendly
    personality: str = ""
    trader: bool = False  # sells goods: buying them goes through trade mode (0.6.0)
    speaks: str = ""  # the NPC's languages, Russian: «общий, дварфийский» (0.17.0)
    understands_hero: bool = True  # shares a tongue with the hero (or a spell bridges it) (0.17.0)
    tie: str = ""  # the NPC's tie with the hero's background: «служивый: уважает звание героя-солдата» (0.17.0)
    memory: list[str] = Field(default_factory=list)  # what the NPC remembers of the hero: «день 2 — …» (0.20.0)
    services: list[str] = Field(default_factory=list)  # «опознание вещей [identify]» — for npc_favor (0.21.0)
    deal: str = ""  # what the NPC granted by words: «скидка герою 10% до дня 9» (0.21.0)
    secrets: list[str] = Field(default_factory=list)  # untold secrets as hints: «[cellar] нервничает из-за погреба — …» (0.22.0)
    refuses: bool = False  # hostile: will not talk or trade (0.22.0)
    eager: bool = False  # a close friend: offers help by itself (0.22.0)
    follows: bool = False  # goes with the hero from room to room (0.33.0)
    under: str = ""  # 0.42.0: the hero's spells on it and until when — «Очарование личности — до 10:35»


class SceneProp(_In):
    """A thing of the room (0.11.0): what the master may describe and the player may act on."""

    prop_id: str
    name: str
    description: str = ""
    state: str = ""  # "" | open | closed | broken | burned | moved
    owner: str | None = None  # npc_id of whoever owns it
    portable: bool = False  # can be taken (it is an item of the catalog)
    text: str = ""  # what is written in or on it
    container: str = ""  # 0.28.0: a container — its kind («сундук», «шкаф»); its contents below
    locked: bool = False  # 0.28.0: locked — a key, thieves' tools or force (effect unlock)
    contents: str = ""  # 0.28.0: «Кинжал ×2 [dagger], Свеча [candle]» — what lies inside
    source: str = ""  # 0.70.0: water | foul_water — water is drawn here


class Scene(_In):
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
    sneaking: bool = False  # the player moves stealthily (0.8.0)
    props: list[SceneProp] = Field(default_factory=list)  # the things of the room — the only ones to describe (0.11.0)
    creatures: list[str] = Field(default_factory=list)  # 0.45.0: foes a fight left here — «Гоблин 2 [c3] — сдался, связан»
    furnish: bool = False  # the room was never furnished: propose `furnish` before describing it (0.11.0)
    closed_exits: list[str] = Field(default_factory=list)  # ways the pack keeps shut until the engine opens them (0.14.0)
    notes: list[str] = Field(default_factory=list)  # the master's own memory of events here, in Russian (0.14.0)
    chronicle: list[str] = Field(default_factory=list)  # the last facts of the engine: «день 2, 09:12, Таверна — …» (0.19.0)
    reputation: str = ""  # the hero's name in this settlement: «Ольховый Брод — свой (+1)» (0.24.0)
    open_edges: list[str] = Field(default_factory=list)  # where the pack lets the master draw new places (0.32.0)
    summons: list[str] = Field(default_factory=list)  # 0.49.0: creatures a spell called to go with the hero — «Волк 1 (Призыв зверей, до конца концентрации)»
    site_name: str = ""  # 0.50.0: the site of the room (a building, a yard) — «Таверна «Хромой олень»»
    site_description: str = ""
    site_owner: str = ""  # its owner's name, if any
    private: bool = False  # the room is not for anyone to walk into (a kitchen, a bedroom)


class InventoryLine(_In):
    item_id: str
    name: str
    qty: int = 1


class SpellSlots(_In):
    level: int
    left: int
    max: int


class ResourceLine(_In):
    name: str
    left: int
    max: int


class CharacterSheet(_In):
    """The sheet in final numbers (ADR-0009 §4). Fields after `features` came in 0.2.1 (the 5e character, v0.5.0);
    a feature's or spell's text is behind engine.lookup."""

    name: str
    gender: Gender = "other"
    race: str = ""
    body: str = ""  # 0.43.0: the hero's age, build and height in words
    class_name: str = ""
    level: int = 1
    hp: int
    max_hp: int
    ac: int
    conditions: list[str] = Field(default_factory=list)
    skills: dict[str, int] = Field(default_factory=dict)  # total bonuses
    gold_cp: int = 0
    reward_left_cp: int | None = None  # what the master may still give until the long rest, cp (0.19.0)
    bags: list[str] = Field(default_factory=list)  # the hero's bags and what is in them: «Рюкзак [bag1]: Верёвка [rope]» (0.29.0)
    development: list[str] = Field(default_factory=list)  # peaceful development: «Торговля 2: Глаз оценщика» (0.30.0)
    goal: str = ""  # the hero's life goal with its assessment: ««…» — трудная, рано: уровень класса 1 из 3» (0.39.0)
    inventory: list[InventoryLine] = Field(default_factory=list)
    features: list[str] = Field(default_factory=list)
    background: str = ""
    abilities: dict[str, int] = Field(default_factory=dict)  # scores, str..cha
    skill_proficiencies: list[str] = Field(default_factory=list)
    speed: int = 30
    equipped: list[str] = Field(default_factory=list)  # names of worn armor and wielded items
    cantrips: list[str] = Field(default_factory=list)
    spells: list[str] = Field(default_factory=list)  # prepared (or known) spells of circle 1+, by name
    spell_slots: list[SpellSlots] = Field(default_factory=list)
    spell_save_dc: int | None = None
    backstory: str = ""  # the player's or the ready-made character's story (0.2.2)
    resources: list[ResourceLine] = Field(default_factory=list)  # feature uses left (0.6.0)
    concentration: str = ""  # the spell the character concentrates on
    effects: list[str] = Field(default_factory=list)  # conditions and boons with time left and cause, in Russian (0.16.0)
    exhaustion: int = 0  # exhaustion level 0-6 (0.16.0)
    resistances: list[str] = Field(default_factory=list)  # damage types the hero resists now, Russian (0.16.0)
    background_feature: str = ""  # the background's feature as a rule for the master (0.17.0)
    languages: list[str] = Field(default_factory=list)  # the hero's languages, Russian, secret ones included (0.17.0)
    tools: list[str] = Field(default_factory=list)  # tool proficiencies: «Воровские инструменты [thieves_tools]» (0.17.0)
    attuned: list[str] = Field(default_factory=list)  # magic items the hero is attuned to, Russian names (0.18.0)
    craft: str = ""  # 0.56.0: the recipes the hero knows and the work in hand («Ремесло (окно «Ремесло»): …»)
    jobs: str = ""  # 0.58.0: where the hero works, the rank and shifts («Работа (кнопка «Смена» …): …»)
    property: str = ""  # 0.59.0: the hero's places and beasts, what is on sale here («Имущество (…): …»)
    bank: str = ""  # 0.60.0: the hero's deposits, loans and vaults, the banks of the scene («Банк (…): …»)
    shop: str = ""  # 0.61.0: the hero's charters, shelves and merchant's name, the suppliers of the scene («Своя торговля (…): …»)
    study: str = ""  # 0.62.0: the hero's schools, courses with progress and misses, the teachers of the scene («Учёба (…): …»)
    bonds: str = ""  # 0.63.0: the hero's bonds with NPCs (kind, step, points, perks) and the romance of the scene's people
    family: str = ""  # 0.64.0: the engagement, the spouse and the home's hours, the children by age, upkeep, the heir
    underworld: str = ""  # 0.65.0: known fences and stolen goods, the hero's criminal jobs, organizations and ranks
    office: str = ""  # 0.66.0: the hero's offices (rank, merit, whispers about bribes, a town's treasury and mood), offices on offer


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
    wishes: list[str] = Field(default_factory=list)  # what the player wants to meet in the game (0.12.0)


class TradeLine(_In):
    item_id: str
    name: str
    qty: int
    price_cp: int  # per item, already with attitude and haggling


class TradeInfo(_In):
    """Trade mode (0.4.0): the merchant's state as the engine keeps it. Deals go through the player's deal panel."""

    npc_id: str
    purse_cp: int = 0
    haggle_pct: int = 0  # won for the next deal (0.26.0; was: the visit): −pct on buying, +pct on selling
    discount_pct: int = 0  # granted by words for days (npc_discount, 0.21.0), already in the prices
    wants: str = ""  # what the trader buys gladly, in words (0.25.0)
    shuns: str = ""  # what it will not buy (0.25.0)
    news: list[str] = Field(default_factory=list)  # what the world's events changed at this trader (0.26.0)
    haggle_locked: bool = False  # a haggle failed today
    stock: list[TradeLine] = Field(default_factory=list)  # what the merchant sells
    buys: list[TradeLine] = Field(default_factory=list)  # the player's things and what the merchant pays


class QuestInfo(_In):
    """A quest of the world pack (0.5.0). Experience comes only from quests and combat, never from the master."""

    id: str
    title: str
    description: str = ""
    done: bool = False
    failed: bool = False  # taken, then its NPC died without an heir (0.19.0)
    step: str = ""  # the current step of a quest with steps (0.9.0); the engine closes steps, not the master
    offered_by: str = ""  # an NPC here offers it and the player has not taken it (0.12.0); taken by the button
    offer_items: list[str] = Field(default_factory=list)  # «name [item_id]» the giver hands over with it (0.12.0)


class CombatFoe(_In):
    id: str
    name: str
    monster: str = ""  # the SRD kind (Russian name)
    distance_ft: int = 0
    side: Literal["left", "right", "same"] = "same"
    # 0.46.0: unconscious — knocked out by a nonlethal blow (v0.7.22.11); the snapshot failed the turn without it
    status: Literal["active", "dead", "fled", "surrendered", "truce", "unconscious"] = "active"
    health: str = ""  # full | hurt | bloodied | near_death | dead | fled | surrendered | truce | unconscious — never numbers
    description: str = ""
    surprised: bool = False  # caught off guard: skips its first turn (0.8.0)
    conditions: list[str] = Field(default_factory=list)  # Russian names with rounds left: «без сознания (9 р.)» (0.10.0)
    speaks: str = ""  # «гоблинский, общий» or «без речи» (0.17.0)
    understands_hero: bool = True  # shares a tongue with the hero or telepathy (0.17.0)


class CombatIncoming(_In):
    """Reinforcements on the way (0.8.0): they come at the edge of the field at the start of a round."""

    names: list[str] = Field(default_factory=list)
    side: Literal["left", "right"] = "right"
    in_rounds: int = 1


class CombatAlly(_In):
    """A fighter on the hero's side under the engine's AI (0.49.0): a follower, a pack ally, a summoned creature."""

    id: str
    name: str
    monster: str = ""
    distance_ft: int = 0
    status: Literal["active", "down", "gone"] = "active"  # down — a follower or a pack ally unconscious; gone — the summoned vanished
    health: str = ""
    source: Literal["follower", "pack", "summon"] = "pack"
    npc_id: str = ""


class CombatInfo(_In):
    """The fight in progress (0.7.0): the engine's field and the lines of the round being narrated."""

    round: int = 1
    enemies: list[CombatFoe] = Field(default_factory=list)
    allies: list[CombatAlly] = Field(default_factory=list)  # 0.49.0
    outcome: str = ""  # "" | victory | truce | player_fled | captured | dead
    player_down: bool = False
    player_hidden: bool = False  # the player hid: foes do not see them (0.8.0)
    incoming: list[CombatIncoming] = Field(default_factory=list)  # (0.8.0)
    log: list[str] = Field(default_factory=list)


class HeroCrimes(_In):
    """Crimes of the hero (0.19.0): facts of the engine, not the master's memory."""

    deeds: list[str] = Field(default_factory=list)  # «убит(а) Сестра Илва [npc_priestess] — Храм, день 2; видели: …; знает вся округа»
    wanted: bool = False  # wanted in this location: its traders and givers turn the hero away
    arrest: bool = False  # the guard holds the hero here now; the answer is the player's button
    escort_to: list[str] = Field(default_factory=list)  # 0.41.0: «Капитан Ольга — Караулка [room_id]» — where the guard may lead the held hero


class Snapshot(_In):
    world: WorldInfo | None = None
    scene: Scene | None = None
    character: CharacterSheet | None = None
    history: list[HistoryLine] = Field(default_factory=list)
    summaries: dict[str, str] = Field(default_factory=dict)  # "location", "dialogue:<npc_id>"
    limits: TurnLimits = Field(default_factory=TurnLimits)
    trade: TradeInfo | None = None  # only in trade mode (0.4.0)
    quests: list[QuestInfo] = Field(default_factory=list)  # (0.5.0)
    combat: CombatInfo | None = None  # only in combat mode (0.7.0)
    crimes: HeroCrimes | None = None  # only when the hero has crimes (0.19.0)


# --- turn.* -----------------------------------------------------------------


class TurnRequestParams(_In):
    turn_id: str = Field(pattern=r"^t-\d+$")
    mode: Mode
    kind: TurnKind
    input: str = ""
    npc_id: str | None = None  # the conversation partner in social / trade
    model: str | None = None  # the player's pick from HelloResult.models; None = server default
    provider: str | None = None  # the provider the player pinned, a tag of ModelInfo.providers; None = the server picks (0.35.0)
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


DcTier = Literal["very_easy", "easy", "medium", "hard", "very_hard", "nearly_impossible"]


class OptionCheck(_Out):
    skill: str
    dc_tier: DcTier


class TurnResult(_Out):
    turn_id: str
    narration: str
    options: list[str] = Field(default_factory=list, max_length=3)
    # The price of each option in copper (0.10.0): the engine takes it when the player picks the option; 0 — free.
    option_costs: list[int] = Field(default_factory=list, max_length=3)
    # The check of each option (0.54.0): the engine sets the DC, shows the chance and rolls when the player picks it.
    option_checks: list[OptionCheck | None] = Field(default_factory=list, max_length=3)
    effect_ids: list[str] = Field(default_factory=list)
    check_ids: list[str] = Field(default_factory=list)
    next_mode: NextMode | None = None
    usage: Usage
    missing_concept: str = ""  # the player's wish the engine has no concepts for (0.23.0): a note for the author, in the trace


class OkResult(_Out):
    ok: bool = True


# --- summary.* ------------------------------------------------------------------


class SummaryParams(_In):
    kind: Literal["location", "dialogue", "npc_memory"]
    subject_id: str
    previous: str = ""
    events: list[str] = Field(min_length=1)
    model: str | None = None
    provider: str | None = None  # as in turn.request (0.35.0)


class SummaryResult(_Out):
    summary: str
    usage: Usage


# --- effects (ADR-0008 §3) ------------------------------------------------------

DamageSeverity = Literal["unpleasant", "dangerous", "deadly"]
HealTier = Literal["minor", "moderate", "major"]
Rarity = Literal["common", "uncommon", "rare", "very_rare", "legendary"]
ItemType = Literal["weapon", "armor", "gear", "consumable", "treasure", "wondrous"]  # wondrous — 0.18.0
# Mechanical properties the engine understands (ADR-0008 §6); free text never carries mechanics.
# Keep in sync with game/data/items.json "properties" (a test checks it).
ItemProperty = Literal[
    "finesse", "light", "heavy", "two_handed", "versatile", "thrown", "reach", "ammunition",
    "silvered", "magic_plus1", "magic_plus2", "magic_plus3",
    "fire_damage", "cold_damage", "lightning_damage", "radiant_damage", "necrotic_damage", "poison_damage",
    "resist_fire", "resist_cold", "resist_poison", "ac_plus1", "ac_plus2", "saves_plus1", "stealth_advantage",
    "light_source", "healing", "cursed",
    # v0.7.12 (0.18.0): every property the engine now resolves
    "resist_force", "resist_lightning", "resist_acid", "resist_necrotic", "checks_plus1", "ranged_damage_plus2",
    "spell_attack_plus1", "speed_30", "perception_advantage", "investigation_advantage", "darkvision", "wound_closure",
    "immune_disease", "understand_all", "missile_snaring", "carry_plus_500", "str_19", "int_19", "mithral", "no_crit",
    "crude", "masterwork",  # 0.56.0: the make of a crafted thing (−1 / +1 to attack; armor −1 AC / no Str and stealth trouble)
]


class GeneratedUse(_Out):
    """What a generated thing does when used (0.27.0), one of: a `spell` of the engine's book (with `charges` — a
    wand that regains them at dawn; without — a scroll, once), `heal` light / medium / strong, `resist` a damage
    type for an hour, `check_adv` — advantage on a skill for an hour (potions, once). The engine prices it in rarity."""

    spell: str | None = None
    level: int | None = Field(default=None, ge=0, le=3)
    charges: int | None = Field(default=None, ge=1, le=7)
    heal: Literal["light", "medium", "strong"] | None = None
    resist: str | None = None
    check_adv: str | None = None


class GeneratedItem(_Out):
    name: str
    item_type: ItemType
    base: str | None = None  # catalog item_id it is based on
    rarity: Rarity
    value_cp: int = Field(ge=0)
    properties: list[ItemProperty] = Field(default_factory=list)
    description: str = ""
    use: GeneratedUse | None = None  # 0.27.0: a wand, a scroll, a potion
    text: str = ""  # 0.27.0: what is written in it — a letter, a diary, an inscription (a thing without mechanics is fine)


class MoveEffect(_Out):
    kind: Literal["move"] = "move"
    room_id: str  # 0.52.0: or «new:<key>» — the first room of a place create_place made at this room in this turn
    npcs: list[str] = Field(default_factory=list)  # NPCs of the scene who go along (0.33.0): as npc_follow, checked by the engine


class DamageEffect(_Out):
    kind: Literal["damage"] = "damage"
    severity: DamageSeverity
    damage_type: str
    reason: str
    target_id: str | None = None  # an enemy id in a fight (0.7.0); None = the player


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


class ContentSpec(_Out):
    """A thing inside a container when the room is furnished (0.28.0): an item of the catalog (`item_id`) or a new one
    (`item`, by the same rules as give_item.item)."""

    item_id: str | None = None
    item: GeneratedItem | None = None
    qty: int = Field(default=1, ge=1, le=99)


class PropSpec(_Out):
    """A thing to put in the room when it is furnished (0.11.0)."""

    name: str = Field(min_length=1, max_length=60)
    description: str = Field(default="", max_length=240)
    item_id: str | None = None  # portable: an item of the catalog (find it with find_items first)
    item: GeneratedItem | None = None  # 0.68.0: portable, made by the master when the catalog lacks it
    owner: str | None = None  # npc_id of the scene who owns it
    text: str = Field(default="", max_length=800)  # what is written in it (a book, a note, a sign)
    container: str | None = None  # 0.28.0: a container kind (rules.containers: chest, barrel, basket, sack, cabinet, crate…)
    # 0.28.0: what lies inside; at most 10 — cut here, not by `maxItems` in the schema: Google rejects the whole request
    # with a limit on a list nested in a list (Gemini 3.8 Flash failed every turn, v0.7.21)
    contents: Annotated[list[ContentSpec], AfterValidator(lambda v: v[:10])] = Field(default_factory=list)
    lock: Literal["simple", "good", "masterwork"] | None = None  # 0.28.0: locked, and how well
    key: str | None = None  # 0.28.0: the item_id of the key that opens it
    source: Literal["water", "foul_water"] | None = None  # 0.70.0: water can be drawn here (a well, a stream, a river)


class FurnishEffect(_Out):
    """The first visit of a room (0.11.0): its things and furniture, fixed for good; the engine checks the count and
    the value of the portable ones."""

    kind: Literal["furnish"] = "furnish"
    props: Annotated[list[PropSpec], AfterValidator(lambda v: v[:10])] = Field(min_length=1)  # at most 10; no maxItems (Gemini)


class TakeFromEffect(_Out):
    """The hero takes a thing out of a container of the room (0.28.0); someone else's before its owner — a theft."""

    kind: Literal["take_from"] = "take_from"
    prop_id: str
    item_id: str
    qty: int = Field(default=1, ge=1, le=99)


class PutInEffect(_Out):
    """The hero puts a thing of their own into a container of the room (0.28.0), within its capacity."""

    kind: Literal["put_in"] = "put_in"
    prop_id: str
    item_id: str
    qty: int = Field(default=1, ge=1, le=99)


class UnlockEffect(_Out):
    """A locked container opens (0.28.0): `key` the hero carries, or after a passed check this turn — `pick`
    (Sleight of Hand with thieves' tools) or `force` (Athletics; it breaks)."""

    kind: Literal["unlock"] = "unlock"
    prop_id: str
    how: Literal["key", "pick", "force"] = "key"


class DoorEffect(_Out):
    """A door on the way to `to_room` from the hero's room (0.51.0): `unlock` / `lock` — its owner (the site's owner,
    here or behind it) does it, or `unlock` after a passed Sleight of Hand this turn; `break` — after a passed Athletics
    this turn. The engine knows the DC; breaking in before eyes is a trespass."""

    kind: Literal["door"] = "door"
    to_room: str
    action: Literal["unlock", "lock", "break"] = "unlock"


class NpcLink(_Out):
    npc_id: str
    kind: Literal["family", "spouse", "parent", "child", "friend", "rival", "master", "servant", "colleague"]


class NewNpc(_Out):
    """A person the world lacks (0.31.0), by the schema of a pack NPC: free text only in description and personality;
    `monster` — a template of people of the SRD (commoner, guard, acolyte, noble, scout, thug, priest, veteran…),
    `race` — an SRD race id, `room_id` — a room of this location (none — here) or «new:<key>» of this turn's create_place
    (0.52.0), `trader` with its shop kind `trade_kind` (0.53.0: the engine's goods of the kind, more each day; none — by
    the role's words), `stock` of ids from find_items and `stock_new` — the master's extra goods, a bad one skipped."""

    name: str = Field(min_length=2, max_length=60)
    role: str = Field(min_length=2, max_length=60)
    race: str | None = None
    gender: Gender = "other"
    # 0.43.0: ids of the engine's lists — age: child, teen, young, adult, middle, elderly, old; build: skinny, thin,
    # slender, wiry, athletic, sturdy, stocky, curvy, plump, heavy; height: very_short, short, medium, tall, very_tall.
    # 0.52.0: or their Russian word («пожилая»); None or an unknown word — the engine picks.
    age: str | None = None
    build: str | None = None
    height: str | None = None
    description: str = Field(default="", max_length=300)
    personality: str = Field(default="", max_length=300)
    monster: str = "commoner"
    room_id: str | None = None
    trader: bool = False
    # 0.53.0: general, smith, bowyer, food, herbalist, temple, tailor, scribe, craftsman (rules.json trade.kinds)
    trade_kind: str | None = None
    stock: list[str] = Field(default_factory=list, max_length=10)
    stock_new: list[GeneratedItem] = Field(default_factory=list, max_length=5)
    links: list[NpcLink] = Field(default_factory=list, max_length=5)


class NewSecret(_Out):
    text: str = Field(min_length=5, max_length=240)
    dc_tier: Literal["very_easy", "easy", "medium", "hard", "very_hard", "nearly_impossible"] = "medium"
    skill: Literal["perception", "investigation"] = "perception"


class NewEnemy(_Out):
    monster: str
    count: int = Field(default=1, ge=1, le=6)
    name: str | None = None
    desc: str = Field(default="", max_length=200)


class NewEncounter(_Out):
    enemies: list[NewEnemy] = Field(min_length=1, max_length=4)


class NewRoom(_Out):
    """A room of a new place (0.32.0) by the schema of a pack room; `exits` — keys of rooms of the same place (only the
    first room leads back to the world)."""

    key: str = Field(min_length=1, max_length=20)
    name: str = Field(min_length=2, max_length=60)
    description: str = Field(default="", max_length=600)
    indoor: bool = False
    dark: bool = False
    public: bool = True  # 0.50.0: false — a private room of the site (a kitchen, a bedroom): entering unasked is trespass
    hooks: list[str] = Field(default_factory=list, max_length=4)
    exits: list[str] = Field(default_factory=list)
    secrets: list[NewSecret] = Field(default_factory=list, max_length=3)
    encounter: NewEncounter | None = None


class NewSite(_Out):
    """The site (0.50.0: a building, a yard, a cave) the new rooms make: its name (empty — the first room's), tags of
    its kind (`tavern`, `smithy`, `shop`, `temple`, `home`, `bathhouse`…), whether anyone may walk in, its owner — an
    NPC of the world or «new» — the person create_npc makes in this turn (0.52.0)."""

    name: str = Field(default="", max_length=60)
    description: str = Field(default="", max_length=400)
    tags: list[str] = Field(default_factory=list, max_length=4)
    public: bool = True
    owner_id: str | None = None


class CreatePlaceEffect(_Out):
    """A room or a small place (0.32.0) on an open edge (`edge` — its index), only after find_places in the same turn:
    1–4 rooms; `new_location` with `name`, `description`, `terrain` — where the edge allows it. `room_id` (0.48.0) —
    the room of the edge from find_places: this room, its location, the neighbouring ones or where the hero has been;
    empty — this room. The hero does not go there by it. The engine checks the schema, the links, the encounter
    budget and the limits. 0.50.0: the rooms are one site (`site`); `inside` — a new site within the location of
    `room_id` (a bathhouse an NPC spoke of), entered from that room, no open edge needed."""

    kind: Literal["create_place"] = "create_place"
    edge: int = Field(default=0, ge=0)
    room_id: str | None = None
    rooms: list[NewRoom] = Field(min_length=1, max_length=4)
    new_location: bool = False
    name: str = ""
    description: str = ""
    terrain: str = ""
    inside: bool = False
    site: NewSite | None = None


class CreateNpcEffect(_Out):
    """Makes a person the world lacks (0.31.0) — only after find_npcs in the same turn; the engine checks the schema,
    the limits and the duplicates; the person lives in this game like one of the pack."""

    kind: Literal["create_npc"] = "create_npc"
    npc: NewNpc


class QuestNpc(NewNpc):
    """A person a quest brings (0.37.0): the schema of create_npc and a `key` its steps name («new:<key>»);
    `room_id` may be «new:<room key>» of the quest's new place."""

    key: str


class QuestPlace(_Out):
    """The place a quest brings (0.37.0): the fields of create_place."""

    edge: int = Field(default=0, ge=0)
    rooms: list[NewRoom] = Field(min_length=1, max_length=4)
    new_location: bool = False
    name: str = ""
    description: str = ""
    terrain: str = ""


class QuestItem(_Out):
    """The quest's thing (0.37.0): a catalog `item_id` or a new `item`, hidden in `room` (an id or «new:<room key>»);
    `hint` — where it lies, found by a check of `dc_tier`. `from_giver` (0.69.0) — the giver hands it over when the
    quest is taken (a parcel to carry): no `room` or `hint`."""

    item_id: str | None = None
    item: GeneratedItem | None = None
    from_giver: bool = False
    room: str = ""
    hint: str = ""
    dc_tier: Literal["very_easy", "easy", "medium", "hard", "very_hard", "nearly_impossible"] = "medium"


class NewQuestStep(_Out):
    """A step of a made quest (0.36.0): an engine fact. `talk` — `target` an NPC id (`item_id` — a thing to hand over),
    `visit` — a room id the hero comes to (`item_id` — a thing left there, 0.69.0), `find` — «room:secret» of the
    world, `fight` — an encounter id.
    What the quest brings (0.37.0): `target` «new:<key>» — its new person or room (fight — the encounter of that room),
    `find` with `target` «item» and `item_id` «item» — its thing."""

    text: str
    kind: Literal["talk", "visit", "find", "fight"]
    target: str
    item_id: str | None = None
    danger: bool = False


class CreateQuestEffect(_Out):
    """A quest from a giver of the scene (0.36.0) — only after find_quests in the same turn. The master names the scale,
    the engine sets the reward (coins, class XP for the dangerous, the giver's goodwill) and adds the way back to the
    giver; the quest is offered at once and lives like a pack quest."""

    kind: Literal["create_quest"] = "create_quest"
    giver: str = ""  # an NPC of the scene; on a board — anyone alive or «new:<key>»; empty for one's own deed (0.38.0)
    board_prop_id: str | None = None  # 0.38.0: an order on a board — a thing of the room that offers it
    for_goal: bool = False  # 0.40.0: the quest for the hero's life goal — past its threshold and after enough hints
    own: bool = False  # 0.38.0: the player's own deed — no giver, taken at once, pays only class XP for the dangerous
    title: str
    description: str = ""
    offer_text: str = ""
    scale: Literal["trifle", "ordinary", "major"]
    steps: list[NewQuestStep] = Field(min_length=1, max_length=4)
    reward_item_id: str | None = None
    @model_validator(mode="after")
    def _giver_or_own(self) -> "CreateQuestEffect":
        # the model left the customer out of a board order (v0.7.21.2 goldens): said at once, before the engine
        if not self.own and not self.giver and self.board_prop_id and len(self.new_npcs) == 1:
            self.giver = f"new:{self.new_npcs[0].key}"  # the order's one new person is its customer
        if not self.own and not self.giver:
            raise ValueError("giver обязателен: id NPC сцены; на доске — id человека мира (find_npcs) или новый заказчик: "
                             "добавь его в new_npcs (name, role, key) и укажи giver «new:<key>»; своё дело без заказчика — own: true")
        return self

    new_npcs: list[QuestNpc] = Field(default_factory=list)  # 0.37.0: up to 2 people the quest brings
    new_place: QuestPlace | None = None  # 0.37.0: a place on an open edge of this room, as create_place
    quest_item: QuestItem | None = None  # 0.37.0: the quest's thing in a hiding place; 0.69.0: or from the giver


class DropItemEffect(_Out):
    """The hero leaves a thing in the room (0.29.0): an item of the pack, or a bag (`item_id` = its bag id) with what
    is in it; it becomes a thing of the room that can be picked up again."""

    kind: Literal["drop_item"] = "drop_item"
    item_id: str
    qty: int = Field(default=1, ge=1, le=99)


class FillEffect(_Out):
    """The hero draws water into the vessels it carries (0.70.0): a waterskin, a flask, a jug, a bucket; `item_id` —
    one kind only, empty — all. The engine checks the water here (the room's tag, a thing with `source`, a well or a
    stream of the room) and fills each to its volume."""

    kind: Literal["fill"] = "fill"
    item_id: str | None = None


class TakePropEffect(_Out):
    """The player takes a portable thing of the room (0.11.0); an owner who sees it reacts by the engine's rules."""

    kind: Literal["take_prop"] = "take_prop"
    prop_id: str


class PropStateEffect(_Out):
    """A thing of the room changes (0.11.0): opened, closed, broken, burned, moved."""

    kind: Literal["prop_state"] = "prop_state"
    prop_id: str
    state: Literal["open", "closed", "broken", "burned", "moved"]


class TakeItemEffect(_Out):
    kind: Literal["take_item"] = "take_item"
    item_id: str
    qty: int = Field(default=1, ge=1, le=20)


class NpcAttitudeEffect(_Out):
    kind: Literal["npc_attitude"] = "npc_attitude"
    npc_id: str
    delta: int = Field(ge=-2, le=2)
    reason: str


ConditionId = Literal["blinded", "charmed", "deafened", "exhaustion", "frightened", "grappled", "incapacitated",
                      "invisible", "paralyzed", "petrified", "poisoned", "prone", "restrained", "stunned", "unconscious"]
SaveAbility = Literal["str", "dex", "con", "int", "wis", "cha"]
SaveTag = Literal["poison", "charm", "fear", "magic", "sleep", "disease"]
ConditionDuration = Literal["round", "minute", "ten_minutes", "hour", "eight_hours", "short_rest", "long_rest",
                            "until_removed"]


class CastEffect(_Out):
    """The player casts a spell (0.6.0): the engine checks it is ready and spends the slot."""

    kind: Literal["cast"] = "cast"
    spell: str  # id or name as in the sheet
    slot_level: int | None = Field(default=None, ge=1, le=5)  # None = the lowest fitting slot
    on_self: bool = False  # cast on the hero: the engine lifts what it cures (0.16.0)


class ConditionSave(_Out):
    """The hero's save against a condition (0.16.0): the engine rolls it with the hero's bonuses."""

    ability: SaveAbility
    dc_tier: DcTier


class ConditionEffect(_Out):
    """A condition (0.16.0 for the hero: a reason, a save of the engine with its tag, a duration from the list;
    without a save only when the hero brought it on with their own words this turn — cause "player")."""

    kind: Literal["condition"] = "condition"
    condition: ConditionId
    on: bool = True  # False lifts it (exhaustion — one level)
    reason: str = ""  # what caused it, in Russian
    save: ConditionSave | None = None
    tag: SaveTag | None = None  # what the save is against: race traits give advantage or immunity
    duration: ConditionDuration = "long_rest"
    repeat_save: bool = False  # in a fight the hero repeats the save at the end of each own turn
    cause: Literal["player"] | None = None  # the hero did it themselves this turn: no save
    by: str | None = None  # the NPC who caused it (the source of fear, the charmer, the grappler)
    ends_on_damage: bool = False  # a sleep that ends when the hero is hurt
    target_id: str | None = None  # an enemy id in a fight (0.7.0)


class DiseaseEffect(_Out):
    """The hero catches a disease (0.55.0): a known one by id or Russian name, or a new one with `days` (then
    incubation_hours, symptoms, weak_saves). The engine always rolls the save; the disease shows after its
    incubation, so the summary does not name it."""

    kind: Literal["disease"] = "disease"
    disease: str = Field(min_length=2)  # id or name of a known disease, or the name of a new one
    reason: str = Field(min_length=3)  # what infected: a bite, foul water, a sick man coughing
    save: ConditionSave
    days: int | None = Field(default=None, ge=1, le=10)  # only for a new disease
    incubation_hours: int | None = Field(default=None, ge=0, le=72)
    symptoms: list[ConditionId] = Field(default_factory=list, max_length=3)
    weak_saves: list[SaveAbility] = Field(default_factory=list, max_length=2)  # saves with disadvantage while sick
    herbs: bool = True  # herbs and a herbalist cure it; False — only magic or time
    contagious: bool = False
    text: str = ""  # how it shows, for the player's card


class RecipeMaterial(_Out):
    item_id: str  # a catalog or library item (find_items)
    qty: int = Field(default=1, ge=1, le=10)


class RecipeEffect(_Out):
    """A recipe the hero learns from the player's words (0.56.0): «сделаю силок из верёвки». The engine checks the tool
    (the hero must be proficient), the station, hours and DC tier by rules.craft.make, and that the output is worth no
    more than its materials and labour; the hero then makes it in the «Ремесло» window (time, the check, the quality)."""

    kind: Literal["recipe"] = "recipe"
    name: str = Field(default="", max_length=60)  # «Силок из верёвки»; empty — the output's name
    tool: str  # smiths_tools, leatherworkers_tools, woodcarvers_tools, carpenters_tools, herbalism_kit, alchemists_supplies, cooks_utensils, tinkers_tools…
    station: Literal["forge", "workbench", "alchemy", "hearth", "fire"] | None = None  # None — anywhere; fire — a hearth or a campfire
    hours: int = Field(ge=1, le=72)
    dc_tier: Literal["very_easy", "easy", "medium", "hard"]
    materials: list[RecipeMaterial] = Field(min_length=1, max_length=4)
    output_id: str | None = None  # a catalog or library item
    output: GeneratedItem | None = None  # or a new one (as give_item.item)
    qty: int = Field(default=1, ge=1, le=20)


class CourseEffect(_Out):
    """A course the world lacks (0.62.0): «Горм, научи меня ковать — я заплачу». A scene NPC teaches: `teach_kind`
    (skill, tool, language, spell up to the 2nd circle, recipe) and `teach_id`, `lessons`, `fee_cp` for the course, the
    check of a lesson `skill`, `dc_tier`. No class experience. Enrolment and lessons are the «Учёба» window's buttons."""

    kind: Literal["course"] = "course"
    npc_id: str  # an NPC of the scene
    name: str = Field(max_length=60)
    teach_kind: Literal["skill", "tool", "language", "spell", "recipe"]
    teach_id: str
    lessons: int = Field(default=4, ge=1, le=20)
    fee_cp: int = Field(default=0, ge=0)
    skill: str | None = None
    dc_tier: Literal["easy", "medium", "hard"] = "medium"


class BondEffect(_Out):
    """A scene that moved a bond (0.63.0): a heart-to-heart, a shared danger, a slight. `delta` ±10 at most, once a day
    per NPC, with the `reason`; `kind` mentor when the NPC took the hero under its wing (romance only by the player's
    «Признаться» button). For an NPC the master made — `romance` {open, genders, why} and `likes` / `dislikes` (taste
    groups of the rules or catalog ids). Gifts and deeds move the bond by the engine."""

    kind: Literal["bond"] = "bond"
    npc_id: str  # an NPC of the scene
    delta: int = Field(default=0, ge=-10, le=10)
    reason: str = Field(default="", max_length=80)
    bond_kind: Literal["friend", "mentor"] | None = None
    romance: dict | None = None
    likes: list[str] = Field(default_factory=list, max_length=6)
    dislikes: list[str] = Field(default_factory=list, max_length=6)


class FenceEffect(_Out):
    """A fence the world lacks (0.65.0): «Горм, возьмёшь колечко, о котором лучше не спрашивать?». A trader of the
    scene buys stolen goods at `buy_pct` of the value (25–50) and sells thieves' goods to the hero; a fence of the pack
    that decided to trust the hero — `buy_pct` omitted. Selling is the trade window — the engine's act."""

    kind: Literal["fence"] = "fence"
    npc_id: str  # a trader of the scene
    buy_pct: int | None = Field(default=None, ge=1, le=100)


class HeistEffect(_Out):
    """A criminal job from the player's plan or an NPC's offer (0.65.0): «обнесу склад торговца ночью», «Сыч, есть
    дело?». `heist_kind` burglary (a place at night, `victim_npc` its owner), robbery (on a road by day, `victim_name`)
    or smuggling (`cargo` — catalog ids carried past `target_room`); the loot and reward within the level's caps. The
    job is the hero's at once; the preparations and the act are the buttons of the «Дела» window — the engine rolls."""

    kind: Literal["heist"] = "heist"
    heist_kind: Literal["burglary", "robbery", "smuggling"]
    name: str = Field(max_length=60)
    target_room: str  # a room of the world where the act is
    victim_npc: str | None = None
    victim_name: str = Field(default="", max_length=60)
    giver_npc: str | None = None  # an NPC of the scene who gives the job
    org_id: str | None = None  # the organization the job is for
    loot_cp: int = Field(default=0, ge=0)
    items: list[str] = Field(default_factory=list, max_length=2)
    reward_cp: int = Field(default=0, ge=0)
    cargo: list[str] = Field(default_factory=list, max_length=4)
    dc_tier: Literal["easy", "medium", "hard"] = "medium"
    text: str = Field(default="", max_length=300)


class OrgEffect(_Out):
    """An organization the world lacks (0.65.0): a thieves' band, a smugglers' ring, a guild around an NPC of the scene
    as its head; the hideout is the scene when it is private. Joining, ranks, the cut and jobs are the buttons of the
    «Братство» window."""

    kind: Literal["org"] = "org"
    npc_id: str  # the head, an NPC of the scene
    name: str = Field(max_length=40)
    org_kind: Literal["criminal", "guild"] = "criminal"
    cut_pct: int | None = Field(default=None, ge=1, le=100)


class SupplierEffect(_Out):
    """A wholesale supplier the world lacks (0.61.0): «Ведана, продашь мне травы оптом для моей лавки?». A scene NPC
    sells lots to a hero with the trade charter at `pct` of the value — its own goods or `goods` (catalog ids). The
    lots are bought by the «Опт» button — the engine's act."""

    kind: Literal["supplier"] = "supplier"
    npc_id: str  # an NPC of the scene
    goods: list[str] = Field(default_factory=list, max_length=12)
    pct: int | None = Field(default=None, ge=1, le=100)


class BankEffect(_Out):
    """A lender the world lacks (0.60.0): «Горм, ты ведь ссужаешь под залог?». A scene NPC (or `new` — the person
    create_npc made in this turn) takes deposits, lends against a collateral or keeps a vault; rates within
    rules.bank.make. Deposits, loans and the vault are the buttons of the «Банк» window — the engine's acts."""

    kind: Literal["bank"] = "bank"
    npc_id: str  # an NPC of the scene or "new"
    services: list[Literal["deposit", "loan", "vault"]] = Field(min_length=1, max_length=3)
    name: str | None = Field(default=None, max_length=60)
    loan_rate_pct_week: float | None = Field(default=None, ge=0)
    deposit_rate_pct_week: float | None = Field(default=None, ge=0)
    ltv_pct: int | None = Field(default=None, ge=0, le=100)


class PropertyEffect(_Out):
    """A place the player wants to buy and the world lacks on sale (0.59.0): «куплю дом у реки». A site of this location
    (or `new` — the one create_place made in this turn) on sale by a seller of the scene (or `new` — the person
    create_npc made); the price and the income within rules.property.make. The hero buys it by the button and gets the
    deed at the registry — the engine's acts."""

    kind: Literal["property"] = "property"
    site_id: str  # "here" (the hero's site), a room or site id of this location, or "new"
    seller_id: str  # an NPC of the scene or "new"
    place_kind: Literal["house", "land", "mill", "shop", "workshop", "farm", "stable", "tavern"]
    name: str | None = Field(default=None, max_length=60)
    price_cp: int = Field(ge=1)
    income_cp_day: int | None = Field(default=None, ge=0)


class JobEffect(_Out):
    """A job an NPC of the scene gives at the player's asking (0.58.0): «пойду переводчиком к караванщику». The engine
    checks the employer is here, the hours, the DC tier and the pay by rules.jobs.make; the hero then hires and works
    shifts by the buttons («Работа» at the employer)."""

    kind: Literal["job"] = "job"
    employer_id: str  # an NPC of the scene
    name: str = Field(min_length=1, max_length=60)  # «Переводчик при караване»
    skill: str | None = None  # the check of a shift: persuasion, athletics, perception…
    tool: str | None = None  # or a tool (cooks_utensils, smiths_tools…); with a skill — it helps
    requires_tool: bool = False  # proficiency in the tool is a must
    hours: int = Field(ge=2, le=10)
    dc_tier: Literal["very_easy", "easy", "medium", "hard"]
    pay_cp: int = Field(ge=1)  # a shift at the first rank, within the engine's cap per hour
    ranks: list[str] | None = None  # three names of ranks, from the first


class UseFeatureEffect(_Out):
    kind: Literal["use_feature"] = "use_feature"
    feature: str  # a feature with limited uses, by name as in the sheet
    amount: int = Field(default=1, ge=1, le=30)  # points (Ki, Lay on Hands)


class UseItemEffect(_Out):
    kind: Literal["use_item"] = "use_item"
    item_id: str


class CombatFoeSpec(_Out):
    monster: str  # an SRD monster id (goblin, wolf, bandit, skeleton, …)
    count: int = Field(default=1, ge=1, le=6)
    name: str | None = None


class NoteEffect(_Out):
    """The master's own memory of an event (0.14.0): a short Russian sentence the player sees in the chat and the
    journal («Айра поклялась служить человеку в капюшоне»). A `flag` is only a flag the world pack knows. With
    `npc_id` (0.20.0) — what that NPC of the scene remembers of the hero («герой обещал вернуть 5 зм к празднику»):
    it comes back in `scene.npcs[].memory` at every meeting."""

    kind: Literal["note"] = "note"
    # a long note is cut, not refused: a refused schema made the turn fail after the tool's retries (v0.7.4 goldens)
    text: Annotated[str, BeforeValidator(lambda v: v.strip()[:200] if isinstance(v, str) else v)] = Field(min_length=3)
    npc_id: str | None = None


class EquipEffect(_Out):
    """The player changes gear by words (0.14.0): `slot` armor / shield / main_hand / off_hand, worn things (0.44.0)
    head / eyes / neck / cloak / hands / feet / ring1 / ring2, or `all` to strip; `item_id` puts that carried item on,
    none takes the slot off. The engine checks it like the character sheet; in a fight armour and worn things cannot
    be changed."""

    kind: Literal["equip"] = "equip"
    slot: Literal["armor", "shield", "main_hand", "off_hand", "head", "eyes", "neck", "cloak", "hands", "feet", "ring1", "ring2", "all"]
    item_id: str | None = None


class StartCombatEffect(_Out):
    """The master starts a fight (0.7.0): the engine checks the XP budget of the character's level. In a fight it is a
    reinforcement (0.8.0): the newcomers come at the edge of the field (`side`) next round, within the same budget."""

    kind: Literal["start_combat"] = "start_combat"
    enemies: list[CombatFoeSpec]
    side: Literal["left", "right"] | None = None
    reason: str = ""


class AdvanceTimeEffect(_Out):
    """The player spends time in the scene (0.10.0): waits, sleeps rough, works — the engine moves the clock within its
    limit; not in combat."""

    kind: Literal["advance_time"] = "advance_time"
    minutes: int = Field(ge=1, le=720)
    reason: str = ""


class CrimeKnownEffect(_Out):
    """A hidden murder becomes known (0.19.0): the hero confessed or was exposed in the scene. `victim_id` — the
    npc_id of a deed «никто не знает». The engine spreads it: attitudes, and the wanted hero where there is law."""

    kind: Literal["crime_known"] = "crime_known"
    victim_id: str


class CrimeReleaseEffect(_Out):
    """The guard lets the held hero go by words (0.41.0): only after a Persuasion, Deception or Intimidation check this
    turn that passed at the engine's tier for the crimes. The hero stays wanted; the guard does not come back at once."""

    kind: Literal["crime_release"] = "crime_release"


class NpcDiscountEffect(_Out):
    """A trader of the scene gives the hero a discount by words (0.21.0): `percent` 5–20 off buying for a week. The
    engine grants it only from an NPC who likes the hero (attitude ≥ +1) or was won over by a successful
    Persuasion, Deception or Intimidation against it this turn."""

    kind: Literal["npc_discount"] = "npc_discount"
    npc_id: str
    percent: int = Field(ge=1, le=100)
    reason: str


class NpcFavorEffect(_Out):
    """An NPC of the scene does one of its services for free (0.21.0): `service` from `scene.npcs[].services`
    (`silver` — `item_id` the weapon). Attitude ≥ +2 or won over this turn; one in a week; the hero owes it."""

    kind: Literal["npc_favor"] = "npc_favor"
    npc_id: str
    service: str
    item_id: str | None = None
    reason: str


class ReputationEffect(_Out):
    """The settlement learned of a deed of the hero (0.24.0): `delta` −3…+3 points of its reputation, once a turn,
    with the deed and who knows of it in `reason`. Quests, murders, thefts the engine counts itself."""

    kind: Literal["reputation"] = "reputation"
    delta: int = Field(ge=-3, le=3)
    reason: str


class RevealSecretEffect(_Out):
    """An NPC of the scene tells a secret of its own by goodwill (0.22.0): `secret_id` from `scene.npcs[].secrets`.
    The engine checks the attitude it needs; a secret won by a social check comes in the check's `revealed`."""

    kind: Literal["reveal_secret"] = "reveal_secret"
    npc_id: str
    secret_id: str


class GoalAssessEffect(_Out):
    """The master's assessment of the hero's life goal (0.39.0): its scale, the direction it needs (`class` or a
    peaceful direction id), the engine concepts it is made of; the engine sets the threshold."""

    kind: Literal["goal_assess"] = "goal_assess"
    scale: Literal["easy", "medium", "hard", "epic", "legendary"]
    direction: str = "class"
    concepts: list[str] = Field(default_factory=list)


class GoalHintEffect(_Out):
    """A hint toward the hero's life goal (0.40.0): only past its threshold and only when the player asks or seeks;
    the engine counts them — the quest for the goal comes after enough."""

    kind: Literal["goal_hint"] = "goal_hint"


class NpcFollowEffect(_Out):
    """An NPC of the scene goes with the hero (0.33.0): from now on it stands wherever the hero is. `follow: false` —
    one who follows stays here (`home: true` — goes back to its own place). The engine allows following to one
    disposed to the hero («дружески») or won over by a check this turn; a few at once."""

    kind: Literal["npc_follow"] = "npc_follow"
    npc_id: str
    follow: bool = True
    home: bool = False


class OwnerEffect(_Out):
    """Ownership changes hands by words (0.47.0): `creature_id` — the hero's bound prisoner of the scene goes to the NPC
    `owner_id` of this room (a sale: `price_cp` the NPC pays, capped by the engine; a thinking one is not sold — no
    slavery in this world) or free (`owner_id` empty); `item_id` with `owner_id` "hero" — the NPC here gives up to the
    hero a thing of its that the hero took without asking."""

    kind: Literal["owner"] = "owner"
    creature_id: str | None = None
    item_id: str | None = None
    owner_id: str = ""
    price_cp: int = Field(default=0, ge=0)


class AcceptQuestEffect(_Out):
    """The hero takes by words a quest its giver here offers (0.21.0), like the button «Взять задание»."""

    kind: Literal["accept_quest"] = "accept_quest"
    quest_id: str


class FlagEffect(_Out):
    kind: Literal["flag"] = "flag"
    flag: str = Field(pattern=r"^[a-z][a-z0-9_]{1,40}$")
    value: bool = True


Effect = Annotated[
    MoveEffect | DamageEffect | HealEffect | CoinsEffect | GiveItemEffect | TakeItemEffect | NpcAttitudeEffect | FlagEffect
    | CastEffect | ConditionEffect | DiseaseEffect | RecipeEffect | JobEffect | PropertyEffect | BankEffect | SupplierEffect | CourseEffect | BondEffect | FenceEffect | HeistEffect | OrgEffect | UseFeatureEffect | UseItemEffect | StartCombatEffect | AdvanceTimeEffect
    | FurnishEffect | TakePropEffect | PropStateEffect | NoteEffect | EquipEffect | CrimeKnownEffect | CrimeReleaseEffect
    | NpcDiscountEffect | NpcFavorEffect | AcceptQuestEffect | RevealSecretEffect | ReputationEffect
    | TakeFromEffect | PutInEffect | UnlockEffect | DropItemEffect | FillEffect | CreateNpcEffect | CreatePlaceEffect | NpcFollowEffect | CreateQuestEffect | GoalAssessEffect | GoalHintEffect
    | OwnerEffect | DoorEffect,
    Field(discriminator="kind"),
]


# --- engine.* (backend -> Godot) ---------------------------------------------



class EngineCheckParams(_Out):
    turn_id: str
    skill: str | None = None
    save: str | None = None
    dc_tier: DcTier
    target_id: str | None = None
    advantage_reason: str | None = None
    sense: Literal["sight", "hearing"] | None = None  # the check needs sight or hearing: blinded / deafened fail (0.16.0)
    tool: str | None = None  # the tool the check uses (thieves_tools, herbalism_kit…): proficiency, a must (0.17.0)
    argument: str | None = None  # 0.42.0: a social check — the player's argument in a few words; a repeat rolls only with a new one


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


class EngineFindNpcsParams(_Out):
    turn_id: str
    query: str


class FoundNpc(_In):
    npc_id: str
    name: str
    role: str = ""
    room: str = ""
    location: str = ""
    source: str = "pack"  # pack | made
    dead: bool = False


class EngineFindNpcsResult(_In):
    npcs: list[FoundNpc] = Field(default_factory=list)


class EngineFindQuestsParams(_Out):
    turn_id: str
    query: str


class FoundQuest(_In):
    quest_id: str
    title: str
    giver: str = ""
    status: str = "offered"  # offered | taken | done | failed
    source: str = "pack"  # pack | made


class EngineFindQuestsResult(_In):
    quests: list[FoundQuest] = Field(default_factory=list)
    open_made: int = 0  # made quests offered or taken now (0.36.0)
    max_open: int = 3


class EngineFindPlacesParams(_Out):
    turn_id: str
    query: str


class FoundPlace(_In):
    room_id: str
    name: str
    location: str = ""
    source: str = "pack"


class FoundEdge(_In):
    """An open edge of the known world where a new place may grow (0.48.0)."""

    room_id: str
    room: str = ""
    location: str = ""
    edge: int = 0
    text: str = ""
    terrain: list[str] = Field(default_factory=list)
    new_location: bool = False


class EngineFindPlacesResult(_In):
    places: list[FoundPlace] = Field(default_factory=list)
    edges: list[FoundEdge] = Field(default_factory=list)  # 0.48.0


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
    "session.set_budget.params": SetBudgetParams,
    "session.set_budget.result": StatusResult,
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
    "engine.find_npcs.params": EngineFindNpcsParams,
    "engine.find_npcs.result": EngineFindNpcsResult,
    "engine.find_places.params": EngineFindPlacesParams,
    "engine.find_places.result": EngineFindPlacesResult,
}
