extends GdUnitTestSuite
## A prisoner hears and remembers (v0.8.4.42.26, the author's trace: the master's `note` about a bound Mira was refused
## — «NPC npc_serving нет в этой комнате»). A pack NPC held as a creature of the room is no person of the scene, yet
## once awake it remembers, takes offence and gives up a secret: `GameSession.minds_here` for note, attitude, secret.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _captive() -> GameSession:
	var s := TestUtils.new_session()
	for p: Dictionary in data["presets"]:
		if p["id"] == "fighter_aira":
			s.character = GameSession.normalized_character(CharacterBuilder.build_preset(p, data))
	CharacterRules.refresh(s.character, data, s.items)
	s.room_id = "brod-tavern-upstairs"
	TestUtils.fight(s, data, [{"monster": "commoner", "name": "Мира", "npc_id": "npc_serving", "by_hero": true, "col": 0}], {})
	var f := CombatRules.fighter(s, CombatRules.enemies(s)[0])
	f["status"] = "unconscious"
	f["hp"] = 0
	s.combat["outcome"] = "victory"
	CreatureRules.after_fight(s, data, s.room_id)
	CombatRules.close(s)
	s.combat = {}
	s.mode = GameSession.MODE_EXPLORATION
	return s


func _note(s: GameSession) -> Dictionary:
	return EffectEngine.new().validate(s, data, "t-1", {"kind": "note", "npc_id": "npc_serving", "text": "Герой допрашивал Миру связанной"})


func test_a_knocked_out_one_remembers_nothing() -> void:
	var s := _captive()
	assert_bool(s.held_as_creature("npc_serving")).is_true()
	assert_bool(s.minds_here(data["world"], s.room_id).has("npc_serving")).is_false()
	assert_bool(bool(_note(s)["accepted"])).is_false()


func test_a_bound_prisoner_awake_remembers_and_takes_offence() -> void:
	var s := _captive()
	var c: Dictionary = CreatureRules.here(s, s.room_id)[0]
	CreatureRules.act(s, data, str(c["id"]), "bind")
	TimeRules.advance(s, data, 241)  # comes to, still bound (v0.8.4.42.21)
	assert_bool(s.held_as_creature("npc_serving")).is_true()
	assert_bool(s.npcs_here(data["world"], s.room_id).has("npc_serving")).is_false()  # no person of the scene
	assert_bool(s.minds_here(data["world"], s.room_id).has("npc_serving")).is_true()
	var fx := EffectEngine.new()
	var r := fx.validate(s, data, "t-1", {"kind": "note", "npc_id": "npc_serving", "text": "Герой допрашивал Миру связанной"})
	assert_bool(bool(r["accepted"])).is_true()
	fx.apply(s, "t-1", [r["effect_id"]])
	assert_str(" ".join(s.memory_of("npc_serving"))).contains("допрашивал Миру")
	var before := s.attitude("npc_serving")
	var a := fx.validate(s, data, "t-2", {"kind": "shift", "what": "attitude", "npc_id": "npc_serving", "delta": -1, "reason": "угрозы"})
	assert_bool(bool(a["accepted"])).is_true()
	fx.apply(s, "t-2", [a["effect_id"]])
	assert_int(s.attitude("npc_serving")).is_less(before)
	s.room_id = "brod-tavern-hall"  # not where she lies
	assert_bool(bool(_note(s)["accepted"])).is_false()
