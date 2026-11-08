class_name Equip
extends RefCounted
## What anybody puts on and takes off (v0.8.4.40, ADR-0016): the hero, a person, a follower, a foe — one set of rules on
## what `Gear.of` gives (the hero's sheet, a fighter, a record). The checks are CharacterRules' (`can_equip`,
## `hands_freed`, `swap_why`); here is who may wear what, what a fight forbids, the curse that holds a slot, and what the
## change lays: the hero's sheet refreshed, another's worn things laid on it (`ItemRules.wear`, `Gear.follow` in a fight).
## The window and the master's `equip` only call these.


## The armour it may wear: the hero's own; a template's — its class's (`rules.combat.classed`), the armour of its SRD gear
## and `rules.creatures.gear.armor` (5e: a creature is proficient with what it is made to wear).
static func armor_profs(s: GameSession, data: Dictionary, id: String) -> Array:
	if id == Being.HERO:
		return s.character.get("armor_profs", [])
	var holder := Gear.of(s, data, id)
	if holder.has("armor_profs"):
		return holder["armor_profs"]
	var tid := Sheet.template_id(data, Sheet.who(s, data, id))
	var out: Array = (cfg(data)["armor"] as Array).duplicate()
	var classed: Dictionary = CombatRules.cfg(data).get("classed", {}).get(tid, {})
	for cat: Variant in data["classes"]["classes"].get(str(classed.get("class", "")), {}).get("armor", []):
		if not out.has(cat):
			out.append(cat)
	for item: Variant in data["monsters"].get(tid, {}).get("equipment", []):
		var cat := str(data["items"]["catalog"].get(str(item), {}).get("armor", {}).get("category", ""))
		if not cat.is_empty() and not out.has(cat):
			out.append(cat)
	return out


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"]["creatures"]["gear"]


## Its own holder for the checks of CharacterRules: a template knows the armour it may wear.
static func _probe(s: GameSession, data: Dictionary, id: String) -> Dictionary:
	var c := Gear.of(s, data, id)
	return c if id == Being.HERO or c.has("armor_profs") else c.merged({"armor_profs": armor_profs(s, data, id)})


## A creature without hands to put things on (a beast, an ooze): "" — it has them.
static func hands_why(s: GameSession, data: Dictionary, id: String) -> String:
	if id == Being.HERO:
		return ""
	var m: Dictionary = data["monsters"].get(Sheet.template_id(data, Sheet.who(s, data, id)), {})
	return "EQUIP_NO_HANDS" if (cfg(data)["no_hands"] as Array).has(str(m.get("type", "")).get_slice(" ", 0)) else ""


## "" when `id` may put `item` into `slot` now, else the reason (a localization key). `spare` — into the set put away,
## `both` — a versatile weapon in both hands.
static func why(s: GameSession, data: Dictionary, id: String, item: String, slot: String, spare := false, both := false) -> String:
	var hands := hands_why(s, data, id)
	if not hands.is_empty():
		return hands
	var c := _probe(s, data, id)
	var fight := CombatRules.active(s)
	if CharacterRules.HANDS.has(slot) and spare:
		return "EQUIP_IN_COMBAT" if slot == "shield" and fight else CharacterRules.can_equip(c, data, s.items, item, slot, true)
	var freed := CharacterRules.hands_freed(c, data, s.items, item, slot, both)
	if fight and (slot in ["armor", "shield"] or CharacterRules.WEAR_SLOTS.has(slot) or freed.has("shield")):
		return "EQUIP_IN_COMBAT"
	var reason := CharacterRules.can_equip(c, data, s.items, item, slot)
	if not reason.is_empty():
		return reason
	return "ITEM_CURSED" if ItemRules.held_by_curse(c, data, s.items, str(c.get("equipped", {}).get(slot, ""))) else ""


## Puts `item` into `slot` (why first): the hands it frees, one copy in one place, a ring on one finger. Settles.
static func put(s: GameSession, data: Dictionary, id: String, item: String, slot: String, spare := false, both := false) -> void:
	var c := Gear.of(s, data, id)
	if CharacterRules.HANDS.has(slot) and spare:
		CharacterRules.put_stowed(c, data, s.items, item, slot)
		settle(s, data, id)
		return
	var freed := CharacterRules.hands_freed(c, data, s.items, item, slot, both)
	if not c.has("equipped"):
		c["equipped"] = {}
	var eq: Dictionary = c["equipped"]
	if CharacterRules.HANDS.has(slot):  # the last copy in the set put away comes to the hands (v0.8.4.24)
		CharacterRules.free_copy(c, item, CharacterRules.stowed(c), slot, eq)
	eq[slot] = item
	for sl: String in freed:  # both hands on the weapon: the shield and the off hand go to the pack
		eq[sl] = ""
	if slot == "main_hand" and str(eq.get("off_hand", "")) == item and int(c["inventory"][item]) < 2:
		eq["off_hand"] = ""
	for pair: Array in [["ring1", "ring2"], ["ring2", "ring1"]]:  # one ring cannot be on two fingers
		if slot == pair[0] and str(eq.get(pair[1], "")) == item and int(c["inventory"][item]) < 2:
			eq[pair[1]] = ""
	settle(s, data, id)


## "" when the slot may be emptied now, else the reason.
static func off_why(s: GameSession, data: Dictionary, id: String, slot: String, spare := false) -> String:
	var c := Gear.of(s, data, id)
	var row: Dictionary = CharacterRules.stowed(c) if spare else c.get("equipped", {})
	if str(row.get(slot, "")).is_empty():
		return "EQUIP_EMPTY"
	if CombatRules.active(s) and (slot in ["armor", "shield"] or CharacterRules.WEAR_SLOTS.has(slot)):
		return "EQUIP_IN_COMBAT"
	return "ITEM_CURSED" if not spare and ItemRules.held_by_curse(c, data, s.items, str(row[slot])) else ""


static func off(s: GameSession, data: Dictionary, id: String, slot: String, spare := false) -> void:
	var c := Gear.of(s, data, id)
	if spare:
		CharacterRules.stowed(c)[slot] = ""
	else:
		c["equipped"][slot] = ""
	settle(s, data, id)


## Everything off at once: the slots of both sets (off_why each first).
static func strip_why(s: GameSession, data: Dictionary, id: String) -> String:
	var c := Gear.of(s, data, id)
	var worn := false
	for sl: String in CharacterRules.SLOTS:
		if str(c.get("equipped", {}).get(sl, "")).is_empty():
			continue
		worn = true
		var reason := off_why(s, data, id, sl)
		if not reason.is_empty():
			return reason
	return "" if worn else "EQUIP_EMPTY"


static func strip(s: GameSession, data: Dictionary, id: String) -> void:
	var c := Gear.of(s, data, id)
	for sl: String in CharacterRules.SLOTS:
		(c["equipped"] as Dictionary)[sl] = ""
	c["stowed"] = {}
	settle(s, data, id)


## The other weapon set to its hands: for nothing, as in BG3.
static func swap_why(s: GameSession, data: Dictionary, id: String) -> String:
	if Guise.has_body(s.character if id == Being.HERO else Sheet.who(s, data, id)):
		return "COMBAT_WILD_SHAPE"
	return CharacterRules.swap_why(Gear.of(s, data, id), data, s.items)


static func swap(s: GameSession, data: Dictionary, id: String) -> void:
	CharacterRules.swap_hands(Gear.of(s, data, id))
	settle(s, data, id)


## A thing it just got goes on by itself when its place is free (BG3: a companion takes up what it is given): armour, a
## shield, a weapon into the empty hands — a ranged one into the empty set put away —, a ring, a cloak. True when worn.
static func fill(s: GameSession, data: Dictionary, id: String, item: String) -> bool:
	if not hands_why(s, data, id).is_empty():
		return false
	var c := Gear.of(s, data, id)
	var def := ItemRules.def_of(data["items"], s.items, item)
	for slot: String in CharacterRules.slots_of(def, data):
		if slot == "off_hand":
			continue  # a second weapon is a choice, not a free hand
		var row: Dictionary = c.get("equipped", {})
		var spare := slot == "main_hand" and not str(row.get(slot, "")).is_empty() and CharacterRules.set_kind(def) == "ranged"
		if spare:
			row = CharacterRules.stowed(c)
		if not str(row.get(slot, "")).is_empty() or CharacterRules.held_copies(c, item) >= int(c.get("inventory", {}).get(item, 0)):
			continue
		if why(s, data, id, item, slot, spare).is_empty():
			put(s, data, id, item, slot, spare)
			return true
	return false


## What the change lays: the hero's sheet refreshed; another's worn things on it — in a fight its blows and AC follow.
static func settle(s: GameSession, data: Dictionary, id: String) -> void:
	if id == Being.HERO:
		CharacterRules.refresh(s.character, data, s.items)
		return
	var f := CombatRules.fighter(s, id) if CombatRules.active(s) else {}
	if not f.is_empty() and f.has("inventory"):
		Gear.follow(s, data, f)
		return
	var c := Gear.of(s, data, id)
	CharacterRules.sanitize_equipped(c)
	ItemRules.wear(c, data, s.items)


## "" when `item` may pass from `from` to `to` now — the hero and one who walks with it (the «Снаряжение» window): only what
## is not on the giver's body, a cursed thing in the pockets too (v0.8.4.39). Else the reason.
static func hand_why(s: GameSession, data: Dictionary, from: String, to: String, item: String) -> String:
	if CombatRules.active(s):
		return "GEAR_NOT_IN_COMBAT"
	var other := to if from == Being.HERO else from
	if not Being.follows(s, other) or (from != Being.HERO and to != Being.HERO):
		return "GEAR_NOT_FOLLOWER"
	var c := Gear.of(s, data, from)
	if int(c.get("inventory", {}).get(item, 0)) <= CharacterRules.held_copies(c, item):
		return "GEAR_TAKE_OFF_FIRST" if int(c.get("inventory", {}).get(item, 0)) > 0 else "EQUIP_NOT_OWNED"
	return ""


## One copy over: out of the giver's things (ItemRules.remove), into the other's — a companion puts it on where it fits (Gear.give).
static func hand(s: GameSession, data: Dictionary, from: String, to: String, item: String) -> Array[String]:
	if ItemRules.remove(Gear.of(s, data, from), item, 1) <= 0:
		return []
	Gear.give(s, data, to, item)
	settle(s, data, from)
	settle(s, data, to)
	return []
