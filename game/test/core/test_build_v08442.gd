extends GdUnitTestSuite
## The build screen's rules (v0.8.4.42, BuildRules): the catalog with its groups and search, walls, windows and doors on
## the squares of the generator, things that work by their rules (a bed, a chest, a station), the master's chest of 50
## pounds, passages into new rooms of their own name — stairs in a house, a plot at the edge of the yard, a building on
## free ground — and what is taken back.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _home(room: String = "brod-river-house") -> GameSession:
	var s := TestUtils.new_session()
	s.settings["needs"] = false
	s.room_id = "brod-townhall"
	s.minute = 12 * 60
	s.character["gold_cp"] = 100000
	PropertyRules.buy(s, data, "river_house")
	s.room_id = room
	return s


func _map(s: GameSession) -> Dictionary:
	return LayoutRules.map_of(s, data, s.room_id)


## The first square of the map `id` may be built on now.
func _spot(s: GameSession, id: String, name: String = "", skip: Array[Vector2i] = [], margin: int = 0) -> Vector2i:
	var map := _map(s)
	for y: int in range(margin, int(map["h"]) - margin):
		for x: int in range(margin, int(map["w"]) - margin):
			var at := Vector2i(x, y)
			if not skip.has(at) and BuildRules.build_why(s, data, id, at, name).is_empty():
				return at
	return Vector2i(-1, -1)


func _char(s: GameSession, at: Vector2i) -> String:
	return str(_map(s)["rows"][at.y])[at.x]


func test_the_catalog_has_parts_things_and_a_passage_by_groups() -> void:
	var s := _home()
	var rows := BuildRules.catalog(s, data, "river_house")
	var ids := rows.map(func(r: Dictionary) -> String: return str(r["id"]))
	assert_array(ids).contains(["wall", "window", "door", "bed", "chest", "hearth", "forge", BuildRules.PASSAGE])
	assert_array(ids).not_contains(["sign", "lock", "porch"])  # no square for an income or a lock
	var craft := BuildRules.view(rows, "", "craft").map(func(r: Dictionary) -> String: return str(r["id"]))
	assert_array(craft).contains(["hearth", "workbench", "forge", "alchemy"])
	assert_array(craft).not_contains(["bed"])
	assert_array(BuildRules.view(rows, "", "rest").map(func(r: Dictionary) -> String: return str(r["id"]))).contains_exactly(["bed"])
	assert_array(BuildRules.view(rows, "сундук", "").map(func(r: Dictionary) -> String: return str(r["id"]))).contains_exactly(["chest"])
	assert_str(BuildRules.build_why(s, data, "wall", Vector2i(1, 1))).is_not_equal("BUILD_NOT_HOME")
	s.room_id = "brod-square"
	assert_str(BuildRules.where_why(s, data)).is_equal("BUILD_NOT_HOME")


func test_a_wall_a_window_and_a_door_on_the_squares() -> void:
	var s := _home()
	var gold := int(s.character["gold_cp"])
	var at := _spot(s, "wall")
	assert_int(at.x).is_greater_equal(0)
	BuildRules.build(s, data, "wall", at)
	assert_str(_char(s, at)).is_equal("#")
	assert_int(int(s.character["gold_cp"])).is_equal(gold - 10)
	assert_str(BuildRules.build_why(s, data, "wall", at)).is_equal("BUILD_SAME")
	assert_str(BuildRules.build_why(s, data, "window", at)).is_empty()
	BuildRules.build(s, data, "window", at)
	assert_str(_char(s, at)).is_equal("w")
	assert_bool(WalkRules.passable(_map(s), data["layouts"], at)).is_false()
	assert_bool(SightRules.opaque(data["layouts"], "w")).is_false()  # seen through, not walked through
	var hero := WalkRules.settle(s, data, _map(s))
	assert_str(BuildRules.build_why(s, data, "wall", hero)).is_equal("BUILD_TAKEN")
	var w := WorldGen.merged(TestUtils.data()["world"], s.generated)  # a loaded game keeps the hands' work
	assert_dict(w["rooms"]["brod-river-house"]["build"]["cells"]).is_not_empty()
	assert_str(BuildRules.remove_why(s, data, at)).is_empty()
	BuildRules.remove(s, data, at)
	assert_str(_char(s, at)).is_equal(".")
	assert_str(BuildRules.remove_why(s, data, at)).is_equal("BUILD_NOTHING")


func test_a_door_joins_floor_to_floor() -> void:
	var s := _home()
	var map := _map(s)
	var outer := Vector2i(-1, -1)  # a wall of the house with nothing beyond it
	for x: int in int(map["w"]):
		if str(map["rows"][0])[x] == "#":
			outer = Vector2i(x, 0)
			break
	assert_str(BuildRules.build_why(s, data, "door", outer)).is_equal("BUILD_DOOR_NOWHERE")
	assert_str(BuildRules.build_why(s, data, "door", _spot(s, "wall"))).is_equal("BUILD_ON_WALL")


func test_a_wall_never_cuts_a_way() -> void:
	var map := {"w": 5, "h": 3, "rows": ["#####", "#...#", "#####"] as Array[String], "exits": [{"x": 1, "y": 1, "ax": 1, "ay": 1}],
		"doors": [{"x": 3, "y": 1}], "marks": []}
	var anchors: Array[Vector2i] = [Vector2i(1, 1), Vector2i(3, 1)]
	assert_bool(BuildRules._sound(data, map, anchors, Vector2i(2, 1), "#")).is_false()
	assert_bool(BuildRules._sound(data, map, anchors, Vector2i(2, 1), "+")).is_true()


func test_a_bed_on_its_square_rests_the_hero_and_comes_off() -> void:
	var s := _home()
	assert_str(ExplorationRules.can_rest(s, data["world"], data)).is_equal("REST_NOT_SAFE")
	var at := _spot(s, "bed")
	var lines := BuildRules.build(s, data, "bed", at)
	assert_str(" ".join(lines)).contains("Кровать")
	assert_bool(PropertyRules.has_upgrade(s.character, "river_house", "bed")).is_true()
	assert_str(ExplorationRules.can_rest(s, data["world"], data)).is_empty()
	var marks: Array = _map(s)["marks"]
	assert_bool(marks.any(func(m: Dictionary) -> bool: return str(m["name"]) == "bed" and int(m["x"]) == at.x and int(m["y"]) == at.y)).is_true()
	var spots := MapSpots.of(s, data, _map(s))
	assert_bool(spots.any(func(t: Dictionary) -> bool: return str(t["ref"]) == "station:bed" and int(t["x"]) == at.x and int(t["y"]) == at.y)).is_true()
	assert_str(BuildRules.build_why(s, data, "bed", _spot(s, "bed"))).is_empty()  # a second bed is fine
	var gold := int(s.character["gold_cp"])
	BuildRules.remove(s, data, at)
	assert_int(int(s.character["gold_cp"])).is_equal(gold + 150)
	assert_bool(PropertyRules.has_upgrade(s.character, "river_house", "bed")).is_false()
	assert_str(ExplorationRules.can_rest(s, data["world"], data)).is_equal("REST_NOT_SAFE")


func test_a_station_crafts_and_a_chest_stores_on_its_square() -> void:
	var s := _home()
	assert_bool(CraftRules.station_here(s, data, "workbench")).is_false()
	var bench := _spot(s, "workbench")
	BuildRules.build(s, data, "workbench", bench)
	assert_bool(CraftRules.station_here(s, data, "workbench")).is_true()
	var chest_at := _spot(s, "chest")
	BuildRules.build(s, data, "chest", chest_at)
	var chests := (s.props.get(s.room_id, []) as Array).filter(func(p: Dictionary) -> bool: return ContainerRules.is_container(p))
	assert_int(chests.size()).is_equal(1)
	var spots := MapSpots.of(s, data, _map(s))
	assert_bool(spots.any(func(t: Dictionary) -> bool:
		return str(t["ref"]) == "prop:" + str(chests[0]["id"]) and int(t["x"]) == chest_at.x and int(t["y"]) == chest_at.y)).is_true()
	chests[0]["contents"] = {"rope_hempen": 1}
	assert_str(BuildRules.remove_why(s, data, chest_at)).is_equal("BUILD_CHEST_FULL")
	chests[0]["contents"] = {}
	BuildRules.remove(s, data, chest_at)
	assert_bool((s.props.get(s.room_id, []) as Array).any(func(p: Dictionary) -> bool: return ContainerRules.is_container(p))).is_false()
	BuildRules.remove(s, data, bench)
	assert_bool(CraftRules.station_here(s, data, "workbench")).is_false()


func test_the_masters_chest_of_fifty_pounds_stands_by_hand() -> void:
	var s := _home()
	var plan := PropertyRules.plan_asked(s, data, {"name": "Сундук на 50 фунтов", "gives": {"storage": true, "capacity_lb": 50}})
	assert_bool(plan.has("reason")).override_failure_message(str(plan.get("reason", ""))).is_false()
	assert_int(int(plan["def"]["price_cp"])).is_equal(250)  # 200 for storage, a copper a pound
	assert_str(" ".join(PropertyRules.apply_asked(s, data, plan))).contains("Обустройство")
	var id := str(plan["id"])
	assert_array(BuildRules.view(BuildRules.catalog(s, data, "river_house"), "", "storage").map(func(r: Dictionary) -> String: return str(r["id"]))).contains([id])
	BuildRules.build(s, data, id, _spot(s, id))
	var chest: Dictionary = (s.props[s.room_id] as Array).filter(func(p: Dictionary) -> bool: return ContainerRules.is_container(p))[0]
	assert_int(int(chest["capacity_lb"])).is_equal(50)
	assert_bool(PropertyRules.plan_asked(s, data, {"name": "Сундук-гигант", "gives": {"capacity_lb": 50}}).has("reason")).is_true()


func test_stairs_into_a_new_room_of_its_own_name() -> void:
	var s := _home()
	var at := _spot(s, BuildRules.PASSAGE, "Мансарда", [], 1)  # on the floor: an outer wall builds a room on behind it (v0.8.4.42.7)
	assert_str(BuildRules.build_why(s, data, BuildRules.PASSAGE, at, "")).is_equal("BUILD_NAME")
	assert_int(BuildRules.price(s, data, BuildRules.PASSAGE, at)).is_equal(1500)
	BuildRules.build(s, data, BuildRules.PASSAGE, at, "Мансарда")
	var w := WorldView.new(data["world"])
	var made := ""
	for to: String in w.exits("brod-river-house"):
		if str(w.room(to).get("name", "")) == "Мансарда":
			made = to
	assert_str(made).is_not_empty()
	assert_bool(bool(w.room(made).get("indoor", false))).is_true()
	assert_int(int(LayoutRules.fields(w.room(made))["floor"])).is_equal(1)
	assert_str(PropertyRules.at(s, data, made)).is_equal("river_house")
	var map := _map(s)
	var way: Array = (map["exits"] as Array).filter(func(e: Dictionary) -> bool: return str(e["to"]) == made)
	assert_int(way.size()).is_equal(1)
	assert_str(str(way[0]["kind"])).is_equal("stairs")
	assert_int(int(way[0]["x"])).is_equal(at.x)
	assert_int(int(way[0]["y"])).is_equal(at.y)
	s.room_id = made
	var up := _map(s)
	assert_bool((up["exits"] as Array).any(func(e: Dictionary) -> bool: return str(e["to"]) == "brod-river-house" and str(e["kind"]) == "stairs")).is_true()
	assert_str(BuildRules.place_of(s, data)).is_equal("river_house")  # furnished the same way
	assert_str(BuildRules.remove_why(s, data, at)).is_not_empty()


func test_a_plot_at_the_edge_and_a_building_on_free_ground() -> void:
	var s := _home("brod-river-yard")
	var map := _map(s)
	var edge := Vector2i(-1, -1)
	for x: int in range(3, int(map["w"]) - 3):
		var at := Vector2i(x, int(map["h"]) - 1)
		if BuildRules.build_why(s, data, BuildRules.PASSAGE, at, "Огород").is_empty():
			edge = at
			break
	assert_int(edge.x).is_greater_equal(0)
	assert_int(BuildRules.price(s, data, BuildRules.PASSAGE, edge)).is_equal(1000)
	BuildRules.build(s, data, BuildRules.PASSAGE, edge, "Огород")
	var garden: Array = (_map(s)["exits"] as Array).filter(func(e: Dictionary) -> bool: return str(WorldView.new(data["world"]).room(str(e["to"])).get("name", "")) == "Огород")
	assert_int(garden.size()).is_equal(1)
	assert_str(str(garden[0]["kind"])).is_equal("edge")
	assert_int(int(garden[0]["x"])).is_equal(edge.x)
	assert_bool(LayoutRules.is_open(s, data, str(garden[0]["to"]))).is_true()
	var inner := _spot(s, BuildRules.PASSAGE, "Сарай", [], 4)  # v0.8.4.42.7: a building on free ground, a box like the pack's
	assert_int(inner.x).is_greater_equal(0)
	BuildRules.build(s, data, BuildRules.PASSAGE, inner, "Сарай")
	var shed: Array = (_map(s)["exits"] as Array).filter(func(e: Dictionary) -> bool: return str(WorldView.new(data["world"]).room(str(e["to"])).get("name", "")) == "Сарай")
	assert_int(shed.size()).is_equal(1)
	assert_str(str(shed[0]["kind"])).is_equal("door")
	assert_str(_char(s, inner)).is_equal("+")
	assert_bool(bool(WorldView.new(data["world"]).room(str(shed[0]["to"])).get("indoor", false))).is_true()
	assert_str(BuildRules.remove_why(s, data, inner)).is_equal("BUILD_NOTHING")
	var w := WorldGen.merged(TestUtils.data()["world"], s.generated)  # a loaded game keeps the new rooms and their ways
	assert_array(w["rooms"]["brod-river-yard"]["exits"]).contains([str(shed[0]["to"]), str(garden[0]["to"])])
