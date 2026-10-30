extends GdUnitTestSuite
## Rumours (v0.7.47): a fact spreads along the roads and reaches a neighbour after days × weight; the fame and a known
## crime travel with it — nobody in Brod knows of a deed in the Pushcha before the rumour comes; the people know
## the place's rumours (a gossip more), asked once a day, the innkeeper sells one; a tip marks the map and is checked
## on the spot; the board's notices; the master's `rumor`; the snapshot of the place's rumours only.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _session(room: String = "brod-tavern-hall") -> GameSession:
	var s := TestUtils.new_session()
	s.settings["needs"] = false
	s.room_id = room
	s.minute = 12 * 60
	RumorRules.seed(s, data)
	return s


func _crime(s: GameSession, victim: String, room: String, loc: String) -> Dictionary:
	var crime := {"id": "cr%d" % (s.crimes.size() + 1), "kind": "murder", "victim": victim, "room": room, "location": loc,
		"at": TimeRules.abs_minute(s), "witnesses": [], "known": false, "settled": false}
	s.crimes.append(crime)
	return crime


func test_the_roads_between_locations() -> void:
	var h := RumorRules.hops(data, "pushcha")
	assert_int(int(h["pushcha"])).is_equal(0)
	assert_int(int(h["brod"])).is_equal(1)
	assert_int(int(h["outpost"])).is_equal(2)  # through Brod


func test_a_rumour_arrives_after_days_by_its_weight() -> void:
	var s := _session()
	var r := RumorRules.add(s, data, {"text": "в Пуще видели белого оленя", "weight": 1, "origin": "pushcha"})
	assert_int(int(r["arrive"]["brod"])).is_equal(s.day + 3)  # one hop × 3 days for a trifle
	assert_int(int(r["arrive"]["outpost"])).is_equal(s.day + 6)
	var ids := func(loc: String) -> Array: return RumorRules.known_at(s, data, loc).map(func(x: Dictionary) -> String: return str(x["id"]))
	assert_bool(ids.call("pushcha").has(r["id"])).is_true()
	assert_bool(ids.call("brod").has(r["id"])).is_false()
	TimeRules.advance(s, data, 2 * 1440)
	assert_bool(ids.call("brod").has(r["id"])).is_false()
	TimeRules.advance(s, data, 1440)
	assert_bool(ids.call("brod").has(r["id"])).is_true()
	var big := RumorRules.add(s, data, {"text": "в Пуще упал огненный камень", "weight": 3, "origin": "pushcha"})
	assert_int(int(big["arrive"]["brod"])).is_equal(s.day + 1)  # the important news runs faster


func test_the_hero_is_not_wanted_in_brod_before_the_rumour() -> void:
	var s := _session("pushcha-glade")
	var lines := CrimeRules._known(s, data, _crime(s, "npc_hermit", "pushcha-glade", "pushcha"))
	assert_bool(s.wanted.has("pushcha")).is_false()  # no law in the forest
	assert_bool(s.wanted.has("brod")).is_false()  # Brod has not heard yet
	assert_int(ReputationRules.points(s, "brod")).is_equal(0)
	assert_str(" ".join(lines)).not_contains("розыске")
	s.room_id = "brod-square"
	var out := TimeRules.advance(s, data, 1440)  # a murder is news of weight 3: a day a hop
	assert_bool(s.wanted.has("brod")).is_true()
	assert_str(" ".join(out)).contains("дошёл слух")
	assert_str(" ".join(out)).contains("Вы в розыске")
	assert_int(ReputationRules.points(s, "brod")).is_less(0)  # its share of the bad fame


func test_a_crime_atoned_before_the_news_makes_no_wanted() -> void:
	var s := _session("pushcha-glade")
	var crime := _crime(s, "npc_hermit", "pushcha-glade", "pushcha")
	CrimeRules._known(s, data, crime)
	crime["settled"] = true
	TimeRules.advance(s, data, 2 * 1440)
	assert_bool(s.wanted.has("brod")).is_false()


func test_the_fame_of_a_deed_comes_with_its_rumour() -> void:
	var s := _session("pushcha-glade")
	ReputationRules.add(s, data, "pushcha", 6, "задание отшельника")  # the hermit's quest: no reputation in the forest
	assert_int(ReputationRules.points(s, "brod")).is_equal(0)
	TimeRules.advance(s, data, 2 * 1440)
	assert_int(ReputationRules.points(s, "brod")).is_equal(0)
	TimeRules.advance(s, data, 1440)
	assert_int(ReputationRules.points(s, "brod")).is_equal(3)  # 50% of 6 when the talk arrives
	TimeRules.advance(s, data, 5 * 1440)
	assert_int(ReputationRules.points(s, "brod")).is_equal(3)  # once
	var small: int = RumorRules._state(s)["list"].size()
	ReputationRules.add(s, data, "brod", 2, "мелочь")
	assert_int(RumorRules._state(s)["list"].size()).is_equal(small)  # below fame.min nobody talks


func test_the_pack_rumours_and_who_knows_them() -> void:
	var s := _session()
	var here := RumorRules.known_at(s, data, "brod").map(func(r: Dictionary) -> String: return str(r["id"]))
	for id: String in ["mill_coins", "tower_fire", "hollow_silver", "miners_missing", "artel_hires"]:
		assert_bool(here.has(id)).override_failure_message(id).is_true()
	var bruno := RumorRules.known_by(s, data, "npc_innkeeper").map(func(r: Dictionary) -> String: return str(r["id"]))
	assert_bool(bruno.has("hollow_silver")).is_true()  # a gossip knows the trifles too
	s.room_id = "brod-smithy"
	var smith := RumorRules.known_by(s, data, "npc_smith").map(func(r: Dictionary) -> String: return str(r["id"]))
	assert_bool(smith.has("mill_coins")).is_true()
	assert_bool(smith.has("hollow_silver")).is_false()  # a plain man — only the important ones


func test_asking_once_a_day_and_a_gossip_tells_more() -> void:
	var s := _session()
	assert_str(RumorRules.ask_why(s, data, "npc_innkeeper")).is_empty()
	var lines := RumorRules.ask(s, data, "npc_innkeeper")
	assert_int(lines.size()).is_equal(2)
	assert_str(lines[0]).contains("Бруно")
	assert_str(RumorRules.ask_why(s, data, "npc_innkeeper")).is_equal("RUMOR_ASK_TODAY")
	s.shift_attitude("npc_serving", -5, data)
	assert_str(RumorRules.ask_why(s, data, "npc_serving")).is_equal("RUMOR_ASK_HOSTILE")
	TimeRules.advance(s, data, 1440)
	assert_str(RumorRules.ask_why(s, data, "npc_innkeeper")).is_empty()
	s.room_id = "brod-smithy"
	assert_int(RumorRules.ask(s, data, "npc_smith").size()).is_equal(1)


func test_the_innkeeper_sells_a_rumour_a_tip_first() -> void:
	var s := _session()
	s.npc_id = "npc_innkeeper"
	var svc := TradeRules.services(s, data, "npc_innkeeper").filter(func(x: Dictionary) -> bool: return x["id"] == "rumor")
	assert_int(svc.size()).is_equal(1)
	assert_str(str(svc[0]["why"])).is_empty()
	var gold := int(s.character["gold_cp"])
	var lines := TradeRules.buy_service(s, data, "npc_innkeeper", "rumor")
	assert_int(int(s.character["gold_cp"])).is_equal(gold - 20)
	assert_str(" ".join(lines)).contains("отмечено на карте")
	assert_int(RumorRules._state(s)["heard"].size()).is_equal(1)


func test_a_true_tip_marks_the_map_and_finds_the_secret() -> void:
	var s := _session()
	var lines := RumorRules.hear(s, data, ["mill_coins"], "Бруно")
	assert_str(lines[0]).contains("отмечено на карте")
	assert_bool((s.character["scouted"] as Array).has("brod-mill")).is_true()
	assert_bool(WorldMap.known(s, data["world"])["rooms"].has("brod-mill")).is_true()
	assert_bool(RumorRules.marks(s, data).has("brod-mill")).is_true()
	assert_str(RumorRules.groups(s, data)[0]["title"]).is_equal("Наводки")
	var found := RumorRules.on_enter(s, data, "brod-mill")
	assert_str(" ".join(found)).contains("Слух подтвердился")
	assert_bool((s.revealed.get("brod-mill", []) as Array).has("sacks")).is_true()
	assert_bool(RumorRules.marks(s, data).is_empty()).is_true()
	assert_array(RumorRules.on_enter(s, data, "brod-mill")).is_empty()  # checked once


func test_a_lie_is_shown_up_on_the_spot() -> void:
	var s := _session()
	RumorRules.hear(s, data, ["hollow_silver"])
	var out := RumorRules.on_enter(s, data, "pushcha-hollow")
	assert_str(" ".join(out)).contains("Слух соврал")
	assert_bool(bool(RumorRules.get_rumor(s, "hollow_silver")["refuted"])).is_true()
	var here := RumorRules.known_at(s, data, "brod").map(func(r: Dictionary) -> String: return str(r["id"]))
	assert_bool(here.has("hollow_silver")).is_false()
	assert_str(str(RumorRules.groups(s, data).back()["lines"][0])).starts_with("✗")


func test_a_true_rumour_fades_a_lie_lives_on() -> void:
	var s := _session()
	var t := RumorRules.add(s, data, {"text": "у кузнеца родилась двойня", "weight": 1, "origin": "brod"})
	var lie := RumorRules.add(s, data, {"text": "кузнец продал душу за молот", "weight": 1, "origin": "brod", "truth": false})
	TimeRules.advance(s, data, 11 * 1440)
	var here := RumorRules.known_at(s, data, "brod").map(func(r: Dictionary) -> String: return str(r["id"]))
	assert_bool(here.has(t["id"])).is_false()
	assert_bool(here.has(lie["id"])).is_true()


func test_the_board_notices() -> void:
	var s := _session("brod-square")
	var ids := RumorRules.notices(s, data).map(func(r: Dictionary) -> String: return str(r["id"]))
	assert_bool(ids.has("miners_missing")).is_true()
	assert_bool(ids.has("artel_hires")).is_true()
	assert_bool(ids.has("mill_coins")).is_false()


func test_the_master_spreads_tells_and_refutes() -> void:
	var s := _session()
	var bad := RumorRules.plan(s, data, {"op": "spread", "text": "ой"}, [])
	assert_bool(bad.has("reason")).is_true()
	var p := RumorRules.plan(s, data, {"op": "spread", "text": "герой в одиночку прогнал волков от брода", "importance": 2, "fame": 2}, [])
	assert_bool(p.has("plan")).is_true()
	assert_bool(p["plan"].has("text")).is_false()  # a plan with `text` is a note
	assert_bool(RumorRules.plan(s, data, {"op": "spread", "text": "ещё один слух о герое", "importance": 1}, [{"kind": "rumor", "plan": p["plan"]}]).has("reason")).is_true()
	var lines := RumorRules.apply(s, data, p["plan"])
	assert_str(lines[0]).contains("Пошёл слух")
	assert_int(ReputationRules.points(s, "brod")).is_equal(6)
	assert_bool(RumorRules.plan(s, data, {"op": "tell", "rumor_ids": ["tower_fire", "nope"]}, []).has("reason")).is_true()
	var tell := RumorRules.plan(s, data, {"op": "tell", "rumor_ids": ["tower_fire", "miners_missing"]}, [])
	var told := RumorRules.apply(s, data, tell["plan"])
	assert_int(told.size()).is_equal(2)
	assert_str(" ".join(told)).contains("отмечено на карте")
	assert_bool(RumorRules.plan(s, data, {"op": "refute", "rumor_id": "mill_coins"}, []).has("reason")).is_true()  # the truth stands
	var ref := RumorRules.plan(s, data, {"op": "refute", "rumor_id": "hollow_silver"}, [])
	RumorRules.apply(s, data, ref["plan"])
	assert_bool(RumorRules.alive(s, RumorRules.get_rumor(s, "hollow_silver"))).is_false()


func test_the_snapshot_holds_the_place_rumours_only() -> void:
	var s := _session()
	var snap := " ".join(RumorRules.snapshot(s, data))
	assert_str(snap).contains("[mill_coins]")
	assert_str(snap).not_contains("hollow_silver")  # a trifle: the place does not talk of it aloud
	assert_str(snap).not_contains("ложн")
	s.mode = GameSession.MODE_SOCIAL
	s.npc_id = "npc_innkeeper"
	assert_str(" ".join(RumorRules.snapshot(s, data))).contains("[hollow_silver]")
	RumorRules.add(s, data, {"text": "на заставе нашли клад", "weight": 2, "origin": "outpost"})
	var far := RumorRules.add(s, data, {"text": "в шахте завёлся дракон", "weight": 1, "origin": "mine", "id": "far"})
	assert_str(" ".join(RumorRules.snapshot(s, data))).not_contains("[far]")  # not arrived yet
	assert_bool(far["arrive"].has("brod")).is_true()
	assert_bool(TurnSnapshot.build(s, data, 2000)["scene"].has("rumors")).is_true()


func test_the_snapshot_after_a_load_reads_the_weight_as_a_number() -> void:
	var s := _session()
	var back := GameSession.from_dict(JSON.parse_string(JSON.stringify(s.to_dict(500))))  # the weight comes back as 2.0
	back.mode = GameSession.MODE_SOCIAL
	back.npc_id = "npc_innkeeper"
	assert_str(" ".join(RumorRules.snapshot(back, data))).contains("[mill_coins]")
