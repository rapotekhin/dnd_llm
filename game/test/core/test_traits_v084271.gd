extends GdUnitTestSuite
## Monster traits on the engine's roads (roadmap v0.8.4.27.1): a trait of a template lays its status for good
## (`rules.feature_wear`) — a swarm shares a square and regains nothing, bites in its own square and less at half its hit
## points; False Appearance hides it at a meeting; Horrific Appearance is an aura of the field; innate spellcasting is
## read into the template's spells.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _hero() -> GameSession:
	return ChecklistProbe.session(data)


func test_a_swarm_and_the_hero_share_a_square() -> void:
	var s := _hero()
	var rats := ChecklistProbe.fight(s, data, "swarm_of_rats")
	var hero := CombatRules.player(s)
	assert_bool(FightGrid.shares(s, data, rats)).is_true()
	assert_bool(FightGrid.shares(s, data, hero)).is_false()
	ChecklistProbe.turn(s, data, rats)
	assert_bool(FightGrid.stops(s, data, rats, Move.routes(s, data, rats)).has(FightGrid.cell(hero))).is_true()
	ChecklistProbe.turn(s, data, hero)
	assert_bool(FightGrid.stops(s, data, hero, Move.routes(s, data, hero)).has(FightGrid.cell(rats))).is_true()


func test_a_goblin_still_cannot_stop_on_the_hero() -> void:
	var s := _hero()
	var gob := ChecklistProbe.fight(s, data, "goblin")
	ChecklistProbe.turn(s, data, gob)
	assert_bool(FightGrid.stops(s, data, gob, Move.routes(s, data, gob)).has(FightGrid.cell(CombatRules.player(s)))).is_false()


func test_a_swarm_bites_in_its_own_square_and_less_when_hurt() -> void:
	var s := _hero()
	var rats := ChecklistProbe.fight(s, data, "swarm_of_rats")
	var hero := CombatRules.player(s)
	var b := Attack.way(s, data, rats, {"action": "Bites"})
	assert_int(int(b["reach"])).is_equal(0)
	assert_bool(CombatRules.blade_reaches(s, data, rats, hero, int(b["reach"]))).is_false()
	FightGrid.put(rats, FightGrid.cell(hero))
	assert_bool(CombatRules.blade_reaches(s, data, rats, hero, int(b["reach"]))).is_true()
	assert_str(str(b["pieces"][0]["dice"])).is_equal("2d6")
	rats["hp"] = int(rats["max_hp"]) / 2
	assert_str(str(Attack.way(s, data, rats, {"action": "Bites"})["pieces"][0]["dice"])).is_equal("1d6")


func test_a_swarm_regains_no_hit_points_and_no_temporary_ones() -> void:
	var s := _hero()
	var rats := ChecklistProbe.fight(s, data, "swarm_of_rats")
	rats["hp"] = 10
	assert_int(Harm.heal(data, rats, 5)).is_equal(0)
	assert_int(int(rats["hp"])).is_equal(10)
	assert_bool(Harm.shield(data, rats, 5)).is_false()
	var c := s.character
	c["hp"] = 1
	assert_int(Harm.heal(data, c, 3)).is_equal(3)
	assert_bool(Harm.shield(data, c, 4)).is_true()
	assert_bool(Harm.shield(data, c, 2)).is_false()


func test_false_appearance_hides_a_head_with_no_roll() -> void:
	var s := _hero()
	var heads := [{"id": "g1", "monster": "gargoyle", "name": "Горгулья"}, {"id": "w1", "monster": "wolf", "name": "Волк"}]
	assert_bool(EncounterRules.still(data, heads[0])).is_true()
	assert_bool(EncounterRules.still(data, heads[1])).is_false()
	for i in 10:
		assert_array(EncounterRules._hide(s, data, heads, false)).is_equal(["g1"])


func test_horrific_appearance_frightens_a_humanoid_who_sees_the_hag() -> void:
	data["monsters"]["sea_hag"] = TestUtils.uncut("monsters", "sea_hag")  # out of the game (v0.8.4.28.4); its road stays
	var s := _hero()
	var hag := ChecklistProbe.fight(s, data, "sea_hag")
	var aura: Array = SpellEffects.zones(s).filter(func(z: Dictionary) -> bool: return str(z["spell"]) == "aura:horrific_appearance")
	assert_int(aura.size()).is_equal(1)
	var hero := CombatRules.player(s)
	var feared := false
	for i in 30:
		ConditionRules.remove(s.character, "frightened")
		aura[0].erase("spared")
		SpellEffects.zone_tick(s, data, hero, "start")
		if ConditionRules.has(s.character, "frightened"):
			feared = true
			break
	assert_bool(feared).is_true()
	assert_str(str(CombatRules.fear_source(s, hero).get("id", ""))).is_equal(str(hag["id"]))


func test_horrific_appearance_spares_a_beast_and_one_who_saved() -> void:
	data["monsters"]["sea_hag"] = TestUtils.uncut("monsters", "sea_hag")  # out of the game (v0.8.4.28.4); its road stays
	var s := _hero()
	ChecklistProbe.fight(s, data, "sea_hag")
	var z: Dictionary = SpellEffects.zones(s).filter(func(x: Dictionary) -> bool: return str(x["spell"]) == "aura:horrific_appearance")[0]
	var wolf := {"id": "w", "monster": "wolf", "x": 40, "y": 31, "status": "active"}
	assert_bool(SpellEffects._reaches(s, data, z, wolf)).is_false()
	var hero := CombatRules.player(s)
	assert_bool(SpellEffects._reaches(s, data, z, hero)).is_true()
	z["spared"] = [str(hero["id"])]
	assert_bool(SpellEffects._reaches(s, data, z, hero)).is_false()


func test_innate_spellcasting_is_read_into_the_spells() -> void:
	var row := ChecklistProbe.monster(data, "dust_mephit")
	assert_bool((row["steps"] as Array).any(func(x: String) -> bool: return x.contains("Врождённое колдовство"))).is_false()
	assert_bool((row["steps"] as Array).any(func(x: String) -> bool: return x.contains("Рой"))).is_false()
	var rats := ChecklistProbe.monster(data, "swarm_of_rats")
	assert_bool((rats["steps"] as Array).any(func(x: String) -> bool: return x.contains("черта «Рой» — в движке"))).is_true()


func test_the_ai_walks_a_swarm_into_the_heros_square_to_bite() -> void:
	var s := _hero()
	var rats := ChecklistProbe.fight(s, data, "swarm_of_rats", true)
	ChecklistProbe.turn(s, data, rats)
	var plan := FightAI.plan(s, data, rats)
	assert_bool(plan.is_empty()).is_false()
	var path: Array = plan["path"]
	assert_bool(not path.is_empty() and path[-1] == FightGrid.cell(CombatRules.player(s))).is_true()
