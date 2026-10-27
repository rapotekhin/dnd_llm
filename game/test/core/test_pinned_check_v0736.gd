extends GdUnitTestSuite
## The player's own check (v0.7.36): a skill or a bare ability pinned to the words; the engine rolls the turn's checks
## by it, whatever the master asked for, and saves stay the master's.

var data: Dictionary
var s: GameSession


func before_test() -> void:
	data = TestUtils.data()
	s = TestUtils.new_session()
	s.room_id = "brod-gate"
	GameState.session = s
	GameState.busy_turn = "t-1"


func after_test() -> void:
	GameState.session = null
	GameState.busy_turn = ""
	GameState.pinned_check = {}
	GameState._forced = {}


func test_the_menu_lists_skills_by_name_then_the_abilities() -> void:
	var list := GameState.check_choices()
	var skills := list.filter(func(c: Dictionary) -> bool: return c["kind"] == "skill")
	assert_int(skills.size()).is_equal((data["rules"]["skills"] as Dictionary).size())
	assert_str(str(list[skills.size()]["kind"])).is_equal("ability")
	assert_int(list.size() - skills.size()).is_equal(6)
	var ath: Dictionary = skills.filter(func(c: Dictionary) -> bool: return c["id"] == "athletics")[0]
	assert_int(int(ath["bonus"])).is_equal(int(s.character["skills"]["athletics"]))
	assert_str(GameState.check_label(ath)).is_equal("Атлетика %+d" % int(ath["bonus"]))


func test_a_bare_ability_check_rolls_the_modifier() -> void:
	var str_mod := CharacterRules.mod(CharacterRules.ability(s.character, "str"))
	assert_int(CheckEngine.bonus_for(s.character, {"ability": "str"}, data)).is_equal(str_mod)
	var r := CheckEngine.roll(data["rules"], s.rng, {"ability": "str", "dc_tier": "easy"}, str_mod, "c-1")
	assert_bool(r.has("error")).is_false()
	assert_dict(CheckEngine.roll(data["rules"], s.rng, {"ability": "luck", "dc_tier": "easy"}, 0, "c-2")).contains_keys(["error"])


func test_the_engine_rolls_the_pinned_skill_not_the_masters() -> void:
	GameState._forced = {"skill": "athletics", "turn": "t-1"}
	var r := GameState.handle_engine_check({"turn_id": "t-1", "skill": "acrobatics", "dc_tier": "easy"})
	assert_str(str(r.get("rolled_as", ""))).is_equal("Атлетика")
	assert_int(int(r["bonus"])).is_equal(int(s.character["skills"]["athletics"]))
	assert_str(str(s.chat[-1]["skill"])).is_equal("athletics")


func test_a_pinned_ability_and_a_save_left_alone() -> void:
	GameState._forced = {"ability": "str", "turn": "t-1"}
	var r := GameState.handle_engine_check({"turn_id": "t-1", "skill": "athletics", "dc_tier": "easy"})
	assert_str(str(r["rolled_as"])).is_equal("Сила")
	assert_str(str(s.chat[-1]["ability"])).is_equal("str")
	assert_str((auto_free(CheckCard.new(s.chat[-1])) as CheckCard).text_for(s.chat[-1])).contains("Сила")
	var save := GameState.handle_engine_check({"turn_id": "t-1", "save": "con", "dc_tier": "easy"})
	assert_bool(save.has("rolled_as")).is_false()


func test_another_turn_is_not_bound() -> void:
	GameState._forced = {"skill": "athletics", "turn": "t-0"}
	var r := GameState.handle_engine_check({"turn_id": "t-1", "skill": "perception", "dc_tier": "easy"})
	assert_bool(r.has("rolled_as")).is_false()
	assert_str(str(s.chat[-1]["skill"])).is_equal("perception")


func test_the_note_makes_the_check_mandatory_and_names_the_pin() -> void:
	# v0.7.38: the master picks only the tier; the server gets the name to hold it to a roll
	assert_str(GameState._pin_name({"skill": "persuasion"})).is_equal("Убеждение")
	assert_str(GameState._pin_name({"ability": "str"})).is_equal("Сила")
	var note := GameState._pinned_note({"skill": "persuasion"})
	assert_str(note).contains("Убеждение").contains("обязательна").contains("nearly_impossible")
	assert_str(note).not_contains("Не нужна")
