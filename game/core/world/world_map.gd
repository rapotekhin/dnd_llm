class_name WorldMap
extends RefCounted
## The map of the hero's world (roadmap v0.7.6, decisions of the author): what is known — visited rooms and the open
## exits out of them as «?» (unvisited, unnamed); where each room stands on the scheme — an automatic layout of the
## whole pack, so places keep their spot as the map grows and nothing unknown leaks; the quest marks; the route of a
## fast travel through visited rooms only. v0.7.22.24: the layout is nested boxes — locations, their sites, rooms.

const ROOM_CELL := Vector2(3.0, 1.9)  # a room's place in a site's box, in map units
const TITLE_CHAR := 0.34  # about how wide a letter of a box's name is, in map units
const SITE_PAD := 0.35
const LOC_PAD := 0.6
const TITLE_H := 0.7  # the band of a box's name
const SITE_GAP := 0.5
const LOC_GAP := 1.6
static var _layouts: Dictionary = {}  # world key → {room id: Vector2 in 0..1}


## What the hero knows: {"rooms": visited ids, "frontier": unvisited ids behind open exits, "edges": [[a, b]]}.
## Edges run between visited rooms and from a visited room to its frontier, each pair once.
static func known(s: GameSession, world: Dictionary) -> Dictionary:
	var rooms: Array[String] = []
	for r: Variant in s.visited:
		if world["rooms"].has(str(r)):
			rooms.append(str(r))
	var frontier: Array[String] = []
	var edges: Array = []
	var seen := {}
	for r: Variant in s.character.get("scouted", []):  # v0.7.43: a pet flew over it — known, its exits not yet
		if world["rooms"].has(str(r)) and not rooms.has(str(r)):
			rooms.append(str(r))
	for r: String in rooms:
		if not s.visited.has(r):
			continue
		for e: String in ExplorationRules.open_exits(s, world, r):
			if not world["rooms"].has(e):
				continue
			if not rooms.has(e) and not frontier.has(e):
				frontier.append(e)
			var key := "%s|%s" % ([r, e] if r < e else [e, r])
			if not seen.has(key):
				seen[key] = true
				edges.append([r, e])
	return {"rooms": rooms, "frontier": frontier, "edges": edges}


## The route of a fast travel from `from` to `to`: room ids after `from`, the last is `to`; [] when there is none.
## Only through visited rooms and open exits, never over an exit guarded by a found live trap (that one is
## disarmed or gone round by hand). Shortest by steps.
static func route(s: GameSession, world: Dictionary, from: String, to: String, data: Dictionary = {}) -> Array[String]:
	if from == to or not s.visited.has(to):
		return []
	var prev := {from: ""}
	var queue: Array[String] = [from]
	while not queue.is_empty():
		var r: String = queue.pop_front()
		if r == to:
			break
		for e: String in ExplorationRules.open_exits(s, world, r):
			if prev.has(e) or not s.visited.has(e) or blocked(s, world, r, e) or (not data.is_empty() and not DoorRules.blocked(s, data, r, e).is_empty()):
				continue
			prev[e] = r
			queue.append(e)
	if not prev.has(to):
		return []
	var out: Array[String] = []
	var at := to
	while at != from:
		out.push_front(at)
		at = str(prev[at])
	return out


## The exit from `room_id` to `to` is guarded by a live trap the hero has found.
static func blocked(s: GameSession, world: Dictionary, room_id: String, to: String) -> bool:
	var trap := ExplorationRules.trap_on_exit(s, world, room_id, to)
	return not trap.is_empty() and ExplorationRules.is_found(s, room_id, trap)


## Minutes of a route by the time rules: a step inside a location, a step into another one.
static func minutes(data: Dictionary, from: String, path: Array[String], mult: float = 1.0) -> int:
	var w := WorldView.new(data["world"])
	var cfg: Dictionary = data["rules"]["time"]
	var total := 0
	var at := from
	for r: String in path:
		total += int(cfg["move_minutes"]) if w.location_id(at) == w.location_id(r) else roundi(int(cfg["travel_minutes"]) * mult)
		at = r
	return total


## Active quests by the visited room where their current step is done or their giver waits for it:
## {room id: [quest titles]}. Places the hero has not seen are never marked.
static func quest_marks(s: GameSession, world: Dictionary) -> Dictionary:
	var out := {}
	var w := WorldView.new(world)
	for qid: Variant in s.quests_active:
		var q := QuestRules.quest(world, str(qid))
		var step := QuestRules.current(s, world, str(qid))
		var rooms: Array[String] = []
		_step_rooms(w, world, step.get("when", {}), rooms)
		for r: String in rooms:
			if s.visited.has(r):
				var list: Array = out.get(r, [])
				if not list.has(str(q.get("title", qid))):
					list.append(str(q.get("title", qid)))
				out[r] = list
	return out


## The known rooms (visited or behind a known exit) of a quest's current step: where the followed quest opens the map.
static func step_rooms(s: GameSession, world: Dictionary, quest_id: String) -> Array[String]:
	var rooms: Array[String] = []
	_step_rooms(WorldView.new(world), world, QuestRules.current(s, world, quest_id).get("when", {}), rooms)
	var frontier: Array = known(s, world)["frontier"]  # a room behind a known exit is shown on the map too
	return rooms.filter(func(r: String) -> bool: return s.visited.has(r) or frontier.has(r))


static func _step_rooms(w: WorldView, world: Dictionary, when: Dictionary, out: Array[String]) -> void:
	for key: String in ["all", "any"]:
		for sub: Variant in when.get(key, []):
			_step_rooms(w, world, sub, out)
	var room := ""
	if when.has("room") or when.has("arrive"):
		room = str(when.get("room", when.get("arrive", "")))
	elif when.has("choice"):
		room = str(when["choice"])
	elif when.has("secret"):
		room = str(when["secret"]).get_slice(":", 0)
	elif when.has("talk"):
		room = npc_room(world, str(when["talk"]))
	elif when.has("encounter"):
		for r: String in world["rooms"]:
			if str(world["rooms"][r].get("encounter", {}).get("id", "")) == str(when["encounter"]):
				room = r
	if not room.is_empty() and not out.has(room):
		out.append(room)


static func npc_room(world: Dictionary, npc_id: String) -> String:
	for r: String in world["rooms"]:
		if (world["rooms"][r].get("npcs", []) as Array).has(npc_id):
			return r
	return ""


## Where every room of the pack stands, 0..1 on both axes — the rooms of boxes() (v0.7.22.24).
static func layout(world: Dictionary) -> Dictionary:
	return boxes(world)["rooms"]


## The map as nested boxes (v0.7.22.24, the author: a location is a frame, its sites are boxes in it, the rooms are
## points in their site), 0..1 on the longer side: {"rooms": {id: Vector2}, "sites": {id: Rect2}, "locations": {id: Rect2},
## "unit": one map unit in 0..1}.
## Locations stand on a grid from the start one, each next to the one it is reached from; the sites of a location — on
## a grid in the order the walk meets them; the rooms of a site — on a grid, the first met first. Deterministic and
## cached per world: the same pack — the same map, a place keeps its spot as the map grows.
static func boxes(world: Dictionary) -> Dictionary:
	var ids: Array = world["rooms"].keys()
	ids.sort()
	var key := "%s|%d|%d|%d" % [str(world.get("start_room", "")), ids.size(), hash(ids), hash((world.get("sites", {}) as Dictionary).keys())]
	if _layouts.has(key):
		return _layouts[key]
	var w := WorldView.new(world)
	var start := str(world.get("start_room", ids[0] if not ids.is_empty() else ""))
	var loc_order: Array[String] = []
	var site_order := {}  # location → [site]
	var room_order := {}  # site → [room]
	for r: String in _walk(world, start):
		var loc := w.location_id(r)
		var sid := w.site_id(r) if not w.site_id(r).is_empty() else "room:" + r
		if not loc_order.has(loc):
			loc_order.append(loc)
			site_order[loc] = []
		if not (site_order[loc] as Array).has(sid):
			(site_order[loc] as Array).append(sid)
			room_order[sid] = []
		(room_order[sid] as Array).append(r)
	var site_size := {}  # a site's box: its rooms on a grid
	for sid: String in room_order:
		var n: int = (room_order[sid] as Array).size()
		var cols := ceili(sqrt(n))
		var title := str(w.site(sid).get("name", "")).length() * TITLE_CHAR  # the name fits its box
		site_size[sid] = Vector2(maxf(cols * ROOM_CELL.x, title), ceili(n / float(cols)) * ROOM_CELL.y) + Vector2(SITE_PAD * 2, SITE_PAD * 2 + TITLE_H)
	var loc_size := {}
	var site_at := {}  # site → its offset in the location's frame
	for loc: String in loc_order:
		var grid := _grid(site_order[loc], site_size, SITE_GAP)
		for sid: String in grid["at"]:
			site_at[sid] = (grid["at"][sid] as Vector2) + Vector2(LOC_PAD, LOC_PAD + TITLE_H)
		loc_size[loc] = Vector2(maxf((grid["size"] as Vector2).x, str(w.location(loc).get("name", "")).length() * TITLE_CHAR * 1.2),
			(grid["size"] as Vector2).y) + Vector2(LOC_PAD * 2, LOC_PAD * 2 + TITLE_H)
	var cell := {}  # location → Vector2i: each next to the one it is reached from
	var used := {}
	for loc: String in loc_order:
		var parent := _parent_location(world, w, loc, cell)
		var at := Vector2i.ZERO if parent.is_empty() else _free_cell(cell[parent], used)
		cell[loc] = at
		used[at] = true
	var lo := Vector2i(999, 999)
	for loc: String in cell:
		lo = Vector2i(mini(lo.x, cell[loc].x), mini(lo.y, cell[loc].y))
	var col_w := {}
	var row_h := {}
	for loc: String in cell:
		col_w[cell[loc].x] = maxf(float(col_w.get(cell[loc].x, 0.0)), (loc_size[loc] as Vector2).x)
		row_h[cell[loc].y] = maxf(float(row_h.get(cell[loc].y, 0.0)), (loc_size[loc] as Vector2).y)
	var out_locs := {}
	var out_sites := {}
	var out_rooms := {}
	for loc: String in cell:
		var x := 0.0
		for c in range(lo.x, cell[loc].x):
			x += float(col_w.get(c, 0.0)) + LOC_GAP
		var y := 0.0
		for rw in range(lo.y, cell[loc].y):
			y += float(row_h.get(rw, 0.0)) + LOC_GAP
		var origin := Vector2(x, y) + (Vector2(float(col_w[cell[loc].x]), float(row_h[cell[loc].y])) - (loc_size[loc] as Vector2)) / 2
		out_locs[loc] = Rect2(origin, loc_size[loc])
		for sid: String in site_order[loc]:
			var sr := Rect2(origin + (site_at[sid] as Vector2), site_size[sid])
			if not sid.begins_with("room:"):
				out_sites[sid] = sr
			var rooms: Array = room_order[sid]
			var cols := ceili(sqrt(rooms.size()))
			var spare := (sr.size.x - SITE_PAD * 2 - cols * ROOM_CELL.x) / 2  # a box wide for its name keeps its rooms in the middle
			for i in rooms.size():
				out_rooms[rooms[i]] = sr.position + Vector2(SITE_PAD + spare, SITE_PAD + TITLE_H) + Vector2((i % cols + 0.5) * ROOM_CELL.x, (i / cols + 0.5) * ROOM_CELL.y)
	var top_left := Vector2(INF, INF)
	for loc: String in out_locs:
		top_left = top_left.min((out_locs[loc] as Rect2).position)
	var span := 0.001
	for loc: String in out_locs:
		var end := (out_locs[loc] as Rect2).end - top_left
		span = maxf(span, maxf(end.x, end.y))
	var res := {"rooms": {}, "sites": {}, "locations": {}, "unit": 1.0 / span}
	for r: String in out_rooms:
		res["rooms"][r] = ((out_rooms[r] as Vector2) - top_left) / span
	for sid: String in out_sites:
		res["sites"][sid] = Rect2(((out_sites[sid] as Rect2).position - top_left) / span, (out_sites[sid] as Rect2).size / span)
	for loc: String in out_locs:
		res["locations"][loc] = Rect2(((out_locs[loc] as Rect2).position - top_left) / span, (out_locs[loc] as Rect2).size / span)
	_layouts[key] = res
	return res


## Boxes of these sizes on a near-square grid, a column as wide and a row as tall as its biggest:
## {"at": {id: offset}, "size": the whole}.
static func _grid(list: Array, sizes: Dictionary, gap: float) -> Dictionary:
	var cols := maxi(1, ceili(sqrt(list.size())))
	var col_w: Array[float] = []
	var row_h: Array[float] = []
	for i in list.size():
		while col_w.size() <= i % cols:
			col_w.append(0.0)
		while row_h.size() <= i / cols:
			row_h.append(0.0)
		col_w[i % cols] = maxf(col_w[i % cols], (sizes[list[i]] as Vector2).x)
		row_h[i / cols] = maxf(row_h[i / cols], (sizes[list[i]] as Vector2).y)
	var at := {}
	for i in list.size():
		var x := 0.0
		for c in i % cols:
			x += col_w[c] + gap
		var y := 0.0
		for rw in i / cols:
			y += row_h[rw] + gap
		at[list[i]] = Vector2(x, y)
	var total := Vector2(gap * maxi(0, col_w.size() - 1), gap * maxi(0, row_h.size() - 1))
	for v: float in col_w:
		total.x += v
	for v: float in row_h:
		total.y += v
	return {"at": at, "size": total}


## Every room once, breadth first from `start` over all exits (closed ones too); the rooms no exit reaches last.
static func _walk(world: Dictionary, start: String) -> Array[String]:
	var out: Array[String] = []
	if world["rooms"].has(start):
		out.append(start)
	var i := 0
	while i < out.size():
		for e: Variant in world["rooms"][out[i]].get("exits", []):
			if world["rooms"].has(str(e)) and not out.has(str(e)):
				out.append(str(e))
		i += 1
	var rest: Array = world["rooms"].keys()
	rest.sort()
	for r: String in rest:
		if not out.has(r):
			out.append(r)
	return out


## The placed location a room of `loc` is reached from ("" — none placed yet: it is the first).
static func _parent_location(world: Dictionary, w: WorldView, loc: String, placed: Dictionary) -> String:
	for r: String in world["rooms"]:
		if w.location_id(r) != loc:
			continue
		for e: Variant in world["rooms"][r].get("exits", []):
			var other := w.location_id(str(e))
			if other != loc and placed.has(other):
				return other
	for other: String in placed:  # an island: next to the first one
		return other
	return ""


## The nearest free grid cell around `at`: right, down, left, up, the corners, then a ring further.
static func _free_cell(at: Vector2i, used: Dictionary) -> Vector2i:
	for ring in range(1, 6):
		for d: Vector2i in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
			if not used.has(at + d * ring):
				return at + d * ring
	return at + Vector2i(used.size(), 0)
