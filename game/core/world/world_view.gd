class_name WorldView
extends RefCounted
## Read-only queries over the active world pack's world.json (WorldPack) and a session's place in it.

var world: Dictionary


func _init(world_data: Dictionary) -> void:
	world = world_data


func start_room() -> String:
	return str(world.get("start_room", ""))


func room(id: String) -> Dictionary:
	return world["rooms"].get(id, {})


func location_id(room_id: String) -> String:
	return str(room(room_id).get("location_id", ""))


func location(id: String) -> Dictionary:
	return world["locations"].get(id, {})


# --- the tree of places (v0.7.66): a room, its site and the sites above it, its location and those above it --------


const TREE_DEPTH := 8  # a `parent` chain longer than this is a loop the validator refuses


## The nodes from a room up: the room first. Any node may say what its children inherit: `indoor`, `dark`, `lit`,
## `terrain`, `law`, `public`, `owner`, `tags`.
func chain(room_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = [room(room_id)]
	_up(site_id(room_id), world.get("sites", {}), out)
	_up(location_id(room_id), world["locations"], out)
	return out


func _up(id: String, nodes: Dictionary, out: Array[Dictionary]) -> void:
	for i in TREE_DEPTH:
		if id.is_empty() or not nodes.has(id):
			return
		out.append(nodes[id])
		id = str(nodes[id].get("parent", ""))


## The nearest value of `key` from a room up.
func inherit(room_id: String, key: String, fallback: Variant = null) -> Variant:
	for n: Dictionary in chain(room_id):
		if n.has(key):
			return n[key]
	return fallback


func flag(room_id: String, key: String) -> bool:
	return bool(inherit(room_id, key, false))


## The nearest value of `key` from a location up.
func location_inherit(id: String, key: String, fallback: Variant = null) -> Variant:
	var out: Array[Dictionary] = []
	_up(id, world["locations"], out)
	for n: Dictionary in out:
		if n.has(key):
			return n[key]
	return fallback


## The tags of a room with those of the nodes above it.
func tags(room_id: String) -> Array[String]:
	var out: Array[String] = []
	for n: Dictionary in chain(room_id):
		for t: Variant in n.get("tags", []):
			if not out.has(str(t)):
				out.append(str(t))
	return out


# --- sites (v0.7.22.24): location → site → room ------------------------------------------------------------


func site_id(room_id: String) -> String:
	return str(room(room_id).get("site_id", ""))


func site(id: String) -> Dictionary:
	return world.get("sites", {}).get(id, {})


func site_of(room_id: String) -> Dictionary:
	return site(site_id(room_id))


## The rooms of a site in the pack's order.
func site_rooms(id: String) -> Array[String]:
	var out: Array[String] = []
	for r: String in world["rooms"]:
		if str(world["rooms"][r].get("site_id", "")) == id:
			out.append(r)
	return out


## The sites of a location in the pack's order.
func sites_in(location: String) -> Array[String]:
	var out: Array[String] = []
	for sid: String in world.get("sites", {}):
		if str(world["sites"][sid].get("location_id", "")) == location:
			out.append(sid)
	return out


## Where one comes into a site: its `entry`, else its first room with a way out of it, else its first room.
func site_entry(id: String) -> String:
	var rooms := site_rooms(id)
	var entry := str(site(id).get("entry", ""))
	if rooms.has(entry):
		return entry
	for r: String in rooms:
		if exits(r).any(func(e: String) -> bool: return site_id(e) != id):
			return r
	return rooms[0] if not rooms.is_empty() else ""


## A room anyone may walk into: the nearest `public` from it up (open by default).
func is_public(room_id: String) -> bool:
	return bool(inherit(room_id, "public", true))


## The room's own name without the site's: «Таверна «Хромой олень» — общий зал» → «общий зал».
func room_short(room_id: String) -> String:
	var name := str(room(room_id).get("name", room_id))
	var sname := str(site_of(room_id).get("name", ""))
	if not sname.is_empty() and name.begins_with(sname + " — "):
		return name.trim_prefix(sname + " — ")
	return name


## «Ольховый Брод › Таверна «Хромой олень» › общий зал»; a site of one room is not repeated.
func place_path(room_id: String) -> String:
	var parts: Array[String] = [str(location(location_id(room_id)).get("name", ""))]
	var sname := str(site_of(room_id).get("name", ""))
	if site_rooms(site_id(room_id)).size() > 1 and not sname.is_empty():
		parts.append(sname)
	parts.append(room_short(room_id) if parts.size() > 1 else str(room(room_id).get("name", room_id)))
	return " › ".join(parts.filter(func(x: String) -> bool: return not x.is_empty()))


func exits(room_id: String) -> Array[String]:
	var out: Array[String] = []
	for e: Variant in room(room_id).get("exits", []):
		out.append(str(e))
	return out


func npcs_in(room_id: String) -> Array[String]:
	var out: Array[String] = []
	for n: Variant in room(room_id).get("npcs", []):
		out.append(str(n))
	return out


func npc(id: String) -> Dictionary:
	return world["npcs"].get(id, {})


func is_trader(id: String) -> bool:
	return bool(npc(id).get("trader", false))
