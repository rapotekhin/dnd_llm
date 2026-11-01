extends GdUnitTestSuite
## v0.8.1: walking on a map. What the hero sees of it, a path by squares, where a click leads, where the hero stands
## after a walk and after a move that was no walk.

var data: Dictionary


func before() -> void:
	data = TestUtils.data().duplicate(true)


func _session(room: String = "brod-tavern-hall") -> GameSession:
	var s := TestUtils.new_session()
	s.game_seed = 42
	s.room_id = room
	return s


func _map(rows: Array[String], rooms: Array, ids: Array) -> Dictionary:
	return {"id": "t", "w": rows[0].length(), "h": rows.size(), "rows": rows, "rooms": PackedInt32Array(rooms), "ids": ids, "exits": [], "doors": [], "marks": []}


func test_a_path_never_cuts_a_corner() -> void:
	var rows: Array[String] = [".#", ".."]
	var map := _map(rows, [0, 0, 0, 0], ["a"])
	var path := WalkRules.path(map, data["layouts"], Vector2i(0, 0), Vector2i(1, 1))
	assert_array(path).is_equal([Vector2i(0, 1), Vector2i(1, 1)])


func test_a_path_goes_straight_on_the_diagonal_of_a_free_floor() -> void:
	var rows: Array[String] = ["...", "...", "..."]
	var map := _map(rows, [0, 0, 0, 0, 0, 0, 0, 0, 0], ["a"])
	assert_int(WalkRules.path(map, data["layouts"], Vector2i(0, 0), Vector2i(2, 2)).size()).is_equal(2)


func test_there_is_no_path_through_a_wall_or_onto_it() -> void:
	var rows: Array[String] = [".#."]
	var map := _map(rows, [0, -1, 1], ["a", "b"])
	assert_array(WalkRules.path(map, data["layouts"], Vector2i(0, 0), Vector2i(2, 0))).is_empty()
	assert_array(WalkRules.path(map, data["layouts"], Vector2i(0, 0), Vector2i(1, 0))).is_empty()
	assert_dict(WalkRules.plan(map, data["layouts"], Vector2i(0, 0), Vector2i(2, 0))).is_empty()


func test_a_leg_stops_before_the_first_square_of_another_room() -> void:
	var rows: Array[String] = ["...."]
	var map := _map(rows, [0, -1, 1, 1], ["a", "b"])
	var steps: Array[Vector2i] = [Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)]
	var leg := WalkRules.leg(map, steps, "a")
	assert_array(leg["steps"]).is_equal([Vector2i(1, 0)])
	assert_str(leg["room"]).is_equal("b")
	var near: Array[Vector2i] = [Vector2i(1, 0)]
	assert_str(WalkRules.leg(map, near, "a")["room"]).is_empty()


func test_a_click_on_a_way_out_walks_to_its_approach() -> void:
	var rows: Array[String] = ["..."]
	var map := _map(rows, [0, 0, 0], ["a"])
	map["exits"] = [{"to": "b", "room": "a", "x": 2, "y": 0, "ax": 1, "ay": 0, "side": "e", "kind": "door"}]
	var plan := WalkRules.plan(map, data["layouts"], Vector2i(0, 0), Vector2i(2, 0))
	assert_str(plan["exit"]).is_equal("b")
	assert_array(plan["path"]).is_equal([Vector2i(1, 0)])


func test_what_the_hero_never_saw_is_blank_and_a_door_to_it_a_wall() -> void:
	var s := _session()
	var seen := 0
	for room: String in data["world"]["rooms"]:
		s.room_id = room
		s.visited.clear()
		var whole := LayoutRules.map_of(s, data, room)
		var view := WalkRules.view(s, data)
		var open := WayRules.open_exits(s, data["world"], room)
		for i: int in (whole["ids"] as Array).size():
			var other := str(whole["ids"][i])
			if other == room or open.has(other):
				continue
			for y: int in int(whole["h"]):
				for x: int in int(whole["w"]):
					var door := (whole["doors"] as Array).any(func(d: Dictionary) -> bool: return int(d["x"]) == x and int(d["y"]) == y)
					if LayoutGen.room_at(whole, x, y) == i and not door:
						seen += 1
						assert_str((view["rows"] as Array[String])[y][x]).is_equal(LayoutGen.BLANK)
			for d: Dictionary in whole["doors"]:
				if i in [int(d["a"]), int(d["b"])]:
					assert_str((view["rows"] as Array[String])[int(d["y"])][int(d["x"])]).is_equal(LayoutGen.WALL)
	assert_int(seen).is_greater(0)


func test_the_view_changes_a_copy_not_the_kept_map() -> void:
	var s := _session()
	s.visited.clear()
	var before_rows: Array = (LayoutRules.map_of(s, data, s.room_id)["rows"] as Array).duplicate()
	WalkRules.view(s, data)
	assert_array(LayoutRules.map_of(s, data, s.room_id)["rows"]).is_equal(before_rows)


func test_every_room_has_a_spot_for_the_hero() -> void:
	var s := _session()
	for room: String in data["world"]["rooms"]:
		s.room_id = room
		s.layouts.erase("at")
		var map := WalkRules.view(s, data)
		var at := WalkRules.settle(s, data, map)
		assert_bool(WalkRules.passable(map, data["layouts"], at)).override_failure_message(room).is_true()


func test_a_walk_keeps_the_spot_and_a_jump_goes_by_the_way_back() -> void:
	var s := _session()
	var map := WalkRules.view(s, data)
	var at := WalkRules.settle(s, data, map)
	var other := WalkRules.around(map, data["layouts"], at, 1)[0]
	WalkRules.stand(s, map, s.room_id, other)
	assert_bool(WalkRules.settle(s, data, map) == other).is_true()
	s.room_id = "brod-square"  # a button, not a walk
	var street := WalkRules.view(s, data)
	var there := WalkRules.settle(s, data, street)
	assert_bool(WalkRules.passable(street, data["layouts"], there)).is_true()
	assert_str(str(s.layouts["at"]["room"])).is_equal("brod-square")
	assert_str(str(s.layouts["at"]["map"])).is_equal(str(street["id"]))


func test_the_spot_comes_back_from_a_save() -> void:
	var s := _session()
	var map := WalkRules.view(s, data)
	var at := WalkRules.settle(s, data, map)
	var back := GameSession.from_dict(JSON.parse_string(JSON.stringify(s.to_dict(5))))
	assert_bool(WalkRules.settle(back, data, WalkRules.view(back, data)) == at).is_true()


func test_those_who_walk_along_stand_on_free_squares() -> void:
	var s := _session()
	var map := WalkRules.view(s, data)
	var at := WalkRules.settle(s, data, map)
	var spots := WalkRules.around(map, data["layouts"], at, 3)
	assert_int(spots.size()).is_equal(3)
	for spot: Vector2i in spots:
		assert_bool(WalkRules.passable(map, data["layouts"], spot)).is_true()
		assert_bool(spot == at).is_false()
