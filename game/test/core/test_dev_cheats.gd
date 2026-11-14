extends GdUnitTestSuite
## The dev console's cheats (Dev.run, Cheats): each goes through the engine's own road and refuses without a session.

var s: GameSession


func before_test() -> void:
	s = TestUtils.new_session()
	GameState.start(s)


func after_test() -> void:
	GameState.session = null
	GameState.busy_turn = ""
	GameState.combat_playing = false


func test_refuses_without_a_session_and_while_the_master_answers() -> void:
	GameState.session = null
	assert_str(Dev.run("give longsword")).is_equal("no session")
	assert_str(Dev.run("find monster волк")).is_equal("no session")
	GameState.session = s
	GameState.busy_turn = "t-1"
	assert_str(Dev.run("gold 5")).contains("мастер")
	assert_str(Dev.run("help")).contains("spawn")


func test_give_by_a_russian_name_with_a_count_and_gold() -> void:
	var before := Gear.count(s, Catalog.data, Being.HERO, "longsword")
	assert_str(Dev.run("give Длинный меч 2")).contains("[longsword]")
	assert_int(Gear.count(s, Catalog.data, Being.HERO, "longsword")).is_equal(before + 2)
	assert_str(Dev.run("give нет-такой-вещи")).contains("не найдено")
	var cp := Ledger.balance(s)
	Dev.run("gold 5")
	assert_int(Ledger.balance(s)).is_equal(cp + 5 * Money.GP)
	Dev.run("gold -100000")
	assert_int(Ledger.balance(s)).is_equal(0)
	assert_array(s.character["cheats"]["used"]).contains(["give", "gold"])


func test_spawn_starts_a_fight_with_the_allies_spawned_before() -> void:
	assert_str(Dev.run("spawn Волк 1 ally")).contains("ждёт боя")
	assert_bool(CombatRules.active(s)).is_false()
	assert_str(Dev.run("spawn goblin 2")).contains("бой")
	assert_bool(CombatRules.active(s)).is_true()
	assert_int(CombatRules.enemies(s).size()).is_equal(2)
	assert_int(CombatRules.allies(s).size()).is_greater_equal(1)
	GameState.busy_turn = ""
	var allies := CombatRules.allies(s).size()
	assert_str(Dev.run("spawn wolf 2 союзник")).contains("союзники в бою")
	assert_int(CombatRules.allies(s).size()).is_equal(allies + 2)
	Dev.run("spawn goblin")
	assert_int(CombatRules.enemies(s).size()).is_equal(3)
	assert_str(Dev.run("goto brod-square")).contains("в бою нельзя")


func test_goto_moves_without_a_master_turn() -> void:
	assert_str(Dev.run("goto brod-smithy")).contains("[brod-smithy]")
	assert_str(s.room_id).is_equal("brod-smithy")
	assert_bool(GameState.is_busy()).is_false()


func test_heal_god_and_endless_slots() -> void:
	var c := s.character
	c["hp"] = 1
	Dev.run("heal")
	assert_int(c["hp"]).is_equal(int(c["max_hp"]))
	assert_str(Dev.run("god")).is_equal("god: вкл")
	var lines: Array[String] = []
	Harm.take(s, Catalog.data, Sheet.HERO, 999, lines)
	assert_int(c["hp"]).is_equal(1)
	Dev.run("god")
	assert_str(Dev.run("spell Огненный шар")).contains("[fireball]")
	assert_bool(SpellRules.ready(c).has("fireball")).is_true()
	Dev.run("slots")
	assert_str(str(SpellRules.check(c, Catalog.data, "fireball", 0).get("reason", ""))).is_empty()
	SpellRules.cast(c, Catalog.data, "fireball", 3, s)
	assert_int(SpellRules.slots_left(c, 3)).is_greater_equal(1)


func test_xp_level_reset_and_class() -> void:
	var c := s.character
	var gear: Dictionary = c["inventory"].duplicate()
	assert_str(Dev.run("xp 50")).contains("+50")
	assert_str(Dev.run("level 3")).contains("3 уровень")
	assert_int(c["level"]).is_equal(3)
	assert_str(Dev.run("reset")).contains("1 уровня")
	assert_int(c["level"]).is_equal(1)
	assert_int(c["xp"]).is_equal(0)
	assert_str(Dev.run("class Волшебник")).contains("Волшебник")
	assert_str(c["class"]).is_equal("wizard")
	assert_dict(c["inventory"]).is_equal(gear)
	assert_bool(c["hp"] == c["max_hp"]).is_true()


func test_feature_trait_and_find() -> void:
	assert_str(Dev.run("feature Второе дыхание")).contains("[second_wind]")
	assert_bool(CharacterRules.has_feature(s.character, "second_wind")).is_true()
	assert_str(Dev.run("trait darkvision")).contains("[darkvision]")
	assert_str(Dev.run("find monster волк")).contains("[wolf]")
	assert_str(Dev.run("find spawn гобл")).contains("[goblin]")


func test_completion_puts_in_the_first_id_and_keeps_the_count() -> void:
	var r := Dev.complete("spawn Волк 2 ally")
	assert_str(r["line"]).is_equal("spawn wolf 2 ally")
	assert_array(r["hints"]).is_not_empty()
	assert_str(Dev.complete("spa")["line"]).is_equal("spawn ")
	assert_str(Dev.complete("find item длинный м")["line"]).is_equal("find item longsword")


## The author's case: a goblin given fire resistance takes half of the hero's Fireball — the same rolls both times.
func test_a_unit_given_fire_resistance_takes_half_a_fireball() -> void:
	TestUtils.fight(s, Catalog.data, [{"monster": "goblin", "col": 2}])
	var gid := TestUtils.foe(s, 1)
	var g := CombatRules.fighter(s, gid)
	g["max_hp"] = 500
	g["hp"] = 500
	assert_str(Dev.run("units")).contains("[@%s]" % gid)
	Dev.run("spell Огненный шар")
	Dev.run("slots")
	var aim := FightGrid.aim_id(FightGrid.cell(g))
	var state := s.rng.state
	CombatRules.economy(s)["action"] = 1
	Acts.one("cast").go(s, Catalog.data, CombatRules.player(s), aim, {"spell": "fireball", "slot": 3})
	var full := 500 - int(g["hp"])
	assert_int(full).is_greater(0)
	g["hp"] = 500
	assert_str(Dev.run("@гоблин resist огонь")).contains("Гоблин: сопротивление")
	assert_int(Sheet.taken(s, Catalog.data, g, "fire", 10)).is_equal(5)
	s.rng.state = state
	CombatRules.economy(s)["action"] = 1
	Acts.one("cast").go(s, Catalog.data, CombatRules.player(s), aim, {"spell": "fireball", "slot": 3})
	assert_int(500 - int(g["hp"])).is_equal(full / 2)
	Dev.run("@гоблин resist fire off")
	assert_int(Sheet.taken(s, Catalog.data, g, "fire", 10)).is_equal(10)


func test_unit_cheats_heal_give_a_status_and_a_feature() -> void:
	TestUtils.fight(s, Catalog.data, [{"monster": "goblin", "col": 1}, {"monster": "goblin", "col": 2}])
	assert_str(Dev.run("@гобл heal")).contains("несколько")
	var gid := TestUtils.foe(s, 2)
	var g := CombatRules.fighter(s, gid)
	g["hp"] = 1
	assert_str(Dev.run("@%s heal" % gid)).contains("HP %d/%d" % [int(g["max_hp"]), int(g["max_hp"])])
	assert_int(g["hp"]).is_equal(int(g["max_hp"]))
	Dev.run("@%s cond prone" % gid)
	assert_bool(ConditionRules.has(g, "prone")).is_true()
	Dev.run("@%s cond prone off" % gid)
	assert_bool(ConditionRules.has(g, "prone")).is_false()
	assert_str(Dev.run("@%s feature Второе дыхание" % gid)).contains("[second_wind]")
	assert_bool((g["features"] as Array).has("second_wind")).is_true()
	Dev.run("@%s give Длинный меч" % gid)
	assert_int(Gear.count(s, Catalog.data, gid, "longsword")).is_equal(1)
	assert_str(Dev.run("@никто heal")).contains("здесь нет")
	assert_str(Dev.run("@%s xp 5" % gid)).contains("@<цель>")
	assert_str(Dev.complete("@%s resist ог" % gid)["line"]).is_equal("@%s resist fire" % gid)


func test_unit_cheats_out_of_a_fight_aim_at_the_people_here() -> void:
	var here := s.npcs_here(Catalog.data["world"], s.room_id)
	assert_array(here).is_not_empty()
	var id := str(here[0])
	assert_str(Dev.run("@%s resist cold" % id)).contains("сопротивление")
	assert_int(Sheet.taken(s, Catalog.data, Sheet.who(s, Catalog.data, id), "cold", 10)).is_equal(5)
	assert_str(Dev.run("@%s feature second_wind" % id)).contains("только бойцу")


func test_immunity_and_vulnerability_on_a_unit_and_on_the_hero() -> void:
	TestUtils.fight(s, Catalog.data, [{"monster": "goblin", "col": 1}])
	var g := CombatRules.fighter(s, TestUtils.foe(s, 1))
	assert_str(Dev.run("@гоблин immune огонь")).contains("иммунитет")
	assert_int(Sheet.taken(s, Catalog.data, g, "fire", 10)).is_equal(0)
	Dev.run("@гоблин immune fire off")
	Dev.run("@гоблин vulnerable fire")
	assert_int(Sheet.taken(s, Catalog.data, g, "fire", 10)).is_equal(20)
	Dev.run("immune poison")
	assert_int(Sheet.taken(s, Catalog.data, Sheet.HERO, "poison", 10)).is_equal(0)
	assert_int(Sheet.taken(s, Catalog.data, Sheet.HERO, "cold", 10)).is_equal(10)


func test_conditions_on_a_unit_and_on_the_hero_with_the_spells_statuses() -> void:
	TestUtils.fight(s, Catalog.data, [{"monster": "goblin", "col": 1}])
	var g := CombatRules.fighter(s, TestUtils.foe(s, 1))
	assert_str(Dev.run("@гоблин cond испуган")).contains("Испуган")
	assert_bool(ConditionRules.has(g, "frightened")).is_true()
	assert_str(Dev.run("@гоблин cond Светится")).contains("Светится")
	assert_array(ConditionRules.attack(Catalog.data, {}, g, true)["adv"]).is_not_empty()
	Dev.run("@гоблин cond outlined off")
	assert_bool(ConditionRules.has(g, "outlined")).is_false()
	assert_str(Dev.run("cond облито маслом")).contains("не найдено")  # a thing's alone; «горит» is a creature's too since v0.8.4.43.54
	Dev.run("cond exhaustion")
	Dev.run("cond exhaustion")
	assert_int(ConditionRules.exhaustion(s.character)).is_equal(2)
	Dev.run("cond exhaustion off")
	assert_int(ConditionRules.exhaustion(s.character)).is_equal(1)
	assert_str(Dev.run("cond ослеплён")).contains("Ослеплён")
	assert_bool(ConditionRules.has(s.character, "blinded")).is_true()


## The damage simulator: one attack roll by Attack.swing — dice, type, crit, forced advantage, the target's defenses, Harm.
func test_hit_rolls_an_attack_through_the_engine_road() -> void:
	assert_str(Dev.run("hit 1d6 fire")).contains("только в бою")
	s.settings["reactions"] = "never"
	TestUtils.fight(s, Catalog.data, [{"monster": "goblin", "col": 1}])
	var g := CombatRules.fighter(s, TestUtils.foe(s, 1))
	g["max_hp"] = 500
	g["hp"] = 500
	var out := Dev.run("@гоблин hit 4d1 огонь crit")
	assert_str(out).contains("удар консоли")
	assert_int(500 - int(g["hp"])).is_equal(8)  # a critical hit rolls the dice twice
	Dev.run("@гоблин resist fire")
	g["hp"] = 500
	out = Dev.run("@гоблин hit 4d1 fire crit")
	assert_int(500 - int(g["hp"])).is_equal(4)
	assert_str(out).contains("сопротивление: огонь")
	assert_str(Dev.run("@гоблин hit 1d1 cold crit adv")).contains("(с преимуществом)")
	assert_str(Dev.run("@гоблин hit 1d1 cold crit dis")).contains("(с помехой)")
	var hp := int(s.character["hp"])
	out = Dev.run("hit 3d1 cold crit")
	assert_str(out).contains("Гоблин — удар консоли")
	assert_int(hp - int(s.character["hp"])).is_equal(6)
	assert_str(Dev.run("hit 1d6 нет-такого-урона")).contains("не найдено")
	assert_str(Dev.run("hit fire")).contains("hit <кубики>")
	g["hp"] = 3
	assert_str(Dev.run("@гоблин hit 5d1 crit")).contains("повержен")


## Damage with no attack roll on the one road (Sheet.damage, Harm.take): out of a fight and in one, the hero and anybody.
func test_dmg_out_of_a_fight_and_in_one() -> void:
	var c := s.character
	var hp := int(c["hp"])
	var out := Dev.run("dmg 3d1 огонь")
	assert_str(out).contains("урон консоли")
	assert_int(hp - int(c["hp"])).is_equal(3)
	Dev.run("immune fire")
	assert_str(Dev.run("dmg 3d1 fire")).contains("−0 HP")
	assert_int(hp - int(c["hp"])).is_equal(3)
	assert_str(Dev.run("dmg 2d1 cold crit")).contains("×2 (крит)")
	assert_int(hp - int(c["hp"])).is_equal(7)
	assert_str(Dev.run("dmg 999d1 cold")).contains("Без сознания")  # out of a fight the hero is knocked out, as by a trap
	assert_int(c["hp"]).is_equal(1)
	GameState.busy_turn = ""
	var npc := str(s.npcs_here(Catalog.data["world"], s.room_id)[0])
	var top := Sheet.max_hp(s, Catalog.data, Sheet.who(s, Catalog.data, npc))
	assert_str(Dev.run("@%s dmg 2d1 piercing" % npc)).contains("HP %d/%d" % [top - 2, top])  # its template's count, less the blow
	TestUtils.fight(s, Catalog.data, [{"monster": "goblin", "col": 1}])
	var g := CombatRules.fighter(s, TestUtils.foe(s, 1))
	assert_str(Dev.run("@гоблин dmg 2d1 fire")).contains("HP %d/%d" % [int(g["max_hp"]) - 2, int(g["max_hp"])])
	assert_str(Dev.run("@гоблин dmg 99d1 fire")).contains("повержен")
	assert_str(Dev.run("@гоблин dmg 1d1")).contains("уже лежит")
	assert_str(Dev.run("dmg огонь")).contains("dmg <кубики>")
