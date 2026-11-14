extends GdUnitTestSuite
## The goal's thing (v0.8.4.42.16, the author's trace): the player asked for an amulet of Blur and for one of
## invisibility, the master assessed the goals as words, the quest designer made a «зыбкой пелены» amulet with the
## stealth property and later gave the same one for invisibility. Now the thing is named at the assessment in the player's
## words, priced by the engine, the goal grows to its rarity, and the goal's quest gives that very thing.

var data: Dictionary
var s: GameSession
var fx: EffectEngine

const BLUR := {"name": "Амулет расплывчатости", "item_type": "wondrous", "rarity": "uncommon", "value_cp": 50000,
	"description": "Мутное стекло в оправе: носящий всегда расплывается для глаза.", "wear": {"status": "spell:blur"}}
const UNSEEN := {"name": "Амулет невидимости", "item_type": "wondrous", "rarity": "uncommon", "value_cp": 50000,
	"description": "Тот, кто его надел, невидим, пока носит.", "wear": {"status": "invisible"}}


func before_test() -> void:
	data = TestUtils.data().duplicate(true)
	s = TestUtils.new_session()
	s.room_id = "brod-tavern-hall"
	fx = EffectEngine.new()


func _do(e: Dictionary, turn: String) -> Dictionary:
	var r := fx.validate(s, data, turn, e)
	if bool(r["accepted"]):
		fx.apply(s, turn, [r["effect_id"]])
	return r


func _assess(text: String, item: Dictionary, scale := "hard") -> Dictionary:
	GoalRules.write(s.character, text)
	return _do({"kind": "goal", "what": "assess", "scale": scale, "concepts": ["вещь", "задание"], "item": item}, "t-a")


func _worn(id: String) -> Array:
	Gear.give(s, data, "npc_veteran", id)
	return ConditionRules.effects(Gear.of(s, data, "npc_veteran")).filter(func(e: Dictionary) -> bool:
		return str(e.get("source", {}).get("kind", "")) == ItemRules.WORN)


func test_the_goal_names_its_thing_and_grows_to_its_rarity() -> void:
	var r := _assess("хочу амулет расплывчатости: надел — и постоянный эффект расплывчатости", BLUR)
	assert_bool(bool(r["accepted"])).override_failure_message(str(r)).is_true()
	var g := GoalRules.goal(s.character)
	assert_str(str(g["scale"])).is_equal("epic")  # Blur for good is very rare: no smaller than a great goal
	var id := GoalRules.item_of(s.character)
	assert_str(id).starts_with("gen_")
	assert_str(str(s.items[id]["wear"]["status"])).is_equal("spell:blur")
	assert_str(str(s.items[id]["rarity"])).is_equal("very_rare")  # the engine's price, not the master's word
	assert_str(GoalRules.text_of(s.character, data)).contains("вещь цели: «Амулет расплывчатости»")
	assert_str(str(r["summary"])).contains("масштаб цели не меньше «великая»")


func test_a_goal_thing_keeps_the_masters_scale_when_it_is_larger() -> void:
	var cheap := {"name": "Кольцо лазания", "item_type": "ring", "rarity": "uncommon", "value_cp": 20000, "description": "Лазать как паук.",
		"wear": {"climb_speed": "walk"}}
	assert_bool(bool(_assess("найти кольцо лазания", cheap, "epic")["accepted"])).is_true()
	assert_str(str(GoalRules.goal(s.character)["scale"])).is_equal("epic")
	assert_bool(bool(_assess("найти кольцо лазания", {"name": "Кольцо", "item_type": "ring", "rarity": "rare", "value_cp": 1,
		"wear": {"status": "spell:nothing_at_all"}})["accepted"])).is_false()  # a thing the engine cannot read is refused


func test_the_goal_things_lay_their_status_on_the_wearer() -> void:
	_assess("амулет расплывчатости", BLUR)
	var blur := _worn(GoalRules.item_of(s.character))
	assert_int(blur.size()).is_equal(1)
	_assess("теперь мне нужен амулет невидимости, чтобы тот, кто его надел, был невидим навсегда", UNSEEN)
	var unseen := GoalRules.item_of(s.character)
	assert_str(str(GoalRules.goal(s.character)["scale"])).is_equal("legendary")  # invisibility for good: out of reach for now
	assert_str(GoalRules.text_of(s.character, data)).contains("пока недостижима")
	Gear.give(s, data, "npc_mercenary", unseen)
	assert_bool(ConditionRules.has(Gear.of(s, data, "npc_mercenary"), "invisible")).is_true()


func test_two_things_of_one_name_and_another_power_are_two_things() -> void:
	var stealth := BLUR.duplicate(true)
	stealth.erase("wear")
	stealth["properties"] = ["stealth_advantage"]
	assert_str(ItemRules.generated_id(BLUR)).is_not_equal(ItemRules.generated_id(stealth))
	assert_array(ItemRules.power_of(BLUR)).contains(["носящему spell:blur"])


func test_find_items_shows_what_a_thing_does_on_the_wearer() -> void:
	_assess("амулет расплывчатости", BLUR)
	var hits := ItemRules.find(data["items"], s.items, "расплывчатости", "", [])
	assert_int(hits.size()).is_greater(0)
	assert_array(hits[0]["power"]).contains(["носящему spell:blur"])


func _goal_quest() -> String:
	s.character["level"] = 5
	assert_bool(bool(_assess("амулет расплывчатости", BLUR)["accepted"])).is_true()
	s.character["goal"]["hints"] = GoalRules.hints_needed(s.character, data)
	fx.searched_quests["t-q"] = true
	var r := _do({"kind": "create", "what": "quest", "giver": "npc_innkeeper", "title": "Зыбкая пелена", "difficulty": "easy", "for_goal": true,
		"acts": [{"title": "Пелена", "goal": "Достать амулет из погреба"}]}, "t-q")
	assert_bool(bool(r["accepted"])).override_failure_message(str(r)).is_true()
	var id := GoalRules.quest_of(s.character)
	QuestRules.accept(s, data, id)
	return id


func test_the_goal_quest_gives_that_very_thing() -> void:
	var qid := _goal_quest()
	var frame := QuestGen.act_frame(s, data, qid)
	assert_str(frame).contains("Задание жизненной цели героя, его словами: «амулет расплывчатости»")
	assert_str(frame).contains("Вещь цели: [%s] Амулет расплывчатости — носящему spell:blur" % GoalRules.item_of(s.character))
	var act := func(item_id: String) -> Dictionary:
		return fx.validate(s, data, "t-act", {"kind": "quest_act", "quest_id": qid, "act": 1,
			"items": [{"key": "amulet", "item_id": item_id, "room": "brod-tavern-cellar", "hint": "в шкатулке за бочками", "dc_tier": "easy",
				"skill": "perception"}],
			"steps": [{"text": "Найти амулет в погребе", "kind": "find", "target": "amulet"}]})
	var wrong: Dictionary = act.call("lute")
	assert_bool(bool(wrong["accepted"])).is_false()
	assert_str(str(wrong["reason"])).contains("вещь цели")
	var right: Dictionary = act.call(GoalRules.item_of(s.character))
	assert_bool(bool(right["accepted"])).override_failure_message(str(right)).is_true()
