class_name HeroDefense
extends RefCounted
## Damage to the hero and the hero's saves by 5e (roadmap v0.7.8): resistances, vulnerabilities and immunities like
## a foe's — from race traits (dwarf, tiefling, dragonborn by ancestry), Rage, items (resist_*), effects (a cure's
## boon), petrification; advantage on saves of a tag from race traits (dwarf — poison, elf — charm, halfling — fear,
## gnome — magic against INT / WIS / CHA) and effects (antitoxin); immunity of an elf to magical sleep. What a blow does
## next is `Harm` (v0.8.4.13). Tables — rules.hero_effects.

const TAG_NAMES := {"poison": "яд", "charm": "очарование", "fear": "страх", "magic": "магия", "sleep": "сон", "disease": "болезнь",
	"paralysis": "паралич", "prone": "падение", "blind": "слепота", "deaf": "глухота", "stun": "оглушение"}


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"]["hero_effects"]


static func tag_name(tag: Variant) -> String:
	if tag is Array:
		return ", ".join((tag as Array).map(func(x: Variant) -> String: return tag_name(str(x))))
	return str(TAG_NAMES.get(tag, tag))


## The tags a status gives advantage on saves against: its `adv_tag`, one or a list (v0.8.4.27.5).
static func adv_tags(e: Dictionary) -> Array:
	var t: Variant = e.get("adv_tag", [])
	return (t as Array) if t is Array else [str(t)]


## The tags of a save against these statuses (rules.hero_effects.cond_tags, v0.8.4.27.4): charmed — charm, prone — prone…
## `more` — the save's own tags before them («magic»). One string for Sheet.save: «charm,magic».
static func cond_tags(data: Dictionary, conds: Array, more: Array = []) -> String:
	var out: Array[String] = []
	var table: Dictionary = cfg(data)["cond_tags"]
	for c: Variant in conds:
		if table.has(str(c)) and not out.has(str(table[c])):
			out.append(str(table[c]))
	for t: Variant in more:
		if not str(t).is_empty() and not out.has(str(t)):
			out.append(str(t))
	return ",".join(out)


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


## The damage types `who` resists now by its race, Rage, things and effects, with where each comes from: {type: source name}.
static func resistances(s: GameSession, data: Dictionary, who: Dictionary = Sheet.HERO) -> Dictionary:
	var c := Sheet.holder(s, who)
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
	if Sheet.raging(s, who):
		for x: Variant in cfg(data)["rage_resist"]:
			out[str(x)] = "Ярость"
	var by_item: Dictionary = cfg(data)["item_resist"]
	for d: Dictionary in Sheet.working(s, data, who):  # its things, attuned when they need it (v0.8.4.15)
		for p: Variant in d.get("properties", []):
			if by_item.has(str(p)):
				out[str(by_item[str(p)])] = str(d.get("name", ""))
	for e: Dictionary in ConditionRules.effects(c):
		for x: Variant in e.get("resist", []):
			out[str(x)] = str(e.get("source", {}).get("name", ""))
	return out


## Why anybody has advantage on a save of `ability` against `tag` now (v0.7.10: Danger Sense on DEX saves, Rage on STR);
## a race's or a monster's trait is a status of `rules.feature_wear` with its `adv_tag` and `abilities`, read with any
## other status's (v0.8.4.27.5).
static func save_advantages(c: Dictionary, data: Dictionary, ability: String, tag: String, raging: bool = false) -> Array[String]:
	var out: Array[String] = []
	if ability == "dex" and CharacterRules.has_feature(c, "danger_sense") \
			and not ["blinded", "deafened"].any(func(x: String) -> bool: return ConditionRules.has(c, x)) and not ConditionRules.incapacitated(c):
		out.append(str(data["classes"]["features"].get("danger_sense", {}).get("name", "")))
	if ability == "str" and raging:
		out.append("ярость")
	var by_spell := SpellEffects.save_adv(c, ability)  # Beacon of Hope (v0.7.13.2)
	if not by_spell.is_empty():
		out.append(by_spell)
	if tag.is_empty():
		return out
	var tags := tag.split(",")  # a save against several things at once: «charm,magic» (v0.7.9)
	for e: Dictionary in ItemRules.born_effects(data, c):
		var name := str(e.get("source", {}).get("name", ""))
		if adv_tags(e).any(func(x: Variant) -> bool: return tags.has(str(x))) and not out.has(name) \
				and (not e.has("abilities") or (e["abilities"] as Array).has(ability)):
			out.append(name)
	return out


## What makes `who` immune to `cond` laid with `tag`: a spell, a race trait (an elf and magical sleep), a paladin's Divine
## Health and a Periapt of Health against disease (v0.7.10, v0.7.12); "" when none. Anybody's (v0.8.4.15).
static func immune(s: GameSession, data: Dictionary, who: Dictionary, cond: String, tag: String) -> String:
	var c := Sheet.holder(s, who)
	var by_spell := SpellEffects.immune(s, data, who, cond)  # Heroism (v0.7.13.1), Steadfast (v0.8.4.27.5)
	if not by_spell.is_empty():
		return by_spell
	if tag.split(",").has("disease") and CharacterRules.has_feature(c, "divine_health"):
		return str(data["classes"]["features"].get("divine_health", {}).get("name", ""))
	if tag.split(",").has("disease") and Sheet.prop(s, data, who, "immune_disease"):
		return "Амулет здоровья"  # Periapt of Health (v0.7.12)
	var table: Dictionary = cfg(data)["trait_immune"]
	for t: String in table:
		if CharacterRules.has_trait(c, t) and tag.split(",").has(str(table[t]["tag"])) and (table[t]["conditions"] as Array).has(cond):
			return str(data["races"]["traits"].get(t, {}).get("name", t))
	return ""


