extends GdUnitTestSuite
## «Смерть и загрузка» (the author's finding on 0.8.4.43.8, v0.8.4.43.9): the hero fell, the death screen, «В меню» with
## no loading, then the autosave loaded — it was written after the death, in a fight that waited for nothing, and the
## game hung. A dead hero's game opens only on its death screen, with the master's words kept in the save.

var data: Dictionary
var _saved_dir: String


func before_test() -> void:
	data = TestUtils.data()
	_saved_dir = SaveManager.save_dir
	SaveManager.save_dir = "user://test_saves"
	DirAccess.make_dir_recursive_absolute(SaveManager.save_dir)


func after_test() -> void:
	GameState.session = null
	GameState.busy_turn = ""
	SaveManager.save_dir = _saved_dir


func _fallen() -> GameSession:
	var s := TestUtils.new_session()
	CombatRules.start(s, data, [{"monster": "wolf"}])
	s.combat["outcome"] = "dead"
	s.combat["narrated"] = true
	s.epitaph = "Айра пала на тропе лесорубов."
	return s


func test_a_fight_lost_to_death_and_the_sixth_exhaustion_are_a_dead_hero() -> void:
	var s := TestUtils.new_session()
	assert_bool(s.hero_dead()).is_false()
	assert_bool(_fallen().hero_dead()).is_true()
	ConditionRules.add_exhaustion(s, data, 6, "голод")
	assert_bool(s.hero_dead()).is_true()


func test_a_living_hero_s_game_opens_on_the_game_screen() -> void:
	assert_dict(GameEntry.opened(TestUtils.new_session())).is_equal({"screen": "game", "args": {}})
	var won := TestUtils.new_session()
	CombatRules.start(won, data, [{"monster": "wolf"}])
	won.combat["outcome"] = "victory"  # the results wait for «Дальше», as they did
	assert_str(str(GameEntry.opened(won)["screen"])).is_equal("game")


func test_a_dead_hero_s_game_opens_on_its_death_screen() -> void:
	var to := GameEntry.opened(_fallen())
	assert_str(str(to["screen"])).is_equal("death")
	assert_str(str(to["args"]["epitaph"])).is_equal("Айра пала на тропе лесорубов.")


func test_the_autosave_after_a_death_loads_onto_the_death_screen_again() -> void:
	assert_bool(SaveManager.save_slot(SaveManager.AUTOSAVE, _fallen())).is_true()
	GameState.start(TestUtils.new_session(7))
	assert_str(GameState.load_from(SaveManager.AUTOSAVE)).is_empty()
	assert_bool(GameState.session.hero_dead()).is_true()
	assert_str(GameState.session.epitaph).is_equal("Айра пала на тропе лесорубов.")
	var to := GameEntry.opened(GameState.session)
	assert_str(str(to["screen"])).is_equal("death")
	assert_str(str(to["args"]["epitaph"])).is_equal("Айра пала на тропе лесорубов.")
