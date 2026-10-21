class_name PropRules
extends RefCounted
## Things of a room (roadmap v0.7.0, the pillar «всё вокруг интерактивно»): on the first visit the master furnishes
## the room (effect `furnish`: 1–rules.props.max_per_room things), the engine checks them — portable ones are items of
## the catalog within the value cap of the character's level, owners are NPCs of the room — and keeps them for good
## in s.props {room_id: [{id, name, description, item_id, owner, text, state}]}. The master describes only these;
## the player acts on them by words: `take_prop` (an owner who sees it reacts — TheftRules.react), `prop_state`.


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"]["props"]


static func needs_furnish(s: GameSession, room_id: String) -> bool:
	return not s.props.has(room_id)


## The things still in the room (a taken one is gone).
static func room_props(s: GameSession, room_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p: Dictionary in s.props.get(room_id, []):
		if str(p.get("state", "")) != "taken":
			out.append(p)
	return out


static func find(s: GameSession, room_id: String, prop_id: String) -> Dictionary:
	for p: Dictionary in room_props(s, room_id):
		if str(p["id"]) == prop_id:
			return p
	return {}


## The snapshot list for the master (protocol SceneProp).
static func snapshot(s: GameSession, data: Dictionary, room_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p: Dictionary in room_props(s, room_id):
		out.append({"prop_id": p["id"], "name": p["name"], "description": p.get("description", ""), "state": p.get("state", ""),
			"owner": p.get("owner") if not str(p.get("owner", "")).is_empty() else null, "portable": not str(p.get("item_id", "")).is_empty(),
			"text": p.get("text", "")})
	return out


## Checks a `furnish` effect: {"plan": {room, props}, "summary"} or {"reason"}.
static func plan_furnish(s: GameSession, data: Dictionary, e: Dictionary) -> Dictionary:
	var room := s.room_id
	if not needs_furnish(s, room):
		return {"reason": "комната уже обставлена — описывай вещи из списка «Вокруг»"}
	var specs: Array = e.get("props", [])
	var cap := int(cfg(data)["max_per_room"])
	if specs.is_empty() or specs.size() > cap:
		return {"reason": "обстановка — от 1 до %d вещей" % cap}
	var level := str(int(s.character.get("level", 1)))
	var value_cap := int(cfg(data)["room_value_cap_cp"].get(level, cfg(data)["room_value_cap_cp"]["5"]))
	var item_cap := int(cfg(data)["item_value_cap_cp"])
	var here := s.npcs_here(WorldView.new(data["world"]).world, room)
	var total := 0
	var props: Array = []
	for spec: Variant in specs:
		if not (spec is Dictionary) or str(spec.get("name", "")).strip_edges().is_empty():
			return {"reason": "у каждой вещи нужно имя"}
		var item := str(spec.get("item_id", "")) if spec.get("item_id") != null else ""
		if not item.is_empty():
			var def := ItemRules.def_of(data["items"], s.items, item)
			if def.is_empty():
				return {"reason": "нет такого предмета %s — найди его через find_items" % item}
			var value := int(def.get("value_cp", 0))
			if value > item_cap:
				return {"reason": "%s слишком дорог для обстановки (%d мм при пределе %d)" % [def.get("name", item), value, item_cap]}
			total += value
		var owner := str(spec.get("owner", "")) if spec.get("owner") != null else ""
		if not owner.is_empty() and not here.has(owner):
			return {"reason": "хозяин %s — не NPC этой комнаты" % owner}
		props.append({"name": str(spec["name"]).strip_edges().left(60), "description": str(spec.get("description", "")).left(240),
			"item_id": item, "owner": owner, "text": str(spec.get("text", "")).left(800), "state": ""})
	if total > value_cap:
		return {"reason": "переносные вещи комнаты стоят %d мм при пределе %d для %s уровня — убери дорогое" % [total, value_cap, level]}
	return {"plan": {"room": room, "props": props}, "summary": "Обстановка: " + ", ".join(props.map(func(p: Dictionary) -> String: return p["name"]))}


static func apply_furnish(s: GameSession, plan: Dictionary) -> void:
	var list: Array = []
	var n := 0
	for p: Dictionary in plan["props"]:
		n += 1
		var prop := p.duplicate()
		prop["id"] = "p%d" % n
		list.append(prop)
	s.props[str(plan["room"])] = list


## Checks a `take_prop`: a portable thing of this room. The plan says whether its owner is here and sees it.
static func plan_take(s: GameSession, data: Dictionary, e: Dictionary) -> Dictionary:
	var p := find(s, s.room_id, str(e.get("prop_id", "")))
	if p.is_empty():
		return {"reason": "в комнате нет вещи %s (есть: %s)" % [e.get("prop_id", ""), ", ".join(room_props(s, s.room_id).map(func(x: Dictionary) -> String: return x["id"]))]}
	if str(p.get("item_id", "")).is_empty():
		return {"reason": "%s не унести — это обстановка; опиши попытку словами или `prop_state`" % p["name"]}
	var owner := str(p.get("owner", ""))
	var seen := not owner.is_empty() and s.npcs_here(WorldView.new(data["world"]).world, s.room_id).has(owner)
	return {"plan": {"room": s.room_id, "prop": p["id"], "owner": owner if seen else ""},
		"summary": "Взято: %s%s" % [p["name"], (" — на глазах у хозяина" if seen else "")]}


## «Забрать всё» (просьба автора, after v0.7.8): the portable things of the room nobody owns, in order, as long as the
## hero can carry them (CharacterRules.capacity). {"take": [prop], "left": [prop too heavy]}.
static func take_all_plan(s: GameSession, data: Dictionary) -> Dictionary:
	var c := s.character
	var weight := CharacterRules.carried_weight(c, data, s.items)
	var cap := float(CharacterRules.capacity(c, data))
	var take: Array[Dictionary] = []
	var left: Array[Dictionary] = []
	for p: Dictionary in room_props(s, s.room_id):
		if str(p.get("item_id", "")).is_empty() or not str(p.get("owner", "")).is_empty():
			continue
		var w := float(ItemRules.def_of(data["items"], s.items, str(p["item_id"])).get("weight", 0))
		if weight + w > cap:
			left.append(p)
			continue
		weight += w
		take.append(p)
	return {"take": take, "left": left}


## Takes what take_all_plan allows. Returns the names taken.
static func take_all(s: GameSession, data: Dictionary) -> Array[String]:
	var names: Array[String] = []
	for p: Dictionary in take_all_plan(s, data)["take"]:
		apply_take(s, data, {"room": s.room_id, "prop": p["id"], "owner": ""})
		names.append(str(p["name"]))
	return names


static func plan_state(s: GameSession, e: Dictionary) -> Dictionary:
	var p := find(s, s.room_id, str(e.get("prop_id", "")))
	if p.is_empty():
		return {"reason": "в комнате нет вещи %s" % e.get("prop_id", "")}
	var state := str(e.get("state", ""))
	if not state in ["open", "closed", "broken", "burned", "moved"]:
		return {"reason": "состояние — open, closed, broken, burned или moved"}
	if str(p.get("state", "")) in ["broken", "burned"] and state in ["open", "closed", "moved"]:
		return {"reason": "%s уже испорчена" % p["name"]}
	return {"plan": {"room": s.room_id, "prop": p["id"], "state": state}, "summary": "%s: %s" % [p["name"], TranslationServer.translate("PROP_STATE_" + state.to_upper())]}


## Applies a take: the item goes to the pack, the thing is gone; an owner who saw it reacts. Lines.
static func apply_take(s: GameSession, data: Dictionary, plan: Dictionary) -> Array[String]:
	var p := find(s, str(plan["room"]), str(plan["prop"]))
	var lines: Array[String] = []
	if p.is_empty():
		return lines
	p["state"] = "taken"
	var item := str(p["item_id"])
	ItemRules.found(s.character, data, s.items, item)
	if not str(plan.get("owner", "")).is_empty():
		lines.append_array(TheftRules.react(s, data, str(plan["owner"])))
	return lines


static func apply_state(s: GameSession, plan: Dictionary) -> void:
	var p := find(s, str(plan["room"]), str(plan["prop"]))
	if not p.is_empty():
		p["state"] = str(plan["state"])
