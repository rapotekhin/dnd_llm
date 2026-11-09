extends GdUnitTestSuite
## A thing taken from a foe (v0.8.4.42.1, the author's feedback: the wolf fled, its hide hidden in another glade — the
## quest could not be done): it lies where the fight is, and a find closes as soon as the hero has it by any way.

var data: Dictionary
var s: GameSession
var fx: EffectEngine


func before_test() -> void:
	data = TestUtils.data().duplicate(true)
	s = TestUtils.new_session()
	s.room_id = "brod-tavern-hall"
	fx = EffectEngine.new()


func _taken() -> String:
	fx.searched_quests["t-1"] = true
	var r := fx.validate(s, data, "t-1", {"kind": "create", "what": "quest", "giver": "npc_innkeeper", "title": "Шкуры для Гуннара",
		"difficulty": "medium", "description": "Кузнецу нужны волчьи шкуры.", "offer_text": "Принеси шкуру.",
		"acts": [{"title": "Опушка", "goal": "Добыть шкуру"}]})
	assert_bool(bool(r["accepted"])).override_failure_message(str(r)).is_true()
	fx.apply(s, "t-1", [r["effect_id"]])
	var id := str(s.generated["quests"].keys()[-1])
	QuestRules.accept(s, data, id)
	return id


func _act(id: String, room: String) -> Dictionary:
	var e := {"kind": "quest_act", "quest_id": id, "act": 1,
		"encounters": [{"key": "wolf", "room": "pushcha-edge", "kind": "ambush", "enemies": [{"monster": "giant_rat", "count": 1}]}],
		"items": [{"key": "hide", "item_id": "raw_hide", "room": room, "hint": "под лапником у стоянки", "dc_tier": "easy", "skill": "survival"}],
		"steps": [{"text": "Одолеть волка на опушке", "kind": "fight", "target": "wolf"},
			{"text": "Снять шкуру", "kind": "find", "target": "hide", "needs": {"kind": "fight", "target": "wolf"}, "needs_text": "сначала волк"},
			{"text": "Отнести шкуру Бруно", "kind": "talk", "target": "npc_innkeeper", "item_id": "hide"}]}
	var r := fx.validate(s, data, "t-9", e)
	if bool(r["accepted"]):
		r["lines"] = fx.apply(s, "t-9", [r["effect_id"]])
	return r


func test_a_thing_found_after_a_fight_lies_where_the_fight_is() -> void:
	var id := _taken()
	assert_str(str(_act(id, "pushcha-hollow").get("reason", ""))).contains("там же, где бой")
	var r := _act(id, "pushcha-edge")
	assert_bool(bool(r["accepted"])).override_failure_message(str(r)).is_true()


func test_a_find_closes_when_the_hero_has_the_thing_by_any_way() -> void:
	var id := _taken()
	assert_bool(bool(_act(id, "pushcha-edge")["accepted"])).is_true()
	var q := QuestRules.quest(data["world"], id)
	s.encounters_passed.append(str(q["steps"][0]["when"]["encounter"]))  # the wolf fled: the fight is over
	QuestRules.advance(s, data)
	assert_int(int(s.quests_active[id])).is_equal(1)  # the hide is still to get
	ItemRules.add(s.character, "raw_hide", 1)  # the master handed one from the camp, not the hidden one
	QuestRules.advance(s, data)
	assert_int(int(s.quests_active[id])).is_equal(2)  # the find is done: take it to Bruno
