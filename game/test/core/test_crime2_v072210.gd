extends GdUnitTestSuite
## Crime and punishment 2.0 (roadmap v0.7.22.10): a sentence by severity in the law's prison, the guilt stays, a hidden
## body is searched once a day — harder each day, a known body is buried.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _hero(room: String) -> GameSession:
	var s := TestUtils.new_session()
	for p: Dictionary in data["presets"]:
		if p["id"] == "rogue_damir":
			s.character = GameSession.normalized_character(CharacterBuilder.build_preset(p, data))
	CharacterRules.refresh(s.character, data, s.items)
	s.room_id = room
	return s


func test_a_murder_sends_the_hero_to_prison_and_the_guilt_stays() -> void:
	var s := _hero("brod-square")
	CrimeRules.on_death(s, data, "npc_merchant", true, s.room_id)  # Fern, not notable
	CrimeRules.reveal(s, data, "npc_merchant")
	s.room_id = "brod-gate"
	TimeRules.advance(s, data, int(data["rules"]["crime"]["search_minutes"]))
	CrimeRules.check_arrest(s, data)
	assert_bool(CrimeRules.held(s)).is_true()
	var sn := CrimeRules.sentence(s, data, "brod")
	assert_str(str(sn["kind"])).is_equal("prison")
	var att := s.attitude("npc_innkeeper")
	var day := s.day
	s.character["hp"] = 1
	var lines := CrimeRules.answer(s, data, "stocks")
	assert_int(s.day).is_equal(day + int(sn["days"]))
	assert_str(s.room_id).is_equal("brod-lockup")  # wakes in the prison, not where caught
	assert_int(int(s.character["hp"])).is_equal(int(s.character["max_hp"]))
	assert_bool(s.wanted.has("brod")).is_false()
	assert_int(s.attitude("npc_innkeeper")).is_equal(att)  # not forgiven
	assert_str(" · ".join(lines)).contains("люди помнят")


func test_more_crimes_mean_hard_labour() -> void:
	var s := _hero("brod-tavern-hall")
	CrimeRules.on_death(s, data, "npc_mercenary", true, s.room_id)  # notable
	CrimeRules.on_death(s, data, "npc_innkeeper", true, s.room_id)
	var sn := CrimeRules.sentence(s, data, "brod")
	assert_str(str(sn["kind"])).is_equal("labour")
	s.room_id = "brod-gate"
	TimeRules.advance(s, data, int(data["rules"]["crime"]["search_minutes"]))
	CrimeRules.check_arrest(s, data)
	CrimeRules.answer(s, data, "stocks")
	assert_int(int(s.character.get("exhaustion", 0))).is_greater(0)


func test_a_hidden_body_is_searched_daily_harder_each_day() -> void:
	var s := _hero("brod-smithy")
	CrimeRules.on_death(s, data, "npc_smith", true, s.room_id)  # no witnesses in the smithy at night? make sure
	s.crimes[0]["witnesses"] = []
	s.crimes[0]["known"] = false
	s.wanted.clear()
	assert_str(CrimeRules.can_hide(s, data, "npc_smith")).is_empty()
	CrimeRules.hide(s, data, "npc_smith", 40, true)  # hidden very well — d20 + 4 never reaches 42
	assert_str(CrimeRules.can_hide(s, data, "npc_smith")).is_equal("CRIME_HIDDEN_ALREADY")
	TimeRules.advance(s, data, 1440 * 3)
	assert_bool(bool(s.crimes[0]["known"])).is_false()
	assert_int(int(s.crimes[0]["searched_days"])).is_equal(3)
	assert_bool(s.bodies.has("npc_smith")).is_true()  # a secret body is not buried


func test_a_badly_hidden_body_is_found_like_any() -> void:
	var s := _hero("brod-smithy")
	CrimeRules.on_death(s, data, "npc_smith", true, s.room_id)
	s.crimes[0]["witnesses"] = []
	s.crimes[0]["known"] = false
	CrimeRules.hide(s, data, "npc_smith", 3, false)
	TimeRules.advance(s, data, int(data["rules"]["crime"]["found_minutes"]))
	assert_bool(bool(s.crimes[0]["known"])).is_true()


func test_a_known_body_is_buried() -> void:
	var s := _hero("brod-tavern-hall")
	CrimeRules.on_death(s, data, "npc_mercenary", false, s.room_id)  # self-defence
	assert_bool(s.bodies.has("npc_mercenary")).is_true()
	var lines := TimeRules.advance(s, data, int(data["rules"]["crime"]["bury_days"]) * 1440)
	assert_bool(s.bodies.has("npc_mercenary")).is_false()
	assert_str(" · ".join(lines)).contains("Похоронили")
