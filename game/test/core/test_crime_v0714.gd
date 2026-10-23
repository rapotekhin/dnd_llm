extends GdUnitTestSuite
## «Последствия и время» (roadmap v0.7.14): a murder is a fact of the world — witnesses, a hidden body found later,
## the location's attitude, the wanted hero turned away by traders and givers, the guard's hold (wergild, stocks,
## resisting), the body to search, quests of the dead passing to the heir or failing.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _hero(room: String) -> GameSession:
	var s := TestUtils.new_session()
	for p: Dictionary in data["presets"]:
		if p["id"] == "rogue_damir":
			s.character = GameSession.normalized_character(CharacterBuilder.build_preset(p, data))
	CharacterRules.refresh(s.character, data, s.items)
	s.room_id = room
	return s


func test_a_murder_before_witnesses_is_known_at_once() -> void:
	var s := _hero("brod-tavern-hall")
	var lines := CrimeRules.on_death(s, data, "npc_mercenary", true, s.room_id)
	assert_str(" · ".join(lines)).contains("видели: Бруно Хмель").contains("Вы в розыске")
	assert_bool(s.dead_npcs.has("npc_mercenary")).is_true()
	assert_bool(bool(s.crimes[0]["known"])).is_true()
	assert_bool(s.wanted.has("brod")).is_true()
	assert_int(s.attitude("npc_innkeeper")).is_equal(-3)  # a witness: one step more
	assert_int(s.attitude("npc_herbalist")).is_equal(-2)  # the whole Brod
	assert_int(s.attitude("npc_hermit")).is_equal(0)  # another location
	assert_bool(TheftRules.shop_closed_for(s, "npc_herbalist", data)).is_true()
	assert_bool(CrimeRules.held(s)).is_false()  # no guard in the hall yet


func test_self_defence_is_no_crime() -> void:
	var s := _hero("brod-tavern-hall")
	CrimeRules.on_death(s, data, "npc_mercenary", false, s.room_id)
	assert_array(s.crimes).is_empty()
	assert_bool(s.wanted.is_empty()).is_true()
	assert_str(str(s.bodies["npc_mercenary"])).is_equal("brod-tavern-hall")


func test_a_hidden_body_is_found_later_and_the_letter_fails() -> void:
	var s := _hero("brod-temple")
	s.quests_active["letter_to_ilva"] = 0
	var lines := CrimeRules.on_death(s, data, "npc_priestess", true, s.room_id)
	assert_str(" · ".join(lines)).contains("свидетелей нет").contains("Задание провалено")
	assert_bool(s.quests_failed.has("letter_to_ilva")).is_true()
	assert_bool(s.wanted.is_empty()).is_true()
	assert_int(s.attitude("npc_innkeeper")).is_equal(0)
	var later := TimeRules.advance(s, data, int(data["rules"]["crime"]["found_minutes"]))
	assert_str(" · ".join(later)).contains("Нашли тело: Сестра Илва").contains("Вы в розыске")
	assert_int(s.attitude("npc_innkeeper")).is_equal(-2)
	var info := QuestRules.info(s, data["world"])
	assert_bool(info.any(func(q: Dictionary) -> bool: return q["id"] == "letter_to_ilva" and bool(q["failed"]))).is_true()


func test_the_captain_holds_the_wanted_hero_and_the_wergild_settles_it() -> void:
	var s := _hero("brod-temple")
	CrimeRules.on_death(s, data, "npc_priestess", true, s.room_id)
	CrimeRules.reveal(s, data, "npc_priestess")  # she confessed (the master's crime_known)
	s.room_id = "brod-gate"
	var lines := CrimeRules.check_arrest(s, data)
	assert_str(" · ".join(lines)).contains("Капитан Ратмир")
	assert_bool(CrimeRules.held(s)).is_true()
	assert_int(CrimeRules.fine(s, data, "brod")).is_equal(10000)  # clergy — twice the wergild
	s.character["gold_cp"] = 100
	assert_str(CrimeRules.can_answer(s, data, "pay")).is_equal("CRIME_NO_MONEY")
	s.character["gold_cp"] = 12000
	CrimeRules.answer(s, data, "pay")
	assert_int(int(s.character["gold_cp"])).is_equal(2000)
	assert_bool(CrimeRules.held(s) or s.wanted.has("brod")).is_false()
	assert_int(s.attitude("npc_innkeeper")).is_equal(-2)  # paid, but not forgiven (v0.7.22.10)
	assert_array(QuestRules.offers_here(s, data["world"])).contains(["ash_over_the_march"])


func test_a_patrol_finds_the_hero_but_not_a_sneaking_one() -> void:
	var s := _hero("brod-tavern-hall")
	CrimeRules.on_death(s, data, "npc_mercenary", true, s.room_id)
	TimeRules.advance(s, data, 61)
	s.sneaking = true
	s.room_id = "brod-square"
	assert_array(CrimeRules.check_arrest(s, data)).is_empty()
	s.sneaking = false
	assert_str(" · ".join(CrimeRules.check_arrest(s, data))).contains("Патруль ополчения")


func test_the_stocks_take_days_and_resisting_is_a_fight() -> void:
	var s := _hero("brod-tavern-hall")
	CrimeRules.on_death(s, data, "npc_mercenary", true, s.room_id)
	s.room_id = "brod-gate"
	CrimeRules.check_arrest(s, data)
	var day := s.day
	var days := CrimeRules.stocks_days(s, data, "brod")  # the sentence by severity (v0.7.22.10): a notable victim — 7
	CrimeRules.answer(s, data, "stocks")
	assert_int(s.day).is_equal(day + days)
	assert_bool(s.wanted.has("brod")).is_false()
	var s2 := _hero("brod-tavern-hall")
	CrimeRules.on_death(s2, data, "npc_mercenary", true, s2.room_id)
	s2.room_id = "brod-gate"
	CrimeRules.check_arrest(s2, data)
	CrimeRules.answer(s2, data, "resist")
	assert_bool(s2.pending_fight.all(func(f: Dictionary) -> bool: return bool(f["by_hero"]))).is_true()
	assert_bool(s2.pending_fight.any(func(f: Dictionary) -> bool: return str(f.get("npc_id", "")) == "npc_captain")).is_true()
	assert_bool(s2.wanted.has("brod")).is_true()


func test_the_captains_chain_passes_to_his_heir() -> void:
	var s := _hero("brod-gate")
	s.quests_active["ash_over_the_march"] = 1  # «report to the captain»
	var lines := CrimeRules.on_death(s, data, "npc_captain", false, s.room_id)
	assert_str(" · ".join(lines)).contains("продолжит Старый Орвин")
	assert_bool(s.quests_active.has("ash_over_the_march")).is_true()
	s.room_id = "brod-tavern-hall"
	assert_bool(QuestRules.talks_here(s, data["world"]).any(func(t: Dictionary) -> bool: return t["npc_id"] == "npc_veteran")).is_true()


func test_searching_a_body_before_people_is_seen() -> void:
	var s := _hero("brod-tavern-hall")
	CrimeRules.on_death(s, data, "npc_innkeeper", false, s.room_id)
	var before := int(s.character["gold_cp"])
	var lines := CrimeRules.search_body(s, data, "npc_innkeeper")
	assert_str(lines[0]).contains("Обыскано тело Бруно Хмель")
	assert_int(int(s.character["gold_cp"])).is_greater_equal(before)
	assert_str(" · ".join(lines)).contains("видит, как вы обираете мёртвого")
	assert_bool(CrimeRules.bodies_here(s, data)[0]["searched"]).is_true()


func test_the_master_sees_the_crimes_and_can_only_reveal_a_hidden_one() -> void:
	var s := _hero("brod-temple")
	CrimeRules.on_death(s, data, "npc_priestess", true, s.room_id)
	var snap := TurnSnapshot.build(s, data, 2000)
	assert_str(str(snap["crimes"]["deeds"][0])).contains("Сестра Илва").contains("никто не знает")
	assert_str(str(CrimeRules.plan_reveal(s, data, "npc_priestess").get("summary", ""))).contains("раскрыто")
	CrimeRules.reveal(s, data, "npc_priestess")
	assert_str(str(CrimeRules.plan_reveal(s, data, "npc_priestess").get("reason", ""))).is_not_empty()


func test_the_master_cannot_walk_the_held_hero_away() -> void:
	var s := _hero("brod-tavern-hall")
	CrimeRules.on_death(s, data, "npc_mercenary", true, s.room_id)
	s.room_id = "brod-gate"
	CrimeRules.check_arrest(s, data)
	var r := EffectEngine.new().validate(s, data, "t-1", {"kind": "move", "room_id": "pushcha-edge"})
	assert_str(str(r)).contains("стража держит героя")  # out of Brod — no; within it the guard may lead (v0.7.22.2)


func test_old_saves_have_no_crimes() -> void:
	var v20 := {"save_version": 20, "session": {"day": 2}}
	SaveFormat._v20_to_v21(v20, {})
	assert_array(v20["session"]["crimes"]).is_empty()
	assert_str(str(v20["session"]["arrest"])).is_empty()
	var s := GameSession.from_dict(v20["session"])
	assert_bool(s.wanted.is_empty()).is_true()
