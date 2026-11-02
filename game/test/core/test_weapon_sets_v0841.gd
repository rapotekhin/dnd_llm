extends GdUnitTestSuite
## v0.8.4.1: two weapon sets as in BG3: a melee row and a ranged row, changed for nothing in a fight and out of it.

var data: Dictionary


func before() -> void:
	data = TestUtils.data()


func _hero(preset_id: String = "fighter_aira") -> GameSession:
	var s := TestUtils.new_session()
	for p: Dictionary in data["presets"]:
		if p["id"] == preset_id:
			s.character = GameSession.normalized_character(CharacterBuilder.build_preset(p, data))
	CharacterRules.refresh(s.character, data, s.items)
	return s


## A longsword and a shield in the hands, a longbow in the other set.
func _armed(s: GameSession) -> void:
	var c := s.character
	for id: String in ["longsword", "shield", "longbow"]:
		c["inventory"][id] = 1
	c["inventory"]["arrows"] = 20
	c["equipped"]["main_hand"] = "longsword"
	c["equipped"]["off_hand"] = ""
	c["equipped"]["shield"] = "shield"
	c["stowed"] = {"main_hand": "longbow", "off_hand": "", "shield": ""}
	CharacterRules.refresh(c, data, s.items)


func _fight(s: GameSession, foes: Array) -> Dictionary:
	TestUtils.fight(s, data, foes, {})
	var order: Array = s.combat["order"]
	order.erase(CombatRules.PLAYER)
	order.push_front(CombatRules.PLAYER)
	s.combat["turn"] = 0
	CombatRules.economy(s)["action"] = 1
	return CombatRules.fighter(s, CombatRules.enemies(s)[0])


func test_things_have_their_rows() -> void:
	for id: String in ["longbow", "crossbow_light", "crossbow_hand", "sling"]:
		assert_str(CharacterRules.set_kind(ItemRules.def_of(data["items"], {}, id))).is_equal("ranged")
	for id: String in ["longsword", "dagger", "shield"]:  # a dagger is thrown, but of the melee row
		assert_str(CharacterRules.set_kind(ItemRules.def_of(data["items"], {}, id))).is_equal("melee")


func test_a_new_hero_has_the_blade_in_hand_and_the_bow_put_away() -> void:
	var c := {"inventory": {"longbow": 1, "longsword": 1}, "armor_profs": [], "equipped": {}}
	CharacterRules.auto_equip(c, data)
	assert_str(str(c["equipped"]["main_hand"])).is_equal("longsword")
	assert_str(str(CharacterRules.stowed(c)["main_hand"])).is_equal("longbow")


func test_only_a_bow_is_in_hand_when_there_is_no_blade() -> void:
	var c := {"inventory": {"longbow": 1}, "armor_profs": [], "equipped": {}}
	CharacterRules.auto_equip(c, data)
	assert_str(str(c["equipped"]["main_hand"])).is_equal("longbow")


func test_the_kind_in_hand_follows_what_is_held() -> void:
	var s := _hero()
	_armed(s)
	assert_str(CharacterRules.active_kind(s.character, data, s.items)).is_equal("melee")
	assert_bool(CharacterRules.goes_stowed(s.character, data, s.items, "longbow")).is_true()
	assert_bool(CharacterRules.goes_stowed(s.character, data, s.items, "longsword")).is_false()
	CharacterRules.swap_hands(s.character)
	assert_str(CharacterRules.active_kind(s.character, data, s.items)).is_equal("ranged")
	assert_bool(CharacterRules.goes_stowed(s.character, data, s.items, "shield")).is_true()


func test_a_swap_changes_the_hands_and_the_armour_class() -> void:
	var s := _hero()
	_armed(s)
	var ac := int(s.character["ac"])
	assert_str(CombatRules.can_swap(s, data)).is_empty()
	CombatRules.swap(s, data)
	assert_str(str(s.character["equipped"]["main_hand"])).is_equal("longbow")
	assert_str(str(s.character["equipped"]["shield"])).is_empty()
	assert_str(str(CharacterRules.stowed(s.character)["shield"])).is_equal("shield")
	assert_int(int(s.character["ac"])).is_equal(ac - 2)  # the shield went with the set
	CombatRules.swap(s, data)
	assert_str(str(s.character["equipped"]["main_hand"])).is_equal("longsword")
	assert_int(int(s.character["ac"])).is_equal(ac)


func test_a_swap_in_a_fight_is_free_as_often_as_wanted() -> void:
	var s := _hero()
	_armed(s)
	_fight(s, [{"monster": "goblin", "col": 2}])
	var before_it: Dictionary = CombatRules.economy(s).duplicate()
	for i: int in 3:
		assert_str(CombatRules.can_swap(s, data)).is_empty()
		CombatRules.swap(s, data)
	assert_dict(CombatRules.economy(s)).is_equal(before_it)


func test_a_swap_only_on_the_heros_turn() -> void:
	var s := _hero()
	_armed(s)
	_fight(s, [{"monster": "goblin", "col": 2}])
	CombatRules.end_player_turn(s, data)
	assert_str(CombatRules.can_swap(s, data)).is_equal("COMBAT_NOT_YOUR_TURN")


func test_the_weapon_put_away_is_one_click_away() -> void:
	var s := _hero()
	_armed(s)
	var f := _fight(s, [{"monster": "goblin", "col": 2}])
	assert_str(CombatRules.can_attack(s, data, str(f["id"]))).is_equal("COMBAT_OUT_OF_REACH")
	assert_str(CombatRules.can_attack_stowed(s, data, str(f["id"]))).is_empty()
	assert_str(str(s.character["equipped"]["main_hand"])).is_equal("longsword")  # asking changes nothing
	var preview: Dictionary = CombatRules.as_stowed(s, func() -> Dictionary: return CombatRules.attack_preview(s, data, str(f["id"]), false))
	assert_dict(preview).is_not_empty()
	assert_str(str(s.character["equipped"]["main_hand"])).is_equal("longsword")


func test_nothing_to_swap_to() -> void:
	var s := _hero()
	_armed(s)
	s.character["stowed"] = {}
	assert_str(CombatRules.can_swap(s, data)).is_equal("SWAP_EMPTY")


func test_a_cursed_weapon_holds_the_hand() -> void:
	var s := _hero()
	_armed(s)
	var cursed := "cursed_sword"
	s.items[cursed] = {"name": "Меч", "item_type": "weapon", "properties": ["cursed"], "weapon": {"range": "melee", "damage": "1d8", "damage_type": "slashing"}}
	s.character["inventory"][cursed] = 1
	s.character["equipped"]["main_hand"] = cursed
	assert_str(CombatRules.can_swap(s, data)).is_equal("ITEM_CURSED")


func test_wild_shape_has_no_hands() -> void:
	var s := _hero()
	_armed(s)
	s.character["effects"] = [{"guise": {"monster": "wolf", "hp": 10, "max_hp": 10}}]
	assert_str(CombatRules.can_swap(s, data)).is_equal("COMBAT_WILD_SHAPE")


func test_what_is_no_longer_carried_leaves_the_set() -> void:
	var s := _hero()
	_armed(s)
	s.character["inventory"].erase("longbow")
	CharacterRules.refresh(s.character, data, s.items)
	assert_str(str(CharacterRules.stowed(s.character)["main_hand"])).is_empty()


func test_a_stowed_weapon_counts_as_held() -> void:
	var s := _hero()
	_armed(s)
	assert_int(CharacterRules.held_copies(s.character, "longbow")).is_equal(1)
	s.character["inventory"]["longbow"] = 2
	assert_int(CharacterRules.held_copies(s.character, "longbow")).is_equal(1)
	assert_bool(CraftRules.salvageable(s, data).has("longsword")).is_false()


func test_a_bow_goes_to_its_row_without_touching_the_hands() -> void:
	var s := _hero()
	_armed(s)
	s.character["stowed"] = {}
	assert_str(CharacterRules.can_equip(s.character, data, s.items, "longbow", "main_hand")).is_empty()
	CharacterRules.put_stowed(s.character, data, s.items, "longbow", "main_hand")
	assert_str(str(s.character["equipped"]["main_hand"])).is_equal("longsword")
	assert_str(str(CharacterRules.stowed(s.character)["main_hand"])).is_equal("longbow")


func test_a_row_is_judged_by_its_own_hands() -> void:
	var s := _hero()
	_armed(s)
	s.character["inventory"]["crossbow_hand"] = 2
	s.character["stowed"] = {"main_hand": "crossbow_hand"}
	assert_str(CharacterRules.can_equip(s.character, data, s.items, "crossbow_hand", "off_hand")).is_empty()  # the sword's shield is no bother
	s.character["stowed"] = {"main_hand": "longbow"}
	assert_str(CharacterRules.can_equip(s.character, data, s.items, "crossbow_hand", "off_hand")).is_equal("EQUIP_HANDS_BUSY")


func test_a_two_handed_weapon_empties_its_own_row() -> void:
	var s := _hero()
	_armed(s)
	s.character["inventory"]["crossbow_hand"] = 2
	s.character["stowed"] = {"main_hand": "crossbow_hand", "off_hand": "crossbow_hand"}
	CharacterRules.put_stowed(s.character, data, s.items, "longbow", "main_hand")
	assert_str(str(CharacterRules.stowed(s.character)["off_hand"])).is_empty()


func test_the_master_sees_both_sets() -> void:
	var s := _hero()
	_armed(s)
	assert_str(str(TurnSnapshot.character_sheet(s, data)["equipped"])).contains("запасной набор, main_hand")


func test_a_weapon_taken_by_words_brings_up_its_set_for_nothing() -> void:
	var s := _hero()
	_armed(s)
	_fight(s, [{"monster": "goblin", "col": 2}])
	var engine := EffectEngine.new()
	var r := engine.validate(s, data, "t-1", {"kind": "equip", "item_id": "longbow", "slot": "main_hand"})
	assert_str(str(r.get("reason", ""))).is_empty()
	engine.apply(s, "t-1", [str(r["effect_id"])])
	assert_str(str(s.character["equipped"]["main_hand"])).is_equal("longbow")
	assert_str(str(CharacterRules.stowed(s.character)["main_hand"])).is_equal("longsword")
	assert_bool(bool(CombatRules.economy(s).get("object", false))).is_false()
