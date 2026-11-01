class_name LayoutGen
extends RefCounted
## The generator of maps (v0.8.0): a separate layer, pure and replaceable. In: the rooms of a map with what they ask,
## the data of game/data/layouts.json and a seed. Out: a layout, the same for the same input. It knows nothing of a
## session or a pack: LayoutRules reads those. `picks` are the chunks already chosen, kept by a save.
##
## A layout: {"w", "h", "rows": Array[String], "rooms": PackedInt32Array (w * h, an index of "ids", -1 outside),
## "ids": Array[String], "marks": [{"name", "x", "y", "room"}], "doors": [{"x", "y", "a", "b"}],
## "exits": [{"to", "room", "x", "y", "side", "kind", "ax", "ay"}], "picks": {...}}.

const WALL := "#"
const FLOOR := "."
const SOCKET := "D"
const DOOR := "+"
const ROAD := "="
const BLANK := " "
const SIDES: Array[String] = ["n", "e", "s", "w"]
const STEP: Dictionary = {"n": Vector2i(0, -1), "e": Vector2i(1, 0), "s": Vector2i(0, 1), "w": Vector2i(-1, 0)}
const OPPOSITE: Dictionary = {"n": "s", "e": "w", "s": "n", "w": "e"}
const ROTATIONS := 4
const FILL := "B"  ## what fills a pocket of an open map nobody can reach, unless the kind scatters something
const ENTRY := "entry"


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
	var queue: Array[String] = [str(asks[0]["id"])]
	var seen: Dictionary = {queue[0]: true}
	while not queue.is_empty():
		var id: String = queue.pop_front()
		var ask: Dictionary = asked[id]
		var at := {}
		if picks.has(id):
			at = _replace(lib, ask, picks[id], grid, free, ids)
		if at.is_empty():
			at = _place(lib, ask, grid, free, ids, rng)
		if at.is_empty():
			left.append(id)
			continue
		var index := ids.size()
		ids.append(id)
		kept[id] = {"chunk": at["chunk"], "rot": at["rot"], "flip": at["flip"], "x": at["x"], "y": at["y"]}
		_stamp(at, index, grid, owner, marks, free, doors)
		for link: Variant in ask.get("links", []):
			if asked.has(str(link)) and not seen.has(str(link)):
				seen[str(link)] = true
				queue.append(str(link))
	for a: Dictionary in asks:  # a room no link reaches is laid on as well: the pack's graph may be one-way
		if not seen.has(str(a["id"])):
			left.append(str(a["id"]))
	var out := _rasterized(grid, owner)
	out["ids"] = ids
	out["left"] = left
	out["picks"] = kept
	out["marks"] = _shifted(marks, out["origin"])
	out["doors"] = _shifted(doors, out["origin"])
	out["exits"] = []
	var rests: Array[Dictionary] = _shifted(free, out["origin"])
	for a: Dictionary in asks:
		var index := ids.find(str(a["id"]))
		if index >= 0:
			var ways: Array = (a.get("exits", []) as Array).duplicate()
			ways.append_array(_unjoined(a, index, ids, doors))
			_exits_of(out, a, index, ways, rests, rng)
			_wanted_marks(out, a, index, rng)
	_close_sockets(out)
	return out


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


## Marks a chunk does not have stand on free squares by a wall.
static func _wanted_marks(out: Dictionary, ask: Dictionary, index: int, rng: RandomNumberGenerator) -> void:
	var names: Array = (ask.get("marks", []) as Array).duplicate()
	names.append(ENTRY)
	for name: Variant in names:
		var has := false
		for m: Dictionary in out["marks"]:
			has = has or (str(m["name"]) == str(name) and int(m["room"]) == index)
		if not has:
			var spot := _by_wall(out, index, rng)
			out["marks"].append({"name": str(name), "x": spot["x"], "y": spot["y"], "room": index})


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


static func _place(lib: Dictionary, ask: Dictionary, grid: Dictionary, free: Array[Dictionary], ids: Array[String], rng: RandomNumberGenerator) -> Dictionary:
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
			var pos := _position(rows, ask, grid, free, ids, rng)
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
static func _position(rows: Array[String], ask: Dictionary, grid: Dictionary, free: Array[Dictionary], ids: Array[String], rng: RandomNumberGenerator) -> Dictionary:
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
			if _fits(rows, pos, grid):
				return {"x": pos.x, "y": pos.y, "join": other}
	return {}


## Rows may lie on what is there only wall on wall: rooms share their walls.
static func _fits(rows: Array[String], pos: Vector2i, grid: Dictionary) -> bool:
	for y: int in rows.size():
		for x: int in rows[y].length():
			var at := pos + Vector2i(x, y)
			if rows[y][x] != BLANK and grid.has(at) and not (_walled(rows[y][x]) and _walled(str(grid[at]))):
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
static func _exits_of(out: Dictionary, ask: Dictionary, index: int, ways: Array, rests: Array[Dictionary], rng: RandomNumberGenerator) -> void:
	for e: Dictionary in ways:
		var side := str(e.get("side", "n"))
		var spot := {} if str(e.get("kind", "door")) == "stairs" else _socket_for(out, rests, index, side)
		if spot.is_empty():
			spot = _by_wall(out, index, rng)
			out["exits"].append({"to": e["to"], "room": str(ask["id"]), "x": spot["x"], "y": spot["y"], "ax": spot["x"], "ay": spot["y"], "side": side, "kind": "stairs"})
			continue
		_set_cell(out, int(spot["x"]), int(spot["y"]), DOOR)
		var inward: Vector2i = STEP[OPPOSITE[str(spot["side"])]]
		var kind := str(e.get("kind", "door"))
		out["exits"].append({"to": e["to"], "room": str(ask["id"]), "x": spot["x"], "y": spot["y"], "ax": int(spot["x"]) + inward.x,
			"ay": int(spot["y"]) + inward.y, "side": spot["side"], "kind": kind})


static func _socket_for(out: Dictionary, rests: Array[Dictionary], index: int, side: String) -> Dictionary:
	for want: bool in [true, false]:
		for i: int in rests.size():
			var s: Dictionary = rests[i]
			if int(s["room"]) == index and (not want or str(s["side"]) == side) and _opens_out(out, s):
				rests.remove_at(i)
				return s
	return {}


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


## `ask`: "id", "kind", "tags", "exits" [{"to", "side", "kind": "edge" | "door"}], "landmark" of a save, "marks" the room
## asks for. A building on the street is a box with a door; a way on is the edge of the map, on its side.
static func open_map(lib: Dictionary, ask: Dictionary, seed_value: int) -> Dictionary:
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
		"left": [] as Array[String], "picks": {}}
	var landmark := {} if not own.is_empty() else _landmark(lib, kind, ask, w, h, rng)
	var ends: Array[Vector2i] = _exits_open(out, grid, ask, cfg)
	for end: Vector2i in ends:
		_road(grid, end, center, tags, rng)
	_clear(grid, center, int(cfg["clear"]))
	if not landmark.is_empty():
		_lay(out, grid, landmark)
		out["picks"] = {"landmark": {"chunk": landmark["chunk"], "rot": landmark["rot"], "flip": landmark["flip"], "x": landmark["x"], "y": landmark["y"]}}
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
	_cut_off(out, lib, center, fill)
	out["marks"].append({"name": ENTRY, "x": center.x, "y": center.y, "room": 0})
	_wanted_marks(out, ask, 0, rng)
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


static func _landmark(lib: Dictionary, kind: Dictionary, ask: Dictionary, w: int, h: int, rng: RandomNumberGenerator) -> Dictionary:
	var kept: Dictionary = ask.get("landmark", {})
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


static func _lay(out: Dictionary, grid: Array[PackedStringArray], at: Dictionary) -> void:
	var rows: Array[String] = at["rows"]
	var legend: Dictionary = at["marks"]
	for y: int in rows.size():
		for x: int in rows[y].length():
			var c: String = rows[y][x]
			var gx := int(at["x"]) + x
			var gy := int(at["y"]) + y
			if c == BLANK or gy < 0 or gy >= grid.size() or gx < 0 or gx >= grid[0].size() or grid[gy][gx] == DOOR or grid[gy][gx] == WALL:
				continue
			if legend.has(c):
				out["marks"].append({"name": str(legend[c]), "x": gx, "y": gy, "room": 0})
				c = FLOOR
			grid[gy][gx] = c


## The ways out: a box with a door on the way to a building, the edge of the map otherwise; the point each road leads to.
static func _exits_open(out: Dictionary, grid: Array[PackedStringArray], ask: Dictionary, cfg: Dictionary) -> Array[Vector2i]:
	var by_side := _spread(ask.get("exits", []), int(cfg["spread"]))
	var ends: Array[Vector2i] = []
	var w: int = grid[0].size()
	var h: int = grid.size()
	var box: Array = cfg["box"]
	for side: String in by_side:
		var list: Array = by_side[side]
		for i: int in list.size():
			var t := (i + 1.0) / (list.size() + 1.0)
			var e: Dictionary = list[i]
			var along := int(round(t * (w if side in ["n", "s"] else h)))
			if str(e.get("kind", "edge")) == "door":
				ends.append(_box(out, grid, e, side, along, box))
			else:
				ends.append(_edge(out, e, side, along, w, h))
	return ends


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


static func _edge(out: Dictionary, e: Dictionary, side: String, along: int, w: int, h: int) -> Vector2i:
	var at := Vector2i(clampi(along, 1, w - 2), 0 if side == "n" else h - 1) if side in ["n", "s"] else Vector2i(0 if side == "w" else w - 1, clampi(along, 1, h - 2))
	var inward: Vector2i = STEP[OPPOSITE[side]]
	out["exits"].append({"to": e["to"], "room": str(out["ids"][0]), "x": at.x, "y": at.y, "ax": at.x + inward.x, "ay": at.y + inward.y, "side": side, "kind": "edge"})
	return at


static func _box(out: Dictionary, grid: Array[PackedStringArray], e: Dictionary, side: String, along: int, box: Array) -> Vector2i:
	var w: int = grid[0].size()
	var h: int = grid.size()
	var bw := int(box[0]) if side in ["n", "s"] else int(box[1])
	var bh := int(box[1]) if side in ["n", "s"] else int(box[0])
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
	for by: int in bh:
		for bx: int in bw:
			if grid[y + by][x + bx] != DOOR:
				grid[y + by][x + bx] = WALL
	var inward: Vector2i = STEP[OPPOSITE[side]]
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
	grid[door.y][door.x] = DOOR
	var front := door + inward
	out["exits"].append({"to": e["to"], "room": str(out["ids"][0]), "x": door.x, "y": door.y, "ax": front.x, "ay": front.y, "side": side, "kind": "door"})
	return front


## A road from a way to the middle: two straight legs; a forest path is floor, a town's road is paved.
static func _road(grid: Array[PackedStringArray], from: Vector2i, to: Vector2i, tags: Array, rng: RandomNumberGenerator) -> void:
	var paved := ROAD if tags.has("road") or tags.has("market") else FLOOR
	var bend := Vector2i(from.x, to.y) if rng.randf() < 0.5 else Vector2i(to.x, from.y)
	for leg: Array in [[from, bend], [bend, to]]:
		var a: Vector2i = leg[0]
		var b: Vector2i = leg[1]
		var at := a
		var step := Vector2i(signi(b.x - a.x), signi(b.y - a.y))
		while true:
			_pave(grid, at, paved)
			if at == b:
				break
			at += step


static func _pave(grid: Array[PackedStringArray], at: Vector2i, paved: String) -> void:
	if at.y < 0 or at.y >= grid.size() or at.x < 0 or at.x >= grid[0].size():
		return
	var c := grid[at.y][at.x]
	if c != DOOR and c != "~":
		if c == WALL:
			return
		grid[at.y][at.x] = paved


static func _clear(grid: Array[PackedStringArray], center: Vector2i, r: int) -> void:
	for y: int in range(center.y - r, center.y + r + 1):
		for x: int in range(center.x - r, center.x + r + 1):
			if grid[y][x] != WALL and grid[y][x] != DOOR:
				grid[y][x] = FLOOR


## Every walkable square reaches the middle: a road cut by a box is led round it, what stays apart is filled.
static func _cut_off(out: Dictionary, lib: Dictionary, center: Vector2i, fill: String) -> void:
	for e: Dictionary in out["exits"]:
		var reach := reached(out, lib, center)
		if not reach.has(Vector2i(int(e["ax"]), int(e["ay"]))):
			_dig(out, lib, Vector2i(int(e["ax"]), int(e["ay"])), reach)
	var reach := reached(out, lib, center)
	var rows: Array[String] = out["rows"]
	for y: int in int(out["h"]):
		for x: int in int(out["w"]):
			var c: String = rows[y][x]
			if c != DOOR and not solid(lib, c) and not reach.has(Vector2i(x, y)):
				_set_cell(out, x, y, fill)


## The shortest way from `from` to what is reached, through anything but walls and doors.
static func _dig(out: Dictionary, lib: Dictionary, from: Vector2i, reach: Dictionary) -> void:
	var prev: Dictionary = {from: from}
	var queue: Array[Vector2i] = [from]
	var rows: Array[String] = out["rows"]
	while not queue.is_empty():
		var at: Vector2i = queue.pop_front()
		if reach.has(at):
			while prev[at] != at:
				at = prev[at]
				if rows[at.y][at.x] != WALL and rows[at.y][at.x] != DOOR:
					_set_cell(out, at.x, at.y, FLOOR)
			return
		for side: String in SIDES:
			var n: Vector2i = at + STEP[side]
			if _inside(out, n.x, n.y) and not prev.has(n) and rows[n.y][n.x] != WALL and rows[n.y][n.x] != DOOR:
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
