extends GdUnitTestSuite
## The chat's engine lines (v0.8.4.43.5.1): the kind says it is the engine's, a repeat right after folds «×N»; the story
## — the master's, an NPC's and the player's words — never folds.


func _effect(line: String, rolls: Array = []) -> Dictionary:
	var e := GameSession.effect_entry([line] as Array[String])
	if not rolls.is_empty():
		e["rolls"] = rolls
	return e


func test_the_kind_says_whose_line_it_is() -> void:
	for e: Dictionary in [_effect("Взято: кружка"), GameSession.system_entry("QUEST_ACT_BUILDING"), GameSession.rolls_entry(1, [], {}),
			GameSession.check_entry({"skill": "perception"}, {"nat": 12, "total": 14, "dc": 12, "success": true})]:
		assert_bool(GameSession.is_engine(e)).override_failure_message(str(e)).is_true()
	for e: Dictionary in [GameSession.dm_entry("Вы осматриваетесь.", "t-1"), GameSession.npc_entry("npc_innkeeper", "Бруно", "Чего налить?", "t-2"),
			GameSession.player_entry("Осматриваюсь")]:
		assert_bool(GameSession.is_engine(e)).override_failure_message(str(e)).is_false()


func test_the_engine_s_line_said_again_folds_into_it() -> void:
	var s := TestUtils.new_session()
	var first := s.append(_effect("Взято: кружка"))
	var again := s.append(_effect("Взято: кружка"))
	var third := s.append(_effect("Взято: кружка"))
	assert_int(s.chat.size()).is_equal(1)
	assert_bool(is_same(first, again) and is_same(first, third)).is_true()  # the view finds the line it rebuilds
	assert_int(GameSession.times(s.chat[0])).is_equal(3)
	assert_str(GameSession.counted("Взято: кружка", s.chat[0])).is_equal("Взято: кружка ×3")
	assert_str(GameSession.counted("Взято: кружка", _effect("Взято: кружка"))).is_equal("Взято: кружка")


func test_a_system_line_folds_by_its_key_and_args() -> void:
	var s := TestUtils.new_session()
	s.append(GameSession.system_entry("ERROR_TIMEOUT"))
	s.append(GameSession.system_entry("ERROR_TIMEOUT"))
	s.append(GameSession.system_entry("ERROR_TIMEOUT", {"n": 2}))
	assert_int(s.chat.size()).is_equal(2)
	assert_int(GameSession.times(s.chat[0])).is_equal(2)
	assert_int(GameSession.times(s.chat[1])).is_equal(1)


func test_another_line_between_breaks_the_fold() -> void:
	var s := TestUtils.new_session()
	s.append(_effect("Взято: кружка"))
	s.append(_effect("Взято: миска"))
	s.append(_effect("Взято: кружка"))
	s.append(GameSession.system_entry("ERROR_TIMEOUT"))
	s.append(GameSession.dm_entry("Бруно хмыкает.", "t-1"))
	s.append(GameSession.system_entry("ERROR_TIMEOUT"))
	assert_int(s.chat.size()).is_equal(6)


func test_the_story_never_folds() -> void:
	var s := TestUtils.new_session()
	for i in 2:
		s.append(GameSession.dm_entry("Вы осматриваетесь.", "t-%d" % i))
	for i in 2:
		s.append(GameSession.npc_entry("npc_innkeeper", "Бруно Хмель", "Вы осматриваетесь.", "t-n%d" % i))
	for i in 2:
		s.append(GameSession.player_entry("Осматриваюсь"))
	assert_int(s.chat.size()).is_equal(6)
	assert_bool(s.chat.all(func(e: Dictionary) -> bool: return GameSession.times(e) == 1)).is_true()


func test_rounds_and_checks_stay_apart() -> void:
	var s := TestUtils.new_session()
	s.append(GameSession.rolls_entry(1, ["Волк: промах"], {}))
	s.append(GameSession.rolls_entry(1, ["Волк: промах"], {}))
	var check := {"nat": 12, "total": 14, "dc": 12, "success": true}
	s.append(GameSession.check_entry({"skill": "perception"}, check))
	s.append(GameSession.check_entry({"skill": "perception"}, check))
	assert_int(s.chat.size()).is_equal(4)


func test_the_rolls_of_every_repeat_stay_on_the_line() -> void:
	var s := TestUtils.new_session()
	s.append(_effect("Скрытность — успех", [{"what": "Скрытность", "nat": 14, "total": 17}]))
	s.append(_effect("Скрытность — успех", [{"what": "Скрытность", "nat": 18, "total": 21}]))
	assert_int(s.chat.size()).is_equal(1)
	var text := RollParts.entry_text(s.chat[0])
	assert_str(text).contains("к20 14").contains("к20 18")


func test_the_chronicle_keeps_each_deed() -> void:
	var s := TestUtils.new_session()
	for i in 3:
		s.append(_effect("Взято: кружка"))
	assert_int(s.chronicle.size()).is_equal(3)


func test_the_master_hears_the_count() -> void:
	var s := TestUtils.new_session()
	for i in 3:
		s.append(_effect("Взято: кружка"))
	var told: Array[Dictionary] = s.history(2000)
	assert_str(str(told[-1]["text"])).is_equal("[Движок уже применил: Взято: кружка ×3]")


func test_a_folded_line_comes_back_from_a_save_and_folds_on() -> void:
	var s := TestUtils.new_session()
	for i in 3:
		s.append(_effect("Взято: кружка", [{"what": "Ловкость рук", "nat": 9, "total": 12}]))
	var back := GameSession.from_dict(JSON.parse_string(JSON.stringify(s.to_dict(50))))
	assert_int(back.chat.size()).is_equal(1)
	assert_that(back.chat[0]["times"]).is_equal(3)
	assert_int(typeof(back.chat[0]["times"])).is_equal(TYPE_INT)
	back.append(_effect("Взято: кружка"))  # typed lines now, untyped from the save: the same words
	assert_int(back.chat.size()).is_equal(1)
	assert_int(GameSession.times(back.chat[0])).is_equal(4)
