class_name FoodRules
extends RefCounted
## Food (roadmap v0.7.25): a carried perishable (an item's `spoils_days`) keeps its batches in c["fresh"]
## {id: [[minute got, qty]]}; a batch past its days turns into rules.needs.spoil_to. A dish's `meal`
## (rules.consumables) gives water and temporary HP on eating, its `adv_tag` a boon for a while.


static func spoils_days(data: Dictionary, session_items: Dictionary, id: String) -> int:
	return int(ItemRules.def_of(data["items"], session_items, ItemRules.real_id(id)).get("spoils_days", 0))


static func _fresh(c: Dictionary) -> Dictionary:
	if not (c.get("fresh") is Dictionary):
		c["fresh"] = {}
	return c["fresh"]


## Brings the batches to the inventory: units beyond the batches were got now, missing ones went oldest first.
static func sync(s: GameSession, data: Dictionary) -> void:
	var c := s.character
	var fresh := _fresh(c)
	var inv: Dictionary = c.get("inventory", {})
	var now := TimeRules.abs_minute(s)
	for id: String in fresh.keys():
		if not inv.has(id):
			fresh.erase(id)
	for id: String in inv:
		if spoils_days(data, s.items, id) <= 0:
			continue
		var batches: Array = fresh.get(id, [])
		var total := 0
		for b: Array in batches:
			total += int(b[1])
		var have := int(inv[id])
		if have > total:
			batches.append([now, have - total])
		var cut := total - have
		while cut > 0 and not batches.is_empty():
			var n := mini(cut, int(batches[0][1]))
			batches[0][1] = int(batches[0][1]) - n
			cut -= n
			if int(batches[0][1]) <= 0:
				batches.pop_front()
		fresh[id] = batches


## The days a perishable has left before it spoils (its oldest batch); -1 when it does not spoil.
static func days_left(s: GameSession, data: Dictionary, id: String) -> int:
	var days := spoils_days(data, s.items, id)
	if days <= 0:
		return -1
	var batches: Array = _fresh(s.character).get(id, [])
	if batches.is_empty():
		return days
	return maxi(0, ceili((int(batches[0][0]) + days * 1440 - TimeRules.abs_minute(s)) / 1440.0))


## Batches past their days spoil (with the needs on). Lines.
static func tick(s: GameSession, data: Dictionary) -> Array[String]:
	var to := str(data["rules"].get("needs", {}).get("spoil_to", ""))
	if not NeedRules.on(s) or to.is_empty():
		return []
	sync(s, data)
	var c := s.character
	var inv: Dictionary = c["inventory"]
	var fresh := _fresh(c)
	var now := TimeRules.abs_minute(s)
	var names: Array[String] = []
	for id: String in fresh.keys():
		var limit := spoils_days(data, s.items, id) * 1440
		var batches: Array = fresh[id]
		var gone := 0
		while not batches.is_empty() and now - int(batches[0][0]) >= limit:
			gone += int(batches.pop_front()[1])
		if gone > 0:
			names.append("%s ×%d" % [ItemRules.display_name(data["items"], s.items, id), gone])
			var left := int(inv.get(id, 0)) - gone
			if left > 0:
				inv[id] = left
			else:
				inv.erase(id)
			inv[to] = int(inv.get(to, 0)) + gone
		if batches.is_empty():
			fresh.erase(id)
	if names.is_empty():
		return []
	CharacterRules.refresh(c, data, s.items)
	return ["Испортилось: " + ", ".join(names)]


## A dish eaten (already taken from the pack): its water, temporary HP and boon. Lines.
static func meal(s: GameSession, data: Dictionary, id: String) -> Array[String]:
	var fx := ItemRules.consumable(data, id, s.items)
	if not fx.has("meal"):
		return []
	var m: Dictionary = fx["meal"]
	var c := s.character
	var lines: Array[String] = []
	if int(m.get("water", 0)) > 0 and NeedRules.on(s):
		NeedRules.set_value(s, data, "water", NeedRules.value(s, data, "water") + float(m["water"]))
	if int(m.get("temp_hp", 0)) > int(c.get("temp_hp", 0)):
		c["temp_hp"] = int(m["temp_hp"])
		lines.append("временные хиты: %d" % int(m["temp_hp"]))
	if fx.has("adv_tag"):
		var d := ItemRules.def_of(data["items"], s.items, ItemRules.real_id(id))
		lines.append_array(ConditionRules.cure(s, data, fx, {"kind": "item", "id": ItemRules.real_id(id), "name": str(d.get("name", id))}))
	return lines


## A dish eaten from the pack by «Использовать»: its food points, then the meal. Lines.
static func eat_one(s: GameSession, data: Dictionary, id: String) -> Array[String]:
	var lines: Array[String] = []
	var food: Dictionary = data["rules"]["hero_effects"]["camp"]["food"]
	if NeedRules.on(s) and food.has(id):
		var v := NeedRules.value(s, data, "food") + float(food[id]) * float(NeedRules.cfg(data)["food"]["points"])
		NeedRules.set_value(s, data, "food", v)
		lines.append("Еда %d/100" % roundi(NeedRules.value(s, data, "food")))
	lines.append_array(meal(s, data, id))
	var foul: Dictionary = data["rules"].get("diseases", {}).get("foul_food", {})
	if foul.has(id):
		lines.append_array(DiseaseRules.expose(s, data, str(foul[id]["disease"]), int(foul[id]["dc"]), "Дурная еда"))
	return lines
