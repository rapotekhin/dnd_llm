class_name SocialRules
extends RefCounted
## Social checks by the NPC's SRD template (roadmap v0.7.15.1, «Социальный режим 2.0»): the DC of Deception,
## Intimidation, Persuasion and Insight against a pack NPC comes from what the NPC is, not only from the master.
## - against: 5e contests — a lie meets the NPC's Insight, a threat its Wisdom save, a plea its Wisdom (how set
##   in its ways), reading it — its Deception (rules.social.contests);
## - DC = 10 + the NPC's bonus + how big the ask is: the master's tier counts from `tier_base` (easy — a bare
##   contest, medium +5, hard +10…);
## - attitude: a friendly NPC is easier to persuade and to fool, a hostile one harder (`attitude_step` a step);
## - the DC stays within [dc_min, dc_max]. The master never sends a number (ADR-0008 §2).


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"]["social"]


static func _mod(score: int) -> int:
	return floori((score - 10) / 2.0)


## The NPC's bonus against `skill` and its name: {bonus, why}, or {} when the skill is not a social one.
static func resistance(data: Dictionary, npc: Dictionary, skill: String) -> Dictionary:
	var against := str(cfg(data)["contests"].get(skill, ""))
	if against.is_empty():
		return {}
	var m: Dictionary = data["monsters"].get(str(npc.get("monster", CombatRules.cfg(data)["default_npc_monster"])), {})
	var ab: Dictionary = m.get("abilities", {})
	var sk: Dictionary = m.get("skills", {})
	match against:
		"insight":
			return {"bonus": int(sk.get("insight", _mod(int(ab.get("wis", 10))))), "why": "Проницательность"}
		"deception":
			return {"bonus": int(sk.get("deception", _mod(int(ab.get("cha", 10))))), "why": "Обман"}
		"wis_save":
			return {"bonus": int(m.get("saves", {}).get("wis", _mod(int(ab.get("wis", 10))))), "why": "спасбросок Мудрости"}
	return {"bonus": _mod(int(ab.get("wis", 10))), "why": "Мудрость"}


## The engine's DC for a social check against `npc_id`: {dc, reason}, or {} when the engine's tier stays.
static func dc(s: GameSession, data: Dictionary, npc_id: String, skill: String, tier: String) -> Dictionary:
	var npc: Dictionary = data["world"]["npcs"].get(npc_id, {})
	if npc.is_empty() or not (data["rules"]["dc_tiers"] as Dictionary).has(tier):
		return {}
	var r := resistance(data, npc, skill)
	if r.is_empty():
		return {}
	var c := cfg(data)
	var ask := int(data["rules"]["dc_tiers"][tier]) - int(data["rules"]["dc_tiers"][str(c["tier_base"])])
	var d := 10 + int(r["bonus"]) + ask
	var parts: Array[String] = ["%s %s %+d" % [r["why"], npc.get("name", npc_id), int(r["bonus"])]]
	if ask != 0:
		parts.append("просьба %+d" % ask)
	if (c["attitude_skills"] as Array).has(skill) and s.attitude(npc_id) != 0:
		var shift := -s.attitude(npc_id) * int(c["attitude_step"])
		d += shift
		parts.append("отношение %+d" % shift)
	return {"dc": clampi(d, int(c["dc_min"]), int(c["dc_max"])), "reason": ", ".join(parts)}


# --- what an NPC grants by words (v0.7.15.2) -------------------------------------------------------------------


## The trader's discount for the hero now, percent (0 — none or ran out).
static func discount(s: GameSession, npc_id: String) -> int:
	var d: Dictionary = s.discounts.get(npc_id, {})
	return int(d.get("pct", 0)) if int(d.get("until_day", 0)) >= s.day else 0


## Why the NPC grants nothing now ("" — it may): attitude ≥ `min_attitude` or won over by a check this turn.
static func _willing(s: GameSession, data: Dictionary, npc_id: String, min_attitude: int, won: bool) -> String:
	if won or s.attitude(npc_id) >= min_attitude:
		return ""
	return "%s пока не настолько расположен(а) к герою (нужно отношение %+d или успешная проверка Убеждения, Обмана или Запугивания в этом ходе)" % [
		data["world"]["npcs"].get(npc_id, {}).get("name", npc_id), min_attitude]


## The plan of npc_discount: {plan, summary} or {reason}. `won` — a social check against this NPC succeeded this turn.
static func plan_discount(s: GameSession, data: Dictionary, npc_id: String, pct: int, won: bool) -> Dictionary:
	var c: Dictionary = cfg(data)["discount"]
	var npc: Dictionary = data["world"]["npcs"].get(npc_id, {})
	if not bool(npc.get("trader", false)):
		return {"reason": "%s не торгует: скидку даёт только торговец" % npc.get("name", npc_id)}
	var why := _willing(s, data, npc_id, int(c["min_attitude"]), won)
	if not why.is_empty():
		return {"reason": why}
	if pct < int(c["min_pct"]) or pct > int(c["max_pct"]):
		return {"reason": "скидка — от %d до %d%%" % [int(c["min_pct"]), int(c["max_pct"])]}
	if discount(s, npc_id) >= pct:
		return {"reason": "у героя уже есть скидка %d%% у %s" % [discount(s, npc_id), npc.get("name", npc_id)]}
	var until := s.day + int(c["days"]) - 1
	return {"plan": {"discount": npc_id, "pct": pct, "until_day": until},
		"summary": "%s: скидка %d%% до дня %d" % [npc.get("name", npc_id), pct, until]}


static func grant_discount(s: GameSession, data: Dictionary, plan: Dictionary) -> void:
	var npc_id := str(plan["discount"])
	s.discounts[npc_id] = {"pct": int(plan["pct"]), "until_day": int(plan["until_day"])}
	s.remember(npc_id, "дал%s герою скидку %d%% до дня %d" % [CrimeRules._ending(data, npc_id), int(plan["pct"]), int(plan["until_day"])])


## The plan of npc_favor: one of the NPC's services for free. {plan, summary} or {reason}.
static func plan_favor(s: GameSession, data: Dictionary, npc_id: String, service: String, item: String, won: bool) -> Dictionary:
	var c: Dictionary = cfg(data)["favor"]
	var npc: Dictionary = data["world"]["npcs"].get(npc_id, {})
	var own := TradeRules.services(s, data, npc_id).filter(func(x: Dictionary) -> bool: return x["id"] == service)
	if own.is_empty():
		var ids: Array = npc.get("services", [])
		return {"reason": "у %s нет услуги %s%s" % [npc.get("name", npc_id), service, "; есть: " + ", ".join(ids) if not ids.is_empty() else ""]}
	if str(own[0]["why"]) == "SERVICE_NOTHING":
		return {"reason": "услуга %s сейчас не нужна: у героя нечего (опознать, снять проклятие, посеребрить)" % service}
	if service == "silver" and not item.is_empty() and not TradeRules.silverable(s, data).has(item):
		return {"reason": "%s не посеребрить: нужно оружие героя из каталога, ещё не посеребрённое" % item}
	if s.favors.has(npc_id) and s.day - int(s.favors[npc_id]) < int(c["cooldown_days"]):
		return {"reason": "%s уже оказал(а) герою услугу даром в день %d — следующая не раньше дня %d" % [npc.get("name", npc_id), int(s.favors[npc_id]), int(s.favors[npc_id]) + int(c["cooldown_days"])]}
	var why := _willing(s, data, npc_id, int(c["min_attitude"]), won)
	if not why.is_empty():
		return {"reason": why}
	return {"plan": {"favor": npc_id, "service": service, "item_id": item},
		"summary": "%s: %s даром — %s" % [npc.get("name", npc_id), tr_service(service), "; ".join(_outcome(s, data, service, item))]}


## What the service will do, told to the master before the turn ends: «опознано: Кольцо защиты» (the master narrates
## it, never invents it).
static func _outcome(s: GameSession, data: Dictionary, service: String, item: String) -> Array[String]:
	var c: Dictionary = s.character.duplicate(true)
	match service:
		"identify":
			return ItemRules.identify(c, data, s.items.duplicate(true))
		"remove_curse":
			return ItemRules.lift_curse(c, data, s.items)
		"silver":
			var weapon := item if not item.is_empty() else TradeRules.silverable(s, data)[0]
			return ["посеребрено: %s" % ItemRules.display_name(data["items"], s.items, weapon)]
	return []


static func grant_favor(s: GameSession, data: Dictionary, plan: Dictionary) -> Array[String]:
	var npc_id := str(plan["favor"])
	s.favors[npc_id] = s.day
	s.remember(npc_id, "оказал%s герою услугу даром (%s) — герой в долгу" % [CrimeRules._ending(data, npc_id), tr_service(str(plan["service"]))])
	return TradeRules.buy_service(s, data, npc_id, str(plan["service"]), str(plan.get("item_id", "")), true)


## A service's name for the lines and the master: «опознание».
static func tr_service(id: String) -> String:
	return {"identify": "опознание вещей", "remove_curse": "снятие проклятия", "silver": "серебрение оружия"}.get(id, id)


## What the NPC granted, for the snapshot: «скидка 10% до дня 9; услуга даром — была в день 3».
static func deal_text(s: GameSession, data: Dictionary, npc_id: String) -> String:
	var parts: Array[String] = []
	if discount(s, npc_id) > 0:
		parts.append("скидка герою %d%% до дня %d" % [discount(s, npc_id), int(s.discounts[npc_id]["until_day"])])
	if s.favors.has(npc_id):
		parts.append("услугу даром оказывал(а) в день %d" % int(s.favors[npc_id]))
	return "; ".join(parts)
