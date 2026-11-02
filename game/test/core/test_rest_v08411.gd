extends GdUnitTestSuite
## Rest, needs, diseases, exhaustion and growth of anybody (v0.8.4.11, ADR-0016): the world rests by its nights, not by
## the hero's sleep; a follower rests with the hero and keeps what it spent until then; a person sickens, is cured and
## catches the hero's disease by the hero's own course; a person of a class grows by the fights it stood in.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _hero(preset: String = "fighter_aira") -> GameSession:
	var s := TestUtils.new_session()
	for p: Dictionary in data["presets"]:
		if p["id"] == preset:
			s.character = GameSession.normalized_character(CharacterBuilder.build_preset(p, data))
	CharacterRules.refresh(s.character, data, s.items)
	return s


func _morning(s: GameSession) -> void:
	var to := TimeRules.day_start(s.day + 1) + int(TimeRules.cfg(data)["wake_minute"]) + 30
	TimeRules.advance(s, data, to - TimeRules.abs_minute(s))


func test_the_world_rests_by_its_nights_not_by_the_heros_sleep() -> void:
	var s := _hero()
	Being.of(s, "npc_veteran")["hp"] = 5
	Being.of(s, "npc_veteran")["exhaustion"] = 2
	TimeRules.advance(s, data, 30)
	assert_int(int(Being.view(s, "npc_veteran")["hp"])).is_equal(5)  # tired today: no rest in the middle of the day
	_morning(s)
	assert_bool(Being.view(s, "npc_veteran").has("hp")).is_false()  # whole the next morning
	assert_int(ConditionRules.exhaustion(Being.view(s, "npc_veteran"))).is_equal(0)


func test_a_follower_rests_with_the_hero_and_keeps_what_it_spent_till_then() -> void:
	var s := _hero()
	FollowRules.apply(s, {"follow_npc": "npc_mercenary", "on": true, "room": ""})
	Being.of(s, "npc_mercenary")["hp"] = 7
	Stock.spend(Being.of(s, "npc_mercenary"), "hit_dice", 1)
	_morning(s)
	assert_int(int(Being.view(s, "npc_mercenary")["hp"])).is_equal(7)  # it walks with the hero: no rest of its own
	TestUtils.fight(s, data, [{"monster": "goblin", "name": "Гоблин"}], {})
	CombatRules.close(s)
	assert_int(Stock.spent(Being.view(s, "npc_mercenary"), "hit_dice")).is_equal(1)  # what it spent waits for a rest
	ExplorationRules.long_rest(s, data)
	assert_bool(Being.view(s, "npc_mercenary").has("hp")).is_false()
	assert_int(Stock.spent(Being.view(s, "npc_mercenary"), "hit_dice")).is_equal(0)


func test_exhaustion_is_one_scale_for_anybody() -> void:
	var s := _hero()
	TestUtils.fight(s, data, [{"monster": "bandit", "name": "Разбойник"}], {})
	var f := CombatRules.fighter(s, CombatRules.enemies(s)[0])
	var lines := ConditionRules.impose(s, data, {"condition": "exhaustion", "source": {"name": "яд"}}, f)
	assert_str("\n".join(lines)).contains("Истощение 1")
	assert_int(ConditionRules.exhaustion(f)).is_equal(1)
	ConditionRules.add_exhaustion(s, data, 5, "", str(f["id"]))
	assert_str(str(f["status"])).is_equal("dead")
	assert_bool(CombatRules.active(s) and str(s.combat.get("outcome", "")).is_empty()).is_true()  # a foe's death, not the hero's


func test_a_person_sickens_and_is_cured_by_the_heros_own_course() -> void:
	var s := _hero()
	assert_str(DiseaseRules.npc_disease(s, data, "npc_sick_pilgrim")).is_equal("cackle_fever")
	assert_bool(ConditionRules.effects(Being.view(s, "npc_sick_pilgrim")).any(func(e: Dictionary) -> bool: return str(e.get("disease", "")) == "cackle_fever")).is_true()
	assert_str("\n".join(DiseaseRules.cure_npc(s, data, "npc_sick_pilgrim", "magic"))).contains("исцелён")
	assert_str(DiseaseRules.npc_disease(s, data, "npc_sick_pilgrim")).is_empty()
	DiseaseRules.contract(s, data, "cackle_fever", "npc_veteran")
	assert_bool(DiseaseRules.sick(Being.view(s, "npc_veteran"), "cackle_fever")).is_true()
	TimeRules.advance(s, data, 60 * 24 * 3)
	assert_str(DiseaseRules.npc_disease(s, data, "npc_veteran")).is_equal("cackle_fever")  # it shows on it in its time


func test_a_follower_eats_its_own_food_first() -> void:
	var s := _hero()
	FollowRules.apply(s, {"follow_npc": "npc_veteran", "on": true, "room": ""})
	Gear.of(s, data, "npc_veteran")["inventory"]["rations"] = 1
	var mine := int(s.character["inventory"].get("rations", 0))
	Being.of(s, "npc_veteran")["fed"] = {"at": TimeRules.abs_minute(s) - 1500, "hungry": 0}
	FollowRules.meals(s, data)
	assert_int(Gear.count(s, data, "npc_veteran", "rations")).is_equal(0)
	assert_int(int(s.character["inventory"].get("rations", 0))).is_equal(mine)


func test_a_person_of_a_class_grows_beside_the_hero() -> void:
	var s := _hero()
	assert_int(GrowthRules.level(s, data, "npc_mercenary")).is_equal(3)
	var lines := GrowthRules.gain(s, data, "npc_mercenary", LevelUp.xp_for(data, 4) - LevelUp.xp_for(data, 3))
	assert_str("\n".join(lines)).contains("4 уровень")
	TestUtils.fight(s, data, [{"monster": "goblin", "name": "Гоблин"}], {"allies": [{"monster": "scout", "name": "Кейра", "npc_id": "npc_mercenary"}]})
	var f := CombatRules.fighter(s, "npc_mercenary")
	assert_int(int(f["level"])).is_equal(4)
	assert_int(int(f["max_hp"])).is_greater(int(data["monsters"]["scout"]["hp"]))
	assert_bool(GrowthRules.gain(s, data, "npc_innkeeper", 100000).is_empty()).is_true()  # a commoner has no class to grow in
