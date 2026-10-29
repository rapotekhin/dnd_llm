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
## building: {id, ready}, kind, staff: [{npc | cid, role, wage, serf}], rent_until, last_day, tax_day, shift_day}}.

const TAME := "tame"


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"]["property"]


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
	return cfg(data)["kinds"].get(kind_id(s, data, id), {})


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
		var g: Dictionary = cfg(data)["upgrades"].get(str(up), {}).get("gives", {})
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
	return maxi(1, roundi(price(s, data, id) * float(cfg(data)["registry"]["fee_pct"]) / 100.0))


static func tax(s: GameSession, data: Dictionary, id: String) -> int:
	return maxi(1, roundi(price(s, data, id) * float(cfg(data)["tax"]["pct"]) / 100.0))


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


static func _patch(s: GameSession, data: Dictionary, what: String, id: String, key: String, value: Variant) -> void:
	var gen := WorldGen.generated(s)
	var bucket := "site_patch" if what == "sites" else "room_patch"
	if not gen.has(bucket):
		gen[bucket] = {}
	var p: Dictionary = gen[bucket].get(id, {})
	p[key] = value
	gen[bucket][id] = p
	if data["world"].get(what, {}).has(id):
		data["world"][what][id][key] = value


static func _add_tag(s: GameSession, data: Dictionary, room_id: String, tag: String) -> void:
	var tags: Array = (WorldView.new(data["world"]).room(room_id).get("tags", []) as Array).duplicate()
	if not tags.has(tag):
		tags.append(tag)
	_patch(s, data, "rooms", room_id, "tags", tags)


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
	c["gold_cp"] = int(c["gold_cp"]) - price(s, data, id)
	state(c)[id] = _fresh(s, float(p.get("condition", 100)))
	_patch(s, data, "sites", str(p["site"]), "owner", OwnerRules.HERO)
	ObjectRules.note(s, str(p["site"]), "куплен героем у %s" % npc_name(data, seller(s, data, id)))
	var who := seller(s, data, id)
	s.remember(who, "продал герою %s" % name_of(s, data, id))
	var lines: Array[String] = ["Куплено: %s за %s — продавец %s" % [name_of(s, data, id), Money.format(price(s, data, id)), npc_name(data, who)]]
	lines.append("Без купчей место ваше лишь на словах — оформите бумагу в ратуше (пошлина %s)" % Money.format(deed_fee(s, data, id)))
	return lines


static func _fresh(s: GameSession, cond: float) -> Dictionary:
	return {"deed": false, "since": s.day, "cond": cond, "cash": 0, "debt": 0, "stock": {}, "upgrades": [], "pending": [], "building": {},
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
	c["gold_cp"] = int(c["gold_cp"]) - fee
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
	ObjectRules.note(s, str(prop(s, data, id).get("site", "")), "отобран у героя: %s" % why)
	_patch(s, data, "sites", str(prop(s, data, id).get("site", "")), "owner", seller(s, data, id))
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
	var wages := 0
	for h: Dictionary in staff(s, id):
		wages += int(cf["serfs"]["feed_cp_day"]) if bool(h.get("serf", false)) else int(h.get("wage", 0))
	if wages > 0:
		var from_till := mini(wages, int(st["cash"]))
		st["cash"] = int(st["cash"]) - from_till
		var rest := wages - from_till
		if rest > 0 and int(c.get("gold_cp", 0)) >= rest:
			c["gold_cp"] = int(c["gold_cp"]) - rest
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
			if from_till < t:
				st["debt"] = int(st.get("debt", 0)) + t - from_till
				lines.append("%s: налог %s не уплачен — долг ратуше %s" % [name_of(s, data, id), Money.format(t), Money.format(int(st["debt"]))])
			if int(st.get("debt", 0)) >= t * int(cf["tax"]["seize_weeks"]):
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
		c["gold_cp"] = int(c.get("gold_cp", 0)) + int(st["cash"])
		parts.append(Money.format(int(st["cash"])))
		st["cash"] = 0
	for item: String in st.get("stock", {}):
		ItemRules.found(c, data, s.items, item, int(st["stock"][item]))
		parts.append("%s ×%d" % [ItemRules.display_name(data["items"], s.items, item), int(st["stock"][item])])
	st["stock"] = {}
	FoodRules.sync(s, data)
	if st.has("debt") and int(st["debt"]) > 0 and int(c["gold_cp"]) > 0:
		var pay := mini(int(st["debt"]), int(c["gold_cp"]))
		c["gold_cp"] = int(c["gold_cp"]) - pay
		st["debt"] = int(st["debt"]) - pay
		parts.append("долг по налогу −%s" % Money.format(pay))
	return ["Из %s забрано: %s" % [name_of(s, data, id), ", ".join(parts)]]


## The tax debt (v0.7.39): paid by the button at the place or at the registry clerk, or by the master's `coins`
## with `settles: "tax"` (`settle_tax`). "" when it can be paid now, else a localization key.
static func pay_tax_why(s: GameSession, data: Dictionary, id: String) -> String:
	if not owned(s.character, id):
		return "PROPERTY_NOT_YOURS"
	if int(state(s.character)[id].get("debt", 0)) <= 0:
		return "PROPERTY_NO_DEBT"
	if here(s, data) != id and registry_here(s, data).is_empty():
		return "PROPERTY_TAX_WHERE"
	return "PROPERTY_NO_MONEY" if int(s.character.get("gold_cp", 0)) <= 0 else ""


## As much of the debt as the purse holds. Lines.
static func pay_tax(s: GameSession, data: Dictionary, id: String) -> Array[String]:
	var st: Dictionary = state(s.character)[id]
	var pay := mini(int(st["debt"]), int(s.character.get("gold_cp", 0)))
	s.character["gold_cp"] = int(s.character.get("gold_cp", 0)) - pay
	return _pay_debt(s, data, id, pay)


static func _pay_debt(s: GameSession, data: Dictionary, id: String, pay: int) -> Array[String]:
	var st: Dictionary = state(s.character)[id]
	st["debt"] = int(st["debt"]) - pay
	var left := int(st["debt"])
	return ["%s: налог уплачен — %s%s" % [name_of(s, data, id), Money.format(pay),
		", долг ещё %s" % Money.format(left) if left > 0 else ", долга больше нет"]]


## The tax debt of all the hero's places (the master's `coins` with `settles: "tax"` pays it).
static func tax_debt(c: Dictionary) -> int:
	var total := 0
	for id: String in state(c):
		total += int(state(c)[id].get("debt", 0))
	return total


## `amount` paid towards the tax debts, the oldest place first; the coins themselves are taken by the caller. Lines.
static func settle_tax(s: GameSession, data: Dictionary, amount: int) -> Array[String]:
	var lines: Array[String] = []
	for id: String in state(s.character):
		var st: Dictionary = state(s.character)[id]
		var pay := mini(amount, int(st.get("debt", 0)))
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
	return JobRules._chance(_shift_bonus(s, data, id), shift_dc(data), false)


## The hero's own shift in the place (the time passed): the day's income × the outcome, straight to the purse.
static func shift(s: GameSession, data: Dictionary, id: String, minutes: int) -> Array[String]:
	var c := s.character
	var st: Dictionary = state(c)[id]
	st["shift_day"] = s.day
	var full := shift_hours(s, data, id) * 60
	var day := income_day(s, data, id)
	if minutes < full:
		var part := roundi(day * float(minutes) / float(full) * 0.5)
		c["gold_cp"] = int(c.get("gold_cp", 0)) + part
		return ["Работа прервана: %s" % Money.format(part)]
	var skill := str(kind(s, data, id).get("skill", "athletics"))
	var mods := ConditionRules.check_mods(c, data, {"skill": skill})
	var dis := not (mods["disadvantage"] as Array).is_empty()
	var rolls := FeatureRules.hero_d20(s, false, dis)
	var nat: int = rolls.min() if dis else rolls[0]
	var b := _shift_bonus(s, data, id)
	var total := nat + b
	RollParts.note(s, name_of(s, data, id), rolls, nat, RollParts.skill(s, data, skill), b, shift_dc(data))
	var margin := 5 if nat == 20 else -5 if nat == 1 else total - shift_dc(data)
	var o := JobRules.outcome_for(data, margin)
	var got := roundi(day * (float(o.get("pay", 1.0)) + float(o.get("tips", 0.0))))
	c["gold_cp"] = int(c.get("gold_cp", 0)) + got
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
	s.character["gold_cp"] = int(s.character["gold_cp"]) - cost
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
	return st.has("rent_until") and int(st["rent_until"]) < (s.day if day < 0 else day)


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
	s.character["gold_cp"] = int(s.character["gold_cp"]) - wage
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
	for up: String in cfg(data)["upgrades"]:
		var u: Dictionary = cfg(data)["upgrades"][up]
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
	var u: Dictionary = cfg(data)["upgrades"].get(up, {})
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
	var u: Dictionary = cfg(data)["upgrades"][up]
	s.character["gold_cp"] = int(s.character["gold_cp"]) - int(u["price_cp"])
	var days := int(u.get("days", 0))
	if days <= 0:
		return _apply_upgrade(s, data, id, up)
	(state(s.character)[id]["pending"] as Array).append({"up": up, "ready": s.day + days})
	return ["%s: заказано «%s» за %s — готово через %s" % [name_of(s, data, id), u["name"], Money.format(int(u["price_cp"])), _days(days)]]


static func _apply_upgrade(s: GameSession, data: Dictionary, id: String, up: String) -> Array[String]:
	var u: Dictionary = cfg(data)["upgrades"][up]
	var g: Dictionary = u.get("gives", {})
	var room := main_room(s, data, id)
	if g.has("station"):
		_add_tag(s, data, room, str(g["station"]))
	if bool(g.get("rest", false)):
		_patch(s, data, "rooms", room, "safe", {"rest_cost_cp": 0})
	if bool(g.get("private", false)):
		_patch(s, data, "sites", str(prop(s, data, id)["site"]), "public", false)
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
	s.character["gold_cp"] = int(s.character["gold_cp"]) - int(bc["price_cp"])
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
	return cfg(data)["kinds"].get(k, {})


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
		if kind_id(s, data, id) == k and state(s.character)[id].has("rent_until") \
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
	s.character["gold_cp"] = int(s.character["gold_cp"]) - cost
	var id := rented(s, data, k, loc)
	if id.is_empty():
		var room := rent_room(data, k, loc)
		id = new_object(s, data, k, room, "%s (%s)" % [_upper_first(str(kind_cfg(data, k).get("name", k))), WorldView.new(data["world"]).room_short(room)])
		state(s.character)[id]["rent_until"] = s.day - 1
	var st: Dictionary = state(s.character)[id]
	st["rent_until"] = maxi(int(st["rent_until"]), s.day - 1) + days
	return ["%s — снято до дня %d, %s" % [name_of(s, data, id), int(st["rent_until"]), Money.format(cost)]]


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
		state(s.character)[id]["rent_until"] = int(shop["stalls"][room])
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
	return cfg(data)["animals"].get(monster, {})


## Animals an NPC sells: [monster id].
static func animals_of(data: Dictionary, npc_id: String) -> Array[String]:
	var out: Array[String] = []
	for m: Variant in WorldView.new(data["world"]).npc(npc_id).get("animals", []):
		if cfg(data)["animals"].has(str(m)) and data["monsters"].has(str(m)):
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


static func buy_animal(s: GameSession, data: Dictionary, npc_id: String, monster: String) -> Array[String]:
	var a := animal_cfg(data, monster)
	var m: Dictionary = data["monsters"][monster]
	s.character["gold_cp"] = int(s.character["gold_cp"]) - int(a["price_cp"])
	s.creature_counter += 1
	var cr := {"id": "c%d" % s.creature_counter, "name": str(m["name"]), "monster": monster, "state": TAME, "bound": false, "led": true,
		"owner": OwnerRules.HERO, "since": TimeRules.abs_minute(s), "hp": int(m["hp"]), "max_hp": int(m["hp"]), "xp_given": true, "fed_day": s.day}
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
			if not pid.is_empty() and int(st.get("cash", 0)) >= feed:
				st["cash"] = int(st["cash"]) - feed
			elif int(s.character.get("gold_cp", 0)) >= feed:
				s.character["gold_cp"] = int(s.character["gold_cp"]) - feed
			else:
				cr["hungry"] = int(cr.get("hungry", 0)) + 1
				continue
			cr["hungry"] = 0
			if not pid.is_empty():
				var stock: Dictionary = st.get("stock", {})
				for item: String in a.get("produce", {}):
					stock[item] = int(stock.get(item, 0)) + int(a["produce"][item])
				st["stock"] = stock
		if int(cr.get("hungry", 0)) >= int(cfg(data)["starve_days"]):
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
		if st.has("rent_until"):
			bits.append("снято до дня %d" % int(st["rent_until"]))
		if int(st.get("debt", 0)) > 0:
			bits.append("долг по налогу %s" % Money.format(int(st["debt"])))
		if not (st.get("upgrades", []) as Array).is_empty():
			bits.append("есть: " + ", ".join((st["upgrades"] as Array).map(func(u: Variant) -> String: return str(cfg(data)["upgrades"].get(str(u), {}).get("name", u)))))
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
		beasts.append("%s (%s)" % [cr["name"], "с героем" if bool(cr.get("led", false)) else WorldView.new(data["world"]).room_short(room_of(s, str(cr["id"])))])
	var out: Array[String] = []
	if not parts.is_empty():
		out.append("Имущество (окно «Имущество» на панели): " + "; ".join(parts))
	if not sale.is_empty():
		out.append("Продаётся здесь (кнопка «Имущество» у продавца): " + "; ".join(sale))
	if not beasts.is_empty():
		out.append("Животные героя: " + ", ".join(beasts))
	return ". ".join(out)


## A place the master puts on sale (effect `property`): a site of this location, its seller of the scene, the price and
## income within rules.property.make. {id, def} or {reason}; site / seller "new" — made in this turn.
static func make(s: GameSession, data: Dictionary, spec: Dictionary) -> Dictionary:
	var m: Dictionary = cfg(data)["make"]
	var site := str(spec.get("site_id", ""))
	var who := str(spec.get("seller_id", ""))
	if who != "new" and not _present(s, data, who):
		return {"reason": "продавец %s не в сцене — продаёт только тот, кто здесь (или «new» — человек create_npc этого хода)" % who}
	var k := str(spec.get("place_kind", ""))
	if not cfg(data)["kinds"].has(k):
		return {"reason": "place_kind — из %s" % ", ".join(cfg(data)["kinds"].keys())}
	var p := int(spec.get("price_cp", 0))
	if p < int(m["price_cp"][0]) or p > int(m["price_cp"][1]):
		return {"reason": "price_cp — от %s до %s" % [Money.format(int(m["price_cp"][0])), Money.format(int(m["price_cp"][1]))]}
	var inc := int(spec.get("income_cp_day", 0)) if spec.get("income_cp_day") != null else 0
	var cap := roundi(p * float(m["income_day_pct"]) / 100.0)
	if inc > cap:
		return {"reason": "income_cp_day не больше %s в день при такой цене" % Money.format(cap)}
	if inc > 0 and int(cfg(data)["kinds"][k].get("income_cp_day", 0)) <= 0:
		return {"reason": "у места вида %s нет дохода — возьми вид с доходом: %s" % [k, ", ".join(cfg(data)["kinds"].keys().filter(func(x: String) -> bool: return int(cfg(data)["kinds"][x].get("income_cp_day", 0)) > 0))]}
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
	return {"id": id, "def": def}


static func apply_make(s: GameSession, _data: Dictionary, plan: Dictionary, made_site: String, made_npc: String) -> Array[String]:
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


static func _upper_first(t: String) -> String:
	return t.left(1).to_upper() + t.substr(1)
