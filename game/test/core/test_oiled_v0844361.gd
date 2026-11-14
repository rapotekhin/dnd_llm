extends GdUnitTestSuite
## Oil underfoot (v0.8.4.43.61, the author: «кто-то наступил в лужу масла — статус облито маслом»): a puddle of oil coats the
## one who walks in or starts its turn there — the one coat `coated` with its liquid (v0.8.4.28.2), fire on it +5 — shown as
## «облито маслом» with its own icon (the row `oiled` of its liquid), told once; not one who flies over it; anybody alike,
## the hero too.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _goblin(s: GameSession) -> Dictionary:
	var g := ChecklistProbe.fight(s, data, "goblin", true)
	SpellEffects.zones(s).clear()
	g["hp"] = 200
	g["max_hp"] = 200
	return g


## A puddle of oil under `f`: a flask of oil spilt on its square.
func _oil(s: GameSession, f: Dictionary) -> void:
	var lines: Array[String] = []
	FightField.splash(s, data, FightGrid.cell(f), {"liquid": "oil"}, "Масло", lines)


func _oiled(s: GameSession, who: Dictionary) -> Array:
	return ConditionRules.shown(s, data, who).filter(func(x: Dictionary) -> bool: return str(x["name"]) == "облито маслом")


func test_stepping_into_oil_is_oiled() -> void:
	var s := ChecklistProbe.session(data)
	var g := _goblin(s)
	_oil(s, g)
	assert_bool(LiquidRules.coat_on(s, g).is_empty()).is_true()  # the puddle is on the ground until one walks in
	var lines: Array[String] = []
	FightField.stepped(s, data, g, lines)
	assert_str(str(LiquidRules.coat_on(s, g).get("liquid", ""))).override_failure_message(" · ".join(lines)).is_equal("oil")
	var st := _oiled(s, g)
	assert_int(st.size()).override_failure_message(str(ConditionRules.shown(s, data, g))).is_equal(1)
	assert_str(str(st[0]["icon"])).is_equal("conditions/oiled")
	assert_str(str(st[0]["text"])).contains("Облито маслом")
	assert_bool(lines.any(func(l: String) -> bool: return l.contains("облито маслом"))).override_failure_message(" · ".join(lines)).is_true()


func test_oil_on_one_who_stepped_in_makes_fire_burn_more() -> void:
	var s := ChecklistProbe.session(data)
	var g := _goblin(s)
	_oil(s, g)
	var lines: Array[String] = []
	FightField.stepped(s, data, g, lines)
	Harm.typed(s, data, g, 1, "fire", lines, "огонь", false)
	assert_int(int(g["hp"])).override_failure_message(" · ".join(lines)).is_less_equal(200 - 6)
	assert_bool(LiquidRules.coat_on(s, g).is_empty()).is_true()  # the oil burns away with the blow


func test_standing_in_oil_renews_the_coat_and_tells_it_once() -> void:
	var s := ChecklistProbe.session(data)
	var g := _goblin(s)
	_oil(s, g)
	var lines: Array[String] = []
	FightField.stepped(s, data, g, lines)
	var first := int(LiquidRules.coat_on(s, g)["ends"]["at"])
	s.combat["round"] = int(s.combat.get("round", 1)) + 1
	var again: Array[String] = []
	FightField.soak(s, data, g, again)  # still in the oil at the start of its turn
	assert_int(ConditionRules.effects_of(g, "coated").size()).is_equal(1)
	assert_int(int(LiquidRules.coat_on(s, g)["ends"]["at"])).is_greater(first)
	assert_bool(again.any(func(l: String) -> bool: return l.contains("облито маслом"))).override_failure_message(" · ".join(again)).is_false()


func test_one_flying_over_oil_stays_clean() -> void:
	var s := ChecklistProbe.session(data)
	var g := _goblin(s)
	SpellEffects.on_friend(s, data, "fly", 3, g, [] as Array[String])
	assert_bool(CombatRules.airborne(s, data, g)).is_true()
	_oil(s, g)
	var lines: Array[String] = []
	FightField.stepped(s, data, g, lines)
	assert_bool(LiquidRules.coat_on(s, g).is_empty()).is_true()
	assert_bool(_oiled(s, g).is_empty()).is_true()


func test_the_hero_is_oiled_by_the_same_road() -> void:
	var s := ChecklistProbe.session(data)
	_goblin(s)
	var p := CombatRules.player(s)
	_oil(s, p)
	var lines: Array[String] = []
	FightField.stepped(s, data, p, lines)
	assert_str(str(LiquidRules.coat_on(s, s.character).get("liquid", ""))).override_failure_message(" · ".join(lines)).is_equal("oil")
	assert_int(_oiled(s, Sheet.HERO).size()).is_equal(1)


func test_water_puddle_wets_and_does_not_oil() -> void:
	var s := ChecklistProbe.session(data)
	var g := _goblin(s)
	var lines: Array[String] = []
	FightField.splash(s, data, FightGrid.cell(g), {"liquid": LiquidRules.WATER}, "вода", lines)
	FightField.stepped(s, data, g, lines)
	assert_bool(ConditionRules.has(g, LiquidRules.WET)).is_true()
	assert_bool(LiquidRules.coat_on(s, g).is_empty()).is_true()
