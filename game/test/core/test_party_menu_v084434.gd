extends GdUnitTestSuite
## The left column and the map's menu as in BG3 (roadmap v0.8.4.43.4, the author): the hero and its companions are
## portraits — the ring of HP, the AC on a shield, statuses and needs as icons, coins and experience at the cursor; the
## people the map draws are not listed; a person, a thing or a foe has one menu, a list with lists inside, read off its
## buttons, and the left button presses its main act.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func after_test() -> void:
	GameState.session = null


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


func test_the_hero_is_a_portrait_with_its_numbers_at_the_cursor() -> void:
	var panel := _panel("brod-tavern-hall")
	var s := GameState.session
	var p := panel.find_child("Portrait_hero", true, false) as Portrait
	assert_object(p).is_not_null()
	assert_int(p.hp).is_equal(int(s.character["hp"]))
	assert_int(p.ac).is_equal(int(s.character["ac"]))
	assert_str(p.tip_body).contains(Money.format(Ledger.balance(s)))
	assert_str(p.tip_body).contains("опыт")
	assert_object(panel.find_child("HeroHp", true, false)).is_null()  # no line of numbers: the portrait and its card
	assert_object(panel.find_child("HeroBar", true, false)).is_not_null()
	await get_tree().process_frame  # the rebuilt rows freed


func test_statuses_and_needs_are_icons() -> void:
	var panel := _panel("brod-tavern-hall")
	var s := GameState.session
	ConditionRules.add_effect(s.character, {"condition": "poisoned", "ends": ConditionRules.ends_for(s, data, "hour"),
		"source": {"kind": "master", "name": "яд в кружке"}})
	EventBus.state_changed.emit()
	var chip := panel.find_child("Chip_poisoned", true, false) as IconSlot
	assert_object(chip).is_not_null()
	assert_str(chip.tip_title).is_equal(ConditionRules.name_of(data, "poisoned"))
	assert_str(chip.tip_body).contains("яд в кружке")
	assert_str(str(chip.spec["ref"])).is_equal("conditions/poisoned")
	var food := panel.find_child("Need_food", true, false) as IconSlot
	assert_object(food).is_not_null()
	assert_float(food.meter).is_between(0.0, 1.0)
	await get_tree().process_frame  # the rebuilt rows freed


func test_a_follower_is_a_portrait_not_a_row() -> void:
	var panel := _panel("brod-tavern-hall")
	Being.follow(GameState.session, "npc_veteran")
	EventBus.state_changed.emit()
	assert_object(panel.find_child("Portrait_npc_veteran", true, false)).is_not_null()
	assert_object(panel.find_child("More_npc_veteran", true, false)).is_null()
	assert_object(panel.find_child("More_npc_serving", true, false)).is_not_null()  # the others stay listed without a map
	await get_tree().process_frame  # the rebuilt rows freed


func test_the_people_the_map_draws_are_not_listed() -> void:
	var panel := _panel("brod-tavern-hall")
	panel.seen = func(ref: String) -> bool: return ref == "npc:npc_veteran"
	panel.refresh()
	assert_object(panel.find_child("More_npc_veteran", true, false)).is_null()
	assert_object(panel.find_child("More_npc_serving", true, false)).is_not_null()
	await get_tree().process_frame  # the rebuilt rows freed


func test_a_persons_menu_is_a_list_with_lists_inside() -> void:
	var panel := _panel("brod-tavern-hall")
	var box := auto_free(VBoxContainer.new()) as VBoxContainer
	add_child(box)
	assert_bool(panel.menu(box, "npc:npc_innkeeper")).is_true()
	assert_object(SidePanel.main_of(box, "npc:npc_innkeeper")).is_null()  # no master on the line: grey, the menu opens instead
	var talk := box.find_child("Talk_npc_innkeeper", true, false) as Button
	talk.disabled = false
	var main := SidePanel.main_of(box, "npc:npc_innkeeper")
	assert_object(main).is_same(talk)
	var m := auto_free(ActsMenu.of(box)) as ActsMenu
	assert_bool(m.is_item_separator(0)).is_true()
	assert_str(m.get_item_text(0)).is_equal(str(data["world"]["npcs"]["npc_innkeeper"]["name"]))
	var subs := m.find_children("List_*", "PopupMenu", false, false)
	assert_int(subs.size()).is_greater(0)  # the groups of its acts as lists
	var last := m.buttons()[m.buttons().size() - 1]
	assert_str(str(last.name)).is_equal("Attack_npc_innkeeper")  # the red act last, apart
	var pressed := [false]
	main.pressed.connect(func() -> void: pressed[0] = true)
	m.id_pressed.emit(m.id_of(main))
	assert_bool(pressed[0]).is_true()
	await get_tree().process_frame  # the rebuilt rows freed


func test_a_things_menu_reads_its_acts() -> void:
	var panel := _panel("brod-tavern-hall")
	var s := GameState.session
	PropRules.ensure(s, data, s.room_id)
	var p: Dictionary = PropRules.room_props(s, s.room_id)[0]
	var box := auto_free(VBoxContainer.new()) as VBoxContainer
	add_child(box)
	assert_bool(panel.menu(box, "prop:" + str(p["id"]))).is_true()
	assert_object(box.find_child("Prop_look_" + str(p["id"]), true, false)).is_not_null()
	var acts := PropRules.acts(s, data, p).map(func(a: Dictionary) -> String: return str(a["act"]))
	assert_array(acts).contains(["look"])
	await get_tree().process_frame  # the rebuilt rows freed


func test_a_refresh_lays_the_worn_and_born_statuses_with_their_uids() -> void:  # a save loads the same (the bot, v0.8.4.43.4)
	var s := TestUtils.new_session()
	for p: Dictionary in data["presets"]:
		if p["id"] == "wizard_yalika":
			s.character = GameSession.normalized_character(CharacterBuilder.build_preset(p, data))
	CharacterRules.refresh(s.character, data, s.items)
	var before := JSON.stringify(s.character["effects"]) + str(s.character.get("next_effect", 0))
	assert_bool(ConditionRules.effects(s.character).any(func(e: Dictionary) -> bool: return str(e["source"].get("kind", "")) == ItemRules.BORN)).is_true()
	CharacterRules.refresh(s.character, data, s.items)
	CharacterRules.refresh(s.character, data, s.items)
	assert_str(JSON.stringify(s.character["effects"]) + str(s.character.get("next_effect", 0))).is_equal(before)

