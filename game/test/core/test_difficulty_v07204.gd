extends GdUnitTestSuite
## Difficulty, first iteration (roadmap M5, v0.7.20.4): «Элементарная» +20, «Лёгкая» +10, «Средняя» 0, «Сложная» −5
## to the hero's checks and saving throws; a game without the setting plays at «Средняя».

var data: Dictionary
var s: GameSession


func before_test() -> void:
	data = TestUtils.data()
	s = TestUtils.new_session()


func test_levels_and_their_bonus() -> void:
	assert_array(DifficultyRules.levels(data)).contains_exactly(["trivial", "easy", "normal", "hard"])
	assert_int(DifficultyRules.bonus(s, data)).is_equal(0)  # an old save without the setting
	for pair: Array in [["trivial", 20], ["easy", 10], ["normal", 0], ["hard", -5]]:
		s.settings["difficulty"] = pair[0]
		assert_int(DifficultyRules.bonus(s, data)).is_equal(pair[1])
	s.settings["difficulty"] = "nightmare"
	assert_int(DifficultyRules.bonus(s, data)).is_equal(0)


func test_a_save_of_the_hero_gets_the_bonus() -> void:
	s.settings["difficulty"] = "trivial"
	var easy := HeroDefense.save(s, data, "wis", 30)
	s.settings["difficulty"] = "hard"
	var hard := HeroDefense.save(s, data, "wis", 30)
	assert_int(int(easy["total"]) - int(easy["nat"]) - (int(hard["total"]) - int(hard["nat"]))).is_equal(25)
	assert_str(str(easy["text"])).contains("Элементарная")


func test_a_new_game_starts_at_the_middle() -> void:
	assert_str(str(WorldPack.default_settings({"id": "frontier"})["difficulty"])).is_equal("normal")
