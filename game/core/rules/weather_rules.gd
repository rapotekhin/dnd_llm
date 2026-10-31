class_name WeatherRules
extends RefCounted
## Weather and seasons (roadmap v0.7.46). Weather is a location's state by days: the pack's `weather.terrain`
## {terrain: {season: {kind: weight}}} by the location's terrain and the calendar's season; a location `indoor` or
## without a table has none. Each new day every location rolls (seeded by the day and the location, not the session's
## rng), yesterday's kind stays with rules.weather.stay_pct. The state lives in `generated.weather` {day, by_loc,
## magic {loc: {kind, until, cause}}, flags, heat_day}. Consequences are the kind's data in rules.weather.kinds:
## `obscure` — disadvantage on ranged attacks and Perception, the watchers' passive Perception −`passive`;
## `travel_mult` — a step into another location takes longer; `camp.fire_out` — a camp under the open sky soaks
## (a CON save, a failure — half the HP in the morning and no hit dice back); `exposure` — cold or heat: a night in a
## camp without its guards (shelter, warm things, a fire, water, a resistance) is a CON save against a level of
## exhaustion by 5e, heat also once a day on the way by day; `hunt_pct` / `fish_pct` — the catch. The world flag
## `weather_<kind>_<location>` drives room variants and closed exits (a flooded ford). The master's `weather` effect
## sets a kind for hours with a cause (Control Weather, a miracle).


static func cfg(data: Dictionary) -> Dictionary:
	return data.get("rules", {}).get("weather", {})


static func on(data: Dictionary) -> bool:
	return not cfg(data).is_empty() and not (data.get("world", {}).get("weather", {}).get("terrain", {}) as Dictionary).is_empty()


static func kind(data: Dictionary, k: String) -> Dictionary:
	return cfg(data).get("kinds", {}).get(k, {})


static func kind_name(data: Dictionary, k: String) -> String:
	return str(kind(data, k).get("name", k))


## The session's switch (`settings.weather`, on unless false): the tests of older systems keep a still sky.
static func live(s: GameSession, data: Dictionary) -> bool:
	return s != null and on(data) and bool(s.settings.get("weather", true))


static func _state(s: GameSession) -> Dictionary:
	var gen := WorldGen.generated(s)
	if not gen.has("weather"):
		gen["weather"] = {"day": 0, "by_loc": {}, "magic": {}, "flags": [], "heat_day": 0}
	return gen["weather"]


static func _world(s: GameSession, data: Dictionary) -> Dictionary:
	return WorldGen.merged(data["world"], WorldGen.generated(s))


## The pack's table {kind: weight} of a location today, {} when it has no weather.
static func table(s: GameSession, data: Dictionary, loc_id: String) -> Dictionary:
	var loc: Dictionary = _world(s, data)["locations"].get(loc_id, {})
	if loc.is_empty() or bool(loc.get("indoor", false)):
		return {}
	var by_season: Dictionary = data["world"].get("weather", {}).get("terrain", {}).get(str(loc.get("terrain", "")), {})
	var season := str(CalendarRules.date(data["world"], s.day).get("season", "")) if CalendarRules.on(data["world"]) else ""
	var t: Variant = by_season.get(season, by_season.get("_default", {}))
	return t if t is Dictionary else {}


static func _roll(s: GameSession, data: Dictionary, loc_id: String, t: Dictionary, was: String) -> String:
	var r := RandomNumberGenerator.new()
	r.seed = hash("weather|%s|%d|%d" % [loc_id, s.day, int(s.rng.seed)])
	if t.has(was) and r.randi_range(1, 100) <= int(cfg(data).get("stay_pct", 0)):
		return was
	var total := 0
	for k: String in t:
		total += maxi(0, int(t[k]))
	var roll := r.randi_range(1, maxi(1, total))
	for k: String in t:
		roll -= maxi(0, int(t[k]))
		if roll <= 0:
			return k
	return "" if t.is_empty() else str(t.keys()[0])


## A new day rolls every location; the master's magic runs out; the world flags follow. Lines for the hero's place.
static func sync(s: GameSession, data: Dictionary) -> Array[String]:
	if not live(s, data):
		return []
	var st := _state(s)
	var lines: Array[String] = []
	var loc := WorldView.new(data["world"]).location_id(s.room_id)
	var before := at(s, data, loc) if int(st["day"]) > 0 else ""
	if int(st["day"]) != s.day:
		var was: Dictionary = st["by_loc"] if int(st["day"]) == s.day - 1 else {}
		var now := {}
		for id: String in _world(s, data)["locations"]:
			var t := table(s, data, id)
			if not t.is_empty():
				now[id] = _roll(s, data, id, t, str(was.get(id, "")))
		st["by_loc"] = now
		st["day"] = s.day
	var magic: Dictionary = st["magic"]
	for id: String in magic.keys():
		if int(magic[id]["until"]) <= TimeRules.abs_minute(s):
			magic.erase(id)
			if id == loc:
				lines.append("Чары над погодой развеялись")
	_flags(s, data)
	var after := at(s, data, loc)
	if after != before and not after.is_empty():
		lines.append("Погода: %s — %s" % [kind_name(data, after), kind(data, after).get("text", "")])
	return lines


static func _flags(s: GameSession, data: Dictionary) -> void:
	var st := _state(s)
	for f: Variant in st["flags"]:
		s.flags.erase(str(f))
	var set: Array = []
	var locs: Dictionary = st["by_loc"].duplicate()
	for id: String in st["magic"]:
		locs[id] = st["magic"][id]["kind"]
	var order: Array = locs.keys()
	order.sort()  # a dictionary loaded from a save has its own order, the flags must not
	for id: String in order:
		var f := "weather_%s_%s" % [locs[id], id]
		if not s.flags.has(f):
			s.flags.append(f)
			set.append(f)
	st["flags"] = set


## The kind at a location now ("" — no weather there): the master's magic first, then the day's roll.
static func at(s: GameSession, data: Dictionary, loc_id: String) -> String:
	if not live(s, data):
		return ""
	var st := _state(s)
	if st["magic"].has(loc_id):
		return str(st["magic"][loc_id]["kind"])
	return str(st["by_loc"].get(loc_id, ""))


## Is the hero's room under a roof (an indoor room or location)?
static func sheltered(s: GameSession, data: Dictionary, room_id: String = "") -> bool:
	var rid := s.room_id if room_id.is_empty() else room_id
	var w := WorldView.new(data["world"])
	return bool(SceneRules.room(s, data["world"], rid).get("indoor", false)) or bool(w.location(w.location_id(rid)).get("indoor", false))


## The kind the hero stands in: "" under a roof or where there is no weather.
static func here(s: GameSession, data: Dictionary) -> String:
	if not live(s, data) or sheltered(s, data):
		return ""
	return at(s, data, WorldView.new(data["world"]).location_id(s.room_id))


## Why ranged attacks and Perception have disadvantage here («ливень», «туман») or "".
static func obscure_why(s: GameSession, data: Dictionary) -> String:
	var k := here(s, data)
	return kind_name(data, k) if bool(kind(data, k).get("obscure", false)) else ""


## The penalty to the watchers' passive Perception here (the hero sneaks more easily).
static func passive(s: GameSession, data: Dictionary) -> int:
	return int(kind(data, here(s, data)).get("passive", 0))


## The time multiplier of a step between two locations: the worse of both.
static func travel_mult(s: GameSession, data: Dictionary, from: String, to: String) -> float:
	if not live(s, data):
		return 1.0
	var w := WorldView.new(data["world"])
	return maxf(float(kind(data, at(s, data, w.location_id(from))).get("travel_mult", 1.0)),
		float(kind(data, at(s, data, w.location_id(to))).get("travel_mult", 1.0)))


## What makes a way between two locations longer: «ливень».
static func way_why(s: GameSession, data: Dictionary, from: String, to: String) -> String:
	var w := WorldView.new(data["world"])
	var a := at(s, data, w.location_id(from))
	var b := at(s, data, w.location_id(to))
	return kind_name(data, a if float(kind(data, a).get("travel_mult", 1.0)) >= float(kind(data, b).get("travel_mult", 1.0)) else b)


## The watchers' passive Perception lost against the hero: invisibility (ConditionRules) and the weather.
static func unseen(s: GameSession, data: Dictionary) -> int:
	return ConditionRules.unseen_penalty(s.character, data) + passive(s, data)


## The catch of a hunt (`game`) or a fishing (`fish`) here in percent.
static func wilds_pct(s: GameSession, data: Dictionary, ground: String) -> int:
	return int(kind(data, here(s, data)).get("hunt_pct" if ground == "game" else "fish_pct", 100))


## What protects the hero against an exposure ("cold" / "heat") now: a reason or "". `fire` — a camp's fire is lit.
static func guard(s: GameSession, data: Dictionary, exposure: String, fire: bool) -> String:
	var ex: Dictionary = cfg(data).get("exposure", {}).get(exposure, {})
	var c := s.character
	var inv: Dictionary = c.get("inventory", {})
	for g: Variant in ex.get("guards", []):
		match str(g):
			"shelter":
				if sheltered(s, data):
					return "под крышей"
				var tent := _has(s, cfg(data).get("shelter_items", []))
				if not tent.is_empty():
					return _item_name(s, data, tent)
			"warm":
				for id: String in inv:
					if int(inv[id]) > 0 and ((cfg(data).get("warm_items", []) as Array).has(id) \
							or (ItemRules.def_of(data["items"], s.items, id).get("properties", []) as Array).has("warm")):
						return ItemRules.display_name(data["items"], s.items, id)
			"fire":
				if fire:
					return "костёр"
			"water":
				if VesselRules.pints(c, data) >= 1.0 or NeedRules.water_here(s, data):
					return "вода"
			"resist":
				var r := str(ex.get("resist", ""))
				var res := HeroDefense.resistances(s, data)
				if not r.is_empty() and res.has(r):
					return "сопротивление: %s" % res[r]
	return ""


## The first of these items the hero carries, or "".
static func _has(s: GameSession, ids: Array) -> String:
	for id: Variant in ids:
		if int(s.character.get("inventory", {}).get(str(id), 0)) > 0:
			return str(id)
	return ""


## The camp's fire: the hero carries a way to light it and the weather does not put it out.
static func camp_fire(s: GameSession, data: Dictionary) -> bool:
	if bool(kind(data, here(s, data)).get("camp", {}).get("fire_out", false)):
		return false
	return not _has(s, cfg(data).get("fire_items", [])).is_empty()


## A night in a camp (the end of ExplorationRules.long_rest with supplies): a downpour soaks an open camp, the cold
## or the heat without a guard costs a CON save against a level of exhaustion. Lines.
static func camp(s: GameSession, data: Dictionary) -> Array[String]:
	var k := here(s, data)
	if k.is_empty():
		return []
	var d := kind(data, k)
	var lines: Array[String] = []
	var tent := _has(s, cfg(data).get("shelter_items", []))
	var cp: Dictionary = d.get("camp", {})
	if bool(cp.get("fire_out", false)):
		if not tent.is_empty():
			lines.append("%s: костёр погас, но в палатке сухо" % kind_name(data, k).capitalize())
		else:
			var r := HeroDefense.save(s, data, "con", int(cp.get("soak_dc", 10)))
			lines.append("%s залил костёр, лагерь промок: %s" % [kind_name(data, k).capitalize(), r["text"]])
			if not bool(r["ok"]):
				var c := s.character
				c["hp"] = maxi(1, mini(int(c["hp"]), int(c["max_hp"]) / 2))
				c["hit_dice_used"] = mini(int(c.get("level", 1)), int(c.get("hit_dice_used", 0)) + maxi(1, int(c.get("level", 1)) / 2))
				lines.append("сон урывками в сырости: HP %d/%d, кости хитов не вернулись" % [c["hp"], c["max_hp"]])
	lines.append_array(_exposure(s, data, k, camp_fire(s, data), "ночь"))
	return lines


## Heat on the way by day (TimeRules.on_move between locations): once a day. Lines.
static func on_way(s: GameSession, data: Dictionary) -> Array[String]:
	var k := here(s, data)
	if str(kind(data, k).get("exposure", "")) != "heat" or TimeRules.is_night(s, data) or int(_state(s)["heat_day"]) == s.day:
		return []
	_state(s)["heat_day"] = s.day
	return _exposure(s, data, k, false, "день в пути")


static func _exposure(s: GameSession, data: Dictionary, k: String, fire: bool, when: String) -> Array[String]:
	var e := str(kind(data, k).get("exposure", ""))
	if e.is_empty():
		return []
	var ex: Dictionary = cfg(data)["exposure"][e]
	var g := guard(s, data, e, fire)
	if not g.is_empty():
		return ["%s: %s не страшен — %s" % [kind_name(data, k).capitalize(), ex["name"], g]]
	var dis := bool(ex.get("heavy_armor_dis", false)) and _heavy(s, data)
	var r := HeroDefense.save(s, data, "con", int(ex["dc"]), "", dis)
	var lines: Array[String] = ["%s, %s без защиты: %s%s" % [kind_name(data, k).capitalize(), when, r["text"], " (тяжёлые доспехи)" if dis else ""]]
	if not bool(r["ok"]):
		lines.append_array(ConditionRules.add_exhaustion(s, data, 1, str(ex["name"])))
	return lines


static func _item_name(s: GameSession, data: Dictionary, g: String) -> String:
	return ItemRules.display_name(data["items"], s.items, g) if data["items"]["catalog"].has(g) or s.items.has(g) else g


static func _heavy(s: GameSession, data: Dictionary) -> bool:
	return str(CharacterRules.item_def(s.character, data, s.items, "armor").get("armor", {}).get("category", "")) == "heavy"


## For the master and the panel: «ливень — …» with the cause of magic, or "".
static func text(s: GameSession, data: Dictionary) -> String:
	var loc := WorldView.new(data["world"]).location_id(s.room_id)
	var k := at(s, data, loc)
	if k.is_empty():
		return ""
	var out := "%s — %s" % [kind_name(data, k), kind(data, k).get("text", "")]
	var m: Dictionary = _state(s)["magic"].get(loc, {})
	if not m.is_empty():
		out += " (чары: %s, ещё %s)" % [m["cause"], TimeRules.span(int(m["until"]) - TimeRules.abs_minute(s))]
	if sheltered(s, data):
		out += "; герой под крышей"
	return out


## What the kind means for the hero, for the panel's hint: its text, then each consequence and the guards carried.
static func effects(s: GameSession, data: Dictionary, k: String) -> Array[String]:
	var d := kind(data, k)
	var out: Array[String] = [str(d.get("text", ""))]
	var m: Dictionary = _state(s)["magic"].get(WeatherRules._loc(s, data), {})
	if not m.is_empty():
		out.append("чары: %s, ещё %s" % [m["cause"], TimeRules.span(int(m["until"]) - TimeRules.abs_minute(s))])
	if bool(d.get("obscure", false)):
		out.append("• помеха дальним атакам и Внимательности; крадущегося заметить труднее (−%d)" % int(d.get("passive", 0)))
	if float(d.get("travel_mult", 1.0)) > 1.0:
		out.append("• переходы между местами ×%s" % str(float(d["travel_mult"])).trim_suffix(".0"))
	if bool(d.get("camp", {}).get("fire_out", false)):
		var tent := _has(s, cfg(data).get("shelter_items", []))
		out.append("• лагерь под открытым небом промокнет (спасбросок Тел %d)%s" % [int(d["camp"].get("soak_dc", 10)),
			"; есть: " + _item_name(s, data, tent) if not tent.is_empty() else "; спасёт палатка или крыша"])
	var e := str(d.get("exposure", ""))
	if not e.is_empty():
		var g := guard(s, data, e, camp_fire(s, data))
		out.append("• %s: %s — спасбросок Тел %d против истощения%s" % [cfg(data)["exposure"][e]["name"],
			"ночь в лагере без тёплой одежды, костра или крыши" if e == "cold" else "день в пути без воды и тени, в тяжёлых доспехах — с помехой",
			int(cfg(data)["exposure"][e]["dc"]), "; защита есть: " + g if not g.is_empty() else ""])
	for ground: String in ["fish", "game"]:
		var p := int(d.get("hunt_pct" if ground == "game" else "fish_pct", 100))
		if p != 100:
			out.append("• %s %s" % ["рыбалка" if ground == "fish" else "охота", "лучше (%d%%)" % p if p > 100 else "хуже (%d%%)" % p])
	return out


static func _loc(s: GameSession, data: Dictionary) -> String:
	return WorldView.new(data["world"]).location_id(s.room_id)


# --- the master's `weather` ----------------------------------------------------------------------------------------


## The plan of `weather` {weather: kind, hours, cause, location_id?}: {plan, summary} or {reason}.
static func plan(s: GameSession, data: Dictionary, e: Dictionary) -> Dictionary:
	if not live(s, data):
		return {"reason": "погоды в этом мире нет"}
	var k := str(e.get("weather", "")) if e.get("weather") != null else ""
	if kind(data, k).is_empty():
		return {"reason": "weather — из %s" % ", ".join(cfg(data)["kinds"].keys())}
	var cause := str(e.get("cause", "")).strip_edges() if e.get("cause") != null else ""
	if cause.length() < 8:
		return {"reason": "нужна cause — какие чары или чудо меняют погоду (от 8 знаков)"}
	var loc := str(e.get("location_id", "")) if e.get("location_id") != null else ""
	if loc.is_empty():
		loc = WorldView.new(data["world"]).location_id(s.room_id)
	if table(s, data, loc).is_empty():
		return {"reason": "в этой локации нет неба — погоды там не бывает"}
	var hours := int(e.get("hours", 0)) if e.get("hours") != null else 0
	var mx := int(cfg(data)["magic"]["max_hours"])
	if hours < 1 or hours > mx:
		return {"reason": "hours — от 1 до %d" % mx}
	var p := {"weather": k, "location": loc, "hours": hours, "cause": cause.left(120)}  # not `text`: a plan with text is a note
	return {"plan": p, "summary": "Погода: %s на %d ч" % [kind_name(data, k), hours]}


static func apply(s: GameSession, data: Dictionary, p: Dictionary) -> Array[String]:
	sync(s, data)
	var loc := str(p["location"])
	_state(s)["magic"][loc] = {"kind": str(p["weather"]), "until": TimeRules.abs_minute(s) + int(p["hours"]) * 60, "cause": str(p["cause"])}
	_flags(s, data)
	var k := str(p["weather"])
	return ["Погода по воле чар: %s на %d ч (%s) — %s" % [kind_name(data, k), int(p["hours"]), p["cause"], kind(data, k).get("text", "")]]
