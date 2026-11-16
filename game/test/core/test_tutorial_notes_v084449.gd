extends GdUnitTestSuite
## v0.8.4.44.9, the author's 18 notes on the tutorial (2026-11-16): the first hall told by its pack text without the
## master; no furnishing by the master in the dream; the wound's screen by the fact `hurt`; a bound creature's main act is
## «Развязать»; the right button opens a foe's acts and the left strikes it.

var _settings_path: String
var _done: bool


func before_test() -> void:
	_settings_path = SaveManager.settings_path
	_done = SaveManager.tutorial_done
	SaveManager.settings_path = "user://test_tutorial_notes_settings.cfg"
	SaveManager.tutorial_done = false


func after_test() -> void:
	GameState.session = null
	GameState.busy_turn = ""
	Catalog.activate("frontier")
	DirAccess.remove_absolute(SaveManager.settings_path)
	SaveManager.settings_path = _settings_path
	SaveManager.tutorial_done = _done


func _dream() -> GameSession:
	Catalog.activate("frontier")
	var choices := {}
	for p: Dictionary in Catalog.data["presets"]:
		if str(p["id"]) == "fighter_aira":
			choices = CharacterBuilder.preset_choices(p)
	var settings := WorldPack.default_settings(Catalog.data["pack"])
	settings["tutorial"] = true
	settings["seed"] = "7"
	GameState.new_game(CharacterBuilder.build(choices, Catalog.data), settings, -1, choices)
	return GameState.session


## The note «первая генерация заменена фиксированным текстом»: the first hall's `told` is the entry, no master's turn.
func test_the_first_hall_is_told_by_the_pack_without_the_master() -> void:
	var s := _dream()
	assert_str(s.room_id).is_equal("dream-1")
	assert_bool(GameState.is_busy()).is_false()
	var told := str(WorldView.new(Catalog.data["world"]).room("dream-1").get("told", ""))
	assert_str(told).is_not_empty()
	assert_bool(s.chat.any(func(e: Dictionary) -> bool: return str(e.get("text", "")) == told)).is_true()
	assert_bool(s.described.has("dream-1")).is_true()


func test_the_master_furnishes_nothing_in_the_dream() -> void:
	var s := _dream()
	assert_bool(DreamRules.closes(Catalog.data, "furnish")).is_true()
	assert_bool(PropRules.needs_furnish(s, "dream-1", Catalog.data)).is_false()


func test_hurt_is_a_fact_of_the_hero_s_wound() -> void:
	var s := TestUtils.new_session()
	s.character["hp"] = int(s.character["max_hp"])
	assert_bool(Cond.met(s, {"hurt": true})).is_false()
	s.character["hp"] = int(s.character["max_hp"]) - 1
	assert_bool(Cond.met(s, {"hurt": true})).is_true()
	assert_bool(WorldPack._when_ok({"hurt": true}, false)).is_true()  # a pack may name it (one list: Cond.FACTS)


## The note «на клик левой кнопкой — развязать пленника»: a bound one's main act is to untie it, its search after.
func test_a_bound_creature_s_main_act_is_to_untie_it() -> void:
	assert_array(SidePanel.MAIN["cr"]).is_equal(["Creature_untie_", "Creature_search_"])
	var box := VBoxContainer.new()
	for n: String in ["Creature_search_c1", "Creature_untie_c1"]:
		var b := Button.new()
		b.name = n
		box.add_child(b)
	assert_str(str(SidePanel.main_of(box, "cr:c1").name)).is_equal("Creature_untie_c1")
	(box.get_node("Creature_untie_c1") as Button).disabled = true  # nobody bound: the search
	assert_str(str(SidePanel.main_of(box, "cr:c1").name)).is_equal("Creature_search_c1")
	box.free()
