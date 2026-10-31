extends GdUnitTestSuite
## 31 kinds of effects (v0.7.69): one name for each, one row in the engine's table.

var data: Dictionary
var s: GameSession
var fx: EffectEngine


func before_test() -> void:
	data = TestUtils.data()
	s = TestUtils.new_session()
	fx = EffectEngine.new()


func test_the_name_of_an_effect() -> void:
	assert_str(EffectEngine.key({"kind": "create", "what": "npc"})).is_equal("create:npc")
	assert_str(EffectEngine.key({"kind": "move_item", "source": "hero", "target": "room"})).is_equal("move_item:hero>room")
	assert_str(EffectEngine.key({"kind": "coins", "delta_cp": 5})).is_equal("coins")
	assert_str(EffectEngine.key({"kind": "make", "what": "status"})).is_equal("make")


func test_every_row_plans_and_applies() -> void:
	var table := fx._table()
	assert_bool(table.is_empty()).is_false()
	for id: String in table:
		var row: Dictionary = table[id]
		assert_bool(row.has("rule") != row.has("plan")).override_failure_message("%s: rule or plan" % id).is_true()
		assert_bool(row.has("apply") != row.has("do")).override_failure_message("%s: apply or do" % id).is_true()
		for k: String in ["rule", "plan", "apply", "do"]:
			if row.has(k):
				assert_bool((row[k] as Callable).is_valid()).override_failure_message("%s.%s" % [id, k]).is_true()


func test_an_unknown_pair_and_an_unknown_member_are_refused() -> void:
	var r := fx.validate(s, data, "t-1", {"kind": "move_item", "source": "npc", "target": "hero", "npc_id": "npc_innkeeper", "item_id": "dagger"})
	assert_bool(bool(r["accepted"])).is_false()
	assert_str(str(r["reason"])).contains("move_item:npc>hero")
	r = fx.validate(s, data, "t-1", {"kind": "create", "what": "castle"})
	assert_bool(bool(r["accepted"])).is_false()
	assert_str(str(r["reason"])).contains("create:castle")


func test_a_row_refuses_a_second_one_in_a_turn() -> void:
	var first := fx.validate(s, data, "t-1", {"kind": "goal", "what": "hint", "text": "x"})
	var pending: Array[Dictionary] = [{"kind": "create:npc"}]
	var second := fx._plan(s, data, "t-1", {"kind": "create", "what": "npc", "npc": {}}, pending)
	assert_str(str(second.get("reason", ""))).is_equal("один новый человек за ход")
	assert_bool(first.has("accepted")).is_true()


func test_a_thing_moves_by_one_effect_from_and_to() -> void:
	var r := fx.validate(s, data, "t-1", {"kind": "move_item", "source": "world", "target": "npc", "npc_id": "npc_innkeeper", "item_id": "dagger", "qty": 1, "cause": "купил у лудильщика"})
	assert_bool(bool(r["accepted"])).override_failure_message(str(r)).is_true()
	fx.apply(s, "t-1", [r["effect_id"]])
	r = fx.validate(s, data, "t-2", {"kind": "move_item", "source": "npc", "target": "world", "npc_id": "npc_innkeeper", "item_id": "dagger", "qty": 1, "cause": "потерял на ярмарке"})
	assert_bool(bool(r["accepted"])).override_failure_message(str(r)).is_true()
	fx.apply(s, "t-2", [r["effect_id"]])
	var before := s.character.duplicate(true)
	r = fx.validate(s, data, "t-3", {"kind": "move_item", "source": "world", "target": "hero", "item_id": "dagger", "qty": 1})
	assert_bool(bool(r["accepted"])).override_failure_message(str(r)).is_true()
	fx.apply(s, "t-3", [r["effect_id"]])
	assert_bool(s.character.hash() == before.hash()).is_false()
