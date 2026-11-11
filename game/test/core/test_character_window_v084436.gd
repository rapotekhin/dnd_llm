extends GdUnitTestSuite
## v0.8.4.43.6: the character window as in BG3 reads the engine only — what a thing allows (ItemActs), what lies loose in
## the grid (Gear.loose), the attack and damage of each weapon set (Gear.set_blow), ★ and ★★ of a skill
## (Sheet.skill_rank), the parts of a number for the card at the cursor (Roll.odds).

var data: Dictionary


func before() -> void:
	data = TestUtils.data()


func _hero(preset_id: String = "fighter_aira") -> GameSession:
	var s := TestUtils.new_session()
	s.minute = 720
	for p: Dictionary in data["presets"]:
		if p["id"] == preset_id:
			s.character = GameSession.normalized_character(CharacterBuilder.build_preset(p, data))
	CharacterRules.refresh(s.character, data, s.items)
	return s


static func _names(rows: Array) -> Array:
	return rows.map(func(r: Dictionary) -> String: return str(r["name"]))


func test_a_loose_weapon_goes_to_either_set_and_down() -> void:
	var s := _hero()
	ItemRules.add(s.character, "shortsword", 1)
	var rows := ItemActs.of(s, data, Being.HERO, "shortsword")
	var names := _names(rows)
	assert_array(names).contains(["Equip_main_hand_shortsword", "EquipStowed_main_hand_shortsword", "Drop_shortsword"])
	assert_str(str(ItemActs.main(rows).get("name", ""))).is_equal("Equip_main_hand_shortsword")  # a double click puts it in the hand


func test_a_worn_thing_comes_off_first() -> void:
	var s := _hero()
	var armor := str(s.character["equipped"]["armor"])
	var rows := ItemActs.of(s, data, Being.HERO, armor, "armor")
	assert_str(str(rows[0]["name"])).is_equal("Unequip_armor")
	assert_str(str(rows[0]["why"])).is_empty()


func test_treasure_is_not_worn_and_has_no_double_click() -> void:
	var s := _hero()
	ItemRules.add(s.character, "silver_ring", 1)
	var rows := ItemActs.of(s, data, Being.HERO, "silver_ring")
	assert_bool(_names(rows).any(func(n: String) -> bool: return n.begins_with("Equip_"))).is_false()
	assert_dict(ItemActs.main(rows)).is_empty()
	assert_array(_names(rows)).contains(["Drop_silver_ring"])


func test_a_potion_goes_onto_the_belt_once() -> void:
	var s := _hero()
	var c := s.character
	c["belt"] = ["", "", "", "", ""]
	ItemRules.add(c, "healing_potion", 2)
	assert_array(_names(ItemActs.of(s, data, Being.HERO, "healing_potion"))).contains(["BeltPut_healing_potion", "DropAll_healing_potion"])
	ItemRules.belt_put(c, data, s.items, "healing_potion")
	assert_array(_names(ItemActs.of(s, data, Being.HERO, "healing_potion"))).not_contains(["BeltPut_healing_potion"])


func test_a_companion_is_handed_things_and_gives_them_back() -> void:
	var s := _hero()
	s.room_id = "brod-square"
	Being.follow(s, "npc_mercenary")
	ItemRules.add(s.character, "longsword", 1)
	var give := ItemActs.of(s, data, Being.HERO, "longsword").filter(func(r: Dictionary) -> bool: return str(r["act"]) == "give")
	assert_int(give.size()).is_equal(1)
	assert_str(str(give[0]["name"])).is_equal("Give_npc_mercenary_longsword")
	assert_str(str(give[0]["group"])).is_equal("BTN_GIVE")
	var its := Gear.of(s, data, "npc_mercenary")
	var item := str((its["inventory"] as Dictionary).keys()[0])
	assert_array(_names(ItemActs.of(s, data, "npc_mercenary", item))).contains(["GearTake_" + item])


func test_the_grid_shows_what_is_neither_worn_nor_on_the_belt() -> void:
	var s := _hero()
	var c := s.character
	c["belt"] = ["", "", "", "", ""]
	ItemRules.add(c, "healing_potion", 2)
	ItemRules.add(c, "rope", 1)
	ItemRules.belt_put(c, data, s.items, "healing_potion")
	var loose := Gear.loose(c, data, s.items)
	assert_bool(loose.has(str(c["equipped"]["armor"]))).is_false()
	assert_bool(loose.has(str(c["equipped"]["main_hand"]))).is_false()
	assert_bool(loose.has("healing_potion")).is_false()
	assert_int(int(loose.get("rope", 0))).is_greater_equal(1)


func test_each_set_says_its_attack_and_damage() -> void:
	var s := _hero()
	var c := s.character
	var main := str(c["equipped"]["main_hand"])
	var held := Gear.set_blow(s, data, Being.HERO, false)
	var p := CombatRules.weapon_profile(c, data, s.items, main)
	assert_int(int(held["to_hit"])).is_equal(int(p["to_hit"]))
	assert_int(RollParts.sum(held["parts"])).is_equal(int(held["to_hit"]))  # every term of the card adds up
	assert_int(int(held["low"])).is_less_equal(int(held["high"]))
	ItemRules.add(c, "longbow", 1)
	Equip.put(s, data, Being.HERO, "longbow", "main_hand", true)
	var spare := Gear.set_blow(s, data, Being.HERO, true)
	assert_str(str(spare["name"])).is_not_equal(str(held["name"]))
	assert_int(int(spare["to_hit"])).is_equal(int(CombatRules.weapon_profile(c, data, s.items, "longbow")["to_hit"]))


func test_a_companions_sets_come_from_its_own_blows() -> void:
	var s := _hero()
	s.room_id = "brod-square"
	Being.follow(s, "npc_mercenary")
	var b := Gear.set_blow(s, data, "npc_mercenary", false)
	assert_bool(b.has("to_hit")).is_true()
	assert_int(int(b["low"])).is_greater(0)


func test_proficiency_and_expertise_as_stars() -> void:
	var s := _hero()
	var c := s.character
	var hero := Sheet.HERO
	assert_int(Sheet.skill_rank(s, data, hero, "athletics")).is_equal(1)
	assert_int(Sheet.skill_rank(s, data, hero, "arcana")).is_equal(0)
	if not c.has("expertise"):
		c["expertise"] = []
	(c["expertise"] as Array).append("athletics")
	CharacterRules.refresh(c, data, s.items)
	assert_int(Sheet.skill_rank(s, data, hero, "athletics")).is_equal(2)
	assert_str(CharacterRules.skill_mastery(c, "athletics")).is_equal("expertise")


func test_the_initiative_card_adds_up() -> void:
	var s := _hero()
	var o := Roll.odds(s, data, Sheet.HERO, {"ability": "dex", "about": "initiative"})
	assert_bool(o.has("parts")).is_true()
	assert_int(RollParts.sum(o["parts"])).is_equal(int(o["bonus"]))
