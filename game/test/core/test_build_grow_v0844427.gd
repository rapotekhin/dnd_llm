extends GdUnitTestSuite
## Building without walls in the way (v0.8.4.42.7, the author: «я должен иметь возможность создавать комнаты беспрепятственно»):
## a room grows past a square clicked beyond its wall, its way out moving with the wall; a room built on behind an outer
## wall on the same map; a door in a doorway between two walls; on the yard a building as a box like the pack's, a plot
## past the edge, the yard grown with its ways where they stood on the ground; one line of what the hands did.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _home(room: String = "brod-river-house") -> GameSession:
	var s := TestUtils.new_session()
	s.settings["needs"] = false
	s.room_id = "brod-townhall"
	s.minute = 12 * 60
	s.character["gold_cp"] = 500000
	PropertyRules.buy(s, data, "river_house")
	s.room_id = room
	return s


func _map(s: GameSession) -> Dictionary:
	return LayoutRules.map_of(s, data, s.room_id)


func _char(s: GameSession, at: Vector2i) -> String:
	var map := _map(s)
	if at.x < 0 or at.y < 0 or at.x >= int(map["w"]) or at.y >= int(map["h"]):
		return " "
	return str(map["rows"][at.y])[at.x]


func _way(s: GameSession, to: String) -> Dictionary:
	for e: Dictionary in _map(s)["exits"]:
		if str(e["to"]) == to:
			return e
	return {}


func _named(name: String) -> String:
	for id: String in data["world"]["rooms"]:
		if str(data["world"]["rooms"][id].get("name", "")) == name:
			return id
	return ""


func test_a_room_grows_past_the_square_clicked_beyond_its_wall() -> void:
	var s := _home()
	var map := _map(s)
	var w := int(map["w"])
	var y := int(map["h"]) / 2
	assert_str(BuildRules.build_why(s, data, "wall", Vector2i(w + 1, y))).is_equal("BUILD_OUTSIDE")
	assert_str(BuildRules.build_why(s, data, BuildRules.GROW, Vector2i(2, 2))).is_equal("BUILD_GROW_SIDE")  # the floor inside
	assert_str(BuildRules.build_why(s, data, BuildRules.GROW, Vector2i(w + 1, y))).is_empty()
	var plan := BuildRules.grow_plan(s, data, Vector2i(w + 1, y))
	assert_int(int(plan["d"])).is_equal(3)
	assert_int(BuildRules.price(s, data, BuildRules.GROW, Vector2i(w + 1, y))).is_equal(int(plan["squares"]) * 20)
	var gold := int(s.character["gold_cp"])
	var lines := BuildRules.build(s, data, BuildRules.GROW, Vector2i(w + 1, y))
	assert_int(int(_map(s)["w"])).is_equal(w + 3)
	assert_int(int(s.character["gold_cp"])).is_equal(gold - int(plan["price_cp"]))
	assert_str(lines[0]).contains("шире на 3")
	assert_str(_char(s, Vector2i(w + 1, y))).is_equal(".")  # the clicked square is floor now
	assert_str(_char(s, Vector2i(w + 2, y))).is_equal("#")  # the wall past it
	assert_str(_char(s, Vector2i(w - 1, y))).is_equal(".")  # the old wall is floor
	var w2 := WorldGen.merged(TestUtils.data()["world"], s.generated)  # a loaded game keeps the room's own rows
	assert_array(w2["rooms"]["brod-river-house"]["layout"]["rows"]).is_not_empty()


func test_a_way_out_moves_with_its_wall_and_what_the_hands_built_there_stops_it() -> void:
	var s := _home()
	var door := _way(s, "brod-river-yard")
	assert_dict(door).is_not_empty()
	var wall := Vector2i(int(door["x"]), int(door["y"]))
	var side := str(door["side"])
	var past: Vector2i = wall + LayoutGen.STEP[side]  # one square out past the wall with the door
	var ground := LayoutGen.on_grid(_map(s), wall)
	BuildRules.build(s, data, BuildRules.GROW, past)
	var moved := _way(s, "brod-river-yard")
	assert_str(str(moved["side"])).is_equal(side)
	var now := LayoutGen.on_grid(_map(s), Vector2i(int(moved["x"]), int(moved["y"])))
	assert_that(now).is_equal(ground + LayoutGen.STEP[side] * 2)
	assert_str(_char(s, Vector2i(int(moved["x"]), int(moved["y"])))).is_equal("+")
	assert_bool(not WalkRules.path(_map(s), data["layouts"], WalkRules.settle(s, data, _map(s)), Vector2i(int(moved["ax"]), int(moved["ay"]))).is_empty() \
		or WalkRules.settle(s, data, _map(s)) == Vector2i(int(moved["ax"]), int(moved["ay"]))).is_true()
	# a window on the other side's wall: that wall stays where it is until it is taken away
	var map := _map(s)
	var other := Vector2i(int(map["w"]) / 2, 0)
	BuildRules.build(s, data, "window", other)
	assert_str(BuildRules.build_why(s, data, BuildRules.GROW, other + Vector2i.UP)).is_equal("BUILD_GROW_BUILT")
	BuildRules.remove(s, data, other)
	assert_str(BuildRules.build_why(s, data, BuildRules.GROW, other + Vector2i.UP)).is_empty()


func test_a_door_goes_into_a_doorway_between_two_walls() -> void:
	var s := _home()
	var map := _map(s)
	var x := -1
	var gap := Vector2i(-1, -1)
	for cx: int in range(2, int(map["w"]) - 2):
		var free := true
		for y: int in range(1, int(map["h"]) - 1):
			free = free and _char(s, Vector2i(cx, y)) == "."
		for y: int in range(2, int(map["h"]) - 2):
			if gap.x < 0 and free and _char(s, Vector2i(cx - 1, y)) == "." and _char(s, Vector2i(cx + 1, y)) == ".":
				gap = Vector2i(cx, y)
		if free and gap.x >= 0:
			x = cx
			break
	assert_int(x).is_greater_equal(0)
	assert_str(BuildRules.build_why(s, data, "door", gap)).is_equal("BUILD_ON_WALL")  # no walls beside it yet
	for y: int in range(1, int(map["h"]) - 1):
		if y != gap.y:
			assert_str(BuildRules.build_why(s, data, "wall", Vector2i(x, y))).is_empty()
			BuildRules.build(s, data, "wall", Vector2i(x, y))
	assert_str(BuildRules.build_why(s, data, "door", gap)).is_empty()
	BuildRules.build(s, data, "door", gap)
	assert_str(_char(s, gap)).is_equal("+")
	BuildRules.remove(s, data, gap)
	assert_str(_char(s, gap)).is_equal(".")


func test_a_room_built_on_behind_an_outer_wall_lies_on_the_same_map() -> void:
	var s := _home()
	var map := _map(s)
	var at := Vector2i(int(map["w"]) / 2, 0)
	assert_str(BuildRules.passage_kind(s, data, map, "brod-river-house", at)).is_equal("room")
	assert_int(BuildRules.price(s, data, BuildRules.PASSAGE, at)).is_equal(1200)
	assert_str(BuildRules.build_why(s, data, BuildRules.PASSAGE, at, "Кладовая")).is_empty()
	BuildRules.build(s, data, BuildRules.PASSAGE, at, "Кладовая")
	var store := _named("Кладовая")
	assert_str(store).is_not_empty()
	assert_str(PropertyRules.at(s, data, store)).is_equal("river_house")
	map = _map(s)
	assert_array(map["ids"]).contains([store])
	assert_int((map["doors"] as Array).size()).is_greater_equal(1)
	var inside := Vector2i(-1, -1)
	for y: int in int(map["h"]):
		for x: int in int(map["w"]):
			if inside.x < 0 and WalkRules.room_of(map, Vector2i(x, y)) == store and str(map["rows"][y])[x] == ".":
				inside = Vector2i(x, y)
	assert_int(inside.x).is_greater_equal(0)
	assert_array(WalkRules.path(map, data["layouts"], WalkRules.settle(s, data, map), inside)).is_not_empty()
	s.room_id = store
	assert_str(BuildRules.place_of(s, data)).is_equal("river_house")
	# the wall with its door no longer moves
	s.room_id = "brod-river-house"
	var door: Dictionary = map["doors"][0]
	var d := Vector2i(int(door["x"]), int(door["y"]))
	assert_str(BuildRules.build_why(s, data, BuildRules.GROW, d)).is_not_empty()


func test_a_building_on_free_ground_of_the_yard_is_a_box_like_the_packs() -> void:
	var s := _home("brod-river-yard")
	var map := _map(s)
	var at := Vector2i(-1, -1)
	for y: int in range(5, int(map["h"]) - 5):
		for x: int in range(5, int(map["w"]) - 5):
			if at.x < 0 and BuildRules.build_why(s, data, BuildRules.PASSAGE, Vector2i(x, y), "Сарай").is_empty():
				at = Vector2i(x, y)
	assert_int(at.x).is_greater_equal(0)
	assert_int(BuildRules.price(s, data, BuildRules.PASSAGE, at)).is_equal(3000)
	BuildRules.build(s, data, BuildRules.PASSAGE, at, "Сарай")
	var shed := _named("Сарай")
	var way := _way(s, shed)
	assert_array(way["box"]).has_size(4)
	assert_str(_char(s, at)).is_equal("+")
	var box: Array = way["box"]
	var corner := LayoutGen.off_grid(_map(s), Vector2i(int(box[0]), int(box[1])))
	for dy: int in int(box[3]):
		for dx: int in int(box[2]):
			var sq := corner + Vector2i(dx, dy)
			if sq != at:  # its walls round the edge and its roof inside, as a building of the pack (LayoutGen._wall_box)
				var edge := dx == 0 or dy == 0 or dx == int(box[2]) - 1 or dy == int(box[3]) - 1
				assert_str(_char(s, sq)).is_equal(LayoutGen.WALL if edge else LayoutGen.ROOF)
	s.room_id = shed
	var inner := _map(s)  # inside — the box's own size, its door on the side it was put
	assert_int(int(inner["w"]) * int(inner["h"])).is_equal(int(box[2]) * int(box[3]))
	assert_array(inner["exits"]).has_size(1)


func test_the_yard_grows_past_its_edge_and_its_ways_stay_on_the_ground() -> void:
	var s := _home("brod-river-yard")
	var map := _map(s)
	var w := int(map["w"])
	var house := _way(s, "brod-river-house")
	var ground := LayoutGen.on_grid(map, Vector2i(int(house["x"]), int(house["y"])))
	var plot := Vector2i(-1, int(map["h"]) / 3)  # a passage past the west edge stands on the edge
	assert_str(BuildRules.build_why(s, data, BuildRules.PASSAGE, plot, "Огород")).is_empty()
	BuildRules.build(s, data, BuildRules.PASSAGE, plot, "Огород")
	var garden := _named("Огород")
	assert_int(int(_way(s, garden)["x"])).is_equal(0)
	var wall := Vector2i(5, 5)
	while not BuildRules.build_why(s, data, "wall", wall).is_empty():
		wall += Vector2i(1, 1)
	BuildRules.build(s, data, "wall", wall)
	var wall_ground := LayoutGen.on_grid(_map(s), wall)
	assert_int(BuildRules.price(s, data, BuildRules.GROW, Vector2i(-3, 10))).is_equal(3 * int(map["h"]) * 2)
	BuildRules.build(s, data, BuildRules.GROW, Vector2i(-3, 10))
	BuildRules.build(s, data, BuildRules.GROW, Vector2i(w + 3 + 2, 10))  # the map is three wider now: its east edge at w + 2
	map = _map(s)
	assert_int(int(map["w"])).is_equal(w + 6)
	var now := _way(s, "brod-river-house")
	assert_that(LayoutGen.on_grid(map, Vector2i(int(now["x"]), int(now["y"])))).is_equal(ground)
	assert_str(_char(s, Vector2i(int(now["x"]), int(now["y"])))).is_equal("+")
	assert_int(int(_way(s, garden)["x"])).is_equal(0)  # the plot's way went with the edge
	assert_str(_char(s, LayoutGen.off_grid(map, wall_ground))).is_equal("#")  # the hands' wall stands where it stood
	var max_open: Array = BuildRules.cfg(data)["grow"]["max_open"]
	assert_str(BuildRules.build_why(s, data, BuildRules.GROW, Vector2i(int(max_open[0]) + 5, 10))).is_equal("BUILD_GROW_MAX")


func test_the_hands_parts_go_into_one_line() -> void:
	var s := _home()
	var tally := {}
	var map := _map(s)
	var done := 0
	for y: int in range(1, int(map["h"]) - 1):
		for x: int in range(1, int(map["w"]) - 1):
			if done < 3 and BuildRules.build_why(s, data, "wall", Vector2i(x, y)).is_empty():
				assert_array(BuildRules.build(s, data, "wall", Vector2i(x, y), "", Being.HERO, tally)).is_empty()
				done += 1
	var lines := BuildRules.summary(tally)
	assert_array(lines).has_size(1)
	assert_str(lines[0]).contains("стена ×3")
