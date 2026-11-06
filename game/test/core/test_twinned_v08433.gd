extends GdUnitTestSuite
## Twinned Spell (v0.8.4.33): a spell of one creature cast at a second one in range, paid by its circle (a cantrip 1);
## the hero picks the second as a chosen target, a sorcerer foe takes the nearest; areas, darts and spells on oneself never.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _sorcerer() -> GameSession:
	var s := TestUtils.new_session()
	for p: Dictionary in data["presets"]:
		if p["id"] == "sorcerer_zlata":
			s.character = GameSession.normalized_character(CharacterBuilder.build_preset(p, data))
	while int(s.character["level"]) < 3:
		s.character["xp"] = LevelUp.xp_for(data, int(s.character["level"]) + 1)
		LevelUp.apply(s.character, data, LevelUp.default_picks(s.character, data))
	(s.character["features"] as Array).append("metamagic_twinned_spell")
	CharacterRules.refresh(s.character, data, s.items)
	s.character["hp"] = int(s.character["max_hp"])
	return s


func _turn(s: GameSession) -> void:
	s.combat["turn"] = (s.combat["order"] as Array).find(CombatRules.PLAYER)
	s.combat["current"] = CombatRules.PLAYER
	var hero := CombatRules.player(s)
	hero["points"] = CombatRules.fresh_points(s, data, hero)


func test_what_may_be_twinned() -> void:
	var s := _sorcerer()
	TestUtils.fight(s, data, [{"monster": "goblin", "col": 3}])
	assert_bool(FeatureRules.twin_fits(s, data, "fire_bolt", 0)).is_true()
	assert_bool(FeatureRules.twin_fits(s, data, "magic_missile", 1)).is_false()  # darts
	assert_bool(FeatureRules.twin_fits(s, data, "burning_hands", 1)).is_false()  # an area
	assert_bool(FeatureRules.twin_fits(s, data, "shield", 1)).is_false()  # on oneself
	assert_int(FeatureRules.meta_cost(data, "twinned_spell", "fire_bolt", 0)).is_equal(1)
	assert_int(FeatureRules.meta_cost(data, "twinned_spell", "hold_person", 3)).is_equal(3)
	assert_array(FeatureRules.metamagic(s.character, data).map(func(m: Dictionary) -> String: return str(m["id"]))).contains(["twinned_spell"])


func test_the_hero_twins_a_fire_bolt_at_a_second_goblin() -> void:
	var s := _sorcerer()
	TestUtils.fight(s, data, [{"monster": "goblin", "col": 3, "name": "Первый"}, {"monster": "goblin", "col": 3, "name": "Второй"}])
	_turn(s)
	var hero := CombatRules.player(s)
	var one := str(CombatRules.enemies(s)[0])
	var two := str(CombatRules.enemies(s)[1])
	var points := Stock.left(s.character, data, "sorcery_points")
	hero["metamagic"] = "twinned_spell"
	var lines := Acts.one("cast").go(s, data, hero, one, {"spell": "fire_bolt", "slot": 0})
	assert_str(" ".join(lines)).contains("Удвоенное заклинание")
	assert_int(Stock.left(s.character, data, "sorcery_points")).is_equal(points - 1)
	var v := CombatRules.volley(s)
	assert_str(str(v.get("side", ""))).is_equal("foe")
	assert_str(CombatRules.can_volley(s, data, one)).is_equal("COMBAT_PICKED")  # not the first one again
	assert_str(Acts.one("volley").can(s, data, hero, two)).is_empty()
	var more := Acts.one("volley").go(s, data, hero, two)
	assert_str(" ".join(more)).contains(str(CombatRules.fighter(s, two)["name"]))
	assert_dict(CombatRules.volley(s)).is_empty()


func test_a_spell_that_does_not_fit_is_cast_plain_and_costs_nothing() -> void:
	var s := _sorcerer()
	TestUtils.fight(s, data, [{"monster": "goblin", "col": 3}, {"monster": "goblin", "col": 3}])
	_turn(s)
	var hero := CombatRules.player(s)
	var points := Stock.left(s.character, data, "sorcery_points")
	hero["metamagic"] = "twinned_spell"
	var lines := Acts.one("cast").go(s, data, hero, str(CombatRules.enemies(s)[0]), {"spell": "magic_missile", "slot": 1})
	assert_str(" ".join(lines)).not_contains("Удвоенное")
	assert_int(Stock.left(s.character, data, "sorcery_points")).is_equal(points)


func test_a_sorcerer_foe_twins_at_the_nearest_other() -> void:
	var s := _sorcerer()
	TestUtils.fight(s, data, [{"monster": "commoner", "class": "sorcerer", "level": 3, "col": 2, "name": "Колдунья"}], {})
	var f := CombatRules.fighter(s, CombatRules.enemies(s)[0])
	(f["features"] as Array).append("metamagic_twinned_spell")
	assert_str(FeatureRules.pay_metamagic(s, data, f, "fire_bolt", 0)).is_equal("twinned_spell")
	s.combat["meta_now"] = "twinned_spell"
	s.combat["by"] = ActionRules.scope(s, data, f, "fire_bolt")
	var lines: Array[String] = []
	ActionRules.twin(s, data, "fire_bolt", 0, "nobody", lines)
	s.combat.erase("by")
	assert_str(" ".join(lines)).contains("Огненный снаряд")


# --- Sculpt Spells (the same version: an evoker's area spares its own side) ----------------------------------------------


func test_an_evoker_shapes_its_area_round_an_ally() -> void:
	var s := TestUtils.new_session()
	for p: Dictionary in data["presets"]:
		if p["id"] == "wizard_yalika":
			s.character = GameSession.normalized_character(CharacterBuilder.build_preset(p, data))
	CharacterRules.refresh(s.character, data, s.items)
	TestUtils.fight(s, data, [{"monster": "goblin", "col": 3}], {"allies": [{"monster": "commoner", "name": "Друг"}]})
	var ally := ""
	for id: String in s.combat["order"]:
		if str(CombatRules.fighter(s, id).get("side")) == "ally":
			ally = id
	var goblin := CombatRules.fighter(s, str(CombatRules.enemies(s)[0]))
	var friend := CombatRules.fighter(s, ally)
	var both: Array[Dictionary] = [goblin, friend]
	var sp: Dictionary = data["spells"]["burning_hands"]
	var lines: Array[String] = []
	assert_int(CombatRules._sculpted(s, data, sp, CombatRules.player(s), both, lines).size()).is_equal(2)  # not an evoker yet
	(s.character["features"] as Array).append("sculpt_spells")
	var left := CombatRules._sculpted(s, data, sp, CombatRules.player(s), both, lines)
	assert_array(left).has_size(1)
	assert_str(str(left[0]["id"])).is_equal(str(goblin["id"]))
	assert_str(" ".join(lines)).contains("вне удара")
	assert_int(CombatRules._sculpted(s, data, data["spells"]["sleep"], CombatRules.player(s), both, lines).size()).is_equal(2)  # not evocation
