extends GdUnitTestSuite
## Letters (v0.7.48): a letter at a person with a post goes by the map's roads — days, a price, a risk on wild roads;
## delivered, the engine's verdict; on the reply day the master answers (`letter_reply` where it is a choice). A
## friend comes to the named place and joins; a denunciation with evidence puts the NPC under guard, a false one is
## the hero's crime; a recommendation opens an office's condition, a school, a private place; a messenger is lost.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _session(room: String = "brod-townhall") -> GameSession:
	var s := TestUtils.new_session()
	s.settings["needs"] = false
	s.room_id = room
	s.minute = 12 * 60
	s.character["gold_cp"] = 10000
	for r: String in ["brod-tavern-hall", "brod-square", "brod-gate", "pushcha-glade", "outpost-yard", "brod-townhall", "brod-smithy"]:
		if not s.visited.has(r):
			s.visited.append(r)
	return s


func _days(s: GameSession, n: int) -> Array[String]:
	return TimeRules.advance(s, data, n * 1440)


func _letter(s: GameSession, to: String, purpose: String, extra: Dictionary = {}, way: String = "post") -> Dictionary:
	var why := LetterRules.send_why(s, data, "npc_clerk", to, purpose, "Прошу вас, ответьте поскорее.", way, extra)
	assert_str(why).is_empty()
	LetterRules.send(s, data, "npc_clerk", to, purpose, "Прошу вас, ответьте поскорее.", way, extra)
	return LetterRules.letters(s)[0]


## The master's turn: the decision by `letter_reply` (when given), then the answer's text.
func _answer(s: GameSession, l: Dictionary, answer: String = "") -> Array[String]:
	if not answer.is_empty():
		var p := LetterRules.plan(s, data, {"letter_id": l["id"], "answer": answer}, [])
		assert_bool(p.has("plan")).override_failure_message(str(p)).is_true()
		LetterRules.apply(s, data, p["plan"])
	return LetterRules.answered(s, data, str(l["id"]), "Получил. Отвечаю как могу.")


func test_the_post_prices_days_and_risk_by_the_roads() -> void:
	var s := _session()
	assert_array(LetterRules.ways_of(data, "npc_clerk")).contains_exactly(["post"])
	assert_array(LetterRules.ways_of(data, "npc_drover")).contains_exactly(["courier"])
	var q := LetterRules.quote(s, data, "post", "npc_hermit")  # Brod → the Pushcha: one hop, a wild one
	assert_int(int(q["hops"])).is_equal(1)
	assert_int(int(q["days"])).is_equal(2)
	assert_int(int(q["cost"])).is_equal(20)
	assert_int(int(q["risk"])).is_equal(15)
	var town := LetterRules.quote(s, data, "post", "npc_innkeeper")  # within Brod: a day, no risk
	assert_int(int(town["days"])).is_equal(1)
	assert_int(int(town["risk"])).is_equal(0)
	assert_str(LetterRules.send_why(s, data, "npc_clerk", "npc_innkeeper", "ties", "hi", "post")).contains("знаков")
	assert_str(LetterRules.send_why(s, data, "npc_clerk", "npc_innkeeper", "ties", "Привет из ратуши", "courier")).is_not_empty()  # the clerk has no courier
	assert_str(LetterRules.send_why(s, data, "npc_clerk", "npc_innkeeper", "denounce", "Донос на Ферна", "post", {"about": "npc_merchant"})).contains("страже")


func test_a_letter_is_delivered_and_its_reply_is_due() -> void:
	var s := _session()
	var gold := int(s.character["gold_cp"])
	var l := _letter(s, "npc_hermit", "ties")
	assert_int(int(s.character["gold_cp"])).is_equal(gold - 20)
	assert_str(str(l["status"])).is_equal("en_route")
	assert_int(int(l["deliver_day"])).is_equal(s.day + 2)
	assert_int(int(l["reply_day"])).is_equal(s.day + 4)
	l["risk"] = 0
	_days(s, 2)
	assert_str(str(l["status"])).is_equal("delivered")
	assert_str(LetterRules.due(s, data)).is_empty()  # the reply is on its way back
	_days(s, 2)
	assert_str(LetterRules.due(s, data)).is_equal(str(l["id"]))
	assert_str(LetterRules.frame(s, data, str(l["id"]))).contains("[letter:%s]" % l["id"])
	assert_int(BondRules.points(s.character, "npc_hermit")).is_equal(4)  # a word to an acquaintance: closeness
	var p := LetterRules.plan(s, data, {"letter_id": l["id"], "answer": "yes"}, [])
	assert_str(str(p.get("reason", ""))).contains("движок")  # no choice here: the engine decided
	_answer(s, l)
	assert_str(str(l["status"])).is_equal("answered")
	assert_str(LetterRules.due(s, data)).is_empty()


func test_a_friend_comes_to_the_place_and_joins() -> void:
	var s := _session()
	BondRules.add(s, data, "npc_innkeeper", 60, "")
	var l := _letter(s, "npc_innkeeper", "help", {"room": "outpost-yard"})
	_days(s, 1)
	assert_bool(bool(l["can"])).is_true()
	_days(s, 1)
	assert_str(LetterRules.due(s, data)).is_equal(str(l["id"]))
	var lines := _answer(s, l, "yes")
	assert_str(" ".join(lines)).contains("придёт")
	assert_str(str(s.npc_at["npc_innkeeper"])).is_empty()  # on the road
	assert_bool(s.npcs_here(data["world"], "brod-tavern-hall").has("npc_innkeeper")).is_false()
	var arrive := int(l["ally"]["arrive"])
	assert_int(arrive).is_equal(s.day + 1)  # Brod → the outpost: one hop
	_days(s, 1)
	assert_str(str(s.npc_at["npc_innkeeper"])).is_equal("outpost-yard")
	s.room_id = "outpost-yard"
	var joined := LetterRules.on_enter(s, data, "outpost-yard")
	assert_str(" ".join(joined)).contains("идёт с героем")
	assert_bool(s.followers.has("npc_innkeeper")).is_true()


func test_a_mere_acquaintance_only_refuses_help() -> void:
	var s := _session()
	var l := _letter(s, "npc_smith", "help", {"room": "brod-square"})
	_days(s, 2)
	assert_bool(bool(l["can"])).is_false()
	assert_str(str(LetterRules.plan(s, data, {"letter_id": l["id"], "answer": "yes"}, []).get("reason", ""))).contains("отказ")
	_answer(s, l, "no")
	assert_bool(l.has("ally")).is_false()
	assert_bool(FollowRules.placed(s, "npc_smith")).is_false()


func test_a_denunciation_with_evidence_puts_the_npc_under_guard() -> void:
	var s := _session()
	s.secrets_told.append("npc_serving:fern_casks")  # Mira told what she saw
	var l := _letter(s, "npc_captain", "denounce", {"about": "npc_merchant"})
	_days(s, 1)
	assert_bool(bool(l["can"])).is_true()
	assert_str(str(l["verdict"])).contains("свидетель — Мира")
	_days(s, 1)  # arrest_days later
	assert_str(str(s.npc_at.get("npc_merchant", ""))).is_equal("brod-lockup")
	assert_bool(LetterRules.jailed(s, "npc_merchant")).is_true()
	assert_bool(s.npcs_here(data["world"], "brod-square").has("npc_merchant")).is_false()
	assert_bool(SocialRules.refuses(s, data, "npc_merchant")).is_true()  # he knows who
	assert_bool(s.wanted.has("brod")).is_false()


func test_the_evidence_item_goes_with_the_letter() -> void:
	var s := _session()
	ItemRules.found(s.character, data, s.items, "fern_tally", 1)
	var l := _letter(s, "npc_captain", "denounce", {"about": "npc_merchant"})
	assert_str(str(l["evidence"])).is_equal("fern_tally")
	assert_bool(s.character["inventory"].has("fern_tally")).is_false()
	_days(s, 2)
	assert_str(str(l["verdict"])).contains("Засаленная")
	assert_str(str(s.npc_at.get("npc_merchant", ""))).is_equal("brod-lockup")


func test_no_evidence_no_case_and_a_false_one_is_a_crime() -> void:
	var s := _session()
	var l := _letter(s, "npc_captain", "denounce", {"about": "npc_merchant"})  # guilty, but nothing to show
	_days(s, 2)
	assert_bool(bool(l["can"])).is_false()
	assert_bool(s.npc_at.has("npc_merchant")).is_false()
	assert_bool(s.crimes.is_empty()).is_true()
	var f := _letter(s, "npc_captain", "denounce", {"about": "npc_smith"})  # an honest smith
	_days(s, 1)
	assert_str(str(f["verdict"])).contains("ложный")
	assert_bool(s.crimes.any(func(c: Dictionary) -> bool: return str(c["kind"]) == "false_report" and bool(c["known"]))).is_true()
	assert_bool(s.npc_at.has("npc_smith")).is_false()


func test_a_recommendation_opens_an_office_a_school_and_a_private_place() -> void:
	var s := _session()
	var judge := OfficeRules.requirements(s, data, "brod_judge")
	assert_bool(judge[0]["ok"]).is_false()  # the standing in Brod
	BondRules.add(s, data, "npc_captain", 30, "")
	var l := _letter(s, "npc_captain", "recommend")
	_days(s, 2)
	assert_bool(bool(l["can"])).is_true()
	var lines := _answer(s, l, "yes")
	assert_str(" ".join(lines)).contains("Рекомендация")
	judge = OfficeRules.requirements(s, data, "brod_judge")
	assert_bool(judge[0]["ok"]).is_true()
	assert_str(str(judge[0]["text"])).contains("рекомендация")
	assert_bool(judge[1]["ok"]).is_false()  # the service is not waived
	var exam := StudyRules.exam(s, data, "brod_school")
	assert_str(" ".join(exam)).contains("без экзамена")
	assert_bool(SiteRules.permitted(s, data, "brod-lockup")).is_true()  # the captain's own place
	assert_bool(SiteRules.permitted(s, data, "brod-den")).is_false()


func test_one_without_standing_cannot_recommend() -> void:
	var s := _session()
	BondRules.add(s, data, "npc_cook", 40, "")
	s.visited.append("brod-tavern-kitchen")
	var l := _letter(s, "npc_cook", "recommend")
	_days(s, 2)
	assert_bool(bool(l["can"])).is_false()
	assert_str(str(l["verdict"])).contains("положения")


func test_a_messenger_lost_on_a_wild_road() -> void:
	var s := _session()
	var l := _letter(s, "npc_hermit", "ties")
	l["risk"] = 100
	_days(s, 2)
	assert_str(str(l["status"])).is_equal("lost")
	var room := str(l["lost_room"])
	assert_str(room).starts_with("pushcha")
	var prop: Dictionary = (s.props[room] as Array).filter(func(p: Dictionary) -> bool: return bool(p.get("lost", false)))[0]
	assert_str(str(ItemRules.def_of(data["items"], s.items, str(prop["item_id"]))["text"])).is_equal("Прошу вас, ответьте поскорее.")
	assert_array(PropRules.abandon(s, data, room)).is_empty()  # it waits in the mud to be found
	assert_str(LetterRules.due(s, data)).is_empty()
	_days(s, 4)
	var silent := LetterRules.groups(s, data).filter(func(g: Dictionary) -> bool: return str(g["title"]) == "Без ответа")
	assert_int(silent.size()).is_equal(1)


func test_a_silent_family_worries() -> void:
	var s := _session()
	s.character["family"] = {"spouse": "npc_innkeeper", "home_room": "brod-tavern-hall", "children": []}
	s.room_id = "outpost-yard"
	BondRules.add(s, data, "npc_innkeeper", 50, "")
	var lines: Array[String] = []
	for i in 14:
		lines.append_array(_days(s, 1))
	assert_str(" ".join(lines)).contains("тревожится")
	assert_int(BondRules.points(s.character, "npc_innkeeper")).is_less(50)


func test_the_journal_tab() -> void:
	var s := _session()
	_letter(s, "npc_hermit", "ties")
	var g := LetterRules.groups(s, data)
	assert_str(str(g[0]["title"])).is_equal("Ждём ответа")
	assert_str(" ".join(g[0]["lines"])).contains("в пути")
	assert_int(LetterRules.count(s, data)).is_equal(1)
