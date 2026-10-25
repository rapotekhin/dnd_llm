extends GdUnitTestSuite
## The sheet and the journal by the genre's pattern (roadmap v0.7.22.32): the followed quest, a worn thing compared.


func test_the_followed_quest_is_the_last_taken_until_picked() -> void:
	var s := TestUtils.new_session()
	var data := Catalog.data
	var world: Dictionary = data["world"]
	assert_str(QuestRules.tracked(s, world)).is_empty()
	QuestRules.accept(s, data, "drogin_amulet")
	QuestRules.accept(s, data, "letter_to_ilva")
	assert_str(QuestRules.tracked(s, world)).is_equal("letter_to_ilva")
	s.tracked_quest = "drogin_amulet"
	assert_str(QuestRules.tracked(s, world)).is_equal("drogin_amulet")
	s.quests_active.erase("drogin_amulet")  # done or failed: back to the last taken
	assert_str(QuestRules.tracked(s, world)).is_equal("letter_to_ilva")


func test_a_ring_is_compared_with_the_worn_one_not_as_a_weapon() -> void:
	var s := TestUtils.new_session()
	var c := s.character
	c["inventory"]["ring_of_jumping"] = 1
	assert_str(ItemInfo.compare(c, Catalog.data, s.items, "ring_of_jumping")).is_empty()
	c["equipped"]["ring1"] = "ring_of_mind_shielding"
	assert_str(ItemInfo.compare(c, Catalog.data, s.items, "ring_of_jumping")).contains("Вместо надетого")
