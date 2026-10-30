extends GdUnitTestSuite
## «Забрать всё» (the author, after v0.7.8): the engine takes every portable thing of the room nobody owns, as long
## as the hero can carry it; the master only narrates.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func after_test() -> void:
	GameState.session = null
	GameState.busy_turn = ""


func _room(s: GameSession) -> void:
	s.props[s.room_id] = [
		{"id": "p1", "name": "Сальная свеча", "item_id": "candle", "owner": "", "state": ""},
		{"id": "p2", "name": "Кружка Горма", "item_id": "ale", "owner": TestUtils.INNKEEPER, "state": ""},
		{"id": "p3", "name": "Очаг", "item_id": "", "owner": "", "state": ""},
		{"id": "p4", "name": "Верёвка", "item_id": "rope", "owner": "", "state": ""},
	]


func test_takes_only_what_nobody_owns_and_can_be_carried() -> void:
	var s := TestUtils.new_session()
	_room(s)
	var plan := PropRules.take_all_plan(s, data)
	assert_array((plan["take"] as Array).map(func(p: Dictionary) -> String: return p["id"])).contains_exactly(["p1", "p4"])
	var names := PropRules.take_all(s, data)
	assert_array(names).has_size(2)
	assert_int(int(s.character["inventory"].get("candle", 0))).is_greater_equal(1)
	assert_array(PropRules.room_props(s, s.room_id).map(func(p: Dictionary) -> String: return p["id"])).contains_exactly(["p2", "p3"])
	assert_array(PropRules.take_all_plan(s, data)["take"]).is_empty()


func test_too_heavy_stays() -> void:
	var s := TestUtils.new_session()
	_room(s)
	s.character["abilities"]["str"] = 1  # capacity 15 lb, the pack is already heavier
	CharacterRules.refresh(s.character, data, s.items)
	var plan := PropRules.take_all_plan(s, data)
	assert_array(plan["take"]).is_empty()
	assert_array(plan["left"]).is_not_empty()


func test_a_chest_emptied_at_once() -> void:  # «Взять всё» in a container's window (v0.7.49.4)
	var s := TestUtils.new_session()
	s.props[s.room_id] = [{"id": "ch", "name": "Сундук", "item_id": "", "owner": "", "state": "", "container": "chest",
		"contents": {"candle": 3, "rope": 1}}]
	GameState.session = s
	assert_str(GameState.container_take_all("ch")).is_empty()
	assert_dict(PropRules.find(s, s.room_id, "ch")["contents"]).is_empty()
	assert_int(int(s.character["inventory"].get("candle", 0))).is_greater_equal(3)
	assert_int(int(s.character["inventory"].get("rope", 0))).is_greater_equal(1)
