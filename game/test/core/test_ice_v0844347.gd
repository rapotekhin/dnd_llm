extends GdUnitTestSuite
## Ice (v0.8.4.43.47): cold on water freezes it — a row `ice` of `rules.combat.grid.surfaces`: slow ground with a DEX save
## or prone on entering, ten rounds, drawn as the ground `ice`; it ends the current on its squares (`clears`).

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _of(s: GameSession, id: String) -> Array:
	return SpellEffects.zones(s).filter(func(z: Dictionary) -> bool: return str(z["spell"]) == id)


func test_cold_on_water_freezes_it_and_ends_the_current() -> void:
	var s := ChecklistProbe.session(data)
	var goblin := ChecklistProbe.fight(s, data, "goblin")
	var at := FightGrid.cell(goblin) + Vector2i(1, 0)
	var dry := FightGrid.cell(goblin) + Vector2i(2, 0)
	var lines: Array[String] = []
	FightField.splash(s, data, at, {"liquid": "water"}, "Вода", lines)
	FightField.react(s, data, "lightning", [at] as Array[Vector2i], {}, lines)
	assert_int(_of(s, "electric_water").size()).is_equal(1)
	FightField.react(s, data, "cold", [at, dry] as Array[Vector2i], {}, lines)
	var ice := _of(s, "ice")
	assert_int(ice.size()).is_equal(1)
	assert_array(ice[0]["cells"]).contains_exactly([FightGrid.tag(at)])
	assert_bool(bool(ice[0]["slow"])).is_true()
	assert_array(_of(s, "electric_water")).is_empty()
	assert_str(str(SpellEffects.zone_view(s, data).filter(func(v: Dictionary) -> bool: return str(v["name"]) == "Лёд")[0]["look"]["ground"])).is_equal("ice")


func test_one_stepping_on_ice_may_fall() -> void:
	var s := ChecklistProbe.session(data)
	var goblin := ChecklistProbe.fight(s, data, "goblin")
	var at := FightGrid.cell(goblin) + Vector2i(1, 0)
	var lines: Array[String] = []
	FightField.splash(s, data, at, {"liquid": "water"}, "Вода", lines)
	FightField.react(s, data, "cold", [at] as Array[Vector2i], {}, lines)
	_of(s, "ice")[0]["dc"] = 99
	FightGrid.put(goblin, at)
	goblin["zoned"] = []
	SpellEffects.zone_tick(s, data, goblin, "enter")
	assert_bool(CombatRules._has(goblin, "prone")).is_true()
