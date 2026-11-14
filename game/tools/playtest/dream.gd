extends "res://tools/playtest/playtest_base.gd"
## The tutorial's dream (python tools/godot_playtest.py --scenario dream), v0.8.4.44.2: «Обучение» on the new game screen,
## on for a fresh profile; the dream world not in the list; the hero wakes in the cave with no things; the halls lead only
## onwards; in the last one the words of waking and «Проснуться» — a new game in Brod from the same choices with its
## kit; the next new game has «Обучение» off.


func run() -> void:
	var gs := node("GameState")
	var sm := node("SaveManager")
	sm.tutorial_done = false
	if not step("master connected", await wait_until(func() -> bool: return node("Backend").is_ready(), 30.0)):
		return
	await tap("NewGameButton")
	await frames(3)
	var tick: CheckButton = find(screen(), "TutorialToggle")
	step("«Обучение» is there and on", tick != null and tick.visible and tick.button_pressed)
	step("the dream is no world to pick", find(screen(), "World_tutorial") == null and find(screen(), "World_frontier") != null)
	await shot("new_game_tutorial")
	await tap("NextButton")
	await tap("Preset_wizard_yalika")
	await press(find(screen(), "StartButton"))
	if not step("the dream began", await wait_until(func() -> bool: return screen_is("GameScreen") and not gs.is_busy(), 90.0)):
		return
	var s: GameSession = gs.session
	step("in the first hall of the dream", s.world_id == "tutorial" and s.room_id == "dream-1", "%s / %s" % [s.world_id, s.room_id])
	step("with no things and no coins", (s.character["inventory"] as Dictionary).is_empty() and int(s.character.get("gold_cp", 0)) == 0, str(s.character["inventory"]))
	step("with the wizard's spells", not (s.character["spells"]["cantrips"] as Array).is_empty(), str(s.character["spells"]["cantrips"]))
	await shot("dream_hall_1")
	for i in range(2, 8):
		await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
		var back := WayRules.open_exits(s, node("Catalog").data["world"], s.room_id)
		step("hall %d leads only onwards" % (i - 1), back == ["dream-%d" % i], str(back))
		step("walked into hall %d" % i, gs.go("dream-%d" % i))
		await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
		await frames(3)
	await wait_until(func() -> bool: return not find_all(get_root(), "WakeBox").is_empty(), 20.0)  # a lambda keeps no outer local
	var boxes := find_all(get_root(), "WakeBox")
	var wake: Control = boxes[0] as Control if not boxes.is_empty() else null
	step("the words of waking in the last hall", wake != null and (find(wake, "WakeText") as Label).text.contains("Пепел над Маркой"))
	step("no «✕» on it", wake != null and not (find(wake, "CloseX") as Control).visible)
	await shot("dream_wake")
	await press(find(wake, "WakeButton"))
	if not step("woke into the world", await wait_until(func() -> bool: return gs.session != s and screen_is("GameScreen") and not gs.is_busy(), 90.0)):
		return
	var w: GameSession = gs.session
	step("in Brod's tavern, level 1, with its kit", w.world_id == "frontier" and w.room_id == str(node("Catalog").data["world"]["start_room"])
		and int(w.character["level"]) == 1 and not (w.character["inventory"] as Dictionary).is_empty(), "%s / %s" % [w.world_id, w.room_id])
	step("nothing of the dream", w.dream.is_empty() and not w.visited.has("dream-1"))
	step("the profile remembers the tutorial", sm.tutorial_done)
	await shot("woke_in_brod")
	gs.close_session()
	node("EventBus").navigate.emit("new_game", {})
	await frames(5)
	tick = find(screen(), "TutorialToggle")
	step("the next new game has «Обучение» off", tick != null and tick.visible and not tick.button_pressed)
	await shot("new_game_after")
	sm.tutorial_done = false
	sm.save_settings()
