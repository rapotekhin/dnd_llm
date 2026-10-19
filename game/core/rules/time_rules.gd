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


## Moves time on; a new part of the day or a new day gives a line.
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
	return lines


## A step from room to room: rules.time.move_minutes, into another location — travel_minutes.
static func on_move(s: GameSession, data: Dictionary, from: String, to: String) -> Array[String]:
	var w := WorldView.new(data["world"])
	var same := w.location_id(from) == w.location_id(to)
	return advance(s, data, int(cfg(data)["move_minutes" if same else "travel_minutes"]))


## A long rest ends in the morning (wake_minute). ExplorationRules.long_rest already counted the new day; a rest
## begun after midnight is already in it.
static func after_long_rest(s: GameSession, data: Dictionary, began_minute: int) -> void:
	if began_minute < int(cfg(data)["wake_minute"]):
		s.day = maxi(1, s.day - 1)
	s.minute = int(cfg(data)["wake_minute"])


static func shops_closed(s: GameSession, data: Dictionary) -> bool:
	return is_night(s, data) and bool(cfg(data).get("night_shops_closed", true))


## Darkvision or a light source in the pack (an item with the light_source property).
static func can_see(s: GameSession, data: Dictionary) -> bool:
	var c := s.character
	if CharacterRules.has_trait(c, "darkvision"):
		return true
	for id: String in c.get("inventory", {}):
		if (ItemRules.def_of(data["items"], s.items, id).get("properties", []) as Array).has("light_source"):
			return true
	return false


## Night outside a lit location without a way to see.
static func dark(s: GameSession, data: Dictionary) -> bool:
	if not is_night(s, data):
		return false
	var w := WorldView.new(data["world"])
	if bool(w.location(w.location_id(s.room_id)).get("lit", false)):
		return false
	return not can_see(s, data)


## Passive Perception lost now: sneaking (−5) and darkness (disadvantage = −5).
static func passive_penalty(s: GameSession, data: Dictionary) -> int:
	return (ExplorationRules.SNEAK_PASSIVE_PENALTY if s.sneaking else 0) + (5 if dark(s, data) else 0)
