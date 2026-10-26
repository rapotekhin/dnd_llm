extends GdUnitTestSuite
## Offices (v0.7.34): appointed on conditions with an interview, the soldier's rank, merit and promotion, the day's
## cases with checks and bribes, the weekly wage, suspicion and the inquiry, absence and removal, the headman by an
## election or a bribe, the town's treasury, tax and projects with a world flag.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _hero(room: String = "brod-townhall", hour: int = 12) -> GameSession:
	var s := TestUtils.new_session()
	s.settings["needs"] = false
	s.settings["difficulty"] = "trivial"
	s.room_id = room
	s.minute = hour * 60
	s.character["gold_cp"] = 100000
	s.rested_at = TimeRules.abs_minute(s) + 60 * 1440
	return s


func _case_of(s: GameSession, id: String, kind: String) -> int:
	var list := OfficeRules.today(s, data, id)
	for i in list.size():
		if str(list[i]["kind"]) == kind and not bool(list[i]["done"]):
			return i
	return -1


func test_the_scribe_needs_the_diploma_or_a_bribe() -> void:
	var s := _hero()
	assert_str(OfficeRules.appoint_why(s, data, "brod_scribe")).is_equal("OFFICE_REQUIREMENTS")
	assert_str(OfficeRules.buy_why(s, data, "brod_scribe")).is_empty()
	s.character["inventory"]["gen_diploma_letters"] = 1
	assert_str(OfficeRules.appoint_why(s, data, "brod_scribe")).is_empty()
	OfficeRules.appoint(s, data, "brod_scribe")
	assert_int(int(OfficeRules.view(s.character)["brod_scribe"].get("suspicion", 0))).is_equal(0)
	assert_bool(OfficeRules.holds(s.character, "brod_scribe")).is_true()
	assert_str(OfficeRules.rank_name(s.character, data, "brod_scribe")).is_equal("младший писарь")


func test_a_bought_place_is_whispered_about() -> void:
	var s := _hero()
	OfficeRules.buy(s, data, "brod_scribe")
	assert_int(int(s.character["gold_cp"])).is_equal(100000 - 3000)
	assert_int(int(OfficeRules.view(s.character)["brod_scribe"]["suspicion"])).is_equal(40)
	assert_str(OfficeRules.suspicion_word(s.character, data, "brod_scribe")).is_equal("шепчутся")


func test_a_soldier_starts_as_a_ten_leader_in_the_militia() -> void:
	var s := _hero("brod-gate")
	s.character["background"] = "soldier"
	assert_str(OfficeRules.appoint_why(s, data, "brod_militia")).is_empty()
	s.rng.seed = 3
	OfficeRules.appoint(s, data, "brod_militia")
	assert_bool(OfficeRules.holds(s.character, "brod_militia")).is_true()
	assert_str(OfficeRules.rank_name(s.character, data, "brod_militia")).is_equal("десятник")


func test_cases_move_merit_and_a_bribe_fills_the_pocket() -> void:
	var s := _hero()
	OfficeRules.buy(s, data, "brod_scribe")
	var list := OfficeRules.today(s, data, "brod_scribe")
	assert_int(list.size()).is_equal(2)
	assert_str(str(list[0]["kind"])).is_equal("record")
	var gold := int(s.character["gold_cp"])
	assert_str(OfficeRules.decide_why(s, data, "brod_scribe", 0, "bribe")).is_empty()
	OfficeRules.decide(s, data, "brod_scribe", 0, "bribe")
	assert_int(int(s.character["gold_cp"])).is_equal(gold + 300)
	assert_int(int(OfficeRules.view(s.character)["brod_scribe"]["suspicion"])).is_equal(60)
	assert_str(OfficeRules.decide_why(s, data, "brod_scribe", 0, "honest")).is_equal("OFFICE_CASE_DONE")
	OfficeRules.decide(s, data, "brod_scribe", 1, "honest")
	assert_int(OfficeRules.merit(s.character, "brod_scribe")).is_greater_equal(3)
	s.room_id = "brod-square"
	assert_str(OfficeRules.decide_why(s, data, "brod_scribe", 1, "honest")).is_equal("OFFICE_NOT_THERE")


func test_promotion_by_merit_and_the_weekly_wage() -> void:
	var s := _hero()
	OfficeRules.buy(s, data, "brod_scribe")
	OfficeRules.view(s.character)["brod_scribe"]["merit"] = 45
	assert_str(OfficeRules.rank_name(s.character, data, "brod_scribe")).is_equal("старший писарь")
	var gold := int(s.character["gold_cp"])
	OfficeRules.view(s.character)["brod_scribe"]["suspicion"] = 0
	s.day += 7
	OfficeRules.view(s.character)["brod_scribe"]["last_day"] = s.day
	OfficeRules.tick(s, data)
	assert_int(int(s.character["gold_cp"])).is_equal(gold + 800)


func test_an_inquiry_removes_and_makes_a_crime() -> void:
	var found := false
	for seed_value in 100:
		var s := _hero()
		s.settings["difficulty"] = "hard"
		OfficeRules.buy(s, data, "brod_scribe")
		OfficeRules.view(s.character)["brod_scribe"]["suspicion"] = 120
		s.rng.seed = seed_value
		s.day += 1
		OfficeRules.view(s.character)["brod_scribe"]["last_day"] = s.day
		OfficeRules.tick(s, data)
		if not OfficeRules.holds(s.character, "brod_scribe"):
			assert_bool(s.crimes.any(func(c: Dictionary) -> bool: return str(c["kind"]) == "corruption" and bool(c["known"]))).is_true()
			assert_str(OfficeRules.buy_why(s, data, "brod_scribe")).is_equal("OFFICE_REMOVED")
			found = true
			break
	assert_bool(found).is_true()


func test_absence_costs_merit_then_the_office() -> void:
	var s := _hero()
	OfficeRules.buy(s, data, "brod_scribe")
	OfficeRules.view(s.character)["brod_scribe"]["merit"] = 20
	s.day += 6
	OfficeRules.tick(s, data)
	assert_int(OfficeRules.merit(s.character, "brod_scribe")).is_equal(15)
	s.day += 7
	OfficeRules.tick(s, data)
	assert_bool(OfficeRules.holds(s.character, "brod_scribe")).is_false()


func test_the_judge_needs_service_first() -> void:
	var s := _hero()
	s.reputation["brod"] = 100
	ReputationRules.refresh(s, data)
	s.room_id = "brod-gate"
	assert_str(OfficeRules.appoint_why(s, data, "brod_judge")).is_equal("OFFICE_REQUIREMENTS")
	OfficeRules._st(s.character, "brod_scribe")["merit"] = 30
	assert_str(OfficeRules.appoint_why(s, data, "brod_judge")).is_empty()


func test_the_headman_elected_rules_the_town() -> void:
	var s := _hero()
	assert_str(OfficeRules.elect_why(s, data, "brod_headman")).is_equal("OFFICE_REQUIREMENTS")
	s.reputation["brod"] = 1000
	ReputationRules.refresh(s, data)
	assert_str(OfficeRules.elect_why(s, data, "brod_headman")).is_empty()
	s.rng.seed = 5
	OfficeRules.elect(s, data, "brod_headman")
	assert_bool(OfficeRules.holds(s.character, "brod_headman")).is_true()
	var t := OfficeRules.town(s, data, "brod")
	assert_int(int(t["treasury"])).is_equal(20000)
	OfficeRules.set_tax(s, data, "brod_headman", "high")
	assert_str(OfficeRules.build_why(s, data, "brod_headman", "palisade")).is_empty()
	OfficeRules.build(s, data, "brod_headman", "palisade")
	assert_int(int(t["treasury"])).is_equal(12000)
	for i in 5:
		s.day += 1
		OfficeRules.view(s.character)["brod_headman"]["last_day"] = s.day
		OfficeRules.tick(s, data)
	assert_bool(s.flags.has("brod_palisade")).is_true()
	assert_int(int(t["treasury"])).is_equal(12000 + 5 * 1000)
	assert_array(SceneRules.room(s, data["world"], "brod-gate")["hooks"]).contains(["новый частокол из свежих брёвен тянется от ворот к реке"])


func test_the_people_remove_a_hated_headman() -> void:
	var s := _hero()
	OfficeRules.buy(s, data, "brod_headman")
	var t := OfficeRules.town(s, data, "brod")
	t["discontent"] = 98
	OfficeRules.set_tax(s, data, "brod_headman", "high")
	s.day += 1
	OfficeRules.view(s.character)["brod_headman"]["last_day"] = s.day
	OfficeRules.view(s.character)["brod_headman"]["suspicion"] = 0
	OfficeRules.tick(s, data)
	assert_bool(OfficeRules.holds(s.character, "brod_headman")).is_false()


func test_the_snapshot_tells_the_master() -> void:
	var s := _hero()
	OfficeRules.buy(s, data, "brod_scribe")
	var snap := TurnSnapshot.build(s, data, 2000)
	assert_str(str(snap["character"].get("office", ""))).contains("Писарь при ратуше")
	assert_str(str(snap["character"].get("office", ""))).contains("Тихон")
