extends GdUnitTestSuite
## Teachers and recipes by words (v0.7.39.7, the author's request): a teacher is an engine concept — its SRD template,
## its trade and its own `teaches`; a spell is taught only by such a teacher, at its price, its lessons and, from the
## 3rd circle, the teacher's attitude; a course may wait at a teacher out of the scene; a quest's act brings the
## teacher the hero looks for and the course opens on reaching it.

var data: Dictionary
var s: GameSession
var fx: EffectEngine


func before_test() -> void:
	data = TestUtils.data().duplicate(true)  # the world grows in this test only
	s = TestUtils.new_session()
	s.room_id = "brod-tavern-hall"
	s.minute = 12 * 60
	fx = EffectEngine.new()


## A wizard of the 5th level: 3rd circle slots.
func _wizard() -> void:
	for p: Dictionary in data["presets"]:
		if str(p.get("id", "")) == "wizard_yalika":
			s.character = CharacterBuilder.build_preset(p, data)
	s.character["level"] = 5
	s.character["slots_max"] = [4, 3, 2]


## A mage made by the master in the smithy (not the tavern): its id.
func _mage(room := "brod-smithy") -> String:
	var p := WorldGen.plan_npc(s, data, {"name": "Ведун Орест", "role": "волшебник", "monster": "mage", "room_id": room}, true, {}, true)
	assert_bool(p.has("reason")).override_failure_message(str(p)).is_false()
	return WorldGen.apply_npc(s, data, p["plan"])


func _fireball(npc: String) -> Dictionary:
	return {"npc_id": npc, "name": "Огненный шар", "teach_kind": "spell", "teach_id": "fireball", "lessons": 2, "fee_cp": 0}


func test_what_people_of_the_world_teach_comes_from_their_template_and_trade() -> void:
	var w := WorldView.new(data["world"])
	var druid := TeachRules.of_npc(data, w.npc("npc_hermit"))
	assert_array(druid["spell_classes"]).contains_exactly(["druid"])
	assert_int(int(druid["circle"])).is_equal(2)
	var priestess := TeachRules.of_npc(data, w.npc("npc_priestess"))
	assert_array(priestess["spell_classes"]).contains_exactly(["cleric"])
	assert_int(int(priestess["circle"])).is_equal(1)
	assert_array(priestess["skills"]).contains(["religion"])
	var smith := TeachRules.of_npc(data, w.npc("npc_smith"))
	assert_int(int(smith["circle"])).is_equal(-1)
	assert_array(smith["tools"]).contains_exactly(["smiths_tools"])
	assert_str(TeachRules.text(data, w.npc("npc_smith"))).contains("ремесло")


func test_nobody_in_the_pack_teaches_fireball_and_a_commoner_never_teaches_a_spell() -> void:
	_wizard()
	assert_array(TeachRules.find(s, data, "spell", "fireball")).is_empty()
	var r := StudyRules.make(s, data, _fireball("npc_innkeeper"))
	assert_str(str(r.get("reason", ""))).contains("не учит").contains("find_teachers")
	r = StudyRules.make(s, data, {"npc_id": "npc_innkeeper", "name": "Свет", "teach_kind": "spell", "teach_id": "light", "lessons": 2, "fee_cp": 0})
	assert_bool(r.has("reason")).is_true()  # v0.7.39.7: no spell by the master's whim


func test_a_mage_of_the_world_is_found_and_teaches_fireball_at_its_price_and_conditions() -> void:
	_wizard()
	var mage := _mage()
	var found := TeachRules.find(s, data, "spell", "fireball")
	assert_int(found.size()).is_equal(1)
	assert_str(str(found[0]["id"])).is_equal(mage)
	assert_bool(bool(found[0]["here"])).is_false()
	assert_str(str(found[0]["place"])).contains("Кузн")
	var r := StudyRules.make(s, data, _fireball(mage))  # the mage is away: the course waits for the hero there
	assert_bool(r.has("reason")).override_failure_message(str(r)).is_false()
	var def: Dictionary = r["plan"]["def"]
	assert_int(int(def["lessons"])).is_equal(6)  # 2 a circle
	assert_int(int(def["fee_cp"])).is_equal(6 * 3 * 5000)  # 50 gp × circle a lesson: 900 gp
	assert_int(int(def["requires"]["attitude"])).is_equal(1)
	assert_str(str(r["summary"])).contains("ждёт у учителя")
	StudyRules.apply_make(s, data, r["plan"])
	var id := str(r["plan"]["id"])
	assert_str(StudyRules.enroll_why(s, data, id)).is_equal("STUDY_TEACHER_AWAY")
	assert_array(StudyRules.waiting(s, data)).contains_exactly([id])  # «Где учиться» in the study window
	assert_str(StudyRules.text(s, data)).contains("ждут героя: «Огненный шар» у Ведун Орест")
	s.room_id = "brod-smithy"
	s.character["gold_cp"] = 100000
	assert_str(StudyRules.enroll_why(s, data, id)).is_equal("STUDY_REQUIREMENTS")
	s.attitudes[mage] = 1
	assert_str(StudyRules.enroll_why(s, data, id)).is_equal("")
	assert_str(str(TeachRules.find(s, data, "spell", "fireball")[0]["course"])).is_equal(id)


func test_fireball_is_closed_to_a_wizard_without_the_third_circle() -> void:
	_wizard()
	s.character["slots_max"] = [4, 3]
	var mage := _mage("brod-tavern-hall")
	var r := StudyRules.make(s, data, _fireball(mage))
	StudyRules.apply_make(s, data, r["plan"])
	var lines := StudyRules.requirements(s, data, str(r["plan"]["id"]))
	assert_bool(lines.any(func(l: Dictionary) -> bool: return str(l["text"]) == "круг 3 доступен" and not bool(l["ok"]))).is_true()


func test_a_teacher_away_teaches_only_its_own_craft() -> void:
	s.character["tools"] = []
	var r := StudyRules.make(s, data, {"npc_id": "npc_smith", "name": "Кузнечное дело", "teach_kind": "tool", "teach_id": "smiths_tools", "lessons": 4, "fee_cp": 400})
	assert_bool(r.has("reason")).override_failure_message(str(r)).is_false()
	r = StudyRules.make(s, data, {"npc_id": "npc_herbalist", "name": "Кузнечное дело", "teach_kind": "tool", "teach_id": "smiths_tools", "lessons": 4, "fee_cp": 400})
	assert_str(str(r.get("reason", ""))).contains("не учит ремеслу")
	var found := TeachRules.find(s, data, "recipe", "longsword")
	assert_bool(found.any(func(x: Dictionary) -> bool: return str(x["id"]) == "npc_smith")).is_true()


func test_a_made_person_teaches_what_the_master_gave_it_but_spells_only_by_its_template() -> void:
	var p := WorldGen.plan_npc(s, data, {"name": "Писарь Лука", "role": "переписчик", "teaches": {"skills": ["history", "arcana"]}}, true)
	assert_bool(p.has("reason")).override_failure_message(str(p)).is_false()
	assert_array(TeachRules.of_npc(data, p["plan"]["npc"])["skills"]).contains(["arcana"])
	p = WorldGen.plan_npc(s, data, {"name": "Лжемаг", "role": "шарлатан", "teaches": {"spells": {"classes": ["wizard"], "max": 9}}}, true)
	assert_str(str(p.get("reason", ""))).contains("шаблон")


func test_an_act_brings_the_teacher_and_its_course_opens_on_reaching_it() -> void:
	_wizard()
	fx.searched_quests["t-1"] = true
	var r := fx.validate(s, data, "t-1", {"kind": "create_quest", "giver": "npc_innkeeper", "title": "Кто учит огню", "difficulty": "easy",
		"description": "Найти волшебника, что учит «Огненному шару».", "offer_text": "Слыхал про одного чародея.",
		"acts": [{"title": "Поиски", "goal": "Найти чародея"}]})
	assert_bool(bool(r["accepted"])).override_failure_message(str(r)).is_true()
	fx.apply(s, "t-1", [r["effect_id"]])
	var qid := str(s.generated["quests"].keys()[-1])
	QuestRules.accept(s, data, qid)
	var act := {"kind": "quest_act", "quest_id": qid, "act": 1,
		"new_npcs": [{"key": "mage", "name": "Ведун Орест", "role": "волшебник", "monster": "mage", "room_id": "brod-mill"}],
		"steps": [{"text": "Расспросить Миру о чародее", "kind": "talk", "target": "npc_serving"},
			{"text": "Найти Ореста на мельнице", "kind": "talk", "target": "new:mage"}],
		"teaches": {"npc": "new:mage", "kind": "spell", "id": "fireball", "name": "Огненный шар"}}
	var bad := act.duplicate(true)
	bad["teaches"]["npc"] = "new:nobody"
	assert_str(str(fx.validate(s, data, "t-9", bad).get("reason", ""))).contains("teaches.npc")
	var v := fx.validate(s, data, "t-9", act)
	assert_bool(bool(v["accepted"])).override_failure_message(str(v)).is_true()
	assert_str(str(v["summary"])).contains("курс у учителя")
	fx.apply(s, "t-9", [v["effect_id"]])
	var mage := ""
	for id: String in s.generated["npcs"]:
		if str(s.generated["npcs"][id]["name"]) == "Ведун Орест":
			mage = id
	var cid := StudyRules.of_teacher(s, data, mage)
	assert_int(cid.size()).is_equal(1)
	var co := StudyRules.course(s, data, cid[0])
	assert_str(str(co["requires"]["flag"])).is_equal(qid + "_teach")
	var q := QuestRules.quest(data["world"], qid)
	assert_str(str(q["steps"][1].get("flag", ""))).is_equal(qid + "_teach")
	s.flags.append(qid + "_teach")  # the talk step with the mage is done
	s.attitudes[mage] = 1
	s.room_id = "brod-mill"
	s.character["gold_cp"] = 100000
	assert_str(StudyRules.enroll_why(s, data, cid[0])).is_equal("")
