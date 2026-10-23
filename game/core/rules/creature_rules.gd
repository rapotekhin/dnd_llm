class_name CreatureRules
extends RefCounted
## The creatures a fight leaves in the room (roadmap v0.7.22.11, big test #11, #13): a truce, a surrender or a
## knock-out no longer wipes the foes away — they stay as creatures of the room (s.creatures {room: [creature]}):
## {id, name, monster, state: truce | surrendered | unconscious, bound, led, since}. The hero ties up the beaten
## (`bind`), lets them go, leads a bound one along (it moves with the hero), talks to them (a master's turn) or
## attacks them again (a fight). Left alone they go: a knocked-out one wakes and slips away, a truce lasts its hours
## (rules.creatures). A pack NPC knocked out is a person of the world, not a creature — it just lives.


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"]["creatures"]


static func here(s: GameSession, room_id: String) -> Array:
	return s.creatures.get(room_id, [])


static func find(s: GameSession, room_id: String, id: String) -> Dictionary:
	for c: Dictionary in here(s, room_id):
		if str(c["id"]) == id:
			return c
	return {}


## After a fight that did not kill everyone: the foes that made a truce, surrendered or were knocked out stay. Lines.
static func after_fight(s: GameSession, data: Dictionary, room_id: String) -> Array[String]:
	var lines: Array[String] = []
	var list: Array = (s.creatures.get(room_id, []) as Array).duplicate()
	for fid: String in CombatRules.enemies(s, false):
		var f := CombatRules.fighter(s, fid)
		var state := str(f.get("status", ""))
		if not state in ["truce", "surrendered", "unconscious"] or not str(f.get("npc_id", "")).is_empty():
			continue
		s.creature_counter += 1
		list.append({"id": "c%d" % s.creature_counter, "name": str(f["name"]), "monster": str(f["monster"]), "state": state,
			"bound": false, "led": false, "since": TimeRules.abs_minute(s)})
		lines.append("%s — %s" % [f["name"], state_word(state)])
	if not list.is_empty():
		s.creatures[room_id] = list
	return lines


static func state_word(state: String) -> String:
	return {"truce": "перемирие", "surrendered": "сдался", "unconscious": "без сознания"}.get(state, state)


## «Гоблин 2 — сдался, связан, идёт с героем» — for the side panel and the master.
static func text(c: Dictionary) -> String:
	var bits: Array[String] = [state_word(str(c["state"]))]
	if bool(c.get("bound", false)):
		bits.append("связан")
	if bool(c.get("led", false)):
		bits.append("идёт с героем на привязи")
	return "%s — %s" % [c["name"], ", ".join(bits)]


## "" when the hero can do `what` (bind, free, lead, attack) with this creature now, else a localization key.
static func can(s: GameSession, id: String, what: String) -> String:
	var c := find(s, s.room_id, id)
	if c.is_empty():
		return "CREATURE_NONE"
	match what:
		"bind":
			if bool(c.get("bound", false)) or str(c["state"]) == "truce":
				return "CREATURE_CANNOT_BIND"
		"lead":
			if not bool(c.get("bound", false)):
				return "CREATURE_NOT_BOUND"
	return ""


## Does it (can first). Lines; an attack leaves s.pending_fight.
static func act(s: GameSession, data: Dictionary, id: String, what: String) -> Array[String]:
	var c := find(s, s.room_id, id)
	match what:
		"bind":
			c["bound"] = true
			return ["%s связан" % c["name"]]
		"lead":
			c["led"] = not bool(c.get("led", false))
			return ["%s %s" % [c["name"], "идёт за вами на верёвке" if bool(c["led"]) else "остаётся здесь, связанный"]]
		"free":
			(s.creatures[s.room_id] as Array).erase(c)
			return ["%s отпущен и уходит" % c["name"]]
		"attack":
			(s.creatures[s.room_id] as Array).erase(c)
			s.pending_fight = [{"monster": str(c["monster"]), "name": str(c["name"]), "col": 0, "by_hero": true}]
			return ["Вы нападаете: %s" % c["name"]]
	return []


## The led ones go with the hero from `from` to `to`.
static func follow(s: GameSession, from: String, to: String) -> void:
	if from == to:
		return
	var moving: Array = here(s, from).filter(func(c: Dictionary) -> bool: return bool(c.get("led", false)))
	if moving.is_empty():
		return
	for c: Dictionary in moving:
		(s.creatures[from] as Array).erase(c)
	var dest: Array = s.creatures.get(to, [])
	dest.append_array(moving)
	s.creatures[to] = dest


## Time passes: an unbound knocked-out one wakes and slips away, an unbound surrendered one runs, a truce ends —
## each after its rules.creatures minutes. Lines only for the hero's room.
static func tick(s: GameSession, data: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var now := TimeRules.abs_minute(s)
	var leave: Dictionary = cfg(data)["leave_minutes"]
	for room: String in s.creatures.keys():
		var keep: Array = []
		for c: Dictionary in s.creatures[room]:
			var limit := int(leave.get(str(c["state"]), 0))
			if bool(c.get("bound", false)) or limit <= 0 or now - int(c["since"]) < limit:
				keep.append(c)
			elif room == s.room_id:
				lines.append("%s уходит" % c["name"])
		if keep.is_empty():
			s.creatures.erase(room)
		else:
			s.creatures[room] = keep
	return lines


## For the master: [«Гоблин 2 [c3] — сдался, связан»].
static func snapshot(s: GameSession, room_id: String) -> Array[String]:
	var out: Array[String] = []
	for c: Dictionary in here(s, room_id):
		out.append("%s [%s]" % [text(c), c["id"]])
	return out
