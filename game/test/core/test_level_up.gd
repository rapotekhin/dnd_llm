extends GdUnitTestSuite
## LevelUp and XpRules (roadmap v0.5.4): thresholds, what each level brings for different classes, picks and
## their checks, HP by the average, spells; experience only from combat and pack quests.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func after_test() -> void:
	GameState.session = null
	GameState.busy_turn = ""


func _preset(id: String) -> Dictionary:
	for p: Dictionary in data["presets"]:
		if p["id"] == id:
			return CharacterBuilder.build_preset(p, data)
	assert(false, "no preset " + id)
	return {}


func _up(c: Dictionary, picks: Dictionary = {}) -> Array[String]:
	c["xp"] = maxi(int(c["xp"]), LevelUp.xp_for(data, int(c["level"]) + 1))
	var p := picks if not picks.is_empty() else LevelUp.default_picks(c, data)
	var errs := LevelUp.errors(c, data, p)
	assert_array(errs).override_failure_message("%s → %d: %s" % [c["class"], int(c["level"]) + 1, errs]).is_empty()
	return LevelUp.apply(c, data, p)


func test_thresholds_and_the_level_cap() -> void:
	var c := _preset("fighter_aira")
	assert_bool(LevelUp.can_level_up(c, data)).is_false()
	c["xp"] = 299
	assert_bool(LevelUp.can_level_up(c, data)).is_false()
	c["xp"] = 300
	assert_bool(LevelUp.can_level_up(c, data)).is_true()
	assert_int(LevelUp.xp_for(data, 5)).is_equal(6500)
	c["level"] = 5
	c["xp"] = 999999
	assert_bool(LevelUp.can_level_up(c, data)).is_false()  # the SRD slice ends at 5


func test_fighter_levels_with_average_hp_subclass_and_asi() -> void:
	var c := _preset("fighter_aira")
	var con := CharacterRules.mod(int(c["abilities"]["con"]))
	var hp := int(c["max_hp"])
	var lines := _up(c)
	assert_int(c["level"]).is_equal(2)
	assert_int(c["max_hp"]).is_equal(hp + 6 + con)
	assert_int(c["hp"]).is_equal(c["max_hp"])
	assert_array(c["features"]).contains(["action_surge_1_use"])
	assert_str(" ".join(lines)).contains("Новый уровень: 2")
	c["xp"] = 900
	assert_array(LevelUp.errors(c, data, {})).contains(["LVL_ERR_SUBCLASS"])
	_up(c, {"subclass": "champion"})
	assert_str(c["subclass"]).is_equal("champion")
	assert_array(c["features"]).contains(["improved_critical"])
	c["xp"] = 2700
	var str_before := int(c["abilities"]["str"])
	assert_array(LevelUp.errors(c, data, {})).contains(["LVL_ERR_ASI"])
	assert_array(LevelUp.errors(c, data, {"asi": {"str": 3}})).contains(["LVL_ERR_ASI"])
	assert_array(LevelUp.errors(c, data, {"asi": {"str": 1}})).contains(["LVL_ERR_ASI"])
	_up(c, {"asi": {"str": 1, "con": 1}})
	assert_int(c["abilities"]["str"]).is_equal(str_before + 1)
	_up(c)
	assert_int(c["prof_bonus"]).is_equal(3)
	assert_bool(LevelUp.can_level_up(c, data)).is_false()


func test_wizard_writes_two_spells_and_prepares_more() -> void:
	var c := _preset("wizard_yalika")
	c["xp"] = 300
	var p := LevelUp.plan(c, data)
	assert_str(p["spell_mode"]).is_equal("spellbook")
	assert_int(p["spells"]).is_equal(2)
	assert_bool(p["subclass"]).is_true()
	var known := (c["spells"]["known"] as Array).size()
	_up(c)
	assert_int((c["spells"]["known"] as Array).size()).is_equal(known + 2)
	assert_int((c["spells"]["prepared"] as Array).size()).is_equal(LevelUp.prepared_count(c, data, 2, c["abilities"]))
	assert_str(c["subclass"]).is_equal("evocation")
	_up(c)  # level 3: 2nd-circle spells open
	assert_int(LevelUp.plan(c, data)["max_spell_level"]).is_equal(2)


func test_warlock_pact_boon_and_known_spells() -> void:
	var c := _preset("warlock_fiber")
	_up(c)
	c["xp"] = 900
	var p := LevelUp.plan(c, data)
	assert_array((p["options"] as Array).map(func(o: Dictionary) -> String: return o["id"])).contains(["pact_boon"])
	assert_int(p["spells"]).is_equal(1)
	assert_int(p["max_spell_level"]).is_equal(2)
	assert_array(LevelUp.errors(c, data, {"spells": [p["spell_list"][0]]})).contains(["LVL_ERR_OPTIONS"])
	_up(c)
	assert_bool((c["features"] as Array).any(func(f: Variant) -> bool: return str(f).begins_with("pact_of_"))).is_true()
	assert_array(c["spells"]["always"]).contains(["blindness_deafness", "scorching_ray"])  # the Fiend's list


func test_bard_expertise_at_three() -> void:
	var c := _preset("bard_yas")
	_up(c)
	c["xp"] = 900
	assert_int(LevelUp.plan(c, data)["expertise"]).is_equal(2)
	assert_array(LevelUp.errors(c, data, {"subclass": "lore"})).contains(["LVL_ERR_EXPERTISE"])
	_up(c)
	assert_int((c["expertise"] as Array).size()).is_greater_equal(2)


func test_every_ready_made_character_reaches_level_five() -> void:
	for preset: Dictionary in data["presets"]:
		var c := CharacterBuilder.build_preset(preset, data)
		for i in 4:
			_up(c)
		assert_int(c["level"]).override_failure_message(preset["id"]).is_equal(5)
		assert_int(c["prof_bonus"]).is_equal(3)
		if not str(c.get("spell_ability", "")).is_empty() and not ["paladin", "ranger", "warlock"].has(str(c["class"])):
			assert_int((c["slots_max"] as Array).reduce(func(a: int, b: Variant) -> int: return a + int(b), 0)) \
				.override_failure_message(preset["id"]).is_greater(2)


func test_experience_only_from_combat_and_quests() -> void:
	assert_int(XpRules.combat_xp(data, ["1/4", "1/4", "1"])).is_equal(300)
	var fx := EffectEngine.new()
	var s := TestUtils.new_session()
	assert_bool(fx.validate(s, data, "t-1", {"kind": "xp", "amount": 300})["accepted"]).is_false()
	var lines := XpRules.award(s.character, data, 300, "бой")
	assert_str(" ".join(lines)).contains("+300 опыта").contains("можно повысить уровень")


func test_a_pack_quest_completes_once_in_its_room() -> void:
	var s := TestUtils.new_session()
	var world: Dictionary = data["world"]
	# A one-button quest (v0.5.4); the letter itself is a quest with steps since v0.6.5.
	world["quests"]["letter_to_ilva"] = {"title": "Письмо для Илвы", "description": "тест", "room": "brod-temple",
		"action": "Отдать Илве письмо Бруно", "xp": 300, "major": true, "done_text": "Илва благодарит."}  # major: class XP (v0.7.19)
	assert_array(XpRules.quests_here(s, world)).is_empty()
	assert_str(XpRules.can_complete(s, world, "letter_to_ilva")).is_equal("QUEST_WRONG_PLACE")
	s.room_id = "brod-temple"
	assert_array(XpRules.quests_here(s, world)).contains(["letter_to_ilva"])
	assert_str(XpRules.can_complete(s, world, "letter_to_ilva")).is_empty()
	var lines := XpRules.complete(s, data, "letter_to_ilva")
	assert_str(lines[0]).contains("Письмо для Илвы")
	assert_int(s.character["xp"]).is_equal(300)
	assert_str(XpRules.can_complete(s, world, "letter_to_ilva")).is_equal("QUEST_DONE")
	assert_array(XpRules.quests_here(s, world)).is_empty()
	var snap := TurnSnapshot.build(s, data, 4000)
	assert_bool(snap["quests"][0]["done"]).is_true()
	var back := GameSession.from_dict(JSON.parse_string(JSON.stringify(s.to_dict(500))))
	assert_array(back.quests_done).is_equal(["letter_to_ilva"])


func test_game_state_levels_up_and_refuses_while_busy() -> void:
	var s := TestUtils.new_session()
	GameState.start(s)
	s.character["xp"] = 300
	var picks := LevelUp.default_picks(s.character, Catalog.data)
	GameState.busy_turn = "t-1"
	assert_str(GameState.level_up(picks)).is_equal("LVL_ERR_BUSY")
	GameState.busy_turn = ""
	assert_str(GameState.level_up(picks)).is_empty()
	assert_int(s.character["level"]).is_equal(2)
	assert_str(GameState.level_up(picks)).is_equal("LVL_ERR_NOT_READY")


func test_b5_b7_new_characters_start_at_zero_and_cleric_slots_grow() -> void:
	var c := _preset("cleric_branko")
	assert_int(c["xp"]).is_equal(0)
	var slots := (c["slots_max"] as Array).duplicate()
	_up(c)
	assert_int(int(c["slots_max"][0])).is_greater(int(slots[0]))
	assert_int((c["spells"]["prepared"] as Array).size()).is_equal(LevelUp.prepared_count(c, data, 2, c["abilities"]))
