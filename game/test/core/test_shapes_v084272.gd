extends GdUnitTestSuite
## Shapechanger and Mimicry on the engine's roads (roadmap v0.8.4.27.2): a form is a row of `rules.shapes` — another
## template's body without hit points of its own, or its own with other feet; the AI takes it when its blows are better;
## it falls in its true form. A voice of Mimicry is told by Insight against the trait's own DC. One end for what lasts
## until someone's turn: Shield, Help and a spell's riders (`ends.turn`), gone with the fight too.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func test_a_werewolf_takes_the_wolf_with_its_bite_and_keeps_its_hit_points() -> void:
	var s := ChecklistProbe.session(data)
	var f := ChecklistProbe.fight(s, data, "werewolf_human")
	f["hp"] = 40
	ChecklistProbe.turn(s, data, f)
	assert_str(Acts.one("shape").can(s, data, f, "", {"form": "wolf"})).is_empty()
	Acts.one("shape").go(s, data, f, "", {"form": "wolf"})
	assert_str(Sheet.template_id(data, f)).is_equal("werewolf_wolf")
	assert_str(str(Attack.way(s, data, f, {"action": "Bite"}).get("name", ""))).is_not_empty()
	assert_bool(Attack.way(s, data, f, {"action": "Spear"}).is_empty()).is_true()
	assert_int(CombatRules.ac_of(f)).is_equal(int(data["monsters"]["werewolf_wolf"]["ac"]))
	var lines: Array[String] = []
	Harm.take(s, data, f, 5, lines, "slashing")
	assert_int(int(f["hp"])).is_equal(35)
	assert_str(FeatureRules.form_of(s, f)).is_equal("wolf")
	FeatureRules.take_form(s, data, f, "")
	assert_str(Sheet.template_id(data, f)).is_equal("werewolf_human")
	assert_bool(Attack.way(s, data, f, {"action": "Spear"}).is_empty()).is_false()


func test_an_imp_as_a_raven_flies_faster_and_as_a_rat_not_at_all() -> void:
	var s := ChecklistProbe.session(data)
	var f := ChecklistProbe.fight(s, data, "imp")
	FeatureRules.take_form(s, data, f, "raven")
	assert_int(int(Move.speeds(s, data, f).get("fly", 0))).is_equal(60)
	assert_str(Sheet.template_id(data, f)).is_equal("imp")
	FeatureRules.take_form(s, data, f, "rat")
	assert_bool(Move.speeds(s, data, f).has("fly")).is_false()
	assert_int(Move.feet(s, data, f)).is_equal(20)


func test_a_shapechanger_falls_in_its_true_form() -> void:
	var s := ChecklistProbe.session(data)
	var f := ChecklistProbe.fight(s, data, "wererat_human")
	FeatureRules.take_form(s, data, f, "rat")
	f["hp"] = 3
	var lines: Array[String] = []
	Harm.take(s, data, f, 10, lines, "slashing")
	assert_str(str(f["status"])).is_equal("dead")
	assert_str(FeatureRules.form_of(s, f)).is_empty()
	assert_str(Sheet.template_id(data, f)).is_equal("wererat_human")


func test_the_ai_takes_the_hybrid_for_its_claws() -> void:
	var s := ChecklistProbe.session(data)
	var f := ChecklistProbe.fight(s, data, "werewolf_human")
	ChecklistProbe.turn(s, data, f)
	var offers := Acts.one("shape").offers(s, data, f, [CombatRules.player(s)])
	assert_bool(offers.any(func(o: Dictionary) -> bool: return str(o["how"]["form"]) == "hybrid" and float(o["power"]) > 0.0)).is_true()
	assert_bool(offers.any(func(o: Dictionary) -> bool: return str(o["how"]["form"]) == "human")).is_false()


func test_the_way_back_is_offered_once() -> void:
	var s := ChecklistProbe.session(data)
	var f := ChecklistProbe.fight(s, data, "wererat_hybrid")
	FeatureRules.take_form(s, data, f, "rat")
	var forms: Array = Acts.one("shape").buttons(s, data, f).map(func(b: Dictionary) -> String: return str(b["how"]["form"]))
	assert_array(forms).contains_exactly_in_any_order(["human", ""])


func test_mimicry_is_told_by_insight_against_its_own_dc() -> void:
	var s := ChecklistProbe.session(data)
	ChecklistProbe.fight(s, data, "raven")
	assert_int(int(CheckEngine.trait_dc(s, data, "mimicry", "insight").get("dc", 0))).is_equal(10)
	assert_bool(CheckEngine.trait_dc(s, data, "mimicry", "perception").is_empty()).is_true()
	var sp: Dictionary = CheckEngine.spec(s, data, {"skill": "insight", "dc_tier": "hard", "about": "mimicry"})["spec"]
	assert_int(int(sp["dc"])).is_equal(10)


func test_chill_touch_holds_off_any_healing_until_the_casters_turn() -> void:
	var s := ChecklistProbe.session(data)
	var f := ChecklistProbe.fight(s, data, "goblin")
	f["hp"] = 10
	var lines: Array[String] = []
	ActionRules.riders(s, data, "chill_touch", 0, f, true, lines)
	assert_int(Harm.heal(data, f, 5)).is_equal(0)
	assert_str(ConditionRules.left_text(s, ConditionRules.effects(f)[-1])).is_equal("до следующего хода")
	ConditionRules.turn_comes(f, CombatRules.PLAYER)
	assert_int(Harm.heal(data, f, 5)).is_equal(5)


func test_help_ends_at_the_helpers_turn_and_shield_with_the_fight() -> void:
	var s := ChecklistProbe.session(data)
	var f := ChecklistProbe.fight(s, data, "goblin")
	TestUtils.beside(s, f)
	ChecklistProbe.turn(s, data, CombatRules.player(s))
	Acts.one("help").go(s, data, CombatRules.player(s), str(f["id"]))
	assert_bool(ConditionRules.has(f, "helped")).is_true()
	ConditionRules.turn_comes(f, str(f["id"]))
	assert_bool(ConditionRules.has(f, "helped")).is_true()
	ConditionRules.turn_comes(f, CombatRules.PLAYER)
	assert_bool(ConditionRules.has(f, "helped")).is_false()
	SpellEffects.guard(s, data, Sheet.HERO, "shield")
	assert_bool(ConditionRules.effects(s.character).any(func(e: Dictionary) -> bool: return e.get("ends", {}).has("turn"))).is_true()
	CombatRules.close(s)
	assert_bool(ConditionRules.effects(s.character).any(func(e: Dictionary) -> bool: return e.get("ends", {}).has("turn"))).is_false()
