class_name TurnSnapshot
extends RefCounted
## The turn snapshot for turn.request (ADR-0009 §4): scene, character in final numbers, history within a
## character budget, summaries, limits. Only what the master may see: hooks, never hidden things.


static func build(s: GameSession, data: Dictionary, history_chars: int) -> Dictionary:
	var world := WorldView.new(data["world"])
	var room := world.room(s.room_id)
	var loc_id := world.location_id(s.room_id)
	var loc := world.location(loc_id)
	var exits: Array[Dictionary] = []
	for e: String in world.exits(s.room_id):
		exits.append({"room_id": e, "name": world.room(e).get("name", e)})
	var npcs: Array[Dictionary] = []
	for id: String in world.npcs_in(s.room_id):
		var n := world.npc(id)
		npcs.append({"npc_id": id, "name": n.get("name", id), "role": n.get("role", ""), "race": n.get("race", ""),
			"gender": n.get("gender", "other"), "description": n.get("description", ""),
			"personality": n.get("personality", ""), "attitude": s.attitude(id)})
	var summaries := {}
	if s.summaries.has("location:" + loc_id):
		summaries["location"] = s.summaries["location:" + loc_id]
	for id: String in world.npcs_in(s.room_id):
		if s.summaries.has("dialogue:" + id):
			summaries["dialogue:" + id] = s.summaries["dialogue:" + id]
	return {
		"scene": {
			"location_id": loc_id, "location_name": loc.get("name", loc_id), "location_description": loc.get("description", ""),
			"room_id": s.room_id, "room_name": room.get("name", s.room_id), "room_description": room.get("description", ""),
			"exits": exits, "npcs": npcs, "hooks": room.get("hooks", []), "flags": s.flags,
		},
		"character": character_sheet(s, data["items"]),
		"history": s.history(history_chars),
		"summaries": summaries,
		"limits": {"max_checks": int(data["rules"]["turn_limits"]["max_checks"]),
			"max_effects": int(data["rules"]["turn_limits"]["max_effects"])},
	}


static func character_sheet(s: GameSession, items: Dictionary) -> Dictionary:
	var c := s.character
	var inventory: Array[Dictionary] = []
	for id: String in c.get("inventory", {}):
		inventory.append({"item_id": id, "name": ItemRules.display_name(items, s.items, id), "qty": int(c["inventory"][id])})
	return {
		"name": c.get("name", ""), "gender": c.get("gender", "other"), "race": c.get("race", ""),
		"class_name": c.get("class_name", ""), "level": int(c.get("level", 1)), "hp": int(c.get("hp", 0)),
		"max_hp": int(c.get("max_hp", 0)), "ac": int(c.get("ac", 10)), "conditions": c.get("conditions", []),
		"skills": c.get("skills", {}), "saves": c.get("saves", {}), "gold_cp": int(c.get("gold_cp", 0)),
		"inventory": inventory, "features": c.get("features", []),
	}
