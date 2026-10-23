extends GdUnitTestSuite
## The big test, batch 3a (roadmap v0.7.22.3): a repeat check rolls again only with a new argument or a changed
## state; Charm Person on an NPC ends and the NPC knows; a potion and the off hand as bonus actions (BG3);
## Misty Step is a bonus action.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _hero(preset_id: String, level: int = 1) -> GameSession:
	var s := TestUtils.new_session()
	for p: Dictionary in data["presets"]:
		if p["id"] == preset_id:
			s.character = GameSession.normalized_character(CharacterBuilder.build_preset(p, data))
	CharacterRules.refresh(s.character, data, s.items)
	while int(s.character["level"]) < level:
		s.character["xp"] = LevelUp.xp_for(data, int(s.character["level"]) + 1)
		LevelUp.apply(s.character, data, LevelUp.default_picks(s.character, data))
		CharacterRules.refresh(s.character, data, s.items)
	s.character["hp"] = int(s.character["max_hp"])
	s.room_id = "brod-tavern-hall"
	return s


func _fight(s: GameSession, foes: Array) -> Array[Dictionary]:
	CombatRules.start(s, data, foes, {})
	var order: Array = s.combat["order"]
	order.erase(CombatRules.PLAYER)
	order.push_front(CombatRules.PLAYER)
	s.combat["turn"] = 0
	CombatRules._begin_turn(s, data, [] as Array[String])
	s.mode = GameSession.MODE_COMBAT
	var out: Array[Dictionary] = []
	for id: String in CombatRules.enemies(s):
		out.append(CombatRules.fighter(s, id))
	return out


func _fail() -> Dictionary:
	return {"check_id": "c-1", "rolls": [3], "bonus": 2, "total": 5, "dc": 15, "success": false, "nat": 3}


func test_the_same_words_keep_the_old_result_a_new_argument_rolls() -> void:
	var s := _hero("bard_yas")
	var p := {"skill": "persuasion", "dc_tier": "medium", "target_id": "npc_innkeeper", "argument": "дай в долг"}
	var state := ExplorationRules.state_key(s, data, p, "npc_innkeeper")
	ExplorationRules.lock(s, p, s.room_id, _fail(), state)
	assert_dict(ExplorationRules.locked(s, p, s.room_id, state)).is_not_empty()  # big test #40: no spam
	var same := p.duplicate()
	same["argument"] = "  Дай в долг "
	assert_dict(ExplorationRules.locked(s, same, s.room_id, state)).is_not_empty()
	var other := p.duplicate()
	other["argument"] = "покажу письмо капитана"
	assert_dict(ExplorationRules.locked(s, other, s.room_id, state)).is_empty()
	ExplorationRules.lock(s, other, s.room_id, _fail(), state)
	assert_dict(ExplorationRules.locked(s, p, s.room_id, state)).is_not_empty()  # the old argument stays used


func test_a_changed_state_rolls_again() -> void:
	var s := _hero("bard_yas")
	var p := {"skill": "perception", "dc_tier": "medium"}
	ConditionRules.add(s.character, "paralyzed")
	var state := ExplorationRules.state_key(s, data, p)
	ExplorationRules.lock(s, p, s.room_id, _fail(), state)
	assert_dict(ExplorationRules.locked(s, p, s.room_id, state)).is_not_empty()
	ConditionRules.remove(s.character, "paralyzed")  # big test #14: the paralysis passed
	assert_dict(ExplorationRules.locked(s, p, s.room_id, ExplorationRules.state_key(s, data, p))).is_empty()
	var talk := {"skill": "persuasion", "dc_tier": "medium", "target_id": "npc_innkeeper"}
	var before := ExplorationRules.state_key(s, data, talk, "npc_innkeeper")
	s.shift_attitude("npc_innkeeper", 1, data)  # a gift, a favour — the listener changed
	assert_str(ExplorationRules.state_key(s, data, talk, "npc_innkeeper")).is_not_equal(before)


func test_charm_person_ends_and_the_npc_knows() -> void:
	var s := _hero("bard_yas")
	var att := s.attitude("npc_innkeeper")
	SpellEffects.charm_npc(s, data, "charm_person", "npc_innkeeper")
	assert_array(SpellEffects.npc_spells(s, "npc_innkeeper")).has_size(1)
	assert_str(SpellEffects.npc_spell_text(s, "npc_innkeeper")).contains("до")
	var snap := TurnSnapshot.build(s, data, 2000)
	var him: Array = snap["scene"]["npcs"].filter(func(n: Dictionary) -> bool: return n["npc_id"] == "npc_innkeeper")
	assert_str(str(him[0]["under"])).is_not_empty()
	assert_array(TimeRules.advance(s, data, 30)).not_contains(["«Очарование личности» спадает с Бруно Хмель — понимает, что был(а) очарован(а)"])
	var lines := TimeRules.advance(s, data, 31)
	assert_str(" · ".join(lines)).contains("спадает").contains("понимает")
	assert_array(SpellEffects.npc_spells(s, "npc_innkeeper")).is_empty()
	assert_int(s.attitude("npc_innkeeper")).is_equal(att - 1)
	var back := GameSession.from_dict(s.to_dict(5))
	assert_bool(back.npc_spells.is_empty()).is_true()


func test_a_concentration_charm_ends_with_the_concentration() -> void:
	var s := _hero("bard_yas")
	SpellEffects.charm_npc(s, data, "suggestion", "npc_innkeeper")
	s.character["concentration"] = "suggestion"
	assert_array(SpellEffects.npc_expire(s, data)).is_empty()
	ConditionRules.end_concentration(s, data, "тест")
	assert_str(" · ".join(SpellEffects.npc_expire(s, data))).contains("спадает")


func test_a_potion_is_a_bonus_action() -> void:
	assert_bool(ItemRules.is_potion(data, {}, "healing_potion")).is_true()
	assert_bool(ItemRules.is_potion(data, {}, "antitoxin")).is_false()
	assert_str(str(CombatRules.cfg(data)["potion_cost"])).is_equal("bonus")


func test_the_off_hand_strikes_without_the_main_attack() -> void:
	var s := _hero("rogue_damir")
	var c := s.character
	c["inventory"]["dagger"] = 2
	c["equipped"]["main_hand"] = "dagger"
	c["equipped"]["off_hand"] = "dagger"
	CharacterRules.refresh(c, data, s.items)
	var f := _fight(s, [{"monster": "goblin", "col": 0}])[0]
	f["col"] = int(CombatRules.player(s)["col"])
	assert_str(CombatRules.can_attack(s, data, str(f["id"]), true)).is_empty()  # as in BG3 (v0.7.22.3)
	CombatRules.player_attack(s, data, str(f["id"]), true)
	assert_int(int(CombatRules.economy(s)["bonus"])).is_equal(0)
	assert_int(int(CombatRules.economy(s)["action"])).is_equal(1)


func test_misty_step_is_a_bonus_action() -> void:
	assert_str(CombatRules.spell_cost(data, "misty_step")).is_equal("bonus")
