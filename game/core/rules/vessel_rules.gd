class_name VesselRules
extends RefCounted
## Vessels of water (v0.7.34.6, the author's review: a skin could not be filled by words, a flask held nothing). A thing
## of rules.needs.water.vessels holds its own pints of water on its copy (Thing: {pints, foul}); a plain copy is empty. A
## new hero's vessels start full.


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"]["needs"]["water"]


## Pints a thing holds; 0 — not a vessel.
static func holds(data: Dictionary, id: String) -> float:
	return float(cfg(data).get("vessels", {}).get(id, {}).get("pints", 0.0))


## The carried vessels, one per copy: [{id, i, pints, cap, foul}].
static func carried(c: Dictionary, data: Dictionary) -> Array[Dictionary]:
	_pour(c, data)
	var out: Array[Dictionary] = []
	for id: String in c.get("inventory", {}):
		var cap := holds(data, id)
		if cap <= 0.0:
			continue
		var list := Thing.states(c, id)
		for i in int(c["inventory"][id]):
			var v: Dictionary = list[i] if i < list.size() else {}
			out.append({"id": id, "i": i, "pints": minf(float(v.get("pints", 0.0)), cap), "cap": cap, "foul": bool(v.get("foul", false))})
	return out


static func pints(c: Dictionary, data: Dictionary) -> float:
	return carried(c, data).reduce(func(a: float, v: Dictionary) -> float: return a + float(v["pints"]), 0.0)


static func room(c: Dictionary, data: Dictionary, only := "") -> float:
	return carried(c, data).filter(func(v: Dictionary) -> bool: return only.is_empty() or v["id"] == only) \
		.reduce(func(a: float, v: Dictionary) -> float: return a + float(v["cap"]) - float(v["pints"]), 0.0)


## Pounds the water adds, less what the catalog counts in a vessel sold full (the waterskin's 5 lb).
static func extra_weight(c: Dictionary, data: Dictionary, session_items: Dictionary = {}) -> float:
	var lb := float(cfg(data).get("lb_per_pint", 1.0))
	var total := 0.0
	for v: Dictionary in carried(c, data):
		total += float(v["pints"]) * lb
		var spec: Dictionary = cfg(data)["vessels"][v["id"]]
		if spec.has("weight"):
			total += float(spec["weight"]) - float(ItemRules.def_of(data["items"], session_items, v["id"]).get("weight", 0))
	return total


## Vessels that water from here would change: not full, or foul at a clean source (poured out and drawn anew).
static func to_fill(c: Dictionary, data: Dictionary, foul: bool, only := "") -> Array[Dictionary]:
	return carried(c, data).filter(func(v: Dictionary) -> bool:
		return (only.is_empty() or v["id"] == only) and (float(v["pints"]) < float(v["cap"]) or bool(v["foul"]) and not foul))


## Fills the vessels (only that id, if given) from the water here: what they held takes the source's kind.
static func fill(c: Dictionary, data: Dictionary, foul: bool, only := "") -> void:
	for v: Dictionary in to_fill(c, data, foul, only):
		_put(c, v, float(v["cap"]), foul)


## Foul water in the vessels turns clean (Purify Food and Drink, v0.8.4.26.2). Lines.
static func clean(c: Dictionary, data: Dictionary) -> Array[String]:
	var n := 0
	for v: Dictionary in carried(c, data):
		if bool(v["foul"]):
			_put(c, v, float(v["pints"]), false)
			n += 1
	return ["вода очищена: сосудов %d" % n] if n > 0 else [] as Array[String]


## Takes up to `want` pints, the least full first (stacks empty one by one). {pints, foul}.
static func take(c: Dictionary, data: Dictionary, want: float) -> Dictionary:
	var list := carried(c, data).filter(func(v: Dictionary) -> bool: return float(v["pints"]) > 0.0)
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["pints"]) < float(b["pints"]))
	var got := 0.0
	var foul := false
	for v: Dictionary in list:
		if got >= want:
			break
		var t := minf(want - got, float(v["pints"]))
		got += t
		foul = foul or bool(v["foul"])
		_put(c, v, float(v["pints"]) - t, bool(v["foul"]))
	return {"pints": got, "foul": foul}


## «Бурдюк — вода 3/4 пинты» per vessel, for the sheet and the panel.
static func lines(c: Dictionary, data: Dictionary, session_items: Dictionary = {}, only := "") -> Array[String]:
	var out: Array[String] = []
	for v: Dictionary in carried(c, data):
		if not only.is_empty() and v["id"] != only:
			continue
		var what := "пусто" if float(v["pints"]) <= 0.0 else ("гнилая вода" if bool(v["foul"]) else "вода")
		out.append("%s — %s %s/%s пинт" % [ItemRules.display_name(data["items"], session_items, v["id"]), what, num(v["pints"]), num(v["cap"])])
	return out


## «вода 3/4, пусто» for the copies of one vessel; "" — not a vessel.
static func summary(c: Dictionary, data: Dictionary, id: String) -> String:
	var parts: Array = carried(c, data).filter(func(v: Dictionary) -> bool: return v["id"] == id).map(func(v: Dictionary) -> String:
		return "пусто" if float(v["pints"]) <= 0.0 else "%s %s/%s" % ["гнилая вода" if bool(v["foul"]) else "вода", num(v["pints"]), num(v["cap"])])
	return ", ".join(parts)


static func num(x: float) -> String:
	return str(int(x)) if is_equal_approx(x, roundf(x)) else "%.1f" % x


static func _put(c: Dictionary, v: Dictionary, p: float, foul: bool) -> void:
	var st := Thing.nth(c, str(v["id"]), int(v["i"]))
	st["pints"] = maxf(p, 0.0)
	st["foul"] = foul and p > 0.0


## The hero's vessels the first time they are looked at: full.
static func _pour(c: Dictionary, data: Dictionary) -> void:
	if bool(c.get("poured", false)):
		return
	c["poured"] = true
	for id: String in c.get("inventory", {}):
		var cap := holds(data, id)
		for i in int(c["inventory"][id]) if cap > 0.0 else 0:
			Thing.nth(c, id, i)["pints"] = cap


## Every vessel empty.
static func drain(c: Dictionary) -> void:
	c["poured"] = true
	for id: String in c.get("copies", {}).keys():
		for st: Dictionary in Thing.states(c, id):
			st.erase("pints")
			st.erase("foul")
