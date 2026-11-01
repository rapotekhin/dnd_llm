extends GdUnitTestSuite
## One sheet for everybody (v0.8.4.6, ADR-0016): the hero is a record, any character reads the same numbers by one road.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func test_the_hero_is_a_record_and_its_sheet_is_the_character() -> void:
	var s := TestUtils.new_session()
	assert_bool(is_same(s.character, s.beings[Being.HERO]["sheet"])).is_true()
	s.character["hp"] = 3
	assert_int(int(s.beings[Being.HERO]["sheet"]["hp"])).is_equal(3)
	assert_array(Being.check(s)).is_empty()


func test_the_hero_comes_back_from_a_save_as_a_record() -> void:
	var s := TestUtils.new_session()
	s.character["needs"] = {"food": {"level": 50.5, "at": 0}, "water": {"level": 100.0, "at": 0}, "done": {}}
	Being.of(s, "bruno")["attitude"] = 2
	var back := GameSession.from_dict(JSON.parse_string(JSON.stringify(s.to_dict(10))))
	assert_str(str(back.character["name"])).is_equal(str(s.character["name"]))
	assert_float(float(back.character["needs"]["food"]["level"])).is_equal(50.5)
	assert_int(int(Being.view(back, "bruno")["attitude"])).is_equal(2)
	assert_bool(s.to_dict(10).has("character")).is_false()


func test_the_hero_stays_when_a_fight_ends() -> void:
	var s := TestUtils.new_session()
	TestUtils.fight(s, data, [{"monster": "goblin", "col": 1}])
	assert_bool(s.beings[Being.HERO].has("fight")).is_true()
	CombatRules.close(s)
	assert_bool(s.beings[Being.HERO].has("fight")).is_false()
	assert_str(str(s.character["name"])).is_not_empty()


func test_every_template_gives_a_sheet_in_the_hero_form() -> void:
	var s := TestUtils.new_session()
	for id: String in data["monsters"]:
		var m: Dictionary = data["monsters"][id]
		var sheet := Sheet.of(s, data, {"monster": id})
		for key: String in ["abilities", "saves", "skills", "passive_perception", "prof_bonus"]:
			assert_bool(s.character.has(key)).override_failure_message(key).is_true()
			assert_bool(sheet.has(key)).override_failure_message("%s: %s" % [id, key]).is_true()
		for ab: String in CharacterRules.ABILITIES:
			var want := int(m["saves"].get(ab, CharacterRules.mod(int(m["abilities"][ab]))))
			assert_int(Sheet.save_bonus(s, data, {"monster": id}, ab)).override_failure_message("%s: %s" % [id, ab]).is_equal(want)
		for sk: String in m["skills"]:
			assert_int(Sheet.skill(s, data, {"monster": id}, sk)).override_failure_message("%s: %s" % [id, sk]).is_equal(int(m["skills"][sk]))


func test_a_person_of_the_pack_without_a_template_is_the_default_one() -> void:
	var fallback := str(CombatRules.cfg(data)["default_npc_monster"])
	assert_str(Sheet.template_id(data, {})).is_equal(fallback)
	assert_str(Sheet.template_id(data, Sheet.HERO)).is_empty()
	assert_dict(Sheet.template(data, Sheet.HERO)).is_empty()


func test_a_fighter_without_its_weapon_has_only_what_is_left() -> void:
	var m := Sheet.template(data, {"monster": "goblin", "actions": []})
	assert_array(m["actions"]).is_empty()
	assert_array(data["monsters"]["goblin"]["actions"]).is_not_empty()


func test_passive_perception_is_one_number_on_every_road() -> void:
	var s := TestUtils.new_session()
	for id: String in data["monsters"]:
		var by_sheet := Sheet.passive(s, data, {"monster": id})
		assert_int(EncounterRules.best_passive(s, data, [{"monster": id}])).override_failure_message(id).is_equal(by_sheet)
	var npc: Dictionary = data["world"]["npcs"].values()[0]
	var npc_id: String = data["world"]["npcs"].keys()[0]
	assert_int(TheftRules.passive(s, data, npc_id)).is_equal(Sheet.passive(s, data, npc))


func test_keen_senses_count_for_a_wolf_on_every_road() -> void:
	var s := TestUtils.new_session()
	var want := int(data["monsters"]["wolf"]["passive_perception"]) + 5
	assert_int(EncounterRules.best_passive(s, data, [{"monster": "wolf"}])).is_equal(want)


func test_the_hero_sneaking_notices_less_on_every_road() -> void:
	var s := TestUtils.new_session()
	var open := Sheet.passive(s, data, Sheet.HERO)
	s.sneaking = true
	assert_int(Sheet.passive(s, data, Sheet.HERO)).is_equal(open - ExplorationRules.SNEAK_PASSIVE_PENALTY)


func test_a_foe_and_the_hero_save_by_one_road() -> void:
	var s := TestUtils.new_session()
	var foe := {"monster": "goblin", "conditions": [], "effects": []}
	for who: Dictionary in [Sheet.HERO, foe]:
		var r := Sheet.save(s, data, who, "dex", 1)
		assert_bool(r.has("text")).is_true()
		assert_int(int(r["total"]) - int(r["nat"])).is_greater_equal(-5)
		assert_bool(Sheet.saved(s, data, who, "dex", 100)).is_false()


func test_magic_resistance_gives_a_foe_the_advantage_on_its_save() -> void:
	var s := TestUtils.new_session()
	var id := ""
	for m: String in data["monsters"]:
		if (data["monsters"][m]["traits"] as Array).any(func(t: Dictionary) -> bool: return str(t.get("id")) == "magic_resistance"):
			id = m
			break
	assert_str(id).is_not_empty()
	var foe := {"monster": id, "conditions": [], "effects": []}
	assert_array(Sheet._advantages(s, data, foe, "wis", "magic")).is_not_empty()
	assert_array(Sheet._advantages(s, data, foe, "wis", "")).is_empty()


func test_a_paralysed_one_fails_a_dex_save_whoever_it_is() -> void:
	var s := TestUtils.new_session()
	var foe := {"monster": "goblin", "conditions": [], "effects": []}
	ConditionRules.add_effect(foe, {"condition": "paralyzed"})
	ConditionRules.add_effect(s.character, {"condition": "paralyzed"})
	for who: Dictionary in [Sheet.HERO, foe]:
		assert_bool(Sheet.saved(s, data, who, "dex", 1)).is_false()


func test_damage_goes_by_one_road() -> void:
	var s := TestUtils.new_session()
	assert_int(Sheet.taken(s, data, Sheet.HERO, "fire", 10)).is_equal(10)
	s.character["effects"].append({"source": {"name": "Защита"}, "resist": ["fire"]})
	var hero := Sheet.damage(s, data, Sheet.HERO, "fire", 10)
	assert_int(int(hero["damage"])).is_equal(5)
	assert_str(str(hero["note"])).contains("Защита")
	assert_int(Sheet.taken(s, data, {"monster": "skeleton", "effects": []}, "poison", 10)).is_equal(0)
	assert_int(Sheet.taken(s, data, {"monster": "skeleton", "effects": []}, "bludgeoning", 10)).is_equal(20)
	assert_int(Sheet.taken(s, data, {"monster": "goblin", "effects": [{"resist": ["fire"]}]}, "fire", 10)).is_equal(5)


func test_ac_and_speed_read_one_way() -> void:
	var s := TestUtils.new_session()
	assert_int(Sheet.ac(s, Sheet.HERO)).is_equal(int(s.character["ac"]))
	assert_int(Sheet.speed(s, data, Sheet.HERO)).is_equal(int(s.character["speed"]))
	var f := {"monster": "goblin", "ac": 13, "effects": [{"ac": 2}], "conditions": [], "cover": 2}
	assert_int(Sheet.ac(s, f)).is_equal(17)
	assert_int(Sheet.speed(s, data, f)).is_equal(30)
	f["conditions"] = ["slowed_spell"]
	assert_int(Sheet.speed(s, data, f)).is_equal(15)


func test_contests_and_talk_read_the_same_sheet() -> void:
	var npc_id: String = data["world"]["npcs"].keys()[0]
	var npc: Dictionary = data["world"]["npcs"][npc_id]
	var sheet := Sheet.of(null, data, npc)
	assert_int(int(ContestRules.npc_bonus(data, npc_id, {"skill": "insight"})["bonus"])).is_equal(int(sheet["skills"]["insight"]))
	var skill: String = (SocialRules.cfg(data)["contests"] as Dictionary).keys()[0]
	assert_dict(SocialRules.resistance(data, npc, skill)).is_not_empty()
