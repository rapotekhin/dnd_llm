extends GdUnitTestSuite
## A liquid the master makes (roadmap v0.8.4.28.5, the author's three): a row of rules.liquids.kinds and its ready thing in
## its vessel, of the parts of rules.make.liquid, priced by the engine. Whisky is drunk and makes one drunk; drow poison
## coats a blade and puts the struck one to sleep as the spell does — until it is hurt; Malice is thrown at a square: its
## area (1×1 by default), a CON save DC 15, poisoned for an hour and blinded while poisoned. Its effect on a blade and in
## a throw is a monster's attack's (MonsterRules.apply_effect).

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _hero(level := 5) -> GameSession:
	var s := ChecklistProbe.session(data)
	s.character["level"] = level
	MakeRules.install(data, s.generated)
	return s


func _make(s: GameSession, key: String, name: String, parts: Array) -> String:
	var p := MakeRules.plan(s, data, {"kind": "make", "what": "liquid", "key": key, "name": name, "text": "Сделано мастером.", "parts": parts})
	assert_bool(p.has("plan")).override_failure_message(str(p)).is_true()
	MakeRules.apply(s, data, p["plan"])
	return str(p["plan"]["id"])


func _whisky(s: GameSession) -> String:
	return _make(s, "whisky", "Виски", [{"part": "drunk", "amount": 6}])


func _drow(s: GameSession) -> String:
	return _make(s, "drow", "Яд дроу", [{"part": "blade"}, {"part": "lay", "value": "unconscious"}, {"part": "lasts", "value": "minute"},
		{"part": "wake"}, {"part": "save", "value": "con", "amount": 13}])


func _malice(s: GameSession, area := 0) -> String:
	var parts: Array = [{"part": "throw"}, {"part": "lay", "value": "poisoned"}, {"part": "also", "value": "blinded"},
		{"part": "lasts", "value": "hour"}, {"part": "save", "value": "con", "amount": 15}]
	if area > 0:
		parts.append({"part": "area", "amount": area})
	return _make(s, "malice%d" % area, "Злоба", parts)


func test_whisky_is_a_new_liquid_in_its_bottle_and_is_drunk() -> void:
	var s := _hero()
	var id := _whisky(s)
	assert_bool(LiquidRules.cfg(data)["kinds"].has(id)).is_true()
	assert_str(LiquidRules.name_of(data, id)).is_equal("Виски")
	assert_str(str(LiquidRules.ready(data, id)["vessel"])).is_equal("bottle_glass")
	s.character["inventory"][id] = 1
	var bottle := LiquidRules.first(s.character, data, id)
	assert_str(str(bottle["liquid"])).is_equal(id)
	assert_str(LiquidRules.drink_why(data, bottle)).is_empty()
	var lines := LiquidRules.drink(s, data, Sheet.HERO, bottle)
	assert_bool(ConditionRules.has(s.character, str(LiquidRules.cfg(data)["drunk"]["condition"]))).override_failure_message(" · ".join(lines)).is_true()


func test_a_made_liquid_comes_back_with_its_game() -> void:
	var s := _hero()
	var id := _whisky(s)
	var fresh := TestUtils.data()
	assert_bool(LiquidRules.cfg(fresh)["kinds"].has(id)).is_false()
	MakeRules.install(fresh, s.generated)
	assert_str(LiquidRules.name_of(fresh, id)).is_equal("Виски")
	assert_bool(fresh["items"]["catalog"].has(id)).is_true()


func test_drow_poison_on_a_blade_puts_the_struck_to_sleep_until_hurt() -> void:
	var s := _hero()
	var id := _drow(s)
	var kind: Dictionary = LiquidRules.cfg(data)["kinds"][id]
	assert_str(str(kind["blade"]["effect"]["condition"])).is_equal("unconscious")
	assert_int(int(kind["blade"]["effect"]["save"]["dc"])).is_equal(13)
	assert_str(str(kind["vessel"])).is_equal("vial")
	var c := s.character
	c["inventory"]["shortsword"] = 1
	c["equipped"]["main_hand"] = "shortsword"
	CharacterRules.refresh(c, data, s.items)
	var goblin := ChecklistProbe.fight(s, data, "goblin")
	goblin["ac"] = 1
	var hero := CombatRules.player(s)
	var lines: Array[String] = []
	for i in 20:
		c["inventory"][id] = 1
		ItemRules.belt_put(c, data, s.items, id)
		ItemRules.use(c, data, s.items, id, s.rng, s)
		assert_int(int(c["inventory"].get("vial", 0))).is_equal(i + 1)  # its vial is left, empty
		ChecklistProbe.turn(s, data, hero)
		lines.append_array(Acts.one("attack").go(s, data, hero, str(goblin["id"])))
		if ConditionRules.has(goblin, "unconscious"):
			break
	assert_bool(ConditionRules.has(goblin, "unconscious")).override_failure_message(" · ".join(lines)).is_true()
	Harm.take(s, data, goblin, 1, lines, "slashing")
	assert_bool(ConditionRules.has(goblin, "unconscious")).is_false()


func test_malice_thrown_at_a_square_poisons_and_blinds_only_its_area() -> void:
	var s := _hero()
	var id := _malice(s)
	assert_int(int(LiquidRules.cfg(data)["kinds"][id]["throw"]["area"])).is_equal(1)
	CombatRules.start(s, data, [{"monster": "goblin", "x": 43, "y": 30}, {"monster": "goblin", "x": 44, "y": 30}], {"field": {"w": 80, "h": 60}})
	var hero := CombatRules.player(s)
	FightGrid.put(hero, Vector2i(40, 30))
	var foes := CombatRules.enemies(s).map(func(x: String) -> Dictionary: return CombatRules.fighter(s, x))
	var near: Dictionary = foes.filter(func(f: Dictionary) -> bool: return FightGrid.cell(f) == Vector2i(43, 30))[0]
	var far: Dictionary = foes.filter(func(f: Dictionary) -> bool: return FightGrid.cell(f) == Vector2i(44, 30))[0]
	var lines: Array[String] = []
	for i in 20:
		s.character["inventory"][id] = 1
		ItemRules.belt_put(s.character, data, s.items, id)
		ChecklistProbe.turn(s, data, hero)
		FightGrid.put(hero, Vector2i(40, 30))  # the foes' turns move them: back where they were
		FightGrid.put(near, Vector2i(43, 30))
		FightGrid.put(far, Vector2i(44, 30))
		var aim := FightGrid.aim_id(Vector2i(43, 30))
		assert_str(Acts.one("throw").why(s, data, hero, aim, {"item": id})).is_empty()
		lines.append_array(Acts.one("throw").go(s, data, hero, aim, {"item": id}))
		if ConditionRules.has(near, "poisoned"):
			break
	assert_bool(ConditionRules.has(near, "poisoned")).override_failure_message(" · ".join(lines)).is_true()
	assert_bool(ConditionRules.has(near, "blinded")).is_true()
	assert_str(" · ".join(lines)).contains("Сл 15")
	assert_bool(ConditionRules.has(far, "poisoned") or ConditionRules.has(far, "blinded")).is_false()
	ConditionRules.remove(near, "poisoned")
	assert_bool(ConditionRules.has(near, "blinded")).is_false()  # blinded while poisoned


func test_a_wider_malice_reaches_the_one_beside() -> void:
	var s := _hero()
	var id := _malice(s, 3)
	CombatRules.start(s, data, [{"monster": "goblin", "x": 43, "y": 30}, {"monster": "goblin", "x": 44, "y": 30}], {"field": {"w": 80, "h": 60}})
	var hero := CombatRules.player(s)
	FightGrid.put(hero, Vector2i(40, 30))
	var lines: Array[String] = []
	s.character["inventory"][id] = 1
	ItemRules.belt_put(s.character, data, s.items, id)
	lines.append_array(Acts.one("throw").go(s, data, hero, FightGrid.aim_id(Vector2i(43, 30)), {"item": id}))
	assert_int(" · ".join(lines).count("спасбросок")).is_equal(2)


func test_what_the_parts_do_not_cover_is_refused() -> void:
	var s := _hero()
	var bad := func(parts: Array) -> String:
		return str(MakeRules.plan(s, data, {"kind": "make", "what": "liquid", "key": "x", "name": "Что-то", "text": "Сделано мастером.", "parts": parts}).get("reason", ""))
	assert_str(bad.call([{"part": "lay", "value": "poisoned"}])).contains("пользуются")
	assert_str(bad.call([{"part": "blade"}])).contains("без действия")
	assert_str(bad.call([{"part": "blade"}, {"part": "throw"}, {"part": "lay", "value": "poisoned"}])).contains("либо")
	assert_str(bad.call([{"part": "drunk", "amount": 2}, {"part": "area", "amount": 2}])).contains("броска")
	var low := _hero(1)
	var strong := MakeRules.plan(low, data, {"kind": "make", "what": "liquid", "key": "m", "name": "Злоба", "text": "Сделано мастером.",
		"parts": [{"part": "throw"}, {"part": "lay", "value": "poisoned"}, {"part": "also", "value": "blinded"}, {"part": "lasts", "value": "hour"},
		{"part": "save", "value": "con", "amount": 15}]})
	assert_str(str(strong.get("reason", ""))).contains("уровня героя")
