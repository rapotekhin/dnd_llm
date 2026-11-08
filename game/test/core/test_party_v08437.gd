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


func test_a_fight_too_strong_for_one_fits_four() -> void:
	var s := TestUtils.new_session()
	var two_goblins := {"enemies": [{"monster": "goblin", "count": 2}]}
	s.settings["party"] = 1  # 100 XP ×2 (two foes, a step up for one hero) = 200 > medium 50
	assert_str(str(QuestGen._plan_encounter(s, data, two_goblins, "medium", 1, false, "a").get("reason", ""))).contains("не по силам")
	s.settings["party"] = 4  # 100 ×1,5 = 150: between easy 100 and medium 200 for four
	var plan := QuestGen._plan_encounter(s, data, two_goblins, "medium", 1, false, "a")
	assert_bool(plan.has("reason")).override_failure_message(str(plan)).is_false()
	var one := {"enemies": [{"monster": "goblin", "count": 1}]}  # 50: too easy for four
	assert_str(str(QuestGen._plan_encounter(s, data, one, "medium", 1, false, "a").get("reason", ""))).contains("лёгкий")


## v0.8.4.38, the author: the DMG's multiplier by the number of foes, a step up for one or two heroes.
func test_a_crowd_weighs_more_by_the_dmg() -> void:
	var s := TestUtils.new_session()
	s.settings["party"] = 4
	var steps := {1: 1.0, 2: 1.5, 3: 2.0, 6: 2.0, 7: 2.5, 11: 3.0, 15: 4.0}
	for n: int in steps:
		assert_float(DifficultyRules.crowd_mult(s, data, n)).override_failure_message("party 4, %d foes" % n).is_equal(steps[n])
	s.settings["party"] = 1
	assert_float(DifficultyRules.crowd_mult(s, data, 1)).is_equal(1.5)
	assert_float(DifficultyRules.crowd_mult(s, data, 4)).is_equal(2.5)
	assert_float(DifficultyRules.crowd_mult(s, data, 20)).is_equal(5.0)
	assert_int(DifficultyRules.weigh(s, data, [{"xp": 50, "count": 4}])).is_equal(500)
	assert_str(DifficultyRules.weigh_text(s, data, [{"xp": 50, "count": 4}])).is_equal("200 опыта ×2,5 за 4 врагов = 500")
	assert_str(DifficultyRules.crowd_line(s, data)).starts_with("1 — ×1,5; 2 — ×2; 3–6 — ×2,5")
