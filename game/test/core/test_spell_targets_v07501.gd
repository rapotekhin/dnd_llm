extends GdUnitTestSuite
## The author's findings (v0.7.50.1): spells with chosen targets on either side, the burrow without allies of its own,
## a knife on a board is no notice board, a quest's step that cures a sick NPC.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _cleric() -> GameSession:
	var s := TestUtils.new_session()
	for p: Dictionary in data["presets"]:
		if p["id"] == "cleric_branko":
			s.character = GameSession.normalized_character(CharacterBuilder.build_preset(p, data))
	CharacterRules.refresh(s.character, data, s.items)
	s.room_id = "pushcha-hollow"
	var sp: Dictionary = s.character["spells"]
	sp["always"] = ["bless", "bane", "cure_wounds", "shield_of_faith", "hold_person", "mass_healing_word"]
	s.character["slots_max"] = [4, 3, 3, 0, 0]
	s.character["slots_used"] = [0, 0, 0, 0, 0]
	return s


func _fight(s: GameSession, foes: Array, allies: Array = [{"monster": "guard", "name": "Влада", "col": 0}, {"monster": "scout", "name": "Ждан", "col": 0}]) -> void:
	CombatRules.start(s, data, foes, {"allies": allies})
	var order: Array = s.combat["order"]
	order.erase(CombatRules.PLAYER)
	order.push_front(CombatRules.PLAYER)
	s.combat["turn"] = 0
	CombatRules._begin_turn(s, data, [] as Array[String])
	s.mode = GameSession.MODE_COMBAT


func test_the_table_names_known_spells_of_one_side() -> void:
	var table: Dictionary = data["rules"]["combat"]["spell_targets"]
	for id: String in table:
		if not id.begins_with("_"):
			assert_bool(data["spells"].has(id)).override_failure_message(id).is_true()
			assert_bool(str(table[id]["side"]) in ["friend", "foe", "any"]).is_true()


func test_bless_is_picked_one_by_one_and_each_once() -> void:
	var s := _cleric()
	_fight(s, [{"monster": "goblin", "col": 2}])
	var ally: Array[String] = CombatRules.allies(s)
	assert_str(CombatRules.can_cast(s, data, "bless", 1, ally[0])).is_empty()
	CombatRules.player_cast(s, data, "bless", 1, ally[0])
	assert_bool(CombatRules.fighter(s, ally[0]).has("plus_die")).is_true()
	assert_int(int(SpellEffects.hero_die(s, data, "attack")["bonus"])).is_equal(0)  # not on the hero yet
	assert_int(int(CombatRules.volley(s)["left"])).is_equal(2)
	assert_str(CombatRules.can_volley(s, data, ally[0])).is_equal("COMBAT_PICKED")
	assert_str(CombatRules.can_volley(s, data, CombatRules.enemies(s)[0])).is_equal("COMBAT_BAD_TARGET")
	CombatRules.volley_shot(s, data, ally[1])
	CombatRules.volley_shot(s, data, CombatRules.PLAYER)
	assert_dict(CombatRules.volley(s)).is_empty()
	assert_bool(ConditionRules.effects(s.character).any(func(e: Dictionary) -> bool: return str(e.get("source", {}).get("id", "")) == "bless")).is_true()
	ConditionRules.end_concentration(s, data, "проверка")
	assert_bool(CombatRules.fighter(s, ally[1]).has("plus_die")).is_false()


func test_a_higher_slot_blesses_one_more() -> void:
	var s := _cleric()
	_fight(s, [{"monster": "goblin", "col": 2}])
	CombatRules.player_cast(s, data, "bless", 2, CombatRules.allies(s)[0])
	assert_int(int(CombatRules.volley(s)["left"])).is_equal(3)


func test_alone_the_hero_is_blessed_at_once() -> void:
	var s := _cleric()
	_fight(s, [{"monster": "goblin", "col": 2}], [])
	CombatRules.player_cast(s, data, "bless", 1, "")
	assert_dict(CombatRules.volley(s)).is_empty()
	assert_bool(ConditionRules.effects(s.character).any(func(e: Dictionary) -> bool: return str(e.get("source", {}).get("id", "")) == "bless")).is_true()


func test_an_ally_is_healed_even_fallen_and_buffed_with_ac_until_the_end() -> void:
	var s := _cleric()
	_fight(s, [{"monster": "goblin", "col": 2}])
	var a := CombatRules.fighter(s, CombatRules.allies(s)[0])
	a["hp"] = 0
	a["status"] = "down"
	assert_str(CombatRules.can_cast(s, data, "bless", 1, str(a["id"]))).is_equal("COMBAT_BAD_TARGET")
	assert_str(CombatRules.can_cast(s, data, "cure_wounds", 1, str(a["id"]))).is_empty()
	CombatRules.player_cast(s, data, "cure_wounds", 1, str(a["id"]))
	assert_int(int(a["hp"])).is_greater(0)
	assert_str(str(a["status"])).is_equal("active")
	var ac := int(a["ac"])
	s.combat["economy"]["action"] = 1
	s.combat["economy"]["bonus"] = 1
	CombatRules.player_cast(s, data, "shield_of_faith", 1, str(a["id"]))
	assert_int(int(a["ac"])).is_equal(ac + 2)
	ConditionRules.end_concentration(s, data, "проверка")
	assert_int(int(a["ac"])).is_equal(ac)


func test_bane_takes_the_chosen_foes_not_the_nearest() -> void:
	var s := _cleric()
	_fight(s, [{"monster": "goblin", "col": 1}, {"monster": "goblin", "col": 1}, {"monster": "goblin", "col": 2}], [])
	s.character["spell_dc"] = 30
	var foes: Array[String] = CombatRules.enemies(s)
	CombatRules.player_cast(s, data, "bane", 1, foes[2])
	assert_bool(CombatRules.fighter(s, foes[2]).has("minus_die")).is_true()
	assert_bool(CombatRules.fighter(s, foes[0]).has("minus_die")).is_false()
	CombatRules.volley_shot(s, data, foes[0])
	assert_bool(CombatRules.fighter(s, foes[0]).has("minus_die")).is_true()
	assert_bool(CombatRules.fighter(s, foes[1]).has("minus_die")).is_false()
	CombatRules.end_player_turn(s, data)  # the third is not picked for the hero
	assert_bool(CombatRules.fighter(s, foes[1]).has("minus_die")).is_false()


func _prep(s: GameSession, ids: Array) -> void:
	var sp: Dictionary = s.character["spells"]
	sp["always"] = (sp["always"] as Array) + ids
	s.character["slots_max"] = [9, 9, 9, 0, 0]


func test_every_spell_on_an_ally_gives_what_it_says() -> void:
	var s := _cleric()
	_prep(s, ["haste", "fly", "magic_weapon", "protection_from_energy", "resistance", "longstrider"])
	_fight(s, [{"monster": "goblin", "col": 2}])
	var a := CombatRules.fighter(s, CombatRules.allies(s)[0])
	SpellEffects.on_friend(s, data, "haste", 3, a, [] as Array[String])
	assert_int(int(a["speed_fx"])).is_greater(0)
	SpellEffects.on_friend(s, data, "fly", 3, a, [] as Array[String])
	assert_bool(SpellEffects.boon(a, "flying") != null).is_true()
	SpellEffects.on_friend(s, data, "magic_weapon", 2, a, [] as Array[String])
	assert_int(int(SpellEffects.boon(a, "weapon_plus", 0))).is_equal(1)
	SpellEffects.on_friend(s, data, "protection_from_energy", 3, a, [] as Array[String])
	assert_int((a["resist_fx"] as Array).size()).is_equal(1)
	assert_int(CombatRules._resist(data, a, str(a["resist_fx"][0]), 10)).is_equal(5)
	s.character["concentration"] = "haste"
	SpellEffects.end_on_foes(s, "haste")
	assert_bool(a.has("lethargy")).is_true()


func test_invisibility_on_an_ally_leaves_the_hero_seen() -> void:
	var s := _cleric()
	_prep(s, ["invisibility"])
	_fight(s, [{"monster": "goblin", "col": 2}])
	var a := CombatRules.allies(s)[0]
	CombatRules.player_cast(s, data, "invisibility", 2, a)
	assert_bool(CombatRules._has(CombatRules.fighter(s, a), "invisible")).is_true()
	assert_bool(ConditionRules.invisible(s.character, data)).is_false()


func test_acid_takes_only_a_near_second_target() -> void:
	var s := _cleric()
	_prep(s, ["acid_splash"])
	_fight(s, [{"monster": "goblin", "col": 1}, {"monster": "goblin", "col": 1}, {"monster": "goblin", "col": 2}], [])
	var near: Array[String] = []
	var far := ""
	for id: String in CombatRules.enemies(s):
		if int(CombatRules.fighter(s, id)["col"]) == 1:
			near.append(id)
		else:
			far = id
	CombatRules.player_cast(s, data, "acid_splash", 0, near[0])
	assert_str(CombatRules.can_volley(s, data, far)).is_equal("COMBAT_OUT_OF_RANGE")
	assert_str(CombatRules.can_volley(s, data, near[1])).is_empty()


func test_reduce_on_a_foe_weakens_its_blows_until_the_end() -> void:
	var s := _cleric()
	_prep(s, ["enlarge_reduce"])
	s.character["spell_dc"] = 40
	_fight(s, [{"monster": "goblin", "col": 1}], [])
	var foe := CombatRules.fighter(s, CombatRules.enemies(s)[0])
	assert_str(CombatRules.can_cast(s, data, "enlarge_reduce", 2, str(foe["id"]))).is_empty()
	CombatRules.player_cast(s, data, "enlarge_reduce", 2, str(foe["id"]))
	assert_bool(foe.has("reduced")).is_true()
	ConditionRules.end_concentration(s, data, "проверка")
	assert_bool(foe.has("reduced")).is_false()


func test_a_follower_keeps_its_wounds_until_a_long_rest() -> void:
	var s := _cleric()
	s.followers.append("npc_ostap")
	var full := int(AllyRules.npc_health(s, data, "npc_ostap")["max"])
	s.npc_hp["npc_ostap"] = 2
	assert_int(int(AllyRules.joining(s, data, [{"monster": "goblin"}])[0]["hp"])).is_equal(2)
	assert_array(AllyRules.cast_on_npc(s, data, "cure_wounds", 1, "npc_ostap")).has_size(1)
	assert_int(int(AllyRules.npc_health(s, data, "npc_ostap")["hp"])).is_greater(2)
	AllyRules.rest(s)
	assert_int(int(AllyRules.npc_health(s, data, "npc_ostap")["hp"])).is_equal(full)


func test_a_blessing_cast_at_an_npc_goes_into_the_fight_and_ends_with_the_concentration() -> void:
	var s := _cleric()
	s.followers.append("npc_ostap")
	AllyRules.cast_on_npc(s, data, "bless", 1, "npc_ostap")
	_fight(s, [{"monster": "goblin", "col": 2}], [])
	assert_bool(CombatRules.fighter(s, CombatRules.allies(s)[0]).has("plus_die")).is_true()
	AllyRules.drop_buffs(s, "bless")
	assert_bool(s.npc_buffs.has("npc_ostap")).is_false()


func test_a_save_keeps_the_wounds_and_the_spells_of_npcs() -> void:
	var s := _cleric()
	s.npc_hp["npc_ostap"] = 3
	s.npc_buffs["npc_ostap"] = [{"spell": "bless", "slot": 1, "ends": -1}]
	var back := GameSession.from_dict(s.to_dict(0))
	assert_int(int(back.npc_hp["npc_ostap"])).is_equal(3)
	assert_str(str(back.npc_buffs["npc_ostap"][0]["spell"])).is_equal("bless")


func _goblins(id: String = "t_gob") -> Dictionary:
	return {"id": id, "faction": "mine_kobolds", "ambush": true, "enemies": [{"monster": "goblin", "name": "Гоблин", "count": 2}]}


func test_foes_beaten_by_words_stay_for_good_and_raise_the_faction() -> void:
	for skill: String in ["persuasion", "intimidation"]:
		var s := TestUtils.new_session()
		s.room_id = "pushcha-hollow"
		s.character["cha"] = 30
		var pts := FactionRules.points(s, data, "mine_kobolds")
		var ok := false
		while not ok:
			ok = not bool(EncounterRules.parley(s, data, s.room_id, _goblins(), skill)["fight"])
		assert_int(FactionRules.points(s, data, "mine_kobolds")).is_equal(pts + 10)
		var list: Array = CreatureRules.here(s, s.room_id)
		var kept := list.filter(func(c: Dictionary) -> bool: return bool(c.get("kept", false)))
		assert_int(kept.size()).is_equal(2)
		s.day += 30
		CreatureRules.tick(s, data)
		assert_int(CreatureRules.here(s, s.room_id).size()).is_equal(list.size())


func test_the_rest_of_the_faction_here_meets_the_hero_as_if_crept_upon() -> void:
	var s := TestUtils.new_session()
	FactionRules.won_by_word(s, data, "mine_kobolds", "pushcha-hollow", "проверка")
	var m := EncounterRules.meet(s, data, "pushcha-hollow", "pushcha-trail", _goblins("t_next"))
	assert_bool(bool(m["lurk"])).is_true()
	assert_bool(bool(EncounterRules.lurking(s, "pushcha-hollow")["word"])).is_true()
	assert_bool(bool(EncounterRules.meet(s, data, "brod-square", "pushcha-trail", _goblins("t_far"))["lurk"])).is_false()


func test_one_beaten_by_words_comes_along_and_fights_beside() -> void:
	var s := _cleric()
	EncounterRules.as_creatures(s, s.room_id, [{"monster": "goblin", "name": "Гоблин"}], "surrendered", {"kept": true, "faction": "mine_kobolds"})
	var c: Dictionary = CreatureRules.here(s, s.room_id)[0]
	assert_str(CreatureRules.can(s, str(c["id"]), "join", data)).is_empty()
	CreatureRules.act(s, data, str(c["id"]), "join")
	assert_bool(bool(c["led"])).is_true()
	assert_str(CreatureRules.text(c, data)).contains("идёт с героем")
	assert_str(CreatureRules.text(c, data)).not_contains("на привязи")
	assert_int(AllyRules.joining(s, data, [{"monster": "wolf"}]).size()).is_equal(1)
	assert_int(AllyRules.joining(s, data, [{"monster": "goblin", "faction": "mine_kobolds"}]).size()).is_equal(0)  # not against its own
	_fight(s, [{"monster": "wolf", "col": 2}], [])
	var f := CombatRules.fighter(s, CombatRules.allies(s)[0])
	f["status"] = "down"
	AllyRules.after_fight(s)
	assert_int(int(c["hp"])).is_equal(1)
	assert_bool(CreatureRules.here(s, s.room_id).has(c)).is_true()


func _fireball(s: GameSession, col: int, allies: Array) -> Dictionary:
	_prep(s, ["fireball", "burning_hands"])
	s.character["spell_dc"] = 40  # the foe fails; the numbers are not the point
	_fight(s, [{"monster": "ogre", "col": col}], allies)
	return CombatRules.fighter(s, CombatRules.enemies(s)[0])


func test_a_fireball_burns_the_ally_beside_the_foe() -> void:
	var s := _cleric()
	var foe := _fireball(s, 2, [{"monster": "guard", "name": "Влада", "col": 2}, {"monster": "guard", "name": "Ждан", "col": 0}])
	var near := CombatRules.fighter(s, CombatRules.allies(s)[0])
	var far := CombatRules.fighter(s, CombatRules.allies(s)[1])
	var hp := [int(near["hp"]), int(far["hp"])]
	CombatRules.player_cast(s, data, "fireball", 3, str(foe["id"]))
	assert_int(int(near["hp"])).is_less(hp[0])
	assert_int(int(far["hp"])).is_equal(hp[1])


func test_a_fireball_at_ones_own_column_burns_the_hero_a_cone_from_the_hero_does_not() -> void:
	var s := _cleric()
	s.character["hp"] = 200
	s.character["max_hp"] = 200
	var foe := _fireball(s, 0, [])
	CombatRules.player_cast(s, data, "fireball", 3, str(foe["id"]))
	assert_int(int(s.character["hp"])).is_less(200)
	var t := _cleric()
	t.character["hp"] = 200
	t.character["max_hp"] = 200
	var f2 := _fireball(t, 0, [])
	CombatRules.player_cast(t, data, "burning_hands", 1, str(f2["id"]))
	assert_int(int(t.character["hp"])).is_equal(200)


func test_the_toggle_turns_friendly_fire_off() -> void:
	var s := _cleric()
	var foe := _fireball(s, 2, [{"monster": "guard", "name": "Влада", "col": 2}])
	var saved: Dictionary = data["rules"]["combat"]["friendly_fire"]
	data["rules"]["combat"]["friendly_fire"] = {"on": false, "attitude": 0}
	var ally := CombatRules.fighter(s, CombatRules.allies(s)[0])
	var hp := int(ally["hp"])
	CombatRules.player_cast(s, data, "fireball", 3, str(foe["id"]))
	assert_int(int(ally["hp"])).is_equal(hp)
	data["rules"]["combat"]["friendly_fire"] = saved


func test_darts_never_fly_at_friends() -> void:
	var s := _cleric()
	_fight(s, [{"monster": "goblin", "col": 2}])
	s.combat["volley"] = {"spell": "magic_missile", "slot": 1, "left": 1, "last": ""}
	assert_str(CombatRules.can_volley(s, data, CombatRules.PLAYER)).is_equal("COMBAT_BAD_TARGET")


func test_the_burrow_has_no_allies_of_its_own() -> void:
	assert_array(data["world"]["rooms"]["pushcha-burrow"]["encounter"].get("allies", []) as Array).is_empty()


func test_a_board_is_a_board_and_a_knife_is_not() -> void:
	for n: String in ["Доска объявлений", "Столб с листками", "Столб с объявлениями", "Объявления у двери", "Старая доска с объявлениями"]:
		assert_bool(QuestGen.is_board(data, {"name": n})).override_failure_message(n).is_true()
	for n: String in ["Кухонный нож на разделочной доске", "Разделочная доска", "Доска для хлеба", "Столб с факелом"]:
		assert_bool(QuestGen.is_board(data, {"name": n})).override_failure_message(n).is_false()


func test_a_quests_step_cures_the_sick_npc() -> void:
	var s := TestUtils.new_session()
	assert_str(DiseaseRules.npc_disease(s, data, "npc_sick_pilgrim")).is_not_empty()
	var lines: Array[String] = []
	QuestRules._reward(s, data, {"cure_npc": "npc_sick_pilgrim"}, lines, false)
	assert_str(DiseaseRules.npc_disease(s, data, "npc_sick_pilgrim")).is_empty()
	assert_array(lines).has_size(1)
