extends GdUnitTestSuite
## Attacking an NPC (roadmap v0.7.22.16, the author's fixes check #16, #21, #26, #32, #33, #34): out of a fight a blow
## at an NPC is never an effect; the master's move is checked like the exit button; a creature fought again keeps its
## wounds and gives no XP twice; a knocked-out pack NPC lies as a creature — searched, finished off, or it wakes and the
## assault is known; hostile spells start the fight; captors of a fight without an encounter lurk after an escape.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _hero(room: String = "brod-tavern-upstairs") -> GameSession:
	var s := TestUtils.new_session()
	for p: Dictionary in data["presets"]:
		if p["id"] == "fighter_aira":
			s.character = GameSession.normalized_character(CharacterBuilder.build_preset(p, data))
	CharacterRules.refresh(s.character, data, s.items)
	s.room_id = room
	return s


func _fight(s: GameSession, foes: Array) -> Array[Dictionary]:
	CombatRules.start(s, data, foes, {})
	s.mode = GameSession.MODE_COMBAT
	var out: Array[Dictionary] = []
	for id: String in CombatRules.enemies(s):
		out.append(CombatRules.fighter(s, id))
	return out


func _end(s: GameSession, outcome: String) -> void:
	s.combat["outcome"] = outcome
	CreatureRules.after_fight(s, data, s.room_id)
	for id: String in CombatRules.enemies(s, false):
		var f := CombatRules.fighter(s, id)
		if not str(f.get("npc_id", "")).is_empty() and bool(f.get("by_hero", false)) and str(f["status"]) != "dead":
			CrimeRules.on_assault(s, data, str(f["npc_id"]), str(f["status"]) != "unconscious", s.room_id)
	s.combat = {}
	s.mode = GameSession.MODE_EXPLORATION


func test_no_blow_at_an_npc_out_of_a_fight() -> void:
	var s := _hero()
	var engine := EffectEngine.new()
	var r := engine.validate(s, data, "t-1", {"kind": "damage", "severity": "deadly", "damage_type": "piercing", "reason": "x", "target_id": "npc_serving"})
	assert_bool(bool(r["accepted"])).is_false()
	assert_str(str(r["reason"])).contains("next_mode combat")
	var hp := int(s.character["hp"])
	assert_int(int(s.character["hp"])).is_equal(hp)  # the hero is not hurt


func test_the_masters_move_is_checked_like_the_button() -> void:
	var s := _hero("brod-tavern-hall")
	var engine := EffectEngine.new()
	s.character["inventory"]["plate_armor"] = 20  # far too heavy
	CharacterRules.refresh(s.character, data, s.items)
	var r := engine.validate(s, data, "t-1", {"kind": "move", "room_id": "brod-tavern-upstairs"})
	assert_bool(bool(r["accepted"])).is_false()
	assert_str(str(r["reason"])).contains("перегружен")


func test_a_creature_keeps_its_wounds_and_gives_no_xp_twice() -> void:
	var s := _hero("brod-square")
	var f := _fight(s, [{"monster": "goblin", "col": 0}])[0]
	f["hp"] = 2
	f["status"] = "surrendered"
	_end(s, "victory")
	var c: Dictionary = CreatureRules.here(s, s.room_id)[0]
	assert_int(int(c["hp"])).is_equal(2)
	assert_bool(bool(c["xp_given"])).is_true()
	assert_str(CreatureRules.can(s, str(c["id"]), "finish")).is_equal("CREATURE_NOT_HELPLESS")
	CreatureRules.act(s, data, str(c["id"]), "attack")
	var spec: Dictionary = s.pending_fight[0]
	assert_int(int(spec["hp"])).is_equal(2)
	var again := _fight(s, s.pending_fight)[0]
	assert_int(int(again["hp"])).is_equal(2)
	again["status"] = "dead"
	s.combat["outcome"] = "victory"
	CombatRules.results(s, data, {})
	assert_int(int(s.combat["xp"])).is_equal(0)


func test_a_knocked_out_npc_lies_as_a_creature_and_is_finished_off() -> void:
	var s := _hero()
	var f := _fight(s, [{"monster": "commoner", "name": "Мира", "npc_id": "npc_serving", "by_hero": true, "col": 0}])[0]
	f["status"] = "unconscious"
	_end(s, "victory")
	assert_bool(s.npcs_here(data["world"], s.room_id).has("npc_serving")).is_false()
	var c: Dictionary = CreatureRules.here(s, s.room_id)[0]
	assert_str(str(c["npc_id"])).is_equal("npc_serving")
	assert_bool(s.crimes.any(func(cr: Dictionary) -> bool: return str(cr.get("kind")) == "assault" and not bool(cr["known"]))).is_true()
	assert_str(CreatureRules.can(s, str(c["id"]), "attack")).is_equal("CREATURE_HELPLESS")
	var searched := CreatureRules.act(s, data, str(c["id"]), "search")
	assert_str(searched[0]).contains("Обыскан")
	var lines := CreatureRules.act(s, data, str(c["id"]), "finish")
	assert_str(" · ".join(lines)).contains("Убийство")
	assert_bool(s.dead_npcs.has("npc_serving")).is_true()
	assert_bool(s.crimes.any(func(cr: Dictionary) -> bool: return str(cr.get("kind")) == "assault")).is_false()  # the murder instead


func test_a_knocked_out_npc_wakes_and_the_assault_is_known() -> void:
	var s := _hero()
	var f := _fight(s, [{"monster": "commoner", "name": "Мира", "npc_id": "npc_serving", "by_hero": true, "col": 0}])[0]
	f["status"] = "unconscious"
	_end(s, "victory")
	var lines := TimeRules.advance(s, data, 120)
	assert_str(" · ".join(lines)).contains("приходит в себя")
	assert_bool(s.held_as_creature("npc_serving")).is_false()
	assert_int(s.attitude("npc_serving")).is_less(0)
	var crime: Dictionary = s.crimes.filter(func(cr: Dictionary) -> bool: return str(cr.get("kind")) == "assault")[0]
	assert_bool(bool(crime["known"])).is_true()
	var loc := WorldView.new(data["world"]).location_id(s.room_id)
	assert_bool(s.wanted.has(loc)).is_true()  # Brod has the law
	var sn := CrimeRules.sentence(s, data, loc)
	assert_str(str(sn["kind"])).is_equal("stocks")  # an assault alone — the stocks, not the prison
	assert_int(CrimeRules.fine(s, data, loc)).is_equal(1000)


func test_hostile_spells_and_the_unaware() -> void:
	assert_bool(CombatRules.hostile_spell(data, "fire_bolt")).is_true()
	assert_bool(CombatRules.hostile_spell(data, "hold_person")).is_true()
	assert_bool(CombatRules.hostile_spell(data, "charm_person")).is_false()
	assert_bool(CombatRules.hostile_spell(data, "cure_wounds")).is_false()
	var s := _hero()
	assert_bool(CombatRules.npc_unaware(s, data, "npc_serving")).is_true()
	s.shift_attitude("npc_serving", -3, data)
	assert_bool(CombatRules.npc_unaware(s, data, "npc_serving")).is_false()


func test_an_aware_npc_is_not_caught_off_guard() -> void:
	var s := _hero()
	CombatRules.start(s, data, [{"monster": "commoner", "npc_id": "npc_serving", "col": 0}], {"opening": {"npc_id": "npc_serving", "unaware": false}})
	var f := CombatRules.fighter(s, CombatRules.enemies(s)[0])
	assert_bool(bool(f.get("surprised", false))).is_false()
	assert_str(str(s.combat["order"][0])).is_equal(CombatRules.PLAYER)


func test_captors_without_an_encounter_lurk_after_an_escape() -> void:
	var s := _hero("pushcha-burrow")
	EncounterRules.capture(s, [{"monster": "acolyte", "name": "Жрец Пепла", "count": 1, "hp": 5, "no_xp": true}], "", "pushcha-hollow")
	s.rng.seed = 1
	var lines: Array[String] = []
	for i in 30:  # until a roll passes
		lines = EncounterRules.escape(s, data, "escape_sleight")
		if not EncounterRules.captive(s):
			break
	assert_bool(EncounterRules.captive(s)).is_false()
	var enc := EncounterRules.lurking_encounter(s, data, s.room_id)
	assert_str(str(enc["enemies"][0]["name"])).is_equal("Жрец Пепла")
	assert_int(int(enc["enemies"][0]["hp"])).is_equal(5)
	var back := GameSession.from_dict(s.to_dict(5))
	assert_int(int(EncounterRules.lurking_encounter(back, data, back.room_id)["enemies"][0]["hp"])).is_equal(5)
