class_name WorldItemRules
extends RefCounted
## The master moves a thing of the world with a cause (v0.7.39.8, the author: «правка созданного места — одна дорога»):
## effect `world_item` {op: give | take, npc_id | prop_id, item_id or item, qty, cause} — into or out of a person's
## pockets (TheftRules.pockets) or a container of the hero's room (ContainerRules). The hero's own things and bags are
## the engine's alone; a thing given that nobody owns (a container without an owner) is the master's gift within the
## reward budget; a new thing is checked as any made item (ItemRules.check_generated), its value up to
## rules.props.item_value_cap_cp.


static func plan(s: GameSession, data: Dictionary, e: Dictionary) -> Dictionary:
	var op := str(e.get("op", ""))
	if not op in ["give", "take"]:
		return {"reason": "op — give (положить) или take (забрать)"}
	var cause := str(e.get("cause", "")).strip_edges() if e.get("cause") != null else ""
	if cause.length() < 8:
		return {"reason": "нужна cause — что в мире так поменяло вещи (купил, отдал, украли, принесли)"}
	var qty := clampi(int(e.get("qty", 1)), 1, 20)
	var npc := str(e.get("npc_id", "")) if e.get("npc_id") != null else ""
	var prop := str(e.get("prop_id", "")) if e.get("prop_id") != null else ""
	if npc.is_empty() == prop.is_empty():
		return {"reason": "одно из двух: npc_id (у человека) или prop_id (контейнер комнаты)"}
	var item := str(e.get("item_id", "")) if e.get("item_id") != null else ""
	var made := {}
	if op == "give" and item.is_empty() and e.get("item") is Dictionary:
		var chk := ItemRules.check_generated(data["items"], e["item"], int(s.character.get("level", 1)), data.get("spells", {}))
		if not bool(chk["ok"]):
			return {"reason": str(chk["reason"])}
		item = ItemRules.generated_id(chk["def"])
		made[item] = chk["def"]
	var def: Dictionary = made[item] if made.has(item) else ItemRules.def_of(data["items"], s.items, item)
	if def.is_empty():
		return {"reason": "вещи %s нет — item_id из каталога (find_items) или item — новая вещь" % item}
	var value := int(def.get("value_cp", 0))
	if op == "give" and value > int(PropRules.cfg(data)["item_value_cap_cp"]):
		return {"reason": "%s слишком дорога — до %s за вещь" % [def.get("name", item), Money.format(int(PropRules.cfg(data)["item_value_cap_cp"]))]}
	var name := str(def.get("name", item))
	var p := {"op": op, "item_id": item, "qty": qty, "cause": cause, "made": made}
	if not npc.is_empty():
		var n := WorldView.new(data["world"]).npc(npc)
		if n.is_empty() or s.dead_npcs.has(npc):
			return {"reason": "человека %s нет в живых или в мире" % npc}
		p["npc"] = npc
		if op == "take":
			var have := 0
			for k: Dictionary in TheftRules.pockets(s, data, npc):
				if str(k.get("item_id", "")) == item:
					have += int(k.get("qty", 1))
			if have < qty:
				return {"reason": "у %s нет %s ×%d" % [n.get("name", npc), name, qty]}
		return {"plan": p, "summary": "%s %s: %s%s (%s)" % [n.get("name", npc), "получает" if op == "give" else "лишается", name,
			" ×%d" % qty if qty > 1 else "", cause]}
	var box := PropRules.find(s, s.room_id, prop)
	if box.is_empty() or not ContainerRules.is_container(box):
		return {"reason": "в комнате нет контейнера %s" % prop}
	if bool(box.get("mine", false)):
		return {"reason": "%s — вещь героя: в неё кладёт и берёт только он сам" % box["name"]}
	p["room"] = s.room_id
	p["prop"] = prop
	if op == "take":
		if int((box.get("contents", {}) as Dictionary).get(item, 0)) < qty:
			return {"reason": "в %s нет %s ×%d; там: %s" % [box["name"], name, qty, ContainerRules.contents_text(data, s.items, box.get("contents", {}))]}
	else:
		var add := float(def.get("weight", 0)) * qty
		if ContainerRules.weight(data, s.items, box.get("contents", {})) + add > float(ContainerRules.kind(data, str(box["container"])).get("capacity_lb", 0)):
			return {"reason": "в %s не влезет" % box["name"]}
		if str(box.get("owner", "")).is_empty():  # nobody's: the master's gift (v0.7.14.3)
			if value * qty > EffectEngine.budget_left(s, data):
				return {"reason": "ничейное стоит %d мм — больше, чем мастер может дать до долгого отдыха (%d мм); дай хозяина или меньше" % [value * qty, EffectEngine.budget_left(s, data)]}
			p["reward"] = value * qty
	return {"plan": p, "summary": "%s %s: %s%s (%s)" % [box["name"], "— положено" if op == "give" else "— убрано", name, " ×%d" % qty if qty > 1 else "", cause]}


static func apply(s: GameSession, data: Dictionary, p: Dictionary) -> Array[String]:
	s.items.merge(p.get("made", {}))
	var item := str(p["item_id"])
	var qty := int(p["qty"])
	if p.has("npc"):
		var list: Array = TheftRules.pockets(s, data, str(p["npc"]))
		if str(p["op"]) == "give":
			var e := {"name": ItemRules.display_name(data["items"], s.items, item), "item_id": item, "cp": 0, "qty": qty, "worn": false}
			e["id"] = "w%d" % (list.size() + 1)
			e["dc"] = TheftRules.dc(s, data, str(p["npc"]), e)
			list.append(e)
		else:
			var left := qty
			for k: Dictionary in list.duplicate():
				if left > 0 and str(k.get("item_id", "")) == item:
					var n := mini(left, int(k.get("qty", 1)))
					left -= n
					k["qty"] = int(k.get("qty", 1)) - n
					if int(k["qty"]) <= 0:
						list.erase(k)
		s.remember(str(p["npc"]), str(p["cause"]))
		return []
	var box := PropRules.find(s, str(p["room"]), str(p["prop"]))
	if box.is_empty():
		return []
	if not box.has("contents"):
		box["contents"] = {}
	var contents: Dictionary = box["contents"]
	contents[item] = int(contents.get(item, 0)) + (qty if str(p["op"]) == "give" else -qty)
	if int(contents[item]) <= 0:
		contents.erase(item)
	return []
