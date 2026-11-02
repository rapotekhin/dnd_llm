extends GdUnitTestSuite
## Allies in a fight (roadmap v0.7.22.22, the author's fixes check #23, #24, #25): a pack encounter's allies, a follower
## who joins (not against the law or its own people), the foes go for the nearest, a summoned creature stays with the
## hero and leaves with the concentration, a familiar's Help, Sneak Attack beside an ally, the follower's buttons.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _hero(preset: String = "fighter_aira", room: String = "pushcha-hollow") -> GameSession:
	var s := TestUtils.new_session()
	for p: Dictionary in data["presets"]:
		if p["id"] == preset:
			s.character = GameSession.normalized_character(CharacterBuilder.build_preset(p, data))
	CharacterRules.refresh(s.character, data, s.items)
	s.room_id = room
	return s


func _wolf_and(s: GameSession, allies: Array) -> void:
	TestUtils.fight(s, data, [{"monster": "wolf", "col": 2}], {"allies": allies})


func _run_until(s: GameSession, id: String) -> Array[String]:
	var lines: Array[String] = []
	var guard := 0
	while CombatRules.current(s) != id and guard < 20:
		guard += 1
		if CombatRules.is_player_turn(s):
			lines.append_array(CombatRules.end_player_turn(s, data))
		else:
			lines.append_array(CombatRules.next_actor(s, data))
	return lines


func test_a_pack_ally_stands_by_the_hero_and_fights() -> void:
	var s := _hero()
	_wolf_and(s, [{"monster": "scout", "name": "Ждан"}])
	var aid := CombatRules.allies(s)[0]
	var a := CombatRules.fighter(s, aid)
	assert_str(str(a["side"])).is_equal("ally")
	assert_int(FightGrid.dist(a, CombatRules.player(s))).is_equal(1)
	assert_array(s.combat["order"] as Array).contains([aid])
	_run_until(s, aid)
	var lines := CombatRules.next_actor(s, data)
	assert_bool(lines.any(func(l: String) -> bool: return l.begins_with("Ждан") and l.contains("по Волк"))).is_true()
	assert_array(CombatRules.snapshot(s, data)["allies"] as Array).has_size(1)


func test_a_foe_goes_for_the_nearest_ally() -> void:
	var s := _hero()
	_wolf_and(s, [{"monster": "guard", "name": "Влада", "col": 2}])
	var wolf := CombatRules.fighter(s, CombatRules.enemies(s)[0])
	var ally := CombatRules.allies(s)[0]
	assert_str(str(FightAI.plan(s, data, wolf)["option"]["t"]["id"])).is_equal(ally)  # the ally stands beside the wolf, the hero far
	FightGrid.put(CombatRules.fighter(s, ally), FightGrid.cell(CombatRules.player(s)) + Vector2i(0, 12))
	TestUtils.beside(s, wolf)
	assert_str(str(FightAI.plan(s, data, wolf)["option"]["t"]["id"])).is_equal(CombatRules.PLAYER)
	s.character["hp"] = 0
	FightGrid.put(CombatRules.fighter(s, ally), FightGrid.cell(CombatRules.player(s)) + Vector2i(0, 5))
	assert_str(str(FightAI.plan(s, data, wolf)["option"]["t"]["id"])).is_equal(ally)  # the hero is down: the ally


func test_the_fight_goes_on_while_an_ally_stands() -> void:
	var s := _hero()
	_wolf_and(s, [{"monster": "guard", "name": "Влада"}])
	s.character["hp"] = 0
	s.combat["death_saves"] = {"ok": 3, "fail": 0, "stable": true}
	assert_array(CombatRules.after_player_action(s, data)).is_empty()
	assert_str(str(s.combat["outcome"])).is_empty()
	var lines: Array[String] = []
	Harm.take(s, data, CombatRules.fighter(s, CombatRules.allies(s)[0]), 99, lines)
	assert_str(lines[0]).contains("падает без сознания")
	CombatRules.after_player_action(s, data)
	assert_str(str(s.combat["outcome"])).is_equal("left")  # beasts: nobody left standing on the hero's side


func test_a_follower_joins_but_not_against_the_law_or_its_own() -> void:
	var s := _hero("fighter_aira", "brod-square")
	Being.follow(s, "npc_mercenary")
	var joins := AllyRules.joining(s, data, [{"monster": "wolf"}])
	assert_array(joins).has_size(1)
	assert_str(str(joins[0]["monster"])).is_equal("scout")
	assert_array(AllyRules.joining(s, data, [{"monster": "guard", "law": true}])).is_empty()
	assert_array(AllyRules.joining(s, data, [{"monster": "thug", "npc_id": "npc_smith"}])).is_empty()  # a neighbour from Brod
	assert_array(AllyRules.joining(s, data, [{"monster": "druid", "npc_id": "npc_hermit"}])).has_size(1)  # a stranger
	TestUtils.fight(s, data, [{"monster": "wolf"}])
	var f := CombatRules.fighter(s, CombatRules.allies(s)[0])
	assert_str(str(f.get("npc_id", ""))).is_equal("npc_mercenary")
	f["status"] = "down"
	s.combat["outcome"] = "victory"
	assert_array(AllyRules.after_fight(s)).contains(["%s приходит в себя" % f["name"]])


func test_summoned_wolves_join_and_leave_with_the_concentration() -> void:
	var s := _hero("druid_olha")
	_wolf_and(s, [])
	s.character["concentration"] = "conjure_animals"
	AllyRules.summon(s, data, "conjure_animals")
	assert_int(AllyRules.called(s).size()).is_equal(4)
	assert_int(CombatRules.allies(s).size()).is_equal(4)
	var lines := CombatRules.end_spell(s, data, "conjure_animals")
	assert_int(CombatRules.allies(s).size()).is_equal(0)
	assert_bool(lines.any(func(l: String) -> bool: return l.contains("концентрация прервана"))).is_true()
	s.character["concentration"] = ""
	AllyRules.expire(s)
	assert_array(AllyRules.called(s)).is_empty()


func test_a_summon_out_of_a_fight_goes_with_the_hero_until_its_time() -> void:
	var s := _hero("wizard_yalika", "brod-square")
	assert_array(AllyRules.summon(s, data, "animate_dead")).is_not_empty()
	assert_int(AllyRules.called(s).size()).is_equal(1)
	assert_str(AllyRules.summon_lines(s, data)[0]).contains("Скелет")
	TestUtils.fight(s, data, [{"monster": "wolf"}])
	assert_int(CombatRules.allies(s).size()).is_equal(1)  # it fights with the hero
	s.combat["outcome"] = "victory"
	CombatRules.fighter(s, CombatRules.allies(s)[0])["hp"] = 5
	AllyRules.after_fight(s)
	assert_int(int(AllyRules.called(s)[0]["hp"])).is_equal(5)  # its wounds stay
	s.combat = {}
	TimeRules.advance(s, data, 1441)
	assert_array(AllyRules.called(s)).is_empty()  # a day passed


func test_a_familiar_helps_and_a_new_one_replaces_it() -> void:
	var s := _hero("wizard_yalika")
	AllyRules.summon(s, data, "find_familiar")
	AllyRules.summon(s, data, "find_familiar")
	assert_int(AllyRules.called(s).size()).is_equal(1)
	assert_str(AllyRules.dismiss(s, str(AllyRules.called(s)[0]["id"]))).is_empty()
	AllyRules.summon(s, data, "find_familiar")
	_wolf_and(s, [])
	var owl := CombatRules.allies(s)[0]
	_run_until(s, owl)
	var lines := CombatRules.next_actor(s, data)
	assert_bool(lines.any(func(l: String) -> bool: return l.contains("отвлекает"))).is_true()
	var wolf := CombatRules.fighter(s, CombatRules.enemies(s)[0])
	assert_bool(CombatRules._has(wolf, "helped")).is_true()
	var w := CombatRules.weapon_profile(s.character, data, s.items, str(s.character["equipped"].get("main_hand", "")))
	assert_array(Attack.mods(s, data, CombatRules.player(s), wolf, Attack.of_weapon(w))["adv"] as Array).contains(["отвлекает союзник"])


func test_sneak_attack_beside_an_ally() -> void:
	var s := _hero("rogue_damir")
	_wolf_and(s, [{"monster": "guard", "name": "Влада", "col": 2}])
	var wolf := CombatRules.fighter(s, CombatRules.enemies(s)[0])
	var w := CombatRules.weapon_profile(s.character, data, s.items, str(s.character["equipped"].get("main_hand", "")))
	assert_str(FeatureRules.sneak_dice(s, data, CombatRules.player(s), Attack.of_weapon(w), false, false, wolf)).is_not_empty()
	TestUtils.to_col(CombatRules.fighter(s, CombatRules.allies(s)[0]), -2)
	assert_str(FeatureRules.sneak_dice(s, data, CombatRules.player(s), Attack.of_weapon(w), false, false, wolf)).is_empty()


func test_the_burrow_brings_no_allies_of_its_own() -> void:  # v0.7.50.1: the hero gathers them in town
	var enc: Dictionary = data["world"]["rooms"]["pushcha-burrow"]["encounter"]
	assert_array(enc.get("allies", []) as Array).is_empty()
	assert_array(WorldPack.validate(WorldPack.load_bundle("res://data/worlds/frontier", "builtin"), TestUtils.base())).is_empty()


func test_summons_survive_a_save() -> void:
	var s := _hero("wizard_yalika")
	AllyRules.summon(s, data, "find_familiar")
	var back := GameSession.from_dict(s.to_dict(10))
	assert_int(AllyRules.called(back).size()).is_equal(1)
