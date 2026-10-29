class_name TeachRules
extends RefCounted
## Teachers (roadmap v0.7.39.7, rules.study.teachers): who in the world may teach what — an engine concept, not a list
## of people. An NPC teaches by its own `teaches` {spells: {classes, max}, tools, skills, languages, recipe_max_cp}
## merged with what its SRD template casts (the spell lists of `templates`, the circle by the template's slots) and what
## its trade kind knows (`trades`). A spell course and a course at a teacher out of the scene need such a teacher
## (StudyRules.make); the master's search `find_teachers` answers who of the living world teaches a thing and where.


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"]["study"]["teachers"]


## What an NPC teaches: {spell_classes, circle (-1 — no spells), tools, skills, languages, recipe_max_cp}.
static func of_npc(data: Dictionary, n: Dictionary) -> Dictionary:
	var t := cfg(data)
	var classes: Array[String] = []
	var circle := -1
	var tmpl := str(n.get("monster", ""))
	if (t["templates"] as Dictionary).has(tmpl):
		_add(classes, t["templates"][tmpl])
		circle = _slots_top(data["monsters"].get(tmpl, {}))
	var tools: Array[String] = []
	var skills: Array[String] = []
	var langs: Array[String] = []
	var trade: Dictionary = t["trades"].get(TradeRules.kind_of(data["rules"], n), {})
	_add(tools, trade.get("tools", []))
	_add(skills, trade.get("skills", []))
	var own_langs := str(trade.get("languages", "")) == "own"
	var max_cp := int(t["recipe_max_cp"])
	var mine: Variant = n.get("teaches")
	if mine is Dictionary:
		var sp: Variant = mine.get("spells")
		if sp is Dictionary:
			_add(classes, sp.get("classes", []))
			circle = maxi(circle, int(sp.get("max", 1)))
		_add(tools, mine.get("tools", []))
		_add(skills, mine.get("skills", []))
		if mine.get("languages") is Array:
			_add(langs, mine["languages"])
		elif str(mine.get("languages", "")) == "own":
			own_langs = true
		max_cp = maxi(max_cp, int(mine.get("recipe_max_cp", 0)))
	if own_langs:
		_add(langs, LanguageRules.npc(data, n))
	return {"spell_classes": classes, "circle": circle if not classes.is_empty() else -1, "tools": tools, "skills": skills,
		"languages": langs, "recipe_max_cp": max_cp}


static func _add(out: Array[String], from: Variant) -> void:
	if not (from is Array):
		return
	for x: Variant in from:
		if not out.has(str(x)):
			out.append(str(x))


## The highest circle of a monster template's slots; 0 — cantrips only, -1 — no spellcasting.
static func _slots_top(m: Dictionary) -> int:
	var sc: Dictionary = m.get("spellcasting", {})
	if sc.is_empty():
		return -1
	var top := 0
	for k: Variant in sc.get("slots", {}):
		if int(sc["slots"][k]) > 0:
			top = maxi(top, int(k))
	return top


## What an NPC teaches, in words: «заклинания волшебника, чародея до 5 круга; ремесло: кузнечные инструменты».
static func text(data: Dictionary, n: Dictionary) -> String:
	var o := of_npc(data, n)
	var parts: Array[String] = []
	if int(o["circle"]) >= 0:
		parts.append("заклинания (%s) до %d круга" % [", ".join(o["spell_classes"]), int(o["circle"])])
	if not (o["tools"] as Array).is_empty():
		parts.append("ремесло и его рецепты: " + ", ".join((o["tools"] as Array).map(func(x: Variant) -> String: return BackgroundRules.tool_name(data, str(x)))))
	if not (o["skills"] as Array).is_empty():
		parts.append("навыки: " + ", ".join((o["skills"] as Array).map(func(x: Variant) -> String: return CraftRules.tr_skill(data, str(x)))))
	if not (o["languages"] as Array).is_empty():
		parts.append("языки: " + ", ".join((o["languages"] as Array).map(func(x: Variant) -> String: return LanguageRules.name_of(data, str(x)))))
	return "; ".join(parts)


## "" when the NPC may teach the thing (a living NPC of the world), else why not — for the master's refusal. For a recipe
## `what` is a recipe or a catalog item; `recipe` — the recipe a course brings of its own (its tool counts).
static func why_not(s: GameSession, data: Dictionary, npc_id: String, kind: String, what: String, recipe: Dictionary = {}) -> String:
	if s != null and s.dead_npcs.has(npc_id):
		return "%s мёртв — учить некому" % npc_id
	var n := BondRules.npc_def(s, data, npc_id)
	if n.is_empty():
		return "NPC %s нет в мире" % npc_id
	return why_not_def(s, data, n, kind, what, recipe)


## why_not by the NPC's definition — also of a person a quest's act is about to bring.
static func why_not_def(s: GameSession, data: Dictionary, n: Dictionary, kind: String, what: String, recipe: Dictionary = {}) -> String:
	var o := of_npc(data, n)
	var who := str(n.get("name", "?"))
	var can := text(data, n)
	var also := (" — учит: " + can) if not can.is_empty() else " — ничему не учит (дай ему teaches при создании или выбери другого учителя)"
	match kind:
		"spell":
			var sp: Dictionary = data["spells"].get(what, {})
			if sp.is_empty():
				return "заклинания %s нет" % what
			if not (sp.get("classes", []) as Array).any(func(cl: Variant) -> bool: return (o["spell_classes"] as Array).has(str(cl))):
				return "%s не учит «%s» (оно из списков %s)%s" % [who, sp.get("name", what), ", ".join(sp.get("classes", [])), also]
			if int(sp.get("level", 9)) > int(o["circle"]):
				return "«%s» — %d круга, а %s учит заклинаниям до %d круга" % [sp.get("name", what), int(sp["level"]), who, int(o["circle"])]
		"tool":
			if not (o["tools"] as Array).has(what):
				return "%s не учит ремеслу %s%s" % [who, BackgroundRules.tool_name(data, what), also]
		"skill":
			if not (o["skills"] as Array).has(what):
				return "%s не учит навыку %s%s" % [who, CraftRules.tr_skill(data, what), also]
		"language":
			if not (o["languages"] as Array).has(what):
				return "%s не учит языку %s%s" % [who, LanguageRules.name_of(data, what), also]
		"recipe":
			var r := recipe if not recipe.is_empty() else CraftRules.recipe(s, data, what)
			if r.is_empty():
				var by_item := CraftRules.for_item(s, data, what)
				r = CraftRules.recipe(s, data, by_item) if not by_item.is_empty() else {}
			var tool := CraftRules.tool_of(r)
			if (o["tools"] as Array).is_empty():
				return "%s не ремесленник%s" % [who, also]
			if not tool.is_empty() and not (o["tools"] as Array).has(tool):
				return "%s не учит ремеслу %s%s" % [who, BackgroundRules.tool_name(data, tool), also]
			var out_id := str(r.get("output", what))
			var cp := int(ItemRules.def_of(data["items"], s.items if s != null else {}, out_id).get("value_cp", 0))
			if cp > int(o["recipe_max_cp"]):
				return "%s дороже %s — такой работе %s не учит" % [ItemRules.display_name(data["items"], s.items if s != null else {}, out_id),
					Money.format(int(o["recipe_max_cp"])), who]
		_:
			return "teach_kind — skill, tool, language, spell или recipe"
	return ""


## Who of the living world teaches the thing (the master's `find_teachers`): [{id, name, teaches, room, place, here,
## course}] — those of the scene first, then of the hero's location, then the rest; at most `find_max`. A teacher whose
## course of it the world already has is in the list by its course.
static func find(s: GameSession, data: Dictionary, kind: String, what: String) -> Array[Dictionary]:
	var w := WorldView.new(data["world"])
	var scene := s.npcs_here(data["world"], s.room_id)
	var loc := w.location_id(s.room_id)
	var by_course := {}
	var all := StudyRules.courses(s, data)
	for cid: String in all:
		var t: Dictionary = all[cid].get("teaches", {})
		if str(t.get("kind", "")) == kind and str(t.get("id", "")) == what and not str(all[cid].get("teacher", "")).is_empty():
			by_course[str(all[cid]["teacher"])] = cid
	var out: Array[Dictionary] = []
	for id: String in data["world"]["npcs"]:
		if s.dead_npcs.has(id) or (not by_course.has(id) and not why_not(s, data, id, kind, what).is_empty()):
			continue
		var n: Dictionary = data["world"]["npcs"][id]
		var room := str(s.npc_at.get(id, ReputationRules.home_room(data, id)))
		var at := w.location_id(room)
		out.append({"id": id, "name": str(n.get("name", id)), "role": str(n.get("role", "")), "teaches": text(data, n),
			"room": room, "place": w.place_path(room) if not room.is_empty() else "", "here": scene.has(id),
			"course": str(by_course.get(id, "")), "_rank": 0 if scene.has(id) else (1 if at == loc and not loc.is_empty() else 2)})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["_rank"]) < int(b["_rank"]) or (int(a["_rank"]) == int(b["_rank"]) and str(a["name"]) < str(b["name"])))
	out = out.slice(0, int(cfg(data)["find_max"]))
	for x: Dictionary in out:
		x.erase("_rank")
	return out


## The engine's id of a thing the master names by an id or a Russian name: a spell, a recipe (its id, an item's id or
## name), a tool, a skill or a language. "" — unknown.
static func resolve(s: GameSession, data: Dictionary, kind: String, what: String) -> String:
	var low := what.strip_edges().to_lower()
	match kind:
		"spell":
			return _by_name(data["spells"], what, low, func(id: String) -> String: return str(data["spells"][id].get("name", id)))
		"tool":
			return _by_name(CraftRules.cfg(data)["tools"], what, low, func(id: String) -> String: return BackgroundRules.tool_name(data, id))
		"skill":
			return _by_name(data["rules"]["skills"], what, low, func(id: String) -> String: return CraftRules.tr_skill(data, id))
		"language":
			return _by_name(data["misc"]["languages"], what, low, func(id: String) -> String: return LanguageRules.name_of(data, id))
		"recipe":
			if not CraftRules.recipe(s, data, what).is_empty() or not ItemRules.def_of(data["items"], s.items, what).is_empty():
				return what
			var all := CraftRules.all(s, data)
			var r := _by_name(all, what, low, func(id: String) -> String: return CraftRules.recipe_name(s, data, id))
			if not r.is_empty():
				return r
			return _by_name(data["items"]["catalog"], what, low, func(id: String) -> String: return str(data["items"]["catalog"][id].get("name", id)))
	return ""


static func _by_name(all: Dictionary, what: String, low: String, name: Callable) -> String:
	if all.has(what):
		return what
	for id: String in all:
		if str(name.call(id)).to_lower() == low:
			return id
	for id: String in all:
		if not low.is_empty() and str(name.call(id)).to_lower().contains(low):
			return id
	return ""


# --- a spell course by the engine ------------------------------------------------------------------------------------


## The lessons of a spell course: at least `spell_lessons_per_circle` × circle (a cantrip — the master's).
static func spell_lessons(data: Dictionary, circle: int, asked: int) -> int:
	return maxi(asked, int(cfg(data)["spell_lessons_per_circle"]) * circle)


## The fee of a spell course: `spell_fee_cp_lesson` × circle a lesson (a cantrip — the master's).
static func spell_fee(data: Dictionary, circle: int, lessons: int, asked: int) -> int:
	return asked if circle <= 0 else int(cfg(data)["spell_fee_cp_lesson"]) * circle * lessons


## The attitude a spell course asks of the teacher (none below `attitude_from_circle`).
static func spell_attitude(data: Dictionary, circle: int) -> int:
	return int(cfg(data)["attitude_min"]) if circle >= int(cfg(data)["attitude_from_circle"]) else -99
