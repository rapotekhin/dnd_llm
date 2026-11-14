extends GdUnitTestSuite
## v0.8.4.43.60, the author (2026-11-14): «кошка заспавнилась внутри сцены… Починка культистов должна была починить этот баг у
## всех персонажей игры». Everybody already stood by one rule — `taken` of MapSpots: a person, a creature, a body and a foe
## never on a square a thing takes. The stage broke it: with no whole place round its mark it was laid "loose" on one square
## and drawn whole over the squares it did not take, where the tavern's cat and the board stood. Now a thing takes on the
## map the very squares it is drawn on: whole beside its mark when it does not fit round it, a token of one square with no
## picture when it fits nowhere.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _room(room: String, seed_value: int) -> GameSession:
	var s := TestUtils.new_session()
	s.room_id = room
	s.game_seed = seed_value
	PetRules.seed(s, data, room)  # the room's beasts: the tavern's cat
	return s


## The squares the things of `tokens` are drawn on (MapGround.place: a picture of its body's size from its corner, turned).
func _drawn(tokens: Array[Dictionary]) -> Dictionary:
	var out := {}
	for t: Dictionary in tokens:
		if t.has("corner"):
			var size: Array = data["rules"]["things"]["bodies"].get(str(t["body"]), {}).get("size", [1, 1])
			for c: Vector2i in MapSpots.footprint(size, t["corner"], int(t["turn"])):
				out[c] = str(t["body"])
		elif str(t["kind"]) in ["thing", "station", "prop"]:
			out[Vector2i(int(t["x"]), int(t["y"]))] = str(t["kind"])
	return out


func _rooms() -> Array:
	return (data["world"]["rooms"] as Dictionary).keys()


## Every thing of every room of the pack takes the squares its picture covers, no more, no fewer.
func test_a_thing_takes_the_squares_it_is_drawn_on() -> void:
	var bodies: Dictionary = data["rules"]["things"]["bodies"]
	for room: String in _rooms():
		for seed_value: int in 6:
			var s := _room(room, 3000 + seed_value)
			for t: Dictionary in MapSpots.of(s, data, WalkRules.view(s, data)):
				if not t.has("corner"):
					continue
				var size: Array = bodies.get(str(t["body"]), {}).get("size", [1, 1])
				var pic := MapSpots.footprint(size, t["corner"], int(t["turn"]))
				assert_array(t["cells"]).override_failure_message("%s seed %d: %s drawn on %s, takes %s" % [room, s.game_seed, t["body"], pic, t["cells"]]) \
					.contains_exactly_in_any_order(pic)


## The tavern's hall over many seeds: the cat, the people and the board never on the stage, the hearth or a table.
func test_nobody_stands_on_a_thing_in_the_tavern() -> void:
	for seed_value: int in 40:
		var s := _room("brod-tavern-hall", 4000 + seed_value)
		var tokens := MapSpots.of(s, data, WalkRules.view(s, data))
		assert_bool(tokens.any(func(t: Dictionary) -> bool: return str(t["kind"]) == "creature")).is_true()  # the cat is here
		var stage := tokens.filter(func(t: Dictionary) -> bool: return str(t.get("body", "")) == "stage")
		assert_array(stage).override_failure_message("seed %d: the stage lost its body" % s.game_seed).has_size(1)
		assert_array(stage[0]["cells"]).has_size(6)  # whole, 3 × 2
		_none_on_things(tokens, "brod-tavern-hall", s.game_seed)


## The same rule in every room of the pack: a person, a creature, a body never on a thing, nor a thing on a thing.
func test_nobody_stands_on_a_thing_anywhere() -> void:
	for room: String in _rooms():
		for seed_value: int in 4:
			var s := _room(room, 5000 + seed_value)
			_none_on_things(MapSpots.of(s, data, WalkRules.view(s, data)), room, s.game_seed)


func _none_on_things(tokens: Array[Dictionary], room: String, seed_value: int) -> void:
	var drawn := _drawn(tokens)
	for t: Dictionary in tokens:
		if str(t["kind"]) in ["npc", "creature", "body"]:
			var at := Vector2i(int(t["x"]), int(t["y"]))
			assert_bool(drawn.has(at)).override_failure_message("%s seed %d: %s stands on %s at %s" % [room, seed_value, t["ref"], drawn.get(at), at]).is_false()
	var seen := {}
	for t: Dictionary in tokens:
		if t.has("corner") or str(t["kind"]) in ["thing", "station", "prop"]:
			for c: Vector2i in t.get("cells", [Vector2i(int(t["x"]), int(t["y"]))]):
				assert_bool(seen.has(c)).override_failure_message("%s seed %d: %s over %s at %s" % [room, seed_value, t["ref"], seen.get(c), c]).is_false()
				seen[c] = t["ref"]


## The foes of a lair (the fix of v0.8.4.43.49) and a creature of the room in a fight start by the same `taken`.
func test_a_foe_and_a_fighter_of_the_room_start_off_the_things() -> void:
	var room := "brod-tavern-hall"
	for seed_value: int in 20:
		var s := _room(room, 6000 + seed_value)
		var tokens := MapSpots.of(s, data, LayoutRules.map_of(s, data, room))
		var drawn := _drawn(tokens)
		var heads := MapSpots.on_lair(s, data, "t_brawl", [{"monster": "thug", "name": "Громила"}, {"monster": "thug", "name": "Громила"},
			{"monster": "bandit", "name": "Разбойник"}])
		for h: Dictionary in heads:
			var at := Vector2i(int(h["x"]), int(h["y"]))
			assert_bool(drawn.has(at)).override_failure_message("seed %d: %s on %s at %s" % [s.game_seed, h["name"], drawn.get(at), at]).is_false()
			assert_bool(tokens.any(func(t: Dictionary) -> bool: return Vector2i(int(t["x"]), int(t["y"])) == at)).is_false()  # nor on one of the room
		var cat: Array = CreatureRules.here(s, room)
		var spot := MapSpots.of_fighter(s, data, {"creature_id": str(cat[0]["id"])})
		assert_bool(spot == FightGrid.NONE or drawn.has(spot)).override_failure_message("seed %d: the cat starts the fight on %s" % [s.game_seed, spot]).is_false()


## A station with no whole place round its mark stands whole beside it, not on one square drawn over others.
func test_a_station_with_no_room_round_its_mark_stands_whole_beside_it() -> void:
	var bodies: Dictionary = data["rules"]["things"]["bodies"]
	var size: Array = bodies["stage"]["size"]
	var spots: Array[Vector2i] = []
	for y: int in 6:
		for x: int in 6:
			spots.append(Vector2i(x, y))
	var taken := {Vector2i(1, 0): true, Vector2i(0, 1): true, Vector2i(1, 1): true}  # the mark (0, 0) shut in a corner
	var laid := MapSpots._lay(data, "stage", "k", Vector2i(0, 0), spots, spots, [] as Array[Vector2i], {}, taken, true)
	assert_bool(laid.has("loose")).is_false()
	assert_int((laid["cells"] as Array).size()).is_equal(int(size[0]) * int(size[1]))
	assert_bool((laid["cells"] as Array).any(func(c: Vector2i) -> bool: return taken.has(c))).is_false()
	var none := MapSpots._lay(data, "stage", "k", Vector2i(0, 0), [Vector2i(0, 0)] as Array[Vector2i], spots, [] as Array[Vector2i], {}, {}, true)
	assert_bool(none.has("loose")).is_true()  # fits nowhere: one square, its body not drawn
	var t := {"ref": "station:stage", "kind": "station", "id": "stage", "name": "Сцена", "x": 0, "y": 0}
	MapSpots._with_body(data, t, "stage", none, {})
	assert_bool(t.has("corner") or t.has("body")).is_false()
