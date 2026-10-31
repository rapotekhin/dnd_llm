class_name OwnerRules
extends RefCounted
## Ownership (roadmap v0.7.22.17, the author's fixes check #7) — one concept for creatures and things, the groundwork
## for property (v0.7.27). A creature of the room has `owner`: HERO (the hero bound it — a prisoner), an NPC id (sold
## or handed over) or none (free). A thing the hero carries that is someone else's — taken from an owner's container,
## shelf or pockets, seen or not — is in s.foreign {item_id: {owner: qty}}, counted only up to what the hero still
## carries; its owner does not buy it back and the master sees it as stolen. The master moves ownership by words with
## the effect `owner`: a beast sold to an NPC of the scene (the engine caps the price), a creature given away or let
## go, a thing its owner gives up to the hero.

const HERO := "hero"


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"]["creatures"]


# --- things ------------------------------------------------------------------------------------------------------


## The hero took `qty` of `item_id` that belongs to `owner` (an NPC id; "" — nobody's, nothing to mark).
static func mark(s: GameSession, item_id: String, qty: int, owner: String) -> void:
	if owner.is_empty() or owner == HERO or qty <= 0:
		return
	var by: Dictionary = s.foreign.get(item_id, {})
	by[owner] = int(by.get(owner, 0)) + qty
	s.foreign[item_id] = by


static func _carried(s: GameSession, id: String) -> int:
	var n := int(s.character.get("inventory", {}).get(id, 0))
	for b: Dictionary in ContainerRules.bags(s.character).values():
		n += int((b.get("contents", {}) as Dictionary).get(id, 0))
	return n


## An unknown thing the hero identified is the same thing: its marks move to its real id.
static func _identified(s: GameSession) -> void:
	for id: String in s.foreign.keys():
		var real := ItemRules.real_id(id)
		if real != id and _carried(s, id) == 0:
			var by: Dictionary = s.foreign.get(real, {})
			for owner: String in s.foreign[id]:
				by[owner] = int(by.get(owner, 0)) + int(s.foreign[id][owner])
			s.foreign[real] = by
			s.foreign.erase(id)


## A thing left the hero: the marks past what the hero still carries go with it, onto the container or the dropped
## thing `p` (at most `limit`, -1 — all). Back in its owner's container the thing is simply returned.
static func store(s: GameSession, p: Dictionary, item_id: String, limit: int = -1) -> void:
	_identified(s)
	var by: Dictionary = s.foreign.get(item_id, {})
	var extra := -_carried(s, item_id)
	for owner: String in by:
		extra += int(by[owner])
	extra = extra if limit < 0 else mini(extra, limit)
	for owner: String in by.keys():
		var n := mini(extra, int(by[owner]))
		if n <= 0:
			continue
		extra -= n
		by[owner] = int(by[owner]) - n
		if int(by[owner]) <= 0:
			by.erase(owner)
		if owner != str(p.get("owner", "")):
			if not p.has("marks"):
				p["marks"] = {}
			var there: Dictionary = p["marks"].get(item_id, {})
			there[owner] = int(there.get(owner, 0)) + n
			p["marks"][item_id] = there
	if by.is_empty():
		s.foreign.erase(item_id)


## `qty` of `item_id` came back out of `p` as `key`: their marks come back too.
static func restore(s: GameSession, p: Dictionary, key: String, item_id: String, qty: int) -> void:
	var there: Dictionary = p.get("marks", {}).get(item_id, {})
	for owner: String in there.keys():
		var n := mini(qty, int(there[owner]))
		if n <= 0:
			continue
		qty -= n
		mark(s, key, n, owner)
		there[owner] = int(there[owner]) - n
		if int(there[owner]) <= 0:
			there.erase(owner)
	if there.is_empty() and p.has("marks"):
		(p["marks"] as Dictionary).erase(item_id)


## What the hero carries of someone else's: {item_id: {owner: qty}}, no more than the hero still has of each.
static func foreign(s: GameSession) -> Dictionary:
	_identified(s)
	var out := {}
	for id: String in s.foreign:
		var left := _carried(s, id)
		var by := {}
		for owner: String in s.foreign[id]:
			var n := mini(left, int(s.foreign[id][owner]))
			if n > 0:
				by[owner] = n
				left -= n
		if not by.is_empty():
			out[id] = by
	return out


## How many of `item_id` the hero carries that belong to `owner`.
static func held_of(s: GameSession, item_id: String, owner: String) -> int:
	return int(foreign(s).get(item_id, {}).get(owner, 0))


## Drops the marks of what the hero no longer carries (after a deal, a drop, a seizure).
static func tidy(s: GameSession) -> void:
	s.foreign = foreign(s)


# --- creatures ---------------------------------------------------------------------------------------------------


static func thinking(data: Dictionary, c: Dictionary) -> bool:
	var m: Dictionary = data["monsters"].get(str(c.get("monster", "")), {})
	return int(m.get("abilities", {}).get("int", 1)) >= int(CombatRules.cfg(data)["intelligent_int"])


static func xp_of(data: Dictionary, c: Dictionary) -> int:
	return int(data["monsters"].get(str(c.get("monster", "")), {}).get("xp", 0))


## What the law pays for a thinking prisoner (the guard's button, an NPC who takes it to the guard): bounty_cp_per_xp × its XP.
static func bounty_cap(data: Dictionary, c: Dictionary) -> int:
	return int(cfg(data)["bounty_cp_per_xp"]) * maxi(1, xp_of(data, c))


## The most an NPC pays for the creature: sale_cp_per_xp × its XP.
static func price_cap(data: Dictionary, c: Dictionary) -> int:
	return int(cfg(data)["sale_cp_per_xp"]) * maxi(1, xp_of(data, c))


static func owner_word(data: Dictionary, owner: String) -> String:
	if owner == HERO:
		return "ваш пленник"
	return "принадлежит: %s" % WorldView.new(data["world"]).npc(owner).get("name", owner)


# --- the master's `owner` effect ---------------------------------------------------------------------------------


## Checks the master's `owner`: {creature_id | item_id, owner_id, price_cp}. A creature here of the hero's goes to an
## NPC of the scene (a sale with a price — only a beast while slavery is off; a thinking one is handed over for the
## law's bounty at most, v0.7.49.4: the NPC takes it to the guard) or free (owner_id ""); a thing of an
## NPC the hero carries becomes the hero's (owner_id "hero") — its owner gives it up here. {plan, summary} or {reason}.
static func plan(s: GameSession, data: Dictionary, e: Dictionary) -> Dictionary:
	var world := WorldView.new(data["world"])
	var to := str(e.get("owner_id", "")) if e.get("owner_id") != null else ""
	var here := s.npcs_here(world.world, s.room_id)
	var cid := str(e.get("creature_id", "")) if e.get("creature_id") != null else ""
	if not cid.is_empty():
		var c := CreatureRules.find(s, s.room_id, cid)
		if c.is_empty():
			return {"reason": "существа %s нет в этой комнате (список существ сцены)" % cid}
		if str(c.get("owner", "")) != HERO:
			return {"reason": "%s — не пленник героя: сначала его связывают (кнопка игрока)" % c["name"]}
		if not str(c.get("npc_id", "")).is_empty():
			return {"reason": "%s — человек пакета: его не продают и не дарят" % c["name"]}
		if to.is_empty():
			return {"plan": {"creature": cid, "to": "", "price": 0}, "summary": "%s отпущен" % c["name"]}
		if not here.has(to):
			return {"reason": "NPC %s нет в этой комнате: продают и отдают тем, кто здесь" % to}
		var price := maxi(0, int(e.get("price_cp", 0)) if e.get("price_cp") != null else 0)
		var bounty := price > 0 and thinking(data, c) and not PropertyRules.slavery(s, data) and not bool(cfg(data).get("slavery", false))
		var cap := bounty_cap(data, c) if bounty else price_cap(data, c)
		if price > cap:
			return {"reason": ("%s разумен: его не продают (рабства нет), а передают, чтобы свели к страже, — награда за поимку не больше %s" if bounty
				else "за %s дадут не больше %s") % [c["name"], Money.format(cap)]}
		var npc := world.npc(to)
		if price > 0 and bool(npc.get("trader", false)) and price > int(TradeRules.merchant(s, data, to)["purse_cp"]):
			return {"reason": "у %s нет столько денег: в кошельке %s" % [npc.get("name", to), Money.format(int(TradeRules.merchant(s, data, to)["purse_cp"]))]}
		return {"plan": {"creature": cid, "to": to, "price": price},
			"summary": "%s теперь у %s%s" % [c["name"], npc.get("name", to), (" — награда за поимку %s" if bounty else " за %s") % Money.format(price) if price > 0 else ""]}
	var item := str(e.get("item_id", "")) if e.get("item_id") != null else ""
	if item.is_empty():
		return {"reason": "нужен creature_id существа сцены или item_id вещи героя"}
	if to != HERO:
		return {"reason": "вещь меняет хозяина эффектом только в пользу героя (owner_id hero); отдать вещь — take_item"}
	var f: Dictionary = foreign(s).get(item, {})
	var from := ""
	for owner: String in f:
		if here.has(owner):
			from = owner
	if from.is_empty():
		return {"reason": "у героя нет чужой вещи %s, чей хозяин здесь" % item}
	return {"plan": {"item": item, "from": from},
		"summary": "%s отдаёт герою: %s" % [world.npc(from).get("name", from), ItemRules.display_name(data["items"], s.items, item)]}


static func apply(s: GameSession, data: Dictionary, p: Dictionary) -> Array[String]:
	if p.has("item"):
		var by: Dictionary = s.foreign.get(str(p["item"]), {})
		by.erase(str(p["from"]))
		if by.is_empty():
			s.foreign.erase(str(p["item"]))
		return []
	var c := CreatureRules.find(s, s.room_id, str(p["creature"]))
	if c.is_empty():
		return []
	var to := str(p["to"])
	if to.is_empty():
		return CreatureRules.act(s, data, str(c["id"]), "free")
	c["owner"] = to
	c["led"] = false
	var lines: Array[String] = []
	var price := int(p.get("price", 0))
	if price > 0:
		Ledger.add(s, price, "owner:apply")
		if bool(WorldView.new(data["world"]).npc(to).get("trader", false)):
			var m := TradeRules.merchant(s, data, to)
			m["purse_cp"] = int(m["purse_cp"]) - price
		lines.append("+" + Money.format(price))
	var home := ReputationRules.home_room(data, to)
	if not home.is_empty() and home != s.room_id:  # it goes with its new owner
		(s.creatures[s.room_id] as Array).erase(c)
		var dest: Array = s.creatures.get(home, [])
		dest.append(c)
		s.creatures[home] = dest
		lines.append("%s уводят к %s" % [c["name"], WorldView.new(data["world"]).npc(to).get("name", to)])
	return lines
