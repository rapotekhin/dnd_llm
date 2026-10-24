extends GdUnitTestSuite
## Sites (roadmap v0.7.22.24, the author's request): location → site → room. The pack's rooms are in sites; a private
## room unasked before eyes is a trespass; the master grows a site inside a location; the map is nested boxes; an old
## save's made rooms get sites of their own.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _hero(room: String) -> GameSession:
	var s := TestUtils.new_session()
	for p: Dictionary in data["presets"]:
		if p["id"] == "fighter_aira":
			s.character = GameSession.normalized_character(CharacterBuilder.build_preset(p, data))
	CharacterRules.refresh(s.character, data, s.items)
	s.room_id = room
	return s


func test_every_room_is_in_a_site_of_its_location() -> void:
	var w := WorldView.new(data["world"])
	for r: String in data["world"]["rooms"]:
		assert_dict(w.site_of(r)).override_failure_message(r).is_not_empty()
		assert_str(str(w.site_of(r)["location_id"])).is_equal(w.location_id(r))
	assert_array(w.site_rooms("brod-tavern")).has_size(4)
	assert_str(w.site_entry("brod-tavern")).is_equal("brod-tavern-hall")
	assert_bool(w.is_public("brod-tavern-hall")).is_true()
	assert_bool(w.is_public("brod-tavern-upstairs")).is_true()  # the rented rooms
	assert_bool(w.is_public("brod-tavern-kitchen")).is_false()
	assert_str(w.place_path("brod-tavern-hall")).is_equal("Ольховый Брод › Таверна «Хромой олень» › общий зал")
	assert_str(w.place_path("brod-square")).is_equal("Ольховый Брод › Рыночная площадь")


func test_the_kitchen_unasked_is_a_trespass() -> void:
	var s := _hero("brod-tavern-kitchen")
	var before := s.attitude("npc_innkeeper")
	var warned := SiteRules.on_enter(s, data, s.room_id)  # the first time — a warning only
	assert_str(" ".join(warned)).contains("Предупреждение")
	assert_array(s.crimes).is_empty()
	assert_int(s.attitude("npc_innkeeper")).is_equal(before)
	var back := GameSession.from_dict(s.to_dict(5))
	assert_bool(back.trespass_warned.has("brod-tavern")).is_true()
	var lines := SiteRules.on_enter(s, data, s.room_id)
	assert_str(" ".join(lines)).contains("без спроса")
	assert_int(s.attitude("npc_innkeeper")).is_equal(before + int(data["rules"]["sites"]["trespass_attitude"]))  # the owner in the hall hears
	var crime: Dictionary = s.crimes.filter(func(c: Dictionary) -> bool: return str(c["kind"]) == "trespass")[0]
	assert_bool(bool(crime["known"])).is_true()
	assert_str(" ".join(s.memory_of("npc_innkeeper"))).contains("без спроса")
	assert_int(s.attitude("npc_merchant")).is_equal(0)  # a light crime: the town does not turn on the hero
	assert_array(SiteRules.on_enter(s, data, s.room_id)).is_empty()  # once a day
	assert_str(" ".join(s.memory_of("npc_merchant"))).contains("вломился")


func test_welcome_unseen_or_public_is_no_trespass() -> void:
	var s := _hero("brod-tavern-kitchen")
	s.shift_attitude("npc_innkeeper", 2, data)  # the owner's friend
	assert_array(SiteRules.on_enter(s, data, s.room_id)).is_empty()
	var t := _hero("brod-tavern-kitchen")
	t.sneaking = true  # slipped in unnoticed
	assert_array(SiteRules.on_enter(t, data, t.room_id)).is_empty()
	var u := _hero("brod-tavern-hall")
	assert_array(SiteRules.on_enter(u, data, u.room_id)).is_empty()
	assert_array(u.crimes).is_empty()


func test_the_master_grows_a_site_inside_a_location() -> void:
	var d := TestUtils.data()
	var s := _hero("brod-square")
	var fx := EffectEngine.new()
	fx.searched_places["t-1"] = true
	var spec := {"kind": "create_place", "inside": true, "room_id": "brod-square",
		"site": {"name": "Баня Гриды", "tags": ["bathhouse"], "public": true},
		"rooms": [{"key": "a", "name": "Предбанник", "description": "Лавки, веники.", "exits": ["b"]},
			{"key": "b", "name": "Парная", "description": "Жар и пар.", "public": false}]}
	var r := fx.validate(s, d, "t-1", spec)
	assert_bool(bool(r["accepted"])).override_failure_message(str(r)).is_true()
	fx.apply(s, "t-1", [r["effect_id"]])
	var w := WorldView.new(d["world"])
	var sid: String = (s.generated["sites"] as Dictionary).keys()[0]
	assert_str(str(w.site(sid)["name"])).is_equal("Баня Гриды")
	assert_str(str(w.site(sid)["location_id"])).is_equal("brod")
	var rooms := w.site_rooms(sid)
	assert_array(rooms).has_size(2)
	assert_array(w.exits("brod-square")).contains([w.site_entry(sid)])
	assert_bool(w.is_public(rooms[1])).is_false()
	assert_array(WorldGen.open_edges(s, d, "brod-square")).is_equal(WorldGen.open_edges(_hero("brod-square"), TestUtils.data(), "brod-square"))  # no edge spent
	for i in 3:  # rules.world_gen.max_sites_inside a location
		fx.searched_places["t-%d" % (i + 2)] = true
		var more := spec.duplicate(true)
		more["site"]["name"] = "Дом %d" % i
		more["rooms"] = [{"key": "a", "name": "Сени %d" % i, "description": "Тесно."}]
		var ri := fx.validate(s, d, "t-%d" % (i + 2), more)
		if i < int(d["rules"]["world_gen"]["max_sites_inside"]) - 1:
			assert_bool(bool(ri["accepted"])).override_failure_message(str(ri)).is_true()
			fx.apply(s, "t-%d" % (i + 2), [ri["effect_id"]])
		else:
			assert_str(str(ri["reason"])).contains("больше нельзя")


func test_the_map_is_nested_boxes() -> void:
	var b := WorldMap.boxes(data["world"])
	assert_that(WorldMap.boxes(data["world"])).is_equal(b)  # stable
	var w := WorldView.new(data["world"])
	for r: String in data["world"]["rooms"]:
		var site: Rect2 = b["sites"][w.site_id(r)]
		assert_bool(site.has_point(b["rooms"][r])).override_failure_message(r).is_true()
		assert_bool((b["locations"][w.location_id(r)] as Rect2).encloses(site)).override_failure_message(r).is_true()
	var locs: Array = b["locations"].keys()
	for i in locs.size():
		for j in range(i + 1, locs.size()):
			assert_bool((b["locations"][locs[i]] as Rect2).intersects(b["locations"][locs[j]])).override_failure_message("%s × %s" % [locs[i], locs[j]]).is_false()


func test_an_old_saves_made_rooms_get_sites() -> void:
	var old := {"save_version": 41, "session": {"generated": {"rooms": {
		"gen_room_1": {"name": "Курган", "location_id": "gen_loc_1", "exits": ["gen_room_2", "brod-gate"]},
		"gen_room_2": {"name": "Хижина", "location_id": "gen_loc_1", "exits": ["gen_room_1"]},
		"gen_room_3": {"name": "Пасека", "location_id": "pushcha", "exits": ["pushcha-trail"]}}}}}
	SaveFormat.migrate(old)
	var rooms: Dictionary = old["session"]["generated"]["rooms"]
	assert_str(str(rooms["gen_room_1"]["site_id"])).is_equal(str(rooms["gen_room_2"]["site_id"]))  # one place — one site
	assert_str(str(rooms["gen_room_3"]["site_id"])).is_not_equal(str(rooms["gen_room_1"]["site_id"]))
	assert_int((old["session"]["generated"]["sites"] as Dictionary).size()).is_equal(2)
