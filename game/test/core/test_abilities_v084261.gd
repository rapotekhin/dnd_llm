extends GdUnitTestSuite
## Abilities off the master's words (roadmap v0.8.4.26.1): a land's circle spells, an invocation once a long rest, a check by
## its subject, Flexible Casting by its features, Protection, Halfling Nimbleness, Slow Fall, Second-Story Work, Evocation
## Savant, One with Shadows, Primeval Awareness.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _hero(cls: String, level: int, features: Array = [], traits: Array = []) -> GameSession:
	var s := ChecklistProbe.session(data)
	var c := s.character
	c["class"] = cls
	c["level"] = level
	(c["features"] as Array).append_array(features)
	(c["traits"] as Array).append_array(traits)
	CharacterRules.refresh(c, data, s.items)
	return s


func test_a_land_gives_its_circle_spells_by_level() -> void:
	var s := _hero("druid", 3, ["circle_of_the_land_forest"])
	s.character["subclass"] = "land"
	assert_array(LevelUp.always(s.character, data, 3)).contains_exactly_in_any_order(["barkskin", "spider_climb"])
	assert_array(LevelUp.always(s.character, data, 5)).contains(["call_lightning", "plant_growth"])


func test_an_invocation_casts_its_spell_once_a_long_rest() -> void:
	var s := _hero("warlock", 5, ["eldritch_invocation_mire_the_mind"])
	var c := s.character
	assert_bool(SpellRules.is_free(c, "slow")).is_true()
	assert_str(SpellRules.stock_of(c, data, "slow")).is_equal("invocation_mire_the_mind")
	var chk := SpellRules.check(c, data, "slow", 0)
	assert_int(int(chk.get("slot", -1))).is_equal(0)
	SpellRules.cast(c, data, "slow", 0, s)
	assert_int(Stock.left(c, data, "invocation_mire_the_mind")).is_equal(0)
	assert_bool(SpellRules.free_now(c, data, "slow")).is_false()
	assert_str(str(SpellRules.check(c, data, "slow", 0).get("reason", ""))).contains("заряды кончились")
	Stock.recharge_all(c, data, "long")
	assert_bool(SpellRules.free_now(c, data, "slow")).is_true()


func test_a_favored_enemy_gives_advantage_by_the_subject() -> void:
	var s := _hero("ranger", 1, ["favored_enemy_undead"])
	var at := CheckEngine.situation(s, data, Sheet.HERO, {"skill": "religion", "about": "undead"})
	assert_array(at["adv"]).contains(["Любимый враг: нежить"])
	assert_array(CheckEngine.situation(s, data, Sheet.HERO, {"skill": "religion", "about": "beast"})["adv"]).is_empty()
	assert_array(LanguageRules.hero(s.character, data)).contains(["abyssal"])


func test_a_favored_enemy_reads_the_target_of_the_check() -> void:
	var s := _hero("ranger", 1, ["favored_enemy_humanoid"])
	var g := ChecklistProbe.fight(s, data, "goblin")
	assert_str(CheckEngine.about_of(s, data, {"target_id": str(g["id"])})).is_equal("humanoid")
	assert_array(CheckEngine.situation(s, data, Sheet.HERO, {"skill": "arcana", "target_id": str(g["id"])})["adv"]).is_not_empty()


func test_stonecunning_counts_the_proficiency_twice() -> void:
	var s := _hero("fighter", 1, [], ["stonecunning"])
	var c := s.character
	c["skill_profs"] = (c["skill_profs"] as Array).filter(func(x: Variant) -> bool: return str(x) != "history")
	var pb := CharacterRules.prof_bonus(c, data)
	var parts: Array = CheckEngine.situation(s, data, Sheet.HERO, {"skill": "history", "about": "stonework"})["parts"]
	assert_int(RollParts.sum(parts)).is_equal(2 * pb)
	assert_int(RollParts.sum(CheckEngine.situation(s, data, Sheet.HERO, {"skill": "history", "about": "dragon"})["parts"])).is_equal(0)


func test_a_dragon_ancestor_speaks_draconic() -> void:
	var s := _hero("sorcerer", 1, ["dragon_ancestor_red___fire_damage"])
	assert_array(LanguageRules.hero(s.character, data)).contains(["draconic"])


func test_flexible_casting_follows_its_features() -> void:
	var s := _hero("sorcerer", 2, ["font_of_magic"])
	var c := s.character
	Stock.spend(c, "slot_1")
	assert_array(FeatureRules.font_options(c, data)).is_empty()
	(c["features"] as Array).append_array(["flexible_casting_creating_spell_slots", "flexible_casting_converting_spell_slot"])
	assert_bool(FeatureRules.font_options(c, data).any(func(o: Dictionary) -> bool: return str(o["id"]) == "slot_1")).is_true()


func test_protection_imposes_disadvantage_for_a_friend() -> void:
	var s := _hero("fighter", 1, ["fighter_fighting_style_protection"])
	var c := s.character
	Gear.give(s, data, Being.HERO, "shield", 1)
	c["equipped"]["off_hand"] = "shield"
	CharacterRules.refresh(c, data, s.items)
	var ally := ChecklistProbe.fight(s, data, "commoner", false, "ally")
	var p := CombatRules.player(s)
	FightGrid.put(ally, Vector2i(41, 30))
	var foe := CombatRules.fighter(s, CombatRules.enemies(s)[0])
	FightGrid.put(foe, Vector2i(42, 30))
	var lines: Array[String] = []
	Attack.swing(s, data, foe, ally, Attack.blade(s, data, foe), lines)
	assert_str(" ".join(lines)).contains("прикрывает щитом")
	assert_bool(bool(p.get("reacted", false))).is_true()


func test_a_halfling_walks_through_a_larger_foe() -> void:
	var s := _hero("rogue", 1, [], ["halfling_nimbleness"])
	s.character["race"] = "halfling"
	var bandit := ChecklistProbe.fight(s, data, "bandit")
	var p := CombatRules.player(s)
	assert_int(int(Move.opts(s, data, p)["larger_by"])).is_equal(1)
	assert_bool(FightGrid.passable(s, data, p, 1).has(FightGrid.cell(bandit))).is_true()
	assert_bool(FightGrid.passable(s, data, p, 2).has(FightGrid.cell(bandit))).is_false()  # small → medium: one size, only with the trait


func test_slow_fall_takes_off_the_damage() -> void:
	var s := _hero("monk", 4, ["slow_fall"])
	ChecklistProbe.fight(s, data, "goblin", true)
	var hp := int(s.character["hp"])
	var lines: Array[String] = []
	CombatRules.fall(s, data, CombatRules.player(s), "15", "падает", {"kind": "engine", "name": "падение"}, lines)
	assert_int(int(s.character["hp"])).is_equal(hp)
	assert_str(" ".join(lines)).contains("замедляет падение: −20")


func test_second_story_work_climbs_at_the_walk() -> void:
	var s := _hero("rogue", 3, ["second_story_work"])
	assert_int(int(Move.speeds(s, data, Sheet.HERO).get("climb", 0))).is_equal(int(Move.speeds(s, data, Sheet.HERO)["walk"]))
	assert_bool(ConditionRules.effects(s.character).any(func(e: Dictionary) -> bool: return int(e.get("jump_ft", -1)) >= 0)).is_true()


func test_evocation_savant_halves_an_evocation_course() -> void:
	data = TestUtils.data().duplicate(true)
	data["world"]["courses"]["arcane_signs"]["teaches"]["id"] = "magic_missile"
	var s := _hero("wizard", 2)
	var fee := StudyRules.fee(s, data, "arcane_signs")
	var lessons := StudyRules.lessons_needed(s, data, "arcane_signs")
	(s.character["features"] as Array).append("evocation_savant")
	assert_int(StudyRules.fee(s, data, "arcane_signs")).is_equal(int(fee / 2.0))
	assert_int(StudyRules.lessons_needed(s, data, "arcane_signs")).is_equal(ceili(lessons / 2.0))


func test_one_with_shadows_lasts_until_the_warlock_moves() -> void:
	var s := _hero("warlock", 5, ["eldritch_invocation_one_with_shadows"])
	var act := Acts.one("feature")
	ChecklistProbe.fight(s, data, "goblin", true)
	var p := CombatRules.player(s)
	ChecklistProbe.turn(s, data, p)
	assert_str(act.can(s, data, p, "", {"id": "one_with_shadows"})).is_equal("COMBAT_NEEDS_DARK")  # the tavern's hall by day
	s.room_id = "brod-tavern-cellar"  # a dark cellar, no light in hand
	s.character["belt"] = ["", "", "", "", ""]
	assert_str(act.can(s, data, p, "", {"id": "one_with_shadows"})).is_empty()
	act.go(s, data, p, "", {"id": "one_with_shadows"})
	assert_bool(ConditionRules.has(s.character, "invisible")).is_true()
	var lines: Array[String] = []
	Move.arrived(s, data, p, lines)
	assert_bool(ConditionRules.has(s.character, "invisible")).is_false()


func test_primeval_awareness_pays_a_slot_and_names_no_kind_when_none() -> void:
	var s := _hero("ranger", 3, ["primeval_awareness"])
	var c := s.character
	var before := Stock.left(c, data, "primeval_awareness")
	assert_int(before).is_greater(0)
	var lines := Stock.use(c, data, "primeval_awareness", 1, s.rng, s)
	assert_int(Stock.left(c, data, "primeval_awareness")).is_equal(before - 1)
	assert_str(" ".join(lines)).contains("рядом")
