extends GdUnitTestSuite
## The abilities found partial by the hand review of v0.8.4.33, the fight's first: Dueling keeps a versatile weapon in one
## hand, Colossus Slayer reads the wound before the blow, Giant Killer answers a miss too, Frenzy's exhaustion comes when the
## rage ends for anybody, the metamagic as the 5e text says, Cutting Words for an ally, a race's spells by its own ability.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _hero(preset: String, level: int = 1, change: Dictionary = {}) -> GameSession:
	var s := TestUtils.new_session()
	for p: Dictionary in data["presets"]:
		if p["id"] == preset:
			var q: Dictionary = p.duplicate(true)
			(q["choices"] as Dictionary).merge(change, true)
			s.character = GameSession.normalized_character(CharacterBuilder.build_preset(q, data))
	while int(s.character["level"]) < level:
		s.character["xp"] = LevelUp.xp_for(data, int(s.character["level"]) + 1)
		LevelUp.apply(s.character, data, LevelUp.default_picks(s.character, data))
	CharacterRules.refresh(s.character, data, s.items)
	s.character["hp"] = int(s.character["max_hp"])
	return s


func test_dueling_keeps_a_versatile_weapon_in_one_hand() -> void:
	var s := _hero("fighter_aira")
	var c := s.character
	ItemRules.add(c, "longsword", 1)
	c["equipped"]["main_hand"] = "longsword"
	c["equipped"]["shield"] = ""
	c["equipped"]["off_hand"] = ""
	c["features"] = (c["features"] as Array).filter(func(f: Variant) -> bool: return not str(f).contains("fighting_style"))
	CharacterRules.refresh(c, data, s.items)
	var plain := CombatRules.weapon_profile(c, data, s.items, "longsword")
	assert_str(str(plain["dice"])).is_equal("1d10")
	(c["features"] as Array).append("fighter_fighting_style_dueling")
	var duel := CombatRules.weapon_profile(c, data, s.items, "longsword")
	assert_str(str(duel["dice"])).is_equal("1d8")
	assert_int(int(duel["bonus"])).is_equal(int(plain["bonus"]) + 2)
	assert_bool(CharacterRules.two_hand_grip(c, data, s.items)).is_false()


func test_colossus_slayer_reads_the_wound_before_the_blow() -> void:
	var s := _hero("ranger_velena", 3)
	(s.character["features"] as Array).append("hunters_prey_colossus_slayer")
	TestUtils.fight(s, data, [{"monster": "ogre", "col": 3}])
	var foe := CombatRules.fighter(s, str(CombatRules.enemies(s)[0]))
	var hero := CombatRules.player(s)
	foe["hp"] = int(foe["max_hp"]) - 5  # the blow itself has hurt it
	assert_str(str(FeatureRules.hit_extras(s, data, hero, {"wounded": false}, foe, false)["dice"])).is_empty()
	assert_str(str(FeatureRules.hit_extras(s, data, hero, {"wounded": true}, foe, false)["dice"])).is_equal("1d8")


func test_giant_killer_answers_a_large_foe_beside() -> void:
	var s := _hero("ranger_velena", 3)
	(s.character["features"] as Array).append("hunters_prey_giant_killer")
	TestUtils.fight(s, data, [{"monster": "ogre", "col": 3}])
	var foe := CombatRules.fighter(s, str(CombatRules.enemies(s)[0]))
	var hero := CombatRules.player(s)
	TestUtils.beside(s, foe)
	assert_bool(FeatureRules.giant_killer(s, data, hero, foe)).is_true()
	hero["reacted"] = true
	assert_bool(FeatureRules.giant_killer(s, data, hero, foe)).is_false()


func test_a_frenzy_costs_exhaustion_when_the_rage_ends() -> void:
	var s := _hero("barbarian_urga", 3)
	TestUtils.fight(s, data, [{"monster": "goblin", "col": 3}])
	var hero := CombatRules.player(s)
	hero["raging"] = true
	hero["frenzy"] = true
	var lines: Array[String] = []
	FeatureRules.end_turn(s, data, hero, lines)  # no blow, no wound: the rage ends
	assert_bool(hero.has("raging") and bool(hero["raging"])).is_false()
	assert_int(ConditionRules.exhaustion(s.character)).is_equal(1)
	assert_bool(hero.has("frenzy")).is_false()


func test_empowered_rerolls_the_worst_dice() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var plain := 0
	var power := 0
	for i in 2000:
		plain += CombatRules.roll_dice(rng, "8d6")
		power += CombatRules.roll_dice(rng, "E3:8d6")
	assert_float(power / 2000.0).is_greater(plain / 2000.0 + 1.5)


func test_extended_doubles_a_minute_or_more_and_distant_makes_a_touch_30_ft() -> void:
	var s := _hero("sorcerer_zlata", 3)
	TestUtils.fight(s, data, [{"monster": "goblin", "col": 3}])
	var base := ConditionRules.spell_rounds(data, "bless", s)
	s.combat["meta_now"] = "extended_spell"
	assert_int(ConditionRules.spell_rounds(data, "bless", s)).is_equal(base * 2)
	s.combat["meta_now"] = ""
	CombatRules.player(s)["metamagic"] = "distant_spell"
	(s.character["features"] as Array).append("metamagic_distant_spell")
	assert_int(CombatRules.spell_range(s, data, "shocking_grasp")).is_equal(30)
	assert_int(CombatRules.spell_range(s, data, "fire_bolt")).is_equal(240)


func test_heightened_falls_on_one_target_only() -> void:
	var s := _hero("sorcerer_zlata", 3)
	TestUtils.fight(s, data, [{"monster": "goblin", "col": 3}])
	s.combat["meta_now"] = "heightened_spell"
	assert_bool(CombatRules._heighten(s)).is_true()
	assert_bool(CombatRules._heighten(s)).is_false()


func test_cutting_words_turn_a_blow_at_an_ally() -> void:
	var s := _hero("bard_yas", 3)
	(s.character["features"] as Array).append("cutting_words")
	TestUtils.fight(s, data, [{"monster": "goblin", "col": 3}], {"allies": [{"monster": "commoner", "name": "Друг"}]})
	var ally := {}
	for id: String in s.combat["order"]:
		if str(CombatRules.fighter(s, id).get("side")) == "ally":
			ally = CombatRules.fighter(s, id)
	var foe := CombatRules.fighter(s, str(CombatRules.enemies(s)[0]))
	var left := Stock.left(s.character, data, "bardic_inspiration")
	var lines: Array[String] = []
	TestUtils.beside(s, foe)
	assert_bool(Attack._words_for(s, data, foe, ally, 12, 12, lines)).is_true()  # any die takes a bare hit off
	assert_int(Stock.left(s.character, data, "bardic_inspiration")).is_equal(left - 1)
	assert_bool(bool(CombatRules.player(s)["reacted"])).is_true()


func test_infernal_legacy_casts_hellish_rebuke_from_level_three_by_charisma() -> void:
	var low := _hero("rogue_damir", 1)
	assert_bool(SpellRules.is_free(low.character, "hellish_rebuke")).is_false()
	var s := _hero("rogue_damir", 3)
	var c := s.character
	assert_bool(SpellRules.free_now(c, data, "hellish_rebuke")).is_true()
	assert_int(SpellEffects.reaction_slot(c, data, "hellish_rebuke")).is_equal(2)
	assert_str(str(ActionRules.numbers(s, data, "hellish_rebuke").get("ability", ""))).is_equal("cha")
	assert_bool(SpellRules.is_free(c, "darkness")).is_false()  # from level 5


func test_a_high_elf_casts_its_cantrip_by_intelligence() -> void:
	var s := _hero("fighter_aira", 1, {"race": "elf", "subrace": "high_elf", "race_cantrips": ["fire_bolt"], "languages": ["dwarvish"]})
	assert_array(SpellRules.ready(s.character)).contains(["fire_bolt"])
	assert_str(str(ActionRules.numbers(s, data, "fire_bolt").get("ability", ""))).is_equal("int")
