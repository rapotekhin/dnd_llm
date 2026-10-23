class_name TradeRules
extends RefCounted
## Trade with a merchant of the pack (roadmap v0.5.3, ADR-0008: the engine runs the deal, the master narrates it):
## - a merchant has a purse and a quantity per item (world.json `purse_cp`, `stock` as {id: qty} or a list of ids
##   with rules.trade.default_stock_qty each); the state lives in the session and restocks on a new day — the pack
##   quantities and purse come back, what the player sold stays for resale;
## - prices come from the catalog value: buying × the attitude percent × (1 − haggle), rounded up; selling at
##   sell_ratio of the value × the attitude sell percent × (1 + haggle), rounded down;
## - haggling is a Persuasion or Deception check against a DC by attitude; the margin picks the haggle percent for
##   this visit, a failure locks haggling with this merchant until the next day;
## - a deal is a cart {"buy": {id: qty}, "sell": {id: qty}} checked against both purses and stocks, then applied
##   at once.
##
## `data` = Catalog.data (rules, items, world).


## The merchant's state in the session, created from the pack on first use and restocked on a new day.
static func merchant(s: GameSession, data: Dictionary, npc_id: String) -> Dictionary:
	var npc: Dictionary = data["world"]["npcs"].get(npc_id, {})
	var m: Dictionary = s.merchants.get(npc_id, {})
	if m.is_empty():
		m = {"purse_cp": 0, "stock": {}, "day": 0, "haggle_pct": 0, "haggle_failed_day": 0, "haggle_result": {}, "sold": {}, "haggles": 0, "haggle_day": 0}
		s.merchants[npc_id] = m
	if not m.has("sold"):
		m["sold"] = {}
	if int(m["day"]) < s.day and not s.dead_npcs.has(npc_id):  # the dead restock nothing (v0.7.22.8)
		var back := int(demand_cfg(data)["recover_per_day"]) * (s.day - int(m["day"])) if int(m["day"]) > 0 else 9999
		var sold: Dictionary = m["sold"]
		for id: String in sold.keys():  # the market forgets what the hero sold (v0.7.17.1)
			sold[id] = int(sold[id]) - back
			if int(sold[id]) <= 0:
				sold.erase(id)
		var pack := pack_stock(npc, data["rules"])
		var mods := variant(s, data, npc_id)  # the world changed the goods (v0.7.17.2)
		for id: String in mods["stock"]:
			pack[id] = int(mods["stock"][id])
		var stock: Dictionary = m["stock"]
		for id: String in pack:
			stock[id] = maxi(int(stock.get(id, 0)), int(pack[id]))
		for id: String in mods["remove"]:
			stock.erase(id)
		m["purse_cp"] = maxi(int(m["purse_cp"]), int(npc.get("purse_cp", 0)))
		m["day"] = s.day
	return m


## The pack stock as {item_id: qty}.
static func pack_stock(npc: Dictionary, rules: Dictionary) -> Dictionary:
	var raw: Variant = npc.get("stock", [])
	var out := {}
	if raw is Dictionary:
		for id: String in raw:
			out[id] = int(raw[id])
	elif raw is Array:
		for id: Variant in raw:
			out[str(id)] = int(rules["trade"]["default_stock_qty"])
	return out


static func _pct(table: Dictionary, attitude: int) -> int:
	var keys: Array = table.keys().filter(func(k: Variant) -> bool: return str(k).is_valid_int()).map(func(k: Variant) -> int: return int(k))
	if keys.is_empty():
		return 100
	return int(table.get(str(clampi(attitude, keys.min(), keys.max())), 100))


static func _value(s: GameSession, data: Dictionary, item_id: String) -> int:
	return int(ItemRules.def_of(data["items"], s.items, item_id).get("value_cp", 0))


## What the player pays for one item now.
static func buy_price(s: GameSession, data: Dictionary, npc_id: String, item_id: String) -> int:
	var t: Dictionary = data["rules"]["trade"]
	var value := _value(s, data, item_id)
	if value <= 0:
		return 0
	var haggle := int(merchant(s, data, npc_id)["haggle_pct"])
	var price := ceili(value * _pct(t["buy_pct_by_attitude"], s.attitude(npc_id)) * (100 - haggle) / 10000.0 * ReputationRules.price_pct(s, data, npc_id, "buy") / 100.0
		* int(variant(s, data, npc_id)["price_pct"]) / 100.0)
	var off := SocialRules.discount(s, npc_id)  # a discount by words (v0.7.15.2)
	if off > 0:
		price = ceili(price * (100 - off) / 100.0)
	price = ceili(price * float(DevelopmentRules.effect(s.character, data, "trade", "buy_pct", 100.0)) / 100.0)  # v0.7.19.1
	return maxi(1, price)


## What the merchant pays for one item of the player now; 0 = it will not buy it or it is worth nothing.
static func sell_price(s: GameSession, data: Dictionary, npc_id: String, item_id: String) -> int:
	return _sell_unit(s, data, npc_id, item_id, 0)


## What the merchant pays for `qty` of an item: each unit sells a little cheaper (the market fills, v0.7.17.1).
static func sell_total(s: GameSession, data: Dictionary, npc_id: String, item_id: String, qty: int) -> int:
	var total := 0
	for i in qty:
		total += _sell_unit(s, data, npc_id, item_id, i)
	return total


static func _sell_unit(s: GameSession, data: Dictionary, npc_id: String, item_id: String, more: int) -> int:
	var t: Dictionary = data["rules"]["trade"]
	var d := demand_cfg(data)
	var want := demand(s, data, npc_id, item_id)
	var value := _value(s, data, item_id)
	if want == "shuns" or value <= 0:
		return 0
	var m := merchant(s, data, npc_id)
	var c := s.character  # the hero's trade skills (v0.7.19.1)
	var sold := int((m["sold"] as Dictionary).get(ItemRules.real_id(item_id), 0)) + more
	var step := float(d["saturation_step"]) * float(DevelopmentRules.effect(c, data, "trade", "saturation_mult", 1.0))
	var fill := maxf(float(d["saturation_floor"]), 1.0 - step * sold)
	var other := minf(1.0, float(d["other"]) * float(DevelopmentRules.effect(c, data, "trade", "other_mult", 1.0)))
	var v := value * float(t["sell_ratio"]) * (float(d["wanted"]) if want == "wants" else other) * fill
	v *= _pct(t["sell_pct_by_attitude"], s.attitude(npc_id)) / 100.0 * ReputationRules.price_pct(s, data, npc_id, "sell") / 100.0
	v *= (100 + int(m["haggle_pct"])) / 100.0 * float(DevelopmentRules.effect(c, data, "trade", "sell_pct", 100.0)) / 100.0
	var top := maxf(float(d["max_ratio"]), float(DevelopmentRules.effect(c, data, "trade", "max_ratio", 0.0)))
	return floori(clampf(v, value * float(d["min_ratio"]), value * top))


# --- the trader and the world (v0.7.17.2) ----------------------------------------------------------------------


## What the world's flags change at this trader (pack NPC `trade_variants` [{if_flag | if_not_flag, price_pct, stock,
## remove, news}], like the rooms' variants v0.7.14.1): {price_pct, stock {id: qty}, remove [ids], news [lines]}.
static func variant(s: GameSession, data: Dictionary, npc_id: String) -> Dictionary:
	var out := {"price_pct": 100, "stock": {}, "remove": [], "news": []}
	for v: Dictionary in data["world"]["npcs"].get(npc_id, {}).get("trade_variants", []):
		if v.has("if_flag") and not s.flags.has(str(v["if_flag"])) or v.has("if_not_flag") and s.flags.has(str(v["if_not_flag"])):
			continue
		out["price_pct"] = int(round(int(out["price_pct"]) * int(v.get("price_pct", 100)) / 100.0))
		for id: String in v.get("stock", {}):
			out["stock"][id] = int(v["stock"][id])
		(out["remove"] as Array).append_array(v.get("remove", []))
		if not str(v.get("news", "")).is_empty():
			(out["news"] as Array).append(str(v["news"]))
	return out


## A trader died: its unsold goods pass to its pack `heir` when the heir trades too. Lines.
static func on_death(s: GameSession, data: Dictionary, npc_id: String) -> Array[String]:
	var npc: Dictionary = data["world"]["npcs"].get(npc_id, {})
	var heir := str(npc.get("heir", ""))
	if not bool(npc.get("trader", false)) or heir.is_empty() or not bool(data["world"]["npcs"].get(heir, {}).get("trader", false)):
		return []
	var from := merchant(s, data, npc_id)
	var to := merchant(s, data, heir)
	for id: String in from["stock"]:
		to["stock"][id] = int(to["stock"].get(id, 0)) + int(from["stock"][id])
	from["stock"] = {}
	return ["Товар %s переходит к %s" % [npc.get("name", npc_id), data["world"]["npcs"][heir].get("name", heir)]]


# --- demand (v0.7.17.1) ---------------------------------------------------------------------------------------


static func demand_cfg(data: Dictionary) -> Dictionary:
	return data["rules"]["trade"]["demand"]


## The tags the trader buys gladly: the pack's `wants`, else the item types of a good share of its own goods.
static func wants(data: Dictionary, npc_id: String) -> Array[String]:
	var npc: Dictionary = data["world"]["npcs"].get(npc_id, {})
	var out: Array[String] = []
	if npc.has("wants"):
		for t: Variant in npc["wants"]:
			out.append(str(t))
		return out
	var stock := pack_stock(npc, data["rules"])
	var count := {}
	for id: String in stock:
		var ty := str(data["items"]["catalog"].get(id, {}).get("item_type", "gear"))
		count[ty] = int(count.get(ty, 0)) + 1
	for ty: String in count:
		if int(count[ty]) >= maxi(2, ceili(stock.size() * float(demand_cfg(data)["default_share"]))):
			out.append(ty)
	return out


static func shuns(data: Dictionary, npc_id: String) -> Array[String]:
	var out: Array[String] = []
	for t: Variant in data["world"]["npcs"].get(npc_id, {}).get("shuns", []):
		out.append(str(t))
	return out


## "wants", "shuns" or "other" for an item of the hero.
static func demand(s: GameSession, data: Dictionary, npc_id: String, item_id: String) -> String:
	var tags := ItemRules.trade_tags(ItemRules.def_of(data["items"], s.items, item_id))
	if shuns(data, npc_id).any(func(t: String) -> bool: return tags.has(t)):
		return "shuns"
	if wants(data, npc_id).any(func(t: String) -> bool: return tags.has(t)):
		return "wants"
	return "other"


## Tags in words for the panel and the master: «оружие, доспехи».
static func tag_words(data: Dictionary, tags: Array[String]) -> String:
	var names: Dictionary = demand_cfg(data)["tag_names"]
	return ", ".join(tags.map(func(t: String) -> String: return str(names.get(t, t))))


## How many of an item the player can sell: owned minus what is worn or wielded.
static func sellable(s: GameSession, item_id: String, data: Dictionary = {}) -> int:
	var c := s.character
	if not data.is_empty() and ItemRules.held_by_curse(c, data, s.items, item_id):
		return 0  # a cursed thing does not leave the hero (v0.7.12)
	var worn := 0
	for slot: String in CharacterRules.SLOTS:
		if str(c.get("equipped", {}).get(slot, "")) == item_id:
			worn += 1
	return maxi(0, int(c.get("inventory", {}).get(item_id, 0)) - worn - ContainerRules.full_bags(c, item_id))  # a full bag — empty it first (v0.7.18.2)


## Totals of a cart and the first reason it cannot go through:
## {"buy_cp", "sell_cp", "net_cp" (what the player pays, < 0 = receives), "error": key or "", "args"}.
static func quote(s: GameSession, data: Dictionary, npc_id: String, cart: Dictionary) -> Dictionary:
	var m := merchant(s, data, npc_id)
	var out := {"buy_cp": 0, "sell_cp": 0, "net_cp": 0, "error": "", "args": {}}
	var buy: Dictionary = cart.get("buy", {})
	var sell: Dictionary = cart.get("sell", {})
	var items: Dictionary = data["items"]
	for id: String in buy:
		var qty := int(buy[id])
		if qty <= 0:
			continue
		if int(m["stock"].get(id, 0)) < qty:
			return _fail(out, "TRADE_ERR_NO_STOCK", {"item": ItemRules.display_name(items, s.items, id)})
		out["buy_cp"] += buy_price(s, data, npc_id, id) * qty
	for id: String in sell:
		var qty := int(sell[id])
		if qty <= 0:
			continue
		if sellable(s, id, data) < qty:
			return _fail(out, "TRADE_ERR_NO_ITEM", {"item": ItemRules.display_name(items, s.items, id)})
		if sellable(s, id, data) - OwnerRules.held_of(s, id, npc_id) < qty:  # v0.7.22.17: it knows its own thing
			return _fail(out, "TRADE_ERR_THEIR_OWN", {"item": ItemRules.display_name(items, s.items, id)})
		var price := sell_total(s, data, npc_id, id, qty)
		if price <= 0:
			return _fail(out, "TRADE_ERR_WORTHLESS", {"item": ItemRules.display_name(items, s.items, id)})
		out["sell_cp"] += price
	out["net_cp"] = int(out["buy_cp"]) - int(out["sell_cp"])
	if int(out["buy_cp"]) == 0 and int(out["sell_cp"]) == 0:
		return _fail(out, "TRADE_ERR_EMPTY", {})
	if int(s.character.get("gold_cp", 0)) < int(out["net_cp"]):
		return _fail(out, "TRADE_ERR_NO_MONEY", {"need": Money.format(int(out["net_cp"]))})
	if int(m["purse_cp"]) < -int(out["net_cp"]):
		return _fail(out, "TRADE_ERR_MERCHANT_NO_MONEY", {"have": Money.format(int(m["purse_cp"]))})
	return out


static func _fail(out: Dictionary, key: String, args: Dictionary) -> Dictionary:
	out["error"] = key
	out["args"] = args
	return out


## Applies a cart that quote() accepted. Returns the deal lines for the chat, the log and the master.
static func execute(s: GameSession, data: Dictionary, npc_id: String, cart: Dictionary) -> Array[String]:
	var q := quote(s, data, npc_id, cart)
	assert(str(q["error"]).is_empty(), "execute() needs a cart that quote() accepts")
	var m := merchant(s, data, npc_id)
	var c := s.character
	var inv: Dictionary = c["inventory"]
	var stock: Dictionary = m["stock"]
	var items: Dictionary = data["items"]
	var lines: Array[String] = []
	var buy: Dictionary = cart.get("buy", {})
	var sell: Dictionary = cart.get("sell", {})
	for id: String in buy:
		var qty := int(buy[id])
		if qty <= 0:
			continue
		lines.append("Куплено: %s%s — %s" % [ItemRules.display_name(items, s.items, id), " ×%d" % qty if qty > 1 else "",
			Money.format(buy_price(s, data, npc_id, id) * qty)])
		stock[id] = int(stock[id]) - qty
		inv[id] = int(inv.get(id, 0)) + qty
	for id: String in sell:
		var qty := int(sell[id])
		if qty <= 0:
			continue
		lines.append("Продано: %s%s — %s" % [ItemRules.display_name(items, s.items, id), " ×%d" % qty if qty > 1 else "",
			Money.format(sell_total(s, data, npc_id, id, qty))])
		stock[ItemRules.real_id(id)] = int(stock.get(ItemRules.real_id(id), 0)) + qty  # the trader knows what it is (v0.7.12)
		var sold: Dictionary = m["sold"]  # the market fills (v0.7.17.1)
		sold[ItemRules.real_id(id)] = int(sold.get(ItemRules.real_id(id), 0)) + qty
		var left := int(inv[id]) - qty
		if left > 0:
			inv[id] = left
		else:
			inv.erase(id)
	var net := int(q["net_cp"])
	c["gold_cp"] = int(c["gold_cp"]) - net
	m["purse_cp"] = int(m["purse_cp"]) + net
	if int(m["haggle_pct"]) > 0:  # the haggle was for this deal (v0.7.17.2)
		m["haggle_pct"] = 0
		m["haggle_result"] = {}
	var src: Dictionary = DevelopmentRules.direction(data, "trade").get("sources", {})  # trade experience (v0.7.19.1)
	var turnover := (int(q["buy_cp"]) + int(q["sell_cp"])) / 100
	var dev := DevelopmentRules.add_xp(c, data, "trade", mini(int(src.get("deal_xp_max", 0)), turnover * int(src.get("deal_xp_per_gp", 0))))
	lines.append_array(dev)  # before «Итого»: deal_note takes the last line for the total
	lines.append("Итого: %s" % ("−" + Money.format(net) if net > 0 else "+" + Money.format(-net) if net < 0 else "без доплаты"))
	return lines


## The deal for the master (turn.input of kind deal): what changed hands and who pays whom, in words — a bare
## «+2 зм» reads both ways.
static func deal_note(lines: Array[String], net_cp: int) -> String:
	var goods := lines.slice(0, lines.size() - 1)
	var money := "игрок платит торговцу %s" % Money.format(net_cp) if net_cp > 0 		else "торговец доплачивает игроку %s" % Money.format(-net_cp) if net_cp < 0 else "обмен без доплаты"
	return "; ".join(goods) + "; итог: " + money


## The DC by the attitude; every haggle already made with this trader today makes the next one harder (v0.7.17.2).
static func haggle_dc(s: GameSession, data: Dictionary, npc_id: String) -> int:
	var m := merchant(s, data, npc_id)
	var done := int(m.get("haggles", 0)) if int(m.get("haggle_day", 0)) == s.day else 0
	if bool(DevelopmentRules.effect(s.character, data, "trade", "no_haggle_escalation", false)):  # «Упорство» (v0.7.19.1)
		done = 0
	return _pct(data["rules"]["trade"]["haggle_dc_by_attitude"], s.attitude(npc_id)) + done * int(data["rules"]["trade"]["haggle_escalation"])


## "" when the player may haggle with this merchant now, otherwise a localization key.
static func can_haggle(s: GameSession, data: Dictionary, npc_id: String) -> String:
	var m := merchant(s, data, npc_id)
	if int(m["haggle_failed_day"]) == s.day:
		return "TRADE_HAGGLE_LOCKED"
	if int(m["haggle_pct"]) > 0:
		return "TRADE_HAGGLE_DONE"
	return ""


## Whether a check of the turn in flight is haggling: Persuasion or Deception aimed at the merchant in trade mode.
static func is_haggle(s: GameSession, data: Dictionary, params: Dictionary) -> bool:
	var target := str(params.get("target_id", "")) if params.get("target_id") != null else ""
	var skill := str(params.get("skill", "")) if params.get("skill") != null else ""
	return s.mode == GameSession.MODE_TRADE and target == s.npc_id \
		and (data["rules"]["trade"]["haggle_skills"] as Array).has(skill)


## The haggling skill with the best bonus of the character.
static func best_skill(s: GameSession, data: Dictionary) -> String:
	var best := ""
	for skill: String in data["rules"]["trade"]["haggle_skills"]:
		if best.is_empty() or int(s.character["skills"].get(skill, 0)) > int(s.character["skills"].get(best, 0)):
			best = skill
	return best


## Applies a haggle check result: a success sets the percent for the next deal by the margin (v0.7.17.2: a deal
## each, every one harder that day), a failure locks haggling until the next day. Returns the percent (0 — failed).
static func apply_haggle(s: GameSession, data: Dictionary, npc_id: String, result: Dictionary) -> int:
	var m := merchant(s, data, npc_id)
	if int(m.get("haggle_day", 0)) != s.day:
		m["haggle_day"] = s.day
		m["haggles"] = 0
	m["haggles"] = int(m["haggles"]) + 1
	var kept := result.duplicate()
	kept.erase("note")
	m["haggle_result"] = kept
	var src: Dictionary = DevelopmentRules.direction(data, "trade").get("sources", {})
	if not bool(result["success"]):
		if bool(DevelopmentRules.effect(s.character, data, "trade", "haggle_retry", false)) and int(m.get("retry_day", 0)) != s.day:
			m["retry_day"] = s.day  # «Второй заход»: once a day the failure does not lock (v0.7.19.1)
			m["haggle_result"] = {}
		else:
			m["haggle_failed_day"] = s.day
		DevelopmentRules.add_xp(s.character, data, "trade", int(src.get("haggle_lost", 0)))
		return 0
	var margin := int(result["total"]) - int(result["dc"])
	var pct := 0
	for tier: Array in data["rules"]["trade"]["haggle_tiers"]:
		if margin >= int(tier[0]):
			pct = int(tier[1])
	pct = maxi(pct, int(data["rules"]["trade"]["haggle_tiers"][0][1]))  # a natural 20 under the DC still wins
	pct += int(DevelopmentRules.effect(s.character, data, "trade", "haggle_plus", 0))  # «Мастер торга» (v0.7.19.1)
	DevelopmentRules.add_xp(s.character, data, "trade", int(src.get("haggle_won", 0)))
	m["haggle_pct"] = pct
	return pct


## The fact line about a haggle for the master (turn.input of kind haggle, engine.check note).
static func haggle_note(skill_name: String, result: Dictionary, pct: int) -> String:
	var roll := "%s %d против DC %d" % [skill_name, int(result["total"]), int(result["dc"])]
	if bool(result.get("blocked", false)):
		if bool(result["success"]):
			return "Торг уже состоялся (%s): скидка — на ближайшую сделку, до неё торговец больше не уступит." % roll
		return "Сегодня торг с этим торговцем уже провален (%s): до завтра он о скидках слышать не хочет." % roll
	if pct > 0:
		return ("Торг удался (%s): на ближайшую сделку торговец уступает %d%% на покупки и платит на %d%% больше за вещи " +
			"игрока. Цены уже пересчитаны движком.") % [roll, pct, pct]
	return "Торг не удался (%s): цены прежние, до завтра торговец о скидках слышать не хочет." % roll


## The end of a visit: the haggled percent is gone.
static func end_visit(s: GameSession, npc_id: String) -> void:
	if s.merchants.has(npc_id):
		s.merchants[npc_id]["haggle_pct"] = 0


## The trade block of the turn snapshot: the merchant's purse, stock and what he pays for the player's things.
static func info(s: GameSession, data: Dictionary, npc_id: String) -> Dictionary:
	var m := merchant(s, data, npc_id)
	var items: Dictionary = data["items"]
	var stock: Array[Dictionary] = []
	for id: String in m["stock"]:
		if int(m["stock"][id]) > 0:
			stock.append({"item_id": id, "name": ItemRules.display_name(items, s.items, id), "qty": int(m["stock"][id]),
				"price_cp": buy_price(s, data, npc_id, id)})
	var buys: Array[Dictionary] = []
	for id: String in s.character.get("inventory", {}):
		var qty := sellable(s, id, data)
		var price := sell_price(s, data, npc_id, id)
		if qty > 0 and price > 0:
			buys.append({"item_id": id, "name": ItemRules.display_name(items, s.items, id), "qty": qty, "price_cp": price,
				"wanted": demand(s, data, npc_id, id) == "wants"})
	return {"npc_id": npc_id, "purse_cp": int(m["purse_cp"]), "haggle_pct": int(m["haggle_pct"]), "discount_pct": SocialRules.discount(s, npc_id),
		"haggle_locked": int(m["haggle_failed_day"]) == s.day, "stock": stock, "buys": buys,
		"wants": tag_words(data, wants(data, npc_id)), "shuns": tag_words(data, shuns(data, npc_id)), "news": variant(s, data, npc_id)["news"]}


# --- services (v0.7.12) ----------------------------------------------------------------------------


## The paid services of this trader (NPC `services` in the pack): [{id, cost_cp, why}] — `why` "" when it can be
## bought now, otherwise a localization key.
static func services(s: GameSession, data: Dictionary, npc_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: Variant in data["world"]["npcs"].get(npc_id, {}).get("services", []):
		var def := service_def(data, str(id))
		if def.is_empty():
			continue
		var cost := int(def["cost_cp"])
		var why := ""
		if int(s.character.get("gold_cp", 0)) < cost:
			why = "TRADE_ERR_NO_COINS"
		elif targets(s, data, str(id)).is_empty():
			why = "SERVICE_NOTHING"
		out.append({"id": str(id), "cost_cp": cost, "why": why, "name": str(def.get("name", id))})
	return out


## A service by id (v0.7.16, pillar 6): the pack's own (world.json `services`) or the rules'; {} — unknown.
static func service_def(data: Dictionary, id: String) -> Dictionary:
	var own: Dictionary = data["world"].get("services", {})
	return own.get(id, ItemRules.cfg(data)["services"].get(id, {}))


## What the service would act on now: the unknown things, the cursed ones, the items it can enchant.
static func targets(s: GameSession, data: Dictionary, id: String) -> Array[String]:
	var def := service_def(data, id)
	match str(def.get("op", "")):
		"identify":
			return ItemRules.unknown_ids(s.character)
		"lift_curse":
			return cursed_held(s, data)
		"enchant":
			return enchantable(s, data, def)
	return []


static func cursed_held(s: GameSession, data: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for id: String in s.character.get("inventory", {}):
		if ItemRules.held_by_curse(s.character, data, s.items, id):
			out.append(id)
	return out


## Catalog items of the hero the `enchant` service takes: of its `needs` kind, without its `property` yet.
static func enchantable(s: GameSession, data: Dictionary, def: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var needs := str(def.get("needs", "any"))
	for id: String in s.character.get("inventory", {}):
		var d := ItemRules.def_of(data["items"], s.items, id)
		if (needs == "any" or d.has(needs)) and data["items"]["catalog"].has(id) and not (d.get("properties", []) as Array).has(str(def["property"])):
			out.append(id)
	return out


## Buys a service (services first; `item` — the thing to enchant; `free` — a favor by words, v0.7.15.2). Lines.
static func buy_service(s: GameSession, data: Dictionary, npc_id: String, id: String, item: String = "", free: bool = false) -> Array[String]:
	var c := s.character
	var sv := service_def(data, id)
	var cost := 0 if free else int(sv["cost_cp"])
	c["gold_cp"] = int(c["gold_cp"]) - cost
	var lines: Array[String] = ["Услуга даром" if free else "Услуга: −%s" % Money.format(cost)]
	match str(sv["op"]):
		"identify":
			lines.append_array(ItemRules.identify(c, data, s.items))
		"lift_curse":
			lines.append_array(ItemRules.lift_curse(c, data, s.items))
		"enchant":
			var weapon := item if not item.is_empty() else enchantable(s, data, sv)[0]
			var base := ItemRules.def_of(data["items"], s.items, weapon)
			var props: Array = (base.get("properties", []) as Array).duplicate()
			props.append(str(sv["property"]))
			var def := {"name": "%s (%s)" % [base.get("name", weapon), sv["suffix"]], "item_type": str(base.get("item_type", "weapon")), "base": weapon,
				"rarity": str(base.get("rarity", "common")), "value_cp": int(base.get("value_cp", 0)) + int(sv["cost_cp"]), "properties": props,
				"description": str(base.get("description", "")), "generated": true}
			var new_id := ItemRules.generated_id(def)
			s.items[new_id] = def
			var inv: Dictionary = c["inventory"]
			inv[new_id] = int(inv.get(new_id, 0)) + 1
			var eq: Dictionary = c.get("equipped", {})
			var slot_of := ""
			for slot: String in eq:
				if str(eq[slot]) == weapon and slot_of.is_empty():
					slot_of = slot
			ItemRules._remove_one(c, weapon)
			if not slot_of.is_empty():
				eq[slot_of] = new_id
			lines.append("%s: %s" % [sv.get("done", "готово"), def["name"]])
	CharacterRules.refresh(c, data, s.items)
	return lines
