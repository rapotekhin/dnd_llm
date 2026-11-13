class_name CharacterRules
extends RefCounted
## 5e numbers of a character from its choices and the SRD catalog (roadmap v0.5.0): ability modifiers,
## proficiency, skills and saves, AC from worn armor, HP by the fixed-average rule, spell slots and DC.
##
## The character is a Dictionary in the session (it goes into saves as is):
##   choices — name, gender, race, subrace, class, subclass, background, level, abilities {str..cha, final},
##     skill_profs, expertise, save_profs, languages, tools, armor_profs, weapon_profs, traits, features,
##     spells {cantrips, known, prepared}, equipped {armor, main_hand, off_hand — a weapon or a shield}, inventory, gold_cp;
##   state — hp, conditions, spent — the stock (Stock);
##   derived cache (refresh) — race_name, class_name, prof_bonus, max_hp, ac, skills {id: bonus}, saves {id: bonus},
##     speed, passive_perception, slots_max [5], spell_ability, spell_dc, spell_attack.
## The cache keeps CheckEngine, EffectEngine and the snapshot simple; refresh() after any change of choices.
##
## `data` = Catalog.data: "rules", "items", "races", "classes", "spells", "backgrounds", "misc".

const ABILITIES: Array[String] = ["str", "dex", "con", "int", "wis", "cha"]
const SLOTS: Array[String] = ["armor", "main_hand", "off_hand", "head", "eyes", "neck", "cloak", "hands", "feet", "ring1", "ring2"]
## Slots of worn things (v0.7.22.9): put on and off out of a fight, like armour.
## The hands of a weapon set (v0.8.4.1); a shield is held in the off hand, as in every RPG (v0.8.4.43.13).
const HANDS: Array[String] = ["main_hand", "off_hand"]
const WEAR_SLOTS: Array[String] = ["head", "eyes", "neck", "cloak", "hands", "feet", "ring1", "ring2"]


static func mod(score: int) -> int:
	return floori((score - 10) / 2.0)


static func class_def(c: Dictionary, data: Dictionary) -> Dictionary:
	return data["classes"]["classes"].get(str(c.get("class", "")), {})


static func level_row(c: Dictionary, data: Dictionary) -> Dictionary:
	return class_def(c, data).get("levels", {}).get(str(int(c.get("level", 1))), {})


static func prof_bonus(c: Dictionary, data: Dictionary) -> int:
	return int(level_row(c, data).get("prof_bonus", 2 + (int(c.get("level", 1)) - 1) / 4))


## The score in play: the sheet's, or an item's floor (Gauntlets of Ogre Power — STR 19, v0.7.12).
static func ability(c: Dictionary, id: String) -> int:
	return maxi(int(c.get("abilities", {}).get(id, 10)), int(c.get("ability_floor", {}).get(id, 0)))


## A property of an item that works now (refresh caches them in `item_props`, v0.7.12).
static func item_prop(c: Dictionary, prop: String) -> bool:
	return (c.get("item_props", []) as Array).has(prop)


static func has_feature(c: Dictionary, id: String) -> bool:
	return (c.get("features", []) as Array).has(id)


static func has_trait(c: Dictionary, id: String) -> bool:
	return (c.get("traits", []) as Array).has(id)


## How the character knows a skill (v0.8.4.43.6: one place for the roll's parts and the sheet's ★): "expertise", "skill"
## (its proficiency, or a feature that gives it), "beguiling" (Beguiling Influence: Deception and Persuasion), "" — none.
static func skill_mastery(c: Dictionary, id: String) -> String:
	if (c.get("expertise", []) as Array).has(id):
		return "expertise"
	if (c.get("skill_profs", []) as Array).has(id) or has_feature(c, "skill_prof_" + id):
		return "skill"
	if id in ["deception", "persuasion"] and has_feature(c, "eldritch_invocation_beguiling_influence"):
		return "beguiling"
	return ""


## A bare ability check (5e: «Сила» to force a door): the modifier, half proficiency with Jack of All Trades, the
## Stone of Good Luck — the sum of its parts (RollParts).
static func ability_check_bonus(c: Dictionary, data: Dictionary, ab: String) -> int:
	if data.is_empty():
		return mod(ability(c, ab))
	return RollParts.sum(RollParts.sheet(c, data, "ability", ab))


## Hit points by the fixed-average rule: full die at level 1, then `hp_step` per level.
static func max_hp(c: Dictionary, data: Dictionary) -> int:
	var die := int(class_def(c, data).get("hit_die", 8))
	var con := mod(ability(c, "con"))
	var hp := maxi(1, die + con + _hp_extra(c))
	for i in range(1, int(c.get("level", 1))):
		hp += hp_step(c, die, con)
	return hp


## What a level past the first adds (v0.8.4.15: one rule for the sheet, the level-up and a person who grew): die / 2 + 1
## and CON, +1 from Dwarven Toughness or Draconic Resilience; at least 1.
static func hp_step(c: Dictionary, die: int, con: int) -> int:
	return maxi(1, die / 2 + 1 + con + _hp_extra(c))


static func _hp_extra(c: Dictionary) -> int:
	return 1 if has_trait(c, "dwarven_toughness") or has_feature(c, "draconic_resilience") else 0


static func item_def(c: Dictionary, data: Dictionary, session_items: Dictionary, slot: String) -> Dictionary:
	var id := str(c.get("equipped", {}).get(slot, ""))
	return {} if id.is_empty() else ItemRules.copy_def(data["items"], session_items, c, id, hold_index(c, id, slot))


## Whether a thing is a shield: it goes to the off hand (v0.8.4.43.13, the author: as in every RPG, no slot of its own).
static func is_shield(def: Dictionary) -> bool:
	return str(def.get("armor", {}).get("category", "")) == "shield"


## The shield the off hand of a set holds — `row` is `equipped` or the set put away; "" — none. Anybody's.
static func shield_in(row: Dictionary, data: Dictionary, session_items: Dictionary = {}) -> String:
	var id := str(row.get("off_hand", ""))
	return id if not id.is_empty() and is_shield(ItemRules.def_of(data["items"], session_items, id)) else ""


## The weapon of the off hand of a set: "" — an empty hand or a shield.
static func off_weapon(row: Dictionary, data: Dictionary, session_items: Dictionary = {}) -> String:
	var id := str(row.get("off_hand", ""))
	return "" if id.is_empty() or not shield_in(row, data, session_items).is_empty() else id


## The worn shield (its copy's definition), {} — none in the hands.
static func shield_def(c: Dictionary, data: Dictionary, session_items: Dictionary = {}) -> Dictionary:
	return {} if shield_in(c.get("equipped", {}), data, session_items).is_empty() else item_def(c, data, session_items, "off_hand")


## The AC of worn armour: its base and DEX within its cap. Anybody's (Gear.ac).
static func armored(armor: Dictionary, dex: int) -> int:
	var ac := int(armor.get("base", 10))
	if bool(armor.get("dex", false)):
		ac += dex if armor.get("max_dex") == null else mini(dex, int(armor["max_dex"]))
	return ac


## Armor Class: worn armor (base + DEX within its cap) or an unarmored formula (Barbarian 10+DEX+CON,
## Monk 10+DEX+WIS without a shield, Draconic Resilience 13+DEX), +2 for a shield, +1 for the Defense style in armor.
static func armor_class(c: Dictionary, data: Dictionary, session_items: Dictionary = {}) -> int:
	if Guise.has_body(c):  # the beast's AC (v0.7.10)
		return int(data["monsters"].get(str(Guise.body(c)["monster"]), {}).get("ac", 10))
	var dex := mod(ability(c, "dex"))
	var armor: Dictionary = item_def(c, data, session_items, "armor").get("armor", {})
	var shield: Dictionary = shield_def(c, data, session_items).get("armor", {})
	var ac := 10 + dex
	if not armor.is_empty():
		ac = armored(armor, dex) + (1 if style(c, "defense") else 0)
	else:
		ac = maxi(ac, unarmored_ac(c, dex, mod(ability(c, "con")), mod(ability(c, "wis")), not shield.is_empty()))
	if not shield.is_empty():
		ac += int(shield.get("base", 2))
	return SpellEffects.armor_class(c, ac + gear_ac(c, data, session_items), armor.is_empty(), dex)  # Mage Armor, Shield of Faith, Barkskin (v0.7.13.2)


## The AC a class or a feature gives without armour, anybody's (v0.8.4.29.4: the hero's sheet and Gear.ac): Unarmored Defense of a
## barbarian (CON) or of a monk without a shield (WIS), Draconic Resilience and Armor of Shadows (mage armour at will). 0 — none.
static func unarmored_ac(c: Dictionary, dex: int, con: int, wis: int, shielded: bool) -> int:
	if has_feature(c, "barbarian_unarmored_defense"):
		return 10 + dex + con
	if has_feature(c, "monk_unarmored_defense") and not shielded:
		return 10 + dex + wis
	if has_feature(c, "draconic_resilience") or has_feature(c, "eldritch_invocation_armor_of_shadows"):
		return 13 + dex
	return 0


## What its things add to the AC, anybody's (v0.8.4.15, Gear.ac too): +N armour and shields (v0.6.3), poor workmanship,
## carried wondrous items (Cloak of Protection).
static func gear_ac(c: Dictionary, data: Dictionary, session_items: Dictionary = {}) -> int:
	var ac := 0
	for d: Dictionary in [item_def(c, data, session_items, "armor"), shield_def(c, data, session_items)]:
		ac += ItemRules.plus(d, ["ac_plus", "magic_plus"]) + mini(0, CraftRules.quality_mod(d))
	for d: Dictionary in carried(c, data, session_items):
		ac += ItemRules.plus(d, ["ac_plus"])
	return ac


## A fighting style of a class: `style` "defense", "archery", "dueling"…
static func style(c: Dictionary, id: String) -> bool:
	return (c.get("features", []) as Array).any(func(f: Variant) -> bool: return str(f).ends_with("fighting_style_" + id))


## Wondrous items that work now (v0.6.3): carried — those that need it, only when attuned (v0.7.12); a worn kind (a
## cloak, a ring, boots) only in its slot (v0.7.22.9).
static func carried(c: Dictionary, data: Dictionary, session_items: Dictionary = {}) -> Array[Dictionary]:
	return _defs(carried_ids(c, data, session_items), data, session_items, c)


## The ids of `carried`.
static func carried_ids(c: Dictionary, data: Dictionary, session_items: Dictionary = {}) -> Array[String]:
	var out: Array[String] = []
	var eq: Dictionary = c.get("equipped", {})
	for id: String in c.get("inventory", {}):
		var d := ItemRules.def_of(data["items"], session_items, id)
		if str(d.get("item_type", "")) != "wondrous" or not ItemRules.active(c, d, id):
			continue
		if wear_slot(d, data).is_empty():
			out.append(id)
			continue
		for slot: String in WEAR_SLOTS:
			if str(eq.get(slot, "")) == id:
				out.append(id)
	return out


## The things that work now (v0.8.4.15: one list for the boons, the properties and the resistances): the wondrous
## ones carried or worn (`carried`) and the gear in the other slots, attuned when they need it.
static func working(c: Dictionary, data: Dictionary, session_items: Dictionary = {}) -> Array[Dictionary]:
	return _defs(working_ids(c, data, session_items), data, session_items, c)


## The ids of `working` (v0.8.4.26: what a worn thing lays is named by its thing).
static func working_ids(c: Dictionary, data: Dictionary, session_items: Dictionary = {}) -> Array[String]:
	var ids := carried_ids(c, data, session_items)
	for slot: String in SLOTS:
		var id := str(c.get("equipped", {}).get(slot, ""))
		if not WEAR_SLOTS.has(slot) and not id.is_empty() and ItemRules.active(c, ItemRules.def_of(data["items"], session_items, id), id):
			ids.append(id)
	return ids


## The defs of `ids`, the k-th of one id read as its k-th copy with that copy's marks (v0.8.4.35).
static func _defs(ids: Array[String], data: Dictionary, session_items: Dictionary, c: Dictionary = {}) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen := {}
	for id: String in ids:
		out.append(ItemRules.copy_def(data["items"], session_items, c, id, int(seen.get(id, 0))))
		seen[id] = int(seen.get(id, 0)) + 1
	return out


## What the things that work now give, for the sheet (v0.7.49.4): «Очки ночного видения: тёмное зрение 60 фт» — each
## thing with the properties rules.item_props names.
static func item_boons(c: Dictionary, data: Dictionary, session_items: Dictionary = {}) -> Array[String]:
	var names: Dictionary = data["rules"]["item_props"]["names"]
	var out: Array[String] = []
	for d: Dictionary in working(c, data, session_items):
		var what: Array = (d.get("properties", []) as Array).filter(func(p: Variant) -> bool: return names.has(str(p))).map(func(p: Variant) -> String: return str(names[str(p)]))
		if d.get("wear") is Dictionary:  # v0.8.4.26: what it lays while it works, in the words of a spell's effect
			what.append(SpellEffects.text(data, ItemRules.wear_spec(c, data, d)))
		if not what.is_empty():
			out.append("%s: %s" % [d.get("name", ""), ", ".join(what)])
	return out


## Properties of the things that work now (v0.7.12): the hero's sheet caches them in `item_props`, anybody's are Sheet.props.
static func active_props(c: Dictionary, data: Dictionary, session_items: Dictionary = {}) -> Array:
	var out: Array = []
	for d: Dictionary in working(c, data, session_items):
		for p: Variant in d.get("properties", []):
			if not out.has(str(p)):
				out.append(str(p))
	return out


## Spells a feature lets the hero cast at will (rules.feature_spells, v0.7.22.4): c.spells.free, rebuilt each refresh.
static func _grant_free_spells(c: Dictionary, data: Dictionary) -> void:
	var sp: Dictionary = c.get("spells", {})
	if sp.is_empty():
		return
	var free: Array = []
	var table: Dictionary = data["rules"].get("feature_spells", {})
	for f: Variant in c.get("features", []):
		for id: Variant in table.get(str(f), []):
			if data["spells"].has(str(id)) and not free.has(str(id)):
				free.append(str(id))
	var by: Dictionary = {}  # a race trait's spells by its own ability (v0.8.4.33)
	var traits: Dictionary = data["rules"].get("trait_spells", {})
	for t: Variant in c.get("traits", []):
		var row: Dictionary = traits.get(str(t), {})
		if row.is_empty():
			continue
		var mine: Array = (data["rules"].get("trait_cantrips", {}).get(str(t), []) as Array) + (sp.get("race", []) as Array)
		for lv: String in row.get("at", {}):
			if int(c.get("level", 1)) >= int(lv):
				for id: Variant in row["at"][lv]:
					mine.append(id)
					if data["spells"].has(str(id)) and not free.has(str(id)):
						free.append(str(id))
		for id: Variant in mine:
			by[str(id)] = str(row.get("ability", ""))
	if by.is_empty():
		sp.erase("ability_of")
	else:
		sp["ability_of"] = by
	if free.is_empty():
		sp.erase("free")
	else:
		sp["free"] = free


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


## Attacks an Attack action adds (5e Extra Attack of every class; Thirsting Blade of the Blade pact) (v0.7.10).
static func extra_attacks(c: Dictionary, data: Dictionary) -> int:
	var n := int(level_row(c, data).get("class_specific", {}).get("extra_attacks", 0))
	for f: String in ["barbarian_extra_attack", "monk_extra_attack", "paladin_extra_attack", "ranger_extra_attack"]:
		if has_feature(c, f):
			n = maxi(n, 1)
	if has_feature(c, "eldritch_invocation_thirsting_blade") and FeatureRules.is_pact(c, str(c.get("equipped", {}).get("main_hand", ""))):
		n = maxi(n, 1)  # with the pact weapon in the hand (v0.8.4.33)
	return n


static func speed(c: Dictionary, data: Dictionary) -> int:
	if Guise.has_body(c):
		return Move.feet_of(data, data["monsters"].get(str(Guise.body(c)["monster"]), {}))
	var race: Dictionary = data["races"]["races"].get(str(c.get("race", "")), {})
	return walk(c, c, data, {}, int(race.get("speed", 30)), ability(c, "str"), c.get("item_props", []))


## The walking feet of anybody from the `feet` its body gives (v0.8.4.29.4, one count for the hero's sheet and `Sheet.speed`):
## a class's Unarmored Movement and Fast Movement, Boots of Striding (`props`), Longstrider and a status's own feet (caltrops),
## Fly, Haste, heavy armour without its Strength; exhaustion 2 — half, 5 — 0, and what holds it in place — 0. `me` — its
## statuses, class and features; `gear` — what it wears.
static func walk(me: Dictionary, gear: Dictionary, data: Dictionary, items: Dictionary, feet: int, strength: int, props: Array) -> int:
	var armor := item_def(gear, data, items, "armor")
	var bonus := 0
	if armor.is_empty() and shield_def(gear, data, items).is_empty():
		bonus = int(level_row(me, data).get("class_specific", {}).get("unarmored_movement", 0))
	feet += bonus
	if props.has("speed_30"):  # Boots of Striding and Springing (v0.7.12)
		feet = maxi(feet, 30 + bonus)
	feet = maxi(feet, Move.status_feet(data, me))  # Fly: 60 feet in the air (v0.7.63)
	if SpellEffects.has(me, "speed_x2"):  # Haste
		feet *= 2
	if has_feature(me, "fast_movement") and str(armor.get("armor", {}).get("category", "")) != "heavy":
		feet += 10  # the barbarian's Fast Movement
	feet -= armor_slow(armor, strength, str(me.get("race", "")), data)
	feet += ConditionRules.sum(me, "speed")  # Longstrider's `speed_plus` (v0.7.13.3), a status's own feet: caltrops (v0.8.4.27)
	var tired := ConditionRules.exhaustion(me)
	if tired >= 5 or ConditionRules.does(me, data, "no_move"):
		return 0
	return feet / 2 if tired >= 2 else feet


## Armour worn without its Strength (5e): −`slow_ft` feet of `rules.item_rules.str_short`; a race of `free_races` walks
## in heavy armour freely. Anybody's (`Sheet.speed`).
static func armor_slow(armor: Dictionary, strength: int, race: String, data: Dictionary) -> int:
	var row: Dictionary = data["rules"]["item_rules"]["str_short"]
	var need := int(armor.get("armor", {}).get("str_min", 0))
	if need <= 0 or strength >= need or (row["free_races"] as Array).has(race):
		return 0
	return int(row["slow_ft"])


static func race_name(c: Dictionary, data: Dictionary) -> String:
	var races: Dictionary = data["races"]
	var sub := str(c.get("subrace", ""))
	if not sub.is_empty() and races["subraces"].has(sub):
		return str(races["subraces"][sub]["name"])
	return str(races["races"].get(str(c.get("race", "")), {}).get("name", c.get("race", "")))


## The race's id of races.json of anybody's record (v0.8.4.43.5.2): the hero's `race`, a made person's `race_id`, else a pack
## person's word («полуэльфийка», «высшая эльфийка») by the stems of `rules.race_words`, the races' and subraces' own
## names; "" — not a race of the game (a gnoll, a goblin). The one reader of a race's word.
static func race_id(data: Dictionary, rec: Dictionary) -> String:
	var races: Dictionary = data["races"]["races"]
	for k: String in ["race_id", "race"]:
		if races.has(str(rec.get(k, ""))):
			return str(rec[k])
	var text := str(rec.get("race", "")).to_lower().replace("ё", "е")
	if text.is_empty():
		return ""
	var stems := {}  # stem → race id
	for id: String in (data["rules"].get("race_words", {}) as Dictionary):
		if races.has(id):
			for w: Variant in data["rules"]["race_words"][id]:
				stems[str(w).to_lower().replace("ё", "е")] = id
	for id: String in races:
		stems[str(races[id].get("name", id)).to_lower().replace("ё", "е")] = id
	for sub: Dictionary in (data["races"].get("subraces", {}) as Dictionary).values():
		if races.has(str(sub.get("race", ""))):
			stems[str(sub.get("name", "")).to_lower().replace("ё", "е")] = str(sub["race"])
	var best := ""
	var out := ""
	for word: String in text.replace(",", " ").replace("-", " ").split(" ", false):
		for stem: String in stems:
			if not stem.contains(" ") and stem.length() > best.length() and word.begins_with(stem):
				best = stem
				out = stems[stem]
	for stem: String in stems:  # a subrace's name of two words («высший эльф») as it is
		if stem.contains(" ") and stem.length() > best.length() and text.contains(stem):
			best = stem
			out = stems[stem]
	return out


static func class_name_of(c: Dictionary, data: Dictionary) -> String:
	return str(class_def(c, data).get("name", c.get("class", "")))


## Recomputes the derived cache in place. Call after creation, load, equip, level-up.
static func refresh(c: Dictionary, data: Dictionary, session_items: Dictionary = {}) -> void:
	sanitize_equipped(c)
	if data.has("items") and data.has("rules"):
		FeatureRules.pact_tidy(c, data, session_items)  # a pact weapon that left its holder (v0.8.4.33)
	for h: Dictionary in Thing.holders(c):
		Thing.trim(h)
	if data.has("rules") and data["rules"].has("containers"):
		ContainerRules.sync_bags(c, data)  # one bag per container item in the pack (v0.7.18.2)
	_grant_trait_cantrips(c, data)
	if (c.get("body", {}) as Dictionary).is_empty() and data.has("rules") and data["rules"].has("body") and c.has("race"):
		c["body"] = BodyRules.make(data, str(c.get("gender", "other")), {}, "hero:" + str(c.get("name", "")), true)  # an old save (v0.7.22.5)
	c["item_props"] = active_props(c, data, session_items)  # v0.7.12
	ItemRules.wear(c, data, session_items)  # v0.8.4.26: what the worn things lay, before the speed reads it
	var floors := {}
	for p: Variant in c["item_props"]:
		if str(p).ends_with("_19") and ABILITIES.has(str(p).get_slice("_", 0)):
			floors[str(p).get_slice("_", 0)] = 19
	c["ability_floor"] = floors
	c["race_name"] = race_name(c, data)
	c["class_name"] = class_name_of(c, data)
	c["prof_bonus"] = prof_bonus(c, data)
	var drained := ConditionRules.max_hp_shift(c)  # Aid, a life drain until a long rest (v0.7.9)
	c["max_hp"] = maxi(1, max_hp(c, data) / (2 if int(c.get("exhaustion", 0)) >= 4 else 1) + drained)  # exhaustion 4 halves it (v0.7.8)
	c["hp"] = clampi(int(c.get("hp", c["max_hp"])), 0, int(c["max_hp"]))
	c["ac"] = armor_class(c, data, session_items)
	# The sheet's numbers are the sums of their parts (v0.7.39.5): the ability, proficiency, items (the Stone of Good
	# Luck, v0.7.12; a Cloak of Protection), spells (Pass without Trace, v0.7.13.3) — the breakdown on hover shows them.
	var skills := {}
	for id: String in data["rules"]["skills"]:
		skills[id] = RollParts.sum(RollParts.sheet(c, data, "skill", id, session_items))
	c["skills"] = skills
	var saves := {}
	for id: String in ABILITIES:
		saves[id] = RollParts.sum(RollParts.sheet(c, data, "save", id, session_items))
	c["saves"] = saves
	c["speed"] = speed(c, data)
	c["passive_perception"] = 10 + int(skills["perception"])
	c["slots_max"] = slots_max(c, data)
	var ab := spell_ability(c, data)
	c["spell_ability"] = ab
	if not ab.is_empty():
		c["spell_dc"] = 8 + int(c["prof_bonus"]) + mod(ability(c, ab)) + FaithRules.lapse(c, data, "spell_dc")  # v0.7.49
		c["spell_attack"] = int(c["prof_bonus"]) + mod(ability(c, ab)) + (1 if item_prop(c, "spell_attack_plus1") else 0) + FaithRules.lapse(c, data, "spell_attack")
	else:
		c.erase("spell_dc")
		c.erase("spell_attack")


## Equipped items must still be in the inventory (an item given away is unequipped).
static func sanitize_equipped(c: Dictionary) -> void:
	var eq: Dictionary = c.get("equipped", {})
	var inv: Dictionary = c.get("inventory", {})
	for row: Dictionary in [eq, stowed(c)]:  # a shield of its own slot, before v0.8.4.43.13: into the off hand
		if row.has("shield"):
			if str(row.get("off_hand", "")).is_empty():
				row["off_hand"] = str(row["shield"])
			row.erase("shield")
	for slot: String in SLOTS:
		var id := str(eq.get(slot, ""))
		if not id.is_empty() and int(inv.get(id, 0)) <= 0:
			eq[slot] = ""
	c["equipped"] = eq
	for slot: String in stowed(c):
		if int(inv.get(str(stowed(c)[slot]), 0)) <= 0:
			stowed(c)[slot] = ""
	for id: Variant in (c.get("attuned", []) as Array).duplicate():  # a thing given away loses its attunement (v0.7.12)
		if int(inv.get(str(id), 0)) <= 0:
			(c["attuned"] as Array).erase(id)


# --- the two weapon sets (v0.8.4.1, as in BG3) ---------------------------------------------------------------------


## The set put away: {main_hand, off_hand}. What is in the hands is `equipped`, so the rules read one place.
static func stowed(c: Dictionary) -> Dictionary:
	return c.get("stowed", {})


## The kind of a thing: a bow, a crossbow, a sling are ranged, the rest, a shield too, melee. Only the starting kit
## is sorted by it (auto_equip); the two sets themselves take any weapon (v0.8.4.24.1).
static func set_kind(def: Dictionary) -> String:
	return "ranged" if str(def.get("weapon", {}).get("range", "melee")) == "ranged" else "melee"


## The kind of a set by what it holds ("" — empty hands): for its name on the panel and the sheet.
static func hands_kind(hands: Dictionary, data: Dictionary, session_items: Dictionary) -> String:
	for slot: String in HANDS:
		var id := str(hands.get(slot, ""))
		if not id.is_empty():
			return set_kind(ItemRules.def_of(data["items"], session_items, id))
	return ""


## "" when the sets can change places, otherwise a reason (localization key).
static func swap_why(c: Dictionary, data: Dictionary, session_items: Dictionary) -> String:
	if hands_kind(stowed(c), data, session_items).is_empty():
		return "SWAP_EMPTY"
	for slot: String in HANDS:
		if ItemRules.held_by_curse(c, data, session_items, str(c.get("equipped", {}).get(slot, ""))):
			return "ITEM_CURSED"
	return ""


static func swap_hands(c: Dictionary) -> void:
	var eq: Dictionary = c.get("equipped", {})
	var was := stowed(c)
	var out := {}
	for slot: String in HANDS:
		out[slot] = str(eq.get(slot, ""))
		eq[slot] = str(was.get(slot, ""))
	c["stowed"] = out


## Puts a thing into the row put away (can_equip first): a weapon of two hands empties the other hand of that row; the
## last copy held in the hands moves over (v0.8.4.24).
static func put_stowed(c: Dictionary, data: Dictionary, session_items: Dictionary, id: String, slot: String) -> void:
	if not c.has("stowed"):
		c["stowed"] = {}
	var row := stowed(c)
	free_copy(c, id, c.get("equipped", {}), slot, row)
	row[slot] = id
	if _two_handed(data, session_items, id) and slot == "main_hand":
		row["off_hand"] = ""
	if slot == "main_hand" and str(row.get("off_hand", "")) == id and int(c["inventory"].get(id, 0)) < 2:
		row["off_hand"] = ""


## A copy of `id` about to go to `to[slot]`: when every copy is already held, the one in the hands of the other row
## leaves them — a javelin moves between the sets, it is not doubled.
static func free_copy(c: Dictionary, id: String, from: Dictionary, slot: String, to: Dictionary) -> void:
	if str(to.get(slot, "")) == id or held_copies(c, id) < int(c.get("inventory", {}).get(id, 0)):
		return
	for sl: String in HANDS:
		if str(from.get(sl, "")) == id:
			from[sl] = ""
			return


## How many copies of the thing are held or worn: a stowed weapon is not for sale either.
## Which copy of `id` the slot holds (v0.8.4.35): the first slot of it the first copy, a second hand of the same the second.
static func hold_index(c: Dictionary, id: String, slot: String) -> int:
	var n := 0
	for sl: String in SLOTS:
		if sl == slot:
			return n
		if str(c.get("equipped", {}).get(sl, "")) == id:
			n += 1
	return 0


static func held_copies(c: Dictionary, id: String) -> int:
	var n := 0
	for slot: String in SLOTS:
		if str(c.get("equipped", {}).get(slot, "")) == id:
			n += 1
	for slot: String in stowed(c):
		if str(stowed(c)[slot]) == id:
			n += 1
	return n


## The slot an item goes to, or "" if it cannot be equipped. A weapon goes to the main hand, a shield to the off hand; a
## wondrous thing to the slot of its look (rules.wear_slots, v0.7.22.9; a ring — ring1, ring2 fits too).
static func slot_for(def: Dictionary, data: Dictionary = {}) -> String:
	if def.has("armor"):
		return "off_hand" if is_shield(def) else "armor"
	if def.has("weapon") or str(def.get("item_type", "")) == "weapon":
		return "main_hand"
	return wear_slot(def, data)


## The worn slot of a wondrous thing ("" — it works carried).
static func wear_slot(def: Dictionary, data: Dictionary) -> String:
	if not str(def.get("slot", "")).is_empty():
		return str(def["slot"])
	if str(def.get("item_type", "")) != "wondrous" or data.is_empty() or not data["rules"].has("wear_slots"):
		return ""
	var by: Dictionary = data["rules"]["wear_slots"]["by_look"]
	var look := str(def.get("look", "")).to_lower()
	if by.has(look):
		return str(by[look])
	var first := str(def.get("name", "")).to_lower().get_slice(" ", 0)
	for k: String in by:
		if first.begins_with(k.get_slice(" ", 0)):
			return str(by[k])
	return ""


## The worn slots a thing fits: its own, the second ring, the off hand of a light weapon.
static func slots_of(def: Dictionary, data: Dictionary) -> Array[String]:
	var slot := slot_for(def, data)
	var out: Array[String] = []
	if not slot.is_empty():
		out.append(slot)
	if slot == "ring1":
		out.append("ring2")
	if slot == "main_hand" and (def.get("properties", []) as Array).has("light"):
		out.append("off_hand")
	return out


## "" when the character can equip `id` into `slot`, otherwise a reason (localization key).
## `spare` — into the set put away, else into the hands: either set takes any weapon (v0.8.4.24.1).
static func can_equip(c: Dictionary, data: Dictionary, session_items: Dictionary, id: String, slot: String, spare: bool = false) -> String:
	if int(c.get("inventory", {}).get(id, 0)) <= 0:
		return "EQUIP_NOT_OWNED"
	var def := ItemRules.def_of(data["items"], session_items, id)
	var natural := slot_for(def, data)
	if natural.is_empty() or (natural != slot and not (natural == "main_hand" and slot == "off_hand") and not (natural == "ring1" and slot == "ring2")):
		return "EQUIP_WRONG_SLOT"
	if natural == "ring1" and str(c.get("equipped", {}).get("ring1" if slot == "ring2" else "ring2", "")) == id and int(c["inventory"][id]) < 2:
		return "EQUIP_NOT_OWNED"
	var eq: Dictionary = stowed(c) if HANDS.has(slot) and spare else c.get("equipped", {})
	var profs: Array = c.get("armor_profs", [])
	match slot:
		"armor":
			if not profs.has(str(def["armor"]["category"])):
				return "EQUIP_NO_PROFICIENCY"
		"off_hand":  # a shield or a light weapon; what the hand held goes to the pack
			if is_shield(def) and not profs.has("shield"):
				return "EQUIP_NO_PROFICIENCY"
			if not is_shield(def) and not (def.get("properties", []) as Array).has("light"):
				return "EQUIP_NOT_LIGHT"
			if _two_handed(data, session_items, str(eq.get("main_hand", ""))):
				return "EQUIP_HANDS_BUSY"
			if str(eq.get("main_hand", "")) == id and int(c["inventory"][id]) < 2:
				return "EQUIP_NOT_OWNED"
		"main_hand":  # a two-handed grip frees the other hand (hands_freed); a cursed thing there holds it
			for sl: String in hands_freed(c, data, session_items, id, slot):
				if ItemRules.held_by_curse(c, data, session_items, str(eq.get(sl, ""))):
					return "EQUIP_HANDS_BUSY"
	return ""


## The slots a weapon taken in both hands empties: the off hand, a weapon or a shield. A two-handed weapon always,
## a versatile one when `both` (5e: its bigger die).
static func hands_freed(c: Dictionary, data: Dictionary, session_items: Dictionary, id: String, slot: String, both: bool = false) -> Array[String]:
	var out: Array[String] = []
	if slot != "main_hand":
		return out
	var w := ItemRules.def_of(data["items"], session_items, id)
	if not ((w.get("properties", []) as Array).has("two_handed") or (both and (w.get("weapon", {}) as Dictionary).has("versatile"))):
		return out
	if not str(c.get("equipped", {}).get("off_hand", "")).is_empty():
		out.append("off_hand")
	return out


## The weapon in the main hand is held in both: a two-handed one, or a versatile one with the other hand empty (a duelist
## keeps it in one: its +2 is worth more than the bigger die, v0.8.4.33).
static func two_hand_grip(c: Dictionary, data: Dictionary, session_items: Dictionary) -> bool:
	var eq: Dictionary = c.get("equipped", {})
	var id := str(eq.get("main_hand", ""))
	if id.is_empty():
		return false
	var w := ItemRules.def_of(data["items"], session_items, id)
	return _two_handed(data, session_items, id) or ((w.get("weapon", {}) as Dictionary).has("versatile")
		and str(eq.get("off_hand", "")).is_empty() and not style(c, "dueling"))


## What a character may take expertise in by `features` (v0.8.4.43.46): its skills, and a tool of `expertise_tools` of
## rules.feature_grants of those features that it knows (the rogue's thieves' tools, 5e); less what it has expertise in already.
static func expertise_pool(data: Dictionary, skills: Array, tools: Array, features: Array, have: Array) -> Array:
	var out: Array = []
	for sk: Variant in skills:
		if not out.has(str(sk)) and not have.has(str(sk)):
			out.append(str(sk))
	var grants: Dictionary = data["rules"].get("feature_grants", {})
	for f: Variant in features:
		for tool: Variant in grants.get(str(f), {}).get("expertise_tools", []):
			if tools.has(str(tool)) and not out.has(str(tool)) and not have.has(str(tool)):
				out.append(str(tool))
	return out


## The word of a pick of expertise: a skill's, or a tool's.
static func expertise_word(data: Dictionary, id: String) -> String:
	return TranslationServer.translate("SKILL_" + id.to_upper()) if data["rules"]["skills"].has(id) else BackgroundRules.tool_name(data, id)


## A hand is free to catch or hold a thing: the main hand empty, or the off hand empty beside a weapon that is not
## two-handed (a versatile one lets go of its second hand at once). `c` — anybody's things (Sheet.things).
static func free_hand(c: Dictionary, data: Dictionary, session_items: Dictionary) -> bool:
	var eq: Dictionary = c.get("equipped", {})
	var main := str(eq.get("main_hand", ""))
	return main.is_empty() or (str(eq.get("off_hand", "")).is_empty() and not _two_handed(data, session_items, main))


## Pounds the hero carries: everything in the pack, worn things too (v0.7.7).
static func carried_weight(c: Dictionary, data: Dictionary, session_items: Dictionary = {}) -> float:
	var total := 0.0
	for id: String in c.get("inventory", {}):
		total += float(ItemRules.def_of(data["items"], session_items, id).get("weight", 0)) * int(c["inventory"][id])
	return total + ContainerRules.bags_weight(c, data, session_items) + LiquidRules.extra_weight(c, data, session_items)  # bags, water


## Carrying capacity (PHB): Strength × rules.carry.per_str pounds.
static func capacity(c: Dictionary, data: Dictionary) -> int:
	return ability(c, "str") * int(data["rules"].get("carry", {}).get("per_str", 15)) + (500 if item_prop(c, "carry_plus_500") else 0)


static func overloaded(c: Dictionary, data: Dictionary, session_items: Dictionary = {}) -> bool:
	return carried_weight(c, data, session_items) > capacity(c, data)


## Minutes a change of gear takes out of a fight (v0.7.7, PHB): armour off and on by its category
## (rules.equip_minutes); a shield and weapons take none. `before` / `after` — the equipped slots.
static func gear_minutes(data: Dictionary, session_items: Dictionary, before: Dictionary, after: Dictionary) -> int:
	var t: Dictionary = data["rules"].get("equip_minutes", {})
	var total := 0
	for pair: Array in [[str(before.get("armor", "")), str(after.get("armor", ""))],
			[shield_in(before, data, session_items), shield_in(after, data, session_items)]]:
		var was := str(pair[0])
		var now := str(pair[1])
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


## Best starting kit: the heaviest armor with proficiency, a melee weapon in hand, the best ranged one in the other set,
## a shield when the hand is free. `full` — every weapon in a hand (a template's gear, v0.8.4.40: it strikes only with what
## it holds): one that finds its set taken goes to the other, a second light blade to the off hand when there is no shield.
static func auto_equip(c: Dictionary, data: Dictionary, full := false) -> void:
	var eq := {"armor": "", "main_hand": "", "off_hand": ""}
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
	c["stowed"] = {}
	var left: Array[String] = []
	for id: String in weapons:
		var row: Dictionary = stowed(c) if set_kind(ItemRules.def_of(data["items"], {}, id)) == "ranged" else eq
		if str(row.get("main_hand", "")).is_empty():
			row["main_hand"] = id
		else:
			left.append(id)
	if str(eq["main_hand"]).is_empty():
		swap_hands(c)
	for id: String in c.get("inventory", {}):
		if not is_shield(ItemRules.def_of(data["items"], {}, id)):
			continue
		if can_equip(c, data, {}, id, "off_hand").is_empty():
			eq["off_hand"] = id
			break
		if can_equip(c, data, {}, id, "off_hand", true).is_empty():  # a bow in both hands: the shield with the blade
			stowed(c)["off_hand"] = id
			break
	if not full:
		return
	var main := str(eq.get("main_hand", ""))
	for id: String in left + ([main] as Array[String]):  # a second blade in the free hand (a captain's dagger)
		if not main.is_empty() and str(eq["off_hand"]).is_empty() and can_equip(c, data, {}, id, "off_hand").is_empty():
			eq["off_hand"] = id
			left.erase(id)
			break
	for id: String in left:  # the rest in the empty hands of the other set (an orc's javelin)
		for row: Dictionary in [stowed(c), eq]:
			if str(row.get("main_hand", "")).is_empty():
				row["main_hand"] = id
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
	_grant_free_spells(c, data)
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
