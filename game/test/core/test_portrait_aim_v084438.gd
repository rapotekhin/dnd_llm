extends GdUnitTestSuite
## v0.8.4.43.8, as in BG3: a spell aimed by a portrait. Out of a fight a spell pinned to the words takes the hero or a person
## here by its portrait — one road with the chip's own boxes (GameState.aim_attached): several ticked up to the spell's
## number, one set; a creature that is no person is no target; a spell not for the hero's side leaves the portrait its own act.

var kept: GameSession
var kept_attached: Dictionary


func before_test() -> void:
	kept = GameState.session
	kept_attached = GameState.attached
	GameState.session = TestUtils.new_session()
	GameState.session.room_id = "brod-tavern-hall"
	GameState.attached = {}


func after_test() -> void:
	GameState.session = kept
	GameState.attached = kept_attached


func _people() -> Array:
	return GameState.attach_targets().filter(func(t: Dictionary) -> bool: return not bool(t["foe"])).map(func(t: Dictionary) -> String: return str(t["id"]))


func test_no_spell_for_the_hero_s_side_leaves_the_portrait_its_own_act() -> void:
	assert_str(GameState.attach_aim_why(Being.HERO)).is_equal("ATTACH_AIM_NONE")
	GameState.attach("spell", "fire_bolt", 0)  # a spell at a foe
	assert_str(GameState.attach_aim_why(Being.HERO)).is_equal("ATTACH_AIM_NONE")
	assert_str(GameState.aim_attached(Being.HERO)).is_equal("ATTACH_AIM_NONE")
	GameState.attach("feature", "second_wind", 0)
	assert_str(GameState.attach_aim_why(Being.HERO)).is_equal("ATTACH_AIM_NONE")


func test_a_heal_takes_one_target_by_its_portrait_and_none_set_is_the_hero() -> void:
	var people := _people()
	assert_bool(people.is_empty()).is_false()
	GameState.attach("spell", "cure_wounds", 1)
	assert_bool(GameState.attach_aimed(Being.HERO)).is_true()  # nothing set: the hero
	assert_str(GameState.aim_attached(str(people[0]))).is_empty()
	assert_str(str(GameState.attached["target"])).is_equal(str(people[0]))
	assert_bool(GameState.attach_aimed(str(people[0]))).is_true()
	assert_bool(GameState.attach_aimed(Being.HERO)).is_false()
	assert_str(GameState.aim_attached(Being.HERO)).is_empty()
	assert_str(str(GameState.attached["target"])).is_empty()
	assert_bool(GameState.attach_aimed(Being.HERO)).is_true()


func test_bless_ticks_and_unticks_up_to_its_number_like_the_chip_s_boxes() -> void:
	var people := _people()
	assert_int(people.size()).is_greater_equal(3)
	GameState.attach("spell", "bless", 1)  # three at the first circle
	assert_str(GameState.aim_attached(Being.HERO)).is_empty()
	assert_str(GameState.aim_attached(str(people[0]))).is_empty()
	assert_array(GameState.attached["targets"]).is_equal([GameState.SELF_TARGET, str(people[0])])
	assert_str(GameState.aim_attached(GameState.SELF_TARGET)).is_empty()  # the chip's box of the hero is the same road
	assert_array(GameState.attached["targets"]).is_equal([str(people[0])])
	assert_str(GameState.aim_attached(str(people[1]))).is_empty()
	assert_str(GameState.aim_attached(str(people[2]))).is_empty()
	assert_str(GameState.aim_attached(Being.HERO)).is_equal("ATTACH_AIM_FULL")
	assert_bool(GameState.attach_aimed(Being.HERO)).is_false()
	assert_str(GameState.aim_attached(str(people[1]))).is_empty()  # one let go, room for the hero
	assert_str(GameState.aim_attached(Being.HERO)).is_empty()
	assert_bool(GameState.attach_aimed(Being.HERO)).is_true()


func test_a_creature_that_is_no_person_is_no_target_out_of_a_fight() -> void:
	GameState.attach("spell", "cure_wounds", 1)
	assert_str(GameState.attach_aim_why("summon:owl_1")).is_equal("ATTACH_AIM_NOT_HERE")
	assert_str(GameState.aim_attached("summon:owl_1")).is_equal("ATTACH_AIM_NOT_HERE")
	assert_str(GameState.attach_aim_why("npc_nobody_here")).is_equal("ATTACH_AIM_NOT_HERE")
