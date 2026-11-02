extends GdUnitTestSuite
## v0.8.4.21: crimes of anybody — a person kills, steals, walks in unasked, forces a door and owes the bank by the hero's
## rules: its witnesses see it, its wanted, guilt and sentence are its own, the rumour names it; what people think of the
## hero, the hero's wanted and hold stay untouched.

const M := "npc_mercenary"
const STRANGER := "npc_hermit"  # lives in the Pushcha: nobody's guest in Brod

var data: Dictionary


func before() -> void:
	data = TestUtils.data()


func _session(hour: int = 12) -> GameSession:
	var s := TestUtils.new_session()
	s.room_id = "brod-square"  # the hero is elsewhere
	s.minute = hour * 60
	return s


func _at(s: GameSession, id: String, room: String) -> void:
	Being.of(s, id)["at"] = room


func test_a_murder_by_a_person_is_its_own() -> void:
	var s := _session()
	_at(s, M, "brod-tavern-hall")
	_at(s, "npc_merchant", "brod-tavern-hall")
	var lines := CrimeRules.on_death(s, data, "npc_merchant", true, "brod-tavern-hall", M)
	var text := " · ".join(lines)
	assert_str(text).contains("Убийство (%s)" % WorldView.name_of(data, M))
	assert_str(str(s.crimes[0]["by"])).is_equal(M)
	if (s.crimes[0]["witnesses"] as Array).is_empty():
		return  # nobody in the hall by the hours: a secret murder, as the hero's
	assert_bool(CrimeRules.wanted_of(s, M).has("brod")).is_true()
	assert_bool(s.wanted.is_empty()).is_true()
	assert_bool(CrimeRules.wanted_at(s, data, "brod-square", M)).is_true()
	assert_bool(CrimeRules.wanted_at(s, data, "brod-square")).is_false()
	assert_int(s.attitude("npc_innkeeper")).is_equal(0)  # what Brod thinks of the hero stays
	assert_int(s.attitude("npc_herbalist")).is_equal(0)
	assert_int(CrimeRules.fine(s, data, "brod", M)).is_greater(0)
	assert_int(CrimeRules.fine(s, data, "brod")).is_equal(0)
	assert_int(int(CrimeRules.sentence(s, data, "brod", M)["days"])).is_greater_equal(0)
	assert_bool(CrimeRules.held(s)).is_false()
	var rumors: Dictionary = RumorRules._state(s)["list"]
	for r: Dictionary in rumors.values():
		assert_str(str(r["text"])).contains(WorldView.name_of(data, M))
	assert_array(Being.check(s)).is_empty()


func test_an_assault_by_a_person_leaves_the_hero_alone() -> void:
	var s := _session()
	_at(s, M, "brod-tavern-hall")
	_at(s, "npc_merchant", "brod-tavern-hall")
	var lines := CrimeRules.on_assault(s, data, "npc_merchant", true, "brod-tavern-hall", M)
	assert_str(" · ".join(lines)).contains("Нападение (%s)" % WorldView.name_of(data, M))
	assert_str(str(s.crimes[0]["kind"])).is_equal("assault")
	assert_str(CrimeRules.doer_of(s.crimes[0])).is_equal(M)
	assert_bool(s.wanted.is_empty()).is_true()
	assert_int(s.attitude("npc_merchant")).is_equal(0)


func test_a_person_picks_pockets_and_is_caught() -> void:
	var s := _session()
	_at(s, M, "brod-tavern-hall")
	_at(s, "npc_merchant", "brod-tavern-hall")
	assert_str(TheftRules.can_steal(s, data, "npc_merchant", M)).is_empty()
	assert_str(TheftRules.can_steal(s, data, M, M)).is_not_empty()  # not its own pockets
	var list: Array = TheftRules.pockets(s, data, "npc_merchant")
	assert_array(list).is_not_empty()
	var entry: Dictionary = list[0]
	var purse := Ledger.balance(s, M)
	var gold := Ledger.balance(s)
	TheftRules.steal(s, data, "npc_merchant", str(entry["id"]), true, M)
	if int(entry.get("cp", 0)) > 0:
		assert_int(Ledger.balance(s, M)).is_equal(purse + int(entry["cp"]))
	else:
		assert_int(Gear.count(s, data, M, str(entry["item_id"]))).is_greater(0)
	assert_int(Ledger.balance(s)).is_equal(gold)
	var rest: Array = TheftRules.pockets(s, data, "npc_merchant")
	if rest.is_empty():
		return
	var lines := TheftRules.steal(s, data, "npc_merchant", str(rest[0]["id"]), false, M)
	assert_str(" · ".join(lines)).contains("замечает руку")
	assert_bool(s.crimes.any(func(c: Dictionary) -> bool: return str(c["kind"]) == "pickpocket" and CrimeRules.doer_of(c) == M)).is_true()
	assert_int(int(Being.view(s, "npc_merchant").get("caught", -1))).is_not_equal(s.day)  # the hero is not the one caught
	assert_bool(s.wanted.is_empty()).is_true()


func test_a_stranger_walks_in_unasked() -> void:
	var s := _session()
	var kitchen := "brod-tavern-kitchen"
	var owner := SiteRules.unwelcome(s, data, kitchen, STRANGER)
	assert_str(owner).is_not_empty()
	assert_str(SiteRules.unwelcome(s, data, kitchen, M)).is_empty()  # it lives at the tavern
	_at(s, STRANGER, kitchen)
	var lines := CrimeRules.on_trespass(s, data, owner, kitchen, ["npc_serving"], STRANGER)
	assert_array(lines).is_not_empty()
	assert_str(CrimeRules.doer_of(s.crimes[0])).is_equal(STRANGER)
	assert_bool(CrimeRules.wanted_of(s, STRANGER).has("brod")).is_true()
	assert_bool(s.wanted.is_empty()).is_true()
	var seen := SiteRules.on_enter(s, data, kitchen, STRANGER)  # who is in the kitchen by the hours decides it
	assert_bool(seen.is_empty() or s.crimes.size() == 2).is_true()


func test_a_door_forced_by_a_person() -> void:
	var s := _session()  # the smith's door by day: damage before the square's eyes
	_at(s, STRANGER, "brod-square")
	assert_str(WayRules.victim(s, data, "brod-square", "brod-smithy", STRANGER)).is_not_empty()
	var seen := WayRules.witnesses(s, data, "brod-square", "brod-smithy", STRANGER)
	assert_array(seen).is_not_empty()
	var lines := WayRules.forced(s, data, "brod-square", "brod-smithy", STRANGER)
	assert_str(lines[0]).starts_with("Видели:")
	assert_bool(s.crimes.any(func(c: Dictionary) -> bool: return str(c["kind"]) == "trespass" and CrimeRules.doer_of(c) == STRANGER)).is_true()
	assert_bool(s.wanted.is_empty()).is_true()


func test_a_person_s_debt_is_its_own_crime_and_is_settled() -> void:
	var s := _session()
	var r := CrimeRules.on_debt(s, data, "npc_changer", "brod", 500, M)
	var id := str(r[0])
	assert_str(CrimeRules.doer_of(s.crimes[0])).is_equal(M)
	assert_bool(CrimeRules.wanted_of(s, M).has("brod")).is_true()
	assert_bool(s.wanted.is_empty()).is_true()
	var lines := CrimeRules.settle_one(s, data, id)
	assert_str(" · ".join(lines)).contains("больше не в розыске")
	assert_bool(CrimeRules.wanted_of(s, M).has("brod")).is_false()
	assert_array(Being.check(s)).is_empty()


func test_the_hero_s_road_is_the_same() -> void:
	var s := _session()
	s.room_id = "brod-tavern-hall"
	CrimeRules.on_death(s, data, "npc_merchant", true, s.room_id)
	assert_str(CrimeRules.doer_of(s.crimes[0])).is_equal(Being.HERO)
	assert_object(CrimeRules.wanted_of(s)).is_same(s.wanted)
	if not (s.crimes[0]["witnesses"] as Array).is_empty():
		assert_bool(s.wanted.has("brod")).is_true()
		assert_int(CrimeRules.fine(s, data, "brod")).is_greater(0)
		assert_int(CrimeRules.fine(s, data, "brod", M)).is_equal(0)
