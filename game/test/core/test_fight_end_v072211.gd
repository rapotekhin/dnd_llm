extends GdUnitTestSuite
## The end of a fight (roadmap v0.7.22.11): fists with a weapon in hand; a nonlethal blow knocks out; the beaten foes
## stay in the room — bound, led along, freed, attacked again; left alone they go.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _hero() -> GameSession:
	var s := TestUtils.new_session()
	for p: Dictionary in data["presets"]:
		if p["id"] == "fighter_aira":
			s.character = GameSession.normalized_character(CharacterBuilder.build_preset(p, data))
	CharacterRules.refresh(s.character, data, s.items)
	s.room_id = "brod-tavern-hall"
	return s


func _fight(s: GameSession, foes: Array) -> Array[Dictionary]:
	CombatRules.start(s, data, foes, {})
	var order: Array = s.combat["order"]
	order.erase(CombatRules.PLAYER)
	order.push_front(CombatRules.PLAYER)
	s.combat["turn"] = 0
	CombatRules._begin_turn(s, data, [] as Array[String])
	s.mode = GameSession.MODE_COMBAT
	var out: Array[Dictionary] = []
	for id: String in CombatRules.enemies(s):
		out.append(CombatRules.fighter(s, id))
	return out


func test_fists_with_a_sword_in_hand() -> void:
	var s := _hero()
	var f := _fight(s, [{"monster": "goblin", "col": 0}])[0]
	f["col"] = int(CombatRules.player(s)["col"])
	assert_str(CombatRules.can_attack(s, data, str(f["id"]), false, true)).is_empty()
	var lines := CombatRules.player_attack(s, data, str(f["id"]), false, false, true)
	assert_str(" · ".join(lines)).contains("Безоружный удар")


func test_a_nonlethal_blow_knocks_out() -> void:
	var s := _hero()
	var f := _fight(s, [{"monster": "goblin", "col": 0}])[0]
	f["col"] = int(CombatRules.player(s)["col"])
	s.combat["nonlethal"] = true
	s.combat["melee_strike"] = true
	var lines: Array[String] = []
	CombatRules._hurt_enemy(s, data, f, 999, lines)
	assert_str(str(f["status"])).is_equal("unconscious")
	s.combat.erase("melee_strike")
	assert_bool(CombatRules.enemies(s).is_empty()).is_true()


func test_the_beaten_stay_and_can_be_bound_and_led() -> void:
	var s := _hero()
	var foes := _fight(s, [{"monster": "goblin", "count": 3, "col": 0}])
	foes[0]["status"] = "surrendered"
	foes[1]["status"] = "unconscious"
	foes[2]["status"] = "dead"
	var lines := CreatureRules.after_fight(s, data, s.room_id)
	assert_int(CreatureRules.here(s, s.room_id).size()).is_equal(2)
	assert_str(" · ".join(lines)).contains("сдался")
	var id := str(CreatureRules.here(s, s.room_id)[0]["id"])
	assert_str(CreatureRules.can(s, id, "lead")).is_equal("CREATURE_NOT_BOUND")
	CreatureRules.act(s, data, id, "bind")
	CreatureRules.act(s, data, id, "lead")
	CreatureRules.follow(s, s.room_id, "brod-square")
	assert_int(CreatureRules.here(s, "brod-square").size()).is_equal(1)
	assert_int(CreatureRules.here(s, "brod-tavern-hall").size()).is_equal(1)
	TimeRules.advance(s, data, 200)  # the knocked-out one wakes and slips away; the bound one stays
	assert_int(CreatureRules.here(s, "brod-tavern-hall").size()).is_equal(0)
	assert_int(CreatureRules.here(s, "brod-square").size()).is_equal(1)
	var back := GameSession.from_dict(s.to_dict(5))
	assert_int(CreatureRules.here(back, "brod-square").size()).is_equal(1)


func test_attacking_a_creature_again_is_a_fight() -> void:
	var s := _hero()
	var foes := _fight(s, [{"monster": "goblin", "col": 0}])
	foes[0]["status"] = "truce"
	CreatureRules.after_fight(s, data, s.room_id)
	s.combat = {}
	var id := str(CreatureRules.here(s, s.room_id)[0]["id"])
	assert_str(CreatureRules.can(s, id, "bind")).is_equal("CREATURE_CANNOT_BIND")  # a truce is kept
	CreatureRules.act(s, data, id, "attack")
	assert_bool(s.pending_fight.is_empty()).is_false()
	assert_bool(CreatureRules.here(s, s.room_id).is_empty()).is_true()
