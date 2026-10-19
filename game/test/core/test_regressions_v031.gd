extends GdUnitTestSuite
## Bugs B1–B19 of the pygame prototype (its test_regressions_v031.py, removed in v0.5.4; review-2026-10 §1) that apply
## to the Godot client today. The rest move with their systems in v0.5.x:
## B2 (screen state on resize) — gone by design: views rebuild from GameState; B5–B7 (XP, HP per level, spell
## slots) — test_level_up.gd; B13 (sell for half) and B16 (equip during trade) — test_trade_rules.gd; B15 (dice expressions)
## — the engine rolls by table, the model never sends dice; B3 (combat dead end) — combat mode (M3).

var _saved_save_dir: String


func before_test() -> void:
	_saved_save_dir = SaveManager.save_dir
	SaveManager.save_dir = "user://test_saves"
	DirAccess.make_dir_recursive_absolute(SaveManager.save_dir)
	GameState.start(TestUtils.new_session())


func after_test() -> void:
	GameState.session = null
	GameState.busy_turn = ""
	SaveManager.save_dir = _saved_save_dir


func test_b1_b19_input_is_ignored_while_the_master_thinks() -> void:
	GameState.busy_turn = "t-1"
	var before := GameState.session.chat.size()
	assert_bool(GameState.submit("ещё действие")).is_false()
	assert_bool(GameState.go(TestUtils.KITCHEN)).is_false()
	assert_bool(GameState.talk_to(TestUtils.INNKEEPER)).is_false()
	assert_int(GameState.session.chat.size()).is_equal(before)


func test_b4_cannot_pay_more_than_the_purse() -> void:
	var fx := EffectEngine.new()
	var gold := int(GameState.session.character["gold_cp"])
	var r := fx.validate(GameState.session, TestUtils.data(), "t-1", {"kind": "coins", "delta_cp": -(gold + 1), "reason": "x"})
	assert_bool(r["accepted"]).is_false()


func test_b8_move_only_to_an_adjacent_room() -> void:
	assert_bool(GameState.world().exits(GameState.session.room_id).has(TestUtils.FAR_ROOM)).is_false()
	assert_bool(GameState.go(TestUtils.FAR_ROOM)).is_false()
	assert_str(GameState.session.room_id).is_equal(TestUtils.START_ROOM)


func test_b9_conversation_only_with_an_npc_in_the_room() -> void:
	var s := GameState.session
	assert_str(GameState._apply_result(s, "t-1", {"narration": "x", "next_mode": {"mode": "social", "npc_id": TestUtils.COOK}}, "action")).is_empty()
	assert_str(s.mode).is_equal(GameSession.MODE_EXPLORATION)
	assert_str(GameState._apply_result(s, "t-2", {"narration": "x", "next_mode": {"mode": "social", "npc_id": "ghost"}}, "action")).is_empty()
	assert_str(GameState._apply_result(s, "t-3", {"narration": "x", "next_mode": {"mode": "social", "npc_id": TestUtils.INNKEEPER}}, "action")).is_equal("enter")
	assert_str(s.mode).is_equal(GameSession.MODE_SOCIAL)
	assert_str(s.npc_id).is_equal(TestUtils.INNKEEPER)


## v0.7.2: the master opened a conversation on its own on «resume» — only the player's words start one.
func test_the_master_does_not_start_a_conversation_on_its_own() -> void:
	var s := GameState.session
	for kind: String in ["enter", "resume", "rest", "wait"]:
		assert_str(GameState._apply_result(s, "t-" + kind, {"narration": "x", "next_mode": {"mode": "social", "npc_id": TestUtils.INNKEEPER}}, kind)).is_empty()
		assert_str(s.mode).is_equal(GameSession.MODE_EXPLORATION)


func test_b9_trade_with_a_non_trader_becomes_a_conversation() -> void:
	var s := GameState.session
	var lira := TestUtils.SERVING
	GameState._apply_result(s, "t-1", {"narration": "x", "next_mode": {"mode": "trade", "npc_id": lira}}, "action")
	assert_str(s.mode).is_equal(GameSession.MODE_SOCIAL)


func test_b10_a_new_game_starts_a_fresh_world() -> void:
	var s := GameState.session
	s.room_id = TestUtils.FAR_ROOM
	s.character["gold_cp"] = 1
	GameState.effects.reserves["e-1"] = {"turn_id": "t-1", "kind": "flag", "plan": {}, "summary": ""}
	GameState.start(TestUtils.new_session(7))
	assert_str(GameState.session.room_id).is_equal(TestUtils.START_ROOM)
	assert_int(GameState.session.character["gold_cp"]).is_equal(int(TestUtils.character()["gold_cp"]))
	assert_dict(GameState.effects.reserves).is_empty()


func test_b11_loading_a_save_restores_the_world_and_mode() -> void:
	var s := GameState.session
	s.mode = GameSession.MODE_SOCIAL
	s.npc_id = TestUtils.INNKEEPER
	assert_bool(GameState.save_to("slot_3")).is_true()
	GameState.start(TestUtils.new_session(8))
	assert_str(GameState.load_from("slot_3")).is_empty()
	assert_str(GameState.session.mode).is_equal(GameSession.MODE_SOCIAL)
	assert_str(GameState.session.npc_id).is_equal(TestUtils.INNKEEPER)


func test_b14_natural_20_and_advantage() -> void:
	var rng := RandomNumberGenerator.new()
	for seed_value in 300:
		rng.seed = seed_value
		var r := CheckEngine.roll(TestUtils.rules(), rng, {"skill": "stealth", "dc_tier": "nearly_impossible", "advantage_reason": "туман"}, 0, "c")
		assert_int(r["nat"]).is_equal(maxi(r["rolls"][0], r["rolls"][1]))
		if r["nat"] == 20:
			assert_bool(r["success"]).is_true()


func test_b17_ten_slots_and_unreadable_saves() -> void:
	assert_int(SaveManager.manual_slots().size()).is_equal(10)
	assert_str(SaveManager.read_slot("slot_does_not_exist")).is_equal(SaveFormat.ERR_UNREADABLE)


func test_b18_failed_turns_tell_the_player_and_can_be_retried() -> void:
	for reason: String in ["llm_unavailable", "llm_invalid_output", "turn_timeout", "connection_lost", "budget_exceeded"]:
		assert_str(GameState._error_key(reason)).starts_with("MSG_")
	assert_str(GameState._error_key("budget_exceeded")).is_equal("MSG_BUDGET_EXCEEDED")
	assert_str(GameState._error_key("llm_invalid_output")).is_equal("MSG_MASTER_FAILED")


## ADR-0008 §2 through GameState: a repeat of a failed check returns the old result without a roll.
func test_repeat_of_a_failed_check_is_blocked_without_a_roll() -> void:
	GameState.busy_turn = "t-1"
	var params := {"turn_id": "t-1", "skill": "arcana", "dc_tier": "nearly_impossible"}
	var first: Dictionary = GameState.handle_engine_check(params)
	if bool(first["success"]):
		return  # a natural 20 (seeded, but keep the test honest)
	var state_before := GameState.session.rng.state
	var second: Dictionary = GameState.handle_engine_check(params)
	assert_bool(second["blocked"]).is_true()
	assert_int(int(second["total"])).is_equal(int(first["total"]))
	assert_int(GameState.session.rng.state).is_equal(state_before)  # no dice rolled
	assert_str(second["check_id"]).is_not_equal(first["check_id"])
