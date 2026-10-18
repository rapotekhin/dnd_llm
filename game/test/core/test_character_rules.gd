extends GdUnitTestSuite
## CharacterRules: modifiers, proficiency, skills and saves, HP by the average rule, AC formulas, equipping.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _built(choices: Dictionary) -> Dictionary:
	var ch := CharacterBuilder.empty_choices()
	ch.merge(choices, true)
	return CharacterBuilder.build(ch, data)


func test_modifier_table() -> void:
	for pair: Array in [[1, -5], [8, -1], [9, -1], [10, 0], [11, 0], [12, 1], [15, 2], [20, 5]]:
		assert_int(CharacterRules.mod(pair[0])).override_failure_message(str(pair)).is_equal(pair[1])


func test_start_character_numbers() -> void:
	var c := TestUtils.character()
	assert_dict(c["abilities"]).is_equal({"str": 16, "dex": 14, "con": 15, "int": 9, "wis": 13, "cha": 11})
	assert_int(c["max_hp"]).is_equal(12)  # d10 + CON 2
	assert_int(c["hp"]).is_equal(12)
	assert_int(c["prof_bonus"]).is_equal(2)
	assert_int(c["ac"]).is_equal(19)
	assert_int(c["skills"]["athletics"]).is_equal(5)  # STR 3 + prof 2 (soldier)
	assert_int(c["skills"]["perception"]).is_equal(3)
	assert_int(c["skills"]["arcana"]).is_equal(-1)
	assert_int(c["saves"]["str"]).is_equal(5)
	assert_int(c["saves"]["dex"]).is_equal(2)
	assert_int(c["passive_perception"]).is_equal(13)
	assert_int(c["speed"]).is_equal(30)
	assert_str(c["race_name"]).is_equal("Человек")
	assert_bool(c.has("spell_dc")).is_false()


func test_hp_by_level_and_toughness() -> void:
	var c := TestUtils.character()
	c["level"] = 3
	assert_int(CharacterRules.max_hp(c, data)).is_equal(12 + 2 * (6 + 2))
	c["abilities"]["con"] = 1  # CON −5: at least 1 per level
	assert_int(CharacterRules.max_hp(c, data)).is_equal(5 + 1 + 1)
	c["abilities"]["con"] = 10
	c["level"] = 1
	c["traits"].append("dwarven_toughness")
	assert_int(CharacterRules.max_hp(c, data)).is_equal(11)


func test_proficiency_bonus_grows_at_level_5() -> void:
	var c := TestUtils.character()
	c["level"] = 5
	CharacterRules.refresh(c, data)
	assert_int(c["prof_bonus"]).is_equal(3)
	assert_int(c["skills"]["athletics"]).is_equal(6)


func test_expertise_and_jack_of_all_trades() -> void:
	var c := TestUtils.character()
	c["expertise"] = ["perception"]
	assert_int(CharacterRules.skill_bonus(c, data, "perception")).is_equal(1 + 4)
	c["features"].append("jack_of_all_trades")
	assert_int(CharacterRules.skill_bonus(c, data, "arcana")).is_equal(-1 + 1)


func test_unarmored_ac_formulas() -> void:
	var c := TestUtils.character()
	c["equipped"] = {"armor": "", "shield": "", "main_hand": "", "off_hand": ""}
	c["abilities"] = {"str": 10, "dex": 16, "con": 14, "int": 10, "wis": 15, "cha": 10}
	assert_int(CharacterRules.armor_class(c, data)).is_equal(13)
	c["features"] = ["barbarian_unarmored_defense"]
	assert_int(CharacterRules.armor_class(c, data)).is_equal(10 + 3 + 2)
	c["features"] = ["monk_unarmored_defense"]
	assert_int(CharacterRules.armor_class(c, data)).is_equal(10 + 3 + 2)
	c["equipped"]["shield"] = "shield"
	assert_int(CharacterRules.armor_class(c, data)).is_equal(13 + 2)  # a monk with a shield loses the WIS bonus
	c["features"] = ["draconic_resilience"]
	c["equipped"]["shield"] = ""
	assert_int(CharacterRules.armor_class(c, data)).is_equal(16)


func test_armor_caps_dex() -> void:
	var c := TestUtils.character()
	c["abilities"]["dex"] = 18
	c["inventory"]["leather_armor"] = 1
	c["inventory"]["chain_shirt"] = 1
	c["features"] = []
	c["equipped"] = {"armor": "leather_armor", "shield": "", "main_hand": "", "off_hand": ""}
	assert_int(CharacterRules.armor_class(c, data)).is_equal(11 + 4)
	c["equipped"]["armor"] = "chain_shirt"
	assert_int(CharacterRules.armor_class(c, data)).is_equal(13 + 2)  # medium: DEX max 2
	c["equipped"]["armor"] = "chain_mail"
	assert_int(CharacterRules.armor_class(c, data)).is_equal(16)  # heavy: no DEX


func test_equip_rules() -> void:
	var c := TestUtils.character()
	var items := {}
	assert_str(CharacterRules.can_equip(c, data, items, "longsword", "armor")).is_equal("EQUIP_WRONG_SLOT")
	assert_str(CharacterRules.can_equip(c, data, items, "rapier", "main_hand")).is_equal("EQUIP_NOT_OWNED")
	assert_str(CharacterRules.can_equip(c, data, items, "handaxe", "off_hand")).is_equal("EQUIP_HANDS_BUSY")  # the shield
	c["equipped"]["shield"] = ""
	assert_str(CharacterRules.can_equip(c, data, items, "handaxe", "off_hand")).is_empty()
	assert_str(CharacterRules.can_equip(c, data, items, "longsword", "off_hand")).is_equal("EQUIP_NOT_LIGHT")
	var wizard := c.duplicate(true)
	wizard["armor_profs"] = []
	assert_str(CharacterRules.can_equip(wizard, data, items, "chain_mail", "armor")).is_equal("EQUIP_NO_PROFICIENCY")


func test_given_away_item_is_unequipped() -> void:
	var c := TestUtils.character()
	c["inventory"].erase("shield")
	CharacterRules.refresh(c, data)
	assert_str(c["equipped"]["shield"]).is_empty()
	assert_int(c["ac"]).is_equal(17)


func test_caster_numbers() -> void:
	var c := _built({"name": "Ялика", "race": "elf", "subrace": "high_elf", "class": "wizard", "background": "sage",
		"base_abilities": {"str": 8, "dex": 14, "con": 13, "int": 15, "wis": 12, "cha": 10},
		"skills": ["investigation", "medicine"], "cantrips": ["fire_bolt", "mage_hand", "light"],
		"spells": ["magic_missile", "shield", "sleep", "detect_magic", "mage_armor", "burning_hands"],
		"race_cantrips": ["prestidigitation"],
		"equipment": [{"alt": 0, "picks": []}, {"alt": 0, "picks": []}, {"alt": 0, "picks": []}],
		"languages": ["dwarvish", "draconic", "giant"]})
	assert_int(c["abilities"]["int"]).is_equal(16)  # 15 + high elf 1
	assert_int(c["abilities"]["dex"]).is_equal(16)  # 14 + elf 2
	assert_int(c["max_hp"]).is_equal(7)  # d6 + CON 1
	assert_int(c["spell_dc"]).is_equal(8 + 2 + 3)
	assert_int(c["spell_attack"]).is_equal(5)
	assert_array(c["slots_max"]).is_equal([2, 0, 0, 0, 0])
	assert_array(c["spells"]["known"]).has_size(6)
	assert_array(c["spells"]["prepared"]).has_size(4)  # INT 3 + level 1
	assert_array(c["spells"]["cantrips"]).contains(["prestidigitation"])
	assert_array(c["skill_profs"]).contains(["perception", "arcana", "history"])  # Keen Senses + sage
	assert_int(c["ac"]).is_equal(13)  # no armor proficiency: 10 + DEX 3
