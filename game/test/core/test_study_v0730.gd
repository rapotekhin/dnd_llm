extends GdUnitTestSuite
## Study (v0.7.30): the school's exam and its stipend, enrolment by the fee, lessons once a day while the teacher is
## here, the end of a course — the skill, the class experience and the diploma; the dorm's bed and chest; misses and
## expulsion; a book read anywhere; a spell course only for its casters; a diploma opens a job; the master's course.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _hero(room: String = "brod-school-hall") -> GameSession:
	var s := TestUtils.new_session()
	s.settings["needs"] = false
	s.room_id = room
	s.minute = 10 * 60
	s.character["gold_cp"] = 100000
	s.rested_at = TimeRules.abs_minute(s) + 60 * 1440
	s.character["skills"]["history"] = 30
	(s.character.get("skill_profs", []) as Array).erase("history")
	return s


func _admit(s: GameSession) -> void:
	StudyRules.state(s.character)["schools"]["brod_school"] = {"since": s.day, "stipend": false}


## Lessons day by day until the course ends (the teacher here at 10:00).
func _finish(s: GameSession, id: String, days: int = 20) -> void:
	for i in days:
		if not StudyRules.enrolled(s.character, id):
			return
		s.minute = 10 * 60
		StudyRules.lesson(s, data, id, StudyRules.lesson_hours(data) * 60)
		TimeRules.advance(s, data, 1440)


func test_the_exam_admits_or_waits() -> void:
	var s := _hero()
	assert_str(StudyRules.enroll_why(s, data, "letters")).is_equal("STUDY_NEED_EXAM")
	assert_str(StudyRules.exam_why(s, data, "brod_school")).is_empty()
	var lines := StudyRules.exam(s, data, "brod_school")
	if StudyRules.admitted(s.character, "brod_school"):
		assert_str(StudyRules.exam_why(s, data, "brod_school")).is_equal("STUDY_ADMITTED")
	else:
		assert_str(StudyRules.exam_why(s, data, "brod_school")).is_equal("STUDY_TRIED")
	assert_str(" ".join(lines)).contains("экзамен")


func test_a_stipend_makes_the_school_free() -> void:
	var s := _hero()
	assert_int(StudyRules.fee(s, data, "letters")).is_equal(400)
	StudyRules.state(s.character)["schools"]["brod_school"] = {"since": 1, "stipend": true}
	assert_int(StudyRules.fee(s, data, "letters")).is_equal(0)


func test_a_course_teaches_the_skill_and_gives_a_diploma() -> void:
	var s := _hero()
	_admit(s)
	assert_str(StudyRules.enroll_why(s, data, "letters")).is_empty()
	StudyRules.enroll(s, data, "letters")
	assert_int(int(s.character["gold_cp"])).is_equal(100000 - 400)
	StudyRules.lesson(s, data, "letters", StudyRules.lesson_hours(data) * 60)
	assert_str(StudyRules.lesson_why(s, data, "letters")).is_equal("STUDY_DONE_TODAY")
	var xp := int(s.character.get("xp", 0))
	_finish(s, "letters")
	assert_bool(StudyRules.done(s.character, "letters")).is_true()
	assert_bool((s.character["skill_profs"] as Array).has("history")).is_true()
	assert_int(int(s.character["xp"])).is_equal(xp + 50)
	assert_bool(StudyRules.has_diploma(s.character, "letters")).is_true()
	assert_int(DevelopmentRules.xp(s.character, "study")).is_greater(0)


func test_the_dorm_is_the_students_while_studying() -> void:
	var s := _hero()
	_admit(s)
	assert_str(SiteRules.unwelcome(s, data, "brod-school-dorm")).is_equal("npc_teacher")
	StudyRules.enroll(s, data, "letters")
	assert_str(SiteRules.unwelcome(s, data, "brod-school-dorm")).is_empty()
	var chest: Dictionary = (s.props["brod-school-dorm"] as Array)[0]
	chest["contents"]["silver_ring"] = 2
	StudyRules.drop(s, data, "letters")
	assert_bool((s.props["brod-school-dorm"] as Array).is_empty()).is_true()
	assert_int(int(s.character["inventory"].get("silver_ring", 0))).is_greater_equal(2)


func test_misses_expel_and_close_the_school() -> void:
	var s := _hero()
	_admit(s)
	StudyRules.enroll(s, data, "letters")
	for i in 20:
		TimeRules.advance(s, data, 1440)
	assert_bool(StudyRules.enrolled(s.character, "letters")).is_false()
	assert_bool(StudyRules.admitted(s.character, "brod_school")).is_false()
	assert_str(StudyRules.exam_why(s, data, "brod_school")).is_equal("STUDY_BANNED")


func test_a_book_is_read_anywhere() -> void:
	var s := _hero("brod-square")
	assert_str(StudyRules.lesson_why(s, data, "medic_book")).is_equal("STUDY_NO_BOOK")
	(s.character.get("skill_profs", []) as Array).erase("medicine")
	s.character["skills"]["medicine"] = 30
	ItemRules.found(s.character, data, s.items, "field_medic_manual", 1)
	assert_str(StudyRules.lesson_why(s, data, "medic_book")).is_empty()
	StudyRules.lesson(s, data, "medic_book", StudyRules.lesson_hours(data) * 60)
	assert_bool(StudyRules.enrolled(s.character, "medic_book")).is_true()
	for i in 20:
		TimeRules.advance(s, data, 1440)
		if StudyRules.done(s.character, "medic_book"):
			break
		StudyRules.lesson(s, data, "medic_book", StudyRules.lesson_hours(data) * 60)
	assert_bool(StudyRules.done(s.character, "medic_book")).is_true()
	assert_bool((s.character["skill_profs"] as Array).has("medicine")).is_true()


func test_a_spell_course_is_for_its_casters() -> void:
	var s := _hero()
	_admit(s)
	s.character["spell_ability"] = ""
	assert_str(StudyRules.enroll_why(s, data, "arcane_signs")).is_equal("STUDY_REQUIREMENTS")
	s.character["class"] = "wizard"
	s.character["spell_ability"] = "int"
	s.character["slots_max"] = [2, 0, 0, 0, 0]
	assert_str(StudyRules.enroll_why(s, data, "arcane_signs")).is_empty()
	StudyRules.grant(s, data, "arcane_signs")
	assert_bool((s.character["spells"]["always"] as Array).has("detect_magic")).is_true()


func test_a_diploma_opens_the_scribes_job() -> void:
	var s := _hero("brod-townhall")
	assert_str(JobRules.hire_why(s, data, "town_scribe")).is_equal("JOB_REQUIREMENTS")
	ItemRules.found(s.character, data, s.items, "gen_diploma_letters", 1)
	s.items["gen_diploma_letters"] = {"name": "Грамота", "item_type": "gear", "value_cp": 0, "weight": 0}
	assert_str(JobRules.hire_why(s, data, "town_scribe")).is_empty()


func test_the_master_makes_a_course() -> void:
	var s := _hero("brod-smithy")
	var engine := EffectEngine.new()
	var xp := engine.validate(s, data, "t-1", {"kind": "course", "npc_id": "npc_smith", "teach_kind": "xp", "name": "Кузнечное дело", "lessons": 4, "fee_cp": 400})
	assert_bool(bool(xp["accepted"])).is_false()
	var r := engine.validate(s, data, "t-1", {"kind": "course", "npc_id": "npc_smith", "teach_kind": "tool", "teach_id": "smiths_tools",
		"name": "Кузнечное дело", "lessons": 4, "fee_cp": 400, "skill": "athletics"})
	assert_bool(bool(r["accepted"])).override_failure_message(str(r.get("reason", ""))).is_true()
	engine.apply(s, "t-1", [r["effect_id"]])
	var ids := StudyRules.of_teacher(s, data, "npc_smith")
	assert_int(ids.size()).is_equal(1)
	assert_str(StudyRules.enroll_why(s, data, ids[0])).is_empty()
	assert_str(str(TurnSnapshot.build(s, data, 1000)["character"]["study"])).contains("Кузнечное дело")
