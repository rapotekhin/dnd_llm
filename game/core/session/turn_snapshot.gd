class_name TurnSnapshot
extends RefCounted
## The turn snapshot for turn.request (ADR-0009 §4): scene, character in final numbers, history within a
## character budget, summaries, limits. Only what the master may see: hooks, never hidden things.


static func build(s: GameSession, data: Dictionary, history_chars: int) -> Dictionary:
	var world := WorldView.new(data["world"])
	var room := SceneRules.room(s, data["world"], s.room_id)  # the variants by the world's flags (v0.7.14.1)
	var loc_id := world.location_id(s.room_id)
	var loc := world.location(loc_id)
	var exits: Array[Dictionary] = []
	for e: String in ExplorationRules.open_exits(s, data["world"], s.room_id):
		exits.append({"room_id": e, "name": world.room(e).get("name", e)})
	var npcs: Array[Dictionary] = []
	for id: String in s.npcs_here(world.world, s.room_id):
		var n := world.npc(id)
		npcs.append({"npc_id": id, "name": n.get("name", id), "role": n.get("role", ""), "race": n.get("race", ""),
			"gender": n.get("gender", "other"), "description": n.get("description", ""),
			"personality": n.get("personality", ""), "attitude": s.attitude(id), "trader": bool(n.get("trader", false)),
			"speaks": ", ".join(LanguageRules.npc(data, n).map(func(l: String) -> String: return LanguageRules.name_of(data, l).to_lower())),
			"understands_hero": LanguageRules.npc_understands(s.character, data, n), "tie": BackgroundRules.tie_text(s.character, data, n),
			"memory": s.memory_of(id, int(data["rules"].get("social", {}).get("memory_in_snapshot", 8))),
			"services": (n.get("services", []) as Array).map(func(x: Variant) -> String: return "%s [%s]" % [SocialRules.tr_service(data, str(x)), x]),
			"deal": SocialRules.deal_text(s, data, id),
			"secrets": SocialRules.secret_hints(s, data, id), "refuses": SocialRules.refuses(s, data, id), "eager": SocialRules.eager(s, data, id),
			"follows": s.followers.has(id)})
	var summaries := {}
	if s.summaries.has("location:" + loc_id):
		summaries["location"] = s.summaries["location:" + loc_id]
	for id: String in s.npcs_here(world.world, s.room_id):
		if s.summaries.has("dialogue:" + id):
			summaries["dialogue:" + id] = s.summaries["dialogue:" + id]
	var out := {
		"scene": {
			"location_name": loc.get("name", loc_id), "location_description": loc.get("description", ""),
			"room_id": s.room_id, "room_name": room.get("name", s.room_id), "room_description": room.get("description", ""),
			"exits": exits, "npcs": npcs, "hooks": hooks(s, data, room), "flags": s.flags,
			"found": ExplorationRules.found_texts(s, data["world"], s.room_id), "sneaking": s.sneaking,
			"props": PropRules.snapshot(s, data, s.room_id),
			"closed_exits": closed_exits(s, data["world"]),
			"chronicle": s.chronicle_tail(data["world"], 12),
			"reputation": ReputationRules.text(s, data, loc_id),
			"open_edges": WorldGen.open_edges(s, data, s.room_id).map(func(e: Dictionary) -> String:
				return "[%d] %s (%s%s)" % [e["index"], e["text"], ", ".join(e.get("terrain", [])), "; можно новую локацию" if bool(e.get("new_location", false)) else ""]),
			"notes": s.notes.slice(-12).map(func(n: Dictionary) -> String: return "день %d, %s — %s" % [int(n["day"]), world.room(str(n["room"])).get("name", n["room"]), n["text"]]),
			"furnish": PropRules.needs_furnish(s, s.room_id) and not CombatRules.active(s) and s.mode == GameSession.MODE_EXPLORATION,
			"time_of_day": "%s, %s%s" % [TimeRules.part_name(s, data), TimeRules.clock(s), ", темно" if TimeRules.dark(s, data) else ""],
		},
		"world": world_info(s, data),
		"character": character_sheet(s, data),
		"history": s.history(history_chars),
		"summaries": summaries,
		"limits": {"max_checks": int(data["rules"]["turn_limits"]["max_checks"]),
			"max_effects": int(data["rules"]["turn_limits"]["max_effects"])},
	}
	out["quests"] = XpRules.quest_list(s, data["world"])
	out["quests"].append_array(quest_offers(s, data["world"]))
	if CombatRules.active(s):
		out["combat"] = CombatRules.snapshot(s, data)
	if s.mode == GameSession.MODE_TRADE and not s.npc_id.is_empty():
		out["trade"] = TradeRules.info(s, data, s.npc_id)
	var crimes := CrimeRules.snapshot(s, data)
	if not crimes.is_empty():
		out["crimes"] = crimes
	return out


## The room's hooks; a secret sign only a rogue (Thieves' Cant) or a druid (Druidic) reads (v0.7.11).
static func hooks(s: GameSession, data: Dictionary, room: Dictionary) -> Array:
	var out: Array = (room.get("hooks", []) as Array).duplicate()
	for a: String in SceneRules.absent(s, data["world"], s.room_id):  # v0.7.14.2: not here at this hour
		out.append("нет на месте: " + a)
	var langs := LanguageRules.hero(s.character)
	if langs.has("thieves_cant") and not str(room.get("thieves_sign", "")).is_empty():
		out.append("тайный знак (читает только герой): " + str(room["thieves_sign"]))
	if langs.has("druidic") and not str(room.get("druid_sign", "")).is_empty():
		out.append("тайный знак (читает только герой): " + str(room["druid_sign"]))
	return out


## Quests a giver in this room offers and the player has not taken (protocol 0.12.0): the master lets the giver
## speak of them when asked, and the player takes one by the button.
static func quest_offers(s: GameSession, world: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: String in QuestRules.offers_here(s, world):
		var q := QuestRules.quest(world, id)
		var giver := str(q.get("giver", ""))
		var things: Array[String] = []
		for item_id: String in q.get("offer_items", {}):
			things.append("%s [%s]" % [str(world.get("items", {}).get(item_id, {}).get("name", item_id)), item_id])
		var by := str(world.get("npcs", {}).get(giver, {}).get("name", giver))
		if q.has("board"):  # an order on a board (v0.7.21.2)
			by = "%s (заказчик — %s)" % [str(PropRules.find(s, str(q["board"]["room"]), str(q["board"]["prop"])).get("name", "доска")), by]
		out.append({"id": id, "title": str(q["title"]), "description": str(q.get("description", "")), "done": false,
			"step": "", "offered_by": by, "offer_items": things})
	return out


## The world pack and the master settings of this game (ADR-0010 §1, §3).
static func world_info(s: GameSession, data: Dictionary) -> Dictionary:
	var p: Dictionary = data.get("pack", {})
	var st := s.settings if not s.settings.is_empty() else WorldPack.default_settings(p)
	return {"name": str(p.get("name", "")), "lore": str(p.get("lore", "")), "tone": str(p.get("tone", "")),
		"magic": str(p.get("magic", "")), "dm_style": str(st.get("dm_style", "classic")),
		"violence": str(st.get("violence", "medium")), "lines": st.get("lines", []), "veils": st.get("veils", []), "wishes": st.get("wishes", [])}


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
			equipped.append("%s: %s [%s]" % [slot, ItemRules.display_name(items, s.items, id), id])
	var sub: Dictionary = data["classes"]["subclasses"].get(str(c.get("subclass", "")), {})
	var class_text := str(c.get("class_name", ""))
	if not sub.is_empty():
		class_text += " (%s)" % sub["name"]
	var sheet := {
		"name": c.get("name", ""), "gender": c.get("gender", "other"), "race": c.get("race_name", ""),
		"class_name": class_text, "level": int(c.get("level", 1)), "hp": int(c.get("hp", 0)),
		"max_hp": int(c.get("max_hp", 0)), "ac": int(c.get("ac", 10)), "conditions": _conditions(c, data),
		"skills": c.get("skills", {}), "gold_cp": int(c.get("gold_cp", 0)),
		"reward_left_cp": EffectEngine.budget_left(s, data),
		"bags": ContainerRules.bags_text(c, data, s.items),
		"development": DevelopmentRules.text(c, data),
		"goal": GoalRules.text_of(c, data),  # v0.7.22: the hero's thoughts
		"inventory": inventory, "features": CharacterRules.feature_names(c, data),
		"background": str(data["backgrounds"].get(str(c.get("background", "")), {}).get("name", "")),
		"background_feature": BackgroundRules.master_text(c, data),
		"attuned": ItemRules.attuned(c).map(func(id: Variant) -> String: return ItemRules.display_name(items, s.items, str(id))),
		"languages": LanguageRules.hero(c).map(func(l: String) -> String: return LanguageRules.name_of(data, l)),
		"tools": (c.get("tools", []) as Array).map(func(t: Variant) -> String:
			return "%s [%s]%s" % [BackgroundRules.tool_name(data, str(t)), t, "" if int(c.get("inventory", {}).get(str(t), 0)) > 0 else " (нет с собой)"]),
		"abilities": c.get("abilities", {}),
		"skill_proficiencies": c.get("skill_profs", []), "speed": int(c.get("speed", 30)), "equipped": equipped,
		"backstory": str(c.get("story", "")),
		"resources": FeatureUses.lines(c, data).map(func(r: Dictionary) -> Dictionary:
			return {"name": r["name"], "left": r["left"], "max": r["max"]}),
		"concentration": str(data["spells"].get(str(c.get("concentration", "")), {}).get("name", "")),
		"effects": ConditionRules.shown(s, data).map(func(e: Dictionary) -> String:
			return "%s — %s%s" % [e["name"], e["left"], (", " + str(e["source"])) if not str(e["source"]).is_empty() else ""]),
		"exhaustion": ConditionRules.exhaustion(c),
		"resistances": HeroDefense.resistances(s, data).keys().map(func(t: Variant) -> String: return str(data["misc"]["damage_types"].get(str(t), t))),
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


## Ways out of this room the pack keeps shut now (v0.7.4): their `text` («лаз под корнями ещё надо найти»), never
## where they lead — the master describes them as closed instead of inventing what lies behind.
static func closed_exits(s: GameSession, world: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var closed: Dictionary = world["rooms"].get(s.room_id, {}).get("closed_exits", {})
	var open := ExplorationRules.open_exits(s, world, s.room_id)
	for to: String in closed:
		if not open.has(to):
			out.append(str(closed[to].get("text", "закрытый путь")))
	return out


## The hero's conditions for the master, invisibility from a held spell included (v0.7.5).
static func _conditions(c: Dictionary, data: Dictionary) -> Array:
	var out: Array = (c.get("conditions", []) as Array).duplicate()
	if ConditionRules.invisible(c, data) and not out.has("invisible"):
		out.append("invisible")
	return out
