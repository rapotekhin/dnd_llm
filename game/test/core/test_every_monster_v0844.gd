extends GdUnitTestSuite
## Every creature of the base in the engine (v0.8.4.4): it comes to a fight with its numbers, its resistances and
## immunities work on damage, every action of it goes through a turn of the AI. The data against the SRD is
## tools/test_srd_monsters.py.

const PHYSICAL: Array[String] = ["bludgeoning", "piercing", "slashing"]

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _types(text: String) -> Array[String]:
	var out: Array[String] = []
	for t: String in data["misc"]["damage_types"]:
		if text.to_lower().contains(t):
			out.append(t)
	return out


func _fight(s: GameSession, id: String) -> Dictionary:
	s.character["max_hp"] = 5000
	s.character["hp"] = 5000
	TestUtils.fight(s, data, [{"monster": id, "col": 1}])
	return CombatRules.fighter(s, CombatRules.enemies(s)[0])


func test_every_monster_comes_with_its_numbers() -> void:
	for id: String in data["monsters"]:
		var m: Dictionary = data["monsters"][id]
		var s := TestUtils.new_session()
		var f := _fight(s, id)
		assert_int(int(f["hp"])).override_failure_message(id).is_equal(int(m["hp"]))
		assert_int(int(f["ac"])).override_failure_message(id).is_equal(int(m["ac"]))
		assert_int(int(f["span"])).override_failure_message(id).is_equal(FightGrid.span_of(data, str(m["size"])))
		CombatRules.close(s)


func test_every_resistance_immunity_and_vulnerability_works() -> void:
	for id: String in data["monsters"]:
		var m: Dictionary = data["monsters"][id]
		var f := {"monster": id, "conditions": []}
		var all_lists: Array = m["resistances"] + m["immunities"] + m["vulnerabilities"]
		for text: Variant in m["resistances"]:
			for t: String in _types(str(text)):
				if not (m["immunities"] as Array).any(func(x: Variant) -> bool: return str(x).contains(t) and not str(x).contains("nonmagical")):
					assert_int(CombatRules._resist(data, f, t, 10, false)).override_failure_message("%s: %s" % [id, t]).is_equal(5)
		for text: Variant in m["immunities"]:
			for t: String in _types(str(text)):
				assert_int(CombatRules._resist(data, f, t, 10, false)).override_failure_message("%s: %s" % [id, t]).is_equal(0)
		for text: Variant in m["vulnerabilities"]:
			for t: String in _types(str(text)):
				assert_int(CombatRules._resist(data, f, t, 10, false)).override_failure_message("%s: %s" % [id, t]).is_equal(20)
		for t: String in data["misc"]["damage_types"]:
			if not all_lists.any(func(x: Variant) -> bool: return str(x).contains(t)):
				assert_int(CombatRules._resist(data, f, t, 10, false)).override_failure_message("%s: %s" % [id, t]).is_equal(10)
			if PHYSICAL.has(t) and all_lists.all(func(x: Variant) -> bool: return not str(x).contains(t) or str(x).contains("nonmagical")):
				assert_int(CombatRules._resist(data, f, t, 10, true)).override_failure_message("%s: %s magic" % [id, t]).is_equal(10)


func test_every_condition_immunity_works() -> void:
	for id: String in data["monsters"]:
		var f := {"monster": id}
		for cond: Variant in data["monsters"][id]["condition_immunities"]:
			assert_bool(CombatRules.immune_to(data, f, str(cond))).override_failure_message("%s: %s" % [id, cond]).is_true()
			assert_bool(ConditionRules.name_of(data, str(cond)).is_empty()).override_failure_message("%s: %s" % [id, cond]).is_false()


func test_every_action_of_every_monster_goes_through_a_turn() -> void:
	var silent: Array[String] = []
	for id: String in data["monsters"]:
		var m: Dictionary = data["monsters"][id]
		for a: Dictionary in m["actions"]:
			var s := TestUtils.new_session()
			var f := _fight(s, id)
			f["actions"] = [a]
			FightGrid.put(f, FightGrid.free_near(s, data, FightGrid.cell(CombatRules.player(s)), int(f["span"])))
			s.combat["order"] = [str(f["id"]), CombatRules.PLAYER]
			s.combat["turn"] = 0
			var lines := CombatRules.next_actor(s, data)
			assert_int(int(s.character["hp"])).override_failure_message("%s: %s" % [id, a["name"]]).is_less_equal(5000)
			if lines.is_empty():
				silent.append("%s: %s" % [id, a["name"]])
			CombatRules.close(s)
	assert_array(silent).is_empty()


func test_every_multiattack_is_struck_in_a_turn() -> void:
	for id: String in data["monsters"]:
		var m: Dictionary = data["monsters"][id]
		if (m["multiattack"] as Array).is_empty():
			continue
		var s := TestUtils.new_session()
		var f := _fight(s, id)
		FightGrid.put(f, FightGrid.free_near(s, data, FightGrid.cell(CombatRules.player(s)), int(f["span"])))
		s.combat["order"] = [str(f["id"]), CombatRules.PLAYER]
		s.combat["turn"] = 0
		assert_array(CombatRules.next_actor(s, data)).override_failure_message(id).is_not_empty()
		CombatRules.close(s)
