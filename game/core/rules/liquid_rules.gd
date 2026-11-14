class_name LiquidRules
extends RefCounted
## Liquids (v0.8.4.28, roadmap «Жидкость»; the vessels of water since v0.7.34.6). A liquid is a row of rules.liquids.kinds:
## water, foul water, ale, wine, milk, oil, alchemist's fire, acid, holy water, poison. A vessel (a row of `vessels`) holds
## one liquid on its copy (Thing: {liquid, pints}); a plain copy is empty. A ready thing of the catalog is a vessel with its
## liquid — the row's `item` in its `vessel` (oil in a flask, ale in a cup): poured out or drunk it leaves its vessel, and
## that vessel filled to the brim with that liquid is the thing again. Anybody pours and drinks alike: `c` is a holder in
## the hero's form (Sheet.things), `who` the one who drinks. A holder's vessels marked `full` start full of that liquid.
## v0.8.4.28.3: a liquid that `needs` a tool is poured only by one proficient with it and carrying it; a vessel takes only
## the liquids of its `only` (a lamp only oil); a light of `burns_hours` lights the way only with that in it and burns it.

const WATER := "water"
const WET := "wet"  ## the status water lays on a creature (v0.8.4.43.59)
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
	if id.is_empty():
		return {}
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
			out.append({"id": id, "i": i, "liquid": str(v.get("liquid", WATER)) if p > 0.0 else "", "pints": p, "cap": cap, "ready": false,
				"only": cfg(data)["vessels"].get(id, {}).get("only", [])})
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


## A thing of this room `lid` is drawn from (a barrel of wine, a vat of oil — the furnishing's `source`); {} — none.
static func source_of(s: GameSession, lid: String) -> Dictionary:
	for p: Dictionary in PropRules.room_props(s, s.room_id):
		if str(p.get("source", "")) == lid:
			return p
	return {}


## The vessels `lid` drawn from a source would go into (only that id): taking it, empty or of it, not full.
static func to_draw(c: Dictionary, data: Dictionary, lid: String, only := "") -> Array[Dictionary]:
	return carried(c, data).filter(func(v: Dictionary) -> bool:
		return not bool(v["ready"]) and takes(v, lid) and (only.is_empty() or v["id"] == only) and float(v["pints"]) < float(v["cap"]) \
			and (float(v["pints"]) <= 0.0 or v["liquid"] == lid))


## Fills those vessels with `lid` to the brim; one filled as a ready thing's vessel becomes that thing. Lines.
static func draw(c: Dictionary, data: Dictionary, lid: String, only := "", session_items: Dictionary = {}) -> Array[String]:
	var list := to_draw(c, data, lid, only)
	list.reverse()  # a vessel that becomes a thing leaves its stack: the later copies first
	var out: Array[String] = []
	for v: Dictionary in list:
		_put(c, v, float(v["cap"]), lid)
		out.append("%s: %s %s пинт" % [_label(data, session_items, v), name_of(data, lid), num(v["cap"])])
		_brim(c, data, v)
	return out


# --- the master's `fill` (0.70.0; v0.8.4.28.3: any liquid, draw, pour out, splash) ----------------------------


## The master's `fill`: `action` draw (default) — `liquid` (water by default) from a source here into the vessels
## (`item_id` — one kind); pour_out — the vessel `item_id` poured out; splash — its liquid on a thing of the room
## (`prop_id`) or on the hero. {plan, summary} or {reason}.
static func plan_fill(s: GameSession, data: Dictionary, e: Dictionary) -> Dictionary:
	var c := s.character
	var only := str(e.get("item_id", "")) if e.get("item_id") != null else ""
	var lid := str(e.get("liquid", "")) if e.get("liquid") != null else ""
	var action := str(e.get("action", "draw")) if e.get("action") != null else "draw"
	if not lid.is_empty() and kind(data, lid).is_empty():
		return {"reason": "нет такой жидкости: %s; есть %s" % [lid, ", ".join(cfg(data)["kinds"].keys())]}
	if action != "draw":
		var v := first(c, data, only)
		if only.is_empty() or v.is_empty():
			return {"reason": "у героя нет сосуда %s — item_id сосуда героя" % only}
		if float(v["pints"]) <= 0.0:
			return {"reason": "%s пуст" % _label(data, s.items, v)}
		if action == "pour_out":
			return {"plan": {"action": action, "key": key_of(v)}, "summary": "Вылить: %s" % line(data, s.items, v)}
		if (kind(data, str(v["liquid"])).get("coat", {}) as Dictionary).is_empty():
			return {"reason": "%s ничем не ложится на облитое" % name_of(data, str(v["liquid"]))}
		var prop := str(e.get("prop_id", "")) if e.get("prop_id") != null else ""
		var p := PropRules.find(s, s.room_id, prop) if not prop.is_empty() else {}
		if not prop.is_empty() and p.is_empty():
			return {"reason": "в комнате нет вещи %s" % prop}
		return {"plan": {"action": action, "key": key_of(v), "prop": prop, "room": s.room_id},
			"summary": "Облить %s: %s" % ["героя" if prop.is_empty() else str(p.get("name", prop)), name_of(data, str(v["liquid"]))]}
	if lid.is_empty() or lid in [WATER, FOUL]:
		var why := NeedRules.can_fill(s, data, only)
		if not why.is_empty():
			return {"reason": {"NEED_NO_SKIN": "у героя нет такой ёмкости (бурдюк, фляга, кувшин, ведро)", "NEED_NO_SOURCE":
				"здесь нет воды: ни тега комнаты, ни вещи-источника (колодец, ручей, река — вещь обстановки с source)",
				"NEED_SKIN_FULL": "ёмкости уже полны"}.get(why, why)}
		return {"plan": {"action": action, "liquid": "", "only": only}, "summary": "Набрать воды: %s" % ", ".join(to_fill(c, data, NeedRules.foul_here(s, data), only)
			.map(func(v: Dictionary) -> String: return ItemRules.display_name(data["items"], s.items, v["id"])))}
	var src := source_of(s, lid)
	if src.is_empty():
		return {"reason": "здесь неоткуда набрать: %s — нет вещи обстановки с source %s" % [name_of(data, lid), lid]}
	var owner := str(src.get("owner", ""))
	if not owner.is_empty():
		return {"reason": "%s — чьё-то (%s): купить у хозяина или взять с его позволения" % [str(src.get("name", "")), WorldView.name_of(data, owner)]}
	if not needs_why(c, data, lid).is_empty():
		return {"reason": "переливать %s может только тот, кто владеет и при себе имеет: %s" % [name_of(data, lid), BackgroundRules.tool_name(data, needs(data, lid))]}
	var list := to_draw(c, data, lid, only)
	if list.is_empty():
		return {"reason": "у героя нет сосуда, куда войдёт %s (пустого или с тем же, не полного)" % name_of(data, lid)}
	return {"plan": {"action": action, "liquid": lid, "only": only}, "summary": "Набрать: %s в %s" % [name_of(data, lid),
		", ".join(list.map(func(v: Dictionary) -> String: return _label(data, s.items, v)))]}


static func apply_fill(s: GameSession, data: Dictionary, plan: Dictionary) -> Array[String]:
	var c := s.character
	var lines: Array[String] = []
	match str(plan["action"]):
		"pour_out":
			return pour_out(c, data, by_key(c, data, str(plan["key"])), s.items)
		"splash":
			var v := by_key(c, data, str(plan["key"]))
			var lid := str(v["liquid"])
			if str(plan["prop"]).is_empty():
				lines.append_array(coat(s, data, c, lid, name_of(data, lid)))
			else:
				lines.append_array(ThingRules.splash(s, data, str(plan["room"]), str(plan["prop"]), lid))
			lines.append_array(pour_out(c, data, v, s.items))
			return lines
	if str(plan["liquid"]).is_empty():
		lines.append_array(NeedRules.fill(s, data, str(plan["only"])))
	else:
		lines.append("Набрано")
		lines.append_array(draw(c, data, str(plan["liquid"]), str(plan["only"]), s.items))
	lines.append_array(TimeRules.advance(s, data, int(NeedRules.cfg(data)["water"]["fill_minutes"])))
	return lines


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


## Why the holder `c` cannot pour `a` into `b`: "" or a localization key.
static func pour_why(c: Dictionary, data: Dictionary, a: Dictionary, b: Dictionary) -> String:
	if a.is_empty() or b.is_empty():
		return "LIQUID_GONE"
	if key_of(a) == key_of(b):
		return "LIQUID_SAME"
	if float(a["pints"]) <= 0.0:
		return "LIQUID_EMPTY"
	var skill := needs_why(c, data, str(a["liquid"]))
	if not skill.is_empty():
		return skill
	if not takes(b, str(a["liquid"])):
		return "LIQUID_NOT_FOR"
	if bool(b["ready"]) or float(b["pints"]) >= float(b["cap"]):
		return "LIQUID_FULL"
	if float(b["pints"]) > 0.0 and b["liquid"] != a["liquid"]:
		return "LIQUID_OTHER"
	return ""


## Why `c` may not pour `lid` from vessel to vessel (v0.8.4.28.3): its `needs` tool not mastered or not carried. "" — it may.
static func needs_why(c: Dictionary, data: Dictionary, lid: String) -> String:
	var tool := str(kind(data, lid).get("needs", ""))
	if tool.is_empty():
		return ""
	if not BackgroundRules.proficient(c, tool):
		return "LIQUID_NEEDS"
	return "" if BackgroundRules.has_tool(c, tool) else "LIQUID_NEEDS_KIT"


## The tool `lid` needs to be poured, "" — none.
static func needs(data: Dictionary, lid: String) -> String:
	return str(kind(data, lid).get("needs", ""))


## The vessel copy `b` takes `lid`: its `only`, if it has one.
static func takes(b: Dictionary, lid: String) -> bool:
	var only: Array = b.get("only", [])
	return only.is_empty() or only.has(lid)


## What `a` may be poured into: the other vessels with room for its liquid.
static func pour_targets(c: Dictionary, data: Dictionary, a: Dictionary) -> Array[Dictionary]:
	return carried(c, data).filter(func(b: Dictionary) -> bool: return pour_why(c, data, a, b).is_empty())


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
	lines.append_array(nourish(s, data, who, amount, d))
	lines.append_array(sickness(s, data, who, lid))
	if d.has("drunk"):
		lines.append_array(_hops(s, data, who, amount * float(d["drunk"])))
	return lines


## What `pints` of a drink of `d` (a liquid's `drink`) give the hero's needs (v0.8.4.29.4, one count for «Попить» and a drink):
## water by NeedRules.per_pint, food by the food points. Needs are the hero's alone. Lines.
static func nourish(s: GameSession, data: Dictionary, who: Dictionary, pints: float, d: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	if not Sheet.is_hero(who) or not NeedRules.on(s) or pints <= 0.0:
		return lines
	if d.has("water"):
		NeedRules.set_value(s, data, "water", NeedRules.value(s, data, "water") + pints * float(d["water"]) * NeedRules.per_pint(data))
		lines.append("Вода %d/100" % roundi(NeedRules.value(s, data, "water")))
	if d.has("food"):
		NeedRules.set_value(s, data, "food", NeedRules.value(s, data, "food") + pints * float(d["food"]) * float(NeedRules.cfg(data)["food"]["points"]))
		lines.append("Еда %d/100" % roundi(NeedRules.value(s, data, "food")))
	return lines


## The disease a liquid carries (its `drink.disease`, a row of rules.diseases: foul water) caught by who drinks it. Lines.
static func sickness(s: GameSession, data: Dictionary, who: Dictionary, lid: String) -> Array[String]:
	var dz: Dictionary = data["rules"].get("diseases", {}).get(str(kind(data, lid).get("drink", {}).get("disease", "")), {})
	if dz.is_empty():
		return []
	var what := name_of(data, lid)
	return DiseaseRules.expose(s, data, str(dz["disease"]), int(dz["dc"]), what.left(1).to_upper() + what.substr(1), str(who.get("id", Being.HERO)))  # «Гнилая вода»


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


# --- a light of oil, a used vial (v0.8.4.28.3) ----------------------------------------------------------


## A light that needs no fuel, or one of `burns_hours` with some of its liquid in a copy: it lights the way.
static func fuelled(c: Dictionary, data: Dictionary, id: String) -> bool:
	return not cfg(data)["vessels"].get(id, {}).has("burns_hours") or not _fuel(c, data, id).is_empty()


## The first copy of a light `id` with its fuel in it; {} — none.
static func _fuel(c: Dictionary, data: Dictionary, id: String) -> Dictionary:
	for v: Dictionary in carried(c, data):
		if v["id"] == id and float(v["pints"]) > 0.0 and takes(v, str(v["liquid"])):
			return v
	return {}


## The hook of time: the lights of oil on the hero's belt burn while they light an unlit place — the whole volume in
## `burns_hours`; not while it slept. Lines.
static func burn(s: GameSession, data: Dictionary) -> Array[String]:
	var c := s.character
	var now := TimeRules.abs_minute(s)
	var mins := now - int(c.get("lamps_at", now))
	c["lamps_at"] = now
	var lines: Array[String] = []
	if mins <= 0 or s.rested_at == now or not TimeRules.unlit(s, data):
		return lines
	var seen: Array[String] = []
	for id: String in ItemRules.belt(c, data, s.items):
		var spec: Dictionary = cfg(data)["vessels"].get(id, {})
		if seen.has(id):  # one lamp in two cells is one lamp
			continue
		seen.append(id)
		var v := _fuel(c, data, id) if spec.has("burns_hours") else {}
		if v.is_empty():
			continue
		var left := maxf(0.0, float(v["pints"]) - float(v["cap"]) * mins / (60.0 * float(spec["burns_hours"])))
		_put(c, v, left, str(v["liquid"]))
		if left <= 0.0:
			lines.append("%s: %s выгорело" % [_label(data, s.items, v), name_of(data, str(v["liquid"]))])
	return lines


## What a vial of a liquid with `blade` does used from the belt: its coat on the blade for a minute; {} — none.
static func blade_of(data: Dictionary, id: String) -> Dictionary:
	var r := ready(data, id)
	if r.is_empty() or not kind(data, str(r["liquid"])).has("blade"):
		return {}
	return {"coat": kind(data, str(r["liquid"]))["blade"], "duration": "minute"}


## One ready thing `id` used up (a vial of poison on a blade): its vessel is left, empty.
static func empty_one(c: Dictionary, data: Dictionary, id: String) -> void:
	var r := ready(data, id)
	_unready(c, data, {"id": id, "liquid": r["liquid"]}, 0.0)


# --- coated -----------------------------------------------------------------------------------------
# One status `coated` with its liquid on any holder: a fighter's sheet or record, a thing of a room (v0.8.4.28.2). It
# carries the keys of the liquid's `coat`: `douses`, `fire_plus`, `burns` with `put_out`.


## The live coat on `h`: the status, {} — none.
static func coat_on(s: GameSession, h: Dictionary) -> Dictionary:
	var t := ConditionRules.now(s)
	for e: Dictionary in ConditionRules.effects_of(h, "coated"):
		if not e.get("ends", {}).has("at") or int(e["ends"]["at"]) > t:
			return e
	return {}


## `h` is splashed with `lid`: its `coat` replaces what was on it; water puts out a fire. `who` — the creature it is on (a
## fighter, Sheet.HERO; {} — a thing): water makes it `wet` (`soak`, v0.8.4.43.59), a coat that burns sets it on fire — the status `burning` of its dice for a minute or until
## put out, its `put_out` the save at the end of its turns (v0.8.4.43.54, one status for every fire). Lines.
static func coat(s: GameSession, data: Dictionary, h: Dictionary, lid: String, cause: String, who: Dictionary = {}) -> Array[String]:
	var k: Dictionary = kind(data, lid).get("coat", {})
	if k.is_empty():
		return []
	var lines: Array[String] = []
	if bool(k.get("douses", false)) and not who.is_empty():  # water on a creature is the status `wet`, what was on it washed off (v0.8.4.43.59)
		ConditionRules.remove(h, "coated")
		return soak(s, data, who, cause)
	if bool(k.get("douses", false)) and put_out(s, data, h) and h.has("name"):  # a thing's fire
		lines.append("%s: пламя погасло" % h["name"])
	ConditionRules.remove(h, "coated")
	var e := {"condition": "coated", "liquid": lid, "ends": {"at": ConditionRules.now(s) + int(k["minutes"]) * ConditionRules.ROUNDS_PER_MINUTE} if k.has("minutes") else {},
		"source": {"kind": "liquid", "id": lid, "name": cause}}
	var fire := not who.is_empty() and k.has("burns")
	for key: String in ["douses", "fire_plus", "burns", "put_out", "catches"]:
		if k.has(key) and not (fire and key in ["burns", "put_out"]):
			e[key] = k[key]
	ConditionRules.add_effect(h, e)
	if fire:
		lines.append_array(alight(s, data, who, str(k["burns"]), k.get("put_out", {}), lid, cause))
	return lines


## A creature catches fire from a liquid (v0.8.4.43.62, one road): the status `burning` of `dice` at the start of its turns
## for a minute, `out` its save at the end of them (DEX 10 by default) — alchemist's fire splashed on it, oil on it that fire
## takes (`catches`). A wet one does not catch (its `immune`). `who` — a fighter, Sheet.HERO. Lines.
static func alight(s: GameSession, data: Dictionary, who: Dictionary, dice: String, out: Dictionary, lid: String, cause: String) -> Array[String]:
	return ConditionRules.impose(s, data, {"condition": "burning", "harm": {"dice": dice, "type": "fire", "when": "start"},
		"save": {"ability": str(out.get("ability", "dex")), "dc": int(out.get("dc", 10)), "tag": "", "repeat": true},
		"ends": {"at": ConditionRules.now(s) + ConditionRules.ROUNDS_PER_MINUTE}, "source": {"kind": "liquid", "id": lid, "name": cause}}, who)


## `lid` on the ground coats a creature that walks in or stands in it (a puddle of oil, v0.8.4.43.61): the coat, renewed while
## it stands there; told once, by the name the coat is shown by («облито маслом», ConditionRules.look_of). `who` — a fighter,
## Sheet.HERO; `cause` — the puddle's name. Lines.
static func smear(s: GameSession, data: Dictionary, who: Dictionary, lid: String, cause: String) -> Array[String]:
	var h := Sheet.holder(s, who)
	var was := str(coat_on(s, h).get("liquid", "")) == lid
	var lines := coat(s, data, h, lid, cause, who)
	var now := coat_on(s, h)
	if not was and str(now.get("liquid", "")) == lid:
		lines.push_front("%s: %s" % [h.get("name", ""), ConditionRules.name_of(data, ConditionRules.look_of(data, now))])
	return lines


## What fire adds to `h` now: oil on it (the coat goes with it).
static func fire_plus(s: GameSession, h: Dictionary) -> int:
	return int(coat_on(s, h).get("fire_plus", 0))


## Water on `h`: no fire takes it.
static func douses(s: GameSession, h: Dictionary) -> bool:
	return bool(coat_on(s, h).get("douses", false))


## Water on a creature, as in BG3 (v0.8.4.43.59): the status `wet` of its row — vulnerable to lightning and cold, resistant to fire,
## no fire takes it and its own goes out — for the row's rounds, renewed while it stands in water or under rain. `who` — a fighter,
## Sheet.HERO; `cause` — the water's name. Lines: the fire that went out, the first soaking (`say` — told).
static func soak(s: GameSession, data: Dictionary, who: Dictionary, cause: String, say := true) -> Array[String]:
	var h := Sheet.holder(s, who)
	var was := ConditionRules.has(h, WET)
	var lit := put_out(s, data, h)  # its fire, a status or a coat that burns
	var lines := ConditionRules.impose(s, data, {"condition": WET, "source": {"kind": "liquid", "id": WATER, "name": cause}}, who)
	if lit:
		lines.append("%s: пламя погасло — %s" % [h.get("name", ""), cause])
	elif say and not was and ConditionRules.has(h, WET):
		lines.append("%s промокает — %s" % [h.get("name", ""), cause])
	return lines


## The dice it burns with at the start of its turn, "" — it does not burn: a burning coat of a thing, a creature's `burning`.
static func burning(s: GameSession, data: Dictionary, h: Dictionary) -> String:
	if coat_on(s, h).has("burns"):
		return str(coat_on(s, h)["burns"])
	for e: Dictionary in ConditionRules.effects_of(h, "burning"):
		if not ConditionRules.harm_of(data, e).is_empty():
			return str(ConditionRules.harm_of(data, e)["dice"])
	return ""


## Water or a beaten flame on `h` (v0.8.4.43.54): every status whose row is put out by water (`out.douse`: burning — a thing's
## fire and a creature's) and a coat that burns go. True when something went out.
static func put_out(s: GameSession, data: Dictionary, h: Dictionary) -> bool:
	var out := false
	var table: Dictionary = data["rules"]["condition_effects"]
	for id: String in table:
		if table[id] is Dictionary and bool((table[id] as Dictionary).get("out", {}).get("douse", false)) and ConditionRules.has(h, id):
			ConditionRules.remove(h, id)
			out = true
	if coat_on(s, h).has("burns"):
		uncoat(h)
		out = true
	return out


## The coat goes (it burnt off, was put out, washed off).
static func uncoat(h: Dictionary) -> void:
	ConditionRules.remove(h, "coated")


## A thrown flask of a liquid: its liquid's `throw` with the liquid named and whether it spills on a square; {} — none.
static func throw_of(data: Dictionary, id: String) -> Dictionary:
	var r := ready(data, id)
	if r.is_empty() or not kind(data, str(r["liquid"])).has("throw"):
		return {}
	var k := kind(data, str(r["liquid"]))
	return (k["throw"] as Dictionary).merged({"liquid": r["liquid"], "spills": k.has("puddle") or (k["throw"] as Dictionary).has("area")})


## A thrown liquid's `effect` on every fighter in its area — a square of `area` cells around `at` (v0.8.4.28.5): each its
## save, as a monster's attack's effect (MonsterRules.apply_effect). Lines.
static func burst(s: GameSession, data: Dictionary, f: Dictionary, at: Vector2i, fx: Dictionary, name: String, lines: Array[String]) -> void:
	var n := maxi(1, int(fx.get("area", 1)))
	var cells := FightGrid.area(s, data, {"type": "cube", "size": n * int(FightGrid.cfg(data)["ft"])}, at, at, false)
	if not cells.has(at):
		cells.append(at)
	for id: String in s.combat.get("order", []):
		var t := CombatRules.fighter(s, id)
		if str(t.get("status")) == "active" and FightGrid.in_cells(t, cells):
			MonsterRules.apply_effect(s, data, f, t, {"name": name, "effect": fx["effect"]}, 0, lines)


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
	return takes(v, WATER) and (float(v["pints"]) <= 0.0 or bool(kind(data, str(v["liquid"])).get("quench", false)))


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


## A holder's vessels the first time they are looked at: those marked `full` hold that liquid (water, a lamp's oil).
static func _pour(c: Dictionary, data: Dictionary) -> void:
	if bool(c.get("poured", false)):
		return
	c["poured"] = true
	for id: String in c.get("inventory", {}):
		var full := str(cfg(data)["vessels"].get(id, {}).get("full", ""))
		if full.is_empty():
			continue
		for i in int(c["inventory"][id]):
			var st := Thing.nth(c, id, i)
			st["pints"] = holds(data, id)
			st["liquid"] = full


## Every vessel empty.
static func drain(c: Dictionary) -> void:
	c["poured"] = true
	for id: String in c.get("copies", {}).keys():
		for st: Dictionary in Thing.states(c, id):
			st.erase("pints")
			st.erase("liquid")
			st.erase("foul")
