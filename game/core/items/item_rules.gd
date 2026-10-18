class_name ItemRules
extends RefCounted
## Item catalog queries and the power check of master-made items (ADR-0008 §6): every property costs rarity
## points, the sum sets the rarity, the rarity is limited by character level and caps the value.


## Definition of an item: catalog first, then items generated in this session. {} if unknown.
static func def_of(items_data: Dictionary, session_items: Dictionary, id: String) -> Dictionary:
	if items_data["catalog"].has(id):
		var d: Dictionary = items_data["catalog"][id].duplicate()
		d["rarity"] = str(d.get("rarity", "common"))
		return d
	return session_items.get(id, {})


static func display_name(items_data: Dictionary, session_items: Dictionary, id: String) -> String:
	return str(def_of(items_data, session_items, id).get("name", id))


## Catalog + session items matching a free-text query (Russian name or id), a base id and required properties.
static func find(items_data: Dictionary, session_items: Dictionary, query: String, base: String, properties: Array) -> Array[Dictionary]:
	var q := query.to_lower().strip_edges()
	var out: Array[Dictionary] = []
	var pools: Array[Dictionary] = [items_data["catalog"], session_items]
	for pool: Dictionary in pools:
		for id: String in pool:
			var d: Dictionary = pool[id]
			var props: Array = d.get("properties", [])
			var name_l := str(d.get("name", "")).to_lower()
			var hit := q.is_empty() or q in name_l or q in id or q == str(d.get("item_type", ""))
			if not base.is_empty() and (id == base or str(d.get("base", "")) == base):
				hit = true
			if not hit or not properties.all(func(p: Variant) -> bool: return props.has(p)):
				continue
			out.append({"item_id": id, "name": d.get("name", id), "item_type": d.get("item_type", ""),
				"rarity": d.get("rarity", "common"), "value_cp": int(d.get("value_cp", 0)), "properties": props,
				"source": "catalog" if pool == items_data["catalog"] else "session"})
	return out


static func rarity_for_points(items_data: Dictionary, points: int) -> String:
	var rarity := "common"
	for step: Array in items_data["rarity_by_points"]:
		if points >= int(step[0]):
			rarity = str(step[1])
	return rarity


## Deterministic id, so the same item made twice (or taken from the backend library) keeps one id.
static func generated_id(item: Dictionary) -> String:
	var props: Array = item.get("properties", []).duplicate()
	props.sort()
	return "gen_" + ("%s|%s|%s" % [item.get("name", ""), item.get("base", ""), ",".join(props)]).md5_text().left(10)


## {"ok": true, "def": normalized definition} or {"ok": false, "reason": text for the master}.
static func check_generated(items_data: Dictionary, item: Dictionary, level: int) -> Dictionary:
	var costs: Dictionary = items_data["properties"]
	var points := 0
	for p: Variant in item.get("properties", []):
		if not costs.has(p):
			return {"ok": false, "reason": "свойство %s движку неизвестно" % p}
		points += int(costs[p])
	var base := str(item.get("base", ""))
	if not base.is_empty() and not items_data["catalog"].has(base):
		return {"ok": false, "reason": "базового предмета %s нет в каталоге" % base}
	var rarity := rarity_for_points(items_data, points)
	if level < int(items_data["rarity_min_level"][rarity]):
		return {"ok": false, "reason": "предмет редкости %s недоступен на %d уровне" % [rarity, level]}
	var value := mini(int(item.get("value_cp", 0)), int(items_data["rarity_max_value_cp"][rarity]))
	var def := {
		"name": str(item.get("name", "")), "item_type": str(item.get("item_type", "gear")), "base": base,
		"rarity": rarity, "value_cp": value, "properties": item.get("properties", []),
		"description": str(item.get("description", "")), "generated": true,
	}
	if def["name"].is_empty():
		return {"ok": false, "reason": "у предмета нет названия"}
	return {"ok": true, "def": def}
