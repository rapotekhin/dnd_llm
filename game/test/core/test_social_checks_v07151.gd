extends GdUnitTestSuite
## «Социальный режим 2.0» (roadmap v0.7.15.1): the DC of a social check against a pack NPC comes from its SRD
## template — a lie meets its Insight, a threat its Wisdom save, a plea its Wisdom; the master's tier only says how
## big the ask is, the attitude makes persuading and fooling easier or harder.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func test_a_lie_meets_the_npcs_insight() -> void:
	var s := TestUtils.new_session()
	var commoner := SocialRules.dc(s, data, "npc_innkeeper", "deception", "easy")
	var priestess := SocialRules.dc(s, data, "npc_priestess", "deception", "easy")
	assert_int(int(commoner["dc"])).is_equal(10)  # Wisdom 10: a bare contest
	assert_int(int(priestess["dc"])).is_equal(12)  # an acolyte, Wisdom 14
	assert_str(str(priestess["reason"])).contains("Проницательность").contains("+2")


func test_the_tier_is_the_size_of_the_ask() -> void:
	var s := TestUtils.new_session()
	assert_int(int(SocialRules.dc(s, data, "npc_hermit", "persuasion", "medium")["dc"])).is_equal(17)  # 10 + 2 + 5
	assert_int(int(SocialRules.dc(s, data, "npc_hermit", "persuasion", "hard")["dc"])).is_equal(22)
	assert_str(str(SocialRules.dc(s, data, "npc_hermit", "persuasion", "hard")["reason"])).contains("просьба +10")


func test_attitude_moves_persuasion_but_not_threats() -> void:
	var s := TestUtils.new_session()
	s.attitudes["npc_smith"] = 2
	assert_int(int(SocialRules.dc(s, data, "npc_smith", "persuasion", "medium")["dc"])).is_equal(11)  # 15 − 4
	assert_int(int(SocialRules.dc(s, data, "npc_smith", "intimidation", "medium")["dc"])).is_equal(15)
	s.attitudes["npc_smith"] = -3
	assert_int(int(SocialRules.dc(s, data, "npc_smith", "deception", "medium")["dc"])).is_equal(21)  # 15 + 6


func test_the_dc_stays_within_bounds_and_only_for_social_skills() -> void:
	var s := TestUtils.new_session()
	s.attitudes["npc_innkeeper"] = 3
	assert_int(int(SocialRules.dc(s, data, "npc_innkeeper", "persuasion", "very_easy")["dc"])).is_equal(5)
	assert_dict(SocialRules.dc(s, data, "npc_innkeeper", "athletics", "medium")).is_empty()
	assert_dict(SocialRules.dc(s, data, "wolf_1", "deception", "medium")).is_empty()  # not a pack NPC


func test_the_check_carries_the_reason_of_its_dc() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var r := CheckEngine.roll(data["rules"], rng, {"skill": "deception", "dc_tier": "medium", "dc": 12, "dc_reason": "Проницательность Сестры Илвы +2"}, 3, "c-1")
	assert_int(int(r["dc"])).is_equal(12)
	assert_str(str(r["dc_reason"])).contains("Сестры Илвы")
