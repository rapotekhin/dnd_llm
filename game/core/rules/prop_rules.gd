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
	return not s.props.has(room_id) or (s.props[room_id] as Array).all(func(p: Dictionary) -> bool: return not furnished(p))


## The things still in the room (a taken one is gone).
static func room_props(s: GameSession, room_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p: Dictionary in s.props.get(room_id, []):
		if str(p.get("state", "")) != "taken":
			out.append(p)
	return out


## What the hero dropped in this room and left longer than rules.props.abandon_hours is gone (v0.7.22.8, big test
## #28: someone took it), except in the hero's own place (v0.7.27). Called on entering the room. The names gone.
static func abandon(s: GameSession, data: Dictionary, room_id: String) -> Array[String]:
	var gone: Array[String] = []
	if PropertyRules.owned(s.character, PropertyRules.at(s, data, room_id)):
		return gone
	var limit := int(cfg(data).get("abandon_hours", 24)) * 60
	for p: Dictionary in room_props(s, room_id):
		if bool(p.get("dropped", false)) and not bool(p.get("lost", false)) and TimeRules.abs_minute(s) - int(p.get("dropped_at", TimeRules.abs_minute(s))) >= limit:
			p["state"] = "taken"
			gone.append(str(p["name"]))
	return gone


## The trader's wares (v0.7.22.8, big test #4: the goods of a killed smith were nowhere): a container «Товары: …» in
## the trader's own room whose contents ARE its stock (TradeRules.merchant) — a deal, a theft and a death all show in
## it; taking from it before the trader is a theft. Made and linked anew whenever the room is looked at.
## v0.7.49.4: under the lock of its kind (`lock`); opened or broken, the trader locks it again the next day.
static func ensure_wares(s: GameSession, data: Dictionary, room_id: String) -> void:
	for npc_id: Variant in data["world"]["rooms"].get(room_id, {}).get("npcs", []):
		var n: Dictionary = data["world"]["npcs"].get(str(npc_id), {})
		if not bool(n.get("trader", false)):
			continue
		var pid := "w_" + str(npc_id)
		var list: Array = s.props.get(room_id, [])
		var p := {}
		for x: Dictionary in list:
			if str(x["id"]) == pid:
				p = x
		if p.is_empty():
			p = {"id": pid, "name": "Товары: %s" % n.get("name", npc_id), "description": "То, чем %s торгует, — на полках и под прилавком." % n.get("name", npc_id),
				"item_id": "", "owner": str(npc_id), "text": "", "state": "", "container": "wares", "wares": str(npc_id)}
			list.append(p)
			s.props[room_id] = list
		_lock_wares(s, data, p)
		p["contents"] = TradeRules.merchant(s, data, str(npc_id))["stock"]


static func _lock_wares(s: GameSession, data: Dictionary, p: Dictionary) -> void:
	var c: Dictionary = data["rules"]["containers"]
	var quality := str(c["kinds"]["wares"].get("lock", ""))
	if quality.is_empty():
		return
	if not p.has("lock_dc"):  # a shop of an older save, or a new one
		p["lock_dc"] = int(c["lock_dc"][quality])
		p["locked"] = true
		return
	if bool(p.get("locked", false)):
		p.erase("open_day")
	elif not p.has("open_day"):
		p["open_day"] = s.day
	elif int(p["open_day"]) < s.day:  # the trader's morning: locked again, a broken lock mended
		p["locked"] = true
		p["state"] = ""
		p.erase("open_day")


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
		if p.has("source"):
			out[-1]["source"] = p["source"]
		if ContainerRules.is_container(p):  # v0.7.18.1
			var row: Dictionary = out[-1]
			row["container"] = ContainerRules.kind_name(data, str(p["container"]))
			row["locked"] = bool(p.get("locked", false))
			row["contents"] = ContainerRules.contents_text(data, s.items, p.get("contents", {}))
	return out


## Checks a `furnish` effect: {"plan": {room, props, add}, "summary"} or {"reason"}. A furnished room takes more only
## with a `cause` in the world (v0.7.39.8: a thing brought, built, left) — within the same caps, the room's things
## counted.
static func plan_furnish(s: GameSession, data: Dictionary, e: Dictionary) -> Dictionary:
	var room := s.room_id
	var cause := str(e.get("cause", "")).strip_edges() if e.get("cause") != null else ""
	var add := not needs_furnish(s, room)
	if add and cause.length() < 8:
		return {"reason": "комната уже обставлена — описывай вещи из списка «Вокруг»; добавить вещь можно только с cause — что в мире её принесло (купили, построили, оставили)"}
	var specs: Array = e.get("props", [])
	var cap := int(cfg(data)["max_per_room"])
	var had: Array = room_props(s, room).filter(func(p: Dictionary) -> bool: return furnished(p)) if add else []
	if specs.is_empty() or specs.size() + had.size() > cap:
		return {"reason": "обстановка — от 1 до %d вещей в комнате (уже %d)" % [cap, had.size()]}
	var level := str(int(s.character.get("level", 1)))
	var value_cap := int(cfg(data)["room_value_cap_cp"].get(level, cfg(data)["room_value_cap_cp"]["5"]))
	var item_cap := int(cfg(data)["item_value_cap_cp"])
	var here := s.npcs_here(WorldView.new(data["world"]).world, room)
	var total := 0
	for p: Dictionary in had:
		total += int(ItemRules.def_of(data["items"], s.items, str(p.get("item_id", ""))).get("value_cp", 0)) if not str(p.get("item_id", "")).is_empty() else 0
	var gift := 0  # what nobody owns inside the containers: the master's gift (v0.7.18.1)
	var made := {}
	var props: Array = []
	for spec: Variant in specs:
		if not (spec is Dictionary) or str(spec.get("name", "")).strip_edges().is_empty():
			return {"reason": "у каждой вещи нужно имя"}
		var item := str(spec.get("item_id", "")) if spec.get("item_id") != null else ""
		if spec.get("item") != null and spec["item"] is Dictionary:  # a portable thing the catalog lacks (v0.7.34.4)
			var chk := ItemRules.check_generated(data["items"], spec["item"], int(s.character.get("level", 1)), data.get("spells", {}))
			if not bool(chk["ok"]):
				return {"reason": "%s: %s" % [spec["name"], chk["reason"]]}
			item = ItemRules.generated_id(chk["def"])
			made[item] = chk["def"]
		if not item.is_empty():
			var def: Dictionary = made[item] if made.has(item) else ItemRules.def_of(data["items"], s.items, item)
			if def.is_empty():
				return {"reason": "нет такого предмета %s — найди его через find_items" % item}
			var value := int(def.get("value_cp", 0))
			if value > item_cap:
				return {"reason": "%s слишком дорог для обстановки (%d мм при пределе %d)" % [def.get("name", item), value, item_cap]}
			total += value
		var owner := str(spec.get("owner", "")) if spec.get("owner") != null else ""
		if not owner.is_empty() and not here.has(owner):
			return {"reason": "хозяин %s — не NPC этой комнаты" % owner}
		var prop := {"name": str(spec["name"]).strip_edges().left(60), "description": str(spec.get("description", "")).left(240),
			"item_id": item, "owner": owner, "text": str(spec.get("text", "")).left(800), "state": ""}
		if str(spec.get("source", "")) in ["water", "foul_water"]:  # water is drawn here (v0.7.34.6)
			prop["source"] = str(spec["source"])
		var box := ContainerRules.plan_spec(s, data, spec)
		if box.has("reason"):
			return {"reason": box["reason"]}
		if not box.is_empty():
			for k: String in ["container", "contents", "locked", "lock_dc", "key"]:
				prop[k] = box[k]
			made.merge(box["made"])
			if owner.is_empty():
				gift += int(box["value"])
		props.append(prop)
	if total > value_cap:
		return {"reason": "переносные вещи комнаты стоят %d мм при пределе %d для %s уровня — убери дорогое" % [total, value_cap, level]}
	if gift > EffectEngine.budget_left(s, data):
		return {"reason": "ничейное в контейнерах стоит %d мм — больше, чем мастер может дать до долгого отдыха (%d мм); положи меньше или дай им хозяина" % [gift, EffectEngine.budget_left(s, data)]}
	return {"plan": {"room": room, "props": props, "made": made, "reward": gift, "add": add, "cause": cause},
		"summary": ("Добавлено в комнату (%s): " % cause if add else "Обстановка: ") + ", ".join(props.map(func(p: Dictionary) -> String: return p["name"]))}


## A thing of the room's furnishing, not the hero's dropped one, a seized one or a trader's wares.
static func furnished(p: Dictionary) -> bool:
	return not (bool(p.get("dropped", false)) or p.has("wares") or bool(p.get("seized", false)))


static func apply_furnish(s: GameSession, plan: Dictionary) -> void:
	s.items.merge(plan.get("made", {}))  # things the master made inside the containers (v0.7.18.1)
	var old: Array = s.props.get(str(plan["room"]), [])
	var n := 0
	if bool(plan.get("add", false)):  # v0.7.39.8: more things in a furnished room, numbered on
		for p: Dictionary in old:
			var pid := str(p.get("id", ""))
			if pid.begins_with("p") and pid.substr(1).is_valid_int():
				n = maxi(n, int(pid.substr(1)))
	var list: Array = []
	for p: Dictionary in plan["props"]:
		n += 1
		var prop := p.duplicate()
		prop["id"] = "p%d" % n
		list.append(prop)
	if bool(plan.get("add", false)):
		s.props[str(plan["room"])] = old + list
		return
	list.append_array(old)  # what the hero dropped and a trader's wares stay, after (v0.7.18.2)
	s.props[str(plan["room"])] = list


## Checks a `take_prop`: a portable thing of this room. The plan says whether its owner is here and sees it.
static func plan_take(s: GameSession, data: Dictionary, e: Dictionary) -> Dictionary:
	if EncounterRules.captive(s):
		return {"reason": "герой связан — сначала освободиться"}
	var p := find(s, s.room_id, str(e.get("prop_id", "")))
	if p.is_empty():
		return {"reason": "в комнате нет вещи %s (есть: %s)" % [e.get("prop_id", ""), ", ".join(room_props(s, s.room_id).map(func(x: Dictionary) -> String: return x["id"]))]}
	if str(p.get("item_id", "")).is_empty():
		return {"reason": "%s не унести — это обстановка; опиши попытку словами или `prop_state`" % p["name"]}
	if not (p.get("contents", {}) as Dictionary).is_empty() and not ContainerRules.is_carried_kind(data, str(p["item_id"])):
		return {"reason": "в %s что-то лежит — сначала `take_from` содержимое" % p["name"]}
	if ContainerRules.is_container(p) and not ContainerRules.closed_why(p).is_empty():
		return {"reason": ContainerRules.closed_why(p)}
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
	if EncounterRules.captive(s):
		return {"take": take, "left": left}
	for p: Dictionary in room_props(s, s.room_id):
		if str(p.get("item_id", "")).is_empty() or not str(p.get("owner", "")).is_empty() or not (p.get("contents", {}) as Dictionary).is_empty():
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
	if state == "open" and bool(p.get("locked", false)):  # v0.7.18.1
		return {"reason": "%s заперт — открыть только `unlock` (ключ; или после успешной проверки Ловкости рук / Атлетики)" % p["name"]}
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
	var key := ItemRules.found(s.character, data, s.items, item)
	OwnerRules.mark(s, key, 1, str(p.get("owner", "")))
	OwnerRules.restore(s, p, key, item, 1)
	FoodRules.taken(s, p, item, key, 1)
	if ContainerRules.is_carried_kind(data, item):  # a bag comes with what is in it (v0.7.18.2)
		ContainerRules.pick_up(s, data, item, p.get("contents", {}))
		for id: String in p.get("contents", {}):
			OwnerRules.mark(s, id, int(p["contents"][id]), str(p.get("owner", "")))
			OwnerRules.restore(s, p, id, id, int(p["contents"][id]))
	if not str(plan.get("owner", "")).is_empty():
		lines.append_array(TheftRules.react(s, data, str(plan["owner"])))
	return lines


static func apply_state(s: GameSession, plan: Dictionary) -> void:
	var p := find(s, str(plan["room"]), str(plan["prop"]))
	if not p.is_empty():
		p["state"] = str(plan["state"])
