extends GdUnitTestSuite
## The chat's look (v0.8.4.43.5.1): the story in its own styles, the engine's lines one quiet style, a repeat of one
## rebuilt where it stands as «×N» — still selectable, its rolls on hover.

var kept: GameSession


func before_test() -> void:
	kept = GameState.session
	GameState.session = TestUtils.new_session()


func after_test() -> void:
	GameState.session = kept


func _chat() -> ChatView:
	var chat: ChatView = auto_free(ChatView.new())
	chat.size = Vector2(500, 600)
	add_child(chat)
	return chat


func _lines(chat: ChatView) -> Array[Node]:
	return chat.get_child(0).get_children()


func test_each_kind_has_its_one_style() -> void:
	var s := GameState.session
	s.append(GameSession.dm_entry("Низкий зал пахнет дымом.", "t-1"))
	s.append(GameSession.effect_entry(["Переход: Рыночная площадь"] as Array[String]))
	s.append(GameSession.system_entry("QUEST_ACT_BUILDING"))
	s.append(GameSession.player_entry("Осматриваюсь"))
	var lines := _lines(_chat())
	assert_int(lines.size()).is_equal(4)
	assert_str((lines[0] as RichTextLabel).theme_type_variation).is_equal(UiTheme.DM_TEXT + UiTheme.RICH)
	assert_str((lines[1] as RichTextLabel).theme_type_variation).is_equal(UiTheme.ENGINE_TEXT + UiTheme.RICH)
	assert_str((lines[2] as RichTextLabel).theme_type_variation).is_equal(UiTheme.ENGINE_TEXT + UiTheme.RICH)
	assert_str((lines[3] as RichTextLabel).theme_type_variation).is_equal(UiTheme.PLAYER_TEXT + UiTheme.RICH)
	# the quiet look is the theme's: smaller than the story, its own colour
	var dm := lines[0] as RichTextLabel
	var engine := lines[1] as RichTextLabel
	assert_int(engine.get_theme_font_size("normal_font_size")).is_less(dm.get_theme_font_size("normal_font_size"))
	assert_bool(engine.get_theme_color("default_color") != dm.get_theme_color("default_color")).is_true()


func test_a_repeat_is_one_line_with_its_count() -> void:
	var chat := _chat()
	var before := _lines(chat).size()
	for i in 3:
		GameState.session.roll_notes.append({"what": "Ловкость рук", "nat": 10 + i, "total": 13 + i})
		GameState._add(GameSession.effect_entry(["Взято: кружка"] as Array[String]))
	await await_idle_frame()
	var lines := _lines(chat)  # the line said before is gone, its count on the new one
	assert_int(lines.size()).is_equal(before + 1)
	var line := lines[-1] as RichTextLabel
	assert_str(line.get_parsed_text()).is_equal("Взято: кружка ×3")
	assert_bool(line.selection_enabled and line.context_menu_enabled).is_true()  # still selected and copied
	assert_str(line.tooltip_text).contains("к20 10").contains("к20 12")  # the breakdown of every repeat on hover


func test_the_story_said_twice_stays_twice() -> void:
	var chat := _chat()
	for i in 2:
		GameState._add(GameSession.dm_entry("Вы осматриваетесь.", "t-%d" % i))
	assert_int(_lines(chat).size()).is_equal(2)
	assert_str((_lines(chat)[-1] as RichTextLabel).get_parsed_text()).is_equal("Вы осматриваетесь.")


func test_a_loaded_chat_shows_the_count() -> void:
	var s := GameState.session
	for i in 2:
		s.append(GameSession.system_entry("QUEST_ACT_BUILDING"))
	var line := _lines(_chat())[0] as RichTextLabel
	assert_str(line.get_parsed_text()).ends_with(" ×2")
