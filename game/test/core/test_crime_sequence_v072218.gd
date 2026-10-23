extends GdUnitTestSuite
## The sequence of a crime (roadmap v0.7.22.18, the author's fixes check #27–#30): a wait where the law is goes in patrol
## steps and stops when the guard comes; the master gets the engine's outcome of an answer to the guard; the room stands
## up for an NPC the hero attacks; the wanted hero gets no services and no paid bed.

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


func test_waiting_at_a_murder_the_guard_comes() -> void:
	var s := _hero("brod-square")
	s.wanted["brod"] = TimeRules.abs_minute(s)
	var start := TimeRules.abs_minute(s)
	var r := CrimeRules.wait(s, data, 240)
	assert_bool(CrimeRules.held(s)).is_true()
	assert_int(int(r["minutes"])).is_less(240)
	assert_int(TimeRules.abs_minute(s) - start).is_equal(int(r["minutes"]))
	assert_str(" ".join(r["lines"])).contains("Ожидание прервано")
	var wild := _hero("pushcha-hollow")
	var w := CrimeRules.wait(wild, data, 240)
	assert_int(int(w["minutes"])).is_equal(240)


func test_the_master_gets_the_outcome_of_the_answer() -> void:
	var s := _hero("brod-square")
	s.wanted["brod"] = TimeRules.abs_minute(s)
	s.arrest = s.room_id
	assert_str(CrimeRules.outcome(s, data)).contains("держит")
	CrimeRules.talked(s, data, "intimidate", true)
	assert_str(CrimeRules.outcome(s, data)).contains("вергельда он не платил")
	s.wanted.erase("brod")
	assert_str(CrimeRules.outcome(s, data)).contains("искуплена")


func test_the_room_stands_up_for_the_npc() -> void:
	var s := _hero("brod-tavern-hall")
	var here := s.npcs_here(data["world"], s.room_id)
	var victim := {"monster": "commoner", "npc_id": "npc_serving", "by_hero": true}
	var help := CrimeRules.defenders(s, data, [victim])
	var names: Array = help.map(func(f: Dictionary) -> String: return str(f["npc_id"]))
	for id: String in here:
		var fighting := (data["world"]["npcs"][id].get("tags", []) as Array).has("military")
		assert_bool(names.has(id)).is_equal(fighting and id != "npc_serving")
	assert_bool(names.has("npc_innkeeper")).is_false()  # a commoner does not fight
	if names.is_empty():
		return
	s.shift_attitude(str(names[0]), 3, data)  # a close friend of the hero stays out
	assert_bool(CrimeRules.defenders(s, data, [victim]).any(func(f: Dictionary) -> bool: return str(f["npc_id"]) == str(names[0]))).is_false()
	assert_array(CrimeRules.defenders(s, data, [{"monster": "commoner", "npc_id": "npc_serving"}])).is_empty()  # the NPC began it


func test_the_law_guard_defends_and_holds() -> void:
	var s := _hero("brod-gate")
	s.npc_at["npc_cook"] = "brod-gate"
	if not s.npcs_here(data["world"], s.room_id).has("npc_captain"):
		return  # not at the gate at this hour
	var help := CrimeRules.defenders(s, data, [{"monster": "commoner", "npc_id": "npc_cook", "by_hero": true}])
	var captain: Array = help.filter(func(f: Dictionary) -> bool: return str(f["npc_id"]) == "npc_captain")
	assert_int(captain.size()).is_equal(1)
	assert_bool(bool(captain[0]["law"])).is_true()


func test_no_services_and_no_bed_for_the_wanted() -> void:
	var s := _hero("brod-temple")
	s.character["inventory"]["ring_of_protection"] = 1
	var before: Array = TradeRules.services(s, data, "npc_priestess").map(func(x: Dictionary) -> String: return str(x["why"]))
	assert_bool(before.has("SHOP_CLOSED_WANTED")).is_false()
	s.wanted["brod"] = TimeRules.abs_minute(s)
	for sv: Dictionary in TradeRules.services(s, data, "npc_priestess"):
		assert_str(str(sv["why"])).is_equal("SHOP_CLOSED_WANTED")
	var favor := SocialRules.plan_favor(s, data, "npc_priestess", "identify", "", true)
	assert_str(str(favor.get("reason", ""))).contains("розыске")
	assert_str(ExplorationRules.can_rest(s, data["world"], data)).is_empty()  # the temple's bed is free
	s.room_id = "brod-tavern-upstairs"
	s.character["gold_cp"] = 10000
	assert_str(ExplorationRules.can_rest(s, data["world"], data)).is_equal("REST_WANTED")
	s.wanted.erase("brod")
	assert_str(ExplorationRules.can_rest(s, data["world"], data)).is_empty()
