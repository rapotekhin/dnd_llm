extends GdUnitTestSuite
## v0.8.4.16: who is here and where — the dead are not of the scene for any rule, an NPC is found where it stands now, one
## live encounter, one «may the hero leave», one name; witnesses and invisibility decided in WatchRules.eyes alone.

var data: Dictionary


func before() -> void:
	data = TestUtils.data()


func _session(room: String) -> GameSession:
	var s := TestUtils.new_session()
	s.room_id = room
	s.minute = 720
	return s


func test_a_dead_employer_is_not_here_for_a_job() -> void:
	var s := _session("brod-tavern-hall")
	var job := ""
	for id: String in JobRules.all(s, data):
		if str(JobRules.job(s, data, id).get("employer", "")) == "npc_innkeeper":
			job = id
	assert_str(job).is_not_empty()
	assert_bool(JobRules.employer_here(s, data, job)).is_true()
	Being.of(s, "npc_innkeeper")["dead"] = true
	assert_bool(JobRules.employer_here(s, data, job)).is_false()


func test_an_npc_is_found_where_it_stands_now() -> void:
	var s := _session("brod-tavern-hall")
	var home := ReputationRules.home_room(data, "npc_prospector")
	assert_str(Where.npc_room(s, data, "npc_prospector")).is_equal(home)
	Being.of(s, "npc_prospector")["at"] = "brod-square"
	assert_str(Where.npc_room(s, data, "npc_prospector")).is_equal("brod-square")
	assert_str(Where.npc_location(s, data, "npc_prospector")).is_equal(WorldView.new(data["world"]).location_id("brod-square"))
	s.quests_active["drogin_amulet"] = 1  # bring it to the prospector: the map marks where he stands
	s.visited.append("brod-square")
	assert_array(WorldMap.step_rooms(s, data, "drogin_amulet")).contains(["brod-square"])


func test_a_fight_at_peace_does_not_wait_and_the_camp_is_made() -> void:
	var s := _session("brod-tavern-hall")
	s.character["inventory"]["rations"] = 2
	for rid: String in data["world"]["rooms"]:
		if not (data["world"]["rooms"][rid].get("encounter", {}) as Dictionary).is_empty():
			s.room_id = rid
			break
	var enc := EncounterRules.live(s, data, s.room_id)
	assert_bool(enc.is_empty()).is_false()
	assert_str(ExplorationRules.can_camp(s, data)).is_equal("REST_DANGER")
	s.encounters_peace.append(str(enc["id"]))
	assert_bool(EncounterRules.live(s, data, s.room_id).is_empty()).is_true()
	assert_str(ExplorationRules.can_camp(s, data)).is_not_equal("REST_DANGER")


func test_one_answer_whether_the_hero_may_leave() -> void:
	var s := _session("brod-tavern-hall")
	var to := ""
	for x: String in WayRules.open_exits(s, data["world"], s.room_id):
		if to.is_empty() and WayRules.blocked(s, data, s.room_id, x).is_empty():
			to = x
	assert_str(WayRules.leave_why(s, data, s.room_id, to)).is_empty()
	s.arrest = s.room_id
	assert_str(WayRules.leave_why(s, data, s.room_id, to)).is_equal("CRIME_HELD")
	s.arrest = ""
	s.character["inventory"]["plate_armor"] = 10
	assert_bool(CharacterRules.overloaded(s.character, data, s.items)).is_true()
	assert_str(WayRules.leave_why(s, data, s.room_id, to)).is_equal("TOO_HEAVY")


func test_one_name_of_an_npc() -> void:
	assert_str(WorldView.name_of(data, "npc_innkeeper")).is_equal(str(data["world"]["npcs"]["npc_innkeeper"]["name"]))
	assert_str(WorldView.name_of(data, "nobody_at_all")).is_equal("nobody_at_all")


func test_an_invisible_hero_is_seen_only_by_who_sees_the_invisible() -> void:
	var s := _session("brod-tavern-hall")
	var here := s.npcs_here(data["world"], s.room_id)
	ConditionRules.add_effect(s.character, {"condition": "invisible", "ends": {"rest": "long"}})
	assert_array(WatchRules.eyes(s, data, here)).is_empty()
	var bruno := Sheet.own(s, "npc_innkeeper")
	ConditionRules.add_effect(bruno, {"condition": "", "see_invisible": true, "source": {"kind": "spell", "id": "see_invisibility", "name": "Видение невидимого"}})
	assert_bool(WatchRules.pierces(s, data, Sheet.who(s, data, "npc_innkeeper"), Sheet.HERO, -1)).is_true()
	assert_bool(WatchRules.pierces(s, data, Sheet.who(s, data, here[0] if here[0] != "npc_innkeeper" else here[1]), Sheet.HERO, -1)).is_false()


func test_one_behind_a_door_sees_a_visible_hero_not_an_invisible_one() -> void:
	var s := _session("brod-tavern-hall")
	var off := ["npc_prospector"]  # not on this map: it counts for a deed in the open
	assert_array(WatchRules.eyes(s, data, off)).contains(off)
	ConditionRules.add_effect(s.character, {"condition": "invisible", "ends": {"rest": "long"}})
	assert_array(WatchRules.eyes(s, data, off)).is_empty()
