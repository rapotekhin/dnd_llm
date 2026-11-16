extends "res://tools/playtest/playtest_base.gd"
## One search (python tools/godot_playtest.py --scenario one_search), v0.8.4.44.9, the author's decision for the tutorial:
## one button «Осмотреться» — the master's description and a Perception check that finds what is hidden too.
## In the tavern's cellar Aira (passive Perception 13) notices the tracks on entering and not the tunnel (`passive: false`);
## «Осмотреться» is a Perception card, takes its minutes and finds the tunnel on a total of 15; no «Обыскать» beside it.


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
	step("«Осмотреться» says it is Perception", look != null and look.tooltip_text.contains("Внимательности"), look.tooltip_text if look != null else "")
	step("no «Обыскать» beside it", find(screen(), "SearchButton") == null)
	var checks := func() -> int: return s.chat.filter(func(e: Dictionary) -> bool: return e["kind"] == GameSession.KIND_CHECK).size()
	var before: int = checks.call()
	var m0 := TimeRules.abs_minute(s)
	s.character["skills"]["perception"] = 30  # the total passes the tunnel's DC 15 unless the die is a 1: a seed with no 1
	for seed_try in range(1, 200):
		var probe := RandomNumberGenerator.new()
		probe.seed = seed_try
		if probe.randi_range(1, 20) != 1:
			s.rng.seed = seed_try
			break
	await press(look)
	await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
	await frames(3)
	var cards: Array = s.chat.filter(func(e: Dictionary) -> bool: return e["kind"] == GameSession.KIND_CHECK)
	var card: Dictionary = cards[before] if cards.size() > before else {}  # the button's own card (the stub master rolls again)
	step("the search is a Perception card", str(card.get("skill", "")) == "perception", str(card))
	step("the search took its minutes", TimeRules.abs_minute(s) - m0 >= int(TimeRules.cfg(data)["search_minutes"]), "%d мин" % (TimeRules.abs_minute(s) - m0))
	step("the search found the tunnel", Knows.has(s, Knows.SECRET, "brod-tavern-cellar", "tunnel"), str(card.get("revealed", [])))
	await shot("search_found")
