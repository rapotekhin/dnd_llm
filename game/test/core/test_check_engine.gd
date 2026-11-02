extends GdUnitTestSuite
## CheckEngine.card: DC ladder, advantage only with a reason, nat 20/1 house rule, bad params (ADR-0008 §2).

var data: Dictionary


func before() -> void:
	data = TestUtils.data()


func _roll(params: Dictionary, seed_value: int = 1) -> Dictionary:
	var s := TestUtils.new_session()
	s.rng.seed = seed_value
	return CheckEngine.card(s, data, params)


func test_dc_comes_from_the_tier() -> void:
	for tier: String in TestUtils.rules()["dc_tiers"]:
		var r := _roll({"skill": "perception", "dc_tier": tier})
		assert_int(r["dc"]).is_equal(int(TestUtils.rules()["dc_tiers"][tier]))


func test_result_fields_are_consistent() -> void:
	for s in range(50):
		var r := _roll({"skill": "stealth", "dc_tier": "medium"}, s)
		assert_int(r["nat"]).is_between(1, 20)
		assert_int(r["total"]).is_equal(r["nat"] + r["bonus"])
		assert_int(RollParts.sum(r["parts"])).is_equal(r["bonus"])
		var expected: bool = r["nat"] == 20 or (r["nat"] != 1 and r["total"] >= 15)
		assert_bool(r["success"]).is_equal(expected)
		assert_str(r["check_id"]).is_not_empty()


func test_natural_20_and_1_override_the_total() -> void:
	var saw_20 := false
	var saw_1 := false
	for s in range(400):
		var r := _roll({"save": "dex", "dc_tier": "nearly_impossible"}, s)
		if r["nat"] == 20:
			saw_20 = true
			assert_bool(r["success"]).is_true()  # 20 < DC 30, still a success
		var easy := _roll({"skill": "perception", "dc_tier": "very_easy", "dc": -10}, s)
		if easy["nat"] == 1:
			saw_1 = true
			assert_bool(easy["success"]).is_false()  # far above the DC, still a failure
	assert_bool(saw_20 and saw_1).is_true()


func test_advantage_needs_a_reason_and_takes_the_higher_die() -> void:
	assert_int(_roll({"skill": "arcana", "dc_tier": "easy", "advantage_reason": ""})["rolls"].size()).is_equal(1)
	for s in range(30):
		var r := _roll({"skill": "arcana", "dc_tier": "easy", "advantage_reason": "верёвка"}, s)
		assert_int(r["rolls"].size()).is_equal(2)
		assert_int(r["nat"]).is_equal(maxi(r["rolls"][0], r["rolls"][1]))
		assert_str(str(r["advantage_reason"])).is_equal("верёвка")


func test_same_seed_same_roll() -> void:
	var a := _roll({"skill": "arcana", "dc_tier": "hard"}, 77)
	var b := _roll({"skill": "arcana", "dc_tier": "hard"}, 77)
	a.erase("check_id")
	b.erase("check_id")
	assert_dict(a).is_equal(b)


func test_bad_params_are_rejected() -> void:
	assert_bool(_roll({"skill": "perception", "dc_tier": "impossible"}).has("error")).is_true()
	assert_bool(_roll({"skill": "flying", "dc_tier": "easy"}).has("error")).is_true()
	assert_bool(_roll({"save": "luck", "dc_tier": "easy"}).has("error")).is_true()
	assert_bool(_roll({"dc_tier": "easy"}).has("error")).is_true()
	assert_bool(_roll({"skill": "perception", "save": "dex", "dc_tier": "easy"}).has("error")).is_true()
