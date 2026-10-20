extends GdUnitTestSuite
## «Правила 5e: состояния и урон по герою» (roadmap v0.7.8): effects on the hero with a source, a duration on the game
## clock and repeat saves; the master's conditions with an engine save, a tag and a duration; the 15 conditions in
## checks and in a fight; exhaustion from the march and a day awake, the camp with food; resistances, save advantages
## and immunities of races; concentration; cures; Relentless Endurance; invisible foes.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func after_test() -> void:
	GameState.session = null
	GameState.busy_turn = ""
	GameState.combat_playing = false


func _session(preset_id: String = "fighter_aira") -> GameSession:
	var s := TestUtils.new_session()
	for p: Dictionary in data["presets"]:
		if p["id"] == preset_id:
			s.character = GameSession.normalized_character(CharacterBuilder.build_preset(p, data))
	CharacterRules.refresh(s.character, data)
	return s


func _fight(s: GameSession, foes: Array) -> String:
	CombatRules.start(s, data, foes, {})
	var order: Array = s.combat["order"]
	order.erase(CombatRules.PLAYER)
	order.push_front(CombatRules.PLAYER)
	s.combat["turn"] = 0
	CombatRules._begin_turn(s, data, [] as Array[String])
	s.mode = GameSession.MODE_COMBAT
	return CombatRules.enemies(s)[0]


func _fx(s: GameSession, turn: String, e: Dictionary) -> Dictionary:
	var fx := EffectEngine.new()
	var r := fx.validate(s, data, turn, e)
	if r["accepted"]:
		fx.apply(s, turn, [r["effect_id"]])
	return r


# --- effects and the clock --------------------------------------------------------------------------------


func test_an_effect_runs_out_on_the_game_clock() -> void:
	var s := _session()
	var c := s.character
	ConditionRules.add_effect(c, {"condition": "poisoned", "ends": ConditionRules.ends_for(s, data, "hour"), "source": {"kind": "master", "name": "яд в кружке"}})
	assert_bool(ConditionRules.has(c, "poisoned")).is_true()
	assert_str(ConditionRules.shown(s, data)[0]["left"]).is_equal("1 ч 0 мин")
	TimeRules.advance(s, data, 30)
	assert_bool(ConditionRules.has(c, "poisoned")).is_true()
	var lines := TimeRules.advance(s, data, 30)
	assert_bool(ConditionRules.has(c, "poisoned")).is_false()
	assert_str(", ".join(lines)).contains("отравлен")


func test_a_rest_ends_rest_bound_effects_only() -> void:
	var s := _session()
	var c := s.character
	ConditionRules.add_effect(c, {"condition": "frightened", "ends": {"rest": "short"}})
	ConditionRules.add_effect(c, {"condition": "charmed", "ends": {"rest": "long"}})
	ConditionRules.add_effect(c, {"condition": "blinded", "ends": {}})
	ExplorationRules.short_rest(s, data, 0, s.rng)
	assert_array(c["conditions"]).contains_exactly_in_any_order(["charmed", "blinded"])
	s.room_id = "brod-temple"
	ExplorationRules.long_rest(s, data)
	assert_array(c["conditions"]).is_equal(["blinded"])  # until removed: a curse outlives a night


func test_a_spells_concentration_ends_with_its_duration() -> void:
	var s := _session("wizard_yalika")
	var c := s.character
	SpellRules.cast(c, data, "invisibility", 2, s)
	assert_int(int(c["concentration_ends"])).is_equal(ConditionRules.now(s) + 600)  # «вплоть до 1 часа»
	TimeRules.advance(s, data, 61)
	assert_str(str(c["concentration"])).is_empty()


func test_damage_calls_for_a_concentration_save() -> void:
	var s := _session("wizard_yalika")
	var c := s.character
	c["concentration"] = "invisibility"
	c["saves"]["con"] = -20  # cannot make it
	var lines := HeroDefense.after_damage(s, data, 30)
	assert_str(str(c["concentration"])).is_empty()
	assert_str(", ".join(lines)).contains("прервана")


# --- the master's conditions ------------------------------------------------------------------------------


func test_the_master_needs_a_save_unless_the_hero_did_it() -> void:
	var s := _session()
	var no_save := _fx(s, "t-1", {"kind": "condition", "condition": "poisoned", "reason": "яд", "duration": "hour"})
	assert_bool(no_save["accepted"]).is_false()
	assert_str(str(no_save["reason"])).contains("спасброс")
	var claimed := _fx(s, "t-2", {"kind": "condition", "condition": "poisoned", "reason": "яд", "duration": "hour", "cause": "player"})
	assert_bool(claimed["accepted"]).is_false()  # not a turn of the player's own words
	var fx := EffectEngine.new()
	fx.player_turns["t-3"] = true
	var drank := fx.validate(s, data, "t-3", {"kind": "condition", "condition": "poisoned", "reason": "выпил из склянки", "duration": "hour", "cause": "player"})
	assert_bool(drank["accepted"]).is_true()
	fx.apply(s, "t-3", [drank["effect_id"]])
	assert_bool(ConditionRules.has(s.character, "poisoned")).is_true()
	assert_str(str(ConditionRules.effects_of(s.character, "poisoned")[0]["source"]["name"])).is_equal("выпил из склянки")


func test_the_engine_rolls_the_masters_save() -> void:
	var s := _session()
	s.character["saves"]["con"] = 40
	var r := _fx(s, "t-1", {"kind": "condition", "condition": "poisoned", "reason": "яд в кружке", "duration": "hour",
		"save": {"ability": "con", "dc_tier": "hard"}, "tag": "poison"})
	assert_bool(r["accepted"]).is_true()
	assert_str(str(r["summary"])).contains("устоял")
	assert_bool(ConditionRules.has(s.character, "poisoned")).is_false()
	s.character["saves"]["con"] = -40
	r = _fx(s, "t-2", {"kind": "condition", "condition": "poisoned", "reason": "яд в кружке", "duration": "hour",
		"save": {"ability": "con", "dc_tier": "hard"}, "tag": "poison"})
	assert_str(str(r["summary"])).contains("провал")
	assert_bool(ConditionRules.has(s.character, "poisoned")).is_true()


func test_an_elf_cannot_be_put_to_sleep_by_magic() -> void:
	var s := _session("wizard_yalika")
	var r := _fx(s, "t-1", {"kind": "condition", "condition": "unconscious", "reason": "колыбельная феи", "duration": "minute",
		"save": {"ability": "wis", "dc_tier": "hard"}, "tag": "sleep"})
	assert_str(str(r["summary"])).contains("не действует")
	assert_bool(ConditionRules.has(s.character, "unconscious")).is_false()


func test_sleep_outside_a_fight_needs_a_time_and_passes() -> void:
	var s := _session()
	var bad := _fx(s, "t-1", {"kind": "condition", "condition": "unconscious", "reason": "сонное зелье", "duration": "long_rest",
		"save": {"ability": "con", "dc_tier": "hard"}, "tag": "sleep"})
	assert_bool(bad["accepted"]).is_false()
	GameState.start(s)
	s.character["saves"]["con"] = -40
	var r := _fx(s, "t-2", {"kind": "condition", "condition": "unconscious", "reason": "сонное зелье", "duration": "hour",
		"save": {"ability": "con", "dc_tier": "hard"}, "tag": "sleep"})
	assert_bool(r["accepted"]).is_true()
	var before := TimeRules.abs_minute(s)
	GameState._apply_result(s, "t-3", {"narration": "сон"})
	assert_int(TimeRules.abs_minute(s) - before).is_equal(60)
	assert_bool(ConditionRules.has(s.character, "unconscious")).is_false()


func test_a_cure_cast_on_oneself_lifts_poison() -> void:
	var s := _session("cleric_branko")
	var c := s.character
	ConditionRules.add_effect(c, {"condition": "poisoned", "ends": {}})
	ConditionRules.cure(s, data, data["rules"]["hero_effects"]["spell_cures"]["lesser_restoration"], {"kind": "spell", "name": "Малое восстановление"})
	assert_bool(ConditionRules.has(c, "poisoned")).is_false()


func test_antitoxin_gives_advantage_on_poison_saves_for_an_hour() -> void:
	var s := _session()
	var c := s.character
	c["inventory"]["antitoxin"] = 1
	ItemRules.use(c, data, s.items, "antitoxin", s.rng, s)
	assert_array(HeroDefense.save_advantages(c, data, "con", "poison")).is_not_empty()
	TimeRules.advance(s, data, 61)
	assert_array(HeroDefense.save_advantages(c, data, "con", "poison")).is_empty()


# --- checks -----------------------------------------------------------------------------------------------


func test_senses_and_incapacitation_in_checks() -> void:
	var c := _session().character
	ConditionRules.add_effect(c, {"condition": "deafened", "ends": {}})
	assert_array(ConditionRules.check_mods(c, data, {"skill": "perception", "sense": "hearing"})["auto_fail"]).contains(["deafened"])
	assert_array(ConditionRules.check_mods(c, data, {"skill": "perception", "sense": "sight"})["auto_fail"]).is_empty()
	ConditionRules.add_effect(c, {"condition": "blinded", "ends": {}})
	assert_array(ConditionRules.check_mods(c, data, {"skill": "investigation"})["auto_fail"]).contains(["blinded"])
	var d := _session().character
	ConditionRules.add_effect(d, {"condition": "incapacitated", "ends": {}})
	assert_array(ConditionRules.check_mods(d, data, {"skill": "persuasion"})["auto_fail"]).is_empty()  # 5e: checks still go


# --- exhaustion and the camp ------------------------------------------------------------------------------


func test_exhaustion_levels_by_5e() -> void:
	var s := _session()
	var c := s.character
	var hp := int(c["max_hp"])
	var speed := int(c["speed"])
	ConditionRules.add_exhaustion(s, data, 1, "")
	assert_array(ConditionRules.check_mods(c, data, {"skill": "athletics"})["disadvantage"]).contains(["exhaustion"])
	ConditionRules.add_exhaustion(s, data, 1, "")
	assert_int(int(c["speed"])).is_equal(speed / 2)
	ConditionRules.add_exhaustion(s, data, 2, "")
	assert_int(int(c["max_hp"])).is_equal(hp / 2)
	ConditionRules.add_exhaustion(s, data, 1, "")
	assert_int(int(c["speed"])).is_equal(0)
	assert_bool(ConditionRules.dead(c)).is_false()
	ConditionRules.add_exhaustion(s, data, 1, "")
	assert_bool(ConditionRules.dead(c)).is_true()


func test_a_long_march_and_a_day_awake_tire_the_hero() -> void:
	var s := _session()
	s.character["saves"]["con"] = -40
	TimeRules.march(s, data, 8 * 60)
	assert_int(ConditionRules.exhaustion(s.character)).is_equal(0)
	var lines := TimeRules.march(s, data, 60)
	assert_int(ConditionRules.exhaustion(s.character)).is_equal(1)
	assert_str(", ".join(lines)).contains("Марш 9 ч")
	s.character["saves"]["con"] = -40  # the sheet was refreshed by the new level
	TimeRules.advance(s, data, 24 * 60)
	assert_int(ConditionRules.exhaustion(s.character)).is_equal(2)  # a day without a long rest


func test_a_camp_eats_food_and_a_long_rest_takes_all_exhaustion() -> void:
	var s := _session()
	var c := s.character
	c["inventory"].erase("rations")
	s.room_id = "brod-tavern-hall"
	assert_str(ExplorationRules.can_camp(s, data)).is_equal("REST_NO_FOOD")
	c["inventory"]["bread"] = 1
	c["inventory"]["rations"] = 2
	assert_dict(ExplorationRules.camp_default(c, data)).is_equal({"bread": 1, "rations": 1})
	assert_str(ExplorationRules.camp_error(s, data, {"rations": 3})).is_equal("REST_BAD_SUPPLIES")
	assert_str(ExplorationRules.camp_error(s, data, {"bread": 1})).is_equal("REST_NO_FOOD")
	ConditionRules.add_exhaustion(s, data, 3, "")
	ExplorationRules.long_rest(s, data, {"rations": 1})
	assert_int(int(c["inventory"]["rations"])).is_equal(1)
	assert_int(ConditionRules.exhaustion(c)).is_equal(0)


func test_no_camp_where_a_fight_still_waits() -> void:
	var s := _session()
	s.character["inventory"]["rations"] = 2
	for rid: String in data["world"]["rooms"]:
		if not (data["world"]["rooms"][rid].get("encounter", {}) as Dictionary).is_empty():
			s.room_id = rid
			break
	assert_str(ExplorationRules.can_camp(s, data)).is_equal("REST_DANGER")


# --- damage to the hero -----------------------------------------------------------------------------------


func test_race_resistances_and_save_advantages() -> void:
	var dwarf := _session("cleric_branko")
	assert_int(int(HeroDefense.adjust(dwarf, data, "poison", 10)["damage"])).is_equal(5)
	assert_array(HeroDefense.save_advantages(dwarf.character, data, "con", "poison")).is_not_empty()
	var tiefling := _session("rogue_damir")
	assert_str(str(HeroDefense.adjust(tiefling, data, "fire", 10)["note"])).contains("сопротивление")
	var gnome := _session("warlock_fiber")
	assert_array(HeroDefense.save_advantages(gnome.character, data, "wis", "magic")).is_not_empty()
	assert_array(HeroDefense.save_advantages(gnome.character, data, "dex", "magic")).is_empty()
	var halfling := _session("druid_olha")
	assert_array(HeroDefense.save_advantages(halfling.character, data, "wis", "fear")).is_not_empty()
	var dragonborn := _session("paladin_gordey")
	assert_dict(HeroDefense.resistances(dragonborn, data)).is_not_empty()
	var human := _session()
	assert_int(int(HeroDefense.adjust(human, data, "fire", 10)["damage"])).is_equal(10)


func test_rage_resists_weapons_in_a_fight() -> void:
	var s := _session("barbarian_urga")
	_fight(s, [{"monster": "goblin", "col": 0}])
	s.combat["raging"] = true
	assert_int(int(HeroDefense.adjust(s, data, "slashing", 8)["damage"])).is_equal(4)
	assert_int(int(HeroDefense.adjust(s, data, "fire", 8)["damage"])).is_equal(8)


func test_relentless_endurance_once_a_long_rest() -> void:
	var s := _session("barbarian_urga")
	var c := s.character
	c["hp"] = 0
	var lines: Array[String] = []
	assert_bool(HeroDefense.relentless(s, data, lines)).is_true()
	assert_int(int(c["hp"])).is_equal(1)
	c["hp"] = 0
	assert_bool(HeroDefense.relentless(s, data, lines)).is_false()
	s.room_id = "brod-temple"
	ExplorationRules.long_rest(s, data)
	c["hp"] = 0
	assert_bool(HeroDefense.relentless(s, data, lines)).is_true()


# --- the fight --------------------------------------------------------------------------------------------


func test_prone_hero_stands_with_the_whole_move() -> void:
	var s := _session()
	_fight(s, [{"monster": "goblin", "col": 2}])
	ConditionRules.add_effect(s.character, {"condition": "prone", "ends": {}})
	assert_str(CombatRules.can_move(s, data, 1)).is_equal("COMBAT_PRONE")
	assert_str(CombatRules.can_stand(s)).is_empty()
	CombatRules.stand(s)
	assert_bool(ConditionRules.has(s.character, "prone")).is_false()
	assert_str(CombatRules.can_move(s, data, 1)).is_equal("COMBAT_NO_MOVE")


func test_a_grappled_hero_breaks_free_with_an_action() -> void:
	var s := _session()
	var gob := _fight(s, [{"monster": "goblin", "col": 0}])
	ConditionRules.add_effect(s.character, {"condition": "grappled", "ends": {}, "by": gob})
	CharacterRules.refresh(s.character, data, s.items)
	assert_str(CombatRules.can_move(s, data, 1)).is_equal("COMBAT_NO_SPEED")
	assert_str(CombatRules.can_escape(s)).is_empty()
	s.character["skills"]["athletics"] = 40
	var lines := CombatRules.escape(s, data)
	assert_str(", ".join(lines)).contains("больше не")
	assert_bool(ConditionRules.has(s.character, "grappled")).is_false()
	assert_str(CombatRules.can_escape(s)).is_equal("COMBAT_NOT_HELD")


func test_fear_keeps_the_hero_from_its_source_and_charm_from_the_charmer() -> void:
	var s := _session()
	var gob := _fight(s, [{"monster": "goblin", "col": 2}])
	ConditionRules.add_effect(s.character, {"condition": "frightened", "ends": {}, "by": gob})
	assert_str(CombatRules.can_move(s, data, 1)).is_equal("COMBAT_FRIGHTENED")
	assert_str(CombatRules.can_move(s, data, -1)).is_empty()
	ConditionRules.add_effect(s.character, {"condition": "charmed", "ends": {}, "by": gob})
	assert_str(CombatRules.can_attack(s, data, gob)).is_equal("COMBAT_CHARMED")


func test_a_paralysed_hero_loses_the_turn_and_shakes_it_off_with_a_save() -> void:
	var s := _session()
	_fight(s, [{"monster": "goblin", "col": 3}])
	s.character["saves"]["wis"] = 40
	ConditionRules.add_effect(s.character, {"condition": "paralyzed", "ends": {"at": ConditionRules.now(s) + 10},
		"save": {"ability": "wis", "dc": 12, "tag": "magic", "repeat": true}, "source": {"kind": "master", "name": "взгляд"}})
	assert_bool(CombatRules.player_skips(s)).is_true()
	var lines := CombatRules.next_actor(s, data)
	assert_str(", ".join(lines)).contains("не может действовать")
	for i in 10:  # a natural 1 still fails: a few more turns at most
		if not ConditionRules.has(s.character, "paralyzed"):
			break
		ConditionRules.end_of_turn(s, data)
	assert_bool(ConditionRules.has(s.character, "paralyzed")).is_false()


func test_the_hero_held_for_good_loses_the_fight() -> void:
	var s := _session()
	_fight(s, [{"monster": "goblin", "col": 3}])
	ConditionRules.add_effect(s.character, {"condition": "petrified", "ends": {}})
	CombatRules.next_actor(s, data)
	assert_str(str(s.combat["outcome"])).is_equal("captured")  # goblins are clever enough to take a statue


func test_blinded_and_prone_hero_attacks_with_disadvantage() -> void:
	var s := _session()
	var gob := _fight(s, [{"monster": "goblin", "col": 0}])
	ConditionRules.add_effect(s.character, {"condition": "blinded", "ends": {}})
	var w := CombatRules.weapon_profile(s.character, data, s.items, str(s.character["equipped"]["main_hand"]))
	var mods := CombatRules._attack_mods(s, data, w, CombatRules.fighter(s, gob))
	assert_array(mods["dis"]).contains(["вы ослеплены"])


func test_an_invisible_foe_that_moved_is_missed() -> void:
	var s := _session()
	var gob := _fight(s, [{"monster": "goblin", "col": 0}])
	var f := CombatRules.fighter(s, gob)
	CombatRules._hold(f, "invisible")
	f["col"] = 2  # it slipped away unseen
	assert_int(CombatRules.shown_col(f)).is_equal(0)
	assert_str(CombatRules.can_attack(s, data, gob)).is_empty()  # the hero swings where it was
	var lines := CombatRules.player_attack(s, data, gob)
	assert_str(", ".join(lines)).contains("в пустоту")
	assert_int(int(f["hp"])).is_equal(int(f["max_hp"]))


func test_exhaustion_six_in_a_fight_is_death() -> void:
	var s := _session()
	_fight(s, [{"monster": "goblin", "col": 3}])
	ConditionRules.add_exhaustion(s, data, 6, "")
	assert_str(str(s.combat["outcome"])).is_equal("dead")


# --- saves ------------------------------------------------------------------------------------------------


func test_an_old_save_keeps_its_conditions_as_effects() -> void:
	var old := {"save_version": 17, "session": {"day": 3, "minute": 600, "character": {"conditions": ["poisoned", "prone"],
		"condition_ends": {"poisoned": "short_rest", "prone": "long_rest"}}}}
	SaveFormat.migrate(old)
	var c: Dictionary = old["session"]["character"]
	assert_int((c["effects"] as Array).size()).is_equal(2)
	assert_dict(c["effects"][0]["ends"]).is_equal({"rest": "short"})
	assert_bool(c.has("condition_ends")).is_false()
	assert_int(int(old["session"]["rested_at"])).is_equal(2 * 1440 + 600)
