extends GdUnitTestSuite
## Usability after playtest-1 (roadmap v0.6.6): rules texts of SRD choices, the journal by tabs and locations, the
## chat markup, inspecting a foe, the save.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func after_test() -> void:
	GameState.session = null


func _session(preset_id: String = "fighter_aira") -> GameSession:
	var s := TestUtils.new_session()
	for p: Dictionary in data["presets"]:
		if p["id"] == preset_id:
			s.character = GameSession.normalized_character(CharacterBuilder.build_preset(p, data))
	CharacterRules.refresh(s.character, data)
	return s


func test_every_choice_of_creation_has_a_rules_text() -> void:
	for id: String in data["races"]["races"]:
		assert_str(InfoBox.race_text(data, id)).is_not_empty()
	for id: String in data["classes"]["classes"]:
		assert_str(InfoBox.class_text(data, id)).contains("Кость хитов")
	for id: String in data["classes"]["subclasses"]:
		assert_str(InfoBox.subclass_text(data, id)).contains("ур. —")
	for id: String in data["backgrounds"]:
		assert_str(InfoBox.background_text(data, id)).contains("Навыки")


func test_the_info_box_shows_the_hovered_choice() -> void:
	var box := InfoBox.new()
	var b := Button.new()
	b.text = "Чемпион"
	InfoBox.hook(b, box, b.text, "3 ур. — Улучшенный критический удар")
	b.mouse_entered.emit()
	assert_str(box.text()).contains("Улучшенный критический")
	box.free()
	b.free()


func test_the_chat_marks_bold_speech_names_and_escapes_brackets() -> void:
	var rx := RegEx.new()
	rx.compile("(?<![\\p{L}])Бруно\\p{L}{0,3}(?![\\p{L}])")
	var out := ChatView.rich("**Письмо** у Бруно: «Отнеси его [сейчас]».", [rx] as Array[RegEx])
	assert_str(out).contains("[b]Письмо[/b]")
	assert_str(out).contains("[lb]сейчас]")
	assert_str(out).contains("[color=#%s]Бруно[/color]" % UiTheme.NAME_COLOR.to_html(false))
	assert_str(out).contains("[color=#%s]«" % UiTheme.SPEECH_COLOR.to_html(false))
	assert_str(ChatView._stem("Ольховый")).is_equal("Ольхов\\p{L}{0,3}")
	assert_str(ChatView.rich("*Бруно вытирает руки.* Чего налить?", [] as Array[RegEx])).contains("[i]Бруно вытирает руки.[/i]")
	assert_str(ChatView.without_name("*Бруно Хмель откладывает кружку.*", "Бруно Хмель")).is_equal("*откладывает кружку.*")


func test_the_journal_groups_by_tab_and_location() -> void:
	var s := _session()
	GameState.session = s
	s.visited.append_array(["brod-square", "pushcha-edge"])
	s.summaries["dialogue:npc_innkeeper"] = "Бруно рассказал о пропавших."
	s.room_id = "brod-tavern-hall"
	var notes := WorldNotes.new(WorldNotes.JOURNAL)
	notes._tab = "places"
	var places := notes._groups(s, GameState.world())
	assert_array(places.map(func(g: Dictionary) -> String: return g["title"])).contains(["Сумеречная Пуща"])
	notes._tab = "people"
	var people := " ".join(notes._groups(s, GameState.world()).map(func(g: Dictionary) -> String: return " ".join(g["lines"])))
	assert_str(people).contains("Бруно Хмель — хозяин таверны").contains("Бруно рассказал")  # v0.7.22.7: a line of its own
	notes._tab = "quests"
	QuestRules.accept(s, data, "letter_to_ilva")
	var quests := notes._groups(s, GameState.world())
	assert_str(str(quests[0]["lines"][0])).contains("Письмо для Илвы")
	notes.free()


func test_inspecting_a_foe_opens_its_kind_for_good() -> void:
	var s := _session()
	CombatRules.start(s, data, [{"monster": "wolf", "col": 1}, {"monster": "wolf", "col": 2}])
	var order: Array = s.combat["order"]
	order.erase(CombatRules.PLAYER)
	order.push_front(CombatRules.PLAYER)
	s.combat["turn"] = 0
	CombatRules._begin_turn(s, data, [] as Array[String])
	assert_str(CombatRules.lore_skill(data, CombatRules.fighter(s, "e1"))).is_equal("nature")
	assert_int(CombatRules.lore_dc(data, CombatRules.fighter(s, "e1"))).is_equal(11)
	assert_str(CombatRules.monster_card(s, data, CombatRules.fighter(s, "e1"))).is_empty()
	s.character["skills"]["nature"] = 40
	var lines := CombatRules.player_inspect(s, data, "e1")
	assert_str(lines[0]).contains("теперь ясно")
	assert_int(int(CombatRules.economy(s)["bonus"])).is_equal(0)
	assert_str(CombatRules.can_inspect(s, data, "e2")).is_equal("COMBAT_NO_BONUS")
	var card := CombatRules.monster_card(s, data, CombatRules.fighter(s, "e2"))  # the same kind: known too
	assert_str(card).contains("КД 13").contains("Укус")
	var back := GameSession.from_dict(JSON.parse_string(JSON.stringify(s.to_dict(500))))
	assert_array(back.known_monsters).contains(["wolf"])
	var v13: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://test/fixtures/saves/save_v13.json"))
	SaveFormat.migrate(v13, {})
	assert_array(v13["session"]["known_monsters"]).is_empty()
