class_name ItemActs
extends RefCounted
## What anybody can do with a thing it carries (v0.8.4.43.6, the character window as in BG3): one list for the right
## button's menu of a cell, the double click's main act and a playtest. A row is {act, item, name, label, args, why, group}:
## `act` names the road GameState.item_act takes, `label` is a localization key formatted with `args`, `why` is "" or the
## reason it is grey, `group` a submenu's title key, `name` the node name of its button. The rules are the engine's own
## (Equip, ItemRules, LiquidRules, ContainerRules); here is only which of them apply to this thing of this character.
## Pure: no nodes.

## The acts a double click takes, the first that may be done now.
const MAIN := ["equip", "use", "drink", "open"]


## The acts of `item` in `who`'s things; `worn` — the slot it is worn in ("" — loose), `spare` — of the set put away.
static func of(s: GameSession, data: Dictionary, who: String, item: String, worn := "", spare := false) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var c := Gear.of(s, data, who)
	if int(c.get("inventory", {}).get(item, 0)) <= 0:
		return out
	var def := ItemRules.def_of(data["items"], s.items, item)
	if not worn.is_empty():
		out.append(_row("unequip", item, ("UnequipStowed_" if spare else "Unequip_") + worn, "BTN_UNEQUIP", Equip.off_why(s, data, who, worn, spare),
			{"slot": worn, "spare": spare}))
		if not spare and worn == "main_hand" and (def.get("weapon", {}) as Dictionary).has("versatile") \
				and not CharacterRules.two_hand_grip(c, data, s.items):  # 5e versatile: the bigger die, the off hand and the shield to the pack
			out.append(_row("equip", item, "BothHands", "BTN_BOTH_HANDS", Equip.why(s, data, who, item, "main_hand", false, true),
				{"slot": "main_hand", "both": true}))
	_equip_rows(s, data, who, c, item, def, out)
	if who == Being.HERO:
		_hero_rows(s, data, c, item, worn, out)
	else:
		out.append(_row("take", item, "GearTake_" + item, "BTN_GEAR_TAKE", Equip.hand_why(s, data, who, Being.HERO, item)))
	return out


## The act a double click takes: the first of MAIN that may be done now, {} — none.
static func main(rows: Array[Dictionary]) -> Dictionary:
	for act: String in MAIN:
		for r: Dictionary in rows:
			if str(r["act"]) == act and str(r["why"]).is_empty() and not bool(r.get("spare", false)) and not bool(r.get("both", false)):
				return r
	return {}


## Into each slot it fits where it is not now; a weapon or a shield into the set put away too (v0.8.4.24.1).
static func _equip_rows(s: GameSession, data: Dictionary, who: String, c: Dictionary, item: String, def: Dictionary, out: Array[Dictionary]) -> void:
	for slot: String in CharacterRules.slots_of(def, data):
		var two := slot == "main_hand" and (def.get("properties", []) as Array).has("two_handed")
		var shield := CharacterRules.is_shield(def)
		if str(c.get("equipped", {}).get(slot, "")) != item:
			out.append(_row("equip", item, "Equip_%s_%s" % [slot, item], "BTN_EQUIP_BOTH_HANDS" if two else "BTN_EQUIP_SHIELD" if shield else "BTN_EQUIP_" + slot.to_upper(),
				Equip.why(s, data, who, item, slot), {"slot": slot}))
		if CharacterRules.HANDS.has(slot) and str(CharacterRules.stowed(c).get(slot, "")) != item:
			out.append(_row("equip", item, "EquipStowed_%s_%s" % [slot, item], "BTN_EQUIP_STOWED_OFF" if slot == "off_hand" and not shield else "BTN_EQUIP_STOWED",
				Equip.why(s, data, who, item, slot, true), {"slot": slot, "spare": true}))


## The hero's own roads: a meal, the belt, a liquid, a forged letter, a quiver, attunement, a spell kept in a thing, a bag,
## a companion's hands, the floor.
static func _hero_rows(s: GameSession, data: Dictionary, c: Dictionary, item: String, worn: String, out: Array[Dictionary]) -> void:
	var def := ItemRules.def_of(data["items"], s.items, item)
	var fx := ItemRules.consumable(data, item, s.items)
	if fx.has("meal"):  # food from the pack; the rest is used from the belt (v0.8.4.24)
		out.append(_row("use", item, "UseItem_" + item, "BTN_USE", ""))
	elif worn.is_empty() and ItemRules.belt_fits(data, s.items, item) and not ItemRules.on_belt(c, data, s.items, item):
		out.append(_row("belt", item, "BeltPut_" + item, "BTN_BELT_PUT", ItemRules.belt_why(c, data, s.items, item)))
	_liquid_rows(s, data, c, item, out)
	if not LetterRules.way_by(data, "tool", item).is_empty():  # a forgery kit writes in the letter's window (v0.8.4.26.4)
		out.append(_row("letter", item, "Letter_" + item, "BTN_LETTER_WRITE", ""))
	for into: Dictionary in ContainerRules.bags_for(s, data, item):  # straight into a quiver or a case (v0.8.4.42.1)
		var n := mini(int(into["n"]), TradeRules.sellable(s, item, data))
		if n > 0:
			var bag := str(into["bag"])
			var name := ContainerRules.bag_name(data, c, bag)
			out.append(_row("to_bag", item, "ToBag_%s_%s" % [bag, item], "BTN_TO_BAG", "", {"bag": bag, "n": n,
				"args": {"name": name.substr(0, 1).to_lower() + name.substr(1)}}))
	if ItemRules.needs_attunement(def):  # v0.7.12
		if ItemRules.attuned(c).has(item):
			out.append(_row("unattune", item, "Unattune_" + item, "BTN_UNATTUNE", ItemRules.can_unattune(c, data, s.items, item)))
		else:
			out.append(_row("attune", item, "Attune_" + item, "BTN_ATTUNE", ItemRules.can_attune(c, data, s.items, item)))
	for o: Dictionary in ItemRules.storable(s, data, item):  # a spell into a thing that keeps spells (v0.8.4.36)
		out.append(_row("store", item, "Store_%s_%s" % [item, o["spell"]], "BTN_STORE_SPELL", "",
			{"spell": str(o["spell"]), "circle": int(o["circle"]), "args": {"name": o["name"], "circle": o["circle"]}}))
	for bag: String in ContainerRules.bags_of(c, item):  # a bag of the pack: its window, or down with what is in it
		out.append(_row("open", item, "OpenBag_" + bag, "BTN_OPEN_BAG_NAMED", "", {"bag": bag, "args": {"name": ContainerRules.bag_name(data, c, bag)}}))
	for f: String in Being.followers(s):
		out.append(_row("give", item, "Give_%s_%s" % [f, item], "BTN_GIVE_TO", Equip.hand_why(s, data, Being.HERO, f, item),
			{"to": f, "group": "BTN_GIVE", "args": {"name": WorldView.name_of(data, f)}}))
	var free := ContainerRules.droppable(s, data, item)  # big test #10 (v0.7.22.2)
	if free > 0:
		out.append(_row("drop", item, "Drop_" + item, "BTN_DROP", "", {"qty": 1}))
		if free > 1:
			out.append(_row("drop", item, "DropAll_" + item, "BTN_DROP_ALL", "", {"qty": free}))
	for bag: String in ContainerRules.bags_of(c, item):
		out.append(_row("drop_bag", item, "DropBag_" + bag, "BTN_DROP_BAG_NAMED", "", {"bag": bag, "args": {"name": ContainerRules.bag_name(data, c, bag)}}))


## What is in a vessel or a ready thing (v0.8.4.28): drink it, pour it into another vessel, pour it out.
static func _liquid_rows(s: GameSession, data: Dictionary, c: Dictionary, item: String, out: Array[Dictionary]) -> void:
	var lv := LiquidRules.first(c, data, item)
	if lv.is_empty() or float(lv["pints"]) <= 0.0:
		return
	var key := LiquidRules.key_of(lv)
	if LiquidRules.drink_why(data, lv).is_empty():
		out.append(_row("drink", item, "Drink_" + item, "BTN_LIQUID_DRINK", "", {"key": key}))
	var skill := LiquidRules.needs_why(c, data, str(lv["liquid"]))
	if not skill.is_empty():  # poured only with its tool (v0.8.4.28.3): grey, the tool named
		out.append(_row("pour", item, "Pour_" + item, "BTN_LIQUID_POUR", skill, {"key": key, "tool": LiquidRules.needs(data, str(lv["liquid"]))}))
	else:
		var i := 0
		for t: Dictionary in LiquidRules.pour_targets(c, data, lv):
			out.append(_row("pour", item, "Pour_%s_%d" % [item, i], "", "", {"key": key, "to": LiquidRules.key_of(t), "group": "BTN_LIQUID_POUR",
				"text": LiquidRules.line(data, s.items, t)}))
			i += 1
	out.append(_row("pour_out", item, "PourOut_" + item, "BTN_LIQUID_POUR_OUT", "", {"key": key}))


static func _row(act: String, item: String, node_name: String, label: String, why: String, extra := {}) -> Dictionary:
	var r := {"act": act, "item": item, "name": node_name, "label": label, "why": why, "args": {}, "group": ""}
	r.merge(extra, true)
	return r
