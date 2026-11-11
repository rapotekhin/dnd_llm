extends GdUnitTestSuite
## v0.8.4.43.11, the author's feedback on 0.8.4.43.8 — companions in a fight are the player's: one of the hero's party (a
## follower, its own beast, a creature it called) waits in its turn for the player's buttons as the hero does
## (CombatRules.driven, actor); an ally of the encounter, the militia, keeps the AI. The turn is ended by the same road
## (end_player_turn finishes whoever's turn it is), a blow of anybody is previewed by its own numbers (blow_preview), a
## familiar that only helps does not strike on its own.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _fight(drive: bool) -> GameSession:
	var s := TestUtils.new_session()
	for p: Dictionary in data["presets"]:
		if p["id"] == "fighter_aira":
			s.character = GameSession.normalized_character(CharacterBuilder.build_preset(p, data))
	CharacterRules.refresh(s.character, data, s.items)
	s.room_id = "brod-tavern-hall"
	Being.follow(s, "npc_veteran")
	CombatRules.start(s, data, [{"monster": "wolf", "name": "Волк"}], {"allies": [{"monster": "guard", "name": "Ополченец"}]})
	if drive:
		s.combat["drive"] = true
	return s


func _militia(s: GameSession) -> String:
	for id: String in CombatRules.allies(s, false):
		if str(CombatRules.fighter(s, id)["name"]) == "Ополченец":
			return id
	return ""


## `f` stands beside `o`.
func _beside(s: GameSession, f: Dictionary, o: Dictionary) -> void:
	FightGrid.put(f, FightGrid.free_near(s, data, FightGrid.cell(o) + Vector2i(1, 0), int(f.get("span", 1))))
	assert_int(FightGrid.dist(f, o)).is_equal(1)


## Plays the others until `id`'s turn: the hero's turn is ended, the rest go by next_actor.
func _until(s: GameSession, id: String) -> void:
	var guard := 0
	while CombatRules.current(s) != id and guard < 30 and str(s.combat.get("outcome", "")).is_empty():
		guard += 1
		if CombatRules.is_player_turn(s) or not CombatRules.actor(s).is_empty():
			CombatRules.end_player_turn(s, data)
		else:
			CombatRules.next_actor(s, data)


func test_the_party_is_driven_only_in_the_game_s_fight_and_never_the_militia() -> void:
	var s := _fight(false)
	var her := CombatRules.fighter(s, "npc_veteran")
	assert_bool(CombatRules.driven(s, her)).is_false()  # a test's or a balance run's fight: the AI as before
	s.combat["drive"] = true
	assert_bool(CombatRules.driven(s, her)).is_true()
	assert_bool(CombatRules.driven(s, CombatRules.fighter(s, _militia(s)))).is_false()
	assert_bool(CombatRules.driven(s, CombatRules.player(s))).is_false()  # the hero is the hero: player_can_act


func test_a_companion_s_turn_waits_for_the_buttons() -> void:
	var s := _fight(true)
	_until(s, "npc_veteran")
	assert_str(CombatRules.current(s)).is_equal("npc_veteran")
	var her := CombatRules.fighter(s, "npc_veteran")
	var at := FightGrid.cell(her)
	assert_dict(CombatRules.actor(s)).is_same(her)
	assert_bool(CombatRules.player_can_act(s)).is_false()  # the hero's own buttons are for the hero's turn
	assert_array(CombatRules.next_actor(s, data)).is_empty()  # nothing by the AI: it is still her turn
	assert_str(CombatRules.current(s)).is_equal("npc_veteran")
	assert_that(FightGrid.cell(her)).is_equal(at)
	CombatRules.end_player_turn(s, data)  # «Конец хода» from her side
	assert_str(CombatRules.current(s)).is_not_equal("npc_veteran")


func test_the_militia_s_turn_goes_by_the_ai() -> void:
	var s := _fight(true)
	var m := _militia(s)
	_until(s, m)
	assert_dict(CombatRules.actor(s)).is_empty()
	CombatRules.next_actor(s, data)
	assert_str(CombatRules.current(s)).is_not_equal(m)


func test_a_companion_strikes_by_its_own_blow_and_its_preview() -> void:
	var s := _fight(true)
	_until(s, "npc_veteran")
	var her := CombatRules.fighter(s, "npc_veteran")
	var wolf := CombatRules.fighter(s, CombatRules.enemies(s)[0])
	_beside(s, wolf, her)
	var blow := ""
	for a: Dictionary in Sheet.template(data, her)["actions"]:
		if str(a.get("kind")) == "melee":
			blow = str(a["name_en"])
			break
	assert_str(blow).is_not_empty()
	var how := {"action": blow}
	var pv := CombatRules.blow_preview(s, data, her, str(wolf["id"]), how)
	assert_int(int(pv["chance"])).is_between(5, 95)
	assert_int(int(pv["max"])).is_greater_equal(int(pv["min"]))
	assert_str(Acts.one("attack").can(s, data, her, str(wolf["id"]), how)).is_empty()
	var lines := Acts.one("attack").go(s, data, her, str(wolf["id"]), how)
	assert_bool(lines.any(func(l: String) -> bool: return l.begins_with(str(her["name"])))).is_true()


func test_the_hero_s_preview_is_the_same_by_the_one_road() -> void:
	var s := _fight(false)
	var wolf := CombatRules.enemies(s)[0]
	var old := CombatRules.attack_preview(s, data, wolf)
	var now := CombatRules.blow_preview(s, data, CombatRules.player(s), wolf, {})
	assert_int(int(now["chance"])).is_equal(int(old["chance"]))
	assert_int(int(now["min"])).is_equal(int(old["min"]))
	assert_int(int(now["max"])).is_equal(int(old["max"]))


func test_a_familiar_that_helps_does_not_strike_on_its_own() -> void:
	var s := _fight(true)
	CombatRules.summon_for(s, data, CombatRules.player(s), "find_familiar")
	var fam := {}
	for id: String in CombatRules.allies(s, false):
		if bool(CombatRules.fighter(s, id).get("helper", false)):
			fam = CombatRules.fighter(s, id)
	assert_dict(fam).is_not_empty()
	assert_bool(CombatRules.driven(s, fam)).is_true()
	_until(s, str(fam["id"]))
	var wolf := CombatRules.fighter(s, CombatRules.enemies(s)[0])
	_beside(s, wolf, fam)
	var bite := str((Sheet.template(data, fam)["actions"] as Array)[0]["name_en"])
	assert_str(Acts.one("attack").can(s, data, fam, str(wolf["id"]), {"action": bite})).is_equal("COMBAT_HELPER_NO_ATTACK")
	assert_str(Acts.one("help").can(s, data, fam, str(wolf["id"]))).is_empty()
