extends GdUnitTestSuite
## v0.8.0: layouts of places. Every chunk is sound, every room of the pack and of the master gets a map whose squares all
## join up, every way out has an approach, a save keeps the chosen chunks, a long rest wipes what was touched.

const SEEDS: Array[int] = [1, 2, 3, 7, 42, 1234, 99991, 31337]

var data: Dictionary
var layouts: Dictionary


func before() -> void:
	data = TestUtils.data().duplicate(true)
	layouts = data["layouts"]


func _session(game_seed: int = 42) -> GameSession:
	var s := TestUtils.new_session()
	s.game_seed = game_seed
	return s


func _room_chunks() -> Array:
	return (layouts["chunks"] as Array).filter(func(c: Dictionary) -> bool: return not c.has("landmarks"))


func _cell_ok(c: String, legend: Dictionary) -> bool:
	return legend.has(c) or layouts["cells"].has(c) or c == LayoutGen.BLANK


func test_every_chunk_is_a_rectangle_of_known_cells() -> void:
	for c: Dictionary in layouts["chunks"]:
		var width := str(c["rows"][0]).length()
		for r: Variant in c["rows"]:
			assert_int(str(r).length()).override_failure_message("%s: %s" % [c["id"], r]).is_equal(width)
			for ch: String in str(r).split("", false):
				assert_bool(_cell_ok(ch, c.get("marks", {}))).override_failure_message("%s: %s" % [c["id"], ch]).is_true()


func test_a_chunks_floor_joins_up_and_every_socket_opens_on_it() -> void:
	for c: Dictionary in _room_chunks():
		var rows := LayoutGen.turned(c["rows"], 0, false)
		var legend: Dictionary = c.get("marks", {})
		var grid: Array[String] = []
		var start := Vector2i(-1, -1)
		var floors := 0
		for y: int in rows.size():
			var line := ""
			for x: int in rows[y].length():
				var ch := "." if legend.has(rows[y][x]) else rows[y][x]
				line += ch
				if not LayoutGen.solid(layouts, ch):
					floors += 1
					start = Vector2i(x, y)
			grid.append(line)
		var out := {"w": rows[0].length(), "h": rows.size(), "rows": grid}
		var reach := LayoutGen.reached(out, layouts, start)
		assert_int(reach.size()).override_failure_message("%s: floor apart" % c["id"]).is_equal(floors)
		var sockets := LayoutGen.sockets(rows)
		assert_bool(sockets.is_empty()).override_failure_message("%s: no sockets" % c["id"]).is_false()
		for s: Dictionary in sockets:
			var inward: Vector2i = Vector2i(int(s["x"]), int(s["y"])) + LayoutGen.STEP[LayoutGen.OPPOSITE[str(s["side"])]]
			assert_bool(reach.has(inward)).override_failure_message("%s: socket %s" % [c["id"], s]).is_true()


func test_turns_and_mirrors_keep_a_chunk_whole() -> void:
	var rows: Array = ["#D#", "#..", "###", "###"]
	assert_array(LayoutGen.turned(rows, 0, true)).is_equal(["#D#", "..#", "###", "###"])
	assert_array(LayoutGen.turned(rows, 1, false)).is_equal(["####", "##.D", "##.#"])
	assert_array(LayoutGen.turned(rows, 4, false)).is_equal(rows)


func _sound(map: Dictionary, what: String) -> void:
	var entry := Vector2i(-1, -1)
	for m: Dictionary in map["marks"]:
		if str(m["name"]) == LayoutGen.ENTRY:
			entry = Vector2i(int(m["x"]), int(m["y"]))
	assert_int(entry.x).override_failure_message("%s: no entry" % what).is_greater_equal(0)
	var reach := LayoutGen.reached(map, layouts, entry)
	var rows: Array[String] = map["rows"]
	var walkable := 0
	for y: int in rows.size():
		for x: int in rows[y].length():
			if not LayoutGen.solid(layouts, rows[y][x]):
				walkable += 1
				if not reach.has(Vector2i(x, y)):
					fail("%s: %d,%d apart\n%s" % [what, x, y, "\n".join(rows)])
					return
	assert_int(walkable).override_failure_message(what).is_greater(0)
	for e: Dictionary in map["exits"]:
		assert_bool(reach.has(Vector2i(int(e["ax"]), int(e["ay"])))).override_failure_message("%s: way to %s\n%s" % [what, e["to"], "\n".join(rows)]).is_true()


func test_every_room_of_the_pack_gets_a_sound_map_on_every_seed() -> void:
	for game_seed: int in SEEDS:
		var s := _session(game_seed)
		for id: String in data["world"]["rooms"]:
			var map := LayoutRules.map_of(s, data, id)
			_sound(map, "%s seed %d" % [id, game_seed])
			assert_bool((map["ids"] as Array).has(id)).override_failure_message("%s on no map" % id).is_true()


func test_every_way_of_a_room_is_on_its_map() -> void:
	var s := _session()
	for id: String in data["world"]["rooms"]:
		var map := LayoutRules.map_of(s, data, id)
		for to: Variant in data["world"]["rooms"][id]["exits"]:
			var there := (map["ids"] as Array).has(str(to))
			for e: Dictionary in map["exits"]:
				there = there or (str(e["to"]) == str(to) and str(e["room"]) == id)
			assert_bool(there).override_failure_message("%s → %s" % [id, to]).is_true()


func test_a_building_is_one_map_a_floor_its_own_and_the_street_apart() -> void:
	var s := _session()
	var hall := LayoutRules.map_of(s, data, "brod-tavern-hall")
	assert_array(hall["ids"]).contains(["brod-tavern-hall", "brod-tavern-kitchen"])
	assert_array(hall["ids"]).not_contains(["brod-tavern-cellar", "brod-tavern-upstairs", "brod-square"])
	assert_array(hall["doors"]).is_not_empty()
	var ways: Dictionary = {}
	for e: Dictionary in hall["exits"]:
		ways[str(e["to"])] = str(e["kind"])
	assert_str(str(ways["brod-tavern-upstairs"])).is_equal("stairs")
	assert_str(str(ways["brod-square"])).is_equal("door")
	var square := LayoutRules.map_of(s, data, "brod-square")
	assert_array(square["ids"]).is_equal(["brod-square"])


func test_an_open_map_has_the_size_of_its_kind() -> void:
	var s := _session()
	var trail := LayoutRules.map_of(s, data, "pushcha-trail")
	assert_int(int(trail["w"])).is_equal(40)
	assert_int(int(trail["h"])).is_equal(40)
	assert_int(int(LayoutRules.map_of(s, data, "brod-square")["w"])).is_equal(32)
	for e: Dictionary in trail["exits"]:
		assert_str(str(e["kind"])).is_equal("edge")


func test_rooms_get_the_marks_of_their_tags() -> void:
	var names: Dictionary = {}
	for m: Dictionary in LayoutRules.map_of(_session(), data, "brod-smithy")["marks"]:
		names[str(m["name"])] = true
	assert_bool(names.has("forge")).is_true()
	assert_bool(names.has("bench")).is_true()


func test_a_way_out_lies_on_the_side_of_the_schemes() -> void:
	var boxes := {"a": Vector2(0.5, 0.5), "e": Vector2(0.9, 0.55), "n": Vector2(0.45, 0.1)}
	assert_str(LayoutRules.side(boxes, "a", "e")).is_equal("e")
	assert_str(LayoutRules.side(boxes, "a", "n")).is_equal("n")
	assert_str(LayoutRules.side(boxes, "e", "a")).is_equal("w")


func test_the_same_game_keeps_the_same_map_and_a_new_chunk_does_not_change_it() -> void:
	var s := _session()
	var first: Array = LayoutRules.map_of(s, data, "brod-tavern-hall")["rows"]
	var saved := s.layouts.duplicate(true)
	var again := _session()
	again.layouts = saved
	var lib: Dictionary = data["layouts"]
	var more := lib.duplicate(true)
	(more["chunks"] as Array).push_front({"id": "newer", "kinds": ["tavern"], "roles": ["hall", "kitchen"], "size": "large", "rows": ["###D###", "D.....D", "###D###"]})
	data["layouts"] = more
	var kept: Array = LayoutRules.map_of(again, data, "brod-tavern-hall")["rows"]
	data["layouts"] = lib
	assert_array(kept).is_equal(first)


func test_a_map_differs_by_the_games_seed() -> void:
	var a: Array = LayoutRules.map_of(_session(1), data, "pushcha-trail")["rows"]
	var b: Array = LayoutRules.map_of(_session(2), data, "pushcha-trail")["rows"]
	assert_bool(a == b).is_false()


func test_what_was_touched_stays_until_a_long_rest() -> void:
	var s := _session()
	var id := LayoutRules.map_id(s, data, "brod-tavern-hall")
	var before_rows: Array = LayoutRules.map_of(s, data, "brod-tavern-hall")["rows"]
	LayoutRules.tick(s, data)
	LayoutRules.touch(s, id, 1, 1, {"cell": "^", "why": "пепелище"})
	assert_str(str(LayoutRules.map_of(s, data, "brod-tavern-hall")["rows"][1][1])).is_equal("^")
	LayoutRules.tick(s, data)
	assert_str(str(LayoutRules.map_of(s, data, "brod-tavern-hall")["rows"][1][1])).is_equal("^")
	s.rested_at += 1000
	LayoutRules.tick(s, data)
	assert_array(LayoutRules.map_of(s, data, "brod-tavern-hall")["rows"]).is_equal(before_rows)


func test_a_new_room_stands_in_the_building_and_the_old_ones_stay() -> void:
	var s := _session()
	var first: Dictionary = LayoutRules.map_of(s, data, "brod-tavern-hall")
	var hall_pick: Dictionary = s.layouts["picks"]["brod-tavern-hall"]["brod-tavern-hall"].duplicate()
	var world: Dictionary = data["world"].duplicate(true)
	world["rooms"]["brod-tavern-bath"] = {"name": "Баня", "location_id": "brod", "site_id": "brod-tavern", "description": "", "exits": ["brod-tavern-hall"], "npcs": [], "indoor": true}
	(world["rooms"]["brod-tavern-hall"]["exits"] as Array).append("brod-tavern-bath")
	var changed := data.duplicate()
	changed["world"] = world
	var map := LayoutRules.map_of(s, changed, "brod-tavern-bath")
	assert_array(map["ids"]).contains(["brod-tavern-bath", "brod-tavern-hall"])
	assert_dict(s.layouts["picks"]["brod-tavern-hall"]["brod-tavern-hall"]).is_equal(hall_pick)
	_sound(map, "with the bath")
	assert_int((map["doors"] as Array).size()).is_greater((first["doors"] as Array).size())


func test_a_place_of_an_unknown_kind_is_built_of_generic_chunks() -> void:
	var ask := {"id": "x", "kind": "observatory", "role": "hall", "tags": ["strange"], "size": "small", "links": [], "exits": [{"to": "out", "side": "n", "kind": "door"}]}
	assert_array(LayoutGen.candidates(layouts, ask)).is_not_empty()
	var map := LayoutGen.stitched(layouts, [ask] as Array[Dictionary], 5, {})
	_sound(map, "observatory")
	assert_array(map["exits"]).has_size(1)


func test_the_chain_goes_from_the_exact_to_the_general() -> void:
	var ask := {"kind": "inn", "role": "kitchen", "tags": [], "size": "medium"}
	var chain := LayoutGen.candidates(layouts, ask)
	assert_str(str(chain[0]["id"])).is_equal("kitchen")
	assert_bool(chain.back().get("generic", false)).is_true()


func test_a_room_with_a_tag_of_its_own_gets_its_chunk() -> void:
	var picks: Dictionary = {}
	LayoutRules.map_of(_session(), data, "mine-gallery")
	var s := _session()
	LayoutRules.map_of(s, data, "mine-flooded")
	picks = s.layouts["picks"][LayoutRules.map_id(s, data, "mine-flooded")]
	assert_str(str(picks["mine-flooded"]["chunk"])).is_equal("flooded")


func test_the_seed_picks_among_the_chunks_of_a_step() -> void:
	var halls: Dictionary = {}
	for sd: int in 12:
		var s := _session(sd)
		LayoutRules.map_of(s, data, "brod-tavern-hall")
		halls[str(s.layouts["picks"]["brod-tavern-hall"]["brod-tavern-hall"]["chunk"])] = true
	assert_int(halls.size()).is_equal(2)


func test_the_author_pins_a_chunk_and_draws_a_room() -> void:
	var game := data.duplicate()
	game["world"] = data["world"].duplicate(true)
	game["world"]["rooms"]["brod-smithy"]["layout"] = {"chunk": {"id": "room_large", "rot": 1, "flip": true}}
	var s := _session()
	LayoutRules.map_of(s, game, "brod-smithy")
	var pick: Dictionary = s.layouts["picks"]["brod-smithy"]["brod-smithy"]
	assert_str(str(pick["chunk"])).is_equal("room_large")
	assert_int(int(pick["rot"])).is_equal(1)
	game["world"]["rooms"]["brod-temple"]["layout"] = {"rows": ["##D##", "#.A.#", "D...D", "##D##"], "marks": {"A": "altar"}}
	var map := LayoutRules.map_of(_session(), game, "brod-temple")
	assert_array(map["rows"]).contains(["#...#"])
	_sound(map, "the author's temple")


func test_a_long_graph_of_tunnels_stays_whole() -> void:
	var asks: Array[Dictionary] = []
	for i: int in 10:
		var links: Array = []
		if i > 0:
			links.append("r%d" % (i - 1))
		if i < 9:
			links.append("r%d" % (i + 1))
		asks.append({"id": "r%d" % i, "kind": "mine", "role": "", "tags": [], "size": "cave", "links": links, "exits": []})
	for sd: int in SEEDS:
		var map := LayoutGen.stitched(layouts, asks, sd, {})
		_sound(map, "tunnels %d" % sd)
		assert_int((map["ids"] as Array).size() + (map["left"] as Array).size()).is_equal(10)


func test_a_kinds_limit_refuses_a_new_room_with_a_reason() -> void:
	var s := _session()
	assert_str(LayoutRules.no_room(s, data, "brod-tavern", "tavern", 1)).is_empty()
	assert_str(LayoutRules.no_room(s, data, "brod-tavern", "tavern", 3)).contains("не больше 6 комнат")
	assert_str(LayoutRules.no_room(s, data, "brod-tavern", "observatory", 30)).is_empty()


func _spec(extra: Dictionary) -> Dictionary:
	return {"inside": true, "room_id": "brod-tavern-hall", "rooms": [{"key": "bath", "name": "Баня при таверне", "description": "Парная.", "indoor": true, "role": "bedroom", "size": "small"}]}.merged(extra)


func test_the_master_joins_a_room_to_a_building_by_words() -> void:
	var game := data.duplicate()
	game["world"] = data["world"].duplicate(true)
	var s := _session()
	s.room_id = "brod-tavern-hall"
	var p := WorldGen.plan_place(s, game, _spec({"extend": true}), true)
	assert_bool(p.has("plan")).override_failure_message(str(p)).is_true()
	var first := WorldGen.apply_place(s, game, p["plan"])
	var room: Dictionary = WorldView.new(LayoutRules.world(s, game)).room(first)
	assert_str(str(room["site_id"])).is_equal("brod-tavern")
	assert_str(str(room["layout"]["size"])).is_equal("small")
	var map := LayoutRules.map_of(s, game, first)
	assert_array(map["ids"]).contains([first, "brod-tavern-hall"])
	_sound(map, "the master's bath")


func test_a_full_building_refuses_the_masters_room_with_a_reason() -> void:
	var s := _session()
	s.room_id = "brod-tavern-hall"
	var spec := _spec({"extend": true})
	spec["rooms"] = []
	for i: int in 3:
		spec["rooms"].append({"key": "r%d" % i, "name": "Пристройка %d" % i, "description": "", "indoor": true, "exits": [] if i == 0 else ["r0"]})
	assert_str(str(WorldGen.plan_place(s, data, spec, true).get("reason", ""))).contains("не больше 6 комнат")


func test_a_saved_map_comes_back_the_same() -> void:
	var s := _session()
	LayoutRules.map_of(s, data, "brod-tavern-hall")
	LayoutRules.touch(s, "brod-tavern-hall", 3, 4, {"door": "broken", "hp": 2})
	s.layouts["rested"] = 480
	var back := GameSession.from_dict(JSON.parse_string(JSON.stringify(s.to_dict(5))))
	assert_str(JSON.stringify(back.layouts)).is_equal(JSON.stringify(s.layouts))


func test_a_save_comes_back_with_whole_numbers_all_the_way_down() -> void:
	var loaded: Variant = GameSession.whole(JSON.parse_string('{"a": 2.0, "b": [1.0, {"c": 3.0}], "d": 1.5, "e": "7"}'))
	assert_str(JSON.stringify(loaded, "", false)).is_equal('{"a":2,"b":[1,{"c":3}],"d":1.5,"e":"7"}')

