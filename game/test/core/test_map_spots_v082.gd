extends GdUnitTestSuite
## v0.8.2: people and things on the map. Everyone of the room has a square of its own, the same one until the hour turns;
## a trader stands at its counter; furniture stays words; the master moves people by words and sees no squares.

var data: Dictionary


func before() -> void:
	data = TestUtils.data().duplicate(true)


func _session(room: String = "brod-tavern-hall") -> GameSession:
	var s := TestUtils.new_session()
	s.game_seed = 42
	s.room_id = room
	return s


func _tokens(s: GameSession) -> Array[Dictionary]:
	return MapSpots.of(s, data, WalkRules.view(s, data))


func _token(s: GameSession, ref: String) -> Dictionary:
	for t: Dictionary in _tokens(s):
		if str(t["ref"]) == ref:
			return t
	return {}


func _at(t: Dictionary) -> Vector2i:
	return Vector2i(int(t["x"]), int(t["y"]))


func test_everyone_of_every_room_stands_on_a_free_square_of_that_room() -> void:
	var s := _session()
	for room: String in data["world"]["rooms"]:
		s.room_id = room
		var map := WalkRules.view(s, data)
		var seen := {}
		for t: Dictionary in MapSpots.of(s, data, map):
			if str(t["kind"]) == "station" or int(t.get("bars", 0)) & MapSpots.PATH:  # a thing that bars the way stands on its own
				continue
			var at := _at(t)
			assert_bool(seen.has(at)).override_failure_message("%s: two on %s" % [room, at]).is_false()
			seen[at] = true
			assert_str(WalkRules.room_of(map, at)).is_equal(room)
			assert_bool(WalkRules.passable(map, data["layouts"], at)).is_true()


func test_a_spot_stays_while_the_hour_stays() -> void:
	var s := _session()
	assert_array(_tokens(s)).is_equal(_tokens(s))


func test_a_spot_comes_back_from_a_save() -> void:
	var s := _session()
	var before_load := _tokens(s)
	var back := GameSession.from_dict(JSON.parse_string(JSON.stringify(s.to_dict(5))))
	assert_array(_tokens(back)).is_equal(before_load)


func test_a_trader_stands_by_its_counter() -> void:
	var s := _session()
	var map := WalkRules.view(s, data)
	var bruno: Dictionary = {}
	for t: Dictionary in MapSpots.of(s, data, map):
		if WorldView.new(data["world"]).is_trader(str(t["id"])):
			bruno = t
	assert_dict(bruno).is_not_empty()
	var counters := (map["marks"] as Array).filter(func(m: Dictionary) -> bool: return str(m["name"]) == "counter")
	if not counters.is_empty():
		assert_int(WalkRules.distance(_at(bruno), Vector2i(int(counters[0]["x"]), int(counters[0]["y"])))).is_less_equal(3)


func test_followers_walk_with_the_hero_and_are_no_tokens() -> void:
	var s := _session()
	var id := str(s.npcs_here(data["world"], s.room_id)[0])
	assert_dict(_token(s, "npc:" + id)).is_not_empty()
	FollowRules.apply(s, {"follow_npc": id, "on": true, "room": ""})
	assert_dict(_token(s, "npc:" + id)).is_empty()


func test_furniture_stays_words_and_what_can_be_used_is_on_the_map() -> void:
	var s := _session()
	s.props[s.room_id] = [
		{"id": "bench", "name": "Скамья", "item_id": "", "owner": "", "text": "", "state": ""},
		{"id": "mug", "name": "Кружка", "item_id": "ale", "owner": "", "text": "", "state": ""},
		{"id": "box", "name": "Сундук", "item_id": "", "owner": "", "text": "", "state": "", "container": "chest"},
		{"id": "sign", "name": "Вывеска", "item_id": "", "owner": "", "text": "Эль", "state": ""},
	]
	assert_dict(_token(s, "prop:bench")).is_empty()
	for ref: String in ["prop:mug", "prop:box", "prop:sign"]:
		assert_dict(_token(s, ref)).is_not_empty()


func test_a_thing_stands_by_the_mark_the_master_named() -> void:
	var s := _session()
	var map := WalkRules.view(s, data)
	var mark: Dictionary = (map["marks"] as Array).filter(func(m: Dictionary) -> bool: return str(m["name"]) != LayoutGen.ENTRY)[0]
	s.props[s.room_id] = [{"id": "box", "name": "Сундук", "item_id": "", "owner": "", "text": "", "state": "", "container": "chest", "near": str(mark["name"])}]
	assert_int(WalkRules.distance(_at(_token(s, "prop:box")), Vector2i(int(mark["x"]), int(mark["y"])))).is_less_equal(3)


func test_the_master_walks_the_hero_up_to_a_person() -> void:
	var s := _session()
	var id := str(s.npcs_here(data["world"], s.room_id)[0])
	var plan := MapSpots.plan(s, data, {"who": "hero", "to": id})
	assert_dict(plan).contains_keys(["plan", "summary"])
	MapSpots.apply(s, data, plan["plan"])
	var map := WalkRules.view(s, data)
	assert_int(WalkRules.distance(WalkRules.settle(s, data, map), _at(_token(s, "npc:" + id)))).is_less_equal(1)


func test_the_master_walks_a_person_up_to_the_hero_until_the_hour_turns() -> void:
	var s := _session()
	var map := WalkRules.view(s, data)
	var hero := WalkRules.settle(s, data, map)
	var id := str(s.npcs_here(data["world"], s.room_id)[0])
	MapSpots.apply(s, data, MapSpots.plan(s, data, {"who": id, "to": "hero"})["plan"])
	assert_int(WalkRules.distance(hero, _at(_token(s, "npc:" + id)))).is_less_equal(1)
	s.layouts["moved"][id]["part"] = "иное время"
	assert_dict(_token(s, "npc:" + id)).is_not_empty()


func test_the_master_cannot_walk_to_what_is_not_here() -> void:
	var s := _session()
	assert_dict(MapSpots.plan(s, data, {"who": "hero", "to": "nobody"})).contains_keys(["reason"])
	assert_dict(MapSpots.plan(s, data, {"who": "nobody", "to": "hero"})).contains_keys(["reason"])
	assert_dict(MapSpots.plan(s, data, {"who": "hero", "to": "hero"})).contains_keys(["reason"])


func test_the_master_gets_words_not_squares() -> void:
	var s := _session()
	var snap := TurnSnapshot.build(s, data, 2000)
	var scene: Dictionary = snap["scene"]
	assert_array(scene["spots"]).is_not_empty()
	assert_str(str(scene["spots"][0])).contains("[")
	var words: Array = (data["rules"]["map"]["distance"] as Array).map(func(d: Dictionary) -> String: return str(d["word"]))
	for n: Dictionary in scene["npcs"]:
		assert_array(words).contains([n["near"]])
	assert_bool(JSON.stringify(scene).contains("\"x\":")).is_false()


func test_a_way_up_stays_in_the_room_and_stops_in_reach() -> void:
	var rows: Array[String] = ["....."]
	var map := {"id": "t", "w": 5, "h": 1, "rows": rows, "rooms": PackedInt32Array([0, 0, 0, 1, 1]), "ids": ["a", "b"], "exits": [], "doors": [], "marks": []}
	var lib: Dictionary = data["layouts"]
	assert_array(WalkRules.near(map, lib, Vector2i(0, 0), Vector2i(2, 0), 1, "a")).is_equal([Vector2i(1, 0)])
	assert_array(WalkRules.near(map, lib, Vector2i(1, 0), Vector2i(2, 0), 1, "a")).is_empty()
	assert_array(WalkRules.near(map, lib, Vector2i(0, 0), Vector2i(4, 0), 1, "a")).is_empty()


## v0.8.4.43.23: a thing of many squares. A table takes two squares in a line, both bar the way of the walk and are blocks
## of a fight; a cabinet bars the eye; the forge of the smithy's mark is two by two round its mark.
func test_a_thing_of_many_squares_takes_them_all_on_the_walk_the_eye_and_the_fight() -> void:
	var s := _session()
	s.props[s.room_id] = [
		{"id": "long", "name": "Стол", "item_id": "", "owner": "", "text": "", "state": "", "body": "table"},
		{"id": "wardrobe", "name": "Шкаф", "item_id": "", "owner": "", "text": "", "state": "", "body": "cabinet"},
		{"id": "pot", "name": "Горшок", "item_id": "", "owner": "", "text": "", "state": "", "body": "plant_pot"},
	]
	var table := _token(s, "prop:long")
	var cells: Array = table["cells"]
	assert_int(cells.size()).is_equal(2)
	assert_int(WalkRules.distance(cells[0], cells[1])).is_equal(1)
	assert_bool(cells.has(_at(table))).is_true()
	var view := WalkRules.view(s, data)
	for c: Vector2i in cells:
		assert_bool(WalkRules.passable(view, data["layouts"], c)).override_failure_message(str(c)).is_false()
	for c: Vector2i in _token(s, "prop:wardrobe")["cells"]:
		assert_bool(SightRules.veiled(view, c)).is_true()
	for c: Vector2i in _token(s, "prop:pot")["cells"]:  # a pot is walked past: it bars nothing
		assert_bool(WalkRules.passable(view, data["layouts"], c)).is_true()
	CombatRules.start(s, data, [{"monster": "goblin", "count": 1}])
	FightField.lay(s, data)
	for c: Vector2i in cells:
		var b: Dictionary = s.combat["blocks"].get(FightGrid.tag(c), {})
		assert_str(str(b.get("body", ""))).is_equal("table")
		assert_int(int(b["flags"]) & FightGrid.SOLID).is_equal(FightGrid.SOLID)
	var forge := _token(_session("brod-smithy"), "station:forge")
	assert_int((forge["cells"] as Array).size()).is_equal(4)
	assert_bool((forge["cells"] as Array).has(_at(forge))).is_true()


func test_a_thing_turns_by_the_seed_and_its_squares_follow() -> void:
	assert_array(MapSpots.footprint([3, 2], Vector2i(1, 1), 0)).has_size(6).contains([Vector2i(3, 2)])
	assert_array(MapSpots.footprint([3, 2], Vector2i(1, 1), 1)).has_size(6).contains([Vector2i(2, 3)])
	assert_array(MapSpots.footprint([3, 2], Vector2i(1, 1), 1)).not_contains([Vector2i(3, 1)])


## v0.8.4.43.26: the spots of a chunk. The tavern's hall has its own tables with benches beside them, its counter along
## the whole run of its marks; another seed — another hall; the spots left free and what stands go to the master.
func test_a_room_stands_its_own_things_on_its_spots_with_their_companions() -> void:
	var s := _session()
	s.props[s.room_id] = []
	var things := _tokens(s).filter(func(t: Dictionary) -> bool: return str(t["kind"]) == "thing")
	var tables := things.filter(func(t: Dictionary) -> bool: return str(t["body"]) == "table")
	assert_int(tables.size()).is_greater(0)
	var benches := things.filter(func(t: Dictionary) -> bool: return str(t["body"]) == "bench")
	assert_int(benches.size()).is_greater(0)
	for b: Dictionary in benches:  # a bench stands by a table
		var by := tables.any(func(t: Dictionary) -> bool:
			return (b["cells"] as Array).any(func(c: Vector2i) -> bool:
				return (t["cells"] as Array).any(func(d: Vector2i) -> bool: return WalkRules.distance(c, d) <= 1)))
		assert_bool(by).is_true()
	var counters := things.filter(func(t: Dictionary) -> bool: return str(t["body"]) == "counter")
	var view := WalkRules.view(s, data)
	var index := (view["ids"] as Array).find(s.room_id)
	var run := (view["marks"] as Array).filter(func(m: Dictionary) -> bool: return str(m["name"]) == "counter" and int(m["room"]) == index)
	var covered := {}
	for t: Dictionary in counters:
		for c: Vector2i in t["cells"]:
			covered[c] = true
	for m: Dictionary in run:  # the counter's marks covered whole, a counter of three squares along them
		assert_bool(covered.has(Vector2i(int(m["x"]), int(m["y"])))).is_true()
	assert_int(covered.size()).is_equal(run.size())
	var seen := {}
	for t: Dictionary in _tokens(s):
		for c: Vector2i in t.get("cells", [_at(t)]):
			assert_bool(seen.has(c) and str(t["kind"]) != "station").override_failure_message(str(c)).is_false()
			seen[c] = true
	var other := _session()
	other.game_seed = s.game_seed + 7
	other.props[other.room_id] = []
	var a := JSON.stringify(things.map(func(t: Dictionary) -> String: return str(t["body"]) + str(t["cells"])))
	var b2 := JSON.stringify(_tokens(other).filter(func(t: Dictionary) -> bool: return str(t["kind"]) == "thing").map(func(t: Dictionary) -> String: return str(t["body"]) + str(t["cells"])))
	assert_str(a).is_not_equal(b2)
	var words := MapSpots.furniture_words(s, data)
	assert_array(words["stood"]).is_not_empty()


func test_the_masters_furniture_takes_a_free_spot_of_its_group() -> void:
	var s := _session()
	s.props[s.room_id] = []
	var free := MapSpots.free_spots(s, data)
	var storage := free.filter(func(sp: Dictionary) -> bool: return str(sp["group"]) == "storage")
	if storage.is_empty():  # every spot of the seed filled: another seed
		for i: int in 20:
			s.game_seed += 1
			storage = MapSpots.free_spots(s, data).filter(func(sp: Dictionary) -> bool: return str(sp["group"]) == "storage")
			if not storage.is_empty():
				break
	assert_array(storage).is_not_empty()
	var spots: Array = storage.map(func(sp: Dictionary) -> Vector2i: return sp["at"])
	s.props[s.room_id] = [{"id": "cask", "name": "Бочка", "item_id": "", "owner": "", "text": "", "state": "", "body": "barrel"}]
	assert_bool(spots.has(_at(_token(s, "prop:cask")))).is_true()
	var cask := _at(_token(s, "prop:cask"))
	assert_bool(MapSpots.free_spots(s, data).any(func(sp: Dictionary) -> bool: return sp["at"] == cask)).is_false()
