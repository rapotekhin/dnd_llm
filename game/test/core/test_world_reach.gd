extends GdUnitTestSuite
## A place may grow on an open edge of the known world, not only of the hero's room (the author, 2026-10-24): asked of
## the innkeeper in the tavern, a bakery «outside the town» is built at the North Gate; the hero stays where he is.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _bakery() -> Dictionary:
	return {"key": "bakery", "name": "Пекарня Хильды", "description": "Тёплая пекарня за воротами, пахнет хлебом.", "exits": []}


func test_the_tavern_sees_the_edges_of_the_town() -> void:
	var s := TestUtils.new_session()
	s.room_id = "brod-tavern-hall"
	assert_array(WorldGen.open_edges(s, data, s.room_id)).is_empty()
	var rooms: Array = WorldGen.reach_edges(s, data).map(func(e: Dictionary) -> String: return str(e["room_id"]))
	assert_array(rooms).contains(["brod-gate", "brod-square"])


func test_a_bakery_at_the_north_gate_from_the_tavern() -> void:
	var s := TestUtils.new_session()
	s.room_id = "brod-tavern-hall"
	var r := WorldGen.plan_place(s, data, {"room_id": "brod-gate", "edge": 0, "rooms": [_bakery()]}, true)
	assert_dict(r).contains_keys(["plan"])
	assert_str(str(r["summary"])).contains("Северные ворота")
	var first := WorldGen.apply_place(s, data, r["plan"])
	assert_str(s.room_id).is_equal("brod-tavern-hall")  # the hero does not go there
	assert_array(ExplorationRules.open_exits(s, data["world"], "brod-gate")).contains([first])
	assert_array(WorldGen.reach_edges(s, data).filter(func(e: Dictionary) -> bool: return str(e["room_id"]) == "brod-gate")).is_empty()  # the edge is used


func test_no_room_id_and_no_edge_here_names_the_known_ones() -> void:
	var s := TestUtils.new_session()
	s.room_id = "brod-tavern-hall"
	var r := WorldGen.plan_place(s, data, {"edge": 0, "rooms": [_bakery()]}, true)
	assert_str(str(r.get("reason", ""))).contains("brod-gate")


func test_the_reach_is_set_by_the_rules() -> void:
	var s := TestUtils.new_session()
	s.room_id = "brod-tavern-hall"
	var narrow := data.duplicate()
	narrow["rules"] = (data["rules"] as Dictionary).duplicate(true)
	narrow["rules"]["world_gen"]["edge_reach"] = {"neighbours": false, "visited": false}
	assert_dict(WorldGen.plan_place(s, narrow, {"room_id": "brod-gate", "edge": 0, "rooms": [_bakery()]}, true)).contains_keys(["plan"])
	assert_dict(WorldGen.plan_place(s, narrow, {"room_id": "pushcha-edge", "edge": 0, "rooms": [_bakery()]}, true)).contains_keys(["reason"])
