extends GdUnitTestSuite
## Objects (v0.7.39.5, the author: «лавка — это объект, всё унифицировано»): staff places by roles, any number of
## hands, a house's counter and a market stall as objects of their own, the pack's objects with their people and the
## hero's job among them, the master's object in create_place, the save of one worker, one's own bed.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _owner(room: String = "brod-townhall") -> GameSession:
	var s := TestUtils.new_session()
	s.settings["needs"] = false
	s.room_id = room
	s.minute = 12 * 60
	s.character["gold_cp"] = 100000
	return s


func _bought(id: String) -> GameSession:
	var s := _owner()
	PropertyRules.buy(s, data, id)
	s.room_id = PropertyRules.main_room(s, data, id)
	return s


func test_a_tavern_hires_by_roles_up_to_its_places() -> void:
	var s := _bought("river_house")
	PropertyRules.state(s.character)["river_house"]["kind"] = "tavern"
	var roles := PropertyRules.places(s, data, "river_house").map(func(p: Dictionary) -> String: return str(p["role"]))
	assert_array(roles).contains_exactly(["половой", "кухарка"])
	PropertyRules.hire_worker(s, data, "river_house", "половой")
	PropertyRules.hire_worker(s, data, "river_house", "половой")
	assert_str(PropertyRules.worker_why(s, data, "river_house", "половой")).is_equal("PROPERTY_HAS_WORKER")
	assert_str(PropertyRules.worker_why(s, data, "river_house", "кухарка")).is_empty()
	PropertyRules.hire_worker(s, data, "river_house", "кухарка")
	assert_int(PropertyRules.staff(s, "river_house").size()).is_equal(3)
	var sid := str(PropertyRules.prop(s, data, "river_house")["site"])
	assert_int(ObjectRules.staff(s, data, sid).filter(func(x: Dictionary) -> bool: return str(x["source"]) == "hired").size()).is_equal(3)
	var who := str(PropertyRules.staff(s, "river_house")[0]["npc"])
	PropertyRules.fire(s, data, "river_house", who)
	assert_int(PropertyRules.staff(s, "river_house").size()).is_equal(2)
	assert_array(SceneRules.npcs(s, data["world"], s.room_id)).not_contains([who])


func test_more_hands_bring_more() -> void:
	assert_float(PropertyRules.staff_mult(data, 1)).is_equal(1.0)
	assert_float(PropertyRules.staff_mult(data, 3)).is_equal(2.0)
	var s := _bought("old_mill")
	PropertyRules.state(s.character)["old_mill"]["cond"] = 100.0
	PropertyRules.hire_worker(s, data, "old_mill")
	PropertyRules.hire_worker(s, data, "old_mill")
	TimeRules.advance(s, data, 1440)
	assert_int(int(PropertyRules.state(s.character)["old_mill"]["cash"])).is_equal(roundi(50 * 1.5) - 30)


func test_the_counter_of_a_house_is_an_object_of_its_own() -> void:
	var s := _bought("river_house")
	assert_str(PropertyRules.upgrade_why(s, data, "river_house", "counter")).is_empty()
	PropertyRules.upgrade(s, data, "river_house", "counter")
	TimeRules.advance(s, data, 2 * 1440)
	var counters := PropertyRules.state(s.character).keys().filter(func(id: String) -> bool: return PropertyRules.kind_id(s, data, id) == "counter")
	assert_int(counters.size()).is_equal(1)
	var cid := str(counters[0])
	var w := WorldView.new(data["world"])
	var room := PropertyRules.main_room(s, data, cid)
	assert_str(w.site_id(room)).is_not_equal(str(PropertyRules.prop(s, data, "river_house")["site"]))
	assert_array(w.exits(room)).contains([PropertyRules.main_room(s, data, "river_house")])
	assert_array(ShopRules.venues(s, data)).contains([cid])
	assert_array(ShopRules.venues(s, data)).not_contains(["river_house"])
	s.room_id = room
	assert_str(PropertyRules.worker_why(s, data, cid, "продавец")).is_empty()
	PropertyRules.hire_worker(s, data, cid, "продавец")
	assert_bool(ShopRules.staffed(s, cid)).is_true()


func test_a_market_stall_is_rented_with_its_seller() -> void:
	var s := _owner()
	PropertyRules.rent(s, data, "npc_clerk", "stall", 1)
	var vid := PropertyRules.rented(s, data, "stall", "brod")
	assert_str(vid).is_not_empty()
	s.room_id = ShopRules.room_of(s, data, vid)
	assert_array(WorldView.new(data["world"]).exits(s.room_id)).contains(["brod-square"])
	PropertyRules.hire_worker(s, data, vid, "продавец")
	assert_bool(ShopRules.staffed(s, vid)).is_true()
	s.character["inventory"]["silver_ring"] = 5
	ShopRules.put(s, data, vid, "silver_ring", 5)
	var lines := TimeRules.advance(s, data, 2 * 1440)  # the stall lapses after the first day
	assert_str("\n".join(lines)).contains("срок аренды вышел")
	assert_bool(PropertyRules.staff(s, vid).is_empty()).is_true()
	assert_bool(ShopRules.staffed(s, vid)).is_false()
	assert_str(PropertyRules.worker_why(s, data, vid, "продавец")).is_equal("SHOP_STALL_LAPSED")


func test_an_old_save_keeps_its_worker_and_stall() -> void:
	var save := {"save_version": 49, "session": {"character": {"property": {"old_mill": {"worker": "gen_npc_9", "serf": "", "since": 3}}}}}
	SaveFormat._v49_to_v50(save, {})
	var st: Dictionary = save["session"]["character"]["property"]["old_mill"]
	assert_bool(st.has("worker")).is_false()
	assert_str(str(st["staff"][0]["npc"])).is_equal("gen_npc_9")
	var s := _bought("old_mill")
	PropertyRules.state(s.character)["old_mill"]["staff"] = [{"npc": "gen_npc_9", "role": "", "wage": 0}]
	s.character["shop"] = {"venues": {"stall:brod-square": {"stock": {"silver_ring": 2}, "prices": {}, "cash": 0, "last_day": 0, "last": {}}},
		"stalls": {"brod-square": s.day + 3}, "charters": {}, "rep": {}}
	PropertyRules.upgrade_legacy(s, data)
	assert_str(str(PropertyRules.staff(s, "old_mill")[0]["role"])).is_equal("подручный мельника")
	assert_int(int(PropertyRules.staff(s, "old_mill")[0]["wage"])).is_equal(15)
	var vid := PropertyRules.rented(s, data, "stall", "brod")
	assert_int(int(PropertyRules.state(s.character)[vid]["rent_until"])).is_equal(s.day + 3)
	assert_int(int(ShopRules.venue(s.character, vid)["stock"]["silver_ring"])).is_equal(2)
	assert_bool(s.character["shop"].has("stalls")).is_false()


func test_the_pack_object_and_the_heros_job_in_its_staff() -> void:
	var s := _owner("brod-tavern-hall")
	var sid := WorldView.new(data["world"]).site_id(ReputationRules.home_room(data, "npc_innkeeper"))
	assert_str(ObjectRules.kind_id(s, data, sid)).is_equal("tavern")  # by the site's tag
	JobRules.state(s.character)["serve_tables"] = {"rank": 0, "good": 0, "shifts": 0}
	var staff := ObjectRules.staff(s, data, sid)
	assert_bool(staff.any(func(x: Dictionary) -> bool: return str(x["source"]) == "owner" and str(x["who"]) == "npc_innkeeper")).is_true()
	assert_bool(staff.any(func(x: Dictionary) -> bool: return str(x["source"]) == "hero")).is_true()
	assert_str(ObjectRules.text(s, data, ReputationRules.home_room(data, "npc_innkeeper"))).contains("штат:")


func _inn(extra: Dictionary) -> Dictionary:
	var site := {"key": "inn", "name": "Корчма «Ракита»", "tags": ["tavern"], "owner_id": "new:host", "kind": "tavern", "owner_role": "корчмарка",
		"staff": [{"npc_id": "new:girl", "role": "подавальщица"}], "upgrades": ["hearth", "bed"], "hours": {"opens": 7, "closes": 23}}
	site.merge(extra, true)
	return {"room_id": "brod-gate", "edge": 0, "new_location": true, "name": "Ракитное", "description": "Деревня.", "terrain": "grassland",
		"rooms": [{"key": "street", "name": "Улица Ракитного", "description": "Улица.", "exits": ["inn"]},
			{"key": "inn", "name": "Корчма «Ракита»", "indoor": true, "site": "inn", "exits": ["street"]}],
		"sites": [site],
		"npcs": [{"key": "host", "name": "Явдоха Ракитная", "role": "корчмарка", "gender": "female", "room_id": "new:inn"},
			{"key": "girl", "name": "Ганка", "role": "подавальщица", "gender": "female", "room_id": "new:inn"}]}


func test_the_master_makes_an_object_with_its_people() -> void:
	var s := _owner("brod-gate")
	var p := WorldGen.plan_place(s, data, _inn({}), true)
	assert_bool(p.has("reason")).override_failure_message(str(p)).is_false()
	WorldGen.apply_place(s, data, p["plan"])
	var inn := str(p["plan"]["ids"]["inn"])
	var sid := WorldView.new(data["world"]).site_id(inn)
	var site := WorldView.new(data["world"]).site(sid)
	var ids: Dictionary = p["plan"]["npc_ids"]
	assert_str(str(site["kind"])).is_equal("tavern")
	assert_str(str(site["staff"][0]["npc"])).is_equal(str(ids["girl"]))
	assert_dict(site["hours"]).is_equal({"from": 7, "to": 23})
	var staff := ObjectRules.staff(s, data, sid)
	assert_bool(staff.any(func(x: Dictionary) -> bool: return str(x["who"]) == str(ids["girl"]) and str(x["role"]) == "подавальщица")).is_true()
	assert_array(ObjectRules.upgrades(s, data, sid)).contains(["Очаг", "Кровать"])
	assert_str(ObjectRules.kind_id(s, data, sid)).is_equal("tavern")


func test_a_bad_object_is_refused() -> void:
	var s := _owner("brod-gate")
	assert_str(str(WorldGen.plan_place(s, data, _inn({"kind": "castle"}), true).get("reason", ""))).contains("kind")
	assert_str(str(WorldGen.plan_place(s, data, _inn({"upgrades": ["moat"]}), true).get("reason", ""))).contains("moat")
	assert_str(str(WorldGen.plan_place(s, data, _inn({"staff": [{"npc_id": "nobody", "role": "x"}]}), true).get("reason", ""))).contains("nobody")


func test_ones_own_bed_in_any_room_of_the_house() -> void:
	var s := _bought("river_house")
	PropertyRules.upgrade(s, data, "river_house", "bed")
	TimeRules.advance(s, data, 1440)
	for room: String in PropertyRules.rooms(s, data, "river_house"):
		assert_bool(bool(ExplorationRules.rest_place(data["world"], room, s, data).get("own", false))).is_true()
	s.room_id = "brod-square"
	assert_bool(bool(ExplorationRules.rest_place(data["world"], s.room_id, s, data).get("own", false))).is_false()
