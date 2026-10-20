class_name WorldMap
extends RefCounted
## The map of the hero's world (roadmap v0.7.6, decisions of the author): what is known — visited rooms and the open
## exits out of them as «?» (unvisited, unnamed); where each room stands on the scheme — an automatic layout of the
## whole pack graph, so places keep their spot as the map grows and nothing unknown leaks; the quest marks; the
## route of a fast travel through visited rooms only.

const TRAVEL_DEPTH := 1.8  # a step into another location, in steps inside one
const MIN_ARC := 1.1  # the arc a room wants for itself, in steps
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
	for r: String in rooms:
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
static func route(s: GameSession, world: Dictionary, from: String, to: String) -> Array[String]:
	if from == to or not s.visited.has(to):
		return []
	var prev := {from: ""}
	var queue: Array[String] = [from]
	while not queue.is_empty():
		var r: String = queue.pop_front()
		if r == to:
			break
		for e: String in ExplorationRules.open_exits(s, world, r):
			if prev.has(e) or not s.visited.has(e) or blocked(s, world, r, e):
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
static func minutes(data: Dictionary, from: String, path: Array[String]) -> int:
	var w := WorldView.new(data["world"])
	var cfg: Dictionary = data["rules"]["time"]
	var total := 0
	var at := from
	for r: String in path:
		total += int(cfg["move_minutes"] if w.location_id(at) == w.location_id(r) else cfg["travel_minutes"])
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


static func _step_rooms(w: WorldView, world: Dictionary, when: Dictionary, out: Array[String]) -> void:
	for key: String in ["all", "any"]:
		for sub: Variant in when.get(key, []):
			_step_rooms(w, world, sub, out)
	var room := ""
	if when.has("room"):
		room = str(when["room"])
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


## Where every room of the pack stands, 0..1 on both axes: a radial tree from the start room over every exit
## (closed ones too) — each branch gets its own sector by the number of rooms in it, so branches never cross; a
## step into another location is longer than a step inside one. Deterministic and cached per world: the same pack —
## the same map, and a place keeps its spot as the map grows.
static func layout(world: Dictionary) -> Dictionary:
	var ids: Array = world["rooms"].keys()
	ids.sort()
	var key := "%s|%d|%d" % [str(world.get("start_room", "")), ids.size(), hash(ids)]
	if _layouts.has(key):
		return _layouts[key]
	var root := str(world.get("start_room", ids[0] if not ids.is_empty() else ""))
	var children := {root: []}
	var depth := {root: 0.0}
	var queue: Array = [root]
	while not queue.is_empty():
		var r: String = queue.pop_front()
		var exits: Array = (world["rooms"][r].get("exits", []) as Array).map(func(e: Variant) -> String: return str(e))
		exits.sort()
		for e: String in exits:
			if depth.has(e) or not world["rooms"].has(e):
				continue
			var far := str(world["rooms"][e].get("location_id", "")) != str(world["rooms"][r].get("location_id", ""))
			depth[e] = float(depth[r]) + (TRAVEL_DEPTH if far else 1.0)
			children[e] = []
			(children[r] as Array).append(e)
			queue.append(e)
	for r: String in ids:  # rooms no exit leads to hang off the root
		if not depth.has(r):
			depth[r] = 1.0
			children[r] = []
			(children[root] as Array).append(r)
	var weight := {}
	_weigh(root, children, weight)
	var pos := {}
	_place(root, 0.0, TAU, children, weight, depth, pos)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for r: String in ids:
		lo = lo.min(pos[r])
		hi = hi.max(pos[r])
	var span := maxf(0.001, maxf(hi.x - lo.x, hi.y - lo.y))
	var out := {}
	for r: String in ids:
		out[r] = (pos[r] - lo) / span
	_layouts[key] = out
	return out


## Rooms in the subtree of `r` (itself included).
static func _weigh(r: String, children: Dictionary, weight: Dictionary) -> int:
	var n := 1
	for c: String in children[r]:
		n += _weigh(c, children, weight)
	weight[r] = n
	return n


static func _place(r: String, from: float, to: float, children: Dictionary, weight: Dictionary, depth: Dictionary, pos: Dictionary) -> void:
	# A narrow sector is pushed out until its room has about a step of arc to itself (labels need the room).
	var radius := float(depth[r])
	if r != "" and to - from < TAU:
		radius = clampf(MIN_ARC / maxf(0.001, to - from), radius, radius + 2.0)
	pos[r] = Vector2.from_angle((from + to) / 2) * radius
	var total := 0
	for c: String in children[r]:
		total += int(weight[c])
	var at := from
	for c: String in children[r]:
		var share := (to - from) * int(weight[c]) / maxf(1.0, total)
		_place(c, at, at + share, children, weight, depth, pos)
		at += share
