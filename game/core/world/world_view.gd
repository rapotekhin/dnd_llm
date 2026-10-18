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
