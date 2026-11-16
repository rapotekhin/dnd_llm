extends GdUnitTestSuite
## v0.8.4.44.10, the author: «на кнопку Tab как в BG3 … открывались одновременно в ряд инвентари всех спутников и
## игрока для удобного перемещения предметов между инвентарями». The party window: a column for the hero and each
## follower, a thing handed between any two of them by Equip.hand (the «Снаряжение» window's rules), the load and its most
## of anybody by Sheet.

var data: Dictionary
var kept: GameSession


func before() -> void:
	data = TestUtils.data()


func before_test() -> void:
	kept = GameState.session
	GameState.session = _party()


func after_test() -> void:
	GameState.session = kept


func _party() -> GameSession:
	var s := TestUtils.new_session()
	s.minute = 720
	for p: Dictionary in data["presets"]:
		if p["id"] == "fighter_aira":
			s.character = GameSession.normalized_character(CharacterBuilder.build_preset(p, data))
	CharacterRules.refresh(s.character, data, s.items)
	s.room_id = "brod-square"
	Being.follow(s, "npc_mercenary")
	Being.follow(s, "npc_veteran")
	return s


func _has(s: GameSession, who: String, item: String) -> int:
	return int(Gear.of(s, data, who).get("inventory", {}).get(item, 0))


func test_the_columns_are_the_hero_and_its_followers() -> void:
	var s := GameState.session
	assert_array(PartyPanel.members(s, data)).is_equal([Being.HERO, "npc_mercenary", "npc_veteran"])


func test_a_stack_goes_from_the_hero_to_a_companion_and_back() -> void:
	var s := GameState.session
	ItemRules.add(s.character, "torch", 5)
	var mine := _has(s, Being.HERO, "torch")
	var had := _has(s, "npc_mercenary", "torch")
	assert_str(GameState.item_act({"act": "give", "item": "torch", "to": "npc_mercenary", "qty": 3}, Being.HERO)).is_empty()
	assert_int(_has(s, Being.HERO, "torch")).is_equal(mine - 3)
	assert_int(_has(s, "npc_mercenary", "torch")).is_equal(had + 3)
	assert_str(GameState.item_act({"act": "give", "item": "torch", "to": Being.HERO, "qty": 1}, "npc_mercenary")).is_empty()
	assert_int(_has(s, Being.HERO, "torch")).is_equal(mine - 2)


func test_one_companion_hands_a_thing_to_another() -> void:
	var s := GameState.session
	ItemRules.add(Gear.of(s, data, "npc_mercenary"), "rope", 1)
	var had := _has(s, "npc_veteran", "rope")
	assert_str(Equip.hand_why(s, data, "npc_mercenary", "npc_veteran", "rope")).is_empty()
	assert_str(GameState.item_act({"act": "give", "item": "rope", "to": "npc_veteran", "qty": 1}, "npc_mercenary")).is_empty()
	assert_int(_has(s, "npc_mercenary", "rope")).is_equal(0)
	assert_int(_has(s, "npc_veteran", "rope")).is_equal(had + 1)


func test_nothing_goes_to_a_stranger_to_oneself_or_in_a_fight() -> void:
	var s := GameState.session
	ItemRules.add(s.character, "torch", 1)
	assert_str(Equip.hand_why(s, data, Being.HERO, "npc_merchant", "torch")).is_equal("GEAR_NOT_FOLLOWER")
	assert_str(Equip.hand_why(s, data, Being.HERO, Being.HERO, "torch")).is_equal("GEAR_NOT_FOLLOWER")
	assert_str(Equip.hand_why(s, data, Being.HERO, "npc_mercenary", "dagger_none")).is_equal("EQUIP_NOT_OWNED")
	TestUtils.fight(s, data, [{"monster": "goblin", "col": 4}])
	assert_str(Equip.hand_why(s, data, Being.HERO, "npc_mercenary", "torch")).is_equal("GEAR_NOT_IN_COMBAT")


func test_the_load_and_its_most_of_anybody_by_one_count() -> void:
	var s := GameState.session
	assert_int(Sheet.capacity(s, data, Sheet.HERO)).is_equal(CharacterRules.capacity(s.character, data))
	var who := Sheet.who(s, data, "npc_mercenary")
	var per := int(data["rules"].get("carry", {}).get("per_str", 15))
	assert_int(Sheet.capacity(s, data, who)).is_equal(Sheet.ability(s, data, who, "str") * per)
	Gear.of(s, data, "npc_mercenary")  # its pockets filled first, as the window does
	var before := Sheet.carried(s, data, who)
	ItemRules.add(Gear.of(s, data, "npc_mercenary"), "torch", 2)
	assert_float(Sheet.carried(s, data, who)).is_equal_approx(before + 2.0 * float(ItemRules.def_of(data["items"], s.items, "torch").get("weight", 0)), 0.01)


func test_the_window_shows_a_column_each_and_a_drop_hands_over() -> void:
	var s := GameState.session
	s.character["inventory"].erase("rope")
	ItemRules.add(s.character, "rope", 4)
	var w := auto_free(UiScenes.open(PartyPanel.SCENE)) as PartyPanel
	add_child(w)
	assert_str(w.open()).is_empty()
	for id: String in [Being.HERO, "npc_mercenary", "npc_veteran"]:
		assert_object(w.find_child("PartyCol_" + id, true, false)).is_not_null()
		assert_object(w.find_child("PartyWeight_" + id, true, false)).is_not_null()
	assert_object(w.grid_of(Being.HERO).find_child("PartyItem_p_rope", true, false)).is_not_null()
	var had := _has(s, "npc_veteran", "rope")
	w.give(Being.HERO, "npc_veteran", "rope", 4)  # the whole stack: no slider without `ask`
	assert_int(_has(s, "npc_veteran", "rope")).is_equal(had + 4)
	assert_int(_has(s, Being.HERO, "rope")).is_equal(0)
	assert_object(w.grid_of("npc_veteran").find_child("PartyItem_npc_veteran_rope", true, false)).is_not_null()


func test_the_window_does_not_open_in_a_fight() -> void:
	var s := GameState.session
	TestUtils.fight(s, data, [{"monster": "goblin", "col": 4}])
	var w := auto_free(UiScenes.open(PartyPanel.SCENE)) as PartyPanel
	add_child(w)
	w.visible = false
	assert_str(w.open()).is_equal("GEAR_NOT_IN_COMBAT")
	assert_bool(w.visible).is_false()
