class_name BankRules
extends RefCounted
## The bank (roadmap v0.7.28): a financial contract is an engine concept — a deposit or a loan between the hero and a
## bank NPC (the pack's tag `bank`, the NPC's own `bank` terms, or the master's effect `bank`) with the sum, the weekly
## rate, the term and the collateral. State: c["bank"] {contracts: [{id, kind, bank, loc, term, principal, balance,
## frac, rate, start, due, last_day, collateral {kind, id, qty, name, value}, state, crime?}], vaults: {npc: {coins,
## contents, fee_day, owed}}, refused: [npc], next}. Interest by game days (TimeRules.advance → tick); an overdue
## loan grows by a penalty, then the collateral goes to the bank; a loan whose property was lost meanwhile becomes the
## crime `debt` (CrimeRules.on_debt). Every act is a button of the bank window (GameState.bank_act).

const DEPOSIT := "deposit"
const LOAN := "loan"
const OPEN := "open"
const WANTED := "wanted"


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"]["bank"]


static func state(c: Dictionary) -> Dictionary:
	if not c.has("bank"):
		c["bank"] = {"contracts": [], "vaults": {}, "refused": [], "next": 1}
	return c["bank"]


static func contracts(c: Dictionary) -> Array:
	return c["bank"]["contracts"] if c.has("bank") else []


static func contract(c: Dictionary, cid: String) -> Dictionary:
	for k: Dictionary in contracts(c):
		if str(k["id"]) == cid:
			return k
	return {}


## Open contracts of the hero (at one bank when `npc_id` is given).
static func open_of(c: Dictionary, npc_id: String = "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for k: Dictionary in contracts(c):
		if str(k["state"]) in [OPEN, WANTED] and (npc_id.is_empty() or str(k["bank"]) == npc_id):
			out.append(k)
	return out


# --- the bank and its terms -----------------------------------------------------------------------------------------


static func is_bank(s: GameSession, data: Dictionary, npc_id: String) -> bool:
	if not data["rules"].has("bank") or npc_id.is_empty():
		return false
	if WorldGen.generated(s).get("banks", {}).has(npc_id):
		return true
	var n := WorldView.new(data["world"]).npc(npc_id)
	return (n.get("tags", []) as Array).has(str(cfg(data)["tag"])) or n.has("bank")


## The bank's terms: rules.bank with the NPC's own `bank` (pack) or the master's (generated.banks) on top:
## {services, deposit_rates {term: pct}, loan_rate, ltv {property, item}, name}.
static func terms(s: GameSession, data: Dictionary, npc_id: String) -> Dictionary:
	var cf := cfg(data)
	var own: Dictionary = WorldGen.generated(s).get("banks", {}).get(npc_id, WorldView.new(data["world"]).npc(npc_id).get("bank", {}))
	var rates := {}
	for t: String in cf["deposit"]["terms"]:
		rates[t] = float(cf["deposit"]["terms"][t]["rate_pct_week"])
	if own.has("deposit_rate_pct_week"):  # one number shifts the demand rate; a term keeps its margin over it
		var d := float(own["deposit_rate_pct_week"]) - float(rates.get("demand", 0.0))
		for t: String in rates:
			rates[t] = maxf(0.0, float(rates[t]) + d)
	var ltv: Dictionary = (cf["loan"]["ltv_pct"] as Dictionary).duplicate()
	if own.has("ltv_pct"):
		for k: String in ltv:
			ltv[k] = int(own["ltv_pct"])
	return {"services": own.get("services", cf["services"]), "deposit_rates": rates,
		"loan_rate": float(own.get("loan_rate_pct_week", cf["loan"]["rate_pct_week"])), "ltv": ltv, "name": str(own.get("name", ""))}


static func offers(s: GameSession, data: Dictionary, npc_id: String, service: String) -> bool:
	return (terms(s, data, npc_id)["services"] as Array).has(service)


static func npc_name(data: Dictionary, npc_id: String) -> String:
	return str(WorldView.new(data["world"]).npc(npc_id).get("name", npc_id))


static func _present(s: GameSession, data: Dictionary, npc_id: String) -> bool:
	return SceneRules.npcs(s, data["world"], s.room_id).has(npc_id)


static func _pct(v: float) -> String:
	return ("%.2f" % v).trim_suffix("0").trim_suffix("0").trim_suffix(".").replace(".", ",") + "%"


## «0,25% в неделю».
static func rate_text(v: float) -> String:
	return "%s в неделю" % _pct(v)


static func _why_bank(s: GameSession, data: Dictionary, npc_id: String, service: String) -> String:
	if not is_bank(s, data, npc_id) or not offers(s, data, npc_id, service):
		return "BANK_NO_SERVICE"
	if not _present(s, data, npc_id):
		return "BANK_NOT_HERE"
	return ""


# --- deposits -------------------------------------------------------------------------------------------------------


static func deposit_why(s: GameSession, data: Dictionary, npc_id: String, term: String, amount: int) -> String:
	var why := _why_bank(s, data, npc_id, DEPOSIT)
	if not why.is_empty():
		return why
	if not cfg(data)["deposit"]["terms"].has(term):
		return "BANK_NO_SERVICE"
	if amount < int(cfg(data)["deposit"]["min_cp"]):
		return "BANK_TOO_LITTLE"
	if int(s.character.get("gold_cp", 0)) < amount:
		return "BANK_NO_MONEY"
	return ""


static func _new(s: GameSession, data: Dictionary, kind: String, npc_id: String, amount: int, rate: float, days: int) -> Dictionary:
	var st := state(s.character)
	var k := {"id": "bk%d" % int(st["next"]), "kind": kind, "bank": npc_id, "loc": WorldView.new(data["world"]).location_id(s.room_id),
		"principal": amount, "balance": amount, "frac": 0.0, "rate": rate, "start": s.day, "due": s.day + days if days > 0 else 0,
		"last_day": s.day, "state": OPEN}
	st["next"] = int(st["next"]) + 1
	st["contracts"].append(k)
	return k


static func deposit(s: GameSession, data: Dictionary, npc_id: String, term: String, amount: int) -> Array[String]:
	var t: Dictionary = cfg(data)["deposit"]["terms"][term]
	var rate := float(terms(s, data, npc_id)["deposit_rates"][term])
	s.character["gold_cp"] = int(s.character["gold_cp"]) - amount
	var k := _new(s, data, DEPOSIT, npc_id, amount, rate, int(t["days"]))
	k["term"] = term
	return ["%s: вклад %s %s, %s%s" % [npc_name(data, npc_id), Money.format(amount), t["name"], rate_text(rate),
		" — до дня %d" % int(k["due"]) if int(k["due"]) > 0 else ""]]


## Taken before the term ends — the sum without the interest.
static func early(s: GameSession, k: Dictionary) -> bool:
	return str(k["kind"]) == DEPOSIT and int(k["due"]) > 0 and s.day < int(k["due"])


static func withdraw_why(s: GameSession, data: Dictionary, cid: String) -> String:
	var k := contract(s.character, cid)
	if k.is_empty() or str(k["kind"]) != DEPOSIT or str(k["state"]) != OPEN:
		return "BANK_NO_CONTRACT"
	return "BANK_NOT_HERE" if not _present(s, data, str(k["bank"])) else ""


static func payout(s: GameSession, k: Dictionary) -> int:
	return int(k["principal"]) if early(s, k) else int(k["balance"])


static func withdraw(s: GameSession, data: Dictionary, cid: String) -> Array[String]:
	var k := contract(s.character, cid)
	var sum := payout(s, k)
	var was_early := early(s, k)
	s.character["gold_cp"] = int(s.character.get("gold_cp", 0)) + sum
	k["state"] = "closed"
	return ["%s: вклад забран — %s%s" % [npc_name(data, str(k["bank"])), Money.format(sum), " — досрочно, без процентов" if was_early else ""]]


# --- loans ----------------------------------------------------------------------------------------------------------


## What the hero can pledge at this bank: [{kind, id, name, value, max}] — own places with a deed, not pledged yet,
## and things that may leave the hero worth item_min_cp or more (one piece).
static func collaterals(s: GameSession, data: Dictionary, npc_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var ltv: Dictionary = terms(s, data, npc_id)["ltv"]
	if data["rules"].has("property"):
		for id: String in PropertyRules.state(s.character):
			var st: Dictionary = PropertyRules.state(s.character)[id]
			if bool(st.get("deed", false)) and str(st.get("pledged", "")).is_empty():
				var v := roundi(PropertyRules.price(s, data, id) * clampf(float(st.get("cond", 100)), 0.0, 100.0) / 100.0)
				out.append({"kind": "property", "id": id, "name": PropertyRules.name_of(s, data, id), "value": v, "max": roundi(v * int(ltv["property"]) / 100.0)})
	for id: String in (s.character.get("inventory", {}) as Dictionary).keys():
		if TradeRules.sellable(s, str(id), data) <= 0:
			continue
		var v := int(ItemRules.def_of(data["items"], s.items, str(id)).get("value_cp", 0))
		if v >= int(cfg(data)["loan"]["item_min_cp"]):
			out.append({"kind": "item", "id": str(id), "name": ItemRules.display_name(data["items"], s.items, str(id)), "value": v, "max": roundi(v * int(ltv["item"]) / 100.0)})
	return out


static func _collateral(s: GameSession, data: Dictionary, npc_id: String, ckind: String, cid: String) -> Dictionary:
	for o: Dictionary in collaterals(s, data, npc_id):
		if str(o["kind"]) == ckind and str(o["id"]) == cid:
			return o
	return {}


static func loan_why(s: GameSession, data: Dictionary, npc_id: String, ckind: String, cid: String, days: int) -> String:
	var why := _why_bank(s, data, npc_id, LOAN)
	if not why.is_empty():
		return why
	if (state(s.character)["refused"] as Array).has(npc_id):
		return "BANK_REFUSED"
	if open_of(s.character, npc_id).any(func(k: Dictionary) -> bool: return str(k["kind"]) == LOAN and s.day > int(k["due"])):
		return "BANK_OVERDUE"
	if not (cfg(data)["loan"]["terms_days"] as Array).any(func(d: Variant) -> bool: return int(d) == days):
		return "BANK_NO_SERVICE"
	var o := _collateral(s, data, npc_id, ckind, cid)
	if o.is_empty():
		return "BANK_NO_COLLATERAL"
	if int(o["max"]) < int(cfg(data)["loan"]["min_cp"]):
		return "BANK_TOO_LITTLE"
	return ""


static func loan(s: GameSession, data: Dictionary, npc_id: String, ckind: String, cid: String, days: int) -> Array[String]:
	var o := _collateral(s, data, npc_id, ckind, cid)
	var amount := int(o["max"])
	var k := _new(s, data, LOAN, npc_id, amount, float(terms(s, data, npc_id)["loan_rate"]), days)
	k["collateral"] = {"kind": ckind, "id": cid, "qty": 1, "name": str(o["name"]), "value": int(o["value"])}
	if ckind == "property":
		PropertyRules.state(s.character)[cid]["pledged"] = str(k["id"])
	else:
		var inv: Dictionary = s.character["inventory"]
		inv[cid] = int(inv.get(cid, 0)) - 1
		if int(inv[cid]) <= 0:
			inv.erase(cid)
	s.character["gold_cp"] = int(s.character.get("gold_cp", 0)) + amount
	return ["%s: кредит %s под залог — %s, %s, вернуть до дня %d" % [npc_name(data, npc_id), Money.format(amount), o["name"],
		rate_text(float(k["rate"])), int(k["due"])]]


static func repay_why(s: GameSession, data: Dictionary, cid: String) -> String:
	var k := contract(s.character, cid)
	if k.is_empty() or str(k["kind"]) != LOAN or not str(k["state"]) in [OPEN, WANTED]:
		return "BANK_NO_CONTRACT"
	if not _present(s, data, str(k["bank"])):
		return "BANK_NOT_HERE"
	return "BANK_NO_MONEY" if int(s.character.get("gold_cp", 0)) < int(k["balance"]) else ""


static func repay(s: GameSession, data: Dictionary, cid: String) -> Array[String]:
	var k := contract(s.character, cid)
	s.character["gold_cp"] = int(s.character["gold_cp"]) - int(k["balance"])
	var lines: Array[String] = ["%s: долг погашен — %s" % [npc_name(data, str(k["bank"])), Money.format(int(k["balance"]))]]
	lines.append_array(_release(s, data, k))
	if str(k["state"]) == WANTED:
		lines.append_array(CrimeRules.settle_one(s, data, str(k.get("crime", ""))))
	k["state"] = "closed"
	return lines


## The collateral back to the hero. Lines.
static func _release(s: GameSession, data: Dictionary, k: Dictionary) -> Array[String]:
	var col: Dictionary = k.get("collateral", {})
	if col.is_empty():
		return []
	if str(col["kind"]) == "property":
		var st: Dictionary = PropertyRules.state(s.character).get(str(col["id"]), {})
		if str(st.get("pledged", "")) == str(k["id"]):
			st.erase("pledged")
			return ["%s больше не в залоге" % col["name"]]
		return []
	ItemRules.found(s.character, data, s.items, str(col["id"]), int(col.get("qty", 1)))
	return ["Заклад возвращён: %s" % col["name"]]


# --- the vault ------------------------------------------------------------------------------------------------------


static func vault(c: Dictionary, npc_id: String) -> Dictionary:
	var v: Dictionary = state(c)["vaults"]
	if not v.has(npc_id):
		v[npc_id] = {"coins": 0, "contents": {}, "fee_day": 0, "owed": 0}
	return v[npc_id]


static func vault_empty(c: Dictionary, npc_id: String) -> bool:
	var v: Dictionary = state(c)["vaults"].get(npc_id, {})
	return v.is_empty() or (int(v["coins"]) <= 0 and (v["contents"] as Dictionary).is_empty())


## "in" — a thing (arg = item id) or coins (amount) into the vault; "out" — back. Unpaid fees are paid first.
static func vault_why(s: GameSession, data: Dictionary, npc_id: String, dir: String, item_id: String, amount: int) -> String:
	var why := _why_bank(s, data, npc_id, "vault")
	if not why.is_empty():
		return why
	var v := vault(s.character, npc_id)
	var gold := int(s.character.get("gold_cp", 0))
	if dir == "out" and int(v["owed"]) > gold + int(v["coins"]):
		return "BANK_OWED"
	if item_id.is_empty():
		if amount <= 0:
			return "BANK_TOO_LITTLE"
		if dir == "in" and gold < amount:
			return "BANK_NO_MONEY"
		if dir == "out" and int(v["coins"]) < amount:
			return "BANK_NO_MONEY"
		return ""
	if dir == "in":
		return "" if TradeRules.sellable(s, item_id, data) > 0 else "BANK_NO_ITEM"
	return "" if int((v["contents"] as Dictionary).get(item_id, 0)) > 0 else "BANK_NO_ITEM"


static func vault_move(s: GameSession, data: Dictionary, npc_id: String, dir: String, item_id: String, amount: int) -> Array[String]:
	var v := vault(s.character, npc_id)
	var c := s.character
	var lines: Array[String] = []
	if dir == "out" and int(v["owed"]) > 0:
		var from_vault := mini(int(v["coins"]), int(v["owed"]))
		v["coins"] = int(v["coins"]) - from_vault
		c["gold_cp"] = int(c.get("gold_cp", 0)) - (int(v["owed"]) - from_vault)
		lines.append("Уплачен долг за ячейку: %s" % Money.format(int(v["owed"])))
		v["owed"] = 0
	if vault_empty(c, npc_id) and dir == "in":
		v["fee_day"] = s.day
	if item_id.is_empty():
		var sum := mini(amount, int(v["coins"])) if dir == "out" else amount
		c["gold_cp"] = int(c.get("gold_cp", 0)) + (sum if dir == "out" else -sum)
		v["coins"] = int(v["coins"]) + (-sum if dir == "out" else sum)
		lines.append("%s: %s" % ["Взято из ячейки" if dir == "out" else "Положено в ячейку", Money.format(sum)])
		return lines
	var name := ItemRules.display_name(data["items"], s.items, item_id)
	var contents: Dictionary = v["contents"]
	if dir == "in":
		var inv: Dictionary = c["inventory"]
		inv[item_id] = int(inv.get(item_id, 0)) - 1
		if int(inv[item_id]) <= 0:
			inv.erase(item_id)
		contents[item_id] = int(contents.get(item_id, 0)) + 1
		lines.append("Положено в ячейку: %s" % name)
	else:
		contents[item_id] = int(contents[item_id]) - 1
		if int(contents[item_id]) <= 0:
			contents.erase(item_id)
		ItemRules.found(c, data, s.items, item_id, 1)
		lines.append("Взято из ячейки: %s" % name)
	return lines


# --- the days -------------------------------------------------------------------------------------------------------


## Each new day: interest on deposits and loans, the penalty and the collateral of an overdue loan, the vault fee.
## Lines only for the events (a term ended, overdue, seized, wanted, the fee unpaid).
static func tick(s: GameSession, data: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	if not data["rules"].has("bank") or not s.character.has("bank"):
		return lines
	for k: Dictionary in open_of(s.character):
		while str(k["state"]) in [OPEN, WANTED] and int(k["last_day"]) < s.day:
			k["last_day"] = int(k["last_day"]) + 1
			lines.append_array(_day(s, data, k, int(k["last_day"])))
	var fee := int(cfg(data)["vault"]["fee_cp_week"])
	for npc_id: String in state(s.character)["vaults"]:
		var v: Dictionary = state(s.character)["vaults"][npc_id]
		if vault_empty(s.character, npc_id):
			v["fee_day"] = s.day
			continue
		while s.day - int(v["fee_day"]) >= 7:
			v["fee_day"] = int(v["fee_day"]) + 7
			if int(v["coins"]) >= fee:
				v["coins"] = int(v["coins"]) - fee
			else:
				if int(v["owed"]) == 0:
					lines.append("%s: плата за ячейку не внесена — долг возьмут, когда придёте" % npc_name(data, npc_id))
				v["owed"] = int(v["owed"]) + fee
	return lines


static func _grow(k: Dictionary, pct: float) -> void:
	var f := float(k["frac"]) + float(k["balance"]) * pct / 100.0
	var whole := floori(f)
	k["balance"] = int(k["balance"]) + whole
	k["frac"] = f - whole


static func _day(s: GameSession, data: Dictionary, k: Dictionary, day: int) -> Array[String]:
	var who := npc_name(data, str(k["bank"]))
	if str(k["kind"]) == DEPOSIT:
		var rate := float(k["rate"])
		if int(k["due"]) > 0 and day > int(k["due"]):
			rate = float(terms(s, data, str(k["bank"]))["deposit_rates"].get("demand", rate))
		_grow(k, rate / 7.0)
		if int(k["due"]) > 0 and day == int(k["due"]):
			return ["%s: срок вклада вышел — %s, забрать можно без потерь" % [who, Money.format(int(k["balance"]))]]
		return []
	if str(k["state"]) == WANTED:
		for crime: Dictionary in s.crimes:  # paid or served by the law — the bank is done with it
			if str(crime["id"]) == str(k.get("crime", "")) and bool(crime["settled"]):
				k["state"] = "closed"
				return ["%s: долг закрыт по закону" % who]
		return []
	_grow(k, float(k["rate"]) / 7.0)
	var due := int(k["due"])
	if day <= due:
		return []
	var lc: Dictionary = cfg(data)["loan"]
	_grow(k, float(lc["penalty_pct_day"]))
	if day == due + 1:
		return ["%s: долг просрочен — %s, пеня %s в день; через %d дн. заберут залог" % [who, Money.format(int(k["balance"])), _pct(float(lc["penalty_pct_day"])), int(lc["grace_days"])]]
	if day < due + int(lc["grace_days"]):
		return []
	return _default(s, data, k)


## The grace is over: the collateral goes to the bank; a property lost meanwhile — the debt becomes a crime. Lines.
static func _default(s: GameSession, data: Dictionary, k: Dictionary) -> Array[String]:
	var col: Dictionary = k.get("collateral", {})
	var who := npc_name(data, str(k["bank"]))
	(state(s.character)["refused"] as Array).append(str(k["bank"]))
	if str(col.get("kind", "")) == "item":
		k["state"] = "seized"
		return ["%s оставил заклад себе: %s — долг закрыт, в долг вам больше не дают" % [who, col["name"]]]
	var id := str(col.get("id", ""))
	if PropertyRules.owned(s.character, id) and str(PropertyRules.state(s.character)[id].get("pledged", "")) == str(k["id"]):
		k["state"] = "seized"
		return PropertyRules._lose(s, data, id, "взыскано за долг (%s)" % who)
	k["state"] = WANTED
	var r := CrimeRules.on_debt(s, data, str(k["bank"]), str(k["loc"]), int(k["balance"]))
	k["crime"] = r[0]
	var lines: Array[String] = ["%s: долг не обеспечен залогом — %s, дело передано страже" % [who, Money.format(int(k["balance"]))]]
	lines.append_array(r.slice(1))
	return lines


# --- the master -----------------------------------------------------------------------------------------------------


## The hero's contracts and vaults and the banks of the scene for the master: one line, "" — none.
static func text(s: GameSession, data: Dictionary) -> String:
	if not data["rules"].has("bank"):
		return ""
	var parts: Array[String] = []
	for k: Dictionary in open_of(s.character):
		var who := npc_name(data, str(k["bank"]))
		if str(k["kind"]) == DEPOSIT:
			parts.append("вклад (%s): %s, %s" % [who, Money.format(int(k["balance"])), rate_text(float(k["rate"]))])
		else:
			parts.append("долг (%s): %s, вернуть до дня %d, залог — %s%s" % [who, Money.format(int(k["balance"])), int(k["due"]),
				k.get("collateral", {}).get("name", "нет"), " — в розыске за неуплату" if str(k["state"]) == WANTED else " — просрочен" if s.day > int(k["due"]) else ""])
	var vaults: Dictionary = s.character["bank"]["vaults"] if s.character.has("bank") else {}
	for npc_id: String in vaults:
		if not vault_empty(s.character, npc_id):
			var v: Dictionary = vaults[npc_id]
			var bits: Array[String] = []
			if int(v["coins"]) > 0:
				bits.append(Money.format(int(v["coins"])))
			if not (v["contents"] as Dictionary).is_empty():
				bits.append(ContainerRules.contents_text(data, s.items, v["contents"]))
			parts.append("ячейка (%s): %s" % [npc_name(data, npc_id), ", ".join(bits)])
	for npc_id: String in SceneRules.npcs(s, data["world"], s.room_id):
		if is_bank(s, data, npc_id):
			var t := terms(s, data, npc_id)
			var sv: Array[String] = []
			if offers(s, data, npc_id, DEPOSIT):
				sv.append("вклады %s" % ", ".join((t["deposit_rates"] as Dictionary).keys().map(func(x: Variant) -> String:
					return "%s — %s" % [cfg(data)["deposit"]["terms"][x]["name"], rate_text(float(t["deposit_rates"][x]))])))
			if offers(s, data, npc_id, LOAN):
				sv.append("кредит под залог %s, до %d%% оценки" % [rate_text(float(t["loan_rate"])), int(t["ltv"]["property"])])
			if offers(s, data, npc_id, "vault"):
				sv.append("ячейка %s в неделю" % Money.format(int(cfg(data)["vault"]["fee_cp_week"])))
			parts.append("здесь банк — %s%s: %s" % [npc_name(data, npc_id), " («%s»)" % t["name"] if not str(t["name"]).is_empty() else "", "; ".join(sv)])
	if parts.is_empty():
		return ""
	return "Банк (окно «Банк» у менялы — вклады, кредит, ячейка — кнопки): " + "; ".join(parts)


## The master's lender (effect `bank`): a scene NPC (or "new" — create_npc of this turn) takes deposits, lends against
## a collateral or keeps a vault, within rules.bank.make. {plan, summary} or {reason}.
static func make(s: GameSession, data: Dictionary, spec: Dictionary) -> Dictionary:
	var m: Dictionary = cfg(data)["make"]
	var who := str(spec.get("npc_id", ""))
	if who != "new" and not _present(s, data, who):
		return {"reason": "%s не в сцене — банком становится только тот, кто здесь (или «new» — человек create_npc этого хода)" % who}
	if who != "new" and is_bank(s, data, who):
		return {"reason": "%s уже банк — окно «Банк» в его действиях" % npc_name(data, who)}
	var services: Array = []
	for x: Variant in spec.get("services", []):
		if (cfg(data)["services"] as Array).has(str(x)) and not services.has(str(x)):
			services.append(str(x))
	if services.is_empty():
		return {"reason": "services — хотя бы одно из %s" % ", ".join(cfg(data)["services"])}
	var def := {"services": services}
	for key: String in ["loan_rate_pct_week", "deposit_rate_pct_week", "ltv_pct"]:
		if spec.get(key) == null:
			continue
		var v := float(spec[key])
		if v < float(m[key][0]) or v > float(m[key][1]):
			return {"reason": "%s — от %s до %s" % [key, m[key][0], m[key][1]]}
		def[key] = int(v) if key == "ltv_pct" else v
	if not str(spec.get("name", "")).strip_edges().is_empty():
		def["name"] = str(spec["name"]).strip_edges().left(60)
	var names := {"deposit": "вклады", "loan": "кредит под залог", "vault": "ячейка"}
	return {"plan": {"npc": who, "def": def}, "summary": "Банк — %s: %s" % ["нового человека" if who == "new" else npc_name(data, who),
		", ".join(services.map(func(x: Variant) -> String: return str(names[str(x)])))]}


static func apply_make(s: GameSession, data: Dictionary, plan: Dictionary, made_npc: String) -> Array[String]:
	var who := str(plan["npc"])
	if who == "new":
		if made_npc.is_empty():
			return ["Банк не открыт: человек не создан"]
		who = made_npc
	var gen := WorldGen.generated(s)
	var banks: Dictionary = gen.get("banks", {})
	banks[who] = (plan["def"] as Dictionary).duplicate(true)
	gen["banks"] = banks
	return ["%s теперь ведёт денежные дела — кнопка «Банк» в его действиях" % npc_name(data, who)]
