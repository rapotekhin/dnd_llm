extends GdUnitTestSuite
## Small text fixes (roadmap v0.7.22.31, С5): a span of time without «0 мин».


func test_a_span_drops_zero_minutes() -> void:
	assert_str(TimeRules.span(45)).is_equal("45 мин")
	assert_str(TimeRules.span(60)).is_equal("1 ч")
	assert_str(TimeRules.span(80)).is_equal("1 ч 20 мин")
	assert_str(TimeRules.span(600)).is_equal("10 ч")


func test_the_combat_speed_sets_the_pause() -> void:
	var was: String = SaveManager.combat_speed
	SaveManager.combat_speed = "instant"
	assert_float(SaveManager.combat_delay()).is_equal(0.0)
	SaveManager.combat_speed = "slow"
	assert_float(SaveManager.combat_delay()).is_greater(0.6)
	SaveManager.combat_speed = was
