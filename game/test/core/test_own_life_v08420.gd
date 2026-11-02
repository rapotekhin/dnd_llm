extends GdUnitTestSuite
## v0.8.4.20: «Своя жизнь» of anybody — a person works, owns land, keeps money in the bank, studies and owes by the hero's
## rules, its life a part of its own record (Life); the hero's stays untouched.

const M := "npc_mercenary"

var data: Dictionary


func before() -> void:
	data = TestUtils.data()


func _session(room: String) -> GameSession:
	var s := TestUtils.new_session()
	s.room_id = "brod-square"  # the hero is elsewhere: only the person's own room counts
	s.minute = 12 * 60
	Being.of(s, M)["at"] = room
	return s


func test_a_person_is_hired_and_works_a_shift() -> void:
	var s := _session("brod-tavern-hall")
	assert_str(JobRules.hire_why(s, data, "serve_tables", M)).is_empty()
	JobRules.hire(s, data, "serve_tables", M)
	var mine := Life.of(s, M, data)
	assert_bool(JobRules.hired(mine, "serve_tables") or (mine.get("jobs_tried", {}) as Dictionary).has("serve_tables")).is_true()
	assert_bool(JobRules.hired(s.character, "serve_tables")).is_false()
	JobRules.state(mine)["serve_tables"] = {"rank": 0, "good": 0, "shifts": 0}
	assert_str(JobRules.shift_why(s, data, "serve_tables", M)).is_empty()
	var purse := Ledger.balance(s, M)
	var gold := Ledger.balance(s)
	var liked := s.attitude("npc_innkeeper")
	JobRules.shift(s, data, "serve_tables", JobRules.hours(s, data, "serve_tables") * 60, M)
	assert_int(Ledger.balance(s, M)).is_greater(purse)
	assert_int(Ledger.balance(s)).is_equal(gold)
	assert_int(int(JobRules.state(mine)["serve_tables"]["shifts"])).is_equal(1)
	assert_int(s.attitude("npc_innkeeper")).is_equal(liked)  # what the innkeeper thinks is of the hero


func test_a_person_buys_land_and_its_days_go_on() -> void:
	var s := _session("brod-townhall")
	Ledger.add(s, 5000, "test", M)
	assert_str(PropertyRules.buy_why(s, data, "plot", M)).is_empty()
	var gold := Ledger.balance(s)
	PropertyRules.buy(s, data, "plot", M)
	var mine := Life.of(s, M, data)
	assert_bool(PropertyRules.owned(mine, "plot")).is_true()
	assert_bool(PropertyRules.owned(s.character, "plot")).is_false()
	assert_int(Ledger.balance(s)).is_equal(gold)
	assert_array(Life.holders(s, "property")).contains([Being.HERO, M])
	s.day += 3
	PropertyRules.tick(s, data)
	assert_int(int(PropertyRules.state(mine)["plot"]["last_day"])).is_equal(s.day)


func test_a_person_keeps_money_in_the_bank() -> void:
	var s := _session("brod-exchange")
	Ledger.add(s, 10000, "test", M)
	assert_str(BankRules.deposit_why(s, data, "npc_changer", "month", 5000, M)).is_empty()
	BankRules.deposit(s, data, "npc_changer", "month", 5000, M)
	var mine := Life.of(s, M, data)
	assert_int(BankRules.open_of(mine).size()).is_equal(1)
	assert_int(BankRules.open_of(s.character).size()).is_equal(0)
	s.day += 14
	BankRules.tick(s, data)
	assert_int(int(BankRules.open_of(mine)[0]["balance"])).is_greater(5000)


func test_what_a_person_learns_is_its_own() -> void:
	var s := _session("brod-school-hall")
	var w := Sheet.who(s, data, M)
	var before := Sheet.skill(s, data, w, "medicine")
	var hero_knew: Array = (s.character.get("skill_profs", []) as Array).duplicate()
	StudyRules.grant(s, data, "medicine", M)
	assert_int(Sheet.skill(s, data, Sheet.who(s, data, M), "medicine")).is_greater(before)
	assert_array(s.character.get("skill_profs", [])).is_equal(hero_knew)
	var parts := RollParts.skill(s, data, "medicine", M)
	assert_int(RollParts.sum(parts)).is_equal(Sheet.skill(s, data, Sheet.who(s, data, M), "medicine"))


func test_a_person_owes_and_its_record_keeps_its_form() -> void:
	var s := _session("brod-townhall")
	Ledger.owe(s, "tax:test", "tax", 120, "npc_clerk", M)
	assert_int(Ledger.owed(s, "tax:test", M)).is_equal(120)
	assert_int(Ledger.owed(s, "tax:test")).is_equal(0)
	assert_int(Ledger.debts(s, M).size()).is_equal(1)
	Ledger.settle(s, "tax:test", 120, M)
	assert_int(Ledger.debts(s, M).size()).is_equal(0)
	JobRules.state(Life.of(s, M, data))["serve_tables"] = {"rank": 0, "good": 0, "shifts": 0}
	StudyRules.grant(s, data, "medicine", M)
	assert_array(Being.check(s)).is_empty()


func test_the_hero_s_road_is_the_same() -> void:
	var s := _session("brod-tavern-hall")
	s.room_id = "brod-tavern-hall"
	assert_str(JobRules.hire_why(s, data, "serve_tables")).is_equal(JobRules.hire_why(s, data, "serve_tables", Being.HERO))
	assert_object(Life.of(s, Being.HERO)).is_same(s.character)
	assert_str(Life.room(s, data, Being.HERO)).is_equal(s.room_id)
	assert_str(Life.owner(Being.HERO)).is_equal(OwnerRules.HERO)
	assert_str(Life.owner(M)).is_equal(M)
