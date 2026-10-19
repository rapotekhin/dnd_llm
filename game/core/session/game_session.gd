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
var created_at: String = ""

## The world pack of this game and its version when the game started.
var world_id: String = ""
var world_version: String = ""
## Master settings of the new game screen: dm_style, death_mode, violence, lines, veils (WorldPack.default_settings).
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
## Short rests taken today (ExplorationRules); a long rest resets it.
var short_rests: int = 0
## Ids of the pack quests the player completed (XpRules).
var quests_done: Array[String] = []
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
	c["condition_ends"] = c.get("condition_ends", {})
	c["concentration"] = str(c.get("concentration", ""))
	c["prepared_day"] = int(c.get("prepared_day", 1))
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
	return entry


func attitude(id: String) -> int:
	return int(attitudes.get(id, 0))


func in_conversation() -> bool:
	return mode == MODE_SOCIAL or mode == MODE_TRADE


## Foes the master summoned this turn (effect start_combat): the fight starts after the turn. Not saved.
var pending_fight: Array = []


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
		"combat": combat,
		"encounters_done": encounters_done,
		"dead_npcs": dead_npcs,
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
	s.combat = _normalized_combat(d.get("combat", {}))
	for e: Variant in d.get("encounters_done", []):
		s.encounters_done.append(str(e))
	for n: Variant in d.get("dead_npcs", []):
		s.dead_npcs.append(str(n))
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
	for k: String in ["round", "turn", "xp", "coins_cp"]:
		if c.has(k):
			c[k] = int(c[k])
	for id: String in c.get("fighters", {}):
		var f: Dictionary = c["fighters"][id]
		for k: String in ["hp", "max_hp", "ac", "col", "init"]:
			if f.has(k):
				f[k] = int(f[k])
	for k: String in ["ok", "fail"]:
		if c.get("death_saves", {}).has(k):
			c["death_saves"][k] = int(c["death_saves"][k])
	for k: String in ["action", "bonus", "move", "attacks"]:
		if c.get("economy", {}).has(k):
			c["economy"][k] = int(c["economy"][k])
	for l: Dictionary in c.get("loot", []):
		l["qty"] = int(l["qty"])
	return c


## The NPCs of a room who are alive (killed ones are gone from the world).
func npcs_alive(ids: Array[String]) -> Array[String]:
	return ids.filter(func(id: String) -> bool: return not dead_npcs.has(id))


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
