class_name LayoutRules
extends RefCounted
## Maps of places in a game (v0.8.0): which rooms share a map, what a room asks of the generator (LayoutGen), what a save
## keeps. A building's floor and tunnels are one map of joined rooms; a street, a forest — a map to each room; another
## floor is a map of its own and stairs lead there. A save keeps the chunks chosen, so a new chunk in the library does not
## change a seen room, and what was touched until the next long rest; the facts of the world live in their own records.

const OPEN := "open"


static func lib(data: Dictionary) -> Dictionary:
	return data["layouts"]


## What a room says of its place on a map.
static func fields(room: Dictionary) -> Dictionary:
	return room.get("layout", {})


static func kind_of(v: WorldView, data: Dictionary, room_id: String) -> String:
	var tags: Array = (v.site_of(room_id).get("tags", []) as Array).duplicate()
	tags.append_array(v.tags(room_id))
	var kind := LayoutGen.kind_of(lib(data), tags)
	if not kind.is_empty() or v.flag(room_id, "indoor"):
		return kind
	var by: Dictionary = lib(data).get("terrains", {})  # an open place with no kind of its own: its land's (v0.8.4.31)
	var terrain := str(v.location(v.location_id(room_id)).get("terrain", ""))
	return str(by.get(terrain, by.get("default", "")))


static func shape_of(v: WorldView, data: Dictionary, room_id: String) -> String:
	var own := str(fields(v.room(room_id)).get("shape", ""))
	return own if not own.is_empty() else LayoutGen.shape_of(lib(data), kind_of(v, data, room_id), v.flag(room_id, "indoor"))


static func _floor(v: WorldView, room_id: String) -> int:
	return int(fields(v.room(room_id)).get("floor", 0))


## The rooms on one map with `room_id`, the root first: joined by exits, of one site, shape and floor.
static func group(v: WorldView, data: Dictionary, room_id: String) -> Array[String]:
	var shape := shape_of(v, data, room_id)
	if shape == OPEN:
		return [room_id]
	var site := v.site_id(room_id)
	var seen: Dictionary = {room_id: true}
	var queue: Array[String] = [room_id]
	while not queue.is_empty():
		for to: String in _exits(v, queue.pop_back()):
			if not seen.has(to) and v.site_id(to) == site and shape_of(v, data, to) == shape and _floor(v, to) == _floor(v, room_id):
				seen[to] = true
				queue.append(to)
	var out: Array[String] = []
	for id: String in v.site_rooms(site):
		if seen.has(id):
			out.append(id)
	return out


static func _exits(v: WorldView, room_id: String) -> Array[String]:
	var out: Array[String] = []
	for e: Variant in v.room(room_id).get("exits", []):
		out.append(str(e))
	return out


## The side of the world's scheme a way leads to.
static func side(boxes: Dictionary, from: String, to: String) -> String:
	var a: Vector2 = boxes.get(from, Vector2.ZERO)
	var b: Vector2 = boxes.get(to, Vector2.ZERO)
	var d := b - a
	if d.is_zero_approx():
		return LayoutGen.SIDES[absi(hash(from + to)) % LayoutGen.SIDES.size()]
	if absf(d.x) >= absf(d.y):
		return "e" if d.x > 0.0 else "w"
	return "s" if d.y > 0.0 else "n"


## What a room asks of the generator.
static func ask(v: WorldView, data: Dictionary, room_id: String, on_map: Array[String], boxes: Dictionary) -> Dictionary:
	var room := v.room(room_id)
	var own := fields(room)
	var kind := kind_of(v, data, room_id)
	var shape := shape_of(v, data, room_id)
	var role := str(own.get("role", ""))
	if role.is_empty() and shape != "tunnels":
		role = "hall" if on_map[0] == room_id else ""
	var tags := v.tags(room_id)
	var out := {"id": room_id, "kind": kind, "role": role, "tags": tags, "size": str(own.get("size", "cave" if shape == "tunnels" else "medium"))}
	var marks: Array[String] = []
	for t: String in tags:
		if lib(data)["mark_tags"].has(t):
			marks.append(str(lib(data)["mark_tags"][t]))
	out["marks"] = marks
	if own.has("chunk"):
		out["chunk"] = own["chunk"]
	if own.has("rows"):
		out["rows"] = own["rows"]
		out["marks_own"] = own.get("marks", {})
	var links: Array[String] = []
	var ways: Array[Dictionary] = []
	var link_sides := {}
	for to: String in _exits(v, room_id):
		if on_map.has(to):
			links.append(to)
			link_sides[to] = side(boxes, room_id, to)
		elif not v.room(to).is_empty():
			ways.append({"to": to, "side": side(boxes, room_id, to), "kind": _way(v, data, room_id, to, shape)})
	out["links"] = links
	out["link_sides"] = link_sides
	out["exits"] = ways
	return out


static func _way(v: WorldView, data: Dictionary, from: String, to: String, shape: String) -> String:
	if v.site_id(from) == v.site_id(to) and shape_of(v, data, to) == shape and _floor(v, from) != _floor(v, to):
		return "stairs"
	if shape != OPEN:
		return "door"
	return "edge" if shape_of(v, data, to) == OPEN else "door"


static func seed_of(s: GameSession, map_id: String) -> int:
	return hash(str(s.game_seed) + ":" + map_id)


## The id of the map a room stands on: its root room, or the room itself when no socket took it.
static func map_id(s: GameSession, data: Dictionary, room_id: String) -> String:
	var v := WorldView.new(data["world"])
	if (s.layouts.get("apart", {}) as Dictionary).has(room_id):
		return room_id
	return group(v, data, room_id)[0]


## The map a room stands on, with what was touched on it.
static func map_of(s: GameSession, data: Dictionary, room_id: String) -> Dictionary:
	var w: Dictionary = data["world"]
	var v := WorldView.new(w)
	var on_map: Array[String] = [room_id]
	if not (s.layouts.get("apart", {}) as Dictionary).has(room_id):
		on_map = group(v, data, room_id)
	var id := on_map[0]
	var boxes := WorldMap.layout(w)
	var asks: Array[Dictionary] = []
	for r: String in on_map:
		asks.append(ask(v, data, r, on_map, boxes))
	var key := hash([asks, BuildRules.records(v, on_map)])  # what the owners built by hand is a part of the map (v0.8.4.42)
	var cached: Dictionary = s.layout_cache.get(id, {})
	var map: Dictionary = cached.get("map", {})
	if int(cached.get("key", 0)) != key or map.is_empty():
		map = _build(s, data, id, on_map, asks)
		s.layout_cache[id] = {"key": key, "map": map}
		if not (map["left"] as Array).is_empty():
			_part(s, map["left"])
			return map_of(s, data, room_id)
		BuildRules.lay(map, v)
	return map


static func _build(s: GameSession, data: Dictionary, id: String, on_map: Array[String], asks: Array[Dictionary]) -> Dictionary:
	var kept: Dictionary = s.layouts.get("picks", {}).get(id, {})
	var map: Dictionary
	if on_map.size() == 1 and shape_of(WorldView.new(data["world"]), data, on_map[0]) == OPEN:
		var a := asks[0].duplicate()
		a["kept"] = kept
		map = LayoutGen.open_map(lib(data), a, seed_of(s, id))
	else:
		map = LayoutGen.stitched(lib(data), asks, seed_of(s, id), kept)
	map["id"] = id
	if int(map["faults"]) >= int(lib(data)["sound"]["retry_from"]):
		push_warning("LayoutRules: %s stays faulty after the tries: %d" % [id, int(map["faults"])])
	if not s.layouts.has("picks"):
		s.layouts["picks"] = {}
	s.layouts["picks"][id] = map["picks"]
	return map


## Rooms no socket took live on maps of their own from now on.
static func _part(s: GameSession, rooms: Array) -> void:
	if not s.layouts.has("apart"):
		s.layouts["apart"] = {}
	for r: Variant in rooms:
		s.layouts["apart"][str(r)] = true


## Time passes: the map here is remembered, a long rest brings maps back to what was generated.
static func tick(s: GameSession, data: Dictionary) -> Array[String]:
	s.layouts["rested"] = s.rested_at
	if not s.room_id.is_empty():
		map_of(s, data, s.room_id)
	return []


## "" or why an open place takes no new way: `open.ways` of layouts.json, and `ways_outer` of them are for other open
## places alone: one joins a new street, the other leaves the two of them a way on. A full square grows by a street of
## its own, and the master builds there.
static func no_way(s: GameSession, data: Dictionary, room_id: String, outer: bool) -> String:
	var v := WorldView.new(data["world"])
	if v.room(room_id).is_empty() or shape_of(v, data, room_id) != OPEN:
		return ""
	var cap := int(lib(data)["open"]["ways"])
	var ways := _exits(v, room_id).filter(func(to: String) -> bool: return not v.room(to).is_empty())
	if ways.size() >= cap:
		return "отсюда уже %d выходов, больше не встанет: новое ставь от другого места" % cap
	var keep := int(lib(data)["open"]["ways_outer"])
	var inner := ways.filter(func(to: String) -> bool: return shape_of(v, data, to) != OPEN).size()
	if not outer and inner >= cap - keep:
		return "последние %d выхода отсюда — только на другие открытые места: сделай первой комнатой улицу или слободу под открытым небом со своим объектом, а здание поставь на ней, в том же create_place" % keep
	return ""


static func is_open(s: GameSession, data: Dictionary, room_id: String) -> bool:
	return shape_of(WorldView.new(data["world"]), data, room_id) == OPEN


static func _limit(data: Dictionary, kind: String) -> int:
	var k: Dictionary = lib(data)["kinds"].get(kind, {})
	while not k.has("limit") and k.has("family"):
		k = lib(data)["kinds"].get(str(k["family"]), {})
	return int(k.get("limit", 0))


## "" or why these new rooms do not fit a site: the limit of its kind. The master tells it in words.
static func no_room(s: GameSession, data: Dictionary, site_id: String, kind: String, count: int) -> String:
	var limit := _limit(data, kind)
	var now := WorldView.new(data["world"]).site_rooms(site_id).size()
	if limit > 0 and now + count > limit:
		return "в таком месте не больше %d комнат, а здесь уже %d: скажи словами или построй рядом другое" % [limit, now]
	return ""


## The same for a new site of these tags.
static func too_many(data: Dictionary, tags: Array, count: int) -> String:
	var limit := _limit(data, LayoutGen.kind_of(lib(data), tags))
	return "в таком месте не больше %d комнат" % limit if limit > 0 and count > limit else ""
