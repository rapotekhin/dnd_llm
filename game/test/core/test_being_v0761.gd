extends GdUnitTestSuite
## One record of a character (v0.7.61): what the game knows of a person lies in `s.beings`, and a save brings it back.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _session() -> GameSession:
	return TestUtils.new_session()


func test_nothing_happened_nothing_is_kept() -> void:
	var s := _session()
	assert_dict(Being.view(s, "npc_innkeeper")).is_empty()
	assert_bool(Being.dead(s, "npc_innkeeper")).is_false()
	assert_dict(s.beings).is_empty()


func test_a_part_comes_and_goes() -> void:
	var s := _session()
	Being.of(s, "npc_innkeeper")["at"] = "brod-gate"
	assert_array(Being.with(s, "at")).contains_exactly(["npc_innkeeper"])
	Being.drop(s, "npc_innkeeper", "at")
	assert_array(Being.with(s, "at")).is_empty()
	Being.drop(s, "nobody", "at")
	assert_bool(s.beings.has("nobody")).is_false()


func test_followers_keep_their_order() -> void:
	var s := _session()
	Being.of(s, "c")["attitude"] = 1
	Being.follow(s, "a")
	Being.follow(s, "c")
	Being.follow(s, "b")
	Being.follow(s, "a")
	assert_array(Being.followers(s)).contains_exactly(["a", "c", "b"])
	Being.unfollow(s, "c")
	Being.follow(s, "c")
	assert_array(Being.followers(s)).contains_exactly(["a", "b", "c"])


func test_the_mood_starts_from_the_place() -> void:
	var s := _session()
	Being.of(s, "npc_innkeeper")["attitude_base"] = 1
	assert_int(s.attitude("npc_innkeeper")).is_equal(1)
	s.shift_attitude("npc_innkeeper", 1, data)
	assert_int(s.attitude("npc_innkeeper")).is_equal(2)
	assert_int(s.attitude("npc_merchant")).is_equal(0)


func test_a_memory_keeps_the_last() -> void:
	var s := _session()
	for i in GameSession.NPC_MEMORY_MAX + 3:
		s.remember("npc_innkeeper", "факт %d" % i)
	s.remember("npc_innkeeper", "факт %d" % (GameSession.NPC_MEMORY_MAX + 2))
	assert_int(s.memory_of("npc_innkeeper").size()).is_equal(GameSession.NPC_MEMORY_MAX)


func test_a_record_comes_back_from_a_save_unchanged() -> void:
	var s := _session()
	var b := Being.of(s, "npc_innkeeper")
	b["hp"] = 3
	b["attitude"] = -2
	b["pockets"] = [{"id": "p1", "cp": 12, "qty": 1, "dc": 10}]
	b["memory"] = [Fact.of(s, "помнит")]
	b["sick"] = {"id": "flu", "until": 2880}
	b["disarmed"] = {"dagger": 2}
	b["fed"] = {"at": 500, "hungry": 0}
	Being.follow(s, "npc_merchant")
	Being.die(s, "npc_herbalist")
	var before := JSON.stringify(s.to_dict(10))
	var back := GameSession.from_dict(JSON.parse_string(before))
	assert_str(JSON.stringify(back.to_dict(10))).is_equal(before)
	assert_int(typeof(Being.view(back, "npc_innkeeper")["hp"])).is_equal(TYPE_INT)
	assert_bool(Being.dead(back, "npc_herbalist")).is_true()
	assert_array(Being.followers(back)).contains_exactly(["npc_merchant"])


func test_the_session_has_no_second_store_of_a_person() -> void:
	var old := RegEx.create_from_string("^var (attitudes|attitude_base|npc_memory|pockets|pickpocketed|caught_by|npc_sick|npc_hp|npc_buffs|npc_spells|bodies|body_at|disarmed|npc_at|follower_fed|discounts|favors|dead_npcs|followers|searched|creatures|creature_counter|summons|summon_counter)\\b")
	for line: String in FileAccess.get_file_as_string("res://core/session/game_session.gd").split("\n"):
		assert_object(old.search(line)).override_failure_message(line).is_null()
