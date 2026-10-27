extends GdUnitTestSuite
## A parcel of a made quest (v0.7.34.5, the wedge of the author's trace 2026-10-27): the giver hands the thing over on
## taking, a step gives it to a person or leaves it at a place; an errand without the thing is not made.

var data: Dictionary
var s: GameSession
var fx: EffectEngine


func before_test() -> void:
	data = TestUtils.data().duplicate(true)
	s = TestUtils.new_session()
	s.room_id = "brod-tavern-hall"
	fx = EffectEngine.new()


func _make(spec: Dictionary, turn := "t-1") -> Dictionary:
	fx.searched_quests[turn] = true
	var e := spec.duplicate(true)
	e["kind"] = "create_quest"
	var r := fx.validate(s, data, turn, e)
	if bool(r["accepted"]):
		fx.apply(s, turn, [r["effect_id"]])
	return r


func _wedge(steps: Array) -> Dictionary:
	return {"giver": "npc_innkeeper", "title": "Клин для лесорубов", "scale": "trifle", "description": "Лесорубы ждут клин.",
		"quest_item": {"item": {"name": "Клин для колки", "item_type": "gear", "rarity": "common", "value_cp": 20}, "from_giver": true},
		"steps": steps}


func test_the_giver_hands_the_parcel_and_it_is_left_at_the_place() -> void:
	var r := _make(_wedge([{"text": "Отнести клин на Тропу лесорубов", "kind": "visit", "target": "pushcha-trail", "item_id": "item"}]))
	assert_bool(bool(r["accepted"])).override_failure_message(str(r)).is_true()
	var qid := str(s.generated["quests"].keys()[0])
	var q := QuestRules.quest(data["world"], qid)
	var wedge := str((q["offer_items"] as Dictionary).keys()[0])
	assert_str(ItemRules.display_name(data["items"], s.items, wedge)).is_equal("Клин для колки")
	assert_dict(q["steps"][0]["when"]).is_equal({"arrive": "pushcha-trail", "item": wedge})
	QuestRules.accept(s, data, qid)
	assert_int(int(s.character["inventory"].get(wedge, 0))).is_equal(1)
	s.room_id = "pushcha-trail"
	var lines := QuestRules.advance(s, data)
	assert_array(lines).contains(["Оставлено: Клин для колки"])
	assert_bool(s.character["inventory"].has(wedge)).is_false()
	assert_int(int(s.quests_active[qid])).is_equal(1)  # the way back to the giver


func test_without_the_parcel_the_place_does_not_close_the_step() -> void:
	assert_bool(bool(_make(_wedge([{"text": "Отнести клин на тропу", "kind": "visit", "target": "pushcha-trail", "item_id": "item"}]))["accepted"])).is_true()
	var qid := str(s.generated["quests"].keys()[0])
	QuestRules.accept(s, data, qid)
	s.character["inventory"].erase(str((QuestRules.quest(data["world"], qid)["offer_items"] as Dictionary).keys()[0]))
	s.room_id = "pushcha-trail"
	QuestRules.advance(s, data)
	assert_int(int(s.quests_active[qid])).is_equal(0)


func test_a_catalog_parcel_goes_to_a_person() -> void:
	var q := {"giver": "npc_innkeeper", "title": "Оберег для жрицы", "scale": "trifle", "description": "Бруно шлёт оберег.",
		"quest_item": {"item_id": "amulet", "from_giver": true},
		"steps": [{"text": "Передать оберег Илве", "kind": "talk", "target": "npc_priestess", "item_id": "item"}]}
	var r := _make(q)
	assert_bool(bool(r["accepted"])).override_failure_message(str(r)).is_true()
	var made := QuestRules.quest(data["world"], str(s.generated["quests"].keys()[0]))
	assert_dict(made["offer_items"]).is_equal({"amulet": 1})
	assert_dict(made["steps"][0]["when"]).is_equal({"talk": "npc_priestess", "item": "amulet"})
	assert_dict(made["steps"][-1]["when"]).is_equal({"talk": "npc_innkeeper"})  # back for the pay, the thing stays given


func test_a_parcel_needs_a_step_that_hands_it_over() -> void:
	var back := _make(_wedge([{"text": "Сходить на тропу", "kind": "visit", "target": "pushcha-trail"}]))
	assert_str(str(back["reason"])).contains("нужен шаг")
	var sought := _make(_wedge([{"text": "Найти клин", "kind": "find", "target": "item"}]), "t-2")
	assert_str(str(sought["reason"])).contains("не ищут")
	var own := _wedge([{"text": "Отнести клин", "kind": "visit", "target": "pushcha-trail", "item_id": "item"}])
	own.erase("giver")
	own["own"] = true
	assert_str(str(_make(own, "t-3")["reason"])).contains("нет заказчика")
