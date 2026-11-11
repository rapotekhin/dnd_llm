extends GdUnitTestSuite
## v0.8.4.43.10, the author's feedback on 0.8.4.43.8 — the party column: the same column in a fight and out of it, the hero
## and its party as portraits (AllyRules.party), never a foe nor an ally of the encounter; the fight's marks as icons
## (CombatRules.marks); the needs and statuses larger; a spell of the hero's side pinned takes its last target by a portrait
## or a token and is cast at once (GameState.attach_ready, cast_attached).

var data: Dictionary
var kept: GameSession
var kept_attached: Dictionary


func before_test() -> void:
	data = TestUtils.data()
	kept = GameState.session
	kept_attached = GameState.attached
	var s := TestUtils.new_session()
	for p: Dictionary in data["presets"]:
		if p["id"] == "cleric_branko":
			s.character = GameSession.normalized_character(CharacterBuilder.build_preset(p, data))
	CharacterRules.refresh(s.character, data, s.items)
	s.room_id = "brod-tavern-hall"
	GameState.session = s
	GameState.attached = {}


func after_test() -> void:
	GameState.session = kept
	GameState.attached = kept_attached


func test_out_of_a_fight_the_party_is_the_hero_and_those_with_it() -> void:
	var s := GameState.session
	Being.follow(s, "npc_veteran")
	var refs := AllyRules.party(s, data).map(func(m: Dictionary) -> String: return str(m["ref"]))
	assert_array(refs).is_equal(["", "npc:npc_veteran"])
	assert_bool(Sheet.is_hero(AllyRules.party(s, data)[0]["who"])).is_true()


func test_in_a_fight_the_party_is_its_fighters_never_a_foe_nor_the_encounter_s_ally() -> void:
	var s := GameState.session
	Being.follow(s, "npc_veteran")
	CombatRules.start(s, data, [{"monster": "wolf", "name": "Волк"}], {"allies": [{"monster": "guard", "name": "Ополченец"}]})
	var party := AllyRules.party(s, data)
	var refs := party.map(func(m: Dictionary) -> String: return str(m["ref"]))
	assert_array(refs).is_equal([CombatRules.PLAYER, "npc_veteran"])
	var militia := CombatRules.allies(s, false).filter(func(id: String) -> bool: return str(CombatRules.fighter(s, id)["name"]) == "Ополченец")
	assert_int(militia.size()).is_equal(1)
	assert_bool(AllyRules.of_party(s, CombatRules.fighter(s, militia[0]))).is_false()
	assert_bool(AllyRules.of_party(s, CombatRules.fighter(s, "npc_veteran"))).is_true()


func test_a_summon_of_the_party_is_of_the_party_one_of_a_foe_is_not() -> void:
	var s := GameState.session
	CombatRules.start(s, data, [{"monster": "wolf", "name": "Волк"}], {})
	var ours := CombatRules.summon_for(s, data, CombatRules.player(s), "find_familiar")
	assert_array(ours).is_not_empty()
	var called := CombatRules.allies(s, false)
	assert_int(called.size()).is_equal(1)
	assert_bool(AllyRules.of_party(s, CombatRules.fighter(s, called[0]))).is_true()
	CombatRules.summon_for(s, data, CombatRules.fighter(s, CombatRules.enemies(s)[0]), "find_familiar")
	for id: String in CombatRules.enemies(s):
		assert_bool(AllyRules.of_party(s, CombatRules.fighter(s, id))).is_false()


func test_the_fight_s_marks_beside_the_statuses() -> void:
	var s := GameState.session
	CombatRules.start(s, data, [{"monster": "wolf", "name": "Волк"}], {})
	var me := CombatRules.player(s)
	assert_array(CombatRules.marks(s, me)).is_empty()
	me["hidden"] = true
	me["raging"] = true
	assert_array(CombatRules.marks(s, me)).is_equal(["hidden", "raging"])


func test_the_column_in_a_fight_draws_the_party_not_the_foes() -> void:
	var s := GameState.session
	Being.follow(s, "npc_veteran")
	CombatRules.start(s, data, [{"monster": "wolf", "name": "Волк"}], {"allies": [{"monster": "guard", "name": "Ополченец"}]})
	var col := auto_free(PartyColumn.new()) as PartyColumn
	add_child(col)
	col.now = "npc_veteran"
	col.refresh()
	assert_object(col.find_child("Portrait_hero", true, false)).is_not_null()
	var her := col.find_child("Portrait_npc_veteran", true, false) as Portrait
	assert_object(her).is_not_null()
	assert_bool(her.picked).is_true()  # whose turn it is: lit
	for id: String in CombatRules.enemies(s) + CombatRules.allies(s, false):
		if id != "npc_veteran":
			assert_object(col.find_child("Portrait_" + id, true, false)).is_null()
	s.character["hp"] = 0
	col.refresh()
	var hero := col.find_child("Portrait_hero", true, false) as Portrait
	assert_bool(hero.down).is_true()
	assert_dict(hero.saves).contains_keys(["ok", "fail"])  # its death saves on the face, as in BG3
	await get_tree().process_frame


func test_the_needs_and_statuses_are_larger() -> void:
	var s := GameState.session
	s.settings["needs"] = true
	ConditionRules.add_effect(s.character, {"condition": "poisoned", "ends": ConditionRules.ends_for(s, data, "hour"), "source": {"kind": "master", "name": "яд"}})
	var col := auto_free(PartyColumn.new()) as PartyColumn
	add_child(col)
	col.refresh()
	var chip := col.find_child("Chip_poisoned", true, false) as IconSlot
	assert_object(chip).is_not_null()
	assert_float(chip.custom_minimum_size.x).is_equal(float(PartyColumn.HERO_ICON))
	var food := col.find_child("Need_food", true, false) as IconSlot
	assert_float(food.custom_minimum_size.x).is_equal(float(PartyColumn.HERO_ICON))
	await get_tree().process_frame


func test_a_heal_is_ready_with_its_one_target_bless_with_all_of_its() -> void:
	var people := GameState.attach_targets().filter(func(t: Dictionary) -> bool: return not bool(t["foe"])).map(func(t: Dictionary) -> String: return str(t["id"]))
	assert_bool(GameState.attach_ready()).is_false()  # nothing pinned
	GameState.attach("spell", "cure_wounds", 1)
	assert_bool(GameState.attach_ready()).is_true()  # one target: the hero by none set, or the one clicked
	GameState.attach("spell", "bless", 1)
	assert_str(GameState.aim_attached(Being.HERO)).is_empty()
	assert_str(GameState.aim_attached(str(people[0]))).is_empty()
	assert_bool(GameState.attach_ready()).is_false()
	assert_str(GameState.aim_attached(str(people[1]))).is_empty()
	assert_bool(GameState.attach_ready()).is_true()
	GameState.attach("spell", "fire_bolt", 0)  # not the hero's side: the words' own
	assert_bool(GameState.attach_ready()).is_false()
	assert_str(GameState.cast_attached()).is_equal("ATTACH_AIM_NONE")
