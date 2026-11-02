extends GdUnitTestSuite
## v0.8.4.14, ADR-0016: one check of anybody (Roll.check with CheckEngine.situation), the chance a window shows from the
## same spec, the saves of NPCs by Sheet.save, the contests of a grapple on one road.

var data: Dictionary


func before() -> void:
	data = TestUtils.data()


func test_a_foe_rolls_with_its_statuses() -> void:
	var s := TestUtils.new_session()
	TestUtils.fight(s, data, [{"monster": "goblin", "col": 4}])
	var f := CombatRules.fighter(s, TestUtils.foe(s, 1))
	ConditionRules.add_effect(f, {"condition": "poisoned", "source": {"kind": "engine", "name": "тест"}})
	var r := Roll.check(s, data, f, {"skill": "athletics", "dc": 10})
	assert_array(r["dis"]).contains(["отравлен"])
	assert_int((r["rolls"] as Array).size()).is_equal(2)


func test_the_lock_pick_card_carries_the_heros_statuses() -> void:
	var s := TestUtils.new_session()
	ConditionRules.add(s.character, "poisoned", "short_rest")
	var r := CheckEngine.card(s, data, {"skill": "sleight_of_hand", "dc_tier": "medium", "dc": 12})
	assert_str(str(r["disadvantage_reason"])).contains("отравлен")


func test_the_shown_chance_is_the_rolls_own() -> void:
	var s := TestUtils.new_session()
	var p := {"skill": "persuasion", "dc_tier": "medium"}
	var clean := int(CheckEngine.preview(s, data, p)["chance"])
	ConditionRules.add(s.character, "poisoned", "short_rest")
	var sick := int(CheckEngine.preview(s, data, p)["chance"])
	assert_int(sick).is_less(clean)
	assert_int(sick).is_equal(Roll.chance(int(CheckEngine.preview(s, data, p)["bonus"]), 15, false, true))


func test_a_peek_does_not_spend_guidance() -> void:
	var s := TestUtils.new_session()
	ConditionRules.add_effect(s.character, {"die": "1d4", "on": ["check"], "once": true, "source": {"kind": "spell", "id": "guidance", "name": "Указание"}})
	var bonus := int(Roll.odds(s, data, Sheet.HERO, {"skill": "arcana"})["bonus"])
	assert_int(bonus).is_equal(Sheet.skill(s, data, Sheet.HERO, "arcana") + DifficultyRules.bonus(s, data) + 3)  # the mean of 1d4, rounded
	assert_int(int(SpellEffects.die(s, s.character, "check", true)["bonus"])).is_equal(3)
	var r := Roll.hero(s, data, {"skill": "arcana", "dc": 10})
	assert_str(str(r["parts"])).contains("Указание")
	assert_int(int(SpellEffects.die(s, s.character, "check", true)["bonus"])).is_equal(0)


func test_armour_hinders_any_stealth_check() -> void:
	var s := TestUtils.new_session()
	s.character["equipped"]["armor"] = "chain_mail"
	var r := CheckEngine.card(s, data, {"skill": "stealth", "dc_tier": "medium"})
	assert_str(str(r.get("disadvantage_reason", ""))).contains("доспех")
	assert_str(str(CombatRules.stealth_roll(s, data)["note"])).contains("доспех")


func test_a_held_foe_does_not_resist_a_grapple() -> void:
	var s := TestUtils.new_session()
	TestUtils.fight(s, data, [{"monster": "ogre", "col": 0}])
	var f := CombatRules.fighter(s, TestUtils.foe(s, 1))
	ConditionRules.add_effect(f, {"condition": "paralyzed", "source": {"kind": "engine", "name": "тест"}})
	var c := CombatRules.contest(s, data, CombatRules.player(s), "athletics", f, ["athletics", "acrobatics"])
	assert_int(int(c["theirs"])).is_equal(0)


func test_an_npc_resists_a_charm_by_its_own_save() -> void:
	var s := TestUtils.new_session()
	s.character["spell_dc"] = 1
	var r := SpellEffects.npc_save(s, data, "suggestion", "npc_innkeeper")
	assert_str(str(r["line"])).contains("против Сл 1")


func test_the_master_s_save_goes_by_sheet_save() -> void:
	var s := TestUtils.new_session()
	ConditionRules.add(s.character, "paralyzed", "long_rest")
	var r := CheckEngine.card(s, data, {"save": "str", "dc_tier": "very_easy"})
	assert_bool(bool(r["success"])).is_false()
	assert_str(str(r["auto_fail_reason"])).contains("парализ")
