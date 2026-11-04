class_name LiquidRules
extends RefCounted
## Liquids (v0.8.4.28, roadmap «Жидкость»; the vessels of water since v0.7.34.6). A liquid is a row of rules.liquids.kinds:
## water, foul water, ale, wine, milk, oil, alchemist's fire, acid, holy water, poison. A vessel (a row of `vessels`) holds
## one liquid on its copy (Thing: {liquid, pints}); a plain copy is empty. A ready thing of the catalog is a vessel with its
## liquid — the row's `item` in its `vessel` (oil in a flask, ale in a cup): poured out or drunk it leaves its vessel, and
## that vessel filled to the brim with that liquid is the thing again. Anybody pours and drinks alike: `c` is a holder in
## the hero's form (Sheet.things), `who` the one who drinks. The hero's vessels marked `full` start full of water.

const WATER := "water"
const FOUL := "foul_water"


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"]["liquids"]


static func kind(data: Dictionary, lid: String) -> Dictionary:
	return cfg(data)["kinds"].get(lid, {})


static func name_of(data: Dictionary, lid: String) -> String:
	return str(kind(data, lid).get("name", lid))


## Pints a vessel holds: its row of `vessels`, else the thing's own `holds` (a pack's cask); 0 — not a vessel.
static func holds(data: Dictionary, id: String) -> float:
	return float(cfg(data)["vessels"].get(id, {}).get("pints", _def(data, id).get("holds", 0.0)))


## The liquid of a ready thing: {liquid, vessel, pints} — the liquid's own `item`, else the thing's `liquid` {kind, vessel,
## pints} (a cask of wine of the pack); {} — not one.
static func ready(data: Dictionary, id: String) -> Dictionary:
	for lid: String in cfg(data)["kinds"]:
		var k: Dictionary = cfg(data)["kinds"][lid]
		if str(k.get("item", "")) == id:
			return {"liquid": lid, "vessel": str(k["vessel"]), "pints": float(k["pints"])}
	var own: Variant = _def(data, id).get("liquid")
	if own is Dictionary and kind(data, str(own.get("kind", ""))).size() > 0:
		return {"liquid": str(own["kind"]), "vessel": str(own["vessel"]), "pints": float(own["pints"])}
	return {}


## A thing of the catalog or of the pack.
static func _def(data: Dictionary, id: String) -> Dictionary:
	return data["items"]["catalog"].get(id, data.get("world", {}).get("items", {}).get(id, {}))


## Every vessel and ready thing carried, one per copy: [{id, i, liquid, pints, cap, ready}]; an empty one has liquid "".
static func carried(c: Dictionary, data: Dictionary) -> Array[Dictionary]:
	_pour(c, data)
	var out: Array[Dictionary] = []
	for id: String in c.get("inventory", {}):
		var cap := holds(data, id)
		var r := ready(data, id)
		if cap <= 0.0 and r.is_empty():
			continue
		var list := Thing.states(c, id)
		for i in int(c["inventory"][id]):
			if not r.is_empty():
				out.append({"id": id, "i": i, "liquid": r["liquid"], "pints": r["pints"], "cap": r["pints"], "ready": true})
				continue
			var v: Dictionary = list[i] if i < list.size() else {}
			var p := minf(float(v.get("pints", 0.0)), cap)
			out.append({"id": id, "i": i, "liquid": str(v.get("liquid", WATER)) if p > 0.0 else "", "pints": p, "cap": cap, "ready": false})
	return out


## The first copy of `id` that holds something, else its first copy; {} — none.
static func first(c: Dictionary, data: Dictionary, id: String) -> Dictionary:
	var mine := carried(c, data).filter(func(v: Dictionary) -> bool: return v["id"] == id)
	for v: Dictionary in mine:
		if float(v["pints"]) > 0.0:
			return v
	return mine[0] if not mine.is_empty() else {}


## The copy named "id:i" (a window's key); {} — gone.
static func by_key(c: Dictionary, data: Dictionary, key: String) -> Dictionary:
	for v: Dictionary in carried(c, data):
		if key_of(v) == key:
			return v
	return {}


static func key_of(v: Dictionary) -> String:
	return "%s:%d" % [v["id"], int(v["i"])]


## Water that quenches thirst (water and foul water), in pints.
static func pints(c: Dictionary, data: Dictionary) -> float:
	return _quenching(c, data).reduce(func(a: float, v: Dictionary) -> float: return a + float(v["pints"]), 0.0)


## Room for water in the vessels that hold water or nothing.
static func room(c: Dictionary, data: Dictionary, only := "") -> float:
	return carried(c, data).filter(func(v: Dictionary) -> bool: return not bool(v["ready"]) and _watery(data, v) and (only.is_empty() or v["id"] == only)) \
		.reduce(func(a: float, v: Dictionary) -> float: return a + float(v["cap"]) - float(v["pints"]), 0.0)


## Pounds the liquids in the vessels add, less what the catalog counts in a vessel sold full (the waterskin's 5 lb).
static func extra_weight(c: Dictionary, data: Dictionary, session_items: Dictionary = {}) -> float:
	var total := 0.0
	for v: Dictionary in carried(c, data):
		if bool(v["ready"]):
			continue
		total += float(v["pints"]) * float(kind(data, str(v["liquid"])).get("lb_per_pint", cfg(data)["lb_per_pint"]))
		var spec: Dictionary = cfg(data)["vessels"].get(v["id"], {})
		if spec.has("weight"):
			total += float(spec["weight"]) - float(ItemRules.def_of(data["items"], session_items, v["id"]).get("weight", 0))
	return total


## Vessels water from here would change: holding water or nothing and not full, or foul at a clean source (poured out
## and drawn anew).
static func to_fill(c: Dictionary, data: Dictionary, foul: bool, only := "") -> Array[Dictionary]:
	return carried(c, data).filter(func(v: Dictionary) -> bool:
		return not bool(v["ready"]) and _watery(data, v) and (only.is_empty() or v["id"] == only) \
			and (float(v["pints"]) < float(v["cap"]) or v["liquid"] == FOUL and not foul))


## Fills the vessels (only that id, if given) from the water here: what they held takes the source's kind.
static func fill(c: Dictionary, data: Dictionary, foul: bool, only := "") -> void:
	for v: Dictionary in to_fill(c, data, foul, only):
		_put(c, v, float(v["cap"]), FOUL if foul else WATER)


## Foul water in the vessels turns clean (Purify Food and Drink, v0.8.4.26.2). Lines.
static func clean(c: Dictionary, data: Dictionary) -> Array[String]:
	var n := 0
	for v: Dictionary in carried(c, data):
		if v["liquid"] == FOUL:
			_put(c, v, float(v["pints"]), WATER)
			n += 1
	return ["вода очищена: сосудов %d" % n] if n > 0 else [] as Array[String]


## Takes up to `want` pints of water to quench thirst, the least full first. {pints, foul}.
static func take(c: Dictionary, data: Dictionary, want: float) -> Dictionary:
	var list := _quenching(c, data).filter(func(v: Dictionary) -> bool: return float(v["pints"]) > 0.0)
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["pints"]) < float(b["pints"]))
	var got := 0.0
	var foul := false
	for v: Dictionary in list:
		if got >= want:
			break
		var t := minf(want - got, float(v["pints"]))
		got += t
		foul = foul or v["liquid"] == FOUL
		_put(c, v, float(v["pints"]) - t, str(v["liquid"]))
	return {"pints": got, "foul": foul}


# --- pour, pour out, drink ----------------------------------------------------------------------------


## Why `a` cannot go into `b`: "" or a localization key.
static func pour_why(a: Dictionary, b: Dictionary) -> String:
	if a.is_empty() or b.is_empty():
		return "LIQUID_GONE"
	if key_of(a) == key_of(b):
		return "LIQUID_SAME"
	if float(a["pints"]) <= 0.0:
		return "LIQUID_EMPTY"
	if bool(b["ready"]) or float(b["pints"]) >= float(b["cap"]):
		return "LIQUID_FULL"
	if float(b["pints"]) > 0.0 and b["liquid"] != a["liquid"]:
		return "LIQUID_OTHER"
	return ""


## What `a` may be poured into: the other vessels with room for its liquid.
static func pour_targets(c: Dictionary, data: Dictionary, a: Dictionary) -> Array[Dictionary]:
	return carried(c, data).filter(func(b: Dictionary) -> bool: return pour_why(a, b).is_empty())


## Pours `a` into `b` as much as goes in. Lines.
static func pour(c: Dictionary, data: Dictionary, a: Dictionary, b: Dictionary, session_items: Dictionary = {}) -> Array[String]:
	var amount := minf(float(a["pints"]), float(b["cap"]) - float(b["pints"]))
	var lid := str(a["liquid"])
	_put(c, b, float(b["pints"]) + amount, lid)  # copies by index first: the stacks change only after
	if not bool(a["ready"]):
		_put(c, a, float(a["pints"]) - amount, lid)
	_brim(c, data, b)
	if bool(a["ready"]):
		_unready(c, data, a, float(a["pints"]) - amount)
	return ["%s: %s %s пинт → %s" % [_label(data, session_items, a), name_of(data, lid), num(amount), _label(data, session_items, b)]]


## Pours `a` out on the ground. Lines.
static func pour_out(c: Dictionary, data: Dictionary, a: Dictionary, session_items: Dictionary = {}) -> Array[String]:
	if bool(a["ready"]):
		_unready(c, data, a, 0.0)
	else:
		_put(c, a, 0.0, "")
	return ["%s: %s вылито" % [_label(data, session_items, a), name_of(data, str(a["liquid"]))]]


## Why `who` cannot drink from `a`: "" or a localization key.
static func drink_why(data: Dictionary, a: Dictionary) -> String:
	if a.is_empty():
		return "LIQUID_GONE"
	if float(a["pints"]) <= 0.0:
		return "LIQUID_EMPTY"
	if not kind(data, str(a["liquid"])).has("drink"):
		return "LIQUID_NOT_DRINK"
	return ""


## `who` drinks a portion from `a` (its things are `c`): water and food to the hero's needs, a disease of foul water,
## the hops of ale and wine. Lines.
static func drink(s: GameSession, data: Dictionary, who: Dictionary, a: Dictionary) -> Array[String]:
	var c := Sheet.things(s, data, who)
	var lid := str(a["liquid"])
	var d: Dictionary = kind(data, lid)["drink"]
	var amount := minf(float(cfg(data)["portion"]), float(a["pints"]))
	if bool(a["ready"]):
		_unready(c, data, a, float(a["pints"]) - amount)
	else:
		_put(c, a, float(a["pints"]) - amount, lid)
	var lines: Array[String] = ["%s: выпито — %s %s пинт" % [str(Sheet.holder(s, who).get("name", "")), name_of(data, lid), num(amount)]]
	if Sheet.is_hero(who) and NeedRules.on(s):  # needs are the hero's alone
		var w: Dictionary = NeedRules.cfg(data)["water"]
		if d.has("water"):
			NeedRules.set_value(s, data, "water", NeedRules.value(s, data, "water") + amount * float(d["water"]) * float(w["drink"]) / float(w.get("drink_pints", 2)))
			lines.append("Вода %d/100" % roundi(NeedRules.value(s, data, "water")))
		if d.has("food"):
			NeedRules.set_value(s, data, "food", NeedRules.value(s, data, "food") + amount * float(d["food"]) * float(NeedRules.cfg(data)["food"]["points"]))
			lines.append("Еда %d/100" % roundi(NeedRules.value(s, data, "food")))
	if d.has("disease"):
		var dz: Dictionary = data["rules"].get("diseases", {}).get(str(d["disease"]), {})
		if not dz.is_empty():
			lines.append_array(DiseaseRules.expose(s, data, str(dz["disease"]), int(dz["dc"]), name_of(data, lid).capitalize(), str(who.get("id", Being.HERO))))
	if d.has("drunk"):
		lines.append_array(_hops(s, data, who, amount * float(d["drunk"])))
	return lines


## Ale and wine (the author, 2026-11-04): hops in points, each sobering in `minutes_per_point`; past 2 + its CON
## modifier the drinker is drunk — poisoned until it sobers to that again. One status of hops keeps the time.
static func _hops(s: GameSession, data: Dictionary, who: Dictionary, pts: float) -> Array[String]:
	var h := Sheet.holder(s, who)
	var dr: Dictionary = cfg(data)["drunk"]
	var per := float(dr["minutes_per_point"]) * ConditionRules.ROUNDS_PER_MINUTE
	var e: Dictionary = {}
	for x: Dictionary in ConditionRules.effects(h):
		if x.has("hops"):
			e = x
	var n := (ConditionRules.rounds_left(s, e) / per if not e.is_empty() else 0.0) + pts
	var now := ConditionRules.now(s)
	if e.is_empty():
		ConditionRules.add_effect(h, {"condition": "", "hops": n, "ends": {"at": now + roundi(n * per)}, "source": {"kind": "engine", "name": str(dr["hops"])}})
	else:
		e["hops"] = n
		e["ends"] = {"at": now + roundi(n * per)}
	var limit := float(dr["base"]) + floorf((Sheet.ability(s, data, who, str(dr["ability"])) - 10) / 2.0)
	if n <= limit:
		return []
	var at := now + roundi((n - limit) * per)
	for x: Dictionary in ConditionRules.effects(h):
		if bool(x.get("drunk", false)):
			x["ends"] = {"at": at}
			return []
	var lines := ConditionRules.impose(s, data, {"condition": str(dr["condition"]), "drunk": true, "ends": {"at": at}, "source": {"kind": "engine", "name": str(dr["name"])}}, who)
	if bool(ConditionRules.effects(h).any(func(x: Dictionary) -> bool: return bool(x.get("drunk", false)))):
		lines.append("%s пьянеет" % str(Sheet.holder(s, who).get("name", "")))
	return lines


# --- text -----------------------------------------------------------------------------------------


## «Бурдюк — вода 3/4 пинты» per vessel, for the sheet and the panel.
static func lines(c: Dictionary, data: Dictionary, session_items: Dictionary = {}, only := "") -> Array[String]:
	var out: Array[String] = []
	for v: Dictionary in carried(c, data):
		if bool(v["ready"]) or not only.is_empty() and v["id"] != only:
			continue
		out.append(line(data, session_items, v))
	return out


## «Бурдюк — вода 3/4 пинт» of one copy; a ready thing is named alone.
static func line(data: Dictionary, session_items: Dictionary, v: Dictionary) -> String:
	if bool(v["ready"]):
		return _label(data, session_items, v)
	return "%s — %s %s/%s пинт" % [_label(data, session_items, v), _what(data, v), num(v["pints"]), num(v["cap"])]


## «вода 3/4, пусто» for the copies of one vessel; "" — not a vessel (a ready thing names its liquid itself).
static func summary(c: Dictionary, data: Dictionary, id: String) -> String:
	var parts: Array = carried(c, data).filter(func(v: Dictionary) -> bool: return v["id"] == id and not bool(v["ready"])).map(func(v: Dictionary) -> String:
		return "пусто" if float(v["pints"]) <= 0.0 else "%s %s/%s" % [_what(data, v), num(v["pints"]), num(v["cap"])])
	return ", ".join(parts)


static func num(x: float) -> String:
	return str(int(x)) if is_equal_approx(x, roundf(x)) else "%.2f" % x if not is_equal_approx(x * 10.0, roundf(x * 10.0)) else "%.1f" % x


static func _what(data: Dictionary, v: Dictionary) -> String:
	return "пусто" if float(v["pints"]) <= 0.0 else name_of(data, str(v["liquid"]))


static func _label(data: Dictionary, session_items: Dictionary, v: Dictionary) -> String:
	return ItemRules.display_name(data["items"], session_items, str(v["id"]))


# --- the copies ------------------------------------------------------------------------------------


static func _watery(data: Dictionary, v: Dictionary) -> bool:
	return float(v["pints"]) <= 0.0 or bool(kind(data, str(v["liquid"])).get("quench", false))


static func _quenching(c: Dictionary, data: Dictionary) -> Array[Dictionary]:
	return carried(c, data).filter(func(v: Dictionary) -> bool: return float(v["pints"]) > 0.0 and bool(kind(data, str(v["liquid"])).get("quench", false)))


## A vessel copy holds `p` pints of `lid` (nothing at 0).
static func _put(c: Dictionary, v: Dictionary, p: float, lid: String) -> void:
	var st := Thing.nth(c, str(v["id"]), int(v["i"]))
	st.erase("foul")
	if p <= 0.0:
		st.erase("pints")
		st.erase("liquid")
		return
	st["pints"] = p
	st["liquid"] = lid


## A vessel filled to the brim with a liquid whose ready thing is in it becomes that thing.
static func _brim(c: Dictionary, data: Dictionary, b: Dictionary) -> void:
	var st: Dictionary = Thing.nth(c, str(b["id"]), int(b["i"]))
	var k := kind(data, str(st.get("liquid", "")))
	if k.is_empty() or str(k.get("vessel", "")) != str(b["id"]) or float(st.get("pints", 0.0)) < float(k.get("pints", INF)) \
			or not is_equal_approx(float(b["cap"]), float(k["pints"])):
		return
	var keep := st.duplicate()
	keep.erase("pints")
	keep.erase("liquid")
	Thing.drop_at(c, str(b["id"]), int(b["i"]))
	Thing.add(c, str(k["item"]), 1, [keep])


## One ready thing leaves its vessel with `left` pints of its liquid in it; what set the copy apart goes along.
static func _unready(c: Dictionary, data: Dictionary, a: Dictionary, left: float) -> void:
	var had := Thing.take(c, str(a["id"]), 1)
	var st: Dictionary = (had[0] as Dictionary).duplicate() if not had.is_empty() else {}
	if left > 0.0:
		st["liquid"] = str(a["liquid"])
		st["pints"] = left
	Thing.add(c, str(ready(data, str(a["id"]))["vessel"]), 1, [st])


## The hero's vessels the first time they are looked at: those marked `full` hold water.
static func _pour(c: Dictionary, data: Dictionary) -> void:
	if bool(c.get("poured", false)):
		return
	c["poured"] = true
	for id: String in c.get("inventory", {}):
		if not bool(cfg(data)["vessels"].get(id, {}).get("full", false)):
			continue
		for i in int(c["inventory"][id]):
			var st := Thing.nth(c, id, i)
			st["pints"] = holds(data, id)
			st["liquid"] = WATER


## Every vessel empty.
static func drain(c: Dictionary) -> void:
	c["poured"] = true
	for id: String in c.get("copies", {}).keys():
		for st: Dictionary in Thing.states(c, id):
			st.erase("pints")
			st.erase("liquid")
			st.erase("foul")
