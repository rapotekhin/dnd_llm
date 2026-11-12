class_name WalkRules
extends RefCounted
## Walking on a map (v0.8.1): what the hero sees of the map here, where the hero stands, a path by squares. A step inside
## a room costs no time and no turn of the master; a step into another room or out of the map goes through GameState.go,
## where locks, trespass and the room's description live.

const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]


## The map as the hero knows it: rooms neither visited nor open from here are blank, a door to them is a wall, a way out
## is shown only when it is open from its room.
static func view(s: GameSession, data: Dictionary) -> Dictionary:
	var map := LayoutRules.map_of(s, data, s.room_id)
	var ids: Array = map["ids"]
	var open := WayRules.open_exits(s, data["world"], s.room_id)
	var known := PackedByteArray()
	known.resize(ids.size())
	for i: int in ids.size():
		known[i] = 1 if ids[i] == s.room_id or s.visited.has(ids[i]) or open.has(ids[i]) else 0
	var out := map.duplicate()
	var rows: Array[String] = (map["rows"] as Array[String]).duplicate()
	var w := int(map["w"])
	for y: int in rows.size():
		for x: int in w:
			var room := LayoutGen.room_at(map, x, y)
			if room >= 0 and room < known.size() and known[room] == 0:
				rows[y][x] = LayoutGen.BLANK
	for d: Dictionary in map["doors"]:
		if known[int(d["a"])] == 0 or known[int(d["b"])] == 0:
			rows[int(d["y"])][int(d["x"])] = LayoutGen.WALL
	out["rows"] = rows
	var exits: Array[Dictionary] = []
	for e: Dictionary in map["exits"]:
		var from := str(e["room"])
		if ids.has(from) and known[ids.find(from)] == 1 and WayRules.open_exits(s, data["world"], from).has(str(e["to"])):
			exits.append(e)
	out["exits"] = exits
	out["walls"] = MapSpots.walls(MapSpots.of(s, data, out))  # the things of the room bar the way and the eye (v0.8.4.43.23)
	return out


## The room of a square, "" for what belongs to none.
static func room_of(map: Dictionary, cell: Vector2i) -> String:
	if cell.x < 0 or cell.y < 0 or cell.x >= int(map["w"]) or cell.y >= int(map["h"]):
		return ""
	var i := LayoutGen.room_at(map, cell.x, cell.y)
	return str(map["ids"][i]) if i >= 0 and i < (map["ids"] as Array).size() else ""


static func passable(map: Dictionary, lib: Dictionary, cell: Vector2i) -> bool:
	return floor_at(map, lib, cell) and int((map.get("walls", {}) as Dictionary).get(cell, 0)) & MapSpots.PATH == 0


## The map's own floor, the things on it aside (v0.8.4.43.23: where a thing may be laid).
static func floor_at(map: Dictionary, lib: Dictionary, cell: Vector2i) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x >= int(map["w"]) or cell.y >= int(map["h"]):
		return false
	return not LayoutGen.solid(lib, (map["rows"] as Array[String])[cell.y][cell.x])


## Squares between two cells, a diagonal counts as one.
static func distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


## The shortest way by squares in eight directions, a corner is not cut: a diagonal needs both squares beside it free.
## Empty when there is none. `from` is not in it.
static func path(map: Dictionary, lib: Dictionary, from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	if from == to or not passable(map, lib, to):
		return []
	return _search(map, lib, from, func(cell: Vector2i) -> bool: return cell == to, "")


## The way up to `reach` squares of `target` inside the room. Empty when the hero is in reach already or there is no way.
static func near(map: Dictionary, lib: Dictionary, from: Vector2i, target: Vector2i, reach: int, room: String) -> Array[Vector2i]:
	if distance(from, target) <= reach:
		return []
	return _search(map, lib, from, func(cell: Vector2i) -> bool: return distance(cell, target) <= reach, room)


## Breadth first until `done`; `room` keeps the way inside a room and on what belongs to none (a door).
static func _search(map: Dictionary, lib: Dictionary, from: Vector2i, done: Callable, room: String) -> Array[Vector2i]:
	var came: Dictionary = {from: from}
	var queue: Array[Vector2i] = [from]
	var head := 0
	var end := Vector2i(-1, -1)
	while head < queue.size():
		var at: Vector2i = queue[head]
		head += 1
		if at != from and done.call(at):
			end = at
			break
		for d: Vector2i in DIRS:
			var next := at + d
			if came.has(next) or not passable(map, lib, next):
				continue
			if d.x != 0 and d.y != 0 and not (passable(map, lib, at + Vector2i(d.x, 0)) and passable(map, lib, at + Vector2i(0, d.y))):
				continue
			if not room.is_empty() and not room_of(map, next) in [room, ""]:
				continue
			came[next] = at
			queue.append(next)
	var out: Array[Vector2i] = []
	if end.x < 0:
		return out
	var back := end
	while back != from:
		out.push_front(back)
		back = came[back]
	return out


## A click on the map: the way there and the room beyond if the click was on a way out. {} — nowhere to go.
static func plan(map: Dictionary, lib: Dictionary, from: Vector2i, cell: Vector2i) -> Dictionary:
	var target := cell
	var to := ""
	for e: Dictionary in map["exits"]:
		if Vector2i(int(e["x"]), int(e["y"])) == cell:
			target = Vector2i(int(e["ax"]), int(e["ay"]))
			to = str(e["to"])
	var steps := path(map, lib, from, target)
	if steps.is_empty() and from != target:
		return {}
	return {"path": steps, "exit": to}


## The square of the way from `room` to `to`: a door or a way out; (-1, -1) — none on this map.
static func way_cell(map: Dictionary, room: String, to: String) -> Vector2i:
	var ids: Array = map["ids"]
	var pair := [ids.find(room), ids.find(to)]
	for d: Dictionary in map["doors"]:
		if pair.has(int(d["a"])) and pair.has(int(d["b"])) and pair[0] != pair[1]:
			return Vector2i(int(d["x"]), int(d["y"]))
	for e: Dictionary in map["exits"]:
		if str(e["room"]) == room and str(e["to"]) == to:
			return Vector2i(int(e["x"]), int(e["y"]))
	return Vector2i(-1, -1)


## The room a door or a way out of `room` on `cell` leads to, "" — nothing of the kind.
static func way_at(map: Dictionary, room: String, cell: Vector2i) -> String:
	var ids: Array = map["ids"]
	var here := ids.find(room)
	for d: Dictionary in map["doors"]:
		if Vector2i(int(d["x"]), int(d["y"])) == cell and here in [int(d["a"]), int(d["b"])]:
			return str(ids[int(d["b"]) if int(d["a"]) == here else int(d["a"])])
	for e: Dictionary in map["exits"]:
		if str(e["room"]) == room and Vector2i(int(e["x"]), int(e["y"])) == cell:
			return str(e["to"])
	return ""


## The first free square of `to` past the door on `cell`, (-1, -1) — none.
static func beyond(map: Dictionary, lib: Dictionary, cell: Vector2i, to: String) -> Vector2i:
	for step: Vector2i in DIRS.slice(0, 4):
		if room_of(map, cell + step) == to and passable(map, lib, cell + step):
			return cell + step
	return Vector2i(-1, -1)


## The steps up to the first square of another room: {"steps", "room"}; `room` is "" when the path stays in `here`.
static func leg(map: Dictionary, steps: Array[Vector2i], here: String) -> Dictionary:
	var out: Array[Vector2i] = []
	for cell: Vector2i in steps:
		var room := room_of(map, cell)
		if not room.is_empty() and room != here:
			return {"steps": out, "room": room}
		out.append(cell)
	return {"steps": out, "room": ""}


static func stand(s: GameSession, map: Dictionary, room: String, cell: Vector2i) -> void:
	var kept := LayoutGen.on_grid(map, cell)
	s.layouts["at"] = {"map": str(map["id"]), "room": room, "x": kept.x, "y": kept.y}
	ConditionRules.on_move(s.character)  # what lasts until the hero moves (v0.8.4.26.1)


## Where the hero stands on the map of the room now. A move that was no walk (a button, the road, the master) puts the
## hero by the door or way that leads back, else at the room's entry.
static func settle(s: GameSession, data: Dictionary, map: Dictionary) -> Vector2i:
	var at: Dictionary = s.layouts.get("at", {})
	var cell := LayoutGen.off_grid(map, Vector2i(int(at.get("x", 0)), int(at.get("y", 0))))
	var came := str(at.get("room", ""))
	if str(at.get("map", "")) == str(map["id"]) and (came == s.room_id or room_of(map, cell) == s.room_id) and passable(map, data["layouts"], cell):
		if came != s.room_id:
			stand(s, map, s.room_id, cell)
		return cell
	cell = _arrival(map, data["layouts"], came, s.room_id)
	stand(s, map, s.room_id, cell)
	return cell


static func _arrival(map: Dictionary, lib: Dictionary, came: String, room: String) -> Vector2i:
	var ids: Array = map["ids"]
	var index := ids.find(room)
	for d: Dictionary in map["doors"]:
		if [str(ids[int(d["a"])]), str(ids[int(d["b"])])].has(came) and index in [int(d["a"]), int(d["b"])]:
			for step: Vector2i in DIRS.slice(0, 4):
				var cell := Vector2i(int(d["x"]), int(d["y"])) + step
				if room_of(map, cell) == room and passable(map, lib, cell):
					return cell
	for e: Dictionary in map["exits"]:
		if str(e["to"]) == came and str(e["room"]) == room and passable(map, lib, Vector2i(int(e["ax"]), int(e["ay"]))):
			return Vector2i(int(e["ax"]), int(e["ay"]))
	for m: Dictionary in map["marks"]:
		if str(m["name"]) == LayoutGen.ENTRY and int(m["room"]) == index and passable(map, lib, Vector2i(int(m["x"]), int(m["y"]))):
			return Vector2i(int(m["x"]), int(m["y"]))
	var rows: Array[String] = map["rows"]
	var any := Vector2i.ZERO
	for y: int in rows.size():
		for x: int in rows[y].length():
			var cell := Vector2i(x, y)
			if passable(map, lib, cell):
				if room_of(map, cell) == room:
					return cell
				any = cell
	return any


## Free squares close to `cell`, nearest first: where those who walk with the hero stand when there is no trail yet.
static func around(map: Dictionary, lib: Dictionary, cell: Vector2i, count: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var seen: Dictionary = {cell: true}
	var queue: Array[Vector2i] = [cell]
	var head := 0
	while head < queue.size() and out.size() < count:
		var at: Vector2i = queue[head]
		head += 1
		for d: Vector2i in DIRS:
			var next := at + d
			if seen.has(next) or not passable(map, lib, next):
				continue
			seen[next] = true
			queue.append(next)
			if out.size() < count:
				out.append(next)
	return out
