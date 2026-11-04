extends GdUnitTestSuite
## Webs on the engine's roads (roadmap v0.8.4.27.3): the Web spell and a spider's lair are one zone of the field — slow, a
## Dexterity save on entering or starting a turn, restrained until broken by Strength against its DC, and it burns. Web
## Walker is not held or slowed by it, Web Sense finds one who hides in it. Entangle is the same kind of zone; a net holds
## until broken too.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _web(s: GameSession, cells: Array[Vector2i], side := "enemy") -> Dictionary:
	var z := FightField.zone_of("web", (FightField.cfg(data)["strewn"]["web"] as Dictionary).merged({"side": side}), FightGrid.pack_cells(cells))
	SpellEffects.add_zone(s, z)
	return z


func _cast(s: GameSession, id: String, target: String) -> Array[String]:
	var c := s.character
	c["spells"]["always"] = (c["spells"].get("always", []) as Array) + [id]
	c["slots_max"] = [4, 3, 3, 0, 0]
	Stock.fill_slots(c)
	CombatRules.economy(s)["action"] = 1
	return Acts.one("cast").go(s, data, CombatRules.player(s), target, {"spell": id, "slot": 2})


func test_the_web_spell_holds_until_broken_and_lets_go_with_its_end() -> void:
	var s := ChecklistProbe.session(data, 3)
	var f := ChecklistProbe.fight(s, data, "goblin", true)
	ChecklistProbe.turn(s, data, CombatRules.player(s))
	s.character["spell_dc"] = 40
	var lines := _cast(s, "web", str(f["id"]))
	assert_bool(ConditionRules.has(f, "restrained")).override_failure_message(" · ".join(lines)).is_true()
	var held: Dictionary = ConditionRules.effects_of(f, "restrained")[0]
	assert_int(int(held["escape_dc"])).is_equal(40)
	assert_array(held["escape"]).contains_exactly(["athletics"])
	assert_bool(TestUtils.slowed(s, f)).is_true()
	assert_bool(Acts.one("escape").shown(s, data, f)).is_true()
	SpellEffects.end_zones(s, "web")
	assert_bool(ConditionRules.has(f, "restrained")).is_false()


func test_a_web_walker_is_neither_held_nor_slowed() -> void:
	var s := ChecklistProbe.session(data)
	var f := ChecklistProbe.fight(s, data, "giant_spider", true)
	var g := ChecklistProbe.fight(s, data, "goblin", true)
	SpellEffects.zones(s).clear()
	FightGrid.put(g, FightGrid.cell(f) + Vector2i(0, 2))
	_web(s, [FightGrid.cell(f), FightGrid.cell(g)] as Array[Vector2i])
	SpellEffects.zones(s)[-1]["dc"] = 40
	SpellEffects.zone_tick(s, data, f, "start")
	SpellEffects.zone_tick(s, data, g, "start")
	assert_bool(ConditionRules.has(f, "restrained")).is_false()
	assert_bool(TestUtils.slowed(s, f)).is_false()
	assert_bool(ConditionRules.has(g, "restrained")).is_true()
	assert_bool(TestUtils.slowed(s, g)).is_true()


func test_a_spider_comes_into_the_fight_among_its_webs() -> void:
	data["monsters"]["phase_spider"] = TestUtils.uncut("monsters", "phase_spider")  # out of the game (v0.8.4.28.4); its road stays
	var s := ChecklistProbe.session(data)
	var f := ChecklistProbe.fight(s, data, "giant_wolf_spider", true)
	var webs := SpellEffects.zones(s).filter(func(z: Dictionary) -> bool: return str(z["spell"]) == "web")
	assert_int(webs.size()).is_equal(1)
	var cells := FightGrid.zone_cells(s, data, webs[0])
	assert_bool(FightGrid.in_cells(f, cells)).is_true()
	assert_int(cells.size()).is_greater(1)
	assert_bool(cells.all(func(at: Vector2i) -> bool: return WalkRules.distance(at, FightGrid.cell(f)) <= 3)).is_true()
	var phase := ChecklistProbe.session(data)
	ChecklistProbe.fight(phase, data, "phase_spider", true)  # a web walker without Web Sense keeps no lair
	assert_bool(SpellEffects.zones(phase).any(func(z: Dictionary) -> bool: return str(z["spell"]) == "web")).is_false()


func test_web_sense_finds_one_who_hides_in_the_web() -> void:
	var s := ChecklistProbe.session(data)
	var f := ChecklistProbe.fight(s, data, "giant_spider", true)
	SpellEffects.zones(s).clear()
	var p := CombatRules.player(s)
	FightGrid.put(p, FightGrid.cell(f) + Vector2i(-4, 0))
	p["hidden"] = true
	var line: Array[Vector2i] = []
	for x: int in range(-4, 1):
		line.append(FightGrid.cell(f) + Vector2i(x, 0))
	_web(s, line)
	assert_bool(FightField.feels(s, data, f, p)).is_true()
	var lines: Array[String] = []
	CombatRules._find_hidden(s, data, f, lines)
	assert_bool(bool(p.get("hidden", false))).is_false()
	var goblin := ChecklistProbe.fight(s, data, "goblin", true)  # no Web Sense: it does not feel the web
	FightGrid.put(goblin, FightGrid.cell(f) + Vector2i(0, 1))
	assert_bool(FightField.feels(s, data, goblin, p)).is_false()


func test_fire_takes_the_web() -> void:
	var s := ChecklistProbe.session(data)
	ChecklistProbe.fight(s, data, "goblin", true)
	SpellEffects.zones(s).clear()
	var at := FightGrid.cell(CombatRules.player(s)) + Vector2i(2, 2)
	var z := _web(s, [at, at + Vector2i(1, 0)] as Array[Vector2i])
	var lines: Array[String] = []
	FightField.kindle(s, data, [at] as Array[Vector2i], lines)
	assert_bool((s.combat["fires"] as Dictionary).has(FightGrid.tag(at))).is_true()
	assert_array(z["cells"]).contains_exactly([FightGrid.tag(at + Vector2i(1, 0))])


func test_entangle_holds_only_as_it_grows() -> void:
	var sus := SpellEffects.sustained(data, "entangle")
	assert_array(sus["on"]).contains_exactly(["now"])
	assert_str(str(sus["save"])).is_equal("str")
	assert_bool(CombatRules.hostile_spell(data, "web")).is_true()
	assert_bool((CombatRules.cfg(data)["condition_spells"] as Dictionary).has("web")).is_false()


func test_a_net_holds_until_broken() -> void:
	var s := ChecklistProbe.session(data)
	var f := ChecklistProbe.fight(s, data, "goblin")
	CombatRules._add_condition(s, data, f, "restrained", {"escape_dc": 10, "escape": ["athletics"], "item": "net"})
	var held: Dictionary = ConditionRules.effects_of(f, "restrained")[0]
	assert_int(int(held["escape_dc"])).is_equal(10)
	assert_bool(held.has("save")).is_false()
	assert_bool(Acts.one("escape").shown(s, data, f)).is_true()


func test_a_walk_stops_in_the_web_and_a_turn_begins_held() -> void:
	var s := ChecklistProbe.session(data)
	var g := ChecklistProbe.fight(s, data, "goblin", true)
	SpellEffects.zones(s).clear()
	var from := FightGrid.cell(g)
	var wall: Array[Vector2i] = []
	for y: int in range(-6, 7):
		wall.append(from + Vector2i(2, y))
	_web(s, wall, "player")  # the hero's web: the goblin is not spared as a friend
	SpellEffects.zones(s)[-1]["dc"] = 40
	ChecklistProbe.turn(s, data, g)
	var lines: Array[String] = []
	Move.go(s, data, g, from + Vector2i(4, 0), lines)
	assert_bool(ConditionRules.has(g, "restrained")).override_failure_message(" · ".join(lines)).is_true()
	assert_int(int(CombatRules.points(s, data, g)["move"])).is_equal(0)
	var p := CombatRules.player(s)
	FightGrid.put(p, from + Vector2i(2, 1))
	_web(s, [from + Vector2i(2, 1)] as Array[Vector2i])
	SpellEffects.zones(s)[-1]["dc"] = 40
	s.combat["turn"] = (s.combat["order"] as Array).find(CombatRules.PLAYER)
	CombatRules._begin_turn(s, data, lines)
	assert_bool(ConditionRules.has(s.character, "restrained")).is_true()
	assert_int(int(CombatRules.points(s, data, p)["move"])).is_equal(0)
