class_name Lookup
extends RefCounted
## engine.lookup (ADR-0009 §3): reference data on a whitelist — rules, conditions, items, NPCs of the
## current room. Never other locations or hidden things. SRD spells come with the catalog (v0.5.0).


static func find(s: GameSession, data: Dictionary, kind: String, id: String) -> Dictionary:
	var rules: Dictionary = data["rules"]
	match kind:
		"condition":
			if rules["conditions"].has(id):
				return _found({"id": id, "text": rules["conditions"][id]})
		"rule":
			if rules["glossary"].has(id):
				return _found({"id": id, "text": rules["glossary"][id]})
			if rules["conditions"].has(id):
				return _found({"id": id, "text": rules["conditions"][id]})
		"item":
			var def := ItemRules.def_of(data["items"], s.items, id)
			if not def.is_empty():
				var out := def.duplicate()
				out["id"] = id
				out["owned"] = int(s.character.get("inventory", {}).get(id, 0))
				return _found(out)
		"npc":
			var world := WorldView.new(data["world"])
			if world.npcs_in(s.room_id).has(id):
				var n := world.npc(id)
				var out := {"id": id, "name": n.get("name", id), "role": n.get("role", ""), "race": n.get("race", ""),
					"description": n.get("description", ""), "personality": n.get("personality", ""),
					"attitude": s.attitude(id), "trader": bool(n.get("trader", false))}
				if bool(n.get("trader", false)):
					var stock: Array[Dictionary] = []
					for item_id: Variant in n.get("stock", []):
						var d := ItemRules.def_of(data["items"], s.items, str(item_id))
						stock.append({"item_id": item_id, "name": d.get("name", item_id), "value_cp": int(d.get("value_cp", 0))})
					out["stock"] = stock
				return _found(out)
	return {"found": false, "data": {}}


static func _found(d: Dictionary) -> Dictionary:
	return {"found": true, "data": d}
