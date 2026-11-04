extends GdUnitTestSuite
## Magic and matter traits on the engine's roads (roadmap v0.8.4.27.6): a creature's own glow is the `light` of a status in
## squares; one road of damage back at a striker beside it (`retort`, Harm.retort) — an azer's Heated Body and Armor of
## Agathys while its temporary hit points last; a basilisk's gaze is an aura whose failed repeat save turns to stone, and one
## who averts its eyes does not see it; a ghast's stench is an aura that never touches the ghast.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _aura(s: GameSession, id: String) -> Dictionary:
	return SpellEffects.zones(s).filter(func(z: Dictionary) -> bool: return str(z["spell"]) == "aura:" + id)[0]


func _hit_until(s: GameSession, f: Dictionary, t: Dictionary, b: Dictionary, lines: Array[String]) -> void:
	Sheet.holder(s, t)["ac"] = 1
	t["ac"] = 1
	for i in 30:
		var was := lines.size()
		Attack.swing(s, data, f, t, b, lines)
		if lines.slice(was).any(func(x: String) -> bool: return x.contains("попадание") or x.contains("КРИТ")):
			return


func test_a_creature_glows_by_its_trait() -> void:
	var s := ChecklistProbe.session(data)
	var azer := ChecklistProbe.fight(s, data, "azer")
	assert_int(SightRules.light(s, data, azer)).is_equal(4)
	assert_int(SightRules.light(s, data, ChecklistProbe.fight(s, data, "will_o_wisp"))).is_equal(8)
	var magmin := ChecklistProbe.fight(s, data, "magmin")
	s.room_id = "mine-gallery"  # an unlit gallery: a magmin sees in the dark, yet its glow shows it from afar
	assert_bool(TimeRules.unlit(s, data)).is_true()
	assert_bool(SightRules.dark_sight(s, data, magmin) > 0).is_true()
	assert_bool(SightRules.lit(s, data, magmin)).is_true()
	ConditionRules.add_effect(s.character, {"condition": "", "light": true, "ends": {}, "source": {"kind": "spell", "name": "Свет"}})
	assert_int(SightRules.light(s, data)).is_equal(int(data["rules"]["sight"]["lights"]["light"]))


func test_heated_body_burns_the_hand_that_strikes_it() -> void:
	var s := ChecklistProbe.session(data)
	var azer := ChecklistProbe.fight(s, data, "azer")
	var p := CombatRules.player(s)
	s.character["hp"] = 200
	s.character["max_hp"] = 200
	var lines: Array[String] = []
	_hit_until(s, p, azer, Attack.blade(s, data, p), lines)
	assert_str(" ".join(lines)).contains("Раскалённое тело")
	assert_int(int(s.character["hp"])).is_less(200)
	var hp := int(s.character["hp"])
	lines.clear()
	CombatRules.tussle(s, data, p, azer, "пытается схватить", "grappled", lines)
	assert_int(int(s.character["hp"])).override_failure_message(" · ".join(lines)).is_less(hp)


func test_armor_of_agathys_chills_a_striker_while_it_lasts() -> void:
	var s := ChecklistProbe.session(data)
	var goblin := ChecklistProbe.fight(s, data, "goblin")
	var c := s.character
	c["hp"] = 200
	c["max_hp"] = 200
	c["spells"]["always"] = (c["spells"].get("always", []) as Array) + ["armor_of_agathys"]
	c["slots_max"] = [4, 3, 3, 0, 0]
	Stock.fill_slots(c)
	SpellRules.cast(c, data, "armor_of_agathys", 2, s, true)
	assert_int(int(c["temp_hp"])).is_equal(10)
	var e: Dictionary = ConditionRules.effects(c).filter(func(x: Dictionary) -> bool: return x.has("retort"))[0]
	assert_str(str(e["retort"]["dice"])).is_equal("10")
	assert_str(SpellEffects.text(data, e)).contains("холод")
	var lines: Array[String] = []
	var hp := int(goblin["hp"])
	_hit_until(s, goblin, CombatRules.player(s), Attack.of_action(data, goblin, Sheet.template(data, goblin)["actions"][0]), lines)
	assert_int(int(goblin["hp"])).override_failure_message(" · ".join(lines)).is_equal(hp - 10)
	c["temp_hp"] = 0
	lines.clear()
	hp = int(goblin["hp"])
	Harm.retort(s, data, goblin, CombatRules.player(s), false, lines)
	assert_int(int(goblin["hp"])).is_equal(hp)


func test_the_basilisk_s_gaze_turns_to_stone() -> void:
	var s := ChecklistProbe.session(data)
	ChecklistProbe.fight(s, data, "basilisk", true)
	var z := _aura(s, "petrifying_gaze")
	z["dc"] = 99
	var hero := CombatRules.player(s)
	SpellEffects.zone_tick(s, data, hero, "start")
	assert_bool(ConditionRules.has(s.character, "restrained")).is_true()
	var held: Dictionary = ConditionRules.effects_of(s.character, "restrained")[0]
	assert_bool(bool(held["save"]["once"])).is_true()
	held["save"]["dc"] = 99
	ConditionRules.end_of_turn(s, data)
	assert_bool(ConditionRules.has(s.character, "petrified")).is_true()


func test_averted_eyes_pass_the_gaze_by() -> void:
	var s := ChecklistProbe.session(data)
	var basilisk := ChecklistProbe.fight(s, data, "basilisk")
	var hero := CombatRules.player(s)
	ConditionRules.remove(s.character, "restrained")  # the gaze may have caught it at the fight's first turn
	var avert := Acts.one("avert")
	assert_bool(avert.shown(s, data, hero)).is_true()
	ChecklistProbe.turn(s, data, hero)
	avert.go(s, data, hero)
	assert_bool(FightGrid.sees(s, data, hero, basilisk)).is_false()
	assert_bool(SpellEffects._reaches(s, data, _aura(s, "petrifying_gaze"), hero)).is_false()
	var blade := Attack.blade(s, data, hero)
	assert_array(Attack.mods(s, data, hero, basilisk, blade)["dis"]).contains(["отводит взгляд"])
	var bite := Attack.of_action(data, basilisk, Sheet.template(data, basilisk)["actions"][0])

	assert_array(Attack.mods(s, data, basilisk, hero, bite)["adv"]).contains(["вас не видно"])
	assert_str(str(avert.buttons(s, data, hero)[0]["text"])).is_equal("Смотреть снова")
	avert.go(s, data, hero)
	assert_bool(FightGrid.sees(s, data, hero, basilisk)).is_true()


func test_an_ally_averts_its_eyes_by_itself() -> void:
	var s := ChecklistProbe.session(data)
	CombatRules.start(s, data, [{"monster": "basilisk", "x": 44, "y": 30}], {"field": {"w": 80, "h": 60}, "allies": [{"monster": "guard", "x": 42, "y": 30}]})
	var guard := CombatRules.fighter(s, CombatRules.allies(s)[0])
	ChecklistProbe.turn(s, data, guard)
	assert_float(Acts.one("avert").worth(s, data, guard)).is_greater(0.0)
	var lines: Array[String] = []
	FightAI.first(s, data, guard, lines)
	assert_bool(ConditionRules.does(guard, data, "averts")).override_failure_message(" · ".join(lines)).is_true()


func test_a_ghast_s_stench_poisons_those_beside_but_not_the_ghast() -> void:
	var s := ChecklistProbe.session(data)
	var ghast := ChecklistProbe.fight(s, data, "ghast")
	var z := _aura(s, "stench")
	z["dc"] = 99
	assert_bool(SpellEffects._reaches(s, data, z, ghast)).is_false()
	SpellEffects.zone_tick(s, data, CombatRules.player(s), "start")
	assert_bool(ConditionRules.has(s.character, "poisoned")).is_true()


func test_damage_already_in_the_attack_is_marked() -> void:
	for pair: Array in [["azer", "heated_weapons"], ["bugbear", "brute"]]:
		var t: Dictionary = (data["monsters"][pair[0]]["traits"] as Array).filter(func(x: Dictionary) -> bool: return str(x["id"]) == pair[1])[0]
		assert_str(str(t.get("into", ""))).is_equal("actions")
	assert_str(str(data["spells"]["armor_of_agathys"]["name"])).is_equal("Броня Агатиса")
	assert_array(data["spells"]["armor_of_agathys"]["classes"]).contains(["warlock"])
