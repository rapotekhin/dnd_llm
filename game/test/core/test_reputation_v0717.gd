extends GdUnitTestSuite
## «Торговля 2.0» (roadmap v0.7.17, batch 1): reputation in a settlement — points from the engine's facts and the
## master's deeds, a step −3…+3 in words; it moves the prices of every trader of the place and the attitude of the
## people the hero has not dealt with yet.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _hero(room: String) -> GameSession:
	var s := TestUtils.new_session()
	for p: Dictionary in data["presets"]:
		if p["id"] == "rogue_damir":
			s.character = GameSession.normalized_character(CharacterBuilder.build_preset(p, data))
	CharacterRules.refresh(s.character, data, s.items)
	s.room_id = room
	return s


func test_steps_by_points_only_in_settlements() -> void:
	var s := _hero("brod-square")
	assert_str(ReputationRules.text(s, data, "brod")).is_equal("Ольховый Брод — чужак (+0)")
	var lines := ReputationRules.add(s, data, "brod", 6, "задание")
	assert_str(" ".join(lines)).contains("«свой»")
	assert_int(ReputationRules.step(s, data, "brod")).is_equal(1)
	assert_array(ReputationRules.add(s, data, "pushcha", 50, "?")).is_empty()  # the forest keeps no name
	assert_str(ReputationRules.text(s, data, "pushcha")).is_empty()
	ReputationRules.add(s, data, "brod", -22, "убийство")  # 6 − 22 = −16
	assert_str(ReputationRules.word(data, ReputationRules.step(s, data, "brod"))).is_equal("дурная слава")


func test_prices_and_strangers_follow_the_name() -> void:
	var s := _hero("brod-square")
	var item := str((TradeRules.merchant(s, data, "npc_merchant")["stock"] as Dictionary).keys().filter(
		func(id: String) -> bool: return TradeRules.buy_price(s, data, "npc_merchant", id) > 1000)[0])
	var before := TradeRules.buy_price(s, data, "npc_merchant", item)
	s.attitudes["npc_smith"] = 0  # already dealt with: stays as it is
	ReputationRules.add(s, data, "brod", 30, "герой")
	assert_int(TradeRules.buy_price(s, data, "npc_merchant", item)).is_less(before)
	assert_int(s.attitude("npc_herbalist")).is_equal(1)
	assert_int(s.attitude("npc_smith")).is_equal(0)
	assert_int(s.attitude("npc_hermit")).is_equal(0)  # the Pushcha is no settlement


func test_the_engine_counts_quests_and_crimes() -> void:
	var s := _hero("brod-tavern-hall")
	CrimeRules.on_death(s, data, "npc_mercenary", true, s.room_id)
	assert_int(ReputationRules.step(s, data, "brod")).is_equal(-2)
	assert_int(s.attitude("npc_prospector")).is_equal(0)  # the mine is another place


func test_the_master_marks_a_deed_once_a_turn_in_a_settlement() -> void:
	var s := _hero("brod-square")
	var fx := EffectEngine.new()
	var r := fx.validate(s, data, "t-1", {"kind": "reputation", "delta": 3, "reason": "вытащил ребёнка из горящего сарая на глазах у всей площади"})
	assert_bool(bool(r["accepted"])).is_true()
	assert_str(str(fx.validate(s, data, "t-1", {"kind": "reputation", "delta": 1, "reason": "и ещё помог"})["reason"])).contains("раза за ход")
	fx.apply(s, "t-1", [r["effect_id"]])
	assert_int(ReputationRules.points(s, "brod")).is_equal(3)
	s.room_id = "pushcha-glade"
	assert_str(str(fx.validate(s, data, "t-2", {"kind": "reputation", "delta": 1, "reason": "помог отшельнику"})["reason"])).contains("не поселение")


func test_old_saves_start_as_strangers() -> void:
	var v26 := {"save_version": 26, "session": {}}
	SaveFormat._v26_to_v27(v26, {})
	assert_dict(v26["session"]["reputation"]).is_empty()
	var s := _hero("brod-square")
	ReputationRules.add(s, data, "brod", 16, "?")
	var back := GameSession.from_dict(s.to_dict(5))
	assert_int(ReputationRules.step(back, data, "brod")).is_equal(2)
	assert_int(back.attitude("npc_cook")).is_equal(1)
