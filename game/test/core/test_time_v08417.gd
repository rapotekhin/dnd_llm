extends GdUnitTestSuite
## v0.8.4.17: time — one way the clock moves (a sentence and a long rest by TimeRules.advance), the calendar and the
## weather as rows of the registry, one catch-up of the daily hooks, one «N times a day», a town's project by Progress,
## the map's minutes as the step spends them, one pay of a shift broken off.

var data: Dictionary


func before() -> void:
	data = TestUtils.data()


func _session() -> GameSession:
	var s := TestUtils.new_session()
	s.room_id = "brod-tavern-hall"
	s.minute = 12 * 60
	return s


func test_the_days_of_a_sentence_pass_for_the_world() -> void:
	var s := _session()
	var c := s.character
	ConditionRules.add_effect(c, {"condition": "poisoned", "ends": ConditionRules.ends_for(s, data, "hour"), "source": {"kind": "master", "name": "яд"}})
	var day := s.day
	var lines := TimeRules.jump(s, data, 3)
	assert_int(s.day).is_equal(day + 3)
	assert_int(s.minute).is_equal(int(TimeRules.cfg(data)["wake_minute"]))
	assert_bool(ConditionRules.has(c, "poisoned")).is_false()  # the hooks ran in those days
	assert_str("\n".join(lines)).contains("Наступил день %d" % (day + 3))
	assert_int(s.rested_at).is_equal(TimeRules.abs_minute(s))


func test_a_long_rest_wakes_in_the_morning_and_feeds_the_followers_once() -> void:
	var s := _session()
	s.minute = 22 * 60
	Being.follow(s, "npc_innkeeper")
	ExplorationRules.long_rest(s, data)
	assert_int(s.minute).is_equal(int(TimeRules.cfg(data)["wake_minute"]))
	assert_int(int(Being.of(s, "npc_innkeeper")["fed"]["at"])).is_equal(TimeRules.abs_minute(s))  # the breakfast, at waking


func test_the_calendar_and_the_weather_are_rows_of_the_registry() -> void:
	var ids: Array = TimeRules.registry().map(func(h: Dictionary) -> String: return str(h["id"]))
	assert_array(ids).contains(["calendar", "weather"])


func test_one_catch_up_of_missed_days() -> void:
	var s := _session()
	var rec := {"last_day": s.day}
	s.day += 3
	assert_array(TimeRules.missed(s, rec)).contains_exactly([s.day - 2, s.day - 1, s.day])
	assert_array(TimeRules.missed(s, rec)).is_empty()
	var fresh := {}
	assert_array(TimeRules.missed(s, fresh)).is_empty()  # a record without its day starts today
	assert_int(int(fresh["last_day"])).is_equal(s.day)


func test_one_count_a_day_and_asking_writes_nothing() -> void:
	var s := _session()
	var holder := {}
	assert_int(TimeRules.today(s, holder, "x")).is_equal(0)
	assert_bool(holder.is_empty()).is_true()
	assert_int(TimeRules.count(s, holder, "x")).is_equal(1)
	assert_int(TimeRules.count(s, holder, "x")).is_equal(2)
	s.day += 1
	assert_int(TimeRules.today(s, holder, "x")).is_equal(0)


func test_asking_for_a_game_writes_nothing() -> void:
	var s := _session()
	ContestRules.why_not(s, data, "npc_innkeeper")
	assert_bool(s.character.has("contests_day")).is_false()


func test_a_town_s_project_is_built_without_a_headman() -> void:
	var s := _session()
	var d := TestUtils.system_on(data.duplicate(true), "office")  # offices are out of the game (v0.8.4.39), their road stays
	var t := {"builds": {"palisade": Progress.by_day(s.day + 1).merged({"office": "brod_headman"})}, "treasury": 0, "discontent": 0, "tax": "normal"}
	OfficeRules._town_day(s, d, "brod", t, s.day + 1)
	assert_bool(s.flags.has("brod_palisade")).is_true()
	assert_bool(bool(OfficeRules.build_rec(t, "palisade")["done"])).is_true()


func test_the_map_counts_the_minutes_the_step_spends() -> void:
	var s := _session()
	s.room_id = "brod-gate"
	var path: Array[String] = ["pushcha-edge"]
	var shown := WorldMap.minutes(s, data, "brod-gate", path)
	var at := TimeRules.abs_minute(s)
	TimeRules.on_move(s, data, "brod-gate", "pushcha-edge")
	assert_int(TimeRules.abs_minute(s) - at).is_equal(shown)


func test_one_pay_of_a_shift_broken_off() -> void:
	assert_int(JobRules.broken_off(100, 120, 480)).is_equal(25)
