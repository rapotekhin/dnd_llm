extends GdUnitTestSuite
## The master readies ahead (v0.8.4.25, master-prefetch.md): the rooms around by the map's ways, the engine's candidates
## for a furnishing, the jobs in order, an effect kept as proposed and checked again when it is used — a furnishing on
## entering, a board's orders, a person's quest, the next act on the last step of the current one.

var data: Dictionary
var s: GameSession
var fx: EffectEngine


func before_test() -> void:
	data = TestUtils.data().duplicate(true)  # the world grows in this test only
	s = TestUtils.new_session()
	CharacterRules.refresh(s.character, data, s.items)
	s.room_id = "brod-tavern-hall"
	fx = EffectEngine.new()


## A background turn: the effects validated under the job's context and kept as the master proposed them.
func _ready_ahead(job: Dictionary, effects: Array, turn := "t-bg") -> Array[Dictionary]:
	fx.ahead[turn] = PrepareRules.ahead_of(job)
	fx.searched_quests[turn] = true
	var ids: Array = []
	for e: Dictionary in effects:
		var r := fx.validate(s, data, turn, e)
		assert_bool(bool(r["accepted"])).override_failure_message(str(r)).is_true()
		ids.append(r["effect_id"])
	var kept := fx.kept(turn, ids)
	PrepareRules.keep(s, data, job, kept)
	return kept


## What the game does when the readied effects are used: checked again under a turn of their own and applied.
func _lay(raw: Array, turn := "t-use") -> Array[String]:
	fx.searched_quests[turn] = true
	var ids: Array = []
	for e: Variant in raw:
		if e is Dictionary and not (e as Dictionary).is_empty():
			var r := fx.validate(s, data, turn, e)
			if bool(r["accepted"]):
				ids.append(r["effect_id"])
	return fx.apply(s, turn, ids)


func test_the_rooms_around_go_by_the_ways_nearest_first() -> void:
	var one := PrepareRules.around(s, data, 1)
	var two := PrepareRules.around(s, data, 2)
	assert_array(one).is_not_empty().not_contains(["brod-tavern-hall"])
	assert_array(two.slice(0, one.size())).is_equal(one)
	assert_int(two.size()).is_greater(one.size())
	for r: String in one:
		assert_bool(WayRules.open_exits(s, data["world"], s.room_id).has(r)).is_true()


func test_a_room_gets_catalog_candidates_of_its_kind_cut_to_the_count() -> void:
	var c := PrepareRules.candidates(s, data, "brod-tavern-hall")
	assert_int(c.size()).is_equal(int(PrepareRules.cfg(data)["candidates"]))
	assert_array(c).contains(["ale"])  # a tavern's own before the everyday
	var cap := int(PropRules.cfg(data)["item_value_cap_cp"])
	for id: String in c:
		assert_int(int(data["items"]["catalog"][id].get("value_cp", 0))).is_less_equal(cap)
	assert_array(PrepareRules.candidates(s, data, "brod-tavern-hall")).is_equal(c)  # the same game, the same list


func test_the_jobs_go_by_need_and_none_twice() -> void:
	var jobs := PrepareRules.jobs(s, data)
	var kinds: Array = jobs.map(func(j: Dictionary) -> String: return j["kind"])
	assert_array(kinds).contains(["furnish"])
	var rooms: Array = jobs.filter(func(j: Dictionary) -> bool: return j["kind"] == "furnish").map(func(j: Dictionary) -> String: return j["room"])
	assert_array(rooms).not_contains(["brod-tavern-hall"])
	for r: String in rooms:
		assert_bool(PrepareRules.around(s, data, 2).has(r)).is_true()
	var quests := jobs.filter(func(j: Dictionary) -> bool: return j["kind"] == "quest")
	assert_int(quests.size()).is_less_equal(int(PrepareRules.cfg(data)["quests_per_day"]))
	var again := PrepareRules.jobs(s, data, ["furnish:" + str(rooms[0])])  # asked on the line already
	assert_bool(again.any(func(j: Dictionary) -> bool: return j["kind"] == "furnish" and j["room"] == rooms[0])).is_false()
	s.combat = {"active": true}
	assert_bool(CombatRules.active(s) and not PrepareRules.jobs(s, data).is_empty()).is_false()


func test_a_furnishing_readied_ahead_is_laid_when_the_hero_enters() -> void:
	var room := PrepareRules.around(s, data, 1)[0]
	assert_bool(PropRules.needs_furnish(s, room)).is_true()
	var frame := PrepareRules.frame(s, data, {"kind": "furnish", "room": room})
	assert_str(frame).starts_with("[prepare furnish | room %s]" % room).contains("Кандидаты")
	var job := {"kind": "furnish", "key": room, "room": room}
	_ready_ahead(job, [{"kind": "furnish", "props": [{"name": "Лавка", "body": "bench"}, {"name": "Свеча", "item_id": "candle"}]}])
	assert_bool(PropRules.needs_furnish(s, room)).is_true()  # kept, not laid
	assert_bool(PrepareRules.jobs(s, data).any(func(j: Dictionary) -> bool: return j["kind"] == "furnish" and j["room"] == room)).is_false()
	s.room_id = room
	var lines := _lay([PrepareRules.furnishing(s, data, room)])
	assert_array(lines).is_not_empty()
	assert_bool(PropRules.needs_furnish(s, room)).is_false()
	assert_array(PropRules.room_props(s, room).map(func(p: Dictionary) -> String: return p["name"])).contains(["Лавка", "Свеча"])
	assert_dict(PrepareRules.furnishing(s, data, room)).is_empty()  # used once


func test_a_furnishing_of_a_changed_room_is_thrown_away() -> void:
	var room := PrepareRules.around(s, data, 1)[0]
	_ready_ahead({"kind": "furnish", "key": room, "room": room}, [{"kind": "furnish", "props": [{"name": "Лавка"}]}])
	data["world"]["rooms"][room]["description"] = "Пепелище: здесь был пожар."
	assert_dict(PrepareRules.furnishing(s, data, room)).is_empty()


func test_orders_readied_for_a_board_are_put_up_when_it_is_read() -> void:
	var r0 := fx.validate(s, data, "t-b", {"kind": "furnish", "props": [{"name": "Доска объявлений", "text": "Заказы Брода"}]})
	fx.apply(s, "t-b", [r0["effect_id"]])
	var board := str(PropRules.room_props(s, s.room_id)[0]["id"])
	var job: Dictionary = PrepareRules.jobs(s, data).filter(func(j: Dictionary) -> bool: return j["kind"] == "board")[0]
	assert_str(str(job["prop"])).is_equal(board)
	s.room_id = PrepareRules.around(s, data, 1)[0]  # the hero walked away: the board is readied from afar
	var order := {"kind": "create", "what": "quest", "board_prop_id": board, "giver": "new:goat", "title": "Пропавшая коза",
		"difficulty": "easy", "description": "Коза ушла в лес.", "offer_text": "Найдите козу!",
		"new_npcs": [{"key": "goat", "name": "Дед Ермил", "role": "пастух"}], "acts": [{"title": "Поиски", "goal": "Найти козу"}]}
	_ready_ahead(job, [order])
	assert_bool(s.generated.get("quests", {}).is_empty()).is_true()
	s.room_id = "brod-tavern-hall"
	var lines := _lay(PrepareRules.orders(s, "brod-tavern-hall", board))
	assert_str(" ".join(lines)).contains("Пропавшая коза")
	assert_int(QuestGen.offered_by(s, "board:brod-tavern-hall:" + board).size()).is_equal(1)


func test_a_persons_quest_waits_for_the_question() -> void:
	var job := {"kind": "quest", "key": "npc_innkeeper", "npc": "npc_innkeeper", "room": "brod-tavern-hall"}
	assert_str(PrepareRules.frame(s, data, job)).starts_with("[prepare quest | giver npc_innkeeper]")
	_ready_ahead(job, [{"kind": "create", "what": "quest", "giver": "npc_innkeeper", "title": "Крысы в погребе", "difficulty": "easy",
		"description": "Крысы грызут мешки.", "offer_text": "Крысы в погребе, разберётесь?", "acts": [{"title": "Погреб", "goal": "Выгнать крыс"}]}])
	assert_str(str(PrepareRules.quest_of(s, "npc_innkeeper").get("offer_text", ""))).contains("Крысы")
	assert_bool(QuestGen.offered_by(s, "npc_innkeeper").is_empty()).is_true()  # nothing offered before the player asks
	assert_bool(PrepareRules.gives_work(s, data, "npc_innkeeper")).is_true()
	_lay([PrepareRules.quest_of(s, "npc_innkeeper")])
	assert_int(QuestGen.offered_by(s, "npc_innkeeper").size()).is_equal(1)
	assert_bool(PrepareRules.gives_work(s, data, "npc_innkeeper")).is_false()


func test_the_next_act_is_built_ahead_on_the_last_step_and_laid_when_it_opens() -> void:
	fx.searched_quests["t-q"] = true
	var r := fx.validate(s, data, "t-q", {"kind": "create", "what": "quest", "giver": "npc_innkeeper", "title": "Волки у просеки",
		"difficulty": "medium", "description": "Волки режут скот.", "offer_text": "Отгони волков.",
		"acts": [{"title": "Следы", "goal": "Найти логово"}, {"title": "Логово", "goal": "Отбиться от волков"}]})
	assert_bool(bool(r["accepted"])).override_failure_message(str(r)).is_true()
	fx.apply(s, "t-q", [r["effect_id"]])
	var id := str(s.generated["quests"].keys()[0])
	QuestRules.accept(s, data, id)
	var one := _lay([{"kind": "quest_act", "quest_id": id, "act": 1, "steps": [{"text": "Расспросить Миру", "kind": "talk", "target": "npc_serving"},
		{"text": "Осмотреть опушку", "kind": "visit", "target": "pushcha-edge"}]}], "t-a1")
	assert_array(one).is_not_empty()
	var two := {"kind": "quest_act", "quest_id": id, "act": 2, "encounters": [{"key": "pack", "room": "pushcha-edge", "kind": "ambush", "enemies": [{"monster": "wolf", "count": 1}]}],
		"steps": [{"text": "Расспросить Миру снова", "kind": "talk", "target": "npc_serving"}, {"text": "Отбиться от волков", "kind": "fight", "target": "pack"}]}
	assert_array(PrepareRules.jobs(s, data).filter(func(j: Dictionary) -> bool: return j["kind"] == "act")).is_empty()
	s.quests_active[id] = 1  # on the last step of the first act
	var job: Dictionary = PrepareRules.jobs(s, data)[0]
	assert_dict(job).is_equal({"kind": "act", "key": id + ":2", "quest": id})
	assert_str(PrepareRules.frame(s, data, job)).starts_with("[quest %s | act 2" % id)
	assert_bool(bool(fx.validate(s, data, "t-no", two)["accepted"])).is_false()  # not awaiting, not ahead
	fx.discard("t-no")
	_ready_ahead(job, [two])
	assert_int(int(QuestRules.quest(data["world"], id)["built"])).is_equal(1)  # kept, not built
	s.quests_active[id] = 2  # the act is done: the quest waits for the next one
	assert_array(QuestRules.awaiting(s, data["world"])).contains([id])
	_lay([PrepareRules.act_of(s, id, 2)])
	assert_int(int(QuestRules.quest(data["world"], id)["built"])).is_equal(2)
	assert_array(QuestRules.awaiting(s, data["world"])).is_empty()


func test_what_is_readied_is_kept_in_a_save() -> void:
	PrepareRules.part(s, PrepareRules.ROOMS)["brod-square"] = {"effect": {"kind": "furnish", "props": [{"name": "Лавка"}]}, "ver": "1"}
	var back := GameSession.from_dict(JSON.parse_string(JSON.stringify(s.to_dict(50))))
	assert_dict(back.prepared).is_equal(s.prepared)
