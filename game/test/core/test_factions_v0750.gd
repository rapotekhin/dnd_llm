extends GdUnitTestSuite
## Factions (v0.7.50): the standing, what it opens, how it moves.


var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _session() -> GameSession:
	var s := TestUtils.new_session()
	s.settings["needs"] = false
	return s


func _wolves() -> Dictionary:
	return {"id": "t_wolves", "faction": "wild_beasts", "enemies": [{"monster": "wolf", "count": 1, "name": "Волк"}]}


func test_every_pack_person_has_a_faction_of_the_pack() -> void:
	var s := _session()
	for id: String in data["world"]["npcs"]:
		assert_bool(FactionRules.has(s, data, FactionRules.of_npc(s, data, id))).is_true()


func test_a_foe_by_its_type_or_its_encounter() -> void:
	assert_str(FactionRules.of_foe(data, {}, {"monster": "wolf"})).is_equal("wild_beasts")
	assert_str(FactionRules.of_foe(data, {}, {"monster": "skeleton"})).is_equal("the_dead")
	assert_str(FactionRules.of_foe(data, {"faction": "gen_house"}, {"monster": "wolf"})).is_equal("gen_house")


func test_beasts_keep_the_peace_with_a_friend_and_a_quest_passes() -> void:
	var s := _session()
	assert_bool(FactionRules.peaceful(s, data, _wolves())).is_false()
	FactionRules.add(s, data, "wild_beasts", 30, "тест")
	assert_bool(FactionRules.peaceful(s, data, _wolves())).is_true()
	var m := EncounterRules.meet(s, data, "pushcha-trail", "pushcha-edge", _wolves())
	assert_bool(bool(m.get("peace", false))).is_true()
	assert_array(s.encounters_passed).contains(["t_wolves"])
	assert_array(s.encounters_peace).contains(["t_wolves"])
	assert_str(str(s.creatures["pushcha-trail"][0]["state"])).is_equal("truce")


func test_the_dead_do_not_make_friends() -> void:
	var s := _session()
	FactionRules.add(s, data, "the_dead", 80, "тест")
	assert_int(FactionRules.points(s, data, "the_dead")).is_equal(0)


func test_a_friend_of_a_member_grows_the_faction_a_settlement_by_its_reputation() -> void:
	var s := _session()
	BondRules.add(s, data, "npc_guildhead", 30, "тест")  # the head counts double
	assert_int(FactionRules.points(s, data, "night_rats")).is_equal(30)
	assert_bool(FactionRules.friendly(s, data, "night_rats")).is_true()
	BondRules.add(s, data, "npc_innkeeper", 40, "тест")
	assert_int(FactionRules.points(s, data, "brod_folk")).is_equal(0)  # one friend does not make a town's
	FactionRules.add(s, data, "brod_folk", 12, "тест")
	assert_int(ReputationRules.points(s, "brod")).is_equal(2)
	assert_int(FactionRules.points(s, data, "brod_folk")).is_equal(10)


func test_friends_walk_into_the_den_free() -> void:
	var s := _session()
	assert_str(OrgRules.entry_why(s, data, "night_rats")).is_not_equal("ORG_ENTRY_OPEN")
	FactionRules.add(s, data, "night_rats", 30, "тест")
	assert_str(OrgRules.entry_why(s, data, "night_rats")).is_equal("ORG_ENTRY_OPEN")
	assert_bool(FactionRules.welcome(s, data, "npc_guildhead")).is_true()


func test_a_settlement_does_not_open_its_houses() -> void:
	var s := _session()
	FactionRules.add(s, data, "brod_folk", 100, "тест")
	assert_bool(FactionRules.friendly(s, data, "brod_folk")).is_true()
	assert_bool(FactionRules.welcome(s, data, "npc_smith")).is_false()


func test_a_known_crime_and_an_enemy_who_will_not_talk() -> void:
	var s := _session()
	FactionRules.on_crime(s, data, "npc_guildhead", "murder")
	assert_int(FactionRules.points(s, data, "night_rats")).is_equal(-40)
	FactionRules.on_crime(s, data, "npc_guildhead", "murder")
	assert_bool(FactionRules.enemy(s, data, "night_rats")).is_true()
	assert_bool(SocialRules.refuses(s, data, "npc_pit_master")).is_true()


func test_beasts_are_calmed_by_animal_handling_only() -> void:
	var s := _session()
	var wolves: Array = _wolves()["enemies"]
	assert_str(EncounterRules.talkable(s, data, wolves, "animal_handling")).is_empty()
	assert_str(EncounterRules.talkable(s, data, [{"monster": "bandit"}], "animal_handling")).is_equal("COMBAT_NO_PARLEY")
	assert_int(EncounterRules.calm_dc(data, wolves)).is_greater(10)


func test_the_master_makes_one_once_and_moves_the_standing_once_a_day() -> void:
	var s := _session()
	var made := FactionRules.make(s, data, {"create": {"name": "Дом чародея", "kind": "household"}})
	FactionRules.apply_make(s, data, made["plan"])
	assert_dict(FactionRules.make(s, data, {"create": {"name": "дом чародея"}})).contains_keys(["reason"])
	var id: String = made["plan"]["create"]
	assert_str(FactionRules.ensure(s, data, "Дом чародея", "people", false)).is_equal(id)
	var p := FactionRules.make(s, data, {"faction_id": id, "delta": 10, "why": "спас"})
	FactionRules.apply_make(s, data, p["plan"])
	assert_int(FactionRules.points(s, data, id)).is_equal(10)
	assert_dict(FactionRules.make(s, data, {"faction_id": id, "delta": 5, "why": "ещё"})).contains_keys(["reason"])
	assert_dict(FactionRules.make(s, data, {"faction_id": id, "delta": 50, "why": "много"})).contains_keys(["reason"])


func test_the_standing_survives_a_save() -> void:
	var s := _session()
	FactionRules.add(s, data, "wild_beasts", 30, "тест")
	s.encounters_peace.append("x")
	var back := GameSession.from_dict(s.to_dict(0))
	assert_int(FactionRules.points(back, data, "wild_beasts")).is_equal(30)
	assert_array(back.encounters_peace).contains(["x"])
	assert_int(FactionRules.met(back, data).size()).is_equal(1)
