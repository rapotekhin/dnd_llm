extends GdUnitTestSuite
## Crime and private places (v0.7.39.2, the author's acceptance of «Своя жизнь»): the owner's leave until a quarrel,
## the Night Rats' hideout answered by the Rats (a paid entry, a warning, their guards), the warning again after a
## punished trespass, a burglary seen only by those who are there.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _hero(room: String) -> GameSession:
	var s := TestUtils.new_session()
	s.room_id = room
	s.minute = 12 * 60
	s.character.erase("orgs")  # the start hero is no Rat
	return s


func test_the_owners_leave_lasts_until_a_quarrel() -> void:
	var s := _hero("brod-tavern-hall")
	assert_array(SiteRules.closed_to_hero(s, data, "npc_innkeeper")).contains(["brod-tavern"])
	assert_str(SiteRules.ask_why(s, data, "npc_innkeeper")).is_empty()
	var lines := SiteRules.grant(s, data, "npc_innkeeper")
	assert_str(" ".join(lines)).contains("разрешает входить")
	assert_str(SiteRules.unwelcome(s, data, "brod-tavern-kitchen")).is_empty()
	assert_str(SiteRules.ask_why(s, data, "npc_innkeeper")).is_equal("SITE_NOTHING_TO_ASK")
	var back := GameSession.from_dict(s.to_dict(5))
	assert_str(str(back.permits.get("brod-tavern", ""))).is_equal("npc_innkeeper")
	s.shift_attitude("npc_innkeeper", -1, data)  # a quarrel
	assert_str(SiteRules.unwelcome(s, data, "brod-tavern-kitchen")).is_equal("npc_innkeeper")


func test_a_refused_ask_waits_a_day() -> void:
	var s := _hero("brod-tavern-hall")
	var lines := SiteRules.ask(s, data, "npc_innkeeper")
	assert_str(lines[0]).contains("Просьба впустить")
	assert_bool(SiteRules.permitted(s, data, "brod-tavern") or s.permit_asked.has("npc_innkeeper")).is_true()
	var t := _hero("brod-tavern-hall")
	t.permit_asked["npc_innkeeper"] = t.day  # refused today
	assert_str(SiteRules.ask_why(t, data, "npc_innkeeper")).is_equal("SITE_ASKED_TODAY")
	t.day += 1
	assert_str(SiteRules.ask_why(t, data, "npc_innkeeper")).is_empty()


func test_the_master_lets_in_by_words() -> void:
	var s := _hero("brod-tavern-hall")
	var fx := EffectEngine.new()
	var r := fx.validate(s, data, "t-1", {"kind": "permit", "npc_id": "npc_innkeeper"})
	assert_bool(bool(r["accepted"])).override_failure_message(str(r)).is_true()
	fx.apply(s, "t-1", [r["effect_id"]])
	assert_bool(SiteRules.permitted(s, data, "brod-tavern")).is_true()
	var no := fx.validate(s, data, "t-2", {"kind": "permit", "npc_id": "npc_smith"})
	assert_bool(bool(no["accepted"])).is_false()


func test_a_stranger_in_the_hideout_is_the_rats_business() -> void:
	var s := _hero("brod-den")
	var warned := SiteRules.on_enter(s, data, s.room_id)
	assert_str(" ".join(warned)).contains("Чужим тут не место")
	assert_array(s.crimes).is_empty()
	assert_bool(s.pending_fight.is_empty()).is_true()
	var lines := SiteRules.on_enter(s, data, s.room_id)
	assert_str(" ".join(lines)).contains("Предупреждали")
	assert_int(s.pending_fight.size()).is_equal(2)
	assert_array(s.crimes).is_empty()  # no law in the Rats' den
	assert_bool(s.wanted.is_empty()).is_true()


func test_the_hideout_is_open_for_its_fee() -> void:
	var s := _hero("brod-mill")
	s.character["gold_cp"] = 100
	assert_str(OrgRules.entry_here(s, data)).is_equal("night_rats")
	assert_str(OrgRules.entry_why(s, data, "night_rats")).is_empty()
	var lines := OrgRules.pay_entry(s, data, "night_rats")
	assert_str(" ".join(lines)).contains("вход оплачен")
	assert_int(int(s.character["gold_cp"])).is_equal(50)
	assert_str(OrgRules.entry_why(s, data, "night_rats")).is_equal("ORG_ENTRY_OPEN")
	s.room_id = "brod-den"
	assert_array(SiteRules.on_enter(s, data, s.room_id)).is_empty()


func test_a_punished_trespass_starts_with_a_warning_again() -> void:
	var s := _hero("brod-tavern-kitchen")
	SiteRules.on_enter(s, data, s.room_id)
	SiteRules.on_enter(s, data, s.room_id)
	assert_int(s.crimes.size()).is_equal(1)
	CrimeRules._settle(s, data, "brod")
	assert_bool(s.trespass_warned.has("brod-tavern")).is_false()
	s.day += 1
	var lines := SiteRules.on_enter(s, data, s.room_id)
	assert_str(" ".join(lines)).contains("Предупреждение")
	assert_int(s.crimes.size()).is_equal(1)


func test_a_burglary_is_seen_only_by_those_who_are_there() -> void:
	var s := _hero("brod-townhall")
	data["rules"]["crime"]["patrol_chance"] = 0.0
	s.minute = 23 * 60  # the clerk is home at night
	assert_array(HeistRules._eyes(s, data, "heist_townhall")).is_empty()
	s.minute = 12 * 60
	assert_array(HeistRules._eyes(s, data, "heist_townhall")).contains(["Тихон Перо"])
	data["rules"]["crime"]["patrol_chance"] = 1.0
	s.minute = 23 * 60
	assert_array(HeistRules._eyes(s, data, "heist_townhall")).contains(["Патруль ополчения"])
