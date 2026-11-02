extends GdUnitTestSuite
## v0.7.63: a status is one record on anyone: one table of what it does, a boon and a curse are statuses, the die is one,
## a status lives on a character's record and goes into a fight and back.

var data: Dictionary


func before() -> void:
	data = TestUtils.data()


func _hero() -> GameSession:
	return TestUtils.new_session()


func _fight(s: GameSession, foes: Array) -> Array[Dictionary]:
	TestUtils.fight(s, data, foes, {})
	var out: Array[Dictionary] = []
	for id: String in CombatRules.enemies(s):
		out.append(CombatRules.fighter(s, id))
	return out


func test_one_table_says_what_a_status_does_to_an_attack() -> void:
	var near := ConditionRules.attack(data, {}, {"conditions": ["prone"]}, true)
	assert_array(near["adv"]).is_not_empty()
	var far := ConditionRules.attack(data, {}, {"conditions": ["prone"]}, false)
	assert_array(far["dis"]).is_not_empty()
	assert_bool(bool(ConditionRules.attack(data, {}, {"conditions": ["paralyzed"]}, true)["crit"])).is_true()
	assert_array(ConditionRules.attack(data, {"conditions": ["poisoned"]}, {}, true)["dis"]).is_not_empty()


func test_a_status_the_table_does_not_know_reads_its_own_parts() -> void:
	var f := {}
	ConditionRules.add_effect(f, {"condition": "gen:rot", "mods": {"attacked": "advantage", "attacked_why": "гниль"}})
	assert_array(ConditionRules.attack(data, {}, f, true)["adv"]).contains(["гниль"])


func test_a_boon_gives_its_numbers_while_it_lasts() -> void:
	var f := {"ac": 12}
	var uid := ConditionRules.add_effect(f, {"source": {"kind": "spell", "id": "x", "name": "X"}, "ac": 2, "speed": 10, "resist": ["fire"]})
	assert_int(CombatRules.ac_of(f)).is_equal(14)
	assert_int(ConditionRules.sum(f, "speed")).is_equal(10)
	assert_bool(ConditionRules.resisted(f, "fire")).is_true()
	ConditionRules.remove_effect(f, uid)
	assert_int(CombatRules.ac_of(f)).is_equal(12)
	assert_bool(ConditionRules.resisted(f, "fire")).is_false()


func test_one_die_for_a_blessing_and_a_curse() -> void:
	var s := _hero()
	var h := {}
	ConditionRules.add_effect(h, {"source": {"kind": "spell", "id": "bless", "name": "Благословение"}, "die": "1d4", "on": ["attack"]})
	ConditionRules.add_effect(h, {"source": {"kind": "spell", "id": "bane", "name": "Порча"}, "die": "1d1", "on": ["attack"], "minus": true})
	var r := SpellEffects.die(s, h, "attack")
	assert_int(int(r["bonus"])).is_between(0, 3)
	assert_array(r["parts"]).has_size(2)
	assert_int(int(SpellEffects.die(s, h, "save")["bonus"])).is_equal(0)


func test_a_once_die_goes_with_its_roll() -> void:
	var s := _hero()
	var h := {}
	ConditionRules.add_effect(h, {"source": {"kind": "spell", "id": "guidance", "name": "Указание"}, "die": "1d4", "on": ["check"], "once": true})
	assert_int(int(SpellEffects.die(s, h, "check")["bonus"])).is_greater(0)
	assert_array(ConditionRules.effects(h)).is_empty()


func test_the_end_of_a_spell_leaves_every_fighter_in_one_pass() -> void:
	var s := _hero()
	var foe := _fight(s, [{"monster": "goblin"}])[0]
	var ally := {}
	ConditionRules.add_effect(foe, {"condition": "cursed_dis", "source": {"kind": "spell", "id": "bestow_curse", "name": "Порча"}})
	assert_bool(CombatRules._has(foe, "cursed_dis")).is_true()
	var lines := SpellEffects.end_on_fighters(s, data, "bestow_curse")
	assert_bool(CombatRules._has(foe, "cursed_dis")).is_false()
	assert_array(lines).has_size(1)
	assert_int(ally.size()).is_equal(0)


func test_a_curses_repeat_save_is_the_status_own() -> void:
	var s := _hero()
	var foe := _fight(s, [{"monster": "goblin"}])[0]
	ConditionRules.add_effect(foe, {"condition": "enfeebled", "save": {"ability": "con", "dc": 1, "repeat": true}, "source": {"kind": "spell", "id": "ray", "name": "Луч"}})
	var lines: Array[String] = []
	for i in 8:  # a natural 1 fails even against DC 1
		lines.append_array(ConditionRules.end_of_turn(s, data, foe))
	assert_bool(CombatRules._has(foe, "enfeebled")).is_false()


func test_a_status_on_a_record_lasts_on_the_clock() -> void:
	var s := _hero()
	var b := Being.of(s, "npc_innkeeper")
	ConditionRules.add_effect(b, {"condition": "poisoned", "ends": {"at": ConditionRules.now(s) + 60 * ConditionRules.ROUNDS_PER_MINUTE}, "source": {"kind": "engine", "name": "яд"}})
	assert_str(ConditionRules.on_record(s, data, b)).contains("Отравлен")
	TimeRules.advance(s, data, 30)
	assert_bool(ConditionRules.has(Being.view(s, "npc_innkeeper"), "poisoned")).is_true()
	TimeRules.advance(s, data, 31)
	assert_bool(Being.view(s, "npc_innkeeper").has("effects")).is_false()
	assert_array(Being.check(s)).is_empty()


func test_the_master_sees_what_is_on_a_person() -> void:
	var s := _hero()
	s.room_id = str(data["world"]["npcs"]["npc_innkeeper"].get("room", s.room_id))
	ConditionRules.add_effect(Being.of(s, "npc_innkeeper"), {"condition": "poisoned", "ends": {"rest": "long"}})
	var snap := TurnSnapshot.build(s, data, 2000)
	var him: Array = snap["scene"]["npcs"].filter(func(n: Dictionary) -> bool: return n["npc_id"] == "npc_innkeeper")
	assert_str(str(him[0]["description"])).contains("На нём: Отравлен")


func test_a_status_goes_into_a_fight_and_comes_back_on_the_record() -> void:
	var s := _hero()
	var id: String = str(Being.spawn(s, {"monster": "goblin", "name": "Гоблин", "base": "Гоблин", "encounter": "t"})["id"])
	ConditionRules.add_effect(Being.of(s, id), {"condition": "poisoned", "ends": {"at": ConditionRules.now(s) + 600}})
	var f := _fight(s, [{"monster": "goblin", "id": id, "name": "Гоблин", "base": "Гоблин"}])[0]
	assert_bool(CombatRules._has(f, "poisoned")).is_true()
	assert_bool(Being.view(s, id).has("effects")).is_false()
	ConditionRules.add_effect(f, {"condition": "prone"})
	CombatRules.close(s)
	var b := Being.view(s, id)
	assert_bool(ConditionRules.has(b, "poisoned")).is_true()
	assert_bool(ConditionRules.has(b, "prone")).is_false()


func test_a_spell_on_a_follower_works_in_a_fight_and_stays_after() -> void:
	var s := _hero()
	Being.follow(s, "npc_ostap")
	AllyRules.cast_on_npc(s, data, "bless", 1, "npc_ostap")
	_fight(s, [{"monster": "goblin", "col": 2}])
	assert_bool(SpellEffects.boon(CombatRules.fighter(s, "npc_ostap"), "die") != null).is_true()
	AllyRules.drop_buffs(s, "bless")
	CombatRules.close(s)
	assert_bool(Being.view(s, "npc_ostap").has("effects")).is_true()


func test_a_save_keeps_statuses_on_a_record_and_in_a_fight() -> void:
	var s := _hero()
	ConditionRules.add_effect(Being.of(s, "npc_innkeeper"), {"condition": "poisoned", "ends": {"rest": "long"}})
	var foe := _fight(s, [{"monster": "goblin"}])[0]
	ConditionRules.add_effect(foe, {"source": {"kind": "spell", "id": "x", "name": "X"}, "ac": 2})
	var back := GameSession.from_dict(JSON.parse_string(JSON.stringify(s.to_dict(10))))
	assert_bool(ConditionRules.has(Being.view(back, "npc_innkeeper"), "poisoned")).is_true()
	assert_int(CombatRules.ac_of(CombatRules.fighter(back, str(foe["id"])))).is_equal(CombatRules.ac_of(foe))
	assert_array(Being.check(back)).is_empty()


func test_slots_hit_dice_and_features_are_one_stock() -> void:
	var s := _hero()
	var c := s.character
	c["slots_max"] = [2, 0, 0, 0, 0]
	c["level"] = 4
	Stock.spend(c, "slot_1", 2)
	Stock.spend(c, "hit_dice", 3)
	assert_int(SpellRules.slots_left(c, 1)).is_equal(0)
	assert_int(Stock.left(c, data, "slot_1")).is_equal(0)
	assert_int(ExplorationRules.hit_dice_left(c)).is_equal(1)
	Stock.recharge_all(c, data, "short")
	assert_int(Stock.spent(c, "slot_1")).is_equal(2)
	Stock.recharge_all(c, data, "long")
	assert_int(SpellRules.slots_left(c, 1)).is_equal(2)
	assert_int(Stock.spent(c, "hit_dice")).is_equal(1)  # a long rest returns half the level
	assert_bool(Stock.owned(c, data).has("slot_1")).is_false()  # no feature with uses on the sheet


func test_pact_slots_come_back_on_a_short_rest() -> void:
	var s := _hero()
	var c := s.character
	c["slots_max"] = [1, 0, 0, 0, 0]
	(c["features"] as Array).append("pact_magic")
	Stock.spend(c, "slot_1")
	Stock.recharge_all(c, data, "short")
	assert_int(SpellRules.slots_left(c, 1)).is_equal(1)


func test_a_body_is_a_status_and_gives_the_template() -> void:
	var s := _hero()
	var c := s.character
	Guise.wear(c, {"monster": "wolf", "hp": 11, "max_hp": 11}, {"kind": "feature", "id": "wild_shape", "name": "Дикий облик"})
	assert_bool(Guise.has_body(c)).is_true()
	assert_int(CharacterRules.armor_class(c, data, s.items)).is_equal(int(data["monsters"]["wolf"]["ac"]))
	assert_bool(ConditionRules.effects(c).any(func(e: Dictionary) -> bool: return e.has("guise"))).is_true()
	Guise.take_off(c)
	assert_bool(Guise.has_body(c)).is_false()


func test_a_face_is_tested_once_by_each_viewer_and_stays_in_the_save() -> void:
	var s := _hero()
	var c := s.character
	Guise.wear(c, {"name": "Старый нищий", "dc": 100}, {"kind": "spell", "id": "disguise_self", "name": "Маскировка"}, {"at": ConditionRules.now(s) + 600})
	assert_str(Guise.face(c)).is_equal("Старый нищий")
	assert_bool(Guise.fools(s, data, c, "npc_innkeeper")).is_true()
	(Guise.of(c)["seen"] as Dictionary)["npc_merchant"] = false
	var back := GameSession.from_dict(JSON.parse_string(JSON.stringify(s.to_dict(10))))
	assert_bool(Guise.fools(back, data, back.character, "npc_merchant")).is_false()
	assert_bool(Guise.fools(back, data, back.character, "npc_innkeeper")).is_true()


func test_a_wanted_hero_with_a_face_walks_past_the_guard() -> void:
	var s := _hero()
	var world := WorldView.new(data["world"])
	var loc := ""
	for l: String in data["world"]["locations"]:
		if not CrimeRules.law(data, l).get("guards", []).is_empty():
			loc = l
			break
	var guard := str(CrimeRules.law(data, loc)["guards"][0])
	s.room_id = str(world.npc(guard).get("room", s.room_id))
	s.wanted[world.location_id(s.room_id)] = TimeRules.abs_minute(s)
	Guise.wear(s.character, {"name": "Старый нищий", "dc": 100}, {"kind": "spell", "id": "disguise_self", "name": "Маскировка"})
	if s.npcs_here(world.world, s.room_id).has(guard):
		assert_array(CrimeRules.check_arrest(s, data)).is_empty()
	Guise.take_off(s.character)
	if s.npcs_here(world.world, s.room_id).has(guard):
		assert_array(CrimeRules.check_arrest(s, data)).is_not_empty()
