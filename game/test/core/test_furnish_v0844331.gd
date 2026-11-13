extends GdUnitTestSuite
## v0.8.4.43.31: furnishings of a chunk — lists of things laid by the author (`furnish` of a chunk in layouts.json).
## The generator turns them with their chunk and mixes the things of all furnishings: each stands where it meets none.

var data: Dictionary


func before() -> void:
	data = TestUtils.data().duplicate(true)


func test_a_square_turns_with_its_chunk_as_the_rows_do() -> void:
	var rows: Array[String] = ["abc", "def"]
	for rot: int in 4:
		for flip: bool in [false, true]:
			var turned := LayoutGen.turned(rows, rot, flip)
			for y: int in 2:
				for x: int in 3:
					var c := LayoutGen.turn_cell(Vector2i(x, y), 3, 2, rot, flip)
					assert_str(turned[c.y][c.x]).override_failure_message("%d %s %d,%d" % [rot, flip, x, y]).is_equal(rows[y][x])
					var o := LayoutGen.turn_cell(Vector2i(0, 0), 3, 2, rot, flip)
					assert_that(c - o).is_equal(LayoutGen.turn_offset(Vector2i(x, y), rot, flip))


func test_a_thing_of_a_furnishing_keeps_its_shape_on_the_turned_chunk() -> void:
	for rot: int in 4:
		for flip: bool in [false, true]:
			for turn: int in 4:
				var laid := MapSpots.set_laid(data, {"name": LayoutGen.SET + "bed", "x": 5, "y": 5, "turn": turn, "rot": rot, "flip": flip})
				var cells: Array = laid["cells"]
				assert_bool(cells.has(Vector2i(5, 5))).is_true()
				var want := MapSpots.footprint([2, 1], laid["at"], int(laid["turn"]))
				assert_int(cells.size()).is_equal(want.size())
				for c: Vector2i in want:
					assert_bool(cells.has(c)).override_failure_message("%d %s %d" % [rot, flip, turn]).is_true()


func test_the_furnishings_of_a_room_mix_and_never_meet() -> void:
	var s := TestUtils.new_session()
	s.room_id = "brod-tavern-hall"
	s.props[s.room_id] = []
	var map := WalkRules.view(s, data)
	var chunk_id := str(map["picks"][s.room_id]["chunk"])
	var chunk: Dictionary = (data["layouts"]["chunks"] as Array).filter(func(c: Dictionary) -> bool: return str(c["id"]) == chunk_id)[0]
	var rows: Array = chunk["rows"]
	var free: Array[Vector2i] = []  # plain floor with plain floor all round: no mark, no wall near
	for y: int in range(2, rows.size() - 2):
		for x: int in range(2, str(rows[y]).length() - 2):
			var plain := true
			for dy: int in [-1, 0, 1]:
				for dx: int in [-1, 0, 1]:
					plain = plain and str(rows[y + dy])[x + dx] == "."
			if plain:
				free.append(Vector2i(x, y))
	assert_int(free.size()).is_greater(1)
	var a := free[0]
	var b := free[free.size() - 1]
	chunk["furnish"] = [
		{"name": "одна", "things": [{"body": "stool", "x": a.x, "y": a.y}, {"body": "barrel", "x": b.x, "y": b.y}]},
		{"name": "другая", "things": [{"body": "crate", "x": a.x, "y": a.y}, {"body": "chest", "x": b.x, "y": b.y}]},
	]
	var mixed := false
	for seed: int in 30:
		s.game_seed = 100 + seed
		s.layout_cache.clear()
		var tokens := MapSpots.of(s, data, WalkRules.view(s, data))
		var mine := tokens.filter(func(t: Dictionary) -> bool: return t.has("set"))
		assert_int(mine.size()).override_failure_message("seed %d" % seed).is_between(1, 2)
		var seen := {}
		for t: Dictionary in tokens:
			if not t.has("cells"):
				continue
			for c: Vector2i in t["cells"]:
				assert_bool(seen.has(c)).override_failure_message("seed %d: two things on %s" % [seed, c]).is_false()
				seen[c] = true
		var sets := {}
		for t: Dictionary in mine:
			assert_bool(str(t["body"]) in ["stool", "barrel", "crate", "chest"]).is_true()
			sets[int(t["set"])] = true
		mixed = mixed or sets.size() == 2
	assert_bool(mixed).override_failure_message("never a thing of each furnishing in one room").is_true()


func test_a_furnishings_thing_is_no_place_the_master_names() -> void:
	var s := TestUtils.new_session()
	s.room_id = "brod-tavern-hall"
	var map := WalkRules.view(s, data)
	var chunk_id := str(map["picks"][s.room_id]["chunk"])
	for c: Dictionary in data["layouts"]["chunks"]:
		if str(c["id"]) == chunk_id:
			c["furnish"] = [{"name": "одна", "things": [{"body": "stool", "x": 3, "y": 3}]}]
	s.layout_cache.clear()
	for line: String in MapSpots.words(s, data):
		assert_str(line).not_contains(LayoutGen.SET)
