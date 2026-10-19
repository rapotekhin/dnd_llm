class_name Lookup
extends RefCounted
## engine.lookup (ADR-0009 §3): reference data on a whitelist — rules, conditions, SRD spells and class /
## race features, items, NPCs of the current room. Never other locations or hidden things.
## Ids may be SRD ids or Russian names (the master sees names in the sheet).


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
		"spell":
			var sid := _resolve(data["spells"], id)
			if not sid.is_empty():
				var out: Dictionary = data["spells"][sid].duplicate()
				out["id"] = sid
				out["known"] = _knows_spell(s.character, sid)
				return _found(out)
		"feature":
			for pool: Dictionary in [data["classes"]["features"], data["races"]["traits"]]:
				var fid := _resolve(pool, id)
				if not fid.is_empty():
					var f: Dictionary = pool[fid]
					return _found({"id": fid, "name": f.get("name", fid), "desc": f.get("desc", ""),
						"has": CharacterRules.has_feature(s.character, fid) or CharacterRules.has_trait(s.character, fid)})
		"item":
			var def := ItemRules.def_of(data["items"], s.items, id)
			if not def.is_empty():
				var out := def.duplicate()
				out["id"] = id
				out["owned"] = int(s.character.get("inventory", {}).get(id, 0))
				return _found(out)
		"npc":
			var world := WorldView.new(data["world"])
			if s.npcs_alive(world.npcs_in(s.room_id)).has(id):
				var n := world.npc(id)
				var out := {"id": id, "name": n.get("name", id), "role": n.get("role", ""), "race": n.get("race", ""),
					"description": n.get("description", ""), "personality": n.get("personality", ""),
					"attitude": s.attitude(id), "trader": bool(n.get("trader", false))}
				if bool(n.get("trader", false)):
					var trade := TradeRules.info(s, data, id)
					out["stock"] = trade["stock"]
					out["purse_cp"] = trade["purse_cp"]
				return _found(out)
	return {"found": false, "data": {}}


## An id of `pool` by id or by Russian / English name (case-insensitive); "" if none.
static func _resolve(pool: Dictionary, id: String) -> String:
	if pool.has(id):
		return id
	var key := id.strip_edges().to_lower()
	for k: String in pool:
		var d: Dictionary = pool[k]
		if str(d.get("name", "")).to_lower() == key or str(d.get("name_en", "")).to_lower() == key:
			return k
	return ""


static func _knows_spell(c: Dictionary, id: String) -> bool:
	var sp: Dictionary = c.get("spells", {})
	for list: String in ["cantrips", "known", "prepared", "always"]:
		if (sp.get(list, []) as Array).has(id):
			return true
	return false


static func _found(d: Dictionary) -> Dictionary:
	return {"found": true, "data": d}
