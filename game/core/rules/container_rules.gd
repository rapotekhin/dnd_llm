class_name ContainerRules
extends RefCounted
## Containers (roadmap v0.7.18.1, the author's request): a thing that holds other things — a concept of the engine,
## not a list. A kind (rules.containers: a catalog item — chest, barrel, basket, sack, backpack, pouch, bag of
## holding — or furniture — a cabinet, a crate) gives the capacity by 5e and whether it locks. A thing of a room
## (s.props) with `container` keeps `contents` {item_id: qty}, `owner`, `locked`, `lock_dc` and `key` (an item that
## opens it). The master fills it when it furnishes the room (what nobody owns — out of the reward budget at once);
## the hero takes and puts by the window or by words (`take_from`, `put_in`); taking from someone else's container
## before its owner is a theft (TheftRules.react). Locked — a key, thieves' tools (Sleight of Hand) or force
## (Athletics, it breaks) against `lock_dc`.
## Carried (v0.7.18.2): a container item in the hero's pack is a bag — c["bags"] {bag_id: {kind, contents}}, one per
## such item; what lies in it weighs on the hero (a bag of holding — not), is not at hand (take it out to use or wear
## it), is dropped and picked up with it, and goes with it to whoever gets it.


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"]["containers"]


## The kind of a container: {name, capacity_lb, lockable?, weightless?}; {} — not a container.
static func kind(data: Dictionary, id: String) -> Dictionary:
	return cfg(data)["kinds"].get(id, {})


static func kind_name(data: Dictionary, id: String) -> String:
	var k := kind(data, id)
	if k.has("name"):
		return str(k["name"])
	return str(data["items"]["catalog"].get(id, {}).get("name", id))


static func is_container(p: Dictionary) -> bool:
	return not str(p.get("container", "")).is_empty()


static func weight(data: Dictionary, session_items: Dictionary, contents: Dictionary) -> float:
	var w := 0.0
	for id: String in contents:
		w += float(ItemRules.def_of(data["items"], session_items, id).get("weight", 0)) * int(contents[id])
	return w


static func value(data: Dictionary, session_items: Dictionary, contents: Dictionary) -> int:
	var v := 0
	for id: String in contents:
		v += int(ItemRules.def_of(data["items"], session_items, id).get("value_cp", 0)) * int(contents[id])
	return v


## The contents for the master and the window: «Кинжал ×2, Свеча».
static func contents_text(data: Dictionary, session_items: Dictionary, contents: Dictionary) -> String:
	var parts: Array[String] = []
	for id: String in contents:
		parts.append("%s%s [%s]" % [ItemRules.display_name(data["items"], session_items, id), " ×%d" % int(contents[id]) if int(contents[id]) > 1 else "", id])
	return ", ".join(parts)


# --- furnishing (PropRules.plan_furnish) -------------------------------------------------------------------------


## Checks the container part of a furnish spec: {container, contents, locked, lock_dc, key, value} or {reason}.
## `level` and `spells` let the master make new things inside (a generated `item`).
static func plan_spec(s: GameSession, data: Dictionary, spec: Dictionary) -> Dictionary:
	var k := str(spec.get("container", "")) if spec.get("container") != null else ""
	if k.is_empty():
		return {}
	var kd := kind(data, k)
	if kd.is_empty():
		return {"reason": "неизвестный вид контейнера %s; есть: %s" % [k, ", ".join((cfg(data)["kinds"] as Dictionary).keys())]}
	var contents := {}
	var made := {}
	for c: Variant in spec.get("contents", []):
		if not (c is Dictionary):
			continue
		var qty := clampi(int(c.get("qty", 1)) if c.get("qty") != null else 1, 1, 99)
		var id := str(c.get("item_id", "")) if c.get("item_id") != null else ""
		if c.get("item") != null and c["item"] is Dictionary:
			var chk := ItemRules.check_generated(data["items"], c["item"], int(s.character.get("level", 1)), data.get("spells", {}))
			if not bool(chk["ok"]):
				return {"reason": "вещь в %s: %s" % [kind_name(data, k), chk["reason"]]}
			id = ItemRules.generated_id(chk["def"])
			made[id] = chk["def"]
		elif ItemRules.def_of(data["items"], s.items, id).is_empty():
			return {"reason": "в %s: нет такого предмета %s — найди его через find_items или создай `item`" % [kind_name(data, k), id]}
		contents[id] = int(contents.get(id, 0)) + qty
	var all_items := s.items.duplicate()
	all_items.merge(made)
	if weight(data, all_items, contents) > float(kd["capacity_lb"]):
		return {"reason": "в %s столько не влезет: ёмкость %s фнт" % [kind_name(data, k), kd["capacity_lb"]]}
	var lock := str(spec.get("lock", "")) if spec.get("lock") != null else ""
	if not lock.is_empty() and (not bool(kd.get("lockable", false)) or not (cfg(data)["lock_dc"] as Dictionary).has(lock)):
		return {"reason": "%s не запирается или замок не из %s" % [kind_name(data, k), ", ".join((cfg(data)["lock_dc"] as Dictionary).keys())]}
	var key := str(spec.get("key", "")) if spec.get("key") != null else ""
	return {"container": k, "contents": contents, "made": made, "locked": not lock.is_empty(),
		"lock_dc": int(cfg(data)["lock_dc"].get(lock, 0)), "key": key, "value": value(data, all_items, contents)}


# --- taking and putting ------------------------------------------------------------------------------------------


## Why the hero cannot reach inside now ("" — can).
static func closed_why(p: Dictionary) -> String:
	if bool(p.get("locked", false)):
		return "%s заперт: ключ, воровские инструменты (Ловкость рук) или сила (Атлетика)" % p["name"]
	return ""


## A container by id: a thing of this room or a bag of the hero ({} — none). Bags carry their name and kind.
static func target(s: GameSession, data: Dictionary, id: String) -> Dictionary:
	var bag: Dictionary = bags(s.character).get(id, {})
	if not bag.is_empty():
		bag["name"] = bag_name(data, s.character, id)
		bag["container"] = bag["kind"]
		return bag
	var p := PropRules.find(s, s.room_id, id)
	return p if not p.is_empty() and is_container(p) else {}


## Checks taking `qty` of `item_id` out of the container `prop_id` (of the room or a bag): {plan, summary} or {reason}.
static func plan_take(s: GameSession, data: Dictionary, prop_id: String, item_id: String, qty: int) -> Dictionary:
	var p := target(s, data, prop_id)
	if p.is_empty():
		return {"reason": "нет контейнера %s (в комнате или сумка героя)" % prop_id}
	var why := closed_why(p)
	if not why.is_empty():
		return {"reason": why}
	var have := int((p.get("contents", {}) as Dictionary).get(item_id, 0))
	if have < qty or qty <= 0:
		return {"reason": "в %s нет %s ×%d; там: %s" % [p["name"], item_id, qty, contents_text(data, s.items, p.get("contents", {}))]}
	var owner := str(p.get("owner", ""))
	var seen := not owner.is_empty() and s.npcs_here(WorldView.new(data["world"]).world, s.room_id).has(owner)
	return {"plan": {"room": s.room_id, "from": prop_id, "item_id": item_id, "qty": qty, "owner": owner if seen else ""},
		"summary": "Взято из %s: %s%s%s" % [p["name"], ItemRules.display_name(data["items"], s.items, item_id), " ×%d" % qty if qty > 1 else "",
			" — на глазах у хозяина" if seen else ""]}


static func apply_take(s: GameSession, data: Dictionary, plan: Dictionary) -> Array[String]:
	var p := target(s, data, str(plan["from"])) if str(plan["room"]) == s.room_id else PropRules.find(s, str(plan["room"]), str(plan["from"]))
	var lines: Array[String] = []
	if p.is_empty():
		return lines
	var contents: Dictionary = p["contents"]
	var id := str(plan["item_id"])
	contents[id] = int(contents.get(id, 0)) - int(plan["qty"])
	if int(contents[id]) <= 0:
		contents.erase(id)
	ItemRules.found(s.character, data, s.items, id, int(plan["qty"]))
	CharacterRules.refresh(s.character, data, s.items)
	if not str(plan.get("owner", "")).is_empty():
		lines.append_array(TheftRules.react(s, data, str(plan["owner"])))
	return lines


## Checks putting `qty` of the hero's `item_id` into the container: {plan, summary} or {reason}.
static func plan_put(s: GameSession, data: Dictionary, prop_id: String, item_id: String, qty: int) -> Dictionary:
	var p := target(s, data, prop_id)
	if p.is_empty():
		return {"reason": "нет контейнера %s (в комнате или сумка героя)" % prop_id}
	var why := closed_why(p)
	if not why.is_empty():
		return {"reason": why}
	if qty <= 0 or TradeRules.sellable(s, item_id, data) < qty:
		return {"reason": "у героя нет свободных %s ×%d (надетое сначала снимают, полную сумку — опустошают)" % [item_id, qty]}
	if bags(s.character).has(prop_id) and str(p["kind"]) == item_id and int(s.character["inventory"].get(item_id, 0)) - qty < bags_of(s.character, item_id).size():
		return {"reason": "сумку в саму себя не положить"}
	var add := float(ItemRules.def_of(data["items"], s.items, item_id).get("weight", 0)) * qty
	var cap := float(kind(data, str(p["container"]))["capacity_lb"])
	if weight(data, s.items, p.get("contents", {})) + add > cap:
		return {"reason": "в %s не влезет: ёмкость %s фнт" % [p["name"], cap]}
	return {"plan": {"room": s.room_id, "into": prop_id, "item_id": item_id, "qty": qty},
		"summary": "Положено в %s: %s%s" % [p["name"], ItemRules.display_name(data["items"], s.items, item_id), " ×%d" % qty if qty > 1 else ""]}


static func apply_put(s: GameSession, data: Dictionary, plan: Dictionary) -> void:
	var p := target(s, data, str(plan["into"]))
	if p.is_empty():
		return
	var inv: Dictionary = s.character["inventory"]
	var id := str(plan["item_id"])
	inv[id] = int(inv.get(id, 0)) - int(plan["qty"])
	if int(inv[id]) <= 0:
		inv.erase(id)
	if not p.has("contents"):
		p["contents"] = {}
	p["contents"][id] = int(p["contents"].get(id, 0)) + int(plan["qty"])
	CharacterRules.refresh(s.character, data, s.items)


# --- locks -------------------------------------------------------------------------------------------------------


## The ways to open a locked container now: "key" (the hero carries it), "pick" (thieves' tools), "force".
static func ways(s: GameSession, data: Dictionary, p: Dictionary) -> Array[String]:
	var out: Array[String] = []
	if not bool(p.get("locked", false)):
		return out
	var key := str(p.get("key", ""))
	if not key.is_empty() and int(s.character.get("inventory", {}).get(key, 0)) > 0:
		out.append("key")
	if int(s.character.get("inventory", {}).get("thieves_tools", 0)) > 0:
		out.append("pick")
	out.append("force")
	return out


## The check of a way: {skill, dc, tool} ({} for the key).
static func lock_check(data: Dictionary, p: Dictionary, how: String) -> Dictionary:
	match how:
		"pick":
			return {"skill": "sleight_of_hand", "dc": int(p.get("lock_dc", 10)), "tool": "thieves_tools"}
		"force":
			return {"skill": "athletics", "dc": int(p.get("lock_dc", 10)) + int(cfg(data)["force_dc_plus"])}
	return {}


## Opens the lock (a key, or a check that passed): forced — the thing is broken. Lines.
static func unlock(p: Dictionary, how: String) -> Array[String]:
	p["locked"] = false
	if how == "force":
		p["state"] = "broken"
		return ["%s взломан силой — замок сломан" % p["name"]]
	return ["%s отперт" % p["name"]]


# --- bags of the hero (v0.7.18.2) -------------------------------------------------------------------------------


static func bags(c: Dictionary) -> Dictionary:
	if not c.has("bags"):
		c["bags"] = {}
	return c["bags"]


## The bag ids of a kind.
static func bags_of(c: Dictionary, item_id: String) -> Array[String]:
	var out: Array[String] = []
	for id: String in bags(c):
		if str(bags(c)[id]["kind"]) == item_id:
			out.append(id)
	return out


static func is_carried_kind(data: Dictionary, item_id: String) -> bool:
	return not kind(data, item_id).is_empty() and data["items"]["catalog"].has(item_id)


## One bag for each container item in the pack: new ones empty; when there are fewer items (sold, given, dropped),
## the empty bags go first, then the full ones with what is in them.
static func sync_bags(c: Dictionary, data: Dictionary) -> void:
	var all := bags(c)
	for item_id: String in c.get("inventory", {}):
		if not is_carried_kind(data, item_id):
			continue
		var have := bags_of(c, item_id)
		for i in int(c["inventory"][item_id]) - have.size():
			var n := 1
			while all.has("bag%d" % n):
				n += 1
			all["bag%d" % n] = {"kind": item_id, "contents": {}}
	for id: String in all.keys():
		var item_id := str(all[id]["kind"])
		var extra := bags_of(c, item_id).size() - int(c.get("inventory", {}).get(item_id, 0))
		if extra <= 0:
			continue
		var order := bags_of(c, item_id)
		order.sort_custom(func(a: String, b: String) -> bool: return (all[a]["contents"] as Dictionary).size() < (all[b]["contents"] as Dictionary).size())
		for k in extra:
			all.erase(order[k])


## How many of a kind are full bags (they cannot be sold or put away until emptied).
static func full_bags(c: Dictionary, item_id: String) -> int:
	return bags_of(c, item_id).filter(func(id: String) -> bool: return not (bags(c)[id]["contents"] as Dictionary).is_empty()).size()


static func bag_name(data: Dictionary, c: Dictionary, bag_id: String) -> String:
	var item_id := str(bags(c)[bag_id]["kind"])
	var same := bags_of(c, item_id)
	var name := str(data["items"]["catalog"].get(item_id, {}).get("name", item_id))
	return name if same.size() <= 1 else "%s %d" % [name, same.find(bag_id) + 1]


## The weight of what the bags hold (a bag of holding weighs nothing inside).
static func bags_weight(c: Dictionary, data: Dictionary, session_items: Dictionary) -> float:
	var w := 0.0
	for id: String in bags(c):
		if not bool(kind(data, str(bags(c)[id]["kind"])).get("weightless", false)):
			w += weight(data, session_items, bags(c)[id]["contents"])
	return w


## For the master: «Рюкзак [bag1]: Верёвка [rope], Факел ×3 [torch]».
static func bags_text(c: Dictionary, data: Dictionary, session_items: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for id: String in bags(c):
		out.append("%s [%s]: %s" % [bag_name(data, c, id), id, contents_text(data, session_items, bags(c)[id]["contents"]) if not (bags(c)[id]["contents"] as Dictionary).is_empty() else "пусто"])
	return out


## A thing of the pack left in the room (v0.7.18.2): a bag goes down with what is in it. {plan, summary} or {reason}.
static func plan_drop(s: GameSession, data: Dictionary, what: String, qty: int) -> Dictionary:
	var c := s.character
	if bags(c).has(what):
		var item_id := str(bags(c)[what]["kind"])
		return {"plan": {"room": s.room_id, "item_id": item_id, "bag": what}, "summary": "Оставлено здесь: %s" % bag_name(data, c, what)}
	if qty <= 0 or TradeRules.sellable(s, what, data) < qty:
		return {"reason": "у героя нет свободных %s ×%d" % [what, qty]}
	return {"plan": {"room": s.room_id, "item_id": what, "qty": qty},
		"summary": "Оставлено здесь: %s%s" % [ItemRules.display_name(data["items"], s.items, what), " ×%d" % qty if qty > 1 else ""]}


static func apply_drop(s: GameSession, data: Dictionary, plan: Dictionary) -> void:
	var c := s.character
	var item_id := str(plan["item_id"])
	var contents := {}
	var qty := int(plan.get("qty", 1))
	if plan.has("bag"):
		contents = (bags(c)[plan["bag"]]["contents"] as Dictionary).duplicate()
		bags(c).erase(plan["bag"])
		qty = 1
	var inv: Dictionary = c["inventory"]
	inv[item_id] = int(inv.get(item_id, 0)) - qty
	if int(inv[item_id]) <= 0:
		inv.erase(item_id)
	sync_bags(c, data)
	var list: Array = s.props.get(str(plan["room"]), [])
	for i in qty:
		var n := 1
		while list.any(func(p: Dictionary) -> bool: return str(p["id"]) == "d%d" % n):
			n += 1
		var prop := {"id": "d%d" % n, "name": ItemRules.display_name(data["items"], s.items, item_id), "description": "", "item_id": item_id,
			"owner": "", "text": "", "state": "", "dropped": true}
		if not contents.is_empty() or is_carried_kind(data, item_id):
			prop["container"] = item_id
			prop["contents"] = contents
			contents = {}
		list.append(prop)
	s.props[str(plan["room"])] = list
	CharacterRules.refresh(c, data, s.items)


## A bag picked up with what is in it (PropRules.apply_take).
static func pick_up(s: GameSession, data: Dictionary, item_id: String, contents: Dictionary) -> void:
	sync_bags(s.character, data)
	if contents.is_empty():
		return
	for id: String in bags_of(s.character, item_id):
		if (bags(s.character)[id]["contents"] as Dictionary).is_empty():
			bags(s.character)[id]["contents"] = contents.duplicate()
			return
