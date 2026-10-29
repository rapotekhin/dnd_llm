extends "res://tools/playtest/playtest_base.gd"
## Weather (python tools/godot_playtest.py --scenario weather), v0.7.46: the weather of the day on the panel under the
## date; fog on the square — Perception with disadvantage; under the tavern's roof the hero is out of it; a downpour
## in the Pushcha — the way through the mud longer, the ford to the glade greyed with why, a camp soaked; a night in
## frost without a fire — a CON save against exhaustion; the river in the rain gives more fish.

const SAY := "Осматриваюсь по сторонам: кто здесь есть?"


func run() -> void:
	var gs := node("GameState")
	if not step("master connected", await wait_until(func() -> bool: return node("Backend").is_ready(), 30.0)):
		return
	await tap("NewGameButton")
	await tap("NextButton")
	await tap("Preset_fighter_aira")
	await press(find(screen(), "StartButton"))
	if not step("game started", await wait_until(func() -> bool: return screen_is("GameScreen") and not gs.is_busy(), 90.0)):
		return
	var s: GameSession = gs.session
	var data: Dictionary = node("Catalog").data
	var c := s.character
	s.settings["needs"] = false
	s.settings["weather"] = true
	s.minute = 12 * 60
	var line: Label = find(screen(), "WeatherLine")
	step("the weather of the day on the panel", line != null and line.text.begins_with("Погода:") and line.text.contains("под крышей"), line.text if line != null else "")
	step("info: the day's weather", true, ", ".join(["brod", "pushcha", "outpost"].map(func(l: String) -> String: return "%s: %s" % [l, WeatherRules.at(s, data, l)])))

	_weather(s, data, "brod", "fog")
	await _go(gs, "brod-square")
	line = find(screen(), "WeatherLine")
	step("fog on the square", line != null and line.text.contains("туман") and line.tooltip_text.contains("помеха"), line.tooltip_text if line != null else "")
	gs.call("_engine_check", {"skill": "perception", "dc_tier": "medium"})
	var card: Dictionary = s.chat.filter(func(e: Dictionary) -> bool: return e["kind"] == GameSession.KIND_CHECK).back()
	step("Perception in the fog — with disadvantage", str(card.get("disadvantage_reason", "")).contains("туман"), str(card.get("disadvantage_reason", "")))
	node("EventBus").state_changed.emit()
	await frames(3)
	await shot("weather_fog_square")

	_weather(s, data, "pushcha", "downpour")
	await _go(gs, "brod-gate")
	var m0 := TimeRules.abs_minute(s)
	await _go(gs, "pushcha-edge")
	var took := TimeRules.abs_minute(s) - m0
	step("the way through the mud is longer", took >= roundi(int(data["rules"]["time"]["travel_minutes"]) * 1.5), "%d мин" % took)
	s.encounters_done.append("trail_wolves")  # the trail's wolves are another playtest's
	await _go(gs, "pushcha-trail")
	node("EventBus").state_changed.emit()
	await frames(3)
	var ford: Button = find(screen(), "Exit_pushcha-glade")
	step("the ford to the glade greyed with why", ford != null and ford.disabled and ford.tooltip_text.contains("брод"), ford.tooltip_text if ford != null else "")
	await shot("weather_ford_flooded")

	c["inventory"]["rations"] = 6
	c["inventory"].erase("tent_two_person")
	c["hp"] = maxi(1, int(c["max_hp"]) - 5)
	var err: String = gs.long_rest(ExplorationRules.camp_default(c, data))
	step("a camp in the downpour", err.is_empty(), err)
	await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
	var fx := _last_effects(s)
	step("the downpour soaked the camp", fx.contains("промок"), fx)
	await shot("weather_camp_soaked")

	_weather(s, data, "pushcha", "frost")
	c["inventory"].erase("tinderbox")
	c["inventory"].erase("blanket")
	c["inventory"].erase("winter_clothes")
	s.minute = 21 * 60
	err = gs.long_rest(ExplorationRules.camp_default(c, data))
	await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
	fx = _last_effects(s)
	step("a night in frost without a fire asks a CON save", fx.contains("без защиты") and fx.contains("Тел"), fx)
	await shot("weather_frost_night")
	_weather(s, data, "pushcha", "clear")
	node("EventBus").state_changed.emit()
	await frames(3)
	ford = find(screen(), "Exit_pushcha-glade")
	step("the water fell — the ford is open", ford != null and not ford.disabled)


func _weather(s: GameSession, data: Dictionary, loc: String, k: String) -> void:
	WeatherRules._state(s)["by_loc"][loc] = k
	WeatherRules._flags(s, data)


func _last_effects(s: GameSession) -> String:
	var fx: Array = s.chat.filter(func(e: Dictionary) -> bool: return e["kind"] == GameSession.KIND_EFFECT)
	return str(fx.back().get("text", fx.back())) if not fx.is_empty() else ""


func _go(gs: Node, to: String) -> void:
	await wait_until(func() -> bool: return not gs.is_busy(), 30.0)
	step("walked to %s" % to, gs.go(to))
	await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
	await frames(3)
