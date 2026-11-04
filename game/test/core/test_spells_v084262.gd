extends GdUnitTestSuite
## Spells off the master's words (roadmap v0.8.4.26.2): ways of moving by a spell's row, Jump, beast speech, Feather Fall
## as a fall's reaction, water made and cleaned, food fresh again, the sense of kinds, sickness seen, a far place seen,
## Sleet Storm and Plant Growth as zones.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _caster(id: String) -> GameSession:
	return ChecklistProbe.caster_session(data, id)


func _cast(s: GameSession, id: String) -> Array[String]:
	var chk := SpellRules.check(s.character, data, id, 0)
	return SpellRules.cast(s.character, data, str(chk["spell_id"]), int(chk["slot"]), s, true)


func test_spider_climb_and_water_walk_move_at_the_walk() -> void:
	var s := _caster("spider_climb")
	_cast(s, "spider_climb")
	var walk := int(Move.speeds(s, data, Sheet.HERO)["walk"])
	assert_int(int(Move.speeds(s, data, Sheet.HERO).get("climb", 0))).is_equal(walk)
	StudyRules.learn_spell(s.character, "water_walk")
	_cast(s, "water_walk")
	assert_int(int(Move.speeds(s, data, Sheet.HERO).get("water_walk", 0))).is_equal(walk)
	assert_bool(int(Move.opts(s, data, Sheet.HERO)["on"]) & FightGrid.WET != 0).is_true()


func test_jump_triples_the_leap() -> void:
	var s := _caster("jump")
	ChecklistProbe.fight(s, data, "goblin", true)
	var p := CombatRules.player(s)
	ChecklistProbe.turn(s, data, p)
	var before: int = Acts.one("jump").call("_reach", s, data, p)
	_cast(s, "jump")
	assert_int(Acts.one("jump").call("_reach", s, data, p)).is_greater(before)


func test_speak_with_animals_lets_a_beast_understand() -> void:
	var s := _caster("speak_with_animals")
	var wolf := ChecklistProbe.fight(s, data, "wolf")
	assert_bool(LanguageRules.foe_understands(s.character, data, wolf)).is_false()
	_cast(s, "speak_with_animals")
	assert_bool(LanguageRules.foe_understands(s.character, data, wolf)).is_true()
	assert_array(CheckEngine.situation(s, data, Sheet.HERO, {"skill": "animal_handling"})["adv"]).is_not_empty()


func test_feather_fall_takes_the_whole_fall_for_a_slot() -> void:
	var s := _caster("feather_fall")
	Cheats.toggle(s.character, "slots")  # real slots
	ChecklistProbe.fight(s, data, "goblin", true)
	var hp := int(s.character["hp"])
	var left := SpellRules.slots_left(s.character, 1)
	var lines: Array[String] = []
	CombatRules.fall(s, data, CombatRules.player(s), "20", "падает", {"kind": "engine", "name": "падение"}, lines)
	assert_int(int(s.character["hp"])).is_equal(hp)
	assert_int(SpellRules.slots_left(s.character, 1)).is_equal(left - 1)


func test_create_water_fills_and_purify_cleans() -> void:
	var s := _caster("create_or_destroy_water")
	var c := s.character
	LiquidRules.drain(c)
	_cast(s, "create_or_destroy_water")
	assert_float(LiquidRules.pints(c, data)).is_greater(0.0)
	LiquidRules.drain(c)
	LiquidRules.fill(c, data, true)
	assert_bool(LiquidRules.carried(c, data).any(func(v: Dictionary) -> bool: return v["liquid"] == LiquidRules.FOUL)).is_true()
	StudyRules.learn_spell(c, "purify_food_and_drink")
	_cast(s, "purify_food_and_drink")
	assert_bool(LiquidRules.carried(c, data).any(func(v: Dictionary) -> bool: return v["liquid"] == LiquidRules.FOUL)).is_false()


func test_detect_poison_and_disease_names_what_incubates() -> void:
	var s := _caster("detect_poison_and_disease")
	var ill := str(DiseaseRules.all(s, data).keys()[0])
	DiseaseRules.contract(s, data, ill)
	assert_str(" ".join(_cast(s, "detect_poison_and_disease"))).contains("зреет болезнь")


func test_clairvoyance_sees_beyond_an_exit() -> void:
	var s := _caster("clairvoyance")
	var at := PetRules.scout_targets(s, data)
	assert_array(at).is_not_empty()
	assert_str(" ".join(_cast(s, "clairvoyance"))).contains("незримый глаз")
	assert_bool(Knows.has(s, Knows.SCOUTED, at[0])).is_true()


func test_sleet_storm_and_plant_growth_lay_zones() -> void:
	for id: String in ["sleet_storm", "plant_growth"]:
		assert_str(ActionRules.way(data, id, true)).is_equal("sustained")
		assert_bool(bool(SpellEffects.sustained(data, id).get("slow", false))).is_true()
