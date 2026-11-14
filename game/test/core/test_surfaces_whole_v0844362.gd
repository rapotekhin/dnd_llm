extends GdUnitTestSuite
## Surfaces as in BG3 and Divinity (v0.8.4.43.62, the author's list of 2026-11-14): oil on a creature that fire takes burns
## on («горит»); water puts the fire out and wets — a flask's hit and Create Water's rain; wet is weak to lightning; a puddle
## reacts whole — alchemist's fire or a Fire Bolt on one square of oil lights all of it, a Ray of Frost freezes all the water,
## a spark runs through it all; fire thaws the ice back into water where it falls; a spell of one target goes at a bare square.

var data: Dictionary
const BY := {"ability": "int", "attack": 50, "dc": 30}


func before_test() -> void:
	data = TestUtils.data()


func _goblin(s: GameSession) -> Dictionary:
	var g := ChecklistProbe.fight(s, data, "goblin", false)
	SpellEffects.zones(s).clear()
	g["hp"] = 200
	g["max_hp"] = 200
	return g


## `n` free squares in a row near the hero: walked, dry, nothing on them or beside them — a puddle of its own.
func _strip(s: GameSession, n: int) -> Array[Vector2i]:
	var g := FightGrid.grid(s, data)
	var taken := FightGrid.bodies(s)
	for y in range(33, 45):
		for x in range(42, 60):
			var row: Array[Vector2i] = []
			var ok := true
			for i in n:
				var at := Vector2i(x + i, y)
				for d: Vector2i in [Vector2i.ZERO] + WalkRules.DIRS:
					if FightField.douses_at(s, data, at + d):
						ok = false
				if not FightGrid.walkable(g, at) or taken.has(at):
					ok = false
				row.append(at)
			if ok and FightGrid.reaches(s, data, CombatRules.player(s), row[0]):
				return row
	return []


## A puddle of `lid` poured flask by flask on `cells`, each flask its own zone, as a player throws them.
func _puddle(s: GameSession, lid: String, cells: Array[Vector2i]) -> void:
	var lines: Array[String] = []
	for at: Vector2i in cells:
		FightField.splash(s, data, at, {"liquid": lid}, "лужа", lines)


func _under(s: GameSession, spell: String) -> Array:
	var out: Array = []
	for z: Dictionary in SpellEffects.zones(s):
		if str(z["spell"]) == spell:
			out.append_array(z["cells"])
	return out


func _all_in(cells: Array[Vector2i], keys: Array) -> bool:
	return cells.all(func(at: Vector2i) -> bool: return keys.has(FightGrid.tag(at)))


func _cast(s: GameSession, spell: String, slot: int, to: String) -> Array[String]:
	return ActionRules.cast(s, data, CombatRules.player(s), spell, slot, to, BY)


func test_one_oiled_burns_on_when_fire_takes_it() -> void:
	var s := ChecklistProbe.session(data)
	var g := _goblin(s)
	_puddle(s, "oil", [FightGrid.cell(g)] as Array[Vector2i])
	var lines: Array[String] = []
	FightField.stepped(s, data, g, lines)
	assert_str(str(LiquidRules.coat_on(s, g).get("liquid", ""))).is_equal("oil")
	Harm.typed(s, data, g, 3, "fire", lines, "огонь", false)
	assert_int(int(g["hp"])).override_failure_message(" · ".join(lines)).is_less_equal(200 - 3 - 5)
	assert_bool(ConditionRules.has(g, "burning")).override_failure_message(" · ".join(lines)).is_true()
	assert_bool(LiquidRules.coat_on(s, g).is_empty()).is_true()  # the oil burnt away into the flame
	var hp := int(g["hp"])
	Harm.each_turn(s, data, g, "start", lines)
	assert_int(int(g["hp"])).override_failure_message(" · ".join(lines)).is_less(hp)  # «горит» deals its 1d4 each turn


func test_one_wet_does_not_catch_from_the_oil() -> void:
	var s := ChecklistProbe.session(data)
	var g := _goblin(s)
	LiquidRules.coat(s, data, g, "oil", "масло", g)
	LiquidRules.soak(s, data, g, "вода")  # wet with the oil still on it: the oil flares, the wet one does not catch
	var lines: Array[String] = []
	Harm.typed(s, data, g, 3, "fire", lines, "огонь", false)
	assert_bool(ConditionRules.has(g, "burning")).override_failure_message(" · ".join(lines)).is_false()


func test_water_puts_out_one_burning_and_wets_it_a_flask_and_create_water() -> void:
	var s := ChecklistProbe.session(data)
	var g := _goblin(s)
	LiquidRules.coat(s, data, g, "alchemists_fire", "Алхимический огонь", g)
	assert_bool(ConditionRules.has(g, "burning")).is_true()
	LiquidRules.coat(s, data, g, LiquidRules.WATER, "вода", g)  # what a flask of water does to the one it hits
	assert_bool(ConditionRules.has(g, "burning")).is_false()
	assert_bool(ConditionRules.has(g, LiquidRules.WET)).is_true()
	var t := ChecklistProbe.session(data)
	var h := _goblin(t)
	LiquidRules.coat(t, data, h, "alchemists_fire", "Алхимический огонь", h)
	FightField._light(t, FightGrid.cell(h) + Vector2i(1, 0))
	FightField._sync_fire(t, data)
	var lines := _cast(t, "create_or_destroy_water", 1, FightGrid.aim_id(FightGrid.cell(h)))
	assert_bool(ConditionRules.has(h, "burning")).override_failure_message(" · ".join(lines)).is_false()
	assert_bool(ConditionRules.has(h, LiquidRules.WET)).override_failure_message(" · ".join(lines)).is_true()
	assert_bool((t.combat["fires"] as Dictionary).has(FightGrid.tag(FightGrid.cell(h) + Vector2i(1, 0)))).override_failure_message(" · ".join(lines)).is_false()
	assert_bool(FightField.douses_at(t, data, FightGrid.cell(h))).is_true()  # the rain left its water


func test_wet_is_weak_to_lightning_and_its_card_says_so() -> void:
	var s := ChecklistProbe.session(data)
	var g := _goblin(s)
	LiquidRules.soak(s, data, g, "вода")
	assert_int(Sheet.taken(s, data, g, "lightning", 8)).is_equal(16)
	var card := CreatureCard.defenses(s, data, g)
	assert_bool(card.any(func(d: Dictionary) -> bool: return str(d["kind"]) == "vulnerable" and str(d["what"]).contains("электричество"))) \
		.override_failure_message(str(card)).is_true()
	var st := ConditionRules.shown(s, data, g)
	assert_bool(st.any(func(x: Dictionary) -> bool: return str(x["condition"]) == LiquidRules.WET)).override_failure_message(str(st)).is_true()


func test_alchemists_fire_on_one_square_lights_the_whole_oil_puddle() -> void:
	var s := ChecklistProbe.session(data)
	_goblin(s)
	var oil := _strip(s, 4)
	assert_int(oil.size()).is_equal(4)
	_puddle(s, "oil", oil)
	var lines: Array[String] = []
	FightField.splash(s, data, oil[0], {"liquid": "alchemists_fire"}, "Алхимический огонь", lines)
	assert_bool(_all_in(oil, (s.combat["fires"] as Dictionary).keys())).override_failure_message(" · ".join(lines) + " " + str(s.combat["fires"])).is_true()
	assert_array(_under(s, "puddle:oil")).is_empty()


func test_a_fire_bolt_at_a_bare_square_of_oil_lights_the_whole_puddle() -> void:
	var s := ChecklistProbe.session(data)
	_goblin(s)
	var oil := _strip(s, 4)
	_puddle(s, "oil", oil)
	var p := CombatRules.player(s)
	assert_str(CombatRules._can_aim(s, data, "fire_bolt", oil[2], p)).is_empty()
	var lines := _cast(s, "fire_bolt", 0, FightGrid.aim_id(oil[2]))
	assert_bool(_all_in(oil, (s.combat["fires"] as Dictionary).keys())).override_failure_message(" · ".join(lines)).is_true()
	assert_bool(lines.any(func(l: String) -> bool: return l.contains("в клетку"))).override_failure_message(" · ".join(lines)).is_true()


func test_a_ray_of_frost_at_the_water_freezes_the_whole_puddle() -> void:
	var s := ChecklistProbe.session(data)
	_goblin(s)
	var water := _strip(s, 4)
	_puddle(s, LiquidRules.WATER, water)
	var lines := _cast(s, "ray_of_frost", 0, FightGrid.aim_id(water[3]))
	assert_bool(_all_in(water, _under(s, "ice"))).override_failure_message(" · ".join(lines) + " " + str(_under(s, "ice"))).is_true()


func test_fire_thaws_the_ice_back_into_water_where_it_falls() -> void:
	var s := ChecklistProbe.session(data)
	_goblin(s)
	var water := _strip(s, 4)
	_puddle(s, LiquidRules.WATER, water)
	var lines: Array[String] = []
	FightField.lands(s, data, "cold", [water[0]] as Array[Vector2i], {}, lines)
	assert_bool(_all_in(water, _under(s, "ice"))).is_true()
	lines.assign(_cast(s, "fire_bolt", 0, FightGrid.aim_id(water[3])))  # one square of it: that square thaws
	assert_bool(_under(s, "ice").has(FightGrid.tag(water[3]))).override_failure_message(" · ".join(lines)).is_false()
	assert_bool(_under(s, "ice").has(FightGrid.tag(water[0]))).is_true()
	lines.assign(_cast(s, "fireball", 3, FightGrid.aim_id(water[1])))  # the fireball's sphere: all of it
	assert_array(_under(s, "ice")).override_failure_message(" · ".join(lines)).is_empty()
	assert_bool(water.all(func(at: Vector2i) -> bool: return FightField.douses_at(s, data, at))).is_true()  # water again, not fire
	assert_bool(water.any(func(at: Vector2i) -> bool: return (s.combat["fires"] as Dictionary).has(FightGrid.tag(at)))).is_false()


func test_lightning_on_one_square_of_water_electrifies_the_whole_puddle() -> void:
	var s := ChecklistProbe.session(data)
	_goblin(s)
	var water := _strip(s, 4)
	_puddle(s, LiquidRules.WATER, water)
	var lines: Array[String] = []
	FightField.lands(s, data, "lightning", [water[1]] as Array[Vector2i], {}, lines)
	assert_bool(_all_in(water, _under(s, "electric_water"))).override_failure_message(" · ".join(lines)).is_true()


func test_a_bare_square_takes_only_a_damage_spell_of_one_target_in_range() -> void:
	var s := ChecklistProbe.session(data)
	_goblin(s)
	var p := CombatRules.player(s)
	var near := FightGrid.cell(p) + Vector2i(0, 3)
	assert_str(CombatRules._can_aim(s, data, "fire_bolt", near, p)).is_empty()
	assert_str(CombatRules._can_aim(s, data, "cure_wounds", near, p)).is_equal("COMBAT_BAD_TARGET")
	assert_str(CombatRules._can_aim(s, data, "bless", near, p)).is_equal("COMBAT_BAD_TARGET")
	assert_str(CombatRules._can_aim(s, data, "ray_of_frost", FightGrid.cell(p) + Vector2i(0, 14), p)).is_equal("COMBAT_OUT_OF_RANGE")


func test_a_spell_at_the_square_of_a_body_strikes_the_body() -> void:
	var s := ChecklistProbe.session(data)
	var g := _goblin(s)
	var lines := _cast(s, "fire_bolt", 0, FightGrid.aim_id(FightGrid.cell(g)))
	assert_bool(lines.any(func(l: String) -> bool: return l.contains("Огненный снаряд по " + str(g["name"])))).override_failure_message(" · ".join(lines)).is_true()
	assert_bool(lines.any(func(l: String) -> bool: return l.contains("в клетку"))).override_failure_message(" · ".join(lines)).is_false()
