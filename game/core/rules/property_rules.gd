class_name PropertyRules
extends RefCounted
## Property (roadmap v0.7.27): a site on sale (location → site → room) — the pack's `properties`, the master's (effect
## `property`) or built on the hero's land. Bought from its seller it is the hero's de facto: the site's owner is the
## hero (a patch of this game's world, s.generated). The deed at the registry (an NPC tagged `registry`) makes it de
## jure: a weekly tax, no dispute. A place with a worker (or the hero's own shift) brings income into its till, decays
## without care, gains upgrades (a station, a bed, a chest, a counter…) and buildings on land. Animals are creatures
## of the hero (state `tame`), fed each day; while the world allows slavery an owned prisoner may be put to work.
## The author's answers: sale in the pack and by the master, building on land, a clerk with the deed, workers and own
## shifts, tax and decay, upgrades, the window and the map, animals, serfs (a world setting, off by default).
## v0.7.39.5 (the author: «лавка — это объект»): the hero's place is an object (ObjectRules) of a kind — its staff
## places by roles (rules.property.kinds[k].staff, `max` each, more by upgrades with `staff_max`), any number of hands,
## each a person of the object paid each day; a trading kind (`trade`) has a shelf (ShopRules); a market stall is an
## object of the kind `stall` rented at the registry (`rent`), the counter of a house — an object of its own (`counter`).
##
## c["property"] = {id: {deed, since, cond, cash, debt, stock: {item: qty}, upgrades: [..], pending: [{up, ready}],
## building: {id, ready}, kind, staff: [{npc | cid, role, wage, serf}], rent_day, last_day, tax_day, shift_day}}.

const TAME := "tame"


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"]["property"]


## The kinds of places: the engine's (rules.property.kinds) and the world's own — the pack's or the master's
## (world.place_kinds, v0.7.39.8).
static func kinds(data: Dictionary) -> Dictionary:
	return _with_world(cfg(data)["kinds"], data["world"].get("place_kinds", {}))


## The upgrades: the engine's and the world's own (world.place_upgrades — a made kind's, one asked at a place).
static func ups(data: Dictionary) -> Dictionary:
	return _with_world(cfg(data)["upgrades"], data["world"].get("place_upgrades", {}))


static func _with_world(base: Dictionary, own: Dictionary) -> Dictionary:
	if own.is_empty():
		return base
	var out := base.duplicate()
	out.merge(own)
	return out


static func all(s: GameSession, data: Dictionary) -> Dictionary:
	var out: Dictionary = (data["world"].get("properties", {}) as Dictionary).duplicate()
	out.merge(WorldGen.generated(s).get("properties", {}), true)
	return out


static func prop(s: GameSession, data: Dictionary, id: String) -> Dictionary:
	return all(s, data).get(id, {})


static func state(c: Dictionary) -> Dictionary:
	if not (c.get("property") is Dictionary):
		c["property"] = {}
	return c["property"]


static func owned(c: Dictionary, id: String) -> bool:
	return state(c).has(id)


static func kind_id(s: GameSession, data: Dictionary, id: String) -> String:
	var st: Dictionary = state(s.character).get(id, {})
	return str(st.get("kind", prop(s, data, id).get("kind", "house")))


static func kind(s: GameSession, data: Dictionary, id: String) -> Dictionary:
	return kinds(data).get(kind_id(s, data, id), {})


static func name_of(s: GameSession, data: Dictionary, id: String) -> String:
	return str(prop(s, data, id).get("name", id))


static func rooms(s: GameSession, data: Dictionary, id: String) -> Array[String]:
	return WorldView.new(data["world"]).site_rooms(str(prop(s, data, id).get("site", "")))


## The room upgrades go to: the first indoor room of the site (a building on land once built), else its entry.
static func main_room(s: GameSession, data: Dictionary, id: String) -> String:
	var w := WorldView.new(data["world"])
	var list := rooms(s, data, id)
	for r: String in list:
		if bool(w.room(r).get("indoor", false)):
			return r
	var entry := w.site_entry(str(prop(s, data, id).get("site", "")))
	return entry if not entry.is_empty() else (list[0] if not list.is_empty() else "")


## The property whose site holds the room ("" — none).
static func at(s: GameSession, data: Dictionary, room_id: String) -> String:
	var sid := WorldView.new(data["world"]).site_id(room_id)
	if sid.is_empty():
		return ""
	var props := all(s, data)
	for id: String in props:
		if str(props[id].get("site", "")) == sid:
			return id
	return ""


## The hero's property the hero stands in ("" — none).
static func here(s: GameSession, data: Dictionary) -> String:
	var id := at(s, data, s.room_id)
	return id if owned(s.character, id) else ""


## The hero's own place with a bed (an upgrade that gives rest) the room belongs to, "" — none (v0.7.39.5).
static func bed_at(s: GameSession, data: Dictionary, room_id: String) -> String:
	var id := at(s, data, room_id)
	return id if owned(s.character, id) and _gives(s, data, id, "rest", 0.0) > 0.0 else ""


static func price(s: GameSession, data: Dictionary, id: String) -> int:
	return int(prop(s, data, id).get("price_cp", 0))


static func seller(s: GameSession, data: Dictionary, id: String) -> String:
	return str(prop(s, data, id).get("seller", ""))


## On sale by this NPC and not the hero's yet.
static func of_seller(s: GameSession, data: Dictionary, npc_id: String) -> Array[String]:
	var out: Array[String] = []
	var props := all(s, data)
	for id: String in props:
		if str(props[id].get("seller", "")) == npc_id and not owned(s.character, id) and not bool(props[id].get("taken", false)):
			out.append(id)
	return out


static func npc_name(data: Dictionary, npc_id: String) -> String:
	return str(WorldView.new(data["world"]).npc(npc_id).get("name", npc_id))


static func _present(s: GameSession, data: Dictionary, npc_id: String) -> bool:
	return SceneRules.npcs(s, data["world"], s.room_id).has(npc_id)


static func has_upgrade(c: Dictionary, id: String, up: String) -> bool:
	return (state(c).get(id, {}).get("upgrades", []) as Array).has(up)


static func _gives(s: GameSession, data: Dictionary, id: String, key: String, base: float) -> float:
	var v := base
	for up: Variant in state(s.character).get(id, {}).get("upgrades", []):
		var g: Dictionary = ups(data).get(str(up), {}).get("gives", {})
		if g.has(key):
			v = v * float(g[key]) if key.ends_with("_mult") else v + float(g[key])
	return v


## The income of a day with a worker: the kind's (or the place's own) × the upgrades × the condition when worn.
static func income_day(s: GameSession, data: Dictionary, id: String) -> int:
	if data["rules"].has("shop") and ShopRules.active(s, id):  # a shelf of goods earns by sales instead (v0.7.29)
		return 0
	var base := int(prop(s, data, id).get("income_cp_day", kind(s, data, id).get("income_cp_day", 0)))
	if base <= 0:
		return 0
	var st: Dictionary = state(s.character).get(id, {})
	var cond := float(st.get("cond", 100.0))
	var worn := 1.0 if cond >= float(cfg(data)["worn_below"]) else cond / 100.0
	return roundi(base * (1.0 + _gives(s, data, id, "income_pct", 0.0) / 100.0) * worn)


static func deed_fee(s: GameSession, data: Dictionary, id: String) -> int:
	return Price.share(price(s, data, id), float(cfg(data)["registry"]["fee_pct"]), 1)


static func tax(s: GameSession, data: Dictionary, id: String) -> int:
	return Price.share(price(s, data, id), float(cfg(data)["tax"]["pct"]), 1)


## The registry NPC of the scene ("" — none here).
static func registry_here(s: GameSession, data: Dictionary) -> String:
	var tag := str(cfg(data)["registry"]["tag"])
	for npc: String in SceneRules.npcs(s, data["world"], s.room_id):
		if (WorldView.new(data["world"]).npc(npc).get("tags", []) as Array).has(tag):
			return npc
	return ""


static func is_registry(data: Dictionary, npc_id: String) -> bool:
	return (WorldView.new(data["world"]).npc(npc_id).get("tags", []) as Array).has(str(cfg(data)["registry"]["tag"]))


static func slavery(s: GameSession, data: Dictionary) -> bool:
	return bool(s.settings.get("slavery", bool(data.get("pack", {}).get("rules", {}).get("slavery", false))))


# --- the world's patches ------------------------------------------------------------------------------------------


static func _add_tag(s: GameSession, data: Dictionary, room_id: String, tag: String) -> void:
	var tags: Array = (WorldView.new(data["world"]).room(room_id).get("tags", []) as Array).duplicate()
	if not tags.has(tag):
		tags.append(tag)
	Overlay.put(s, data, EntityRef.room(room_id), "tags", tags)


# --- buying and the deed --------------------------------------------------------------------------------------------


## "" when the hero may buy it now, else a localization key.
static func buy_why(s: GameSession, data: Dictionary, id: String) -> String:
	if prop(s, data, id).is_empty():
		return "PROPERTY_UNKNOWN"
	if owned(s.character, id):
		return "PROPERTY_OWNED"
	if not _present(s, data, seller(s, data, id)):
		return "PROPERTY_SELLER_AWAY"
	if SocialRules.refuses(s, data, seller(s, data, id)):
		return "TALK_REFUSED"
	if int(s.character.get("gold_cp", 0)) < price(s, data, id):
		return "PROPERTY_NO_MONEY"
	return ""


static func buy(s: GameSession, data: Dictionary, id: String) -> Array[String]:
	var c := s.character
	var p := prop(s, data, id)
	Ledger.add(s, -price(s, data, id), "property:buy")
	state(c)[id] = _fresh(s, float(p.get("condition", 100)))
	Overlay.put(s, data, EntityRef.site(str(p["site"])), "owner", OwnerRules.HERO)
	ObjectRules.note(s, str(p["site"]), "куплен героем у %s" % npc_name(data, seller(s, data, id)))
	var who := seller(s, data, id)
	s.remember(who, "продал герою %s" % name_of(s, data, id))
	var lines: Array[String] = ["Куплено: %s за %s — продавец %s" % [name_of(s, data, id), Money.format(price(s, data, id)), npc_name(data, who)]]
	lines.append("Без купчей место ваше лишь на словах — оформите бумагу в ратуше (пошлина %s)" % Money.format(deed_fee(s, data, id)))
	return lines


static func _fresh(s: GameSession, cond: float) -> Dictionary:
	return {"deed": false, "since": s.day, "cond": cond, "cash": 0, "stock": {}, "upgrades": [], "pending": [], "building": {},
		"staff": [], "last_day": s.day, "tax_day": s.day, "shift_day": -1}


static func deed_why(s: GameSession, data: Dictionary, id: String) -> String:
	if not owned(s.character, id):
		return "PROPERTY_NOT_YOURS"
	if bool(state(s.character)[id].get("deed", false)):
		return "PROPERTY_DEED_DONE"
	if registry_here(s, data).is_empty():
		return "PROPERTY_NO_REGISTRY"
	if int(s.character.get("gold_cp", 0)) < deed_fee(s, data, id):
		return "PROPERTY_NO_MONEY"
	return ""


static func deed(s: GameSession, data: Dictionary, id: String) -> Array[String]:
	var c := s.character
	var fee := deed_fee(s, data, id)
	Ledger.add(s, -fee, "property:deed")
	var st: Dictionary = state(c)[id]
	st["deed"] = true
	st["tax_day"] = s.day
	var clerk := registry_here(s, data)
	var item := {"name": "Купчая: %s" % name_of(s, data, id), "item_type": "gear", "value_cp": 0, "weight": 0, "properties": [], "generated": true,
		"description": "Заверенная бумага ратуши: место — ваше по закону.",
		"text": "Сим удостоверяется, что %s отныне принадлежит %s. Писано в ратуше, день %d. %s" % [name_of(s, data, id),
			str(c.get("name", "")), s.day, npc_name(data, clerk)]}
	var iid := ItemRules.generated_id(item)
	s.items[iid] = item
	ItemRules.found(c, data, s.items, iid)
	return ["Купчая заверена: %s — пошлина %s; налог %s в неделю" % [name_of(s, data, id), Money.format(fee), Money.format(tax(s, data, id))]]


## The place is lost (seized, disputed): the seller's again. Lines.
static func _lose(s: GameSession, data: Dictionary, id: String, why: String) -> Array[String]:
	var st: Dictionary = state(s.character)[id]
	for h: Dictionary in staff(s, id).duplicate():
		_fire(s, data, id, h)
	state(s.character).erase(id)
	Ledger.forgive(s, "tax:" + id)
	ObjectRules.note(s, str(prop(s, data, id).get("site", "")), "отобран у героя: %s" % why)
	Overlay.put(s, data, EntityRef.site(str(prop(s, data, id).get("site", ""))), "owner", seller(s, data, id))
	return ["%s больше не ваше: %s%s" % [name_of(s, data, id), why, "" if int(st.get("cash", 0)) <= 0 else "; выручка в кассе пропала"]]


# --- the days -------------------------------------------------------------------------------------------------------


## Each new day: work done, income and wages, decay, tax or dispute, animals fed. Lines (a summary per place).
static func tick(s: GameSession, data: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	if not data["rules"].has("property"):
		return lines
	for id: String in state(s.character).keys():
		var st: Dictionary = state(s.character)[id]
		var got := 0
		var paid := 0
		var days := 0
		while owned(s.character, id) and int(st["last_day"]) < s.day:
			st["last_day"] = int(st["last_day"]) + 1
			days += 1
			var r := _day(s, data, id, int(st["last_day"]))
			got += int(r["income"])
			paid += int(r["wages"])
			lines.append_array(r["lines"])
		if days > 0 and owned(s.character, id) and (got > 0 or paid > 0):
			lines.append("%s: выручка %s%s" % [name_of(s, data, id), Money.format(got), (", жалованье %s" % Money.format(paid)) if paid > 0 else ""])
	lines.append_array(_animals(s, data))
	lines.append_array(MountRules.day(s, data))  # v0.7.42: a rent's end, a beast stolen
	return lines


static func _day(s: GameSession, data: Dictionary, id: String, day: int) -> Dictionary:
	var st: Dictionary = state(s.character)[id]
	var c := s.character
	var cf := cfg(data)
	var lines: Array[String] = []
	var keep: Array = []
	for pd: Dictionary in st.get("pending", []):
		if int(pd["ready"]) <= day:
			lines.append_array(_apply_upgrade(s, data, id, str(pd["up"])))
		else:
			keep.append(pd)
	st["pending"] = keep
	var b: Dictionary = st.get("building", {})
	if not b.is_empty() and int(b["ready"]) <= day:
		lines.append_array(_finish_build(s, data, id, str(b["id"])))
	for h: Dictionary in staff(s, id).duplicate():
		if bool(h.get("serf", false)) and s.rng.randf() < float(cf["serfs"]["escape_chance_day"]):
			lines.append("%s сбежал из %s" % [hand_name(s, data, h), name_of(s, data, id)])
			_remove_creature(s, str(h["cid"]))
			(st["staff"] as Array).erase(h)
	if lapsed(s, id, day):  # a rented object past its term: the hands go, nothing works
		for h: Dictionary in staff(s, id).duplicate():
			lines.append("%s ушёл из %s: срок аренды вышел" % [hand_name(s, data, h), name_of(s, data, id)])
			_fire(s, data, id, h)
	var hands := staff(s, id).size()
	if bool(kind(s, data, id).get("decay", true)):
		var rate := float(cf["decay_worker"] if hands > 0 else cf["decay_per_day"]) * _gives(s, data, id, "decay_mult", 1.0)
		st["cond"] = clampf(float(st.get("cond", 100.0)) - rate, 0.0, 100.0)
	var income := roundi(income_day(s, data, id) * staff_mult(data, hands)) if hands > 0 else 0
	st["cash"] = int(st.get("cash", 0)) + income
	if hands > 0 or (kind(s, data, id).get("staff", []) as Array).is_empty():  # v0.7.39.8: a boat's catch, the hands at work
		var made := produce(s, data, id)
		var stock: Dictionary = st.get("stock", {})
		for item: String in made:
			stock[item] = int(stock.get(item, 0)) + int(made[item])
		st["stock"] = stock
	var wages := 0
	for h: Dictionary in staff(s, id):
		wages += int(cf["serfs"]["feed_cp_day"]) if bool(h.get("serf", false)) else int(h.get("wage", 0))
	if wages > 0:
		var from_till := mini(wages, int(st["cash"]))
		st["cash"] = int(st["cash"]) - from_till
		var rest := wages - from_till
		if rest > 0 and int(c.get("gold_cp", 0)) >= rest:
			Ledger.add(s, -rest, "property:day")
		elif rest > 0:  # the hired go, the last hired first, until the rest is paid
			for h: Dictionary in staff(s, id).duplicate():
				if rest <= 0:
					break
				if bool(h.get("serf", false)):
					continue
				lines.append("%s ушёл из %s: нечем платить" % [hand_name(s, data, h), name_of(s, data, id)])
				rest -= int(h.get("wage", 0))
				_fire(s, data, id, h)
	if bool(st.get("deed", false)):
		if day - int(st.get("tax_day", day)) >= int(cf["tax"]["every_days"]):
			st["tax_day"] = day
			var t := tax(s, data, id)
			var from_till := mini(t, int(st["cash"]))
			st["cash"] = int(st["cash"]) - from_till
			from_till += ShopRules.from_till(c, id, t - from_till)
			if from_till < t:
				Ledger.owe(s, "tax:" + id, "tax", t - from_till, "registry")
				lines.append("%s: налог %s не уплачен — долг ратуше %s" % [name_of(s, data, id), Money.format(t), Money.format(Ledger.owed(s, "tax:" + id))])
			if Ledger.owed(s, "tax:" + id) >= t * int(cf["tax"]["seize_weeks"]):
				lines.append_array(_lose(s, data, id, "ратуша забрала его за долги по налогу"))
				return {"income": income, "wages": wages, "lines": lines}
	else:
		var held := day - int(st.get("since", day))
		if held >= int(cf["dispute"]["grace_days"]) and held % 7 == 0 and s.rng.randf() < float(cf["dispute"]["chance"]):
			lines.append_array(_lose(s, data, id, "без купчей прежний хозяин оспорил сделку, и ратуша вернула место ему"))
	return {"income": income, "wages": wages, "lines": lines}


# --- in the place ---------------------------------------------------------------------------------------------------


static func collect_why(s: GameSession, data: Dictionary, id: String) -> String:
	if not owned(s.character, id) or here(s, data) != id:
		return "PROPERTY_NOT_HERE"
	var st: Dictionary = state(s.character)[id]
	if int(st.get("cash", 0)) <= 0 and (st.get("stock", {}) as Dictionary).is_empty():
		return "PROPERTY_TILL_EMPTY"
	return ""


static func collect(s: GameSession, data: Dictionary, id: String) -> Array[String]:
	var st: Dictionary = state(s.character)[id]
	var c := s.character
	var parts: Array[String] = []
	if int(st.get("cash", 0)) > 0:
		Ledger.add(s, int(st["cash"]), "property:collect")
		parts.append(Money.format(int(st["cash"])))
		st["cash"] = 0
	for item: String in st.get("stock", {}):
		ItemRules.found(c, data, s.items, item, int(st["stock"][item]))
		parts.append("%s ×%d" % [ItemRules.display_name(data["items"], s.items, item), int(st["stock"][item])])
	st["stock"] = {}
	FoodRules.sync(s, data)
	if Ledger.owed(s, "tax:" + id) > 0 and int(c["gold_cp"]) > 0:
		var pay := mini(Ledger.owed(s, "tax:" + id), int(c["gold_cp"]))
		Ledger.add(s, -pay, "property:collect")
		Ledger.settle(s, "tax:" + id, pay)
		parts.append("долг по налогу −%s" % Money.format(pay))
	return ["Из %s забрано: %s" % [name_of(s, data, id), ", ".join(parts)]]


## The tax debt (v0.7.39): paid by the button at the place or at the registry clerk, or by the master's `coins`
## with `settles: "tax"` (`settle_tax`). "" when it can be paid now, else a localization key.
static func pay_tax_why(s: GameSession, data: Dictionary, id: String) -> String:
	if not owned(s.character, id):
		return "PROPERTY_NOT_YOURS"
	if Ledger.owed(s, "tax:" + id) <= 0:
		return "PROPERTY_NO_DEBT"
	if here(s, data) != id and registry_here(s, data).is_empty():
		return "PROPERTY_TAX_WHERE"
	return "PROPERTY_NO_MONEY" if int(s.character.get("gold_cp", 0)) <= 0 else ""


## As much of the debt as the purse holds. Lines.
static func pay_tax(s: GameSession, data: Dictionary, id: String) -> Array[String]:
	var pay := mini(Ledger.owed(s, "tax:" + id), int(s.character.get("gold_cp", 0)))
	Ledger.add(s, -pay, "property:pay_tax")
	return _pay_debt(s, data, id, pay)


static func _pay_debt(s: GameSession, data: Dictionary, id: String, pay: int) -> Array[String]:
	Ledger.settle(s, "tax:" + id, pay)
	var left := Ledger.owed(s, "tax:" + id)
	return ["%s: налог уплачен — %s%s" % [name_of(s, data, id), Money.format(pay),
		", долг ещё %s" % Money.format(left) if left > 0 else ", долга больше нет"]]


## The tax debt of all the hero's places (the master's `coins` with `settles: "tax"` pays it).
static func tax_debt(s: GameSession) -> int:
	var total := 0
	for id: String in state(s.character):
		total += Ledger.owed(s, "tax:" + id)
	return total


## `amount` paid towards the tax debts, the oldest place first; the coins themselves are taken by the caller. Lines.
static func settle_tax(s: GameSession, data: Dictionary, amount: int) -> Array[String]:
	var lines: Array[String] = []
	for id: String in state(s.character):
		var pay := mini(amount, Ledger.owed(s, "tax:" + id))
		if pay <= 0:
			continue
		lines.append_array(_pay_debt(s, data, id, pay))
		amount -= pay
	return lines


static func shift_why(s: GameSession, data: Dictionary, id: String) -> String:
	var unfree := EncounterRules.unfree_why(s)
	if not unfree.is_empty():
		return unfree
	if not owned(s.character, id) or here(s, data) != id:
		return "PROPERTY_NOT_HERE"
	if data["rules"].has("shop") and ShopRules.active(s, id):
		return "PROPERTY_SHOP_SHIFT"
	if income_day(s, data, id) <= 0:
		return "PROPERTY_NO_INCOME"
	if int(state(s.character)[id].get("shift_day", -1)) == s.day:
		return "PROPERTY_SHIFT_DONE"
	return ""


static func shift_hours(s: GameSession, data: Dictionary, id: String) -> int:
	return int(kind(s, data, id).get("hours", 8))


static func _shift_bonus(s: GameSession, data: Dictionary, id: String) -> int:
	return CheckEngine.bonus_for(s.character, {"skill": str(kind(s, data, id).get("skill", "athletics"))}) + DifficultyRules.bonus(s, data)


static func shift_dc(data: Dictionary) -> int:
	return int(data["rules"]["dc_tiers"]["medium"])


static func shift_chance(s: GameSession, data: Dictionary, id: String) -> int:
	return Roll.chance(_shift_bonus(s, data, id), shift_dc(data), false)


## The hero's own shift in the place (the time passed): the day's income × the outcome, straight to the purse.
static func shift(s: GameSession, data: Dictionary, id: String, minutes: int) -> Array[String]:
	var c := s.character
	var st: Dictionary = state(c)[id]
	st["shift_day"] = s.day
	var full := shift_hours(s, data, id) * 60
	var day := income_day(s, data, id)
	if minutes < full:
		var part := roundi(day * float(minutes) / float(full) * 0.5)
		Ledger.add(s, part, "property:shift")
		return ["Работа прервана: %s" % Money.format(part)]
	var skill := str(kind(s, data, id).get("skill", "athletics"))
	var r := Roll.hero(s, data, {"what": name_of(s, data, id), "skill": skill, "dc": shift_dc(data)})
	var nat := int(r["nat"])
	var b := int(r["bonus"])
	var total := int(r["total"])
	var o := JobRules.outcome_for(data, int(r["margin"]))
	var got := roundi(day * (float(o.get("pay", 1.0)) + float(o.get("tips", 0.0))))
	Ledger.add(s, got, "property:shift")
	return ["%s: %s %d + %d = %d против Сл %d — %s" % [name_of(s, data, id), CraftRules.tr_skill(data, skill), nat, b, total, shift_dc(data), o["name"]],
		"Выручка: %s" % Money.format(got)]


static func repair_cost(s: GameSession, data: Dictionary, id: String, points: float) -> int:
	return roundi(price(s, data, id) * float(cfg(data)["repair_pct"]) / 100.0 * points / 100.0)


static func repair_hours(s: GameSession, data: Dictionary, id: String) -> int:
	var lost := 100.0 - float(state(s.character).get(id, {}).get("cond", 100.0))
	return maxi(1, ceili(lost / float(cfg(data)["repair_points_hour"])))


static func repair_why(s: GameSession, data: Dictionary, id: String) -> String:
	if not owned(s.character, id) or here(s, data) != id:
		return "PROPERTY_NOT_HERE"
	var lost := 100.0 - float(state(s.character)[id].get("cond", 100.0))
	if lost < 1.0:
		return "PROPERTY_WHOLE"
	if int(s.character.get("gold_cp", 0)) < repair_cost(s, data, id, lost):
		return "PROPERTY_NO_MONEY"
	return ""


static func repair(s: GameSession, data: Dictionary, id: String, minutes: int) -> Array[String]:
	var st: Dictionary = state(s.character)[id]
	var lost := 100.0 - float(st.get("cond", 100.0))
	var points := minf(lost, float(cfg(data)["repair_points_hour"]) * minutes / 60.0)
	var cost := repair_cost(s, data, id, points)
	Ledger.add(s, -cost, "property:repair")
	st["cond"] = minf(100.0, float(st["cond"]) + points)
	return ["%s подновлено: состояние %d%%, материалы %s" % [name_of(s, data, id), int(st["cond"]), Money.format(cost)]]


# --- workers and serfs ----------------------------------------------------------------------------------------------


## The hands of the hero's object: [{npc | cid, role, wage, serf}] (v0.7.39.5).
static func staff(s: GameSession, id: String) -> Array:
	var st: Dictionary = state(s.character).get(id, {})
	if not (st.get("staff") is Array):
		if st.is_empty():
			return []
		st["staff"] = []
	return st["staff"]


## The places of the object by roles: [{role, wage, max, taken}] — its kind's, more by upgrades (`staff_max` adds to
## the first role).
static func places(s: GameSession, data: Dictionary, id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p: Dictionary in kind(s, data, id).get("staff", []):
		out.append({"role": str(p["role"]), "wage": int(p.get("wage_cp_day", 0)), "max": int(p.get("max", 1)), "taken": 0})
	if not out.is_empty():
		out[0]["max"] = int(out[0]["max"]) + roundi(_gives(s, data, id, "staff_max", 0.0))
	for h: Dictionary in staff(s, id):
		for p: Dictionary in out:
			if str(p["role"]) == str(h.get("role", "")):
				p["taken"] = int(p["taken"]) + 1
	return out


static func _place(s: GameSession, data: Dictionary, id: String, role: String) -> Dictionary:
	for p: Dictionary in places(s, data, id):
		if str(p["role"]) == role:
			return p
	return {}


## Each hand past the first adds rules.property.staff_extra_pct of the base (income, buyers).
static func staff_mult(data: Dictionary, hands: int) -> float:
	return 1.0 + maxi(0, hands - 1) * float(cfg(data).get("staff_extra_pct", 0)) / 100.0


static func hand_name(s: GameSession, data: Dictionary, h: Dictionary) -> String:
	if bool(h.get("serf", false)):
		var cr := _creature(s, str(h.get("cid", "")))
		return str(cr.get("name", "подневольный"))
	return npc_name(data, str(h.get("npc", "")))


## A rented object (a stall) past its term on `day` (default today).
static func lapsed(s: GameSession, id: String, day: int = -1) -> bool:
	var st: Dictionary = state(s.character).get(id, {})
	return st.has("rent_day") and int(st["rent_day"]) < (s.day if day < 0 else day)


static func worker_why(s: GameSession, data: Dictionary, id: String, role: String = "") -> String:
	if not owned(s.character, id) or here(s, data) != id:
		return "PROPERTY_NOT_HERE"
	var p := _place(s, data, id, role) if not role.is_empty() else (places(s, data, id)[0] if not places(s, data, id).is_empty() else {})
	if p.is_empty():
		return "PROPERTY_NO_WORK"
	if lapsed(s, id):
		return "SHOP_STALL_LAPSED"
	if int(p["taken"]) >= int(p["max"]):
		return "PROPERTY_HAS_WORKER"
	if int(s.character.get("gold_cp", 0)) < int(p["wage"]):
		return "PROPERTY_NO_MONEY"
	return ""


## A worker of the place: a person the engine makes from the pack's names, living in the place, paid each day.
static func hire_worker(s: GameSession, data: Dictionary, id: String, role: String = "") -> Array[String]:
	var p := _place(s, data, id, role) if not role.is_empty() else places(s, data, id)[0]
	var hand := make_hand(s, data, str(p["role"]), main_room(s, data, id), name_of(s, data, id))
	if hand.has("reason"):
		return ["Работника не найти: %s" % hand["reason"]]
	var wage := int(p["wage"])
	Ledger.add(s, -wage, "property:hire_worker")
	staff(s, id).append({"npc": str(hand["npc"]), "role": str(p["role"]), "wage": wage, "since": s.day})
	ObjectRules.note(s, str(prop(s, data, id).get("site", "")), "нанят %s — %s" % [hand["name"], p["role"]])
	return ["Нанят %s — %s («%s»), %s в день (первый день уплачен)" % [hand["name"], p["role"], name_of(s, data, id), Money.format(wage)]]


## A hired hand: a person the engine makes from the pack's names in the room. {npc, name} or {reason}.
static func make_hand(s: GameSession, data: Dictionary, role: String, room: String, place: String) -> Dictionary:
	var gender := "male" if s.rng.randf() < 0.5 else "female"
	var names: Array = data.get("pack", {}).get("names", {}).get(gender, [])
	var taken: Array = data["world"]["npcs"].values().map(func(n: Dictionary) -> String: return str(n.get("name", "")))
	var free: Array = names.filter(func(n: Variant) -> bool: return not taken.has(str(n)))
	var name := str(free[s.rng.randi_range(0, free.size() - 1)]) if not free.is_empty() else ("Работник" if gender == "male" else "Работница")
	var plan := WorldGen.plan_npc(s, data, {"name": name, "role": role, "room_id": room, "gender": gender,
		"description": "%s в %s" % [_upper_first(role), place], "personality": "работящий, держится за место"}, true)
	if plan.has("reason"):
		return {"reason": str(plan["reason"])}
	var npc := WorldGen.apply_npc(s, data, plan["plan"])
	s.shift_attitude(npc, 1, data)
	return {"npc": npc, "name": name}


## A hired hand leaves the world: out of its room, no room of its own.
static func dismiss_hand(s: GameSession, data: Dictionary, npc: String) -> void:
	var gen := WorldGen.generated(s)
	var room := str(gen.get("npc_rooms", {}).get(npc, ""))
	if data["world"]["rooms"].has(room):
		(data["world"]["rooms"][room].get("npcs", []) as Array).erase(npc)
	if gen.get("npc_rooms", {}).has(npc):
		gen["npc_rooms"][npc] = ""


## The hand of the object by its person (an NPC id or a creature id), {} — none.
static func hand_of(s: GameSession, id: String, who: String) -> Dictionary:
	for h: Dictionary in staff(s, id):
		if str(h.get("npc", h.get("cid", ""))) == who:
			return h
	return {}


static func fire_why(s: GameSession, _data: Dictionary, id: String, who: String = "") -> String:
	if not owned(s.character, id):
		return "PROPERTY_NOT_YOURS"
	if who.is_empty():
		return "" if not staff(s, id).is_empty() else "PROPERTY_NO_WORKER"
	return "" if not hand_of(s, id, who).is_empty() else "PROPERTY_NO_WORKER"


## Lets a hand go (`who` empty — the last hired).
static func fire(s: GameSession, data: Dictionary, id: String, who: String = "") -> Array[String]:
	var h: Dictionary = hand_of(s, id, who) if not who.is_empty() else staff(s, id)[staff(s, id).size() - 1]
	var name := hand_name(s, data, h)
	_fire(s, data, id, h)
	ObjectRules.note(s, str(prop(s, data, id).get("site", "")), "%s больше не работает здесь" % name)
	return ["%s больше не работает в %s" % [name, name_of(s, data, id)]]


static func _fire(s: GameSession, data: Dictionary, id: String, h: Dictionary) -> void:
	if bool(h.get("serf", false)):
		_creature(s, str(h.get("cid", ""))).erase("serf")
	elif not str(h.get("npc", "")).is_empty():
		dismiss_hand(s, data, str(h["npc"]))
	staff(s, id).erase(h)


static func _creature(s: GameSession, cid: String) -> Dictionary:
	if cid.is_empty():
		return {}
	for room: String in s.creatures:
		for cr: Dictionary in s.creatures[room]:
			if str(cr["id"]) == cid:
				return cr
	return {}


static func _remove_creature(s: GameSession, cid: String) -> void:
	for room: String in s.creatures.keys():
		for cr: Dictionary in s.creatures[room]:
			if str(cr["id"]) == cid:
				(s.creatures[room] as Array).erase(cr)
				if (s.creatures[room] as Array).is_empty():
					s.creatures.erase(room)
				return


## A bound prisoner of the hero, a person, in the place: may be put to work while the world allows slavery.
static func serf_why(s: GameSession, data: Dictionary, id: String, cid: String) -> String:
	if not slavery(s, data):
		return "PROPERTY_NO_SLAVERY"
	if not owned(s.character, id) or here(s, data) != id:
		return "PROPERTY_NOT_HERE"
	var cr := CreatureRules.find(s, s.room_id, cid)
	if cr.is_empty() or not bool(cr.get("bound", false)) or str(cr.get("owner", "")) != OwnerRules.HERO or not OwnerRules.thinking(data, cr):
		return "PROPERTY_NOT_A_SERF"
	var free := places(s, data, id).filter(func(p: Dictionary) -> bool: return int(p["taken"]) < int(p["max"]))
	if places(s, data, id).is_empty():
		return "PROPERTY_NO_WORK"
	if free.is_empty():
		return "PROPERTY_HAS_WORKER"
	return ""


static func set_serf(s: GameSession, data: Dictionary, id: String, cid: String) -> Array[String]:
	var cr := CreatureRules.find(s, s.room_id, cid)
	cr["serf"] = id
	cr["led"] = false
	var p: Dictionary = places(s, data, id).filter(func(x: Dictionary) -> bool: return int(x["taken"]) < int(x["max"]))[0]
	staff(s, id).append({"cid": cid, "role": str(p["role"]), "wage": 0, "serf": true, "since": s.day})
	return ["%s приставлен к работе в %s — %s, без платы, за еду" % [cr["name"], name_of(s, data, id), p["role"]]]


# --- upgrades and building ------------------------------------------------------------------------------------------


## The upgrades the place may take: [id].
static func upgrades_for(s: GameSession, data: Dictionary, id: String) -> Array[String]:
	var out: Array[String] = []
	if bool(kind(s, data, id).get("buildable", false)):
		return out
	var k := kind(s, data, id)
	var all_ups := ups(data)
	for up: String in all_ups:
		var u: Dictionary = all_ups[up]
		if u.has("places") and not (u["places"] as Array).has(id):  # asked at this place (effect `upgrade`)
			continue
		if u.has("kinds") and not (u["kinds"] as Array).has(kind_id(s, data, id)):
			continue
		if bool(u.get("income", false)) and int(k.get("income_cp_day", 0)) <= 0 and not k.has("trade"):
			continue
		if bool(u.get("trade", false)) and not k.has("trade"):
			continue
		if (k.get("staff", []) as Array).is_empty() and u.get("gives", {}).has("staff_max"):
			continue
		out.append(up)
	return out


static func pending(c: Dictionary, id: String, up: String) -> Dictionary:
	for pd: Dictionary in state(c).get(id, {}).get("pending", []):
		if str(pd["up"]) == up:
			return pd
	return {}


static func upgrade_why(s: GameSession, data: Dictionary, id: String, up: String) -> String:
	if not owned(s.character, id) or here(s, data) != id:
		return "PROPERTY_NOT_HERE"
	var u: Dictionary = ups(data).get(up, {})
	if u.is_empty() or not upgrades_for(s, data, id).has(up):
		return "PROPERTY_NO_UPGRADE"
	if has_upgrade(s.character, id, up) or not pending(s.character, id, up).is_empty():
		return "PROPERTY_UPGRADE_HAS"
	if bool(u.get("indoor", false)) and not bool(WorldView.new(data["world"]).room(main_room(s, data, id)).get("indoor", false)):
		return "PROPERTY_NEEDS_ROOF"
	if int(s.character.get("gold_cp", 0)) < int(u["price_cp"]):
		return "PROPERTY_NO_MONEY"
	return ""


static func upgrade(s: GameSession, data: Dictionary, id: String, up: String) -> Array[String]:
	var u: Dictionary = ups(data)[up]
	Ledger.add(s, -int(u["price_cp"]), "property:upgrade")
	var days := int(u.get("days", 0))
	if days <= 0:
		return _apply_upgrade(s, data, id, up)
	(state(s.character)[id]["pending"] as Array).append({"up": up, "ready": s.day + days})
	return ["%s: заказано «%s» за %s — готово через %s" % [name_of(s, data, id), u["name"], Money.format(int(u["price_cp"])), _days(days)]]


static func _apply_upgrade(s: GameSession, data: Dictionary, id: String, up: String) -> Array[String]:
	var u: Dictionary = ups(data)[up]
	var g: Dictionary = u.get("gives", {})
	var room := main_room(s, data, id)
	if g.has("station"):
		_add_tag(s, data, room, str(g["station"]))
	if bool(g.get("rest", false)):
		Overlay.put(s, data, EntityRef.room(room), "safe", {"rest_cost_cp": 0})
	if bool(g.get("private", false)):
		Overlay.put(s, data, EntityRef.site(str(prop(s, data, id)["site"])), "public", false)
	if g.has("object"):  # v0.7.39.5: a counter — a trading object of its own beside the house
		(state(s.character)[id]["upgrades"] as Array).append(up)
		var made := new_object(s, data, str(g["object"]), room, "%s: %s" % [name_of(s, data, id), str(kind_cfg(data, str(g["object"])).get("name", ""))])
		return ["%s: готово «%s» — %s (новое место: %s)" % [name_of(s, data, id), u["name"], u.get("text", ""), name_of(s, data, made)]]
	if bool(g.get("storage", false)):
		var list: Array = s.props.get(room, [])
		list.append({"id": "chest_" + id, "name": "Ваш сундук", "description": "Крепкий сундук с вашим замком.", "item_id": "",
			"owner": "", "text": "", "state": "", "container": "chest", "contents": {}, "mine": true})
		s.props[room] = list
	(state(s.character)[id]["upgrades"] as Array).append(up)
	ObjectRules.note(s, str(prop(s, data, id).get("site", "")), "готово «%s»" % u["name"])
	return ["%s: готово «%s» — %s" % [name_of(s, data, id), u["name"], u.get("text", "")]]


static func build_why(s: GameSession, data: Dictionary, id: String, b: String) -> String:
	if not owned(s.character, id) or here(s, data) != id:
		return "PROPERTY_NOT_HERE"
	if not bool(kind(s, data, id).get("buildable", false)) or not cfg(data)["build"].has(b):
		return "PROPERTY_NOT_LAND"
	if not (state(s.character)[id].get("building", {}) as Dictionary).is_empty():
		return "PROPERTY_BUILDING"
	if int(s.character.get("gold_cp", 0)) < int(cfg(data)["build"][b]["price_cp"]):
		return "PROPERTY_NO_MONEY"
	return ""


static func build(s: GameSession, data: Dictionary, id: String, b: String) -> Array[String]:
	var bc: Dictionary = cfg(data)["build"][b]
	Ledger.add(s, -int(bc["price_cp"]), "property:build")
	state(s.character)[id]["building"] = {"id": b, "ready": s.day + int(bc["days"])}
	return ["%s: заложено «%s» за %s — плотники управятся за %s" % [name_of(s, data, id), bc["name"], Money.format(int(bc["price_cp"])), _days(int(bc["days"]))]]


## The building stands: its rooms in the land's site, the place of its kind. Lines.
static func _finish_build(s: GameSession, data: Dictionary, id: String, b: String) -> Array[String]:
	var bc: Dictionary = cfg(data)["build"][b]
	var st: Dictionary = state(s.character)[id]
	var gen := WorldGen.generated(s)
	for k: String in ["rooms", "edge_exits"]:
		if not gen.has(k):
			gen[k] = {}
	var w := WorldView.new(data["world"])
	var land := main_room(s, data, id)
	var sid := str(prop(s, data, id)["site"])
	for spec: Dictionary in bc["rooms"]:
		var n := 1
		while data["world"]["rooms"].has("gen_room_%d" % n):
			n += 1
		var rid := "gen_room_%d" % n
		var room := {"name": str(spec["name"]), "location_id": w.location_id(land), "description": str(spec.get("description", "")),
			"exits": [land], "npcs": [], "hooks": [], "secrets": [], "generated": true, "site_id": sid}
		if bool(spec.get("indoor", false)):
			room["indoor"] = true
		if spec.has("tags"):
			room["tags"] = (spec["tags"] as Array).duplicate()
		gen["rooms"][rid] = room
		data["world"]["rooms"][rid] = room.duplicate(true)
		var exits: Array = gen["edge_exits"].get(land, [])
		exits.append(rid)
		gen["edge_exits"][land] = exits
		(data["world"]["rooms"][land]["exits"] as Array).append(rid)
	st["building"] = {}
	st["kind"] = str(bc["kind"])
	st["cond"] = 100.0
	return ["%s: построено «%s»" % [name_of(s, data, id), bc["name"]]]


# --- objects the engine makes: a counter, a rented stall (v0.7.39.5) ---------------------------------------------


static func kind_cfg(data: Dictionary, k: String) -> Dictionary:
	return kinds(data).get(k, {})


## A new object of the hero of `kind` beside `anchor` (a room): its own site and room (rules.property.kinds[k].room),
## its way from the anchor, the hero's state. Its id.
static func new_object(s: GameSession, data: Dictionary, k: String, anchor: String, name: String) -> String:
	var gen := WorldGen.generated(s)
	for key: String in ["rooms", "sites", "edge_exits", "properties"]:
		if not gen.has(key):
			gen[key] = {}
	var w := WorldView.new(data["world"])
	var spec: Dictionary = kind_cfg(data, k).get("room", {})
	var n := 1
	while data["world"]["rooms"].has("gen_room_%d" % n) or gen["rooms"].has("gen_room_%d" % n):
		n += 1
	var rid := "gen_room_%d" % n
	var sn := 1
	while data["world"].get("sites", {}).has("gen_site_%d" % sn) or gen["sites"].has("gen_site_%d" % sn):
		sn += 1
	var sid := "gen_site_%d" % sn
	var room := {"name": str(spec.get("name", name)), "location_id": w.location_id(anchor), "description": str(spec.get("description", "")),
		"exits": [anchor], "npcs": [], "hooks": [], "secrets": [], "generated": true, "site_id": sid}
	if bool(spec.get("indoor", false)):
		room["indoor"] = true
	gen["rooms"][rid] = room
	gen["sites"][sid] = {"name": name, "location_id": w.location_id(anchor), "entry": rid, "owner": OwnerRules.HERO, "kind": k, "public": true}
	var exits: Array = gen["edge_exits"].get(anchor, [])
	exits.append(rid)
	gen["edge_exits"][anchor] = exits
	var id := "gen_p_" + sid
	gen["properties"][id] = {"site": sid, "name": name, "kind": k, "seller": "", "price_cp": 0, "generated": true}
	data["world"]["rooms"][rid] = room.duplicate(true)
	if not data["world"].has("sites"):
		data["world"]["sites"] = {}
	data["world"]["sites"][sid] = (gen["sites"][sid] as Dictionary).duplicate(true)
	(data["world"]["rooms"][anchor]["exits"] as Array).append(rid)
	state(s.character)[id] = _fresh(s, 100.0)
	state(s.character)[id]["kind"] = k
	ObjectRules.note(s, sid, "открыт героем")
	return id


## The hero's rented object of `kind` in the location ("" — none).
static func rented(s: GameSession, data: Dictionary, k: String, loc: String) -> String:
	for id: String in state(s.character):
		if kind_id(s, data, id) == k and state(s.character)[id].has("rent_day") \
				and WorldView.new(data["world"]).location_id(main_room(s, data, id)) == loc:
			return id
	return ""


## The room of the location an object of `kind` is rented at (its `rent.tag`), "" — none.
static func rent_room(data: Dictionary, k: String, loc: String) -> String:
	var tag := str(kind_cfg(data, k).get("rent", {}).get("tag", ""))
	for id: String in data["world"]["rooms"]:
		var r: Dictionary = data["world"]["rooms"][id]
		if not tag.is_empty() and str(r.get("location_id", "")) == loc and (r.get("tags", []) as Array).has(tag) and not bool(r.get("generated", false)):
			return id
	return ""


## Renting an object (a market stall) at the registry clerk for `days`. "" or a localization key.
static func rent_why(s: GameSession, data: Dictionary, npc_id: String, k: String, days: int) -> String:
	if not is_registry(data, npc_id) or not _present(s, data, npc_id):
		return "SHOP_NOT_HERE"
	var rent: Dictionary = kind_cfg(data, k).get("rent", {})
	if rent.is_empty():
		return "SHOP_NO_SERVICE"
	if rent_room(data, k, WorldView.new(data["world"]).location_id(s.room_id)).is_empty():
		return "SHOP_NO_MARKET"
	if not (rent["days"] as Array).any(func(d: Variant) -> bool: return int(d) == days):
		return "SHOP_NO_SERVICE"
	return "SHOP_NO_MONEY" if int(s.character.get("gold_cp", 0)) < days * int(rent["cp_day"]) else ""


static func rent(s: GameSession, data: Dictionary, _npc_id: String, k: String, days: int) -> Array[String]:
	var loc := WorldView.new(data["world"]).location_id(s.room_id)
	var cost := days * int(kind_cfg(data, k)["rent"]["cp_day"])
	Ledger.add(s, -cost, "property:rent")
	var id := rented(s, data, k, loc)
	if id.is_empty():
		var room := rent_room(data, k, loc)
		id = new_object(s, data, k, room, "%s (%s)" % [_upper_first(str(kind_cfg(data, k).get("name", k))), WorldView.new(data["world"]).room_short(room)])
		state(s.character)[id]["rent_day"] = s.day - 1
	var st: Dictionary = state(s.character)[id]
	st["rent_day"] = maxi(int(st["rent_day"]), s.day - 1) + days
	return ["%s — снято до дня %d, %s" % [name_of(s, data, id), int(st["rent_day"]), Money.format(cost)]]


## Saves before v0.7.39.5: a stall rented at a market room and a house with the counter become objects of their own,
## their shelves moved with them. Once, on load.
static func upgrade_legacy(s: GameSession, data: Dictionary) -> void:
	if not data["rules"].has("property"):
		return
	var shop: Dictionary = s.character.get("shop", {})
	for room: String in (shop.get("stalls", {}) as Dictionary).keys():
		var loc := WorldView.new(data["world"]).location_id(room)
		var id := rented(s, data, "stall", loc)
		if id.is_empty():
			id = new_object(s, data, "stall", room, "%s (%s)" % [_upper_first(str(kind_cfg(data, "stall").get("name", ""))), WorldView.new(data["world"]).room_short(room)])
		state(s.character)[id]["rent_day"] = int(shop["stalls"][room])
		var venues: Dictionary = shop.get("venues", {})
		if venues.has("stall:" + room):
			venues[id] = venues["stall:" + room]
			venues.erase("stall:" + room)
	shop.erase("stalls")
	for id: String in state(s.character):  # a staff migrated from one worker: its role and wage by the kind
		for h: Dictionary in staff(s, id):
			if str(h.get("role", "")).is_empty() and not places(s, data, id).is_empty():
				h["role"] = str(places(s, data, id)[0]["role"])
				h["wage"] = 0 if bool(h.get("serf", false)) else int(places(s, data, id)[0]["wage"])
	for id: String in state(s.character).keys():
		if kind_id(s, data, id) == "house" and has_upgrade(s.character, id, "counter"):
			var made := false
			for other: String in state(s.character):
				made = made or (prop(s, data, other).get("generated", false) and kind_id(s, data, other) == "counter" \
					and (WorldView.new(data["world"]).room(main_room(s, data, other)).get("exits", []) as Array).has(main_room(s, data, id)))
			if made:
				continue
			var counter := new_object(s, data, "counter", main_room(s, data, id), "%s: %s" % [name_of(s, data, id), str(kind_cfg(data, "counter").get("name", ""))])
			var venues: Dictionary = shop.get("venues", {})
			if venues.has(id):
				venues[counter] = venues[id]
				venues.erase(id)


static func _days(n: int) -> String:
	return "%d %s" % [n, "день" if n % 10 == 1 and n % 100 != 11 else "дня" if n % 10 in [2, 3, 4] and not n % 100 in [12, 13, 14] else "дней"]


# --- animals --------------------------------------------------------------------------------------------------------


static func animal_cfg(data: Dictionary, monster: String) -> Dictionary:
	var own: Dictionary = cfg(data)["animals"].get(monster, data["world"].get("animal_kinds", {}).get(monster, {}))  # v0.7.42: the master's beasts
	return own if not own.is_empty() else PetRules.kind(data, monster)  # v0.7.43: a tamed beast


## Animals an NPC sells: [monster id].
static func animals_of(data: Dictionary, npc_id: String) -> Array[String]:
	var out: Array[String] = []
	for m: Variant in WorldView.new(data["world"]).npc(npc_id).get("animals", []):
		if not animal_cfg(data, str(m)).is_empty() and data["monsters"].has(str(m)):
			out.append(str(m))
	return out


static func animal_why(s: GameSession, data: Dictionary, npc_id: String, monster: String) -> String:
	if not animals_of(data, npc_id).has(monster):
		return "PROPERTY_NO_ANIMAL"
	if not _present(s, data, npc_id):
		return "PROPERTY_SELLER_AWAY"
	if SocialRules.refuses(s, data, npc_id):
		return "TALK_REFUSED"
	if int(s.character.get("gold_cp", 0)) < int(animal_cfg(data, monster)["price_cp"]):
		return "PROPERTY_NO_MONEY"
	return ""


## `price` (v0.7.42) — what is paid instead of the full price (a rent).
static func buy_animal(s: GameSession, data: Dictionary, npc_id: String, monster: String, price: int = -1) -> Array[String]:
	var a := animal_cfg(data, monster)
	var m: Dictionary = data["monsters"][monster]
	Ledger.add(s, -(int(a["price_cp"]) if price < 0 else price), "property:buy_animal")
	s.creature_counter += 1
	var cr := {"id": "c%d" % s.creature_counter, "name": str(m["name"]), "monster": monster, "state": TAME, "bound": false, "led": true,
		"owner": OwnerRules.HERO, "since": TimeRules.abs_minute(s), "hp": int(m["hp"]), "max_hp": int(m["hp"]), "xp_given": true, "fed_day": s.day}
	var pk := PetRules.kind(data, monster)  # v0.7.43: a dog bought is a pet of the hero
	if not pk.is_empty() and not bool(a.get("pack", false)) and (bool(pk["fights"]) or bool(pk["scout"]) or not (pk["help"] as Array).is_empty() or float(pk["spoil_mult"]) > 1.0):
		cr.merge({"pet": true, "close": 1})
	var list: Array = s.creatures.get(s.room_id, [])
	list.append(cr)
	s.creatures[s.room_id] = list
	s.remember(npc_id, "продал герою: %s" % m["name"])
	return ["Куплено: %s за %s — идёт с вами; корм %s в день" % [m["name"], Money.format(int(a["price_cp"])), Money.format(int(a["feed_cp_day"]))]]


static func animals(s: GameSession) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for room: String in s.creatures:
		for cr: Dictionary in s.creatures[room]:
			if str(cr.get("state", "")) == TAME and str(cr.get("owner", "")) == OwnerRules.HERO:
				out.append(cr)
	return out


static func room_of(s: GameSession, cid: String) -> String:
	for room: String in s.creatures:
		for cr: Dictionary in s.creatures[room]:
			if str(cr["id"]) == cid:
				return room
	return ""


## Feeding each day: from the till of the own place the beast stands in, else the purse; unfed past starve_days — it
## goes. A beast at an own place gives its produce into the place's stock.
static func _animals(s: GameSession, data: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	for cr: Dictionary in animals(s):
		var a := animal_cfg(data, str(cr["monster"]))
		var room := room_of(s, str(cr["id"]))
		var pid := at(s, data, room)
		if not owned(s.character, pid):
			pid = ""
		while int(cr.get("fed_day", s.day)) < s.day:
			cr["fed_day"] = int(cr.get("fed_day", s.day)) + 1
			var feed := roundi(int(a.get("feed_cp_day", 0)) * (_gives(s, data, pid, "feed_mult", 1.0) if not pid.is_empty() else 1.0))
			var st: Dictionary = state(s.character).get(pid, {})
			if PetRules.eat(s, data, cr):  # v0.7.43: a pet beside the hero eats of his things first
				pass
			elif not pid.is_empty() and int(st.get("cash", 0)) >= feed:
				st["cash"] = int(st["cash"]) - feed
			elif int(s.character.get("gold_cp", 0)) >= feed and MountRules.fed_by_purse(s, data, cr):  # v0.7.42: left alone — no feed
				Ledger.add(s, -feed, "property:animals")
			else:
				cr["hungry"] = int(cr.get("hungry", 0)) + 1
				continue
			cr["hungry"] = 0
			if not pid.is_empty():
				var stock: Dictionary = st.get("stock", {})
				for item: String in a.get("produce", {}):
					stock[item] = int(stock.get(item, 0)) + int(a["produce"][item])
				st["stock"] = stock
		if int(cr.get("hungry", 0)) >= PetRules.starve_days(data, cr):  # v0.7.43: a close pet bears longer
			lines.append("%s убежал — его не кормили" % cr["name"])
			_remove_creature(s, str(cr["id"]))
	return lines


## The way between places shortens while a beast to ride is led (the best of them).
static func travel_mult(s: GameSession, data: Dictionary, room_id: String) -> float:
	var mult := 1.0
	if not data["rules"].has("property"):
		return mult
	for cr: Dictionary in CreatureRules.here(s, room_id):
		if str(cr.get("state", "")) == TAME and bool(cr.get("led", false)):
			mult = minf(mult, float(animal_cfg(data, str(cr["monster"])).get("travel_mult", 1.0)))
	return mult


## The led beasts that fight beside the hero (AllyRules.joining's specs).
static func fighting(s: GameSession, data: Dictionary) -> Array:
	var out: Array = []
	for cr: Dictionary in CreatureRules.here(s, s.room_id):
		if str(cr.get("state", "")) == TAME and bool(cr.get("led", false)) and bool(animal_cfg(data, str(cr["monster"])).get("fights", false)):
			out.append({"monster": str(cr["monster"]), "name": str(cr["name"]), "hp": int(cr.get("hp", 1)), "ally": "animal", "creature_id": str(cr["id"])})
	return out


# --- for the master -------------------------------------------------------------------------------------------------


## «Имущество (окно «Имущество»): Дом у реки (дом) — с купчей, состояние 70%…; продаётся рядом: …; животные: …».
static func text(s: GameSession, data: Dictionary) -> String:
	if not data["rules"].has("property"):
		return ""
	var parts: Array[String] = []
	for id: String in state(s.character):
		var st: Dictionary = state(s.character)[id]
		var bits: Array[String] = ["с купчей" if bool(st.get("deed", false)) else "без купчей"]
		if bool(kind(s, data, id).get("decay", true)):
			bits.append("состояние %d%%" % int(st.get("cond", 100)))
		if not staff(s, id).is_empty():
			bits.append("штат: " + ", ".join(staff(s, id).map(func(h: Dictionary) -> String: return "%s (%s)" % [hand_name(s, data, h), h.get("role", "")])))
		if st.has("rent_day"):
			bits.append("снято до дня %d" % int(st["rent_day"]))
		if Ledger.owed(s, "tax:" + id) > 0:
			bits.append("долг по налогу %s" % Money.format(Ledger.owed(s, "tax:" + id)))
		if not (st.get("upgrades", []) as Array).is_empty():
			bits.append("есть: " + ", ".join((st["upgrades"] as Array).map(func(u: Variant) -> String: return str(ups(data).get(str(u), {}).get("name", u)))))
		parts.append("%s (%s) — %s" % [name_of(s, data, id), kind(s, data, id).get("name", ""), ", ".join(bits)])
	var sale: Array[String] = []
	var loc := WorldView.new(data["world"]).location_id(s.room_id)
	var props := all(s, data)
	for id: String in props:
		if owned(s.character, id) or WorldView.new(data["world"]).location_id(main_room(s, data, id)) != loc:
			continue
		sale.append("%s — %s, продаёт %s" % [name_of(s, data, id), Money.format(price(s, data, id)), npc_name(data, seller(s, data, id))])
	var beasts: Array[String] = []
	for cr: Dictionary in animals(s):
		var where := "с героем" if bool(cr.get("led", false)) else ("ждёт у входа: " if bool(cr.get("waiting", false)) else "") + WorldView.new(data["world"]).room_short(room_of(s, str(cr["id"])))
		var load := MountRules.load_text(s, data, cr) if MountRules.on(data) else ""  # v0.7.42
		if bool(cr.get("pet", false)):  # v0.7.43
			load = "питомец [%s]: %s" % [cr["id"], PetRules.text(data, cr)]
		beasts.append("%s (%s%s)" % [cr["name"], where, "; " + load if not load.is_empty() else ""])
	var stolen: Array[String] = []
	for st: Dictionary in s.character.get("stolen_animals", []):  # v0.7.42: a quest to get it back is the master's
		stolen.append("%s — увели в день %d у %s%s" % [st["name"], int(st["day"]), WorldView.new(data["world"]).room_short(str(st["room"])),
			", с грузом: " + str(st["load"]) if not str(st.get("load", "")).is_empty() else ""])
	var out: Array[String] = []
	if not parts.is_empty():
		out.append("Имущество (окно «Имущество» на панели): " + "; ".join(parts))
	if not sale.is_empty():
		out.append("Продаётся здесь (кнопка «Имущество» у продавца): " + "; ".join(sale))
	if not beasts.is_empty():
		out.append("Животные героя: " + ", ".join(beasts))
	if not stolen.is_empty():
		out.append("Украдены у героя (вора можно искать — задание мастера): " + "; ".join(stolen.slice(-3)))
	return ". ".join(out)


## A place the master puts on sale (effect `property`): a site of this location, its seller of the scene, the price and
## income within rules.property.make. {id, def, made?} or {reason}; site / seller "new" — made in this turn. `new_kind`
## (v0.7.39.8) — a kind of the master's own (a school, a fishing pier…): `made` = plan_kind's, kept on apply.
static func make(s: GameSession, data: Dictionary, spec: Dictionary) -> Dictionary:
	var m: Dictionary = cfg(data)["make"]
	var site := str(spec.get("site_id", ""))
	var who := str(spec.get("seller_id", ""))
	if who != "new" and not _present(s, data, who):
		return {"reason": "продавец %s не в сцене — продаёт только тот, кто здесь (или «new» — человек create_npc этого хода)" % who}
	var p := int(spec.get("price_cp", 0))
	if p < int(m["price_cp"][0]) or p > int(m["price_cp"][1]):
		return {"reason": "price_cp — от %s до %s" % [Money.format(int(m["price_cp"][0])), Money.format(int(m["price_cp"][1]))]}
	var all_kinds := kinds(data)
	var made := {}
	var k := str(spec.get("place_kind", "")) if spec.get("place_kind") != null else ""
	if spec.get("new_kind") is Dictionary:
		made = plan_kind(s, data, spec["new_kind"])
		if made.has("reason"):
			return made
		k = str(made["key"])
		all_kinds = all_kinds.duplicate()
		all_kinds[k] = made["def"]
	elif not all_kinds.has(k):
		return {"reason": "place_kind — из %s, или new_kind — свой вид места" % ", ".join(all_kinds.keys())}
	var inc := int(spec.get("income_cp_day", 0)) if spec.get("income_cp_day") != null else 0
	var cap := roundi(p * float(m["income_day_pct"]) / 100.0)
	if (inc if inc > 0 else int(all_kinds[k].get("income_cp_day", 0))) > cap:
		return {"reason": "доход не больше %s в день при такой цене — подними цену или убавь доход" % Money.format(cap)}
	if inc > 0 and int(all_kinds[k].get("income_cp_day", 0)) <= 0:
		return {"reason": "у места вида %s нет дохода — возьми вид с доходом: %s" % [k, ", ".join(all_kinds.keys().filter(func(x: String) -> bool: return int(all_kinds[x].get("income_cp_day", 0)) > 0))]}
	var w := WorldView.new(data["world"])
	if site == "here":  # the site the hero stands in
		site = w.site_id(s.room_id)
	elif data["world"]["rooms"].has(site):  # a room's id stands for its site
		site = w.site_id(site)
	var name := str(spec.get("name", "")).strip_edges().left(60)
	if site != "new":
		if w.site(site).is_empty():
			return {"reason": "объекта %s нет: site_id из сцены или «new» — объект create_place этого хода" % site}
		if str(w.site(site).get("location_id", "")) != w.location_id(s.room_id):
			return {"reason": "продают объект этой локации"}
		var owner := str(w.site(site).get("owner", ""))
		if not owner.is_empty() and owner != who:
			return {"reason": "у объекта уже хозяин %s — продать его может только он" % npc_name(data, owner)}
		if w.site_rooms(site).size() > int(m["max_rooms"]):
			return {"reason": "слишком большой объект — до %d комнат" % int(m["max_rooms"])}
		if not at(s, data, w.site_entry(site)).is_empty():
			return {"reason": "этот объект уже продаётся или куплен"}
		if name.is_empty():
			name = str(w.site(site).get("name", site))
	if name.is_empty():
		return {"reason": "нужно name — как называется место"}
	var id := "gen_p_" + ("%s|%s" % [site, name]).md5_text().left(8)
	var def := {"site": site, "name": name, "kind": k, "seller": who, "price_cp": p, "generated": true}
	if inc > 0:
		def["income_cp_day"] = inc
	var out := {"id": id, "def": def}
	if not made.is_empty():
		out["made"] = made
	return out


static func apply_make(s: GameSession, data: Dictionary, plan: Dictionary, made_site: String, made_npc: String) -> Array[String]:
	if plan.has("made"):
		keep_made(s, data, plan["made"])
	var def: Dictionary = (plan["def"] as Dictionary).duplicate(true)
	if str(def["site"]) == "new":
		if made_site.is_empty():
			return ["Продажа не открыта: место не создано"]
		def["site"] = made_site
	if str(def["seller"]) == "new":
		if made_npc.is_empty():
			return ["Продажа не открыта: продавец не создан"]
		def["seller"] = made_npc
	var gen := WorldGen.generated(s)
	var props: Dictionary = gen.get("properties", {})
	props[str(plan["id"])] = def
	gen["properties"] = props
	return ["Продаётся: %s за %s — кнопка «Имущество» у продавца" % [def["name"], Money.format(int(def["price_cp"]))]]


# --- the master's kinds, upgrades and stations (v0.7.39.8) ---------------------------------------------------------


## A kind of place the master makes: {name, income_cp_day, skill, hours, staff [{role, wage_cp_day, max}], visitors,
## upgrades [upgrade specs]} within rules.property.kind_make. {key, def, upgrades {id: def}, stations {id: def}} or
## {reason}; its upgrades are its own (`kinds` [key]), priced by the engine.
static func plan_kind(s: GameSession, data: Dictionary, spec: Dictionary) -> Dictionary:
	var km: Dictionary = cfg(data)["kind_make"]
	var name := str(spec.get("name", "")).strip_edges().to_lower().left(40)
	if name.length() < 3:
		return {"reason": "new_kind.name — как зовут такие места («школа», «рыбацкий причал»)"}
	var all_kinds := kinds(data)
	for k: String in all_kinds:
		if str(all_kinds[k].get("name", "")) == name:
			return {"reason": "вид «%s» уже есть — place_kind %s" % [name, k]}
	var key := "gen_k_" + name.md5_text().left(6)
	var def := {"name": name, "generated": true}
	var inc := int(spec.get("income_cp_day", 0)) if spec.get("income_cp_day") != null else 0
	if inc < int(km["income_cp_day"][0]) or inc > int(km["income_cp_day"][1]):
		return {"reason": "new_kind.income_cp_day — от %d до %d мм в день" % [int(km["income_cp_day"][0]), int(km["income_cp_day"][1])]}
	var staff_list: Array = []
	for h: Variant in spec.get("staff", []) if spec.get("staff") is Array else []:
		var role := str((h as Dictionary).get("role", "")).strip_edges().to_lower().left(30)
		var wage := int((h as Dictionary).get("wage_cp_day", 0))
		if role.is_empty() or wage < int(km["wage_cp_day"][0]) or wage > int(km["wage_cp_day"][1]):
			return {"reason": "new_kind.staff — {role, wage_cp_day от %d до %d, max}" % [int(km["wage_cp_day"][0]), int(km["wage_cp_day"][1])]}
		staff_list.append({"role": role, "wage_cp_day": wage, "max": clampi(int((h as Dictionary).get("max", 1)), 1, int(km["staff_max"]))})
	if staff_list.size() > int(km["staff_roles"]):
		return {"reason": "new_kind.staff — не больше %d ролей" % int(km["staff_roles"])}
	if not staff_list.is_empty():
		def["staff"] = staff_list
	if inc > 0:
		if staff_list.is_empty():
			return {"reason": "место с доходом работает руками — нужен staff (кто здесь трудится)"}
		var skill := str(spec.get("skill", ""))
		if not data["rules"]["skills"].has(skill):
			return {"reason": "new_kind.skill — навык смены героя из %s" % ", ".join(data["rules"]["skills"].keys())}
		def["income_cp_day"] = inc
		def["skill"] = skill
		def["hours"] = clampi(int(spec.get("hours", 8)), int(km["hours"][0]), int(km["hours"][1]))
	var vis := int(spec.get("visitors", 0)) if spec.get("visitors") != null else 0
	if vis > 0:
		def["trade"] = {"visitors": clampi(vis, 1, int(km["visitors"][1]))}
	var out := {"key": key, "def": def, "upgrades": {}, "stations": {}}
	var list: Array = spec.get("upgrades", []) if spec.get("upgrades") is Array else []
	if list.size() > int(km["upgrades_max"]):
		return {"reason": "new_kind.upgrades — не больше %d" % int(km["upgrades_max"])}
	for u: Variant in list:
		var up := plan_upgrade(s, data, u as Dictionary, def)
		if up.has("reason"):
			return {"reason": "улучшение «%s»: %s" % [(u as Dictionary).get("name", ""), up["reason"]]}
		up["def"]["kinds"] = [key]
		out["upgrades"][str(up["id"])] = up["def"]
		out["stations"].merge(up["stations"])
	return out


## An upgrade the master makes: {name, text, indoor, gives {rest, storage, private, station, station_new {name, tools},
## income_pct, staff_max, decay_mult, feed_mult, produce {item: qty}, produce_pct, lesson_bonus}} — only what the
## engine runs, within rules.property.upgrade_make.caps; the price and the days by its formula. `kind_def` — the
## place's kind (its income for income_pct). {id, def, stations {id: def}} or {reason}.
static func plan_upgrade(s: GameSession, data: Dictionary, spec: Dictionary, kind_def: Dictionary) -> Dictionary:
	var um: Dictionary = cfg(data)["upgrade_make"]
	var caps: Dictionary = um["caps"]
	var name := str(spec.get("name", "")).strip_edges().left(40)
	if name.length() < 3:
		return {"reason": "нужно name улучшения («Лодка», «Станок ювелира»)"}
	var g_in: Dictionary = spec.get("gives", {}) if spec.get("gives") is Dictionary else {}
	var g := {}
	var stations := {}
	var price := 0.0
	var payback := float(um["payback_days"])
	for key: String in g_in:
		var v: Variant = g_in[key]
		if v == null or (v is bool and not v):
			continue
		match key:
			"rest", "storage", "private":
				g[key] = true
				price += float(um["base_cp"][key])
			"station":
				if not CraftRules.stations(data).has(str(v)):
					return {"reason": "станции %s нет; есть: %s — или station_new {name, tools}" % [v, ", ".join(CraftRules.stations(data).keys())]}
				g["station"] = str(v)
				price += float(um["base_cp"]["station"])
			"station_new":
				var st := _plan_station(data, v)
				if st.has("reason"):
					return st
				g["station"] = str(st["id"])
				stations[str(st["id"])] = st["def"]
				price += float(um["base_cp"]["station"])
			"income_pct":
				if int(kind_def.get("income_cp_day", 0)) <= 0 and not kind_def.has("trade"):
					return {"reason": "income_pct — только месту с доходом или торговлей"}
				var pct := clampi(int(v), 1, int(caps["income_pct"]))
				g[key] = pct
				price += maxi(int(kind_def.get("income_cp_day", 0)), 20) * pct / 100.0 * payback
			"staff_max":
				if (kind_def.get("staff", []) as Array).is_empty():
					return {"reason": "staff_max — месту, где есть работники"}
				g[key] = clampi(int(v), 1, int(caps["staff_max"]))
				price += float(um["base_cp"]["staff_max"]) * int(g[key])
			"decay_mult", "feed_mult":
				g[key] = clampf(float(v), float(caps[key]), 0.9)
				price += float(um["base_cp"][key])
			"lesson_bonus":
				g[key] = clampi(int(v), 1, int(caps["lesson_bonus"]))
				price += float(um["base_cp"]["lesson_bonus"]) * int(g[key])
			"produce":
				if v is Array:  # the protocol's rows [{item_id, qty}]
					var rows := {}
					for row: Variant in v:
						if row is Dictionary:
							rows[str(row.get("item_id", ""))] = int(row.get("qty", 1))
					v = rows
				if not (v is Dictionary) or (v as Dictionary).is_empty():
					return {"reason": "produce — {вещь: штук в день}"}
				var made := {}
				for item: String in v:
					var d := ItemRules.def_of(data["items"], s.items, item)
					if d.is_empty():
						return {"reason": "вещи %s нет в каталоге — найди её через find_items" % item}
					if int(d.get("value_cp", 0)) > int(caps["produce_item_cp"]) or not str(d.get("rarity", "")) in ["", "common"]:
						return {"reason": "%s не промысел — до %s за штуку, без магии" % [d.get("name", item), Money.format(int(caps["produce_item_cp"]))]}
					made[item] = clampi(int(v[item]), 1, int(caps["produce_qty"]))
					price += int(d.get("value_cp", 0)) * int(made[item]) * payback
				g[key] = made
			"produce_pct":
				g[key] = clampi(int(v), 1, int(caps["produce_pct"]))
				price += float(um["base_cp"]["staff_max"]) * int(g[key]) / 25.0
			_:
				return {"reason": "gives.%s — движок так не умеет; можно: rest, storage, private, station, station_new, income_pct, staff_max, decay_mult, feed_mult, produce, produce_pct, lesson_bonus" % key}
	if g.is_empty():
		return {"reason": "gives пусто — что улучшение даёт по правилам"}
	var cp := clampi(roundi(price), int(um["price_cp"][0]), int(um["price_cp"][1]))
	var days := clampi(roundi(cp / float(um["cp_per_day"])), int(um["days"][0]), int(um["days"][1]))
	var def := {"name": name, "price_cp": cp, "days": days, "gives": g, "text": str(spec.get("text", "")).strip_edges().left(120), "generated": true}
	if bool(spec.get("indoor", false)):
		def["indoor"] = true
	return {"id": "gen_u_" + ("%s|%s" % [name, JSON.stringify(g)]).md5_text().left(8), "def": def, "stations": stations}


static func _plan_station(data: Dictionary, v: Variant) -> Dictionary:
	var bad := {"reason": "station_new — {name, tools [инструменты ремесла из %s]}" % ", ".join(CraftRules.cfg(data)["tools"].keys())}
	if not (v is Dictionary):
		return bad
	var name := str((v as Dictionary).get("name", "")).strip_edges().left(40)
	var tools: Array = []
	for t: Variant in (v as Dictionary).get("tools", []) if (v as Dictionary).get("tools") is Array else []:
		if not CraftRules.cfg(data)["tools"].has(str(t)):
			return bad
		tools.append(str(t))
	if name.length() < 3 or tools.is_empty():
		return bad
	var known := CraftRules.stations(data)
	for id: String in known:
		if str(known[id].get("name", "")).to_lower() == name.to_lower():
			return {"id": id, "def": known[id]}
	return {"id": "gen_st_" + name.to_lower().md5_text().left(6), "def": {"name": name, "tools": tools,
		"rent_cp_hour": int(cfg(data)["upgrade_make"]["station_rent_cp_hour"]), "generated": true}}


## Keeps what the master made — a kind (plan_kind), upgrades, stations — in this game's world: s.generated and the world.
static func keep_made(s: GameSession, data: Dictionary, made: Dictionary) -> void:
	var gen := WorldGen.generated(s)
	if made.has("key"):
		_keep(gen, data, "place_kinds", str(made["key"]), made["def"])
	for id: String in made.get("upgrades", {}):
		_keep(gen, data, "place_upgrades", id, made["upgrades"][id])
	for id: String in made.get("stations", {}):
		if not CraftRules.cfg(data)["stations"].has(id):
			_keep(gen, data, "stations", id, made["stations"][id])


static func _keep(gen: Dictionary, data: Dictionary, bucket: String, id: String, def: Dictionary) -> void:
	if not gen.has(bucket):
		gen[bucket] = {}
	gen[bucket][id] = def.duplicate(true)
	if not data["world"].has(bucket):
		data["world"][bucket] = {}
	data["world"][bucket][id] = def.duplicate(true)


## The master's upgrade asked at the hero's place (effect `upgrade`): the place the hero owns (`place_id`, "here" —
## where the hero stands). {id, def, stations, place} or {reason}.
static func plan_asked(s: GameSession, data: Dictionary, spec: Dictionary) -> Dictionary:
	var pid := str(spec.get("place_id", "here")) if spec.get("place_id") != null else "here"
	if pid == "here" or pid.is_empty():
		pid = here(s, data)
	if pid.is_empty() or not owned(s.character, pid):
		return {"reason": "улучшение — только месту героя: он стоит не в своём месте (или place_id его места)"}
	if bool(kind(s, data, pid).get("buildable", false)):
		return {"reason": "на голой земле сначала строят — улучшения потом"}
	var all_ups := ups(data)
	var mine := 0
	for u: String in all_ups:
		if (all_ups[u].get("places", []) as Array).has(pid):
			mine += 1
			if str(all_ups[u]["name"]).to_lower() == str(spec.get("name", "")).strip_edges().to_lower():
				return {"reason": "«%s» здесь уже можно заказать — кнопка в окне «Имущество»" % all_ups[u]["name"]}
	if mine >= int(cfg(data)["upgrade_make"]["per_place"]):
		return {"reason": "у места уже %d своих улучшений — больше нельзя" % mine}
	var up := plan_upgrade(s, data, spec, kind(s, data, pid))
	if up.has("reason"):
		return up
	up["def"]["places"] = [pid]
	up["place"] = pid
	return up


static func apply_asked(s: GameSession, data: Dictionary, plan: Dictionary) -> Array[String]:
	keep_made(s, data, {"upgrades": {str(plan["id"]): plan["def"]}, "stations": plan.get("stations", {})})
	var u: Dictionary = plan["def"]
	ObjectRules.note(s, str(prop(s, data, str(plan["place"])).get("site", "")), "можно заказать «%s»" % u["name"])
	return ["%s: можно заказать «%s» за %s, работы — %s (кнопка в окне «Имущество»)" % [name_of(s, data, str(plan["place"])), u["name"],
		Money.format(int(u["price_cp"])), _days(int(u["days"]))]]


## What the place's upgrades bring each working day: {item: qty} (`produce` × `produce_pct`).
static func produce(s: GameSession, data: Dictionary, id: String) -> Dictionary:
	var out := {}
	var all_ups := ups(data)
	for up: Variant in state(s.character).get(id, {}).get("upgrades", []):
		var p: Variant = all_ups.get(str(up), {}).get("gives", {}).get("produce")
		if p is Dictionary:
			for item: String in p:
				out[item] = int(out.get(item, 0)) + int(p[item])
	var mult := 1.0 + _gives(s, data, id, "produce_pct", 0.0) / 100.0
	for item: String in out:
		out[item] = roundi(int(out[item]) * mult)
	return out


## A number the place's upgrades give (`lesson_bonus`…), 0 — none.
static func bonus(s: GameSession, data: Dictionary, id: String, key: String) -> int:
	return roundi(_gives(s, data, id, key, 0.0)) if owned(s.character, id) else 0


static func _upper_first(t: String) -> String:
	return t.left(1).to_upper() + t.substr(1)
