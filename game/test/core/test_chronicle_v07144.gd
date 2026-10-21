extends GdUnitTestSuite
## «Последствия и время» (roadmap v0.7.14.4): every line of the engine goes to the chronicle with its day, time and
## room — the journal's «Хроника» and the master's memory of what already happened.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func test_engine_lines_go_to_the_chronicle_with_their_time_and_room() -> void:
	var s := TestUtils.new_session()
	s.room_id = "brod-temple"
	s.day = 2
	s.minute = 9 * 60 + 12
	s.append(GameSession.effect_entry(["Убийство: Кейра — видели: Бруно Хмель"] as Array[String]))
	s.append({"kind": GameSession.KIND_DM, "text": "Слова мастера в хронику не идут."})
	assert_int(s.chronicle.size()).is_equal(1)
	assert_array(s.chronicle_tail(data["world"], 5)).contains_exactly(["день 2, 09:12, Храм Светлой Матери — Убийство: Кейра — видели: Бруно Хмель"])


func test_the_master_gets_the_facts_not_the_walking() -> void:
	var s := TestUtils.new_session()
	for i in 20:
		s.append(GameSession.effect_entry(["Переход: Рыночная площадь"] as Array[String]))
	s.append(GameSession.effect_entry(["+5 зм"] as Array[String]))
	var snap := TurnSnapshot.build(s, data, 2000)
	assert_int((snap["scene"]["chronicle"] as Array).size()).is_equal(1)
	assert_str(str(snap["scene"]["chronicle"][0])).ends_with("+5 зм")


func test_the_chronicle_keeps_the_newest() -> void:
	var s := TestUtils.new_session()
	for i in GameSession.CHRONICLE_MAX + 10:
		s.append(GameSession.effect_entry(["событие %d" % i] as Array[String]))
	assert_int(s.chronicle.size()).is_equal(GameSession.CHRONICLE_MAX)
	assert_str(str(s.chronicle[-1]["text"])).is_equal("событие %d" % (GameSession.CHRONICLE_MAX + 9))
	var back := GameSession.from_dict(s.to_dict(50))
	assert_int(back.chronicle.size()).is_equal(GameSession.CHRONICLE_MAX)


func test_an_old_save_starts_the_chronicle_from_its_chat() -> void:
	var v22 := {"save_version": 22, "session": {"day": 3, "minute": 600, "room_id": "brod-square",
		"chat": [{"kind": "effect", "lines": ["+2 зм"]}, {"kind": "dm", "text": "…"}]}}
	SaveFormat._v22_to_v23(v22, {})
	assert_array(v22["session"]["chronicle"]).has_size(1)
	assert_int(int(v22["session"]["chronicle"][0]["day"])).is_equal(3)
