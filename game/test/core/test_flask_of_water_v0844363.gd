extends GdUnitTestSuite
## A flask of water thrown (v0.8.4.43.63, the author: «кидают склянку с водой»): a vessel that breaks (`throw` of its row in
## `rules.liquids.vessels`: a flask, a bottle, a vial) is thrown from the belt with what it holds, by that liquid's `throw` —
## water at one burning puts the fire out and wets it, on a square it is a puddle that puts the fire there out; the very copy
## that held it breaks, an empty one is not thrown; a waterskin is no flask.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _goblin(s: GameSession) -> Dictionary:
	var g := ChecklistProbe.fight(s, data, "goblin")
	SpellEffects.zones(s).clear()
	g["hp"] = 200
	g["max_hp"] = 200
	g["ac"] = 1
	return g


## `n` flasks on the hero's belt: new ones, full of water as a new holder's vessels are.
func _flasks(s: GameSession, n: int) -> void:
	s.character["inventory"]["empty_flask"] = n
	ItemRules.belt_put(s.character, data, s.items, "empty_flask")


func _throw(s: GameSession, to: String) -> Array[String]:
	var hero := CombatRules.player(s)
	var lines: Array[String] = []
	for i in 9:
		ChecklistProbe.turn(s, data, hero)
		lines.append_array(Acts.one("throw").go(s, data, hero, to, {"item": "empty_flask"}))
		var t := CombatRules.fighter(s, to)
		if t.is_empty() or ConditionRules.has(t, LiquidRules.WET):
			break
	return lines


func test_a_flask_of_water_puts_out_one_burning_and_wets_it() -> void:
	var s := ChecklistProbe.session(data)
	var g := _goblin(s)
	LiquidRules.coat(s, data, g, "alchemists_fire", "Алхимический огонь", g)
	assert_bool(ConditionRules.has(g, "burning")).is_true()
	_flasks(s, 9)
	var hero := CombatRules.player(s)
	assert_str(Acts.one("throw").why(s, data, hero, str(g["id"]), {"item": "empty_flask"})).is_empty()
	var lines := _throw(s, str(g["id"]))
	assert_bool(ConditionRules.has(g, LiquidRules.WET)).override_failure_message(" · ".join(lines)).is_true()
	assert_bool(ConditionRules.has(g, "burning")).override_failure_message(" · ".join(lines)).is_false()
	assert_bool(lines.any(func(l: String) -> bool: return l.contains("вода"))).override_failure_message(" · ".join(lines)).is_true()


func test_a_flask_of_water_on_a_square_is_a_puddle_that_puts_the_fire_out() -> void:
	var s := ChecklistProbe.session(data)
	_goblin(s)
	_flasks(s, 1)
	var at := FightGrid.cell(CombatRules.player(s)) + Vector2i(0, 2)
	FightField._light(s, at)
	FightField._sync_fire(s, data)
	var hero := CombatRules.player(s)
	ChecklistProbe.turn(s, data, hero)
	var lines := Acts.one("throw").go(s, data, hero, FightGrid.aim_id(at), {"item": "empty_flask"})
	assert_bool((s.combat["fires"] as Dictionary).has(FightGrid.tag(at))).override_failure_message(" · ".join(lines)).is_false()
	assert_bool(FightField.douses_at(s, data, at)).is_true()
	assert_int(int(s.character["inventory"].get("empty_flask", 0))).is_equal(0)  # the flask broke


func test_the_full_copy_breaks_and_an_empty_one_is_not_thrown() -> void:
	var s := ChecklistProbe.session(data)
	var g := _goblin(s)
	_flasks(s, 2)
	var c := s.character
	var mine := LiquidRules.carried(c, data).filter(func(v: Dictionary) -> bool: return v["id"] == "empty_flask")
	assert_int(mine.size()).is_equal(2)
	LiquidRules.pour_out(c, data, mine[0], s.items)  # the first one emptied, the second full
	assert_int(int(ItemRules.use_of(c, data, s.items, "empty_flask")["throw"]["copy"])).is_equal(1)
	var hero := CombatRules.player(s)
	ChecklistProbe.turn(s, data, hero)
	Acts.one("throw").go(s, data, hero, FightGrid.aim_id(FightGrid.cell(g) + Vector2i(1, 0)), {"item": "empty_flask"})
	var left := LiquidRules.carried(c, data).filter(func(v: Dictionary) -> bool: return v["id"] == "empty_flask")
	assert_int(left.size()).is_equal(1)
	assert_float(float(left[0]["pints"])).is_equal(0.0)  # the empty one stays
	assert_str(Acts.one("throw").why(s, data, hero, str(g["id"]), {"item": "empty_flask"})).is_equal("COMBAT_ITEM_CANT")


func test_a_bottle_of_oil_is_thrown_as_oil_and_a_waterskin_is_no_flask() -> void:
	var s := ChecklistProbe.session(data)
	_goblin(s)
	var c := s.character
	c["inventory"]["bottle_glass"] = 1
	var v: Dictionary = LiquidRules.carried(c, data).filter(func(x: Dictionary) -> bool: return x["id"] == "bottle_glass")[0]
	LiquidRules._put(c, v, 1.0, "oil")
	assert_str(str(ItemRules.use_of(c, data, s.items, "bottle_glass").get("throw", {}).get("liquid", ""))).is_equal("oil")
	assert_bool(ItemRules.belt_fits(data, s.items, "empty_flask")).is_true()
	assert_bool(ItemRules.belt_fits(data, s.items, "waterskin")).is_false()
	c["inventory"]["waterskin"] = 1
	assert_bool(ItemRules.use_of(c, data, s.items, "waterskin").is_empty()).is_true()
