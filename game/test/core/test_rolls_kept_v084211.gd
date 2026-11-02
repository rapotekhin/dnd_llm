extends GdUnitTestSuite
## v0.8.4.21.1: a fight's rolls stay in the chat after it — a round's engine lines with their breakdowns as one entry,
## not in the master's history and not in the chronicle.


func test_a_round_s_rolls_are_one_entry_of_the_chat() -> void:
	var s := TestUtils.new_session()
	var lines := ["Серый волк — Укус: 15 + 4 = 19 против КД 18 — попадание, 6 (колющий)", "Вы — Длинный меч: 7 + 5 = 12 против КД 13 — промах"]
	var e := s.append(GameSession.rolls_entry(2, lines, {lines[0]: "к20 15 · Сила +2 · умение +2"}))
	assert_str(str(e["kind"])).is_equal(GameSession.KIND_ROLLS)
	assert_int(int(e["round"])).is_equal(2)
	assert_array(e["lines"]).is_equal(lines)
	assert_str(str(e["tips"][lines[0]])).contains("к20 15")
	lines.clear()  # the entry keeps its own copy
	assert_int((e["lines"] as Array).size()).is_equal(2)
	assert_array(s.history(10000)).is_empty()
	assert_array(s.chronicle).is_empty()
