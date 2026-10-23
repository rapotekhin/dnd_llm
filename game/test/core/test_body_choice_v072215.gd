extends GdUnitTestSuite
## The hero's body chosen at creation (the author's request, v0.7.22.15): what the player picked stays, the rest the
## engine picks; a pick that does not fit the gender is dropped; a child is not offered to the hero.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func test_the_chosen_body_stays_and_the_rest_is_picked() -> void:
	var ch := CharacterBuilder.random_choices(data, RandomNumberGenerator.new())
	ch["gender"] = "female"
	ch["body"] = {"age": "elderly", "build": "curvy"}
	var c := CharacterBuilder.build(ch, data)
	assert_str(str(c["body"]["age"])).is_equal("elderly")
	assert_str(str(c["body"]["build"])).is_equal("curvy")
	assert_str(str(c["body"]["height"])).is_not_empty()
	ch["gender"] = "male"  # «пышная» has no male word: the engine picks instead
	assert_str(str(CharacterBuilder.build(ch, data)["body"]["build"])).is_not_equal("curvy")


func test_hero_lists() -> void:
	assert_bool(BodyRules.hero_ids(data, "age", "male").has("child")).is_false()
	assert_bool(BodyRules.hero_ids(data, "age", "male").has("old")).is_true()
	assert_bool(BodyRules.hero_ids(data, "build", "female").has("slender")).is_true()
	assert_bool(BodyRules.hero_ids(data, "build", "male").has("slender")).is_false()
	assert_dict(BodyRules.fit(data, {"age": "child", "build": "wiry", "height": "tall"}, "male")).is_equal({"build": "wiry", "height": "tall"})
