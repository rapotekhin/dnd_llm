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
		exits.append({"room_id": e, "name": world.room(e).get("name", e), "door": DoorRules.describe(s, data, s.room_id, e)})
	var npcs: Array[Dictionary] = []
	for id: String in s.npcs_here(world.world, s.room_id):
		var n := world.npc(id)
		npcs.append({"npc_id": id, "name": n.get("name", id), "role": n.get("role", ""), "race": n.get("race", ""),
			"body": BodyRules.npc_text(data, id, n),
			"gender": n.get("gender", "other"), "description": str(n.get("description", "")) + _sick(s, data, id, n) + _hungry(s, id),
			"personality": n.get("personality", ""), "attitude": s.attitude(id), "trader": bool(n.get("trader", false)),
			"speaks": ", ".join(LanguageRules.npc(data, n).map(func(l: String) -> String: return LanguageRules.name_of(data, l).to_lower())),
			"understands_hero": LanguageRules.npc_understands(s.character, data, n), "tie": BackgroundRules.tie_text(s.character, data, n),
			"memory": s.memory_of(id, int(data["rules"].get("social", {}).get("memory_in_snapshot", 8))),
			"services": (n.get("services", []) as Array).map(func(x: Variant) -> String: return "%s [%s]" % [SocialRules.tr_service(data, str(x)), x]),
			"deal": SocialRules.deal_text(s, data, id),
			"secrets": SocialRules.secret_hints(s, data, id), "refuses": SocialRules.refuses(s, data, id), "eager": SocialRules.eager(s, data, id),
			"follows": s.followers.has(id), "under": SpellEffects.npc_spell_text(s, id), "animals": _animals(data, id)})
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
			"site_name": str(world.site_of(s.room_id).get("name", "")), "site_description": str(world.site_of(s.room_id).get("description", "")),
			"site_owner": "герой (его имущество)" if str(world.site_of(s.room_id).get("owner", "")) == OwnerRules.HERO else str(world.npc(str(world.site_of(s.room_id).get("owner", ""))).get("name", "")), "private": not world.is_public(s.room_id),  # v0.7.22.24
			"exits": exits, "npcs": npcs, "hooks": hooks(s, data, room), "flags": s.flags,
			"found": ExplorationRules.found_texts(s, data["world"], s.room_id), "sneaking": s.sneaking,
			"props": _props(s, data),
			"creatures": CreatureRules.snapshot(s, data, s.room_id) + EncounterRules.snapshot(s, data, s.room_id),  # v0.7.22.11, v0.7.22.12
			"closed_exits": closed_exits(s, data["world"]),
			"summons": AllyRules.summon_lines(s, data),  # v0.7.22.22
			"chronicle": s.chronicle_tail(data["world"], 12),
			"reputation": ReputationRules.text(s, data, loc_id),
			"wilds": WildsRules.lines(s, data),  # v0.7.41
			"open_edges": WorldGen.open_edges(s, data, s.room_id).map(func(e: Dictionary) -> String:
				return "[%d] %s (%s%s)" % [e["index"], e["text"], ", ".join(e.get("terrain", [])), "; можно новую локацию" if bool(e.get("new_location", false)) else ""]),
			"notes": s.notes.slice(-12).map(func(n: Dictionary) -> String: return "день %d, %s — %s" % [int(n["day"]), world.room(str(n["room"])).get("name", n["room"]), n["text"]]),
			"furnish": PropRules.needs_furnish(s, s.room_id) and not CombatRules.active(s) and s.mode == GameSession.MODE_EXPLORATION,
			"time_of_day": "%s%s, %s%s" % [(CalendarRules.text(data["world"], s.day) + " (" + CalendarRules.season_text(data["world"], s.day) + "), ") if CalendarRules.on(data["world"]) else "",
				TimeRules.part_name(s, data), TimeRules.clock(s), ", темно" if TimeRules.dark(s, data) else ""],  # v0.7.44: the date
			"calendar": CalendarRules.snapshot(s, data, data["world"]),  # v0.7.44: festivals on and near
			"weather": WeatherRules.text(s, data),  # v0.7.46
			"rumors": RumorRules.snapshot(s, data),  # v0.7.47
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
		"violence": str(st.get("violence", "medium")), "lines": st.get("lines", []), "veils": st.get("veils", []), "wishes": st.get("wishes", []),
		"adult": bool(st.get("adult", false))}



## The sheet in final numbers (ADR-0009 §4): the master never computes bonuses. Features and spells go by name;
## their text is behind engine.lookup (kind feature / spell).
static func character_sheet(s: GameSession, data: Dictionary) -> Dictionary:
	var c := s.character
	var items: Dictionary = data["items"]
	var inventory: Array[Dictionary] = []
	var foreign := OwnerRules.foreign(s)  # v0.7.22.17: someone else's, taken without asking
	for id: String in c.get("inventory", {}):
		var whose: Array = (foreign.get(id, {}) as Dictionary).keys().map(func(o: String) -> String: return str(WorldView.new(data["world"]).npc(o).get("name", o)))
		var water := VesselRules.summary(c, data, id)  # v0.7.34.6: the master sees an empty skin
		inventory.append({"item_id": id, "name": ItemRules.display_name(items, s.items, id) + (" (%s)" % water if not water.is_empty() else "")
			+ (" (чужое: %s — взято без спроса)" % ", ".join(whose) if not whose.is_empty() else ""),
			"qty": int(c["inventory"][id])})
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
		"name": c.get("name", ""), "gender": c.get("gender", "other"), "race": c.get("race_name", ""), "body": BodyRules.text(data, c.get("body", {}), str(c.get("gender", "other"))),
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
		"craft": CraftRules.snapshot(s, data),  # v0.7.24
		"jobs": JobRules.text(s, data),  # v0.7.26
		"property": ". ".join([PropertyRules.text(s, data), ObjectRules.text(s, data, s.room_id)].filter(func(x: String) -> bool: return not x.is_empty())),  # v0.7.27; the object here (v0.7.39.5)
		"bank": BankRules.text(s, data),  # v0.7.28
		"shop": ShopRules.text(s, data),  # v0.7.29
		"study": StudyRules.text(s, data),  # v0.7.30
		"bonds": BondRules.text(s, data),  # v0.7.31
		"family": FamilyRules.text(s, data),  # v0.7.32
		"underworld": _underworld(s, data),  # v0.7.33
		"office": OfficeRules.text(s, data),  # v0.7.34
		"tools": (c.get("tools", []) as Array).map(func(t: Variant) -> String:
			return "%s [%s]%s" % [BackgroundRules.tool_name(data, str(t)), t, "" if int(c.get("inventory", {}).get(str(t), 0)) > 0 else " (нет с собой)"]),
		"abilities": c.get("abilities", {}),
		"skill_proficiencies": c.get("skill_profs", []), "speed": int(c.get("speed", 30)), "equipped": equipped,
		"backstory": str(c.get("story", "")),
		"resources": FeatureUses.lines(c, data).map(func(r: Dictionary) -> Dictionary:
			return {"name": r["name"], "left": r["left"], "max": r["max"]}),
		"concentration": str(data["spells"].get(str(c.get("concentration", "")), {}).get("name", "")),
		"effects": ConditionRules.shown(s, data).map(func(e: Dictionary) -> String:
			return "%s — %s%s" % [e["name"], e["left"], (", " + str(e["source"])) if not str(e["source"]).is_empty() else ""]) + 			NeedRules.shown(s, data).map(func(n: Dictionary) -> String: return "нужда: " + str(n["line"])),  # v0.7.23
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
## The things of the room for the master, the trader's wares among them (v0.7.22.8).
static func _props(s: GameSession, data: Dictionary) -> Array[Dictionary]:
	PropRules.ensure_wares(s, data, s.room_id)
	return PropRules.snapshot(s, data, s.room_id)


static func _conditions(c: Dictionary, data: Dictionary) -> Array:
	var out: Array = (c.get("conditions", []) as Array).duplicate()
	if ConditionRules.invisible(c, data) and not out.has("invisible"):
		out.append("invisible")
	return out


## A follower the hero has not fed (v0.7.39.1): the master sees its hunger.
static func _hungry(s: GameSession, id: String) -> String:
	var n := int(s.follower_fed.get(id, {}).get("hungry", 0))
	return " Голоден: %d дн. без еды от героя." % n if n > 0 and s.followers.has(id) else ""


## « Болен: хохочущая лихорадка, заразно.» — a sick NPC (v0.7.23.1); its course ends (v0.7.39): « Уже здоров…».

## A dealer's beasts and vehicles for the master (v0.7.42): «Мул [mule] 8 зм».
static func _animals(data: Dictionary, id: String) -> Array:
	var out: Array = []
	if not data["rules"].has("property"):
		return out
	for m: String in PropertyRules.animals_of(data, id):
		out.append("%s [%s] %s" % [data["monsters"][m].get("name", m), m, Money.format(int(PropertyRules.animal_cfg(data, m)["price_cp"]))])
	if MountRules.on(data):
		for v: String in MountRules.vehicles_of(data, id):
			out.append("%s %s" % [MountRules.vehicle(data, v)["name"], Money.format(int(MountRules.vehicle(data, v)["price_cp"]))])
	return out
static func _sick(s: GameSession, data: Dictionary, id: String, n: Dictionary) -> String:
	var d := DiseaseRules.def_of(s, data, DiseaseRules.npc_disease(s, data, id))
	if d.is_empty():
		return " Уже здоров: болезнь прошла, описание выше — о прошлом." if not str(n.get("sick", "")).is_empty() else ""
	return " Болен: %s%s." % [str(d.get("name", "")).to_lower(), ", заразно" if bool(d.get("contagious", false)) else ""]


## The underworld for the master (v0.7.33): known fences and stolen goods, the hero's jobs and organizations.
static func _underworld(s: GameSession, data: Dictionary) -> String:
	if not data["rules"].has("underworld"):
		return ""
	var parts: Array[String] = []
	for p: String in [FenceRules.text(s, data), HeistRules.text(s, data), OrgRules.text(s, data)]:
		if not p.is_empty():
			parts.append(p)
	return ". ".join(parts)
