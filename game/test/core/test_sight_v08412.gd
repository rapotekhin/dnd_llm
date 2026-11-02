extends GdUnitTestSuite
## v0.8.4.12, ADR-0016: sight of anybody — darkvision, light, the dark and the passive by one road, the hero's and
## everybody else's; who sees a deed of anybody, not only of the hero.

var data: Dictionary


func before() -> void:
	data = TestUtils.data()


func _session(room: String) -> GameSession:
	var s := TestUtils.new_session()
	s.game_seed = 42
	s.room_id = room
	s.minute = 720
	s.character["inventory"] = {}
	s.character["traits"] = []
	CharacterRules.refresh(s.character, data, s.items)
	return s


func test_darkvision_and_light_of_anybody() -> void:
	var s := _session("mine-gallery")
	var c := SightRules.cfg(data)
	assert_int(SightRules.dark_sight(s, data, {"monster": "goblin"})).is_equal(12)  # its 60 ft
	assert_int(SightRules.reach(s, data, {"monster": "commoner"})).is_equal(int(c["blind"]))
	Being.of(s, "npc_innkeeper")["inventory"] = {"torch": 1}
	var bruno := Sheet.who(s, data, "npc_innkeeper")
	assert_int(SightRules.light(s, data, bruno)).is_equal(int(c["lights"]["torch"]))
	assert_int(SightRules.reach(s, data, bruno)).is_equal(int(c["lights"]["torch"]))
	assert_bool(SightRules.lit(s, data, bruno)).is_true()  # it shows from afar, as the hero with a torch does
	assert_str(SightRules.in_dark(s, data, bruno)).is_empty()


func test_a_foe_without_darkvision_is_blind_in_the_dark_and_hides_well() -> void:
	var s := _session("mine-gallery")
	var man := {"monster": "bandit"}
	assert_bool(CombatRules.dark_for(s, data, man)).is_true()
	assert_str(SightRules.in_dark(s, data, man)).is_equal("темнота")  # its own Hide has advantage here, as the hero's
	var blind := Sheet.passive(s, data, man)
	s.character["inventory"] = {"torch": 1}
	assert_bool(CombatRules.dark_for(s, data, man)).is_false()  # the hero's torch lights it for everybody
	assert_int(Sheet.passive(s, data, man)).is_equal(blind + 5)  # the dark took 5 from what it notices
	s.character["inventory"] = {}
	assert_bool(CombatRules.dark_for(s, data, {"monster": "goblin"})).is_false()


func test_one_hidden_or_invisible_goes_unseen_but_in_a_cone_whoever_it_is() -> void:
	var s := _session("brod-tavern-hall")
	assert_bool(WatchRules.sneaky(s, data, {"monster": "bandit"})).is_false()
	assert_bool(WatchRules.sneaky(s, data, {"monster": "bandit", "hidden": true})).is_true()
	var ghost := {"monster": "bandit"}
	ConditionRules.add_effect(ghost, {"condition": "invisible", "ends": {"rest": "long"}})
	assert_bool(WatchRules.sneaky(s, data, ghost)).is_true()


func test_a_deed_of_a_person_is_seen_by_the_others_not_by_itself() -> void:
	var s := _session("brod-tavern-hall")
	var here := s.npcs_here(data["world"], s.room_id)
	assert_int(here.size()).is_greater(1)
	var doer := str(here[0])
	var seen := WatchRules.eyes(s, data, here, doer)
	assert_bool(seen.has(doer)).is_false()
	assert_bool(seen.is_empty()).is_false()  # the hall is lit and small: somebody sees it
