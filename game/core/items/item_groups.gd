class_name ItemGroups
extends RefCounted
## The hero's things by groups, sorted and filtered (v0.8.4.32, as in BG3 and Pathfinder): a thing's group is the first
## row of `rules.item_rules.groups.rows` whose `when` fits it; the sheet shows a group, a search by name and a sort.

const ALL := ""
const TYPE := "type"


static func cfg(data: Dictionary) -> Dictionary:
	return ItemRules.cfg(data)["groups"]


static func rows(data: Dictionary) -> Array:
	return cfg(data)["rows"]


static func sorts(data: Dictionary) -> Dictionary:
	var out: Dictionary = cfg(data)["sorts"].duplicate()
	out.erase("_doc")
	return out


static func name_of(data: Dictionary, gid: String) -> String:
	for r: Dictionary in rows(data):
		if str(r["id"]) == gid:
			return str(r["name"])
	return gid


## The group of a thing: the id of the first row that fits it.
static func of(data: Dictionary, session_items: Dictionary, id: String) -> String:
	var def := ItemRules.def_of(data["items"], session_items, id)
	for r: Dictionary in rows(data):
		if not r.has("when") or fits(data, session_items, id, def, r["when"]):
			return str(r["id"])
	return str(rows(data).back()["id"])


## Any of the matchers of `when` fits the thing.
static func fits(data: Dictionary, session_items: Dictionary, id: String, def: Dictionary, when: Dictionary) -> bool:
	var real := ItemRules.real_id(id)
	for f: String in when.get("has", []):
		if def.has(f):
			return true
	if (when.get("type", []) as Array).has(str(def.get("item_type", ""))):
		return true
	var use := ItemRules.consumable(data, real, session_items)
	for k: String in when.get("use", []):
		if use.has(k):
			return true
	if bool(when.get("potion", false)) and ItemRules.is_potion(data, session_items, real):
		return true
	if bool(when.get("ammo", false)) and (ItemRules.cfg(data)["ammo"] as Dictionary).values().has(real):
		return true
	if bool(when.get("food", false)) and (data["rules"]["hero_effects"]["camp"]["food"].has(real) or use.has("meal")):
		return true
	if bool(when.get("drink", false)) and drink(data, real):
		return true
	return bool(when.get("container", false)) and not ContainerRules.kind(data, real).is_empty()


## A thing to drink from: a ready drink (ale, wine) or a vessel filled with a drink when full (a waterskin), not a chest or a barrel.
static func drink(data: Dictionary, id: String) -> bool:
	if not ContainerRules.kind(data, id).is_empty():
		return false
	var lid := str(LiquidRules.ready(data, id).get("liquid", LiquidRules.cfg(data)["vessels"].get(id, {}).get("full", "")))
	return LiquidRules.kind(data, lid).has("drink")


## The weight of `qty` of a thing.
static func weight(data: Dictionary, session_items: Dictionary, id: String, qty: int) -> float:
	return ContainerRules.weight(data, session_items, {id: qty})


## The price of `qty` of a thing by the catalog; -1 — not known until it is identified.
static func value(data: Dictionary, session_items: Dictionary, id: String, qty: int) -> int:
	return -1 if id.begins_with(ItemRules.UNKNOWN) else ContainerRules.value(data, session_items, {id: qty})


## How many kinds of things of `inv` fall into each group, in the order of the rows; empty groups left out.
static func counts(data: Dictionary, session_items: Dictionary, inv: Dictionary) -> Dictionary:
	var by := {}
	for id: String in inv:
		var g := of(data, session_items, id)
		by[g] = int(by.get(g, 0)) + 1
	var out := {}
	for r: Dictionary in rows(data):
		if by.has(str(r["id"])):
			out[str(r["id"])] = by[str(r["id"])]
	return out


## The ids of `inv` to show: of `group` (ALL — every one) whose name holds `find`, sorted by `sort` (a key of `sorts`);
## `reverse` turns the order round. Ties go by the name.
static func view(data: Dictionary, session_items: Dictionary, inv: Dictionary, group := ALL, sort := TYPE, find := "", reverse := false) -> Array[String]:
	var items: Dictionary = data["items"]
	var order := {}
	for i in rows(data).size():
		order[str(rows(data)[i]["id"])] = i
	var rarities: Array = ItemRules.cfg(data)["rarity_order"]
	var keys := inv.keys()
	var rec := {}
	for i in keys.size():
		var id := str(keys[i])
		var g := of(data, session_items, id)
		var nm := ItemRules.display_name(items, session_items, id)
		if (group != ALL and g != group) or (not find.strip_edges().is_empty() and nm.findn(find.strip_edges()) < 0):
			continue
		var qty := int(inv[id])
		var key: float
		match sort:
			"weight":
				key = -weight(data, session_items, id, qty)
			"value":
				key = -float(value(data, session_items, id, qty))
			"rarity":
				key = -float(rarities.find(str(ItemRules.def_of(items, session_items, id).get("rarity", "common"))))
			"new":
				key = -float(i)
			"name":
				key = 0.0
			_:
				key = float(order.get(g, 0))
		rec[id] = [key, nm.to_lower()]
	var out: Array[String] = []
	out.assign(rec.keys())
	out.sort_custom(func(a: String, b: String) -> bool:
		var x: Array = rec[a]
		var y: Array = rec[b]
		if x[0] != y[0]:
			return x[0] < y[0]
		return str(x[1]) < str(y[1]) if x[1] != y[1] else a < b)
	if reverse:
		out.reverse()
	return out
