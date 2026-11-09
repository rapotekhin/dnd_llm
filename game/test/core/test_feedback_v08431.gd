extends GdUnitTestSuite
## The author's feedback of 2026-11-06 (roadmap v0.8.4.31).

var data: Dictionary
var s: GameSession
var fx: EffectEngine


func before_test() -> void:
	data = TestUtils.data().duplicate(true)
	s = TestUtils.new_session()
	s.room_id = "pushcha-trail"
	fx = EffectEngine.new()


func _place(spec: Dictionary, turn := "t-1") -> Dictionary:
	fx.searched_places[turn] = true
	var e := spec.duplicate(true)
	e["kind"] = "create"
	e["what"] = "place"
	var r := fx.validate(s, data, turn, e)
	if bool(r["accepted"]):
		fx.apply(s, turn, [r["effect_id"]])
	return r


func _glade(name: String) -> Dictionary:
	return {"edge": 0, "rooms": [{"key": "a", "name": name, "description": "Поляна.", "exits": []}]}


# --- people of made rooms ---------------------------------------------------------------------------------------


func test_a_made_person_stays_when_the_next_place_is_made() -> void:
	assert_bool(bool(_place(_glade("Южная вырубка"))["accepted"])).is_true()
	var room := str(s.generated["edge_exits"]["pushcha-trail"][0])
	WorldGen.generated(s)["npcs"]["gen_npc_t"] = {"name": "Тихон Рябой", "role": "лесоруб"}
	data["world"]["npcs"]["gen_npc_t"] = {"name": "Тихон Рябой", "role": "лесоруб"}
	WorldGen.place_npc(s, data, "gen_npc_t", room)
	assert_array(data["world"]["rooms"][room]["npcs"]).contains(["gen_npc_t"])
	assert_bool(bool(_place(_glade("Овраг"), "t-2")["accepted"])).is_true()
	assert_array(data["world"]["rooms"][room]["npcs"]).contains(["gen_npc_t"])
	assert_str(Where.npc_room(s, data, "gen_npc_t")).is_equal(room)


# --- a weapon thrown and picked up ------------------------------------------------------------------------------


func _armed_with_dagger() -> void:
	ItemRules.add(s.character, "dagger", 1)
	s.character["equipped"]["main_hand"] = "dagger"
	CharacterRules.refresh(s.character, data, s.items)


func _hero_turn() -> void:
	s.combat["turn"] = (s.combat["order"] as Array).find(CombatRules.PLAYER)
	s.combat["current"] = CombatRules.PLAYER
	CombatRules.player(s).erase("points")


func test_a_dagger_is_struck_or_thrown_by_its_own_button_and_lies_where_it_fell() -> void:
	_armed_with_dagger()
	var had := int(s.character["inventory"].get("dagger", 0))
	TestUtils.fight(s, data, [{"monster": "goblin", "col": 1}])
	_hero_turn()
	var hero := CombatRules.player(s)
	var foe := TestUtils.foe(s, 1)
	assert_str(Acts.one("attack").can(s, data, hero, foe, {})).is_equal("COMBAT_OUT_OF_REACH")  # no throw by a blow's button
	assert_str(Acts.one("attack").can(s, data, hero, foe, {"throw": true})).is_equal("")
	var lines := Acts.one("attack").go(s, data, hero, foe, {"throw": true})
	assert_str(" ".join(lines)).contains("(бросок)")
	assert_int(int(s.character["inventory"].get("dagger", 0))).is_equal(had - 1)
	assert_dict(Gear.left_on_field(s)).contains_key_value("dagger", 1)
	var at := Vector2i(int(s.combat["dropped"][0]["x"]), int(s.combat["dropped"][0]["y"]))
	assert_that(at).is_equal(FightGrid.cell(CombatRules.fighter(s, foe)))
	FightGrid.put(hero, at + Vector2i(-1, 0))
	_hero_turn()
	assert_str(Acts.one("pick_up").can(s, data, hero, "", {})).is_equal("")
	Acts.one("pick_up").go(s, data, hero, "", {})
	assert_int(int(s.character["inventory"].get("dagger", 0))).is_equal(had)
	assert_str(str(s.character["equipped"].get("main_hand", ""))).is_equal("dagger")
	assert_dict(Gear.left_on_field(s)).is_empty()
	assert_str(Acts.one("pick_up").can(s, data, hero, "", {})).is_not_empty()


func test_a_foe_beside_strikes_with_its_dagger_and_throws_it_only_from_afar() -> void:
	TestUtils.fight(s, data, [{"monster": "goblin", "col": 0}])
	var f := CombatRules.fighter(s, TestUtils.foe(s, 1))
	var throws := Acts.one("attack").offers(s, data, f, [CombatRules.player(s)]).filter(func(o: Dictionary) -> bool: return bool(o["how"].get("throw", false)))
	assert_array(throws).is_empty()


# --- a quest goes on after a failed step ------------------------------------------------------------------------


func _quest_with_a_find(qid: String) -> void:
	var room := s.room_id
	data["world"]["rooms"][room]["secrets"] = [{"id": "trace", "dc": 15, "text": "следы поджигателей", "skill": "perception"}]
	var q := {"title": "Пепел", "difficulty": "easy", "xp": 100, "reward_cp": 1000, "giver": "", "own": true,
		"acts": [{"title": "Гарь", "goal": "осмотреть пепелище"}, {"title": "Логово", "goal": "найти поджигателей"}], "built": 1,
		"steps": [{"text": "Найти следы на пепелище", "when": {"secret": "%s:trace" % room}, "act": 0},
			{"text": "Расспросить торговку", "when": {"arrive": "brod-market"}, "act": 0}]}
	WorldGen.generated(s)["quests"] = {qid: q}
	data["world"]["quests"][qid] = q.duplicate(true)
	s.quests_active[qid] = 0


func test_a_missed_secret_of_a_step_turns_its_act_to_the_failure() -> void:
	_quest_with_a_find("gen_quest_t")
	Knows.add(s, Knows.SECRET, s.room_id, "trace")  # found by the check: no failure
	assert_array(QuestRules.missed(s, data, "perception")).is_empty()
	s.knows.erase(Knows.SECRET)
	assert_array(QuestRules.missed(s, data, "athletics")).is_empty()  # not a search for it
	var lines := QuestRules.missed(s, data, "perception")
	assert_str(" ".join(lines)).contains("пойдёт иначе")
	var q: Dictionary = WorldGen.generated(s)["quests"]["gen_quest_t"]
	assert_int(int(q["built"])).is_equal(0)
	assert_int((q["steps"] as Array).size()).is_equal(1)
	assert_array(QuestRules.awaiting(s, data["world"])).contains(["gen_quest_t"])
	assert_str(" ".join(QuestRules.history(s, data["world"], "gen_quest_t"))).contains("✗ Найти следы")
	assert_str(QuestGen.act_frame(s, data, "gen_quest_t")).contains("ПРОВАЛ ШАГА")


func test_the_act_of_a_failure_is_readied_ahead_and_laid_when_it_happens() -> void:
	_quest_with_a_find("gen_quest_t")
	var sb := PrepareRules.setback_preview(s, data, "gen_quest_t")
	assert_int(int(sb["act"])).is_equal(0)
	assert_str(QuestGen.act_frame(s, data, "gen_quest_t", sb)).contains("ПРОВАЛ ШАГА")
	var jobs := PrepareRules.jobs(s, data).filter(func(j: Dictionary) -> bool: return j.has("setback"))
	assert_array(jobs).has_size(1)
	assert_str(str(jobs[0]["key"])).is_equal("gen_quest_t:1!0")
	PrepareRules.keep(s, data, jobs[0], [{"kind": "quest_act", "quest_id": "gen_quest_t", "act": 1}])
	QuestRules.setback(s, data, "gen_quest_t", "find")
	assert_dict(PrepareRules.act_of(s, "gen_quest_t", 1)).contains_key_value("act", 1)


func test_only_an_act_after_a_failure_may_end_the_quest_or_cut_its_reward() -> void:
	_quest_with_a_find("gen_quest_t")
	s.quests_active["gen_quest_t"] = 2  # both steps done: the second act waits
	var r := QuestGen.plan_act(s, data, {"quest_id": "gen_quest_t", "act": 2, "ends": "fail",
		"steps": [{"text": "Уйти ни с чем", "kind": "visit", "target": "brod-market"}]})
	assert_str(str(r.get("reason", ""))).contains("после провала")


func test_a_dead_end_fails_the_quest_at_its_last_step() -> void:
	_quest_with_a_find("gen_quest_t")
	var q: Dictionary = WorldGen.generated(s)["quests"]["gen_quest_t"]
	q["steps"][0]["fail_end"] = true
	data["world"]["quests"]["gen_quest_t"] = q.duplicate(true)
	QuestRules._complete_step(s, data, "gen_quest_t")
	assert_array(s.quests_failed).contains(["gen_quest_t"])
	assert_bool(s.quests_active.has("gen_quest_t")).is_false()


# --- the map of a made place ------------------------------------------------------------------------------------


func test_an_open_made_place_takes_its_lands_kind_for_its_map() -> void:
	assert_bool(bool(_place(_glade("Опушка"))["accepted"])).is_true()
	var room := str(s.generated["edge_exits"]["pushcha-trail"][0])
	var v := WorldView.new(data["world"])
	var terrain := str(v.location(v.location_id(room)).get("terrain", ""))
	var want := str(LayoutRules.lib(data)["terrains"].get(terrain, LayoutRules.lib(data)["terrains"]["default"]))
	assert_str(LayoutRules.kind_of(v, data, room)).is_equal(want)
	assert_bool((LayoutRules.lib(data)["kinds"] as Dictionary).has(want)).is_true()
