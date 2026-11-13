extends GdUnitTestSuite
## Spot areas (v0.8.4.43.48): squares of one spot group side by side are one spot — a thing stands wholly inside it, of the
## group's bodies only one that fits; a lone square lets a bigger thing spread round it as before. The chunk editor draws
## the area and the thing that will stand there.

var data: Dictionary


func before() -> void:
	data = TestUtils.data().duplicate(true)


func _map(rows: Array, marks: Array) -> Dictionary:
	return {"rows": rows, "marks": marks}


func test_squares_of_one_group_side_by_side_are_one_spot() -> void:
	var marks := [
		{"name": "spot:table", "x": 2, "y": 1, "room": 0}, {"name": "spot:table", "x": 3, "y": 1, "room": 0},
		{"name": "spot:storage", "x": 4, "y": 1, "room": 0}, {"name": "spot:table", "x": 2, "y": 3, "room": 0},
	]
	var got := MapSpots.spot_marks(_map([], marks), 0)
	assert_int(got.size()).is_equal(3)
	assert_array(got[0]["area"]).contains_exactly([Vector2i(2, 1), Vector2i(3, 1)])
	assert_str(str(got[1]["group"])).is_equal("storage")
	assert_array(got[2]["area"]).contains_exactly([Vector2i(2, 3)])


func test_every_table_of_the_tavern_stands_on_its_area_for_every_seed() -> void:
	var s := TestUtils.new_session()
	s.room_id = "brod-tavern-hall"
	s.props[s.room_id] = []
	for seed: int in 12:
		s.game_seed = 100 + seed
		s.layout_cache.clear()
		s.layouts.erase("picks")
		var view := WalkRules.view(s, data)
		var index := (view["ids"] as Array).find(s.room_id)
		var areas := MapSpots.spot_marks(view, index).filter(func(sp: Dictionary) -> bool: return str(sp["group"]) == "table")
		assert_int(areas.size()).is_greater(0)
		var tables := MapSpots.of(s, data, view).filter(func(t: Dictionary) -> bool: return str(t.get("body", "")) == "table")
		for t: Dictionary in tables:  # a table takes exactly the two squares of one area, never spread round it
			var on := areas.any(func(sp: Dictionary) -> bool:
				return (sp["area"] as Array).size() == 2 and (t["cells"] as Array).all(func(c: Vector2i) -> bool: return (sp["area"] as Array).has(c)))
			assert_bool(on).override_failure_message("seed %d: table %s off its area" % [s.game_seed, t["cells"]]).is_true()


func test_an_area_takes_only_what_fits_in_it() -> void:
	var s := TestUtils.new_session()
	s.room_id = "brod-tavern-hall"
	s.props[s.room_id] = []
	var view := WalkRules.view(s, data)
	var index := (view["ids"] as Array).find(s.room_id)
	var sp: Dictionary = MapSpots.spot_marks(view, index).filter(func(x: Dictionary) -> bool: return str(x["group"]) == "table")[0]
	var spots: Array[Vector2i] = []
	spots.assign(sp["area"])
	var none: Array[Vector2i] = []
	assert_bool(bool(MapSpots._on_spot(data, "cart", "k", sp, spots, spots, none, {}, {}).get("loose", false))).is_true()  # a cart of 3×2 is not for an area of two
	var laid := MapSpots._on_spot(data, "table", "k", sp, spots, spots, none, {}, {})
	assert_bool(bool(laid.get("loose", false))).is_false()
	assert_array(laid["cells"]).contains_exactly_in_any_order(sp["area"])
