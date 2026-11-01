extends GdUnitTestSuite
## v0.8.2: people and things on the map. Everyone of the room has a square of its own, the same one until the hour turns;
## a trader stands at its counter; furniture stays words; the master moves people by words and sees no squares.

var data: Dictionary


func before() -> void:
	data = TestUtils.data().duplicate(true)


func _session(room: String = "brod-tavern-hall") -> GameSession:
	var s := TestUtils.new_session()
	s.game_seed = 42
	s.room_id = room
	return s


func _tokens(s: GameSession) -> Array[Dictionary]:
	return MapSpots.of(s, data, WalkRules.view(s, data))


func _token(s: GameSession, ref: String) -> Dictionary:
	for t: Dictionary in _tokens(s):
		if str(t["ref"]) == ref:
			return t
	return {}


func _at(t: Dictionary) -> Vector2i:
	return Vector2i(int(t["x"]), int(t["y"]))


func test_everyone_of_every_room_stands_on_a_free_square_of_that_room() -> void:
	var s := _session()
	for room: String in data["world"]["rooms"]:
		s.room_id = room
		var map := WalkRules.view(s, data)
		var seen := {}
		for t: Dictionary in MapSpots.of(s, data, map):
			if str(t["kind"]) == "station":
				continue
			var at := _at(t)
			assert_bool(seen.has(at)).override_failure_message("%s: two on %s" % [room, at]).is_false()
			seen[at] = true
			assert_str(WalkRules.room_of(map, at)).is_equal(room)
			assert_bool(WalkRules.passable(map, data["layouts"], at)).is_true()


func test_a_spot_stays_while_the_hour_stays() -> void:
	var s := _session()
	assert_array(_tokens(s)).is_equal(_tokens(s))


func test_a_spot_comes_back_from_a_save() -> void:
	var s := _session()
	var before_load := _tokens(s)
	var back := GameSession.from_dict(JSON.parse_string(JSON.stringify(s.to_dict(5))))
	assert_array(_tokens(back)).is_equal(before_load)


func test_a_trader_stands_by_its_counter() -> void:
	var s := _session()
	var map := WalkRules.view(s, data)
	var bruno: Dictionary = {}
	for t: Dictionary in MapSpots.of(s, data, map):
		if WorldView.new(data["world"]).is_trader(str(t["id"])):
			bruno = t
	assert_dict(bruno).is_not_empty()
	var counters := (map["marks"] as Array).filter(func(m: Dictionary) -> bool: return str(m["name"]) == "counter")
	if not counters.is_empty():
		assert_int(WalkRules.distance(_at(bruno), Vector2i(int(counters[0]["x"]), int(counters[0]["y"])))).is_less_equal(3)


func test_followers_walk_with_the_hero_and_are_no_tokens() -> void:
	var s := _session()
	var id := str(s.npcs_here(data["world"], s.room_id)[0])
	assert_dict(_token(s, "npc:" + id)).is_not_empty()
	FollowRules.apply(s, {"follow_npc": id, "on": true, "room": ""})
	assert_dict(_token(s, "npc:" + id)).is_empty()


func test_furniture_stays_words_and_what_can_be_used_is_on_the_map() -> void:
	var s := _session()
	s.props[s.room_id] = [
		{"id": "bench", "name": "Скамья", "item_id": "", "owner": "", "text": "", "state": ""},
		{"id": "mug", "name": "Кружка", "item_id": "ale", "owner": "", "text": "", "state": ""},
		{"id": "box", "name": "Сундук", "item_id": "", "owner": "", "text": "", "state": "", "container": "chest"},
		{"id": "sign", "name": "Вывеска", "item_id": "", "owner": "", "text": "Эль", "state": ""},
	]
	assert_dict(_token(s, "prop:bench")).is_empty()
	for ref: String in ["prop:mug", "prop:box", "prop:sign"]:
		assert_dict(_token(s, ref)).is_not_empty()


func test_a_thing_stands_by_the_mark_the_master_named() -> void:
	var s := _session()
	var map := WalkRules.view(s, data)
	var mark: Dictionary = (map["marks"] as Array).filter(func(m: Dictionary) -> bool: return str(m["name"]) != LayoutGen.ENTRY)[0]
	s.props[s.room_id] = [{"id": "box", "name": "Сундук", "item_id": "", "owner": "", "text": "", "state": "", "container": "chest", "near": str(mark["name"])}]
	assert_int(WalkRules.distance(_at(_token(s, "prop:box")), Vector2i(int(mark["x"]), int(mark["y"])))).is_less_equal(3)


func test_the_master_walks_the_hero_up_to_a_person() -> void:
	var s := _session()
	var id := str(s.npcs_here(data["world"], s.room_id)[0])
	var plan := MapSpots.plan(s, data, {"who": "hero", "to": id})
	assert_dict(plan).contains_keys(["plan", "summary"])
	MapSpots.apply(s, data, plan["plan"])
	var map := WalkRules.view(s, data)
	assert_int(WalkRules.distance(WalkRules.settle(s, data, map), _at(_token(s, "npc:" + id)))).is_less_equal(1)


func test_the_master_walks_a_person_up_to_the_hero_until_the_hour_turns() -> void:
	var s := _session()
	var map := WalkRules.view(s, data)
	var hero := WalkRules.settle(s, data, map)
	var id := str(s.npcs_here(data["world"], s.room_id)[0])
	MapSpots.apply(s, data, MapSpots.plan(s, data, {"who": id, "to": "hero"})["plan"])
	assert_int(WalkRules.distance(hero, _at(_token(s, "npc:" + id)))).is_less_equal(1)
	s.layouts["moved"][id]["part"] = "иное время"
	assert_dict(_token(s, "npc:" + id)).is_not_empty()


func test_the_master_cannot_walk_to_what_is_not_here() -> void:
	var s := _session()
	assert_dict(MapSpots.plan(s, data, {"who": "hero", "to": "nobody"})).contains_keys(["reason"])
	assert_dict(MapSpots.plan(s, data, {"who": "nobody", "to": "hero"})).contains_keys(["reason"])
	assert_dict(MapSpots.plan(s, data, {"who": "hero", "to": "hero"})).contains_keys(["reason"])


func test_the_master_gets_words_not_squares() -> void:
	var s := _session()
	var snap := TurnSnapshot.build(s, data, 2000)
	var scene: Dictionary = snap["scene"]
	assert_array(scene["spots"]).is_not_empty()
	assert_str(str(scene["spots"][0])).contains("[")
	var words: Array = (data["rules"]["map"]["distance"] as Array).map(func(d: Dictionary) -> String: return str(d["word"]))
	for n: Dictionary in scene["npcs"]:
		assert_array(words).contains([n["near"]])
	assert_bool(JSON.stringify(scene).contains("\"x\":")).is_false()


func test_a_way_up_stays_in_the_room_and_stops_in_reach() -> void:
	var rows: Array[String] = ["....."]
	var map := {"id": "t", "w": 5, "h": 1, "rows": rows, "rooms": PackedInt32Array([0, 0, 0, 1, 1]), "ids": ["a", "b"], "exits": [], "doors": [], "marks": []}
	var lib: Dictionary = data["layouts"]
	assert_array(WalkRules.near(map, lib, Vector2i(0, 0), Vector2i(2, 0), 1, "a")).is_equal([Vector2i(1, 0)])
	assert_array(WalkRules.near(map, lib, Vector2i(1, 0), Vector2i(2, 0), 1, "a")).is_empty()
	assert_array(WalkRules.near(map, lib, Vector2i(0, 0), Vector2i(4, 0), 1, "a")).is_empty()
