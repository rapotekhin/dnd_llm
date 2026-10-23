extends GdUnitTestSuite
## Combat animations (roadmap v0.7.22.14): the engine notes what HP does not tell — a dodge, a crit, a spell; the
## screen takes the notes once. CombatFx itself only plays them.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _fight(s: GameSession) -> Dictionary:
	CombatRules.start(s, data, [{"monster": "goblin", "col": 0}], {})
	var order: Array = s.combat["order"]
	order.erase(CombatRules.PLAYER)
	order.push_front(CombatRules.PLAYER)
	s.combat["turn"] = 0
	CombatRules._begin_turn(s, data, [] as Array[String])
	return CombatRules.fighter(s, CombatRules.enemies(s)[0])


func test_a_miss_is_a_dodge_and_a_crit_is_noted() -> void:
	var s := TestUtils.new_session()
	var f := _fight(s)
	f["ac"] = 99
	var lines: Array[String] = []
	CombatRules._attack(s, data, "Герой", "Меч", 0, false, false, f, "1d8", 0, "slashing", lines)
	var fx := CombatRules.take_fx(s)
	assert_bool(fx.any(func(e: Dictionary) -> bool: return e["who"] == str(f["id"]) and e["kind"] == "dodge")).is_true()
	assert_array(CombatRules.take_fx(s)).is_empty()  # taken once
	f["ac"] = 0
	f["hp"] = 999
	f["max_hp"] = 999
	CombatRules._attack(s, data, "Герой", "Меч", 0, false, false, f, "1d8", 0, "slashing", lines, "", true)
	assert_bool(CombatRules.take_fx(s).any(func(e: Dictionary) -> bool: return e["kind"] == "crit")).is_true()


func test_play_ignores_a_missing_node() -> void:
	CombatFx.play(null, "hit")  # nothing to animate — no error
	CombatFx.look(null, "hidden")
