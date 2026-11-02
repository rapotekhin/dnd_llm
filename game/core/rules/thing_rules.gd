class_name ThingRules
extends RefCounted
## The body of a thing (v0.7.65, the author: «у каждого объекта есть хиты, он разрушаем и может получать состояния»). One
## rule for a door, a chest, a table and a dropped sword. A thing's AC comes from its material, its HP from its size and
## frailty (DMG, rules.things); only the damage taken is kept, on the thing's state (`dmg`): a copy, a prop, a door. A
## status is the same record a character holds (ConditionRules): `on: ["thing"]` in its row says it lies on things. Fire
## takes what burns, what is not worn or held, spreads to what stands beside it and dies in the rain; a closed container
## shelters what is in it until it breaks, then its things fall out. A `body` (rules.things.bodies) says what a thing does
## on the map: the cells it takes, what it blocks, the cover it gives; the map of v0.8 reads it.


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"]["things"]


## What a thing is made of: its own word, its body's, or by its type.
static func material_id(data: Dictionary, d: Dictionary) -> String:
	if d.get("material") is String and not str(d["material"]).is_empty():
		return str(d["material"])
	if not str(d.get("made_of", "")).is_empty():
		return str(d["made_of"])
	return str(cfg(data)["by_type"].get(str(d.get("item_type", "")), "wood"))


static func material(data: Dictionary, d: Dictionary) -> Dictionary:
	return cfg(data)["materials"].get(material_id(data, d), {})


static func ac(data: Dictionary, d: Dictionary) -> int:
	return int(material(data, d).get("ac", 15))


## The row of its size by its weight.
static func size_row(data: Dictionary, d: Dictionary) -> Dictionary:
	var rows: Array = cfg(data)["sizes"]
	for r: Dictionary in rows:
		if float(d.get("weight", 0)) <= float(r["up_to"]):
			return r
	return rows[-1]


static func max_hp(data: Dictionary, d: Dictionary) -> int:
	if d.has("hp"):
		return int(d["hp"])
	return int(size_row(data, d)["fragile" if bool(material(data, d).get("fragile", false)) else "resilient"])


static func hp(data: Dictionary, st: Dictionary, d: Dictionary) -> int:
	return maxi(0, max_hp(data, d) - int(st.get("dmg", 0)))


## A blow: poison and the mind do nothing to a thing, a threshold stops what is less. {took, broke}.
static func hurt(data: Dictionary, st: Dictionary, d: Dictionary, amount: int, dtype: String = "") -> Dictionary:
	if (cfg(data)["immune"] as Array).has(dtype) or amount < int(material(data, d).get("threshold", 0)):
		return {"took": 0, "broke": false}
	st["dmg"] = int(st.get("dmg", 0)) + amount
	return {"took": amount, "broke": hp(data, st, d) <= 0}


## Whether a status lies on the thing and has not run out.
static func has(s: GameSession, st: Dictionary, id: String) -> bool:
	var t := ConditionRules.now(s)
	return ConditionRules.effects_of(st, id).any(func(e: Dictionary) -> bool:
		return not e.get("ends", {}).has("at") or int(e["ends"]["at"]) > t)


## A status on the thing for `minutes` (−1 — until removed), with its cause.
static func lay(s: GameSession, st: Dictionary, id: String, minutes: int, cause: String) -> void:
	var ends := {"at": ConditionRules.now(s) + minutes * ConditionRules.ROUNDS_PER_MINUTE} if minutes >= 0 else {}
	ConditionRules.add_effect(st, {"condition": id, "ends": ends, "at": TimeRules.abs_minute(s), "source": {"kind": "thing", "name": cause}})


static func lift(st: Dictionary, id: String) -> void:
	ConditionRules.remove(st, id)
	ConditionRules.tidy(st)


## Statuses a thing can hold: the rows with `on: ["thing"]`.
static func lies_on_things(data: Dictionary, id: String) -> bool:
	var row: Variant = data["rules"]["condition_effects"].get(id)
	return row is Dictionary and (row.get("on", []) as Array).has("thing")


static func burns(s: GameSession, data: Dictionary, st: Dictionary, d: Dictionary) -> bool:
	return bool(material(data, d).get("burns", false)) or has(s, st, "oiled")


## Sets the thing on fire: "" or why it will not catch.
static func ignite(s: GameSession, data: Dictionary, st: Dictionary, d: Dictionary, cause: String) -> String:
	if has(s, st, "wet"):
		return "мокрое не горит"
	if not burns(s, data, st, d):
		return "%s не горит" % str(material(data, d).get("name", "это"))
	if not has(s, st, "burning"):
		lay(s, st, "burning", int(cfg(data)["burn_minutes"]), cause)
	return ""


## Water on the thing: the fire goes out, the thing is wet for a while.
static func douse(s: GameSession, data: Dictionary, st: Dictionary) -> void:
	lift(st, "burning")
	lift(st, "oiled")
	lay(s, st, "wet", int(cfg(data)["wet_minutes"]), "вода")


## The numbers of a lock: Sleight of Hand to pick it, Athletics to force it.
static func lock_dcs(data: Dictionary, pick: int, d: Dictionary) -> Dictionary:
	return {"pick": pick, "force": pick + int(data["rules"]["containers"]["force_dc_plus"]) + int(material(data, d).get("force_plus", 0))}


## What a thing of the room is, for the rules: its item, its container kind and its body.
static func spec(data: Dictionary, s: GameSession, p: Dictionary) -> Dictionary:
	var d := {}
	if not str(p.get("item_id", "")).is_empty():
		d = ItemRules.def_of(data["items"], s.items, str(p["item_id"]))
	if p.has("body"):
		d.merge(body(data, p))
	return d


## The body of a thing of the room: {cells, blocks, cover, made_of}; {} — it stands in nobody's way.
static func body(data: Dictionary, p: Dictionary) -> Dictionary:
	return cfg(data)["bodies"].get(str(p.get("body", "")), {})


## A quest's thing is not broken while the quest needs it, unless the pack or the master says so.
static func guarded(s: GameSession, data: Dictionary, p: Dictionary) -> bool:
	var id := str(p.get("item_id", ""))
	return bool(p.get("quest", false)) or (not id.is_empty() and QuestRules.needs_item(s, data, id))


## The master harms a thing of the room by a deed: {prop_id, damage, damage_type, status, cause}. {plan, summary} or {reason}.
static func plan(s: GameSession, data: Dictionary, p: Dictionary, e: Dictionary) -> Dictionary:
	var cause := str(e.get("cause", "")).strip_edges() if e.get("cause") != null else ""
	if cause.length() < 4:
		return {"reason": "нужна cause — что с вещью сделали"}
	var d := spec(data, s, p)
	var status := str(e.get("status", "")) if e.get("status") != null else ""
	var amount := int(e.get("damage", 0)) if e.get("damage") != null else 0
	if amount > int(cfg(data)["master_damage"]):
		return {"reason": "урон по вещи — до %d за раз" % int(cfg(data)["master_damage"])}
	if guarded(s, data, p) and (amount > 0 or status == "burning"):
		return {"reason": "%s нужна заданию: она уцелеет, скажи об этом в истории" % p["name"]}
	if not status.is_empty():
		if not lies_on_things(data, status):
			return {"reason": "на вещь ложатся: %s" % ", ".join((data["rules"]["condition_effects"] as Dictionary).keys().filter(func(k: String) -> bool: return lies_on_things(data, k)))}
		if status == "burning" and not has(s, p, "burning"):
			var why := "мокрое не горит" if has(s, p, "wet") else ("" if burns(s, data, p, d) else "%s не горит" % str(material(data, d).get("name", "это")))
			if not why.is_empty():
				return {"reason": why}
	return {"plan": {"room": s.room_id, "prop": p["id"], "status": status, "damage": amount, "type": str(e.get("damage_type", "")) if e.get("damage_type") != null else "", "cause": cause},
		"summary": "%s: %s" % [p["name"], cause]}


## The plan applied: the thing burns, breaks and lets go of what is in it. Its owner, if here, takes it as a crime. Lines.
static func apply(s: GameSession, data: Dictionary, q: Dictionary) -> Array[String]:
	var p := PropRules.find(s, str(q["room"]), str(q["prop"]))
	if p.is_empty():
		return []
	var d := spec(data, s, p)
	var lines: Array[String] = []
	match str(q["status"]):
		"":
			pass
		"burning":
			ignite(s, data, p, d, str(q["cause"]))
		"wet":
			douse(s, data, p)
		var other:
			lay(s, p, str(other), int(cfg(data)["status_minutes"]), str(q["cause"]))
	if int(q["damage"]) > 0 and bool(hurt(data, p, d, int(q["damage"]), str(q["type"]))["broke"]):
		lines.append_array(ruin(s, data, str(q["room"]), p, "broken"))
	var owner := str(p.get("owner", ""))
	if WatchRules.sees_hero(s, data, owner):
		lines.append_array(TheftRules.react(s, data, owner))
	return lines


## The thing is broken or burnt: what was in it falls out. Lines.
static func ruin(s: GameSession, data: Dictionary, room: String, p: Dictionary, state: String) -> Array[String]:
	p["state"] = state
	p["locked"] = false
	var what: Array[String] = []
	var out: Array[String] = []
	var contents: Dictionary = p.get("contents", {})
	for id: String in contents.keys():
		var n := int(contents[id])
		var had := Thing.take(p, id, n)
		for i in n:
			ContainerRules.lay_down(s, data, room, id, had[i] if i < had.size() else {})
		what.append(ItemRules.display_name(data["items"], s.items, id))
	if not what.is_empty():
		out.append("Из %s выпадает: %s" % [p["name"], ", ".join(what)])
	return out


## Time passes: a fire ends in ash and may catch what stands beside it; rain puts it out. Lines for the hero's room.
static func tick(s: GameSession, data: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var t := ConditionRules.now(s)
	for k: String in s.ways:
		var st: Dictionary = s.ways[k]
		if _burnt(st, t, data) and not bool(st.get("broken", false)):
			st["broken"] = true
			st["burnt"] = true
			if s.room_id in k.split("|"):
				lines.append("Дверь прогорела насквозь — путь открыт")
	var loc := WeatherRules.here(s, data)
	var pouring := bool(WeatherRules.kind(data, loc).get("camp", {}).get("fire_out", false))
	for room: String in s.props:
		var list: Array = s.props[room]
		for p: Dictionary in list.duplicate():
			if not p.has("effects"):
				continue
			if pouring and has(s, p, "burning") and room == s.room_id and not SceneRules.indoor(s, data["world"], room):
				douse(s, data, p)
				lines.append("Дождь гасит огонь: %s" % p["name"])
				continue
			var fire: Array = ConditionRules.effects_of(p, "burning")
			if not fire.is_empty() and not bool(p.get("spread", false)) and TimeRules.abs_minute(s) - int(fire[0].get("at", 0)) >= int(cfg(data)["spread_minutes"]):
				p["spread"] = true
				_spread(s, data, list, p, str(fire[0].get("source", {}).get("name", "")))
			if _burnt(p, t, data):
				p.erase("spread")
				var said := ruin(s, data, room, p, "burned")
				if room == s.room_id:
					lines.append("%s сгорает дотла" % p["name"])
					lines.append_array(said)
	return lines


static func _spread(s: GameSession, data: Dictionary, list: Array, from: Dictionary, cause: String) -> void:
	for o: Dictionary in list:
		if o != from and not str(o.get("state", "")) in ["taken", "burned"] and not has(s, o, "wet"):
			ignite(s, data, o, spec(data, s, o), cause)


## What has run out leaves the thing; true when a fire ended.
static func _burnt(st: Dictionary, t: int, data: Dictionary) -> bool:
	var was := ConditionRules.effects_of(st, "burning").any(func(e: Dictionary) -> bool: return e.get("ends", {}).has("at") and int(e["ends"]["at"]) <= t)
	ConditionRules._run_out(st, data, t)
	ConditionRules.tidy(st)
	return was
