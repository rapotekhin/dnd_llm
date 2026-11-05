extends GdUnitTestSuite
## One road, review 2, groups F and J (v0.8.4.29.3): the chance a window shows is the roll's own (Attack.odds, the spell's blow,
## PetRules.spec, ContestRules.settled), one count of darts, Harm.save_half and Harm.mend, one DC, one blow at a thing, one die.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _hero(preset_id: String) -> GameSession:
	var s := TestUtils.new_session()
	for p: Dictionary in data["presets"]:
		if p["id"] == preset_id:
			s.character = GameSession.normalized_character(CharacterBuilder.build_preset(p, data))
	CharacterRules.refresh(s.character, data, s.items)
	s.character["hp"] = int(s.character["max_hp"])
	return s


func test_a_weapons_window_is_the_rolls_odds() -> void:
	var s := _hero("fighter_aira")
	TestUtils.fight(s, data, [{"monster": "goblin"}], {})
	var id: String = CombatRules.enemies(s)[0]
	var t := CombatRules.fighter(s, id)
	var c := s.character
	var w := CombatRules.weapon_profile(c, data, s.items, str(c.get("equipped", {}).get("main_hand", "")))
	var odds := Attack.odds(s, data, CombatRules.player(s), t, Attack.of_weapon(w))
	assert_int(int(CombatRules.attack_preview(s, data, id)["chance"])).is_equal(int(odds["chance"]))
	assert_int(int(odds["chance"])).is_equal(Roll.chance(int(w["to_hit"]), Attack.ac_against(s, data, CombatRules.player(s), t), false, false))
	assert_bool(t.has("cover")).is_false()  # laid for the count only


func test_a_champions_19_is_in_the_chance() -> void:
	assert_int(Roll.chance(0, 30, false, false, 19)).is_equal(10)
	assert_int(Roll.chance(0, 30)).is_equal(5)


func test_a_spell_attacks_window_has_every_reason_of_the_roll() -> void:
	var s := _hero("wizard_yalika")
	TestUtils.fight(s, data, [{"monster": "goblin"}], {})
	var id: String = CombatRules.enemies(s)[0]
	ConditionRules.add_effect(CombatRules.fighter(s, id), {"condition": "invisible", "ends": {}, "source": {"kind": "spell", "name": "проба"}})
	var pv := CombatRules.cast_preview(s, data, "fire_bolt", 0, id)
	assert_array(pv["dis"]).contains(["цель невидима"])  # the hand-made window knew only three reasons


func test_one_count_of_darts() -> void:
	assert_int(SpellEffects.count(data, "magic_missile", 1, 1)).is_equal(3)
	assert_int(SpellEffects.count(data, "magic_missile", 2, 1)).is_equal(4)
	assert_int(SpellEffects.count(data, "fire_bolt", 1, 5)).is_equal(1)
	assert_int(SpellEffects.count(data, "eldritch_blast", 0, 5)).is_greater(SpellEffects.count(data, "eldritch_blast", 0, 1))


func test_a_save_for_half_is_one_road() -> void:
	var s := _hero("fighter_aira")
	TestUtils.fight(s, data, [{"monster": "ogre"}], {})
	var o := CombatRules.fighter(s, CombatRules.enemies(s)[0])
	var none := Harm.save_half(s, data, o, "", 15, [{"n": 20, "type": "fire"}])
	assert_bool(bool(none["ok"])).is_false()
	assert_int(int(none["damage"])).is_equal(20)
	for i in 20:
		var r := Harm.save_half(s, data, o, "dex", 12, [{"n": 20, "type": "fire"}, {"n": 6, "type": "cold"}])
		assert_int(int(r["damage"])).is_equal(13 if bool(r["ok"]) else 26)
		assert_bool(o.has("cover")).is_false()


func test_mend_raises_the_fallen_hero() -> void:
	var s := _hero("fighter_aira")
	TestUtils.fight(s, data, [{"monster": "goblin"}], {})
	s.character["hp"] = 0
	ConditionRules.impose(s, data, {"condition": "unconscious", "ends": {"rest": "long"}, "source": {"kind": "engine", "name": "0 HP"}})
	s.combat["death_saves"] = {"ok": 1, "fail": 2}
	assert_int(Harm.mend(s, data, Sheet.HERO, 5)).is_equal(5)
	assert_bool(ConditionRules.has(s.character, "unconscious")).is_false()
	assert_int(int(s.combat["death_saves"]["fail"])).is_equal(0)


func test_a_contests_natural_dice_in_the_core() -> void:
	assert_int(ContestRules.settled(20, 5, 30)).is_equal(31)
	assert_int(ContestRules.settled(1, 40, 10)).is_equal(9)
	assert_int(ContestRules.settled(10, 12, 15, true)).is_equal(12)
	assert_int(ContestRules.chance(0, 0)).is_between(40, 50)


func test_one_dc_of_anybody() -> void:
	var s := _hero("wizard_yalika")
	var c := s.character
	assert_int(Sheet.dc(s, data, Sheet.HERO, "int")).is_equal(8 + int(c["prof_bonus"]) + CharacterRules.mod(CharacterRules.ability(c, "int")))


func test_dice_helpers() -> void:
	assert_str(CombatRules.dice_of([2, 4, 2])).is_equal("2d4+2")
	assert_str(CombatRules.dice_of([1, 8, "level"], 3)).is_equal("1d8+3")
	assert_int(CombatRules.max_dice("2d6+3")).is_equal(15)
	assert_float(CombatRules.dice_avg("2d6")).is_equal(7.0)
	var rng := RandomNumberGenerator.new()
	for i in 30:
		assert_int(CombatRules.roll_dice(rng, "1d6", false, 0, 6)).is_between(1, 6)


func test_a_thing_shrugs_off_a_weak_blow() -> void:
	var mats: Dictionary = data["rules"]["things"]["materials"]
	for m: String in mats:
		var th := int(mats[m].get("threshold", 0))
		if th > 1:
			assert_int(ThingRules.takes(data, {"material": m}, th - 1)).is_equal(0)
			assert_int(ThingRules.takes(data, {"material": m}, th)).is_equal(th)
			return


func test_a_template_knows_its_weapons() -> void:
	assert_bool(CombatRules.weapon_proficient({}, {"category": "martial"}, "longsword")).is_true()
	assert_bool(CombatRules.weapon_proficient({"class": "wizard", "weapon_profs": ["dagger"]}, {"category": "martial"}, "longsword")).is_false()
	assert_bool(CombatRules.weapon_proficient({"class": "wizard", "weapon_profs": ["dagger"]}, {"category": "simple"}, "dagger")).is_true()
