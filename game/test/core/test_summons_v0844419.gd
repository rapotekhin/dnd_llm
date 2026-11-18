extends GdUnitTestSuite
## v0.8.4.44.19, the author's notes on the tutorial: a creature a spell called walks on the map out of a fight; one let go,
## replaced or run out in a fight leaves the field without a hole in the queue («что за два null в списке боя?»); a
## companion's blow with a weapon taken up from its other set strikes by its own name («<null> по …»); one healed lies
## prone in a fight as in 5e and gets up when the fight ends (its token stayed flat for ever).

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _session() -> GameSession:
	var s := TestUtils.new_session()
	for p: Dictionary in data["presets"]:
		if p["id"] == "fighter_aira":
			s.character = GameSession.normalized_character(CharacterBuilder.build_preset(p, data))
	CharacterRules.refresh(s.character, data, s.items)
	s.room_id = "brod-tavern-hall"
	return s


## Every id of the queue is a fighter with a name: the queue never shows «<null>».
func _whole_queue(s: GameSession) -> void:
	for id: Variant in s.combat.get("order", []):
		var f := CombatRules.fighter(s, str(id))
		assert_dict(f).override_failure_message("no fighter for %s" % id).is_not_empty()
		assert_str(str(f.get("name", ""))).is_not_empty()


func test_a_summoned_creature_stands_on_the_map_out_of_a_fight() -> void:
	var s := _session()
	AllyRules.summon(s, data, "mage_hand")
	var hand: Dictionary = AllyRules.called(s)[0]
	var refs := MapSpots.party(s, data).map(func(t: Dictionary) -> String: return str(t["ref"]))
	assert_array(refs).contains(["summon:" + str(hand["id"])])
	AllyRules.dismiss(s, str(hand["id"]))
	assert_array(MapSpots.party(s, data).map(func(t: Dictionary) -> String: return str(t["ref"]))).not_contains(["summon:" + str(hand["id"])])


func test_one_called_again_in_a_fight_leaves_no_hole_in_the_queue() -> void:
	var s := _session()
	CombatRules.start(s, data, [{"monster": "wolf", "name": "Волк"}], {})
	AllyRules.summon(s, data, "mage_hand")
	var first := str(AllyRules.called(s)[0]["id"])
	AllyRules.summon(s, data, "mage_hand")  # one hand at a time: the new one replaces the old
	var second := str(AllyRules.called(s)[0]["id"])
	assert_str(second).is_not_equal(first)
	assert_int(AllyRules.called(s).size()).is_equal(1)
	_whole_queue(s)
	assert_str(str(CombatRules.fighter(s, first)["status"])).is_equal("gone")  # off the field, its record kept to the end
	assert_str(str(CombatRules.fighter(s, second)["status"])).is_equal("active")
	AllyRules.dismiss(s, second)
	_whole_queue(s)
	CombatRules.close(s)
	assert_dict(Being.view(s, first)).is_empty()  # the fight's end forgets them
	assert_dict(Being.view(s, second)).is_empty()


func test_one_run_out_in_a_fight_leaves_the_field_and_the_queue_whole() -> void:
	var s := _session()
	CombatRules.start(s, data, [{"monster": "wolf", "name": "Волк"}], {})
	AllyRules.summon(s, data, "mage_hand")
	var id := str(AllyRules.called(s)[0]["id"])
	TimeRules.advance(s, data, 2)  # Mage Hand lasts a minute
	assert_array(AllyRules.called(s)).is_empty()
	_whole_queue(s)
	assert_str(str(CombatRules.fighter(s, id)["status"])).is_equal("gone")


func test_a_companion_strikes_with_a_weapon_taken_up_by_its_own_name() -> void:
	var s := _session()
	Being.follow(s, "npc_veteran")
	Gear.take(s, data, "npc_veteran", "spear")  # its template's weapon lost: the hand's blow takes up that one's name
	Gear.give(s, data, "npc_veteran", "scimitar")
	Equip.put(s, data, "npc_veteran", "scimitar", "main_hand", true)
	CombatRules.start(s, data, [{"monster": "wolf", "name": "Волк"}], {})
	var f := CombatRules.fighter(s, "npc_veteran")
	var wolf := str(CombatRules.foes_of(s, f)[0])
	FightGrid.put(f, FightGrid.free_near(s, data, FightGrid.cell(CombatRules.fighter(s, wolf)), 1))
	assert_str(Acts.one("attack").why(s, data, f, wolf, {"action": "scimitar"})).is_empty()
	var lines := Acts.one("attack").go(s, data, f, wolf, {"action": "scimitar"})  # the bar's button: «Blow_scimitar»
	assert_str(" | ".join(lines)).contains("берёт в руки: Ятаган")
	assert_str(" | ".join(lines)).contains("— Ятаган по Волк")
	assert_str(" | ".join(lines)).not_contains("<null>")


func test_one_healed_from_nothing_gets_up_when_the_fight_ends() -> void:
	var s := _session()
	CombatRules.start(s, data, [{"monster": "wolf", "name": "Волк"}], {})
	var lines: Array[String] = []
	Harm.take(s, data, CombatRules.player(s), int(s.character["hp"]) + 1, lines)
	assert_bool(ConditionRules.has(s.character, "prone")).is_true()
	Harm.mend(s, data, Sheet.HERO, 5)
	assert_bool(ConditionRules.has(s.character, "unconscious")).is_false()
	assert_bool(ConditionRules.has(s.character, "prone")).is_true()  # 5e: up from nothing, still lying — «Встать»
	CombatRules.close(s)
	assert_bool(ConditionRules.has(s.character, "prone")).is_false()  # out of a fight one gets up for nothing
