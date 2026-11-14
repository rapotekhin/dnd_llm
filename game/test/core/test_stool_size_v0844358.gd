extends GdUnitTestSuite
## v0.8.4.43.58, the author: «табурет размером с бочку, давай его в два раза уменьшим». A thing's picture is sized to its
## squares by a row of data (`grounds.size`, read by MapGround.per_prop for the shader's `prop_size`), centred on them;
## its squares and what they bar stay as they were.

var lib: Dictionary


func before() -> void:
	lib = TestUtils.data().duplicate(true)["layouts"]


func _of(key: String, fallback: float, id: String) -> float:
	var at := MapGround.prop_ids(lib).find(id)
	assert_int(at).override_failure_message(id).is_greater_equal(0)
	return MapGround.per_prop(lib, key, fallback)[at]


func test_a_stool_is_drawn_half_a_barrel() -> void:
	assert_float(_of("size", 1.0, "stool")).is_equal(0.5)
	assert_float(_of("size", 1.0, "barrel")).is_equal(1.0)  # not in the row: its whole square
	assert_float(_of("size", 1.0, "stool") / _of("size", 1.0, "barrel")).is_equal(0.5)
	assert_float(_of("size", 1.0, "tree")).is_equal_approx(1.7, 0.0001)  # a tree overflows its square as before


func test_a_stool_keeps_its_one_square_and_is_walked_round_as_before() -> void:
	assert_vector(MapGround.dims_of(lib, "stool")).is_equal(Vector2(1, 1))
	var body: Dictionary = MapGround.bodies_of()["stool"]
	assert_array(body["size"]).is_equal([1.0, 1.0])
	assert_array(body.get("blocks", [])).is_empty()


func test_one_reader_of_a_thing_s_number_for_every_row() -> void:
	assert_float(_of("thin", 0.0, "bench")).is_equal(0.5)  # v0.8.4.43.49
	assert_float(_of("thin", 0.0, "stool")).is_equal(0.0)
	assert_float(_of("shimmer", 0.0, "waterfall_left")).is_equal_approx(float(lib["grounds"]["shimmer"]["waterfall"]), 0.0001)  # a part reads its base
	assert_float(_of("size", 1.0, "tree_v2")).is_equal_approx(1.7, 0.0001)  # a variant reads its base
	var all := MapGround.per_prop(lib, "size", 1.0)
	assert_int(all.size()).is_equal(MapGround.MAX_PROPS)
	var drawn := MapGround.prop_ids(lib).size()
	if drawn < MapGround.MAX_PROPS:
		assert_float(all[drawn]).is_equal(1.0)  # past the things — the fallback
	assert_float(MapGround.per_prop(lib, "no_such_row", 0.25)[0]).is_equal(0.25)
