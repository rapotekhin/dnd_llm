extends GdUnitTestSuite
## One road, review 2, group E (v0.8.4.29.2): the hero in a fight as anybody — ConditionRules.impose the one gate of
## immunity, initiative and the death save on the roll's road, holds let go by anybody who falls, one count of a fighter's
## maximum of hit points (exhaustion 4, Aid, a drain), a reach blow of anybody.

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


func test_heroism_keeps_fear_off_the_hero_at_the_one_gate() -> void:
	var s := _hero("paladin_gordey")
	var sp: Dictionary = s.character["spells"]
	sp["always"] = (sp.get("always", []) as Array) + ["heroism"]
	s.character["slots_max"] = [4, 3, 3, 0, 0]
	Stock.fill_slots(s.character)
	SpellRules.cast(s.character, data, "heroism", 1, s, true)
	var lines := ConditionRules.impose(s, data, {"condition": "frightened", "tag": "fear", "ends": {}, "source": {"kind": "monster", "name": "Рёв"}})
	assert_bool(ConditionRules.has(s.character, "frightened")).is_false()
	assert_str("\n".join(lines)).contains("не действует")


func test_initiative_is_a_dex_check_of_anybody() -> void:
	var s := _hero("fighter_aira")
	TestUtils.fight(s, data, [{"monster": "goblin"}], {})
	var g := CombatRules.fighter(s, CombatRules.enemies(s)[0])
	var dex := Sheet.ability_mod(s, data, g, "dex")
	for i in 20:
		var n := CombatRules.initiative_of(s, data, str(g["id"]))
		assert_int(n).is_between(1 + dex, 20 + dex)


func test_a_death_save_is_a_save() -> void:
	var s := _hero("fighter_aira")
	TestUtils.fight(s, data, [{"monster": "goblin"}], {})
	s.character["hp"] = 0
	ConditionRules.impose(s, data, {"condition": "unconscious", "ends": {"rest": "long"}, "source": {"kind": "engine", "name": "0 HP"}})
	var r := Sheet.save(s, data, CombatRules.player(s), "", 10, "death")
	assert_str(str(r["text"])).contains("от смерти")
	var lines: Array[String] = []
	CombatRules._death_save(s, data, CombatRules.player(s), lines)
	assert_str("\n".join(lines)).contains("спасбросок от смерти")


func test_a_fighters_maximum_is_one_count() -> void:
	var s := _hero("fighter_aira")
	TestUtils.fight(s, data, [{"monster": "ogre"}], {})
	var o := CombatRules.fighter(s, CombatRules.enemies(s)[0])
	var top := int(o["max_hp"])
	ConditionRules.add_exhaustion(s, data, 4, "проба", str(o["id"]))
	assert_int(int(o["max_hp"])).is_equal(top / 2)
	ConditionRules.add_effect(o, {"condition": "", "max_hp": 5, "ends": {}, "source": {"kind": "spell", "name": "Помощь"}})
	Sheet.refresh_max(s, data, o)
	assert_int(int(o["max_hp"])).is_equal(top / 2 + 5)
	ConditionRules.add_exhaustion(s, data, -4, "проба", str(o["id"]))
	assert_int(int(o["max_hp"])).is_equal(top + 5)
	o["max_hp"] = 500  # set by hand (the console, a probe): its own number, the status kept apart
	Sheet.refresh_max(s, data, o)
	assert_int(int(o["max_hp"])).is_equal(500)


func test_a_fallen_holder_lets_go() -> void:
	var s := _hero("fighter_aira")
	TestUtils.fight(s, data, [{"monster": "goblin"}], {})
	var g := CombatRules.fighter(s, CombatRules.enemies(s)[0])
	CombatRules._hold(g, "grappled", CombatRules.PLAYER)
	assert_bool(ConditionRules.has(g, "grappled")).is_true()
	ConditionRules.impose(s, data, {"condition": "unconscious", "ends": {"rest": "long"}, "source": {"kind": "engine", "name": "0 HP"}})
	assert_bool(ConditionRules.has(g, "grappled")).is_false()  # the hero's hold goes as anybody's
