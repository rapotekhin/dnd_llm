class_name PrepareRules
extends RefCounted
## The master readies ahead (v0.8.4.25, the author's decision of 2026-11-02, docs/production/master-prefetch.md): while the
## player plays, a second line of requests asks the master for what the hero will meet soon — the furnishing of the rooms
## within `depth` of the map's ways, the orders of a board, a quest of a person around (given only when the player asks)
## and the next act of a taken quest once the hero is on the last step of the current one. A readied effect is kept in
## s.prepared as the master proposed it and checked by the engine again when it is used, so a world that changed meanwhile
## refuses it and the live turn does the work as before. Numbers in rules.prepare.

const ROOMS := "rooms"
const BOARDS := "boards"
const QUESTS := "quests"
const ACTS := "acts"


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"].get("prepare", {})


static func on(data: Dictionary) -> bool:
	return bool(cfg(data).get("on", false))


static func part(s: GameSession, name: String) -> Dictionary:
	if not s.prepared.has(name):
		s.prepared[name] = {}
	return s.prepared[name]


## The rooms within `depth` steps of the map's open ways from the hero, nearest first, without the hero's own.
static func around(s: GameSession, data: Dictionary, depth: int) -> Array[String]:
	var seen := {s.room_id: 0}
	var out: Array[String] = []
	var front: Array[String] = [s.room_id]
	for d in range(1, depth + 1):
		var next: Array[String] = []
		for r: String in front:
			for x: String in WayRules.open_exits(s, data["world"], r):
				if seen.has(x) or WorldView.new(data["world"]).room(x).is_empty():
					continue
				seen[x] = d
				out.append(x)
				next.append(x)
		front = next
	return out


## What the room's furnishing stands on: its name, text, tags and the people who live or work there. Changed — the
## furnishing readied for it is thrown away.
static func fingerprint(s: GameSession, data: Dictionary, room: String) -> String:
	var r := SceneRules.room(s, data["world"], room)
	return str(hash([r.get("name", ""), r.get("description", ""), SceneRules.tags(s, data["world"], room), r.get("npcs", [])]))


## What to ready now, the most wanted first: the next act of a quest, then the rooms by distance (again when the hour,
## the weather or the people of one changed: its description is told for them), the boards, the people around. [{kind: act|furnish|board|quest, key, …}] without what is readied already or asked on the line (`busy`).
static func jobs(s: GameSession, data: Dictionary, busy: Array = []) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not on(data) or CombatRules.active(s):
		return out
	var c := cfg(data)
	var world: Dictionary = data["world"]
	for qid: String in s.quests_active:
		if QuestRules.on_last_step(s, world, qid):
			var key := "%s:%d" % [qid, int(QuestRules.quest(world, qid).get("built", 0)) + 1]
			if not part(s, ACTS).has(key) and not busy.has("act:" + key):
				out.append({"kind": "act", "key": key, "quest": qid})
	var rooms := around(s, data, int(c.get("depth", 2)))
	for room: String in rooms:
		var rec: Dictionary = part(s, ROOMS).get(room, {})
		if PropRules.needs_furnish(s, room) and not busy.has("furnish:" + room) \
				and (str(rec.get("ver", "")) != fingerprint(s, data, room) or str(rec.get("moment", "")) != moment(s, data, room)):
			out.append({"kind": "furnish", "key": room, "room": room})
	for room: String in [s.room_id] + rooms:
		for p: Dictionary in PropRules.room_props(s, room):
			if not QuestGen.is_board(data, p):
				continue
			var key := "%s:%s" % [room, p["id"]]
			var left := int(QuestGen.cfg(data)["max_offered"]) - QuestGen.offered_by(s, "board:" + key).size()
			if left > 0 and not part(s, BOARDS).has(key) and not busy.has("board:" + key):
				out.append({"kind": "board", "key": key, "room": room, "prop": str(p["id"]), "left": left})
	var today := TimeRules.today(s, s.prepared, "quests_today") + busy.filter(func(b: Variant) -> bool: return str(b).begins_with("quest:")).size()
	var near: Array[String] = [s.room_id]
	near.append_array(around(s, data, int(c.get("quest_depth", 1))))
	for room: String in near:
		for npc: String in s.npcs_here(world, room):
			if today >= int(c.get("quests_per_day", 0)):
				return out
			if part(s, QUESTS).has(npc) or busy.has("quest:" + npc) or not gives_work(s, data, npc):
				continue
			out.append({"kind": "quest", "key": npc, "npc": npc, "room": room})
			today += 1
	return out


## A person who may give the hero work: alive, not hostile, not with the hero, with no made quest of its own waiting.
static func gives_work(s: GameSession, data: Dictionary, npc: String) -> bool:
	return not Being.follows(s, npc) and not Being.dead(s, npc) and not SocialRules.refuses(s, data, npc) \
		and QuestGen.offered_by(s, npc).is_empty()


## The catalog things offered to the master for a room instead of a search: those of its kind, role and tags and of a
## trader who lives there, then everyday ones by the game's seed; up to rules.prepare.candidates.
static func candidates(s: GameSession, data: Dictionary, room: String) -> Array[String]:
	var c := cfg(data)
	var v := WorldView.new(data["world"])
	var cat: Dictionary = data["items"]["catalog"]
	var cap := int(PropRules.cfg(data)["item_value_cap_cp"])
	var own: Array = []
	own.append_array(c.get("by_kind", {}).get(LayoutRules.kind_of(v, data, room), []))
	own.append_array(c.get("by_role", {}).get(str(LayoutRules.fields(v.room(room)).get("role", "")), []))
	for tag: Variant in SceneRules.tags(s, data["world"], room):
		own.append_array(c.get("by_tag", {}).get(str(tag), []))
	for npc: Variant in v.room(room).get("npcs", []):
		var kind := TradeRules.kind_of(data["rules"], v.npc(str(npc)))
		if not kind.is_empty():
			var row: Dictionary = TradeRules.kinds(data["rules"])[kind]
			own.append_array((row.get("stock", {}) as Dictionary).keys())
			own.append_array(row.get("extras", {}).get("pool", []))
	var daily: Array = (c.get("everyday", []) as Array).duplicate()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([s.game_seed, room])
	for i in range(daily.size() - 1, 0, -1):  # the everyday ones in an order of this game and room
		var j := rng.randi_range(0, i)
		var x: Variant = daily[i]
		daily[i] = daily[j]
		daily[j] = x
	var out: Array[String] = []
	for id: Variant in own + daily:
		var def: Dictionary = cat.get(str(id), {})
		if not def.is_empty() and not out.has(str(id)) and int(def.get("value_cp", 0)) <= cap:
			out.append(str(id))
		if out.size() >= int(c.get("candidates", 40)):
			break
	return out


## The engine's frame of a job: what the master readies, the place, its people; the hero is not in it.
static func frame(s: GameSession, data: Dictionary, job: Dictionary) -> String:
	var v := WorldView.new(data["world"])
	var lines: Array[String] = []
	match str(job["kind"]):
		"act":
			return QuestGen.act_frame(s, data, str(job["quest"]))
		"furnish":
			var room := str(job["room"])
			var r := SceneRules.room(s, data["world"], room)
			lines.append("[prepare furnish | room %s]" % room)
			lines.append("Комната: %s — %s." % [v.location(v.location_id(room)).get("name", ""), r.get("name", room)])
			lines.append("Описание: %s" % r.get("description", ""))
			lines.append("Вид места: %s; теги: %s; %s." % [LayoutRules.kind_of(v, data, room), ", ".join(SceneRules.tags(s, data["world"], room)),
				"под крышей" if SceneRules.indoor(s, data["world"], room) else "под открытым небом"])
			lines.append("Люди комнаты: %s." % _people(s, data, PropRules.owners(s, data, room)))
			lines.append("Сейчас здесь: %s." % _people(s, data, s.npcs_here(data["world"], room)))
			var weather := WeatherRules.at(s, data, v.location_id(room))
			lines.append("Время: %s, %s; погода: %s." % [TimeRules.part_name(s, data), TimeRules.clock(s),
				WeatherRules.kind_name(data, weather) if not weather.is_empty() else "без примет"])
			var marks := MapSpots.words(s, data, room)
			if not marks.is_empty():
				lines.append("Места комнаты: %s." % ", ".join(marks))
			lines.append("Кандидаты (item_id — название, цена):")
			for id: String in candidates(s, data, room):
				var def: Dictionary = data["items"]["catalog"][id]
				lines.append("- %s — %s (%s)" % [id, def.get("name", id), Money.format(int(def.get("value_cp", 0)))])
		"board":
			var room := str(job["room"])
			var p := PropRules.find(s, room, str(job["prop"]))
			lines.append("[prepare board | room %s | prop %s | left %d]" % [room, job["prop"], int(job["left"])])
			lines.append("Доска: «%s» [%s], %s — %s." % [p.get("name", ""), job["prop"], v.location(v.location_id(room)).get("name", ""), v.room(room).get("name", room)])
			if not str(p.get("text", "")).is_empty():
				lines.append("На ней уже: %s" % p["text"])
			lines.append("Округа: %s" % v.location(v.location_id(room)).get("description", ""))
		"quest":
			var npc := str(job["npc"])
			var n := v.npc(npc)
			var room := str(job["room"])
			lines.append("[prepare quest | giver %s]" % npc)
			lines.append("Заказчик: %s [%s] — %s; %s, %s." % [v.npc_name(npc), npc, n.get("role", ""), v.room(room).get("name", room),
				v.location(v.location_id(room)).get("name", "")])
			for k: String in ["personality", "description"]:
				if not str(n.get(k, "")).is_empty():
					lines.append(str(n[k]))
			var hooks: Array = v.room(room).get("hooks", [])
			if not hooks.is_empty():
				lines.append("Зацепки места: %s" % "; ".join(hooks))
	return "\n".join(lines)


static func _people(s: GameSession, data: Dictionary, ids: Array) -> String:
	if ids.is_empty():
		return "никого"
	var v := WorldView.new(data["world"])
	return ", ".join(ids.map(func(id: Variant) -> String: return "%s [%s], %s" % [v.npc_name(str(id)), id, v.npc(str(id)).get("role", "")]))


## The engine adds to each effect of a job's turn: the room a furnishing is for, the room of a board or a giver, `ahead`
## for an act.
static func ahead_of(job: Dictionary) -> Dictionary:
	match str(job["kind"]):
		"furnish":
			return {"room": str(job["room"])}
		"act":
			return {"ahead": true}
	return {"at": str(job["room"])}


## What came back from a job's turn is kept: its effects as the master proposed them; a furnishing with the room's
## description (`told`) and the moment it was written for.
static func keep(s: GameSession, data: Dictionary, job: Dictionary, effects: Array[Dictionary], told := "") -> void:
	if effects.is_empty():
		return
	match str(job["kind"]):
		"furnish":
			var room := str(job["room"])
			part(s, ROOMS)[room] = {"effect": effects[0], "ver": fingerprint(s, data, room), "told": told.strip_edges(),
				"moment": moment(s, data, room)}
		"board":
			part(s, BOARDS)[str(job["key"])] = effects
		"quest":
			part(s, QUESTS)[str(job["npc"])] = effects[0]
			TimeRules.count(s, s.prepared, "quests_today")
		"act":
			part(s, ACTS)[str(job["key"])] = effects[0]


## What a room's readied description stands on beside its furnishing: the part of the day, the weather and who is there.
static func moment(s: GameSession, data: Dictionary, room: String) -> String:
	var here := s.npcs_here(data["world"], room).filter(func(n: String) -> bool: return not Being.follows(s, n))  # they come with the hero
	here.sort()
	return str(hash([TimeRules.part(s, data), WeatherRules.at(s, data, WorldView.new(data["world"]).location_id(room)), here]))


## The description readied with the furnishing of `room`, while the room, the hour, the weather and its people are as
## they were; "" — the master's entry turn tells it.
static func told(s: GameSession, data: Dictionary, room: String) -> String:
	var rec: Dictionary = part(s, ROOMS).get(room, {})
	if rec.is_empty() or str(rec.get("ver", "")) != fingerprint(s, data, room) or str(rec.get("moment", "")) != moment(s, data, room):
		return ""
	return str(rec.get("told", ""))


## The furnishing readied for `room`, if the room is still as it was; {} — none (a stale one is thrown away).
static func furnishing(s: GameSession, data: Dictionary, room: String) -> Dictionary:
	var rec: Dictionary = part(s, ROOMS).get(room, {})
	part(s, ROOMS).erase(room)
	return rec.get("effect", {}) if not rec.is_empty() and str(rec.get("ver", "")) == fingerprint(s, data, room) else {}


static func orders(s: GameSession, room: String, prop: String) -> Array:
	var out: Array = part(s, BOARDS).get("%s:%s" % [room, prop], [])
	part(s, BOARDS).erase("%s:%s" % [room, prop])
	return out


static func quest_of(s: GameSession, npc: String) -> Dictionary:
	return part(s, QUESTS).get(npc, {})


static func act_of(s: GameSession, quest_id: String, act: int) -> Dictionary:
	var key := "%s:%d" % [quest_id, act]
	var out: Dictionary = part(s, ACTS).get(key, {})
	part(s, ACTS).erase(key)
	return out
