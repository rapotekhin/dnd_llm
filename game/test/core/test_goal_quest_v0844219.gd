extends GdUnitTestSuite
## The goal's quest ends in the goal (v0.8.4.42.19, the author's trace): the goal «пора найти и убить дракона», great;
## its quest «Серебро для Сумеречного Зуба» of «hard» found the silver, forged a blade and ended — no dragon in it; the
## goal stuck (no hint, no new quest, never done); the «silver blade» of the finale came as a plain longsword, since a
## choice's reward could only be a catalog id. Now the last act of a goal's quest has the step that fulfills the goal,
## the quest done with it fulfills the goal, one without it was a link and frees the goal, the quest of a great deed is no
## easier than «hard», and a finale's reward may be a thing the master made.

var data: Dictionary
var s: GameSession
var fx: EffectEngine

const SILVER := {"name": "Серебряный клинок", "item_type": "weapon", "base": "longsword", "properties": ["silvered"],
	"rarity": "common", "value_cp": 0, "description": "Длинный меч с серебряной кромкой."}


func before_test() -> void:
	data = TestUtils.data().duplicate(true)
	s = TestUtils.new_session()
	s.room_id = "brod-tavern-hall"
	fx = EffectEngine.new()


func _do(e: Dictionary, turn: String) -> Dictionary:
	if e["kind"] == "create":
		fx.searched_quests[turn] = true
	var r := fx.validate(s, data, turn, e)
	if bool(r["accepted"]):
		fx.apply(s, turn, [r["effect_id"]])
	return r


func _goal(text: String, scale: String) -> void:
	GoalRules.write(s.character, text)
	var r := _do({"kind": "goal", "what": "assess", "scale": scale, "concepts": ["бой", "слава"]}, "t-a")
	assert_bool(bool(r["accepted"])).override_failure_message(str(r)).is_true()
	s.character["goal"]["hints"] = GoalRules.hints_needed(s.character, data)


func _quest(diff: String, acts := 1) -> Dictionary:
	var list: Array = []
	for i in acts:
		list.append({"title": "Акт %d" % (i + 1), "goal": "Сделать дело номер %d" % (i + 1)})
	return _do({"kind": "create", "what": "quest", "giver": "npc_innkeeper", "title": "Дело цели", "difficulty": diff, "for_goal": true,
		"description": "Дело жизни героя.", "offer_text": "Есть у меня мысль насчёт твоего замысла.", "acts": list}, "t-q")


func test_a_great_deed_asks_a_quest_no_easier_than_hard() -> void:
	s.character["level"] = 5
	_goal("пора найти и убить дракона", "epic")
	var r := _quest("medium", 2)
	assert_bool(bool(r["accepted"])).is_false()
	assert_str(str(r["reason"])).contains("не легче «сложное»")
	assert_bool(bool(_quest("hard", 2)["accepted"])).is_true()


func test_the_last_act_must_hold_the_goal_itself() -> void:
	_goal("помириться с Бруно", "easy")
	assert_bool(bool(_quest("easy")["accepted"])).is_true()
	var id := GoalRules.quest_of(s.character)
	QuestRules.accept(s, data, id)
	assert_str(QuestGen.act_frame(s, data, id)).contains("Финал задания — сама цель")
	var act := {"kind": "quest_act", "quest_id": id, "act": 1, "steps": [{"text": "Поговорить с Мирой о Бруно", "kind": "talk", "target": "npc_serving"}]}
	var r := fx.validate(s, data, "t-1", act)
	assert_bool(bool(r["accepted"])).is_false()
	assert_str(str(r["reason"])).contains("goal: true")
	act["steps"][0]["goal"] = true
	act["reward_item"] = SILVER
	r = fx.validate(s, data, "t-2", act)
	assert_bool(bool(r["accepted"])).override_failure_message(str(r)).is_true()
	fx.apply(s, "t-2", [r["effect_id"]])
	var q := QuestRules.quest(data["world"], id)
	assert_bool(bool(q["steps"][0].get("goal", false))).is_true()
	var silver := ItemRules.generated_id(ItemRules.check_generated(data, SILVER, 1)["def"])
	assert_bool(s.items.has(silver)).is_true()  # the master's reward is a thing of this game
	assert_bool((s.items[silver]["properties"] as Array).has("silvered")).is_true()
	assert_int(int(q["steps"][-1]["items"][silver])).is_equal(1)


func test_a_quest_done_with_its_goal_step_fulfills_the_goal() -> void:
	_goal("помириться с Бруно", "easy")
	_quest("easy")
	var id := GoalRules.quest_of(s.character)
	QuestRules.quest(data["world"], id)["steps"] = [{"text": "Помириться", "when": {"talk": "npc_innkeeper"}, "goal": true}]
	s.quests_done.append(id)
	var lines := WorldEvent.emit(s, data, "quest_done", {"giver": "npc_innkeeper", "title": "Дело цели", "npc": "npc_innkeeper",
		"location": ReputationRules.home_of(data, "npc_innkeeper"), "points": "quest_done", "why": "задание", "bond_deed": "quest_done",
		"bond_why": "задание", "faction": FactionRules.of_npc(s, data, "npc_innkeeper"), "source": "quest_done"})
	assert_array(lines).contains(["Жизненная цель исполнена: «помириться с Бруно»"])
	assert_bool(GoalRules.done(s.character)).is_true()
	assert_str(GoalRules.hint_why_not(s.character, data)).contains("исполнена")


func test_a_quest_without_its_goal_step_was_a_link_and_frees_the_goal() -> void:
	s.character["level"] = 5
	_goal("пора найти и убить дракона", "epic")
	_quest("hard", 2)
	var id := GoalRules.quest_of(s.character)
	QuestRules.quest(data["world"], id)["steps"] = [{"text": "Выковать серебряный клинок", "when": {"talk": "npc_smith"}}]
	s.quests_done.append(id)  # an old save: its quest done before this version — settled on the next look
	assert_str(GoalRules.quest_due(s, data)).is_empty()  # no clue's giver in this test: the master makes it when asked
	assert_bool(GoalRules.done(s.character)).is_false()
	assert_str(GoalRules.quest_of(s.character)).is_empty()
	assert_int(GoalRules.hints(s.character)).is_equal(GoalRules.hints_needed(s.character, data) - 1)
	var r := fx.validate(s, data, "t-h", {"kind": "goal", "what": "hint", "clue": "Логово на Сумеречном Зубе", "npc": "npc_smith"})
	assert_bool(bool(r["accepted"])).override_failure_message(str(r)).is_true()  # one more hint, then the next quest


func test_a_finale_choice_may_give_a_thing_the_master_made() -> void:
	var r := QuestGen._plan_choices(s, data, [
		{"id": "blade", "action": "Выковать серебряный клинок", "done_text": "Гуннар плавит серебро в кромку клинка.", "reward_item": SILVER},
		{"id": "coin", "action": "Продать серебро", "done_text": "Серебро ушло скупщику за звонкую монету."}], {"room_keys": []}, "q", 100000)
	assert_bool(r.has("choices")).override_failure_message(str(r)).is_true()
	var blade: Dictionary = r["choices"][0]
	var id := str((blade["items"] as Dictionary).keys()[0])
	assert_str(id).starts_with("gen_")
	assert_bool((blade["made"][id]["properties"] as Array).has("silvered")).is_true()
	var both := QuestGen._plan_choices(s, data, [
		{"id": "blade", "action": "Выковать клинок", "done_text": "Гуннар плавит серебро в кромку клинка.", "reward_item": SILVER, "reward_item_id": "longsword"},
		{"id": "coin", "action": "Продать серебро", "done_text": "Серебро ушло скупщику за звонкую монету."}], {"room_keys": []}, "q", 100000)
	assert_str(str(both["reason"])).contains("не обе")
