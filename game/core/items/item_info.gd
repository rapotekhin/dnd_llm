class_name ItemInfo
extends RefCounted
## What an item is, for the inventory, the trade and the sheet (roadmap v0.7.7, the author's request): its kind, damage
## or AC, properties, rarity, weight, price, proficiency, what a consumable does, the description, and how it compares
## with what the hero wears now. Text keys of the UI are localization keys; the numbers come from the engine rules.

## Short lines about the item: [kind and numbers, properties, rarity · weight · price, proficiency, use, description].
static func lines(c: Dictionary, data: Dictionary, session_items: Dictionary, id: String) -> Array[String]:
	var def := ItemRules.def_of(data["items"], session_items, id)
	var out: Array[String] = []
	if def.is_empty():
		return out
	var head := kind_line(data, def)
	if not head.is_empty():
		out.append(head)
	var props := properties_line(def)
	if not props.is_empty():
		out.append(props)
	var meta: Array[String] = []
	var rarity := str(def.get("rarity", ""))
	if not rarity.is_empty() and rarity != "common":
		meta.append(TranslationServer.translate("RARITY_" + rarity.to_upper()))
	if float(def.get("weight", 0)) > 0:
		meta.append(TranslationServer.translate("ITEM_WEIGHT").format({"n": _num(float(def["weight"]))}))
	if int(def.get("value_cp", 0)) > 0:
		meta.append(Money.format(int(def["value_cp"])))
	if not meta.is_empty():
		out.append(" · ".join(meta))
	var prof := proficiency_line(c, def, id)
	if not prof.is_empty():
		out.append(prof)
	var use := use_line(data, id)
	if not use.is_empty():
		out.append(use)
	var text := str(def.get("description", ""))
	if not text.is_empty():
		out.append(text)
	return out


## «Воинское оружие ближнего боя · 1к8 рубящий (двумя руками 1к10)», «Тяжёлый доспех · КД 16 · Сила 13 · помеха
## Скрытности», «Щит · КД +2», or the kind of a plain thing.
static func kind_line(data: Dictionary, def: Dictionary) -> String:
	if def.has("weapon"):
		var w: Dictionary = def["weapon"]
		var kind: String = _t("ITEM_WEAPON_%s_%s" % [str(w.get("category", "simple")).to_upper(), str(w.get("range", "melee")).to_upper()])
		var dmg := "%s %s" % [_dice(str(w.get("damage", ""))), str(data["misc"]["damage_types"].get(str(w.get("damage_type", "")), ""))]
		var plus := ItemRules.plus(def, ["magic_plus"])
		if plus > 0:
			dmg = "%s +%d" % [dmg, plus]
		var parts: Array[String] = [kind, dmg.strip_edges()]
		if w.has("versatile"):
			parts.append(_t("ITEM_VERSATILE").format({"dice": _dice(str(w["versatile"]))}))
		var rng: Array = w.get("reach_ft", [])
		if rng.size() == 2:
			parts.append(_t("ITEM_RANGE").format({"near": int(rng[0]), "far": int(rng[1])}))
		return " · ".join(parts)
	if def.has("armor"):
		var a: Dictionary = def["armor"]
		var plus := ItemRules.plus(def, ["ac_plus", "magic_plus"])
		if str(a["category"]) == "shield":
			return _t("ITEM_SHIELD_LINE").format({"n": int(a["base"]) + plus})
		var dex := "" if not bool(a["dex"]) else (_t("ITEM_DEX") if a.get("max_dex") == null else _t("ITEM_DEX_MAX").format({"n": int(a["max_dex"])}))
		var parts: Array[String] = [_t("ITEM_ARMOR_" + str(a["category"]).to_upper()), "%s%s" % [_t("ITEM_AC").format({"n": int(a["base"]) + plus}), dex]]
		if int(a.get("str_min", 0)) > 0:
			parts.append(_t("ITEM_STR_MIN").format({"n": int(a["str_min"])}))
		if bool(a.get("stealth_disadvantage", false)):
			parts.append(_t("ITEM_STEALTH_DIS"))
		return " · ".join(parts)
	var it := str(def.get("item_type", ""))
	return "" if it.is_empty() else _t("ITEM_TYPE_" + it.to_upper())


## «Свойства: фехтовальное, лёгкое, магическое +1»; "" when none to show.
static func properties_line(def: Dictionary) -> String:
	var names: Array[String] = []
	for p: Variant in def.get("properties", []):
		var key := "ITEM_PROP_" + str(p).to_upper()
		var n := TranslationServer.translate(key)
		if n != key and not n.is_empty():
			names.append(n)
	return "" if names.is_empty() else TranslationServer.translate("ITEM_PROPERTIES").format({"list": ", ".join(names)})


## Weapons and armor the hero is not trained with: no proficiency bonus / disadvantage and no spells in armor.
static func proficiency_line(c: Dictionary, def: Dictionary, id: String) -> String:
	if c.is_empty():
		return ""
	if def.has("weapon"):
		var profs: Array = c.get("weapon_profs", [])
		var base := str(def.get("base", id))
		if not (profs.has(str(def["weapon"].get("category", ""))) or profs.has(id) or profs.has(base)):
			return TranslationServer.translate("ITEM_NO_PROF_WEAPON")
	elif def.has("armor"):
		var cat := str(def["armor"]["category"])
		if not (c.get("armor_profs", []) as Array).has(cat):
			return TranslationServer.translate("ITEM_NO_PROF_ARMOR")
	return ""


## What using a consumable does (rules.consumables): «Лечит 2к4+2 хитов», «Снимает: отравление».
static func use_line(data: Dictionary, id: String) -> String:
	var fx := ItemRules.consumable(data, id)
	var parts: Array[String] = []
	if fx.has("heal"):
		var h: Array = fx["heal"]
		parts.append(TranslationServer.translate("ITEM_USE_HEAL").format({"dice": "%dк%d%s" % [int(h[0]), int(h[1]), ("+%d" % int(h[2])) if int(h[2]) > 0 else ""]}))
	if fx.has("remove"):
		var names: Array = (fx["remove"] as Array).map(func(x: Variant) -> String:
			return str(data["rules"]["conditions"].get(str(x), x)).get_slice(":", 0).to_lower())
		parts.append(TranslationServer.translate("ITEM_USE_REMOVE").format({"list": ", ".join(names)}))
	return " · ".join(parts)


## How the item compares with what is worn now: «КД 16 → 18», «атака +5, 1к8+3 (сейчас +4, 1к6+2)»; "" for the rest
## or when it is the worn one.
static func compare(c: Dictionary, data: Dictionary, session_items: Dictionary, id: String) -> String:
	if c.is_empty():
		return ""
	var def := ItemRules.def_of(data["items"], session_items, id)
	var slot := CharacterRules.slot_for(def)
	var eq: Dictionary = c.get("equipped", {})
	if slot.is_empty() or str(eq.get(slot, "")) == id:
		return ""
	if slot == "armor" or slot == "shield":
		var probe := c.duplicate(true)
		probe["equipped"][slot] = id
		if slot == "shield" and not str(eq.get("off_hand", "")).is_empty():
			probe["equipped"]["off_hand"] = ""
		var now := CharacterRules.armor_class(c, data, session_items)
		var then := CharacterRules.armor_class(probe, data, session_items)
		return TranslationServer.translate("ITEM_CMP_AC").format({"now": now, "then": then})
	var cur := CombatRules.weapon_profile(c, data, session_items, str(eq.get("main_hand", "")))
	var probe := c.duplicate(true)
	probe["equipped"]["main_hand"] = id
	var neu := CombatRules.weapon_profile(probe, data, session_items, id)
	return TranslationServer.translate("ITEM_CMP_WEAPON").format({"hit": _signed(int(neu["to_hit"])), "dmg": _dmg(neu),
		"hit_now": _signed(int(cur["to_hit"])), "dmg_now": _dmg(cur)})


static func _t(key: String) -> String:
	return TranslationServer.translate(key)


static func _dmg(w: Dictionary) -> String:
	var b := int(w["bonus"])
	return "%s%s" % [_dice(str(w["dice"])), ("+%d" % b) if b > 0 else (str(b) if b < 0 else "")]


static func _dice(d: String) -> String:
	return d.replace("d", "к")


static func _signed(n: int) -> String:
	return ("+%d" % n) if n >= 0 else str(n)


static func _num(x: float) -> String:
	return str(int(x)) if is_equal_approx(x, roundf(x)) else String.num(x, 2)
