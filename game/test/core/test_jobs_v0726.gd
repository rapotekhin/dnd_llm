extends GdUnitTestSuite
## Work (v0.7.26): jobs of the pack's employers with requirements, an interview against the employer, shifts only
## while the employer is here, the pay by the check's margin, a promotion after good shifts, the direction «Работа»,
## the master's job.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _worker() -> GameSession:
	var s := TestUtils.new_session()
	s.settings["needs"] = false
	s.room_id = "brod-tavern-hall"
	s.minute = 12 * 60
	s.character["gold_cp"] = 0
	return s


func _sure(s: GameSession, skill: String) -> void:
	s.character["skills"][skill] = 40  # every roll but a 1 wins


func test_the_employers_jobs() -> void:
	var s := _worker()
	assert_array(JobRules.of(s, data, "npc_innkeeper")).contains(["serve_tables"])
	assert_array(JobRules.of(s, data, "npc_smith")).contains(["smith_apprentice"])
	assert_array(JobRules.of(s, data, "npc_veteran")).is_empty()


func test_requirements_and_the_employer_here() -> void:
	var s := _worker()
	assert_str(JobRules.hire_why(s, data, "serve_tables")).is_empty()
	assert_str(JobRules.hire_why(s, data, "smith_apprentice")).is_equal("JOB_EMPLOYER_AWAY")
	s.room_id = "brod-smithy"
	s.character["tools"] = []
	assert_str(JobRules.hire_why(s, data, "smith_apprentice")).is_equal("JOB_REQUIREMENTS")
	s.character["tools"] = ["smiths_tools"]
	assert_str(JobRules.hire_why(s, data, "smith_apprentice")).is_empty()


func test_a_failed_interview_waits_a_day() -> void:
	var s := _worker()
	s.character["skills"]["persuasion"] = -40
	var lines := JobRules.hire(s, data, "serve_tables")
	assert_bool(JobRules.hired(s.character, "serve_tables")).is_false()
	assert_str(" ".join(lines)).contains("завтра")
	assert_str(JobRules.hire_why(s, data, "serve_tables")).is_equal("JOB_TRIED")
	s.day += 1
	assert_str(JobRules.hire_why(s, data, "serve_tables")).is_empty()


func test_a_good_shift_pays_and_counts() -> void:
	var s := _worker()
	_sure(s, "persuasion")
	JobRules.hire(s, data, "serve_tables")
	assert_bool(JobRules.hired(s.character, "serve_tables")).is_true()
	var r := JobRules.shift(s, data, "serve_tables", 360)
	assert_int(int(s.character["gold_cp"])).is_greater_equal(20)
	assert_int(int(JobRules.state(s.character)["serve_tables"]["good"])).is_between(0, 1)
	assert_str(" ".join(r["lines"])).contains("Плата")
	assert_int(DevelopmentRules.xp(s.character, "work")).is_greater(0)


func test_a_bad_shift_pays_half_and_sours_the_employer() -> void:
	var s := _worker()
	_sure(s, "persuasion")
	JobRules.hire(s, data, "serve_tables")
	s.character["skills"]["persuasion"] = -40
	var before := s.attitude("npc_innkeeper")
	JobRules.shift(s, data, "serve_tables", 360)
	assert_int(int(s.character["gold_cp"])).is_equal(10)
	assert_int(s.attitude("npc_innkeeper")).is_equal(before - 1)


func test_a_broken_shift_pays_its_share_without_a_check() -> void:
	var s := _worker()
	_sure(s, "persuasion")
	JobRules.hire(s, data, "serve_tables")
	JobRules.shift(s, data, "serve_tables", 180)
	assert_int(int(s.character["gold_cp"])).is_equal(10)
	assert_int(int(JobRules.state(s.character)["serve_tables"]["shifts"])).is_equal(0)


func test_promotion_after_good_shifts() -> void:
	var s := _worker()
	_sure(s, "persuasion")
	JobRules.hire(s, data, "serve_tables")
	var before := s.attitude("npc_innkeeper")
	JobRules.state(s.character)["serve_tables"]["good"] = JobRules.promote_after(s, data) - 1
	var lines: Array[String] = []
	for i in 3:  # a natural 1 may spoil one
		if JobRules.rank(s.character, "serve_tables") == 0:
			lines.append_array(JobRules.shift(s, data, "serve_tables", 360)["lines"])
	assert_int(JobRules.rank(s.character, "serve_tables")).is_equal(1)
	assert_str(" ".join(lines)).contains("Повышение: старший подавальщик")
	assert_int(JobRules.pay(s, data, "serve_tables")).is_equal(30)
	assert_int(JobRules.dc(s, data, "serve_tables")).is_equal(12)
	assert_int(s.attitude("npc_innkeeper")).is_greater_equal(before)


func test_shifts_only_while_the_employer_is_here() -> void:
	var s := _worker()
	_sure(s, "persuasion")
	JobRules.hire(s, data, "serve_tables")
	s.room_id = "brod-square"
	assert_str(JobRules.shift_why(s, data, "serve_tables")).is_equal("JOB_EMPLOYER_AWAY")


func test_the_direction_raises_the_pay() -> void:
	var s := _worker()
	_sure(s, "persuasion")
	JobRules.hire(s, data, "serve_tables")
	DevelopmentRules.state(s.character, "work")["skills"] = ["valued"]
	assert_int(JobRules.pay(s, data, "serve_tables")).is_equal(22)


func test_a_tool_job_checks_the_tool() -> void:
	var s := _worker()
	s.room_id = "brod-tavern-kitchen"
	assert_str(JobRules.hire_why(s, data, "kitchen_help")).is_empty()
	assert_int(JobRules.shift_chance(s, data, "kitchen_help")).is_between(5, 100)


func test_the_master_makes_a_job_and_the_hero_sees_it() -> void:
	var s := _worker()
	var engine := EffectEngine.new()
	var dear := engine.validate(s, data, "t-1", {"kind": "job", "employer_id": "npc_innkeeper", "name": "Вышибала", "skill": "athletics",
		"hours": 6, "dc_tier": "easy", "pay_cp": 500})
	assert_bool(bool(dear["accepted"])).is_false()
	var away := engine.validate(s, data, "t-1", {"kind": "job", "employer_id": "npc_smith", "name": "Молотобоец", "skill": "athletics",
		"hours": 6, "dc_tier": "easy", "pay_cp": 20})
	assert_bool(bool(away["accepted"])).is_false()
	var r := engine.validate(s, data, "t-1", {"kind": "job", "employer_id": "npc_innkeeper", "name": "Вышибала", "skill": "athletics",
		"hours": 6, "dc_tier": "easy", "pay_cp": 20, "ranks": ["вышибала", "старший вышибала", "начальник охраны"]})
	assert_bool(bool(r["accepted"])).override_failure_message(str(r.get("reason", ""))).is_true()
	engine.apply(s, "t-1", [r["effect_id"]])
	var mine := JobRules.of(s, data, "npc_innkeeper").filter(func(id: String) -> bool: return str(JobRules.job(s, data, id)["name"]) == "Вышибала")
	assert_array(mine).has_size(1)
	_sure(s, "persuasion")
	JobRules.hire(s, data, mine[0])
	assert_str(str(TurnSnapshot.build(s, data, 1000)["character"]["jobs"])).contains("Вышибала — вышибала, наниматель Бруно")
