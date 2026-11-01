extends GdUnitTestSuite
## One character from first sight to the end (v0.7.62): the same id in a room, in a fight and after it; a kind of
## character is a part put on the record or taken off.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _hero(room: String = "pushcha-trail") -> GameSession:
	var s := TestUtils.new_session()
	s.room_id = room
	return s


func _wolves() -> Dictionary:
	return {"id": "t_wolves", "enemies": [{"monster": "wolf", "name": "Волк", "count": 2}, {"monster": "goblin"}]}


func test_a_creature_is_a_part_of_its_record() -> void:
	var s := _hero()
	var c := CreatureRules.add(s, s.room_id, {"name": "Гоблин", "monster": "goblin", "state": "surrendered", "bound": false, "led": false, "since": 0})
	assert_dict(Being.view(s, str(c["id"]))["creature"]).is_same(c)
	assert_array(CreatureRules.here(s, s.room_id)).has_size(1)
	assert_array(CreatureRules.here(s, "elsewhere")).is_empty()
	CreatureRules.remove(s, c)
	assert_bool(s.beings.has(str(c["id"]))).is_false()


func test_the_order_of_a_room_survives_a_save() -> void:
	var s := _hero()
	for i in 12:
		CreatureRules.add(s, s.room_id, {"name": "Гоблин %d" % i, "monster": "goblin", "state": "truce", "bound": false, "led": false, "since": 0})
	var back := GameSession.from_dict(JSON.parse_string(JSON.stringify(s.to_dict(10))))
	var names: Array = CreatureRules.here(back, s.room_id).map(func(c: Dictionary) -> String: return str(c["name"]))
	assert_str(str(names[2])).is_equal("Гоблин 2")
	assert_str(str(names[11])).is_equal("Гоблин 11")


func test_a_person_knocked_out_wakes_with_its_life_whole() -> void:
	var s := _hero()
	Being.of(s, "npc_innkeeper")["attitude"] = 2
	var c := Being.put(s, "npc_innkeeper", "creature", {"name": "Бруно", "monster": "commoner", "state": "unconscious", "npc_id": "npc_innkeeper",
		"at": s.room_id, "bound": false, "led": false, "since": 0})
	assert_bool(s.held_as_creature("npc_innkeeper")).is_true()
	CreatureRules.remove(s, c)
	assert_bool(s.held_as_creature("npc_innkeeper")).is_false()
	assert_int(int(Being.view(s, "npc_innkeeper")["attitude"])).is_equal(2)


func test_a_summoned_one_has_one_record() -> void:
	var s := _hero()
	var m := Being.made(s, "summon", {"spell": "find_familiar", "monster": "owl", "name": "Сова", "until": -1, "concentration": false, "hp": 1, "helper": true})
	assert_array(AllyRules.called(s)).has_size(1)
	assert_str(AllyRules.dismiss(s, str(m["id"]))).is_empty()
	assert_array(s.beings.keys()).is_equal([Being.HERO])


func test_a_fighter_is_the_record_with_its_id() -> void:
	var s := _hero()
	var id := str(CreatureRules.add(s, s.room_id, {"name": "Гоблин", "monster": "goblin", "state": "truce", "bound": false, "led": false, "since": 0, "hp": 3, "max_hp": 7})["id"])
	CreatureRules.act(s, data, id, "attack")
	TestUtils.fight(s, data, s.pending_fight, {})
	assert_array(CombatRules.enemies(s)).contains_exactly([id])
	assert_dict(CombatRules.fighter(s, id)).is_same(Being.view(s, id)["fight"])
	assert_int(int(CombatRules.fighter(s, id)["hp"])).is_equal(3)


func test_an_npc_fights_under_its_own_id() -> void:
	var s := _hero()
	TestUtils.fight(s, data, [{"monster": "commoner", "name": "Бруно", "npc_id": "npc_innkeeper"}], {})
	assert_array(CombatRules.enemies(s)).contains_exactly(["npc_innkeeper"])
	CombatRules.close(s)
	assert_array(s.beings.keys()).is_equal([Being.HERO])


func test_the_beaten_foe_stays_the_same_character() -> void:
	var s := _hero()
	TestUtils.fight(s, data, [{"monster": "goblin", "name": "Гоблин"}], {})
	var id := TestUtils.foe(s, 1)
	CombatRules.fighter(s, id)["status"] = "surrendered"
	s.combat["outcome"] = "victory"
	CreatureRules.after_fight(s, data, s.room_id)
	CombatRules.close(s)
	assert_str(str(CreatureRules.here(s, s.room_id)[0]["id"])).is_equal(id)
	assert_bool(Being.view(s, id).has("fight")).is_false()


func test_a_fight_leaves_no_one_it_did_not_keep() -> void:
	var s := _hero()
	TestUtils.fight(s, data, [{"monster": "goblin", "name": "Гоблин", "count": 2}], {})
	for id: String in CombatRules.enemies(s):
		CombatRules.fighter(s, id)["status"] = "dead"
	CombatRules.close(s)
	assert_array(s.beings.keys()).is_equal([Being.HERO])
	assert_dict(s.combat).is_empty()


func test_an_encounter_makes_its_heads_once() -> void:
	var s := _hero()
	var heads := EncounterRules.heads(s, data, s.room_id, _wolves())
	assert_array(heads.map(func(b: Dictionary) -> String: return str(b["name"]))).contains_exactly(["Волк 1", "Волк 2", "Гоблин"])
	assert_array(EncounterRules.heads(s, data, s.room_id, _wolves()).map(func(b: Dictionary) -> String: return str(b["id"]))) \
		.contains_exactly(heads.map(func(b: Dictionary) -> String: return str(b["id"])))


func test_foes_left_behind_keep_their_dead_and_wounds() -> void:
	var s := _hero()
	var heads := EncounterRules.heads(s, data, s.room_id, _wolves())
	TestUtils.fight(s, data, heads, {"encounter": "t_wolves"})
	var ids := CombatRules.enemies(s, false)
	CombatRules.fighter(s, ids[0])["status"] = "dead"
	CombatRules.fighter(s, ids[1])["hp"] = 2
	CombatRules.close(s)
	var left := EncounterRules.heads(s, data, s.room_id, _wolves())
	assert_int(left.size()).is_equal(2)
	assert_int(int(Being.view(s, ids[1])["hp"])).is_equal(2)
	TestUtils.fight(s, data, left, {"encounter": "t_wolves"})
	assert_int(int(CombatRules.fighter(s, ids[1])["hp"])).is_equal(2)
	AllyRules.rest(s)
	assert_bool(Being.view(s, ids[1]).has("hp")).is_false()


func test_captors_are_the_foes_of_the_fight() -> void:
	var s := _hero()
	TestUtils.fight(s, data, [{"monster": "bandit", "name": "Разбойник"}], {})
	var id := TestUtils.foe(s, 1)
	CombatRules.fighter(s, id)["hp"] = 4
	EncounterRules.capture(s, [id], "", "pushcha-edge")
	CombatRules.close(s)
	assert_str(str(EncounterRules.captors(s)[0]["name"])).is_equal("Разбойник")
	assert_int(int(Being.view(s, id)["hp"])).is_equal(4)


func test_a_fight_comes_back_from_a_save() -> void:
	var s := _hero()
	TestUtils.fight(s, data, [{"monster": "goblin", "name": "Гоблин"}], {})
	var back := GameSession.from_dict(JSON.parse_string(JSON.stringify(s.to_dict(10))))
	assert_array(CombatRules.enemies(back)).contains_exactly(CombatRules.enemies(s))
	assert_int(typeof(CombatRules.fighter(back, TestUtils.foe(back, 1))["hp"])).is_equal(TYPE_INT)
	assert_array(Being.check(back)).is_empty()


func test_the_form_of_a_record_is_declared() -> void:
	var s := _hero()
	Being.of(s, "npc_innkeeper")["atitude"] = 1
	Being.of(s, "npc_merchant")["hp"] = "три"
	CreatureRules.add(s, s.room_id, {"name": "Гоблин", "monster": "goblin", "state": "truce", "bond": true})
	var found := Being.check(s)
	assert_int(found.size()).is_equal(3)
	assert_str(found[0]).contains("atitude")
	assert_str(found[2]).contains("bond")
