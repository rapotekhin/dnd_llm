extends GdUnitTestSuite
## Conversation as in BG3 (roadmap v0.7.22.28): a master's option with a check shows the skill, the engine's DC and the
## chance.

var _was: GameSession


func before_test() -> void:
	_was = GameState.session
	GameState.session = TestUtils.new_session()


func after_test() -> void:
	GameState.session = _was


func test_a_checked_option_shows_the_engines_dc_and_chance() -> void:
	var s := GameState.session
	s.options = ["Осмотреться", "Взобраться на балку"]
	s.option_checks = [{}, {"skill": "athletics", "dc_tier": "medium"}]
	assert_dict(GameState.option_preview(0)).is_empty()
	var pv := GameState.option_preview(1)
	var bonus := int(s.character["skills"]["athletics"]) + DifficultyRules.bonus(s, Catalog.data)
	assert_int(int(pv["dc"])).is_equal(15)
	assert_int(int(pv["bonus"])).is_equal(bonus)
	assert_int(int(pv["chance"])).is_equal(clampi((21 - (15 - bonus)) * 5, 5, 95))  # natural 1 and 20 count


func test_an_impossible_check_still_has_the_natural_twenty() -> void:
	GameState.session.option_checks = [{"skill": "athletics", "dc_tier": "nearly_impossible"}]
	GameState.session.options = ["Перепрыгнуть пропасть"]
	assert_int(int(GameState.option_preview(0)["chance"])).is_equal(5)
