class_name NeedRules
extends RefCounted
## Needs of the hero (roadmap v0.7.23, rules.needs): food and water empty over the game clock from the last meal or
## drink, sleep is read from the hours awake. A low need is a stage (a chip, a line for the master, hampered saves);
## an empty one past its grace days gives a level of exhaustion each day. Kept in c["needs"]:
## {food: {level, at}, water: {level, at}, done: {need: exhaustion levels given}}; the water carried — LiquidRules.

const KINDS: Array[String] = ["food", "water", "sleep"]


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"]["needs"]


## The game setting «Нужды» (on by default; off — no scales, no hunger).
static func on(s: GameSession) -> bool:
	return bool(s.settings.get("needs", true))


## The hero's needs, made full at this moment the first time they are asked for (an old save, a new hero).
static func state(s: GameSession, data: Dictionary) -> Dictionary:
	var c := s.character
	if not (c.get("needs") is Dictionary) or (c["needs"] as Dictionary).is_empty():
		var now := TimeRules.abs_minute(s)
		c["needs"] = {"food": {"level": 100.0, "at": now}, "water": {"level": 100.0, "at": now}, "done": {}}
	return c["needs"]


## 0–100 now: food and water from the last meal or drink, sleep from the hours awake.
static func value(s: GameSession, data: Dictionary, need: String) -> float:
	if need == "sleep":
		var hours := float(data["rules"]["hero_effects"]["exhaustion"]["awake_hours"])
		return clampf(100.0 * (1.0 - float(TimeRules.abs_minute(s) - s.rested_at) / (hours * 60.0)), 0.0, 100.0)
	var n: Dictionary = state(s, data)[need]
	var per_minute := 100.0 / (float(cfg(data)[need]["hours"]) * 60.0)
	return clampf(float(n["level"]) - float(TimeRules.abs_minute(s) - int(n["at"])) * per_minute, 0.0, 100.0)


static func set_value(s: GameSession, data: Dictionary, need: String, v: float) -> void:
	var st := state(s, data)
	st[need] = {"level": clampf(v, 0.0, 100.0), "at": TimeRules.abs_minute(s)}
	(st["done"] as Dictionary).erase(need)
	_refresh_mods(s, data)


## The stage the need is in now ({} — fine): the lowest of rules.needs.<need>.stages it is below.
static func stage(s: GameSession, data: Dictionary, need: String) -> Dictionary:
	return Scale.below(cfg(data)[need]["stages"], value(s, data, need))


## The needs that show now: [{need, chip, line}] for the panel chips and the master's effects.
static func shown(s: GameSession, data: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not on(s):
		return out
	for need: String in KINDS:
		var st := stage(s, data, need)
		if not st.is_empty():
			out.append({"need": need, "chip": str(st["chip"]), "line": str(st["line"])})
	return out


## Days an empty need is borne before exhaustion: a number or "3+con" (5e: 3 + CON modifier, at least 1).
static func grace(c: Dictionary, data: Dictionary, need: String) -> int:
	var g := str(cfg(data)[need].get("grace_days", "1"))
	if g.ends_with("+con"):
		return maxi(1, int(g.trim_suffix("+con")) + CharacterRules.mod(CharacterRules.ability(c, "con")))
	return maxi(0, int(g))


## After time passed: a level of exhaustion for each full day an empty need ran past its grace; the saves a stage
## hampers. Lines.
static func tick(s: GameSession, data: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	if not on(s) or not data["rules"].has("needs"):
		s.character["need_mods"] = {}
		return lines
	var st := state(s, data)
	var now := TimeRules.abs_minute(s)
	for need: String in ["food", "water"]:
		var n: Dictionary = st[need]
		var empty_at := int(n["at"]) + int(float(n["level"]) / 100.0 * float(cfg(data)[need]["hours"]) * 60.0)
		if now < empty_at:
			continue
		var owed := maxi(0, (now - empty_at) / 1440 + 1 - grace(s.character, data, need))
		var done: Dictionary = st["done"]
		while int(done.get(need, 0)) < owed:
			done[need] = int(done.get(need, 0)) + 1
			lines.append_array(ConditionRules.add_exhaustion(s, data, 1, "голод" if need == "food" else "жажда"))
	_refresh_mods(s, data)
	return lines


## The saves the needs' stages hamper now, kept on the hero for ConditionRules.check_mods: {ability: mode}.
static func _refresh_mods(s: GameSession, data: Dictionary) -> void:
	var mods := {}
	if on(s):
		for need: String in KINDS:
			var saves: Dictionary = stage(s, data, need).get("saves", {})
			for a: String in saves:
				mods[a] = str(saves[a])
	s.character["need_mods"] = mods


# --- eating and drinking ---------------------------------------------------------------------------


## What the hero can eat: {item_id: points} of the food the camp knows (rules.hero_effects.camp.food).
static func food_items(c: Dictionary, data: Dictionary) -> Dictionary:
	var food: Dictionary = data["rules"]["hero_effects"]["camp"]["food"]
	var out := {}
	for id: String in ExplorationRules.camp_food(c, data):
		out[id] = int(food[id])
	return out


## One hunger of anybody fed by the day (v0.8.4.29.4: a follower, a beast, a pet): for each day past `rec[key]` (its last meal,
## by `step` of the same clock as `now`) `eat` (Callable() -> bool) is asked; a meal sets the hungry days to 0, none adds one and
## `missed` (Callable()) is told. The hungry days now (`rec.hungry`).
static func hunger(rec: Dictionary, key: String, now: int, step: int, eat: Callable, missed: Callable = Callable()) -> int:
	while now - int(rec.get(key, now)) >= step:
		rec[key] = int(rec.get(key, now)) + step
		if eat.call():
			rec["hungry"] = 0
		else:
			rec["hungry"] = int(rec.get("hungry", 0)) + 1
			if missed.is_valid():
				missed.call()
	return int(rec.get("hungry", 0))


## "" when eating now does good, else a localization key.
static func can_eat(s: GameSession, data: Dictionary) -> String:
	if food_items(s.character, data).is_empty():
		return "NEED_NO_FOOD"
	if value(s, data, "food") >= 75.0:
		return "NEED_NOT_HUNGRY"
	return ""


## Eats the cheapest food first until the hero is fed (75+). Lines.
static func eat(s: GameSession, data: Dictionary) -> Array[String]:
	var c := s.character
	var have := food_items(c, data)
	var v := value(s, data, "food")
	var eaten: Array[String] = []
	var after: Array[String] = []
	for id: Variant in FoodRules.portions(s, data, c):  # what spoils first, foul food last (v0.8.4.29.4: one order)
		var n := 0
		while v < 75.0 and int(c["inventory"].get(id, 0)) > 0:
			v += float(have[id]) * float(cfg(data)["food"]["points"])
			ItemRules.remove(c, str(id))
			eaten.append(ItemRules.display_name(data["items"], s.items, str(id)))
			n += 1
		if n > 0:  # the one meal: its food, a dish's water, temporary HP and boon once a kind, foul food's disease (v0.7.25)
			after.append_array(FoodRules.eat_one(s, data, str(id), Sheet.HERO, n, false))
	var lines: Array[String] = ["Поел: " + ", ".join(eaten), "Еда %d/100" % roundi(value(s, data, "food"))]
	lines.append_array(after)
	return lines


## Pints the hero's vessels hold in all (v0.7.34.6).
static func capacity(c: Dictionary, data: Dictionary) -> float:
	return LiquidRules.room(c, data) + LiquidRules.pints(c, data)


static func drinks(s: GameSession, data: Dictionary) -> float:
	return LiquidRules.pints(s.character, data)


## Water here: the room's tag `water` or `foul_water`, a thing of the room with `source` (v0.7.34.6, the master's
## river), one named by rules.needs.water_words (a well, a stream), or a thing of the hero's that pours it (`water_source`).
static func water_here(s: GameSession, data: Dictionary) -> bool:
	if Sheet.prop(s, data, Sheet.HERO, "water_source"):  # v0.8.4.26: a Decanter of Endless Water pours anywhere
		return true
	var tags := SceneRules.tags(s, data["world"], s.room_id)
	if tags.has("water") or tags.has("foul_water"):
		return true
	var words: Array = cfg(data).get("water_words", [])
	for p: Dictionary in PropRules.room_props(s, s.room_id):
		var name := str(p.get("name", "")).to_lower()
		if str(p.get("source", "")) in [LiquidRules.WATER, LiquidRules.FOUL] or words.any(func(w: Variant) -> bool: return name.contains(str(w))):
			return true
	return false


## Water here is foul (the room's tag `foul_water`, v0.7.23.1, or only a source thing of foul water): a drink of it or
## of a vessel filled here risks a disease.
static func foul_here(s: GameSession, data: Dictionary) -> bool:
	var tags := SceneRules.tags(s, data["world"], s.room_id)
	if tags.has("foul_water"):
		return true
	if tags.has("water"):
		return false
	var src: Array = PropRules.room_props(s, s.room_id).map(func(p: Dictionary) -> String: return str(p.get("source", "")))
	return src.has("foul_water") and not src.has("water")


static func _foul_drink(s: GameSession, data: Dictionary) -> Array[String]:
	return LiquidRules.sickness(s, data, Sheet.HERO, LiquidRules.FOUL)  # the liquid's own disease (v0.8.4.29.4)


static func can_drink(s: GameSession, data: Dictionary) -> String:
	if not water_here(s, data) and drinks(s, data) <= 0.0:
		return "NEED_NO_WATER"
	if value(s, data, "water") >= 75.0:
		return "NEED_NOT_THIRSTY"
	return ""


## Drinks from the source here (free) or from the waterskins until 75+. Lines.
static func drink(s: GameSession, data: Dictionary) -> Array[String]:
	var here := water_here(s, data)
	var r := _sip(s, data, 75.0, here)
	var lines: Array[String] = ["Напился" + ("" if here else " из ёмкостей (осталось %s пинт)" % LiquidRules.num(drinks(s, data)))]
	lines.append("Вода %d/100" % roundi(value(s, data, "water")))
	if bool(r["foul"]):
		lines.append_array(_foul_drink(s, data))
	return lines


## Drinks up to `upto`: from the source here by whole drinks, else from the vessels (a pint gives drink / drink_pints).
static func _sip(s: GameSession, data: Dictionary, upto: float, here: bool) -> Dictionary:
	var w: Dictionary = cfg(data)["water"]
	var v := value(s, data, "water")
	if here:
		set_value(s, data, "water", minf(100.0, v + ceilf(maxf(0.0, upto - v) / float(w["drink"])) * float(w["drink"])))
		return {"foul": foul_here(s, data)}
	var got := LiquidRules.take(s.character, data, maxf(0.0, upto - v) / per_pint(data))
	LiquidRules.nourish(s, data, Sheet.HERO, float(got["pints"]), {"water": 1})
	return {"foul": bool(got["foul"])}


## The water one pint of a drink gives the need (rules.needs.water: a drink of `drink_pints`).
static func per_pint(data: Dictionary) -> float:
	var w: Dictionary = cfg(data)["water"]
	return float(w["drink"]) / float(w.get("drink_pints", 2))


## `only` — one kind of vessel (the master's `fill` with an item_id).
static func can_fill(s: GameSession, data: Dictionary, only := "") -> String:
	if LiquidRules.carried(s.character, data).filter(func(v: Dictionary) -> bool: return not bool(v["ready"]) and (only.is_empty() or v["id"] == only)).is_empty():
		return "NEED_NO_SKIN"
	if not water_here(s, data):
		return "NEED_NO_SOURCE"
	if LiquidRules.to_fill(s.character, data, foul_here(s, data), only).is_empty():
		return "NEED_SKIN_FULL"
	return ""


static func fill(s: GameSession, data: Dictionary, only := "") -> Array[String]:
	var foul := foul_here(s, data)
	LiquidRules.fill(s.character, data, foul, only)
	var lines: Array[String] = ["Набрал воды" + (" — гнилой" if foul else "")]
	lines.append_array(LiquidRules.lines(s.character, data, s.items, only))
	return lines


## A long rest's meal: a bed in a settlement feeds and waters; a camp eats its `points` of food and drinks from the
## source or the waterskins. Lines.
static func rest_meal(s: GameSession, data: Dictionary, camp_points: int, bed: bool) -> Array[String]:
	var lines: Array[String] = []
	if not on(s) or not data["rules"].has("needs"):
		return lines
	if bed and bool(cfg(data).get("rest_meal", true)):
		set_value(s, data, "food", 100.0)
		set_value(s, data, "water", 100.0)
		return ["ужин и вода — с ночлегом"]
	if camp_points > 0:
		set_value(s, data, "food", value(s, data, "food") + camp_points * float(cfg(data)["food"]["points"]))
	if value(s, data, "water") < 100.0 and (water_here(s, data) or drinks(s, data) > 0.0):
		if bool(_sip(s, data, 100.0, water_here(s, data))["foul"]):
			lines.append_array(_foul_drink(s, data))
	lines.append("еда %d, вода %d" % [roundi(value(s, data, "food")), roundi(value(s, data, "water"))])
	return lines


## After the night of a long rest (v0.7.39): the rest's meal was eaten at `began` (an absolute minute), but it counts
## as the breakfast — food and water filled by it stand as they were at waking, not emptied by the hours of sleep.
static func woke(s: GameSession, data: Dictionary, began: int) -> void:
	if not on(s) or not data["rules"].has("needs"):
		return
	var st := state(s, data)
	for need: String in ["food", "water"]:
		if int(st[need]["at"]) >= began:
			st[need]["at"] = TimeRules.abs_minute(s)
	_refresh_mods(s, data)


## A paid meal (the service `meal`): fed and watered.
static func meal(s: GameSession, data: Dictionary) -> Array[String]:
	set_value(s, data, "food", 100.0)
	set_value(s, data, "water", 100.0)
	return ["Сыт и напоен"]


