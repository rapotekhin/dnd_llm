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
		m = {"purse_cp": 0, "stock": {}, "day": 0, "haggle_pct": 0, "haggle_failed_day": 0, "haggle_result": {}}
		s.merchants[npc_id] = m
	if int(m["day"]) < s.day:
		var pack := pack_stock(npc, data["rules"])
		var stock: Dictionary = m["stock"]
		for id: String in pack:
			stock[id] = maxi(int(stock.get(id, 0)), int(pack[id]))
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
	return int(table.get(str(clampi(attitude, -3, 3)), 100))


static func _value(s: GameSession, data: Dictionary, item_id: String) -> int:
	return int(ItemRules.def_of(data["items"], s.items, item_id).get("value_cp", 0))


## What the player pays for one item now.
static func buy_price(s: GameSession, data: Dictionary, npc_id: String, item_id: String) -> int:
	var t: Dictionary = data["rules"]["trade"]
	var value := _value(s, data, item_id)
	if value <= 0:
		return 0
	var haggle := int(merchant(s, data, npc_id)["haggle_pct"])
	var price := ceili(value * _pct(t["buy_pct_by_attitude"], s.attitude(npc_id)) * (100 - haggle) / 10000.0)
	return maxi(1, price)


## What the merchant pays for one item of the player now; 0 = not worth selling.
static func sell_price(s: GameSession, data: Dictionary, npc_id: String, item_id: String) -> int:
	var t: Dictionary = data["rules"]["trade"]
	var haggle := int(merchant(s, data, npc_id)["haggle_pct"])
	var v := _value(s, data, item_id) * float(t["sell_ratio"]) * _pct(t["sell_pct_by_attitude"], s.attitude(npc_id))
	return floori(v * (100 + haggle) / 10000.0)


## How many of an item the player can sell: owned minus what is worn or wielded.
static func sellable(s: GameSession, item_id: String) -> int:
	var c := s.character
	var worn := 0
	for slot: String in CharacterRules.SLOTS:
		if str(c.get("equipped", {}).get(slot, "")) == item_id:
			worn += 1
	return maxi(0, int(c.get("inventory", {}).get(item_id, 0)) - worn)


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
		if sellable(s, id) < qty:
			return _fail(out, "TRADE_ERR_NO_ITEM", {"item": ItemRules.display_name(items, s.items, id)})
		var price := sell_price(s, data, npc_id, id)
		if price <= 0:
			return _fail(out, "TRADE_ERR_WORTHLESS", {"item": ItemRules.display_name(items, s.items, id)})
		out["sell_cp"] += price * qty
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
			Money.format(sell_price(s, data, npc_id, id) * qty)])
		stock[id] = int(stock.get(id, 0)) + qty
		var left := int(inv[id]) - qty
		if left > 0:
			inv[id] = left
		else:
			inv.erase(id)
	var net := int(q["net_cp"])
	c["gold_cp"] = int(c["gold_cp"]) - net
	m["purse_cp"] = int(m["purse_cp"]) + net
	lines.append("Итого: %s" % ("−" + Money.format(net) if net > 0 else "+" + Money.format(-net) if net < 0 else "без доплаты"))
	return lines


## The deal for the master (turn.input of kind deal): what changed hands and who pays whom, in words — a bare
## «+2 зм» reads both ways.
static func deal_note(lines: Array[String], net_cp: int) -> String:
	var goods := lines.slice(0, lines.size() - 1)
	var money := "игрок платит торговцу %s" % Money.format(net_cp) if net_cp > 0 		else "торговец доплачивает игроку %s" % Money.format(-net_cp) if net_cp < 0 else "обмен без доплаты"
	return "; ".join(goods) + "; итог: " + money


static func haggle_dc(s: GameSession, data: Dictionary, npc_id: String) -> int:
	return _pct(data["rules"]["trade"]["haggle_dc_by_attitude"], s.attitude(npc_id))


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


## Applies a haggle check result: a success sets the percent for this visit by the margin, a failure locks
## haggling until the next day. Returns the percent won (0 on a failure).
static func apply_haggle(s: GameSession, data: Dictionary, npc_id: String, result: Dictionary) -> int:
	var m := merchant(s, data, npc_id)
	var kept := result.duplicate()
	kept.erase("note")
	m["haggle_result"] = kept
	if not bool(result["success"]):
		m["haggle_failed_day"] = s.day
		return 0
	var margin := int(result["total"]) - int(result["dc"])
	var pct := 0
	for tier: Array in data["rules"]["trade"]["haggle_tiers"]:
		if margin >= int(tier[0]):
			pct = int(tier[1])
	pct = maxi(pct, int(data["rules"]["trade"]["haggle_tiers"][0][1]))  # a natural 20 under the DC still wins
	m["haggle_pct"] = pct
	return pct


## The fact line about a haggle for the master (turn.input of kind haggle, engine.check note).
static func haggle_note(skill_name: String, result: Dictionary, pct: int) -> String:
	var roll := "%s %d против DC %d" % [skill_name, int(result["total"]), int(result["dc"])]
	if bool(result.get("blocked", false)):
		if bool(result["success"]):
			return "Торг уже состоялся (%s): скидка действует до конца визита, больше торговец не уступит." % roll
		return "Сегодня торг с этим торговцем уже провален (%s): до завтра он о скидках слышать не хочет." % roll
	if pct > 0:
		return ("Торг удался (%s): до конца визита торговец уступает %d%% на покупки и платит на %d%% больше за вещи " +
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
		var qty := sellable(s, id)
		var price := sell_price(s, data, npc_id, id)
		if qty > 0 and price > 0:
			buys.append({"item_id": id, "name": ItemRules.display_name(items, s.items, id), "qty": qty, "price_cp": price})
	return {"npc_id": npc_id, "purse_cp": int(m["purse_cp"]), "haggle_pct": int(m["haggle_pct"]),
		"haggle_locked": int(m["haggle_failed_day"]) == s.day, "stock": stock, "buys": buys}
