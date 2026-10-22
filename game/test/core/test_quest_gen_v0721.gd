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


func _yard_quest() -> Dictionary:
	return {"giver": "npc_merchant", "title": "Пропавший задаток", "scale": "ordinary",
		"new_place": {"edge": 0, "rooms": [{"key": "yard", "name": "Задний двор лавки", "description": "Бочки, крапива, гнилое крыльцо.",
			"encounter": {"enemies": [{"monster": "wolf", "count": 1}]}}]},
		"new_npcs": [{"key": "boy", "name": "Тимоша", "role": "мальчишка-посыльный", "room_id": "new:yard"}],
		"quest_item": {"item_id": "amulet", "room": "new:yard", "hint": "Под гнилым крыльцом что-то блестит", "dc_tier": "easy"},
		"steps": [{"text": "Расспросить посыльного", "kind": "talk", "target": "new:boy"},
			{"text": "Найти задаток", "kind": "find", "target": "item"},
			{"text": "Отогнать волка со двора", "kind": "fight", "target": "new:yard"},
			{"text": "Отдать задаток торговцу", "kind": "talk", "target": "npc_merchant", "item_id": "item"}]}


func test_a_quest_brings_its_place_person_and_thing_in_one_deal() -> void:
	s.room_id = "brod-square"
	var r := _make(_yard_quest())
	assert_bool(bool(r["accepted"])).override_failure_message(str(r)).is_true()
	assert_str(str(r["summary"])).contains("Тимоша")
	var qid := str(s.generated["quests"].keys()[0])
	var steps: Array = QuestRules.quest(data["world"], qid)["steps"]
	var yard := str(steps[0]["when"]["talk"])  # the boy's id; his room is the new yard
	assert_str(yard).starts_with("gen_npc_")
	var room := str(s.generated["npc_rooms"][yard])
	assert_bool(s.generated["rooms"].has(room)).is_true()
	assert_str(str(steps[1]["when"]["secret"])).is_equal("%s:q_%s" % [room, qid])
	assert_str(str(steps[2]["when"]["encounter"])).is_equal(room + "_enc")
	assert_str(str(steps[3]["when"]["item"])).is_equal("amulet")
	assert_int(steps.size()).is_equal(4)  # the last step is already the way back to the giver
	# the whole chain by the engine's facts
	QuestRules.accept(s, data, qid)
	s.room_id = room
	QuestRules.talk(s, data, qid)
	s.revealed[room] = ["q_" + qid]
	ExplorationRules.take_caches(s, data, room)
	assert_int(int(s.character["inventory"].get("amulet", 0))).is_equal(1)
	QuestRules.advance(s, data)
	s.encounters_done.append(room + "_enc")
	QuestRules.advance(s, data)
	s.room_id = "brod-square"
	QuestRules.talk(s, data, qid)
	assert_bool(s.quests_done.has(qid)).is_true()
	# the hiding place survives a save
	var world := WorldGen.merged(TestUtils.data()["world"], GameSession.from_dict(s.to_dict(5)).generated)
	assert_bool((world["rooms"][room]["secrets"] as Array).any(func(x: Dictionary) -> bool: return str(x["id"]) == "q_" + qid)).is_true()


func test_a_quest_is_all_or_nothing_and_its_people_have_a_depth() -> void:
	s.room_id = "brod-square"
	var bad := _yard_quest()
	bad["new_npcs"][0]["monster"] = "young_red_dragon"
	assert_str(str(_make(bad)["reason"])).contains("человек задания boy")
	assert_bool(WorldGen.generated(s).get("rooms", {}).is_empty()).is_true()  # nothing of the deal was made
	assert_bool(bool(_make(_yard_quest(), "t-2")["accepted"])).is_true()
	var boy := str(WorldGen.generated(s)["npcs"].keys()[0])
	assert_int(int(data["world"]["npcs"][boy]["quest_depth"])).is_equal(1)
	data["world"]["npcs"][boy]["quest_depth"] = 2  # a person of a quest of a quest
	s.room_id = str(s.generated["npc_rooms"][boy])
	var deeper := {"giver": boy, "title": "Ещё глубже", "scale": "trifle", "steps": [{"text": "Сходить к Мире", "kind": "talk", "target": "npc_serving"}]}
	assert_str(str(_make(deeper, "t-3")["reason"])).contains("глубина")


func test_the_way_back_takes_the_quest_thing_to_the_giver() -> void:
	var q := {"giver": "npc_innkeeper", "title": "Кольцо хозяйки", "scale": "trifle",
		"quest_item": {"item_id": "amulet", "room": "brod-tavern-cellar", "hint": "Меж бочек блестит", "dc_tier": "easy"},
		"steps": [{"text": "Найти кольцо в погребе", "kind": "find", "target": "item"}]}
	assert_bool(bool(_make(q)["accepted"])).is_true()
	var steps: Array = QuestRules.quest(data["world"], str(s.generated["quests"].keys()[0]))["steps"]
	assert_dict(steps[-1]["when"]).is_equal({"talk": "npc_innkeeper", "item": "amulet"})
