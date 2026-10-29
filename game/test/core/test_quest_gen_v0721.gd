extends GdUnitTestSuite
## Quests the master makes (roadmap v0.7.21; by acts — v0.7.39.6): the skeleton (difficulty, acts) is offered at
## once; an act is built when it opens by the designer's `quest_act` — the engine checks its steps, people, places and
## fights by the difficulty; the reward is the engine's.

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


func _act(spec: Dictionary, turn := "t-9") -> Dictionary:
	var e := spec.duplicate(true)
	e["kind"] = "quest_act"
	var r := fx.validate(s, data, turn, e)
	if bool(r["accepted"]):
		r["lines"] = fx.apply(s, turn, [r["effect_id"]])
	return r


func _skeleton(diff := "medium", acts := 1, title := "Волки у просеки") -> Dictionary:
	var list: Array = []
	for i in acts:
		list.append({"title": "Акт %d" % (i + 1), "goal": "Сделать дело номер %d" % (i + 1)})
	return {"giver": "npc_innkeeper", "title": title, "difficulty": diff, "description": "Волки режут скот лесорубов.",
		"offer_text": "Отгони волков — заплачу.", "acts": list}


## A taken quest: its id.
func _taken(spec: Dictionary) -> String:
	var r := _make(spec)
	assert_bool(bool(r["accepted"])).override_failure_message(str(r)).is_true()
	var id := str(s.generated["quests"].keys()[-1])
	QuestRules.accept(s, data, id)
	return id


func _wolf_at(room: String, key := "pack", n := 1, monster := "wolf") -> Dictionary:
	return {"key": key, "room": room, "kind": "ambush", "enemies": [{"monster": monster, "count": n}]}


func test_a_skeleton_is_offered_and_waits_for_its_act_when_taken() -> void:
	var r := _make(_skeleton())
	assert_bool(bool(r["accepted"])).override_failure_message(str(r)).is_true()
	var id := str(s.generated["quests"].keys()[0])
	assert_array(QuestRules.offers_here(s, data["world"])).contains([id])
	var q := QuestRules.quest(data["world"], id)
	assert_int(int(q["reward_cp"])).is_equal(2500)  # medium, level 1
	assert_array(q["steps"]).is_empty()
	var lines := QuestRules.accept(s, data, id)
	assert_array(lines).contains(["Цель: Сделать дело номер 1"])
	assert_array(QuestRules.awaiting(s, data["world"])).contains([id])
	assert_str(QuestRules.step_text(s, data["world"], id)).contains("мастер готовит")
	assert_str(QuestRules.tracked(s, data["world"])).is_equal(id)
	assert_str(QuestGen.act_frame(s, data, id)).starts_with("[quest %s | act 1 | giver npc_innkeeper" % id).contains("wolf")


func test_an_act_with_an_ambush_is_built_fought_and_paid() -> void:
	var id := _taken(_skeleton())
	var one := {"quest_id": id, "act": 1, "encounters": [_wolf_at("pushcha-edge")],
		"steps": [{"text": "Отбиться от волков на опушке", "kind": "fight", "target": "pack"}]}
	assert_str(str(_act(one)["reason"])).contains("не меньше 2 шагов")
	one["steps"].push_front({"text": "Расспросить Миру", "kind": "talk", "target": "npc_serving"})
	var r := _act(one)
	assert_bool(bool(r["accepted"])).override_failure_message(str(r)).is_true()
	var q := QuestRules.quest(data["world"], id)
	assert_int((q["steps"] as Array).size()).is_equal(3)  # the talk, the fight and the way back to the giver
	assert_int(int(q["steps"][2]["reward_cp"])).is_equal(2500)
	assert_int(int(q["steps"][2]["xp"])).is_equal(150)
	assert_bool(bool(q["steps"][2].get("danger", false))).is_true()
	var enc: Dictionary = SceneRules.room(s, data["world"], "pushcha-edge")["encounter"]
	assert_str(str(enc["id"])).is_equal(id + "_pack")
	assert_bool(bool(enc.get("ambush", false))).is_true()
	assert_array(QuestRules.awaiting(s, data["world"])).is_empty()
	s.room_id = "brod-tavern-hall"
	QuestRules.talk(s, data, id)
	s.encounters_done.append(str(enc["id"]))
	QuestRules.advance(s, data)
	var gold := int(s.character["gold_cp"])
	QuestRules.talk(s, data, id)
	assert_bool(s.quests_done.has(id)).is_true()
	assert_int(int(s.character["gold_cp"]) - gold).is_equal(2500)
	assert_bool(SceneRules.room(s, data["world"], "pushcha-edge").has("encounter")).is_false()  # gone with the quest


func test_the_engine_checks_the_skeleton() -> void:
	assert_str(str(_make(_skeleton(), "t-1", false)["reason"])).contains("find_quests")
	var bad := _skeleton()
	bad["giver"] = "npc_smith"
	assert_str(str(_make(bad, "t-2")["reason"])).contains("этой сцены")
	bad = _skeleton()
	bad["difficulty"] = "epic"
	assert_str(str(_make(bad, "t-3")["reason"])).contains("сложность")
	assert_str(str(_make(_skeleton("hard", 1), "t-4")["reason"])).contains("актов 2–3")
	assert_str(str(_make(_skeleton("deadly", 2), "t-5")["reason"])).contains("актов 3–4")


func test_a_fight_is_checked_by_the_difficulty_and_the_room() -> void:
	var id := _taken(_skeleton())
	var talk := {"text": "Расспросить Миру", "kind": "talk", "target": "npc_serving"}
	var fight := {"text": "Отбиться", "kind": "fight", "target": "pack"}
	var act := func(enc: Dictionary) -> String:
		return str(_act({"quest_id": id, "act": 1, "encounters": [enc], "steps": [talk, fight]}).get("reason", ""))
	assert_str(act.call(_wolf_at("pushcha-edge", "pack", 3, "bandit"))).contains("не по силам")  # 75 > medium 50
	assert_str(act.call(_wolf_at("pushcha-edge", "pack", 1, "giant_rat"))).contains("слишком лёгкий")  # 25 — easy
	assert_str(act.call(_wolf_at("brod-square"))).contains("люди")
	assert_str(act.call(_wolf_at("pushcha-trail"))).contains("уже ждёт встреча")
	assert_str(act.call(_wolf_at("brod-tavern-upstairs"))).contains("отдыха")
	assert_str(act.call(_wolf_at("brod-tavern-hall"))).contains("люди")
	var boss := _wolf_at("pushcha-edge")
	boss["boss"] = true
	assert_str(act.call(boss)).contains("главарь")
	var spare := _act({"quest_id": id, "act": 1, "encounters": [_wolf_at("pushcha-edge"), _wolf_at("mine-flooded", "more")], "steps": [talk, fight]})
	assert_str(str(spare["reason"])).contains("more не нужен")


func test_a_hard_quest_by_acts_with_parts_a_lair_its_boss_and_the_choice() -> void:
	var id := _taken(_skeleton("hard", 2, "Пепельная стая"))
	var act1 := {"quest_id": id, "act": 1, "encounters": [{"key": "watch", "room": "outpost-tower", "kind": "guard",
			"enemies": [{"monster": "wolf"}, {"monster": "bandit"}]}],
		"steps": [{"text": "Осмотреть штрек и башню", "kind": "all", "parts": [{"text": "штрек", "kind": "visit", "target": "mine-flooded"},
			{"text": "башня", "kind": "fight", "target": "watch"}]}, {"text": "Рассказать Мире", "kind": "talk", "target": "npc_serving"}]}
	var r := _act(act1)
	assert_bool(bool(r["accepted"])).override_failure_message(str(r)).is_true()
	var q := QuestRules.quest(data["world"], id)
	assert_int(int(q["steps"][1]["xp"])).is_equal(150)  # hard, level 1: 300 by two acts
	s.room_id = "mine-flooded"
	s.visited.append("mine-flooded")
	assert_array(QuestRules.advance(s, data)).contains(["«Пепельная стая»: штрек — сделано"])
	s.encounters_done.append(id + "_watch")
	QuestRules.advance(s, data)
	s.room_id = "brod-tavern-hall"
	var lines := QuestRules.talk(s, data, id)
	assert_array(lines).contains(["«Пепельная стая»: акт «Акт 1» пройден"])
	assert_array(QuestRules.awaiting(s, data["world"])).contains([id])
	var lair := {"room_id": "pushcha-edge", "edge": 0, "rooms": [{"key": "den", "name": "Логово Хорта", "description": "Нора под корнями.",
		"encounter": {"enemies": [{"monster": "gnoll", "name": "Хорт"}], "boss": true}}]}
	var act2 := {"quest_id": id, "act": 2, "new_places": [lair],
		"steps": [{"text": "Одолеть Хорта", "kind": "fight", "target": "new:den"}]}
	assert_str(str(_act(act2)["reason"])).contains("не меньше 4 шагов")
	act2["steps"].append({"text": "Решить судьбу логова", "kind": "choice", "target": "new:den"})
	assert_str(str(_act(act2)["reason"])).contains("выбор")
	act2["choices"] = [{"id": "spare", "action": "Пощадить щенков", "done_text": "Щенки уползли в чащу, логово опустело.",
			"attitude": {"npc_innkeeper": 1}, "changes": [{"room_id": "new:den", "description": "Пустая нора, кости и тишина."}]},
		{"id": "burn", "action": "Сжечь логово", "done_text": "Нора горит до утра.", "reward_item_id": "healers_kit"}]
	r = _act(act2)
	assert_bool(bool(r["accepted"])).override_failure_message(str(r)).is_true()
	q = QuestRules.quest(data["world"], id)
	var den := str(s.generated["rooms"].keys()[-1])
	assert_bool(bool(data["world"]["rooms"][den]["encounter"].get("boss", false))).is_true()
	var tail: Dictionary = q["steps"][-1]
	assert_dict(tail["when"]).is_equal({"talk": "npc_innkeeper"})
	assert_int(int(tail["xp"])).is_equal(150)
	assert_int(int(tail["reward_cp"])).is_equal(7500 - int(data["items"]["catalog"]["healers_kit"]["value_cp"]))
	s.encounters_done.append(str(data["world"]["rooms"][den]["encounter"]["id"]))
	QuestRules.advance(s, data)
	s.room_id = den
	assert_int(QuestRules.choices_here(s, data["world"]).size()).is_equal(2)
	QuestRules.choose(s, data, id, "spare")
	assert_bool(s.flags.has(id + "_spare")).is_true()
	assert_str(str(SceneRules.room(s, data["world"], den)["description"])).is_equal("Пустая нора, кости и тишина.")
	s.room_id = "brod-tavern-hall"
	QuestRules.talk(s, data, id)
	assert_bool(s.quests_done.has(id)).is_true()


func test_a_boss_and_a_choice_belong_to_the_last_act() -> void:
	var id := _taken(_skeleton("hard", 2))
	var boss := {"key": "lead", "room": "outpost-tower", "kind": "target", "boss": true, "enemies": [{"monster": "gnoll", "name": "Хорт"}]}
	assert_str(str(_act({"quest_id": id, "act": 1, "encounters": [boss], "steps": [{"text": "Одолеть Хорта", "kind": "fight", "target": "lead"}]})["reason"])).contains("последнем акте")
	assert_str(str(_act({"quest_id": id, "act": 1, "steps": [{"text": "Решить", "kind": "choice", "target": "outpost-tower"}]})["reason"])).contains("последнем акте")
	var unnamed := {"key": "lead", "room": "outpost-tower", "kind": "target", "enemies": [{"monster": "wolf"}, {"monster": "bandit"}]}
	assert_str(str(_act({"quest_id": id, "act": 1, "encounters": [unnamed], "steps": [{"text": "Одолеть вожака", "kind": "fight", "target": "lead"}]})["reason"])).contains("имя")


func test_knowledge_holds_a_step() -> void:
	var id := _taken(_skeleton("easy"))
	var r := _act({"quest_id": id, "act": 1, "steps": [{"text": "Спросить Миру о следах", "kind": "talk", "target": "npc_serving",
		"needs": {"kind": "visit", "target": "mine-flooded"}, "needs_text": "сперва взглянуть на штрек"}]})
	assert_bool(bool(r["accepted"])).override_failure_message(str(r)).is_true()
	assert_array(QuestRules.talks_here(s, data["world"])).is_empty()
	assert_str(QuestRules.step_text(s, data["world"], id)).contains("сперва взглянуть на штрек")
	s.visited.append("mine-flooded")
	assert_int(QuestRules.talks_here(s, data["world"]).size()).is_equal(1)


func test_acts_and_their_fights_survive_a_save() -> void:
	var id := _taken(_skeleton())
	assert_bool(bool(_act({"quest_id": id, "act": 1, "encounters": [_wolf_at("pushcha-edge")],
		"steps": [{"text": "Расспросить Миру", "kind": "talk", "target": "npc_serving"}, {"text": "Отбиться", "kind": "fight", "target": "pack"}]})["accepted"])).is_true()
	var back := GameSession.from_dict(s.to_dict(5))
	var world := WorldGen.merged(TestUtils.data()["world"], back.generated)
	assert_int((QuestRules.quest(world, id)["steps"] as Array).size()).is_equal(3)
	assert_str(str(SceneRules.room(back, world, "pushcha-edge")["encounter"]["id"])).is_equal(id + "_pack")
	var base := (TestUtils.data()["world"]["rooms"]["pushcha-edge"].get("variants", []) as Array).size()
	assert_int((world["rooms"]["pushcha-edge"]["variants"] as Array).size()).is_equal(base + 1)
	assert_int((WorldGen.merged(world, back.generated)["rooms"]["pushcha-edge"]["variants"] as Array).size()).is_equal(base + 1)  # no doubles


func test_at_most_three_offered_by_a_giver_and_three_taken() -> void:
	for i in 3:
		assert_bool(bool(_make(_skeleton("easy", 1, "Дело %d" % i), "t-%d" % i)["accepted"])).is_true()
	assert_str(str(_make(_skeleton("easy", 1, "Дело 9"), "t-9")["reason"])).contains("уже предлагает 3")
	for id: String in s.generated["quests"]:
		QuestRules.accept(s, data, id)
	assert_str(QuestGen.can_take(s, data, str(s.generated["quests"].keys()[0]))).is_equal("QUEST_TOO_MANY")
	assert_str(str(QuestGen.find_quests(s, data, "Дело")[0]["source"])).is_equal("made")


func test_an_order_on_a_board_is_offered_at_the_board_and_paid_by_its_customer() -> void:
	var r0 := fx.validate(s, data, "t-b", {"kind": "furnish", "props": [{"name": "Доска объявлений", "text": "Заказы и вести Брода"}]})
	fx.apply(s, "t-b", [r0["effect_id"]])
	var board := str(PropRules.room_props(s, s.room_id)[0]["id"])
	var order := _skeleton("easy", 1, "Пропавшая коза")
	order["board_prop_id"] = board
	order["giver"] = "new:goat"
	order["new_npcs"] = [{"key": "goat", "name": "Дед Ермил", "role": "пастух"}]
	var r := _make(order)
	assert_bool(bool(r["accepted"])).override_failure_message(str(r)).is_true()
	var id := str(s.generated["quests"].keys()[0])
	var q := QuestRules.quest(data["world"], id)
	assert_str(str(data["world"]["npcs"][str(q["giver"])]["name"])).is_equal("Дед Ермил")
	assert_array(QuestRules.offers_here(s, data["world"])).contains([id])
	assert_str(QuestGen.difficulty_line(data, q)).contains("простое")


func test_an_own_deed_is_taken_at_once_and_waits_for_its_act() -> void:
	var own := _skeleton("easy", 1, "Моё дело")
	own.erase("giver")
	own["own"] = true
	assert_bool(bool(_make(own)["accepted"])).is_true()
	var id := str(s.generated["quests"].keys()[0])
	assert_bool(s.quests_active.has(id)).is_true()
	assert_int(int(QuestRules.quest(data["world"], id)["reward_cp"])).is_equal(0)
	var r := _act({"quest_id": id, "act": 1, "steps": [{"text": "Осмотреть штрек", "kind": "visit", "target": "mine-flooded"}]})
	assert_bool(bool(r["accepted"])).override_failure_message(str(r)).is_true()
	assert_dict(QuestRules.quest(data["world"], id)["steps"][-1]["when"]).is_equal({"arrive": "mine-flooded"})  # no way back
	s.room_id = "mine-flooded"
	QuestRules.advance(s, data)
	assert_bool(s.quests_done.has(id)).is_true()


func test_a_visit_step_closes_on_arriving_and_never_where_the_hero_stands() -> void:
	var id := _taken(_skeleton("easy"))
	assert_str(str(_act({"quest_id": id, "act": 1, "steps": [{"text": "Посидеть в зале", "kind": "visit", "target": "brod-tavern-hall"}]})["reason"])).contains("уже здесь")
	s.visited.append("pushcha-edge")
	assert_bool(bool(_act({"quest_id": id, "act": 1, "steps": [{"text": "Вернуться на опушку", "kind": "visit", "target": "pushcha-edge"}]})["accepted"])).is_true()
	s.room_id = "pushcha-edge"
	QuestRules.advance(s, data)
	assert_int(int(s.quests_active[id])).is_equal(1)


func test_an_old_made_quest_gets_its_difficulty() -> void:
	var d := {"save_version": 50, "session": {"generated": {"quests": {"gen_quest_1": {"title": "Старое", "scale": "major", "steps": []}}}}}
	SaveFormat.migrate(d)
	assert_str(str(d["session"]["generated"]["quests"]["gen_quest_1"]["difficulty"])).is_equal("hard")


func test_a_part_done_stays_done_when_the_hero_moves_on() -> void:
	var id := _taken(_skeleton("easy"))
	var r := _act({"quest_id": id, "act": 1, "encounters": [_wolf_at("pushcha-edge", "pack", 1, "giant_rat")],
		"steps": [{"text": "Осмотреть штрек и отбить волка", "kind": "all", "parts": [{"text": "штрек", "kind": "visit", "target": "mine-flooded"},
			{"text": "волк", "kind": "fight", "target": "pack"}]}]})
	assert_bool(bool(r["accepted"])).override_failure_message(str(r)).is_true()
	s.room_id = "mine-flooded"
	QuestRules.advance(s, data)
	s.room_id = "pushcha-edge"
	s.encounters_done.append(id + "_pack")
	QuestRules.advance(s, data)
	assert_str(QuestRules.step_text(s, data["world"], id)).contains("Вернуться к")
