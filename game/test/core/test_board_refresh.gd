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


func test_an_old_save_keeps_its_read_day() -> void:
	var d := {"session": {"generated": {"boards_read": {"board:r:p1": 3}}}}
	SaveFormat._v45_to_v46(d, {})
	assert_dict(d["session"]["generated"]["boards_read"]["board:r:p1"]).is_equal({"read_day": 3, "fresh_day": 0})
