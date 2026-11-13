class_name FightField
extends RefCounted
## What the squares of a fight do (v0.8.4): what a step lands on, a push, doors, things that block the way, the fire that
## spreads, who hears the fight, the ways out and those who run after the hero. The spaces come from FightGrid; a hazard and
## a fire are zones of `s.combat.zones`, the same record as a spell's.

const SHUT_FAST: Array[String] = ["DOOR_LOCKED", "DOOR_CLOSED_HOURS", "DOOR_ARCANE", "DOOR_PRIVATE", "DOOR_SOLID"]


static func cfg(data: Dictionary) -> Dictionary:
	return FightGrid.cfg(data)


## What a fight finds on its map: the doors as they stand, the things that can be moved, the ground that hurts.
static func lay(s: GameSession, data: Dictionary) -> void:
	for id: String in s.combat["fighters"]:  # a spider's webs around it, on any field (v0.8.4.27.3)
		_lays(s, data, CombatRules.fighter(s, id))
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
		SpellEffects.add_zone(s, zone_of("hazard", hz, ground))
	for t: Dictionary in MapSpots.of(s, data, m):  # each square of a thing of the room: what its body bars (v0.8.4.43.23)
		if str(t.get("body", "")).is_empty():
			continue
		var b := _block(data, str(t["body"]), str(t["name"]))
		if int(b["flags"]) == 0:
			continue
		if str(t["kind"]) == "prop":
			b["prop"] = str(t["id"])
		b["span"] = (t["cells"] as Array).size()
		for c: Vector2i in t["cells"]:
			s.combat["blocks"][FightGrid.tag(c)] = b.duplicate()
	SpellEffects.lay_glyphs(s, data)  # the hero's runes of this room (v0.8.4.26.3)
	FightGrid.changed(s)


## What a fighter's trait strews around it as the fight begins (`lays`: Web Sense — the lair's webs): a row of
## `rules.combat.grid.strewn` on a `share` of the free squares within `around`, its own square among them.
static func _lays(s: GameSession, data: Dictionary, f: Dictionary) -> void:
	if f.is_empty() or Sheet.is_hero(f):
		return
	var born := ItemRules.born_rows(f, data, Sheet.template(data, f))
	for id: String in born:
		var lays: Variant = born[id]["row"].get("lays")
		if not lays is Dictionary:
			continue
		var g := FightGrid.grid(s, data)
		var others := {}
		for o: String in CombatRules.foes_of(s, f):
			for at: Vector2i in FightGrid.body(CombatRules.fighter(s, o)):
				others[at] = true
		var cells: Array[Vector2i] = []
		var around := int(lays.get("around", 3))
		var own := FightGrid.body(f)
		for at: Vector2i in FightGrid.body_at(FightGrid.cell(f) - Vector2i(around, around), around * 2 + own.size()):
			if at.x >= 0 and at.y >= 0 and at.x < int(g["w"]) and at.y < int(g["h"]) and FightGrid.walkable(g, at) and not others.has(at) \
					and (own.has(at) or s.rng.randf() < float(lays.get("share", 0.3))):
				cells.append(at)
		var row: Dictionary = cfg(data)["strewn"][str(lays["ground"])]
		SpellEffects.add_zone(s, zone_of(str(lays["ground"]), row.merged({"side": str(f.get("side", "enemy"))}), FightGrid.pack_cells(cells)))


## `a` knows where `b` is through a zone it feels (Web Sense, v0.8.4.27.3): both touch one zone whose `feel` is a flag of
## `a`'s statuses — `a` standing in it or beside it, `b` in it.
static func feels(s: GameSession, data: Dictionary, a: Dictionary, b: Dictionary) -> bool:
	for z: Dictionary in SpellEffects.zones(s):
		if not z.has("feel") or not ConditionRules.does(Sheet.holder(s, a), data, str(z["feel"])):
			continue
		var cells := FightGrid.zone_cells(s, data, z)
		if FightGrid.in_cells(b, cells) and FightGrid.body(a).any(func(at: Vector2i) -> bool:
				return WalkRules.DIRS.any(func(d: Vector2i) -> bool: return cells.has(at + d)) or cells.has(at)):
			return true
	return false


## A zone does not hold `f`: its `pass` is a flag of `f`'s statuses (Web Walker, v0.8.4.27.3).
static func passes(s: GameSession, data: Dictionary, f: Dictionary, z: Dictionary) -> bool:
	return z.has("pass") and ConditionRules.does(Sheet.holder(s, f), data, str(z["pass"]))


static func _ends(m: Dictionary, d: Dictionary) -> Array[String]:
	return [str(m["ids"][int(d["a"])]), str(m["ids"][int(d["b"])])]


## The keys of a row a zone takes as they are: what a failed save does, what it hides, who it spares, whom it touches.
const ZONE_KEYS: Array[String] = ["cond", "fail", "tag", "obscure", "veil", "silence", "retch", "block_ranged", "spares_friends", "for",
	"types", "sees", "spare_saved", "shape", "follow", "by", "side", "escape", "burns", "pass", "feel", "douses", "tile", "worn", "reveal"]


## A zone of the field by its row: one record for the ground, strewn things, the fire, a spell's zone and a trait's aura
## (v0.8.4.27.2). A row says its save, what a failed one does (`cond`, `fail`, `for`) and when it bites (`on`); `cells` — its
## squares, or none with `shape` and `follow` (it moves with `by`).
static func zone_of(id: String, row: Dictionary, cells: Array) -> Dictionary:
	var z := {"spell": id, "name": str(row["name"]), "shape": {}, "follow": false, "dice": str(row.get("dice", "")), "type": str(row.get("type", "")),
		"save": str(row.get("save", "")), "on": row.get("on", ["enter", "start"]), "dc": int(row.get("dc", 0)), "slow": bool(row.get("slow", false)), "cells": cells}
	for k: String in ZONE_KEYS:
		if row.has(k):
			z[k] = row[k]
	return z


## The auras of a fighter (Horrific Appearance, v0.8.4.27.1; a worn thing's, v0.8.4.35): a born or worn `aura` is a zone of
## the field that follows it, the record a spell's zone has (`_ground`) with a sphere of `ft` around it; `types` — only those
## of these types, `sees` — only those who see it, `spare_saved` — one who saved is spared after, `for` — the status's rounds
## and repeated save. Anybody's, the hero's too; called when it joins a fight and at the start of its turns, so a thing put
## on or off changes it (a zone kept keeps whom it spared).
static func auras(s: GameSession, data: Dictionary, f: Dictionary) -> void:
	var rows := {}
	var h := Sheet.holder(s, f)
	var born := ItemRules.born_rows(h, data, Sheet.template(data, f))
	for id: String in born:
		if born[id]["row"].get("aura") is Dictionary:
			rows["aura:" + id] = {"aura": born[id]["row"]["aura"], "name": born[id]["name"]}
	for e: Dictionary in ConditionRules.effects(h):
		if e.get("aura") is Dictionary and str(e.get("source", {}).get("kind", "")) == ItemRules.WORN:
			rows["aura:" + str(e["source"]["id"])] = {"aura": e["aura"], "name": str(e["source"].get("name", "")), "worn": str(e["source"]["id"])}
	var by := str(f["id"])
	for z: Dictionary in SpellEffects.zones(s).duplicate():
		if str(z.get("by", "")) == by and str(z["spell"]).begins_with("aura:") and bool(z.get("follow", false)) and not rows.has(str(z["spell"])):
			SpellEffects.zones(s).erase(z)
	var have := SpellEffects.zones(s).filter(func(z: Dictionary) -> bool: return str(z.get("by", "")) == by).map(func(z: Dictionary) -> String: return str(z["spell"]))
	for id: String in rows:
		if have.has(id):
			continue
		var r: Dictionary = rows[id]
		var row: Dictionary = (r["aura"] as Dictionary).merged({"name": r["name"], "follow": true,
			"shape": {"type": "sphere", "size": int(r["aura"].get("ft", 5))}, "by": by, "side": str(f.get("side", "enemy"))})
		if r.has("worn"):
			row["worn"] = r["worn"]
		SpellEffects.add_zone(s, zone_of(id, row, []))


## A thing on a square of a fight: its flags by its body — what bars the way is solid, what bars the eye or a shot is
## opaque (full cover past it), a low thing gives half cover.
static func _block(data: Dictionary, body_id: String, name: String) -> Dictionary:
	var b: Dictionary = ThingRules.cfg(data)["bodies"].get(body_id, {})
	var blocks: Array = b.get("blocks", [])
	var flags := FightGrid.SOLID if blocks.has("path") else 0
	if blocks.has("sight") or blocks.has("shots"):
		flags |= FightGrid.OPAQUE
	elif str(b.get("cover", "")) == "half":
		flags |= FightGrid.LOW
	return {"body": body_id, "name": name, "hp": int(cfg(data)["blocks"]["hp"]), "weight": int(b.get("weight", 0)), "made_of": str(b.get("made_of", "wood")),
		"flags": flags}


## The start of a round: who came after the hero, the fire, who heard.
static func round_starts(s: GameSession, data: Dictionary, lines: Array[String]) -> void:
	chasers_arrive(s, data, lines)
	fire_round(s, data, lines)
	hear(s, data, lines)


# --- surfaces a damage leaves ------------------------------------------------------------------------------


## A damage of `dtype` touches `cells` (v0.8.4.43.45): each row of `rules.combat.grid.surfaces` by that type lays its
## zone on the squares it is for — water under lightning, water blessed by radiance, hellfire where a fiend's fire falls.
## `source` — who dealt it (a fighter, {} — none). Lines.
static func react(s: GameSession, data: Dictionary, dtype: String, cells: Array[Vector2i], source: Dictionary, lines: Array[String]) -> void:
	var g := FightGrid.grid(s, data)
	for id: String in cfg(data).get("surfaces", {}):
		var row: Variant = cfg(data)["surfaces"][id]
		if not row is Dictionary or str(row.get("damage", "")) != dtype:
			continue
		if row.has("from") and not (row["from"] as Array).has(str(Sheet.template(data, source).get("type", "")) if not source.is_empty() else ""):
			continue
		var hit: Array[Vector2i] = []
		for at: Vector2i in cells:
			var fits := douses_at(s, data, at) if str(row["where"]) == "wet" else FightGrid.walkable(g, at)
			if fits:
				hit.append(at)
		if hit.is_empty():
			continue
		var packed := FightGrid.pack_cells(hit)
		var gone: Array = [id] + (row.get("clears", []) as Array)  # one of its kind on a square, and what it ends there (ice — the current)
		for z: Dictionary in SpellEffects.zones(s).duplicate():
			if gone.has(str(z["spell"])):
				for key: Variant in packed:
					(z["cells"] as Array).erase(key)
				if (z["cells"] as Array).is_empty():
					SpellEffects.zones(s).erase(z)
		var z := zone_of(id, (row as Dictionary).merged({"on": row.get("when", ["enter", "start"])}, true), packed)
		z["until_round"] = int(s.combat.get("round", 1)) + int(row.get("rounds", 1)) - 1  # gone by SpellEffects.zones_expire
		SpellEffects.add_zone(s, z)
		lines.append("%s (клеток: %d)" % [row["name"], hit.size()])



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
		ExplorationRules.place(s, room)
	WalkRules.stand(s, map, s.room_id, at)


## The body walked into a square: what lies there acts on it. True when the walk stops.
static func stepped(s: GameSession, data: Dictionary, f: Dictionary, lines: Array[String]) -> bool:
	var g := FightGrid.grid(s, data)
	var bits := FightGrid.flags_at(g, FightGrid.cell(f))
	if douses_at(s, data, FightGrid.cell(f)) and not LiquidRules.burning(s, Sheet.holder(s, f)).is_empty():
		LiquidRules.uncoat(Sheet.holder(s, f))
		lines.append("%s гасит пламя в воде" % f["name"])
	var hero := str(f.get("id")) == CombatRules.PLAYER
	var flying := CombatRules.airborne(s, data, f)
	if bits & FightGrid.PIT != 0 and not flying:
		_fall(s, data, f, lines)
		return true
	var before := lines.size()
	if not flying:
		lines.append_array(SpellEffects.zone_tick(s, data, f, "enter"))
	if int(CombatRules.points(s, data, f).get("move", 1)) <= 0:
		return true  # caltrops: a failed save ends the walk (v0.8.4.27)
	if hero:
		return int(s.character.get("hp", 0)) <= 0 or ConditionRules.has(s.character, "prone")
	return str(f.get("status")) != "active" or (lines.size() > before and CombatRules._has(f, "prone"))


## A body over a square with no floor: a pit, or what the cell's name finds in rules.combat.grid (lava, v0.8.4.43.32).
static func _fall(s: GameSession, data: Dictionary, f: Dictionary, lines: Array[String]) -> void:
	var at := FightGrid.cell(f)
	var rows: Array = FightGrid.grid(s, data)["map"].get("rows", [])
	var c := str(rows[at.y])[at.x] if at.y >= 0 and at.y < rows.size() and at.x >= 0 and at.x < str(rows[at.y]).length() else ""
	var name := str(data["layouts"]["cells"].get(c, {}).get("name", "pit"))
	var row: Dictionary = cfg(data).get(name, cfg(data)["pit"]) if name != "pit" else cfg(data)["pit"]
	CombatRules.fall(s, data, f, str(row["dice"]), str(row.get("what", "падает в яму")), {"kind": "engine", "name": str(row.get("name", "яма"))}, lines,
		str(row.get("type", "bludgeoning")))


## Standing on this square hurts: the AI's fear of it.
static func hurts(s: GameSession, data: Dictionary, f: Dictionary) -> bool:
	for z: Dictionary in SpellEffects.zones(s):
		if SpellEffects.harmful(z) and not bool(z.get("hidden", false)) and SpellEffects.bites(s, data, z, f):
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


## The acts `f` has with what stands beside it, by name.
static func acts(s: GameSession, data: Dictionary, f: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var d := door_near(s, data, f)
	if not d.is_empty():
		var g := FightGrid.grid(s, data)
		var at := Vector2i(int(d["x"]), int(d["y"]))
		if not FightGrid.shut(s, g, at):
			out.append("door_close")
		elif FightGrid.fast(s, g, at):
			out.append("door_force")
			if bool(FightGrid.door_state(s, at).get("barred", false)):
				out.append("door_unbar")
			elif Thing.count(Sheet.things(s, data, f), "thieves_tools") > 0:
				out.append("door_pick")  # a lock, not a bar: thieves' tools (a bonus action by Fast Hands, rules.combat.act_bonus)
		else:
			out.append("door_bar")
			if _has_key(s, data, f, d):
				out.append("door_lock")
	if block_near(s, f) != FightGrid.NONE:
		out.append("block_push")
		out.append("block_smash")
	return out


## The door beside `f`, a row of the map's `doors`, {} — none or gone. A door someone stands in cannot be shut.
static func door_near(s: GameSession, data: Dictionary, f: Dictionary) -> Dictionary:
	var taken := FightGrid.bodies(s)
	for d: Dictionary in FightGrid.map(s, data).get("doors", []):
		var at := Vector2i(int(d["x"]), int(d["y"]))
		if FightGrid.dist_to(f, at) <= 1 and not taken.has(at) and not bool(FightGrid.door_state(s, at).get("gone", false)):
			return d
	return {}


## `f` carries the door's key: anybody may lock it behind itself (v0.8.4.15).
static func _has_key(s: GameSession, data: Dictionary, f: Dictionary, d: Dictionary) -> bool:
	var ends := _ends(FightGrid.map(s, data), d)
	var id := str(WayRules.def(data, ends[0], ends[1]).get("key", ""))
	return not id.is_empty() and int(Sheet.things(s, data, f).get("inventory", {}).get(id, 0)) > 0


## "" — the act can be done now; a key otherwise.
static func why_not(s: GameSession, data: Dictionary, f: Dictionary, how: String) -> String:
	if not acts(s, data, f).has(how):
		return "COMBAT_BAD_TARGET"
	if how == "block_push":
		var at := block_near(s, f)
		var b: Dictionary = s.combat["blocks"][FightGrid.tag(at)]
		var strength := Sheet.ability(s, data, f, "str")
		if int(b["weight"]) > strength * int(cfg(data)["blocks"]["per_str"]) or int(b.get("span", 1)) > 1:  # a thing of many squares stays
			return "COMBAT_TOO_HEAVY"
		if not _block_can_go(s, data, at + (at - FightGrid.cell(f)).sign()):
			return "COMBAT_BLOCK_STUCK"
	return ""


## An act of `f` with a door or a thing. Lines.
static func act(s: GameSession, data: Dictionary, f: Dictionary, how: String, lines: Array[String]) -> void:
	var c := Sheet.holder(s, f)
	if how.begins_with("block"):
		if how == "block_push":
			_push_block(s, data, f, lines)
		else:
			_smash_block(s, data, f, lines)
		return
	var d := door_near(s, data, f)
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
		"door_pick":  # the lock of a door with thieves' tools (Sleight of Hand), as out of a fight (v0.8.4.43.46)
			var dc := int(WayRules.dcs(s, data, ends[0], ends[1])["pick"])
			var r := Roll.check(s, data, f, {"what": "Вскрыть замок", "skill": "sleight_of_hand", "dc": dc, "tool": "thieves_tools"})
			if bool(r["ok"]):
				doors.erase(key)
				WayRules.unlock(s, data, ends[0], ends[1])
				lines.append("%s вскрывает замок двери: %d против Сл %d" % [c["name"], int(r["total"]), dc])
				var doer := Being.HERO if Sheet.is_hero(f) else str(f.get("npc_id", ""))
				if not doer.is_empty():
					lines.append_array(WayRules.forced(s, data, ends[0], ends[1], doer))
			else:
				lines.append("Замок не поддался: %d против Сл %d" % [int(r["total"]), dc])
		"door_force":
			var r := Roll.check(s, data, f, {"what": "Выломать дверь", "skill": "athletics", "dc": _door_dc(s, data, at, d), "about": "force"})
			if bool(r["ok"]):
				_break_door(s, data, at, d)
				lines.append("%s выбивает дверь" % c["name"])
				var doer := Being.HERO if Sheet.is_hero(f) else str(f.get("npc_id", ""))
				if not doer.is_empty():  # a door forced before eyes, in a fight too: witnesses and trespass (v0.8.4.29.3)
					lines.append_array(WayRules.forced(s, data, ends[0], ends[1], doer))
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


## The thing beside `f`, NONE — none.
static func block_near(s: GameSession, f: Dictionary) -> Vector2i:
	var at := FightGrid.cell(f)
	for d: Vector2i in WalkRules.DIRS:
		if (s.combat.get("blocks", {}) as Dictionary).has(FightGrid.tag(at + d)):
			return at + d
	return FightGrid.NONE


static func _block_can_go(s: GameSession, data: Dictionary, to: Vector2i) -> bool:
	var g := FightGrid.grid(s, data)
	return FightGrid.flags_at(g, to) & FightGrid.SOLID == 0 and not FightGrid.bodies(s).has(to) and not FightGrid.shut(s, g, to)


static func _push_block(s: GameSession, data: Dictionary, f: Dictionary, lines: Array[String]) -> void:
	var who := str(Sheet.holder(s, f)["name"])
	var at := block_near(s, f)
	var to := at + (at - FightGrid.cell(f)).sign()
	var b: Dictionary = s.combat["blocks"][FightGrid.tag(at)]
	_lift(s, data, at)
	var g := FightGrid.grid(s, data)
	if FightGrid.flags_at(g, to) & FightGrid.PIT != 0:
		lines.append("%s: %s падает в яму" % [who, b["name"]])
	else:
		s.combat["blocks"][FightGrid.tag(to)] = b
		(s.combat.get("cleared", {}) as Dictionary).erase(FightGrid.tag(to))
		lines.append("%s толкает: %s" % [who, b["name"]])
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


static func _smash_block(s: GameSession, data: Dictionary, f: Dictionary, lines: Array[String]) -> void:
	var at := block_near(s, f)
	var b: Dictionary = s.combat["blocks"][FightGrid.tag(at)]
	var mat := {"material": b["made_of"]}
	var r := ThingRules.blow(s, data, f, mat, "Удар по вещи")  # the door's road: its threshold too (v0.8.4.29.3)
	if not bool(r["ok"]):
		lines.append("%s: удар по вещи — %d против КД %d, без толку" % [r["name"], int(r["total"]), int(r["ac"])])
		return
	var dmg := ThingRules.takes(data, mat, int(r["damage"]))
	b["hp"] = int(b["hp"]) - dmg
	if int(b["hp"]) > 0:
		lines.append("%s: %d урона по вещи — %s ещё цел(а)" % [r["name"], dmg, b["name"]])
		return
	lines.append("%s: %d урона — %s разбит(а)" % [r["name"], dmg, b["name"]])
	_ruin(s, data, at, lines)


## A thing of the room is gone for good; one of the map stays gone only in this fight.
static func _ruin(s: GameSession, data: Dictionary, at: Vector2i, lines: Array[String]) -> void:
	var b: Dictionary = s.combat["blocks"][FightGrid.tag(at)]
	_lift(s, data, at)
	for p: Dictionary in PropRules.room_props(s, s.room_id):
		if str(p["id"]) == str(b.get("prop", "")):
			lines.append_array(ThingRules.ruin(s, data, s.room_id, p, "broken"))


# --- fire ----------------------------------------------------------------------------------------------------


## Water on the square: the map's or a puddle (v0.8.4.28.2) — no fire there, and one walking in is put out.
static func douses_at(s: GameSession, data: Dictionary, at: Vector2i) -> bool:
	var key := FightGrid.tag(at)
	return FightGrid.flags_at(FightGrid.grid(s, data), at) & FightGrid.WET != 0 		or SpellEffects.zones(s).any(func(z: Dictionary) -> bool: return bool(z.get("douses", false)) and (z.get("cells", []) as Array).has(key))


static func _burnable(s: GameSession, data: Dictionary, at: Vector2i) -> bool:
	var key := FightGrid.tag(at)
	if douses_at(s, data, at):
		return false
	if SpellEffects.zones(s).any(func(z: Dictionary) -> bool: return bool(z.get("burns", false)) and (z.get("cells", []) as Array).has(key)):
		return true  # oil, a web, Entangle's plants (v0.8.4.27.3)
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
	for z: Dictionary in SpellEffects.zones(s).duplicate():  # what burns of a zone is gone with the fire, all of it — the zone too
		if bool(z.get("burns", false)):
			(z.get("cells", []) as Array).erase(key)
			if (z.get("cells", []) as Array).is_empty() and (z.get("shape", {}) as Dictionary).is_empty():
				SpellEffects.zones(s).erase(z)


## A flask broken on a square: its liquid's `puddle` (v0.8.4.28.2) — a zone of the ground (oil to slip on and burn, water
## that puts the fire out), or alchemist's fire that burns at once.
static func splash(s: GameSession, data: Dictionary, at: Vector2i, fx: Dictionary, name: String, lines: Array[String], side := "player") -> void:
	if fx.has("strew"):
		strew(s, data, at, str(fx["strew"]), side, lines)
		return
	var lid := str(fx.get("liquid", ""))
	var p: Dictionary = LiquidRules.kind(data, lid).get("puddle", {})
	if p.is_empty():
		return
	var key := FightGrid.tag(at)
	if bool(p.get("fire", false)):
		if douses_at(s, data, at):
			lines.append("%s: шипит в воде и гаснет" % name)
			return
		_light(s, at)
		_sync_fire(s, data)
		lines.append("%s: клетка в огне" % name)
		return
	if bool(p.get("douses", false)) and (s.combat["fires"] as Dictionary).has(key):
		(s.combat["fires"] as Dictionary).erase(key)
		_sync_fire(s, data)
		lines.append("%s: огонь на клетке погас" % name)
	SpellEffects.add_zone(s, zone_of("puddle:" + lid, p.merged({"side": side, "on": p.get("on", [])}), FightGrid.pack_cells([at] as Array[Vector2i])))
	lines.append("%s: %s растекается по клетке" % [name, LiquidRules.name_of(data, lid)])
	if (s.combat["fires"] as Dictionary).has(key):
		kindle(s, data, [at] as Array[Vector2i], lines)


## Caltrops or ball bearings strewn from `at` (v0.8.4.27): a zone of the ground by the row of `rules.combat.grid.strewn`,
## the thrower's side its own. Lines.
static func strew(s: GameSession, data: Dictionary, at: Vector2i, row_id: String, side: String, lines: Array[String]) -> void:
	var row: Dictionary = cfg(data)["strewn"][row_id]
	var cells: Array[Vector2i] = []
	var g := FightGrid.grid(s, data)
	for c: Vector2i in FightGrid.body_at(at, int(row.get("span", 1))):
		if FightGrid.walkable(g, c):
			cells.append(c)
	SpellEffects.add_zone(s, zone_of(row_id, row.merged({"side": side}), FightGrid.pack_cells(cells)))
	lines.append("%s: рассыпаны по клетке — кто войдёт, спасбросок %s Сл %d" % [row["name"], CombatRules.ab_name(str(row["save"])), int(row["dc"])])


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
		zones.append(zone_of("fire", cfg(data)["fire"], cells))
	s.combat["zones"] = zones


# --- noise ---------------------------------------------------------------------------------------------------


## What is left of the noise from `a` at `b`: below 0 it is not heard. `more` — a loud blow's extra squares.
static func _loud(g: Dictionary, c: Dictionary, a: Vector2i, b: Vector2i, more: int = 0) -> int:
	var left := int(c["reach"]) + more - WalkRules.distance(a, b)
	for at: Vector2i in FightGrid.line_of(a, b):
		if FightGrid.flags_at(g, at) & FightGrid.OPAQUE != 0:
			left -= int(c["wall"])
	return left


## A blow of a loud kind sounded (thunder: Thunderwave, Shatter): the next round is heard farther. Called by Harm.
static func din(s: GameSession, data: Dictionary, dtype: String) -> void:
	var more := int(cfg(data)["noise"]["loud"].get(dtype, 0))
	if more > 0:
		s.combat["loud"] = maxi(int(s.combat.get("loud", 0)), more)


## Does the fight's noise go through the way `a` → `b`? Only within one location and never along a road.
static func carries(data: Dictionary, a: String, b: String) -> bool:
	var w := WorldView.new(data["world"])
	return w.location_id(a) == w.location_id(b) and not (cfg(data)["noise"]["deaf"] as Array).has(str(WayRules.row(data, a, b)["kind"]))


## The fight is heard. Those who hear stand where they stand: the guard and the foes' own come, the peaceful hide.
static func hear(s: GameSession, data: Dictionary, lines: Array[String]) -> void:
	if s.combat.has("field") or s.combat.has("arena"):
		return
	var c: Dictionary = cfg(data)["noise"]
	var g := FightGrid.grid(s, data)
	var m: Dictionary = g["map"]
	var at := FightGrid.cell(CombatRules.player(s))
	var more := int(s.combat.get("loud", 0))
	s.combat.erase("loud")
	for room: String in m["ids"]:
		var cells := MapSpots._cells(m, data["layouts"], room)
		if cells.is_empty():
			continue
		var spot: Vector2i = cells[cells.size() / 2]
		if room == s.room_id or _loud(g, c, at, spot, more) >= 0:
			_wakes(s, data, room, spot, lines)
	for e: Dictionary in m["exits"]:
		var spot := Vector2i(int(e["ax"]), int(e["ay"]))
		if carries(data, str(e["room"]), str(e["to"])) and _loud(g, c, at, spot, more) >= int(c["beyond"]):
			_wakes(s, data, str(e["to"]), spot, lines)


static func _wakes(s: GameSession, data: Dictionary, room: String, spot: Vector2i, lines: Array[String]) -> void:
	if not s.combat.has("heard"):
		s.combat["heard"] = []
	var heard: Array = s.combat["heard"]
	var world := WorldView.new(data["world"])
	var enc := EncounterRules.live(s, data, room)
	var side := str(s.combat.get("faction", ""))
	if not enc.is_empty() and not side.is_empty() and str(enc.get("faction", "")) == side and not heard.has(str(enc["id"])) and str(enc["id"]) != str(s.combat.get("encounter", "")):
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
		if FightGrid.dist_to(f, at) <= near and Move.steps(s, data, f) > 0:
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
	ExplorationRules.place(s, str(e["to"]))
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
	for z: Dictionary in SpellEffects.zones(s).duplicate():  # what was poured stays in the room it was poured in
		if str(z["spell"]).begins_with("puddle:"):
			SpellEffects.zones(s).erase(z)
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
	if acts(s, data, f).has("door_force") and Acts.one("field").can(s, data, f, "", {"how": "door_force"}).is_empty():
		lines.append_array(Acts.one("field").go(s, data, f, "", {"how": "door_force"}))
		return
	lines.append("%s стоит на месте" % f["name"])
