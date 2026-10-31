extends GdUnitTestSuite
## One language of conditions, one store of what the hero knows, one record of what happened (v0.7.68).

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _session() -> GameSession:
	var s := TestUtils.new_session()
	s.room_id = "brod-tavern-hall"
	return s


func test_a_condition_reads_a_flag_and_a_quest() -> void:
	var s := _session()
	assert_bool(Cond.met(s, {"flag": "x"})).is_false()
	assert_bool(Cond.met(s, {"not_flag": "x"})).is_true()
	s.flags.append("x")
	assert_bool(Cond.met(s, {"flag": "x"})).is_true()
	s.quests_active["q"] = {}
	assert_bool(Cond.met(s, {"quest": "q"})).is_true()
	assert_bool(Cond.met(s, {"quest_done": "q"})).is_false()
	s.quests_done.append("q")
	assert_bool(Cond.met(s, {"all": [{"flag": "x"}, {"quest_done": "q"}]})).is_true()
	assert_bool(Cond.met(s, {"any": [{"flag": "y"}, {"not_flag": "x"}]})).is_false()


func test_a_record_without_a_condition_always_holds() -> void:
	var s := _session()
	assert_bool(Cond.holds(s, {"text": "дверь"})).is_true()
	assert_bool(Cond.holds(s, {"when": {"flag": "x"}})).is_false()


func test_a_room_and_a_trader_read_the_same_language() -> void:
	var s := _session()
	var w: Dictionary = data["world"].duplicate(true)
	w["rooms"][s.room_id]["variants"] = [{"when": {"quest": "q"}, "description": "занято"}]
	assert_str(str(SceneRules.room(s, w, s.room_id)["description"])).is_not_equal("занято")
	s.quests_active["q"] = {}
	assert_str(str(SceneRules.room(s, w, s.room_id)["description"])).is_equal("занято")
	var d := data.duplicate()
	d["world"] = w
	w["npcs"]["npc_merchant"]["trade_variants"] = [{"when": {"not_flag": "war"}, "price_pct": 150}]
	assert_int(int(TradeRules.variant(s, d, "npc_merchant")["price_pct"])).is_equal(150)
	s.flags.append("war")
	assert_int(int(TradeRules.variant(s, d, "npc_merchant")["price_pct"])).is_equal(100)


func test_requires_asks_any_condition() -> void:
	var s := _session()
	var req := {"when": {"quest": "q"}, "when_text": "задание взято"}
	var row: Dictionary = Require.rows(s, data, req)[0]
	assert_str(str(row["text"])).is_equal("задание взято")
	assert_bool(bool(row["ok"])).is_false()
	s.quests_active["q"] = {}
	assert_bool(bool(Require.rows(s, data, req)[0]["ok"])).is_true()


func test_the_pack_has_no_old_conditions() -> void:
	var text := JSON.stringify(data["world"])
	assert_bool(text.contains("if_flag") or text.contains("if_not_flag") or text.contains("if_quest")).is_false()
	assert_array(WorldPack.validate(WorldPack.load_bundle("res://data/worlds/frontier", "builtin"), data)).is_empty()


func test_a_flag_of_a_variant_may_be_set_by_the_master() -> void:
	assert_bool(QuestRules.known_flags(data["world"]).has("menhir_power")).is_true()


func test_knowing_is_one_store() -> void:
	var s := _session()
	assert_bool(Knows.add(s, Knows.SECRET, "room", "a")).is_true()
	assert_bool(Knows.add(s, Knows.SECRET, "room", "a")).is_false()
	Knows.add(s, Knows.SECRET, "room", "b")
	Knows.add(s, Knows.SECRET, "other", "c")
	assert_array(Knows.under(s, Knows.SECRET, "room")).contains_exactly(["a", "b"])
	assert_bool(Knows.has(s, Knows.SECRET, "other:c")).is_true()  # a condition names it whole
	assert_bool(Cond.met(s, {"secret": "room:b"})).is_true()
	assert_bool(Knows.has(s, Knows.MONSTER, "wolf")).is_false()


func test_what_is_known_comes_back_from_a_save() -> void:
	var s := _session()
	Knows.add(s, Knows.FENCE, "npc_merchant")
	Knows.add(s, Knows.LIKES, "npc_innkeeper", "drink")
	var back := GameSession.from_dict(JSON.parse_string(JSON.stringify(s.to_dict(10))))
	assert_bool(FenceRules.known(back, data, "npc_merchant") or Knows.has(back, Knows.FENCE, "npc_merchant")).is_true()
	assert_array(BondRules.known(back, "npc_innkeeper")["likes"]).contains_exactly(["drink"])


func test_a_fact_keeps_its_moment() -> void:
	var s := _session()
	s.day = 3
	s.minute = 9 * 60 + 5
	var f := Fact.of(s, "случилось", s.room_id)
	assert_int(Fact.day(f)).is_equal(3)
	assert_str(Fact.clock(f)).is_equal("09:05")


func test_the_records_read_alike() -> void:
	var s := _session()
	s.day = 4
	s.minute = 600
	s.append(GameSession.effect_entry(["Что-то случилось"] as Array[String]))
	s.remember("npc_innkeeper", "герой помог")
	ObjectRules.note(s, "brod-tavern", "открыта вновь")
	var mem: Dictionary = Being.view(s, "npc_innkeeper")["memory"][0]
	for f: Dictionary in [s.chronicle[0], mem]:
		assert_int(Fact.day(f)).is_equal(4)
		assert_str(Fact.clock(f)).is_equal("10:00")
		assert_str(str(f["room"])).is_equal(s.room_id)
	assert_array(ObjectRules.facts(s, "brod-tavern")).contains_exactly(["день 4: открыта вновь"])
	assert_array(s.memory_of("npc_innkeeper")).contains_exactly(["день 4 — герой помог"])


func test_the_master_never_sees_the_truth_of_a_rumour() -> void:
	var s := _session()
	var lie := RumorRules.add(s, data, {"text": "в реке живёт дракон и ест овец", "weight": 3, "origin": "brod", "truth": false})
	assert_bool(bool(lie["truth"])).is_false()  # the engine knows
	assert_bool(Fact.told(lie).has("truth")).is_false()
	assert_bool(Fact.told(lie).has("text")).is_true()
	var seen := " ".join(RumorRules.snapshot(s, data))
	assert_str(seen).contains("дракон")
	assert_str(seen.to_lower()).not_contains("лож")
	assert_str(seen.to_lower()).not_contains("правд")


func test_a_rumour_heard_is_known() -> void:
	var s := _session()
	var r := RumorRules.add(s, data, {"text": "у мельника новая лодка на реке", "weight": 1, "origin": "brod"})
	assert_bool(RumorRules.heard(s, str(r["id"]))).is_false()
	RumorRules.hear(s, data, [r["id"]])
	assert_bool(RumorRules.heard(s, str(r["id"]))).is_true()
	assert_array(Knows.all(s, Knows.RUMOR)).contains([str(r["id"])])
