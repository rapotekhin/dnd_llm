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


func _rng_asks(n: int, game_seed: int) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = game_seed
	var asks: Array[Dictionary] = []
	for i: int in n:
		asks.append({"id": "r%d" % i, "kind": "tavern", "role": "", "tags": ["hearth"], "size": "medium", "links": [], "marks": ["hearth"],
			"exits": [{"to": "out%d" % i, "side": LayoutGen.SIDES[rng.randi_range(0, 3)], "kind": "door"}]})
	for i: int in range(1, n):
		var p := rng.randi_range(maxi(0, i - 2), i - 1)
		asks[i]["links"].append("r%d" % p)
		asks[p]["links"].append("r%d" % i)
	return asks


## The squares of roads joined with the middle: one road may start at a door, the middle may stand aside of a landmark.
func _on_roads(map: Dictionary) -> Dictionary:
	var rows: Array[String] = map["rows"]
	var from := Vector2i(int(map["w"]) / 2, int(map["h"]) / 2)
	var seen := {from: true}
	var queue: Array[Vector2i] = [from]
	while not queue.is_empty():
		var at: Vector2i = queue.pop_back()
		for side: String in LayoutGen.SIDES:
			var n: Vector2i = at + LayoutGen.STEP[side]
			if n.x >= 0 and n.y >= 0 and n.x < int(map["w"]) and n.y < int(map["h"]) and not seen.has(n) and rows[n.y][n.x] in [LayoutGen.ROAD, LayoutGen.PATH]:
				seen[n] = true
				queue.append(n)
	return seen


func test_every_way_of_an_open_map_lies_on_the_roads() -> void:
	for game_seed: int in [1, 2, 3, 7, 42]:
		var s := _session(game_seed)
		for id: String in data["world"]["rooms"]:
			var map := LayoutRules.map_of(s, data, id)
			if not map.has("open"):
				continue
			var road := _on_roads(map)
			for e: Dictionary in map["exits"]:
				var end := Vector2i(int(e["x"]), int(e["y"])) if str(e["kind"]) == "edge" else Vector2i(int(e["ax"]), int(e["ay"]))
				assert_bool(road.has(end)).override_failure_message("%s → %s, seed %d\n%s" % [id, e["to"], game_seed, "\n".join(map["rows"])]).is_true()


func test_roads_fork_and_a_town_is_paved_and_a_forest_is_a_path() -> void:
	var exits: Array = []
	for to: String in ["a", "b", "c", "d", "e", "f"]:
		exits.append({"to": to, "side": "n" if to < "d" else "e", "kind": "edge"})
	var town := LayoutGen.open_map(layouts, {"id": "r", "kind": "square", "tags": [], "exits": exits}, 3)
	var wild := LayoutGen.open_map(layouts, {"id": "r", "kind": "wild", "tags": [], "exits": exits}, 3)
	assert_str("".join(town["rows"])).contains(LayoutGen.ROAD)
	assert_str("".join(wild["rows"])).contains(LayoutGen.PATH)
	assert_str("".join(wild["rows"])).not_contains(LayoutGen.ROAD)
	var side := int(town["w"]) + int(town["h"])
	var cells := "".join(town["rows"]).count(LayoutGen.ROAD)
	assert_int(cells).override_failure_message("a star of six would be about %d" % (side * 3)).is_less(side * 2)


func test_a_new_way_adds_a_branch_of_road_and_leaves_the_old_ones() -> void:
	var exits: Array = [{"to": "a", "side": "n", "kind": "edge"}, {"to": "b", "side": "w", "kind": "edge"}]
	var ask := {"id": "r", "kind": "wild", "tags": [], "exits": exits}
	var before := LayoutGen.open_map(layouts, ask, 21)
	var more := ask.duplicate(true)
	(more["exits"] as Array).append({"to": "c", "side": "e", "kind": "edge"})
	more["kept"] = before["picks"]
	var after := LayoutGen.open_map(layouts, more, 21)
	assert_array(after["picks"]["roads"]).is_equal((before["picks"]["roads"] as Array) + ["c"])
	for y: int in int(before["h"]):
		for x: int in int(before["w"]):
			if before["rows"][y][x] == LayoutGen.PATH:
				assert_str(after["rows"][y][x]).is_equal(LayoutGen.PATH)


func test_a_road_changes_no_walking() -> void:
	assert_bool(LayoutGen.solid(layouts, LayoutGen.PATH)).is_false()
	assert_bool(LayoutGen.solid(layouts, LayoutGen.ROAD)).is_false()
	assert_int(int(layouts["cells"][LayoutGen.PATH].get("cost", 1))).is_equal(1)


func _crowded() -> Dictionary:
	var game := data.duplicate()
	game["world"] = data["world"].duplicate(true)
	var exits: Array = game["world"]["rooms"]["brod-square"]["exits"]
	exits.erase("brod-gate")
	exits.erase("brod-river-yard")
	exits.append("brod-mill")
	return game


func test_no_open_place_of_the_pack_is_past_its_ways() -> void:
	var s := _session()
	var v := WorldView.new(data["world"])
	for id: String in data["world"]["rooms"]:
		if LayoutRules.is_open(s, data, id):
			var inner := v.exits(id).filter(func(to: String) -> bool: return not LayoutRules.is_open(s, data, to)).size()
			assert_int(v.exits(id).size()).override_failure_message(id).is_less_equal(int(layouts["open"]["ways"]))
			assert_int(inner).override_failure_message(id).is_less_equal(int(layouts["open"]["ways"]) - int(layouts["open"]["ways_outer"]))


func test_the_last_ways_of_an_open_place_wait_for_other_open_places() -> void:
	var s := _session()
	assert_int((data["world"]["rooms"]["brod-square"]["exits"] as Array).size()).is_equal(8)
	assert_str(LayoutRules.no_way(s, data, "brod-square", false)).is_empty()
	var game := _crowded()
	assert_str(LayoutRules.no_way(s, game, "brod-square", false)).contains("последние 2 выхода")
	assert_str(LayoutRules.no_way(s, game, "brod-square", true)).is_empty()
	(game["world"]["rooms"]["brod-square"]["exits"] as Array).append("brod-gate")
	assert_str(LayoutRules.no_way(s, game, "brod-square", false)).contains("последние 2 выхода")
	assert_str(LayoutRules.no_way(s, game, "brod-square", true)).is_empty()
	(game["world"]["rooms"]["brod-square"]["exits"] as Array).append("brod-river-yard")
	assert_str(LayoutRules.no_way(s, game, "brod-square", true)).contains("больше не встанет")
	assert_str(LayoutRules.no_way(s, game, "brod-tavern-hall", false)).is_empty()


func _bakery() -> Dictionary:
	return {"room_id": "brod-square", "edge": 0, "site": {"name": "Пекарня", "tags": ["shop"]},
		"rooms": [{"key": "bakery", "name": "Пекарня", "description": "Жарко и пахнет хлебом.", "indoor": true}]}


func test_a_building_on_a_full_square_stands_on_a_new_street() -> void:
	var game := _crowded()
	var s := _session()
	s.room_id = "brod-square"
	assert_str(str(WorldGen.plan_place(s, game, _bakery(), true).get("reason", ""))).contains("последние 2 выхода")
	var spec := {"room_id": "brod-square", "edge": 0, "sites": [{"key": "lane", "name": "Хлебный переулок", "tags": ["square"]}, {"key": "bake", "name": "Пекарня", "tags": ["shop"]}],
		"rooms": [{"key": "lane", "name": "Хлебный переулок", "description": "Узкая улочка.", "site": "lane", "exits": ["bakery"]},
			{"key": "bakery", "name": "Пекарня", "description": "Жарко и пахнет хлебом.", "indoor": true, "site": "bake", "exits": ["lane"]}]}
	var p := WorldGen.plan_place(s, game, spec, true)
	assert_bool(p.has("plan")).override_failure_message(str(p)).is_true()
	var lane := WorldGen.apply_place(s, game, p["plan"])
	assert_bool(LayoutRules.is_open(s, game, lane)).is_true()
	var map := LayoutRules.map_of(s, game, lane)
	_sound(map, "the new street")
	assert_int((map["exits"] as Array).size()).is_equal(2)
	assert_array(WorldView.new(game["world"]).exits("brod-square")).contains([lane])


func test_a_full_square_offers_no_edge_and_takes_no_way() -> void:
	var game := _crowded()
	(game["world"]["rooms"]["brod-square"]["exits"] as Array).append_array(["brod-gate", "brod-river-yard"])
	var s := _session()
	s.room_id = "brod-square"
	var edges := WorldGen.reach_edges(s, game).filter(func(e: Dictionary) -> bool: return str(e["room_id"]) == "brod-square")
	assert_array(edges).is_empty()
	var made := WayRules.plan_make(s, game, {"to_room": "brod-plot", "way_kind": "door"})
	assert_str(str(made.get("reason", ""))).contains("больше не встанет")


func test_a_ruin_keeps_its_ways_on_many_seeds() -> void:
	for game_seed: int in range(1, 41):
		_sound(LayoutRules.map_of(_session(game_seed * 7919), data, "outpost-yard"), "the yard, seed %d" % game_seed)


func test_every_way_of_a_crowded_open_map_is_reached() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for kind: String in ["ruin", "square", "wild", "land", "arena"]:
		for sd: int in 40:
			var exits: Array = []
			for j: int in rng.randi_range(2, 10):
				exits.append({"to": "x%d" % j, "side": LayoutGen.SIDES[rng.randi_range(0, 3)], "kind": "door" if rng.randf() < 0.6 else "edge"})
			var map := LayoutGen.open_map(layouts, {"id": "r", "kind": kind, "tags": ["road"] if sd % 2 == 0 else [], "exits": exits}, sd * 31)
			_sound(map, "%s %d" % [kind, sd])
			assert_int((map["exits"] as Array).size()).is_equal(exits.size())


func test_a_map_with_a_way_nobody_reaches_is_built_again() -> void:
	var one := layouts.duplicate(true)
	one["sound"]["tries"] = 1
	var ask := {"id": "r", "kind": "ruin", "tags": [], "exits": [{"to": "a", "side": "e", "kind": "door"}]}
	var map := LayoutGen.open_map(layouts, ask, 77)
	assert_int(int(map["faults"])).is_less(int(layouts["sound"]["retry_from"]))
	assert_int(int(map["picks"]["try"])).is_greater_equal(0)
	var again := ask.duplicate()
	again["kept"] = map["picks"]
	assert_array(LayoutGen.open_map(one, again, 77)["rows"]).is_equal(map["rows"])


func test_a_room_added_later_moves_nothing_of_the_old_rooms() -> void:
	for sd: int in 60:
		var asks := _rng_asks(5, sd)
		var before := LayoutGen.stitched(layouts, asks, sd, {})
		var more: Array[Dictionary] = asks.duplicate(true)
		more.append({"id": "new", "kind": "tavern", "role": "", "tags": [], "size": "medium", "links": ["r0"], "exits": []})
		more[0]["links"].append("new")
		var after := LayoutGen.stitched(layouts, more, sd, before["picks"])
		var was := {}
		for m: Dictionary in before["marks"]:
			was[[str(m["name"]), before["ids"][int(m["room"])], LayoutGen.on_grid(before, Vector2i(int(m["x"]), int(m["y"])))]] = true
		for m: Dictionary in after["marks"]:
			var id := str(after["ids"][int(m["room"])])
			if id != "new":
				assert_bool(was.has([str(m["name"]), id, LayoutGen.on_grid(after, Vector2i(int(m["x"]), int(m["y"])))])).override_failure_message("mark %s of %s, seed %d" % [m["name"], id, sd]).is_true()
		var ways := {}
		for e: Dictionary in before["exits"]:
			ways[[str(e["to"]), LayoutGen.on_grid(before, Vector2i(int(e["x"]), int(e["y"])))]] = true
		for e: Dictionary in after["exits"]:
			if str(e["room"]) != "new":
				assert_bool(ways.has([str(e["to"]), LayoutGen.on_grid(after, Vector2i(int(e["x"]), int(e["y"])))])).override_failure_message("way %s, seed %d" % [e["to"], sd]).is_true()


func test_a_way_added_to_a_street_moves_nothing_of_the_old_ways() -> void:
	var exits: Array = [{"to": "a", "side": "n", "kind": "door"}, {"to": "b", "side": "n", "kind": "door"}, {"to": "c", "side": "e", "kind": "edge"}]
	var ask := {"id": "r", "kind": "square", "tags": ["road"], "exits": exits}
	var before := LayoutGen.open_map(layouts, ask, 9)
	var more := ask.duplicate(true)
	(more["exits"] as Array).append({"to": "d", "side": "n", "kind": "door"})
	more["kept"] = before["picks"]
	var after := LayoutGen.open_map(layouts, more, 9)
	for e: Dictionary in before["exits"]:
		assert_bool((after["exits"] as Array).has(e)).override_failure_message(str(e)).is_true()
	assert_int((after["exits"] as Array).size()).is_equal(4)
	_sound(after, "a street with one more way")


func test_the_hero_and_what_was_touched_keep_their_place_when_the_rows_begin_elsewhere() -> void:
	var s := _session()
	var map := LayoutRules.map_of(s, data, "brod-tavern-hall")
	var cell := LayoutGen.off_grid(map, Vector2i(map["origin"]) + Vector2i(3, 3))
	WalkRules.stand(s, map, "brod-tavern-hall", cell)
	var moved := map.duplicate()
	moved["origin"] = Vector2i(map["origin"]) + Vector2i(-2, -1)
	assert_object(LayoutGen.off_grid(moved, LayoutGen.on_grid(map, cell))).is_equal(cell + Vector2i(2, 1))
	assert_int(int(s.layouts["at"]["x"])).is_equal(LayoutGen.on_grid(map, cell).x)


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
	var room: Dictionary = WorldView.new(game["world"]).room(first)
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
	s.layouts["rested"] = 480
	var back := GameSession.from_dict(JSON.parse_string(JSON.stringify(s.to_dict(5))))
	assert_str(JSON.stringify(back.layouts)).is_equal(JSON.stringify(s.layouts))


func test_every_map_comes_back_the_same_after_a_load() -> void:
	var s := _session()
	var before_load := {}
	for room: String in data["world"]["rooms"]:
		var map := LayoutRules.map_of(s, data, room)
		before_load[room] = JSON.stringify([map["rows"], map["marks"], map["exits"], map["doors"]])
	var back := GameSession.from_dict(JSON.parse_string(JSON.stringify(s.to_dict(5))))
	for room: String in data["world"]["rooms"]:
		var map := LayoutRules.map_of(back, data, room)
		assert_str(JSON.stringify([map["rows"], map["marks"], map["exits"], map["doors"]])).override_failure_message(room).is_equal(before_load[room])


func test_a_save_comes_back_with_whole_numbers_all_the_way_down() -> void:
	var loaded: Variant = GameSession.whole(JSON.parse_string('{"a": 2.0, "b": [1.0, {"c": 3.0}], "d": 1.5, "e": "7"}'))
	assert_str(JSON.stringify(loaded, "", false)).is_equal('{"a":2,"b":[1,{"c":3}],"d":1.5,"e":"7"}')



## v0.8.4.36, the author's feedback: new ways to new places were laid right beside the old ones — now they keep `open.gap`
## (and `open.room_gap` in a building's room) while there is room for it.
func test_new_ways_are_laid_apart_from_the_old() -> void:
	var gap := int(layouts["open"]["gap"])
	for kind: String in ["wild", "square"]:
		for sd: int in 6:
			var ask := {"id": "r", "kind": kind, "tags": [], "exits": [{"to": "a", "side": "n", "kind": "edge"}]}
			var map := LayoutGen.open_map(layouts, ask, sd * 13 + 1)
			for to: String in ["b", "c", "d"]:  # each made later, one at a time, on the same side
				ask = ask.duplicate(true)
				(ask["exits"] as Array).append({"to": to, "side": "n", "kind": "door" if kind == "square" else "edge"})
				ask["kept"] = map["picks"]
				map = LayoutGen.open_map(layouts, ask, sd * 13 + 1)
				var new_one: Dictionary = (map["exits"] as Array).filter(func(e: Dictionary) -> bool: return str(e["to"]) == to)[0]
				for e: Dictionary in map["exits"]:
					if str(e["to"]) != to:
						var d := maxi(absi(int(e["x"]) - int(new_one["x"])), absi(int(e["y"]) - int(new_one["y"])))
						assert_int(d).override_failure_message("%s seed %d: %s beside %s" % [kind, sd, to, e["to"]]).is_greater_equal(gap)


func test_every_square_has_a_ground_of_the_order_and_every_cell_one_of_its_own() -> void:
	var g: Dictionary = layouts["grounds"]
	var order: Array = g["order"]
	assert_int(order.size()).is_less_equal(MapGround.MAX_GROUNDS)
	for kind: String in layouts["kinds"]:
		var keys := LayoutGen.ground_keys(layouts, {"kind": kind, "shape": LayoutGen.shape_of(layouts, kind, true)})
		for c: String in layouts["cells"]:
			assert_bool(order.has(LayoutGen.ground_of(layouts, keys, c))).override_failure_message("%s in %s" % [c, kind]).is_true()
	for row: Variant in g["props"].values():
		for id: Variant in (row as Dictionary).values():
			assert_bool(g["size"].has(id)).override_failure_message(str(id)).is_true()
	var plain := layouts.duplicate(true)
	plain["grounds"]["patches"] = {}
	var map := {"w": 3, "h": 2, "rows": ["#.~", " T,"], "shape": "open"}
	var got := LayoutGen.grounds(plain, map)
	assert_array(Array(got)).is_equal([order.find("wall"), order.find("grass"), order.find("water"),
		LayoutGen.NO_GROUND, order.find("grass"), order.find("dirt")])
	map["shape"] = "building"
	assert_int(LayoutGen.grounds(plain, map)[1]).is_equal(order.find("planks"))
	assert_str(LayoutGen.prop_of(layouts, ["building", "*"], "B")).is_equal("table")
	assert_str(LayoutGen.prop_of(layouts, ["open", "*"], "B")).is_equal("boulder")


func test_a_place_of_a_kind_gets_its_own_ground_its_family_and_shape_the_rest() -> void:
	var at := func(map: Dictionary, c: String) -> String:
		return LayoutGen.ground_of(layouts, LayoutGen.ground_keys(layouts, map), c)
	assert_array(LayoutGen.ground_keys(layouts, {"kind": "inn", "shape": "building"})).is_equal(["inn", "tavern", "house", "building", "*"])
	assert_str(at.call({"kind": "temple", "shape": "building"}, ".")).is_equal("flagstone")
	assert_str(at.call({"kind": "inn", "shape": "building"}, ".")).is_equal("planks")
	assert_str(at.call({"kind": "cave", "shape": "tunnels"}, "#")).is_equal("rock")
	assert_str(at.call({"kind": "tavern", "shape": "building"}, "#")).is_equal("wall")
	assert_str(at.call({"kind": "dunes", "shape": "open"}, ".")).is_equal("sand")
	assert_str(at.call({"kind": "swamp", "shape": "open"}, "~")).is_equal("still_water")
	assert_str(at.call({"shape": "open"}, ".")).is_equal("grass")
	assert_str(LayoutGen.prop_of(layouts, LayoutGen.ground_keys(layouts, {"kind": "ruin", "shape": "open"}), "B")).is_equal("rubble")


func test_a_shore_has_a_beach_round_its_water_and_a_desert_no_patches_of_earth() -> void:
	var order: Array = layouts["grounds"]["order"]
	var rim := layouts.duplicate(true)
	rim["grounds"]["patches"]["shore"] = (rim["grounds"]["patches"]["shore"] as Array).filter(func(r: Dictionary) -> bool: return r.has("near"))
	var map := {"id": "r", "w": 5, "h": 3, "rows": [".....", "..~..", "....."], "shape": "open", "kind": "shore", "seed": 1}
	var got := LayoutGen.grounds(rim, map)
	assert_int(got[0]).is_equal(order.find("grass"))
	assert_int(got[1]).is_equal(order.find("sand"))
	assert_int(got[7]).is_equal(order.find("water"))
	assert_int(got[4]).is_equal(order.find("grass"))
	var dunes := LayoutGen.open_map(layouts, {"id": "d", "kind": "dunes", "tags": [], "exits": []}, 4)
	dunes["kind"] = "dunes"
	assert_bool(Array(LayoutGen.grounds(layouts, dunes)).has(order.find("dirt"))).is_false()


func test_a_caves_halls_are_ragged_in_rock_and_still_meet_by_their_sockets() -> void:
	for c: Dictionary in _room_chunks():  # a cave's chunk is no box: a blank outside its walls somewhere
		var kinds: Array = c.get("kinds", [])
		if not kinds.is_empty() and kinds.all(func(k: Variant) -> bool: return k in ["cave", "mine"]):
			assert_bool((c["rows"] as Array).any(func(r: Variant) -> bool: return str(r).contains(LayoutGen.BLANK))).override_failure_message(str(c["id"])).is_true()
	var asks: Array[Dictionary] = []
	for i: int in 4:
		var links: Array = []
		if i > 0:
			links.append("r%d" % (i - 1))
		if i < 3:
			links.append("r%d" % (i + 1))
		asks.append({"id": "r%d" % i, "kind": "cave", "role": "hall" if i == 0 else "", "tags": [], "size": "medium", "links": links,
			"exits": [{"to": "out", "side": "s", "kind": "door"}] if i == 0 else []})
	var order: Array = layouts["grounds"]["order"]
	for sd: int in 4:
		var map := LayoutGen.stitched(layouts, asks, sd * 13 + 1, {})
		assert_array(map.get("left", [])).override_failure_message("seed %d" % sd).is_empty()
		map["shape"] = "tunnels"
		map["kind"] = "cave"
		var got := LayoutGen.grounds(layouts, map)
		var rows: Array = map["rows"]
		for y: int in rows.size():  # the blank between the halls is rock, as their walls are
			for x: int in (rows[y] as String).length():
				if (rows[y] as String)[x] == LayoutGen.BLANK:
					assert_int(got[y * int(map["w"]) + x]).is_equal(order.find("rock"))


func test_an_open_maps_grounds_lie_in_patches_with_no_lone_square() -> void:
	for kind: String in ["wild", "forest", "swamp", "shore", "square"]:
		for sd: int in 4:
			var ask := {"id": "r", "kind": kind, "tags": ["water"] if kind == "shore" else [], "exits": [{"to": "a", "side": "n", "kind": "edge"}]}
			var map := LayoutGen.open_map(layouts, ask, sd * 7 + 3)
			var rows: Array = map["rows"]
			for y: int in rows.size():
				for x: int in (rows[y] as String).length():
					var c: String = rows[y][x]
					if not c in ["~", "%"]:
						continue
					var same := 0
					for side: String in LayoutGen.SIDES:
						var n: Vector2i = Vector2i(x, y) + LayoutGen.STEP[side]
						if n.y >= 0 and n.y < rows.size() and n.x >= 0 and n.x < (rows[n.y] as String).length() and rows[n.y][n.x] == c:
							same += 1
					assert_int(same).override_failure_message("%s seed %d: a lone %s at %d,%d" % [kind, sd, c, x, y]).is_greater_equal(1)


func test_a_building_on_an_open_map_has_walls_round_a_roof() -> void:
	var ask := {"id": "r", "kind": "square", "tags": [], "exits": [{"to": "a", "side": "n", "kind": "door"}, {"to": "b", "side": "s", "kind": "door"}]}
	var map := LayoutGen.open_map(layouts, ask, 5)
	var roofs := 0
	for e: Dictionary in map["exits"]:
		if not e.has("box"):
			continue
		var b: Array = e["box"]
		for y: int in range(int(b[1]), int(b[1]) + int(b[3])):
			for x: int in range(int(b[0]), int(b[0]) + int(b[2])):
				var c: String = map["rows"][y][x]
				var edge := x == int(b[0]) or y == int(b[1]) or x == int(b[0]) + int(b[2]) - 1 or y == int(b[1]) + int(b[3]) - 1
				if c == LayoutGen.DOOR:
					continue
				assert_str(c).override_failure_message("%d,%d" % [x, y]).is_equal(LayoutGen.WALL if edge else LayoutGen.ROOF)
				roofs += 1 if c == LayoutGen.ROOF else 0
	assert_int(roofs).is_greater(0)


func test_patches_of_ground_come_out_the_same_for_one_map() -> void:
	var map := LayoutGen.open_map(layouts, {"id": "r", "kind": "wild", "tags": [], "exits": []}, 9)
	map["seed"] = 9
	var a := LayoutGen.grounds(layouts, map)
	assert_array(Array(a)).is_equal(Array(LayoutGen.grounds(layouts, map)))
	assert_bool(Array(a).has((layouts["grounds"]["order"] as Array).find("dirt"))).is_true()


func test_an_edge_sheet_is_laid_on_corners_that_give_each_case_once() -> void:
	var g: Dictionary = layouts["grounds"]
	var rows: Array = g["edge_layout"]
	assert_int(rows.size()).is_equal(5)
	var seen := {}
	for y: int in 4:
		for x: int in 4:
			seen["%s%s%s%s" % [str(rows[y])[x], str(rows[y])[x + 1], str(rows[y + 1])[x], str(rows[y + 1])[x + 1]]] = true
	assert_int(seen.size()).is_equal(16)
	var cells := Array(MapGround.edge_cells(layouts))
	cells.sort()
	assert_array(cells).is_equal(range(16))
	var order: Array = g["order"]
	for pair: Dictionary in g["edges"]:
		var low := order.find(pair["low"])
		var high := order.find(pair["high"])
		assert_bool(low >= 0 and high > low).override_failure_message(str(pair)).is_true()
		assert_bool((g["sharp"] as Array).has(pair["high"])).override_failure_message(str(pair)).is_false()
