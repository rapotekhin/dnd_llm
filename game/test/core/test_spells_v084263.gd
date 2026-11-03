extends GdUnitTestSuite
## The last spells of the checklist on the engine (roadmap v0.8.4.26.3): death saves of anybody of the hero's side and
## Spare the Dying, Warding Bond through Harm, Sending as a letter of the hero itself, Mage Hand's reach, Magic Circle
## bound to its room, Zone of Truth on the NPC's save, Glyph of Warding as a zone of the fight, Gentle Repose, Mending,
## Unseen Servant; the rings and the helm on their spells' roads; the cut spells out of the data.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _caster(id: String) -> GameSession:
	return ChecklistProbe.caster_session(data, id)


func _cast(s: GameSession, id: String) -> Array[String]:
	var chk := SpellRules.check(s.character, data, id, 0)
	return SpellRules.cast(s.character, data, str(chk["spell_id"]), int(chk["slot"]), s, true)


## A fight with a goblin ally beside the hero, fallen and dying.
func _fallen_ally(s: GameSession) -> Dictionary:
	var a := ChecklistProbe.fight(s, data, "goblin", false, "ally")
	a["hp"] = 0
	a["status"] = "down"
	return a


func test_a_fallen_ally_rolls_death_saves_and_dies_on_three_blows() -> void:
	var s := _caster("spare_the_dying")
	var a := _fallen_ally(s)
	assert_bool(CombatRules.dying(s, a)).is_true()
	assert_array(CombatRules.dying_of(s, CombatRules.player(s))).contains([str(a["id"])])
	var lines: Array[String] = []
	for i in 3:
		Harm.take(s, data, a, 3, lines)
	assert_str(str(a["status"])).is_equal("dead")


func test_spare_the_dying_stabilizes_an_ally_and_not_oneself() -> void:
	var s := _caster("spare_the_dying")
	var a := _fallen_ally(s)
	var p := CombatRules.player(s)
	ChecklistProbe.turn(s, data, p)
	var act := Acts.one("cast")
	assert_str(act.can(s, data, p, "", {"spell": "spare_the_dying", "slot": 0})).is_equal("COMBAT_BAD_TARGET")
	assert_str(act.can(s, data, p, str(a["id"]), {"spell": "spare_the_dying", "slot": 0})).is_empty()
	act.go(s, data, p, str(a["id"]), {"spell": "spare_the_dying", "slot": 0})
	assert_bool(CombatRules.dying(s, a)).is_false()
	assert_bool(bool(CombatRules.saves_of(s, a)["stable"])).is_true()


func test_warding_bond_shares_the_damage_and_halves_it() -> void:
	var s := _caster("warding_bond")
	var a := ChecklistProbe.fight(s, data, "goblin", false, "ally")
	var p := CombatRules.player(s)
	ChecklistProbe.turn(s, data, p)
	var ac := Sheet.ac(s, a)
	Acts.one("cast").go(s, data, p, str(a["id"]), {"spell": "warding_bond", "slot": 2})
	assert_int(Sheet.ac(s, a)).is_equal(ac + 1)
	var hero_hp := int(s.character["hp"])
	var hp := int(a["hp"])
	var lines: Array[String] = []
	Harm.typed(s, data, a, 10, "slashing", lines)
	assert_int(hp - int(a["hp"])).is_equal(5)
	assert_int(hero_hp - int(s.character["hp"])).is_equal(5)


func test_sending_is_a_letter_of_the_hero_itself() -> void:
	var s := _caster("sending")
	for rid: String in data["world"]["rooms"]:
		if rid != s.room_id and not (data["world"]["rooms"][rid].get("npcs", []) as Array).is_empty():
			s.visited.append(rid)
			break
	var to := LetterRules.recipients(s, data)[0]
	assert_array(LetterRules.ways(s, data, "")).contains(["sending"])
	var long := " ".join(range(30).map(func(i: int) -> String: return "слово"))
	assert_str(LetterRules.send_why(s, data, "", to, "ties", long, "sending")).contains("25")
	assert_str(LetterRules.send_why(s, data, "", to, "ties", "Жив, иду к вам.", "sending")).is_empty()
	assert_str(" ".join(LetterRules.send(s, data, "", to, "ties", "Жив, иду к вам.", "sending"))).contains("ячейка 3 круга")
	var l: Dictionary = LetterRules.letters(s)[0]
	assert_int(int(l["reply_day"])).is_equal(s.day)
	Cheats.toggle(s.character, "slots")  # real slots of a sorcerer of the 1st level: no 3rd circle, no Sending
	assert_array(LetterRules.ways(s, data, "")).not_contains(["sending"])


func test_mage_hand_reaches_a_thing_not_a_person() -> void:
	var s := _caster("mage_hand")
	var touch := MapSpots.reach(s, data, "touch", "prop:x")
	_cast(s, "mage_hand")
	assert_int(MapSpots.reach(s, data, "touch", "prop:x")).is_equal(6)
	assert_int(MapSpots.reach(s, data, "touch", "npc:bruno")).is_equal(touch)


func test_magic_circle_stays_in_its_room() -> void:
	var s := _caster("magic_circle")
	_cast(s, "magic_circle")
	assert_array(SpellEffects.hero_effects(s.character, "foe_types_dis")).is_not_empty()
	assert_array(ConditionRules.left_room(s.character, s.room_id)).is_empty()
	assert_array(ConditionRules.left_room(s.character, "elsewhere")).is_not_empty()
	assert_array(SpellEffects.hero_effects(s.character, "foe_types_dis")).is_empty()


func test_zone_of_truth_gives_insight_not_persuasion() -> void:
	var s := _caster("zone_of_truth")
	var npc := s.npcs_here(data["world"], s.room_id)[0]
	SpellEffects.charm_npc(s, data, "zone_of_truth", npc)
	var spec := {"target_id": npc}
	assert_array(CheckEngine.situation(s, data, Sheet.HERO, spec.merged({"skill": "insight"}))["adv"]).is_not_empty()
	assert_array(CheckEngine.situation(s, data, Sheet.HERO, spec.merged({"skill": "persuasion"}))["adv"]).is_empty()


func test_glyph_goes_off_once_under_a_foe() -> void:
	var s := _caster("glyph_of_warding")
	SpellEffects.world_spell(s, data, "glyph_of_warding")
	var room := EntityRef.room(s.room_id)
	assert_int((Overlay.target(data["world"], room).get("glyphs", []) as Array).size()).is_equal(1)
	var at := WalkRules.settle(s, data, LayoutRules.map_of(s, data, s.room_id))
	var g := ChecklistProbe.fight(s, data, "goblin")
	SpellEffects.lay_glyphs(s, data)
	FightGrid.put(g, at)
	var hp := int(g["hp"])
	SpellEffects.zone_tick(s, data, g, "enter")
	assert_int(int(g["hp"])).is_less(hp)
	assert_array(Overlay.target(data["world"], room).get("glyphs", [])).is_empty()
	assert_array(SpellEffects.zones(s).filter(func(z: Dictionary) -> bool: return z.has("glyph"))).is_empty()


func test_gentle_repose_keeps_a_body_from_burial() -> void:
	var s := _caster("gentle_repose")
	var npc := s.npcs_here(data["world"], s.room_id)[0]
	CrimeRules.on_death(s, data, npc, false, s.room_id)
	SpellEffects.world_spell(s, data, "gentle_repose")
	s.day += int(CrimeRules.cfg(data)["bury_days"]) + 1
	assert_array(CrimeRules.bury(s, data)).is_empty()
	s.day += 10
	assert_array(CrimeRules.bury(s, data)).is_not_empty()


func test_mending_makes_a_damaged_thing_whole() -> void:
	var s := _caster("mending")
	var c := s.character
	var id := str(c["inventory"].keys()[0])
	Thing.stamp(c, id, 1, "dmg", 3)
	assert_str(" ".join(SpellEffects.world_spell(s, data, "mending"))).contains("цел")
	assert_bool(Thing.states(c, id).any(func(st: Dictionary) -> bool: return int(st.get("dmg", 0)) > 0)).is_false()


func test_unseen_servant_carries_a_little() -> void:
	var s := _caster("unseen_servant")
	AllyRules.summon(s, data, "unseen_servant")
	var cr := CreatureRules.all(s).filter(func(x: Dictionary) -> bool: return str(x.get("spell", "")) == "unseen_servant")
	assert_int(int(MountRules.capacity(data, cr[0]))).is_equal(30)


func test_the_rings_and_the_helm_on_their_spells() -> void:
	var cat: Dictionary = data["items"]["catalog"]
	assert_str(str(cat["ring_of_jumping"]["use"]["spell"])).is_equal("jump")
	assert_str(str(cat["helm_of_telepathy"]["use"]["spell"])).is_equal("detect_thoughts")
	assert_str(str(cat["medallion_of_thoughts"]["use"]["spell"])).is_equal("detect_thoughts")
	assert_str(str(cat["ring_of_water_walking"]["wear"]["water_walk"])).is_equal("walk")


func test_the_cut_spells_and_things_are_out_of_the_game() -> void:
	for id: String in ["tiny_hut", "alarm", "rope_trick", "meld_into_stone", "water_breathing", "levitate", "locate_object",
			"locate_animals_or_plants", "revivify", "nondetection", "arcanists_magic_aura"]:
		assert_bool(data["spells"].has(id)).override_failure_message(id).is_false()
	for id: String in ["immovable_rod", "deck_of_illusions", "rope_of_climbing", "philter_of_love", "potion_of_water_breathing"]:
		assert_bool(data["items"]["catalog"].has(id)).override_failure_message(id).is_false()
