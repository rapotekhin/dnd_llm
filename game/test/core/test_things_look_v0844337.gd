extends GdUnitTestSuite
## v0.8.4.43.37: the look of the things of a map — a thing in pictures of its own variants by its square's number, a natural
## one sized and shifted a little by its square, like ones side by side drawn as one picture of their group (a ridge of
## boulders, a grove); the squares keep their rules.

var lib: Dictionary
var keys: Array[String] = ["open", "*"]


func before() -> void:
	lib = TestUtils.data().duplicate(true)["layouts"]


func test_a_square_keeps_its_variant_and_a_grove_has_more_than_one() -> void:
	assert_int(LayoutGen.cell_hash(3, 4, 77)).is_equal(LayoutGen.cell_hash(3, 4, 77))
	assert_int(LayoutGen.cell_hash(-5, 9, -1234567)).is_greater_equal(0)
	var seen := {}
	for x: int in 12:
		seen[LayoutGen.variant(lib, "tree", Vector2i(x, 0), 5)] = true
	assert_int(seen.size()).is_equal(int(lib["grounds"]["variants"]["tree"]))
	assert_str(LayoutGen.variant(lib, "door", Vector2i(1, 1), 5)).is_equal("door")
	assert_str(LayoutGen.prop_base(lib, "tree_v2")).is_equal("tree")
	assert_str(LayoutGen.prop_base(lib, "waterfall_left")).is_equal("waterfall")
	assert_str(LayoutGen.prop_base(lib, "grove_v1")).is_equal("grove")


func _ids(laid: Array[Dictionary]) -> Array:
	return laid.map(func(t: Dictionary) -> String: return LayoutGen.prop_base(lib, str(t["id"])))


func test_boulders_side_by_side_are_one_ridge_and_a_pair_stands_either_way() -> void:
	var ridge := _ids(LayoutGen.props_laid(lib, keys, ["BB.", "BB.", "..."], 3))
	assert_array(ridge).is_equal(["boulder_ridge", "", "", "", "", "", "", "", ""])
	var row := LayoutGen.props_laid(lib, keys, ["BBB"], 3)
	assert_array(_ids(row)).is_equal(["boulder_pair", "", "boulder"])
	assert_int(int(row[0]["turn"])).is_equal(0)
	var upright := LayoutGen.props_laid(lib, keys, ["B.", "B."], 3)
	assert_array(_ids(upright)).is_equal(["boulder_pair", "", "", ""])
	assert_int(int(upright[0]["turn"])).is_equal(1)
	assert_array(_ids(LayoutGen.props_laid(lib, keys, ["TT", "TT", "TB"], 3))).is_equal(["grove", "", "", "", "tree", "boulder"])


func test_every_drawn_thing_has_its_place_and_its_squares() -> void:
	var drawn := MapGround.prop_ids(lib)
	assert_int(drawn.size()).is_less_equal(MapGround.MAX_PROPS)
	for id: String in ["tree_v2", "boulder_v1", "grove", "grove_v1", "tree_pair", "boulder_ridge", "bush_v2"]:
		assert_bool(drawn.has(id)).override_failure_message(id).is_true()
	assert_vector(MapGround.dims_of(lib, "boulder_ridge_v1")).is_equal(Vector2(2, 2))
	assert_vector(MapGround.dims_of(lib, "tree_pair")).is_equal(Vector2(2, 1))
	for id: String in lib["grounds"]["natural"]["of"]:
		assert_bool(drawn.has(id)).override_failure_message(id).is_true()


func test_squares_side_by_side_take_their_variants_apart() -> void:
	var same := 0
	for y: int in 30:
		for x: int in 30:
			if LayoutGen.cell_hash(x, y, 91) % 3 == LayoutGen.cell_hash(x + 1, y, 91) % 3:
				same += 1
	assert_float(same / 900.0).is_less(0.42)
	assert_int(LayoutGen.cell_hash(7, 11, -5)).is_equal(2612891002)  # as map-view.js `cellHash` counts it
