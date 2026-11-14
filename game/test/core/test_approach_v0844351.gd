extends GdUnitTestSuite
## v0.8.4.43.51, the author: «когда я выбрал атаку в рукопашную при наведении курсора на врага мне показывался пунктиром
## путь куда мой персонаж пойдёт и как, чтобы ударить врага». A blow out of reach walks up first: `Acts.approach` finds the
## cheapest stop of this turn's walk the act's own `can` lets it from, `Acts.near_why` counts it, GameState gives the way.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func after_test() -> void:
	GameState.session = null


func _fight(foes: Array) -> GameSession:
	var s := TestUtils.new_session()
	for p: Dictionary in data["presets"]:
		if p["id"] == "fighter_aira":
			s.character = GameSession.normalized_character(CharacterBuilder.build_preset(p, data))
	CharacterRules.refresh(s.character, data)
	TestUtils.fight(s, data, foes)
	var order: Array = s.combat["order"]
	order.erase(CombatRules.PLAYER)
	order.push_front(CombatRules.PLAYER)
	s.combat["turn"] = 0
	CombatRules._begin_turn(s, data, [] as Array[String])
	return s


func test_a_blow_out_of_reach_walks_up_to_the_nearest_square_it_strikes_from() -> void:
	var s := _fight([{"monster": "goblin", "col": 1}])  # six squares off: a walk of 30 ft brings it in
	var hero := CombatRules.player(s)
	var foe := TestUtils.foe(s, 1)
	assert_str(Acts.one("attack").can(s, data, hero, foe)).is_equal("COMBAT_OUT_OF_REACH")
	assert_str(Acts.near_why(s, data, hero, "attack", foe)).is_empty()
	var way := Acts.approach(s, data, hero, "attack", foe)
	assert_bool(way.is_empty()).is_false()
	var ghost := hero.duplicate()
	FightGrid.put(ghost, way[-1])
	assert_bool(FightGrid.touching(ghost, CombatRules.fighter(s, foe))).is_true()
	var routes := Move.routes(s, data, hero)
	for at: Vector2i in FightGrid.stops(s, data, hero, routes):  # no stop of fewer feet strikes it
		if int(routes[at][0]) < int(routes[way[-1]][0]):
			FightGrid.put(ghost, at)
			assert_str(Acts.one("attack").can(s, data, ghost, foe)).is_not_empty()
	Acts.one("walk").go(s, data, hero, FightGrid.aim_id(way[-1]))  # as GameState.combat_act does: the walk, then the blow
	assert_str(Acts.one("attack").can(s, data, hero, foe)).is_empty()
	assert_array(Acts.approach(s, data, hero, "attack", foe)).is_empty()  # beside it no walk


func test_too_far_for_this_turn_s_walk_keeps_its_reason() -> void:
	var s := _fight([{"monster": "goblin", "col": 2}])  # twelve squares off: a walk of 30 ft does not bring it in
	var hero := CombatRules.player(s)
	var foe := TestUtils.foe(s, 1)
	assert_array(Acts.approach(s, data, hero, "attack", foe)).is_empty()
	assert_str(Acts.near_why(s, data, hero, "attack", foe)).is_equal("COMBAT_OUT_OF_REACH")


func test_a_reason_a_walk_does_not_take_away_stays() -> void:
	var s := _fight([{"monster": "goblin", "col": 1}])
	var hero := CombatRules.player(s)
	var foe := TestUtils.foe(s, 1)
	CombatRules.points(s, data, hero)["move"] = 0  # no feet left
	assert_array(Acts.approach(s, data, hero, "attack", foe)).is_empty()
	assert_str(Acts.near_why(s, data, hero, "attack", foe)).is_equal("COMBAT_OUT_OF_REACH")


func test_the_hover_gets_the_way_from_the_hero_s_own_square() -> void:
	var s := _fight([{"monster": "goblin", "col": 1}])
	GameState.session = s
	var foe := TestUtils.foe(s, 1)
	var way := GameState.combat_way("attack", foe)
	assert_int(way.size()).is_greater(1)
	assert_object(way[0]).is_equal(FightGrid.cell(CombatRules.player(s)))
	assert_str(GameState.combat_can("attack", foe)).is_empty()
