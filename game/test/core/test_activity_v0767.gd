extends GdUnitTestSuite
## One occupation (v0.7.67): a check, a step of a ladder, one line; progress to a term; what a job, a course and an office
## ask read in one place; a group of people read in one place.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _hero() -> GameSession:
	var s := TestUtils.new_session()
	for p: Dictionary in data["presets"]:
		if p["id"] == "fighter_aira":
			s.character = GameSession.normalized_character(CharacterBuilder.build_preset(p, data))
	CharacterRules.refresh(s.character, data, s.items)
	s.room_id = "brod-tavern-hall"
	return s


func test_a_step_of_a_ladder_is_the_last_reached() -> void:
	var ladder := [{"from": -99, "id": "bad", "name": "плохо"}, {"from": 0, "id": "ok", "name": "сносно"}, {"from": 5, "id": "good", "name": "хорошо"}]
	assert_str(str(Activity.step(ladder, -3)["id"])).is_equal("bad")
	assert_str(str(Activity.step(ladder, 0)["id"])).is_equal("ok")
	assert_str(str(Activity.step(ladder, 7)["id"])).is_equal("good")


func test_an_attempt_rolls_and_says_the_line() -> void:
	var s := _hero()
	var ladder: Array = data["rules"]["jobs"]["outcomes"]
	var a := Activity.attempt(s, data, {"what": "Смена", "label": "Атлетика", "skill": "athletics", "dc": 10, "ladder": ladder})
	assert_str(str(a["line"])).contains("Смена: Атлетика")
	assert_str(str(a["line"])).contains("против Сл 10")
	assert_str(str(a["line"])).contains(str(a["step"]["name"]))
	assert_int(int(a["roll"]["dc"])).is_equal(10)


func test_a_negative_bonus_reads_as_a_minus() -> void:
	assert_str(Activity.line("Урок", "", {"nat": 12, "total": 10, "dc": 11}, "неудача")).contains("12 − 2 = 10")


func test_work_counts_up_to_its_need() -> void:
	var rec := Progress.of_work(3)
	assert_bool(Progress.add(rec, 2)).is_false()
	assert_int(Progress.left(rec)).is_equal(1)
	assert_int(Progress.percent(rec)).is_equal(66)
	assert_bool(Progress.add(rec, 0, 2)).is_true()  # the term came nearer


func test_what_is_due_leaves_the_list() -> void:
	var list: Array = [Progress.by_day(3).merged({"up": "a"}), Progress.by_day(9).merged({"up": "b"})]
	var due := Progress.take_due(list, 5)
	assert_int(due.size()).is_equal(1)
	assert_str(str(due[0]["up"])).is_equal("a")
	assert_int(list.size()).is_equal(1)


func test_a_course_and_a_craft_stand_on_progress() -> void:
	var s := _hero()
	for id: String in data["world"].get("courses", {}):
		s.character["study"] = {"courses": {}, "done": [], "schools": {}}
		StudyRules.state(s.character)["courses"][id] = StudyRules._new_course(s, data, id)
		assert_int(int(StudyRules.state(s.character)["courses"][id]["need"])).is_equal(StudyRules.lessons_needed(s, data, id))
		break


func test_require_reads_the_rows_of_all_three() -> void:
	var s := _hero()
	s.character["level"] = 2
	var rows := Require.rows(s, data, {"level": 3, "language": "dwarvish", "reputation": 1, "served": 2}, {"location": "brod"})
	assert_int(rows.size()).is_equal(4)
	assert_bool(rows.any(func(r: Dictionary) -> bool: return str(r["text"]) == "уровень 3" and not bool(r["ok"]))).is_true()
	assert_bool(Require.met(rows)).is_false()
	assert_bool(Require.met(Require.rows(s, data, {"level": 2}))).is_true()


func test_a_job_says_true_and_an_office_says_which() -> void:
	var s := _hero()
	var by_job := Require.rows(s, data, {"skill": true}, {"skill": "stealth"})
	var by_office := Require.rows(s, data, {"skill": "stealth"})
	assert_str(str(by_job[0]["text"])).is_equal(str(by_office[0]["text"]))
	assert_array(Require.rows(s, data, {"skill": false}, {"skill": "stealth"})).is_empty()


func test_a_recommendation_stands_for_a_row() -> void:
	var s := _hero()
	var row: Dictionary = Require.rows(s, data, {"reputation": 3}, {"location": "brod", "waive": {"reputation": "Бруно"}})[0]
	assert_bool(bool(row["ok"])).is_true()
	assert_str(str(row["text"])).contains("рекомендация: Бруно")


func test_a_faction_reads_as_a_group() -> void:
	var s := _hero()
	var g := Group.view(s, data, "brod_folk")
	assert_str(str(g["kind"])).is_equal("settlement")
	assert_bool((g["members"] as Array).has("npc_innkeeper")).is_true()
	assert_dict(Group.view(s, data, "no_such")).is_empty()


func test_an_organization_gives_its_ranks() -> void:
	var s := _hero()
	var g := Group.view(s, data, "night_rats")
	assert_bool((g["ranks"] as Array).is_empty()).is_false()
	assert_int(int(g["rank"])).is_equal(-1)  # not a member


func test_the_family_and_the_party_read_alike() -> void:
	var s := _hero()
	Being.follow(s, "npc_innkeeper")
	var party := Group.view(s, data, Group.PARTY)
	assert_str(str(party["head"])).is_equal(OwnerRules.HERO)
	assert_array(party["members"]).contains(["npc_innkeeper"])
	assert_array(Group.view(s, data, Group.FAMILY)["members"]).is_empty()


func test_a_town_with_a_treasury_shows_it() -> void:
	var s := _hero()
	TestUtils.system_on(data, "office")  # offices are out of the game (v0.8.4.39), their road stays
	OfficeRules.town(s, data, "brod")["treasury"] = 1234
	assert_int(int(Group.view(s, data, "brod_folk")["treasury_cp"])).is_equal(1234)
