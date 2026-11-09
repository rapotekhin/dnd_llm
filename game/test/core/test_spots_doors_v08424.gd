extends GdUnitTestSuite
## v0.8.4.24: a thing never lies in a doorway. A prop, a body or a trap gets a square of the room that is no door, no way
## out and no square before a way out; the doors are kept clear by `keep_free` of the door's cell in layouts.json.

var data: Dictionary


func before() -> void:
	data = TestUtils.data().duplicate(true)


func _session(room: String) -> GameSession:
	var s := TestUtils.new_session()
	s.game_seed = 42
	s.room_id = room
	return s


func _props(s: GameSession, room: String, n: int) -> void:
	var list: Array = []
	for i: int in n:
		list.append({"id": "thing%d" % i, "name": "Вещь %d" % i, "item_id": "torch", "owner": "", "text": "", "state": ""})
	s.props[room] = list


func _ways(map: Dictionary, room: String) -> Dictionary:
	var out := {}
	var index := (map["ids"] as Array).find(room)
	for e: Dictionary in map["exits"]:
		if str(e["room"]) == room:
			out[Vector2i(int(e["x"]), int(e["y"]))] = true
			out[Vector2i(int(e["ax"]), int(e["ay"]))] = true
	for d: Dictionary in map["doors"]:
		if index in [int(d["a"]), int(d["b"])]:
			out[Vector2i(int(d["x"]), int(d["y"]))] = true
	return out


func _things(tokens: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for t: Dictionary in tokens:
		if str(t["kind"]) in ["prop", "body", "creature"]:
			out.append(t)
	return out


## A corridor of three squares, the third a door into the next room: before the fix the third thing stood in it.
func test_a_thing_never_lies_on_a_door_between_rooms() -> void:
	var s := _session("t-a")
	var rows: Array[String] = ["..+.."]
	var map := {"id": "t", "w": 5, "h": 1, "rows": rows, "rooms": PackedInt32Array([0, 0, 0, 1, 1]), "ids": ["t-a", "t-b"],
		"exits": [], "doors": [{"x": 2, "y": 0, "a": 0, "b": 1}], "marks": []}
	_props(s, "t-a", 3)
	for t: Dictionary in _things(MapSpots.of(s, data, map)):
		assert_that(Vector2i(int(t["x"]), int(t["y"]))).override_failure_message("%s on the door" % t["ref"]).is_not_equal(Vector2i(2, 0))


## A way out of the map at its edge: neither its door nor the square before it holds a thing.
func test_a_thing_never_lies_on_a_way_out() -> void:
	var s := _session("t-a")
	var rows: Array[String] = ["+...."]
	var map := {"id": "t", "w": 5, "h": 1, "rows": rows, "rooms": PackedInt32Array([0, 0, 0, 0, 0]), "ids": ["t-a"],
		"exits": [{"to": "t-out", "room": "t-a", "x": 0, "y": 0, "ax": 1, "ay": 0, "side": "w", "kind": "door"}], "doors": [], "marks": []}
	_props(s, "t-a", 4)
	for t: Dictionary in _things(MapSpots.of(s, data, map)):
		assert_int(int(t["x"])).override_failure_message("%s on the way out" % t["ref"]).is_greater(1)


## A trap that guards a door between two rooms lies before it, not in it.
func test_a_trap_lies_before_a_door_not_in_it() -> void:
	var s := _session("t-a")
	var rows: Array[String] = ["..+.."]
	var map := {"id": "t", "w": 5, "h": 1, "rows": rows, "rooms": PackedInt32Array([0, 0, 0, 1, 1]), "ids": ["t-a", "t-b"],
		"exits": [], "doors": [{"x": 2, "y": 0, "a": 0, "b": 1}], "marks": []}
	var at := MapSpots.secret_cell(s, data, map, "t-a", {"id": "trap", "trap": {"guards": "t-b"}})
	assert_that(at).is_equal(Vector2i(1, 0))


## Every room of the pack crowded with things: none on a door or a way out.
func test_no_thing_of_any_room_of_the_pack_stands_in_a_doorway() -> void:
	var s := _session("brod-tavern-hall")
	for room: String in data["world"]["rooms"]:
		s.room_id = room
		_props(s, room, 24)
		var map := WalkRules.view(s, data)
		var ways := _ways(map, room)
		for t: Dictionary in _things(MapSpots.of(s, data, map)):
			var at := Vector2i(int(t["x"]), int(t["y"]))
			var c := str((map["rows"] as Array)[at.y])[at.x]
			assert_bool(ways.has(at) or c == LayoutGen.DOOR).override_failure_message("%s: %s on a way at %s" % [room, t["ref"], at]).is_false()
		s.props.erase(room)


## v0.8.4.42.1 (the author: a person stood in a doorway, the door could not be clicked): no person of any room of the pack
## stands on a door or a way out, nor one who walked up to the hero there.
func test_no_person_of_any_room_of_the_pack_stands_in_a_doorway() -> void:
	var s := _session("brod-tavern-hall")
	var moved_once := false
	for room: String in data["world"]["rooms"]:
		s.room_id = room
		var map := WalkRules.view(s, data)
		var ways := _ways(map, room)
		var people := s.npcs_here(data["world"], room)
		if not moved_once and not people.is_empty() and not ways.is_empty():
			var door: Vector2i = ways.keys()[0]  # one walked up to the hero standing in the doorway
			var on := LayoutGen.on_grid(map, door)
			s.layouts["moved"] = {str(people[0]): {"room": room, "part": TimeRules.part_name(s, data), "x": on.x, "y": on.y}}
			moved_once = true
		for t: Dictionary in MapSpots.of(s, data, map) + MapSpots.foes(s, data, map):
			if not str(t["kind"]) in ["npc", "foe"]:
				continue
			var at := Vector2i(int(t["x"]), int(t["y"]))
			var c := str((map["rows"] as Array)[at.y])[at.x]
			assert_bool(ways.has(at) or c == LayoutGen.DOOR).override_failure_message("%s: %s in a doorway at %s" % [room, t["ref"], at]).is_false()
	assert_bool(moved_once).is_true()
