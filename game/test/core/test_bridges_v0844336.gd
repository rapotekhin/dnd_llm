extends GdUnitTestSuite
## v0.8.4.43.36: bridges and falls the generator lays itself: a bridge where a road crosses water or lava (and in the
## ford's piece), its deck a ground of planks with a drawn edge on the water; a waterfall or a fall of lava where a cliff
## has the liquid on two opposite sides, a ribbon of falling water over the cliff turned down the slope, its piece by the falls beside it.

var data: Dictionary
var lib: Dictionary


func before() -> void:
	data = TestUtils.data().duplicate(true)
	lib = data["layouts"]


func _grid(rows: Array) -> Array[PackedStringArray]:
	var out: Array[PackedStringArray] = []
	for r: Variant in rows:
		out.append(str(r).split(""))
	return out


func _rows(grid: Array[PackedStringArray]) -> Array:
	return grid.map(func(line: PackedStringArray) -> String: return "".join(line))


func _chunk(id: String) -> Dictionary:
	return (lib["chunks"] as Array).filter(func(c: Dictionary) -> bool: return str(c["id"]) == id)[0]


func test_a_bridge_is_walked_and_a_fall_is_not() -> void:
	for c: String in ["_", ";"]:
		assert_str(str(lib["cells"][c]["name"])).is_equal("bridge")
		assert_bool(bool(lib["cells"][c].get("solid", false))).is_false()
		assert_str(LayoutGen.prop_of(lib, ["open", "*"] as Array[String], c)).is_empty()  # the deck is a ground
		assert_str(str(lib["grounds"]["cells"][c])).is_equal("planks")
	assert_bool((lib["grounds"]["edges"] as Array).any(func(e: Dictionary) -> bool: return e["low"] == "water" and e["high"] == "planks")).is_true()
	for c: String in ["|", "!"]:
		assert_bool(bool(lib["cells"][c].get("solid", false))).is_true()
		assert_bool(bool(lib["cells"][c].get("opaque", false))).is_false()
	assert_float(float(lib["grounds"]["shimmer"]["waterfall"])).is_greater(0.0)


func test_a_road_over_water_lays_a_bridge_and_no_water_is_paved() -> void:
	var exits: Array = [{"to": "a", "side": "n", "kind": "edge"}, {"to": "b", "side": "s", "kind": "edge"},
		{"to": "c", "side": "w", "kind": "edge"}, {"to": "d", "side": "e", "kind": "edge"}]
	var bridges := 0
	for sd: int in 24:
		var map := LayoutGen.open_map(lib, {"id": "r", "kind": ["wild", "square"][sd % 2], "tags": ["water"], "exits": exits}, sd * 11 + 5)
		var rows: Array = map["rows"]
		bridges += "".join(rows).count("_")
		for y: int in rows.size():
			for x: int in str(rows[y]).length():
				if str(rows[y])[x] == "_":
					assert_bool(WalkRules.passable(map, lib, Vector2i(x, y))).is_true()
	assert_int(bridges).override_failure_message("a forest with streams and a square with ponds, four roads, no bridge").is_greater(0)


func test_the_ford_is_a_bridge_now_and_its_sides_still_meet_water_and_road() -> void:
	var rows: Array[String] = []
	rows.assign(_chunk("tile_path_ford")["rows"])
	assert_str("".join(rows)).contains("_")
	var codes := LayoutGen._tile_codes(rows)
	assert_str(str(codes["n"])).is_equal("w")
	assert_str(str(codes["w"])).is_equal("r")


func test_a_cliff_with_water_on_both_sides_falls_and_its_picture_turns_down_the_slope() -> void:
	var down := _grid(_chunk("tile_stream_falls_a")["rows"])
	LayoutGen._falls(lib, down)
	var rows := _rows(down)
	assert_str(str(rows[6]).substr(5, 2)).is_equal("||")
	assert_int(LayoutGen.prop_turn(lib, rows, 5, 6, "waterfall")).is_equal(0)  # high ground north: it falls south
	var east := _grid(_chunk("tile_stream_falls_b")["rows"])
	LayoutGen._falls(lib, east)
	rows = _rows(east)
	assert_str(str(rows[5])[6] + str(rows[6])[6]).is_equal("||")
	assert_int(LayoutGen.prop_turn(lib, rows, 6, 5, "waterfall")).is_equal(1)  # high ground west: it falls east
	var hot := _grid([".:&:.", ".///.", "..&.."])
	LayoutGen._falls(lib, hot)
	assert_str(_rows(hot)[1]).is_equal("./!/.")
	var dry := _grid(["..:..", ".///.", "....."])
	LayoutGen._falls(lib, dry)
	assert_str(_rows(dry)[1]).is_equal(".///.")


func test_one_rule_turns_a_door_and_a_fall() -> void:
	assert_int(LayoutGen.prop_turn(lib, ["#+#"], 1, 0, "door")).is_equal(1)
	assert_int(LayoutGen.prop_turn(lib, [".#.", ".+.", ".#."], 1, 1, "door")).is_equal(0)
	assert_int(LayoutGen.prop_turn(lib, ["~~:", "./|", "..~"], 2, 1, "tree")).is_equal(0)
	assert_int(LayoutGen.prop_turn(lib, [".:.", ".~.", "/|/", ".~."], 1, 2, "waterfall")).is_equal(0)
	assert_int(LayoutGen.prop_turn(lib, [".~.", "/|/", ".~.", ".:."], 1, 1, "waterfall")).is_equal(2)  # high ground south


func test_a_fall_takes_its_piece_of_the_strip_by_the_falls_beside_it() -> void:
	var keys: Array[String] = ["open", "*"]
	var wide := ["::~~::", "//||//", "..~~.."]  # falls south, two squares wide
	assert_dict(LayoutGen.prop_at(lib, keys, wide, 2, 1)).is_equal({"id": "waterfall_left", "turn": 0})
	assert_dict(LayoutGen.prop_at(lib, keys, wide, 3, 1)).is_equal({"id": "waterfall_right", "turn": 0})
	assert_str(str(LayoutGen.prop_at(lib, keys, ["::~::", "//|//", "..~.."], 2, 1)["id"])).is_equal("waterfall_one")
	assert_str(str(LayoutGen.prop_at(lib, keys, [":~~~:", "/|||/", ".~~~."], 2, 1)["id"])).is_equal("waterfall_mid")
	var east := ["::/..", "~~|~~", "~~|~~", "::/.."]  # falls east: the picture's left end is the south one
	assert_dict(LayoutGen.prop_at(lib, keys, east, 2, 2)).is_equal({"id": "waterfall_left", "turn": 1})
	assert_dict(LayoutGen.prop_at(lib, keys, east, 2, 1)).is_equal({"id": "waterfall_right", "turn": 1})
	assert_str(str(LayoutGen.prop_at(lib, keys, ["::&::", "//!//", "..&.."], 2, 1)["id"])).is_equal("lavafall_one")
	assert_str(LayoutGen.prop_base(lib, "waterfall_mid")).is_equal("waterfall")
	assert_str(LayoutGen.prop_base(lib, "tree")).is_equal("tree")
	var drawn := MapGround.prop_ids(lib)
	assert_bool(drawn.has("waterfall_left") and drawn.has("lavafall_one")).is_true()
	assert_bool(drawn.has("waterfall")).is_false()
	assert_int(drawn.size()).is_less_equal(MapGround.MAX_PROPS)


func test_a_bridge_over_the_stream_above_a_fall_does_not_turn_it_aside() -> void:
	var keys: Array[String] = ["open", "*"]
	var rows := [":__:", "/||/", ".~~."]  # the path crosses on a bridge right above the falls
	assert_dict(LayoutGen.prop_at(lib, keys, rows, 1, 1)).is_equal({"id": "waterfall_left", "turn": 0})
