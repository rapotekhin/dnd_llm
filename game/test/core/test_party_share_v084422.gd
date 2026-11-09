extends GdUnitTestSuite
## The party's experience and rewards (v0.8.4.42.2, the author): a reward is that of the party the fights are made for, and
## experience is split evenly between the hero and its followers beside it; a follower's level rises by the player's button.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _hero() -> GameSession:
	var s := TestUtils.new_session()
	for p: Dictionary in data["presets"]:
		if p["id"] == "fighter_aira":
			s.character = GameSession.normalized_character(CharacterBuilder.build_preset(p, data))
	CharacterRules.refresh(s.character, data, s.items)
	s.character["xp"] = 0
	return s


func test_a_reward_is_the_partys() -> void:
	var s := _hero()
	assert_int(DifficultyRules.reward(s, data, 100)).is_equal(100)
	s.settings["party"] = 4
	assert_int(DifficultyRules.reward(s, data, 100)).is_equal(400)
	var one := EffectEngine.budget_left(s, data)
	s.settings["party"] = 1
	assert_int(one).is_equal(EffectEngine.budget_left(s, data) * 4)  # the master's treasure too


func test_alone_the_hero_takes_the_whole_and_with_followers_a_share() -> void:
	var s := _hero()
	XpRules.share(s, data, 300, "бой", [])
	assert_int(int(s.character["xp"])).is_equal(300)
	Being.follow(s, "npc_mercenary")
	var before := int(Being.view(s, "npc_mercenary").get("xp", LevelUp.xp_for(data, GrowthRules.level(s, data, "npc_mercenary"))))
	var lines := XpRules.share(s, data, 300, "бой", ["npc_mercenary"])
	assert_int(int(s.character["xp"])).is_equal(450)
	assert_int(int(Being.view(s, "npc_mercenary")["xp"])).is_equal(before + 150)
	assert_str("\n".join(lines)).contains("доля одного из 2")


func test_a_won_fight_is_split_with_the_follower_who_fought_only() -> void:
	var s := _hero()
	Being.follow(s, "npc_mercenary")
	TestUtils.fight(s, data, [{"monster": "goblin", "name": "Гоблин"}], {"allies": [{"monster": "guard", "name": "Стражник", "npc_id": "npc_captain"}]})
	assert_array(GrowthRules.fought(s)).contains_exactly(["npc_mercenary"])  # the follower joins by itself; the captain is an ally, not of the party


func test_a_quest_pays_the_partys_reward_split_with_the_company() -> void:
	var s := _hero()
	s.settings["party"] = 2
	var lines: Array[String] = []
	QuestRules._reward(s, data, {"reward_cp": 1000, "xp": 100}, lines)
	assert_int(Ledger.balance(s)).is_greater_equal(2000)
	assert_int(int(s.character["xp"])).is_equal(200)  # alone: the two's experience
