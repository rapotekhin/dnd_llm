extends GdUnitTestSuite
## The foundation of the unified models (v0.7.60): one roll, one scale, one clock with its list of hooks, one account
## book with one kind of debt, one price with its labels.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _session() -> GameSession:
	var s := TestUtils.new_session()
	s.character["gold_cp"] = 10000
	s.character["skills"]["persuasion"] = 3
	return s


func _sources() -> Array[String]:
	var out: Array[String] = []
	var dirs: Array[String] = ["res://core", "res://autoload"]
	while not dirs.is_empty():
		var dir: String = dirs.pop_back()
		for d: String in DirAccess.get_directories_at(dir):
			dirs.append(dir.path_join(d))
		for f: String in DirAccess.get_files_at(dir):
			if f.ends_with(".gd"):
				out.append(dir.path_join(f))
	return out


# --- Roll ------------------------------------------------------------------------------------------------------------


func test_the_die_that_counts() -> void:
	var two: Array[int] = [4, 15]
	assert_int(Roll.kept(two, true, false)).is_equal(15)
	assert_int(Roll.kept(two, false, true)).is_equal(4)
	var one: Array[int] = [9]
	assert_int(Roll.kept(one, true, true)).is_equal(9)
	var rng := RandomNumberGenerator.new()
	assert_int(Roll.dice(rng, true, true).size()).is_equal(1)
	assert_int(Roll.dice(rng, true, false).size()).is_equal(2)


func test_natural_rolls_and_the_margin() -> void:
	assert_bool(Roll.succeeds(20, 21, 30)).is_true()
	assert_bool(Roll.succeeds(1, 30, 10)).is_false()
	assert_int(Roll.margin(20, 21, 30)).is_equal(5)
	assert_int(Roll.margin(1, 30, 10, 10)).is_equal(-10)
	assert_int(Roll.margin(12, 15, 10)).is_equal(5)


func test_the_chance() -> void:
	assert_int(Roll.chance(5, 15)).is_equal(55)
	assert_int(Roll.chance(5, 15, true)).is_equal(80)
	assert_int(Roll.chance(5, 15, false, true)).is_equal(30)
	assert_int(Roll.chance(5, 15, true, true)).is_equal(55)
	assert_int(Roll.chance(40, 10)).is_equal(95)
	assert_int(Roll.chance(-40, 10)).is_equal(5)


func test_a_condition_counts_in_every_check() -> void:
	var s := _session()
	ConditionRules.add(s.character, "poisoned")
	var r := Roll.hero(s, data, {"what": "Смена", "skill": "persuasion", "dc": 10})
	assert_int((r["rolls"] as Array).size()).is_equal(2)
	assert_int(int(r["nat"])).is_equal((r["rolls"] as Array).min())


func test_the_breakdown_and_the_total() -> void:
	var s := _session()
	var r := Roll.hero(s, data, {"what": "Смена", "skill": "persuasion", "dc": 10})
	assert_int(int(r["total"])).is_equal(int(r["nat"]) + RollParts.sum(r["parts"]))
	assert_str(str(s.roll_notes.back()["what"])).is_equal("Смена")


func test_inspiration_helps_a_failed_check_and_is_spent() -> void:
	var s := _session()
	s.character["skills"]["persuasion"] = -40
	FeatureUses.use(s.character, data, "bardic_inspiration", 1, s.rng)
	var used := false
	for i in 30:
		var r := Roll.hero(s, data, {"what": "Просьба", "skill": "persuasion", "dc": 10})
		if int(r["nat"]) in [1, 20]:
			continue
		used = (r["parts"] as Array).any(func(p: Dictionary) -> bool: return str(p["label"]).begins_with("Вдохновение"))
		break
	assert_bool(used).is_true()
	assert_int(FeatureRules.inspiration_die(s.character)).is_equal(0)


func test_no_die_of_twenty_outside_roll() -> void:
	for path: String in _sources():
		if path.ends_with("/roll.gd"):
			continue
		assert_bool(FileAccess.get_file_as_string(path).contains("randi_range(1, 20)")).override_failure_message(path).is_false()


# --- Scale -----------------------------------------------------------------------------------------------------------


func test_a_value_finds_its_step() -> void:
	var steps := [{"at": 0, "n": "a"}, {"at": 10, "n": "b"}, {"at": 30, "n": "c"}]
	assert_str(str(Scale.step(steps, 15)["n"])).is_equal("b")
	assert_dict(Scale.step(steps, -1)).is_empty()
	assert_str(str(Scale.step(steps, -1, "at", steps[0])["n"])).is_equal("a")
	assert_int(Scale.index(steps, 30)).is_equal(2)
	assert_int(Scale.index([0, 100, 300], 150)).is_equal(1)
	assert_int(Scale.next(steps, 10)).is_equal(30)
	assert_int(Scale.next(steps, 30)).is_equal(-1)


func test_going_down_and_both_ways() -> void:
	var down := [{"below": 50, "n": "a"}, {"below": 20, "n": "b"}]
	assert_str(str(Scale.below(down, 30)["n"])).is_equal("a")
	assert_str(str(Scale.below(down, 10)["n"])).is_equal("b")
	assert_dict(Scale.below(down, 60)).is_empty()
	var fall := [{"at": -20}, {"at": -60}]
	assert_int(int(Scale.below(fall, -20, "at", true)["at"])).is_equal(-20)
	assert_int(Scale.signed([5, 15, 40], 20)).is_equal(2)
	assert_int(Scale.signed([5, 15, 40], -50)).is_equal(-3)
	assert_array(Scale.row([[0, "x"], [5, "y"]], 7)).is_equal([5, "y"])
	assert_array(Scale.row([[2, "x"]], 1)).is_empty()


# --- the clock -------------------------------------------------------------------------------------------------------


func test_day_and_minute_are_views_of_one_clock() -> void:
	var s := _session()
	assert_int(s.clock).is_equal(480)
	assert_int(s.day).is_equal(1)
	s.day = 3
	s.minute = 100
	assert_int(s.clock).is_equal(2 * 1440 + 100)
	assert_int(TimeRules.abs_minute(s)).is_equal(s.clock)
	s.minute += 1440  # the old way of carrying still adds up
	assert_int(s.day).is_equal(4)
	assert_int(s.minute).is_equal(100)
	var back := GameSession.from_dict(s.to_dict(10))
	assert_int(back.clock).is_equal(s.clock)


func test_time_passes_a_day_at_a_time() -> void:
	var s := _session()
	var lines := TimeRules.advance(s, data, 3 * 1440)
	assert_int(s.day).is_equal(4)
	assert_int(s.minute).is_equal(480)
	assert_int(lines.filter(func(l: String) -> bool: return l.begins_with("Наступил день")).size()).is_equal(3)


func test_a_term_in_days_is_a_moment() -> void:
	assert_int(TimeRules.day_start(1)).is_equal(0)
	assert_int(TimeRules.day_start(3)).is_equal(2880)
	assert_int(TimeRules.day_of(2880)).is_equal(3)
	assert_int(TimeRules.day_of(2879)).is_equal(2)


func test_the_hooks_are_one_list_in_order() -> void:
	var ids: Array = TimeRules.registry().map(func(h: Dictionary) -> String: return str(h["id"]))
	var unique := {}
	for id: String in ids:
		unique[id] = true
	assert_int(unique.size()).is_equal(ids.size())
	assert_bool(ids.find("conditions") < ids.find("needs")).is_true()
	assert_bool(ids.find("family") < ids.find("property")).is_true()  # the family's help goes into the till before its tax
	assert_bool(ids.find("property") < ids.find("shops")).is_true()


func test_a_hook_without_its_rules_is_skipped() -> void:
	var s := _session()
	var no_doors := data.duplicate()
	no_doors["rules"] = (data["rules"] as Dictionary).duplicate()
	(no_doors["rules"] as Dictionary).erase("doors")
	assert_array(TimeRules.hooks(s, no_doors)).is_empty()


# --- Ledger ----------------------------------------------------------------------------------------------------------


func test_coins_change_with_a_cause() -> void:
	var s := _session()
	Ledger.add(s, -300, "arena:enlist")
	Ledger.add(s, 500, "arena:prize")
	Ledger.add(s, 0, "nothing")
	assert_int(Ledger.balance(s)).is_equal(10200)
	assert_int(s.ledger.size()).is_equal(2)
	assert_int(int(s.ledger[0]["at"])).is_equal(s.clock)
	assert_int(Ledger.total(s, "arena")).is_equal(200)
	var back := GameSession.from_dict(s.to_dict(10))
	assert_int(back.ledger.size()).is_equal(2)


func test_the_journal_keeps_the_last() -> void:
	var s := _session()
	for i in Ledger.KEEP + 5:
		Ledger.add(s, 1, "t")
	assert_int(s.ledger.size()).is_equal(Ledger.KEEP)


func test_a_rule_pays_through_the_book() -> void:
	var s := _session()
	s.room_id = "brod-square"
	PropertyRules.buy(s, data, "river_house")
	assert_int(Ledger.total(s, "property:buy")).is_less(0)


func test_one_kind_of_debt() -> void:
	var s := _session()
	Ledger.owe(s, "tax:river_house", "tax", 500, "registry")
	Ledger.owe(s, "tax:river_house", "tax", 100, "registry")
	Ledger.owe(s, "cut:night_rats", "cut", 40, "npc_head")
	assert_int(Ledger.owed(s, "tax:river_house")).is_equal(600)
	assert_int(Ledger.debts(s).size()).is_equal(2)
	Ledger.settle(s, "tax:river_house", 100)
	assert_int(Ledger.owed(s, "tax:river_house")).is_equal(500)
	Ledger.settle(s, "tax:river_house", 500)
	assert_int(Ledger.owed(s, "tax:river_house")).is_equal(0)
	assert_int(Ledger.debts(s).size()).is_equal(1)
	assert_int(int(GameSession.from_dict(s.to_dict(10)).character["debts"]["cut:night_rats"]["cp"])).is_equal(40)


func test_the_book_comes_back_from_a_save_unchanged() -> void:
	var s := _session()
	Ledger.add(s, 5, "bot:found")
	Ledger.owe(s, "tax:river_house", "tax", 500, "registry")
	var before := JSON.stringify(s.to_dict(10))
	var after := JSON.stringify(GameSession.from_dict(JSON.parse_string(before)).to_dict(10))
	assert_str(after).is_equal(before)


func test_a_loan_is_in_the_list_of_debts() -> void:
	var s := _session()
	BankRules.state(s.character)["contracts"].append({"id": "bk1", "kind": BankRules.LOAN, "bank": "npc_changer", "balance": 700, "start": 1, "state": BankRules.OPEN})
	var d := Ledger.debts(s)
	assert_int(d.size()).is_equal(1)
	assert_str(str(d[0]["kind"])).is_equal("loan")
	assert_int(int(d[0]["cp"])).is_equal(700)


func test_coins_are_written_only_by_the_book() -> void:
	var direct := RegEx.create_from_string("\\[\"gold_cp\"\\]\\s*[-+]?=[^=]")
	for path: String in _sources():
		if path.ends_with("/ledger.gd"):
			continue
		for line: String in FileAccess.get_file_as_string(path).split("\n"):
			if direct.search(line) == null or line.contains("heir_c[") or path.ends_with("/character_builder.gd"):
				continue
			assert_str(line).override_failure_message(path + ": " + line).is_empty()


# --- Price -----------------------------------------------------------------------------------------------------------


func test_a_price_has_its_reasons() -> void:
	var q := Price.start(1000)
	Price.mod(q, "торг", 90)
	Price.mod(q, "ничего", 100)
	Price.mod(q, "праздник", 110)
	assert_int(Price.rounded(q)).is_equal(990)
	assert_int((q["parts"] as Array).size()).is_equal(2)
	var text := Price.text(q, 990)
	assert_str(text).contains("-10% торг")
	assert_str(text).contains("+10% праздник")


func test_rounding_and_limits() -> void:
	assert_int(Price.ceiled(Price.mod(Price.start(101), "x", 50))).is_equal(51)
	assert_int(Price.floored(Price.mod(Price.start(101), "x", 50))).is_equal(50)
	assert_int(Price.share(1, 10, 1)).is_equal(1)
	var q := Price.clamp_to(Price.mod(Price.start(100), "x", 300), 10.0, 150.0, "предел")
	assert_int(Price.floored(q)).is_equal(150)
	assert_str(Price.text(q, 150)).contains("предел")


func test_the_trader_s_price_shows_the_haggle() -> void:
	var s := _session()
	var npc := "npc_merchant"
	var item := "rope_hempen"
	for id: String in data["world"]["npcs"]:
		if bool(data["world"]["npcs"][id].get("trader", false)):
			npc = id
			break
	s.room_id = str(ReputationRules.home_room(data, npc))
	item = str(TradeRules.merchant(s, data, npc)["stock"].keys()[0])
	var plain := TradeRules.buy_price(s, data, npc, item)
	TradeRules.merchant(s, data, npc)["haggle_pct"] = 10
	var q := TradeRules.buy_quote(s, data, npc, item)
	assert_int(int(q["cp"])).is_less_equal(plain)
	assert_bool((q["parts"] as Array).any(func(p: Dictionary) -> bool: return str(p["label"]) == "торг")).is_true()
