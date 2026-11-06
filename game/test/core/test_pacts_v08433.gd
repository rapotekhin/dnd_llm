extends GdUnitTestSuite
## Pact of the Chain and Pact of the Tome (v0.8.4.33): Find Familiar without a slot, the special forms and the familiar's
## blow for one of the warlock's attacks; three cantrips of any class in the Book of Shadows, cast while it is carried.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _hero(level: int, features: Array) -> GameSession:
	var s := ChecklistProbe.session(data)
	var c := s.character
	c["class"] = "warlock"
	c["level"] = level
	(c["features"] as Array).append_array(features)
	CharacterRules.refresh(c, data, s.items)
	return s


# --- Pact of the Chain ------------------------------------------------------------------------------------------


func test_the_chain_knows_find_familiar_without_a_slot_and_its_special_forms() -> void:
	var s := _hero(3, ["pact_of_the_chain"])
	var c := s.character
	assert_bool(SpellRules.is_free(c, "find_familiar")).is_true()
	var forms: Array = AllyRules.familiar_options(s, data, c).map(func(o: Dictionary) -> String: return str(o["id"]))
	assert_array(forms).contains(["imp", "quasit", "sprite", "cat"])
	var plain := _hero(3, [])
	plain.character["spells"]["free"] = ["find_familiar"]
	assert_array(AllyRules.familiar_options(plain, data, plain.character).map(func(o: Dictionary) -> String: return str(o["id"]))).not_contains(["imp"])


func test_the_familiar_comes_in_the_form_picked() -> void:
	var s := _hero(3, ["pact_of_the_chain"])
	AllyRules.choose_familiar(s, data, Sheet.HERO, "imp")
	AllyRules.summon(s, data, "find_familiar")
	assert_str(str(AllyRules.called(s)[0]["monster"])).is_equal("imp")
	AllyRules.choose_familiar(s, data, Sheet.HERO, "dragon")  # no such form: nothing changes
	assert_str(AllyRules.familiar_form(s, data, s.character)).is_equal("imp")


func test_the_warlock_gives_one_attack_and_the_familiar_strikes_by_its_reaction() -> void:
	var s := _hero(3, ["pact_of_the_chain"])
	AllyRules.choose_familiar(s, data, Sheet.HERO, "sprite")
	AllyRules.summon(s, data, "find_familiar")
	TestUtils.fight(s, data, [{"monster": "goblin", "col": 3}])
	var hero := CombatRules.player(s)
	s.combat["turn"] = (s.combat["order"] as Array).find(CombatRules.PLAYER)
	s.combat["current"] = CombatRules.PLAYER
	var fam := preload("res://core/acts/familiar_strike.gd").familiar(s, hero)
	assert_dict(fam).is_not_empty()
	var foe := CombatRules.fighter(s, TestUtils.foe(s, 1))
	FightGrid.put(fam, FightGrid.cell(foe) + Vector2i(-1, 0))
	var act := Acts.one("familiar_strike")
	assert_str(act.can(s, data, hero, str(foe["id"]))).is_equal("")
	var lines := act.go(s, data, hero, str(foe["id"]))
	assert_str(" ".join(lines)).contains("отдаёт атаку фамильяру")
	assert_bool(bool(fam["reacted"])).is_true()
	assert_str(act.can(s, data, hero, str(foe["id"]))).is_not_empty()  # its reaction is spent
	var none := _hero(3, [])
	TestUtils.fight(none, data, [{"monster": "goblin", "col": 3}])
	assert_bool(act.shown(none, data, CombatRules.player(none))).is_false()


# --- Pact of the Tome -------------------------------------------------------------------------------------------


func test_the_tome_picked_at_level_three_asks_three_cantrips_of_any_class() -> void:
	var s := _hero(2, [])
	var c := s.character
	c["xp"] = LevelUp.xp_for(data, 3)
	var picks := {"options": {"pact_boon": ["pact_of_the_tome"]}}
	var p := LevelUp.plan(c, data, picks)
	assert_int(int(p["tome"])).is_equal(3)
	assert_array(p["tome_list"]).contains(["sacred_flame", "fire_bolt"])  # a cleric's and a wizard's
	assert_array(LevelUp.errors(c, data, picks)).contains(["LVL_ERR_TOME"])
	assert_int(int(LevelUp.plan(c, data, {"options": {"pact_boon": ["pact_of_the_blade"]}})["tome"])).is_equal(0)


func test_the_tomes_cantrips_are_cast_only_with_the_book() -> void:
	var s := _hero(2, [])
	var c := s.character
	c["xp"] = LevelUp.xp_for(data, 3)
	var picks := LevelUp.default_picks(c, data)
	picks["options"] = {"pact_boon": ["pact_of_the_tome"]}
	picks["tome"] = ["sacred_flame", "fire_bolt", "guidance"]
	assert_array(LevelUp.errors(c, data, picks)).is_empty()
	LevelUp.apply(c, data, picks, s.items)
	assert_int(int(c["inventory"].get("book_of_shadows", 0))).is_equal(1)
	assert_array(SpellRules.ready(c)).contains(["sacred_flame", "fire_bolt", "guidance"])
	ItemRules.remove(c, "book_of_shadows")
	assert_array(SpellRules.ready(c)).not_contains(["sacred_flame"])
