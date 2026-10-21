extends GdUnitTestSuite
## «Социальный режим 2.0» (roadmap v0.7.15): an NPC remembers facts about the hero — the engine's own (quests of
## this NPC, a caught theft, a known murder) and the master's notes about the NPC — at every meeting, not only the
## summary of the last conversation.

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


func _note(s: GameSession, effect: Dictionary) -> Dictionary:
	var fx := EffectEngine.new()
	var r := fx.validate(s, data, "t-1", effect)
	if bool(r["accepted"]):
		fx.apply(s, "t-1", [r["effect_id"]])
	return r


func test_a_note_about_an_npc_of_the_scene_goes_to_its_memory() -> void:
	var s := _hero("brod-tavern-hall")
	s.day = 2
	var r := _note(s, {"kind": "note", "text": "герой обещал вернуть 5 зм к празднику", "npc_id": "npc_innkeeper"})
	assert_str(str(r["summary"])).contains("запомнит")
	assert_array(s.notes).is_empty()
	assert_array(s.memory_of("npc_innkeeper")).contains_exactly(["день 2 — герой обещал вернуть 5 зм к празднику"])
	var snap := TurnSnapshot.build(s, data, 2000)
	var npc: Dictionary = (snap["scene"]["npcs"] as Array).filter(func(n: Dictionary) -> bool: return n["npc_id"] == "npc_innkeeper")[0]
	assert_array(npc["memory"]).has_size(1)


func test_a_note_about_an_npc_elsewhere_is_refused() -> void:
	var s := _hero("brod-tavern-hall")
	var r := _note(s, {"kind": "note", "text": "герой нагрубил кузнецу", "npc_id": "npc_smith"})
	assert_bool(bool(r["accepted"])).is_false()
	assert_str(str(r["reason"])).contains("нет в этой комнате")
	var plain := _note(s, {"kind": "note", "text": "в трактире пахнет гарью", "npc_id": null})
	assert_bool(bool(plain["accepted"])).is_true()
	assert_array(s.notes).has_size(1)


func test_the_engine_records_quests_thefts_and_murders() -> void:
	var s := _hero("brod-tavern-hall")
	QuestRules.accept(s, data, "letter_to_ilva")
	assert_str(" ".join(s.memory_of("npc_innkeeper"))).contains("взял задание")
	TheftRules.react(s, data, "npc_serving")
	assert_str(" ".join(s.memory_of("npc_serving"))).contains("поймала героя на краже")
	CrimeRules.on_death(s, data, "npc_mercenary", true, s.room_id)
	assert_str(" ".join(s.memory_of("npc_herbalist"))).contains("убита героем")
	assert_array(s.memory_of("npc_hermit")).is_empty()  # another location


func test_memory_keeps_the_newest_once_and_survives_a_save() -> void:
	var s := _hero("brod-square")
	for i in GameSession.NPC_MEMORY_MAX + 3:
		s.remember("npc_merchant", "факт %d" % i)
	s.remember("npc_merchant", "факт %d" % (GameSession.NPC_MEMORY_MAX + 2))
	assert_array(s.memory_of("npc_merchant")).has_size(GameSession.NPC_MEMORY_MAX)
	assert_array(s.memory_of("npc_merchant", 2)).has_size(2)
	var back := GameSession.from_dict(s.to_dict(50))
	assert_array(back.memory_of("npc_merchant")).is_equal(s.memory_of("npc_merchant"))


func test_old_saves_start_with_empty_memories() -> void:
	var v23 := {"save_version": 23, "session": {"day": 2}}
	SaveFormat._v23_to_v24(v23, {})
	assert_dict(v23["session"]["npc_memory"]).is_empty()
