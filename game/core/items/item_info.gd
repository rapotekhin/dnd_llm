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
	if def.has("unknown_of"):  # v0.7.12: an unidentified thing shows only what it looks like
		if def.has("weapon") or def.has("armor"):
			out.append(kind_line(data, ItemRules.def_of(data["items"], session_items, str(def.get("base", "")))) if not str(def.get("base", "")).is_empty() else kind_line(data, def))
		out.append(_t("ITEM_UNKNOWN"))
		return out
	var head := kind_line(data, def)
	if not head.is_empty():
		out.append(head)
	var props := properties_line(def)
	if not props.is_empty():
		out.append(props)
	var marked := marks_line(c, data, id)  # v0.8.4.35: what a service laid on a copy
	if not marked.is_empty():
		out.append(marked)
	var meta := meta_parts(def, true)
	if not meta.is_empty():
		out.append(" · ".join(meta))
	out.append_array(notes(c, data, session_items, id, def))
	var text := str(def.get("description", ""))
	if not text.is_empty():
		out.append(text)
	if not str(def.get("text", "")).is_empty():  # a letter, a diary, an inscription (v0.7.18)
		out.append(TranslationServer.translate("ITEM_WRITTEN").format({"text": def["text"]}))
	return out


## Rarity, weight and price of a thing: «Редкий», «6 фнт», «10 зм» (the rarity only when asked and not common).
static func meta_parts(def: Dictionary, rarity_too: bool) -> Array[String]:
	var meta: Array[String] = []
	var rarity := str(def.get("rarity", ""))
	if rarity_too and not rarity.is_empty() and rarity != "common":
		meta.append(TranslationServer.translate("RARITY_" + rarity.to_upper()))
	if float(def.get("weight", 0)) > 0:
		meta.append(TranslationServer.translate("ITEM_WEIGHT").format({"n": _num(float(def["weight"]))}))
	if int(def.get("value_cp", 0)) > 0:
		meta.append(Money.format(int(def["value_cp"])))
	return meta


## What a thing does beyond its numbers, a line each: proficiency, use, what it lays worn or on a hit, its spells and
## charges, attunement, spoiling, a curse, the master's making (the lines of the card and of `lines`).
static func notes(c: Dictionary, data: Dictionary, session_items: Dictionary, id: String, def: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var prof := proficiency_line(c, def, ItemRules.plain_of(data["items"], session_items, id))
	if not prof.is_empty():
		out.append(prof)
	var use := use_line(data, id, session_items)
	if not use.is_empty():
		out.append(use)
	if def.get("wear") is Dictionary:  # v0.8.4.26: what it lays while it works, in the words of a spell's effect
		out.append(_t("ITEM_WEAR").format({"what": SpellEffects.text(data, ItemRules.wear_spec(c, data, def))}))
	if def.get("hit") is Dictionary:  # v0.8.4.36: what a weapon lays on the one it strikes
		out.append(_t("ITEM_HIT").format({"what": MonsterRules.effect_text(data, {"effect": ItemRules.hit_effect(def)})}))
	var spells: Array[String] = []
	for r: Dictionary in def.get("spells", []):
		var rid := "item:%s:%s" % [ItemRules.real_id(id), r["spell"]]
		var have := (c.get("item_stock", {}) as Dictionary).has(rid)
		spells.append("%s %s" % [data["spells"].get(str(r["spell"]), {}).get("name", r["spell"]),
			("%d/%d" % [Stock.left(c, data, rid), int(r["uses"])]) if have else "×%d" % int(r["uses"])])
	if not spells.is_empty():
		out.append(_t("ITEM_SPELLS").format({"list": ", ".join(spells)}))
	if int(def.get("store", 0)) > 0:
		var kept: Array = ItemRules.stored(c, id, def).map(func(k: Dictionary) -> String: return "%s (%d)" % [data["spells"].get(str(k["spell"]), {}).get("name", k["spell"]), int(k["circle"])])
		out.append(_t("ITEM_STORE").format({"n": int(def["store"]), "list": ", ".join(kept) if not kept.is_empty() else _t("ITEM_STORE_EMPTY")}))
	if ItemRules.charges_max(def) > 0:  # v0.7.12
		out.append(_t("ITEM_CHARGES").format({"left": ItemRules.charges_left(c, def, id) if not c.is_empty() else ItemRules.charges_max(def), "max": ItemRules.charges_max(def)}))
	if ItemRules.needs_attunement(def):
		out.append(_t("ITEM_ATTUNED") if not c.is_empty() and ItemRules.attuned(c).has(id) else _t("ITEM_NEEDS_ATTUNEMENT"))
	elif str(def.get("item_type", "")) == "wondrous" and (not (def.get("properties", []) as Array).is_empty() or def.has("wear")) and not id.begins_with(ItemRules.UNKNOWN):
		# big test #23: a worn kind works only worn (v0.7.22.9), a stone or a pearl — in the pack
		out.append(_t("ITEM_WORN_TO_WORK" if not CharacterRules.wear_slot(def, data).is_empty() else "ITEM_WORKS_CARRIED"))
	if int(def.get("spoils_days", 0)) > 0 and def.has("spoils_to"):  # a clockwork of a tinker gnome winds down (v0.8.4.43.46)
		out.append(_t("ITEM_WINDS_DOWN").format({"n": int(def["spoils_days"]), "to": ItemRules.display_name(data["items"], {}, str(def["spoils_to"]))}))
	elif int(def.get("spoils_days", 0)) > 0:
		out.append(_t("ITEM_SPOILS").format({"n": int(def["spoils_days"])}))
	if ItemRules.cursed(def):
		out.append(_t("ITEM_CURSED_LINE"))
	if bool(def.get("master", false)):
		out.append(_t("ITEM_MASTER"))
	return out


## The kind of a thing in a word, without its numbers: «Воинское оружие ближнего боя», «Тяжёлый доспех», «Щит», «Снаряжение».
static func kind_name(def: Dictionary) -> String:
	if def.has("weapon"):
		var w: Dictionary = def["weapon"]
		return _t("ITEM_WEAPON_%s_%s" % [str(w.get("category", "simple")).to_upper(), str(w.get("range", "melee")).to_upper()])
	if def.has("armor"):
		var cat := str(def["armor"]["category"])
		return _t("ITEM_SHIELD") if cat == "shield" else _t("ITEM_ARMOR_" + cat.to_upper())
	var it := str(def.get("item_type", ""))
	return "" if it.is_empty() else _t("ITEM_TYPE_" + it.to_upper())


## «Воинское оружие ближнего боя · 1к8 рубящий (двумя руками 1к10)», «Тяжёлый доспех · КД 16 · Сила 13 · помеха
## Скрытности», «Щит · КД +2», or the kind of a plain thing.
static func kind_line(data: Dictionary, def: Dictionary) -> String:
	if def.has("weapon"):
		var w: Dictionary = def["weapon"]
		var kind := kind_name(def)
		var dmg := "%s %s" % [dice_text(str(w.get("damage", ""))), str(data["misc"]["damage_types"].get(str(w.get("damage_type", "")), ""))]
		var plus := ItemRules.plus(def, ["magic_plus"])
		if plus > 0:
			dmg = "%s +%d" % [dmg, plus]
		dmg += _elements(data, def)
		var parts: Array[String] = [kind, dmg.strip_edges()]
		if w.has("versatile"):
			parts.append(_t("ITEM_VERSATILE").format({"dice": dice_text(str(w["versatile"]))}))
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
		var parts: Array[String] = [kind_name(def), "%s%s" % [_t("ITEM_AC").format({"n": int(a["base"]) + plus}), dex]]
		if int(a.get("str_min", 0)) > 0:
			parts.append(_t("ITEM_STR_MIN").format({"n": int(a["str_min"])}))
		if bool(a.get("stealth_disadvantage", false)):
			parts.append(_t("ITEM_STEALTH_DIS"))
		return " · ".join(parts)
	return kind_name(def)


## «Свойства: фехтовальное, лёгкое, магическое +1»; "" when none to show.
static func properties_line(def: Dictionary) -> String:
	var names := property_names(def)
	return "" if names.is_empty() else TranslationServer.translate("ITEM_PROPERTIES").format({"list": ", ".join(names)})


## The words of a thing's properties: «фехтовальное», «лёгкое», a made property's own name.
static func property_names(def: Dictionary) -> Array[String]:
	var names: Array[String] = []
	for p: Variant in def.get("properties", []):
		var key := "ITEM_PROP_" + str(p).to_upper()
		var n := TranslationServer.translate(key)
		if n != key and not n.is_empty():
			names.append(n)
	for n: Variant in def.get("built", []):
		names.append(str(n))
	return names


## «Сделано у мастера: посеребрено — 1 из 2»: the marks of the copies `h` holds (v0.8.4.35); "" when none.
static func marks_line(h: Dictionary, data: Dictionary, id: String) -> String:
	if h.is_empty():
		return ""
	var n := Thing.count(h, id)
	var marked := 0
	var names: Array[String] = []
	for i in n:
		var m := ItemRules.marks(h, id, i)
		marked += 1 if not m.is_empty() else 0
		for p: Variant in m:
			var name := mark_name(data, str(p))
			if not names.has(name):
				names.append(name)
	if marked == 0:
		return ""
	if marked == n:
		return _t("ITEM_MARKS").format({"list": ", ".join(names)})
	return _t("ITEM_MARKS_SOME").format({"list": ", ".join(names), "n": marked, "of": n})


## A mark's word: the sheet's name of a property, a made property's own, or the token.
static func mark_name(data: Dictionary, p: String) -> String:
	var names: Dictionary = data["rules"].get("item_props", {}).get("names", {})
	if names.has(p):
		return str(names[p])
	var built: Dictionary = data["items"].get("built", {})
	if built.has(p):
		return str(built[p]["name"])
	var key := "ITEM_PROP_" + p.to_upper()
	var n := TranslationServer.translate(key)
	return p if n == key else n.get_slice(":", 0)


## Weapons and armor the hero is not trained with: no proficiency bonus / disadvantage and no spells in armor. `id` is the
## plain kind of the thing (`ItemRules.plain_of`): a fine storm longsword asks the longsword.
static func proficiency_line(c: Dictionary, def: Dictionary, id: String) -> String:
	if c.is_empty():
		return ""
	if def.has("weapon"):
		if not CombatRules.weapon_proficient(c, def["weapon"], id):
			return TranslationServer.translate("ITEM_NO_PROF_WEAPON")
	elif def.has("armor"):
		var cat := str(def["armor"]["category"])
		if not (c.get("armor_profs", []) as Array).has(cat):
			return TranslationServer.translate("ITEM_NO_PROF_ARMOR")
	return ""


## What using a consumable does (rules.consumables): «Лечит 2к4+2 хитов», «Снимает: отравление».
static func use_line(data: Dictionary, id: String, session_items: Dictionary = {}) -> String:
	var fx := ItemRules.consumable(data, id, session_items)
	var parts: Array[String] = []
	if fx.has("heal"):
		var h: Array = fx["heal"]
		parts.append(TranslationServer.translate("ITEM_USE_HEAL").format({"dice": "%dк%d%s" % [int(h[0]), int(h[1]), ("+%d" % int(h[2])) if int(h[2]) > 0 else ""]}))
	if fx.has("remove"):
		var names: Array = (fx["remove"] as Array).map(func(x: Variant) -> String:
			return str(data["rules"]["conditions"].get(str(x), x)).get_slice(":", 0).to_lower())
		parts.append(TranslationServer.translate("ITEM_USE_REMOVE").format({"list": ", ".join(names)}))
	if fx.has("throw"):
		parts.append(_t("ITEM_USE_THROW"))
	if fx.has("spell"):
		var sp: Dictionary = data["spells"].get(str(fx["spell"]), {})
		parts.append(_t("ITEM_USE_SPELL").format({"spell": sp.get("name", fx["spell"]), "n": int(fx.get("level", 1))}))
	if fx.has("summon"):  # v0.8.4.26: a row of the summons
		var sp := AllyRules.summon_spec(data, ItemRules.summon_key(id, fx), session_items)
		var who: Array = (sp.get("pick", [sp.get("monster", "")]) as Array).map(func(m: Variant) -> String: return str(data["monsters"].get(str(m), {}).get("name", m)))
		parts.append(_t("ITEM_USE_SUMMON").format({"who": " или ".join(who)}))
	if bool(fx.get("at_will", false)):
		parts.append(_t("ITEM_USE_AT_WILL"))
	if fx.has("resist"):
		parts.append(_t("ITEM_USE_RESIST").format({"type": str(data["misc"]["damage_types"].get(str(fx["resist"]), fx["resist"]))}))
	if fx.has("recover_slot"):
		parts.append(_t("ITEM_USE_SLOT"))
	if fx.has("meal"):  # a dish (v0.7.25)
		var m: Dictionary = fx["meal"]
		var food := int(data["rules"]["hero_effects"]["camp"]["food"].get(ItemRules.real_id(id), 0)) * int(data["rules"].get("needs", {}).get("food", {}).get("points", 0))
		if food > 0:
			parts.append(_t("ITEM_USE_FOOD").format({"n": food}))
		if int(m.get("water", 0)) > 0:
			parts.append(_t("ITEM_USE_WATER").format({"n": int(m["water"])}))
		if int(m.get("temp_hp", 0)) > 0:
			parts.append(_t("ITEM_USE_TEMP_HP").format({"n": int(m["temp_hp"])}))
		if fx.has("adv_tag"):
			parts.append(_t("ITEM_USE_ADV").format({"tag": HeroDefense.tag_name(str(fx["adv_tag"]))}))
	return " · ".join(parts)


## How the item compares with what is worn now: «КД 16 → 18», «атака +5, 1к8+3 (сейчас +4, 1к6+2)»; "" for the rest
## or when it is the worn one.
static func compare(c: Dictionary, data: Dictionary, session_items: Dictionary, id: String) -> String:
	if c.is_empty():
		return ""
	var def := ItemRules.def_of(data["items"], session_items, id)
	var slot := CharacterRules.slot_for(def, data)
	var eq: Dictionary = c.get("equipped", {})
	if slot.is_empty() or str(eq.get(slot, "")) == id:
		return ""
	if slot == "armor" or CharacterRules.is_shield(def):  # a shield into the off hand: what it held goes to the pack
		var probe := c.duplicate(true)
		probe["equipped"][slot] = id
		var now := CharacterRules.armor_class(c, data, session_items)
		var then := CharacterRules.armor_class(probe, data, session_items)
		return TranslationServer.translate("ITEM_CMP_AC").format({"now": now, "then": then})
	if slot != "main_hand":  # a ring, a cloak, boots: what it replaces
		var worn := str(eq.get(slot, ""))
		if worn.is_empty():
			return ""
		return TranslationServer.translate("ITEM_CMP_WORN").format({"name": ItemRules.display_name(data["items"], session_items, worn)})
	var cur := CombatRules.weapon_profile(c, data, session_items, str(eq.get("main_hand", "")))
	var probe := c.duplicate(true)
	probe["equipped"]["main_hand"] = id
	var neu := CombatRules.weapon_profile(probe, data, session_items, id)
	return TranslationServer.translate("ITEM_CMP_WEAPON").format({"hit": _signed(int(neu["to_hit"])), "dmg": damage(data, session_items, neu),
		"hit_now": _signed(int(cur["to_hit"])), "dmg_now": damage(data, session_items, cur)})


static func _t(key: String) -> String:
	return TranslationServer.translate(key)


static func damage_text(w: Dictionary) -> String:
	var b := int(w["bonus"])
	return "%s%s" % [dice_text(str(w["dice"])), ("+%d" % b) if b > 0 else (str(b) if b < 0 else "")]


## A weapon's whole damage by its profile: «1к4+2 колющий + 1к6 огонь» (v0.8.4.30, the author's feedback: the fire of an
## elemental blade was told only in its description).
static func damage(data: Dictionary, session_items: Dictionary, w: Dictionary) -> String:
	var main := "%s %s" % [damage_text(w), str(data["misc"]["damage_types"].get(str(w.get("type", "")), ""))]
	return main.strip_edges() + _elements(data, ItemRules.def_of(data["items"], session_items, str(w.get("id", ""))))


static func _elements(data: Dictionary, def: Dictionary) -> String:
	var out := ""
	for el: Dictionary in ItemRules.elements(data, def):
		out += " + %s %s" % [dice_text(str(el["dice"])), data["misc"]["damage_types"][el["type"]]]
	return out


static func dice_text(d: String) -> String:
	return d.replace("d", "к")


static func _signed(n: int) -> String:
	return ("+%d" % n) if n >= 0 else str(n)


static func _num(x: float) -> String:
	return str(int(x)) if is_equal_approx(x, roundf(x)) else String.num(x, 2)
