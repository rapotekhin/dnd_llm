extends GdUnitTestSuite
## v0.8.4.43.51, the author: «брать только те фурнитуры и расстановки предметов в помещении, которые были сделаны заранее в
## редакторе… фиксированную расстановку полностью». A room stands one furnishing of its chunk whole, the one for its kind of
## place, a station's thing as the furnishing sets it; nothing stands on a spot by chance — the spots left are the master's.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _tavern(seed_value: int) -> GameSession:
	var s := TestUtils.new_session()
	s.room_id = "brod-tavern-hall"
	s.props[s.room_id] = []
	s.game_seed = seed_value
	return s


func test_every_room_chunk_with_spots_or_a_station_thing_has_a_furnishing() -> void:
	var bodies: Dictionary = data["rules"]["map"]["station_bodies"]
	for ch: Dictionary in data["layouts"]["chunks"]:
		var marks: Array = (ch.get("marks", {}) as Dictionary).values()
		if marks.any(func(v: Variant) -> bool: return str(v).begins_with(MapSpots.SPOT) or bodies.has(str(v))):
			assert_array(ch.get("furnish", [])).override_failure_message(str(ch["id"])).is_not_empty()


func test_a_room_stands_one_furnishing_whole() -> void:
	var sets := {}
	for seed_value: int in 12:
		var s := _tavern(700 + seed_value)
		var map := WalkRules.view(s, data)
		var chunk := LayoutGen.chunk(data["layouts"], str(map["picks"][s.room_id]["chunk"]))
		var tokens := MapSpots.of(s, data, map)
		var mine := tokens.filter(func(t: Dictionary) -> bool: return t.has("set"))
		var used := {}
		for t: Dictionary in mine:
			used[int(t["set"])] = true
		assert_int(used.size()).is_equal(1)  # one furnishing, never a mix
		var one := int(used.keys()[0])
		sets[one] = true
		var whole: Array = (chunk["furnish"][one]["things"] as Array).filter(func(t: Dictionary) -> bool: return str(t.get("station", "")).is_empty())
		assert_int(mine.size()).override_failure_message("%s set %d: %s of %s" % [chunk["id"], one, mine.map(func(t: Dictionary) -> String: return t["body"]),
			whole.map(func(t: Dictionary) -> String: return t["body"])]).is_equal(whole.size())  # every thing of it stands
		assert_bool(tokens.any(func(t: Dictionary) -> bool: return t.has("spot"))).is_false()  # nothing on a spot by chance
	assert_int(sets.size()).is_greater(1)  # another seed — another of the chunk's furnishings


func test_a_station_stands_as_its_furnishing_sets_it() -> void:
	var s := _tavern(41)
	var map := WalkRules.view(s, data)
	var index := (map["ids"] as Array).find(s.room_id)
	var arranged := MapSpots.arranged(data, map, index, "%d|%s" % [s.game_seed, s.room_id], LayoutGen.ground_keys(data["layouts"], map))
	var hearth: Array = arranged.filter(func(m: Dictionary) -> bool: return str(m.get("station", "")) == "hearth")
	assert_array(hearth).has_size(1)
	var laid := MapSpots.set_laid(data, hearth[0])
	var token: Array = MapSpots.of(s, data, map).filter(func(t: Dictionary) -> bool: return str(t.get("body", "")) == "hearth")
	assert_array(token).has_size(1)
	assert_array(token[0]["cells"]).contains_exactly_in_any_order(laid["cells"])


func test_the_furnishing_is_the_one_for_the_kind_of_place() -> void:
	var marks: Array[Dictionary] = []
	for one: Array in [[0, ["registry"]], [1, ["school"]], [2, []]]:
		marks.append({"name": LayoutGen.SET + "crate", "x": 1, "y": 1, "room": 0, "set": one[0], "kinds": one[1], "piece": "0,0"})
	var map := {"marks": marks}
	for seed_value: int in 6:
		var key := "%d|r" % seed_value
		assert_int(int(MapSpots.arranged(data, map, 0, key, ["registry", "building", "*"])[0]["set"])).is_equal(0)
		assert_int(int(MapSpots.arranged(data, map, 0, key, ["tavern", "building", "*"])[0]["set"])).is_equal(2)  # none of its own: one that names none


func test_the_spots_no_thing_stands_on_are_the_masters() -> void:
	var s := _tavern(41)
	var map := WalkRules.view(s, data)
	var index := (map["ids"] as Array).find(s.room_id)
	var taken := {}
	for t: Dictionary in MapSpots.of(s, data, map):
		for c: Vector2i in t.get("cells", []):
			taken[c] = true
	var free := MapSpots.free_spots(s, data)
	for sp: Dictionary in MapSpots.spot_marks(map, index):
		var clear := not (sp["area"] as Array).any(func(c: Vector2i) -> bool: return taken.has(c))
		assert_bool(free.any(func(f: Dictionary) -> bool: return f["at"] == sp["at"])).is_equal(clear)
