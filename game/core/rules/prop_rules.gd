class_name PropRules
extends RefCounted
## Things of a room (roadmap v0.7.0, the pillar «всё вокруг интерактивно»): on the first visit the master furnishes
## the room (effect `furnish`: 1–rules.props.max_per_room things), the engine checks them — portable ones are items of
## the catalog within the value cap of the character's level, owners are NPCs of the room — and keeps them for good
## in s.props {room_id: [{id, name, description, item_id, owner, text, state}]}. The master describes only these;
## the player acts on them by words: `move_item:room>hero` (an owner who sees it reacts — TheftRules.react), `prop_state`.


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


## What the engine keeps in a room beside the master's furnishing: the pack's fixed things and a trader's wares.
static func ensure(s: GameSession, data: Dictionary, room_id: String) -> void:
	ensure_fixed(s, data, room_id)
	ensure_wares(s, data, room_id)


## The pack's fixed things of a room (v0.8.4.25.4: a notice board is there before anyone furnishes the room, so its
## orders are readied from the start): `props` of the room, kept as «f_<id>» and never counted as its furnishing.
static func ensure_fixed(s: GameSession, data: Dictionary, room_id: String) -> void:
	var list: Array = s.props.get(room_id, [])
	for spec: Dictionary in data["world"]["rooms"].get(room_id, {}).get("props", []):
		var pid := "f_" + str(spec["id"])
		if list.any(func(x: Dictionary) -> bool: return str(x["id"]) == pid):
			continue
		list.append({"id": pid, "name": str(spec["name"]), "description": str(spec.get("description", "")), "item_id": "",
			"owner": "", "text": str(spec.get("text", "")), "state": "", "fixed": true})
		s.props[room_id] = list


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
		if (p.get("conditions", []) as Array).size() > 0:  # v0.7.65
			out[-1]["state"] = ", ".join((p["conditions"] as Array).map(func(c: Variant) -> String: return str(data["rules"]["condition_effects"][str(c)]["name"])))
		if ContainerRules.is_container(p):  # v0.7.18.1
			var row: Dictionary = out[-1]
			row["container"] = ContainerRules.kind_name(data, str(p["container"]))
			row["locked"] = bool(p.get("locked", false))
			row["contents"] = ContainerRules.contents_text(data, s.items, p.get("contents", {}))
	return out


## Checks a `furnish` effect: {"plan": {room, props, add}, "summary"} or {"reason"}. A furnished room takes more only
## with a `cause` in the world (v0.7.39.8: a thing brought, built, left) — within the same caps, the room's things
## counted. `room` — the room it is for when the master furnishes ahead (v0.8.4.25, set by the engine), else here.
static func plan_furnish(s: GameSession, data: Dictionary, e: Dictionary) -> Dictionary:
	var room := str(e.get("room", s.room_id)) if e.get("room") != null else s.room_id
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
	var here := owners(s, data, room)
	var total := 0
	for p: Dictionary in had:
		total += int(ItemRules.def_of(data["items"], s.items, str(p.get("item_id", ""))).get("value_cp", 0)) if not str(p.get("item_id", "")).is_empty() else 0
	var gift := 0  # what nobody owns inside the containers: the master's gift (v0.7.18.1)
	var made := {}
	var props: Array = []
	var fixed: Array = room_props(s, room).filter(func(p: Dictionary) -> bool: return bool(p.get("fixed", false)))
	for spec: Variant in specs:
		if not (spec is Dictionary) or str(spec.get("name", "")).strip_edges().is_empty():
			return {"reason": "у каждой вещи нужно имя"}
		if fixed.any(func(f: Dictionary) -> bool: return _same(data, f, spec)):
			continue  # the pack's own board is there already: not a second one
		var item := str(spec.get("item_id", "")) if spec.get("item_id") != null else ""
		if spec.get("item") != null and spec["item"] is Dictionary:  # a portable thing the catalog lacks (v0.7.34.4)
			var chk := ItemRules.check_generated(data, spec["item"], int(s.character.get("level", 1)))
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
		if spec.get("source") != null and LiquidRules.kind(data, str(spec["source"])).size() > 0:  # drawn here: water (v0.7.34.6), any liquid (v0.8.4.28.3)
			prop["source"] = str(spec["source"])
		if spec.get("near") != null and not str(spec["near"]).is_empty():  # where on the map: a mark or a person (v0.8.2)
			prop["near"] = str(spec["near"])
		var shape := str(spec.get("body", "")) if spec.get("body") != null else ""
		if not shape.is_empty():  # v0.7.65: what it does on the map
			if not (ThingRules.cfg(data)["bodies"] as Dictionary).has(shape):
				return {"reason": "body — из %s" % ", ".join((ThingRules.cfg(data)["bodies"] as Dictionary).keys())}
			prop["body"] = shape
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
	if props.is_empty():
		return {"reason": "эти вещи в комнате уже есть — обставь её другими"}
	if total > value_cap:
		return {"reason": "переносные вещи комнаты стоят %d мм при пределе %d для %s уровня — убери дорогое" % [total, value_cap, level]}
	if gift > EffectEngine.budget_left(s, data):
		return {"reason": "ничейное в контейнерах стоит %d мм — больше, чем мастер может дать до долгого отдыха (%d мм); положи меньше или дай им хозяина" % [gift, EffectEngine.budget_left(s, data)]}
	return {"plan": {"room": room, "props": props, "made": made, "reward": gift, "add": add, "cause": cause},
		"summary": ("Добавлено в комнату (%s): " % cause if add else "Обстановка: ") + ", ".join(props.map(func(p: Dictionary) -> String: return p["name"]))}


static func _same(data: Dictionary, a: Dictionary, b: Dictionary) -> bool:
	return str(a["name"]).to_lower() == str(b["name"]).strip_edges().to_lower() or (QuestGen.is_board(data, a) and QuestGen.is_board(data, b))


## Who may own the room's things: who is here now and who lives or works here though out at this hour (v0.8.4.25: a room
## furnished ahead or at night still has its innkeeper's chest).
static func owners(s: GameSession, data: Dictionary, room: String) -> Array[String]:
	var out: Array[String] = []
	out.assign(s.npcs_here(data["world"], room))
	for n: Variant in WorldView.new(data["world"]).room(room).get("npcs", []):
		if not out.has(str(n)):
			out.append(str(n))
	var enc := EncounterRules.live(s, data, room)
	if not enc.is_empty():  # the foes of the place own what is in their lair (v0.8.4.30)
		out.append(OwnerRules.FOES + str(enc["id"]))
	return out


## A thing of the room's furnishing, not the hero's dropped one, a seized one or a trader's wares.
static func furnished(p: Dictionary) -> bool:
	return not (bool(p.get("dropped", false)) or p.has("wares") or bool(p.get("seized", false)) or bool(p.get("fixed", false)))


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


## Checks a `move_item:room>hero`: a portable thing of this room. The plan says whether its owner is here and sees it.
static func plan_take(s: GameSession, data: Dictionary, e: Dictionary) -> Dictionary:
	if EncounterRules.captive(s):
		return {"reason": "герой связан — сначала освободиться"}
	var p := find(s, s.room_id, str(e.get("prop_id", "")))
	if p.is_empty():
		return {"reason": "в комнате нет вещи %s (есть: %s)" % [e.get("prop_id", ""), ", ".join(room_props(s, s.room_id).map(func(x: Dictionary) -> String: return x["id"]))]}
	if str(p.get("item_id", "")).is_empty():
		return {"reason": "%s не унести — это обстановка; опиши попытку словами или `prop_state`" % p["name"]}
	if not ContainerRules.load_why(data, p).is_empty():
		return {"reason": ContainerRules.load_why(data, p)}
	if ContainerRules.is_container(p) and not ContainerRules.closed_why(p).is_empty():
		return {"reason": ContainerRules.closed_why(p)}
	var owner := str(p.get("owner", ""))
	var seen := WatchRules.sees_hero(s, data, owner)
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
		if str(p.get("item_id", "")).is_empty() or OwnerRules.claims(str(p.get("owner", ""))) or not (p.get("contents", {}) as Dictionary).is_empty():
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


static func plan_state(s: GameSession, data: Dictionary, e: Dictionary) -> Dictionary:
	var p := find(s, s.room_id, str(e.get("prop_id", "")))
	if p.is_empty():
		return {"reason": "в комнате нет вещи %s" % e.get("prop_id", "")}
	if e.get("damage") != null or e.get("status") != null:  # v0.7.65: the body of the thing, by the engine
		return ThingRules.plan(s, data, p, e)
	var state := str(e.get("state", ""))
	if state in ["broken", "burned"] and ThingRules.guarded(s, data, p):
		return {"reason": "%s нужна заданию: она уцелеет, скажи об этом в истории" % p["name"]}
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
	if p.has("self"):
		Thing.lay(s.character, key, [p["self"]])
		p.erase("self")
	OwnerRules.mark(s, key, 1, str(p.get("owner", "")))
	if ContainerRules.is_carried_kind(data, item):  # a bag comes with what is in it (v0.7.18.2)
		ContainerRules.pick_up(s, data, item, p)
	if not str(plan.get("owner", "")).is_empty():
		lines.append_array(TheftRules.react(s, data, str(plan["owner"])))
	return lines


static func apply_state(s: GameSession, data: Dictionary, plan: Dictionary) -> Array[String]:
	if plan.has("cause"):
		return ThingRules.apply(s, data, plan)
	var p := find(s, str(plan["room"]), str(plan["prop"]))
	if p.is_empty():
		return []
	if str(plan["state"]) in ["broken", "burned"]:
		return ThingRules.ruin(s, data, str(plan["room"]), p, str(plan["state"]))
	p["state"] = str(plan["state"])
	return []
