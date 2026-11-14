extends "res://tools/playtest/playtest_base.gd"
## One search (python tools/godot_playtest.py --scenario one_search), v0.8.4.44, the author's decision for the tutorial:
## «Осмотреться» is the master's description with no check, «Обыскать» rolls Perception and finds what is hidden too.
## In the tavern's cellar Aira (passive Perception 13) notices the tracks on entering and not the tunnel (`passive: false`);
## the look asks no roll; the search is a Perception card, takes its minutes and finds the tunnel on a total of 15.


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
	var seen := ExplorationRules.enter_room(s, data["world"], "brod-tavern-cellar")
	node("EventBus").state_changed.emit()
	await frames(4)
	step("the tracks noticed on entering, the tunnel not", seen.size() == 1 and str(seen[0]).contains("след")
		and not Knows.has(s, Knows.SECRET, "brod-tavern-cellar", "tunnel"), ", ".join(seen))
	var look: Button = find(screen(), "LookButton")
	var search: Button = find(screen(), "SearchButton")
	step("«Осмотреться» says it asks no check", look != null and look.tooltip_text.contains("Без проверки"), look.tooltip_text if look != null else "")
	step("«Обыскать» says it is Perception", search != null and search.tooltip_text.contains("Внимательности"), search.tooltip_text if search != null else "")
	var checks := func() -> int: return s.chat.filter(func(e: Dictionary) -> bool: return e["kind"] == GameSession.KIND_CHECK).size()
	var before: int = checks.call()
	var m0 := TimeRules.abs_minute(s)
	await press(look)
	await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
	await frames(3)
	step("the look rolled nothing and took no time", checks.call() == before and TimeRules.abs_minute(s) == m0, "%d → %d" % [before, checks.call()])
	await shot("look_no_check")
	s.character["skills"]["perception"] = 30  # the total passes the tunnel's DC 15 unless the die is a 1: a seed with no 1
	for seed_try in range(1, 200):
		var probe := RandomNumberGenerator.new()
		probe.seed = seed_try
		if probe.randi_range(1, 20) != 1:
			s.rng.seed = seed_try
			break
	await press(find(screen(), "SearchButton"))  # the panel was laid anew after the turn
	await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
	await frames(3)
	var cards: Array = s.chat.filter(func(e: Dictionary) -> bool: return e["kind"] == GameSession.KIND_CHECK)
	var card: Dictionary = cards[before] if cards.size() > before else {}  # the button's own card (the stub master rolls again)
	step("the search is a Perception card", str(card.get("skill", "")) == "perception", str(card))
	step("the search took its minutes", TimeRules.abs_minute(s) - m0 >= int(TimeRules.cfg(data)["search_minutes"]), "%d мин" % (TimeRules.abs_minute(s) - m0))
	step("the search found the tunnel", Knows.has(s, Knows.SECRET, "brod-tavern-cellar", "tunnel"), str(card.get("revealed", [])))
	await shot("search_found")
