extends GdUnitTestSuite
## v0.8.4.43.13, the author's findings on the character window: a shield is held in the off hand as in every RPG — no slot
## of its own, for the hero, a person and a template alike, in both sets; the book lists the acts of a fight anybody has
## (`Act.book`) and each reaction with its icon.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _hero() -> GameSession:
	return TestUtils.new_session()  # the first preset: chain mail, a longsword and a shield, the Defense style


func test_a_shield_goes_to_the_off_hand() -> void:
	var d := ItemRules.def_of(data["items"], {}, "shield")
	assert_str(CharacterRules.slot_for(d, data)).is_equal("off_hand")
	assert_array(CharacterRules.slots_of(d, data)).contains_exactly(["off_hand"])
	assert_bool(CharacterRules.SLOTS.has("shield")).is_false()
	var c := _hero().character
	var eq: Dictionary = c["equipped"]
	assert_str(str(eq["off_hand"])).is_equal("shield")
	assert_bool(eq.has("shield")).is_false()
	assert_str(CharacterRules.shield_in(eq, data)).is_equal("shield")
	assert_str(CharacterRules.off_weapon(eq, data)).is_empty()
	assert_int(int(c["ac"])).is_equal(19)  # chain mail 16, the shield 2, Defense 1
	assert_str(CharacterRules.can_equip(c, data, {}, "shield", "main_hand")).is_equal("EQUIP_WRONG_SLOT")


func test_a_light_blade_takes_the_shields_place_and_two_hands_free_it() -> void:
	var s := _hero()
	var c := s.character
	Gear.give(s, data, Being.HERO, "dagger", 1)
	assert_str(Equip.why(s, data, Being.HERO, "dagger", "off_hand")).is_empty()
	Equip.put(s, data, Being.HERO, "dagger", "off_hand")
	assert_str(str(c["equipped"]["off_hand"])).is_equal("dagger")
	assert_str(CharacterRules.off_weapon(c["equipped"], data)).is_equal("dagger")
	assert_int(int(c["ac"])).is_equal(17)  # the shield went to the pack
	assert_int(int(c["inventory"]["shield"])).is_equal(1)
	Equip.put(s, data, Being.HERO, "shield", "off_hand")
	assert_int(int(c["ac"])).is_equal(19)
	c["inventory"]["greatsword"] = 1
	assert_array(CharacterRules.hands_freed(c, data, {}, "greatsword", "main_hand")).contains_exactly(["off_hand"])
	Equip.put(s, data, Being.HERO, "greatsword", "main_hand")
	assert_str(str(c["equipped"]["off_hand"])).is_empty()
	assert_str(CharacterRules.can_equip(c, data, {}, "shield", "off_hand")).is_equal("EQUIP_HANDS_BUSY")


func test_a_shield_is_not_moved_in_a_fight() -> void:
	var s := _hero()
	Gear.give(s, data, Being.HERO, "dagger", 1)
	ChecklistProbe.fight(s, data, "goblin", true)
	assert_str(Equip.why(s, data, Being.HERO, "dagger", "off_hand")).is_equal("EQUIP_IN_COMBAT")  # the shield would come off
	assert_str(Equip.off_why(s, data, Being.HERO, "off_hand")).is_equal("EQUIP_IN_COMBAT")


func test_a_versatile_blade_beside_a_shield_keeps_one_hand_and_dueling_its_bonus() -> void:
	var c := _hero().character
	var one := CombatRules.weapon_profile(c, data, {}, "longsword")
	assert_str(str(one["dice"])).is_equal("1d8")  # the shield holds the other hand
	(c["features"] as Array).append("fighting_style_dueling")
	var duel := CombatRules.weapon_profile(c, data, {}, "longsword")
	assert_int(int(duel["bonus"])).is_equal(int(one["bonus"]) + 2)  # 5e: Dueling allows a shield


func test_a_template_holds_its_shield_in_the_off_hand_and_its_ac_counts_it() -> void:
	var s := _hero()
	var kit := Gear.start(data, "guard")
	assert_str(str(kit["equipped"]["off_hand"])).is_equal("shield")
	var with := {"inventory": kit["inventory"], "equipped": kit["equipped"].duplicate()}
	assert_int(Gear.ac(s, data, "guard", with)).is_equal(16)
	with["equipped"]["off_hand"] = ""
	assert_int(Gear.ac(s, data, "guard", with)).is_equal(14)


func test_an_old_shield_slot_folds_into_the_off_hand() -> void:
	var c := _hero().character
	c["equipped"] = {"armor": "chain_mail", "shield": "shield", "main_hand": "longsword", "off_hand": ""}
	CharacterRules.refresh(c, data)
	assert_str(str(c["equipped"]["off_hand"])).is_equal("shield")
	assert_bool((c["equipped"] as Dictionary).has("shield")).is_false()
	assert_int(int(c["ac"])).is_equal(19)


func test_the_masters_shield_slot_is_the_off_hands() -> void:
	var s := _hero()
	var fx := EffectEngine.new()
	var r := fx.validate(s, data, "t-1", {"kind": "equip", "slot": "shield"})
	assert_bool(bool(r["accepted"])).is_true()
	fx.apply(s, "t-1", [str(r["effect_id"])])
	assert_str(str(s.character["equipped"]["off_hand"])).is_empty()
	var none := fx.validate(s, data, "t-2", {"kind": "equip", "slot": "shield"})
	assert_bool(bool(none["accepted"])).is_false()
	assert_str(str(none["reason"])).contains("щита в руках нет")


func test_the_book_lists_the_acts_anybody_has() -> void:
	var ids := Acts.all().filter(func(a: Act) -> bool: return a.tab() == "common" and a.book()).map(func(a: Act) -> String: return a.id)
	assert_array(ids).contains(["dash", "dodge", "disengage", "help", "hide", "shove", "grapple", "jump"])
	assert_array(ids).not_contains(["stand", "field", "escape", "pick_up", "parley"])  # by the moment


func test_a_reaction_row_carries_its_icon() -> void:
	var s := _hero()
	var c := s.character
	c["class"] = "monk"
	c["level"] = 3
	(c["features"] as Array).append("deflect_missiles")
	CharacterRules.refresh(c, data, s.items)
	var icons := {}
	for r: Dictionary in FeatureRules.reaction_list(s, data, Sheet.HERO):
		icons[str(r["id"])] = str(r["icon"])
	assert_str(str(icons["opportunity"])).is_equal("acts/opportunity")
	assert_str(str(icons["deflect_missiles"])).is_equal("features/deflect_missiles")
