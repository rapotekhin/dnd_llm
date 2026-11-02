class_name TimeRules
extends RefCounted
## Time of day (roadmap v0.6.3, decision of the author): minutes since midnight in `s.minute`. A step between rooms
## and rests move it (rules.time); crossing midnight starts a new day. Parts of the day — rules.time.parts. At night
## traders are closed; at night outside a lit location (`lit` in the pack) a character without darkvision or a
## light source in the pack has disadvantage on Perception (passive −5). The master sees the part in the scene.


static var _hooks: Array[Dictionary] = []


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


## Moves time on; a new part of the day or a new day gives a line. The one way the clock moves (v0.8.4.17): a step, a
## wait, a rest and a sentence alike. Each midnight crossed runs the rows of `each_day` (a festival begins and ends on
## its own day), then `arrived` (what the mover sets at the new moment, before the world reacts), then the hooks.
static func advance(s: GameSession, data: Dictionary, minutes: int, arrived: Callable = Callable()) -> Array[String]:
	var lines: Array[String] = []
	var before := part(s, data)
	var left := maxi(0, minutes)
	while left >= 1440 - s.minute:
		left -= 1440 - s.minute
		s.clock += 1440 - s.minute
		lines.append("Наступил день %d%s" % [s.day, (" — " + CalendarRules.text(data["world"], s.day)) if CalendarRules.on(data["world"]) else ""])
		lines.append_array(_run(s, data, true))
	s.clock += left
	if arrived.is_valid():
		arrived.call()
	if part(s, data) != before:
		lines.append("Время суток: %s" % part_name(s, data))
	lines.append_array(hooks(s, data))
	return lines


## The days of a sentence, to their morning: the clock goes on by `advance`, the hero wakes rested and fed (v0.8.4.17:
## the world's days pass with it — rent, interest, letters, rumours).
static func jump(s: GameSession, data: Dictionary, days: int) -> Array[String]:
	var wake := day_start(s.day + days) + int(cfg(data)["wake_minute"])
	s.rested_at = wake
	s.awake_saves = 0
	return advance(s, data, wake - abs_minute(s), func() -> void:
		NeedRules.set_value(s, data, "food", 100.0)
		NeedRules.set_value(s, data, "water", 100.0))


## A long rest to its morning (v0.8.4.17, one sequence): the clock goes to the wake minute (an elf's trance — three hours
## sooner) by `advance`; begun after midnight and before the wake, it ends the same day. The day awake starts at waking,
## the rest's meal counts as the breakfast of the hero and the followers.
static func sleep(s: GameSession, data: Dictionary, began: int) -> Array[String]:
	var wake_at := int(cfg(data)["wake_minute"]) - (180 if CharacterRules.has_trait(s.character, "trance") else 0)
	var wake := day_start(day_of(began)) + maxi(0, wake_at)
	if wake <= began:
		wake += 1440
	s.rested_at = wake
	s.awake_saves = 0
	return advance(s, data, wake - abs_minute(s), func() -> void:
		NeedRules.woke(s, data, began)
		FollowRules.rested(s))


## The date's own state at a start or a load, with no time passing: the festivals' flags and the weather.
static func settle(s: GameSession, data: Dictionary) -> void:
	_run(s, data, true)
	WeatherRules.sync(s, data)


## What passing time does to the world, in its order: the one list of what happens as the clock runs (v0.7.60). `rules` —
## the section of rules.json a hook needs. A rule that wants time adds a line here.
static func registry() -> Array[Dictionary]:
	if _hooks.is_empty():
		_hooks = [
			{"id": "calendar", "run": func(s: GameSession, data: Dictionary) -> Array[String]: return CalendarRules.sync(s, data["world"]), "each_day": true},  # festivals begin and end (v0.7.44)
			{"id": "weather", "run": WeatherRules.sync},  # a new day's weather, the master's magic runs out (v0.7.46)
			{"id": "charms", "run": SpellEffects.npc_expire},  # Charm Person on an NPC ends (v0.7.22.3), before the statuses' time out
			{"id": "conditions", "run": ConditionRules.expire},
			{"id": "rest", "run": Rest.tick},  # who is not with the hero rests a night each (v0.8.4.11)
			{"id": "summoned", "run": AllyRules.expire},  # the summoned go when their time is out (v0.7.22.22)
			{"id": "creatures", "run": CreatureRules.tick, "rules": "creatures"},  # the beaten foes left alone go (v0.7.22.11)
			{"id": "awake", "run": _awake},
			{"id": "needs", "run": NeedRules.tick},
			{"id": "follower_meals", "run": FollowRules.meals},  # followers eat from the hero's things (v0.7.39.1)
			{"id": "diseases", "run": DiseaseRules.tick},  # hunger and thirst past their grace (v0.7.23)
			{"id": "food", "run": FoodRules.tick},  # food spoils (v0.7.25)
			{"id": "family", "run": FamilyRules.tick},  # births, growth, the help into the till before its tax (v0.7.32)
			{"id": "orgs", "run": OrgRules.tick},  # unpaid cuts, the own band's income (v0.7.33)
			{"id": "offices", "run": OfficeRules.tick},  # wages, inquiries, absence, towns (v0.7.34)
			{"id": "property", "run": PropertyRules.tick},  # income, wages, decay, tax, beasts fed (v0.7.27)
			{"id": "bank", "run": BankRules.tick},  # interest, overdue loans, vault fees (v0.7.28)
			{"id": "shops", "run": ShopRules.tick},  # the shelves sell by days (v0.7.29)
			{"id": "study", "run": StudyRules.tick},  # misses and expulsions (v0.7.30)
			{"id": "crime", "run": CrimeRules.spread},  # a hidden body is found (v0.7.14)
			{"id": "rumors", "run": RumorRules.tick},  # rumours reach the neighbours with the fame and the wanted (v0.7.47)
			{"id": "letters", "run": LetterRules.tick},  # letters delivered or lost, helpers come, the arrested taken (v0.7.48)
			{"id": "things", "run": ThingRules.tick, "rules": "things"},  # fire takes doors and things, spreads, dies in the rain (v0.7.65)
			{"id": "layouts", "run": LayoutRules.tick},  # the map here is kept, a long rest wipes what was touched (v0.8.0)
		]
	return _hooks


## What passing time does now: the rows of the registry but those of each midnight.
static func hooks(s: GameSession, data: Dictionary) -> Array[String]:
	return _run(s, data, false)


static func _run(s: GameSession, data: Dictionary, each_day: bool) -> Array[String]:
	var lines: Array[String] = []
	for h: Dictionary in registry():
		if bool(h.get("each_day", false)) == each_day and (not h.has("rules") or data["rules"].has(str(h["rules"]))):
			lines.append_array((h["run"] as Callable).call(s, data))
	return lines


## The days a record missed since its `key` (v0.8.4.17: the one catch-up of every daily hook): each day after its own up
## to today, oldest first; the record now stands on today. A record without the key (or with 0) starts today, unless
## `from` names its first day.
static func missed(s: GameSession, rec: Dictionary, key: String = "last_day", from: int = -1) -> Array[int]:
	var last := int(rec.get(key, from if from >= 0 else s.day))
	if last <= 0:
		last = s.day
	rec[key] = s.day
	var out: Array[int] = []
	for d in range(last + 1, s.day + 1):
		out.append(d)
	return out


## Today's record under `key` of `holder` (v0.8.4.17: one «N times a day»): {day, n, …} of today, else {}; reading
## writes nothing. `make` starts today's record in the holder.
static func day_rec(s: GameSession, holder: Dictionary, key: String, make: bool = false) -> Dictionary:
	var r: Variant = holder.get(key)
	if r is Dictionary and int((r as Dictionary).get("day", -1)) == s.day:
		return r
	if not make:
		return {}
	holder[key] = {"day": s.day, "n": 0}
	return holder[key]


## How many times today, by `day_rec`.
static func today(s: GameSession, holder: Dictionary, key: String) -> int:
	return int(day_rec(s, holder, key).get("n", 0))


## One more time today; the count now.
static func count(s: GameSession, holder: Dictionary, key: String) -> int:
	var r := day_rec(s, holder, key, true)
	r["n"] = int(r["n"]) + 1
	return int(r["n"])


## The absolute minute of the game clock (since the first day's midnight).
static func abs_minute(s: GameSession) -> int:
	return s.clock


## The first minute of a day: a term in days as a moment of `until`.
static func day_start(day: int) -> int:
	return (day - 1) * 1440


## The day of an absolute minute.
static func day_of(minute: int) -> int:
	return minute / 1440 + 1


## Each full rules.hero_effects.exhaustion.awake_hours without a long rest: a CON save, DC awake_dc + awake_dc_step
## per day before; a failure — a level of exhaustion. Lines.
static func _awake(s: GameSession, data: Dictionary) -> Array[String]:
	var ex: Dictionary = data["rules"]["hero_effects"]["exhaustion"]
	var days := (abs_minute(s) - s.rested_at) / (int(ex["awake_hours"]) * 60)
	var lines: Array[String] = []
	while s.awake_saves < days:
		var dc := int(ex["awake_dc"]) + int(ex["awake_dc_step"]) * s.awake_saves
		s.awake_saves += 1
		var r := Sheet.save(s, data, Sheet.HERO, "con", dc)
		lines.append("Без сна %d ч: %s" % [s.awake_saves * int(ex["awake_hours"]), r["text"]])
		if not bool(r["ok"]):
			lines.append_array(ConditionRules.add_exhaustion(s, data, 1, "без сна"))
	return lines


## A step from room to room: rules.time.move_minutes, into another location — travel_minutes. The way counts towards
## the day's march (v0.7.8).
static func on_move(s: GameSession, data: Dictionary, from: String, to: String) -> Array[String]:
	var same := WorldView.new(data["world"]).location_id(from) == WorldView.new(data["world"]).location_id(to)
	var step := step_minutes(s, data, from, to)
	var minutes := int(step["minutes"])
	var wm := float(step["weather"])
	var lines: Array[String] = []
	if wm > 1.0:  # mud and snow (v0.7.46)
		lines.append("Дорога тяжела — %s: путь ×%s" % [WeatherRules.way_why(s, data, from, to), str(wm).trim_suffix(".0")])
	lines.append_array(advance(s, data, minutes))
	lines.append_array(march(s, data, minutes))
	if not same:
		lines.append_array(WeatherRules.on_way(s, data))  # the heat by day
	return lines


## The minutes of one step (v0.8.4.17: the one count for the step and the map's button): the way's own; into another
## location — an outlander's Wanderer (v0.7.11), riding (v0.7.27), mud and snow (v0.7.46). {minutes, weather}.
static func step_minutes(s: GameSession, data: Dictionary, from: String, to: String) -> Dictionary:
	var w := WorldView.new(data["world"])
	var minutes := WayRules.minutes(data, from, to)
	if w.location_id(from) == w.location_id(to):
		return {"minutes": minutes, "weather": 1.0}
	minutes = BackgroundRules.travel_minutes(s, data, minutes, to)
	minutes = roundi(minutes * minf(PropertyRules.travel_mult(s, data, from), PropertyRules.travel_mult(s, data, to)))
	var wm := WeatherRules.travel_mult(s, data, from, to)
	return {"minutes": roundi(minutes * wm) if wm > 1.0 else minutes, "weather": wm}


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
		var r := Sheet.save(s, data, Sheet.HERO, "con", int(ex["march_dc"]) + hour)
		lines.append("Марш %d ч за день: %s" % [int(ex["march_hours"]) + hour, r["text"]])
		if not bool(r["ok"]):
			lines.append_array(ConditionRules.add_exhaustion(s, data, 1, "марш"))
	return lines


static func shops_closed(s: GameSession, data: Dictionary) -> bool:
	return is_night(s, data) and bool(cfg(data).get("night_shops_closed", true))


## Darkvision (or Devil's Sight, v0.7.10), the Light spell or a light source among its things: SightRules. Anybody's.
static func can_see(s: GameSession, data: Dictionary, who: Dictionary = Sheet.HERO) -> bool:
	return SightRules.dark_sight(s, data, who) > 0 or SightRules.light(s, data, who) > 0


## No light of its own here: night outside a lit location, or a dark room of the pack (`dark` at a room or its location —
## a mine, a crypt, a burrow; v0.7.10).
static func unlit(s: GameSession, data: Dictionary) -> bool:
	var w := WorldView.new(data["world"])
	return w.flag(s.room_id, "dark") or (is_night(s, data) and not w.flag(s.room_id, "lit"))


## An unlit place without a way to see, for anybody (v0.8.4.12): the hero's light lights it for everybody.
static func dark(s: GameSession, data: Dictionary, who: Dictionary = Sheet.HERO) -> bool:
	return unlit(s, data) and not can_see(s, data, who) and not SightRules.lit(s, data)


## Passive Perception lost now: the hero's sneaking (−5), and for anybody darkness (disadvantage = −5) or the weather.
static func passive_penalty(s: GameSession, data: Dictionary, who: Dictionary = Sheet.HERO) -> int:
	var sneak := ExplorationRules.SNEAK_PASSIVE_PENALTY if Sheet.is_hero(who) and s.sneaking else 0
	return sneak + (5 if dark(s, data, who) else WeatherRules.passive(s, data))  # fog, a downpour (v0.7.46)


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

