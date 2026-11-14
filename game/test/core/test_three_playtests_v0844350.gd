extends GdUnitTestSuite
## v0.8.4.43.50: the causes of three live playtests red since v0.8.4.43.48 (webs, spell_targets, meeting).
## A giant spider's poison goes by the one road of damage (Harm.take): the console's immortality, temporary hit points and
## a beast form take it first, and at 0 HP it leaves anybody stable, poisoned and paralysed — not the hero alone, not by
## hand. A square is reached for an area, a flask or a lit square by the rule of a blow — total cover by 5e's four lines
## (FightGrid.reaches) — not by the one straight line: a lone tree on it is half cover. An escape from bonds fails on a
## natural 1 whatever the total (ADR-0008 §2) and frees the hero on the next try.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _bite() -> Dictionary:
	for a: Dictionary in data["monsters"]["giant_spider"]["actions"]:
		if str(a["name_en"]) == "Bite":
			return a
	return {}


# --- a giant spider's poison ------------------------------------------------------------------------------------


func test_the_spiders_poison_spares_the_hero_with_the_consoles_immortality() -> void:
	var s := ChecklistProbe.session(data)
	var f := ChecklistProbe.fight(s, data, "giant_spider")
	Cheats.toggle(s.character, "god")
	s.character["hp"] = 1
	var lines: Array[String] = []
	MonsterRules.apply_effect(s, data, f, CombatRules.player(s), _bite(), 5, lines)
	assert_int(int(s.character["hp"])).override_failure_message(" · ".join(lines)).is_equal(1)
	assert_bool(ConditionRules.has(s.character, "paralyzed")).is_false()
	assert_bool(ConditionRules.has(s.character, "unconscious")).is_false()
	assert_str(str(s.combat.get("outcome", ""))).is_empty()


func test_temporary_hit_points_take_the_spiders_poison_first() -> void:
	var s := ChecklistProbe.session(data)
	var f := ChecklistProbe.fight(s, data, "giant_spider")
	s.character["hp"] = 1
	s.character["temp_hp"] = 99
	var lines: Array[String] = []
	MonsterRules.apply_effect(s, data, f, CombatRules.player(s), _bite(), 5, lines)
	assert_int(int(s.character["hp"])).override_failure_message(" · ".join(lines)).is_equal(1)
	assert_int(int(s.character["temp_hp"])).is_less(99)
	assert_bool(ConditionRules.has(s.character, "paralyzed")).is_false()


func test_the_spiders_poison_leaves_an_ally_stable_and_paralysed() -> void:
	var s := ChecklistProbe.session(data)
	TestUtils.fight(s, data, [{"monster": "giant_spider", "col": 2}], {"allies": [{"monster": "guard"}]})
	var spider := CombatRules.fighter(s, CombatRules.enemies(s)[0])
	var ally := CombatRules.fighter(s, CombatRules.allies(s)[0])
	ally["hp"] = 1
	var lines: Array[String] = []
	MonsterRules.apply_effect(s, data, spider, ally, _bite(), 5, lines)
	assert_str(str(ally["status"])).override_failure_message(" · ".join(lines)).is_equal("down")
	assert_bool(bool(CombatRules.saves_of(s, ally).get("stable", false))).is_true()
	assert_bool(CombatRules.dying(s, ally)).is_false()
	assert_bool(ConditionRules.has(ally, "poisoned")).is_true()
	assert_bool(ConditionRules.has(ally, "paralyzed")).is_true()


func test_the_spiders_poison_knocks_a_foe_out_not_dead() -> void:
	var s := ChecklistProbe.session(data)
	TestUtils.fight(s, data, [{"monster": "goblin", "col": 2}], {"allies": [{"monster": "giant_spider"}]})
	var spider := CombatRules.fighter(s, CombatRules.allies(s)[0])
	var goblin := CombatRules.fighter(s, CombatRules.enemies(s)[0])
	goblin["hp"] = 1
	var lines: Array[String] = []
	MonsterRules.apply_effect(s, data, spider, goblin, _bite(), 5, lines)
	assert_str(str(goblin["status"])).override_failure_message(" · ".join(lines)).is_equal("unconscious")
	assert_bool(ConditionRules.has(goblin, "paralyzed")).is_true()


func test_the_spiders_poison_still_leaves_a_downed_hero_stable() -> void:
	var s := ChecklistProbe.session(data)
	var f := ChecklistProbe.fight(s, data, "giant_spider")
	s.character["hp"] = 1
	s.character["max_hp"] = 40  # no massive damage: 2d8 of poison never kills it outright
	var lines: Array[String] = []
	MonsterRules.apply_effect(s, data, f, CombatRules.player(s), _bite(), 5, lines)
	assert_int(int(s.character["hp"])).override_failure_message(" · ".join(lines)).is_equal(0)
	assert_bool(bool(s.combat["death_saves"]["stable"])).is_true()
	assert_bool(ConditionRules.has(s.character, "unconscious")).is_true()
	assert_bool(ConditionRules.has(s.character, "paralyzed")).is_true()


# --- a square behind a lone tree ---------------------------------------------------------------------------------


func _trees(s: GameSession, cells: Array[Vector2i]) -> void:
	for at: Vector2i in cells:
		s.combat["blocks"][FightGrid.tag(at)] = FightField._block(data, "tree", "дерево")
	FightGrid.changed(s)


func test_a_lone_tree_on_the_straight_line_is_no_wall_for_an_area_or_a_flask() -> void:
	var s := ChecklistProbe.session(data)
	s.character["inventory"]["oil_flask"] = 1
	ChecklistProbe.fight(s, data, "goblin", true)
	var p := CombatRules.player(s)
	FightGrid.put(p, Vector2i(40, 30))
	var at := Vector2i(39, 27)
	_trees(s, [Vector2i(39, 28)] as Array[Vector2i])
	assert_bool(FightGrid.clear(FightGrid.grid(s, data), FightGrid.cell(p), at)).is_false()
	assert_int(FightGrid.cover_at(s, data, FightGrid.cell(p), at)).is_less(FightGrid.FULL_COVER)
	assert_bool(FightGrid.reaches(s, data, p, at)).is_true()
	assert_str(CombatRules._can_aim(s, data, "fireball", at, p)).is_empty()
	assert_str(Acts.one("throw").why(s, data, p, FightGrid.aim_id(at), {"item": "oil_flask"})).is_empty()


func test_a_wall_of_trees_is_total_cover_for_an_area() -> void:
	var s := ChecklistProbe.session(data)
	ChecklistProbe.fight(s, data, "goblin", true)
	var p := CombatRules.player(s)
	FightGrid.put(p, Vector2i(40, 30))
	var wall: Array[Vector2i] = []
	for x: int in range(30, 50):
		wall.append(Vector2i(x, 28))
	_trees(s, wall)
	assert_bool(FightGrid.reaches(s, data, p, Vector2i(39, 27))).is_false()
	assert_str(CombatRules._can_aim(s, data, "fireball", Vector2i(39, 27), p)).is_equal("COMBAT_NO_LINE")


# --- bonds and a natural 1 ---------------------------------------------------------------------------------------


## A seed whose first two d20 are both 1 (`one`), or both above 1: the die of a check with or without a second one.
func _seed(one: bool) -> int:
	var rng := RandomNumberGenerator.new()
	for i: int in 100000:
		rng.seed = i
		var a := rng.randi_range(1, 20)
		var b := rng.randi_range(1, 20)
		if (a == 1 and b == 1) if one else (a > 1 and b > 1):
			return i
	return 0


func test_a_natural_1_fails_an_escape_whatever_the_total_and_the_next_try_frees() -> void:
	var s := ChecklistProbe.session(data)
	s.character["traits"] = (s.character.get("traits", []) as Array).filter(func(t: Variant) -> bool: return str(t) != "lucky")
	s.room_id = "outpost-yard"
	EncounterRules.capture(s, data, [Being.spawn(s, {"monster": "bandit", "name": "Разбойник"})["id"]], "", "outpost-road")
	s.character["skills"]["athletics"] = 40
	s.rng.seed = _seed(true)
	var lines := EncounterRules.escape(s, data, "escape_athletics")
	assert_bool(EncounterRules.captive(s)).override_failure_message(" · ".join(lines)).is_true()
	assert_str(lines[0]).contains("провал")
	s.character["skills"]["athletics"] = 40
	s.rng.seed = _seed(false)
	lines = EncounterRules.escape(s, data, "escape_athletics")
	assert_bool(EncounterRules.captive(s)).override_failure_message(" · ".join(lines)).is_false()
