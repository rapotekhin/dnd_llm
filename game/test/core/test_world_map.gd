extends GdUnitTestSuite
## The map 2.0 (roadmap v0.7.6): what the hero knows (visited rooms, «?» behind open exits), the fast travel route
## through visited rooms only, its minutes, the quest marks, the layout of the scheme.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _session(visited: Array) -> GameSession:
	var s := TestUtils.new_session()
	s.visited.clear()
	for r: String in visited:
		s.visited.append(r)
	s.room_id = str(visited[0])
	return s


func test_known_rooms_and_the_unknown_behind_open_exits() -> void:
	var s := _session(["brod-tavern-hall", "brod-square"])
	var k := WorldMap.known(s, data["world"])
	assert_array(k["rooms"]).contains_exactly(["brod-tavern-hall", "brod-square"])
	assert_array(k["frontier"]).contains_exactly_in_any_order(["brod-tavern-kitchen", "brod-tavern-upstairs", "brod-smithy",
		"brod-herbalist", "brod-temple", "brod-gate", "brod-townhall", "brod-river-yard"])
	assert_int((k["edges"] as Array).size()).is_equal(9)  # hall–square once, 2 from the hall, 6 from the square


func test_a_shut_way_is_not_on_the_map() -> void:
	var s := _session(["pushcha-hollow"])
	var k := WorldMap.known(s, data["world"])
	assert_array(k["frontier"]).not_contains(["pushcha-burrow"])


func test_the_route_goes_through_visited_rooms_only() -> void:
	var s := _session(["brod-tavern-hall", "brod-square", "brod-gate", "pushcha-edge"])
	assert_array(WorldMap.route(s, data["world"], "brod-tavern-hall", "pushcha-edge")).contains_exactly(["brod-square", "brod-gate", "pushcha-edge"])
	assert_array(WorldMap.route(s, data["world"], "brod-tavern-hall", "brod-smithy")).is_empty()  # never been there
	assert_array(WorldMap.route(s, data["world"], "brod-tavern-hall", "brod-tavern-hall")).is_empty()
	var far := _session(["brod-tavern-hall", "brod-square", "pushcha-edge"])  # the gate is unknown — no way round it
	assert_array(WorldMap.route(far, data["world"], "brod-tavern-hall", "pushcha-edge")).is_empty()


func test_a_found_trap_blocks_the_route_until_it_is_gone() -> void:
	var s := _session(["mine-entrance", "mine-gallery", "mine-deep"])
	assert_array(WorldMap.route(s, data["world"], "mine-entrance", "mine-deep")).contains_exactly(["mine-gallery", "mine-deep"])
	var trap := ExplorationRules.trap_on_exit(s, data["world"], "mine-gallery", "mine-deep")
	s.revealed["mine-gallery"] = [str(trap["id"])]
	assert_bool(WorldMap.blocked(s, data["world"], "mine-gallery", "mine-deep")).is_true()
	assert_array(WorldMap.route(s, data["world"], "mine-entrance", "mine-deep")).is_empty()
	ExplorationRules.disarm_trap(s, "mine-gallery", trap)
	assert_array(WorldMap.route(s, data["world"], "mine-entrance", "mine-deep")).contains_exactly(["mine-gallery", "mine-deep"])


func test_route_minutes_by_the_time_rules() -> void:
	var path: Array[String] = ["brod-square", "brod-gate", "pushcha-edge"]
	assert_int(WorldMap.minutes(data, "brod-tavern-hall", path)).is_equal(10 + 10 + 60)


func test_a_quest_mark_only_on_a_seen_place() -> void:
	var s := _session(["brod-tavern-hall", "brod-square", "brod-gate", "mine-entrance", "mine-gallery"])
	s.quests_active["drogin_amulet"] = 0  # find the amulet in the flooded gallery
	assert_dict(WorldMap.quest_marks(s, data["world"])).is_empty()
	s.visited.append("mine-flooded")
	var marks := WorldMap.quest_marks(s, data["world"])
	assert_array(marks.keys()).contains_exactly(["mine-flooded"])
	s.quests_active["drogin_amulet"] = 1  # bring it to the prospector
	marks = WorldMap.quest_marks(s, data["world"])
	assert_array(marks.keys()).not_contains(["mine-flooded"])


func test_the_layout_is_stable_and_fits() -> void:
	var a := WorldMap.layout(data["world"])
	var b := WorldMap.layout(data["world"])
	assert_int(a.size()).is_equal((data["world"]["rooms"] as Dictionary).size())
	var spots := {}
	for r: String in a:
		var p: Vector2 = a[r]
		assert_bool(p.x >= 0.0 and p.x <= 1.0 and p.y >= 0.0 and p.y <= 1.0).is_true()
		assert_that(b[r]).is_equal(p)
		spots["%d,%d" % [roundi(p.x * 100), roundi(p.y * 100)]] = r
	assert_int(spots.size()).is_equal(a.size())  # no two rooms on one spot
