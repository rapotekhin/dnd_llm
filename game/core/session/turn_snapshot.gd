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
			"personality": n.get("personality", ""), "attitude": s.attitude(id), "trader": bool(n.get("trader", false))})
	var summaries := {}
	if s.summaries.has("location:" + loc_id):
		summaries["location"] = s.summaries["location:" + loc_id]
	for id: String in world.npcs_in(s.room_id):
		if s.summaries.has("dialogue:" + id):
			summaries["dialogue:" + id] = s.summaries["dialogue:" + id]
	var out := {
		"scene": {
			"location_id": loc_id, "location_name": loc.get("name", loc_id), "location_description": loc.get("description", ""),
			"room_id": s.room_id, "room_name": room.get("name", s.room_id), "room_description": room.get("description", ""),
			"exits": exits, "npcs": npcs, "hooks": room.get("hooks", []), "flags": s.flags,
			"found": ExplorationRules.found_texts(s, data["world"], s.room_id),
		},
		"world": world_info(s, data),
		"character": character_sheet(s, data),
		"history": s.history(history_chars),
		"summaries": summaries,
		"limits": {"max_checks": int(data["rules"]["turn_limits"]["max_checks"]),
			"max_effects": int(data["rules"]["turn_limits"]["max_effects"])},
	}
	out["quests"] = XpRules.quest_list(s, data["world"])
	if s.mode == GameSession.MODE_TRADE and not s.npc_id.is_empty():
		out["trade"] = TradeRules.info(s, data, s.npc_id)
	return out


## The world pack and the master settings of this game (ADR-0010 §1, §3).
static func world_info(s: GameSession, data: Dictionary) -> Dictionary:
	var p: Dictionary = data.get("pack", {})
	var st := s.settings if not s.settings.is_empty() else WorldPack.default_settings(p)
	return {"name": str(p.get("name", "")), "lore": str(p.get("lore", "")), "tone": str(p.get("tone", "")),
		"magic": str(p.get("magic", "")), "dm_style": str(st.get("dm_style", "classic")),
		"violence": str(st.get("violence", "medium")), "lines": st.get("lines", []), "veils": st.get("veils", [])}


## The sheet in final numbers (ADR-0009 §4): the master never computes bonuses. Features and spells go by name;
## their text is behind engine.lookup (kind feature / spell).
static func character_sheet(s: GameSession, data: Dictionary) -> Dictionary:
	var c := s.character
	var items: Dictionary = data["items"]
	var inventory: Array[Dictionary] = []
	for id: String in c.get("inventory", {}):
		inventory.append({"item_id": id, "name": ItemRules.display_name(items, s.items, id), "qty": int(c["inventory"][id])})
	var equipped: Array[String] = []
	for slot: String in CharacterRules.SLOTS:
		var id := str(c.get("equipped", {}).get(slot, ""))
		if not id.is_empty():
			equipped.append(ItemRules.display_name(items, s.items, id))
	var sub: Dictionary = data["classes"]["subclasses"].get(str(c.get("subclass", "")), {})
	var class_text := str(c.get("class_name", ""))
	if not sub.is_empty():
		class_text += " (%s)" % sub["name"]
	var sheet := {
		"name": c.get("name", ""), "gender": c.get("gender", "other"), "race": c.get("race_name", ""),
		"class_name": class_text, "level": int(c.get("level", 1)), "hp": int(c.get("hp", 0)),
		"max_hp": int(c.get("max_hp", 0)), "ac": int(c.get("ac", 10)), "conditions": c.get("conditions", []),
		"skills": c.get("skills", {}), "saves": c.get("saves", {}), "gold_cp": int(c.get("gold_cp", 0)),
		"inventory": inventory, "features": CharacterRules.feature_names(c, data),
		"background": str(data["backgrounds"].get(str(c.get("background", "")), {}).get("name", "")),
		"abilities": c.get("abilities", {}), "proficiency_bonus": int(c.get("prof_bonus", 2)),
		"skill_proficiencies": c.get("skill_profs", []), "speed": int(c.get("speed", 30)), "equipped": equipped,
		"backstory": str(c.get("story", "")),
		"resources": FeatureUses.lines(c, data).map(func(r: Dictionary) -> Dictionary:
			return {"name": r["name"], "left": r["left"], "max": r["max"]}),
		"hit_dice_left": ExplorationRules.hit_dice_left(c),
		"concentration": str(data["spells"].get(str(c.get("concentration", "")), {}).get("name", "")),
	}
	if not str(c.get("spell_ability", "")).is_empty():
		var prepared := CharacterRules.spell_names(c, data, "prepared")
		for n: String in CharacterRules.spell_names(c, data, "always"):
			if not prepared.has(n):
				prepared.append(n)
		var slots: Array[Dictionary] = []
		var used: Array = c.get("slots_used", [])
		var maxes: Array = c.get("slots_max", [])
		for i in maxes.size():
			if int(maxes[i]) > 0:
				slots.append({"level": i + 1, "left": int(maxes[i]) - int(used[i] if i < used.size() else 0), "max": int(maxes[i])})
		sheet["cantrips"] = CharacterRules.spell_names(c, data, "cantrips")
		sheet["spells"] = prepared
		sheet["spell_slots"] = slots
		sheet["spell_save_dc"] = int(c.get("spell_dc", 0))
	return sheet
