extends GdUnitTestSuite
## The hero's life goal (roadmap v0.7.22, batch 1): written by the player, assessed by the master, its threshold set
## by the engine — the level of the direction the goal needs.

var data: Dictionary
var s: GameSession
var fx: EffectEngine


func before_test() -> void:
	data = TestUtils.data()
	s = TestUtils.new_session()
	fx = EffectEngine.new()


func _assess(e: Dictionary, turn := "t-1") -> Dictionary:
	var spec := e.duplicate()
	spec["kind"] = "goal_assess"
	var r := fx.validate(s, data, turn, spec)
	if bool(r["accepted"]):
		fx.apply(s, turn, [r["effect_id"]])
	return r


func test_a_goal_is_written_assessed_and_has_a_threshold() -> void:
	var c := s.character
	assert_str(str(_assess({"scale": "epic"})["reason"])).contains("нет жизненной цели")
	GoalRules.write(c, "  Убить дракона  ")
	assert_str(GoalRules.text_of(c, data)).contains("ещё не оценена")
	assert_bool(bool(_assess({"scale": "epic", "direction": "class", "concepts": ["бой", "место"]}, "t-2")["accepted"])).is_true()
	assert_int(GoalRules.threshold(c, data)).is_equal(5)
	assert_bool(GoalRules.reached(c, data)).is_false()
	assert_str(GoalRules.text_of(c, data)).contains("рано: уровень класса 1 из 5")
	c["level"] = 5
	assert_bool(GoalRules.reached(c, data)).is_true()
	GoalRules.write(c, "Убить дракона")  # the same text keeps its assessment
	assert_int(GoalRules.threshold(c, data)).is_equal(5)
	GoalRules.write(c, "Открыть свою таверну")  # a new one waits for the master again
	assert_int(GoalRules.threshold(c, data)).is_equal(-1)
	GoalRules.write(c, "")
	assert_bool(GoalRules.goal(c).is_empty()).is_true()


func test_a_peaceful_goal_counts_its_direction() -> void:
	var c := s.character
	GoalRules.write(c, "Открыть свою таверну")
	assert_str(str(_assess({"scale": "medium", "direction": "smithing"})["reason"])).contains("направление")
	assert_bool(bool(_assess({"scale": "medium", "direction": "trade"}, "t-2")["accepted"])).is_true()
	assert_str(GoalRules.text_of(c, data)).contains("Торговля 0 из 2")
	GoalRules.write(c, "Стать королём")
	_assess({"scale": "legendary"}, "t-3")
	assert_str(GoalRules.text_of(c, data)).contains("пока недостижима")


func test_the_goal_is_in_the_snapshot_and_the_save() -> void:
	GoalRules.write(s.character, "Изучить пещеры")
	_assess({"scale": "easy"})
	var snap := TurnSnapshot.build(s, data, 2000)
	assert_str(str(snap["character"]["goal"])).contains("по силам")
	var back := GameSession.from_dict(s.to_dict(5))
	assert_str(str(GoalRules.goal(back.character)["scale"])).is_equal("easy")


func test_past_the_threshold_hints_come_first_then_the_quest() -> void:
	var c := s.character
	s.room_id = "brod-tavern-hall"
	GoalRules.write(c, "Убить тролля")
	_assess({"scale": "hard"})  # level 3 of the class, two hints before the quest
	assert_str(str(_assess_kind({"kind": "goal_hint"}, "t-2")["reason"])).contains("ещё не по силам")
	var quest := {"kind": "create_quest", "giver": "npc_innkeeper", "title": "След тролля", "scale": "major", "for_goal": true,
		"steps": [{"text": "Расспросить Миру", "kind": "talk", "target": "npc_serving"}]}
	fx.searched_quests["t-3"] = true
	assert_str(str(_assess_kind(quest, "t-3")["reason"])).contains("ещё не по силам")
	c["level"] = 3
	fx.searched_quests["t-4"] = true
	assert_str(str(_assess_kind(quest, "t-4")["reason"])).contains("намёков 0 из 2")
	assert_bool(bool(_assess_kind({"kind": "goal_hint"}, "t-5")["accepted"])).is_true()
	assert_bool(bool(_assess_kind({"kind": "goal_hint"}, "t-6")["accepted"])).is_true()
	assert_str(GoalRules.text_of(c, data)).contains("намёков 2 из 2")
	fx.searched_quests["t-7"] = true
	assert_bool(bool(_assess_kind(quest, "t-7")["accepted"])).is_true()


func test_a_simple_goal_needs_no_hints() -> void:
	GoalRules.write(s.character, "Изучить пещеры")
	_assess({"scale": "easy"})
	assert_str(GoalRules.quest_why_not(s.character, data)).is_empty()


func _assess_kind(e: Dictionary, turn: String) -> Dictionary:
	var r := fx.validate(s, data, turn, e)
	if bool(r["accepted"]):
		fx.apply(s, turn, [r["effect_id"]])
	return r
