class_name CardInfo
extends RefCounted
## The card of a spell, a feature, a thing or an act as in BG3 (v0.8.4.43.33, the author: «название, уровень, урон с его
## описанием, описание, сколько действует, как накладывается, дистанция, концентрация, что требует»). A card is data —
## the window draws it (DetailsPanel), the numbers come from the rules:
## {title, title_color, sub, icon, big, dice: [{text, type, color, heal}], status: [{icon, text}], desc, notes: [], props: [],
##  cost: [{kind, text}], foot: []}. `big` is the headline number (the damage, the healing, the AC); `dice` its dice by
## damage type; `status` what the spell lays, with the icon of its condition; `props` how it works (a glyph and words);
## `cost` what it takes (an action, a bonus action, a reaction, a slot); `foot` a thing's weight and price.

## The glyph of a cost: the same shapes as the counters over the hotbar.
const GLYPH := {"action": "●", "bonus": "▲", "reaction": "◆", "slot": "■", "free": "○", "time": "⧗", "move": "➜"}
const DURATION := "⧗"
const RANGE := "◎"
const AREA := "✺"
const ATTACK := "⌖"
const SAVE := "⛉"
const CONCENTRATION := "◉"
const USES := "◈"


## A spell at a slot (0 — its own circle), its numbers by the caster `c` ({} — by the spell alone).
static func spell(data: Dictionary, id: String, slot: int = 0, c: Dictionary = {}) -> Dictionary:
	var sp: Dictionary = data["spells"].get(id, {})
	if sp.is_empty():
		return {}
	var lv := int(sp.get("level", 0))
	var at := maxi(slot, lv)
	var school := str(sp.get("school", ""))
	var sub := _t("CARD_CANTRIP_SUB") if lv == 0 else _t("CARD_SPELL_SUB").format({"n": at})
	sub += (" · " + school) if not school.is_empty() else ""
	if bool(sp.get("ritual", false)):
		sub += " · " + _t("CARD_RITUAL")
	var card := {"title": str(sp.get("name", id)), "sub": sub, "icon": "spells/" + id, "desc": str(sp.get("desc", "")),
		"dice": [], "status": [], "notes": [], "props": [], "cost": [], "foot": []}
	var level := int(c.get("level", 1))
	var ab := str(sp.get("ability", c.get("spell_ability", "")))
	var mod := CharacterRules.mod(CharacterRules.ability(c, ab)) if not c.is_empty() and not ab.is_empty() else 0
	var known_mod := not c.is_empty() and not ab.is_empty()
	var dtype := str(sp.get("damage_type", ""))
	if sp.has("heal_at_slot"):
		var hr := SpellRules.heal_range(data, c, id, maxi(1, at), mod)
		var dice := str(sp["heal_at_slot"].get(str(maxi(1, at)), ""))
		card["big"] = _t("CARD_BIG_HEAL").format({"lo": hr[0], "hi": hr[1]}) if known_mod or not dice.contains("MOD") else ""
		card["dice"].append({"text": _mod_dice(dice, mod, known_mod), "type": _t("CARD_HEALING"), "color": "", "heal": true})
	elif sp.has("damage_at_slot") or sp.has("damage_at_level"):
		var dice := CombatRules.spell_dice(sp, at, level)
		var n := SpellEffects.count(data, id, at, level)
		var r := CombatRules.dice_range(dice, mod)
		card["big"] = _t("CARD_BIG_DAMAGE").format({"lo": r[0] * n, "hi": r[1] * n})
		card["dice"].append({"text": ("%d × " % n if n > 1 else "") + _mod_dice(dice, mod, known_mod), "type": damage_name(data, dtype),
			"color": element_color(data, dtype)})
	var cspec: Dictionary = CombatRules.cfg(data)["condition_spells"].get(id, {})
	for cond: Variant in cspec.get("conditions", []):
		card["status"].append({"icon": "conditions/" + str(cond), "text": ConditionRules.name_of(data, str(cond))})
	var conc := bool(sp.get("concentration", false))
	var dur := str(sp.get("duration", ""))
	if conc and dur.to_lower().begins_with("концентрация"):
		dur = dur.substr(dur.find(",") + 1).strip_edges() if dur.contains(",") else ""
	if not dur.is_empty() and not dur.to_lower().begins_with("мгновен"):
		card["props"].append("%s %s" % [DURATION, dur.left(1).to_upper() + dur.substr(1)])
	if not str(sp.get("range", "")).is_empty():
		card["props"].append("%s %s" % [RANGE, sp["range"]])
	if sp.get("area") is Dictionary:
		var area: Dictionary = sp["area"]
		card["props"].append("%s %s" % [AREA, _t("CARD_AREA_" + str(area.get("type", "sphere")).to_upper()).format({"n": int(area.get("size", 0))})])
	if sp.has("attack"):
		card["props"].append("%s %s" % [ATTACK, _t("CARD_ATTACK_" + str(sp["attack"]).to_upper())])
	if sp.get("save") is Dictionary:
		var save: Dictionary = sp["save"]
		card["props"].append("%s %s%s" % [SAVE, _t("SAVE_" + str(save.get("ability", "dex")).to_upper()),
			(" · " + _t("CARD_SAVE_HALF")) if str(save.get("success", "")) == "half" else ""])
	if conc:
		card["props"].append("%s %s" % [CONCENTRATION, _t("CARD_CONCENTRATION")])
	if SpellRules.by_master(data, id):
		card["notes"].append(_t("DETAILS_BY_MASTER"))
	var grown := SpellRules.at_slot(data, id, slot)  # v0.7.22.19: what the chosen slot gives
	if not grown.is_empty():
		card["notes"].append(grown)
	card["cost"].append(time_cost(str(sp.get("casting_time", ""))))
	if lv > 0:
		var free := not c.is_empty() and SpellRules.free_now(c, data, id)
		card["cost"].append({"kind": "free", "text": _t("CARD_COST_AT_WILL")} if free else {"kind": "slot", "text": _t("CARD_COST_SLOT").format({"n": at})})
	return card


## A thing as `c` holds it (its blow and its AC by `c`; {} — by the thing alone).
static func item(c: Dictionary, data: Dictionary, session_items: Dictionary, id: String) -> Dictionary:
	var def := ItemRules.def_of(data["items"], session_items, id)
	if def.is_empty():
		return {}
	var card := {"title": ItemRules.display_name(data["items"], session_items, id), "icon": "items/" + id, "desc": "",
		"dice": [], "status": [], "notes": [], "props": [], "cost": [], "foot": ItemInfo.meta_parts(def, false)}
	if def.has("unknown_of"):  # v0.7.12: an unidentified thing shows only what it looks like
		var base := str(def.get("base", ""))
		var look := ItemRules.def_of(data["items"], session_items, base) if (def.has("weapon") or def.has("armor")) and not base.is_empty() else def
		card["sub"] = ItemInfo.kind_name(look)
		card["notes"].append(_t("ITEM_UNKNOWN"))
		return card
	var rarity := str(def.get("rarity", ""))
	card["sub"] = ItemInfo.kind_name(def)
	if not rarity.is_empty() and rarity != "common":
		card["sub"] = "%s · %s" % [_t("RARITY_" + rarity.to_upper()), card["sub"]] if not str(card["sub"]).is_empty() else _t("RARITY_" + rarity.to_upper())
		card["title_color"] = str(IconRules.cfg(data).get("rarity", {}).get(rarity, ""))
	if def.has("weapon"):
		_weapon(c, data, session_items, id, def, card)
	elif def.has("armor"):
		var a: Dictionary = def["armor"]
		var ac := int(a["base"]) + ItemRules.plus(def, ["ac_plus", "magic_plus"])
		if str(a["category"]) == "shield":
			card["big"] = _t("CARD_BIG_SHIELD").format({"n": ac})
		else:
			var dex := "" if not bool(a["dex"]) else (_t("ITEM_DEX") if a.get("max_dex") == null else _t("ITEM_DEX_MAX").format({"n": int(a["max_dex"])}))
			card["big"] = _t("ITEM_AC").format({"n": ac}) + dex
			if int(a.get("str_min", 0)) > 0:
				card["props"].append(_t("ITEM_STR_MIN").format({"n": int(a["str_min"])}))
			if bool(a.get("stealth_disadvantage", false)):
				card["props"].append(_t("ITEM_STEALTH_DIS"))
	for p: String in ItemInfo.property_names(def):
		card["props"].append(p)
	var marked := ItemInfo.marks_line(c, data, id)  # v0.8.4.35: what a service laid on a copy
	if not marked.is_empty():
		card["notes"].append(marked)
	card["notes"].append_array(ItemInfo.notes(c, data, session_items, id, def))
	card["desc"] = str(def.get("description", ""))
	if not str(def.get("text", "")).is_empty():  # a letter, a diary, an inscription (v0.7.18)
		card["notes"].append(_t("ITEM_WRITTEN").format({"text": def["text"]}))
	var cmp := ItemInfo.compare(c, data, session_items, id)
	if not cmp.is_empty():
		card["notes"].append(cmp)
	return card


## A weapon's blow: the damage range by the one who holds it, its dice by type, two hands and the range.
static func _weapon(c: Dictionary, data: Dictionary, session_items: Dictionary, id: String, def: Dictionary, card: Dictionary) -> void:
	var w: Dictionary = def["weapon"]
	var lo := 0
	var hi := 0
	if not c.is_empty():
		var p := CombatRules.weapon_profile(c, data, session_items, id)
		var r := CombatRules.dice_range(str(p["dice"]))
		lo = maxi(1, r[0] + int(p["bonus"]))
		hi = maxi(1, r[1] + int(p["bonus"]))
		card["dice"].append({"text": ItemInfo.damage_text(p), "type": damage_name(data, str(p.get("type", ""))), "color": ""})
	else:
		var plus := ItemRules.plus(def, ["magic_plus"])
		var r := CombatRules.dice_range(str(w.get("damage", "")))
		lo = r[0] + plus
		hi = r[1] + plus
		card["dice"].append({"text": ItemInfo.dice_text(str(w.get("damage", ""))) + ("+%d" % plus if plus > 0 else ""),
			"type": damage_name(data, str(w.get("damage_type", ""))), "color": ""})
	for el: Dictionary in ItemRules.elements(data, def):
		var er := CombatRules.dice_range(str(el["dice"]))
		lo += er[0]
		hi += er[1]
		card["dice"].append({"text": "+" + ItemInfo.dice_text(str(el["dice"])), "type": damage_name(data, str(el["type"])), "color": element_color(data, str(el["type"]))})
	card["big"] = _t("CARD_BIG_DAMAGE").format({"lo": lo, "hi": hi})
	if w.has("versatile"):
		card["props"].append(_t("ITEM_VERSATILE").format({"dice": ItemInfo.dice_text(str(w["versatile"]))}))
	var rng: Array = w.get("reach_ft", [])
	if rng.size() == 2:
		card["props"].append("%s %s" % [RANGE, _t("ITEM_RANGE").format({"near": int(rng[0]), "far": int(rng[1])})])


## A class feature, a race trait or a resource of Stock (its first feature), with the uses `c` has left.
static func feature(data: Dictionary, id: String, c: Dictionary = {}) -> Dictionary:
	var feats: Dictionary = data["classes"]["features"]
	var traits: Dictionary = data["races"]["traits"]
	var res := Stock.table(data, c)
	var fid := id
	if not feats.has(fid) and not traits.has(fid) and res.has(id):
		for f: Variant in (res[id].get("features", []) as Array) + (res[id].get("traits", []) as Array):
			if feats.has(str(f)) or traits.has(str(f)):
				fid = str(f)
				break
	var row: Dictionary = feats.get(fid, traits.get(fid, {}))
	if row.is_empty():
		return {}
	var card := {"title": str(row.get("name", fid)), "icon": "features/" + fid if feats.has(fid) else "traits/" + fid, "desc": str(row.get("desc", "")),
		"dice": [], "status": [], "notes": [], "props": [], "cost": [], "foot": []}
	if feats.has(fid):
		var cls := str(data["classes"]["classes"].get(str(row.get("class", "")), {}).get("name", ""))
		card["sub"] = _t("CARD_FEATURE_SUB").format({"class": cls, "n": int(row.get("level", 1))}) if not cls.is_empty() else _t("CARD_FEATURE")
	else:
		card["sub"] = _t("CARD_TRAIT_SUB")
	var rid := id if res.has(id) else ""
	if rid.is_empty():
		for r: String in res:
			if (res[r].get("features", []) as Array).has(fid) or (res[r].get("traits", []) as Array).has(fid):
				rid = r
				break
	if not rid.is_empty():
		var spec: Dictionary = res[rid]
		var back := _t("CARD_RECHARGE_" + (Stock.recharge(c, data, rid) if not c.is_empty() else str(spec.get("recharge", "long"))).to_upper())
		if not c.is_empty() and Stock.max_uses(c, data, rid) > 0:
			card["props"].append("%s %s · %s" % [USES, _t("CARD_USES").format({"left": Stock.left(c, data, rid), "max": Stock.max_uses(c, data, rid)}), back])
		else:
			card["props"].append("%s %s" % [USES, back])
		var how := str(spec.get("combat_cost", ""))
		if how in ["action", "bonus", "reaction"]:
			card["cost"].append(cost(how))
	return card


## An act of a fight (Act): its name, what it does, what it costs `f` now.
static func act(s: GameSession, data: Dictionary, f: Dictionary, a: Act, tip: String = "") -> Dictionary:
	var card := {"title": a.title(), "icon": "acts/" + a.id, "desc": tip if not tip.is_empty() else a.tip(), "sub": _t("CARD_ACT"),
		"dice": [], "status": [], "notes": [], "props": [], "cost": [], "foot": []}
	if s != null and not f.is_empty():  # out of a fight by a copy: the points of a turn are never written on the hero's key
		card["cost"].append(cost(a.cost(s, data, f.duplicate() if f.is_read_only() else f, {})))
	return card


## A cost by its kind: «● Действие», «▲ Бонусное действие», «◆ Реакция», «➜ Перемещение», «○ Без действия».
static func cost(kind: String) -> Dictionary:
	var k := "action" if kind == "attack" else kind
	return {"kind": k, "text": _t("CARD_COST_" + k.to_upper())}


## The cost of a spell by its casting time: an action, a bonus action, a reaction, or a while («⧗ 1 минута»).
static func time_cost(casting_time: String) -> Dictionary:
	var t := casting_time.to_lower()
	if t.contains("бонус"):
		return cost("bonus")
	if t.contains("реакц"):
		return cost("reaction")
	if t.contains("действ") or t.is_empty():
		return cost("action")
	return {"kind": "time", "text": casting_time}


## The plain text of a card: what a test, the chat and an old window read.
static func plain(card: Dictionary) -> String:
	var out: Array[String] = []
	for k: String in ["sub", "big"]:
		if not str(card.get(k, "")).is_empty():
			out.append(str(card[k]))
	for d: Dictionary in card.get("dice", []):
		out.append(("%s %s" % [d["text"], d.get("type", "")]).strip_edges())
	for st: Dictionary in card.get("status", []):
		out.append(str(st["text"]))
	if not str(card.get("desc", "")).is_empty():
		out.append(str(card["desc"]))
	for n: Variant in card.get("notes", []):
		out.append(str(n))
	if not (card.get("props", []) as Array).is_empty():
		out.append(" · ".join(card["props"]))
	var costs: Array = (card.get("cost", []) as Array).map(func(x: Dictionary) -> String: return str(x["text"]))
	if not costs.is_empty():
		out.append(" · ".join(costs))
	if not (card.get("foot", []) as Array).is_empty():
		out.append(" · ".join(card["foot"]))
	return "\n".join(out)


## The word of a damage type: «огонь», «рубящий».
static func damage_name(data: Dictionary, type: String) -> String:
	return str(data["misc"]["damage_types"].get(type, type))


## The colour of a damage type's element (data/icons.json `elements`); "" for a weapon's own.
static func element_color(data: Dictionary, type: String) -> String:
	return str(IconRules.cfg(data).get("elements", {}).get(type, ""))


## Dice in words: «1к8+3»; a caster's MOD by its number, or «+ мод.» when there is no caster.
static func _mod_dice(dice: String, mod: int, known: bool) -> String:
	var d := ItemInfo.dice_text(dice)
	if not d.contains("MOD"):
		return d
	return d.replace("+MOD", ("%+d" % mod) if known else _t("CARD_PLUS_MOD"))


static func _t(key: String) -> String:
	return TranslationServer.translate(key)
