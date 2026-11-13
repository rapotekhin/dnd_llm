extends GdUnitTestSuite
## Surfaces a damage leaves (v0.8.4.43.45, `rules.combat.grid.surfaces`, `FightField.react`): lightning on water lays
## water under current, radiance blesses water against the undead and fiends, a fiend's fire leaves hellfire on any floor;
## a surface lies its rounds and goes by `SpellEffects.zones_expire`.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _wet(s: GameSession, at: Vector2i) -> void:
	var lines: Array[String] = []
	FightField.splash(s, data, at, {"liquid": "water"}, "Вода", lines)


func _of(s: GameSession, id: String) -> Array:
	return SpellEffects.zones(s).filter(func(z: Dictionary) -> bool: return str(z["spell"]) == id)


func test_lightning_on_a_puddle_electrifies_only_the_wet_squares() -> void:
	var s := ChecklistProbe.session(data)
	var goblin := ChecklistProbe.fight(s, data, "goblin")
	var wet := FightGrid.cell(goblin) + Vector2i(1, 0)
	var dry := FightGrid.cell(goblin) + Vector2i(2, 0)
	_wet(s, wet)
	var lines: Array[String] = []
	FightField.react(s, data, "lightning", [wet, dry] as Array[Vector2i], CombatRules.player(s), lines)
	var z := _of(s, "electric_water")
	assert_int(z.size()).override_failure_message(" · ".join(lines)).is_equal(1)
	assert_array(z[0]["cells"]).contains_exactly([FightGrid.tag(wet)])
	assert_str(str(z[0]["type"])).is_equal("lightning")
	assert_bool(SpellEffects.harmful(z[0])).is_true()


func test_no_surface_where_nothing_fits() -> void:
	var s := ChecklistProbe.session(data)
	var goblin := ChecklistProbe.fight(s, data, "goblin")
	var lines: Array[String] = []
	FightField.react(s, data, "lightning", [FightGrid.cell(goblin) + Vector2i(2, 0)] as Array[Vector2i], CombatRules.player(s), lines)
	FightField.react(s, data, "cold", [FightGrid.cell(goblin) + Vector2i(2, 0)] as Array[Vector2i], CombatRules.player(s), lines)
	assert_array(SpellEffects.zones(s).filter(func(z: Dictionary) -> bool: return str(z["spell"]) in ["electric_water", "blessed_water", "hellfire"])).is_empty()


func test_blessed_water_touches_only_the_undead_and_fiends() -> void:
	var s := ChecklistProbe.session(data)
	var goblin := ChecklistProbe.fight(s, data, "goblin")
	var at := FightGrid.cell(goblin) + Vector2i(1, 0)
	_wet(s, at)
	var lines: Array[String] = []
	FightField.react(s, data, "radiant", [at] as Array[Vector2i], CombatRules.player(s), lines)
	var z := _of(s, "blessed_water")
	assert_int(z.size()).is_equal(1)
	assert_array(z[0]["types"]).contains_exactly_in_any_order(["undead", "fiend"])


func test_hellfire_only_from_a_fiends_fire() -> void:
	var s := ChecklistProbe.session(data)
	var goblin := ChecklistProbe.fight(s, data, "goblin")
	var at := FightGrid.cell(goblin) + Vector2i(1, 0)
	var lines: Array[String] = []
	FightField.react(s, data, "fire", [at] as Array[Vector2i], CombatRules.player(s), lines)
	assert_array(_of(s, "hellfire")).is_empty()
	var imp := {"id": "imp_1", "monster": "imp"}
	assert_str(str(Sheet.template(data, imp).get("type", ""))).is_equal("fiend")
	FightField.react(s, data, "fire", [at] as Array[Vector2i], imp, lines)
	assert_int(_of(s, "hellfire").size()).is_equal(1)


func test_a_surface_lies_its_rounds_and_a_new_one_takes_its_square() -> void:
	var s := ChecklistProbe.session(data)
	var goblin := ChecklistProbe.fight(s, data, "goblin")
	var at := FightGrid.cell(goblin) + Vector2i(1, 0)
	_wet(s, at)
	s.combat["round"] = 3
	var lines: Array[String] = []
	FightField.react(s, data, "lightning", [at] as Array[Vector2i], {}, lines)
	FightField.react(s, data, "lightning", [at] as Array[Vector2i], {}, lines)
	assert_int(_of(s, "electric_water").size()).is_equal(1)  # one of its kind on a square
	SpellEffects.zones_expire(s)
	assert_int(_of(s, "electric_water").size()).is_equal(1)  # it lies through its round
	s.combat["round"] = 4
	SpellEffects.zones_expire(s)
	assert_array(_of(s, "electric_water")).is_empty()


func test_a_lightning_spell_at_a_foe_in_water_lays_the_surface() -> void:
	var s := ChecklistProbe.session(data)
	var goblin := ChecklistProbe.fight(s, data, "goblin")
	goblin["hp"] = 200
	_wet(s, FightGrid.cell(goblin))
	var lines: Array[String] = []
	CombatRules._spell_damage(s, data, "lightning_bolt", 3, str(goblin["id"]), lines)
	assert_int(_of(s, "electric_water").size()).override_failure_message(" · ".join(lines)).is_equal(1)
