class_name ContainerRules
extends RefCounted
## Containers (roadmap v0.7.18.1, the author's request): a thing that holds other things — a concept of the engine,
## not a list. A kind (rules.containers: a catalog item — chest, barrel, basket, sack, backpack, pouch, bag of
## holding — or furniture — a cabinet, a crate) gives the capacity by 5e and whether it locks. A thing of a room
## (s.props) with `container` keeps `contents` {item_id: qty}, `owner`, `locked`, `lock_dc` and `key` (an item that
## opens it). The master fills it when it furnishes the room (what nobody owns — out of the reward budget at once);
## the hero takes and puts by the window or by words (`move_item:container>hero`, `move_item:hero>container`); taking from someone else's container
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


## How many more of `item_id` go into the container `p` (v0.8.4.27): its kind's `holds` groups — what goes in and how
## many of the group — and its capacity in pounds (`p.capacity_lb` of a beast's pack or a cart first).
static func room_for(data: Dictionary, session_items: Dictionary, p: Dictionary, item_id: String) -> int:
	var k := kind(data, str(p.get("container", "")))
	var contents: Dictionary = p.get("contents", {})
	var d := ItemRules.def_of(data["items"], session_items, item_id)
	var n := 1 << 30
	if k.has("holds"):
		var group := _group(data, session_items, k, item_id)
		if group.is_empty():
			return 0
		n = int(group["n"])
		for id: String in contents:
			if _group(data, session_items, k, id) == group:
				n -= int(contents[id])
	var cap := float(p.get("capacity_lb", k.get("capacity_lb", 0)))
	var each := float(d.get("weight", 0))
	if each > 0:
		n = mini(n, int(floor((cap - weight(data, session_items, contents)) / each + 0.0001)))
	return maxi(0, n)


## The group of a kind's `holds` that takes `item_id` ({} — none): by its id, or by a key of its `use` (a scroll).
static func _group(data: Dictionary, session_items: Dictionary, k: Dictionary, item_id: String) -> Dictionary:
	var real := ItemRules.real_id(item_id)
	var use: Dictionary = ItemRules.def_of(data["items"], session_items, item_id).get("use", {})
	for g: Dictionary in k.get("holds", []):
		if (g.get("ids", []) as Array).has(real) or (g.has("use") and bool(use.get(str(g["use"]), false))):
			return g
	return {}


## Why the hero cannot lift the container `p` with what is in it ("" — can): a chest or a barrel with things goes only on
## a beast or a cart (size `load`, v0.8.4.27); another kind that is not a bag is emptied first.
static func load_why(data: Dictionary, p: Dictionary) -> String:
	if (p.get("contents", {}) as Dictionary).is_empty():
		return ""
	var item := str(p.get("item_id", ""))
	if is_carried_kind(data, item) and str(kind(data, item).get("size", "big")) != "load":
		return ""
	if is_carried_kind(data, item):
		return "%s с вещами поднимет только вьючный зверь или телега — сначала переложите вещи" % p["name"]
	return "в %s что-то лежит — сначала `move_item:container>hero` содержимое" % p["name"]


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
			var chk := ItemRules.check_generated(data, c["item"], int(s.character.get("level", 1)))
			if not bool(chk["ok"]):
				return {"reason": "вещь в %s: %s" % [kind_name(data, k), chk["reason"]]}
			id = ItemRules.generated_id(chk["def"])
			made[id] = chk["def"]
		elif ItemRules.def_of(data["items"], s.items, id).is_empty():
			return {"reason": "в %s: нет такого предмета %s — найди его через find_items или создай `item`" % [kind_name(data, k), id]}
		contents[id] = int(contents.get(id, 0)) + qty
	var all_items := s.items.duplicate()
	all_items.merge(made)
	var box := {"container": k, "contents": {}}
	for id: String in contents:
		if room_for(data, all_items, box, id) < int(contents[id]):
			return {"reason": "в %s столько %s не влезет: ёмкость %s фнт%s" % [kind_name(data, k), id, kd["capacity_lb"], _holds_text(data, kd)]}
		box["contents"][id] = contents[id]
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
## v0.7.42: «pack:<id>» / «cart:<id>» — the pack or the vehicle of the hero's beast here (MountRules), with its
## `capacity_lb`.
static func target(s: GameSession, data: Dictionary, id: String) -> Dictionary:
	var mount := MountRules.container(s, data, id)
	if not mount.is_empty():
		return mount
	var body := CreatureRules.box(s, data, id)
	if not body.is_empty():
		return body
	var bag: Dictionary = bags(s.character).get(id, {})
	if not bag.is_empty():
		bag["name"] = bag_name(data, s.character, id)
		bag["container"] = bag["kind"]
		return bag
	PropRules.ensure(s, data, s.room_id)  # the pack's fixed things, the trader's wares (v0.7.22.8)
	var p := PropRules.find(s, s.room_id, id)
	return p if not p.is_empty() and is_container(p) else {}


## Checks taking `qty` of `item_id` out of the container `prop_id` (of the room or a bag): {plan, summary} or {reason}.
static func plan_take(s: GameSession, data: Dictionary, prop_id: String, item_id: String, qty: int) -> Dictionary:
	if EncounterRules.captive(s):
		return {"reason": "герой связан — сначала освободиться"}
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
	var seen := WatchRules.sees_hero(s, data, owner)
	return {"plan": {"room": s.room_id, "from": prop_id, "item_id": item_id, "qty": qty, "owner": owner if seen else ""},
		"summary": "Взято из %s: %s%s%s" % [p["name"], ItemRules.display_name(data["items"], s.items, item_id), " ×%d" % qty if qty > 1 else "",
			" — на глазах у хозяина" if seen else ""]}


static func apply_take(s: GameSession, data: Dictionary, plan: Dictionary) -> Array[String]:
	var p := target(s, data, str(plan["from"])) if str(plan["room"]) == s.room_id else PropRules.find(s, str(plan["room"]), str(plan["from"]))
	var lines: Array[String] = []
	if p.is_empty():
		return lines
	var id := str(plan["item_id"])
	var had := Thing.take(p, id, int(plan["qty"]))
	var key := ItemRules.found(s.character, data, s.items, id, int(plan["qty"]))
	Thing.lay(s.character, key, had)
	OwnerRules.mark(s, key, int(plan["qty"]), str(p.get("owner", "")))
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
	if bags(s.character).has(prop_id) and is_carried_kind(data, item_id):
		return {"reason": "сумку в сумку не кладут"}  # v0.7.22.9
	if room_for(data, s.items, p, item_id) < qty:
		var k := kind(data, str(p["container"]))
		return {"reason": "в %s не влезет: ёмкость %s фнт%s" % [p["name"], p.get("capacity_lb", k.get("capacity_lb", 0)), _holds_text(data, k)]}
	return {"plan": {"room": s.room_id, "into": prop_id, "item_id": item_id, "qty": qty},
		"summary": "Положено в %s: %s%s" % [p["name"], ItemRules.display_name(data["items"], s.items, item_id), " ×%d" % qty if qty > 1 else ""]}


## «; вмещает: Стрелы ×20» — what a kind with `holds` takes, for a refusal.
static func _holds_text(data: Dictionary, k: Dictionary) -> String:
	var bits: Array[String] = []
	for g: Dictionary in k.get("holds", []):
		var names: Array[String] = []
		for id: Variant in g.get("ids", []):
			names.append(str(data["items"]["catalog"].get(str(id), {}).get("name", id)))
		if g.has("use"):
			names.append("свитки")
		bits.append("%s ×%d" % [", ".join(names), int(g["n"])])
	return "" if bits.is_empty() else "; вмещает: " + "; ".join(bits)


static func apply_put(s: GameSession, data: Dictionary, plan: Dictionary) -> void:
	var p := target(s, data, str(plan["into"]))
	if p.is_empty():
		return
	var id := str(plan["item_id"])
	FoodRules.sync(s, data)
	Thing.move(s.character, p, id, int(plan["qty"]))
	OwnerRules.returned(p, id)
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
	var dcs := ThingRules.lock_dcs(data, int(p.get("lock_dc", 10)), ThingRules.body(data, p))
	match how:
		"pick":
			return {"skill": "sleight_of_hand", "dc": int(dcs["pick"]), "tool": "thieves_tools"}
		"force":
			return {"skill": "athletics", "dc": int(dcs["force"])}
	return {}


## Opens the lock (a key, or a check that passed): forced — the thing is broken. Lines.
static func unlock(p: Dictionary, how: String) -> Array[String]:
	p["locked"] = false
	if how == "force":
		p["state"] = "broken"
		return ["%s взломан силой — замок сломан" % p["name"]]
	return ["%s отперт" % p["name"]]


# --- the hero's own lock (v0.8.4.27) -----------------------------------------------------------------------------


## The lock the hero carries to hang ("" — none): an item of `own_locks`.
static func own_lock(s: GameSession, data: Dictionary) -> String:
	for id: String in cfg(data)["own_locks"]:
		if Thing.count(s.character, id) > 0:
			return id
	return ""


## The lock_dc of the hero's own lock `item`.
static func own_lock_dc(data: Dictionary, item: String) -> int:
	return int(cfg(data)["lock_dc"][str(cfg(data)["own_locks"][item])])


## A key made for what the hero's lock shuts: a copy of `key_item` named by it, given to the hero. Its id.
static func new_key(s: GameSession, data: Dictionary, what: String) -> String:
	var base := str(cfg(data)["key_item"])
	var n := 1
	while s.items.has("%s_own%d" % [base, n]):
		n += 1
	var id := "%s_own%d" % [base, n]
	var d := ItemRules.def_of(data["items"], s.items, base).duplicate(true)
	d["name"] = "%s: %s" % [d["name"], what]
	s.items[id] = d
	Gear.give(s, data, Being.HERO, id, 1)
	return id


## The acts of the hero's lock on a container of the room: "hang" — its lock on a lockable one, open, nobody's or the
## hero's, without a whole lock of its own; "relock" — shut again by the key the hero holds.
static func lock_ways(s: GameSession, data: Dictionary, p: Dictionary) -> Array[String]:
	var out: Array[String] = []
	if bool(p.get("locked", false)) or not bool(kind(data, str(p.get("container", ""))).get("lockable", false)) or bags(s.character).has(str(p.get("id", ""))):
		return out
	var whole := not str(p.get("key", "")).is_empty() and str(p.get("state", "")) != "broken"
	if whole and Thing.count(s.character, str(p["key"])) > 0:
		out.append("relock")
	elif not whole and not own_lock(s, data).is_empty() and str(p.get("owner", "")) in ["", OwnerRules.HERO]:
		out.append("hang")
	return out


## Hangs the hero's lock on `p` (the lock spent, its key made, the chest the hero's) or shuts it again by the key. Lines.
static func lock_up(s: GameSession, data: Dictionary, p: Dictionary, how: String) -> Array[String]:
	p["locked"] = true
	if how != "hang":
		return ["%s заперт" % p["name"]]
	var item := own_lock(s, data)
	Gear.take(s, data, Being.HERO, item, 1)
	p["lock_dc"] = own_lock_dc(data, item)
	p["key"] = new_key(s, data, str(p["name"]))
	p["state"] = ""
	if str(p.get("owner", "")).is_empty():
		p["owner"] = OwnerRules.HERO
	return ["На %s повешен ваш замок (Сл %d), ключ у вас" % [p["name"], int(p["lock_dc"])]]


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
	for id: String in all.keys():  # the bags gone first: a freed place takes a new bag (v0.7.22.9)
		if not all.has(id):
			continue
		var gone_kind := str(all[id]["kind"])
		var extra := bags_of(c, gone_kind).size() - int(c.get("inventory", {}).get(gone_kind, 0))
		if extra <= 0:
			continue
		var order := bags_of(c, gone_kind)
		order.sort_custom(func(a: String, b: String) -> bool: return (all[a]["contents"] as Dictionary).size() < (all[b]["contents"] as Dictionary).size())
		for k in extra:
			all.erase(order[k])
	for item_id: String in c.get("inventory", {}):
		if not is_carried_kind(data, item_id):
			continue
		var have := bags_of(c, item_id)
		for i in int(c["inventory"][item_id]) - have.size():
			if not _bag_room(c, data, item_id):
				break  # one big bag and two small ones at a time (v0.7.22.9): the rest are plain things
			var n := 1
			while all.has("bag%d" % n):
				n += 1
			all["bag%d" % n] = {"kind": item_id, "contents": {}}


## Whether the hero can carry one more bag of this kind (rules.containers.worn_bags by its size).
static func _bag_room(c: Dictionary, data: Dictionary, item_id: String) -> bool:
	var size := str(kind(data, item_id).get("size", "big"))
	var limit := int(cfg(data).get("worn_bags", {}).get(size, 0))  # a chest or a barrel (`load`) is never a bag
	var n := 0
	for id: String in bags(c):
		if str(kind(data, str(bags(c)[id]["kind"])).get("size", "big")) == size:
			n += 1
	return n < limit


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
	return w * float(cfg(data).get("bag_weight_share", 1.0))  # a bag makes it easier to carry (v0.7.22.9)


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
	if qty <= 0 or droppable(s, data, what) < qty:
		return {"reason": "у героя нет свободных %s ×%d" % [what, qty]}
	return {"plan": {"room": s.room_id, "item_id": what, "qty": qty},
		"summary": "Оставлено здесь: %s%s" % [ItemRules.display_name(data["items"], s.items, what), " ×%d" % qty if qty > 1 else ""]}


## How many of `item_id` the hero can drop (big test #10, v0.7.22.2): a held weapon or a worn trinket goes down
## too (5e: dropping is free), worn armour and a shield are taken off first (minutes), a full bag goes as a bag,
## a cursed thing does not leave the hero.
static func droppable(s: GameSession, data: Dictionary, item_id: String) -> int:
	var c := s.character
	if ItemRules.held_by_curse(c, data, s.items, item_id):
		return 0
	var worn := 0
	for slot: String in ["armor", "shield"]:
		if str(c.get("equipped", {}).get(slot, "")) == item_id:
			worn += 1
	return maxi(0, int(c.get("inventory", {}).get(item_id, 0)) - worn - full_bags(c, item_id))


static func apply_drop(s: GameSession, data: Dictionary, plan: Dictionary) -> void:
	var c := s.character
	var item_id := str(plan["item_id"])
	var bag := {}
	var qty := int(plan.get("qty", 1))
	if plan.has("bag"):
		bag = bags(c)[plan["bag"]]
		bags(c).erase(plan["bag"])
		qty = 1
	FoodRules.sync(s, data)
	var had := Thing.take(c, item_id, qty)
	var inv: Dictionary = c["inventory"]
	if not inv.has(item_id):
		(c.get("attuned", []) as Array).erase(item_id)
	var held := 0  # the hands let go of what is no longer carried
	for slot: String in CharacterRules.SLOTS:
		if str(c.get("equipped", {}).get(slot, "")) == item_id:
			held += 1
			if held > int(inv.get(item_id, 0)):
				c["equipped"][slot] = ""
	sync_bags(c, data)
	for i in qty:
		var prop := lay_down(s, data, str(plan["room"]), item_id, had[i] if i < had.size() else {})
		if not (bag.get("contents", {}) as Dictionary).is_empty() or is_carried_kind(data, item_id):
			prop["container"] = item_id
			prop["contents"] = (bag.get("contents", {}) as Dictionary).duplicate()
			if bag.has("copies"):
				prop["copies"] = bag["copies"]
			bag = {}
	CharacterRules.refresh(c, data, s.items)


## One thing lies on the floor of `room` now, with what sets it apart (`self`, beside what lies in it).
static func lay_down(s: GameSession, data: Dictionary, room: String, item_id: String, state: Dictionary) -> Dictionary:
	var list: Array = s.props.get(room, [])
	var n := 1
	while list.any(func(p: Dictionary) -> bool: return str(p["id"]) == "d%d" % n):
		n += 1
	var prop := {"id": "d%d" % n, "name": ItemRules.display_name(data["items"], s.items, item_id), "description": "", "item_id": item_id,
		"owner": "", "text": "", "state": "", "dropped": true, "dropped_at": TimeRules.abs_minute(s)}
	if not state.is_empty():
		prop["self"] = state
	list.append(prop)
	s.props[room] = list
	return prop


## A bag picked up with what is in it (PropRules.apply_take).
static func pick_up(s: GameSession, data: Dictionary, item_id: String, p: Dictionary) -> void:
	sync_bags(s.character, data)
	var contents: Dictionary = p.get("contents", {})
	if contents.is_empty():
		return
	var to := s.character  # no room for one more bag (v0.7.22.9): what was in it goes loose
	for id: String in bags_of(s.character, item_id):
		if (bags(s.character)[id]["contents"] as Dictionary).is_empty():
			to = bags(s.character)[id]
			break
	for id: String in contents.keys():
		var n := int(contents[id])
		Thing.move(p, to, id, n)
		Thing.stamp(to, id, n, "owner", str(p.get("owner", ""))) if not str(p.get("owner", "")).is_empty() else null
