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
	return out


## The room of a square, "" for what belongs to none.
static func room_of(map: Dictionary, cell: Vector2i) -> String:
	if cell.x < 0 or cell.y < 0 or cell.x >= int(map["w"]) or cell.y >= int(map["h"]):
		return ""
	var i := LayoutGen.room_at(map, cell.x, cell.y)
	return str(map["ids"][i]) if i >= 0 and i < (map["ids"] as Array).size() else ""


static func passable(map: Dictionary, lib: Dictionary, cell: Vector2i) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x >= int(map["w"]) or cell.y >= int(map["h"]):
		return false
	return not LayoutGen.solid(lib, (map["rows"] as Array[String])[cell.y][cell.x])


## The shortest way by squares in eight directions, a corner is not cut: a diagonal needs both squares beside it free.
## Empty when there is none. `from` is not in it.
static func path(map: Dictionary, lib: Dictionary, from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if from == to or not passable(map, lib, to):
		return out
	var came: Dictionary = {from: from}
	var queue: Array[Vector2i] = [from]
	var head := 0
	while head < queue.size():
		var at: Vector2i = queue[head]
		head += 1
		if at == to:
			break
		for d: Vector2i in DIRS:
			var next := at + d
			if came.has(next) or not passable(map, lib, next):
				continue
			if d.x != 0 and d.y != 0 and not (passable(map, lib, at + Vector2i(d.x, 0)) and passable(map, lib, at + Vector2i(0, d.y))):
				continue
			came[next] = at
			queue.append(next)
	if not came.has(to):
		return out
	var back := to
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
	s.layouts["at"] = {"map": str(map["id"]), "room": room, "x": cell.x, "y": cell.y}


## Where the hero stands on the map of the room now. A move that was no walk (a button, the road, the master) puts the
## hero by the door or way that leads back, else at the room's entry.
static func settle(s: GameSession, data: Dictionary, map: Dictionary) -> Vector2i:
	var at: Dictionary = s.layouts.get("at", {})
	var cell := Vector2i(int(at.get("x", 0)), int(at.get("y", 0)))
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
