class_name TimeRules
extends RefCounted
## Time of day (roadmap v0.6.3, decision of the author): minutes since midnight in `s.minute`. A step between rooms
## and rests move it (rules.time); crossing midnight starts a new day. Parts of the day — rules.time.parts. At night
## traders are closed; at night outside a lit location (`lit` in the pack) a character without darkvision or a
## light source in the pack has disadvantage on Perception (passive −5). The master sees the part in the scene.


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"]["time"]


## The id of the part of the day (morning / day / evening / night).
static func part(s: GameSession, data: Dictionary) -> String:
	var parts: Array = cfg(data)["parts"]
	var id := str(parts[parts.size() - 1]["id"])  # before the first part — still the night
	for p: Dictionary in parts:
		if s.minute >= int(p["from"]):
			id = str(p["id"])
	return id


## The Russian word of the part for the master and the panel («утро»).
static func part_name(s: GameSession, data: Dictionary) -> String:
	for p: Dictionary in cfg(data)["parts"]:
		if str(p["id"]) == part(s, data):
			return str(p["name"])
	return ""


static func clock(s: GameSession) -> String:
	return "%02d:%02d" % [s.minute / 60, s.minute % 60]


static func is_night(s: GameSession, data: Dictionary) -> bool:
	return part(s, data) == "night"


## Moves time on; a new part of the day or a new day gives a line. Effects on the hero run out, and a day awake
## without a long rest calls for a CON save against exhaustion (v0.7.8).
static func advance(s: GameSession, data: Dictionary, minutes: int) -> Array[String]:
	var lines: Array[String] = []
	var before := part(s, data)
	s.minute += maxi(0, minutes)
	while s.minute >= 1440:
		s.minute -= 1440
		s.day += 1
		lines.append("Наступил день %d" % s.day)
	if part(s, data) != before:
		lines.append("Время суток: %s" % part_name(s, data))
	lines.append_array(ConditionRules.expire(s, data))
	lines.append_array(SpellEffects.npc_expire(s, data))  # Charm Person on an NPC ends (v0.7.22.3)
	lines.append_array(AllyRules.expire(s))  # the summoned go when their time is out (v0.7.22.22)
	if data["rules"].has("creatures"):
		lines.append_array(CreatureRules.tick(s, data))  # the beaten foes left alone go (v0.7.22.11)
	lines.append_array(_awake(s, data))
	lines.append_array(NeedRules.tick(s, data))
	lines.append_array(DiseaseRules.tick(s, data))  # hunger and thirst past their grace (v0.7.23)
	lines.append_array(FoodRules.tick(s, data))  # food spoils (v0.7.25)
	lines.append_array(PropertyRules.tick(s, data))  # income, wages, decay, tax, beasts fed (v0.7.27)
	lines.append_array(CrimeRules.spread(s, data))  # a hidden body is found (v0.7.14)
	if data["rules"].has("doors"):
		lines.append_array(DoorRules.tick(s, data))  # a burning door burns through (v0.7.22.25)
	return lines


## The absolute minute of the game clock (since the first day's midnight).
static func abs_minute(s: GameSession) -> int:
	return (s.day - 1) * 1440 + s.minute


## Each full rules.hero_effects.exhaustion.awake_hours without a long rest: a CON save, DC awake_dc + awake_dc_step
## per day before; a failure — a level of exhaustion. Lines.
static func _awake(s: GameSession, data: Dictionary) -> Array[String]:
	var ex: Dictionary = data["rules"]["hero_effects"]["exhaustion"]
	var days := (abs_minute(s) - s.rested_at) / (int(ex["awake_hours"]) * 60)
	var lines: Array[String] = []
	while s.awake_saves < days:
		var dc := int(ex["awake_dc"]) + int(ex["awake_dc_step"]) * s.awake_saves
		s.awake_saves += 1
		var r := HeroDefense.save(s, data, "con", dc)
		lines.append("Без сна %d ч: %s" % [s.awake_saves * int(ex["awake_hours"]), r["text"]])
		if not bool(r["ok"]):
			lines.append_array(ConditionRules.add_exhaustion(s, data, 1, "без сна"))
	return lines


## A step from room to room: rules.time.move_minutes, into another location — travel_minutes. The way counts towards
## the day's march (v0.7.8).
static func on_move(s: GameSession, data: Dictionary, from: String, to: String) -> Array[String]:
	var w := WorldView.new(data["world"])
	var same := w.location_id(from) == w.location_id(to)
	var minutes := int(cfg(data)["move_minutes" if same else "travel_minutes"])
	if not same:
		minutes = BackgroundRules.travel_minutes(s, data, minutes, to)  # an outlander's Wanderer (v0.7.11)
		minutes = roundi(minutes * minf(PropertyRules.travel_mult(s, data, from), PropertyRules.travel_mult(s, data, to)))  # riding (v0.7.27)
	var lines := advance(s, data, minutes)
	lines.append_array(march(s, data, minutes))
	return lines


## A forced march (5e): every hour on the way past rules.hero_effects.exhaustion.march_hours a day — a CON save,
## DC march_dc + the hours past; a failure — a level of exhaustion. Lines.
static func march(s: GameSession, data: Dictionary, minutes: int) -> Array[String]:
	var ex: Dictionary = data["rules"]["hero_effects"]["exhaustion"]
	if s.march_day != s.day:
		s.march_day = s.day
		s.march_minutes = 0
	var limit := int(ex["march_hours"]) * 60
	var before := s.march_minutes
	s.march_minutes += maxi(0, minutes)
	var lines: Array[String] = []
	for hour in range(maxi(0, (before - limit) / 60) + 1, maxi(0, (s.march_minutes - limit) / 60) + 1):
		var r := HeroDefense.save(s, data, "con", int(ex["march_dc"]) + hour)
		lines.append("Марш %d ч за день: %s" % [int(ex["march_hours"]) + hour, r["text"]])
		if not bool(r["ok"]):
			lines.append_array(ConditionRules.add_exhaustion(s, data, 1, "марш"))
	return lines


## A long rest ends in the morning (wake_minute). ExplorationRules.long_rest already counted the new day; a rest
## begun after midnight is already in it.
static func after_long_rest(s: GameSession, data: Dictionary, began_minute: int) -> void:
	if began_minute < int(cfg(data)["wake_minute"]):
		s.day = maxi(1, s.day - 1)
	s.minute = int(cfg(data)["wake_minute"])
	if CharacterRules.has_trait(s.character, "trance"):  # an elf rests four hours, not eight (v0.7.10)
		s.minute = maxi(0, s.minute - 180)
	s.rested_at = abs_minute(s)
	s.awake_saves = 0


static func shops_closed(s: GameSession, data: Dictionary) -> bool:
	return is_night(s, data) and bool(cfg(data).get("night_shops_closed", true))


## Darkvision (or Devil's Sight, v0.7.10) or a light source in the pack (an item with the light_source property).
static func can_see(s: GameSession, data: Dictionary) -> bool:
	var c := s.character
	if CharacterRules.has_trait(c, "darkvision") or CharacterRules.has_feature(c, "eldritch_invocation_devils_sight") or CharacterRules.item_prop(c, "darkvision") \
			or SpellEffects.has(c, "darkvision") or SpellEffects.has(c, "light"):  # Light and the like (v0.7.13.8)
		return true
	for id: String in c.get("inventory", {}):
		if (ItemRules.def_of(data["items"], s.items, id).get("properties", []) as Array).has("light_source"):
			return true
	return false


## Night outside a lit location, or a dark room of the pack (`dark` at a room or its location — a mine, a crypt, a
## burrow; v0.7.10), without a way to see.
static func dark(s: GameSession, data: Dictionary) -> bool:
	var w := WorldView.new(data["world"])
	var unlit := bool(w.room(s.room_id).get("dark", false)) or bool(w.location(w.location_id(s.room_id)).get("dark", false))
	if not unlit:
		if not is_night(s, data) or bool(w.location(w.location_id(s.room_id)).get("lit", false)):
			return false
	return not can_see(s, data)


## Passive Perception lost now: sneaking (−5) and darkness (disadvantage = −5).
static func passive_penalty(s: GameSession, data: Dictionary) -> int:
	return (ExplorationRules.SNEAK_PASSIVE_PENALTY if s.sneaking else 0) + (5 if dark(s, data) else 0)


## Minutes until `target`: "hour" — 60, a part id — its next start (a full day when it is starting right now).
static func minutes_until(s: GameSession, data: Dictionary, target: String) -> int:
	if target == "hour":
		return 60
	for p: Dictionary in cfg(data)["parts"]:
		if str(p["id"]) == target:
			var m := posmod(int(p["from"]) - s.minute, 1440)
			return m if m > 0 else 1440
	return 0


## A span of time in words: «45 мин», «1 ч», «1 ч 20 мин» (v0.7.22.31, С5).
static func span(minutes: int) -> String:
	if minutes < 60:
		return "%d мин" % minutes
	return "%d ч%s" % [minutes / 60, (" %d мин" % (minutes % 60)) if minutes % 60 > 0 else ""]


## The clock after `minutes` («18:00»).
static func clock_after(s: GameSession, minutes: int) -> String:
	var m := posmod(s.minute + minutes, 1440)
	return "%02d:%02d" % [m / 60, m % 60]

