extends GdUnitTestSuite
## Combat details (roadmap v0.6.2): surprise (sneaking, ambush), Hide in a fight, reinforcements (pack waves, a call
## for help, the master's start_combat), parley (Intimidation, Persuasion, truce), the hit hint, sneaking outside a
## fight and the save.

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


## A fight where `first` acts first (the player by default): tests do not depend on the initiative roll.
func _fight(s: GameSession, foes: Array, source: Dictionary = {}, first: String = CombatRules.PLAYER) -> Array[String]:
	var lines := CombatRules.start(s, data, foes, source)
	var order: Array = s.combat["order"]
	order.erase(first)
	order.push_front(first)
	s.combat["turn"] = 0
	CombatRules._begin_turn(s, data, [] as Array[String])
	s.mode = GameSession.MODE_COMBAT
	return lines


## Plays turns until the given round starts.
func _to_round(s: GameSession, n: int) -> void:
	var guard := 0
	while int(s.combat["round"]) < n and guard < 40:
		guard += 1
		if CombatRules.is_player_turn(s) and not CombatRules.player_skips(s):
			CombatRules.end_player_turn(s, data)
		else:
			CombatRules.next_actor(s, data)


# --- surprise -------------------------------------------------------------------------------------


func test_a_sneaking_player_catches_the_foes_off_guard_and_starts_hidden() -> void:
	var s := _session()
	s.character["skills"]["stealth"] = 40
	var lines := _fight(s, [{"monster": "wolf", "count": 2}], {"sneak": true}, "e1")
	assert_str("\n".join(lines)).contains("застигнуты врасплох")
	assert_bool(bool(CombatRules.fighter(s, "e1").get("surprised", false))).is_true()
	assert_bool(bool(CombatRules.player(s).get("hidden", false))).is_true()
	var turn := CombatRules.next_actor(s, data)  # the surprised wolf loses its turn
	assert_str("\n".join(turn)).contains("врасплох")
	assert_int(int(s.character["hp"])).is_equal(int(s.character["max_hp"]))
	assert_bool(TurnSnapshot.build(s, data, 4000)["combat"]["player_hidden"]).is_true()


func test_a_clumsy_sneak_is_noticed() -> void:
	var s := _session()
	s.character["skills"]["stealth"] = -40
	var lines := _fight(s, [{"monster": "wolf"}], {"sneak": true})
	assert_str("\n".join(lines)).contains("замечают")
	assert_bool(bool(CombatRules.fighter(s, "e1").get("surprised", false))).is_false()
	assert_bool(bool(CombatRules.player(s).get("hidden", false))).is_false()


func test_an_ambush_surprises_an_inattentive_player_who_loses_the_first_turn() -> void:
	var s := _session()
	s.character["passive_perception"] = -20
	var lines := _fight(s, [{"monster": "wolf"}], {"ambush": true})
	assert_str("\n".join(lines)).contains("Засада")
	assert_bool(CombatRules.player_skips(s)).is_true()
	assert_bool(CombatRules.player_can_act(s)).is_false()
	var turn := CombatRules.next_actor(s, data)
	assert_str("\n".join(turn)).contains("врасплох")
	assert_str(CombatRules.current(s)).is_equal("e1")
	_to_round(s, 2)
	assert_bool(bool(CombatRules.player(s).get("surprised", false))).is_false()


func test_an_attentive_player_spots_the_ambush() -> void:
	var s := _session()
	s.character["passive_perception"] = 99
	var lines := _fight(s, [{"monster": "wolf"}], {"ambush": true})
	assert_str("\n".join(lines)).contains("вовремя замечает")
	assert_bool(CombatRules.player_skips(s)).is_false()


func test_heavy_armor_gives_disadvantage_on_stealth() -> void:
	var s := _session()
	s.character["equipped"]["armor"] = "chain_mail"
	assert_str(str(CombatRules.stealth_roll(s, data)["note"])).contains("доспех")
	s.character["equipped"]["armor"] = ""
	assert_str(str(CombatRules.stealth_roll(s, data)["note"])).is_empty()


# --- hide -----------------------------------------------------------------------------------------


func test_hiding_needs_distance_and_gives_advantage_until_the_attack() -> void:
	var s := _session()
	_fight(s, [{"monster": "goblin", "col": 0}])
	assert_str(CombatRules.can_hide(s, data)).is_equal("COMBAT_HIDE_SEEN")
	CombatRules.fighter(s, "e1")["col"] = 2
	s.character["skills"]["stealth"] = 40
	assert_str(CombatRules.can_hide(s, data)).is_empty()
	var lines := CombatRules.player_hide(s, data)
	assert_str(lines[0]).contains("теряют из виду")
	assert_bool(bool(CombatRules.player(s)["hidden"])).is_true()
	assert_int(int(CombatRules.economy(s)["action"])).is_equal(0)
	assert_str(CombatRules.can_hide(s, data)).is_equal("COMBAT_ALREADY_HIDDEN")
	assert_array(CombatRules.attack_preview(s, data, "e1")["adv"]).contains(["вы спрятаны"])
	# Foes attack a hidden player with disadvantage.
	var bow := CombatRules._best_action(data, CombatRules.fighter(s, "e1"), "ranged")
	var hits: Array[String] = []
	CombatRules._enemy_attack(s, data, CombatRules.fighter(s, "e1"), bow, hits)
	assert_str(hits[0]).contains("с помехой")


func test_the_rogue_hides_as_a_bonus_action_and_an_attack_reveals() -> void:
	var s := _session("rogue_damir")
	(s.character["features"] as Array).append("cunning_action")  # level 2
	_fight(s, [{"monster": "goblin", "col": 2}])
	s.character["skills"]["stealth"] = 40
	CombatRules.player_hide(s, data)
	assert_int(int(CombatRules.economy(s)["bonus"])).is_equal(0)
	assert_int(int(CombatRules.economy(s)["action"])).is_equal(1)
	s.character["equipped"]["main_hand"] = "shortbow"
	CombatRules.player_attack(s, data, "e1")
	assert_bool(bool(CombatRules.player(s)["hidden"])).is_false()


func test_a_foe_coming_close_finds_the_hidden_player() -> void:
	var s := _session()
	_fight(s, [{"monster": "wolf", "col": 1}])
	CombatRules.player(s)["hidden"] = true
	CombatRules.end_player_turn(s, data)
	var lines := CombatRules.next_actor(s, data)
	assert_str("\n".join(lines)).contains("находит")
	assert_bool(bool(CombatRules.player(s)["hidden"])).is_false()


# --- reinforcements -------------------------------------------------------------------------------


func test_a_pack_wave_waits_at_the_edge_and_arrives_at_its_round() -> void:
	var s := _session()
	_fight(s, [{"monster": "goblin", "col": 2}], {"waves": [{"round": 2, "side": "left", "enemies": [{"monster": "goblin"}]}]})
	assert_array(s.combat["incoming"]).has_size(1)
	var snap: Dictionary = CombatRules.snapshot(s, data)
	assert_str(snap["incoming"][0]["side"]).is_equal("left")
	assert_int(snap["incoming"][0]["in_rounds"]).is_equal(1)
	s.character["hp"] = 999  # survive the goblin
	s.character["max_hp"] = 999
	var lines := CombatRules.end_player_turn(s, data)
	lines.append_array(CombatRules.next_actor(s, data))
	assert_int(int(s.combat["round"])).is_equal(2)
	assert_str("\n".join(lines)).contains("Подкрепление слева")
	assert_array(s.combat["incoming"]).is_empty()
	var newcomer := CombatRules.fighter(s, "e2")
	assert_int(int(newcomer["col"])).is_equal(-3)
	assert_str(str(newcomer["name"])).is_equal("Гоблин 2")
	assert_array(s.combat["order"]).contains(["e2"])


func test_a_hurt_intelligent_foe_calls_for_help_once() -> void:
	var s := _session()
	_fight(s, [{"monster": "bandit", "col": 0}], {"help": {"side": "right", "delay": 2, "enemies": [{"monster": "bandit", "count": 2}]}})
	var b := CombatRules.fighter(s, "e1")
	b["hp"] = 2
	b["morale"] = true  # no morale roll in this test
	CombatRules.end_player_turn(s, data)
	var lines := CombatRules.next_actor(s, data)
	assert_str("\n".join(lines)).contains("зовёт на помощь")
	assert_array(s.combat["incoming"]).has_size(1)
	assert_int(int(s.combat["incoming"][0]["at"])).is_equal(3)
	assert_int(int(s.combat["incoming"][0]["col"])).is_equal(3)
	_to_round(s, 2)
	CombatRules.end_player_turn(s, data)
	assert_str("\n".join(CombatRules.next_actor(s, data))).not_contains("зовёт на помощь")


func test_the_master_reinforces_within_the_budget() -> void:
	var s := _session()
	_fight(s, [{"monster": "jackal", "col": 2}])
	var fx := EffectEngine.new()
	var ok := fx.validate(s, data, "t-1", {"kind": "start_combat", "enemies": [{"monster": "jackal", "count": 2}], "side": "left"})
	assert_bool(ok["accepted"]).is_true()
	fx.apply(s, "t-1", [ok["effect_id"]])
	assert_array(s.combat["incoming"]).has_size(1)
	assert_int(int(s.combat["incoming"][0]["col"])).is_equal(-3)
	assert_int(int(s.combat["incoming"][0]["at"])).is_equal(2)
	var heavy := fx.validate(s, data, "t-2", {"kind": "start_combat", "enemies": [{"monster": "wolf", "count": 2}]})
	assert_str(str(heavy.get("reason", ""))).contains("не по силам")


# --- parley ---------------------------------------------------------------------------------------


func test_parley_needs_intelligent_foes_and_one_try_per_skill() -> void:
	var s := _session()
	_fight(s, [{"monster": "wolf", "col": 1}])
	assert_str(CombatRules.can_parley(s, data, "intimidation")).is_equal("COMBAT_NO_PARLEY")
	var b := _session()
	_fight(b, [{"monster": "bandit", "col": 1}])
	assert_str(CombatRules.can_parley(b, data, "persuasion")).is_empty()
	assert_str(CombatRules.can_parley(b, data, "deception")).is_equal("COMBAT_NO_PARLEY")
	var lines := CombatRules.parley_apply(b, data, "persuasion", false)
	assert_str(lines[0]).contains("не слушают")
	assert_str(CombatRules.can_parley(b, data, "persuasion")).is_equal("COMBAT_PARLEY_TRIED")
	assert_str(CombatRules.can_parley(b, data, "intimidation")).is_empty()


func test_the_parley_dc_falls_with_every_foe_out() -> void:
	var s := _session()
	_fight(s, [{"monster": "bandit", "count": 3, "col": 1}])
	var full := CombatRules.parley_dc(s, data)
	assert_int(full).is_equal(12 + CharacterRules.mod(int(data["monsters"]["bandit"]["abilities"]["wis"])))
	CombatRules.fighter(s, "e1")["status"] = "dead"
	assert_int(CombatRules.parley_dc(s, data)).is_equal(full - 2)


func test_intimidation_makes_foes_surrender_or_flee_and_the_fight_is_won() -> void:
	var s := _session()
	_fight(s, [{"monster": "bandit", "col": 0}, {"monster": "bandit", "col": 2}, {"monster": "wolf", "col": 3}])
	var lines := CombatRules.parley_apply(s, data, "intimidation", true)
	assert_str(CombatRules.fighter(s, "e1")["status"]).is_equal("surrendered")
	assert_str(CombatRules.fighter(s, "e2")["status"]).is_equal("fled")
	assert_str(CombatRules.fighter(s, "e3")["status"]).is_equal("active")  # the beast fights on
	assert_int(lines.size()).is_equal(2)
	CombatRules.fighter(s, "e3")["status"] = "dead"
	CombatRules.after_player_action(s, data)
	assert_str(s.combat["outcome"]).is_equal("victory")


func test_persuasion_ends_the_fight_in_a_truce_with_full_xp_and_no_encounter_loot() -> void:
	var s := _session()
	_fight(s, [{"monster": "bandit", "count": 2, "col": 1}])
	CombatRules.parley_apply(s, data, "persuasion", true)
	assert_str(CombatRules.health_key(CombatRules.fighter(s, "e1"))).is_equal("HEALTH_TRUCE")
	CombatRules.after_player_action(s, data)
	assert_str(s.combat["outcome"]).is_equal("truce")
	CombatRules.results(s, data, {"coins_cp": 500, "items": {"healing_potion": 1}})
	assert_int(int(s.combat["xp"])).is_equal(2 * int(data["monsters"]["bandit"]["xp"]))
	assert_int(int(s.combat["coins_cp"])).is_equal(0)
	assert_array(s.combat["loot"]).is_empty()


func test_the_masters_intimidation_check_in_a_fight_is_a_parley() -> void:
	var s := _session()
	_fight(s, [{"monster": "bandit", "col": 0}])
	GameState.session = s
	GameState.busy_turn = "t-9"
	var r := GameState.handle_engine_check({"turn_id": "t-9", "skill": "intimidation", "dc_tier": "easy"})
	assert_int(int(r["dc"])).is_equal(CombatRules.parley_dc(s, data))
	assert_str(str(r["note"])).contains("Переговоры")
	assert_array(s.combat["parley_tried"]).contains(["intimidation"])


# --- the hint -------------------------------------------------------------------------------------


func test_hit_chance_and_dice_range() -> void:
	assert_int(CombatRules.hit_chance(5, 15, false, false)).is_equal(55)
	assert_int(CombatRules.hit_chance(5, 15, true, false)).is_equal(80)
	assert_int(CombatRules.hit_chance(5, 15, false, true)).is_equal(30)
	assert_int(CombatRules.hit_chance(5, 15, true, true)).is_equal(55)
	assert_int(CombatRules.hit_chance(20, 10, false, false)).is_equal(95)
	assert_int(CombatRules.hit_chance(0, 30, false, false)).is_equal(5)
	assert_array(CombatRules.dice_range("2d6+3")).is_equal([5, 15])
	assert_array(CombatRules.dice_range("1d8-1")).is_equal([0, 7])


func test_the_attack_preview_shows_the_chance_and_the_reasons() -> void:
	var s := _session()
	_fight(s, [{"monster": "goblin", "col": 0}])
	var w := CombatRules.weapon_profile(s.character, data, s.items, str(s.character["equipped"]["main_hand"]))
	var pv := CombatRules.attack_preview(s, data, "e1")
	assert_int(pv["chance"]).is_equal(CombatRules.hit_chance(int(w["to_hit"]), 15, false, false))
	var r := CombatRules.dice_range(str(w["dice"]))
	assert_int(pv["max"]).is_equal(r[1] + int(w["bonus"]))
	CombatRules.fighter(s, "e1")["dodging"] = true
	assert_array(CombatRules.attack_preview(s, data, "e1")["dis"]).contains(["цель уклоняется"])


func test_the_spell_preview_attack_or_save() -> void:
	var s := _session("wizard_yalika")
	_fight(s, [{"monster": "goblin", "col": 2}])
	var bolt := CombatRules.cast_preview(s, data, "fire_bolt", 0, "e1")
	assert_bool(bolt["save"]).is_false()
	assert_int(bolt["chance"]).is_between(5, 95)
	var flame := CombatRules.cast_preview(s, data, "sacred_flame", 0, "e1")
	assert_bool(flame["save"]).is_true()
	var darts := CombatRules.cast_preview(s, data, "magic_missile", 1, "e1")
	assert_int(darts["chance"]).is_equal(100)
	assert_int(darts["count"]).is_equal(3)
	assert_dict(CombatRules.cast_preview(s, data, "cure_wounds", 1, "e1")).is_empty()


# --- sneaking outside a fight and the save -------------------------------------------------------


func test_sneaking_lowers_passive_perception_for_hidden_things() -> void:
	var world: Dictionary = data["world"]
	for rid: String in world["rooms"]:
		for sec: Dictionary in ExplorationRules.secrets(world, rid):
			if str(sec.get("skill", "perception")) != "perception":
				continue
			var s := _session()
			s.character["passive_perception"] = int(sec["dc"])
			s.sneaking = true
			assert_array(ExplorationRules.enter_room(s, world, rid)).is_empty()
			var t := _session()
			t.character["passive_perception"] = int(sec["dc"])
			assert_array(ExplorationRules.enter_room(t, world, rid)).is_not_empty()
			return
	fail("no perception secret in the pack")


func test_sneaking_and_reinforcements_survive_the_save() -> void:
	var s := _session()
	s.sneaking = true
	_fight(s, [{"monster": "goblin", "col": 2}], {"waves": [{"round": 3, "side": "right", "enemies": [{"monster": "wolf", "count": 2}]}]})
	var back := GameSession.from_dict(JSON.parse_string(JSON.stringify(s.to_dict(500))))
	assert_bool(back.sneaking).is_true()
	assert_dict(back.combat).is_equal(s.combat)
	var v9: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://test/fixtures/saves/save_v9.json"))
	SaveFormat.migrate(v9, {})
	assert_bool(v9["session"]["sneaking"]).is_false()
