extends GdUnitTestSuite
## The master and the turn (roadmap v0.7.22.20, the author's fixes check #8): a room the master described today is
## entered again with one line of the engine — the place and who is here — and no master's turn.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _session(room: String) -> GameSession:
	var s := TestUtils.new_session()
	s.room_id = room
	s.props[room] = [{"id": "p1", "name": "Стол", "description": "", "item_id": "", "owner": "", "text": "", "state": ""}]
	return s


func test_described_today_gives_the_engines_line() -> void:
	var s := _session("brod-tavern-hall")
	assert_str(ExplorationRules.again_line(s, data, s.room_id)).is_empty()  # not described yet: the master's turn
	s.described[s.room_id] = s.day
	var line := ExplorationRules.again_line(s, data, s.room_id)
	assert_str(line).contains(str(data["world"]["rooms"]["brod-tavern-hall"]["name"]))
	for id: String in s.npcs_here(data["world"], s.room_id):
		assert_str(line).contains(str(data["world"]["npcs"][id]["name"]))
	s.day += 1
	assert_str(ExplorationRules.again_line(s, data, s.room_id)).is_empty()  # a new day: described anew


func test_a_room_to_furnish_is_always_the_masters() -> void:
	var s := _session("brod-square")
	s.props.erase("brod-square")
	s.described["brod-square"] = s.day
	assert_str(ExplorationRules.again_line(s, data, "brod-square")).is_empty()


func test_a_pack_may_give_its_own_lines() -> void:
	var s := _session("brod-tavern-hall")
	s.described[s.room_id] = s.day
	var own := data.duplicate()
	own["world"] = (data["world"] as Dictionary).duplicate()
	own["world"]["revisit"] = ["Опять {place}!"]
	assert_str(ExplorationRules.again_line(s, own, s.room_id)).starts_with("Опять ")


func test_the_described_days_survive_the_save() -> void:
	var s := _session("brod-tavern-hall")
	s.described["brod-tavern-hall"] = 3
	var back := GameSession.from_dict(s.to_dict(5))
	assert_int(int(back.described["brod-tavern-hall"])).is_equal(3)
	var old := {"save_version": 39, "session": {}}
	SaveFormat.migrate(old)
	assert_dict(old["session"]["described"]).is_empty()
