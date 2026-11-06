extends GdUnitTestSuite
## Circle of the Land (v0.8.4.33): the SRD's levels left its land and its circle spells out, so a druid of the circle had no
## choice of land and no spell of it. Now the land is picked at level 2 and its spells are always prepared from level 3.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _druid() -> Dictionary:
	var c: Dictionary
	for p: Dictionary in data["presets"]:
		if p["id"] == "druid_olha":
			c = GameSession.normalized_character(CharacterBuilder.build_preset(p, data))
	CharacterRules.refresh(c, data)
	return c


func test_the_land_is_offered_at_level_two_and_its_spells_come_at_three() -> void:
	var c := _druid()
	c["xp"] = LevelUp.xp_for(data, 2)
	var picks := LevelUp.default_picks(c, data)
	picks["subclass"] = "land"
	var p := LevelUp.plan(c, data, picks)
	assert_array((p.get("features", []) as Array)).contains(["circle_of_the_land"])
	picks["options"] = {"circle_of_the_land": ["circle_of_the_land_forest"]}
	assert_array(LevelUp.errors(c, data, picks)).is_empty()
	LevelUp.apply(c, data, picks)
	assert_array(c["features"]).contains(["circle_of_the_land", "circle_of_the_land_forest"])
	c["xp"] = LevelUp.xp_for(data, 3)
	LevelUp.apply(c, data, LevelUp.default_picks(c, data))
	assert_array(c["features"]).contains(["circle_spells_1"])
	assert_array(LevelUp.always(c, data, 3)).contains(["barkskin", "spider_climb"])


func test_a_land_is_picked_by_default_when_none_is_named() -> void:
	var c := _druid()
	c["xp"] = LevelUp.xp_for(data, 2)
	var picks := LevelUp.default_picks(c, data)
	picks["subclass"] = "land"
	picks = LevelUp.default_picks(c, data).merged(picks, true)
	assert_array(LevelUp.errors(c, data, picks)).is_empty()
