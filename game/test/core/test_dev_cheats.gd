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
