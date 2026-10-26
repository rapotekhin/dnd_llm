extends GdUnitTestSuite
## Bonds (v0.7.31): steps by points and kind, gifts by taste once a day, perks (a discount, cheaper services, a bed,
## serving the wanted, hiding, a word to the guard), a rival's markup and an enemy's refusal, the confession and its
## consent, breaking up, deeds of the engine, a mentor after a course, the master's `bond`.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _hero(room: String = "brod-tavern-hall") -> GameSession:
	var s := TestUtils.new_session()
	s.settings["needs"] = false
	s.room_id = room
	s.minute = 12 * 60
	s.character["gender"] = "male"
	s.character["gold_cp"] = 100000
	s.rested_at = TimeRules.abs_minute(s) + 60 * 1440
	return s


func _bond(s: GameSession, npc: String, pts: int, kind: String = "friend") -> void:
	if not s.character.has("bonds"):
		s.character["bonds"] = {}
	s.character["bonds"][npc] = {"kind": kind, "points": pts}


func test_steps_follow_the_points() -> void:
	var s := _hero()
	assert_str(BondRules.word(s.character, data, "npc_innkeeper")).is_empty()
	var lines := BondRules.add(s, data, "npc_innkeeper", 30, "тест")
	assert_str(BondRules.word(s.character, data, "npc_innkeeper")).is_equal("приятель")
	assert_str(" ".join(lines)).contains("связь — приятель")
	BondRules.add(s, data, "npc_innkeeper", 30, "тест")
	assert_str(BondRules.word(s.character, data, "npc_innkeeper")).is_equal("друг")
	assert_int(BondRules.next_at(s.character, data, "npc_innkeeper")).is_equal(100)
	_bond(s, "npc_merchant", -25)
	assert_str(BondRules.word(s.character, data, "npc_merchant")).is_equal("соперник")
	assert_bool(SocialRules.refuses(s, data, "npc_merchant")).is_false()
	_bond(s, "npc_merchant", -70)
	assert_str(BondRules.word(s.character, data, "npc_merchant")).is_equal("враг")
	assert_bool(SocialRules.refuses(s, data, "npc_merchant")).is_true()


func test_a_gift_by_taste_once_a_day() -> void:
	var s := _hero()
	var c := s.character
	c["inventory"]["ale"] = 2
	c["inventory"]["dagger"] = 1
	assert_str(BondRules.gift_why(s, data, "npc_innkeeper", "ale")).is_empty()
	var lines := BondRules.gift(s, data, "npc_innkeeper", "ale")
	assert_int(BondRules.points(c, "npc_innkeeper")).is_equal(10)
	assert_int(int(c["inventory"]["ale"])).is_equal(1)
	assert_array(BondRules.known(c, "npc_innkeeper")["likes"]).contains(["drink"])
	assert_bool(TheftRules.pockets(s, data, "npc_innkeeper").any(func(e: Dictionary) -> bool: return str(e["item_id"]) == "ale")).is_true()
	assert_str(" ".join(lines)).contains("по душе")
	assert_str(BondRules.gift_why(s, data, "npc_innkeeper", "ale")).is_equal("BOND_GIFT_TODAY")
	s.day += 1
	BondRules.gift(s, data, "npc_innkeeper", "dagger")
	assert_int(BondRules.points(c, "npc_innkeeper")).is_equal(2)
	assert_array(BondRules.known(c, "npc_innkeeper")["dislikes"]).contains(["weapons"])


func test_a_neutral_gift_counts_by_value() -> void:
	var s := _hero()
	s.character["inventory"]["book"] = 1
	assert_int(BondRules.gift_points(s, data, "npc_innkeeper", "book")).is_equal(4)
	s.character["inventory"]["candle"] = 1
	assert_int(BondRules.gift_points(s, data, "npc_innkeeper", "candle")).is_equal(1)


func test_a_friend_sells_cheaper_and_a_rival_dearer() -> void:
	var s := _hero("brod-square")
	var base := TradeRules.buy_price(s, data, "npc_merchant", "lantern")
	_bond(s, "npc_merchant", 60)
	assert_int(TradeRules.buy_price(s, data, "npc_merchant", "lantern")).is_less(base)
	_bond(s, "npc_merchant", -30)
	assert_int(TradeRules.buy_price(s, data, "npc_merchant", "lantern")).is_greater(base)


func test_a_friend_serves_for_less() -> void:
	var s := _hero("brod-temple")
	var full := int(TradeRules.service_def(data, "identify")["cost_cp"])
	_bond(s, "npc_priestess", 60)
	var sv := TradeRules.services(s, data, "npc_priestess").filter(func(x: Dictionary) -> bool: return x["id"] == "identify")
	assert_int(int(sv[0]["cost_cp"])).is_equal(ceili(full * 0.5))


func test_a_close_friend_gives_a_bed_and_serves_the_wanted() -> void:
	var s := _hero()
	assert_dict(ExplorationRules.rest_place(data["world"], s.room_id, s, data)).is_empty()
	_bond(s, "npc_innkeeper", 60)
	var place := ExplorationRules.rest_place(data["world"], s.room_id, s, data)
	assert_int(int(place["cost_cp"])).is_equal(0)
	assert_str(str(place["host"])).is_equal("npc_innkeeper")
	s.wanted["brod"] = TimeRules.abs_minute(s)
	assert_bool(CrimeRules.shunned_by(s, data, "npc_innkeeper")).is_false()
	assert_bool(CrimeRules.shunned_by(s, data, "npc_merchant")).is_true()


func test_a_friend_hides_the_hero_from_the_patrol() -> void:
	var s := _hero()
	_bond(s, "npc_innkeeper", 60)
	assert_str(BondRules.hide_why(s, data, "npc_innkeeper")).is_equal("BOND_NOT_WANTED")
	s.wanted["brod"] = TimeRules.abs_minute(s) - 10000
	assert_str(BondRules.hide_why(s, data, "npc_innkeeper")).is_empty()
	BondRules.hide(s, data, "npc_innkeeper")
	assert_array(CrimeRules.check_arrest(s, data)).is_empty()
	assert_str(BondRules.hide_why(s, data, "npc_innkeeper")).is_equal("BOND_HIDE_COOLDOWN")


func test_a_friend_of_the_law_speaks_for_the_hero() -> void:
	var s := _hero()
	s.crimes.append({"id": "cr1", "kind": "assault", "victim": "npc_merchant", "room": "brod-square", "location": "brod",
		"at": 0, "witnesses": [], "known": true, "settled": false})
	var fine := CrimeRules.fine(s, data, "brod")
	var sentence := CrimeRules.sentence(s, data, "brod")
	_bond(s, "npc_captain", 60)
	assert_str(BondRules.intercessor(s, data, "brod")).is_equal("npc_captain")
	assert_int(CrimeRules.fine(s, data, "brod")).is_equal(fine / 2)
	assert_int(int(CrimeRules.sentence(s, data, "brod")["severity"])).is_less_equal(int(sentence["severity"]))


func test_romance_needs_the_pack_consent() -> void:
	var s := _hero()
	assert_str(BondRules.romance_closed(s, data, "npc_serving")).is_empty()
	assert_str(BondRules.romance_closed(s, data, "npc_captain")).contains("женат")
	assert_str(BondRules.romance_closed(s, data, "npc_priestess")).is_not_empty()
	assert_str(BondRules.romance_closed(s, data, "npc_innkeeper")).is_not_empty()  # only towards women
	s.character["gender"] = "female"
	assert_str(BondRules.romance_closed(s, data, "npc_innkeeper")).is_empty()


func test_a_confession_and_breaking_up() -> void:
	var s := _hero()
	var c := s.character
	c["skills"]["persuasion"] = 40
	assert_str(BondRules.confess_why(s, data, "npc_serving")).is_equal("BOND_TOO_EARLY")
	_bond(s, "npc_serving", 45)
	for i in 5:
		if BondRules.kind(c, "npc_serving") == "romance":
			break
		c["bonds"]["npc_serving"]["confess_day"] = -999
		c["bonds"]["npc_serving"]["points"] = 45
		assert_str(BondRules.confess_why(s, data, "npc_serving")).is_empty()
		BondRules.confess(s, data, "npc_serving")
	assert_str(BondRules.kind(c, "npc_serving")).is_equal("romance")
	assert_str(BondRules.partner(s)).is_equal("npc_serving")
	assert_str(BondRules.word(c, data, "npc_serving")).is_equal("ухаживание")
	_bond(s, "npc_mercenary", 50)
	assert_str(BondRules.confess_why(s, data, "npc_mercenary")).is_equal("BOND_HAS_PARTNER")
	var before := BondRules.points(c, "npc_serving")
	BondRules.break_off(s, data, "npc_serving")
	assert_str(BondRules.kind(c, "npc_serving")).is_equal("friend")
	assert_int(BondRules.points(c, "npc_serving")).is_equal(before - 30)


func test_a_refused_confession_waits_a_week() -> void:
	var s := _hero()
	s.character["skills"]["persuasion"] = -40
	_bond(s, "npc_serving", 45)
	BondRules.confess(s, data, "npc_serving")
	if BondRules.kind(s.character, "npc_serving") != "romance":  # a natural 20 still wins
		assert_int(BondRules.points(s.character, "npc_serving")).is_equal(35)
		s.character["bonds"]["npc_serving"]["points"] = 45
		assert_str(BondRules.confess_why(s, data, "npc_serving")).is_equal("BOND_CONFESS_COOLDOWN")


func test_deeds_of_the_engine_move_the_bond() -> void:
	var s := _hero()
	TheftRules.react(s, data, "npc_innkeeper")
	assert_int(BondRules.points(s.character, "npc_innkeeper")).is_equal(-15)
	BondRules.on_deed(s, data, "npc_veteran", "quest_done", "задание")
	assert_int(BondRules.points(s.character, "npc_veteran")).is_equal(10)


func test_a_course_makes_a_mentor_who_asks_less() -> void:
	var s := _hero("brod-school-hall")
	s.minute = 10 * 60
	s.character["skills"]["history"] = 30
	StudyRules.state(s.character)["schools"]["brod_school"] = {"since": s.day, "stipend": false}
	var fee := StudyRules.fee(s, data, "elvish")
	StudyRules.enroll(s, data, "letters")
	for i in 20:
		if not StudyRules.enrolled(s.character, "letters"):
			break
		s.minute = 10 * 60
		StudyRules.lesson(s, data, "letters", StudyRules.lesson_hours(data) * 60)
		TimeRules.advance(s, data, 1440)
	assert_bool(StudyRules.done(s.character, "letters")).is_true()
	assert_str(BondRules.kind(s.character, "npc_teacher")).is_equal("mentor")
	assert_str(BondRules.word(s.character, data, "npc_teacher")).is_equal("учитель")
	assert_int(StudyRules.fee(s, data, "elvish")).is_less(fee)


func test_the_master_moves_a_bond_once_a_day() -> void:
	var s := _hero()
	assert_str(str(BondRules.make(s, data, {"npc_id": "npc_captain", "delta": 5, "reason": "x"}).get("reason", ""))).contains("не в сцене")
	assert_str(str(BondRules.make(s, data, {"npc_id": "npc_innkeeper", "delta": 15, "reason": "x"}).get("reason", ""))).contains("delta")
	assert_str(str(BondRules.make(s, data, {"npc_id": "npc_innkeeper", "delta": 5}).get("reason", ""))).contains("reason")
	assert_str(str(BondRules.make(s, data, {"npc_id": "npc_innkeeper", "romance": {"open": true}}).get("reason", ""))).contains("автор")
	var made := BondRules.make(s, data, {"npc_id": "npc_innkeeper", "delta": 5, "reason": "выпили за старую заставу"})
	assert_dict(made["plan"]).is_not_empty()
	BondRules.apply_make(s, data, made["plan"])
	assert_int(BondRules.points(s.character, "npc_innkeeper")).is_equal(5)
	assert_str(str(BondRules.make(s, data, {"npc_id": "npc_innkeeper", "delta": 5, "reason": "ещё"}).get("reason", ""))).contains("сегодня")
	assert_str(BondRules.text(s, data)).contains("Бруно Хмель — дружба")


func test_the_snapshot_tells_the_romance_of_the_scene() -> void:
	var s := _hero()
	var t := BondRules.text(s, data)
	assert_str(t).contains("Мира: роман возможен")
	assert_str(t).contains("связей нет")
