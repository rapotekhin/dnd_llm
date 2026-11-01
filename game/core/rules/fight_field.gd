class_name FightField
extends RefCounted
## What the squares of a fight do (v0.8.4): what a step lands on, a push, doors, things that block the way, the fire that
## spreads, who hears the fight, the ways out and those who run after the hero. The spaces come from FightGrid; a hazard and
## a fire are zones of `s.combat.zones`, the same record as a spell's.

const SHUT_FAST: Array[String] = ["DOOR_LOCKED", "DOOR_CLOSED_HOURS", "DOOR_ARCANE", "DOOR_SOLID"]


static func cfg(data: Dictionary) -> Dictionary:
	return FightGrid.cfg(data)


## What a fight finds on its map: the doors as they stand, the things that can be moved, the ground that hurts.
static func lay(s: GameSession, data: Dictionary) -> void:
	if s.combat.has("field"):
		return
	var m := FightGrid.map(s, data)
	var taken := FightGrid.bodies(s)
	var doors: Dictionary = s.combat["doors"]
	for d: Dictionary in m.get("doors", []):
		var at := Vector2i(int(d["x"]), int(d["y"]))
		var ends := _ends(m, d)
		if taken.has(at):
			doors[FightGrid.tag(at)] = {"open": true}
		elif bool(s.ways.get(WayRules.key(ends[0], ends[1]), {}).get("broken", false)):
			doors[FightGrid.tag(at)] = {"gone": true}
		elif SHUT_FAST.has(WayRules.blocked(s, data, ends[0], ends[1])):
			doors[FightGrid.tag(at)] = {"locked": true}
	var bl: Dictionary = cfg(data)["blocks"]
	var hz: Dictionary = cfg(data)["hazard"]
	var ground: Array = []
	var rows: Array = m["rows"]
	for y: int in rows.size():
		var row: String = rows[y]
		for x: int in row.length():
			if row[x] == str(bl["cell"]):
				s.combat["blocks"][FightGrid.tag(Vector2i(x, y))] = _block(data, str(bl["body"]), str(bl["name"]))
			elif row[x] == str(hz["cell"]):
				ground.append(FightGrid.tag(Vector2i(x, y)))
	if not ground.is_empty():
		(s.combat["zones"] as Array).append(_ground("hazard", hz, ground))
	for p: Dictionary in PropRules.room_props(s, s.room_id):
		var body := ThingRules.body(data, p)
		if (body.get("blocks", []) as Array).has("path"):
			for t: Dictionary in MapSpots.of(s, data, m):
				if str(t["ref"]) == "prop:" + str(p["id"]):
					var b := _block(data, str(p["body"]), str(p["name"]))
					b["prop"] = str(p["id"])
					s.combat["blocks"][FightGrid.tag(Vector2i(int(t["x"]), int(t["y"])))] = b
	FightGrid.changed(s)


static func _ends(m: Dictionary, d: Dictionary) -> Array[String]:
	return [str(m["ids"][int(d["a"])]), str(m["ids"][int(d["b"])])]


## A zone of the ground: one kind with the zones of spells.
static func _ground(id: String, row: Dictionary, cells: Array) -> Dictionary:
	return {"spell": id, "name": str(row["name"]), "shape": {}, "follow": false, "dice": str(row["dice"]), "type": str(row["type"]), "save": "",
		"on": ["enter", "start"], "dc": 0, "slow": false, "cells": cells}


static func _block(data: Dictionary, body_id: String, name: String) -> Dictionary:
	var b: Dictionary = ThingRules.cfg(data)["bodies"].get(body_id, {})
	return {"body": body_id, "name": name, "hp": int(cfg(data)["blocks"]["hp"]), "weight": int(b.get("weight", 0)), "made_of": str(b.get("made_of", "wood"))}


## The start of a round: who came after the hero, the fire, who heard.
static func round_starts(s: GameSession, data: Dictionary, lines: Array[String]) -> void:
	chasers_arrive(s, data, lines)
	fire_round(s, data, lines)
	hear(s, data, lines)


## The squares a body walked this turn, for the map to play. Taken by the screen as `CombatRules.take_fx`.
static func note_walk(s: GameSession, who: String, trail: Array) -> void:
	if trail.is_empty():
		return
	var moves: Array = s.combat.get("moves", [])
	moves.append({"who": who, "path": trail})
	s.combat["moves"] = moves


static func take_moves(s: GameSession) -> Array:
	var out: Array = s.combat.get("moves", [])
	s.combat.erase("moves")
	return out


## The hero's square is the walk's too: after the fight it stands where it stopped. A door crossed — another room.
static func hero_stands(s: GameSession, data: Dictionary) -> void:
	if s.combat.has("field"):
		return
	var map := FightGrid.map(s, data)
	var at := FightGrid.cell(CombatRules.player(s))
	var room := WalkRules.room_of(map, at)
	if not room.is_empty() and room != s.room_id:
		s.room_id = room
		if not s.visited.has(room):
			s.visited.append(room)
	WalkRules.stand(s, map, s.room_id, at)


## The body walked into a square: what lies there acts on it. True when the walk stops.
static func stepped(s: GameSession, data: Dictionary, f: Dictionary, lines: Array[String]) -> bool:
	var g := FightGrid.grid(s, data)
	var bits := FightGrid.flags_at(g, FightGrid.cell(f))
	if bits & FightGrid.WET != 0 and f.has("burning"):
		f.erase("burning")
		lines.append("%s гасит пламя в воде" % f["name"])
	var hero := str(f.get("id")) == CombatRules.PLAYER
	var flying := CombatRules.airborne(s, data, f)
	if bits & FightGrid.PIT != 0 and not flying:
		_fall(s, data, f, lines)
		return true
	var before := lines.size()
	if not flying:
		lines.append_array(SpellEffects.zone_tick(s, data, f, "enter"))
	if hero:
		return int(s.character.get("hp", 0)) <= 0 or ConditionRules.has(s.character, "prone")
	return str(f.get("status")) != "active" or (lines.size() > before and CombatRules._has(f, "prone"))


static func _fall(s: GameSession, data: Dictionary, f: Dictionary, lines: Array[String]) -> void:
	var dmg := CombatRules.roll_dice(s.rng, str(cfg(data)["pit"]["dice"]))
	lines.append("%s падает в яму: %d" % [f["name"], dmg])
	CombatRules._hurt_any(s, data, f, dmg, lines, "bludgeoning")
	if str(f.get("id")) == CombatRules.PLAYER:
		if int(s.character.get("hp", 0)) > 0:
			lines.append_array(ConditionRules.impose(s, data, {"condition": "prone", "ends": {"rest": "short"}, "source": {"kind": "engine", "name": "яма"}}))
	elif str(f.get("status")) == "active":
		CombatRules._hold(f, "prone")


## Standing on this square hurts: the AI's fear of it.
static func hurts(s: GameSession, data: Dictionary, f: Dictionary) -> bool:
	for z: Dictionary in SpellEffects.zones(s):
		if not str(z.get("dice", "")).is_empty() and FightGrid.in_cells(f, FightGrid.zone_cells(s, data, z)):
			return true
	return false


## `t` is pushed `n` squares along `dir`, until a wall or a body stops it. A pit or a fire on the way does its work. Lines.
static func thrust(s: GameSession, data: Dictionary, t: Dictionary, dir: Vector2i, n: int, lines: Array[String]) -> void:
	var g := FightGrid.grid(s, data)
	var d := dir.sign()
	if d == Vector2i.ZERO:
		d = Vector2i.RIGHT
	var span := int(t.get("span", 1))
	var trail: Array = []
	for i: int in n:
		var next := FightGrid.cell(t) + d
		var occupied := FightGrid.bodies(s, str(t.get("id", "")))
		var free := true
		for c: Vector2i in FightGrid.body_at(next, span):
			if FightGrid.flags_at(g, c) & FightGrid.SOLID != 0 or occupied.has(c) or FightGrid.shut(s, g, c):
				free = false
		if not free:
			break
		FightGrid.put(t, next)
		trail.append(FightGrid.tag(next))
		if stepped(s, data, t, lines):
			break
	note_walk(s, str(t.get("id", "")), trail)
	if str(t.get("id")) == CombatRules.PLAYER and not trail.is_empty():
		hero_stands(s, data)


# --- doors -----------------------------------------------------------------------------------------------------


## A shut door the walker goes through is open from now on.
static func opens_on_way(s: GameSession, data: Dictionary, f: Dictionary, at: Vector2i, lines: Array[String]) -> void:
	var g := FightGrid.grid(s, data)
	if FightGrid.shut(s, g, at):
		(s.combat["doors"] as Dictionary)[FightGrid.tag(at)] = {"open": true}
		FightGrid.changed(s)
		lines.append("%s открывает дверь" % f["name"])


## The acts the hero has with what stands beside it, by name; `COMBAT_ACT_<NAME>` is the button.
static func acts(s: GameSession, data: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var d := door_near(s, data)
	if not d.is_empty():
		var g := FightGrid.grid(s, data)
		var at := Vector2i(int(d["x"]), int(d["y"]))
		if not FightGrid.shut(s, g, at):
			out.append("door_close")
		elif FightGrid.fast(s, g, at):
			out.append("door_force")
			if bool(FightGrid.door_state(s, at).get("barred", false)):
				out.append("door_unbar")
		else:
			out.append("door_bar")
			if _has_key(s, data, d):
				out.append("door_lock")
	if block_near(s) != FightGrid.NONE:
		out.append("block_push")
		out.append("block_smash")
	return out


## The door beside the hero, a row of the map's `doors`, {} — none or gone. A door someone stands in cannot be shut.
static func door_near(s: GameSession, data: Dictionary) -> Dictionary:
	var p := CombatRules.player(s)
	var taken := FightGrid.bodies(s)
	for d: Dictionary in FightGrid.map(s, data).get("doors", []):
		var at := Vector2i(int(d["x"]), int(d["y"]))
		if FightGrid.dist_to(p, at) <= 1 and not taken.has(at) and not bool(FightGrid.door_state(s, at).get("gone", false)):
			return d
	return {}


static func _has_key(s: GameSession, data: Dictionary, d: Dictionary) -> bool:
	var ends := _ends(FightGrid.map(s, data), d)
	var id := str(WayRules.def(data, ends[0], ends[1]).get("key", ""))
	return not id.is_empty() and int(s.character.get("inventory", {}).get(id, 0)) > 0


## "" — the act can be done now; a key otherwise.
static func why_not(s: GameSession, data: Dictionary, how: String) -> String:
	if not acts(s, data).has(how):
		return "COMBAT_BAD_TARGET"
	if how == "block_push":
		var at := block_near(s)
		var b: Dictionary = s.combat["blocks"][FightGrid.tag(at)]
		if int(b["weight"]) > CharacterRules.ability(s.character, "str") * int(cfg(data)["blocks"]["per_str"]):
			return "COMBAT_TOO_HEAVY"
		if not _block_can_go(s, data, at + (at - FightGrid.cell(CombatRules.player(s))).sign()):
			return "COMBAT_BLOCK_STUCK"
	return ""


## The hero's act with a door or a thing. Lines.
static func act(s: GameSession, data: Dictionary, how: String, lines: Array[String]) -> void:
	var c := s.character
	if how.begins_with("block"):
		if how == "block_push":
			_push_block(s, data, lines)
		else:
			_smash_block(s, data, lines)
		return
	var d := door_near(s, data)
	var at := Vector2i(int(d["x"]), int(d["y"]))
	var doors: Dictionary = s.combat["doors"]
	var key := FightGrid.tag(at)
	var ends := _ends(FightGrid.map(s, data), d)
	match how:
		"door_close":
			doors.erase(key)
			lines.append("%s закрывает дверь" % c["name"])
		"door_bar":
			doors[key] = {"barred": true}
			lines.append("%s подпирает дверь" % c["name"])
		"door_unbar":
			doors.erase(key)
			lines.append("%s убирает подпорку" % c["name"])
		"door_lock":
			doors[key] = {"locked": true}
			WayRules.lock(s, ends[0], ends[1])
			lines.append("%s запирает дверь на ключ" % c["name"])
		"door_force":
			var r := Roll.hero(s, data, {"what": "Выломать дверь", "skill": "athletics", "dc": _door_dc(s, data, at, d)})
			if bool(r["ok"]):
				_break_door(s, data, at, d)
				lines.append("%s выбивает дверь" % c["name"])
			else:
				lines.append("Дверь выдержала: %d против Сл %d" % [int(r["total"]), _door_dc(s, data, at, d)])
	FightGrid.changed(s)


static func _door_dc(s: GameSession, data: Dictionary, at: Vector2i, d: Dictionary) -> int:
	var ends := _ends(FightGrid.map(s, data), d)
	var bar := int(cfg(data)["doors"]["bar_plus"]) if bool(FightGrid.door_state(s, at).get("barred", false)) else 0
	return int(WayRules.dcs(s, data, ends[0], ends[1])["force"]) + bar


static func _break_door(s: GameSession, data: Dictionary, at: Vector2i, d: Dictionary) -> void:
	(s.combat["doors"] as Dictionary)[FightGrid.tag(at)] = {"gone": true}
	var ends := _ends(FightGrid.map(s, data), d)
	WayRules.break_down(s, ends[0], ends[1])
	FightGrid.changed(s)


# --- things --------------------------------------------------------------------------------------------------


## The thing beside the hero, NONE — none.
static func block_near(s: GameSession) -> Vector2i:
	var at := FightGrid.cell(CombatRules.player(s))
	for d: Vector2i in WalkRules.DIRS:
		if (s.combat.get("blocks", {}) as Dictionary).has(FightGrid.tag(at + d)):
			return at + d
	return FightGrid.NONE


static func _block_can_go(s: GameSession, data: Dictionary, to: Vector2i) -> bool:
	var g := FightGrid.grid(s, data)
	return FightGrid.flags_at(g, to) & FightGrid.SOLID == 0 and not FightGrid.bodies(s).has(to) and not FightGrid.shut(s, g, to)


static func _push_block(s: GameSession, data: Dictionary, lines: Array[String]) -> void:
	var at := block_near(s)
	var to := at + (at - FightGrid.cell(CombatRules.player(s))).sign()
	var b: Dictionary = s.combat["blocks"][FightGrid.tag(at)]
	_lift(s, data, at)
	var g := FightGrid.grid(s, data)
	if FightGrid.flags_at(g, to) & FightGrid.PIT != 0:
		lines.append("%s: %s падает в яму" % [s.character["name"], b["name"]])
	else:
		s.combat["blocks"][FightGrid.tag(to)] = b
		(s.combat.get("cleared", {}) as Dictionary).erase(FightGrid.tag(to))
		lines.append("%s толкает: %s" % [s.character["name"], b["name"]])
	FightGrid.changed(s)
	if (s.combat["fires"] as Dictionary).has(FightGrid.tag(to)):
		kindle(s, data, [to] as Array[Vector2i], lines)


## The thing is off its square: a square of the map's own thing is floor from now on.
static func _lift(s: GameSession, data: Dictionary, at: Vector2i) -> void:
	var key := FightGrid.tag(at)
	(s.combat["blocks"] as Dictionary).erase(key)
	var rows: Array = FightGrid.map(s, data)["rows"]
	if str(rows[at.y])[at.x] == str(cfg(data)["blocks"]["cell"]):
		if not s.combat.has("cleared"):
			s.combat["cleared"] = {}
		s.combat["cleared"][key] = true
	FightGrid.changed(s)


static func _smash_block(s: GameSession, data: Dictionary, lines: Array[String]) -> void:
	var c := s.character
	var at := block_near(s)
	var b: Dictionary = s.combat["blocks"][FightGrid.tag(at)]
	var w := CombatRules.weapon_profile(c, data, s.items, str(c.get("equipped", {}).get("main_hand", "")))
	var ac := int(ThingRules.material(data, {"material": b["made_of"]}).get("ac", 15))
	var r := Roll.hero(s, data, {"what": "Удар по вещи", "parts": WayRules._hit_parts(w), "bonus": w["to_hit"], "dc": ac})
	if not bool(r["ok"]):
		lines.append("%s: удар по вещи — %d против КД %d, без толку" % [w["name"], int(r["total"]), ac])
		return
	var dmg := maxi(1, CombatRules.roll_dice(s.rng, str(w["dice"]), int(r["nat"]) == 20) + int(w["bonus"]))
	b["hp"] = int(b["hp"]) - dmg
	if int(b["hp"]) > 0:
		lines.append("%s: %d урона по вещи — %s ещё цел(а)" % [w["name"], dmg, b["name"]])
		return
	lines.append("%s: %d урона — %s разбит(а)" % [w["name"], dmg, b["name"]])
	_ruin(s, data, at, lines)


## A thing of the room is gone for good; one of the map stays gone only in this fight.
static func _ruin(s: GameSession, data: Dictionary, at: Vector2i, lines: Array[String]) -> void:
	var b: Dictionary = s.combat["blocks"][FightGrid.tag(at)]
	_lift(s, data, at)
	for p: Dictionary in PropRules.room_props(s, s.room_id):
		if str(p["id"]) == str(b.get("prop", "")):
			lines.append_array(ThingRules.ruin(s, data, s.room_id, p, "broken"))


# --- fire ----------------------------------------------------------------------------------------------------


static func _burnable(s: GameSession, data: Dictionary, at: Vector2i) -> bool:
	var key := FightGrid.tag(at)
	if (s.combat.get("oil", {}) as Dictionary).has(key):
		return true
	var b: Dictionary = (s.combat.get("blocks", {}) as Dictionary).get(key, {})
	if not b.is_empty():
		return bool(ThingRules.material(data, {"material": b["made_of"]}).get("burns", false))
	var g := FightGrid.grid(s, data)
	if at.x < 0 or at.y < 0 or at.x >= int(g["w"]) or at.y >= int(g["h"]):
		return false
	return bool(data["layouts"]["cells"].get(str(FightGrid.map(s, data)["rows"][at.y])[at.x], {}).get("burns", false))


## Fire touches `cells`: what burns there catches. Oil and wood; bare stone does not.
static func kindle(s: GameSession, data: Dictionary, cells: Array[Vector2i], lines: Array[String]) -> void:
	var lit := false
	for at: Vector2i in cells:
		if _burnable(s, data, at) and not (s.combat["fires"] as Dictionary).has(FightGrid.tag(at)):
			_light(s, at)
			lit = true
	if lit:
		_sync_fire(s, data)
		lines.append("Огонь занимается")


static func _light(s: GameSession, at: Vector2i) -> void:
	var key := FightGrid.tag(at)
	s.combat["fires"][key] = int(s.combat["round"])
	(s.combat.get("oil", {}) as Dictionary).erase(key)


## A flask broken on a square: oil lies there, alchemist's fire burns at once.
static func splash(s: GameSession, data: Dictionary, at: Vector2i, fx: Dictionary, name: String, lines: Array[String]) -> void:
	if fx.has("burning"):
		_light(s, at)
		_sync_fire(s, data)
		lines.append("%s: клетка в огне" % name)
		return
	if not s.combat.has("oil"):
		s.combat["oil"] = {}
	s.combat["oil"][FightGrid.tag(at)] = true
	lines.append("%s: масло растекается по клетке" % name)
	if (s.combat["fires"] as Dictionary).has(FightGrid.tag(at)):
		kindle(s, data, [at] as Array[Vector2i], lines)


## The fires of a round: what stands beside a fire and burns catches, what burnt out goes, a thing with it.
static func fire_round(s: GameSession, data: Dictionary, lines: Array[String]) -> void:
	var fires: Dictionary = s.combat.get("fires", {})
	if fires.is_empty():
		return
	var now := int(s.combat["round"])
	var last := int(cfg(data)["fire"]["rounds"])
	var catching: Array[Vector2i] = []
	for key: String in fires.keys():
		var at := FightGrid.y_x(key)
		for d: Vector2i in WalkRules.DIRS:
			if not fires.has(FightGrid.tag(at + d)) and _burnable(s, data, at + d):
				catching.append(at + d)
		if now - int(fires[key]) >= last:
			fires.erase(key)
			if (s.combat["blocks"] as Dictionary).has(key):
				lines.append("%s сгорает" % s.combat["blocks"][key]["name"])
				_ruin(s, data, at, lines)
	for at: Vector2i in catching:
		_light(s, at)
	_sync_fire(s, data)
	if fires.is_empty():
		lines.append("Огонь гаснет")


## The burning squares are one zone: the same record as a spell's.
static func _sync_fire(s: GameSession, data: Dictionary) -> void:
	var zones: Array = SpellEffects.zones(s)
	var cells: Array = (s.combat["fires"] as Dictionary).keys()
	for z: Dictionary in zones.duplicate():
		if str(z["spell"]) == "fire":
			zones.erase(z)
	if not cells.is_empty():
		zones.append(_ground("fire", cfg(data)["fire"], cells))
	s.combat["zones"] = zones


# --- noise ---------------------------------------------------------------------------------------------------


## What is left of the noise from `a` at `b`: below 0 it is not heard.
static func _loud(g: Dictionary, c: Dictionary, a: Vector2i, b: Vector2i) -> int:
	var left := int(c["reach"]) - WalkRules.distance(a, b)
	for at: Vector2i in FightGrid.line_of(a, b):
		if FightGrid.flags_at(g, at) & FightGrid.OPAQUE != 0:
			left -= int(c["wall"])
	return left


## The fight is heard. Those who hear stand where they stand: the guard and the foes' own come, the peaceful hide.
static func hear(s: GameSession, data: Dictionary, lines: Array[String]) -> void:
	if s.combat.has("field") or s.combat.has("arena"):
		return
	var c: Dictionary = cfg(data)["noise"]
	var g := FightGrid.grid(s, data)
	var m: Dictionary = g["map"]
	var at := FightGrid.cell(CombatRules.player(s))
	for room: String in m["ids"]:
		var cells := MapSpots._cells(m, data["layouts"], room)
		if cells.is_empty():
			continue
		var spot: Vector2i = cells[cells.size() / 2]
		if room == s.room_id or _loud(g, c, at, spot) >= 0:
			_wakes(s, data, room, spot, lines)
	for e: Dictionary in m["exits"]:
		var spot := Vector2i(int(e["ax"]), int(e["ay"]))
		if _loud(g, c, at, spot) >= int(c["beyond"]):
			_wakes(s, data, str(e["to"]), spot, lines)


static func _wakes(s: GameSession, data: Dictionary, room: String, spot: Vector2i, lines: Array[String]) -> void:
	if not s.combat.has("heard"):
		s.combat["heard"] = []
	var heard: Array = s.combat["heard"]
	var world := WorldView.new(data["world"])
	var enc: Dictionary = SceneRules.room(s, data["world"], room).get("encounter", {})
	var side := str(s.combat.get("faction", ""))
	if not enc.is_empty() and not side.is_empty() and str(enc.get("faction", "")) == side and not heard.has(str(enc["id"])) and str(enc["id"]) != str(s.combat.get("encounter", "")) \
			and not s.encounters_done.has(str(enc["id"])) and not s.encounters_peace.has(str(enc["id"])):
		heard.append(str(enc["id"]))
		var joined: Array = s.combat.get("joined", [])
		joined.append(str(enc["id"]))
		s.combat["joined"] = joined
		_comes(s, data, EncounterRules.heads(s, data, room, enc), spot, false, lines)
	var fought := {}
	for id: String in s.combat["fighters"]:
		fought[str(CombatRules.fighter(s, id).get("npc_id", ""))] = true
	var by_hero := CombatRules.enemies(s).any(func(id: String) -> bool: return not str(CombatRules.fighter(s, id).get("npc_id", "")).is_empty())
	var guards: Array = CrimeRules.law(data, world.location_id(room)).get("guards", [])
	for id: String in s.npcs_here(world.world, room):
		if fought.has(id) or heard.has(id) or Being.follows(s, id):
			continue
		var n := world.npc(id)
		if guards.has(id):
			heard.append(id)
			_comes(s, data, [{"monster": str(n.get("monster", CombatRules.cfg(data)["default_npc_monster"])), "name": str(n.get("name", id)),
				"desc": str(n.get("description", "")), "npc_id": id, "by_hero": by_hero, "law": true}], spot, not by_hero, lines)
		elif room == s.room_id:
			heard.append(id)
			var scared: Array = s.combat.get("scared", [])
			scared.append(id)
			s.combat["scared"] = scared
			lines.append("%s прячется от боя" % n.get("name", id))


static func _comes(s: GameSession, data: Dictionary, foes: Array, spot: Vector2i, ally: bool, lines: Array[String]) -> void:
	var names: Array = foes.map(func(f: Dictionary) -> String: return str(f.get("name", data["monsters"][f["monster"]]["name"])))
	(s.combat["incoming"] as Array).append({"at": int(s.combat["round"]) + 1, "side": "right", "foes": foes, "names": names, "x": spot.x, "y": spot.y, "ally": ally})
	lines.append("На шум боя идут: " + ", ".join(names))
static func ways_out(s: GameSession, data: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for e: Dictionary in FightGrid.map(s, data).get("exits", []):
		out.append(Vector2i(int(e["ax"]), int(e["ay"])))
	return out


static func at_way_out(s: GameSession, data: Dictionary, at: Vector2i) -> bool:
	if s.combat.has("field"):
		var g := FightGrid.grid(s, data)
		return at.x <= 0 or at.y <= 0 or at.x >= int(g["w"]) - 1 or at.y >= int(g["h"]) - 1
	return ways_out(s, data).has(at)


## "" when a way out stands open at the square; the rim of an open field always does. A key otherwise.
static func way_out_shut(s: GameSession, data: Dictionary, at: Vector2i) -> String:
	if not at_way_out(s, data, at):
		return "COMBAT_NOT_AT_EXIT"
	var e := _exit_at(s, data, at)
	return "" if e.is_empty() else WayRules.blocked(s, data, str(e["room"]), str(e["to"]))


static func _exit_at(s: GameSession, data: Dictionary, at: Vector2i) -> Dictionary:
	for e: Dictionary in FightGrid.map(s, data).get("exits", []):
		if Vector2i(int(e["ax"]), int(e["ay"])) == at:
			return e
	return {}


## Who runs after the hero through `at`: the free bodies within `grid.pursuit` squares of it.
static func _chasers(s: GameSession, data: Dictionary, at: Vector2i) -> Array[String]:
	var out: Array[String] = []
	var near := int(cfg(data)["pursuit"])
	for id: String in CombatRules.enemies(s) + CombatRules.allies(s):
		var f := CombatRules.fighter(s, id)
		if FightGrid.dist_to(f, at) <= near and FightAI.steps(s, data, f) > 0:
			out.append(id)
	return out


## The hero goes through the way out under its feet. With nobody near the fight is over; with someone near it goes on beyond:
## the hero stands on the new map, those near come through the same way in a round or two, the others stay behind.
static func leave(s: GameSession, data: Dictionary, lines: Array[String]) -> void:
	var at := FightGrid.cell(CombatRules.player(s))
	var e := _exit_at(s, data, at)
	var foe_near := _chasers(s, data, at).any(func(id: String) -> bool: return str(CombatRules.fighter(s, id).get("side")) == "enemy")
	if e.is_empty() or not foe_near:
		s.combat["outcome"] = "player_fled"
		if not e.is_empty():
			s.combat["flee_to"] = str(e["to"])
		lines.append("%s выходит из боя" % s.character["name"])
		return
	var chasers := _chasers(s, data, at)
	s.room_id = str(e["to"])
	if not s.visited.has(s.room_id):
		s.visited.append(s.room_id)
	s.combat["map"] = s.room_id
	s.combat["doors"] = {}
	s.combat["blocks"] = {}
	s.combat["fires"] = {}
	s.combat["zones"] = SpellEffects.zones(s).filter(func(z: Dictionary) -> bool: return bool(z.get("follow", false)))
	FightGrid.changed(s)
	var map := FightGrid.map(s, data)
	var came := WalkRules.settle(s, data, map)
	var p := CombatRules.player(s)
	FightGrid.put(p, came)
	s.combat.erase("cleared")
	s.combat.erase("oil")
	lay(s, data)
	var bounds: Array = cfg(data)["pursuit_rounds"]
	var list: Array = []
	for id: String in CombatRules.enemies(s) + CombatRules.allies(s):
		var f := CombatRules.fighter(s, id)
		f["status"] = "away" if chasers.has(id) else "left"
		if chasers.has(id):
			list.append({"id": id, "at": int(s.combat["round"]) + s.rng.randi_range(int(bounds[0]), int(bounds[1])), "x": came.x, "y": came.y})
	s.combat["chasers"] = list
	FightGrid.changed(s)
	lines.append("%s выбегает: %s — за ним погоня" % [s.character["name"], SceneRules.room(s, data["world"], s.room_id).get("name", s.room_id)])


## Somebody is still on the way through the door.
static func chased(s: GameSession) -> bool:
	return not (s.combat.get("chasers", []) as Array).is_empty()


## Foes stayed behind on another map.
static func left_foes(s: GameSession) -> bool:
	return CombatRules.enemies(s, false).any(func(id: String) -> bool: return str(CombatRules.fighter(s, id).get("status")) == "left")


## The start of a round: those whose time came stand at the way they came by.
static func chasers_arrive(s: GameSession, data: Dictionary, lines: Array[String]) -> void:
	var still: Array = []
	for c: Dictionary in s.combat.get("chasers", []):
		if int(c["at"]) > int(s.combat["round"]):
			still.append(c)
			continue
		var f := CombatRules.fighter(s, str(c["id"]))
		FightGrid.put(f, FightGrid.free_near(s, data, Vector2i(int(c["x"]), int(c["y"])), int(f.get("span", 1))))
		f["status"] = "active"
		lines.append("%s выбегает следом" % f["name"])
	s.combat["chasers"] = still


## It stands at a door barred or locked with no other way: it throws itself at it, by the SRD's Strength against the door.
static func force_way(s: GameSession, data: Dictionary, f: Dictionary, lines: Array[String]) -> void:
	var g := FightGrid.grid(s, data)
	for d: Dictionary in FightGrid.map(s, data).get("doors", []):
		var at := Vector2i(int(d["x"]), int(d["y"]))
		if FightGrid.dist_to(f, at) > 1 or not FightGrid.shut(s, g, at):
			continue
		var dc := _door_dc(s, data, at, d)
		var total := Roll.d20(s.rng) + CharacterRules.mod(int(CombatRules._monster(data, f)["abilities"].get("str", 10)))
		if total >= dc:
			_break_door(s, data, at, d)
			lines.append("%s выбивает дверь" % f["name"])
		else:
			lines.append("%s бьётся в дверь: %d против Сл %d" % [f["name"], total, dc])
		return
	lines.append("%s стоит на месте" % f["name"])
