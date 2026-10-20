extends GdUnitTestSuite
## «Правила 5e: монстры» (roadmap v0.7.9): the effects of monster attacks on the hero (prone, paralysis, poison, webs,
## grapples, life drain, stone), recharge and control before damage, traits, casters, Parry, magic weapons against
## resistance, condition immunities, a downed hero left by beasts.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _session(preset_id: String = "fighter_aira") -> GameSession:
	var s := TestUtils.new_session()
	for p: Dictionary in data["presets"]:
		if p["id"] == preset_id:
			s.character = GameSession.normalized_character(CharacterBuilder.build_preset(p, data))
	CharacterRules.refresh(s.character, data)
	return s


func _fight(s: GameSession, monster: String, col: int = 0) -> Dictionary:
	CombatRules.start(s, data, [{"monster": monster, "col": col}], {})
	var order: Array = s.combat["order"]
	order.erase(CombatRules.PLAYER)
	order.push_front(CombatRules.PLAYER)
	s.combat["turn"] = 0
	CombatRules._begin_turn(s, data, [] as Array[String])
	s.mode = GameSession.MODE_COMBAT
	return CombatRules.fighter(s, CombatRules.enemies(s)[0])


func _action(monster: String, name_en: String) -> Dictionary:
	for a: Dictionary in data["monsters"][monster]["actions"]:
		if str(a["name_en"]) == name_en:
			return a
	return {}


func _weak(s: GameSession) -> void:
	for ab: String in ["str", "dex", "con", "int", "wis", "cha"]:
		s.character["saves"][ab] = -40  # only a natural 20 saves


func _hit(s: GameSession, f: Dictionary, a: Dictionary, tries: int = 30) -> Array[String]:
	var lines: Array[String] = []
	for i in tries:  # until it hits (the dice are the session's)
		lines.clear()
		s.character["hp"] = int(s.character["max_hp"])
		CombatRules._enemy_attack(s, data, f, a, lines)
		if not ", ".join(lines).contains("промах"):
			break
	return lines


func test_the_import_keeps_the_effects() -> void:
	assert_str(str(_action("wolf", "Bite")["effect"]["condition"])).is_equal("prone")
	var claws := _action("ghoul", "Claws")
	assert_str(str(claws["effect"]["condition"])).is_equal("paralyzed")
	assert_bool(bool(claws["effect"]["repeat"])).is_true()
	assert_array(claws["effect"]["immune_races"]).contains(["elf"])
	var web := _action("giant_spider", "Web")
	assert_int(int(web["recharge"])).is_equal(5)
	assert_int(int(web["effect"]["escape_dc"])).is_equal(12)
	assert_str(str(_action("constrictor_snake", "Constrict")["effect"]["also"])).is_equal("restrained")
	assert_str(str(data["monsters"]["bandit_captain"]["reactions"][0]["id"])).is_equal("parry")
	assert_dict(data["monsters"]["cult_fanatic"]["spellcasting"]).contains_keys(["dc", "slots", "spells"])
	assert_str(str(data["monsters"]["ghoul"]["languages"])).contains("Common")


func test_a_wolf_bite_knocks_the_hero_down() -> void:
	var s := _session()
	var f := _fight(s, "wolf")
	_weak(s)
	var lines := _hit(s, f, _action("wolf", "Bite"))
	assert_str(", ".join(lines)).contains("спасбросок")
	assert_bool(ConditionRules.has(s.character, "prone")).is_true()


func test_ghoul_claws_paralyse_but_not_an_elf() -> void:
	var s := _session()
	var f := _fight(s, "ghoul")
	_weak(s)
	_hit(s, f, _action("ghoul", "Claws"))
	assert_bool(ConditionRules.has(s.character, "paralyzed")).is_true()
	var e: Dictionary = ConditionRules.effects_of(s.character, "paralyzed")[0]
	assert_bool(bool(e["save"]["repeat"])).is_true()
	assert_bool(e["ends"].has("at")).is_true()
	var elf := _session("wizard_yalika")
	var g := _fight(elf, "ghoul")
	_weak(elf)
	_hit(elf, g, _action("ghoul", "Claws"))
	assert_bool(ConditionRules.has(elf.character, "paralyzed")).is_false()


func test_a_constrictor_holds_until_it_dies() -> void:
	var s := _session()
	var f := _fight(s, "constrictor_snake")
	_hit(s, f, _action("constrictor_snake", "Constrict"))
	assert_array(s.character["conditions"]).contains(["grappled", "restrained"])
	assert_int(int(s.character["speed"])).is_equal(0)
	var lines: Array[String] = []
	CombatRules._hurt_enemy(s, data, f, 999, lines)
	assert_array(s.character["conditions"]).not_contains(["grappled", "restrained"])


func test_a_web_breaks_with_its_dc_and_recharges() -> void:
	var s := _session()
	var f := _fight(s, "giant_spider", 1)
	var web := _action("giant_spider", "Web")
	assert_dict(MonsterRules.pick(s, data, f, "ranged")).is_equal(web)  # control first
	_hit(s, f, web)
	assert_bool(ConditionRules.has(s.character, "restrained")).is_true()
	assert_bool(MonsterRules.available(f, web)).is_false()
	assert_str(str(MonsterRules.pick(s, data, f, "melee")["name_en"])).is_equal("Bite")
	assert_int(int(ConditionRules.effects_of(s.character, "restrained")[0]["escape_dc"])).is_equal(12)
	s.character["skills"]["athletics"] = 40
	CombatRules.escape(s, data)
	assert_bool(ConditionRules.has(s.character, "restrained")).is_false()
	var lines: Array[String] = []
	for i in 40:
		MonsterRules.start_turn(s, data, f, lines)
		if MonsterRules.available(f, web):
			break
	assert_bool(MonsterRules.available(f, web)).is_true()


func test_spider_poison_that_drops_the_hero_leaves_them_paralysed_and_stable() -> void:
	var s := _session()
	var f := _fight(s, "giant_spider")
	_weak(s)
	s.character["hp"] = 1
	var lines: Array[String] = []
	MonsterRules.apply_effect(s, data, f, _action("giant_spider", "Bite"), 5, lines)
	if int(s.character["hp"]) > 0:
		return  # a natural 20 on the save
	assert_bool(ConditionRules.has(s.character, "paralyzed")).is_true()
	assert_bool(bool(s.combat["death_saves"]["stable"])).is_true()


func test_life_drain_lowers_the_maximum_until_a_long_rest() -> void:
	var s := _session()
	var f := _fight(s, "specter")
	_weak(s)
	var before := int(s.character["max_hp"])
	MonsterRules.apply_effect(s, data, f, _action("specter", "Life Drain"), 6, [] as Array[String])
	assert_int(int(s.character["max_hp"])).is_equal(before - 6)
	s.combat = {}
	s.room_id = "brod-temple"
	ExplorationRules.long_rest(s, data)
	CharacterRules.refresh(s.character, data, s.items)
	assert_int(int(s.character["max_hp"])).is_equal(before)


func test_a_cockatrice_turns_the_hero_to_stone_on_a_second_failure() -> void:
	var s := _session()
	var f := _fight(s, "cockatrice")
	_weak(s)
	MonsterRules.apply_effect(s, data, f, _action("cockatrice", "Bite"), 2, [] as Array[String])
	assert_bool(ConditionRules.has(s.character, "restrained")).is_true()
	_weak(s)  # the sheet was refreshed by the new condition
	ConditionRules.end_of_turn(s, data)
	assert_bool(ConditionRules.has(s.character, "petrified")).is_true()
	assert_bool(ConditionRules.has(s.character, "restrained")).is_false()


func test_a_breath_in_reach_comes_first() -> void:
	var s := _session()
	var f := _fight(s, "dust_mephit")
	assert_str(str(MonsterRules.save_action(s, data, f, 0).get("name_en", ""))).is_equal("Blinding Breath")
	assert_dict(MonsterRules.save_action(s, data, f, 2)).is_empty()  # 15 ft does not reach 60


func test_traits_of_monsters() -> void:
	var s := _session()
	var wolf := _fight(s, "wolf", 2)
	assert_int(CombatRules.monster_passive(data, wolf)).is_equal(int(data["monsters"]["wolf"]["passive_perception"]) + 5)
	assert_bool(MonsterRules.save_advantage(data, {"monster": "bearded_devil"}, "wis", ["magic"])).is_true()
	assert_bool(MonsterRules.save_advantage(data, {"monster": "cultist"}, "wis", ["charm", "magic"])).is_true()
	assert_bool(MonsterRules.save_advantage(data, {"monster": "wolf"}, "wis", ["magic"])).is_false()
	var boar := {"id": "e9", "monster": "boar", "name": "Кабан", "hp": 5, "max_hp": 11}
	assert_bool(MonsterRules.survives(s, data, boar, 6, "slashing", false, [] as Array[String])).is_true()
	assert_bool(MonsterRules.survives(s, data, boar, 6, "slashing", false, [] as Array[String])).is_false()  # once
	s.minute = 12 * 60
	s.room_id = "pushcha-edge"
	assert_array(MonsterRules.attack_mods(s, data, {"monster": "kobold"}, {"kind": "melee"})["dis"]).contains(["солнце"])
	s.room_id = "mine-gallery"
	assert_array(MonsterRules.attack_mods(s, data, {"monster": "kobold"}, {"kind": "melee"})["dis"]).is_empty()


func test_a_charge_hits_harder_after_a_run() -> void:
	var s := _session()
	var f := _fight(s, "boar")
	f["moved"] = 1
	f["once"] = []
	var out := MonsterRules.extra_on_hit(s, data, f, _action("boar", "Tusk"), false, false, false)
	assert_int(int(out["damage"])).is_greater(0)
	assert_dict(out["prone"]).contains_keys(["save"])
	f["moved"] = 0
	f["once"] = []
	assert_int(int(MonsterRules.extra_on_hit(s, data, f, _action("boar", "Tusk"), false, false, false)["damage"])).is_equal(0)


func test_a_fanatic_holds_the_hero_until_it_loses_concentration() -> void:
	var s := _session()
	var f := _fight(s, "cult_fanatic", 1)
	_weak(s)
	var lines: Array[String] = []
	MonsterRules._cast(s, data, f, {"id": "hold_person", "slot": 2}, lines)
	assert_bool(ConditionRules.has(s.character, "paralyzed")).is_true()
	assert_str(str(f["concentration"])).is_equal("hold_person")
	assert_int(int(f["slots"]["2"])).is_equal(int(data["monsters"]["cult_fanatic"]["spellcasting"]["slots"]["2"]) - 1)
	MonsterRules.release(s, data, f, lines)
	assert_bool(ConditionRules.has(s.character, "paralyzed")).is_false()


func test_a_hurt_acolyte_heals_itself() -> void:
	var s := _session()
	var f := _fight(s, "acolyte", 2)
	f["hp"] = 1
	var lines: Array[String] = []
	assert_bool(MonsterRules.cast_turn(s, data, f, lines)).is_true()
	assert_int(int(f["hp"])).is_greater(1)


func test_a_captain_parries_a_close_hit() -> void:
	var s := _session()
	var f := _fight(s, "bandit_captain")
	var lines: Array[String] = []
	assert_bool(MonsterRules.parry(s, data, f, int(f["ac"]), lines)).is_true()
	assert_bool(MonsterRules.parry(s, data, f, int(f["ac"]), lines)).is_false()  # one reaction a round
	f["reacted"] = false
	assert_bool(MonsterRules.parry(s, data, f, int(f["ac"]) + 2, lines)).is_false()  # too strong to turn


func test_magic_weapons_pierce_resistance_to_nonmagical_attacks() -> void:
	var t := {"monster": "wight"}
	assert_int(CombatRules._resist(data, t, "slashing", 10, false)).is_equal(5)
	assert_int(CombatRules._resist(data, t, "slashing", 10, true)).is_equal(10)


func test_immune_foes_cannot_be_shoved_down() -> void:
	var s := _session()
	var f := _fight(s, "ochre_jelly")
	assert_bool(CombatRules.immune_to(data, f, "prone")).is_true()
	s.character["skills"]["athletics"] = 40
	CombatRules.grapple(s, data, str(f["id"]), true)
	assert_bool(CombatRules._has(f, "prone")).is_false()


func test_beasts_leave_a_downed_hero() -> void:
	var s := _session()
	var f := _fight(s, "wolf")
	s.character["hp"] = 0
	s.combat["death_saves"] = {"ok": 3, "fail": 0, "stable": true}
	var lines: Array[String] = []
	CombatRules._enemy_turn(s, data, f, lines)
	assert_str(", ".join(lines)).contains("теряет интерес")
	CombatRules._check_end(s, data, lines)
	assert_str(str(s.combat["outcome"])).is_equal("left")
