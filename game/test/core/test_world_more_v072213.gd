extends GdUnitTestSuite
## The master makes the world more willingly (roadmap v0.7.22.13): the menhir's ending needs the hero to know what it
## holds; a notice board is a window of real orders, read once a day.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func test_the_menhir_ending_needs_knowing() -> void:
	var s := TestUtils.new_session()
	var world: Dictionary = data["world"]
	s.quests_active["ash_over_the_march"] = 3  # the menhir's step
	s.room_id = "pushcha-glade"
	assert_array(QuestRules.choices_here(s, world)).is_empty()  # killed the priest, never looked at the stone
	assert_str(QuestRules.step_text(s, world, "ash_over_the_march")).contains("сначала поймите")
	s.revealed["pushcha-glade"] = ["runes"]
	assert_int(QuestRules.choices_here(s, world).size()).is_equal(2)
	s.revealed.erase("pushcha-glade")
	s.flags.append("menhir_understood")  # the hermit told it
	assert_int(QuestRules.choices_here(s, world).size()).is_equal(2)
	assert_bool(QuestRules.known_flags(world).has("menhir_understood")).is_true()  # the master may set it


func test_a_board_and_its_reading() -> void:
	var s := TestUtils.new_session()
	assert_bool(QuestGen.is_board(data, {"name": "Доска объявлений"})).is_true()
	assert_bool(QuestGen.is_board(data, {"name": "Столб с листками"})).is_true()
	assert_bool(QuestGen.is_board(data, {"name": "Стол"})).is_false()
	assert_str(QuestGen.board_why_not(s, data, "p1")).is_empty()
	QuestGen.mark_board_read(s, "p1")
	assert_str(QuestGen.board_why_not(s, data, "p1")).is_equal("BOARD_READ_TODAY")
	s.day += 1
	assert_str(QuestGen.board_why_not(s, data, "p1")).is_empty()
