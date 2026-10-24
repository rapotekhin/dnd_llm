extends GdUnitTestSuite
## The side panel 2.0 (roadmap v0.7.22.23, the UI audit С1, И2–И4, П4): a person is one row with the full name, the
## rest of the acts open under it by «▾» or the right button; the exits and the looks are pinned under the list; the
## lock of the description panel pins what is shown.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func after_test() -> void:
	GameState.session = null


func _rmb(c: Control) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_RIGHT
	ev.pressed = true
	c.gui_input.emit(ev)


func _panel(room: String) -> SidePanel:
	var s := TestUtils.new_session()
	for p: Dictionary in data["presets"]:
		if p["id"] == "fighter_aira":
			s.character = GameSession.normalized_character(CharacterBuilder.build_preset(p, data))
	CharacterRules.refresh(s.character, data, s.items)
	s.room_id = room
	GameState.session = s
	var panel := auto_free(SidePanel.new()) as SidePanel
	add_child(panel)
	return panel


func test_a_person_is_one_row_with_the_full_name() -> void:
	var panel := _panel("brod-tavern-hall")
	var talk := panel.find_child("Talk_npc_veteran", true, false) as Button
	assert_object(talk).is_not_null()
	assert_str(talk.text).is_equal(str(data["world"]["npcs"]["npc_veteran"]["name"]))  # not cut to the first word
	assert_object(panel.find_child("Trade_npc_innkeeper", true, false)).is_not_null()  # a trader's trade stays at hand
	assert_object(panel.find_child("Attack_npc_veteran", true, false)).is_null()  # the rest is closed
	(panel.find_child("More_npc_veteran", true, false) as Button).pressed.emit()
	await get_tree().process_frame
	var attack := panel.find_child("Attack_npc_veteran", true, false) as Button
	assert_object(attack).is_not_null()
	assert_object(panel.find_child("Pockets_npc_veteran", true, false)).is_not_null()
	assert_object(panel.find_child("Attack_npc_serving", true, false)).is_null()  # one row open at a time
	_rmb(panel.find_child("Talk_npc_serving", true, false) as Control)  # the right button opens another one
	await get_tree().process_frame
	assert_object(panel.find_child("Attack_npc_serving", true, false)).is_not_null()
	assert_object(panel.find_child("Attack_npc_veteran", true, false)).is_null()


func test_the_exits_and_looks_are_pinned_under_the_list() -> void:
	var panel := _panel("brod-tavern-hall")
	var footer := panel.find_child("SideFooter", true, false) as Control
	assert_object(footer.find_child("LookButton", true, false)).is_not_null()
	assert_object(footer.find_child("SneakToggle", true, false)).is_not_null()
	var exits := footer.find_children("Exit_*", "Button", true, false)
	assert_int(exits.size()).is_equal(ExplorationRules.open_exits(GameState.session, data["world"], "brod-tavern-hall").size())
	assert_object(panel.find_child("ExitsGrid", true, false)).is_null()


func test_a_creature_row_opens_its_acts() -> void:
	var panel := _panel("pushcha-hollow")
	var s := GameState.session
	EncounterRules.as_creatures(s, s.room_id, [{"monster": "goblin", "name": "Гоблин"}], "surrendered")
	EventBus.state_changed.emit()
	var cid := str(CreatureRules.here(s, s.room_id)[0]["id"])
	assert_object(panel.find_child("Creature_bind_" + cid, true, false)).is_null()
	_rmb(panel.find_child("CreatureLine_" + cid, true, false) as Control)
	await get_tree().process_frame
	assert_object(panel.find_child("Creature_bind_" + cid, true, false)).is_not_null()


func test_the_lock_pins_what_is_shown() -> void:
	var panel := auto_free(DetailsPanel.new()) as DetailsPanel
	var lock := panel.find_child("DetailsUnpin", true, false) as Button
	assert_bool(lock.visible).is_false()  # the hint is nothing to pin
	var a := auto_free(Button.new()) as Button
	var b := auto_free(Button.new()) as Button
	panel.hook(a, "Щит", "КД +5")
	panel.hook(b, "Огненный снаряд", "1к10 огня")
	a.mouse_entered.emit()
	assert_bool(lock.visible).is_true()
	lock.pressed.emit()
	assert_str(panel.pinned()).is_equal("Щит")
	assert_bool(a.modulate == Color.WHITE).is_false()  # the pinned row is lit
	b.mouse_entered.emit()
	assert_str(panel.title()).is_equal("Щит")
	lock.pressed.emit()
	assert_str(panel.pinned()).is_empty()
