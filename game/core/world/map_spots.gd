class_name MapSpots
extends RefCounted
## Who and what stands where on the map of the room (v0.8.2). A person stands by its role at a mark of the room, else on a
## square of its own for this part of the day; a thing lies where the master said («у очага») or on a square of its own.
## Nothing here is kept except a move by the master's words: the rest follows from the seed, so a save holds no squares
## of people. People do not block the way. The master never sees squares: `words` and `near_word` speak for them.


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
		var at := _npc_cell(s, data, map, cells, taken, id, part)
		taken[at] = true
		var n := world.npc(id)
		var t := _token("npc:" + id, "npc", id, str(n.get("name", id)), at)
		t["attitude"] = s.attitude(id)
		out.append(t)
	for c: Dictionary in CreatureRules.here(s, s.room_id):
		var id := str(c["id"])
		if str(c["state"]) == PropertyRules.TAME or bool(c.get("led", false)) or bool(c.get("ally", false)):
			continue
		var at := _seeded(cells, taken, "%d|%s" % [s.game_seed, id])
		taken[at] = true
		out.append(_token("cr:" + id, "creature", id, str(c["name"]), at))
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


static func _npc_cell(s: GameSession, data: Dictionary, map: Dictionary, cells: Array[Vector2i], taken: Dictionary, id: String, part: String) -> Vector2i:
	var moved: Dictionary = (s.layouts.get("moved", {}) as Dictionary).get(id, {})
	if str(moved.get("room", "")) == s.room_id and str(moved.get("part", "")) == part:
		var at := LayoutGen.off_grid(map, Vector2i(int(moved["x"]), int(moved["y"])))
		if cells.has(at):
			return at
	if WorldView.new(data["world"]).is_trader(id):
		for wanted: String in cfg(data)["trader_marks"]:
			var at := _mark_cell(map, s.room_id, wanted)
			if at.x >= 0:
				return _closest(cells, taken, at)
	return _seeded(cells, taken, "%d|%s|%s" % [s.game_seed, id, part])


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
