extends GdUnitTestSuite
## v0.8.4.43.32: lava — a ground of its own with a drawn crust where it meets the floor, a pond of a place tagged `lava`,
## halls of lava in caves; not walked, and one who falls or is shoved in burns by the DMG's 10d10 fire.

var data: Dictionary


func before() -> void:
	data = TestUtils.data().duplicate(true)


func test_lava_is_a_ground_that_glows_and_is_never_walked() -> void:
	var lib: Dictionary = data["layouts"]
	assert_bool(bool(lib["cells"]["&"].get("solid", false))).is_true()
	assert_bool(bool(lib["cells"]["&"].get("opaque", false))).is_false()
	assert_str(str(lib["grounds"]["cells"]["&"])).is_equal("magma")
	assert_bool((lib["grounds"]["order"] as Array).has("magma")).is_true()
	var move := MapGround.ground_motion(lib)
	var at := (lib["grounds"]["order"] as Array).find("magma")
	assert_float(move[at].w).is_greater(0.0)
	assert_float(move[(lib["grounds"]["order"] as Array).find("grass")].w).is_equal(0.0)
	var edges: Array = (lib["grounds"]["edges"] as Array).filter(func(e: Dictionary) -> bool: return str(e["low"]) == "magma")
	assert_int(edges.size()).is_greater_equal(2)


func test_a_place_tagged_lava_has_a_pond_of_it_and_one_tagged_water_none() -> void:
	var layouts: Dictionary = data["layouts"]
	var exits: Array = [{"to": "a", "side": "n", "kind": "edge"}, {"to": "b", "side": "s", "kind": "edge"}]
	for sd: int in 5:
		var hot := LayoutGen.open_map(layouts, {"id": "r", "kind": "square", "tags": ["lava"], "exits": exits}, sd * 7 + 3)
		assert_bool("".join(hot["rows"]).contains("&")).override_failure_message("seed %d" % sd).is_true()
		var wet := LayoutGen.open_map(layouts, {"id": "r", "kind": "square", "tags": ["water"], "exits": exits}, sd * 7 + 3)
		assert_bool("".join(wet["rows"]).contains("&")).is_false()
		assert_bool("".join(wet["rows"]).contains("~")).is_true()


func test_a_cave_room_tagged_lava_takes_a_hall_of_lava() -> void:
	var lib: Dictionary = data["layouts"]
	var halls: Array = (lib["chunks"] as Array).filter(func(c: Dictionary) -> bool: return (c.get("tags", []) as Array).has("lava"))
	assert_int(halls.size()).is_greater_equal(2)
	for c: Dictionary in halls:
		assert_bool("".join(c["rows"]).contains("&")).is_true()
		assert_bool((c["marks"] as Dictionary).values().has("water")).override_failure_message(str(c["id"])).is_false()


func test_one_who_falls_into_lava_burns() -> void:
	var s := TestUtils.new_session()
	TestUtils.fight(s, data, [{"monster": "wolf", "col": 0}])
	var wolf := CombatRules.fighter(s, TestUtils.foe(s, 1))
	var at := FightGrid.cell(wolf)
	var g := FightGrid.grid(s, data)
	var rows: Array = g["map"]["rows"]
	var line: String = rows[at.y]
	rows[at.y] = line.substr(0, at.x) + "&" + line.substr(at.x + 1)
	var lines: Array[String] = []
	wolf["hp"] = 200
	FightField._fall(s, data, wolf, lines)
	assert_int(int(wolf["hp"])).is_less_equal(190)
	assert_str("\n".join(lines)).contains("лаву")
	assert_int(FightGrid._kind(data["layouts"], "&")[0] & FightGrid.PIT).is_not_equal(0)
