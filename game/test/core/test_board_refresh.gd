extends GdUnitTestSuite
## A notice board fills again (the author, after v0.7.22.33): unread until looked at, read while its orders hang,
## unread again 1d4 days after the first order is taken off it.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _order(s: GameSession, id: String) -> Dictionary:
	var q := {"id": id, "title": "Листок", "giver": "", "steps": [{"text": "Сделать"}], "board": {"room": s.room_id, "prop": "p1"}}
	var gen := WorldGen.generated(s)
	var all: Dictionary = gen.get("quests", {})
	all[id] = q
	gen["quests"] = all
	return q


func test_a_board_is_unread_until_looked_at() -> void:
	var s := TestUtils.new_session()
	assert_bool(QuestGen.board_unread(s, s.room_id, "p1")).is_true()
	QuestGen.mark_board_read(s, "p1")
	assert_bool(QuestGen.board_unread(s, s.room_id, "p1")).is_false()
	_order(s, "gen_q1")
	s.day += 5
	assert_bool(QuestGen.board_unread(s, s.room_id, "p1")).is_false()  # its orders still hang, nothing taken
	assert_str(QuestGen.board_why_not(s, data, "p1")).is_equal("BOARD_READ_TODAY")


## v0.8.4.25.4: the master's turn at a board that put no order up leaves it unread — the hero reads it again.
func test_a_board_is_read_only_once_an_order_hangs_on_it() -> void:
	var s := TestUtils.new_session()
	var plan := {"quest": {"title": "Листок", "giver": "", "steps": [{"text": "Сделать"}], "board": {"room": s.room_id, "prop": "p1"}}}
	assert_str(QuestGen.board_why_not(s, data, "p1")).is_empty()
	assert_bool(QuestGen.board_unread(s, s.room_id, "p1")).is_true()  # nothing was put up: still to read
	QuestGen.apply_quest(s, data.duplicate(true), plan)  # the world grows in this test only
	assert_bool(QuestGen.board_unread(s, s.room_id, "p1")).is_false()
	assert_str(QuestGen.board_why_not(s, data, "p1")).is_equal("BOARD_READ_TODAY")


func test_taking_an_order_fills_the_board_again_in_d4_days() -> void:
	var s := TestUtils.new_session()
	QuestGen.mark_board_read(s, "p1")
	var q := _order(s, "gen_q1")
	QuestGen.board_taken(s, data, q)
	var fresh := int(QuestGen.board_state(s, s.room_id, "p1")["fresh_day"])
	assert_int(fresh - s.day).is_between(1, 4)
	QuestGen.board_taken(s, data, q)  # a second order the same day does not move it
	assert_int(int(QuestGen.board_state(s, s.room_id, "p1")["fresh_day"])).is_equal(fresh)
	s.day = fresh - 1
	assert_bool(QuestGen.board_unread(s, s.room_id, "p1")).is_false()
	s.day = fresh
	assert_bool(QuestGen.board_unread(s, s.room_id, "p1")).is_true()
	assert_str(QuestGen.board_why_not(s, data, "p1")).is_empty()
	QuestGen.mark_board_read(s, "p1")
	assert_bool(QuestGen.board_unread(s, s.room_id, "p1")).is_false()
