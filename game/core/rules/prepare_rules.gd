class_name PrepareRules
extends RefCounted
## The master readies ahead (v0.8.4.25, the author's decision of 2026-11-02, docs/production/master-prefetch.md): while the
## player plays, a second line of requests asks the master for what the hero will meet soon — the furnishing of the rooms
## within `depth` of the map's ways, the orders of a board, a quest of a person around (given only when the player asks)
## and the next act of a quest: the first of an offered one, the next of a taken one within rules.prepare.act_steps steps
## (v0.8.4.30), built on this line also when the quest already waits for it, so the game goes on meanwhile. A readied effect is kept in
## s.prepared as the master proposed it and checked by the engine again when it is used, so a world that changed meanwhile
## refuses it and the live turn does the work as before. Numbers in rules.prepare.

const ROOMS := "rooms"
const BOARDS := "boards"
const QUESTS := "quests"
const ACTS := "acts"
const GOAL := "goal"


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


## What to ready now, the most wanted first: the next act of a quest, the boards (the hero's own first: they do not
## stale with the hour, v0.8.4.25.4), then the rooms by distance (again when the hour, the weather or the people of one
## changed: its description is told for them), the people around. [{kind: act|board|furnish|quest, key, …}] without
## what is readied already or asked on the line (`busy`).
static func jobs(s: GameSession, data: Dictionary, busy: Array = []) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not on(data) or CombatRules.active(s):
		return out
	var c := cfg(data)
	var world: Dictionary = data["world"]
	var made: Array = s.quests_active.keys()  # the taken first, then the offered ones for their first act
	made.append_array(WorldGen.generated(s).get("quests", {}).keys().filter(func(q: String) -> bool: return not s.quests_active.has(q)))
	for qid: String in made:
		if QuestRules.ahead(s, world, qid, int(c.get("act_steps", 1000))):
			var key := "%s:%d" % [qid, int(QuestRules.quest(world, qid).get("built", 0)) + 1]
			if not part(s, ACTS).has(key) and not busy.has("act:" + key):
				out.append({"kind": "act", "key": key, "quest": qid})
	var giver := GoalRules.quest_due(s, data)  # v0.8.4.36: the quest for the hero's life goal, from the last clue's giver
	if not giver.is_empty() and not part(s, GOAL).has(giver) and not busy.has("goal:" + giver) 			and TimeRules.today(s, s.prepared, "goal_tries") < int(c.get("goal_per_day", 2)):
		out.append({"kind": "goal", "key": giver, "npc": giver, "room": Where.npc_room(s, data, giver)})
	if bool(c.get("setbacks", false)):  # v0.8.4.31: the act after a failed check or a lost fight, readied beside the act after a success
		for qid: String in s.quests_active.keys():
			var sb := setback_preview(s, data, qid)
			if sb.is_empty():
				continue
			var key := "%s:%d!%d" % [qid, int(sb["act"]) + 1, int(sb["index"])]
			if not part(s, ACTS).has(key) and not busy.has("act:" + key):
				out.append({"kind": "act", "key": key, "quest": qid, "setback": sb})
	var rooms := around(s, data, int(c.get("depth", 2)))
	for room: String in [s.room_id] + rooms:
		PropRules.ensure_fixed(s, data, room)  # a pack's board is there before the room is furnished
		for p: Dictionary in PropRules.room_props(s, room):
			if not QuestGen.is_board(data, p):
				continue
			var key := "%s:%s" % [room, p["id"]]
			var left := int(QuestGen.cfg(data)["max_offered"]) - QuestGen.offered_by(s, "board:" + key).size()
			if left > 0 and not part(s, BOARDS).has(key) and not busy.has("board:" + key):
				out.append({"kind": "board", "key": key, "room": room, "prop": str(p["id"]), "left": left})
	for room: String in rooms:
		var rec: Dictionary = part(s, ROOMS).get(room, {})
		if PropRules.needs_furnish(s, room) and not busy.has("furnish:" + room) \
				and (str(rec.get("ver", "")) != fingerprint(s, data, room) or str(rec.get("moment", "")) != moment(s, data, room)):
			out.append({"kind": "furnish", "key": room, "room": room})
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
			return QuestGen.act_frame(s, data, str(job["quest"]), job.get("setback", {}))
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
		"quest", "goal":
			var npc := str(job["npc"])
			var n := SceneRules.npc(s, data["world"], npc)  # as the world is now (v0.8.4.42.18)
			var room := str(job["room"])
			lines.append("[prepare quest | giver %s%s]" % [npc, " | goal" if job["kind"] == "goal" else ""])
			if job["kind"] == "goal":
				var c := s.character
				lines.append("Жизненная цель героя: «%s» (%s; направление — %s)." % [GoalRules.goal(c)["text"], data["rules"]["goal"]["names"].get(str(GoalRules.goal(c).get("scale", "")), ""),
					", ".join(GoalRules.goal(c).get("concepts", []))])
				if not GoalRules.clues(c).is_empty():
					lines.append("Зацепки, что герой уже узнал (задание продолжает их, не спорит с ними): %s." % GoalRules.clues_text(c, data))
				if not GoalRules.item_line(s, data).is_empty():
					lines.append("%s. Задание ведёт к этой вещи — её и даст его последний акт." % GoalRules.item_line(s, data))
				else:  # v0.8.4.42.19: the goal itself is the quest's finale
					lines.append("Финал задания — сама цель: её исполняет последний акт; подготовка (оружие, союзники, путь) — ранние акты, не отдельное задание. Сложность — не легче «%s»." % 						data["rules"]["quest_gen"]["difficulties"].get(str(GoalRules.cfg(data).get("quest_difficulty", {}).get(str(GoalRules.goal(c).get("scale", "")), "")), {}).get("name", ""))
			lines.append("Заказчик: %s [%s] — %s; %s, %s." % [v.npc_name(npc), npc, n.get("role", ""), v.room(room).get("name", room),
				v.location(v.location_id(room)).get("name", "")])
			for k: String in ["personality", "description"]:
				if not str(n.get(k, "")).is_empty():
					lines.append(str(n[k]))
			lines.append_array(QuestGen.person_past(s, data, npc))  # v0.8.4.30: a new quest goes on from what happened
			var facts := s.chronicle_tail(data["world"], 8)
			if not facts.is_empty():
				lines.append("Летопись (последнее): " + "; ".join(facts))
			var hooks: Array = v.room(room).get("hooks", [])
			if not hooks.is_empty():
				lines.append("Зацепки места: %s" % "; ".join(hooks))
	return "\n".join(lines)


static func _people(s: GameSession, data: Dictionary, ids: Array) -> String:
	if ids.is_empty():
		return "никого"
	var v := WorldView.new(data["world"])
	return ", ".join(ids.map(func(id: Variant) -> String: return "%s [%s], %s" % [OwnerRules.name_of(s, data, str(id)), id,
		"враги этого места" if str(id).begins_with(OwnerRules.FOES) else v.npc(str(id)).get("role", "")]))


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
		"goal":
			var e: Dictionary = effects[0].duplicate(true)
			e["for_goal"] = true  # whatever the master wrote: this is the goal's quest
			part(s, GOAL)[str(job["npc"])] = e
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


## The quests for the goal readied ahead, taken out to be laid wherever the hero is: [effect], each `at` the room its
## giver stands in now (offered by it there, as a person's readied quest).
static func goal_quests(s: GameSession, data: Dictionary) -> Array:
	var out: Array = []
	for npc: String in part(s, GOAL):
		var e: Dictionary = (part(s, GOAL)[npc] as Dictionary).duplicate(true)
		var room := Where.npc_room(s, data, npc)
		if not room.is_empty():
			e["at"] = room
		out.append(e)
	part(s, GOAL).clear()
	return out


## The setback the current step of a taken quest by acts may have (a `find` or a `fight`), as `QuestRules.setback` would
## set it: {act, index, step, why}; {} — the step cannot go wrong.
static func setback_preview(s: GameSession, data: Dictionary, quest_id: String) -> Dictionary:
	var q := QuestRules.quest(data["world"], quest_id)
	var step := QuestRules.current(s, data["world"], quest_id)
	var kind := QuestRules.setback_kind(step)
	if not q.has("acts") or kind.is_empty():
		return {}
	return {"act": int(step.get("act", maxi(0, int(q.get("built", 1)) - 1))), "index": int(s.quests_active[quest_id]), "step": str(step["text"]),
		"why": QuestRules.setback_why(step, kind)}


## A step went wrong (QuestRules.setback): the acts readied for its quest are stale; the one readied for this failure,
## if any, becomes the act to lay.
static func take_setback(s: GameSession, quest_id: String, act: int, index: int) -> void:
	var acts := part(s, ACTS)
	var ready: Dictionary = acts.get("%s:%d!%d" % [quest_id, act, index], {})
	for key: String in acts.keys():
		if key.get_slice(":", 0) == quest_id:
			acts.erase(key)
	if not ready.is_empty():
		acts["%s:%d" % [quest_id, act]] = ready


static func act_of(s: GameSession, quest_id: String, act: int) -> Dictionary:
	var key := "%s:%d" % [quest_id, act]
	var out: Dictionary = part(s, ACTS).get(key, {})
	part(s, ACTS).erase(key)
	return out
