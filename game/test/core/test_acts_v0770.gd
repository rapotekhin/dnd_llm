extends GdUnitTestSuite
## One way for an act of a window's button (v0.7.70): the guards, an unknown act, the rule's refusal.

var kept: GameSession


func before_test() -> void:
	kept = GameState.session
	GameState.session = TestUtils.new_session()


func after_test() -> void:
	GameState.session = kept


func test_no_game_and_a_fight_refuse_by_the_act_s_own_key() -> void:
	GameState.session = null
	assert_str(GameState.study_act("drop", "x")).is_equal("PROPERTY_NOT_NOW")
	assert_str(GameState.pet_act("feed", "x")).is_equal("PET_NOT_NOW")
	assert_str(GameState.faith_act("service")).is_equal("EQUIP_BUSY")
	GameState.session = TestUtils.new_session()
	GameState.session.mode = GameSession.MODE_COMBAT
	assert_str(GameState.bank_act("deposit", "npc_merchant")).is_equal("PROPERTY_NOT_NOW")


func test_an_unknown_act_is_refused() -> void:
	assert_str(GameState.bank_act("nonsense", "npc_merchant")).is_equal("PROPERTY_NOT_NOW")
	assert_str(GameState.pet_act("nonsense", "x")).is_equal("PET_NOT_NOW")
	assert_str(GameState.faith_act("nonsense")).is_equal("FAITH_NO_SHRINE")


func test_the_rule_s_refusal_comes_back_and_nothing_is_told() -> void:
	var said := GameState.session.chat.size()
	assert_str(GameState.study_act("drop", "no_course")).is_equal("STUDY_NOT_ENROLLED")
	assert_str(GameState.office_act("leave", "no_office")).is_equal("OFFICE_NOT_HELD")
	assert_str(GameState.heist_act("give_up", "no_heist")).is_equal("HEIST_NOT_ACTIVE")
	assert_int(GameState.session.chat.size()).is_equal(said)
