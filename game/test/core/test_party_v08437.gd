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
	s.character["level"] = 3
	s.settings["party"] = 1
	var one := QuestGen.tier_xp(s, data, "medium", 3)
	assert_that(QuestGen.tier_band(s, data, "medium", 3)).is_equal(Vector2i(150, 224))  # v0.8.4.42.8: the DMG's medium, up to hard
	assert_int(DifficultyRules.hard_cap(s, data)).is_equal(399)  # a hard fight at most: below deadly 400
	s.settings["party"] = 3
	assert_int(QuestGen.tier_xp(s, data, "medium", 3)).is_equal(one * 3)
	assert_that(QuestGen.tier_band(s, data, "medium", 3)).is_equal(Vector2i(450, 674))
	assert_int(DifficultyRules.hard_cap(s, data)).is_equal(1199)
	assert_that(QuestGen.tier_band(s, data, "deadly", 3)).is_equal(Vector2i(1200, 1800))


func test_a_fight_too_strong_for_one_fits_four() -> void:
	var s := TestUtils.new_session()
	var four_goblins := {"enemies": [{"monster": "goblin", "count": 4}]}
	s.settings["party"] = 1  # 200 XP ×2,5 (four foes, a step up for one hero) = 500 > 74 below hard 75
	assert_str(str(QuestGen._plan_encounter(s, data, four_goblins, "medium", 1, false, "a").get("reason", ""))).contains("не по силам")
	s.settings["party"] = 4  # 200 ×2 = 400: medium 200 … 299 for four? no — hard; three goblins 150 ×2 = 300 also hard
	var two := {"enemies": [{"monster": "goblin", "count": 2}, {"monster": "kobold", "count": 2}]}  # 150 ×2 = 300 — hard for four
	assert_str(str(QuestGen._plan_encounter(s, data, two, "medium", 1, false, "a").get("reason", ""))).contains("не по силам")
	var fits := {"enemies": [{"monster": "goblin", "count": 2}, {"monster": "kobold", "count": 1}]}  # 125 ×2 = 250 of [200, 299]
	var plan := QuestGen._plan_encounter(s, data, fits, "medium", 1, false, "a")
	assert_bool(plan.has("reason")).override_failure_message(str(plan)).is_false()
	var one := {"enemies": [{"monster": "goblin", "count": 2}]}  # 100 ×1,5 = 150: easy for four, below medium 200
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
