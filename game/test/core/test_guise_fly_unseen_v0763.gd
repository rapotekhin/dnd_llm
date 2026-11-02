extends GdUnitTestSuite
## v0.7.63, three spells whole: Disguise Self as one of a faction (its people friends, their foes enemies), Fly in a fight,
## invisibility in a fight and out of one: what reaches the engine and what the master is told.

const CULT := "ash_cult"
const FOLK := "brod_folk"

var data: Dictionary


func before() -> void:
	data = TestUtils.data().duplicate(true)


func _hero() -> GameSession:
	var s := TestUtils.new_session()
	s.character["level"] = 5
	s.character["spell_dc"] = 30  # taken in by everyone: what the look does, not the dice
	s.mode = GameSession.MODE_EXPLORATION
	return s


func _disguised(s: GameSession, faction: String = CULT, dc: int = 30) -> void:
	s.character["spell_dc"] = dc
	SpellEffects.apply_self(s, data, "disguise_self", 1)
	var p := Guise.plan(s, data, {"look": "культист в пепельной рясе", "faction": faction}, [] as Array[Dictionary])
	assert_bool(p.has("plan")).override_failure_message(str(p)).is_true()
	Guise.apply(s, data, p["plan"])


func _enc(faction: String, monster: String = "bandit") -> Dictionary:
	return {"id": "enc_test", "faction": faction, "enemies": [{"monster": monster, "count": 2}]}


func _npc_of(s: GameSession, faction: String) -> String:
	for id: String in data["world"]["npcs"]:
		if FactionRules.of_npc(s, data, id) == faction:
			return id
	return ""


# --- Disguise Self ---------------------------------------------------------------------------------------------------


func test_the_spell_lays_a_look_the_master_has_to_name() -> void:
	var s := _hero()
	SpellEffects.apply_self(s, data, "disguise_self", 1)
	assert_str(Guise.face(s.character)).is_empty()
	assert_str(Guise.text(s, data)).contains("облик не назван")
	assert_int(int(Guise.of(s.character)["dc"])).is_equal(30)
	assert_str(Guise.text(s, data)).contains("guise")


func test_no_look_without_a_spell() -> void:
	var s := _hero()
	var p := Guise.plan(s, data, {"look": "старый нищий"}, [] as Array[Dictionary])
	assert_str(str(p.get("reason", ""))).contains("сначала заклинание")


func test_the_look_may_come_in_the_turn_of_the_spell() -> void:
	var s := _hero()
	var pending: Array[Dictionary] = [{"kind": "cast", "plan": {"spell_id": "disguise_self", "slot": 1}}]
	assert_bool(Guise.plan(s, data, {"look": "старый нищий"}, pending).has("plan")).is_true()


func test_no_beast_and_no_unknown_faction() -> void:
	var s := _hero()
	SpellEffects.apply_self(s, data, "disguise_self", 1)
	assert_str(str(Guise.plan(s, data, {"look": "волк", "faction": "wild_beasts"}, [] as Array[Dictionary]).get("reason", ""))).contains("не выдать")
	assert_str(str(Guise.plan(s, data, {"look": "кто-то", "faction": "nobody"}, [] as Array[Dictionary]).get("reason", ""))).contains("фракции nobody нет")


func test_the_master_is_told_the_look_the_faction_and_its_foes() -> void:
	var s := _hero()
	_disguised(s)
	var line := Guise.text(s, data)
	assert_str(line).contains("культист в пепельной рясе").contains(CULT).contains(str(FactionRules.def(s, data, FOLK)["name"]))
	assert_str(str(TurnSnapshot.build(s, data, 2000)["character"]["guise"])).is_equal(line)


func test_the_master_reads_per_person_what_they_took_the_hero_for() -> void:
	var s := _hero()
	_disguised(s)
	var npc := _npc_of(s, FOLK)
	assert_str(Guise.seen_by(s, "npc_somebody_far")).contains("Ещё не присматривался")
	(Guise.of(s.character)["seen"] as Dictionary)[npc] = true
	assert_str(Guise.seen_by(s, npc)).contains("Принимает героя за: культист")
	(Guise.of(s.character)["seen"] as Dictionary)[npc] = false
	assert_str(Guise.seen_by(s, npc)).contains("Разглядел")


func test_the_faction_takes_the_hero_for_its_own_and_keeps_the_peace() -> void:
	var s := _hero()
	assert_bool(FactionRules.peaceful(s, data, _enc(CULT))).is_false()
	_disguised(s)
	assert_bool(FactionRules.peaceful(s, data, _enc(CULT))).is_true()


func test_a_viewer_that_sees_through_fights_and_stays_so() -> void:
	var s := _hero()
	_disguised(s, CULT, 1)  # nobody fails to notice
	assert_bool(FactionRules.peaceful(s, data, _enc(CULT))).is_false()
	s.character["effects"][0]["guise"]["dc"] = 40
	assert_bool(FactionRules.peaceful(s, data, _enc(CULT))).override_failure_message("the answer is kept").is_false()


func test_their_foes_are_the_heros_foes_even_when_they_keep_the_peace_otherwise() -> void:
	var s := _hero()
	var enc := _enc(FOLK)
	assert_bool(FactionRules.peaceful(s, data, enc)).is_true()
	_disguised(s)
	assert_bool(FactionRules.peaceful(s, data, enc)).is_false()


func test_the_foes_go_both_ways() -> void:
	var s := _hero()
	assert_array(FactionRules.foes_of(s, data, FOLK)).contains([CULT])
	assert_array(FactionRules.foes_of(s, data, CULT)).contains([FOLK])


func test_people_of_the_faction_like_the_hero_its_foes_will_not_talk() -> void:
	var s := _hero()
	var folk := _npc_of(s, FOLK)
	var before := s.attitude(folk)
	_disguised(s)
	(Guise.of(s.character)["seen"] as Dictionary)[folk] = true
	ReputationRules.refresh(s, data)
	assert_int(s.attitude(folk)).is_less(before)
	assert_bool(SocialRules.refuses(s, data, folk)).is_true()


func test_the_attitude_comes_back_when_the_look_runs_out() -> void:
	var s := _hero()
	var folk := _npc_of(s, FOLK)
	var before := s.attitude(folk)
	_disguised(s)
	(Guise.of(s.character)["seen"] as Dictionary)[folk] = true
	ReputationRules.refresh(s, data)
	s.character["effects"][0]["ends"] = {"at": 0}
	ConditionRules.expire(s, data)
	assert_bool(Guise.of(s.character).is_empty()).is_true()
	assert_int(s.attitude(folk)).is_equal(before)


func test_private_places_of_the_faction_open_and_its_foes_close() -> void:
	var s := _hero()
	var folk := _npc_of(s, FOLK)
	data["world"]["factions"]["hall"] = {"name": "Дом", "kind": "household", "scope": "global", "foes": ["ash_cult"]}
	var own := {"faction": "ash_cult"}
	_disguised(s)
	assert_bool(FactionRules.welcome(s, data, folk)).is_false()
	data["world"]["npcs"][folk].merge({"faction": "hall"}, true)
	(Guise.of(s.character)["seen"] as Dictionary)[folk] = true
	assert_bool(FactionRules.welcome(s, data, folk)).is_false()
	data["world"]["npcs"][folk].merge(own, true)
	assert_bool(FactionRules.welcome(s, data, folk)).is_true()
	data["world"]["npcs"][folk]["faction"] = FOLK


func test_in_a_mixed_fight_its_people_stand_on_the_heros_side() -> void:
	var s := _hero()
	_disguised(s)
	var foes := [{"monster": "bandit", "faction": CULT, "name": "Культист"}, {"monster": "bandit", "faction": FOLK, "name": "Ополченец"}]
	TestUtils.fight(s, data, foes, {"encounter": "enc_mixed"})
	assert_array(CombatRules.enemies(s).map(func(id: String) -> String: return str(CombatRules.fighter(s, id)["name"]))).contains_exactly(["Ополченец"])
	assert_array(CombatRules.allies(s).map(func(id: String) -> String: return str(CombatRules.fighter(s, id)["name"]))).contains(["Культист"])


func test_a_fight_the_hero_picked_with_them_is_a_fight() -> void:
	var s := _hero()
	_disguised(s)
	TestUtils.fight(s, data, [{"monster": "bandit", "faction": CULT, "name": "Культист"}], {"encounter": "enc_own"})
	assert_int(CombatRules.enemies(s).size()).is_equal(1)


# --- Fly -------------------------------------------------------------------------------------------------------------


func _in_the_air(s: GameSession, monster: String) -> Dictionary:
	TestUtils.fight(s, data, [{"monster": monster, "col": 0}], {})
	SpellEffects.apply_self(s, data, "fly", 3)
	CharacterRules.refresh(s.character, data, s.items)
	var f := CombatRules.fighter(s, CombatRules.enemies(s)[0])
	TestUtils.beside(s, f)
	return f


func test_fly_gives_sixty_feet() -> void:
	var s := _hero()
	SpellEffects.apply_self(s, data, "fly", 3)
	CharacterRules.refresh(s.character, data, s.items)
	assert_int(int(s.character["speed"])).is_equal(60)


func test_a_ground_foe_does_not_reach_the_air_and_a_flier_does() -> void:
	var s := _hero()
	var f := _in_the_air(s, "wolf")
	assert_bool(CombatRules.airborne(s, data, CombatRules.player(s))).is_true()
	assert_bool(Move.air(s, data, f)).is_false()
	var lines: Array[String] = []
	var hp := int(s.character["hp"])
	CombatRules._enemy_turn(s, data, f, lines)
	assert_str("\n".join(lines)).contains("не достаёт летящего героя")
	assert_int(int(s.character["hp"])).is_equal(hp)


func test_a_melee_blow_brings_the_hero_in_reach_until_the_next_turn() -> void:
	var s := _hero()
	var f := _in_the_air(s, "wolf")
	CombatRules.player_attack(s, data, str(f["id"]))
	assert_bool(CombatRules.airborne(s, data, CombatRules.player(s))).override_failure_message("in reach after a melee blow").is_false()
	s.combat["order"] = [CombatRules.PLAYER, str(f["id"])]
	s.combat["turn"] = 0
	var lines: Array[String] = []
	CombatRules._begin_turn(s, data, lines)
	assert_bool(CombatRules.airborne(s, data, CombatRules.player(s))).override_failure_message("in the air again on the hero's turn").is_true()


func test_an_archer_shoots_the_flier() -> void:
	var s := _hero()
	var f := _in_the_air(s, "bandit")
	var lines: Array[String] = []
	CombatRules._enemy_turn(s, data, f, lines)
	assert_str("\n".join(lines)).not_contains("не достаёт летящего героя")


func test_no_blow_in_passing_from_the_ground() -> void:
	var s := _hero()
	var f := _in_the_air(s, "wolf")
	f["status"] = "active"
	var lines := TestUtils.walk(s, data, 1)
	assert_str("\n".join(lines)).not_contains("бьёт вдогонку")


func test_losing_the_concentration_in_the_air_is_a_fall() -> void:
	var s := _hero()
	s.character["hp"] = 200
	s.character["max_hp"] = 200
	_in_the_air(s, "wolf")
	s.character["concentration"] = "fly"
	var lines := ConditionRules.end_concentration(s, data, "удар")
	assert_str("\n".join(lines)).contains("падает")
	assert_int(int(s.character["hp"])).is_less(200)
	assert_bool(ConditionRules.has(s.character, "prone")).is_true()
	assert_bool(CombatRules.airborne(s, data, CombatRules.player(s))).is_false()


func test_fly_ends_on_the_ground_out_of_a_fight_without_a_fall() -> void:
	var s := _hero()
	SpellEffects.apply_self(s, data, "fly", 3)
	s.character["concentration"] = "fly"
	var hp := int(s.character["hp"])
	ConditionRules.end_concentration(s, data, "время вышло")
	assert_int(int(s.character["hp"])).is_equal(hp)


# --- invisibility ----------------------------------------------------------------------------------------------------


func _unseen(s: GameSession) -> void:
	ConditionRules.add_effect(s.character, {"condition": "invisible", "ends_on_attack": true, "ends": {"rest": "long"},
		"source": {"kind": "spell", "id": "invisibility", "name": "Невидимость"}})


func test_the_master_gets_the_condition_by_its_id_even_from_a_held_spell() -> void:
	var s := _hero()
	s.character["concentration"] = "invisibility"
	assert_array(TurnSnapshot.build(s, data, 2000)["character"]["conditions"]).contains(["invisible"])


func test_in_a_fight_the_hero_strikes_with_advantage_and_is_struck_with_disadvantage() -> void:
	var s := _hero()
	TestUtils.fight(s, data, [{"monster": "wolf", "col": 0}], {})
	_unseen(s)
	var t := CombatRules.fighter(s, CombatRules.enemies(s)[0])
	assert_array(CombatRules._attack_mods(s, data, CombatRules.unarmed_profile(s.character, data), t)["adv"]).is_not_empty()
	assert_bool(ConditionRules.invisible(s.character, data)).is_true()


func test_an_attack_ends_the_spell_and_greater_invisibility_stays() -> void:
	var s := _hero()
	_unseen(s)
	ConditionRules.end_invisibility_on_attack(s.character, data)
	assert_bool(ConditionRules.invisible(s.character, data)).is_false()
	s.character["concentration"] = "greater_invisibility"
	ConditionRules.end_invisibility_on_attack(s.character, data)
	assert_bool(ConditionRules.invisible(s.character, data)).is_true()


func test_unseen_goes_through_a_private_place() -> void:
	var s := _hero()
	var room := ""
	var world := WorldView.new(data["world"])
	for r: String in data["world"]["rooms"]:
		s.room_id = r
		if not SiteRules.unwelcome(s, data, r).is_empty():
			room = r
			break
	if room.is_empty():
		return
	assert_bool(world.room(room).is_empty()).is_false()
	s.room_id = room
	_unseen(s)
	assert_array(SiteRules.on_enter(s, data, room)).is_empty()
	assert_array(s.wanted.keys()).is_empty()


func test_a_theft_felt_has_nobody_to_blame() -> void:
	var s := _hero()
	_unseen(s)
	var npc := _npc_of(s, FOLK)
	var before := s.attitude(npc)
	var lines := TheftRules.react(s, data, npc)
	assert_str("\n".join(lines)).contains("вора не видно")
	assert_int(s.attitude(npc)).is_equal(before)
	assert_array(s.wanted.keys()).is_empty()


func test_the_watchers_lose_their_passive_perception() -> void:
	var s := _hero()
	var seen := WeatherRules.unseen(s, data)
	_unseen(s)
	assert_int(WeatherRules.unseen(s, data)).is_equal(seen + int(data["rules"]["invisibility"]["passive_penalty"]))


func test_a_foe_room_is_passed_unseen() -> void:
	var s := _hero()
	_unseen(s)
	s.character["skills"]["stealth"] = 40
	var m := EncounterRules.meet(s, data, s.room_id, "", {"id": "e", "enemies": [{"monster": "wolf", "count": 1}], "faction": "ash_cult"})
	assert_bool(bool(m["fight"])).is_false()
