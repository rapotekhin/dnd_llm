class_name HeroDefense
extends RefCounted
## Damage to the hero and the hero's saves by 5e (roadmap v0.7.8): resistances, vulnerabilities and immunities like
## a foe's — from race traits (dwarf, tiefling, dragonborn by ancestry), Rage, items (resist_*), effects (a cure's
## boon), petrification; advantage on saves of a tag from race traits (dwarf — poison, elf — charm, halfling — fear,
## gnome — magic against INT / WIS / CHA) and effects (antitoxin); immunity of an elf to magical sleep; a
## concentration save after damage; Relentless Endurance of a half-orc. Tables — rules.hero_effects.

const TAG_NAMES := {"poison": "яд", "charm": "очарование", "fear": "страх", "magic": "магия", "sleep": "сон", "disease": "болезнь"}


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"]["hero_effects"]


static func tag_name(tag: String) -> String:
	return str(TAG_NAMES.get(tag, tag))


## A damage type id by its id or Russian name («огонь», «fire»); "" when unknown.
static func damage_type(data: Dictionary, text: String) -> String:
	var t := text.strip_edges().to_lower()
	var types: Dictionary = data["misc"]["damage_types"]
	if types.has(t):
		return t
	for id: String in types:
		if str(types[id]).to_lower() == t or (not t.is_empty() and str(types[id]).to_lower().begins_with(t.left(4))):
			return id
	return ""


## The hero's damage types resisted now, with where each comes from: {type: source name}.
static func resistances(s: GameSession, data: Dictionary) -> Dictionary:
	var c := s.character
	var out := {}
	var traits: Dictionary = data["races"]["traits"]
	var by_trait: Dictionary = cfg(data)["trait_resist"]
	for t: String in by_trait:
		if not CharacterRules.has_trait(c, t):
			continue
		var name := str(traits.get(t, {}).get("name", t))
		if by_trait[t] is Array:
			for x: Variant in by_trait[t]:
				out[str(x)] = name
		elif str(by_trait[t]) == "ancestry":
			for id: Variant in c.get("traits", []):
				var dt := str(traits.get(str(id), {}).get("damage_type", ""))
				if str(id).begins_with("draconic_ancestry_") and not dt.is_empty():
					out[dt] = name
	if CombatRules.active(s) and bool(s.combat.get("raging", false)):
		for x: Variant in cfg(data)["rage_resist"]:
			out[str(x)] = "Ярость"
	var by_item: Dictionary = cfg(data)["item_resist"]
	for d: Dictionary in _worn(c, data, s.items):
		for p: Variant in d.get("properties", []):
			if by_item.has(str(p)):
				out[str(by_item[str(p)])] = str(d.get("name", ""))
	for e: Dictionary in ConditionRules.effects(c):
		for x: Variant in e.get("resist", []):
			out[str(x)] = str(e.get("source", {}).get("name", ""))
	return out


## Carried wondrous items and the equipped gear: where resist_* properties work.
static func _worn(c: Dictionary, data: Dictionary, session_items: Dictionary) -> Array[Dictionary]:
	var out := CharacterRules.carried(c, data, session_items)
	for slot: String in CharacterRules.SLOTS:
		var id := str(c.get("equipped", {}).get(slot, ""))
		if not id.is_empty():
			out.append(ItemRules.def_of(data["items"], session_items, id))
	return out


## Damage of one type to the hero after resistances: {"damage", "note"} («сопротивление: Ярость» or "").
static func adjust(s: GameSession, data: Dictionary, dtype: String, dmg: int) -> Dictionary:
	if dmg <= 0:
		return {"damage": maxi(0, dmg), "note": ""}
	if ConditionRules.has(s.character, "petrified"):
		return {"damage": dmg / 2, "note": "сопротивление: окаменение"}
	var res := resistances(s, data)
	if not dtype.is_empty() and res.has(dtype):
		return {"damage": dmg / 2, "note": "сопротивление: %s" % res[dtype]}
	return {"damage": dmg, "note": ""}


## Why the hero has advantage on a save of `ability` against `tag` now (race traits, effects; v0.7.10: Danger Sense
## on DEX saves, Rage on STR).
static func save_advantages(c: Dictionary, data: Dictionary, ability: String, tag: String, raging: bool = false) -> Array[String]:
	var out: Array[String] = []
	if ability == "dex" and CharacterRules.has_feature(c, "danger_sense") \
			and not ["blinded", "deafened"].any(func(x: String) -> bool: return ConditionRules.has(c, x)) and not ConditionRules.incapacitated(c):
		out.append(str(data["classes"]["features"].get("danger_sense", {}).get("name", "")))
	if ability == "str" and raging:
		out.append("ярость")
	if tag.is_empty():
		return out
	var tags := tag.split(",")  # a save against several things at once: «charm,magic» (v0.7.9)
	var traits: Dictionary = data["races"]["traits"]
	var table: Dictionary = cfg(data)["trait_saves"]
	for t: String in table:
		var spec: Dictionary = table[t]
		if CharacterRules.has_trait(c, t) and (spec["tags"] as Array).any(func(x: Variant) -> bool: return tags.has(str(x))) \
				and (not spec.has("abilities") or (spec["abilities"] as Array).has(ability)):
			out.append(str(traits.get(t, {}).get("name", t)))
	for e: Dictionary in ConditionRules.effects(c):
		if tags.has(str(e.get("adv_tag", ""))) and not out.has(str(e.get("source", {}).get("name", ""))):
			out.append(str(e.get("source", {}).get("name", "")))
	return out


## The race trait that makes the hero immune to `cond` laid with `tag` (an elf and magical sleep; a paladin's Divine
## Health and disease, v0.7.10), "" when none.
static func immune(c: Dictionary, data: Dictionary, cond: String, tag: String) -> String:
	if tag.split(",").has("disease") and CharacterRules.has_feature(c, "divine_health"):
		return str(data["classes"]["features"].get("divine_health", {}).get("name", ""))
	if tag.split(",").has("disease") and CharacterRules.item_prop(c, "immune_disease"):
		return "Амулет здоровья"  # Periapt of Health (v0.7.12)
	var table: Dictionary = cfg(data)["trait_immune"]
	for t: String in table:
		if CharacterRules.has_trait(c, t) and tag.split(",").has(str(table[t]["tag"])) and (table[t]["conditions"] as Array).has(cond):
			return str(data["races"]["traits"].get(t, {}).get("name", t))
	return ""


## A saving throw of the hero by the engine: the sheet's bonus, conditions (auto-fail of STR / DEX when paralysed,
## disadvantage of DEX when restrained), exhaustion 3+, advantages of the tag. Natural 20 / 1 succeed / fail.
## {"ok", "total", "text"} — «Тел 14 против Сл 13, с преимуществом (Стойкость дварфа) — успех».
static func save(s: GameSession, data: Dictionary, ability: String, dc: int, tag: String = "") -> Dictionary:
	var c := s.character
	var mods := ConditionRules.check_mods(c, data, {"save": ability})
	var bonus := int(c.get("saves", {}).get(ability, 0))
	var adv_why := save_advantages(c, data, ability, tag, CombatRules.active(s) and bool(s.combat.get("raging", false)))
	var adv := not adv_why.is_empty()
	var dis := not (mods["disadvantage"] as Array).is_empty()
	var rolls := FeatureRules.hero_d20(s, adv, dis)  # Lucky (v0.7.10)
	var nat: int = rolls.max() if adv and not dis else rolls.min() if dis and not adv else rolls[0]
	var total := nat + bonus
	var ok := nat == 20 or (nat != 1 and total >= dc)
	var note := ""
	if not ok and nat != 1 and (mods["auto_fail"] as Array).is_empty():
		var insp := FeatureRules.use_inspiration(s)  # Bardic Inspiration on a failed save
		if insp > 0:
			total += insp
			ok = total >= dc
			note = ", вдохновение +%d" % insp
	if not (mods["auto_fail"] as Array).is_empty():
		ok = false
		note += ", автопровал: " + ", ".join((mods["auto_fail"] as Array).map(func(x: Variant) -> String: return ConditionRules.name_of(data, str(x)).to_lower()))
	elif adv and not dis:
		note += ", с преимуществом (%s)" % ", ".join(adv_why)
	elif dis and not adv:
		note += ", с помехой (%s)" % ", ".join((mods["disadvantage"] as Array).map(func(x: Variant) -> String:
			return "истощение" if str(x) == "exhaustion" else ConditionRules.name_of(data, str(x)).to_lower()))
	return {"ok": ok, "total": total, "nat": nat,
		"text": "%s %d против Сл %d%s — %s" % [CombatRules.ab_name(ability), total, dc, note, "успех" if ok else "провал"]}


## After damage the hero still has: a concentration save (DC 10 or half the damage) and waking from an effect that
## ends on damage (sleep). Lines.
static func after_damage(s: GameSession, data: Dictionary, dmg: int) -> Array[String]:
	var c := s.character
	var lines: Array[String] = []
	if dmg <= 0:
		return lines
	for e: Dictionary in ConditionRules.effects(c).duplicate():
		if bool(e.get("wake", false)) and int(c.get("hp", 0)) > 0:
			ConditionRules.remove_effect(c, int(e["uid"]))
			lines.append("%s: %s проходит от удара" % [c.get("name", ""), ConditionRules.name_of(data, str(e.get("condition", ""))).to_lower()])
	var spell := str(c.get("concentration", ""))
	if not spell.is_empty() and int(c.get("hp", 0)) > 0:
		var r := save(s, data, "con", maxi(10, dmg / 2), "")
		if bool(r["ok"]):
			lines.append("концентрация удержана (%s)" % r["text"])
		else:
			lines.append_array(ConditionRules.end_concentration(s, data, r["text"]))
	return lines


## Relentless Endurance (half-orc, once per long rest): the hero dropped to 0 HP without being killed outright stays
## at 1 HP. True when it worked; the line goes to `lines`.
static func relentless(s: GameSession, data: Dictionary, lines: Array[String]) -> bool:
	var c := s.character
	if not CharacterRules.has_trait(c, "relentless_endurance") or bool(c.get("relentless_used", false)) or int(c.get("hp", 0)) > 0:
		return false
	c["hp"] = 1
	c["relentless_used"] = true
	lines.append("%s: %s — остаётся на ногах с 1 HP" % [c.get("name", ""), data["races"]["traits"].get("relentless_endurance", {}).get("name", "")])
	return true


## Temporary hit points take damage first (Dark One's Blessing and the like, v0.7.10). Returns what is left.
static func absorb(c: Dictionary, dmg: int, lines: Array[String]) -> int:
	var thp := int(c.get("temp_hp", 0))
	if thp <= 0 or dmg <= 0:
		return dmg
	var taken := mini(thp, dmg)
	c["temp_hp"] = thp - taken
	lines.append("временные хиты: −%d" % taken)
	return dmg - taken
