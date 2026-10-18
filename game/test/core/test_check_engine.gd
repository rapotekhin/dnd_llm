extends GdUnitTestSuite
## CheckEngine: DC ladder, advantage only with a reason, nat 20/1 house rule, bad params (ADR-0008 §2).


func _rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r


func _roll(params: Dictionary, bonus: int = 0, seed_value: int = 1) -> Dictionary:
	return CheckEngine.roll(TestUtils.rules(), _rng(seed_value), params, bonus, "c-1")


func test_dc_comes_from_the_tier() -> void:
	for tier: String in TestUtils.rules()["dc_tiers"]:
		var r := _roll({"skill": "perception", "dc_tier": tier})
		assert_int(r["dc"]).is_equal(int(TestUtils.rules()["dc_tiers"][tier]))


func test_result_fields_are_consistent() -> void:
	for s in range(50):
		var r := _roll({"skill": "stealth", "dc_tier": "medium"}, 3, s)
		assert_int(r["rolls"].size()).is_equal(1)
		assert_int(r["nat"]).is_between(1, 20)
		assert_int(r["total"]).is_equal(r["nat"] + 3)
		var expected: bool = r["nat"] == 20 or (r["nat"] != 1 and r["total"] >= 15)
		assert_bool(r["success"]).is_equal(expected)
		assert_str(r["check_id"]).is_equal("c-1")


func test_natural_20_and_1_override_the_total() -> void:
	var saw_20 := false
	var saw_1 := false
	for s in range(400):
		var r := _roll({"save": "dex", "dc_tier": "nearly_impossible"}, 0, s)
		if r["nat"] == 20:
			saw_20 = true
			assert_bool(r["success"]).is_true()  # 20 < DC 30, still a success
		var easy := _roll({"save": "dex", "dc_tier": "very_easy"}, 10, s)
		if easy["nat"] == 1:
			saw_1 = true
			assert_bool(easy["success"]).is_false()  # 11 >= DC 5, still a failure
	assert_bool(saw_20 and saw_1).is_true()


func test_advantage_needs_a_reason_and_takes_the_higher_die() -> void:
	assert_int(_roll({"skill": "athletics", "dc_tier": "easy", "advantage_reason": ""})["rolls"].size()).is_equal(1)
	for s in range(30):
		var r := _roll({"skill": "athletics", "dc_tier": "easy", "advantage_reason": "верёвка"}, 0, s)
		assert_int(r["rolls"].size()).is_equal(2)
		assert_int(r["nat"]).is_equal(maxi(r["rolls"][0], r["rolls"][1]))


func test_same_seed_same_roll() -> void:
	assert_dict(_roll({"skill": "arcana", "dc_tier": "hard"}, 2, 77)).is_equal(_roll({"skill": "arcana", "dc_tier": "hard"}, 2, 77))


func test_bad_params_are_rejected() -> void:
	assert_bool(_roll({"skill": "perception", "dc_tier": "impossible"}).has("error")).is_true()
	assert_bool(_roll({"skill": "flying", "dc_tier": "easy"}).has("error")).is_true()
	assert_bool(_roll({"save": "luck", "dc_tier": "easy"}).has("error")).is_true()
	assert_bool(_roll({"dc_tier": "easy"}).has("error")).is_true()
	assert_bool(_roll({"skill": "perception", "save": "dex", "dc_tier": "easy"}).has("error")).is_true()
