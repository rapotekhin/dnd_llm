extends GdUnitTestSuite
## A knocked-out creature comes to (v0.8.4.42.21, the author: «пленники остаются без сознания даже после долгого
## отдыха»): 5e — stable at 0 HP, 1 HP in 1d4 hours (rules.creatures.wake_hours), sooner when a night's rest heals it.
## One road for any creature of a room: unbound it slips away, bound it stays the hero's prisoner and tries its bonds
## only once awake.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _knocked_out(room: String = "brod-tavern-hall") -> GameSession:
	var s := TestUtils.new_session()
	for p: Dictionary in data["presets"]:
		if p["id"] == "fighter_aira":
			s.character = GameSession.normalized_character(CharacterBuilder.build_preset(p, data))
	CharacterRules.refresh(s.character, data, s.items)
	s.room_id = room
	TestUtils.fight(s, data, [{"monster": "goblin", "col": 0}], {})
	var f := CombatRules.fighter(s, CombatRules.enemies(s)[0])
	f["hp"] = 0
	f["status"] = "unconscious"
	s.combat["outcome"] = "victory"
	CreatureRules.after_fight(s, data, s.room_id)
	CombatRules.close(s)
	s.combat = {}
	s.mode = GameSession.MODE_EXPLORATION
	return s


func _the(s: GameSession) -> Dictionary:
	return CreatureRules.all(s)[0] if not CreatureRules.all(s).is_empty() else {}


func test_the_hour_it_comes_to_is_rolled_at_the_blow() -> void:
	var s := _knocked_out()
	var c := _the(s)
	var after := int(c["wakes"]) - int(c["since"])
	assert_int(after).is_between(60, 240)
	assert_int(after % 60).is_equal(0)


func test_a_bound_prisoner_comes_to_and_stays_bound() -> void:
	var s := _knocked_out()
	var c := _the(s)
	CreatureRules.act(s, data, str(c["id"]), "bind")
	assert_str(CreatureRules.can(s, str(c["id"]), "talk", data)).is_equal("CREATURE_CANNOT_TALK")
	var lines := TimeRules.advance(s, data, 241)
	c = _the(s)
	assert_str(str(c["state"])).is_equal("surrendered")
	assert_bool(bool(c["bound"])).is_true()
	assert_str(str(c["owner"])).is_equal(OwnerRules.HERO)
	assert_int(int(c["hp"])).is_equal(1)
	assert_bool(c.has("wakes")).is_false()
	assert_str(" · ".join(lines)).contains("приходит в себя — связан")
	assert_str(CreatureRules.can(s, str(c["id"]), "talk", data)).is_empty()  # awake, it speaks
	assert_str(CreatureRules.can(s, str(c["id"]), "finish", data)).is_empty()  # still helpless: bound
	assert_str(CreatureRules.text(c, data)).contains("сдался, связан")


func test_a_long_rest_wakes_it_for_sure() -> void:
	var s := _knocked_out()
	var c := _the(s)
	CreatureRules.act(s, data, str(c["id"]), "bind")
	TimeRules.sleep(s, data, TimeRules.abs_minute(s))
	c = _the(s)
	assert_str(str(c["state"])).is_equal("surrendered")
	assert_bool(bool(c["bound"])).is_true()


func test_a_nights_healing_wakes_it_before_its_hour() -> void:
	var s := _knocked_out()
	var c := _the(s)
	CreatureRules.act(s, data, str(c["id"]), "bind")
	c["wakes"] = TimeRules.abs_minute(s) + 10000
	Rest.long(s, data, str(c["id"]))  # the world's night: its wounds whole
	CreatureRules.tick(s, data)
	assert_str(str(_the(s)["state"])).is_equal("surrendered")
	assert_int(int(_the(s)["hp"])).is_equal(int(_the(s)["max_hp"]))


func test_an_unbound_one_comes_to_and_slips_away() -> void:
	var s := _knocked_out()
	var c := _the(s)
	c["wakes"] = TimeRules.abs_minute(s) + 120
	TimeRules.advance(s, data, 119)
	assert_str(str(_the(s)["state"])).is_equal("unconscious")  # not before its hour
	var lines := TimeRules.advance(s, data, 2)
	assert_array(CreatureRules.all(s)).is_empty()
	assert_str(" · ".join(lines)).contains("приходит в себя и уходит")


func test_one_lying_does_not_try_its_bonds() -> void:
	var s := _knocked_out()
	var c := _the(s)
	CreatureRules.act(s, data, str(c["id"]), "bind")
	c["wakes"] = TimeRules.abs_minute(s) + 100000
	s.room_id = "brod-square"  # left unwatched past leave_minutes.bound many times
	for i in 3:
		TimeRules.advance(s, data, int(data["rules"]["creatures"]["leave_minutes"]["bound"]) + 1)
	c = _the(s)
	assert_str(str(c["state"])).is_equal("unconscious")
	assert_bool(bool(c["bound"])).is_true()
