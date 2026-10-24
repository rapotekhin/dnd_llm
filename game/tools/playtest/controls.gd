extends "res://tools/playtest/playtest_base.gd"
## Safety and keyboard (python tools/godot_playtest.py --scenario controls), v0.7.22.27: Esc leaves the input, C / K / I
## open the sheet's tabs, M and J toggle the map and the journal; «Напасть» asks first and «Отмена» does nothing;
## F5 saves to the quick slot and F9 loads it; in the fight Tab picks a foe and Space ends the turn.


func _key(code: Key, unicode: int = 0) -> void:
	for down: bool in [true, false]:
		var ev := InputEventKey.new()
		ev.physical_keycode = code
		ev.keycode = code
		ev.unicode = unicode if down else 0
		ev.pressed = down
		root.push_input(ev)
	await frames(3)


func run() -> void:
	var gs := node("GameState")
	var saves := node("SaveManager")
	if not step("master connected", await wait_until(func() -> bool: return node("Backend").is_ready(), 30.0)):
		return
	await tap("NewGameButton")
	await tap("NextButton")
	await tap("Preset_fighter_aira")
	await press(find(screen(), "StartButton"))
	if not step("game started", await wait_until(func() -> bool: return screen_is("GameScreen") and not gs.is_busy(), 60.0)):
		return
	var s: GameSession = gs.session
	s.room_id = "brod-tavern-hall"
	node("EventBus").state_changed.emit()
	await frames(3)
	var game := screen()
	var input: LineEdit = game.get("input")
	input.grab_focus()
	await frames(2)
	await _key(KEY_ESCAPE)
	step("Esc leaves the input, no pause", not input.has_focus() and not (game.get("_pause") as Control).visible)
	var sheet: Control = find(game, "CharacterSheet")
	await _key(KEY_C)
	step("C — the character", sheet.visible and int(sheet.call("current_tab")) == 0)
	await _key(KEY_K)
	step("K — the spells", sheet.visible and int(sheet.call("current_tab")) == 1)
	await _key(KEY_I)
	step("I — the inventory", sheet.visible and int(sheet.call("current_tab")) == 2)
	await shot("inventory_by_key")
	await _key(KEY_I)
	step("I again closes it", not sheet.visible)
	var map: Control = find(game, "MapView")
	var journal: Control = find(game, "JournalView")
	await _key(KEY_M)
	step("M — the map", map != null and map.visible)
	await _key(KEY_M)
	await _key(KEY_J)
	step("M closes the map, J — the journal", not map.visible and journal.visible)
	await _key(KEY_J)
	step("J closes it", not journal.visible)
	await _key(KEY_H, "р".unicode_at(0))
	step("a letter without a hotkey goes into the input", input.has_focus() and input.text == "р", input.text)
	input.clear()
	await _key(KEY_ESCAPE)

	# The question before «Напасть».
	saves.confirm_risky = true
	var data: Dictionary = node("Catalog").data
	var here := s.npcs_here(data["world"], s.room_id)
	var first := "npc_serving" if here.has("npc_serving") else str(here[0])
	await open_row("More_" + first)
	await press(find(game, "Attack_" + first))
	var box := root.get_node_or_null("ConfirmBox")
	step("«Напасть» asks first", box != null)
	if box != null:
		step("«Больше не показывать» is off", not (find(box, "NeverAsk") as CheckBox).button_pressed)
		await shot("confirm_attack")
		await press(find(box, "ConfirmNo"))
		await frames(3)
	step("«Отмена» — no fight, the question stays on", screen_is("GameScreen") and s.combat.is_empty() and saves.confirm_risky)

	# F5 / F9.
	await _key(KEY_F5)
	step("F5 — the quick slot saved", await wait_until(func() -> bool: return saves.has_slot(saves.QUICKSAVE), 5.0))
	var minute := s.minute
	s.minute += 300
	await _key(KEY_F9)
	var back := await wait_until(func() -> bool: return gs.session != s and screen_is("GameScreen") and not gs.is_busy(), 30.0)
	step("F9 — the quick slot loaded", back and gs.session.minute == minute, "%d → %d" % [minute, gs.session.minute if gs.session else -1])
	await shot("quick_loaded")

	# The fight by the keys.
	saves.confirm_risky = false
	s = gs.session
	s.room_id = "brod-tavern-hall"
	node("EventBus").state_changed.emit()
	await frames(3)
	await open_row("More_" + first)
	await press(find(screen(), "Attack_" + first))
	if not step("the fight", await wait_until(func() -> bool: return screen_is("CombatScreen") and not gs.is_busy(), 60.0)):
		return
	await frames(3)
	await _key(KEY_TAB)
	var focus := root.gui_get_focus_owner()
	step("Tab — a foe's card", focus != null and str(focus.name).begins_with("Foe_"), str(focus.name) if focus else "")
	await shot("tab_target")
	var round := int(s.combat.get("round", 1))
	await _key(KEY_SPACE)
	var passed := await wait_until(func() -> bool: return s.combat.is_empty() or int(s.combat.get("round", 1)) > round, 30.0)
	step("Space ends the turn", passed, str(s.combat.get("round", "")))
