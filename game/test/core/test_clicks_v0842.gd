extends GdUnitTestSuite
## v0.8.4.2: a private door shut to the hero, opened by the owner's leave, a pick for a day, a broken leaf; the square of a
## way; the seed from any text; the slots of a thing; a quest's giver in reach.

const HALL := "brod-tavern-hall"
const KITCHEN := "brod-tavern-kitchen"

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _hero(room: String) -> GameSession:
	var s := TestUtils.new_session()
	s.room_id = room
	s.minute = 12 * 60
	return s


func test_a_private_door_is_shut_one_way() -> void:
	var s := _hero(HALL)
	assert_str(WayRules.blocked(s, data, HALL, KITCHEN)).is_equal("DOOR_PRIVATE")
	assert_str(WayRules.blocked(s, data, KITCHEN, HALL)).is_empty()  # from inside it opens
	assert_str(WayRules.label(s, data, HALL, KITCHEN)).contains("заперто")


func test_the_owners_leave_opens_it() -> void:
	var s := _hero(HALL)
	s.permits["brod-tavern"] = "npc_innkeeper"
	assert_str(WayRules.blocked(s, data, HALL, KITCHEN)).is_empty()


func test_a_quarrel_shuts_it_again() -> void:
	var s := _hero(HALL)
	s.permits["brod-tavern"] = "npc_innkeeper"
	s.shift_attitude("npc_innkeeper", -3, data)
	assert_str(WayRules.blocked(s, data, HALL, KITCHEN)).is_equal("DOOR_PRIVATE")


func test_a_picked_door_stays_open_a_day() -> void:
	var s := _hero(HALL)
	WayRules.unlock(s, data, HALL, KITCHEN)
	assert_str(WayRules.blocked(s, data, HALL, KITCHEN)).is_empty()
	s.day += 2
	assert_str(WayRules.blocked(s, data, HALL, KITCHEN)).is_equal("DOOR_PRIVATE")


func test_a_broken_door_stays_open() -> void:
	var s := _hero(HALL)
	WayRules.break_down(s, HALL, KITCHEN)
	s.day += 5
	assert_str(WayRules.blocked(s, data, HALL, KITCHEN)).is_empty()


func test_the_ways_with_a_private_door() -> void:
	var s := _hero(HALL)
	var hows := WayRules.ways(s, data, HALL, KITCHEN).map(func(w: Dictionary) -> String: return str(w["how"]))
	assert_array(hows).contains(["ask", "force"])


func test_no_knock_when_asked_in_vain_today() -> void:
	var s := _hero(HALL)
	s.permit_asked["npc_innkeeper"] = s.day
	var hows := WayRules.ways(s, data, HALL, KITCHEN).map(func(w: Dictionary) -> String: return str(w["how"]))
	assert_array(hows).not_contains(["ask"])


func test_a_public_way_has_no_door() -> void:
	assert_dict(WayRules.def(data, HALL, "brod-square")).is_empty()


func test_the_square_of_a_way() -> void:
	var s := _hero(HALL)
	var map := LayoutRules.map_of(s, data, HALL)
	var cell := WalkRules.way_cell(map, HALL, KITCHEN)
	assert_int(cell.x).is_greater_equal(0)
	assert_str(WalkRules.way_at(map, HALL, cell)).is_equal(KITCHEN)
	var past := WalkRules.beyond(map, data["layouts"], cell, KITCHEN)
	assert_str(WalkRules.room_of(map, past)).is_equal(KITCHEN)


func test_no_way_on_a_plain_square() -> void:
	var s := _hero(HALL)
	var map := LayoutRules.map_of(s, data, HALL)
	assert_str(WalkRules.way_at(map, HALL, WalkRules.settle(s, data, map))).is_empty()


func test_a_seed_from_any_text() -> void:
	assert_int(GameSession.seed_of("42")).is_equal(42)
	assert_int(GameSession.seed_of(" 7 ")).is_equal(7)
	assert_int(GameSession.seed_of("волк")).is_equal(GameSession.seed_of("волк"))
	assert_int(GameSession.seed_of("волк")).is_not_equal(GameSession.seed_of("Волк"))
	assert_int(GameSession.seed_of("-5")).is_greater_equal(0)


func test_the_slots_of_a_thing() -> void:
	var items: Dictionary = data["items"]
	assert_array(CharacterRules.slots_of(ItemRules.def_of(items, {}, "dagger"), data)).contains_exactly(["main_hand", "off_hand"])
	assert_array(CharacterRules.slots_of(ItemRules.def_of(items, {}, "longsword"), data)).contains_exactly(["main_hand"])
	assert_array(CharacterRules.slots_of(ItemRules.def_of(items, {}, "torch"), data)).is_empty()


func test_a_giver_in_reach_by_the_map() -> void:
	var s := _hero(HALL)
	var map := LayoutRules.map_of(s, data, HALL)
	var at := MapSpots.cell_of(s, data, map, "npc_innkeeper")
	var near := WalkRules.around(map, data["layouts"], at, 1)[0]
	WalkRules.stand(s, map, HALL, near)
	assert_bool(MapSpots.in_reach(s, data, "npc_innkeeper", "talk")).is_true()


func test_wait_of_any_minutes_is_capped_in_the_rules() -> void:
	assert_int(int(TimeRules.cfg(data)["wait_max_minutes"])).is_equal(1440)
