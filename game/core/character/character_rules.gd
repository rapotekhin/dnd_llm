class_name CharacterRules
extends RefCounted
## 5e numbers of a character from its choices and the SRD catalog (roadmap v0.5.0): ability modifiers,
## proficiency, skills and saves, AC from worn armor, HP by the fixed-average rule, spell slots and DC.
##
## The character is a Dictionary in the session (it goes into saves as is):
##   choices — name, gender, race, subrace, class, subclass, background, level, abilities {str..cha, final},
##     skill_profs, expertise, save_profs, languages, tools, armor_profs, weapon_profs, traits, features,
##     spells {cantrips, known, prepared}, equipped {armor, shield, main_hand, off_hand}, inventory, gold_cp;
##   state — hp, conditions, slots_used [5], hit_dice_used;
##   derived cache (refresh) — race_name, class_name, prof_bonus, max_hp, ac, skills {id: bonus}, saves {id: bonus},
##     speed, passive_perception, slots_max [5], spell_ability, spell_dc, spell_attack.
## The cache keeps CheckEngine, EffectEngine and the snapshot simple; refresh() after any change of choices.
##
## `data` = Catalog.data: "rules", "items", "races", "classes", "spells", "backgrounds", "misc".

const ABILITIES: Array[String] = ["str", "dex", "con", "int", "wis", "cha"]
const SLOTS: Array[String] = ["armor", "shield", "main_hand", "off_hand"]


static func mod(score: int) -> int:
	return floori((score - 10) / 2.0)


static func class_def(c: Dictionary, data: Dictionary) -> Dictionary:
	return data["classes"]["classes"].get(str(c.get("class", "")), {})


static func level_row(c: Dictionary, data: Dictionary) -> Dictionary:
	return class_def(c, data).get("levels", {}).get(str(int(c.get("level", 1))), {})


static func prof_bonus(c: Dictionary, data: Dictionary) -> int:
	return int(level_row(c, data).get("prof_bonus", 2 + (int(c.get("level", 1)) - 1) / 4))


static func ability(c: Dictionary, id: String) -> int:
	return int(c.get("abilities", {}).get(id, 10))


static func has_feature(c: Dictionary, id: String) -> bool:
	return (c.get("features", []) as Array).has(id)


static func has_trait(c: Dictionary, id: String) -> bool:
	return (c.get("traits", []) as Array).has(id)


static func skill_bonus(c: Dictionary, data: Dictionary, skill: String) -> int:
	var ab := str(data["rules"]["skills"].get(skill, "int"))
	var bonus := mod(ability(c, ab))
	var pb := prof_bonus(c, data)
	if (c.get("expertise", []) as Array).has(skill):
		bonus += pb * 2
	elif (c.get("skill_profs", []) as Array).has(skill):
		bonus += pb
	elif has_feature(c, "jack_of_all_trades"):
		bonus += pb / 2
	return bonus


static func save_bonus(c: Dictionary, data: Dictionary, save: String) -> int:
	var bonus := mod(ability(c, save))
	if (c.get("save_profs", []) as Array).has(save):
		bonus += prof_bonus(c, data)
	return bonus


## Hit points by the fixed-average rule: full die at level 1, then die/2 + 1 per level; CON every level;
## +1 per level from Dwarven Toughness or Draconic Resilience. At least 1 per level.
static func max_hp(c: Dictionary, data: Dictionary) -> int:
	var die := int(class_def(c, data).get("hit_die", 8))
	var level := int(c.get("level", 1))
	var con := mod(ability(c, "con"))
	var per_level := 1 if has_trait(c, "dwarven_toughness") or has_feature(c, "draconic_resilience") else 0
	var hp := maxi(1, die + con + per_level)
	for i in range(1, level):
		hp += maxi(1, die / 2 + 1 + con + per_level)
	return hp


static func item_def(c: Dictionary, data: Dictionary, session_items: Dictionary, slot: String) -> Dictionary:
	var id := str(c.get("equipped", {}).get(slot, ""))
	return {} if id.is_empty() else ItemRules.def_of(data["items"], session_items, id)


## Armor Class: worn armor (base + DEX within its cap) or an unarmored formula (Barbarian 10+DEX+CON,
## Monk 10+DEX+WIS without a shield, Draconic Resilience 13+DEX), +2 for a shield, +1 for the Defense style in armor.
static func armor_class(c: Dictionary, data: Dictionary, session_items: Dictionary = {}) -> int:
	var dex := mod(ability(c, "dex"))
	var armor: Dictionary = item_def(c, data, session_items, "armor").get("armor", {})
	var shield: Dictionary = item_def(c, data, session_items, "shield").get("armor", {})
	var ac := 10 + dex
	if not armor.is_empty():
		ac = int(armor["base"])
		if bool(armor.get("dex", false)):
			ac += dex if armor.get("max_dex") == null else mini(dex, int(armor["max_dex"]))
		for f: Variant in c.get("features", []):
			if str(f).ends_with("fighting_style_defense"):
				ac += 1
				break
	elif has_feature(c, "barbarian_unarmored_defense"):
		ac = 10 + dex + mod(ability(c, "con"))
	elif has_feature(c, "monk_unarmored_defense") and shield.is_empty():
		ac = 10 + dex + mod(ability(c, "wis"))
	elif has_feature(c, "draconic_resilience"):
		ac = 13 + dex
	if not shield.is_empty():
		ac += int(shield.get("base", 2))
	# Magic (v0.6.3): +N armor and shields, carried wondrous items (Cloak of Protection).
	ac += ItemRules.plus(item_def(c, data, session_items, "armor"), ["ac_plus", "magic_plus"])
	ac += ItemRules.plus(item_def(c, data, session_items, "shield"), ["ac_plus", "magic_plus"])
	for d: Dictionary in carried(c, data, session_items):
		ac += ItemRules.plus(d, ["ac_plus"])
	return ac


## Wondrous items in the pack (v0.6.3): they work while carried (no attunement in this version).
static func carried(c: Dictionary, data: Dictionary, session_items: Dictionary = {}) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: String in c.get("inventory", {}):
		var d := ItemRules.def_of(data["items"], session_items, id)
		if str(d.get("item_type", "")) == "wondrous":
			out.append(d)
	return out


## The name of a carried wondrous item with this property, "" when there is none (Boots of Elvenkind → stealth).
static func carried_with(c: Dictionary, data: Dictionary, session_items: Dictionary, prop: String) -> String:
	for d: Dictionary in carried(c, data, session_items):
		if (d.get("properties", []) as Array).has(prop):
			return str(d.get("name", ""))
	return ""


static func slots_max(c: Dictionary, data: Dictionary) -> Array[int]:
	var out: Array[int] = [0, 0, 0, 0, 0]
	var row: Array = level_row(c, data).get("slots", [])
	for i in mini(row.size(), 5):
		out[i] = int(row[i])
	return out


static func spell_ability(c: Dictionary, data: Dictionary) -> String:
	return str(class_def(c, data).get("spellcasting", {}).get("ability", ""))


static func speed(c: Dictionary, data: Dictionary) -> int:
	var race: Dictionary = data["races"]["races"].get(str(c.get("race", "")), {})
	var bonus := 0
	var spec: Dictionary = level_row(c, data).get("class_specific", {})
	if item_def(c, data, {}, "armor").is_empty() and item_def(c, data, {}, "shield").is_empty():
		bonus = int(spec.get("unarmored_movement", 0))
	var feet := int(race.get("speed", 30)) + bonus
	# v0.7.8: grappled and restrained — 0; exhaustion 5 — 0, 2 — half (5e).
	var exhaustion := int(c.get("exhaustion", 0))
	if exhaustion >= 5 or (c.get("conditions", []) as Array).any(func(x: Variant) -> bool: return str(x) in ["grappled", "restrained", "paralyzed", "petrified"]):
		return 0
	return feet / 2 if exhaustion >= 2 else feet


static func race_name(c: Dictionary, data: Dictionary) -> String:
	var races: Dictionary = data["races"]
	var sub := str(c.get("subrace", ""))
	if not sub.is_empty() and races["subraces"].has(sub):
		return str(races["subraces"][sub]["name"])
	return str(races["races"].get(str(c.get("race", "")), {}).get("name", c.get("race", "")))


static func class_name_of(c: Dictionary, data: Dictionary) -> String:
	return str(class_def(c, data).get("name", c.get("class", "")))


## Recomputes the derived cache in place. Call after creation, load, equip, level-up.
static func refresh(c: Dictionary, data: Dictionary, session_items: Dictionary = {}) -> void:
	sanitize_equipped(c)
	_grant_trait_cantrips(c, data)
	c["race_name"] = race_name(c, data)
	c["class_name"] = class_name_of(c, data)
	c["prof_bonus"] = prof_bonus(c, data)
	var drained := 0  # life drain until a long rest (v0.7.9)
	for e: Variant in c.get("effects", []):
		if e is Dictionary:
			drained += int((e as Dictionary).get("max_hp", 0))
	c["max_hp"] = maxi(1, max_hp(c, data) / (2 if int(c.get("exhaustion", 0)) >= 4 else 1) + drained)  # exhaustion 4 halves it (v0.7.8)
	c["hp"] = clampi(int(c.get("hp", c["max_hp"])), 0, int(c["max_hp"]))
	c["ac"] = armor_class(c, data, session_items)
	var skills := {}
	for id: String in data["rules"]["skills"]:
		skills[id] = skill_bonus(c, data, id)
	c["skills"] = skills
	var saves := {}
	var save_plus := 0
	for d: Dictionary in carried(c, data, session_items):
		save_plus += ItemRules.plus(d, ["saves_plus"])
	for id: String in ABILITIES:
		saves[id] = save_bonus(c, data, id) + save_plus
	c["saves"] = saves
	c["speed"] = speed(c, data)
	c["passive_perception"] = 10 + int(skills["perception"])
	c["slots_max"] = slots_max(c, data)
	var ab := spell_ability(c, data)
	c["spell_ability"] = ab
	if not ab.is_empty():
		c["spell_dc"] = 8 + int(c["prof_bonus"]) + mod(ability(c, ab))
		c["spell_attack"] = int(c["prof_bonus"]) + mod(ability(c, ab))
	else:
		c.erase("spell_dc")
		c.erase("spell_attack")


## Equipped items must still be in the inventory (an item given away is unequipped).
static func sanitize_equipped(c: Dictionary) -> void:
	var eq: Dictionary = c.get("equipped", {})
	var inv: Dictionary = c.get("inventory", {})
	for slot: String in SLOTS:
		var id := str(eq.get(slot, ""))
		if not id.is_empty() and int(inv.get(id, 0)) <= 0:
			eq[slot] = ""
	c["equipped"] = eq


## The slot an item goes to, or "" if it cannot be equipped. A weapon goes to the main hand.
static func slot_for(def: Dictionary) -> String:
	if def.has("armor"):
		return "shield" if str(def["armor"]["category"]) == "shield" else "armor"
	if def.has("weapon") or str(def.get("item_type", "")) == "weapon":
		return "main_hand"
	return ""


## "" when the character can equip `id` into `slot`, otherwise a reason (localization key).
static func can_equip(c: Dictionary, data: Dictionary, session_items: Dictionary, id: String, slot: String) -> String:
	if int(c.get("inventory", {}).get(id, 0)) <= 0:
		return "EQUIP_NOT_OWNED"
	var def := ItemRules.def_of(data["items"], session_items, id)
	var natural := slot_for(def)
	if natural.is_empty() or (natural != slot and not (natural == "main_hand" and slot == "off_hand")):
		return "EQUIP_WRONG_SLOT"
	var eq: Dictionary = c.get("equipped", {})
	var profs: Array = c.get("armor_profs", [])
	match slot:
		"armor":
			if not profs.has(str(def["armor"]["category"])):
				return "EQUIP_NO_PROFICIENCY"
		"shield":
			if not profs.has("shield"):
				return "EQUIP_NO_PROFICIENCY"
			if not str(eq.get("off_hand", "")).is_empty() or _two_handed(data, session_items, str(eq.get("main_hand", ""))):
				return "EQUIP_HANDS_BUSY"
		"off_hand":
			if not (def.get("properties", []) as Array).has("light"):
				return "EQUIP_NOT_LIGHT"
			if not str(eq.get("shield", "")).is_empty() or _two_handed(data, session_items, str(eq.get("main_hand", ""))):
				return "EQUIP_HANDS_BUSY"
			if str(eq.get("main_hand", "")) == id and int(c["inventory"][id]) < 2:
				return "EQUIP_NOT_OWNED"
		"main_hand":
			if (def.get("properties", []) as Array).has("two_handed") and (not str(eq.get("shield", "")).is_empty() or not str(eq.get("off_hand", "")).is_empty()):
				return "EQUIP_HANDS_BUSY"
	return ""


## Pounds the hero carries: everything in the pack, worn things too (v0.7.7).
static func carried_weight(c: Dictionary, data: Dictionary, session_items: Dictionary = {}) -> float:
	var total := 0.0
	for id: String in c.get("inventory", {}):
		total += float(ItemRules.def_of(data["items"], session_items, id).get("weight", 0)) * int(c["inventory"][id])
	return total


## Carrying capacity (PHB): Strength × rules.carry.per_str pounds.
static func capacity(c: Dictionary, data: Dictionary) -> int:
	return ability(c, "str") * int(data["rules"].get("carry", {}).get("per_str", 15))


static func overloaded(c: Dictionary, data: Dictionary, session_items: Dictionary = {}) -> bool:
	return carried_weight(c, data, session_items) > capacity(c, data)


## Minutes a change of gear takes out of a fight (v0.7.7, PHB): armour off and on by its category
## (rules.equip_minutes); a shield and weapons take none. `before` / `after` — the equipped slots.
static func gear_minutes(data: Dictionary, session_items: Dictionary, before: Dictionary, after: Dictionary) -> int:
	var t: Dictionary = data["rules"].get("equip_minutes", {})
	var total := 0
	for slot: String in ["armor", "shield"]:
		var was := str(before.get(slot, ""))
		var now := str(after.get(slot, ""))
		if was == now:
			continue
		if not was.is_empty():
			total += int(t.get("doff", {}).get(_armor_category(data, session_items, was), 0))
		if not now.is_empty():
			total += int(t.get("don", {}).get(_armor_category(data, session_items, now), 0))
	return total


static func _armor_category(data: Dictionary, session_items: Dictionary, id: String) -> String:
	return str(ItemRules.def_of(data["items"], session_items, id).get("armor", {}).get("category", ""))


static func _two_handed(data: Dictionary, session_items: Dictionary, id: String) -> bool:
	return not id.is_empty() and (ItemRules.def_of(data["items"], session_items, id).get("properties", []) as Array).has("two_handed")


## Best starting kit: the heaviest armor with proficiency, a melee weapon in hand, a shield when the hand is free.
static func auto_equip(c: Dictionary, data: Dictionary) -> void:
	var eq := {"armor": "", "shield": "", "main_hand": "", "off_hand": ""}
	c["equipped"] = eq
	var best_ac := -1
	var weapons: Array[String] = []
	for id: String in c.get("inventory", {}):
		var def := ItemRules.def_of(data["items"], {}, id)
		var slot := slot_for(def)
		if slot == "armor" and can_equip(c, data, {}, id, "armor").is_empty() and int(def["armor"]["base"]) > best_ac:
			best_ac = int(def["armor"]["base"])
			eq["armor"] = id
		elif slot == "main_hand":
			weapons.append(id)
	weapons.sort_custom(func(a: String, b: String) -> bool: return _weapon_rank(data, a) > _weapon_rank(data, b))
	if not weapons.is_empty():
		eq["main_hand"] = weapons[0]
	for id: String in c.get("inventory", {}):
		if slot_for(ItemRules.def_of(data["items"], {}, id)) == "shield" and can_equip(c, data, {}, id, "shield").is_empty():
			eq["shield"] = id
			break


static func _weapon_rank(data: Dictionary, id: String) -> int:
	var w: Dictionary = ItemRules.def_of(data["items"], {}, id).get("weapon", {})
	var dmg := str(w.get("damage", "1d1"))
	var sides := int(dmg.get_slice("d", 1)) * int(dmg.get_slice("d", 0))
	return sides + (10 if str(w.get("range", "")) == "melee" else 0)


## Short Russian lines of the sheet for the master (snapshot): features, traits and spells by name.
static func feature_names(c: Dictionary, data: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var feats: Dictionary = data["classes"]["features"]
	for id: Variant in c.get("features", []):
		var f: Dictionary = feats.get(str(id), {})
		if not f.is_empty() and not (f.has("options") and _has_chosen_option(c, f)):
			out.append(str(f["name"]))
	var traits: Dictionary = data["races"]["traits"]
	for id: Variant in c.get("traits", []):
		var t: Dictionary = traits.get(str(id), {})
		if not t.is_empty() and not t.has("options"):
			out.append(str(t["name"]))
	return out


static func _has_chosen_option(c: Dictionary, f: Dictionary) -> bool:
	return (f["options"]["from"] as Array).any(func(o: Variant) -> bool: return has_feature(c, str(o)))


static func spell_names(c: Dictionary, data: Dictionary, list: String) -> Array[String]:
	var out: Array[String] = []
	for id: Variant in c.get("spells", {}).get(list, []):
		out.append(str(data["spells"].get(str(id), {}).get("name", id)))
	return out


## Cantrips of race traits (rules.json `trait_cantrips`, e.g. Infernal Legacy → Thaumaturgy) belong to the
## character's cantrips: casting checks them like any other.
static func _grant_trait_cantrips(c: Dictionary, data: Dictionary) -> void:
	var table: Dictionary = data["rules"].get("trait_cantrips", {})
	for t: Variant in c.get("traits", []):
		for id: Variant in table.get(str(t), []):
			var sp: Dictionary = c.get("spells", {})
			if sp.is_empty():
				continue
			var list: Array = sp.get("cantrips", [])
			if not list.has(id):
				list.append(id)
			sp["cantrips"] = list
