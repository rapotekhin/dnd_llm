extends GdUnitTestSuite
## One way (v0.7.66): any way between two places is a row over its kind — a door, a crawl, a ford, a road, a breach; who
## passes, what it costs, what goes through it, a latch from one side, a fall; the master's `way`. The tree of places: a
## node's values go down to its rooms.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data().duplicate()
	data["world"] = (data["world"] as Dictionary).duplicate(true)


func _hero(room: String) -> GameSession:
	var s := TestUtils.new_session()
	for p: Dictionary in data["presets"]:
		if p["id"] == "fighter_aira":
			s.character = GameSession.normalized_character(CharacterBuilder.build_preset(p, data))
	CharacterRules.refresh(s.character, data, s.items)
	s.room_id = room
	s.minute = 12 * 60
	return s


func _way(a: String, b: String, row: Dictionary) -> void:
	var room: Dictionary = data["world"]["rooms"][a]
	if not (room["exits"] as Array).has(b):
		(room["exits"] as Array).append(b)
	var own: Dictionary = room.get("ways", {})
	own[b] = row
	room["ways"] = own


func _hows(s: GameSession, a: String, b: String) -> Array:
	return WayRules.ways(s, data, a, b).map(func(w: Dictionary) -> String: return str(w["how"]))


func test_an_exit_without_a_row_is_plain_or_a_road() -> void:
	assert_str(str(WayRules.row(data, "brod-tavern-hall", "brod-tavern-kitchen")["kind"])).is_equal("plain")
	var w := WorldView.new(data["world"])
	for r: String in data["world"]["rooms"]:
		for e: String in w.exits(r):
			if w.location_id(r) != w.location_id(e):
				assert_str(str(WayRules.row(data, r, e)["kind"])).is_equal("road")
				return


func test_the_pack_says_a_crawl_and_a_ford() -> void:
	assert_str(str(WayRules.row(data, "pushcha-hollow", "pushcha-burrow")["kind"])).is_equal("crawl")
	assert_str(str(WayRules.row(data, "pushcha-trail", "pushcha-glade")["kind"])).is_equal("ford")
	assert_str(WayRules.describe(_hero("pushcha-hollow"), data, "pushcha-hollow", "pushcha-burrow")).contains("лаз")


func test_when_shuts_only_its_own_side() -> void:
	var s := _hero("pushcha-hollow")
	assert_array(WayRules.open_exits(s, data["world"], "pushcha-hollow")).not_contains(["pushcha-burrow"])
	assert_array(WayRules.closed_texts(s, data["world"], "pushcha-hollow")).has_size(1)
	assert_array(WayRules.open_exits(s, data["world"], "pushcha-burrow")).contains(["pushcha-hollow"])  # out is free


func test_a_crawl_takes_time_and_lets_no_big_body_through() -> void:
	var move := int(data["rules"]["time"]["move_minutes"])
	assert_int(WayRules.minutes(data, "pushcha-hollow", "pushcha-burrow")).is_equal(move + 5)
	var s := _hero("pushcha-hollow")
	assert_str(WayRules.blocked(s, data, "pushcha-hollow", "pushcha-burrow")).is_empty()
	_way("brod-square", "brod-tavern-hall", {"kind": "crawl", "max_size": "tiny"})
	assert_str(WayRules.blocked(_hero("brod-square"), data, "brod-square", "brod-tavern-hall")).is_equal("DOOR_TOO_SMALL")


func test_a_beast_waits_before_a_crawl_but_wades_a_ford() -> void:
	assert_str(WayRules.beast_why(data, "pushcha-hollow", "pushcha-burrow", "mule")).contains("лаз")
	assert_str(WayRules.beast_why(data, "pushcha-trail", "pushcha-glade", "mule")).is_empty()


func test_a_road_of_its_own_hours_counts_on_the_map() -> void:
	_way("brod-square", "brod-tavern-hall", {"kind": "bridge", "minutes": 90})
	assert_int(WayRules.minutes(data, "brod-square", "brod-tavern-hall")).is_equal(90)
	var path: Array[String] = ["brod-tavern-hall"]
	assert_int(WorldMap.minutes(data, "brod-square", path)).is_equal(90)


func test_what_goes_through_a_shut_leaf() -> void:
	var s := _hero("brod-square")
	_way("brod-square", "brod-tavern-hall", {"kind": "grate"})
	_way("brod-tavern-hall", "brod-tavern-kitchen", {"kind": "door"})
	assert_bool(WayRules.passes(s, data, "brod-square", "brod-tavern-hall", "shot")).is_true()
	assert_bool(WayRules.passes(s, data, "brod-tavern-hall", "brod-tavern-kitchen", "sight")).is_false()
	WayRules.break_down(s, "brod-tavern-hall", "brod-tavern-kitchen")
	assert_bool(WayRules.passes(s, data, "brod-tavern-hall", "brod-tavern-kitchen", "sight")).is_true()
	assert_bool(WayRules.passes(s, data, "brod-tavern-hall", "brod-tavern-upstairs", "sound")).is_true()  # nothing shuts it


func test_a_latch_opens_from_one_side_only() -> void:
	_way("brod-tavern-hall", "brod-tavern-kitchen", {"kind": "hatch", "locked": true, "latch": "brod-tavern-hall"})
	var s := _hero("brod-tavern-hall")
	assert_array(_hows(s, "brod-tavern-hall", "brod-tavern-kitchen")).contains(["latch"])
	assert_array(_hows(s, "brod-tavern-kitchen", "brod-tavern-hall")).not_contains(["latch"])
	WayRules.unlock(s, data, "brod-tavern-hall", "brod-tavern-kitchen")
	assert_str(WayRules.blocked(s, data, "brod-tavern-kitchen", "brod-tavern-hall")).is_empty()


func test_a_breach_has_no_lock_and_only_breaks() -> void:
	_way("brod-tavern-hall", "brod-tavern-kitchen", {"kind": "breach", "material": "wood"})
	var s := _hero("brod-tavern-hall")
	s.character["inventory"]["thieves_tools"] = 1
	assert_str(WayRules.blocked(s, data, "brod-tavern-hall", "brod-tavern-kitchen")).is_equal("DOOR_SOLID")
	var hows := _hows(s, "brod-tavern-hall", "brod-tavern-kitchen")
	assert_array(hows).contains(["force"])
	assert_array(hows).not_contains(["pick", "key", "latch"])
	WayRules.break_down(s, "brod-tavern-hall", "brod-tavern-kitchen")
	assert_str(WayRules.blocked(s, data, "brod-tavern-hall", "brod-tavern-kitchen")).is_empty()
	assert_str(WayRules.break_line(data, "brod-tavern-hall", "brod-tavern-kitchen")).contains("проломлена")


func test_a_way_down_is_a_fall_unless_the_hero_flies() -> void:
	_way("brod-square", "brod-tavern-hall", {"kind": "plain", "drop": 30})
	var s := _hero("brod-square")
	var hp := int(s.character["hp"])
	assert_str("\n".join(WayRules.on_pass(s, data, "brod-square", "brod-tavern-hall"))).contains("Падение")
	assert_int(int(s.character["hp"])).is_less(hp)


func test_the_master_lays_a_way_and_it_stays_in_the_save() -> void:
	var s := _hero("brod-square")
	var plan := WayRules.plan_make(s, data, {"to_room": "brod-tavern-kitchen", "way_kind": "crawl", "text": "щель за бочками"})
	assert_bool(plan.has("plan")).override_failure_message(str(plan)).is_true()
	WayRules.apply_make(s, data, plan["plan"])
	assert_array(WayRules.open_exits(s, data["world"], "brod-square")).contains(["brod-tavern-kitchen"])
	assert_array(WayRules.open_exits(s, data["world"], "brod-tavern-kitchen")).contains(["brod-square"])
	assert_str(str(WayRules.row(data, "brod-square", "brod-tavern-kitchen")["kind"])).is_equal("crawl")
	var fresh := TestUtils.data().duplicate()
	fresh["world"] = (fresh["world"] as Dictionary).duplicate(true)
	WorldGen.lay_ways(fresh["world"], WorldGen.generated(s))
	assert_array(fresh["world"]["rooms"]["brod-square"]["exits"]).contains(["brod-tavern-kitchen"])
	assert_str(str(WayRules.row(fresh, "brod-square", "brod-tavern-kitchen")["kind"])).is_equal("crawl")


func test_a_one_way_stands_in_one_list() -> void:
	var s := _hero("brod-square")
	var plan := WayRules.plan_make(s, data, {"to_room": "brod-tavern-kitchen", "way_kind": "secret", "one_way": true})
	WayRules.apply_make(s, data, plan["plan"])
	assert_array(WayRules.open_exits(s, data["world"], "brod-tavern-kitchen")).not_contains(["brod-square"])


func test_the_master_cannot_open_what_the_world_shuts() -> void:
	var s := _hero("pushcha-hollow")
	assert_str(str(WayRules.plan_make(s, data, {"to_room": "pushcha-hollow", "way_kind": "crawl"}).get("reason", ""))).is_not_empty()
	s.room_id = "pushcha-trail"
	assert_str(str(WayRules.plan_make(s, data, {"to_room": "pushcha-burrow", "way_kind": "crawl"}).get("reason", ""))).contains("открывает мир")
	s.room_id = "brod-square"
	assert_str(str(WayRules.plan_make(s, data, {"to_room": "pushcha-hollow", "way_kind": "crawl"}).get("reason", ""))).contains("локации")
	assert_str(str(WayRules.plan_make(s, data, {"to_room": "brod-tavern-kitchen", "way_kind": "road"}).get("reason", ""))).contains("way_kind")


func test_the_pack_checks_a_way() -> void:
	var c := WorldPack.load_bundle("res://data/worlds/frontier", "builtin")
	c["world"]["rooms"]["pushcha-hollow"]["ways"]["pushcha-burrow"]["kind"] = "wormhole"
	assert_str("\n".join(WorldPack.validate(c, TestUtils.base()))).contains("wormhole")


func test_a_node_gives_its_rooms_what_they_do_not_say() -> void:
	var w := WorldView.new(data["world"])
	var loc := w.location_id("brod-tavern-upstairs")
	var sid := w.site_id("brod-tavern-upstairs")
	assert_bool(w.flag("brod-tavern-upstairs", "dark")).is_false()
	data["world"]["sites"][sid]["dark"] = true
	assert_bool(w.flag("brod-tavern-upstairs", "dark")).is_true()
	data["world"]["rooms"]["brod-tavern-upstairs"]["dark"] = false
	assert_bool(w.flag("brod-tavern-upstairs", "dark")).is_false()  # the nearest wins
	assert_str(str(w.inherit("brod-tavern-hall", "terrain", ""))).is_equal(str(w.location(loc).get("terrain", "")))
	assert_bool(w.is_public("brod-tavern-hall")).is_equal(true)


func test_a_site_under_a_site_and_a_region_above_a_location() -> void:
	var w := WorldView.new(data["world"])
	var sid := w.site_id("brod-tavern-cellar")
	data["world"]["sites"]["brod-block"] = {"name": "Квартал", "location_id": w.location_id("brod-tavern-cellar"), "public": false}
	data["world"]["sites"][sid]["parent"] = "brod-block"
	data["world"]["rooms"]["brod-tavern-cellar"].erase("public")
	data["world"]["sites"][sid].erase("public")
	assert_bool(w.is_public("brod-tavern-cellar")).is_false()
	var loc := w.location_id("brod-tavern-cellar")
	data["world"]["locations"]["march"] = {"name": "Марка", "description": "", "law": {"name": "закон Марки"}}
	data["world"]["locations"][loc].erase("law")
	data["world"]["locations"][loc]["parent"] = "march"
	assert_str(str(w.location_inherit(loc, "law", {}).get("name", ""))).is_equal("закон Марки")
	data["world"]["sites"]["brod-block"]["parent"] = sid  # a loop ends at the depth limit
	assert_bool(w.chain("brod-tavern-cellar").size() <= 2 * WorldView.TREE_DEPTH + 1).is_true()
	var c := WorldPack.load_bundle("res://data/worlds/frontier", "builtin")
	c["world"]["sites"]["brod-square"]["parent"] = "brod-square"
	assert_str("\n".join(WorldPack.validate(c, TestUtils.base()))).contains("родител")


func test_a_tag_of_the_site_counts_in_its_rooms() -> void:
	var s := _hero("brod-tavern-hall")
	assert_array(SceneRules.tags(s, data["world"], "brod-tavern-hall")).contains(["stage", "tavern"])
