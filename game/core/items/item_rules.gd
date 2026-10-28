class_name ItemRules
extends RefCounted
## Item catalog queries and the power check of master-made items (ADR-0008 §6): every property costs rarity
## points, the sum sets the rarity, the rarity is limited by character level and caps the value.
## v0.7.12 (5e items): an unidentified thing lives in the pack under `unk_<id>` — it works, but its name and properties
## are hidden until a short rest, an attunement, Identify or a trader's service; attunement (up to three, an hour);
## charges with a regain at dawn (the long rest); a catalog item's own `use` (potions, scrolls, wands, the pearl).

const UNKNOWN := "unk_"


## Definition of an item: catalog first, then items generated in this session. {} if unknown. An item on a `base`
## (a magic sword on a longsword, v0.6.3) takes the base's weapon / armor block, weight, type and properties.
static func def_of(items_data: Dictionary, session_items: Dictionary, id: String) -> Dictionary:
	if id.begins_with(UNKNOWN):  # an unidentified thing: the real item under a plain name (v0.7.12)
		var real := def_of(items_data, session_items, id.trim_prefix(UNKNOWN))
		if real.is_empty():
			return {}
		real["unknown_of"] = id.trim_prefix(UNKNOWN)
		real["name"] = unknown_name(items_data, real)
		real.erase("description")
		return real
	var d: Dictionary
	if items_data["catalog"].has(id):
		d = items_data["catalog"][id].duplicate()
		d["rarity"] = str(d.get("rarity", "common"))
	elif session_items.has(id):
		d = (session_items[id] as Dictionary).duplicate()
	else:
		return {}
	var base := str(d.get("base", ""))
	if not base.is_empty() and items_data["catalog"].has(base):
		var b := def_of(items_data, {}, base)  # a base on a base: a silvered +1 sword (v0.7.12)
		for k: String in ["weapon", "armor", "weight"]:
			if not d.has(k) and b.has(k):
				d[k] = b[k]
		if b.has("weapon") or b.has("armor"):
			d["item_type"] = str(b.get("item_type", d.get("item_type", "gear")))
		var props: Array = (b.get("properties", []) as Array).duplicate()
		for p: Variant in d.get("properties", []):
			if not props.has(p):
				props.append(p)
		d["properties"] = props
	var props: Array = d.get("properties", [])
	if (props.has("mithral") or props.has("masterwork")) and d.has("armor"):  # no Strength need, no stealth trouble
		var a: Dictionary = (d["armor"] as Dictionary).duplicate()
		a["str_min"] = 0
		a["stealth_disadvantage"] = false
		d["armor"] = a
	return d


## «Плащ, свойства неизвестны» — what an unidentified thing is called.
static func unknown_name(items_data: Dictionary, d: Dictionary) -> String:
	var look := str(d.get("look", ""))
	if look.is_empty():
		look = str(def_of(items_data, {}, str(d.get("base", ""))).get("name", "вещь")) if not str(d.get("base", "")).is_empty() else "вещь"
	return look.left(1).to_upper() + look.substr(1) + str(items_data.get("unknown_suffix", ", свойства неизвестны"))


static func real_id(id: String) -> String:
	return id.trim_prefix(UNKNOWN)


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"]["item_rules"]


# --- identification (v0.7.12) ----------------------------------------------------------------------


## A found magic thing (rarity above common, not one the master made) comes unidentified.
static func needs_identify(d: Dictionary) -> bool:
	return not d.is_empty() and not bool(d.get("generated", false)) and str(d.get("rarity", "common")) not in ["common", ""]


## The hero finds `qty` of `id` (a cache, a body, a thing in the room, the master's gift, a theft): a magic one comes
## unidentified. Returns the id it lies under.
static func found(c: Dictionary, data: Dictionary, session_items: Dictionary, id: String, qty: int = 1) -> String:
	var key := id
	if not id.begins_with(UNKNOWN) and needs_identify(def_of(data["items"], session_items, id)):
		key = UNKNOWN + id
	var inv: Dictionary = c["inventory"]
	inv[key] = int(inv.get(key, 0)) + qty
	return key


## The trade tags of an item (v0.7.17.1, demand): its item_type, magic, scroll, tool and the item's own `tags`.
static func trade_tags(def: Dictionary) -> Array[String]:
	var out: Array[String] = [str(def.get("item_type", "gear"))]
	if not str(def.get("rarity", "common")) in ["common", ""]:
		out.append("magic")
	if bool(def.get("use", {}).get("scroll", false)):
		out.append("scroll")
	if def.has("tool"):
		out.append("tool")
	for t: Variant in def.get("tags", []):
		out.append(str(t))
	return out


static func unknown_ids(c: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for id: String in c.get("inventory", {}):
		if id.begins_with(UNKNOWN):
			out.append(id)
	return out


## Identifies the hero's unknown things (all, or `only`): the stack, the slot, the attunement and the charges move to
## the real id. Lines «опознано: Плащ защиты».
static func identify(c: Dictionary, data: Dictionary, session_items: Dictionary, only: Array = []) -> Array[String]:
	var lines: Array[String] = []
	var inv: Dictionary = c["inventory"]
	for key: String in unknown_ids(c):
		if not only.is_empty() and not only.has(key) and not only.has(real_id(key)):
			continue
		var real := real_id(key)
		inv[real] = int(inv.get(real, 0)) + int(inv[key])
		inv.erase(key)
		var eq: Dictionary = c.get("equipped", {})
		for slot: String in eq:
			if str(eq[slot]) == key:
				eq[slot] = real
		var att: Array = c.get("attuned", [])
		if att.has(key):
			att[att.find(key)] = real
		var used: Dictionary = c.get("charges_used", {})
		if used.has(key):
			used[real] = used[key]
			used.erase(key)
		lines.append("опознано: %s" % display_name(data["items"], session_items, real))
	if not lines.is_empty():  # «Артефакция» learns from the things it sees through (v0.7.39.1)
		lines.append_array(DevelopmentRules.add_xp(c, data, "artifice", lines.size() * _artifice_xp(data, "identify")))
	return lines


static func _artifice_xp(data: Dictionary, source: String) -> int:
	return int(DevelopmentRules.direction(data, "artifice").get("sources", {}).get(source, 0))


# --- attunement (v0.7.12) --------------------------------------------------------------------------


static func needs_attunement(d: Dictionary) -> bool:
	return bool(d.get("attunement", false)) or ((d.get("properties", []) as Array).has("cursed") and str(d.get("item_type", "")) == "wondrous")


static func attuned(c: Dictionary) -> Array:
	return c.get("attuned", [])


## An item works: no attunement needed, or the hero is attuned to it.
static func active(c: Dictionary, d: Dictionary, id: String) -> bool:
	return not needs_attunement(d) or attuned(c).has(id) or attuned(c).has(real_id(id))


static func cursed(d: Dictionary) -> bool:
	return (d.get("properties", []) as Array).has("cursed")


## "" when the hero can attune to the item now, otherwise a localization key.
static func can_attune(c: Dictionary, data: Dictionary, session_items: Dictionary, id: String) -> String:
	var d := def_of(data["items"], session_items, id)
	if int(c.get("inventory", {}).get(id, 0)) <= 0:
		return "EQUIP_NOT_OWNED"
	if not needs_attunement(d):
		return "ATTUNE_NOT_NEEDED"
	if attuned(c).has(id) or attuned(c).has(real_id(id)):
		return "ATTUNE_ALREADY"
	if attuned(c).size() >= int(cfg(data)["attune_max"]):
		return "ATTUNE_FULL"
	if bool(d.get("caster", false)) and str(c.get("spell_ability", "")).is_empty():
		return "ATTUNE_CASTER_ONLY"
	return ""


## An hour with the thing (the caller moves the clock): it is identified and bound. Lines.
static func attune(c: Dictionary, data: Dictionary, session_items: Dictionary, id: String) -> Array[String]:
	var lines: Array[String] = []
	if id.begins_with(UNKNOWN):
		lines = identify(c, data, session_items, [id])
	var real := real_id(id)
	if not c.has("attuned"):
		c["attuned"] = []
	(c["attuned"] as Array).append(real)
	var d := def_of(data["items"], session_items, real)
	lines.append("настройка: %s" % d.get("name", real))
	if cursed(d):
		lines.append("вещь проклята — снять её теперь нельзя")
	lines.append_array(DevelopmentRules.add_xp(c, data, "artifice", _artifice_xp(data, "attune")))
	return lines


## "" when the hero can end the attunement (a cursed thing holds on), otherwise a localization key.
static func can_unattune(c: Dictionary, data: Dictionary, session_items: Dictionary, id: String) -> String:
	if not attuned(c).has(id):
		return "ATTUNE_NOT_ATTUNED"
	if cursed(def_of(data["items"], session_items, id)):
		return "ITEM_CURSED"
	return ""


## A cursed thing the hero wears, wields or is attuned to: it does not come off (v0.7.12).
static func held_by_curse(c: Dictionary, data: Dictionary, session_items: Dictionary, id: String) -> bool:
	if id.is_empty() or not cursed(def_of(data["items"], session_items, id)):
		return false
	return attuned(c).has(id) or (c.get("equipped", {}) as Dictionary).values().has(id)


## Remove Curse (the spell or the priestess): the cursed things come off and lose the attunement; they stay cursed.
static func lift_curse(c: Dictionary, data: Dictionary, session_items: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	for thing: String in (c.get("inventory", {}) as Dictionary).keys():
		if not held_by_curse(c, data, session_items, thing):
			continue
		unattune(c, thing)
		var eq: Dictionary = c.get("equipped", {})
		for slot: String in eq:
			if str(eq[slot]) == thing:
				eq[slot] = ""
		lines.append("проклятие отпустило: %s (сама вещь проклята по-прежнему)" % display_name(data["items"], session_items, thing))
	return lines


static func unattune(c: Dictionary, id: String) -> void:
	(c.get("attuned", []) as Array).erase(id)


# --- charges (v0.7.12) -----------------------------------------------------------------------------


static func charges_max(d: Dictionary) -> int:
	return int(d.get("charges", {}).get("max", 0))


static func charges_left(c: Dictionary, d: Dictionary, id: String) -> int:
	return maxi(0, charges_max(d) - int(c.get("charges_used", {}).get(real_id(id), c.get("charges_used", {}).get(id, 0))))


## Spends a charge; the last one of a wand may turn it to dust (1 on a d20, DMG). Lines.
static func spend_charge(c: Dictionary, data: Dictionary, session_items: Dictionary, id: String, rng: RandomNumberGenerator) -> Array[String]:
	var d := def_of(data["items"], session_items, id)
	if not c.has("charges_used"):
		c["charges_used"] = {}
	var used: Dictionary = c["charges_used"]
	used[id] = int(used.get(id, 0)) + 1
	var left := charges_left(c, d, id)
	var lines: Array[String] = ["зарядов: %d из %d" % [left, charges_max(d)]]
	if left == 0 and bool(d.get("charges", {}).get("crumble", false)) and rng.randi_range(1, 20) == 1:
		_remove_one(c, id)
		used.erase(id)
		lines.append("%s рассыпается в пыль" % d.get("name", id))
	elif left == 0 and not d.get("charges", {}).has("regain"):
		_remove_one(c, id)
		used.erase(id)
		lines.append("%s закончилась" % d.get("name", id))
	return lines


## Dawn (the long rest): charges come back by the item's dice. Lines.
static func dawn(c: Dictionary, data: Dictionary, session_items: Dictionary, rng: RandomNumberGenerator) -> Array[String]:
	var lines: Array[String] = []
	var used: Dictionary = c.get("charges_used", {})
	for id: String in used.keys():
		var d := def_of(data["items"], session_items, id)
		var regain := str(d.get("charges", {}).get("regain", ""))
		if regain.is_empty() or int(used[id]) <= 0:
			continue
		var back := mini(int(used[id]), CombatRules.roll_dice(rng, regain))
		used[id] = int(used[id]) - back
		lines.append("%s: +%d %s" % [d.get("name", id), back, "заряд" if back == 1 else "заряда" if back < 5 else "зарядов"])
	return lines


## One use of the thing: a charge, or the thing itself. Lines.
static func consume(c: Dictionary, data: Dictionary, session_items: Dictionary, id: String, rng: RandomNumberGenerator) -> Array[String]:
	if charges_max(def_of(data["items"], session_items, id)) > 0:
		return spend_charge(c, data, session_items, id, rng)
	_remove_one(c, id)
	return []


static func _remove_one(c: Dictionary, id: String) -> void:
	var inv: Dictionary = c["inventory"]
	var left := int(inv.get(id, 0)) - 1
	if left > 0:
		inv[id] = left
	else:
		inv.erase(id)
		(c.get("attuned", []) as Array).erase(id)


# --- what a found thing may be (v0.7.12) -----------------------------------------------------------


## "" when the master may hand this catalog item to a hero of `level` (not rarer than max_found_rarity at levels
## 1-5), otherwise the reason for the master.
static func rarity_ok(data: Dictionary, d: Dictionary, level: int) -> String:
	var order: Array = cfg(data)["rarity_order"]
	var r := str(d.get("rarity", "common"))
	if level <= 5 and order.find(r) > order.find(str(cfg(data)["max_found_rarity"])):
		return "«%s» — редкость %s: на 1–5 уровне мастер такое не выдаёт (только награды заданий мира)" % [d.get("name", ""), r]
	return ""


## The sum of «+N» properties of an item ("magic_plus1", "ac_plus2"…) for the given prefixes.
static func plus(def: Dictionary, prefixes: Array) -> int:
	var n := 0
	for p: Variant in def.get("properties", []):
		for pre: String in prefixes:
			if str(p).begins_with(pre) and str(p).trim_prefix(pre).is_valid_int():
				n += int(str(p).trim_prefix(pre))
	return n


static func display_name(items_data: Dictionary, session_items: Dictionary, id: String) -> String:
	return str(def_of(items_data, session_items, id).get("name", id))


## Catalog + session items matching a free-text query (Russian name or id), a base id and required properties.
static func find(items_data: Dictionary, session_items: Dictionary, query: String, base: String, properties: Array) -> Array[Dictionary]:
	var q := query.to_lower().strip_edges()
	var stems := word_stems(q)
	var out: Array[Dictionary] = []
	var loose: Array[Dictionary] = []  # a word of the query, not the whole of it: after the exact hits (v0.7.34.4)
	var pools: Array[Dictionary] = [items_data["catalog"], session_items]
	for pool: Dictionary in pools:
		for id: String in pool:
			var d: Dictionary = pool[id]
			var props: Array = d.get("properties", [])
			var name_l := str(d.get("name", "")).to_lower()
			var hit := q.is_empty() or q in name_l or q in id or q == str(d.get("item_type", ""))
			if not base.is_empty() and (id == base or str(d.get("base", "")) == base):
				hit = true
			var near := not hit and (stems.size() > 1 and stems.any(func(w: String) -> bool: return w in name_l)
				or q.length() >= 4 and q in str(d.get("description", "")).to_lower())
			if not (hit or near) or not properties.all(func(p: Variant) -> bool: return props.has(p)):
				continue
			(out if hit else loose).append({"item_id": id, "name": d.get("name", id), "item_type": d.get("item_type", ""),
				"rarity": d.get("rarity", "common"), "value_cp": int(d.get("value_cp", 0)), "properties": props,
				"source": "catalog" if pool == items_data["catalog"] else "session"})
	out.append_array(loose)
	return out


## The first five letters of each word of three letters or more: «кувшин глиняный» finds «Кувшин».
static func word_stems(q: String) -> Array[String]:
	var out: Array[String] = []
	for w: String in q.split(" ", false):
		if w.length() >= 3:
			out.append(w.left(5))
	return out


static func rarity_for_points(items_data: Dictionary, points: int) -> String:
	var rarity := "common"
	for step: Array in items_data["rarity_by_points"]:
		if points >= int(step[0]):
			rarity = str(step[1])
	return rarity


## Deterministic id, so the same item made twice (or taken from the backend library) keeps one id.
static func generated_id(item: Dictionary) -> String:
	var props: Array = item.get("properties", []).duplicate()
	props.sort()
	return "gen_" + ("%s|%s|%s" % [item.get("name", ""), item.get("base", ""), ",".join(props)]).md5_text().left(10)


## {"ok": true, "def": normalized definition} or {"ok": false, "reason": text for the master}.
static func check_generated(items_data: Dictionary, item: Dictionary, level: int, spells: Dictionary = {}) -> Dictionary:
	var costs: Dictionary = items_data["properties"]
	var points := 0
	for p: Variant in item.get("properties", []):
		if not costs.has(p):
			return {"ok": false, "reason": "свойство %s движку неизвестно" % p}
		points += int(costs[p])
	var base := str(item.get("base", ""))
	if not base.is_empty() and not items_data["catalog"].has(base):
		return {"ok": false, "reason": "базового предмета %s нет в каталоге" % base}
	var use := _generated_use(items_data, item, spells)  # v0.7.18: what the thing does when used
	if use.has("reason"):
		return {"ok": false, "reason": use["reason"]}
	points += int(use.get("points", 0))
	if points == 0 and not str(item.get("rarity", "common")) in ["common", ""]:  # big test #16 (v0.7.22.2)
		return {"ok": false, "reason": ("магическая вещь (%s) без механики станет простой безделушкой — движок не опознает её и ничего ей не даст. " +
			"Дай ей свойства (`properties` из словаря движка) или `use` (заряды заклинания, зелье), либо возьми готовую магическую вещь " +
			"каталога через find_items (кольцо, плащ, амулет, очки…). Если это и правда простая вещь — rarity common") % item.get("rarity", "")}
	var rarity := rarity_for_points(items_data, points)
	if level < int(items_data["rarity_min_level"][rarity]):
		return {"ok": false, "reason": "предмет редкости %s недоступен на %d уровне" % [rarity, level]}
	var value := mini(int(item.get("value_cp", 0)), int(items_data["rarity_max_value_cp"][rarity]))
	var def := {
		"name": str(item.get("name", "")), "item_type": str(item.get("item_type", "gear")), "base": base,
		"rarity": rarity, "value_cp": value, "properties": item.get("properties", []),
		"description": str(item.get("description", "")), "generated": true,
	}
	if not str(item.get("text", "")).strip_edges().is_empty():  # what is written on it (a letter, a diary), v0.7.18
		def["text"] = str(item["text"]).strip_edges().left(1000)
	if use.has("use"):
		def["use"] = use["use"]
		if use.has("charges"):
			def["charges"] = use["charges"]
		if use.has("look"):
			def["look"] = use["look"]
	if def["name"].is_empty():
		return {"ok": false, "reason": "у предмета нет названия"}
	return {"ok": true, "def": def}


## The `use` of a generated thing (v0.7.18, by the catalog's own shapes): a spell of the engine's book with charges
## (a wand) or once (a scroll), healing, a resistance or an advantage once (a potion). {} — none; {reason}; or
## {use, charges?, look?, points}. Points by items.json `use_points`.
static func _generated_use(items_data: Dictionary, item: Dictionary, spells: Dictionary) -> Dictionary:
	var u: Variant = item.get("use")
	if u == null or not (u is Dictionary) or (u as Dictionary).is_empty():
		return {}
	var cost: Dictionary = items_data["use_points"]
	var charges := int(u.get("charges", 0)) if u.get("charges") != null else 0
	var once := charges <= 0
	var out := {"points": 0}
	if u.get("spell") != null and not str(u["spell"]).is_empty():
		var sp := str(u["spell"])
		var spell: Dictionary = spells.get(sp, {})
		if spell.is_empty():
			return {"reason": "заклинания %s нет в книге движка" % sp}
		var lvl := maxi(int(spell.get("level", 0)), int(u.get("level", 0)) if u.get("level") != null else 0)
		if lvl > 3:
			return {"reason": "заклинание в предмете — не выше 3 круга"}
		out["use"] = {"spell": sp, "level": lvl}
		if once:
			out["use"]["scroll"] = true
			out["look"] = "свиток"
			out["points"] = int(cost["scroll"][lvl])
		else:
			out["look"] = "волшебная палочка"
			out["points"] = int(cost["wand"][lvl])
	elif u.get("heal") != null and not str(u["heal"]).is_empty():
		var h: Dictionary = cost["heal"].get(str(u["heal"]), {})
		if h.is_empty():
			return {"reason": "лечение: light, medium или strong"}
		out["use"] = {"heal": (h["dice"] as Array).map(func(x: Variant) -> int: return int(x))}
		out["points"] = int(h["points"])
		out["look"] = "зелье"
	elif u.get("resist") != null and not str(u["resist"]).is_empty():
		out["use"] = {"resist": str(u["resist"]), "duration": "hour"}
		out["points"] = int(cost["resist"])
		out["look"] = "зелье"
	elif u.get("check_adv") != null and not str(u["check_adv"]).is_empty():
		out["use"] = {"check_adv": str(u["check_adv"]), "duration": "hour"}
		out["points"] = int(cost["check_adv"])
		out["look"] = "зелье"
	else:
		return {"reason": "use: spell, heal, resist или check_adv"}
	if not once:
		if not out["use"].has("spell"):
			return {"reason": "заряды — только у предмета с заклинанием (жезл); зелья и свитки одноразовые"}
		var most := int(cost["charges_max"])
		if charges > most:
			return {"reason": "зарядов не больше %d" % most}
		out["charges"] = {"max": charges, "regain": "1d%d" % maxi(1, charges - 1), "crumble": true}
		if str(item.get("item_type", "")) not in ["wondrous", "weapon", "gear"]:
			return {"reason": "предмет с зарядами — wondrous (жезл, посох), оружие или снаряжение"}
	elif str(item.get("item_type", "")) != "consumable":
		return {"reason": "одноразовый предмет (зелье, свиток) — item_type consumable"}
	return out


## What using an item does (rules.json `consumables`): {"heal": [n, sides, bonus], "remove": [conditions]}; {} = not usable.
## `session_items` — the generated things of the game: a thing the master made has its own `use` too (v0.7.18).
static func consumable(data: Dictionary, id: String, session_items: Dictionary = {}) -> Dictionary:
	id = real_id(id)
	if id.begins_with("_"):
		return {}
	var all: Dictionary = data["rules"].get("consumables", {})
	if all.has(id):
		return all[id]
	if session_items.has(id):
		return session_items[id].get("use", {})
	return data["items"]["catalog"].get(id, {}).get("use", {})  # potions, scrolls, wands, the pearl (v0.7.12)


## A potion (v0.7.22.3: drunk as a bonus action in a fight): a catalog potion or a made one with a potion's `use`.
static func is_potion(data: Dictionary, session_items: Dictionary, id: String) -> bool:
	var real := real_id(id)
	var d := def_of(data["items"], session_items, real)
	if real.contains("potion") or str(d.get("look", "")) == "зелье":
		return true
	var use: Dictionary = d.get("use", {}) if d.get("use") is Dictionary else {}
	return use.has("heal") or use.has("resist") or use.has("check_adv")


## "" when the character can use the item now, otherwise the reason (for the master).
static func can_use(c: Dictionary, data: Dictionary, session_items: Dictionary, id: String, pending: int = 0) -> String:
	if int(c.get("inventory", {}).get(id, 0)) - pending <= 0:
		return "у персонажа нет %s" % display_name(data["items"], session_items, id)
	var fx := consumable(data, id, session_items)
	if fx.is_empty():
		return "%s нельзя использовать так — это не расходник с действием движка" % display_name(data["items"], session_items, id)
	var d := def_of(data["items"], session_items, id)
	if not active(c, d, id):
		return "%s не работает без настройки" % d.get("name", id)
	if charges_max(d) > 0 and charges_left(c, d, id) <= 0:
		return "у %s не осталось зарядов — они вернутся на рассвете" % d.get("name", id)
	if fx.has("recover_slot") and not (c.get("slots_used", []) as Array).any(func(n: Variant) -> bool: return int(n) > 0):
		return "все ячейки заклинаний и так целы"
	return ""


## Uses one item (can_use first): removes it, heals, lifts conditions; with the session (v0.7.8) it also leaves its
## boon for a while (antitoxin — advantage on saves against poison for an hour). Returns the chat lines.
static func use(c: Dictionary, data: Dictionary, session_items: Dictionary, id: String, rng: RandomNumberGenerator, s: GameSession = null) -> Array[String]:
	var fx := consumable(data, id, session_items)
	var d := def_of(data["items"], session_items, real_id(id))
	var lines: Array[String] = ["Использовано: %s" % d.get("name", id)]
	lines.append_array(consume(c, data, session_items, id, rng))
	if fx.has("throw"):  # out of a fight: thrown at a thing, the master narrates (v0.7.12)
		lines[0] = "Брошено: %s" % d.get("name", id)
		return lines
	if fx.has("spell"):
		lines.append_array(_spell_use(c, data, session_items, fx, rng, s))
		return lines
	if fx.has("recover_slot"):
		var used: Array = (c.get("slots_used", [0, 0, 0, 0, 0]) as Array).duplicate()
		for lv in range(mini(int(fx["recover_slot"]), used.size()), 0, -1):
			if int(used[lv - 1]) > 0:
				used[lv - 1] = int(used[lv - 1]) - 1
				lines.append("ячейка %d круга восстановлена" % lv)
				break
		c["slots_used"] = used
		return lines
	if s != null and fx.has("poison"):  # a Potion of Poison drunk for a healing one
		var p: Dictionary = fx["poison"]
		var dmg := CombatRules.roll_dice(rng, str(p["dice"]))
		var r := HeroDefense.save(s, data, str(p["save"]), int(p["dc"]), "poison")
		if bool(r["ok"]):
			dmg /= 2
		var adj := HeroDefense.adjust(s, data, "poison", dmg)
		c["hp"] = maxi(0, int(c["hp"]) - int(adj["damage"]))
		lines.append("яд! −%d HP, спасбросок %s" % [int(adj["damage"]), r["text"]])
		if not bool(r["ok"]):
			lines.append_array(ConditionRules.impose(s, data, {"condition": "poisoned", "ends": ConditionRules.ends_for(s, data, "hour"),
				"source": {"kind": "item", "id": real_id(id), "name": str(d.get("name", ""))}}))
		lines.append_array(HeroDefense.after_damage(s, data, int(adj["damage"])))
		return lines
	if s != null and fx.has("meal"):  # a dish (v0.7.25)
		lines.append_array(FoodRules.eat_one(s, data, id))
		return lines
	if s != null and fx.has("invisible_minutes"):
		var minutes := CombatRules.roll_dice(rng, str(fx["invisible_minutes"]))
		ConditionRules.add_effect(c, {"condition": "invisible", "ends": {"at": ConditionRules.now(s) + minutes * 10},
			"source": {"kind": "item", "id": real_id(id), "name": str(d.get("name", ""))}})
		lines.append("невидимость на %d мин" % minutes)
		return lines
	if fx.has("heal"):
		var h: Array = fx["heal"]
		var amount := int(h[2])
		for i in int(h[0]):
			amount += rng.randi_range(1, int(h[1]))
		var before := int(c["hp"])
		c["hp"] = mini(int(c["max_hp"]), before + amount)
		lines.append("+%d HP" % (int(c["hp"]) - before))
	if s != null and (fx.has("adv_tag") or fx.has("resist") or fx.has("check_adv") or fx.has("enlarged") or fx.has("cure")):
		lines.append_array(ConditionRules.cure(s, data, fx, {"kind": "item", "id": real_id(id), "name": str(d.get("name", ""))}))
		return lines
	for cond: Variant in fx.get("remove", []):
		if ConditionRules.has(c, str(cond)):
			ConditionRules.remove(c, str(cond))
			lines.append("снято: %s" % str(data["rules"]["conditions"].get(str(cond), cond)).get_slice(":", 0))
	return lines


## A scroll read or a wand used out of a fight: a scroll of the hero's own class within their power needs no check,
## otherwise Arcana DC 10 + the circle (BG3: anyone may try); healing lands on the hero, Identify names every unknown
## thing, the rest is the master's to narrate. Lines.
static func _spell_use(c: Dictionary, data: Dictionary, session_items: Dictionary, fx: Dictionary, rng: RandomNumberGenerator, s: GameSession) -> Array[String]:
	var sp_id := str(fx["spell"])
	var sp: Dictionary = data["spells"].get(sp_id, {})
	var lines: Array[String] = []
	if bool(fx.get("scroll", false)):
		var read := read_scroll(c, data, sp_id, int(fx.get("level", 1)), rng)
		lines.append(str(read["line"]))
		if not bool(read["ok"]):
			return lines
	var dcs := scroll_numbers(data, int(fx.get("level", 1)))
	if sp_id == "identify":
		lines.append_array(identify(c, data, session_items))
		if lines.size() == 1:
			lines.append("неопознанных вещей нет")
		return lines
	if sp.has("heal_at_slot"):
		var ab := CharacterRules.mod(CharacterRules.ability(c, str(c.get("spell_ability", "wis")))) if not str(c.get("spell_ability", "")).is_empty() else 0
		var heal := CombatRules.roll_dice(rng, str(sp["heal_at_slot"].get(str(maxi(1, int(fx.get("level", 1)))), "1d8+MOD")), false, ab)
		var before := int(c["hp"])
		c["hp"] = mini(int(c["max_hp"]), before + heal)
		lines.append("+%d HP" % (int(c["hp"]) - before))
		return lines
	lines.append("%s (Сл %d)" % [sp.get("name", sp_id), int(fx.get("dc", dcs[0]))])
	return lines


## DC and attack bonus of a scroll's spell by the circle (DMG).
static func scroll_numbers(data: Dictionary, level: int) -> Array:
	return cfg(data)["scrolls"].get(str(clampi(level, 0, 3)), [13, 5])


## Reading a scroll: {"ok", "line"}. A spell of the hero's class list and within the slots they have — no check;
## otherwise Arcana DC 10 + circle, a failure wastes the scroll.
static func read_scroll(c: Dictionary, data: Dictionary, spell_id: String, level: int, rng: RandomNumberGenerator) -> Dictionary:
	var sp: Dictionary = data["spells"].get(spell_id, {})
	var name := str(sp.get("name", spell_id))
	var own := (sp.get("classes", []) as Array).has(str(c.get("class", ""))) and (level == 0 or int(c.get("slots_max", [0, 0, 0, 0, 0])[maxi(0, level - 1)]) > 0)
	if own:
		return {"ok": true, "line": "свиток прочитан: %s" % name}
	var dc := 10 + level
	var bonus := int(c.get("skills", {}).get("arcana", 0))
	var roll := rng.randi_range(1, 20)
	var ok := roll + bonus >= dc
	return {"ok": ok, "line": "Магия %d + %d = %d против Сл %d — %s" % [roll, bonus, roll + bonus, dc,
		("свиток прочитан: " + name) if ok else "слова не даются, свиток рассыпается впустую"]}
