extends GdUnitTestSuite
## v0.8.4.43.44: new things of a map — a fence that turns along its like squares, the deep middle of a pond with its
## shallow rim kept and no lone deep square, a garden's beds of farmland in a town, graves on a graveyard's spots, the
## bodies of a trap, a grave, a mine timber, a rug and straw with their pictures.

var data: Dictionary
var lib: Dictionary


func before_test() -> void:
	data = TestUtils.data()
	lib = data["layouts"]


func test_a_fence_turns_along_its_line() -> void:
	var rows := ["fff", "f..", "f.."]
	assert_int(LayoutGen.prop_turn(lib, rows, 1, 0, "fence")).is_equal(0)  # along the row
	assert_int(LayoutGen.prop_turn(lib, rows, 0, 2, "fence")).is_equal(1)  # up and down
	assert_int(LayoutGen.prop_turn(lib, rows, 0, 0, "fence")).is_equal(0)  # a corner keeps the row
	assert_dict(LayoutGen.prop_at(lib, ["square", "open", "*"], rows, 0, 1)).is_equal({"id": "fence", "turn": 1})


func _deep(rows: Array) -> Array:
	var out := {"rows": rows}
	LayoutGen._deep(out, lib)
	return out["rows"]


func test_a_pond_has_its_deep_middle_and_a_shallow_rim() -> void:
	var rows := _deep(["~~~~~", "~~~~~", "~~~~~", "~~~~~", "~~~~~"])
	assert_array(rows).is_equal(["~~~~~", "~$$$~", "~$$$~", "~$$$~", "~~~~~"])
	assert_array(_deep([".....", ".~~~.", ".~~~.", ".~~~.", "....."])).is_equal([".....", ".~~~.", ".~~~.", ".~~~.", "....."])  # one deep square alone goes back


func test_deep_water_has_its_ground_and_a_bridge() -> void:
	var order: Array = lib["grounds"]["order"]
	assert_str(LayoutGen.ground_of(lib, ["field", "open", "*"], "$")).is_equal("deep_water")
	assert_str(LayoutGen.ground_of(lib, ["swamp", "open", "*"], "$")).is_equal("still_water")
	assert_int(order.find("deep_water")).is_less(order.find("water"))
	assert_str(str(lib["open"]["bridges"]["$"])).is_equal("_")
	assert_int(int(lib["cells"]["$"]["cost"])).is_greater(int(lib["cells"]["~"]["cost"]))


func test_a_town_garden_is_farmland_and_graves_lie_on_their_spots() -> void:
	assert_str(LayoutGen.ground_of(lib, ["square", "open", "*"], "%")).is_equal("farmland")
	var chunks: Dictionary = {}
	for c: Dictionary in lib["chunks"]:
		chunks[str(c["id"])] = c
	assert_bool(chunks.has("garden") and chunks.has("graves")).is_true()
	assert_str(str(chunks["graves"]["marks"]["g"])).is_equal("spot:grave")
	assert_array((lib["spots"]["groups"]["grave"]["bodies"]["*"] as Dictionary).keys()).is_equal(["grave"])


func test_the_new_bodies_have_their_pictures() -> void:
	var bodies: Dictionary = data["rules"]["things"]["bodies"]
	var ids := MapGround.prop_ids(lib)
	for id: String in ["trap", "grave", "timber", "rug", "straw", "fence"]:
		assert_bool(ids.has(id)).override_failure_message(id).is_true()
		if id != "fence":
			assert_bool(bodies.has(id)).override_failure_message(id).is_true()
