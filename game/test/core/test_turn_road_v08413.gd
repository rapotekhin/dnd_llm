extends GdUnitTestSuite
## v0.8.4.13, ADR-0016: one start and one end of a turn for anybody, one road of damage in and out of a fight.

var data: Dictionary


func before() -> void:
	data = TestUtils.data()


func _fight(foes: Array) -> GameSession:
	var s := TestUtils.new_session()
	TestUtils.fight(s, data, foes)
	return s


## Makes `f`'s turn the current one, as the fight's loop does.
func _turn_of(s: GameSession, f: Dictionary, lines: Array[String]) -> void:
	s.combat["turn"] = (s.combat["order"] as Array).find(str(f["id"]))
	CombatRules._begin_turn(s, data, lines)


func test_acid_burns_a_foe_at_the_end_of_its_ordinary_turn() -> void:
	var s := _fight([{"monster": "ogre", "col": 4}])
	var f := CombatRules.fighter(s, TestUtils.foe(s, 1))
	f["acid"] = "2d4"
	var hp := int(f["hp"])
	var lines: Array[String] = []
	_turn_of(s, f, lines)
	lines.append_array(CombatRules.next_actor(s, data))
	assert_bool(f.has("acid")).is_false()
	assert_int(int(f["hp"])).override_failure_message("\n".join(lines)).is_less(hp)


func test_a_foe_turned_to_stone_by_its_last_failed_save() -> void:
	var s := _fight([{"monster": "goblin", "col": 4}])
	var f := CombatRules.fighter(s, TestUtils.foe(s, 1))
	ConditionRules.add_effect(f, {"condition": "paralyzed", "source": {"kind": "engine", "name": "тест"}})  # fails DEX saves
	ConditionRules.add_effect(f, {"condition": "restrained", "save": {"ability": "dex", "dc": 10, "repeat": true, "once": true},
		"escalate": {"condition": "petrified", "duration": "day"}, "source": {"kind": "monster", "name": "Взгляд"}})
	var lines := ConditionRules.end_of_turn(s, data, f)
	assert_bool(ConditionRules.has(f, "restrained")).is_false()
	assert_bool(ConditionRules.has(f, "petrified")).override_failure_message("\n".join(lines)).is_true()


func test_an_ally_gets_its_recharge_back_at_the_start_of_its_turn() -> void:
	var s := _fight([{"monster": "goblin", "col": 6}])
	var ids := CombatRules.add_allies(s, data, [{"monster": "wolf", "ally": "follower"}], true)
	var a := CombatRules.fighter(s, ids[0])
	a["recharging"] = {"Bite": 1}  # a recharge of 1 always comes back
	var lines: Array[String] = []
	_turn_of(s, a, lines)
	assert_bool((a["recharging"] as Dictionary).is_empty()).is_true()
	Stock.spend(a, "hit_dice", 1)  # what its features spent is not a recharge: it waits for a rest
	_turn_of(s, a, lines)
	assert_int(Stock.spent(a, "hit_dice")).is_equal(1)


func test_retching_takes_the_action_not_the_turn() -> void:
	var s := _fight([{"monster": "goblin", "col": 6}])
	var f := CombatRules.fighter(s, TestUtils.foe(s, 1))
	f["retching"] = true
	var lines: Array[String] = []
	_turn_of(s, f, lines)
	assert_int(int(f["points"]["action"])).is_equal(0)
	assert_int(int(f["points"]["move"])).is_greater(0)


func test_a_condition_on_the_hero_lasts_as_on_a_foe() -> void:
	var s := _fight([{"monster": "goblin", "col": 6}])
	var f := CombatRules.fighter(s, TestUtils.foe(s, 1))
	s.combat["turn"] = 0  # both are yet to act in this round
	CombatRules._add_condition(s, data, CombatRules.player(s), "frightened", {"rounds": 1, "by": str(f["id"])})
	CombatRules._add_condition(s, data, f, "frightened", {"rounds": 1, "by": CombatRules.PLAYER})
	var hero_end := int(ConditionRules.effects_of(s.character, "frightened")[0]["ends"]["at"])
	assert_int(hero_end).is_equal(int(ConditionRules.effects_of(f, "frightened")[0]["ends"]["at"]))


func test_temporary_hit_points_take_a_trap_out_of_a_fight() -> void:
	var s := TestUtils.new_session()
	var c := s.character
	c["hp"] = 10
	c["temp_hp"] = 5
	var lines: Array[String] = []
	Harm.take(s, data, Sheet.HERO, 8, lines, "piercing")
	assert_int(int(c["temp_hp"])).is_equal(0)
	assert_int(int(c["hp"])).is_equal(7)


func test_a_foe_losing_concentration_keeps_its_grapple() -> void:
	var s := _fight([{"monster": "goblin", "col": 1}])
	var f := CombatRules.fighter(s, TestUtils.foe(s, 1))
	f["concentration"] = "bless"
	ConditionRules.add_effect(s.character, {"condition": "grappled", "hold": true, "by": str(f["id"]), "source": {"kind": "monster", "name": "хватка"}})
	var lines := ConditionRules.lose_concentration(s, data, f, "удар")
	assert_str(str(f.get("concentration", ""))).is_empty()
	assert_bool(ConditionRules.has(s.character, "grappled")).override_failure_message("\n".join(lines)).is_true()


func test_a_foe_at_zero_drops_its_concentration_through_the_one_road() -> void:
	var s := _fight([{"monster": "goblin", "col": 1}])
	var f := CombatRules.fighter(s, TestUtils.foe(s, 1))
	f["concentration"] = "bless"
	var lines: Array[String] = []
	Harm.take(s, data, f, 999, lines, "slashing")
	assert_str(str(f["status"])).is_equal("dead")
	assert_bool(f.has("concentration")).is_false()


func test_damage_with_no_roll_goes_through_the_defenses_of_anybody() -> void:
	var s := _fight([{"monster": "goblin", "col": 4}])
	var f := CombatRules.fighter(s, TestUtils.foe(s, 1))
	f["hp"] = 30
	ConditionRules.add_effect(f, {"condition": "petrified", "source": {"kind": "engine", "name": "тест"}})  # resists everything
	var lines: Array[String] = []
	assert_int(Harm.typed(s, data, f, 10, "bludgeoning", lines, "яма: {hp} ({words})")).is_equal(5)
	assert_int(int(f["hp"])).is_equal(25)
	assert_str(lines[0]).starts_with("яма: 5 (").contains("окаменение")


func test_damage_with_no_roll_names_its_type_and_an_immunity() -> void:
	var s := TestUtils.new_session()
	s.character["hp"] = 10
	Cheats.defense(s, data, Being.HERO, "immune", "poison", true)
	var lines: Array[String] = []
	assert_int(Harm.typed(s, data, Sheet.HERO, 6, "poison", lines)).is_equal(0)
	assert_int(int(s.character["hp"])).is_equal(10)
	assert_str(lines[0]).is_equal("−0 HP (%s, иммунитет)" % data["misc"]["damage_types"]["poison"])
