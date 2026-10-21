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
var attitudes: Dictionary = {}
var flags: Array[String] = []
## Failed skill checks: "skill|target" → {"result", "advantages"} (ExplorationRules); cleared by a long rest.
var locks: Dictionary = {}
## room_id → ids of secrets noticed or found there.
var revealed: Dictionary = {}
## Rooms the player has been to, in order (the map).
var visited: Array[String] = []
## Days since the start; a long rest starts the next one.
var day: int = 1
## npc_id → merchant state (TradeRules): purse_cp, stock {item_id: qty}, day of the last restock, haggle_pct of
## the current visit, haggle_failed_day, haggle_result. Created from the pack on the first trade.
var merchants: Dictionary = {}
## The fight in progress (CombatRules), {} when there is none.
var combat: Dictionary = {}
## Encounters of the pack already fought (CombatRules) and NPCs killed in a fight.
var encounters_done: Array[String] = []
var dead_npcs: Array[String] = []
## The «Красться» toggle of exploration (v0.6.2).
var sneaking: bool = false
## Minutes since midnight (TimeRules, v0.6.3); a new game starts in the morning.
var minute: int = 480
## Quests with steps taken: {quest_id: step index} (QuestRules, v0.6.3).
var quests_active: Dictionary = {}
## Parts of "all" steps already announced: {quest_id: [index]} (QuestRules, v0.6.4).
var quest_parts: Dictionary = {}
## Spent traps {"room:secret": "sprung" | "disarmed"} and emptied caches ["room:secret"] (v0.6.3).
var traps: Dictionary = {}
var caches_taken: Array[String] = []
## Pickpocketed NPCs: {npc_id: day} — one theft per NPC a day (v0.6.5).
var pickpocketed: Dictionary = {}
## The room where people noticed the sneaking player: no sneaking there until they leave (v0.6.5).
var sneak_noticed: String = ""
## Kinds of foes the player knows (inspected in a fight, v0.6.6): their numbers show on the cards.
var known_monsters: Array[String] = []
## Things of the rooms {room_id: [prop]} (PropRules), NPCs' pockets {npc_id: [entry]} (TheftRules), shops closed
## for the player {npc_id: day} and thefts caught {npc_id: day} (v0.7.0).
var props: Dictionary = {}
var pockets: Dictionary = {}
var shop_closed: Dictionary = {}
var caught_by: Dictionary = {}

## Crimes of the hero (CrimeRules, v0.7.14): [{id, victim, room, location, at, witnesses, known, settled}]; wanted
## {location_id: abs minute since}; the room where the guard holds the hero ("" — free); bodies {npc_id: room_id}
## and the searched ones; quests failed with a dead NPC (QuestRules.on_death).
var crimes: Array[Dictionary] = []
var wanted: Dictionary = {}
var arrest: String = ""
var bodies: Dictionary = {}
var searched: Array[String] = []
var quests_failed: Array[String] = []
## The chronicle (v0.7.14.4): every line of the engine in the chat with its day, minute and room
## [{day, minute, room, text}], the newest CHRONICLE_MAX — the journal's «Хроника» and the master's memory.
const CHRONICLE_MAX := 400
var chronicle: Array[Dictionary] = []
## What the master gave (cp of coins and things) since the last long rest (EffectEngine, v0.7.14.3).
var reward_spent: int = 0
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
var npc_memory: Dictionary = {}
## What NPCs granted by words (v0.7.15.2): npc_id → {pct, until_day} — a trader's discount; npc_id → the day of
## its last free service.
var discounts: Dictionary = {}
var favors: Dictionary = {}
## Reputation in settlements (v0.7.17, ReputationRules): location_id → points; the attitude of the people not dealt
## with yet by it: npc_id → attitude (recomputed when the reputation changes).
var reputation: Dictionary = {}
var attitude_base: Dictionary = {}
## NPC secrets the hero learned (v0.7.15.3): "npc_id:secret_id".
var secrets_told: Array[String] = []
## "location:<id>" and "dialogue:<npc_id>" → text from summary.request.
var summaries: Dictionary = {}
## Lines of the current conversation, the events for its summary.
var dialogue_log: Array[String] = []
## Events since the last location summary.
var location_log: Array[String] = []


static func create(new_seed: int, now: String, start_room: String, new_character: Dictionary) -> GameSession:
	var s := GameSession.new()
	s.game_seed = new_seed
	s.rng.seed = new_seed
	s.created_at = now
	s.room_id = start_room
	s.character = normalized_character(new_character)
	return s


## JSON brings numbers back as floats: the counters, scores and quantities of a character become ints again.
static func normalized_character(t: Dictionary) -> Dictionary:
	var c := t.duplicate(true)
	for k: String in ["level", "xp", "hp", "max_hp", "ac", "gold_cp", "hit_dice_used", "prof_bonus", "speed",
			"passive_perception", "spell_dc", "spell_attack"]:
		if c.has(k):
			c[k] = int(c[k])
	for k: String in ["abilities", "skills", "saves", "inventory", "resources_used"]:
		var m := {}
		for id: String in c.get(k, {}):
			m[id] = int(c[k][id])
		c[k] = m
	for k: String in ["slots_used", "slots_max"]:
		if c.get(k) is Array:
			c[k] = (c[k] as Array).map(func(v: Variant) -> int: return int(v))
	c["conditions"] = c.get("conditions", [])
	var effects: Array = []
	for e: Variant in c.get("effects", []):
		if e is Dictionary:
			effects.append(_whole_numbers((e as Dictionary).duplicate(true)))
	c["effects"] = effects
	c["next_effect"] = int(c.get("next_effect", 1))
	c["temp_hp"] = int(c.get("temp_hp", 0))  # v0.7.10
	if c.get("wild_shape") is Dictionary:
		c["wild_shape"] = _whole_numbers(c["wild_shape"])
	c["exhaustion"] = int(c.get("exhaustion", 0))
	c["concentration"] = str(c.get("concentration", ""))
	c["concentration_ends"] = int(c.get("concentration_ends", -1))
	c["prepared_day"] = int(c.get("prepared_day", 1))
	c["attuned"] = (c.get("attuned", []) as Array).map(func(v: Variant) -> String: return str(v))  # v0.7.12
	var used := {}
	for id: Variant in c.get("charges_used", {}):
		used[str(id)] = int(c["charges_used"][id])
	c["charges_used"] = used
	if c.get("ammo_left") is Dictionary:
		c["ammo_left"] = _whole_numbers(c["ammo_left"])
	return c


## JSON brings every number back as a float: whole ones become ints again, all the way down (effects, the beast form).
static func _whole_numbers(d: Dictionary) -> Dictionary:
	for k: Variant in d.keys():
		var v: Variant = d[k]
		if v is float and is_equal_approx(v, roundf(v)):
			d[k] = int(v)
		elif v is Dictionary:
			d[k] = _whole_numbers(v)
	return d


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
		chronicle.append({"day": day, "minute": minute, "room": room_id, "text": " · ".join(entry["lines"])})
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
		out.append("день %d, %02d:%02d, %s — %s" % [int(e["day"]), int(e["minute"]) / 60, int(e["minute"]) % 60,
			world["rooms"].get(str(e["room"]), {}).get("name", e["room"]), t])
	return out.slice(maxi(0, out.size() - n))


## The NPC remembers a fact about the hero (the same fact twice is kept once).
func remember(npc_id: String, text: String) -> void:
	if npc_id.is_empty() or text.strip_edges().is_empty():
		return
	var list: Array = npc_memory.get(npc_id, [])
	if list.any(func(m: Dictionary) -> bool: return str(m["text"]) == text):
		return
	list.append({"day": day, "text": text})
	npc_memory[npc_id] = list.slice(maxi(0, list.size() - NPC_MEMORY_MAX))


## What the NPC remembers, «день 2 — …», the newest `n`.
func memory_of(npc_id: String, n: int = NPC_MEMORY_MAX) -> Array[String]:
	var out: Array[String] = []
	for m: Dictionary in npc_memory.get(npc_id, []):
		out.append("день %d — %s" % [int(m["day"]), m["text"]])
	return out.slice(maxi(0, out.size() - n))


## The NPC's attitude; one the hero has not dealt with yet — by the reputation of its place (v0.7.17).
func attitude(id: String) -> int:
	return int(attitudes.get(id, attitude_base.get(id, 0)))


## Moves an NPC's attitude by `delta` within rules.attitude_range (v0.7.7: the range is data, not code).
func shift_attitude(id: String, delta: int, data: Dictionary) -> void:
	var r := attitude_bounds(data)
	attitudes[id] = clampi(attitude(id) + delta, r.x, r.y)


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
		"character": str(character.get("name", "")), "room_id": room_id, "world_id": world_id}


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
		"created_at": created_at,
		"world_id": world_id,
		"world_version": world_version,
		"settings": settings,
		"room_id": room_id,
		"mode": mode,
		"npc_id": npc_id,
		"character": character,
		"items": items,
		"attitudes": attitudes,
		"flags": flags,
		"summaries": summaries,
		"locks": locks,
		"revealed": revealed,
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
		"dead_npcs": dead_npcs,
		"sneaking": sneaking,
		"minute": minute,
		"quests_active": quests_active,
		"quest_parts": quest_parts,
		"traps": traps,
		"caches_taken": caches_taken,
		"pickpocketed": pickpocketed,
		"sneak_noticed": sneak_noticed,
		"fight_on_load": fight_on_load,
		"known_monsters": known_monsters,
		"props": props,
		"pockets": pockets,
		"shop_closed": shop_closed,
		"caught_by": caught_by,
		"notes": notes,
		"npc_memory": npc_memory,
		"discounts": discounts,
		"favors": favors,
		"secrets_told": secrets_told,
		"reputation": reputation,
		"attitude_base": attitude_base,
		"crimes": crimes,
		"wanted": wanted,
		"arrest": arrest,
		"bodies": bodies,
		"searched": searched,
		"quests_failed": quests_failed,
		"reward_spent": reward_spent,
		"chronicle": chronicle,
		"dialogue_log": dialogue_log,
		"location_log": location_log,
	}


static func from_dict(d: Dictionary) -> GameSession:
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
	s.created_at = str(d.get("created_at", ""))
	s.world_id = str(d.get("world_id", ""))
	s.world_version = str(d.get("world_version", ""))
	s.settings = d.get("settings", {})
	s.room_id = str(d.get("room_id", ""))
	s.mode = str(d.get("mode", MODE_EXPLORATION))
	s.npc_id = str(d.get("npc_id", ""))
	s.character = normalized_character(d.get("character", {}))
	s.items = d.get("items", {})
	for id: String in d.get("attitudes", {}):
		s.attitudes[id] = int(d["attitudes"][id])
	for f: Variant in d.get("flags", []):
		s.flags.append(str(f))
	s.summaries = d.get("summaries", {})
	s.locks = d.get("locks", {})
	for key: String in s.locks:
		_normalized(s.locks[key]["result"])
	s.revealed = d.get("revealed", {})
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
	for n: Variant in d.get("dead_npcs", []):
		s.dead_npcs.append(str(n))
	s.sneaking = bool(d.get("sneaking", false))
	s.minute = int(d.get("minute", 480))
	for q: String in d.get("quests_active", {}):
		s.quests_active[q] = int(d["quests_active"][q])
	for q: String in d.get("quest_parts", {}):
		s.quest_parts[q] = (d["quest_parts"][q] as Array).map(func(x: Variant) -> int: return int(x))
	s.traps = d.get("traps", {})
	for k: Variant in d.get("caches_taken", []):
		s.caches_taken.append(str(k))
	for n: String in d.get("pickpocketed", {}):
		s.pickpocketed[n] = int(d["pickpocketed"][n])
	s.sneak_noticed = str(d.get("sneak_noticed", ""))
	var fight: Variant = d.get("fight_on_load", {})
	s.fight_on_load = (fight as Dictionary).duplicate(true) if fight is Dictionary else {}
	for m: Variant in d.get("known_monsters", []):
		s.known_monsters.append(str(m))
	s.props = d.get("props", {})
	s.pockets = d.get("pockets", {})
	for n: String in s.pockets:
		for e: Dictionary in s.pockets[n]:
			for k: String in ["cp", "qty", "dc"]:
				e[k] = int(e.get(k, 0))
	for n: String in d.get("shop_closed", {}):
		s.shop_closed[n] = int(d["shop_closed"][n])
	for n: String in d.get("caught_by", {}):
		s.caught_by[n] = int(d["caught_by"][n])
	for e: Variant in d.get("crimes", []):
		if e is Dictionary:
			var cr := (e as Dictionary).duplicate(true)
			cr["at"] = int(cr.get("at", 0))
			cr["witnesses"] = (cr.get("witnesses", []) as Array).map(func(x: Variant) -> String: return str(x))
			s.crimes.append(cr)
	for loc: String in d.get("wanted", {}):
		s.wanted[loc] = int(d["wanted"][loc])
	s.arrest = str(d.get("arrest", ""))
	for n: String in d.get("bodies", {}):
		s.bodies[n] = str(d["bodies"][n])
	for n: Variant in d.get("searched", []):
		s.searched.append(str(n))
	for q: Variant in d.get("quests_failed", []):
		s.quests_failed.append(str(q))
	s.reward_spent = int(d.get("reward_spent", 0))
	for e: Variant in d.get("chronicle", []):
		if e is Dictionary:
			s.chronicle.append({"day": int(e.get("day", 1)), "minute": int(e.get("minute", 0)), "room": str(e.get("room", "")), "text": str(e.get("text", ""))})
	for e: Variant in d.get("notes", []):
		if e is Dictionary:
			s.notes.append((e as Dictionary).duplicate())
	for id: String in d.get("discounts", {}):
		var dsc: Dictionary = d["discounts"][id]
		s.discounts[id] = {"pct": int(dsc.get("pct", 0)), "until_day": int(dsc.get("until_day", 0))}
	for id: String in d.get("favors", {}):
		s.favors[id] = int(d["favors"][id])
	for k: Variant in d.get("secrets_told", []):
		s.secrets_told.append(str(k))
	for k: String in d.get("reputation", {}):
		s.reputation[k] = int(d["reputation"][k])
	for k: String in d.get("attitude_base", {}):
		s.attitude_base[k] = int(d["attitude_base"][k])
	var mem: Variant = d.get("npc_memory", {})
	if mem is Dictionary:
		for id: String in mem:
			var list: Array = []
			for m: Variant in mem[id]:
				if m is Dictionary:
					list.append({"day": int(m.get("day", 1)), "text": str(m.get("text", ""))})
			s.npc_memory[id] = list
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
	for k: String in ["round", "turn", "xp", "coins_cp", "next_id", "parley_ok", "parley_fail"]:
		if c.has(k):
			c[k] = int(c[k])
	for id: String in c.get("fighters", {}):
		var f: Dictionary = c["fighters"][id]
		for k: String in ["hp", "max_hp", "ac", "col", "init"]:
			if f.has(k):
				f[k] = int(f[k])
		_whole_numbers(f)  # the riders of v0.7.13 (guided, slowed, oiled…) and the timers
	for z: Variant in c.get("zones", []):  # the spell zones of v0.7.13.5
		if z is Dictionary:
			_whole_numbers(z)
	for k: String in ["ok", "fail"]:
		if c.get("death_saves", {}).has(k):
			c["death_saves"][k] = int(c["death_saves"][k])
	for k: String in ["action", "bonus", "move", "attacks", "haste"]:
		if c.get("economy", {}).has(k):
			c["economy"][k] = int(c["economy"][k])
	for l: Dictionary in c.get("loot", []):
		l["qty"] = int(l["qty"])
	for w: Dictionary in c.get("incoming", []):
		w["at"] = int(w["at"])
		w["col"] = int(w["col"])
		for spec: Dictionary in w.get("foes", []):
			if spec.has("count"):
				spec["count"] = int(spec["count"])
	for spec: Dictionary in c.get("help", {}).get("enemies", []):
		if spec.has("count"):
			spec["count"] = int(spec["count"])
	return c


## The NPCs of a room who are alive (killed ones are gone from the world).
func npcs_alive(ids: Array[String]) -> Array[String]:
	return ids.filter(func(id: String) -> bool: return not dead_npcs.has(id))


## The living pack NPCs in the room now: the room's variants by the world's flags (SceneRules, v0.7.14.1).
func npcs_here(world: Dictionary, room_id: String) -> Array[String]:
	return npcs_alive(SceneRules.npcs(self, world, room_id))


static func _normalized_merchant(m: Dictionary) -> Dictionary:
	var out := m.duplicate(true)
	for k: String in ["purse_cp", "day", "haggle_pct", "haggle_failed_day"]:
		out[k] = int(out.get(k, 0))
	var stock := {}
	for id: String in out.get("stock", {}):
		stock[id] = int(out["stock"][id])
	out["stock"] = stock
	if out.get("haggle_result") is Dictionary and not (out["haggle_result"] as Dictionary).is_empty():
		_normalized(out["haggle_result"])
	else:
		out["haggle_result"] = {}
	return out


## JSON brings every number back as float; check cards keep ints so a loaded session equals the saved one.
static func _normalized(e: Dictionary) -> Dictionary:
	if str(e.get("kind", KIND_CHECK)) != KIND_CHECK:
		return e
	for k: String in ["bonus", "total", "dc", "nat", "haggle_pct"]:
		if e.has(k):
			e[k] = int(e[k])
	if e.get("rolls") is Array:
		e["rolls"] = (e["rolls"] as Array).map(func(r: Variant) -> int: return int(r))
	return e
