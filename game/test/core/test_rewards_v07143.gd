extends GdUnitTestSuite
## «Последствия и время» (roadmap v0.7.14.3): what the master gives itself — coins and things outside quests — fits
## the budget of the level until the long rest; a nearly impossible success gives at most a quarter of what is left.

var data: Dictionary
var fx: EffectEngine


func before_test() -> void:
	data = TestUtils.data()
	fx = EffectEngine.new()


func _hero() -> GameSession:
	var s := TestUtils.new_session()
	s.character["level"] = 1
	return s


func _give(s: GameSession, turn: String, effect: Dictionary) -> Dictionary:
	var r := fx.validate(s, data, turn, effect)
	if bool(r["accepted"]):
		fx.apply(s, turn, [r["effect_id"]])
	return r


func test_the_master_gives_within_the_budget_until_the_long_rest() -> void:
	var s := _hero()
	assert_bool(bool(_give(s, "t-1", {"kind": "coins", "delta_cp": 2000, "reason": "находка"})["accepted"])).is_true()
	assert_int(s.reward_spent).is_equal(2000)
	var r := _give(s, "t-2", {"kind": "coins", "delta_cp": 1500, "reason": "ещё"})
	assert_bool(bool(r["accepted"])).is_false()
	assert_str(str(r["reason"])).contains("бюджет наград").contains("10 зм")
	assert_bool(bool(_give(s, "t-3", {"kind": "give_item", "item_id": "healing_potion", "qty": 1, "reason": "дар"})["accepted"])).is_false()
	assert_bool(bool(_give(s, "t-4", {"kind": "coins", "delta_cp": -500, "reason": "плата"})["accepted"])).is_true()  # paying is no gift
	ExplorationRules.long_rest(s, data, {"forage": 1})
	assert_int(s.reward_spent).is_equal(0)
	assert_bool(bool(_give(s, "t-5", {"kind": "coins", "delta_cp": 2500, "reason": "клад"})["accepted"])).is_true()


func test_two_gifts_of_one_turn_share_the_budget() -> void:
	var s := _hero()
	assert_bool(bool(fx.validate(s, data, "t-1", {"kind": "coins", "delta_cp": 2000, "reason": "а"})["accepted"])).is_true()
	assert_bool(bool(fx.validate(s, data, "t-1", {"kind": "coins", "delta_cp": 1500, "reason": "б"})["accepted"])).is_false()


func test_a_nearly_impossible_success_gives_a_quarter_at_most() -> void:
	var s := _hero()
	fx.note_check("t-1", "nearly_impossible", true)
	var r := fx.validate(s, data, "t-1", {"kind": "coins", "delta_cp": 1000, "reason": "чудо"})
	assert_str(str(r.get("reason", ""))).contains("почти невозможного")
	assert_bool(bool(fx.validate(s, data, "t-1", {"kind": "coins", "delta_cp": 700, "reason": "чудо"})["accepted"])).is_true()


func test_the_master_sees_what_is_left() -> void:
	var s := _hero()
	_give(s, "t-1", {"kind": "coins", "delta_cp": 1000, "reason": "находка"})
	assert_int(int(TurnSnapshot.build(s, data, 2000)["character"]["reward_left_cp"])).is_equal(2000)


func test_old_saves_start_with_a_full_budget() -> void:
	var v21 := {"save_version": 21, "session": {}}
	SaveFormat._v21_to_v22(v21, {})
	assert_int(int(v21["session"]["reward_spent"])).is_equal(0)
