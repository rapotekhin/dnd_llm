extends GdUnitTestSuite
## v0.8.4.44.2.1, the author's question (2026-11-14): «почему таверна каждый раз генерирует фурнитуру рандомно, если она
## в редакторе стоит в другом месте». A room that wants a mark takes a chunk where the mark is drawn first; a chunk stands
## as the author drew it unless that does not join its neighbours; a station's thing stands where the furnishing sets it,
## even off the marks of its station — the counter the author moved is the counter, a hearth is the hearth by its body.

var data: Dictionary
var lib: Dictionary


func before_test() -> void:
	data = TestUtils.data()
	lib = data["layouts"]


func test_a_hall_that_wants_a_stage_takes_a_chunk_with_the_stage_drawn() -> void:
	var ask := {"id": "hall", "kind": "tavern", "role": "hall", "tags": ["stage"], "marks": ["stage"], "size": "large"}
	for sd: int in 20:
		var rng := RandomNumberGenerator.new()
		rng.seed = sd
		var first: Dictionary = LayoutGen.candidates(lib, ask, rng)[0]
		assert_array((first.get("marks", {}) as Dictionary).values()).override_failure_message("seed %d: %s" % [sd, first["id"]]).contains(["stage"])


func test_a_room_on_its_own_stands_as_drawn() -> void:
	var ask := {"id": "hall", "kind": "tavern", "role": "hall", "tags": ["stage"], "marks": ["stage"], "size": "large", "links": [], "exits": []}
	for sd: int in 12:
		var pick: Dictionary = LayoutGen.stitched(lib, [ask], sd, {})["picks"]["hall"]
		assert_int(int(pick["rot"])).override_failure_message("seed %d" % sd).is_equal(0)
		assert_bool(bool(pick["flip"])).override_failure_message("seed %d" % sd).is_false()


func test_a_station_moved_off_its_marks_stands_where_the_furnishing_sets_it() -> void:
	var drawn := [{"name": "counter", "x": 2, "y": 2, "room": 0}, {"name": "counter", "x": 3, "y": 2, "room": 0},
		{"name": "counter", "x": 4, "y": 2, "room": 0}, {"name": "hearth", "x": 9, "y": 1, "room": 0}]
	var counter := {"name": LayoutGen.SET + "counter", "x": 1, "y": 6, "room": 0, "set": 0, "piece": "0,0", "station": "counter"}
	var hearth := {"name": LayoutGen.SET + "hearth", "x": 9, "y": 1, "room": 0, "set": 0, "piece": "0,0"}  # on its mark, no `station`
	var map := {"ids": ["r"], "marks": drawn + [counter, hearth]}
	var got := MapSpots.marks_set(data, map, 0, [counter, hearth])
	var of := func(name: String) -> Array:
		return got.filter(func(m: Dictionary) -> bool: return str(m["name"]) == name).map(func(m: Dictionary) -> Vector2i: return Vector2i(int(m["x"]), int(m["y"])))
	assert_array(of.call("counter")).contains_exactly([Vector2i(1, 6)])  # the drawn run is left: the counter is where it was moved
	assert_array(of.call("hearth")).contains_exactly([Vector2i(9, 1)])  # kept on its mark: the marks as drawn


func test_a_station_s_thing_is_its_station_by_its_body() -> void:
	assert_str(MapSpots.station_of(data, {"name": LayoutGen.SET + "hearth"})).is_equal("hearth")
	assert_str(MapSpots.station_of(data, {"name": LayoutGen.SET + "workbench"})).is_equal("bench")
	assert_str(MapSpots.station_of(data, {"name": LayoutGen.SET + "well"})).is_equal("water")
	assert_str(MapSpots.station_of(data, {"name": LayoutGen.SET + "bench"})).is_empty()  # a seat, not a workbench
	assert_str(MapSpots.station_of(data, {"name": LayoutGen.SET + "table"})).is_empty()
	var drawn := [{"name": "hearth", "x": 1, "y": 1, "room": 0}]
	var off := {"name": LayoutGen.SET + "hearth", "x": 6, "y": 4, "room": 0, "set": 0, "piece": "0,0"}
	var got := MapSpots.marks_set(data, {"ids": ["r"], "marks": drawn + [off]}, 0, [off])
	var hearths := got.filter(func(m: Dictionary) -> bool: return str(m["name"]) == "hearth")
	assert_array(hearths).has_size(1)  # one hearth, where the author set it — not a second one at the drawn mark
	assert_int(int(hearths[0]["x"])).is_equal(6)


func test_the_brod_tavern_stands_its_moved_counter_and_one_of_each_station() -> void:
	var s := TestUtils.new_session()
	s.room_id = "brod-tavern-hall"
	s.props[s.room_id] = []
	for sd: int in 8:
		s.game_seed = 300 + sd
		s.layout_cache.clear()
		s.layouts.erase("picks")
		var map := WalkRules.view(s, data)
		var index := (map["ids"] as Array).find(s.room_id)
		var arranged := MapSpots.arranged(data, map, index, "%d|%s" % [s.game_seed, s.room_id], LayoutGen.ground_keys(lib, map))
		var tokens := MapSpots.of(s, data, map)
		for m: Dictionary in arranged:
			var station := MapSpots.station_of(data, m)
			if station.is_empty():
				continue
			var laid := MapSpots.set_laid(data, m)
			var body := str(m["name"]).substr(LayoutGen.SET.length())
			var on := tokens.any(func(t: Dictionary) -> bool:
				return str(t.get("body", "")) == body and (t["cells"] as Array).all(func(c: Vector2i) -> bool: return (laid["cells"] as Array).has(c)))
			assert_bool(on).override_failure_message("seed %d: %s at %s not where the furnishing sets it" % [s.game_seed, body, laid["cells"]]).is_true()
