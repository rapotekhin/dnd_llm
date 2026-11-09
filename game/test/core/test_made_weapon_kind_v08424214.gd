extends GdUnitTestSuite
## v0.8.4.42.14, the author: «Длинный меч (грозовой) (отличная работа)» made at the forge struck as a thrown thing. A fine
## copy stands on the storm longsword of the session, which stands on `longsword`: what is read by the weapon's kind (its
## sprite and look, a shot and its ammunition, the proficiency) goes through the whole chain by `ItemRules.plain_of`.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


## A fine elemental `base` made by «Артефакция» at the forge, as the hero makes it: {id, s}.
func _made(base: String, element: String) -> Dictionary:
	var s := TestUtils.new_session()
	s.settings["needs"] = false
	var c := s.character
	c["tools"] = ["smiths_tools"]
	c["inventory"]["smiths_tools"] = 1
	c["inventory"][base] = 1
	c["inventory"]["arcane_dust"] = 8
	s.room_id = "brod-smithy"
	s.minute = 12 * 60
	for pair: Array in [["artifice", "enchant_weapon"], ["artifice", "elemental"], ["craft", "weaponsmith"]]:
		DevelopmentRules.state(c, pair[0])["xp"] = 1200
		(DevelopmentRules.state(c, pair[0])["skills"] as Array).append(pair[1])
	var id := "tpl:elemental:%s:%s" % [base, element]
	var r := CraftRules.recipe(s, data, id)
	assert_str(CraftRules.why_not(s, data, id)).is_empty()
	CraftRules.start(s, data, id)
	var fine := CraftRules.make_output(s, data, str(r["output"]), 1, CraftRules.tier_by_id(data, "excellent"))
	assert_str(str(s.items[str(fine["id"])]["base"])).is_equal(str(r["output"]))
	c["inventory"][str(fine["id"])] = 1
	return {"id": str(fine["id"]), "s": s}


func test_the_plain_kind_goes_through_every_base() -> void:
	var m := _made("longsword", "lightning_damage")
	var s: GameSession = m["s"]
	assert_str(ItemRules.plain_of(data["items"], s.items, str(m["id"]))).is_equal("longsword")
	assert_str(ItemRules.plain_of(data["items"], s.items, "longsword")).is_equal("longsword")
	assert_str(ItemRules.plain_of(data["items"], s.items, "nothing_at_all")).is_equal("nothing_at_all")


func test_a_fine_storm_longsword_strikes_in_melee_and_swings() -> void:
	var m := _made("longsword", "lightning_damage")
	var s: GameSession = m["s"]
	var id := str(m["id"])
	s.character["equipped"]["main_hand"] = id
	s.character["equipped"]["shield"] = ""
	CharacterRules.refresh(s.character, data, s.items)
	TestUtils.fight(s, data, [{"monster": "goblin", "col": 0}])
	var w := CombatRules.weapon_profile(s.character, data, s.items, id)
	assert_bool(bool(w["melee"])).is_true()
	assert_array(w["range"]).is_empty()
	assert_str(str(w["ammo"])).is_empty()
	assert_str(str(w["dice"])).is_equal("1d10")  # versatile with no shield: the longsword's own die
	var hero := CombatRules.player(s)
	hero["x"] = 0
	hero["y"] = 0
	var foe := {"id": "g", "x": 1, "y": 0}
	var look := AnimRules.of_blow(s, data, hero, foe, Attack.of_weapon(w))
	assert_str(str(look["anim"])).is_equal("swing")
	assert_str(str(look["sprite"])).is_equal("sword")
	assert_str(str(look["proj"])).is_empty()
	assert_str(str(AnimRules.gear(s, data, hero)["sprite"])).is_equal("sword")


func test_a_fine_storm_crossbow_shoots_bolts() -> void:
	var m := _made("crossbow_heavy", "lightning_damage")
	var s: GameSession = m["s"]
	var id := str(m["id"])
	s.character["equipped"]["main_hand"] = id
	CharacterRules.refresh(s.character, data, s.items)
	assert_str(Gear.ammo_of(data, s.items, id)).is_equal("crossbow_bolt")
	var w := CombatRules.weapon_profile(s.character, data, s.items, id)
	assert_bool(bool(w["melee"])).is_false()
	var hero := CombatRules.player(s)
	hero["x"] = 0
	hero["y"] = 0
	var look := AnimRules.of_blow(s, data, hero, {"id": "g", "x": 6, "y": 0}, Attack.of_weapon(w))
	assert_str(str(look["anim"])).is_equal("shot")
	assert_str(str(look["proj"])).is_equal(str(data["anims"]["shots"]["crossbow_heavy"]))


func test_a_made_weapon_is_known_by_its_kind() -> void:
	var m := _made("longsword", "lightning_damage")
	var s: GameSession = m["s"]
	var c := s.character
	c["weapon_profs"] = ["simple", "longsword"]  # a race's own weapon, not the martial category
	var w := CombatRules.weapon_profile(c, data, s.items, str(m["id"]))
	assert_int(int(w["to_hit"])).is_equal(CharacterRules.mod(CharacterRules.ability(c, "str")) + int(c.get("prof_bonus", 2)) + CraftRules.quality_mod(ItemRules.def_of(data["items"], s.items, str(m["id"]))))
	assert_str(ItemInfo.proficiency_line(c, ItemRules.def_of(data["items"], s.items, str(m["id"])), ItemRules.plain_of(data["items"], s.items, str(m["id"])))).is_empty()
