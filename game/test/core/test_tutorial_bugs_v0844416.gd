extends GdUnitTestSuite
## v0.8.4.44.16, the author's tutorial notes of 2026-11-17: «Волшебная рука должна призывать суммона», «во время боя можно
## покинуть комнату и объекты там теряют свой ассет».

var data: Dictionary


func before() -> void:
	data = TestUtils.data()


func _session() -> GameSession:
	var s := TestUtils.new_session()
	for p: Dictionary in data["presets"]:
		if p["id"] == "fighter_aira":
			s.character = GameSession.normalized_character(CharacterBuilder.build_preset(p, data))
	CharacterRules.refresh(s.character, data, s.items)
	s.room_id = "brod-square"
	return s


func test_mage_hand_calls_a_spectral_hand_that_helps_and_never_strikes() -> void:
	assert_str(ActionRules.way(data, "mage_hand", false)).is_equal("summon")
	assert_dict(data["monsters"]["spectral_hand"]).is_not_empty()
	assert_array(data["monsters"]["spectral_hand"]["actions"]).is_empty()
	var s := _session()
	var lines := AllyRules.summon(s, data, "mage_hand")
	assert_str(str(lines)).contains("Призрачная рука")
	var hands := AllyRules.called(s).filter(func(m: Dictionary) -> bool: return str(m["spell"]) == "mage_hand")
	assert_int(hands.size()).is_equal(1)
	assert_bool(bool(hands[0]["helper"])).is_true()
	AllyRules.summon(s, data, "mage_hand")  # cast again: still one hand
	assert_int(AllyRules.called(s).filter(func(m: Dictionary) -> bool: return str(m["spell"]) == "mage_hand").size()).is_equal(1)


func test_mage_hand_in_a_fight_joins_the_heros_side() -> void:
	var s := _session()
	CombatRules.start(s, data, [{"monster": "wolf"}])
	AllyRules.summon(s, data, "mage_hand")
	var hand := CombatRules.allies(s).map(func(id: String) -> Dictionary: return CombatRules.fighter(s, id)) \
		.filter(func(f: Dictionary) -> bool: return str(f.get("monster", "")) == "spectral_hand")
	assert_int(hand.size()).is_equal(1)
	assert_bool(bool(hand[0].get("helper", false))).is_true()


func test_a_fight_is_left_by_its_own_way_out_not_a_rooms_exit() -> void:
	var s := _session()
	var to := str(WayRules.open_exits(s, data["world"], s.room_id)[0])
	assert_str(WayRules.leave_why(s, data, s.room_id, to)).is_not_equal("LEAVE_IN_FIGHT")
	CombatRules.start(s, data, [{"monster": "wolf"}])
	assert_str(WayRules.leave_why(s, data, s.room_id, to)).is_equal("LEAVE_IN_FIGHT")
