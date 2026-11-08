class_name LayoutGen
extends RefCounted
## The generator of maps (v0.8.0): a separate layer, pure and replaceable. In: the rooms of a map with what they ask,
## the data of game/data/layouts.json and a seed. Out: a layout, the same for the same input. It knows nothing of a
## session or a pack: LayoutRules reads those. `picks` are the chunks already chosen, kept by a save.
##
## A layout: {"w", "h", "rows": Array[String], "rooms": PackedInt32Array (w * h, an index of "ids", -1 outside),
## "ids": Array[String], "marks": [{"name", "x", "y", "room"}], "doors": [{"x", "y", "a", "b"}],
## "exits": [{"to", "room", "x", "y", "side", "kind", "ax", "ay"}], "picks": {...}, "origin": where its rows begin on the
## grid, "faults"}. A map is built, checked (`faults`) and built again on the next seed while something is wrong: the best
## of the tries stands and `picks` keep it. What a save keeps is on the grid: a room laid later does not move the others.

const WALL := "#"
const FLOOR := "."
const SOCKET := "D"
const DOOR := "+"
const ROAD := "="
const PATH := ","
const BLANK := " "
const SIDES: Array[String] = ["n", "e", "s", "w"]
const STEP: Dictionary = {"n": Vector2i(0, -1), "e": Vector2i(1, 0), "s": Vector2i(0, 1), "w": Vector2i(-1, 0)}
const OPPOSITE: Dictionary = {"n": "s", "e": "w", "s": "n", "w": "e"}
const ROTATIONS := 4
const FILL := "B"  ## what fills a pocket of an open map nobody can reach, unless the kind scatters something
const ENTRY := "entry"
const TRY_STEP := 1000  ## how far apart the seeds of two tries are: an open map takes two of its own


# --- chunks --------------------------------------------------------------------------------------------------------


## A chunk's rows turned by `rot` quarter turns and mirrored; the letters of marks turn with them.
static func turned(rows: Array, rot: int, flip: bool) -> Array[String]:
	var out: Array[String] = []
	for r: Variant in rows:
		out.append(str(r))
	if flip:
		for i: int in out.size():
			out[i] = out[i].reverse()
	for _i: int in posmod(rot, ROTATIONS):
		out = _quarter(out)
	return out


static func _quarter(rows: Array[String]) -> Array[String]:
	var h := rows.size()
	var w := rows[0].length()
	var out: Array[String] = []
	for x: int in w:
		var line := ""
		for y: int in range(h - 1, -1, -1):
			line += rows[y][x]
		out.append(line)
	return out


## The sockets of turned rows: [{"x", "y", "side"}].
static func sockets(rows: Array[String]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var h := rows.size()
	var w := rows[0].length()
	for y: int in h:
		for x: int in w:
			if rows[y][x] != SOCKET:
				continue
			var side := "n" if y == 0 else "s" if y == h - 1 else "w" if x == 0 else "e"
			out.append({"x": x, "y": y, "side": side})
	return out


static func chunk(lib: Dictionary, id: String) -> Dictionary:
	for c: Dictionary in lib["chunks"]:
		if str(c["id"]) == id:
			return c
	return {}


## The kind of a place by its tags; a kind that only names a family stands for that family (inn → tavern).
static func kind_of(lib: Dictionary, tags: Array) -> String:
	for t: Variant in tags:
		if lib["kinds"].has(str(t)):
			return str(t)
	return ""


static func shape_of(lib: Dictionary, kind: String, indoor: bool) -> String:
	var k: Dictionary = lib["kinds"].get(kind, {})
	while not k.has("shape") and k.has("family"):
		k = lib["kinds"].get(str(k["family"]), {})
	return str(k.get("shape", "building" if indoor else "open"))


## The chain of a room's chunks from the exact to the general: it cannot end in nothing, a generic one fits every size.
## A chunk made for a room's tag comes first; with `rng` the chunks of one step come in a random order.
static func candidates(lib: Dictionary, ask: Dictionary, rng: RandomNumberGenerator = null) -> Array[Dictionary]:
	var kind := str(ask.get("kind", ""))
	var role := str(ask.get("role", ""))
	var tags: Array = ask.get("tags", [])
	var size := str(ask.get("size", "medium"))
	var rooms_only: Array = (lib["chunks"] as Array).filter(func(c: Dictionary) -> bool: return not c.has("landmarks"))
	var out: Array[Dictionary] = []
	_step(out, rooms_only.filter(func(c: Dictionary) -> bool:
		return tags.any(func(t: Variant) -> bool: return (c.get("tags", []) as Array).has(t))), rng)
	var family := kind
	while not family.is_empty():
		var step_family := family
		_step(out, rooms_only.filter(func(c: Dictionary) -> bool:
			return (c.get("kinds", []) as Array).has(step_family) and (role.is_empty() or not c.has("roles") or (c["roles"] as Array).has(role))), rng)
		family = str(lib["kinds"].get(family, {}).get("family", ""))
	_step(out, rooms_only.filter(func(c: Dictionary) -> bool: return bool(c.get("generic", false)) and str(c["size"]) == size), rng)
	_step(out, rooms_only.filter(func(c: Dictionary) -> bool: return bool(c.get("generic", false))), rng)
	return out


static func _step(out: Array[Dictionary], list: Array, rng: RandomNumberGenerator) -> void:
	if rng != null:
		_shuffle(list, rng)
	for c: Dictionary in list:
		if not out.has(c):
			out.append(c)


# --- stitched maps: a building's floor, tunnels ----------------------------------------------------------------------


## `asks`: one per room, its "id", "kind", "role", "tags", "size", "links" (the ids of this map's rooms next to it),
## "exits" [{"to", "side", "kind"}] out of the map, "chunk" {"id", "rot", "flip"} or "rows" of the author's. The first
## is the root. A room that finds no socket goes into "left": LayoutRules gives it a map of its own.
static func stitched(lib: Dictionary, asks: Array[Dictionary], seed_value: int, picks: Dictionary) -> Dictionary:
	var all_kept := asks.all(func(a: Dictionary) -> bool: return picks.has(str(a["id"])))
	return _best(lib, asks, picks, 1 if all_kept else int(lib["sound"]["tries"]), func(t: int) -> Dictionary:
		return _stitch(lib, asks, seed_value + t * TRY_STEP, picks))


## Builds until a map is sound or the tries are over; the best one stands, a save keeps which try it was.
static func _best(lib: Dictionary, asks: Array[Dictionary], kept: Dictionary, tries: int, build: Callable) -> Dictionary:
	var first := int(kept.get("try", 0))
	var best := {}
	var fewest := -1
	for t: int in range(first, first + tries):
		var out: Dictionary = build.call(t)
		var n := faults(lib, out, asks)
		if fewest < 0 or n < fewest:
			fewest = n
			best = out
			best["picks"]["try"] = t
		if n < int(lib["sound"]["retry_from"]):
			break
	best["faults"] = fewest
	return best


## What is wrong with a map, weighed by `sound` of layouts.json; 0 is a sound map.
static func faults(lib: Dictionary, out: Dictionary, asks: Array[Dictionary]) -> int:
	var sound: Dictionary = lib["sound"]
	var n := (out["left"] as Array).size() * int(sound["left"])
	var reach := reached(out, lib, _start(out))
	if out.has("open") and reach.size() < float(sound["min_reach"]) * int(out["w"]) * int(out["h"]):
		n += int(sound["way"])
	var stairs := {}
	for a: Dictionary in asks:
		for e: Dictionary in a.get("exits", []):
			if str(e.get("kind", "")) == "stairs":
				stairs[str(e["to"])] = true
	for e: Dictionary in out["exits"]:
		if not reach.has(Vector2i(int(e["ax"]), int(e["ay"]))):
			n += int(sound["way"])
		elif str(e["kind"]) == "stairs" and not stairs.has(str(e["to"])):
			n += int(sound["stairs"])
	for a: Dictionary in asks:
		for e: Dictionary in a.get("exits", []):
			for got: Dictionary in out["exits"]:
				if str(got["to"]) == str(e["to"]) and str(got["side"]) != str(e.get("side", got["side"])):
					n += int(sound["side"])
	return n


static func _start(out: Dictionary) -> Vector2i:
	for m: Dictionary in out["marks"]:
		if str(m["name"]) == ENTRY:
			return Vector2i(int(m["x"]), int(m["y"]))
	return Vector2i(int(out["w"]) / 2, int(out["h"]) / 2)


## A square of a map as a save keeps it, and back.
static func on_grid(map: Dictionary, cell: Vector2i) -> Vector2i:
	return cell + map.get("origin", Vector2i.ZERO)


static func off_grid(map: Dictionary, cell: Vector2i) -> Vector2i:
	return cell - map.get("origin", Vector2i.ZERO)


## One try: the rooms a save keeps first, in the order they were laid, then the new ones by the links from the root.
static func _stitch(lib: Dictionary, asks: Array[Dictionary], seed_value: int, picks: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var grid: Dictionary[Vector2i, String] = {}
	var owner: Dictionary[Vector2i, int] = {}
	var ids: Array[String] = []
	var kept: Dictionary = {}
	var marks: Array[Dictionary] = []
	var doors: Array[Dictionary] = []
	var free: Array[Dictionary] = []  # the unused sockets of placed rooms, on the grid
	var left: Array[String] = []
	var asked: Dictionary = {}
	for a: Dictionary in asks:
		asked[str(a["id"])] = a
	for id: String in _kept_order(picks, asked):
		var at := _replace(lib, asked[id], picks[id], grid, free, ids)
		if not at.is_empty():
			_put(id, at, ids, kept, grid, owner, marks, free, doors)
	var reserved := _reserved(picks, free)
	var queue: Array[String] = [str(asks[0]["id"])]
	var seen: Dictionary = {queue[0]: true}
	while not queue.is_empty():
		var id: String = queue.pop_front()
		var ask: Dictionary = asked[id]
		if not ids.has(id):
			var at := _place(lib, ask, grid, free, ids, rng, reserved)
			if at.is_empty():
				left.append(id)
				continue
			_put(id, at, ids, kept, grid, owner, marks, free, doors)
		for link: Variant in ask.get("links", []):
			if asked.has(str(link)) and not seen.has(str(link)):
				seen[str(link)] = true
				queue.append(str(link))
	for a: Dictionary in asks:  # a room no link reaches is laid on as well: the pack's graph may be one-way
		if not seen.has(str(a["id"])) and not ids.has(str(a["id"])):
			left.append(str(a["id"]))
	rng.seed = seed_value  # what follows comes out the same whether the rooms were laid anew or from a save's picks
	var out := _rasterized(grid, owner)
	out["ids"] = ids
	out["left"] = left
	out["picks"] = kept
	out["marks"] = _shifted(marks, out["origin"])
	out["doors"] = _shifted(doors, out["origin"])
	out["exits"] = []
	var rests: Array[Dictionary] = _shifted(free, out["origin"])
	for a: Dictionary in asks:
		var id := str(a["id"])
		var index := ids.find(id)
		if index >= 0:
			var pick: Dictionary = picks.get(id, {})
			if int(pick.get("x", 0)) != int(kept[id]["x"]) or int(pick.get("y", 0)) != int(kept[id]["y"]):
				pick = {}
			var ways: Array = (a.get("exits", []) as Array).duplicate()
			ways.append_array(_unjoined(a, index, ids, doors))
			_exits_of(out, a, index, ways, rests, rng, pick, int(lib["open"].get("room_gap", 0)))
			kept[id]["spots"] = _wanted_marks(out, a, index, rng, pick)
			kept[id]["ways"] = _ways_of(out, id)
	_close_sockets(out)
	return out


static func _kept_order(picks: Dictionary, asked: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for id: Variant in picks:
		if asked.has(str(id)):
			out.append(str(id))
	out.sort_custom(func(a: String, b: String) -> bool: return int(picks[a].get("i", 0)) < int(picks[b].get("i", 0)))
	return out


static func _put(id: String, at: Dictionary, ids: Array[String], kept: Dictionary, grid: Dictionary, owner: Dictionary, marks: Array[Dictionary], free: Array[Dictionary], doors: Array[Dictionary]) -> void:
	var index := ids.size()
	ids.append(id)
	kept[id] = {"chunk": at["chunk"], "rot": at["rot"], "flip": at["flip"], "x": at["x"], "y": at["y"], "i": index}
	_stamp(at, index, grid, owner, marks, free, doors)


## The ways of kept rooms stay: a new room takes neither their sockets nor the squares behind them.
static func _reserved(picks: Dictionary, free: Array[Dictionary]) -> Dictionary:
	var out := {}
	for pick: Variant in picks.values():
		if not pick is Dictionary:
			continue
		var ways: Dictionary = (pick as Dictionary).get("ways", {})
		for e: Dictionary in ways.values():
			if str(e["kind"]) != "stairs":
				var cell := Vector2i(int(e["x"]), int(e["y"]))
				out[cell] = true
				out[cell + STEP[str(e["side"])]] = true
	for i: int in range(free.size() - 1, -1, -1):
		if out.has(Vector2i(int(free[i]["x"]), int(free[i]["y"]))):
			free.remove_at(i)
	return out


## The ways of a room on the grid, as a save keeps them.
static func _ways_of(out: Dictionary, id: String) -> Dictionary:
	var ways := {}
	var origin: Vector2i = out.get("origin", Vector2i.ZERO)
	for e: Dictionary in out["exits"]:
		if str(e["room"]) == id:
			var kept := e.duplicate()
			for k: String in ["x", "ax"]:
				kept[k] = int(e[k]) + origin.x
			for k: String in ["y", "ay"]:
				kept[k] = int(e[k]) + origin.y
			ways[str(e["to"])] = kept
	return ways


## A kept way of a stitched room back on its square; false when the square is no longer free for it.
static func _way_back(out: Dictionary, was: Dictionary, rests: Array[Dictionary]) -> bool:
	var e := was.duplicate()
	var origin: Vector2i = out.get("origin", Vector2i.ZERO)
	for k: String in ["x", "ax"]:
		e[k] = int(was[k]) - origin.x
	for k: String in ["y", "ay"]:
		e[k] = int(was[k]) - origin.y
	var x := int(e["x"])
	var y := int(e["y"])
	if not _inside(out, x, y):
		return false
	if str(e["kind"]) != "stairs":
		if str(out["rows"][y][x]) != SOCKET:
			return false
		_set_cell(out, x, y, DOOR)
		for i: int in rests.size():
			if int(rests[i]["x"]) == x and int(rests[i]["y"]) == y:
				rests.remove_at(i)
				break
	out["exits"].append(e)
	return true


## The links a door does not serve (a ring of rooms, a room left out): ways of their own.
static func _unjoined(ask: Dictionary, index: int, ids: Array[String], doors: Array[Dictionary]) -> Array:
	var out: Array = []
	for link: Variant in ask.get("links", []):
		var other := ids.find(str(link))
		var joined := false
		for d: Dictionary in doors:
			joined = joined or (int(d["a"]) == index and int(d["b"]) == other) or (int(d["b"]) == index and int(d["a"]) == other)
		if not joined:
			out.append({"to": str(link), "side": ask.get("link_sides", {}).get(str(link), "n"), "kind": "door"})
	return out


## Marks a chunk does not have stand on free squares by a wall; a kept one stays where it stood. Out: all of them on the grid.
static func _wanted_marks(out: Dictionary, ask: Dictionary, index: int, rng: RandomNumberGenerator, pick: Dictionary) -> Dictionary:
	var names: Array = (ask.get("marks", []) as Array).duplicate()
	names.append(ENTRY)
	var spots: Dictionary = (pick.get("spots", {}) as Dictionary).duplicate()
	var origin: Vector2i = out.get("origin", Vector2i.ZERO)
	var fresh: Array[String] = []
	for name: Variant in names:
		var has := false
		for m: Dictionary in out["marks"]:
			has = has or (str(m["name"]) == str(name) and int(m["room"]) == index)
		if has:
			continue
		if spots.has(str(name)):
			var at: Array = spots[str(name)]
			out["marks"].append({"name": str(name), "x": int(at[0]) - origin.x, "y": int(at[1]) - origin.y, "room": index})
		else:
			fresh.append(str(name))
	for name: String in fresh:
		var spot := _by_wall(out, index, rng)
		out["marks"].append({"name": name, "x": spot["x"], "y": spot["y"], "room": index})
		spots[name] = [int(spot["x"]) + origin.x, int(spot["y"]) + origin.y]
	return spots


## A room back where a save keeps it, its door on the socket it shares with a linked room.
static func _replace(lib: Dictionary, ask: Dictionary, pick: Dictionary, grid: Dictionary, free: Array[Dictionary], ids: Array[String]) -> Dictionary:
	var src := _source(lib, ask, str(pick.get("chunk", "")))
	if src.is_empty():
		return {}
	var rows := turned(src["rows"], int(pick.get("rot", 0)), bool(pick.get("flip", false)))
	var pos := Vector2i(int(pick.get("x", 0)), int(pick.get("y", 0)))
	if not grid.is_empty() and not _fits(rows, pos, grid):
		return {}
	var join := {}
	for s: Dictionary in sockets(rows):
		var cell := pos + Vector2i(int(s["x"]), int(s["y"]))
		for other: Dictionary in free:
			if int(other["x"]) == cell.x and int(other["y"]) == cell.y and (ask.get("links", []) as Array).has(ids[int(other["room"])]):
				join = other
	return {"chunk": src["id"], "rot": int(pick.get("rot", 0)), "flip": bool(pick.get("flip", false)), "x": pos.x, "y": pos.y, "rows": rows,
		"marks": src.get("marks", {}), "join": join}


static func _source(lib: Dictionary, ask: Dictionary, id: String) -> Dictionary:
	if ask.has("rows"):
		return {"id": "own", "rows": ask["rows"], "marks": ask.get("marks_own", {})}
	return chunk(lib, id)


static func _place(lib: Dictionary, ask: Dictionary, grid: Dictionary, free: Array[Dictionary], ids: Array[String], rng: RandomNumberGenerator, reserved: Dictionary) -> Dictionary:
	var pool: Array[Dictionary] = []
	if ask.has("rows"):
		pool.append(_source(lib, ask, ""))
	elif ask.has("chunk"):
		pool.append(chunk(lib, str(ask["chunk"].get("id", ""))))
		pool.append_array(candidates(lib, ask, rng))
	else:
		pool = candidates(lib, ask, rng)
	var fixed: Dictionary = ask.get("chunk", {})
	for src: Dictionary in pool:
		if src.is_empty():
			continue
		for turn: Vector2i in _turns(rng, src, fixed):
			var rows := turned(src["rows"], turn.x, turn.y == 1)
			var pos := _position(rows, ask, grid, free, ids, rng, reserved)
			if pos.is_empty():
				continue
			pos.merge({"chunk": src["id"], "rot": turn.x, "flip": turn.y == 1, "rows": rows, "marks": src.get("marks", {})})
			return pos
	return {}


static func _turns(rng: RandomNumberGenerator, src: Dictionary, fixed: Dictionary) -> Array[Vector2i]:
	if str(fixed.get("id", "")) == str(src["id"]):
		return [Vector2i(int(fixed.get("rot", 0)), 1 if fixed.get("flip", false) else 0)]
	var out: Array[Vector2i] = []
	for rot: int in ROTATIONS:
		for f: int in 2:
			out.append(Vector2i(rot, f))
	_shuffle(out, rng)
	return out


static func _shuffle(list: Array, rng: RandomNumberGenerator) -> void:
	for i: int in range(list.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t: Variant = list[i]
		list[i] = list[j]
		list[j] = t


## The spot of turned rows: a free socket of a linked room matched with an opposite socket of these rows.
static func _position(rows: Array[String], ask: Dictionary, grid: Dictionary, free: Array[Dictionary], ids: Array[String], rng: RandomNumberGenerator, reserved: Dictionary) -> Dictionary:
	if ids.is_empty():
		return {"x": 0, "y": 0, "join": {}}
	var own := sockets(rows)
	_shuffle(own, rng)
	for other: Dictionary in free:
		if not (ask.get("links", []) as Array).has(ids[int(other["room"])]):
			continue
		for mine: Dictionary in own:
			if str(mine["side"]) != str(OPPOSITE[str(other["side"])]):
				continue
			var pos := Vector2i(int(other["x"]) - int(mine["x"]), int(other["y"]) - int(mine["y"]))
			if _fits(rows, pos, grid, reserved):
				return {"x": pos.x, "y": pos.y, "join": other}
	return {}


## Rows may lie on what is there only wall on wall: rooms share their walls. `reserved` squares stay as they are.
static func _fits(rows: Array[String], pos: Vector2i, grid: Dictionary, reserved: Dictionary = {}) -> bool:
	for y: int in rows.size():
		for x: int in rows[y].length():
			var at := pos + Vector2i(x, y)
			if rows[y][x] == BLANK:
				continue
			if reserved.has(at) or (grid.has(at) and not (_walled(rows[y][x]) and _walled(str(grid[at])))):
				return false
	return true


static func _walled(c: String) -> bool:
	return c == WALL or c == SOCKET or c == DOOR


static func _stamp(at: Dictionary, index: int, grid: Dictionary, owner: Dictionary, marks: Array[Dictionary], free: Array[Dictionary], doors: Array[Dictionary]) -> void:
	var pos := Vector2i(int(at["x"]), int(at["y"]))
	var rows: Array[String] = at["rows"]
	var legend: Dictionary = at["marks"]
	for y: int in rows.size():
		for x: int in rows[y].length():
			var c: String = rows[y][x]
			if c == BLANK:
				continue
			var cell := pos + Vector2i(x, y)
			if legend.has(c):
				marks.append({"name": str(legend[c]), "x": cell.x, "y": cell.y, "room": index})
				c = FLOOR
			if not grid.has(cell):
				grid[cell] = c
				owner[cell] = index
			elif c != SOCKET and grid[cell] == SOCKET:  # a wall laid on a free socket: the socket is gone
				grid[cell] = WALL
	var join: Dictionary = at.get("join", {})
	if not join.is_empty():
		var door := Vector2i(int(join["x"]), int(join["y"]))
		grid[door] = DOOR
		doors.append({"x": door.x, "y": door.y, "a": int(join["room"]), "b": index})
	for s: Dictionary in sockets(rows):
		var cell := pos + Vector2i(int(s["x"]), int(s["y"]))
		if grid.get(cell) == SOCKET and int(owner[cell]) == index:
			free.append({"x": cell.x, "y": cell.y, "side": s["side"], "room": index})
	for i: int in range(free.size() - 1, -1, -1):
		if grid.get(Vector2i(int(free[i]["x"]), int(free[i]["y"]))) != SOCKET:
			free.remove_at(i)


static func _rasterized(grid: Dictionary, owner: Dictionary) -> Dictionary:
	var lo := Vector2i(1 << 20, 1 << 20)
	var hi := -lo
	for cell: Vector2i in grid:
		lo = Vector2i(mini(lo.x, cell.x), mini(lo.y, cell.y))
		hi = Vector2i(maxi(hi.x, cell.x), maxi(hi.y, cell.y))
	var w := hi.x - lo.x + 1
	var h := hi.y - lo.y + 1
	var rows: Array[String] = []
	var rooms := PackedInt32Array()
	rooms.resize(w * h)
	rooms.fill(-1)
	for y: int in h:
		var line := ""
		for x: int in w:
			var cell := lo + Vector2i(x, y)
			line += str(grid.get(cell, BLANK))
			if owner.has(cell):
				rooms[y * w + x] = int(owner[cell])
		rows.append(line)
	return {"w": w, "h": h, "rows": rows, "rooms": rooms, "origin": lo}


static func _shifted(list: Array[Dictionary], origin: Vector2i) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Dictionary in list:
		var moved := e.duplicate()
		moved["x"] = int(e["x"]) - origin.x
		moved["y"] = int(e["y"]) - origin.y
		out.append(moved)
	return out


## The ways out of a room: a free socket on the side of the world's scheme, else any, else a square by a wall.
static func _exits_of(out: Dictionary, ask: Dictionary, index: int, ways: Array, rests: Array[Dictionary], rng: RandomNumberGenerator, pick: Dictionary, gap: int) -> void:
	var fresh: Array[Dictionary] = []
	for e: Dictionary in ways:
		var was: Dictionary = pick.get("ways", {}).get(str(e["to"]), {})
		if was.is_empty() or not _way_back(out, was, rests):
			fresh.append(e)
	for e: Dictionary in fresh:
		var side := str(e.get("side", "n"))
		var spot := {} if str(e.get("kind", "door")) == "stairs" else _socket_for(out, rests, index, side, gap, str(ask["id"]))
		if spot.is_empty():
			spot = _by_wall(out, index, rng)
			out["exits"].append({"to": e["to"], "room": str(ask["id"]), "x": spot["x"], "y": spot["y"], "ax": spot["x"], "ay": spot["y"], "side": side, "kind": "stairs"})
			continue
		_set_cell(out, int(spot["x"]), int(spot["y"]), DOOR)
		var inward: Vector2i = STEP[OPPOSITE[str(spot["side"])]]
		var kind := str(e.get("kind", "door"))
		out["exits"].append({"to": e["to"], "room": str(ask["id"]), "x": spot["x"], "y": spot["y"], "ax": int(spot["x"]) + inward.x,
			"ay": int(spot["y"]) + inward.y, "side": spot["side"], "kind": kind})


## A socket for a way: away from the room's other ways first (the author's feedback, v0.8.4.36), on the wanted side first.
static func _socket_for(out: Dictionary, rests: Array[Dictionary], index: int, side: String, gap: int, room: String) -> Dictionary:
	for far: bool in [true, false]:
		for want: bool in [true, false]:
			for i: int in rests.size():
				var s: Dictionary = rests[i]
				if int(s["room"]) == index and (not want or str(s["side"]) == side) and _opens_out(out, s) 						and (not far or _gap_to(out, Vector2i(int(s["x"]), int(s["y"])), room) >= gap):
					rests.remove_at(i)
					return s
	return {}


## Squares from `at` to the nearest way already laid (of `room` alone when it is given); far when there is none.
static func _gap_to(out: Dictionary, at: Vector2i, room := "") -> int:
	var best := 1 << 20
	for e: Dictionary in out["exits"]:
		if room.is_empty() or str(e["room"]) == room:
			best = mini(best, maxi(absi(int(e["x"]) - at.x), absi(int(e["y"]) - at.y)))
	return best


## A way out must lead to nothing of this map: the square behind the socket is empty.
static func _opens_out(out: Dictionary, s: Dictionary) -> bool:
	var beyond: Vector2i = Vector2i(int(s["x"]), int(s["y"])) + STEP[str(s["side"])]
	return not _inside(out, beyond.x, beyond.y) or str(out["rows"][beyond.y][beyond.x]) == BLANK


static func _by_wall(out: Dictionary, index: int, rng: RandomNumberGenerator) -> Dictionary:
	var by_wall: Array[Dictionary] = []
	var free: Array[Dictionary] = []
	for y: int in int(out["h"]):
		for x: int in int(out["w"]):
			if room_at(out, x, y) != index or str(out["rows"][y][x]) != FLOOR or _marked(out, x, y):
				continue
			free.append({"x": x, "y": y})
			for side: String in SIDES:
				var n: Vector2i = Vector2i(x, y) + STEP[side]
				if _inside(out, n.x, n.y) and str(out["rows"][n.y][n.x]) == WALL:
					by_wall.append({"x": x, "y": y})
					break
	var list := by_wall if not by_wall.is_empty() else free
	return list[rng.randi_range(0, list.size() - 1)] if not list.is_empty() else {"x": 1, "y": 1}


static func _marked(out: Dictionary, x: int, y: int) -> bool:
	for m: Dictionary in out["marks"]:
		if int(m["x"]) == x and int(m["y"]) == y:
			return true
	for e: Dictionary in out["exits"]:
		if int(e["x"]) == x and int(e["y"]) == y:
			return true
	return false


static func _close_sockets(out: Dictionary) -> void:
	var rows: Array[String] = out["rows"]
	for y: int in rows.size():
		rows[y] = rows[y].replace(SOCKET, WALL)


# --- open maps: a street, a forest -----------------------------------------------------------------------------------


## `ask`: "id", "kind", "tags", "exits" [{"to", "side", "kind": "edge" | "door"}], "kept" — the picks of a save, "marks" the
## room asks for. A building on the street is a box with a door; a way on is the edge of the map, on its side.
static func open_map(lib: Dictionary, ask: Dictionary, seed_value: int) -> Dictionary:
	var kept: Dictionary = ask.get("kept", {})
	var asks: Array[Dictionary] = [ask]
	return _best(lib, asks, kept, 1 if kept.has("ways") else int(lib["sound"]["tries"]), func(t: int) -> Dictionary:
		return _open(lib, ask, kept, seed_value + t * TRY_STEP))


static func _open(lib: Dictionary, ask: Dictionary, kept: Dictionary, seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var kinds: Dictionary = lib["kinds"]
	var kind: Dictionary = kinds.get(str(ask.get("kind", "")), {})
	var cfg: Dictionary = lib["open"]
	var size: Array = kind.get("size", cfg["size"])
	var w := int(size[0])
	var h := int(size[1])
	var own: Array = ask.get("rows", [])
	if not own.is_empty():
		w = str(own[0]).length()
		h = own.size()
	var grid: Array[PackedStringArray] = []
	for y: int in h:
		var line := PackedStringArray()
		line.resize(w)
		line.fill(FLOOR)
		if not own.is_empty():
			line = str(own[y]).split("")
			line.resize(w)
		grid.append(line)
	var tags: Array = ask.get("tags", [])
	if own.is_empty():
		_scatter(grid, kind.get("scatter", []), int(cfg["noise_cell"]), rng)
		if tags.has("water"):
			_pond(grid, float(cfg["pond"]), rng)
	var center := Vector2i(w / 2, h / 2)
	var out := {"w": w, "h": h, "ids": [str(ask["id"])], "marks": [] as Array[Dictionary], "doors": [] as Array[Dictionary], "exits": [] as Array[Dictionary],
		"left": [] as Array[String], "origin": Vector2i.ZERO, "open": true}
	var landmark := {} if not own.is_empty() else _landmark(lib, kind, kept.get("landmark", {}), w, h, rng)
	rng.seed = seed_value + 1  # a kept landmark draws nothing: what follows comes out the same after a save
	var taken := {}  # the squares nothing may wall up: the middle, ways out and what lies before them
	var boxes := {}  # the walls of the buildings: unlike a ruin's, no way is dug through them
	var clear := int(cfg["clear"])
	for y: int in range(center.y - clear, center.y + clear + 1):
		for x: int in range(center.x - clear, center.x + clear + 1):
			taken[Vector2i(x, y)] = true
	_exits_open(out, grid, ask, cfg, kept, taken, boxes)
	_clear(grid, center, clear)
	var picks := {}
	if not landmark.is_empty():
		_lay(out, grid, landmark, taken)
		picks["landmark"] = {"chunk": landmark["chunk"], "rot": landmark["rot"], "flip": landmark["flip"], "x": landmark["x"], "y": landmark["y"]}
	grid[center.y][center.x] = FLOOR
	var rows: Array[String] = []
	for line: PackedStringArray in grid:
		rows.append("".join(line))
	out["rows"] = rows
	var rooms := PackedInt32Array()
	rooms.resize(w * h)
	rooms.fill(0)
	out["rooms"] = rooms
	var scattered: Array = kind.get("scatter", [])
	var fill := str(scattered[0]["cell"]) if not scattered.is_empty() and solid(lib, str(scattered[0]["cell"])) else FILL
	_cut_off(out, lib, center, fill, boxes)
	out["marks"].append({"name": ENTRY, "x": center.x, "y": center.y, "room": 0})
	picks["spots"] = _wanted_marks(out, ask, 0, rng, kept)
	picks["ways"] = _ways_of(out, str(ask["id"]))
	var paved := ROAD if tags.has("road") or tags.has("market") or bool(kind.get("paved", false)) else PATH
	picks["roads"] = _roads(out, lib, center, paved, kept, seed_value)
	out["picks"] = picks
	return out


static func _scatter(grid: Array[PackedStringArray], rows: Array, cell: int, rng: RandomNumberGenerator) -> void:
	for row: Dictionary in rows:
		var coarse := _coarse(grid[0].size(), grid.size(), cell, rng)
		var share := float(row["share"])
		for y: int in grid.size():
			for x: int in grid[y].size():
				if rng.randf() < share * 2.0 * _noise(coarse, cell, x, y):
					grid[y][x] = str(row["cell"])


static func _coarse(w: int, h: int, cell: int, rng: RandomNumberGenerator) -> Array[PackedFloat32Array]:
	var out: Array[PackedFloat32Array] = []
	for _y: int in h / cell + 2:
		var line := PackedFloat32Array()
		for _x: int in w / cell + 2:
			line.append(rng.randf())
		out.append(line)
	return out


static func _noise(coarse: Array[PackedFloat32Array], cell: int, x: int, y: int) -> float:
	var cx := x / cell
	var cy := y / cell
	var fx := float(x % cell) / cell
	var fy := float(y % cell) / cell
	var top := lerpf(coarse[cy][cx], coarse[cy][cx + 1], fx)
	var bottom := lerpf(coarse[cy + 1][cx], coarse[cy + 1][cx + 1], fx)
	return lerpf(top, bottom, fy)


static func _pond(grid: Array[PackedStringArray], share: float, rng: RandomNumberGenerator) -> void:
	var h := grid.size()
	var w := grid[0].size()
	var rx := maxf(3.0, sqrt(share * w * h / PI) * rng.randf_range(0.8, 1.3))
	var ry := maxf(3.0, share * w * h / PI / rx)
	var center := Vector2(rng.randf_range(rx + 2.0, w - rx - 2.0), rng.randf_range(ry + 2.0, h - ry - 2.0))
	for y: int in h:
		for x: int in w:
			if pow((x - center.x) / rx, 2.0) + pow((y - center.y) / ry, 2.0) <= 1.0:
				grid[y][x] = "~"


static func _landmark(lib: Dictionary, kind: Dictionary, kept_one: Dictionary, w: int, h: int, rng: RandomNumberGenerator) -> Dictionary:
	var kept := kept_one
	var src := chunk(lib, str(kept.get("chunk", "")))
	if src.is_empty():
		var pool: Array = (lib["chunks"] as Array).filter(func(c: Dictionary) -> bool:
			for t: Variant in c.get("landmarks", []):
				if (kind.get("landmarks", []) as Array).has(t):
					return true
			return false)
		if pool.is_empty():
			return {}
		src = pool[rng.randi_range(0, pool.size() - 1)]
		kept = {"rot": rng.randi_range(0, ROTATIONS - 1), "flip": rng.randf() < 0.5}
	var rows := turned(src["rows"], int(kept.get("rot", 0)), bool(kept.get("flip", false)))
	var x := int(kept.get("x", (w - rows[0].length()) / 2 + rng.randi_range(-w / 6, w / 6)))
	var y := int(kept.get("y", (h - rows.size()) / 2 + rng.randi_range(-h / 6, h / 6)))
	return {"chunk": src["id"], "rot": int(kept.get("rot", 0)), "flip": bool(kept.get("flip", false)), "x": x, "y": y, "rows": rows, "marks": src.get("marks", {})}


static func _lay(out: Dictionary, grid: Array[PackedStringArray], at: Dictionary, taken: Dictionary) -> void:
	var rows: Array[String] = at["rows"]
	var legend: Dictionary = at["marks"]
	for y: int in rows.size():
		for x: int in rows[y].length():
			var c: String = rows[y][x]
			var gx := int(at["x"]) + x
			var gy := int(at["y"]) + y
			if c == BLANK or gy < 0 or gy >= grid.size() or gx < 0 or gx >= grid[0].size() or grid[gy][gx] == DOOR or grid[gy][gx] == WALL or taken.has(Vector2i(gx, gy)):
				continue
			if legend.has(c):
				out["marks"].append({"name": str(legend[c]), "x": gx, "y": gy, "room": 0})
				c = FLOOR
			grid[gy][gx] = c


## The ways out: a box with a door on the way to a building, the edge of the map otherwise. A kept way stands where it
## stood; of the new ones the edges come first, so that a box keeps off what lies before them.
static func _exits_open(out: Dictionary, grid: Array[PackedStringArray], ask: Dictionary, cfg: Dictionary, kept: Dictionary, taken: Dictionary, boxes: Dictionary) -> void:
	var fresh: Array = []
	for e: Dictionary in ask.get("exits", []):
		var was: Dictionary = kept.get("ways", {}).get(str(e["to"]), {})
		if was.is_empty():
			fresh.append(e)
		else:
			_way_again(out, grid, was, taken, boxes)
	var by_side := _spread(fresh, int(cfg["spread"]))
	var w: int = grid[0].size()
	var h: int = grid.size()
	for doors: bool in [false, true]:
		for side: String in by_side:
			var list: Array = by_side[side]
			for i: int in list.size():
				var e: Dictionary = list[i]
				if (str(e.get("kind", "edge")) == "door") != doors:
					continue
				var along := int(round((i + 1.0) / (list.size() + 1.0) * (w if side in ["n", "s"] else h)))
				if not doors or not _box(out, grid, e, side, along, cfg, taken, boxes):
					_edge(out, grid, e, side, along, taken, int(cfg.get("gap", 0)))
	var order := {}
	for e: Dictionary in ask.get("exits", []):
		order[str(e["to"])] = order.size()
	(out["exits"] as Array[Dictionary]).sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(order[str(a["to"])]) < int(order[str(b["to"])]))


static func _way_again(out: Dictionary, grid: Array[PackedStringArray], was: Dictionary, taken: Dictionary, boxes: Dictionary) -> void:
	var e := was.duplicate()
	var at := Vector2i(int(e["x"]), int(e["y"]))
	if e.has("box"):
		var b: Array = e["box"]
		_wall_box(grid, int(b[0]), int(b[1]), int(b[2]), int(b[3]), boxes)
		grid[at.y][at.x] = DOOR
	out["exits"].append(e)
	taken[at] = true
	taken[Vector2i(int(e["ax"]), int(e["ay"]))] = true


## The spots for a way: along its side from the wanted one outwards, then the same on the next sides, clockwise.
static func _around(side: String, along: int, w: int, h: int) -> Array[Array]:
	var out: Array[Array] = []
	var start := SIDES.find(side)
	for turn: int in SIDES.size():
		var s: String = SIDES[(start + turn) % SIDES.size()]
		var span := w if s in ["n", "s"] else h
		var from := along if turn == 0 else span / 2
		for d: int in span:
			for a: int in ([from] if d == 0 else [from + d, from - d]):
				if a >= 1 and a <= span - 2:
					out.append([s, a])
	return out


## The ways by sides of the world's scheme; a side past `spread` passes the rest on to the next one, clockwise.
static func _spread(ways: Array, spread: int) -> Dictionary:
	var out: Dictionary = {}
	for side: String in SIDES:
		out[side] = []
	for e: Dictionary in ways:
		var i := SIDES.find(str(e.get("side", "n")))
		var turns := 0
		while (out[SIDES[i]] as Array).size() >= spread and turns < SIDES.size() - 1:
			i = (i + 1) % SIDES.size()
			turns += 1
		(out[SIDES[i]] as Array).append(e)
	return out


## A way on the edge: the nearest free spot to the wanted one that keeps `gap` from the ways already there (the author's
## feedback, v0.8.4.36: new ways were laid right beside the old), else the nearest free one.
static func _edge(out: Dictionary, grid: Array[PackedStringArray], e: Dictionary, side: String, along: int, taken: Dictionary, gap := 0) -> void:
	var w: int = grid[0].size()
	var h: int = grid.size()
	var spots := _around(side, along, w, h)
	var pick: Array = spots[0]
	var found := false
	for far: bool in [true, false]:
		for spot: Array in spots:
			var at := _edge_cell(str(spot[0]), int(spot[1]), w, h)
			var before: Vector2i = at + STEP[OPPOSITE[str(spot[0])]]
			if not taken.has(at) and not taken.has(before) and grid[before.y][before.x] != WALL and grid[before.y][before.x] != DOOR 					and (not far or _gap_to(out, at) >= gap):
				pick = spot
				found = true
				break
		if found:
			break
	var s := str(pick[0])
	var at := _edge_cell(s, int(pick[1]), w, h)
	var before: Vector2i = at + STEP[OPPOSITE[s]]
	taken[at] = true
	taken[before] = true
	out["exits"].append({"to": e["to"], "room": str(out["ids"][0]), "x": at.x, "y": at.y, "ax": before.x, "ay": before.y, "side": s, "kind": "edge"})


static func _edge_cell(side: String, along: int, w: int, h: int) -> Vector2i:
	if side in ["n", "s"]:
		return Vector2i(along, 0 if side == "n" else h - 1)
	return Vector2i(0 if side == "w" else w - 1, along)


## A box on a free spot: walls may meet, a door and what lies before it stay free. False: no spot, not even for a small one.
static func _box(out: Dictionary, grid: Array[PackedStringArray], e: Dictionary, side: String, along: int, cfg: Dictionary, taken: Dictionary, boxes: Dictionary) -> bool:
	for far: bool in [true, false]:  # away from the ways already there first (v0.8.4.36)
		if _box_far(out, grid, e, side, along, cfg, taken, boxes, int(cfg.get("gap", 0)) if far else 0):
			return true
	return false


static func _box_far(out: Dictionary, grid: Array[PackedStringArray], e: Dictionary, side: String, along: int, cfg: Dictionary, taken: Dictionary, boxes: Dictionary, gap: int) -> bool:
	var w: int = grid[0].size()
	var h: int = grid.size()
	for size: Array in [cfg["box"], cfg["box_small"]]:
		for spot: Array in _around(side, along, w, h):
			var at := _box_at(str(spot[0]), int(spot[1]), size, w, h)
			if not _box_free(grid, at, taken) or _gap_to(out, at["door"]) < gap:
				continue
			var door: Vector2i = at["door"]
			var front: Vector2i = at["front"]
			_wall_box(grid, at["x"], at["y"], at["w"], at["h"], boxes)
			grid[door.y][door.x] = DOOR
			taken[door] = true
			taken[front] = true
			out["exits"].append({"to": e["to"], "room": str(out["ids"][0]), "x": door.x, "y": door.y, "ax": front.x, "ay": front.y, "side": spot[0], "kind": "door",
				"box": [at["x"], at["y"], at["w"], at["h"]]})
			return true
	return false


static func _box_at(side: String, along: int, size: Array, w: int, h: int) -> Dictionary:
	var bw := int(size[0]) if side in ["n", "s"] else int(size[1])
	var bh := int(size[1]) if side in ["n", "s"] else int(size[0])
	var margin := 1
	var x: int
	var y: int
	match side:
		"n":
			x = along - bw / 2
			y = margin
		"s":
			x = along - bw / 2
			y = h - bh - margin
		"w":
			x = margin
			y = along - bh / 2
		_:
			x = w - bw - margin
			y = along - bh / 2
	x = clampi(x, 1, w - bw - 1)
	y = clampi(y, 1, h - bh - 1)
	var door: Vector2i
	match side:
		"n":
			door = Vector2i(x + bw / 2, y + bh - 1)
		"s":
			door = Vector2i(x + bw / 2, y)
		"w":
			door = Vector2i(x + bw - 1, y + bh / 2)
		_:
			door = Vector2i(x, y + bh / 2)
	return {"x": x, "y": y, "w": bw, "h": bh, "door": door, "front": door + STEP[OPPOSITE[side]]}


static func _box_free(grid: Array[PackedStringArray], at: Dictionary, taken: Dictionary) -> bool:
	var x: int = at["x"]
	var y: int = at["y"]
	var bw: int = at["w"]
	var bh: int = at["h"]
	if x < 1 or y < 1 or x + bw >= grid[0].size() or y + bh >= grid.size():
		return false
	for by: int in bh:
		for bx: int in bw:
			if taken.has(Vector2i(x + bx, y + by)):
				return false
	for cell: Vector2i in [at["door"], at["front"]]:
		if taken.has(cell) or grid[cell.y][cell.x] == WALL or grid[cell.y][cell.x] == DOOR:
			return false
	return true


static func _wall_box(grid: Array[PackedStringArray], x: int, y: int, bw: int, bh: int, boxes: Dictionary) -> void:
	for by: int in bh:
		for bx: int in bw:
			if grid[y + by][x + bx] != DOOR:
				grid[y + by][x + bx] = WALL
			boxes[Vector2i(x + bx, y + by)] = true


## The roads: a tree over the middle and every way out, by the heuristic of Takahashi and Matsuyama for a Steiner tree.
## The nearest way joins what is laid by the cheapest path from the whole net, so roads fork and merge rather than all run
## to the middle. A road is only a look, walking does not change. Out: the order of the branches: a save's order first,
## so a new way adds a branch and the old ones stay.
static func _roads(out: Dictionary, lib: Dictionary, center: Vector2i, paved: String, kept: Dictionary, seed_value: int) -> Array:
	var w := int(out["w"])
	var weights := _road_weights(out, lib, seed_value)
	var net: Array[int] = [center.y * w + center.x]
	var ends := {}
	for e: Dictionary in out["exits"]:
		ends[str(e["to"])] = int(e["y"]) * w + int(e["x"]) if str(e["kind"]) == "edge" else int(e["ay"]) * w + int(e["ax"])
	var order: Array = []
	var known: Array = (kept.get("roads", []) as Array).filter(func(to: Variant) -> bool: return ends.has(str(to)))
	while not ends.is_empty():
		var found := _cheapest(w, int(out["h"]), weights, net)
		var dist: PackedInt32Array = found["dist"]
		var to := str(known.pop_front()) if not known.is_empty() else _nearest(ends, dist)
		var at := int(ends[to])
		ends.erase(to)
		order.append(to)
		var prev: PackedInt32Array = found["prev"]
		if dist[at] < 0:
			continue
		while dist[at] > 0:
			net.append(at)
			_pave(out, at % w, at / w, paved)
			at = prev[at]
	if not order.is_empty():
		_pave(out, center.x, center.y, paved)
	return order


static func _pave(out: Dictionary, x: int, y: int, paved: String) -> void:
	if str(out["rows"][y][x]) != DOOR:
		_set_cell(out, x, y, paved)


## The way out the net reaches most cheaply; ties go by name, so the same map comes out every time.
static func _nearest(ends: Dictionary, dist: PackedInt32Array) -> String:
	var best := ""
	for to: String in ends:
		var d := dist[int(ends[to])]
		var was := dist[int(ends[best])] if not best.is_empty() else -1
		if best.is_empty() or (d >= 0 and (was < 0 or d < was or (d == was and to < best))):
			best = to
	return best


## What a square costs a road, -1 where none goes; a soft noise makes the roads bend.
static func _road_weights(out: Dictionary, lib: Dictionary, seed_value: int) -> PackedInt32Array:
	var cfg: Dictionary = lib["open"]
	var costs: Dictionary = cfg["road_cost"]
	var cell := int(cfg["noise_cell"])
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 2
	var w := int(out["w"])
	var h := int(out["h"])
	var coarse := _coarse(w, h, cell, rng)
	var weights := PackedInt32Array()
	weights.resize(w * h)
	for y: int in h:
		for x: int in w:
			var c: String = out["rows"][y][x]
			weights[y * w + x] = int(costs[c]) + int(_noise(coarse, cell, x, y) * int(cfg["road_wander"])) if costs.has(c) else -1
	return weights


## Dijkstra from a whole net on a bucket queue: the costs are small whole numbers. {"dist", "prev"} by a square's index.
static func _cheapest(w: int, h: int, weights: PackedInt32Array, net: Array[int]) -> Dictionary:
	var dist := PackedInt32Array()
	dist.resize(w * h)
	dist.fill(-1)
	var prev := PackedInt32Array()
	prev.resize(w * h)
	prev.fill(-1)
	var top := 1
	for c: int in weights:
		top = maxi(top, c + 1)
	var buckets: Array[PackedInt32Array] = []
	buckets.resize(top)
	for i: int in net:
		dist[i] = 0
		buckets[0].append(i)
	var left := net.size()
	var d := 0
	while left > 0:
		var list := buckets[d % top]
		buckets[d % top] = PackedInt32Array()
		left -= list.size()
		for i: int in list:
			if dist[i] != d:
				continue
			var x := i % w
			var y := i / w
			for side: String in SIDES:
				var n: Vector2i = Vector2i(x, y) + STEP[side]
				if n.x < 0 or n.y < 0 or n.x >= w or n.y >= h:
					continue
				var j := n.y * w + n.x
				if weights[j] >= 0 and (dist[j] < 0 or d + weights[j] < dist[j]):
					dist[j] = d + weights[j]
					prev[j] = i
					buckets[dist[j] % top].append(j)
					left += 1
		d += 1
	return {"dist": dist, "prev": prev}


static func _clear(grid: Array[PackedStringArray], center: Vector2i, r: int) -> void:
	for y: int in range(center.y - r, center.y + r + 1):
		for x: int in range(center.x - r, center.x + r + 1):
			if grid[y][x] != WALL and grid[y][x] != DOOR:
				grid[y][x] = FLOOR


## Every walkable square reaches the middle: a road cut by a box is led round it, what stays apart is filled.
static func _cut_off(out: Dictionary, lib: Dictionary, center: Vector2i, fill: String, boxes: Dictionary) -> void:
	for e: Dictionary in out["exits"]:
		var reach := reached(out, lib, center)
		if not reach.has(Vector2i(int(e["ax"]), int(e["ay"]))):
			_dig(out, Vector2i(int(e["ax"]), int(e["ay"])), reach, boxes)
	var reach := reached(out, lib, center)
	var rows: Array[String] = out["rows"]
	for y: int in int(out["h"]):
		for x: int in int(out["w"]):
			var c: String = rows[y][x]
			if c != DOOR and not solid(lib, c) and not reach.has(Vector2i(x, y)):
				_set_cell(out, x, y, fill)


## The shortest way from `from` to what is reached, through anything but a building: a ruin's wall gets a breach.
static func _dig(out: Dictionary, from: Vector2i, reach: Dictionary, boxes: Dictionary) -> void:
	var prev: Dictionary = {from: from}
	var queue: Array[Vector2i] = [from]
	var rows: Array[String] = out["rows"]
	while not queue.is_empty():
		var at: Vector2i = queue.pop_front()
		if reach.has(at):
			while prev[at] != at:
				at = prev[at]
				if rows[at.y][at.x] != DOOR:
					_set_cell(out, at.x, at.y, FLOOR)
			return
		for side: String in SIDES:
			var n: Vector2i = at + STEP[side]
			if _inside(out, n.x, n.y) and not prev.has(n) and rows[n.y][n.x] != DOOR and not boxes.has(n):
				prev[n] = at
				queue.append(n)


# --- reading a layout ------------------------------------------------------------------------------------------------


static func _inside(out: Dictionary, x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < int(out["w"]) and y < int(out["h"])


static func room_at(out: Dictionary, x: int, y: int) -> int:
	return int(out["rooms"][y * int(out["w"]) + x])


static func _set_cell(out: Dictionary, x: int, y: int, c: String) -> void:
	var rows: Array[String] = out["rows"]
	rows[y] = rows[y].substr(0, x) + c + rows[y].substr(x + 1)


static func solid(lib: Dictionary, c: String) -> bool:
	return c == BLANK or bool(lib["cells"].get(c, {}).get("solid", false))


## The squares a walker reaches from `from` by the four sides; doors are walked through.
static func reached(out: Dictionary, lib: Dictionary, from: Vector2i) -> Dictionary:
	var seen: Dictionary = {from: true}
	var queue: Array[Vector2i] = [from]
	var rows: Array[String] = out["rows"]
	while not queue.is_empty():
		var at: Vector2i = queue.pop_back()
		for side: String in SIDES:
			var n: Vector2i = at + STEP[side]
			if _inside(out, n.x, n.y) and not seen.has(n) and not solid(lib, rows[n.y][n.x]):
				seen[n] = true
				queue.append(n)
	return seen
