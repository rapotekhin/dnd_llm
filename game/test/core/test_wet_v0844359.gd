extends GdUnitTestSuite
## Wet as in BG3 (v0.8.4.43.59, the author's pick of 2026-11-14): water on a creature is one status `wet` of its row — lightning
## and cold double, fire half, no fire takes it and its own goes out — for 2 rounds, renewed while it stands in water or under
## rain. A square of water wets one who walks in and one who starts its turn there, not one who flies over it; a flask of water
## wets the one it hits; a thing keeps the coat of water as before; anybody alike, the hero too.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _goblin(s: GameSession) -> Dictionary:
	var g := ChecklistProbe.fight(s, data, "goblin", true)
	SpellEffects.zones(s).clear()
	g["hp"] = 200
	g["max_hp"] = 200
	return g


## A puddle of water under `f` (a zone that douses, as a flask of water spilt).
func _puddle(s: GameSession, f: Dictionary) -> void:
	var lines: Array[String] = []
	FightField.splash(s, data, FightGrid.cell(f), {"liquid": LiquidRules.WATER}, "вода", lines)


func test_walking_into_water_wets_and_puts_out_the_fire() -> void:
	var s := ChecklistProbe.session(data)
	var g := _goblin(s)
	LiquidRules.coat(s, data, g, "alchemists_fire", "Алхимический огонь", g)
	assert_bool(ConditionRules.has(g, "burning")).is_true()
	_puddle(s, g)
	assert_bool(FightField.douses_at(s, data, FightGrid.cell(g))).is_true()
	var lines: Array[String] = []
	FightField.stepped(s, data, g, lines)
	assert_bool(ConditionRules.has(g, LiquidRules.WET)).override_failure_message(" · ".join(lines)).is_true()
	assert_bool(ConditionRules.has(g, "burning")).is_false()
	assert_bool(lines.any(func(l: String) -> bool: return l.contains("пламя погасло"))).override_failure_message(" · ".join(lines)).is_true()


func test_wet_takes_lightning_and_cold_double_and_fire_half() -> void:
	var s := ChecklistProbe.session(data)
	var g := _goblin(s)
	assert_int(Sheet.taken(s, data, g, "lightning", 8)).is_equal(8)
	LiquidRules.soak(s, data, g, "вода")
	assert_int(Sheet.taken(s, data, g, "lightning", 8)).is_equal(16)
	assert_int(Sheet.taken(s, data, g, "cold", 8)).is_equal(16)
	assert_int(Sheet.taken(s, data, g, "fire", 8)).is_equal(4)
	assert_int(Sheet.taken(s, data, g, "slashing", 8)).is_equal(8)
	var lines: Array[String] = []
	Harm.typed(s, data, g, 5, "lightning", lines)
	assert_int(int(g["hp"])).override_failure_message(" · ".join(lines)).is_equal(190)
	assert_bool(" · ".join(lines).contains("уязвимость")).override_failure_message(" · ".join(lines)).is_true()


func test_a_wet_creature_does_not_catch_fire() -> void:
	var s := ChecklistProbe.session(data)
	var g := _goblin(s)
	LiquidRules.soak(s, data, g, "вода")
	LiquidRules.coat(s, data, g, "alchemists_fire", "Алхимический огонь", g)
	assert_bool(ConditionRules.has(g, "burning")).is_false()
	FightField._light(s, FightGrid.cell(g) + Vector2i(1, 0))
	FightField._sync_fire(s, data)
	g["x"] = int(g["x"]) + 1
	SpellEffects.zone_tick(s, data, g, "enter")
	assert_bool(ConditionRules.has(g, "burning")).is_false()
	var card := CreatureCard.defenses(s, data, g)
	assert_bool(card.any(func(d: Dictionary) -> bool: return str(d["kind"]) == "no_condition" and str(d["what"]).contains("горит"))) \
		.override_failure_message(str(card)).is_true()
	assert_bool(card.any(func(d: Dictionary) -> bool: return str(d["kind"]) == "vulnerable" and str(d["what"]).contains("электричество"))) \
		.override_failure_message(str(card)).is_true()


func test_wet_lasts_two_rounds_and_is_renewed_in_water() -> void:
	var s := ChecklistProbe.session(data)
	var g := _goblin(s)
	_puddle(s, g)
	var lines: Array[String] = []
	FightField.stepped(s, data, g, lines)
	assert_int(ConditionRules.effects_of(g, LiquidRules.WET).size()).is_equal(1)
	s.combat["round"] = int(s.combat.get("round", 1)) + 1
	FightField.soak(s, data, g, lines)  # still in the water at the start of its turn: renewed, not doubled
	assert_int(ConditionRules.effects_of(g, LiquidRules.WET).size()).is_equal(1)
	var at := int(ConditionRules.effects_of(g, LiquidRules.WET)[0]["ends"]["at"])
	assert_int(at).is_equal(ConditionRules.now(s) + 2)
	SpellEffects.zones(s).clear()  # out of the water: two rounds more, then dry
	s.combat["round"] = int(s.combat["round"]) + 1
	ConditionRules.end_of_turn(s, data, g)
	assert_bool(ConditionRules.has(g, LiquidRules.WET)).is_true()
	s.combat["round"] = int(s.combat["round"]) + 1
	lines.append_array(ConditionRules.end_of_turn(s, data, g))
	assert_bool(ConditionRules.has(g, LiquidRules.WET)).override_failure_message(" · ".join(lines)).is_false()


func test_one_flying_over_water_stays_dry() -> void:
	var s := ChecklistProbe.session(data)
	var g := _goblin(s)
	SpellEffects.on_friend(s, data, "fly", 3, g, [] as Array[String])
	assert_bool(CombatRules.airborne(s, data, g)).is_true()
	_puddle(s, g)
	var lines: Array[String] = []
	FightField.stepped(s, data, g, lines)
	assert_bool(ConditionRules.has(g, LiquidRules.WET)).is_false()


func test_a_flask_of_water_wets_the_one_it_hits_and_a_thing_keeps_its_coat() -> void:
	var s := ChecklistProbe.session(data)
	var g := _goblin(s)
	LiquidRules.coat(s, data, g, "oil", "масло", g)
	var lines := LiquidRules.coat(s, data, g, LiquidRules.WATER, "вода", g)
	assert_bool(ConditionRules.has(g, LiquidRules.WET)).is_true()
	assert_bool(LiquidRules.coat_on(s, g).is_empty()).is_true()  # the oil washed off, water is no coat on a creature
	assert_bool(lines.any(func(l: String) -> bool: return l.contains("промокает"))).override_failure_message(" · ".join(lines)).is_true()
	var chest := {}
	LiquidRules.coat(s, data, chest, LiquidRules.WATER, "вода")
	assert_bool(LiquidRules.douses(s, chest)).is_true()
	assert_bool(ConditionRules.has(chest, LiquidRules.WET)).is_false()


func test_the_hero_is_wet_by_the_same_road() -> void:
	var s := ChecklistProbe.session(data)
	_goblin(s)
	var p := CombatRules.player(s)
	s.character["hp"] = 60
	s.character["temp_hp"] = 0
	_puddle(s, p)
	var lines: Array[String] = []
	FightField.stepped(s, data, p, lines)
	assert_bool(ConditionRules.has(s.character, LiquidRules.WET)).override_failure_message(" · ".join(lines)).is_true()
	Harm.typed(s, data, p, 5, "cold", lines, "холод", false)
	assert_int(int(s.character["hp"])).override_failure_message(" · ".join(lines)).is_equal(50)
	assert_str(" · ".join(ConditionRules.impose(s, data, {"condition": "burning", "ends": {}, "source": {"kind": "engine", "name": "огонь"}}))) \
		.contains("не действует")


func test_rain_wets_everybody_under_the_sky_and_not_under_a_roof() -> void:
	var s := ChecklistProbe.session(data)
	s.settings["weather"] = true
	s.room_id = "brod-square"
	var g := _goblin(s)
	WeatherRules._state(s)["by_loc"][WorldView.new(data["world"]).location_id(s.room_id)] = "downpour"
	assert_str(WeatherRules.wets(s, data)).is_equal("ливень")
	var lines: Array[String] = []
	FightField.soak(s, data, g, lines)
	assert_bool(ConditionRules.has(g, LiquidRules.WET)).is_true()
	assert_bool(lines.is_empty()).override_failure_message(" · ".join(lines)).is_true()  # everybody is wet: not told one by one
	var dry := ChecklistProbe.session(data)
	dry.settings["weather"] = true
	var d := _goblin(dry)
	WeatherRules._state(dry)["by_loc"][WorldView.new(data["world"]).location_id(dry.room_id)] = "downpour"
	FightField.soak(dry, data, d, lines)
	assert_bool(ConditionRules.has(d, LiquidRules.WET)).is_false()  # the tavern's hall has a roof


func test_the_master_and_the_console_lay_wet_on_a_creature() -> void:
	assert_bool(Cheats.conditions(data).has(LiquidRules.WET)).is_true()
	assert_bool(ThingRules.only_things(data, LiquidRules.WET)).is_false()
	var s := ChecklistProbe.session(data)
	var lines := Cheats.condition(s, data, Being.HERO, LiquidRules.WET, true)
	assert_bool(ConditionRules.has(s.character, LiquidRules.WET)).override_failure_message(" · ".join(lines)).is_true()
