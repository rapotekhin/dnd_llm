extends GdUnitTestSuite
## Statuses as in BG3 (v0.8.4.43.54, the author's ask of 2026-11-13): one status of damage each turn from any source with its
## own numbers. The fire of a square no longer hurts by itself: it lays «горит» for a turn, renewed while one stands in it, and
## the status burns at the start of the turn. A flask of alchemist's fire sets one alight until put out — its save, the act
## «Потушить», water. One status from two sources is weighed by its row, not doubled; a row weakens (a save, the speed); a made
## status has the part `harm`; the console lays any of them with its own dice.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _goblin(s: GameSession) -> Dictionary:
	var g := ChecklistProbe.fight(s, data, "goblin", true)
	SpellEffects.zones(s).clear()
	g["hp"] = 200
	g["max_hp"] = 200
	return g


## A square on fire, whatever lies on it (the fire's own zone of the field).
func _alight(s: GameSession, at: Vector2i) -> void:
	FightField._light(s, at)
	FightField._sync_fire(s, data)


func test_the_fire_of_a_square_burns_through_the_status() -> void:
	var s := ChecklistProbe.session(data)
	var g := _goblin(s)
	var lines: Array[String] = []
	_alight(s, FightGrid.cell(g))
	lines.append_array(SpellEffects.zone_tick(s, data, g, "enter"))
	assert_int(int(g["hp"])).override_failure_message(" · ".join(lines)).is_equal(200)  # the square does not hurt by itself
	assert_bool(ConditionRules.has(g, "burning")).is_true()
	var e: Dictionary = ConditionRules.effects_of(g, "burning")[0]
	assert_int(int(e["ticks"])).is_equal(1)
	Harm.each_turn(s, data, g, "start", lines)
	assert_int(int(g["hp"])).override_failure_message(" · ".join(lines)).is_equal(195)  # the fire's own 5
	assert_bool(ConditionRules.has(g, "burning")).is_false()  # one turn, then gone
	lines.append_array(SpellEffects.zone_tick(s, data, g, "start"))  # still standing in it: alight again
	assert_bool(ConditionRules.has(g, "burning")).is_true()


func test_alchemists_fire_burns_until_put_out_by_the_act() -> void:
	var s := ChecklistProbe.session(data)
	var g := _goblin(s)
	LiquidRules.coat(s, data, g, "alchemists_fire", "Алхимический огонь", g)
	var e: Dictionary = ConditionRules.effects_of(g, "burning")[0]
	assert_str(str(e["harm"]["dice"])).is_equal("1d4")
	assert_bool(bool(e["save"]["repeat"])).is_true()
	assert_bool(e.has("ticks")).is_false()  # until put out
	assert_bool(LiquidRules.coat_on(s, g).has("burns")).is_false()  # the fire is the status, not the coat
	var lines: Array[String] = []
	Harm.each_turn(s, data, g, "start", lines)
	Harm.each_turn(s, data, g, "start", lines)
	assert_bool(ConditionRules.has(g, "burning")).is_true()
	assert_int(int(g["hp"])).is_less(200)
	var act := Acts.one("put_out")
	assert_bool(act.shown(s, data, g)).is_true()
	var tries := 0
	while ConditionRules.has(g, "burning") and tries < 12:  # a DEX check against DC 10, as a player tries again
		tries += 1
		ChecklistProbe.turn(s, data, g)
		assert_str(act.can(s, data, g)).is_empty()
		lines.append_array(act.go(s, data, g))
	assert_bool(ConditionRules.has(g, "burning")).override_failure_message(" · ".join(lines)).is_false()
	assert_bool(lines.any(func(l: String) -> bool: return l.contains("сбивает пламя"))).is_true()
	assert_bool(act.shown(s, data, g)).is_false()


func test_water_puts_out_a_creature_s_fire() -> void:
	var s := ChecklistProbe.session(data)
	var g := _goblin(s)
	LiquidRules.coat(s, data, g, "alchemists_fire", "Алхимический огонь", g)
	var lines := LiquidRules.coat(s, data, g, LiquidRules.WATER, "вода", g)
	assert_bool(ConditionRules.has(g, "burning")).is_false()
	assert_bool(lines.any(func(l: String) -> bool: return l.contains("пламя погасло"))).is_true()


func test_one_burning_from_two_sources_is_not_doubled() -> void:
	var s := ChecklistProbe.session(data)
	var g := _goblin(s)
	LiquidRules.coat(s, data, g, "alchemists_fire", "Алхимический огонь", g)
	var lines: Array[String] = []
	_alight(s, FightGrid.cell(g))
	SpellEffects.zone_tick(s, data, g, "enter")
	var all := ConditionRules.effects_of(g, "burning")
	assert_int(all.size()).is_equal(1)
	assert_str(str(all[0]["harm"]["dice"])).is_equal("5")  # the stronger fire
	assert_bool(all[0].has("save")).is_true()  # and the longer one: until put out, not one turn
	assert_bool(all[0].has("ticks")).is_false()
	Harm.each_turn(s, data, g, "start", lines)
	assert_int(int(g["hp"])).override_failure_message(" · ".join(lines)).is_equal(195)  # once, not twice


func test_a_row_weakens_and_runs_out_by_its_turns() -> void:
	var s := ChecklistProbe.session(data)
	var g := _goblin(s)
	ConditionRules.impose(s, data, {"condition": "bleeding", "ends": {}, "source": {"kind": "engine", "name": "тест"}}, g)
	var e: Dictionary = ConditionRules.effects_of(g, "bleeding")[0]
	assert_array(e["save_dis"]).contains_exactly(["con"])
	assert_int(int(e["ticks"])).is_equal(2)
	ConditionRules.impose(s, data, {"condition": "frostbitten", "ends": {}, "source": {"kind": "engine", "name": "тест"}}, g)
	assert_int(int(ConditionRules.effects_of(g, "frostbitten")[0]["speed_plus"])).is_equal(-10)
	var lines: Array[String] = []
	Harm.each_turn(s, data, g, "start", lines)
	Harm.each_turn(s, data, g, "start", lines)
	assert_bool(ConditionRules.has(g, "bleeding")).is_false()
	assert_bool(ConditionRules.has(g, "frostbitten")).is_false()
	assert_int(lines.filter(func(l: String) -> bool: return l.contains("кровотечение")).size()).is_equal(2)


func test_the_hero_burns_by_the_same_road() -> void:
	var s := ChecklistProbe.session(data)
	_goblin(s)
	var p := CombatRules.player(s)
	s.character["hp"] = 60
	LiquidRules.coat(s, data, s.character, "alchemists_fire", "Алхимический огонь", p)
	assert_bool(ConditionRules.has(s.character, "burning")).is_true()
	var lines: Array[String] = []
	Harm.each_turn(s, data, p, "start", lines)
	assert_int(int(s.character["hp"])).override_failure_message(" · ".join(lines)).is_less(60)


func test_a_made_status_hurts_each_turn() -> void:
	var s := ChecklistProbe.session(data)
	var g := _goblin(s)
	s.character["level"] = 20
	var p := MakeRules.plan(s, data, {"kind": "make", "what": "status", "key": "brand", "name": "Жгучее клеймо", "text": "Клеймо жжёт огнём.",
		"parts": [{"part": "harm", "value": "fire", "amount": 2}]})
	assert_bool(p.has("plan")).override_failure_message(str(p)).is_true()
	MakeRules.apply(s, data, p["plan"])
	var id := str(p["plan"]["id"])
	ConditionRules.impose(s, data, {"condition": id, "ends": {}, "source": {"kind": "master", "name": "мастер"}}, g)
	assert_str(str(ConditionRules.harm_of(data, ConditionRules.effects_of(g, id)[0]).get("dice", ""))).is_equal("2d6")
	var lines: Array[String] = []
	Harm.each_turn(s, data, g, "start", lines)
	assert_int(int(g["hp"])).override_failure_message(" · ".join(lines)).is_less(200)


func test_the_console_lays_burning_with_its_dice() -> void:
	var s := ChecklistProbe.session(data)
	_goblin(s)
	var lines := Cheats.condition(s, data, Being.HERO, "burning", true, "2d6")
	assert_str(str(ConditionRules.effects_of(s.character, "burning")[0]["harm"]["dice"])).is_equal("2d6")
	assert_bool(lines[0].contains("2к6")).override_failure_message(" · ".join(lines)).is_true()
	assert_bool(Cheats.conditions(data).has("burning")).is_true()  # a creature's status now, not a thing's alone
