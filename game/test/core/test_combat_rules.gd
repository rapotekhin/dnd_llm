extends GdUnitTestSuite
## CombatRules (roadmap v0.6.1, ADR-0010 §7): the 7-column field, initiative, attacks and their economy, reach and
## range, opportunity attacks and fleeing, spells, the enemy AI and morale, death saves, results, effects in a
## fight, the snapshot and saves.

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


## A fight where the player acts first: the order is rewritten so tests do not depend on the initiative roll.
func _fight(s: GameSession, foes: Array) -> void:
	CombatRules.start(s, data, foes)
	var order: Array = s.combat["order"]
	order.erase(CombatRules.PLAYER)
	order.push_front(CombatRules.PLAYER)
	s.combat["turn"] = 0
	CombatRules._begin_turn(s, data, [] as Array[String])


func test_monsters_come_from_the_srd_with_russian_names() -> void:
	assert_int(data["monsters"].size()).is_greater(150)
	var g: Dictionary = data["monsters"]["goblin"]
	assert_str(g["name"]).is_equal("Гоблин")
	assert_int(int(g["ac"])).is_equal(15)
	assert_array(g["actions"].map(func(a: Dictionary) -> String: return a["kind"])).contains(["melee", "ranged"])


func test_a_fight_starts_with_initiative_and_the_field() -> void:
	var s := _session()
	var lines := CombatRules.start(s, data, [{"monster": "goblin", "count": 2}, {"monster": "wolf"}])
	assert_str(lines[0]).contains("Инициатива")
	assert_array(s.combat["order"]).has_size(4)
	assert_int(int(CombatRules.player(s)["col"])).is_equal(0)
	for id: String in CombatRules.enemies(s):
		assert_int(absi(int(CombatRules.fighter(s, id)["col"]))).is_between(1, 3)
	assert_str(CombatRules.fighter(s, "e1")["name"]).is_equal("Гоблин 1")


func test_weapon_numbers_of_the_sheet() -> void:
	var s := _session()
	var c := s.character
	var w := CombatRules.weapon_profile(c, data, s.items, str(c["equipped"]["main_hand"]))
	assert_int(w["to_hit"]).is_equal(CharacterRules.mod(int(c["abilities"]["str"])) + int(c["prof_bonus"]))
	assert_bool(w["melee"]).is_true()
	var r := _session("rogue_damir")
	var rw := CombatRules.weapon_profile(r.character, data, r.items, "rapier")
	assert_int(rw["bonus"]).is_equal(maxi(CharacterRules.mod(int(r.character["abilities"]["str"])), CharacterRules.mod(int(r.character["abilities"]["dex"]))))
	var bow := CombatRules.weapon_profile(r.character, data, r.items, "shortbow")
	assert_array(bow["range"]).is_equal([80, 320])


func test_reach_range_and_the_attack_economy() -> void:
	var s := _session()
	_fight(s, [{"monster": "goblin", "col": 2}])
	assert_str(CombatRules.can_attack(s, data, "e1")).is_equal("COMBAT_OUT_OF_REACH")
	CombatRules.player_move(s, data, 1)
	assert_str(CombatRules.can_move(s, data, 1)).is_equal("COMBAT_NO_MOVE")
	CombatRules.player_simple(s, data, "dash")
	CombatRules.player_move(s, data, 1)
	assert_str(CombatRules.can_attack(s, data, "e1")).is_equal("COMBAT_NO_ACTION")  # Dash took the action
	CombatRules.end_player_turn(s, data)
	CombatRules.next_actor(s, data)  # the goblin
	if CombatRules.is_player_turn(s) and int(s.character["hp"]) > 0:
		assert_str(CombatRules.can_attack(s, data, "e1")).is_empty()
		var lines := CombatRules.player_attack(s, data, "e1")
		assert_str(lines[0]).contains("против КД 15")
		assert_str(CombatRules.can_attack(s, data, "e1")).is_equal("COMBAT_NO_ACTION")


func test_extra_attack_at_level_five() -> void:
	var s := _session()
	s.character["level"] = 5
	CharacterRules.refresh(s.character, data)
	_fight(s, [{"monster": "ogre", "col": 0}] if data["monsters"].has("ogre") else [{"monster": "bandit", "col": 0}])
	CombatRules.player_attack(s, data, "e1")
	if str(CombatRules.fighter(s, "e1")["status"]) == "active":
		assert_str(CombatRules.can_attack(s, data, "e1")).is_empty()
		CombatRules.player_attack(s, data, "e1")
	assert_str(CombatRules.can_attack(s, data, "e1")).is_not_empty()


func test_leaving_melee_provokes_and_disengage_does_not() -> void:
	var s := _session()
	_fight(s, [{"monster": "goblin", "col": 0}])
	var lines := CombatRules.player_move(s, data, 1)
	assert_str(" ".join(lines)).contains("вдогонку")
	var t := _session()
	_fight(t, [{"monster": "goblin", "col": 0}])
	CombatRules.player_simple(t, data, "disengage")
	assert_str(" ".join(CombatRules.player_move(t, data, 1))).not_contains("вдогонку")


func test_stepping_off_the_edge_leaves_the_fight() -> void:
	var s := _session()
	_fight(s, [{"monster": "goblin", "col": -3}])
	CombatRules.player(s)["col"] = 3
	CombatRules.player_move(s, data, 1)
	assert_str(s.combat["outcome"]).is_equal("player_fled")


func test_the_ai_closes_in_and_shooters_keep_their_range() -> void:
	var s := _session()
	_fight(s, [{"monster": "wolf", "col": 2}])
	CombatRules.end_player_turn(s, data)
	CombatRules.next_actor(s, data)
	assert_int(int(CombatRules.fighter(s, "e1")["col"])).is_less(2)
	var t := _session()
	_fight(t, [{"monster": "goblin", "col": 0}])
	t.combat["fighters"]["e1"]["monster"] = "goblin"
	CombatRules.end_player_turn(t, data)
	var lines := CombatRules.next_actor(t, data)
	assert_str(" ".join(lines)).contains("Ятаган")  # in melee the goblin uses its scimitar


func test_morale_makes_intelligent_foes_surrender_or_flee() -> void:
	var surrendered := false
	var fled := false
	for seed_value in 40:
		var s := _session()
		s.rng.seed = seed_value
		_fight(s, [{"monster": "bandit", "col": 0}])
		var f := CombatRules.fighter(s, "e1")
		f["hp"] = 1
		CombatRules.end_player_turn(s, data)
		var lines := CombatRules.next_actor(s, data)
		surrendered = surrendered or str(f["status"]) == "surrendered"
		fled = fled or bool(f.get("fleeing", false))
	assert_bool(surrendered).is_true()


func test_death_saves_and_massive_damage() -> void:
	var s := _session()
	_fight(s, [{"monster": "wolf", "col": 0}])
	var lines: Array[String] = []
	CombatRules._hurt_player(s, data, int(s.character["hp"]), false, lines)
	assert_int(s.character["hp"]).is_equal(0)
	assert_bool(ConditionRules.has(s.character, "unconscious")).is_true()
	CombatRules._hurt_player(s, data, 5, true, lines)
	assert_int(int(s.combat["death_saves"]["fail"])).is_equal(2)
	CombatRules._hurt_player(s, data, 1, false, lines)
	assert_str(s.combat["outcome"]).is_equal("dead")
	var t := _session()
	_fight(t, [{"monster": "wolf", "col": 0}])
	CombatRules._hurt_player(t, data, int(t.character["hp"]) + int(t.character["max_hp"]), false, lines)
	assert_str(t.combat["outcome"]).is_equal("dead")


func test_intelligent_foes_take_a_stable_hero_alive() -> void:
	var s := _session()
	_fight(s, [{"monster": "bandit", "col": 0}])
	var lines: Array[String] = []
	CombatRules._hurt_player(s, data, int(s.character["hp"]), false, lines)
	s.combat["death_saves"] = {"ok": 3, "fail": 0, "stable": true}
	CombatRules._check_end(s, data, lines)
	assert_str(s.combat["outcome"]).is_equal("captured")


func test_engine_spells_attack_save_darts_and_heal() -> void:
	var s := _session("wizard_yalika")
	var c := s.character
	c["spells"]["prepared"].append_array(["burning_hands", "magic_missile"])
	c["spells"]["cantrips"].append("fire_bolt")
	_fight(s, [{"monster": "goblin", "count": 2, "col": 0}])
	assert_str(CombatRules.can_cast(s, data, "fire_bolt", 0, "e1")).is_empty()
	var lines := CombatRules.player_cast(s, data, "fire_bolt", 0, "e1")
	assert_str(" ".join(lines)).contains("Огненный снаряд")
	CombatRules.economy(s)["action"] = 1
	lines = CombatRules.player_cast(s, data, "burning_hands", 1, "e1")
	assert_int(lines.filter(func(l: String) -> bool: return l.contains("спасбросок Лов")).size()).override_failure_message(str(lines)).is_greater_equal(1)
	assert_int(SpellRules.slots_left(c, 1)).is_equal(1)
	CombatRules.economy(s)["action"] = 1
	var alive := CombatRules.enemies(s)
	if not alive.is_empty():
		lines = CombatRules.player_cast(s, data, "magic_missile", 1, alive[0])
		assert_int(lines.filter(func(l: String) -> bool: return l.begins_with("Волшебная стрела:")).size()).is_greater_equal(1)
	var cl := _session("cleric_branko")
	_fight(cl, [{"monster": "goblin", "col": 2}])
	cl.character["hp"] = 1
	CombatRules.player_cast(cl, data, "cure_wounds", 1, "")
	assert_int(cl.character["hp"]).is_greater(1)


func test_a_won_fight_gives_xp_and_the_gear_of_the_fallen() -> void:
	var s := _session()
	_fight(s, [{"monster": "goblin", "col": 0}])
	CombatRules.fighter(s, "e1")["status"] = "dead"
	var lines := CombatRules.after_player_action(s, data)
	assert_str(s.combat["outcome"]).is_equal("victory")
	CombatRules.results(s, data, {"coins_cp": 150, "items": {"torch": 2}})
	assert_int(s.combat["xp"]).is_equal(50)
	var ids: Array = s.combat["loot"].map(func(l: Dictionary) -> String: return l["item_id"])
	assert_array(ids).contains(["scimitar", "torch"])
	assert_int(s.combat["coins_cp"]).is_equal(150)


func test_finish_combat_takes_the_chosen_loot_and_remembers_the_fight() -> void:
	var s := _session()
	GameState.start(s)
	_fight(s, [{"monster": "commoner", "col": 0, "npc_id": TestUtils.INNKEEPER, "name": "Бруно"}])
	s.combat["encounter"] = "test_enc"
	s.mode = GameSession.MODE_COMBAT
	CombatRules.fighter(s, "e1")["status"] = "dead"
	CombatRules.after_player_action(s, data)
	CombatRules.results(s, data, {"coins_cp": 20})
	s.combat["narrated"] = true
	var gold := int(s.character["gold_cp"])
	GameState.finish_combat(["club"])
	assert_bool(CombatRules.active(s)).is_false()
	assert_str(s.mode).is_equal(GameSession.MODE_EXPLORATION)
	assert_int(s.character["gold_cp"]).is_equal(gold + 20)
	assert_int(int(s.character["inventory"].get("club", 0))).is_greater_equal(1)
	assert_array(s.encounters_done).contains(["test_enc"])
	assert_bool(s.npcs_here(GameState.world().world, s.room_id).has(TestUtils.INNKEEPER)).is_false()


func test_effects_in_a_fight_hit_foes_and_the_master_cannot_move_or_pay() -> void:
	var s := _session()
	_fight(s, [{"monster": "goblin", "col": 0}])
	s.mode = GameSession.MODE_COMBAT
	var fx := EffectEngine.new()
	var r := fx.validate(s, data, "t-1", {"kind": "damage", "severity": "deadly", "damage_type": "дробящий", "reason": "стол", "target_id": "e1"})
	assert_bool(r["accepted"]).is_true()
	fx.apply(s, "t-1", [r["effect_id"]])
	assert_int(int(CombatRules.fighter(s, "e1")["hp"])).is_less(7)
	var c := fx.validate(s, data, "t-2", {"kind": "condition", "condition": "prone", "target_id": "e1"})
	assert_bool(c["accepted"] or str(CombatRules.fighter(s, "e1")["status"]) != "active").is_true()
	assert_bool(fx.validate(s, data, "t-3", {"kind": "move", "room_id": TestUtils.KITCHEN})["accepted"]).is_false()
	assert_bool(fx.validate(s, data, "t-3", {"kind": "coins", "delta_cp": 5})["accepted"]).is_false()


## v0.7.4 (playtest-3: the master summoned made-up miners in a made-up tunnel): outside a fight the master starts
## none — a fight begins with the scene's people or an encounter of the world; in a fight it is a reinforcement.
func test_the_master_does_not_summon_foes_outside_a_fight() -> void:
	var s := _session()
	var fx := EffectEngine.new()
	var r := fx.validate(s, data, "t-1", {"kind": "start_combat", "enemies": [{"monster": "wolf", "count": 1}]})
	assert_bool(r["accepted"]).is_false()
	assert_str(str(r.get("reason", ""))).contains("вне боя")


func test_the_snapshot_and_the_save_keep_the_fight() -> void:
	var s := _session()
	_fight(s, [{"monster": "goblin", "col": -2}])
	s.mode = GameSession.MODE_COMBAT
	var snap := TurnSnapshot.build(s, data, 4000)
	assert_str(snap["combat"]["enemies"][0]["side"]).is_equal("left")
	assert_int(snap["combat"]["enemies"][0]["distance_ft"]).is_equal(60)
	assert_str(snap["combat"]["enemies"][0]["health"]).is_equal("full")
	var back := GameSession.from_dict(JSON.parse_string(JSON.stringify(s.to_dict(500))))
	assert_dict(back.combat).is_equal(s.combat)
