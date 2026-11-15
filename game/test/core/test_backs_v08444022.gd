extends GdUnitTestSuite
## v0.8.4.44.2.2, the author (2026-11-14): «у нас сцена в таверне повёрнута не правильно же». A thing whose picture has a
## front (a stage, a desk, a chest, a bed's head) has its `back` in `rules.things.bodies`: the engine lays it with that side
## to a wall where it may, and the tavern's stage of every furnishing looks into the hall.

var data: Dictionary
var lib: Dictionary


func before_test() -> void:
	data = TestUtils.data()
	lib = data["layouts"]


## A room of floor x 0…w-1, y 0…h-1 with walls round it.
func _room(w: int, h: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y: int in h:
		for x: int in w:
			out.append(Vector2i(x, y))
	return out


func _as_set(cells: Array[Vector2i]) -> Dictionary:
	var out := {}
	for c: Vector2i in cells:
		out[c] = true
	return out


func test_a_stage_by_the_east_wall_has_its_back_to_it_turned_three_quarters() -> void:
	var room := _as_set(_room(14, 11))
	var east := MapSpots.footprint([3, 2], Vector2i(12, 8), 3)  # 2 × 3 at x 12–13
	assert_bool(MapSpots.back_to_wall("n", east, 3, room)).is_true()  # its top looks east, at the wall
	assert_bool(MapSpots.back_to_wall("n", east, 1, room)).is_false()  # its top looks west, into the hall
	var bed := MapSpots.footprint([2, 1], Vector2i(0, 0), 0)
	assert_bool(MapSpots.back_to_wall("w", bed, 0, room)).is_true()  # the head is the picture's left
	assert_bool(MapSpots.back_to_wall("w", bed, 2, room)).is_false()


func test_the_engine_lays_a_stage_at_its_mark_with_its_back_to_the_wall_for_every_seed() -> void:
	var cells := _room(10, 7)
	var room := _as_set(cells)
	var at := Vector2i(9, 3)  # a mark by the east wall
	for sd: int in 24:
		var laid := MapSpots._lay(data, "stage", "seed %d" % sd, at, cells, cells, [], {}, {}, true, {at: true})
		assert_bool(bool(laid.get("loose", false))).override_failure_message("seed %d" % sd).is_false()
		assert_array(laid["cells"]).override_failure_message("seed %d" % sd).contains([at])
		assert_bool(MapSpots.back_to_wall("n", laid["cells"], int(laid["turn"]), room)).override_failure_message(
			"seed %d: turn %d at %s" % [sd, int(laid["turn"]), laid["at"]]).is_true()


func test_a_chest_laid_near_a_wall_turns_its_lock_to_the_room() -> void:
	var cells := _room(6, 5)
	var room := _as_set(cells)
	for sd: int in 12:
		var laid := MapSpots._lay(data, "chest", "chest %d" % sd, Vector2i(2, 0), cells, cells, [], {}, {}, false)
		assert_bool(MapSpots.back_to_wall("n", laid["cells"], int(laid["turn"]), room)).override_failure_message("seed %d" % sd).is_true()


func test_a_thing_with_no_back_keeps_its_turn_by_the_seed() -> void:
	var cells := _room(6, 5)
	var turns := {}
	for sd: int in 24:
		turns[int(MapSpots._lay(data, "table", "table %d" % sd, Vector2i(2, 2), cells, cells, [], {}, {}, false)["turn"])] = true
	assert_int(turns.size()).is_greater(1)


func test_the_tavern_s_stage_looks_into_the_hall_in_every_furnishing() -> void:
	var chunk: Dictionary = (lib["chunks"] as Array).filter(func(c: Dictionary) -> bool: return str(c["id"]) == "tavern_hall")[0]
	var rows: Array = chunk["rows"]
	var floor: Array[Vector2i] = []
	for y: int in rows.size():
		for x: int in str(rows[y]).length():
			if str(rows[y])[x] != LayoutGen.WALL:
				floor.append(Vector2i(x, y))
	var room := _as_set(floor)
	var back := str(data["rules"]["things"]["bodies"]["stage"]["back"])
	var seen := 0
	for f: Dictionary in chunk["furnish"]:
		for t: Dictionary in f["things"]:
			if str(t["body"]) != "stage":
				continue
			seen += 1
			var turn := int(t.get("turn", 0))
			var mine := MapSpots.footprint([3, 2], Vector2i(int(t["x"]), int(t["y"])), turn)
			assert_bool(MapSpots.back_to_wall(back, mine, turn, room)).override_failure_message("%s: turn %d" % [f["name"], turn]).is_true()
	assert_int(seen).is_greater(0)


## v0.8.4.44.3.1, the author: «Да, поверни» — no thing of any furnishing of any chunk has its front to a wall and its back
## free (a desk turned to the wall, a chest with its lock at the wall); the chunk editor warns of it alike (`facesWall`).
func test_no_thing_of_any_furnishing_looks_at_a_wall() -> void:
	var bodies: Dictionary = data["rules"]["things"]["bodies"]
	var cells: Dictionary = lib["cells"]
	var bad: Array[String] = []
	for chunk: Dictionary in lib["chunks"]:
		var rows: Array = chunk.get("rows", [])
		var marks: Dictionary = chunk.get("marks", {})
		var floor: Array[Vector2i] = []
		for y: int in rows.size():
			for x: int in str(rows[y]).length():
				var c := str(rows[y])[x]
				if c != LayoutGen.BLANK and (marks.has(c) or c in ["+", "D"] or not bool(cells.get(c, {}).get("solid", false))):
					floor.append(Vector2i(x, y))
		var room := _as_set(floor)
		for f: Dictionary in chunk.get("furnish", []):
			for t: Dictionary in f["things"]:
				var back := str(bodies.get(str(t["body"]), {}).get("back", ""))
				if back.is_empty():
					continue
				var turn := int(t.get("turn", 0))
				var mine := MapSpots.footprint(bodies[str(t["body"])]["size"], Vector2i(int(t["x"]), int(t["y"])), turn)
				var front: String = LayoutGen.TOPS[(LayoutGen.TOPS.find(back) + 2) % 4]
				if MapSpots.back_to_wall(front, mine, turn, room) and not MapSpots.back_to_wall(back, mine, turn, room):
					bad.append("%s «%s»: %s (%d, %d) turn %d" % [chunk["id"], f.get("name", ""), t["body"], int(t["x"]), int(t["y"]), turn])
	assert_array(bad).override_failure_message("лицом к стене:\n" + "\n".join(bad)).is_empty()
