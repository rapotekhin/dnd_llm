class_name MapSpots
extends RefCounted
## Who and what stands where on the map of the room (v0.8.2). A person stands by its role at a mark of the room, else on a
## square of its own for this part of the day; a thing lies where the master said («у очага») or on a square of its own.
## Nothing here is kept except a move by the master's words: the rest follows from the seed, so a save holds no squares
## of people. People do not block the way. The master never sees squares: `words` and `near_word` speak for them.
## v0.8.3: foes before a fight stand away from the ways in (`foes`), a trap and a cache lie on a square (`secret_cell`).


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"]["map"]


## The tokens of the room now: {"ref", "kind", "id", "name", "mark", "x", "y", "attitude"}. Those who walk with the hero
## are not here: they stand by the hero.
static func of(s: GameSession, data: Dictionary, map: Dictionary) -> Array[Dictionary]:
	var lib: Dictionary = data["layouts"]
	var cells := _cells(map, lib, s.room_id)
	var out: Array[Dictionary] = []
	if cells.is_empty():
		return out
	var taken := {}
	for e: Dictionary in map["exits"]:
		taken[Vector2i(int(e["ax"]), int(e["ay"]))] = true
	var index := (map["ids"] as Array).find(s.room_id)
	var stations: Array = cfg(data)["stations"]
	var seen := {}
	for m: Dictionary in map["marks"]:
		var mark := str(m["name"])
		if int(m["room"]) == index and stations.has(mark) and not seen.has(mark):
			seen[mark] = true
			var at := Vector2i(int(m["x"]), int(m["y"]))
			taken[at] = true
			out.append(_token("station:" + mark, "station", mark, _word(data, mark), at))
	var world := WorldView.new(data["world"])
	var followers := Being.followers(s)
	var part := TimeRules.part_name(s, data)
	for id: String in _sorted(s.npcs_here(data["world"], s.room_id)):
		if followers.has(id):
			continue
		var at := _npc_cell(s, data, map, s.room_id, cells, taken, id, part)
		taken[at] = true
		var n := world.npc(id)
		var t := _token("npc:" + id, "npc", id, str(n.get("name", id)), at)
		t["attitude"] = s.attitude(id)
		out.append(t)
	for c: Dictionary in CreatureRules.here(s, s.room_id):
		var id := str(c["id"])
		if str(c["state"]) == PropertyRules.TAME or bool(c.get("led", false)) or bool(c.get("ally", false)):
			continue
		var fell := Vector2i(int(c.get("x", -1)), int(c.get("y", -1)))
		var at := fell if cells.has(fell) and not taken.has(fell) else _seeded(cells, taken, "%d|%s" % [s.game_seed, id])
		taken[at] = true
		out.append(_token("cr:" + id, "body" if str(c["state"]) == CreatureRules.DEAD else "creature", id, str(c["name"]), at))
	for b: Dictionary in CrimeRules.bodies_here(s, data):
		var id := str(b["npc_id"])
		var at := _seeded(cells, taken, "%d|%s" % [s.game_seed, id])
		taken[at] = true
		out.append(_token("body:" + id, "body", id, str(b["name"]), at))
	for p: Dictionary in PropRules.room_props(s, s.room_id):
		if not _shown(data, p):
			continue
		var at := _prop_cell(s, data, map, cells, taken, out, p)
		taken[at] = true
		out.append(_token("prop:" + str(p["id"]), "prop", str(p["id"]), str(p["name"]), at))
	return out


static func _token(ref: String, kind: String, id: String, name: String, at: Vector2i) -> Dictionary:
	return {"ref": ref, "kind": kind, "id": id, "name": name, "mark": name.left(1), "x": at.x, "y": at.y, "attitude": 0}


## Furniture and decor stay words; on the map is what can be taken or used.
static func _shown(data: Dictionary, p: Dictionary) -> bool:
	if p.has("wares") or bool(p.get("hidden", false)):
		return false
	return not str(p.get("item_id", "")).is_empty() or not str(p.get("container", "")).is_empty() or p.has("source") \
		or not str(p.get("text", "")).is_empty() or QuestGen.is_board(data, p)


static func _npc_cell(s: GameSession, data: Dictionary, map: Dictionary, room: String, cells: Array[Vector2i], taken: Dictionary, id: String, part: String) -> Vector2i:
	var moved: Dictionary = (s.layouts.get("moved", {}) as Dictionary).get(id, {})
	if str(moved.get("room", "")) == room and str(moved.get("part", "")) == part:
		var at := LayoutGen.off_grid(map, Vector2i(int(moved["x"]), int(moved["y"])))
		if cells.has(at):
			return at
	if WorldView.new(data["world"]).is_trader(id):
		for wanted: String in cfg(data)["trader_marks"]:
			var at := _mark_cell(map, room, wanted)
			if at.x >= 0:
				return _closest(cells, taken, at)
	return _seeded(cells, taken, "%d|%s|%s" % [s.game_seed, id, part])


## People of the other rooms of this map the hero knows: seen through a door, walked up to on the map, spoken to there.
static func others(s: GameSession, data: Dictionary, map: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var world := WorldView.new(data["world"])
	var part := TimeRules.part_name(s, data)
	var followers := Being.followers(s)
	for room: String in map["ids"]:
		if room == s.room_id or not s.visited.has(room):
			continue
		var cells := _cells(map, data["layouts"], room)
		var taken := {}
		for id: String in _sorted(s.npcs_here(data["world"], room)):
			if followers.has(id) or cells.is_empty():
				continue
			var at := _npc_cell(s, data, map, room, cells, taken, id, part)
			taken[at] = true
			var t := _token("far:" + id, "npc", id, str(world.npc(id).get("name", id)), at)
			t["attitude"] = s.attitude(id)
			out.append(t)
	return out


## The square a fighter of a fight starts on: its person's, its creature's, the lair of its encounter. (-1, -1) — no such.
static func of_fighter(s: GameSession, data: Dictionary, spec: Dictionary) -> Vector2i:
	var map := FightGrid.map(s, data)
	var npc := str(spec.get("npc_id", ""))
	var creature := str(spec.get("creature_id", ""))
	if not npc.is_empty() or not creature.is_empty():
		var ref := "npc:" + npc if not npc.is_empty() else "cr:" + creature
		for t: Dictionary in of(s, data, map):
			if str(t["ref"]) == ref:
				return Vector2i(int(t["x"]), int(t["y"]))
	var key := str(s.combat.get("encounter", ""))
	var cells := _cells(map, data["layouts"], s.room_id)
	if key.is_empty() or cells.is_empty():
		return Vector2i(-1, -1)
	return _lair(s, data, map, cells, key)


## The foes of the room before a fight, each with its "record". They stand together, away from the ways in; the seed
## keeps their squares.
static func foes(s: GameSession, data: Dictionary, map: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if EncounterRules.lurking(s, s.room_id).is_empty():
		return out
	var cells := _cells(map, data["layouts"], s.room_id)
	if cells.is_empty():
		return out
	var enc := EncounterRules.lurking_encounter(s, data, s.room_id)
	var taken := {}
	var lair := _lair(s, data, map, cells, str(enc.get("id", "")))
	for e: Dictionary in enc.get("enemies", []):
		if Being.dead(s, EncounterRules.foe_id(e)):
			continue
		var at := _closest(cells, taken, lair)
		taken[at] = true
		var t := _token("foe:" + EncounterRules.foe_id(e), "foe", EncounterRules.foe_id(e), str(e.get("name", e.get("monster", ""))), at)
		t["record"] = e
		out.append(t)
	return out


static func _lair(s: GameSession, data: Dictionary, map: Dictionary, cells: Array[Vector2i], key: String) -> Vector2i:
	var ways := _ways_in(map, s.room_id)
	var far := int(SightRules.cfg(data)["lair"])
	var fit: Array[Vector2i] = cells.filter(func(cell: Vector2i) -> bool:
		return ways.all(func(way: Vector2i) -> bool: return WalkRules.distance(way, cell) >= far))
	return _seeded(fit if not fit.is_empty() else cells, {}, "%d|%s" % [s.game_seed, key])


static func _ways_in(map: Dictionary, room: String) -> Array[Vector2i]:
	var ways: Array[Vector2i] = []
	var index := (map["ids"] as Array).find(room)
	for e: Dictionary in map["exits"]:
		if str(e["room"]) == room:
			ways.append(Vector2i(int(e["ax"]), int(e["ay"])))
	for d: Dictionary in map["doors"]:
		if index in [int(d["a"]), int(d["b"])]:
			ways.append(Vector2i(int(d["x"]), int(d["y"])))
	return ways


## The square of a trap or a cache: a trap lies before the way it guards, a thing where the pack says (`near`, a mark) or
## where the seed puts it. (-1, -1) — the room has no free square.
static func secret_cell(s: GameSession, data: Dictionary, map: Dictionary, room: String, sec: Dictionary) -> Vector2i:
	var cells := _cells(map, data["layouts"], room)
	if cells.is_empty():
		return Vector2i(-1, -1)
	var to := str((sec.get("trap", {}) as Dictionary).get("guards", ""))
	for e: Dictionary in map["exits"]:
		if str(e["room"]) == room and str(e["to"]) == to:
			return Vector2i(int(e["ax"]), int(e["ay"]))
	var ids: Array = map["ids"]
	for d: Dictionary in map["doors"]:
		if not to.is_empty() and ids[int(d["a"])] in [room, to] and ids[int(d["b"])] in [room, to]:
			return _closest(cells, {}, Vector2i(int(d["x"]), int(d["y"])))
	var near := _mark_cell(map, room, str(sec.get("near", "")))
	return near if cells.has(near) else _seeded(cells, {}, "%d|%s|%s" % [s.game_seed, room, str(sec["id"])])


## The traps the hero found, on their squares.
static func traps(s: GameSession, data: Dictionary, map: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for ft: Dictionary in ExplorationRules.found_traps(s, data["world"], s.room_id):
		var sec: Dictionary = ft["secret"]
		var at := secret_cell(s, data, map, s.room_id, sec)
		if at.x >= 0:
			out.append(_token("trap:" + str(sec["id"]), "trap", str(sec["id"]), str(sec["text"]), at))
	return out


static func _prop_cell(s: GameSession, data: Dictionary, map: Dictionary, cells: Array[Vector2i], taken: Dictionary, placed: Array[Dictionary], p: Dictionary) -> Vector2i:
	var near := str(p.get("near", ""))
	if not near.is_empty():
		var at := _mark_cell(map, s.room_id, near)
		for t: Dictionary in placed:
			if str(t["id"]) == near:
				at = Vector2i(int(t["x"]), int(t["y"]))
		if at.x >= 0:
			return _closest(cells, taken, at)
	return _seeded(cells, taken, "%d|%s" % [s.game_seed, str(p["id"])])


## The free squares of a room, in a fixed order.
static func _cells(map: Dictionary, lib: Dictionary, room: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y: int in int(map["h"]):
		for x: int in int(map["w"]):
			var cell := Vector2i(x, y)
			if WalkRules.room_of(map, cell) == room and WalkRules.passable(map, lib, cell):
				out.append(cell)
	return out


static func _seeded(cells: Array[Vector2i], taken: Dictionary, key: String) -> Vector2i:
	var start := absi(key.hash()) % cells.size()
	for i: int in cells.size():
		var at := cells[(start + i) % cells.size()]
		if not taken.has(at):
			return at
	return cells[start]


static func _closest(cells: Array[Vector2i], taken: Dictionary, to: Vector2i) -> Vector2i:
	var best := cells[0]
	var length := 1 << 30
	for at: Vector2i in cells:
		var d := WalkRules.distance(at, to)
		if d < length and not taken.has(at):
			length = d
			best = at
	return best


static func _mark_cell(map: Dictionary, room: String, name: String) -> Vector2i:
	var index := (map["ids"] as Array).find(room)
	for m: Dictionary in map["marks"]:
		if str(m["name"]) == name and int(m["room"]) == index:
			return Vector2i(int(m["x"]), int(m["y"]))
	return Vector2i(-1, -1)


static func _sorted(ids: Array[String]) -> Array[String]:
	var out := ids.duplicate()
	out.sort()
	return out


static func _word(data: Dictionary, mark: String) -> String:
	return str(cfg(data)["mark_words"].get(mark, mark))


## The square of the one or the thing named by the master: "hero", a person, a thing, a mark of the room. (-1, -1) — none.
static func cell_of(s: GameSession, data: Dictionary, map: Dictionary, name: String) -> Vector2i:
	if name == "hero":
		return WalkRules.settle(s, data, map)
	for t: Dictionary in of(s, data, map):
		if str(t["id"]) == name:
			return Vector2i(int(t["x"]), int(t["y"]))
	if Being.follows(s, name):
		return WalkRules.settle(s, data, map)
	return _mark_cell(map, s.room_id, name)


## Is `name` within `reach` of the hero, in a line of sight? One who has no square here stands in reach.
static func in_reach(s: GameSession, data: Dictionary, name: String, reach: String) -> bool:
	var map := LayoutRules.map_of(s, data, s.room_id)
	var at := cell_of(s, data, map, name)
	if at.x < 0:
		return true
	var hero := WalkRules.settle(s, data, map)
	return WalkRules.distance(hero, at) <= int(cfg(data)["reach"][reach]) and SightRules.line(map, data["layouts"], hero, at)


## What the master may name as a place of the room: «очаг [hearth]».
static func words(s: GameSession, data: Dictionary) -> Array[String]:
	var map := LayoutRules.map_of(s, data, s.room_id)
	var index := (map["ids"] as Array).find(s.room_id)
	var out: Array[String] = []
	for m: Dictionary in map["marks"]:
		var mark := str(m["name"])
		var line := "%s [%s]" % [_word(data, mark), mark]
		if int(m["room"]) == index and mark != LayoutGen.ENTRY and not out.has(line):
			out.append(line)
	return out


## How far from the hero, in words: {id: «рядом»}; the mark the hero stands by is under "hero" («стойка»).
static func near_words(s: GameSession, data: Dictionary) -> Dictionary:
	var map := WalkRules.view(s, data)
	var hero := WalkRules.settle(s, data, map)
	var out := {}
	for t: Dictionary in of(s, data, map):
		out[t["id"]] = str(Scale.step(cfg(data)["distance"], WalkRules.distance(hero, Vector2i(int(t["x"]), int(t["y"]))))["word"])
	var index := (map["ids"] as Array).find(s.room_id)
	var length := int(cfg(data)["by_mark"]) + 1
	for m: Dictionary in map["marks"]:
		var d := WalkRules.distance(hero, Vector2i(int(m["x"]), int(m["y"])))
		if int(m["room"]) == index and str(m["name"]) != LayoutGen.ENTRY and d < length:
			length = d
			out["hero"] = _word(data, str(m["name"]))
	return out


## The master's `approach`: the hero or a person walks up to someone or something of the room. The engine finds the square.
static func plan(s: GameSession, data: Dictionary, e: Dictionary) -> Dictionary:
	var who := str(e.get("who", "hero"))
	var to := str(e.get("to", ""))
	var world := WorldView.new(data["world"])
	if who == to:
		return {"reason": "подойти к самому себе нельзя"}
	if who != "hero" and not s.npcs_here(data["world"], s.room_id).has(who):
		return {"reason": "%s нет в этой комнате: подходят те, кто здесь" % who}
	var map := WalkRules.view(s, data)
	var target := cell_of(s, data, map, to)
	if target.x < 0:
		return {"reason": "«%s» нет в этой комнате: подойти можно к человеку и вещи сцены или к месту из scene.spots" % to}
	var from := cell_of(s, data, map, who)
	var steps := WalkRules.near(map, data["layouts"], from, target, int(cfg(data)["reach"]["touch"]), s.room_id)
	var at := steps[-1] if not steps.is_empty() else from
	var name := "Герой" if who == "hero" else str(world.npc(who).get("name", who))
	var aim := "герою" if to == "hero" else str(world.npc(to).get("name", _name_of(s, data, map, to)))
	return {"plan": {"who": who, "x": at.x, "y": at.y}, "summary": "%s: к %s" % [name, aim]}


static func _name_of(s: GameSession, data: Dictionary, map: Dictionary, to: String) -> String:
	for t: Dictionary in of(s, data, map):
		if str(t["id"]) == to:
			return str(t["name"])
	return _word(data, to)


static func apply(s: GameSession, data: Dictionary, p: Dictionary) -> Array[String]:
	var cell := Vector2i(int(p["x"]), int(p["y"]))
	if str(p["who"]) == "hero":
		WalkRules.stand(s, LayoutRules.map_of(s, data, s.room_id), s.room_id, cell)
		return []
	var moved: Dictionary = s.layouts.get_or_add("moved", {})
	var kept := LayoutGen.on_grid(LayoutRules.map_of(s, data, s.room_id), cell)
	moved[str(p["who"])] = {"room": s.room_id, "part": TimeRules.part_name(s, data), "x": kept.x, "y": kept.y}
	return []
