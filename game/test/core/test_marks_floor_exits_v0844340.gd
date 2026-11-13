extends GdUnitTestSuite
## v0.8.4.43.40: what stands at a chunk's marks, a room's floor by its role and the things of the ways out — a stage, a
## market stall, an ore vein, a desk, a millstone and a menhir at their marks; water a well in a town and nothing in a cave;
## a cellar of flagstones under a house of planks; a signpost at the rim of an open map, stairs up and down turned to
## their wall, a door its own.

var data: Dictionary
var lib: Dictionary


func before_test() -> void:
	data = TestUtils.data()
	lib = data["layouts"]


func test_every_mark_with_a_body_has_its_thing_and_its_picture() -> void:
	var bodies: Dictionary = data["rules"]["things"]["bodies"]
	var ids := MapGround.prop_ids(lib)
	for mark: String in data["rules"]["map"]["station_bodies"]:
		var row: Variant = data["rules"]["map"]["station_bodies"][mark]
		var all: Array = (row as Dictionary).values() if row is Dictionary else [row]
		for id: Variant in all:
			if str(id).is_empty():
				continue
			assert_bool(bodies.has(str(id))).override_failure_message("a body of %s" % mark).is_true()
			assert_bool(ids.has(str(id))).override_failure_message("a picture of %s" % id).is_true()
	for id: String in ["signpost", "stairs_up", "stairs_down"]:
		assert_bool(ids.has(id)).is_true()


func test_water_is_a_well_in_a_town_and_nothing_in_a_cave() -> void:
	var row: Variant = data["rules"]["map"]["station_bodies"]["water"]
	var cave := LayoutGen.ground_keys(lib, {"kind": "cave", "shape": "tunnels"})
	var town := LayoutGen.ground_keys(lib, {"kind": "square", "shape": "open"})
	assert_str(LayoutGen.by_keys(row, cave)).is_empty()
	assert_str(LayoutGen.by_keys(row, town)).is_equal("well")
	assert_str(LayoutGen.by_keys(data["rules"]["map"]["station_bodies"]["stage"], cave)).is_equal("stage")


func test_a_cellar_has_a_floor_of_flagstones_in_a_house_of_planks() -> void:
	var map := {"w": 2, "h": 1, "rows": [".."], "rooms": PackedInt32Array([0, 1]), "ids": ["hall", "cellar"],
		"roles": ["hall", "cellar"], "kind": "house", "shape": "building"}
	var order: Array = lib["grounds"]["order"]
	var g := LayoutGen.grounds(lib, map)
	assert_str(str(order[g[0]])).is_equal("planks")
	assert_str(str(order[g[1]])).is_equal("flagstone")
	map.erase("roles")  # a map of an older build: the place's floor everywhere
	assert_str(str(order[LayoutGen.grounds(lib, map)[1]])).is_equal("planks")


func test_the_pack_cellar_is_laid_with_its_role() -> void:
	var s := TestUtils.new_session()
	s.room_id = "brod-tavern-cellar"
	var map := LayoutRules.map_of(s, data, s.room_id)
	var at := (map["ids"] as Array).find("brod-tavern-cellar")
	assert_int(at).is_greater_equal(0)
	assert_str(str(map["roles"][at])).is_equal("cellar")
	var order: Array = lib["grounds"]["order"]
	var g := LayoutGen.grounds(lib, map)
	var rooms: PackedInt32Array = map["rooms"]
	var rows: Array = map["rows"]
	var found := false
	for i: int in rooms.size():
		if rooms[i] == at and str(rows[i / int(map["w"])])[i % int(map["w"])] == LayoutGen.FLOOR:
			assert_str(str(order[g[i]])).is_equal("flagstone")
			found = true
			break
	assert_bool(found).is_true()
	var stairs := (map["exits"] as Array).filter(func(e: Dictionary) -> bool: return str(e["kind"]) == "stairs")
	assert_bool(stairs.is_empty() or stairs.all(func(e: Dictionary) -> bool: return bool(e["up"]))).is_true()  # from the cellar only up


func test_the_ways_out_draw_their_things_turned() -> void:
	var keys: Array[String] = ["house", "building", "*"]
	var rows := ["#####", "#...#", "#...#", "#####"]
	var exits := [
		{"kind": "stairs", "x": 1, "y": 1, "up": false},  # the wall north and west: north first
		{"kind": "stairs", "x": 3, "y": 2, "up": true},  # the wall east and south: south first
		{"kind": "door", "x": 2, "y": 0, "side": "n"},
	]
	var laid := LayoutGen.props_laid(lib, keys, rows, 1, exits)
	assert_dict(laid[1 * 5 + 1]).is_equal({"id": "stairs_down", "turn": 0})
	assert_dict(laid[2 * 5 + 3]).is_equal({"id": "stairs_up", "turn": 2})
	assert_str(str(laid[0 * 5 + 2]["id"])).is_empty()  # a door is its own `+`, not a thing of the way
	var open := ["....", "....", "...."]
	var rim := LayoutGen.props_laid(lib, ["open", "*"], open, 1, [{"kind": "edge", "x": 3, "y": 1, "side": "e"}, {"kind": "edge", "x": 0, "y": 1, "side": "w"}])
	assert_dict(rim[1 * 4 + 3]).is_equal({"id": "signpost", "turn": 3})
	assert_dict(rim[1 * 4 + 0]).is_equal({"id": "signpost", "turn": 1})
