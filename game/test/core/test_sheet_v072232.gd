extends GdUnitTestSuite
## The sheet and the journal by the genre's pattern (roadmap v0.7.22.32): the followed quest, a worn thing compared.


func test_the_followed_quest_is_the_last_taken_until_picked() -> void:
	var s := TestUtils.new_session()
	var data := Catalog.data
	var world: Dictionary = data["world"]
	assert_str(QuestRules.tracked(s, world)).is_empty()
	QuestRules.accept(s, data, "drogin_amulet")
	QuestRules.accept(s, data, "letter_to_ilva")
	assert_str(QuestRules.tracked(s, world)).is_equal("letter_to_ilva")
	s.tracked_quest = "drogin_amulet"
	assert_str(QuestRules.tracked(s, world)).is_equal("drogin_amulet")
	s.quests_active.erase("drogin_amulet")  # done or failed: back to the last taken
	assert_str(QuestRules.tracked(s, world)).is_equal("letter_to_ilva")


func test_a_ring_is_compared_with_the_worn_one_not_as_a_weapon() -> void:
	var s := TestUtils.new_session()
	var c := s.character
	c["inventory"]["ring_of_jumping"] = 1
	assert_str(ItemInfo.compare(c, Catalog.data, s.items, "ring_of_jumping")).is_empty()
	c["equipped"]["ring1"] = "ring_of_mind_shielding"
	assert_str(ItemInfo.compare(c, Catalog.data, s.items, "ring_of_jumping")).contains("Вместо надетого")


func test_a_two_handed_weapon_frees_the_shield_hand() -> void:
	var c := TestUtils.character()  # longsword and shield in hand
	c["inventory"]["greatsword"] = 1
	assert_array(CharacterRules.hands_freed(c, Catalog.data, {}, "greatsword", "main_hand")).contains_exactly(["shield"])
	assert_str(CharacterRules.can_equip(c, Catalog.data, {}, "greatsword", "main_hand")).is_empty()
	c["equipped"]["main_hand"] = "greatsword"
	assert_str(CharacterRules.can_equip(c, Catalog.data, {}, "shield", "shield")).is_equal("EQUIP_HANDS_BUSY")


func test_a_versatile_weapon_in_both_hands() -> void:
	var c := TestUtils.character()
	c["inventory"]["longsword"] = 1
	c["equipped"]["main_hand"] = "longsword"
	assert_bool(CharacterRules.two_hand_grip(c, Catalog.data, {})).is_false()  # the shield is on
	assert_array(CharacterRules.hands_freed(c, Catalog.data, {}, "longsword", "main_hand")).is_empty()
	assert_array(CharacterRules.hands_freed(c, Catalog.data, {}, "longsword", "main_hand", true)).contains_exactly(["shield"])
	c["equipped"]["shield"] = ""
	assert_bool(CharacterRules.two_hand_grip(c, Catalog.data, {})).is_true()
	assert_str(CombatRules.weapon_profile(c, Catalog.data, {}, "longsword")["dice"]).is_equal("1d10")


func test_the_masters_equip_frees_the_shield() -> void:
	var s := TestUtils.new_session()
	s.character = TestUtils.character()
	s.character["inventory"]["greatsword"] = 1
	var engine := EffectEngine.new()
	var r := engine.validate(s, Catalog.data, "t-1", {"kind": "equip", "item_id": "greatsword", "slot": "main_hand"})
	assert_bool(bool(r["accepted"])).is_true()
	engine.apply(s, "t-1", [str(r["effect_id"])])
	assert_str(str(s.character["equipped"]["main_hand"])).is_equal("greatsword")
	assert_str(str(s.character["equipped"]["shield"])).is_empty()
