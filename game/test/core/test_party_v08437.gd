extends GdUnitTestSuite
## v0.8.4.37, the author: the master's fights are made for a party of 1..4 heroes — the DMG budget of one hero times
## the number (rules.difficulty.party, session.settings.party), chosen for a new game and in the settings.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func test_one_hero_by_default_and_the_choice_is_kept_in_bounds() -> void:
	var s := TestUtils.new_session()
	s.settings.erase("party")
	assert_int(DifficultyRules.party(s, data)).is_equal(1)
	assert_array(DifficultyRules.party_sizes(data)).is_equal([1, 2, 3, 4])
	s.settings["party"] = 9
	assert_int(DifficultyRules.party(s, data)).is_equal(4)
	assert_bool(WorldPack.default_settings({}).has("party")).is_true()


func test_the_budget_grows_with_the_party() -> void:
	var s := TestUtils.new_session()
	s.settings["party"] = 1
	var one := QuestGen.tier_xp(s, data, "medium", 3)
	var cap := DifficultyRules.hard_cap(s, data)
	s.settings["party"] = 3
	assert_int(QuestGen.tier_xp(s, data, "medium", 3)).is_equal(one * 3)
	assert_int(DifficultyRules.hard_cap(s, data)).is_equal(cap * 3)


func test_a_fight_too_strong_for_one_fits_a_pair() -> void:
	var s := TestUtils.new_session()
	var two_goblins := {"enemies": [{"monster": "goblin", "count": 2}]}
	s.settings["party"] = 1
	assert_str(str(QuestGen._plan_encounter(s, data, two_goblins, "medium", 1, false, "a").get("reason", ""))).contains("не по силам")
	s.settings["party"] = 2
	var plan := QuestGen._plan_encounter(s, data, two_goblins, "medium", 1, false, "a")
	assert_bool(plan.has("reason")).override_failure_message(str(plan)).is_false()
	s.settings["party"] = 4  # for four, two goblins are too easy for a medium fight
	assert_str(str(QuestGen._plan_encounter(s, data, two_goblins, "medium", 1, false, "a").get("reason", ""))).contains("лёгкий")
