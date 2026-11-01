class_name GameSession
extends RefCounted
## One playthrough: seeded RNG, counters, chat, and (since save v2) the world state of the start scene —
## room, conversation mode, character, generated items, NPC attitudes, flags, summaries.
## Pure data: no nodes, no autoloads, no tr().

const KIND_PLAYER := "player"
const KIND_DM := "dm"
## An NPC line in social / trade mode: `npc_id`, `name`, `text`.
const KIND_NPC := "npc"
const KIND_CHECK := "check"
## Applied effects of a turn: `lines` (already human-readable summaries from the engine).
const KIND_EFFECT := "effect"
## Engine/system notice; `key` is a localization key, `args` its format arguments.
const KIND_SYSTEM := "system"

const MODE_EXPLORATION := "exploration"
const MODE_SOCIAL := "social"
const MODE_TRADE := "trade"
const MODE_COMBAT := "combat"

var game_seed: int = 0
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var turn_counter: int = 0
var check_counter: int = 0
var effect_counter: int = 0
var chat: Array[Dictionary] = []
## The master's last «interesting» options (turn.result.options), shown as buttons.
var options: Array[String] = []
## The price of each option in copper (turn.result.option_costs, v0.6.5): taken when the player picks it.
var option_costs: Array[int] = []
## The check of each option, {skill, dc_tier} or {} (turn.result.option_checks, v0.7.22.28): the engine rolls it.
var option_checks: Array = []
## The quest the player follows (v0.7.22.32, П11); "" — the last one taken.
var tracked_quest := ""
var created_at: String = ""

## The world pack of this game and its version when the game started.
var world_id: String = ""
var world_version: String = ""
## Master settings of the new game screen: dm_style, death_mode, violence, lines, veils, wishes (WorldPack.default_settings).
var settings: Dictionary = {}
var room_id: String = ""
var mode: String = MODE_EXPLORATION
## The conversation partner in social / trade.
var npc_id: String = ""
## The character in the CharacterRules layout: choices, state (hp, conditions, slots) and the derived cache.
var character: Dictionary = {}
## Items created by the master and accepted by the engine: {item_id: definition}. Kept so saves work alone.
var items: Dictionary = {}
## Every character the game touched, one record each (v0.7.61, Being): {id: record}.
var beings: Dictionary = {}
var being_counter: int = 0
var flags: Array[String] = []
## Failed skill checks: "skill|target" → {"result", "advantages"} (ExplorationRules); cleared by a long rest.
var locks: Dictionary = {}
## What the hero knows, {kind: [key]} (Knows, v0.7.68).
var knows: Dictionary = {}
var layouts: Dictionary = {}  ## what maps keep: chosen chunks and what was touched (LayoutRules, v0.8.0)
var layout_cache: Dictionary = {}  ## built maps of this run, not saved
## Rooms the player has been to, in order (the map).
var visited: Array[String] = []
## Days since the start; a long rest starts the next one.
## The clock (v0.7.60): minutes since midnight of the first day. `day` and `minute` are its two views.
var clock: int = 480
var day: int:
	get:
		return clock / 1440 + 1
	set(v):
		clock = (v - 1) * 1440 + clock % 1440
## npc_id → merchant state (TradeRules): purse_cp, stock {item_id: qty}, day of the last restock, haggle_pct of
## the current visit, haggle_failed_day, haggle_result. Created from the pack on the first trade.
var merchants: Dictionary = {}
## The fight in progress (CombatRules), {} when there is none.
var combat: Dictionary = {}
## Encounters of the pack already fought (CombatRules) and NPCs killed in a fight.
var encounters_done: Array[String] = []
## Encounters the hero slipped past unseen — out of the room by another way than in (v0.7.49.3): a quest's
## «пройти стражу» is done, the foes still there.
var encounters_passed: Array[String] = []
var encounters_peace: Array[String] = []  # met as friends (v0.7.50)
var factions: Dictionary = {}  # the hero's standing: {id: {pts, met_day, rest, why, master_day}} (v0.7.50)
## The «Красться» toggle of exploration (v0.6.2).
var sneaking: bool = false
## Minutes since midnight (TimeRules, v0.6.3); a new game starts in the morning.
var minute: int:
	get:
		return clock % 1440
	set(v):
		clock += v - clock % 1440
## Quests with steps taken: {quest_id: step index} (QuestRules, v0.6.3).
var quests_active: Dictionary = {}
## Parts of "all" steps already announced: {quest_id: [index]} (QuestRules, v0.6.4).
var quest_parts: Dictionary = {}
## Spent traps {"room:secret": "sprung" | "disarmed"} and emptied caches ["room:secret"] (v0.6.3).
var traps: Dictionary = {}
var caches_taken: Array[String] = []
## The room where people noticed the sneaking player: no sneaking there until they leave (v0.6.5).
var sneak_noticed: String = ""
## Things of the rooms {room_id: [prop]} (PropRules) and shops closed for the player {npc_id: day} (v0.7.0).
var props: Dictionary = {}
var shop_closed: Dictionary = {}

## Crimes of the hero (CrimeRules, v0.7.14): [{id, victim, room, location, at, witnesses, known, settled}]; wanted
## {location_id: abs minute since}; the room where the guard holds the hero ("" — free); bodies {npc_id: room_id}
## and the searched ones; quests failed with a dead NPC (QuestRules.on_death).
var crimes: Array[Dictionary] = []
var wanted: Dictionary = {}
var arrest: String = ""
## v0.7.22.2: {location_id: abs minute} — let go or fought free, nobody holds the hero there until then; the talk
## answers already tried in this hold.
var let_go: Dictionary = {}
var arrest_tried: Array[String] = []
## v0.7.22.12 (EncounterRules): foes that did not notice the hero {room: {encounter, from}}; the hero's captivity
## {room, foes, encounter, from} ({} — free).
var lurking: Dictionary = {}
var captive: Dictionary = {}
## v0.7.22.17: the creature the hero last spoke to (its master's replies go when it does).
var talk_creature: String = ""
## v0.7.22.24 (SiteRules): the sites whose private room the hero was warned off {site_id: abs minute}.
var trespass_warned: Dictionary = {}
## v0.7.39.2 (SiteRules): the owner's leave to walk into its private sites {site_id: owner} — kept until a quarrel;
## the day the hero last asked each owner in vain {npc_id: day}.
var permits: Dictionary = {}
var permit_asked: Dictionary = {}
## v0.7.66 (WayRules): the state of the ways' leaves {"a|b": {locked, unlocked_until, broken, hp, effects, arcane_by_hero}}.
var ways: Dictionary = {}
## The day the master last described each room (v0.7.22.20, ExplorationRules.again_line): {room_id: day}.
var described: Dictionary = {}
## The rolls of the rules since the last chat line of effects (RollParts.note, v0.7.39.5): not saved, the next
## effect line takes them for its hover.
var roll_notes: Array[Dictionary] = []
## Lines of the faith (FaithRules.deed) from a roll inside a turn (v0.7.49): not saved, the next chat line takes them.
var faith_lines: Array[String] = []
var quests_failed: Array[String] = []
## The chronicle (v0.7.14.4): every line of the engine in the chat with its day, minute and room
## [{day, minute, room, text}], the newest CHRONICLE_MAX — the journal's «Хроника» and the master's memory.
const CHRONICLE_MAX := 400
var chronicle: Array[Dictionary] = []
## The account book (Ledger, v0.7.60): the last changes of the hero's coins [{at, cp, why}].
var ledger: Array[Dictionary] = []
## What the master gave (cp of coins and things) since the last long rest (EffectEngine, v0.7.14.3).
var reward_spent: int = 0
var magic_given: int = 0  # magic things the master gave since the long rest (v0.7.22.2)
## The master's own memory of events (effect `note`, v0.7.4): [{day, clock, room, text}] — shown in the journal.
var notes: Array[Dictionary] = []
## Short rests taken today (ExplorationRules); a long rest resets it.
var short_rests: int = 0
## Exhaustion by the clock (TimeRules, v0.7.8): minutes on the way on `march_day`; the absolute minute the last long
## rest ended and the saves already made for the days awake since.
var march_day: int = 1
var march_minutes: int = 0
var rested_at: int = 480  # a new game starts in the morning, rested
var awake_saves: int = 0
## Ids of the pack quests the player completed (XpRules).
var quests_done: Array[String] = []
## What each NPC remembers of the hero (v0.7.15, «Социальный режим 2.0»): npc_id → [{day, text}], the newest
## NPC_MEMORY_MAX — facts the engine records (quests, caught thefts, murders) and the master's notes about the NPC.
const NPC_MEMORY_MAX := 12
## Reputation in settlements (v0.7.17, ReputationRules): location_id → points.
var reputation: Dictionary = {}
## What the master made in this game (v0.7.20, WorldGen): {"npcs": {id: def}, "npc_rooms": {id: room}} — merged into the
## game's copy of the pack's world.
var generated: Dictionary = {}
## Creatures a spell called to go with the hero (v0.7.22.22, AllyRules): [{id, spell, monster, name, until, concentration,
## hp, helper}]; `until` — the absolute minute they go, −1 until let go.
## "location:<id>" and "dialogue:<npc_id>" → text from summary.request.
var summaries: Dictionary = {}
## Lines of the current conversation, the events for its summary.
var dialogue_log: Array[String] = []
## Events since the last location summary.
var location_log: Array[String] = []


## The number of a seed the player wrote: a whole number stays itself, any other text goes by its hash.
static func seed_of(text: Variant) -> int:
	var raw := str(text).strip_edges()
	if raw.is_valid_int() and raw.to_int() >= 0:
		return raw.to_int()
	return absi(raw.hash())


static func create(new_seed: int, now: String, start_room: String, new_character: Dictionary) -> GameSession:
	var s := GameSession.new()
	s.game_seed = new_seed
	s.rng.seed = new_seed
	s.created_at = now
	s.room_id = start_room
	s.character = normalized_character(new_character)
	return s


## JSON gives back every number as a float: the whole ones become ints again, all the way down. A save goes through it
## once in from_dict, so no field needs its own cast; a value that must stay a fraction is read with float().
static func whole(v: Variant) -> Variant:
	if v is float and float(v) == floorf(v):
		return int(v)
	if v is Array:
		return (v as Array).map(whole)
	if v is Dictionary:
		var out := {}
		for k: Variant in v:
			out[k] = whole(v[k])
		return out
	return v


static func normalized_character(t: Dictionary) -> Dictionary:
	var c := t.duplicate(true)
	for k: String in ["level", "xp", "hp", "max_hp", "ac", "gold_cp", "prof_bonus", "speed",
			"passive_perception", "spell_dc", "spell_attack"]:
		if c.has(k):
			c[k] = int(c[k])
	for k: String in ["abilities", "skills", "saves", "inventory", "spent"]:
		var m := {}
		for id: String in c.get(k, {}):
			m[id] = int(c[k][id])
		c[k] = m
	if c.get("slots_max") is Array:
		c["slots_max"] = (c["slots_max"] as Array).map(func(v: Variant) -> int: return int(v))
	var dev := {}
	for dir: String in c.get("development", {}):
		dev[dir] = {"xp": int(c["development"][dir].get("xp", 0)), "skills": (c["development"][dir].get("skills", []) as Array).map(func(x: Variant) -> String: return str(x))}
	c["development"] = dev
	var bags := {}
	for id: String in c.get("bags", {}):
		var contents := {}
		for it: String in c["bags"][id].get("contents", {}):
			contents[it] = int(c["bags"][id]["contents"][it])
		bags[id] = {"kind": str(c["bags"][id].get("kind", "")), "contents": contents}
		if c["bags"][id].has("copies"):
			bags[id]["copies"] = whole(c["bags"][id]["copies"])
	c["bags"] = bags
	for k: String in ["copies", "study", "bonds", "family", "heists", "orgs", "offices", "towns", "faith", "debts"]:  # v0.7.25 food batches, v0.7.30 study, v0.7.31 bonds: whole numbers only
		if c.has(k):
			c[k] = whole(c[k])
	c["conditions"] = c.get("conditions", [])
	var body := {}  # v0.7.22.5: age, build, height — ids of rules.body
	for k: String in c.get("body", {}):
		body[k] = str(c["body"][k])
	c["body"] = body
	var effects: Array = []
	for e: Variant in c.get("effects", []):
		if e is Dictionary:
			effects.append(whole((e as Dictionary).duplicate(true)))
	c["effects"] = effects
	c["next_effect"] = int(c.get("next_effect", 1))
	c["temp_hp"] = int(c.get("temp_hp", 0))  # v0.7.10
	c["exhaustion"] = int(c.get("exhaustion", 0))
	if c.get("needs") is Dictionary and not (c["needs"] as Dictionary).is_empty():  # v0.7.23: the levels stay fractions
		var n: Dictionary = c["needs"]
		for k: String in ["food", "water"]:
			n[k] = {"level": float(n[k].get("level", 100.0)), "at": int(n[k].get("at", 0))}
		n["done"] = whole(n.get("done", {}))
	if c.has("diseases"):  # v0.7.23.1: diseases still incubating
		var sick: Array = []
		for d: Variant in c["diseases"]:
			if d is Dictionary:
				sick.append({"id": str(d.get("id", "")), "onset": int(d.get("onset", 0))})
		c["diseases"] = sick
	if c.get("disease_met") is Dictionary:
		c["disease_met"] = whole(c["disease_met"])
	c["concentration"] = str(c.get("concentration", ""))
	c["concentration_ends"] = int(c.get("concentration_ends", -1))
	c["may_prepare"] = bool(c.get("may_prepare", false))
	c["attuned"] = (c.get("attuned", []) as Array).map(func(v: Variant) -> String: return str(v))  # v0.7.12
	if c.get("ammo_left") is Dictionary:
		c["ammo_left"] = whole(c["ammo_left"])
	if c.get("stowed") is Dictionary:
		c["stowed"] = whole(c["stowed"])
	return c


func next_turn_id() -> String:
	turn_counter += 1
	return "t-%d" % turn_counter


func next_check_id() -> String:
	check_counter += 1
	return "c-%d" % check_counter


func next_effect_id() -> String:
	effect_counter += 1
	return "e-%d" % effect_counter


func append(entry: Dictionary) -> Dictionary:
	chat.append(entry)
	if str(entry.get("kind", "")) == KIND_EFFECT and not (entry.get("lines", []) as Array).is_empty():  # v0.7.14.4
		chronicle.append(Fact.of(self, " · ".join(entry["lines"]), room_id))
		if chronicle.size() > CHRONICLE_MAX:
			chronicle = chronicle.slice(chronicle.size() - CHRONICLE_MAX)
	return entry


## The chronicle for the master: the last `n` facts away from mere walking, «день 2, 09:12, Таверна — …».
func chronicle_tail(world: Dictionary, n: int) -> Array[String]:
	var out: Array[String] = []
	for e: Dictionary in chronicle:
		var t := str(e["text"])
		if t.begins_with("Переход:") and not t.contains(" · ") or t.begins_with("Путь:") and not t.contains(" · "):
			continue
		out.append("день %d, %s, %s — %s" % [Fact.day(e), Fact.clock(e), world["rooms"].get(str(e["room"]), {}).get("name", e["room"]), t])
	return out.slice(maxi(0, out.size() - n))


## The NPC remembers a fact about the hero (the same fact twice is kept once).
func remember(npc_id: String, text: String) -> void:
	if npc_id.is_empty() or text.strip_edges().is_empty():
		return
	var list: Array = Being.view(self, npc_id).get("memory", [])
	if list.any(func(m: Dictionary) -> bool: return str(m["text"]) == text):
		return
	list.append(Fact.of(self, text, room_id))
	Being.of(self, npc_id)["memory"] = list.slice(maxi(0, list.size() - NPC_MEMORY_MAX))


## What the NPC remembers, «день 2 — …», the newest `n`.
func memory_of(npc_id: String, n: int = NPC_MEMORY_MAX) -> Array[String]:
	var out: Array[String] = []
	for m: Dictionary in Being.view(self, npc_id).get("memory", []):
		out.append("день %d — %s" % [Fact.day(m), m["text"]])
	return out.slice(maxi(0, out.size() - n))


## The NPC's attitude; one the hero has not dealt with yet — by the reputation of its place (v0.7.17).
func attitude(id: String) -> int:
	var b := Being.view(self, id)
	return int(b.get("attitude", b.get("attitude_base", 0)))


## Moves an NPC's attitude by `delta` within rules.attitude_range (v0.7.7: the range is data, not code).
func shift_attitude(id: String, delta: int, data: Dictionary) -> void:
	var r := attitude_bounds(data)
	Being.of(self, id)["attitude"] = clampi(attitude(id) + delta, r.x, r.y)


static func attitude_bounds(data: Dictionary) -> Vector2i:
	var r: Array = data["rules"].get("attitude_range", [-3, 3])
	return Vector2i(int(r[0]), int(r[1]))


func in_conversation() -> bool:
	return mode == MODE_SOCIAL or mode == MODE_TRADE


## Foes the master summoned this turn (effect start_combat): the fight starts after the turn. Not saved.
var pending_fight: Array = []

## The fight about to start, kept only in the pre-fight save {foes, source} (v0.7.2): the hero is already in the
## encounter room there, and an encounter starts only on entering — loading that save starts this fight again.
var fight_on_load: Dictionary = {}


static func player_entry(text: String) -> Dictionary:
	return {"kind": KIND_PLAYER, "text": text}


static func dm_entry(text: String, turn_id: String) -> Dictionary:
	return {"kind": KIND_DM, "text": text, "turn_id": turn_id}


static func npc_entry(id: String, npc_name: String, text: String, turn_id: String) -> Dictionary:
	return {"kind": KIND_NPC, "npc_id": id, "name": npc_name, "text": text, "turn_id": turn_id}


static func effect_entry(lines: Array[String]) -> Dictionary:
	return {"kind": KIND_EFFECT, "lines": lines}


static func system_entry(key: String, args: Dictionary = {}) -> Dictionary:
	return {"kind": KIND_SYSTEM, "key": key, "args": args}


static func check_entry(params: Dictionary, result: Dictionary) -> Dictionary:
	var e := result.duplicate()
	e["kind"] = KIND_CHECK
	e["skill"] = str(params.get("skill", ""))
	e["save"] = str(params.get("save", ""))
	e["ability"] = str(params.get("ability", ""))
	if params.get("advantage_reason") != null and not str(params["advantage_reason"]).is_empty():
		e["advantage_reason"] = str(params["advantage_reason"])
	return e


## Player / master / NPC lines for the turn snapshot, newest last, within `max_chars` (ADR-0009 §4).
func history(max_chars: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var used := 0
	for i in range(chat.size() - 1, -1, -1):
		var e := chat[i]
		var role := ""
		var text := ""
		match str(e["kind"]):
			KIND_PLAYER:
				role = "player"
				text = str(e["text"])
			KIND_DM:
				role = "dm"
				text = str(e["text"])
			KIND_NPC:
				role = "npc"
				text = "%s: %s" % [e.get("name", ""), e["text"]]
			KIND_EFFECT:
				# Applied effects stay in the history so the master does not charge or give the same thing twice.
				role = "dm"
				text = "[Движок уже применил: %s]" % " · ".join(e.get("lines", []))
		if role.is_empty():
			continue
		used += text.length()
		if used > max_chars and not out.is_empty():
			break
		out.push_front({"role": role, "text": text})
	return out


## Short info for the slot list.
func meta() -> Dictionary:
	var preview := ""
	for i in range(chat.size() - 1, -1, -1):
		if str(chat[i]["kind"]) in [KIND_DM, KIND_NPC]:
			preview = str(chat[i]["text"]).left(80)
			break
	return {"turns": turn_counter, "preview": preview, "created_at": created_at,
		"character": str(character.get("name", "")), "room_id": room_id, "world_id": world_id,
		"day": day, "level": int(character.get("level", 1))}


func to_dict(kept_chat: int) -> Dictionary:
	return {
		"seed": game_seed,
		"rng_state": str(rng.state),  # 64-bit: a JSON number would lose precision
		"turn_counter": turn_counter,
		"check_counter": check_counter,
		"effect_counter": effect_counter,
		"chat": chat.slice(maxi(0, chat.size() - kept_chat)),
		"options": options,
		"option_costs": option_costs,
		"option_checks": option_checks,
		"tracked_quest": tracked_quest,
		"created_at": created_at,
		"world_id": world_id,
		"world_version": world_version,
		"settings": settings,
		"room_id": room_id,
		"mode": mode,
		"npc_id": npc_id,
		"character": character,
		"beings": beings,
		"being_counter": being_counter,
		"items": items,
		"flags": flags,
		"summaries": summaries,
		"locks": locks,
		"knows": knows,
		"layouts": layouts,
		"visited": visited,
		"day": day,
		"merchants": merchants,
		"quests_done": quests_done,
		"short_rests": short_rests,
		"march_day": march_day,
		"march_minutes": march_minutes,
		"rested_at": rested_at,
		"awake_saves": awake_saves,
		"combat": combat,
		"encounters_done": encounters_done,
		"encounters_passed": encounters_passed,
		"encounters_peace": encounters_peace,
		"factions": factions,
		"sneaking": sneaking,
		"minute": minute,
		"quests_active": quests_active,
		"quest_parts": quest_parts,
		"traps": traps,
		"caches_taken": caches_taken,
		"sneak_noticed": sneak_noticed,
		"fight_on_load": fight_on_load,
		"props": props,
		"shop_closed": shop_closed,
		"notes": notes,
		"generated": generated,
		"reputation": reputation,
		"crimes": crimes,
		"wanted": wanted,
		"arrest": arrest,
		"let_go": let_go,
		"arrest_tried": arrest_tried,
		"lurking": lurking,
		"captive": captive,
		"talk_creature": talk_creature,
		"trespass_warned": trespass_warned,
		"permits": permits,
		"permit_asked": permit_asked,
		"ways": ways,
		"described": described,
		"quests_failed": quests_failed,
		"reward_spent": reward_spent,
		"magic_given": magic_given,
		"chronicle": chronicle,
		"ledger": ledger,
		"dialogue_log": dialogue_log,
		"location_log": location_log,
	}


static func from_dict(saved: Dictionary) -> GameSession:
	var d: Dictionary = whole(saved)
	var s := GameSession.new()
	s.game_seed = int(d.get("seed", 0))
	s.rng.seed = s.game_seed
	s.rng.state = str(d.get("rng_state", "0")).to_int()
	s.turn_counter = int(d.get("turn_counter", 0))
	s.check_counter = int(d.get("check_counter", 0))
	s.effect_counter = int(d.get("effect_counter", 0))
	for e: Variant in d.get("chat", []):
		if e is Dictionary:
			s.chat.append(_normalized(e))
	for o: Variant in d.get("options", []):
		s.options.append(str(o))
	for c: Variant in d.get("option_costs", []):
		s.option_costs.append(int(c))
	s.tracked_quest = str(d.get("tracked_quest", ""))
	for ch: Variant in d.get("option_checks", []):
		s.option_checks.append(ch if ch is Dictionary else {})
	s.created_at = str(d.get("created_at", ""))
	s.world_id = str(d.get("world_id", ""))
	s.world_version = str(d.get("world_version", ""))
	s.settings = d.get("settings", {})
	s.room_id = str(d.get("room_id", ""))
	s.mode = str(d.get("mode", MODE_EXPLORATION))
	s.npc_id = str(d.get("npc_id", ""))
	s.character = normalized_character(d.get("character", {}))
	s.items = d.get("items", {})
	s.beings = whole(d.get("beings", {}))
	s.being_counter = int(d.get("being_counter", 0))
	for f: Variant in d.get("flags", []):
		s.flags.append(str(f))
	s.summaries = d.get("summaries", {})
	s.locks = d.get("locks", {})
	for key: String in s.locks:
		_normalized(s.locks[key]["result"])
	s.knows = d.get("knows", {})
	s.layouts = d.get("layouts", {})
	for v: Variant in d.get("visited", []):
		s.visited.append(str(v))
	s.day = int(d.get("day", 1))
	s.short_rests = int(d.get("short_rests", 0))
	s.march_day = int(d.get("march_day", 1))
	s.march_minutes = int(d.get("march_minutes", 0))
	s.rested_at = int(d.get("rested_at", 480))
	s.awake_saves = int(d.get("awake_saves", 0))
	s.combat = _normalized_combat(d.get("combat", {}))
	for e: Variant in d.get("encounters_done", []):
		s.encounters_done.append(str(e))
	for e: Variant in d.get("encounters_passed", []):
		s.encounters_passed.append(str(e))
	for e: Variant in d.get("encounters_peace", []):
		s.encounters_peace.append(str(e))
	s.factions = whole(d.get("factions", {}))
	s.sneaking = bool(d.get("sneaking", false))
	s.minute = int(d.get("minute", 480))
	for q: String in d.get("quests_active", {}):
		s.quests_active[q] = int(d["quests_active"][q])
	for q: String in d.get("quest_parts", {}):
		s.quest_parts[q] = (d["quest_parts"][q] as Array).map(func(x: Variant) -> int: return int(x))
	s.traps = d.get("traps", {})
	for k: Variant in d.get("caches_taken", []):
		s.caches_taken.append(str(k))
	s.sneak_noticed = str(d.get("sneak_noticed", ""))
	var fight: Variant = d.get("fight_on_load", {})
	s.fight_on_load = (fight as Dictionary).duplicate(true) if fight is Dictionary else {}
	s.props = whole(d.get("props", {}))  # days and counters, the food batches lying there
	for room: String in s.props:  # whole numbers back from JSON: contents, the lock, when it was dropped (v0.7.22.8)
		for p: Variant in s.props[room]:
			if not (p is Dictionary):
				continue
			if p.get("contents") is Dictionary:
				var contents := {}
				for id: String in p["contents"]:
					contents[id] = int(p["contents"][id])
				p["contents"] = contents
			for k: String in ["lock_dc", "dropped_at"]:
				if p.has(k):
					p[k] = int(p[k])
	for n: String in d.get("shop_closed", {}):
		s.shop_closed[n] = int(d["shop_closed"][n])
	for e: Variant in d.get("crimes", []):
		if e is Dictionary:
			var cr: Dictionary = (e as Dictionary).duplicate(true)
			cr["witnesses"] = (cr.get("witnesses", []) as Array).map(func(x: Variant) -> String: return str(x))
			s.crimes.append(cr)
	for loc: String in d.get("wanted", {}):
		s.wanted[loc] = int(d["wanted"][loc])
	s.arrest = str(d.get("arrest", ""))
	for loc: String in d.get("let_go", {}):
		s.let_go[loc] = int(d["let_go"][loc])
	for how: Variant in d.get("arrest_tried", []):
		s.arrest_tried.append(str(how))
	s.lurking = (d.get("lurking", {}) as Dictionary).duplicate(true)
	s.captive = (d.get("captive", {}) as Dictionary).duplicate(true)
	s.talk_creature = str(d.get("talk_creature", ""))
	s.ways = whole(d.get("ways", {}))
	for sid: String in d.get("trespass_warned", {}):
		s.trespass_warned[sid] = int(d["trespass_warned"][sid])
	for sid: String in d.get("permits", {}):
		s.permits[sid] = str(d["permits"][sid])
	for n: String in d.get("permit_asked", {}):
		s.permit_asked[n] = int(d["permit_asked"][n])
	for r: String in d.get("described", {}):
		s.described[r] = int(d["described"][r])
	for q: Variant in d.get("quests_failed", []):
		s.quests_failed.append(str(q))
	s.reward_spent = int(d.get("reward_spent", 0))
	s.magic_given = int(d.get("magic_given", 0))
	s.ledger.assign(whole(d.get("ledger", [])))
	s.chronicle.assign(whole(d.get("chronicle", [])))  # a Fact's `at`: a whole number again after JSON
	s.notes.assign(whole(d.get("notes", [])))
	if d.get("generated") is Dictionary:
		s.generated = (d["generated"] as Dictionary).duplicate(true)
		if s.generated.has("site_facts"):
			s.generated["site_facts"] = whole(s.generated["site_facts"])
	for k: String in d.get("reputation", {}):
		s.reputation[k] = int(d["reputation"][k])
	for q: Variant in d.get("quests_done", []):
		s.quests_done.append(str(q))
	for id: String in d.get("merchants", {}):
		s.merchants[id] = _normalized_merchant(d["merchants"][id])
	for line: Variant in d.get("dialogue_log", []):
		s.dialogue_log.append(str(line))
	for line: Variant in d.get("location_log", []):
		s.location_log.append(str(line))
	return s


## JSON floats back to ints in a saved fight.
static func _normalized_combat(raw: Variant) -> Dictionary:
	if not (raw is Dictionary) or (raw as Dictionary).is_empty():
		return {}
	var c: Dictionary = (raw as Dictionary).duplicate(true)
	for k: String in ["round", "turn", "xp", "parley_ok", "parley_fail", "rev"]:
		if c.has(k):
			c[k] = int(c[k])
	for ch: Dictionary in c.get("chasers", []):
		for k: String in ["at", "x", "y"]:
			ch[k] = int(ch[k])
	for k: String in ["ok", "fail"]:
		if c.get("death_saves", {}).has(k):
			c["death_saves"][k] = int(c["death_saves"][k])
	for k: String in ["action", "bonus", "move", "attacks", "haste"]:
		if c.get("economy", {}).has(k):
			c["economy"][k] = int(c["economy"][k])
	for w: Dictionary in c.get("incoming", []):
		w["at"] = int(w["at"])
		for spec: Dictionary in w.get("foes", []):
			if spec.has("count"):
				spec["count"] = int(spec["count"])
	for spec: Dictionary in c.get("help", {}).get("enemies", []):
		if spec.has("count"):
			spec["count"] = int(spec["count"])
	return c


## The NPCs of a room who are alive (killed ones are gone from the world).
func npcs_alive(ids: Array[String]) -> Array[String]:
	return ids.filter(func(id: String) -> bool: return not Being.dead(self, id))


## The living pack NPCs in the room now: the room's variants by the world's flags (SceneRules, v0.7.14.1).
func npcs_here(world: Dictionary, room_id: String) -> Array[String]:
	return npcs_alive(SceneRules.npcs(self, world, room_id)).filter(func(id: String) -> bool: return not held_as_creature(id))


## A pack NPC knocked out in a fight lies as a creature of a room (v0.7.22.16): not a person of the scene till it wakes.
func held_as_creature(npc_id: String) -> bool:
	return Being.view(self, npc_id).has("creature")


static func _normalized_merchant(m: Dictionary) -> Dictionary:
	var out := m.duplicate(true)
	for k: String in ["purse_cp", "day", "haggle_pct", "haggle_failed_day", "haggles", "haggle_day"]:
		out[k] = int(out.get(k, 0))
	if out.has("fence_day"):  # the fence's restock (v0.7.33)
		out["fence_day"] = int(out["fence_day"])
	for key: String in ["stock", "sold", "extras"]:  # extras — the day's goods of the shop kind (v0.7.22.26)
		var qty := {}
		for id: String in out.get(key, {}):
			qty[id] = int(out[key][id])
		out[key] = qty
	if out.get("haggle_result") is Dictionary and not (out["haggle_result"] as Dictionary).is_empty():
		_normalized(out["haggle_result"])
	else:
		out["haggle_result"] = {}
	return out


## JSON brings every number back as float; check cards keep ints so a loaded session equals the saved one.
static func _normalized(e: Dictionary) -> Dictionary:
	if str(e.get("kind", KIND_CHECK)) == KIND_EFFECT and e.get("rolls") is Array:  # a line's rolls (v0.7.39.5)
		e["rolls"] = (e["rolls"] as Array).map(func(r: Variant) -> Variant: return _normalized(r) if r is Dictionary else r)
	if str(e.get("kind", KIND_CHECK)) != KIND_CHECK:
		return e
	for k: String in ["bonus", "total", "dc", "nat", "haggle_pct"]:
		if e.has(k):
			e[k] = int(e[k])
	if e.get("rolls") is Array:
		e["rolls"] = (e["rolls"] as Array).map(func(r: Variant) -> int: return int(r))
	return e
