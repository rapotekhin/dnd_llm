extends GdUnitTestSuite
## A parcel of a made quest (v0.7.34.5, the wedge of the author's trace 2026-10-27): the giver hands the thing over on
## taking, a step gives it to a person or leaves it at a place; an errand without the thing is not made. v0.7.39.6: the
## parcel is a thing of the first act, handed over when it is built on taking.

var data: Dictionary
var s: GameSession
var fx: EffectEngine


func before_test() -> void:
	data = TestUtils.data().duplicate(true)
	s = TestUtils.new_session()
	s.room_id = "brod-tavern-hall"
	fx = EffectEngine.new()


func _quest(own := false) -> String:
	fx.searched_quests["t-1"] = true
	var e := {"kind": "create_quest", "title": "Своё: клин" if own else "Клин для лесорубов", "difficulty": "easy", "description": "Лесорубы ждут клин.",
		"acts": [{"title": "Клин", "goal": "Доставить клин лесорубам"}]}
	if own:
		e["own"] = true
	else:
		e["giver"] = "npc_innkeeper"
	var r := fx.validate(s, data, "t-1", e)
	assert_bool(bool(r["accepted"])).override_failure_message(str(r)).is_true()
	fx.apply(s, "t-1", [r["effect_id"]])
	var id := str(s.generated["quests"].keys()[-1])
	if not own:
		QuestRules.accept(s, data, id)
	return id


func _act(id: String, items: Array, steps: Array, turn := "t-2") -> Dictionary:
	var r := fx.validate(s, data, turn, {"kind": "quest_act", "quest_id": id, "act": 1, "items": items, "steps": steps})
	if bool(r["accepted"]):
		fx.apply(s, turn, [r["effect_id"]])
	return r


const WEDGE := {"key": "wedge", "item": {"name": "Клин для колки", "item_type": "gear", "rarity": "common", "value_cp": 20}, "from_giver": true}


func test_the_giver_hands_the_parcel_and_it_is_left_at_the_place() -> void:
	var id := _quest()
	var r := _act(id, [WEDGE], [{"text": "Отнести клин на Тропу лесорубов", "kind": "visit", "target": "pushcha-trail", "item_id": "wedge"}])
	assert_bool(bool(r["accepted"])).override_failure_message(str(r)).is_true()
	var q := QuestRules.quest(data["world"], id)
	var wedge := str(q["items"]["wedge"])
	assert_str(ItemRules.display_name(data["items"], s.items, wedge)).is_equal("Клин для колки")
	assert_dict(q["steps"][0]["when"]).is_equal({"arrive": "pushcha-trail", "item": wedge})
	assert_int(int(s.character["inventory"].get(wedge, 0))).is_equal(1)
	s.room_id = "pushcha-trail"
	var lines := QuestRules.advance(s, data)
	assert_array(lines).contains(["Оставлено: Клин для колки"])
	assert_bool(s.character["inventory"].has(wedge)).is_false()
	assert_int(int(s.quests_active[id])).is_equal(1)  # the way back to the giver


func test_without_the_parcel_the_place_does_not_close_the_step() -> void:
	var id := _quest()
	assert_bool(bool(_act(id, [WEDGE], [{"text": "Отнести клин на тропу", "kind": "visit", "target": "pushcha-trail", "item_id": "wedge"}])["accepted"])).is_true()
	s.character["inventory"].erase(str(QuestRules.quest(data["world"], id)["items"]["wedge"]))
	s.room_id = "pushcha-trail"
	QuestRules.advance(s, data)
	assert_int(int(s.quests_active[id])).is_equal(0)


func test_a_catalog_parcel_goes_to_a_person() -> void:
	var id := _quest()
	var r := _act(id, [{"key": "amulet", "item_id": "amulet", "from_giver": true}], [{"text": "Передать оберег Илве", "kind": "talk", "target": "npc_priestess", "item_id": "amulet"}])
	assert_bool(bool(r["accepted"])).override_failure_message(str(r)).is_true()
	var made := QuestRules.quest(data["world"], id)
	assert_dict(made["steps"][0]["when"]).is_equal({"talk": "npc_priestess", "item": "amulet"})
	assert_dict(made["steps"][-1]["when"]).is_equal({"talk": "npc_innkeeper"})  # back for the pay, the thing stays given


func test_a_parcel_needs_a_step_that_hands_it_over() -> void:
	var id := _quest()
	assert_str(str(_act(id, [WEDGE], [{"text": "Сходить на тропу", "kind": "visit", "target": "pushcha-trail"}])["reason"])).contains("не нужна ни одному шагу")
	assert_str(str(_act(id, [WEDGE], [{"text": "Найти клин", "kind": "find", "target": "wedge"}], "t-3")["reason"])).contains("не ищут")
	var own := _quest(true)
	assert_str(str(_act(own, [WEDGE], [{"text": "Отнести клин", "kind": "visit", "target": "pushcha-trail", "item_id": "wedge"}], "t-4")["reason"])).contains("from_giver")
