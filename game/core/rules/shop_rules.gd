class_name ShopRules
extends RefCounted
## Own trade (roadmap v0.7.29): a venue is the hero's object (ObjectRules, PropertyRules) of a trading kind — its kind
## has `trade` {visitors, tavern}: a shop, a workshop, a tavern, a market stall rented at the registry, the counter of a
## house (v0.7.39.5: each an object of its own). The hero puts own things on its shelf at a price (a percent of the
## value); buyers come by days while its staff stands there (more hands — more buyers, PropertyRules.staff_mult), and on
## the hero's own shifts. A charter of the location (from the registry) makes it lawful — a tax on the takings,
## wholesale at the suppliers; without it the guard fines. The merchant's reputation of a location scales the buyers.
## State: c["shop"] {venues: {vid: {stock, prices, cash, last_day, last}}, charters: {loc: day}, rep: {loc: float}};
## a venue's id is its property id. Every act is a button (GameState.shop_act).


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"]["shop"]


static func state(c: Dictionary) -> Dictionary:
	if not c.has("shop"):
		c["shop"] = {"venues": {}, "charters": {}, "rep": {}}
	return c["shop"]


static func _part(c: Dictionary, key: String) -> Dictionary:
	return c["shop"].get(key, {}) if c.has("shop") else {}


static func venue(c: Dictionary, vid: String) -> Dictionary:
	var v: Dictionary = state(c)["venues"]
	if not v.has(vid):
		v[vid] = {"stock": {}, "prices": {}, "cash": 0, "last_day": 0, "last": {}}
	return v[vid]


## Takes up to `sum` out of a venue's till (the tax of its place). What was taken.
static func from_till(c: Dictionary, vid: String, sum: int) -> int:
	var v: Dictionary = _part(c, "venues").get(vid, {})
	var n := mini(sum, int(v.get("cash", 0)))
	if n > 0:
		v["cash"] = int(v["cash"]) - n
	return n


# --- venues ---------------------------------------------------------------------------------------------------------


## The trade of a hero's object: its kind's `trade` ({} — it does not trade).
static func kind_cfg(s: GameSession, data: Dictionary, vid: String) -> Dictionary:
	if not data["rules"].has("shop") or not PropertyRules.owned(s.character, vid):
		return {}
	return PropertyRules.kind(s, data, vid).get("trade", {})


static func room_of(s: GameSession, data: Dictionary, vid: String) -> String:
	return PropertyRules.main_room(s, data, vid)


static func loc_of(s: GameSession, data: Dictionary, vid: String) -> String:
	return WorldView.new(data["world"]).location_id(room_of(s, data, vid))


static func name_of(s: GameSession, data: Dictionary, vid: String) -> String:
	return PropertyRules.name_of(s, data, vid)


## The hero's venues: the objects of trading kinds (a lapsed stall keeps its shelf until taken back).
static func venues(s: GameSession, data: Dictionary) -> Array[String]:
	var out: Array[String] = []
	if not data["rules"].has("shop"):
		return out
	for id: String in PropertyRules.state(s.character):
		if not kind_cfg(s, data, id).is_empty():
			out.append(id)
	return out


## The hero's venue in this room ("" — none).
static func here(s: GameSession, data: Dictionary) -> String:
	for vid: String in venues(s, data):
		if room_of(s, data, vid) == s.room_id or vid == PropertyRules.here(s, data):
			return vid
	return ""


## Who sells there by days: the staff of the object, while a rented one is rented.
static func staffed(s: GameSession, vid: String, day: int = -1) -> bool:
	return not PropertyRules.staff(s, vid).is_empty() and not PropertyRules.lapsed(s, vid, day)


## A venue with goods on its shelf: its place earns by sales, not by the flat income.
static func active(s: GameSession, vid: String) -> bool:
	var v: Dictionary = _part(s.character, "venues").get(vid, {})
	return not v.is_empty() and not (v["stock"] as Dictionary).is_empty()


# --- the shelf and the prices ---------------------------------------------------------------------------------------


static func value(s: GameSession, data: Dictionary, item_id: String) -> int:
	return int(ItemRules.def_of(data["items"], s.items, item_id).get("value_cp", 0))


static func price_pct(s: GameSession, data: Dictionary, vid: String, item_id: String) -> int:
	return int(venue(s.character, vid)["prices"].get(item_id, cfg(data)["price_pct"]["default"]))


static func price(s: GameSession, data: Dictionary, vid: String, item_id: String) -> int:
	return Price.share(value(s, data, item_id), price_pct(s, data, vid, item_id), 1)


static func is_food(data: Dictionary, item_id: String) -> bool:
	var r: Dictionary = data["rules"]
	return r["hero_effects"]["camp"]["food"].has(item_id) or r.get("consumables", {}).get(item_id, {}).has("meal") or (cfg(data)["tavern"]["drinks"] as Array).has(item_id)


static func _reach(s: GameSession, data: Dictionary, vid: String) -> String:
	if not venues(s, data).has(vid):
		return "SHOP_NO_VENUE"
	if room_of(s, data, vid) != s.room_id and here(s, data) != vid:
		return "SHOP_NOT_HERE"
	return ""


static func put_why(s: GameSession, data: Dictionary, vid: String, item_id: String) -> String:
	var why := _reach(s, data, vid)
	if not why.is_empty():
		return why
	if TradeRules.sellable(s, item_id, data) <= 0 or value(s, data, item_id) <= 0:
		return "SHOP_NO_ITEM"
	if bool(kind_cfg(s, data, vid).get("tavern", false)) and not is_food(data, item_id):
		return "SHOP_TAVERN_FOOD"
	return ""


static func put(s: GameSession, data: Dictionary, vid: String, item_id: String, qty: int) -> Array[String]:
	var n := mini(qty, TradeRules.sellable(s, item_id, data))
	var inv: Dictionary = s.character["inventory"]
	inv[item_id] = int(inv[item_id]) - n
	if int(inv[item_id]) <= 0:
		inv.erase(item_id)
	var v := venue(s.character, vid)
	if int(v["last_day"]) == 0:
		v["last_day"] = s.day
	var stock: Dictionary = v["stock"]
	stock[item_id] = int(stock.get(item_id, 0)) + n
	return ["Выставлено: %s ×%d — %s" % [ItemRules.display_name(data["items"], s.items, item_id), n, name_of(s, data, vid)]]


static func take_why(s: GameSession, data: Dictionary, vid: String, item_id: String) -> String:
	var why := _reach(s, data, vid)
	if not why.is_empty():
		return why
	return "" if int(venue(s.character, vid)["stock"].get(item_id, 0)) > 0 else "SHOP_NO_ITEM"


static func take(s: GameSession, data: Dictionary, vid: String, item_id: String) -> Array[String]:
	var stock: Dictionary = venue(s.character, vid)["stock"]
	var n := int(stock[item_id])
	stock.erase(item_id)
	venue(s.character, vid)["prices"].erase(item_id)
	ItemRules.found(s.character, data, s.items, item_id, n)
	return ["Снято с прилавка: %s ×%d" % [ItemRules.display_name(data["items"], s.items, item_id), n]]


## One step up (+1) or down (−1) of the price percent within rules.shop.price_pct. "" or a key.
static func price_step_why(s: GameSession, data: Dictionary, vid: String, item_id: String, dir: int) -> String:
	if not _reach(s, data, vid).is_empty() or int(venue(s.character, vid)["stock"].get(item_id, 0)) <= 0:
		return "SHOP_NO_ITEM"
	var p: Dictionary = cfg(data)["price_pct"]
	var next := price_pct(s, data, vid, item_id) + dir * int(p["step"])
	return "" if next >= int(p["min"]) and next <= int(p["max"]) else "SHOP_PRICE_LIMIT"


static func price_step(s: GameSession, data: Dictionary, vid: String, item_id: String, dir: int) -> void:
	venue(s.character, vid)["prices"][item_id] = price_pct(s, data, vid, item_id) + dir * int(cfg(data)["price_pct"]["step"])


static func collect_why(s: GameSession, data: Dictionary, vid: String) -> String:
	var why := _reach(s, data, vid)
	if not why.is_empty():
		return why
	return "" if int(venue(s.character, vid)["cash"]) > 0 else "SHOP_NO_CASH"


static func collect(s: GameSession, _data: Dictionary, vid: String) -> Array[String]:
	var v := venue(s.character, vid)
	var sum := int(v["cash"])
	v["cash"] = 0
	Ledger.add(s, sum, "shop:collect")
	return ["Выручка забрана: %s" % Money.format(sum)]


# --- the market: sales, the charter, the reputation -----------------------------------------------------------------


static func has_charter(s: GameSession, loc: String) -> bool:
	return _part(s.character, "charters").has(loc)


static func rep(s: GameSession, loc: String) -> float:
	return float(_part(s.character, "rep").get(loc, 0.0))


static func rep_word(data: Dictionary, r: float) -> String:
	var words: Array = cfg(data)["reputation"]["words"]
	var w := Scale.row(words, r)
	return str(w[1] if not w.is_empty() else words[0][1])


static func _rep_add(s: GameSession, data: Dictionary, loc: String, d: float) -> void:
	var rc: Dictionary = cfg(data)["reputation"]
	state(s.character)["rep"][loc] = clampf(rep(s, loc) + d, float(rc["min"]), float(rc["max"]))


## The chance a buyer takes a thing at this price ratio: linear between the rules.shop.buy_chance points.
static func buy_chance(data: Dictionary, ratio: float) -> float:
	var pts: Array = cfg(data)["buy_chance"]
	if ratio <= float(pts[0][0]):
		return float(pts[0][1])
	for i in range(1, pts.size()):
		if ratio <= float(pts[i][0]):
			var a: Array = pts[i - 1]
			var b: Array = pts[i]
			return lerpf(float(a[1]), float(b[1]), (ratio - float(a[0])) / (float(b[0]) - float(a[0])))
	return float(pts[pts.size() - 1][1])


## The pack traders of the location who sell the thing too: buyers go to them first.
static func _rivals(s: GameSession, data: Dictionary, loc: String) -> Dictionary:
	var out := {}
	for id: String in CrimeRules.people_of(data, loc):
		if s.dead_npcs.has(id):
			continue
		for item: String in TradeRules.pack_stock(WorldView.new(data["world"]).npc(id), data["rules"]):
			out[item] = true
	return out


static func visitors(s: GameSession, data: Dictionary, vid: String, base: int) -> int:
	var mult := clampf(1.0 + rep(s, loc_of(s, data, vid)) * float(cfg(data)["reputation"]["visitors_per_point"]), 0.5, 1.5)
	mult *= 1.0 + PropertyRules._gives(s, data, vid, "income_pct", 0.0) / 100.0
	return maxi(1, roundi(base * mult))


## `n` buyers at the shelf: each picks a thing and buys it by the price. {sold {id: qty}, revenue}; the shelf shrinks.
static func sell_round(s: GameSession, data: Dictionary, vid: String, n: int) -> Dictionary:
	var v := venue(s.character, vid)
	var stock: Dictionary = v["stock"]
	var loc := loc_of(s, data, vid)
	var rivals := _rivals(s, data, loc)
	var tavern := bool(kind_cfg(s, data, vid).get("tavern", false))
	var rc: Dictionary = cfg(data)["reputation"]
	var sold := {}
	var revenue := 0
	for i in n:
		var ids: Array[String] = []
		var weights: Array[float] = []
		var total := 0.0
		for id: String in stock:
			if int(stock[id]) <= 0 or (tavern and not is_food(data, id)):
				continue
			var w := float(cfg(data)["competition"]) if rivals.has(id) else float(cfg(data)["scarce"])
			ids.append(id)
			weights.append(w)
			total += w
		if ids.is_empty():
			break
		var r := s.rng.randf() * total
		var pick := ids[ids.size() - 1]
		for j in ids.size():
			r -= weights[j]
			if r <= 0.0:
				pick = ids[j]
				break
		var ratio := float(price_pct(s, data, vid, pick)) / 100.0
		if s.rng.randf() >= buy_chance(data, ratio):
			continue
		stock[pick] = int(stock[pick]) - 1
		if int(stock[pick]) <= 0:
			stock.erase(pick)
		sold[pick] = int(sold.get(pick, 0)) + 1
		revenue += price(s, data, vid, pick)
		var d := float(rc["fair"]) if ratio <= float(rc["fair_ratio"]) else float(rc["dear"]) if ratio >= float(rc["dear_ratio"]) else 0.0
		for q: Variant in ItemRules.def_of(data["items"], s.items, pick).get("properties", []):
			d += float(rc["quality"].get(str(q), 0.0))
		_rep_add(s, data, loc, d)
	return {"sold": sold, "revenue": revenue}


static func _sold_text(s: GameSession, data: Dictionary, sold: Dictionary) -> String:
	var parts: Array[String] = []
	for id: String in sold:
		parts.append("%s ×%d" % [ItemRules.display_name(data["items"], s.items, id), int(sold[id])])
	return ", ".join(parts)


## The tax on the takings when the hero has the charter; the rest. [kept, tax].
static func _after_tax(s: GameSession, data: Dictionary, loc: String, revenue: int) -> Array[int]:
	if not has_charter(s, loc):
		return [revenue, 0]
	var tax := roundi(revenue * float(cfg(data)["charter"]["tax_pct"]) / 100.0)
	return [revenue - tax, tax]


static func shift_why(s: GameSession, data: Dictionary, vid: String) -> String:
	var unfree := EncounterRules.unfree_why(s)
	if not unfree.is_empty():
		return unfree
	var why := _reach(s, data, vid)
	if not why.is_empty():
		return why
	if PropertyRules.lapsed(s, vid):
		return "SHOP_STALL_LAPSED"
	if not active(s, vid):
		return "SHOP_EMPTY"
	return "SHOP_DONE_TODAY" if int(venue(s.character, vid).get("shift_day", 0)) == s.day else ""


static func shift_hours(data: Dictionary) -> int:
	return int(cfg(data)["shift"]["hours"])


static func _shift_bonus(s: GameSession, data: Dictionary) -> int:
	return CheckEngine.bonus_for(s.character, {"skill": str(cfg(data)["shift"]["skill"])}) + DifficultyRules.bonus(s, data)


static func shift_dc(data: Dictionary) -> int:
	return int(data["rules"]["dc_tiers"][str(cfg(data)["shift"]["dc_tier"])])


static func shift_chance(s: GameSession, data: Dictionary) -> int:
	return Roll.chance(_shift_bonus(s, data), shift_dc(data), false)


## The hero behind the counter (the time passed): a check, its outcome × the shift's buyers, the takings to the purse.
static func shift(s: GameSession, data: Dictionary, vid: String, minutes: int) -> Array[String]:
	var c := s.character
	venue(c, vid)["shift_day"] = s.day
	var sc: Dictionary = cfg(data)["shift"]
	var base := visitors(s, data, vid, int(sc["visitors"]))
	var lines: Array[String] = []
	if minutes < shift_hours(data) * 60:
		base = roundi(base * float(minutes) / float(shift_hours(data) * 60) * 0.5)
		lines.append("Торговля прервана")
	else:
		var skill := str(sc["skill"])
		var ro := Roll.hero(s, data, {"what": name_of(s, data, vid), "skill": skill, "dc": shift_dc(data)})
		var nat := int(ro["nat"])
		var b := int(ro["bonus"])
		var o := JobRules.outcome_for(data, int(ro["margin"]))
		base = roundi(base * (float(o.get("pay", 1.0)) + float(o.get("tips", 0.0)) * 2.0))
		lines.append("%s: %s %d + %d = %d против Сл %d — %s" % [name_of(s, data, vid), CraftRules.tr_skill(data, skill), nat, b, nat + b, shift_dc(data), o["name"]])
	var r := sell_round(s, data, vid, base)
	var loc := loc_of(s, data, vid)
	var t := _after_tax(s, data, loc, int(r["revenue"]))
	Ledger.add(s, t[0], "shop:shift")
	if (r["sold"] as Dictionary).is_empty():
		lines.append("Покупателей на ваш товар не нашлось")
	else:
		lines.append("Продано: %s — выручка %s%s" % [_sold_text(s, data, r["sold"]), Money.format(t[0]), " (налог %s)" % Money.format(t[1]) if t[1] > 0 else ""])
		var src: Dictionary = DevelopmentRules.direction(data, "trade").get("sources", {})  # the hero's own counter (v0.7.39)
		var xp := mini(int(src.get("shift_xp_max", 0)), int(r["revenue"]) / 100 * int(src.get("shift_xp_per_gp", 0)))
		lines.append_array(DevelopmentRules.add_xp(c, data, "trade", xp))
	lines.append_array(_fine(s, data, loc))
	return lines


## Trade without the charter where the law is: the guard may fine. Lines.
static func _fine(s: GameSession, data: Dictionary, loc: String) -> Array[String]:
	var ch: Dictionary = cfg(data)["charter"]
	if has_charter(s, loc) or CrimeRules.law(data, loc).is_empty() or s.rng.randf() >= float(ch["fine_chance"]):
		return []
	var fine := mini(int(ch["fine_cp"]), int(s.character.get("gold_cp", 0)))
	Ledger.add(s, -fine, "shop:fine")
	return ["Стража: торговля без грамоты — штраф %s" % Money.format(fine)]


## Each new day: a staffed venue sells to its buyers, the takings to its till; a tavern's lodgers. Lines (a summary).
static func tick(s: GameSession, data: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	if not data["rules"].has("shop") or not s.character.has("shop"):
		return lines
	for vid: String in venues(s, data):
		var v := venue(s.character, vid)
		if int(v["last_day"]) == 0:
			v["last_day"] = s.day
		var sold := {}
		var kept := 0
		var days := 0
		while int(v["last_day"]) < s.day:
			v["last_day"] = int(v["last_day"]) + 1
			if not PropertyRules.owned(s.character, vid) or not staffed(s, vid, int(v["last_day"])):
				continue
			days += 1
			var k := kind_cfg(s, data, vid)
			var r := sell_round(s, data, vid, roundi(visitors(s, data, vid, int(k.get("visitors", 0))) * PropertyRules.staff_mult(data, PropertyRules.staff(s, vid).size())))
			var rev := int(r["revenue"])
			if bool(k.get("tavern", false)) and PropertyRules._gives(s, data, vid, "rest", 0.0) > 0.0:  # beds to let
				var tc: Dictionary = cfg(data)["tavern"]
				rev += roundi(visitors(s, data, vid, int(k["visitors"])) * float(tc["lodgers_share"])) * int(tc["lodging_cp"])
			var t := _after_tax(s, data, loc_of(s, data, vid), rev)
			v["cash"] = int(v["cash"]) + t[0]
			kept += t[0]
			for id: String in r["sold"]:
				sold[id] = int(sold.get(id, 0)) + int(r["sold"][id])
			lines.append_array(_fine_till(s, data, vid))
		if days > 0:
			v["last"] = {"day": s.day, "sold": sold, "cash": kept}
			if kept > 0:
				lines.append("%s: продано за %s — %s; выручка %s в кассе" % [name_of(s, data, vid), _days_text(days), _sold_text(s, data, sold) if not sold.is_empty() else "ночлег", Money.format(kept)])
	return lines


static func _fine_till(s: GameSession, data: Dictionary, vid: String) -> Array[String]:
	var loc := loc_of(s, data, vid)
	var ch: Dictionary = cfg(data)["charter"]
	if has_charter(s, loc) or CrimeRules.law(data, loc).is_empty() or s.rng.randf() >= float(ch["fine_chance"]):
		return []
	var v := venue(s.character, vid)
	var fine := mini(int(ch["fine_cp"]), int(v["cash"]))
	v["cash"] = int(v["cash"]) - fine
	return ["%s: стража взяла штраф за торговлю без грамоты — %s" % [name_of(s, data, vid), Money.format(fine)]] if fine > 0 else []


static func _days_text(n: int) -> String:
	return "день" if n == 1 else "%d %s" % [n, "дня" if n % 10 in [2, 3, 4] and not n % 100 in [12, 13, 14] else "дней"]


# --- the registry: the charter and the stalls -----------------------------------------------------------------------


static func _registry_here(s: GameSession, data: Dictionary, npc_id: String) -> String:
	if not data["rules"].has("shop") or not PropertyRules.is_registry(data, npc_id):
		return "SHOP_NO_SERVICE"
	return "" if SceneRules.npcs(s, data["world"], s.room_id).has(npc_id) else "SHOP_NOT_HERE"


static func charter_why(s: GameSession, data: Dictionary, npc_id: String) -> String:
	var why := _registry_here(s, data, npc_id)
	if not why.is_empty():
		return why
	if has_charter(s, WorldView.new(data["world"]).location_id(s.room_id)):
		return "SHOP_HAS_CHARTER_ERR"
	return "SHOP_NO_MONEY" if int(s.character.get("gold_cp", 0)) < int(cfg(data)["charter"]["fee_cp"]) else ""


static func charter(s: GameSession, data: Dictionary, _npc_id: String) -> Array[String]:
	var loc := WorldView.new(data["world"]).location_id(s.room_id)
	var fee := int(cfg(data)["charter"]["fee_cp"])
	Ledger.add(s, -fee, "shop:charter")
	state(s.character)["charters"][loc] = s.day
	var lname := str(WorldView.new(data["world"]).location(loc).get("name", loc))
	var doc := {"id": "gen_charter_" + loc, "name": "Торговая грамота: %s" % lname, "item_type": "gear", "value_cp": 0, "weight": 0,
		"description": "Свидетельство ратуши: владелец торгует законно в %s; налог %d%% с выручки." % [lname, int(cfg(data)["charter"]["tax_pct"])]}
	s.items[doc["id"]] = doc
	ItemRules.found(s.character, data, s.items, doc["id"], 1)
	return ["Торговая грамота: %s — пошлина %s, налог %d%% с выручки; опт у поставщиков открыт" % [lname, Money.format(fee), int(cfg(data)["charter"]["tax_pct"])]]


# --- suppliers ------------------------------------------------------------------------------------------------------


static func is_supplier(s: GameSession, data: Dictionary, npc_id: String) -> bool:
	if not data["rules"].has("shop"):
		return false
	return WorldGen.generated(s).get("suppliers", {}).has(npc_id) or WorldView.new(data["world"]).npc(npc_id).has("wholesale")


static func _supply(s: GameSession, data: Dictionary, npc_id: String) -> Dictionary:
	return WorldGen.generated(s).get("suppliers", {}).get(npc_id, WorldView.new(data["world"]).npc(npc_id).get("wholesale", {}))


## The supplier's goods: its own list (the master's) or the trader's pack stock.
static func goods(s: GameSession, data: Dictionary, npc_id: String) -> Array[String]:
	var out: Array[String] = []
	var own: Array = _supply(s, data, npc_id).get("goods", [])
	if own.is_empty():
		own = TradeRules.pack_stock(WorldView.new(data["world"]).npc(npc_id), data["rules"]).keys()
	for id: Variant in own:
		if value(s, data, str(id)) > 0:
			out.append(str(id))
	return out


static func wholesale_price(s: GameSession, data: Dictionary, npc_id: String, item_id: String) -> int:
	return Price.ceiled(Price.mod(Price.start(value(s, data, item_id)), "опт", int(_supply(s, data, npc_id).get("pct", cfg(data)["wholesale"]["pct"]))), 1)


static func lot(data: Dictionary) -> int:
	return int(cfg(data)["wholesale"]["lot"])


static func wholesale_why(s: GameSession, data: Dictionary, npc_id: String, item_id: String) -> String:
	if not is_supplier(s, data, npc_id) or not goods(s, data, npc_id).has(item_id):
		return "SHOP_NO_SERVICE"
	if not SceneRules.npcs(s, data["world"], s.room_id).has(npc_id):
		return "SHOP_NOT_HERE"
	if not has_charter(s, WorldView.new(data["world"]).location_id(s.room_id)):
		return "SHOP_NEED_CHARTER"
	return "SHOP_NO_MONEY" if int(s.character.get("gold_cp", 0)) < wholesale_price(s, data, npc_id, item_id) * lot(data) else ""


static func wholesale(s: GameSession, data: Dictionary, npc_id: String, item_id: String) -> Array[String]:
	var cost := wholesale_price(s, data, npc_id, item_id) * lot(data)
	Ledger.add(s, -cost, "shop:wholesale")
	ItemRules.found(s.character, data, s.items, item_id, lot(data))
	return ["Опт: %s ×%d — %s (%s)" % [ItemRules.display_name(data["items"], s.items, item_id), lot(data), Money.format(cost), WorldView.new(data["world"]).npc(npc_id).get("name", npc_id)]]


# --- the master -----------------------------------------------------------------------------------------------------


static func text(s: GameSession, data: Dictionary) -> String:
	if not data["rules"].has("shop"):
		return ""
	var parts: Array[String] = []
	for loc: String in _part(s.character, "charters"):
		parts.append("грамота: %s" % WorldView.new(data["world"]).location(loc).get("name", loc))
	for loc: String in _part(s.character, "rep"):
		parts.append("слава торговца (%s): %s" % [WorldView.new(data["world"]).location(loc).get("name", loc), rep_word(data, rep(s, loc))])
	for vid: String in venues(s, data):
		var v: Dictionary = _part(s.character, "venues").get(vid, {})
		var n := 0
		for id: String in v.get("stock", {}):
			n += int(v["stock"][id])
		parts.append("%s — на полках %d шт.%s%s" % [name_of(s, data, vid), n, ", в кассе %s" % Money.format(int(v["cash"])) if int(v.get("cash", 0)) > 0 else "",
			", торгует работник" if staffed(s, vid) else ""])
	for npc_id: String in SceneRules.npcs(s, data["world"], s.room_id):
		if is_supplier(s, data, npc_id):
			parts.append("здесь оптом продаёт %s (%d%% цены, нужна грамота)" % [WorldView.new(data["world"]).npc(npc_id).get("name", npc_id), int(_supply(s, data, npc_id).get("pct", cfg(data)["wholesale"]["pct"]))])
	if parts.is_empty():
		return ""
	return "Своя торговля (окно «Лавка», грамота и прилавок у писаря, «Опт» у поставщика — кнопки): " + "; ".join(parts)


## The master's supplier (effect `supplier`): a scene NPC sells wholesale to a charter holder. {plan, summary} or {reason}.
static func make(s: GameSession, data: Dictionary, spec: Dictionary) -> Dictionary:
	var m: Dictionary = cfg(data)["make"]
	var who := str(spec.get("npc_id", ""))
	if not SceneRules.npcs(s, data["world"], s.room_id).has(who):
		return {"reason": "%s не в сцене — поставщиком становится только тот, кто здесь" % who}
	if is_supplier(s, data, who):
		return {"reason": "%s уже продаёт оптом — кнопка «Опт» в его действиях" % WorldView.new(data["world"]).npc(who).get("name", who)}
	var list: Array = []
	for id: Variant in spec.get("goods", []):
		if not data["items"]["catalog"].has(str(id)) and not s.items.has(str(id)):
			return {"reason": "нет вещи %s в каталоге — сначала find_items" % id}
		if not list.has(str(id)):
			list.append(str(id))
	if list.size() > int(m["max_goods"]):
		return {"reason": "goods — не больше %d" % int(m["max_goods"])}
	if list.is_empty() and TradeRules.pack_stock(WorldView.new(data["world"]).npc(who), data["rules"]).is_empty():
		return {"reason": "у %s нет своих товаров — перечисли goods" % who}
	var pct := int(spec.get("pct", cfg(data)["wholesale"]["pct"])) if spec.get("pct") != null else int(cfg(data)["wholesale"]["pct"])
	if pct < int(m["pct"][0]) or pct > int(m["pct"][1]):
		return {"reason": "pct — от %d до %d" % [int(m["pct"][0]), int(m["pct"][1])]}
	var def := {"pct": pct}
	if not list.is_empty():
		def["goods"] = list
	return {"plan": {"npc": who, "def": def}, "summary": "Опт — %s: %d%% цены" % [WorldView.new(data["world"]).npc(who).get("name", who), pct]}


static func apply_make(s: GameSession, data: Dictionary, plan: Dictionary) -> Array[String]:
	var gen := WorldGen.generated(s)
	var sup: Dictionary = gen.get("suppliers", {})
	sup[str(plan["npc"])] = (plan["def"] as Dictionary).duplicate(true)
	gen["suppliers"] = sup
	return ["%s продаёт оптом торговцам с грамотой — кнопка «Опт» в его действиях" % WorldView.new(data["world"]).npc(str(plan["npc"])).get("name", plan["npc"])]
