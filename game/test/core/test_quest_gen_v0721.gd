extends GdUnitTestSuite
## «Генерация заданий», batch 1 (roadmap v0.7.21): a quest the master makes from a giver of the scene, on what the
## world has; the engine checks its steps, sets the reward by the table, and the quest lives like a pack quest.

var data: Dictionary
var s: GameSession
var fx: EffectEngine


func before_test() -> void:
	data = TestUtils.data().duplicate(true)  # the world grows in this test only
	s = TestUtils.new_session()
	s.room_id = "brod-tavern-hall"
	fx = EffectEngine.new()


func _make(spec: Dictionary, turn := "t-1", search := true) -> Dictionary:
	if search:
		fx.searched_quests[turn] = true
	var e := spec.duplicate(true)
	e["kind"] = "create_quest"
	var r := fx.validate(s, data, turn, e)
	if bool(r["accepted"]):
		fx.apply(s, turn, [r["effect_id"]])
	return r


func _wolves() -> Dictionary:
	return {"giver": "npc_innkeeper", "title": "Волки у просеки", "scale": "ordinary", "description": "Волки режут скот лесорубов.",
		"offer_text": "Отгони волков с просеки — заплачу.", "steps": [{"text": "Перебить волков на просеке", "kind": "fight", "target": "trail_wolves"}]}


func test_a_made_quest_is_offered_taken_and_rewarded_by_the_table() -> void:
	var r := _make(_wolves())
	assert_bool(bool(r["accepted"])).override_failure_message(str(r)).is_true()
	var id := str(s.generated["quests"].keys()[0])
	assert_array(QuestRules.offers_here(s, data["world"])).contains([id])
	var q := QuestRules.quest(data["world"], id)
	assert_int((q["steps"] as Array).size()).is_equal(2)  # the fight and the way back to the giver
	assert_int(int(q["steps"][1]["reward_cp"])).is_equal(2500)  # ordinary, level 1
	assert_bool(bool(q["steps"][1].get("danger", false))).is_true()  # a fight: class XP at the end
	QuestRules.accept(s, data, id)
	s.encounters_done.append("trail_wolves")
	QuestRules.advance(s, data)
	var gold := int(s.character["gold_cp"])
	QuestRules.talk(s, data, id)
	assert_bool(s.quests_done.has(id)).is_true()
	assert_int(int(s.character["gold_cp"]) - gold).is_equal(2500)


func test_the_engine_checks_the_quest() -> void:
	assert_str(str(_make(_wolves(), "t-1", false)["reason"])).contains("find_quests")
	var bad := _wolves()
	bad["giver"] = "npc_smith"
	assert_str(str(_make(bad, "t-2")["reason"])).contains("этой сцены")
	bad = _wolves()
	bad["steps"] = [{"text": "Найти дракона", "kind": "fight", "target": "dragon_lair"}]
	assert_str(str(_make(bad, "t-3")["reason"])).contains("встречи")
	bad = _wolves()
	bad["scale"] = "epic"
	assert_str(str(_make(bad, "t-4")["reason"])).contains("величина")
	bad = _wolves()
	bad["reward_item_id"] = "plate_armor"
	assert_str(str(_make(bad, "t-5")["reason"])).contains("дороже")


func test_at_most_three_open_made_quests_and_they_survive_a_save() -> void:
	for i in 3:
		var q := _wolves()
		q["title"] = "Дело %d" % i
		q["steps"] = [{"text": "Расспросить Миру", "kind": "talk", "target": "npc_serving"}]
		assert_bool(bool(_make(q, "t-%d" % i)["accepted"])).is_true()
	var more := _wolves()
	assert_str(str(_make(more, "t-9")["reason"])).contains("уже 3")
	var back := GameSession.from_dict(s.to_dict(5))
	var world := WorldGen.merged(TestUtils.data()["world"], back.generated)
	assert_int(QuestRules.stepped(world).size() - QuestRules.stepped(TestUtils.data()["world"]).size()).is_equal(3)
	assert_str(str(QuestGen.find_quests(s, data, "Дело")[0]["source"])).is_equal("made")
