class_name NeedRules
extends RefCounted
## Needs of the hero (roadmap v0.7.23, rules.needs): food and water empty over the game clock from the last meal or
## drink, sleep is read from the hours awake. A low need is a stage (a chip, a line for the master, hampered saves);
## an empty one past its grace days gives a level of exhaustion each day. Kept in c["needs"]:
## {food: {level, at}, water: {level, at}, skin: drinks in the waterskins, done: {need: exhaustion levels given}}.

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
		c["needs"] = {"food": {"level": 100.0, "at": now}, "water": {"level": 100.0, "at": now}, "skin": capacity(c, data), "skin_foul": false, "done": {}}
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
	var v := value(s, data, need)
	var out := {}
	for st: Dictionary in cfg(data)[need]["stages"]:
		if v < float(st["below"]):
			out = st
	return out


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
	var ids: Array = have.keys()
	var foul: Dictionary = data["rules"].get("diseases", {}).get("foul_food", {})
	var key := func(id: Variant) -> int:  # foul food last (v0.7.23.1), what spoils first (v0.7.25)
		return int(foul.has(id)) * 1000 + int(FoodRules.spoils_days(data, s.items, str(id)) <= 0) * 100 + int(have[id])
	ids.sort_custom(func(a: Variant, b: Variant) -> bool: return key.call(a) < key.call(b))
	var v := value(s, data, "food")
	var eaten: Array[String] = []
	for id: Variant in ids:
		while v < 75.0 and int(c["inventory"].get(id, 0)) > 0:
			v += float(have[id]) * float(cfg(data)["food"]["points"])
			_take(c, str(id))
			eaten.append(ItemRules.display_name(data["items"], s.items, str(id)))
	set_value(s, data, "food", v)
	var lines: Array[String] = ["Поел: " + ", ".join(eaten), "Еда %d/100" % roundi(value(s, data, "food"))]
	for id: Variant in ids:  # a dish's water, temporary HP and boon, once a kind (v0.7.25)
		if eaten.has(ItemRules.display_name(data["items"], s.items, str(id))):
			lines.append_array(FoodRules.meal(s, data, str(id)))
	for id: Variant in ids:
		if foul.has(id) and eaten.has(ItemRules.display_name(data["items"], s.items, str(id))):
			lines.append_array(DiseaseRules.expose(s, data, str(foul[id]["disease"]), int(foul[id]["dc"]), "Дурная еда"))
	return lines


## Waterskins the hero carries × rules.needs.water.skin_drinks.
static func capacity(c: Dictionary, data: Dictionary) -> int:
	var w: Dictionary = cfg(data)["water"]
	return int(c.get("inventory", {}).get(str(w["skin"]), 0)) * int(w["skin_drinks"])


static func drinks(s: GameSession, data: Dictionary) -> int:
	return mini(int(state(s, data).get("skin", 0)), capacity(s.character, data))


## Water here: the room's tag `water`, or a thing of the room named by rules.needs.water_words (a well, a stream).
static func water_here(s: GameSession, data: Dictionary) -> bool:
	if (SceneRules.room(s, data["world"], s.room_id).get("tags", []) as Array).has("water"):
		return true
	var words: Array = cfg(data).get("water_words", [])
	for p: Dictionary in PropRules.room_props(s, s.room_id):
		var name := str(p.get("name", "")).to_lower()
		if words.any(func(w: Variant) -> bool: return name.contains(str(w))):
			return true
	return false


## Water here is foul (the room's tag `foul_water`, v0.7.23.1): a drink of it or of a skin filled here risks a disease.
static func foul_here(s: GameSession, data: Dictionary) -> bool:
	return (SceneRules.room(s, data["world"], s.room_id).get("tags", []) as Array).has("foul_water")


static func _foul_drink(s: GameSession, data: Dictionary) -> Array[String]:
	var fw: Dictionary = data["rules"].get("diseases", {}).get("foul_water", {})
	if fw.is_empty():
		return []
	return DiseaseRules.expose(s, data, str(fw["disease"]), int(fw["dc"]), "Гнилая вода")


static func can_drink(s: GameSession, data: Dictionary) -> String:
	if not water_here(s, data) and drinks(s, data) <= 0:
		return "NEED_NO_WATER"
	if value(s, data, "water") >= 75.0:
		return "NEED_NOT_THIRSTY"
	return ""


## Drinks from the source here (free) or from the waterskins until 75+. Lines.
static func drink(s: GameSession, data: Dictionary) -> Array[String]:
	var st := state(s, data)
	var v := value(s, data, "water")
	var from_skin := 0
	var here := water_here(s, data)
	while v < 75.0 and (here or drinks(s, data) > 0):
		v += float(cfg(data)["water"]["drink"])
		if not here:
			st["skin"] = drinks(s, data) - 1
			from_skin += 1
	set_value(s, data, "water", v)
	var lines: Array[String] = ["Напился" + (" из бурдюка (%d/%d)" % [drinks(s, data), capacity(s.character, data)] if from_skin > 0 else "")]
	lines.append("Вода %d/100" % roundi(value(s, data, "water")))
	if here and foul_here(s, data) or not here and bool(st.get("skin_foul", false)):
		lines.append_array(_foul_drink(s, data))
	return lines


static func can_fill(s: GameSession, data: Dictionary) -> String:
	if capacity(s.character, data) <= 0:
		return "NEED_NO_SKIN"
	if not water_here(s, data):
		return "NEED_NO_SOURCE"
	if drinks(s, data) >= capacity(s.character, data):
		return "NEED_SKIN_FULL"
	return ""


static func fill(s: GameSession, data: Dictionary) -> Array[String]:
	state(s, data)["skin"] = capacity(s.character, data)
	state(s, data)["skin_foul"] = foul_here(s, data)
	return ["Бурдюк полон (%d/%d)" % [drinks(s, data), capacity(s.character, data)]]


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
	if value(s, data, "water") < 100.0 and (water_here(s, data) or drinks(s, data) > 0):
		var st := state(s, data)
		if water_here(s, data) and foul_here(s, data) or not water_here(s, data) and bool(st.get("skin_foul", false)):
			lines.append_array(_foul_drink(s, data))
		var v := value(s, data, "water")
		while v < 100.0 and (water_here(s, data) or drinks(s, data) > 0):
			v += float(cfg(data)["water"]["drink"])
			if not water_here(s, data):
				st["skin"] = drinks(s, data) - 1
		set_value(s, data, "water", v)
	lines.append("еда %d, вода %d" % [roundi(value(s, data, "food")), roundi(value(s, data, "water"))])
	return lines


## A paid meal (the service `meal`): fed and watered.
static func meal(s: GameSession, data: Dictionary) -> Array[String]:
	set_value(s, data, "food", 100.0)
	set_value(s, data, "water", 100.0)
	return ["Сыт и напоен"]


static func _take(c: Dictionary, id: String) -> void:
	var left := int(c["inventory"].get(id, 0)) - 1
	if left > 0:
		c["inventory"][id] = left
	else:
		(c["inventory"] as Dictionary).erase(id)
