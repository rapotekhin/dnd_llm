extends GdUnitTestSuite
## «Мирное развитие и опыт» (roadmap v0.7.19, batch 1; the author: a letter brought — 300 XP and new spells makes no
## sense): class experience for a quest only for the dangerous — a step with a fight or marked `danger`, any step of a
## `major` quest; a peaceful step pays in coins, things and reputation.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func test_what_is_dangerous() -> void:
	var w: Dictionary = data["world"]["quests"]
	assert_bool(QuestRules.dangerous(w["letter_to_ilva"], w["letter_to_ilva"]["steps"][0])).is_false()
	assert_bool(QuestRules.dangerous(w["drogin_amulet"], w["drogin_amulet"]["steps"][0])).is_true()  # the flooded mine
	assert_bool(QuestRules.dangerous(w["drogin_amulet"], w["drogin_amulet"]["steps"][1])).is_false()  # handing it over
	assert_bool(QuestRules.dangerous({}, {"when": {"all": [{"encounter": "x"}, {"room": "y"}]}})).is_true()
	assert_bool(QuestRules.dangerous(w["ash_over_the_march"], w["ash_over_the_march"]["steps"][1])).is_true()  # major


func test_the_letter_pays_coins_not_experience() -> void:
	var s := TestUtils.new_session()
	s.room_id = "brod-tavern-hall"
	QuestRules.accept(s, data, "letter_to_ilva")
	s.room_id = "brod-temple"
	var gold := int(s.character["gold_cp"])
	var lines := QuestRules.talk(s, data, "letter_to_ilva")
	assert_int(int(s.character["xp"])).is_equal(0)
	assert_int(int(s.character["gold_cp"])).is_equal(gold + 500)
	assert_str(" ".join(lines)).not_contains("опыта")
