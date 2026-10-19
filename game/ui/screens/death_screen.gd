class_name DeathScreen
extends Control
## The hero died in a fight (roadmap v0.6.1): the master's epitaph and the hero's path; load the autosave made
## before the fight or go to the menu. «Одна жизнь» (no loading) — M5.

var epitaph: String


func _init(text: String = "") -> void:
	epitaph = text


func _ready() -> void:
	var center := CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.theme_type_variation = UiTheme.SIDE
	panel.custom_minimum_size = Vector2(1000, 0)
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	panel.add_child(col)
	var title := Label.new()
	title.text = "DEATH_TITLE"
	title.theme_type_variation = UiTheme.TITLE
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var s := GameState.session if GameState.has_session() else null
	if s != null:
		var c := s.character
		var who := Label.new()
		who.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		who.theme_type_variation = UiTheme.HEADING
		who.text = tr("DEATH_WHO").format({"name": c["name"], "race": c.get("race_name", ""), "class": c.get("class_name", ""), "level": int(c.get("level", 1))})
		col.add_child(who)
	var text := Label.new()
	text.name = "Epitaph"
	text.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.theme_type_variation = UiTheme.DM_TEXT
	text.text = epitaph
	col.add_child(text)
	if s != null:
		var path := Label.new()
		path.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		path.theme_type_variation = UiTheme.MUTED_LABEL
		path.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		path.text = tr("DEATH_PATH").format({"days": s.day, "quests": s.quests_done.size(), "xp": int(s.character.get("xp", 0))})
		col.add_child(path)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 16)
	col.add_child(buttons)
	var load := Button.new()
	load.name = "LoadBeforeFight"
	load.text = "BTN_LOAD_BEFORE_FIGHT"
	load.theme_type_variation = UiTheme.ACCENT_BUTTON
	load.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	load.custom_minimum_size = Vector2(0, 64)
	load.disabled = not SaveManager.has_slot(GameState.COMBAT_SAVE)
	load.pressed.connect(func() -> void:
		var err := GameState.load_from(GameState.COMBAT_SAVE)
		if not err.is_empty():
			EventBus.message.emit(tr(err)))
	buttons.add_child(load)
	var menu := Button.new()
	menu.name = "ToMenu"
	menu.text = "BTN_TO_MENU"
	menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	menu.custom_minimum_size = Vector2(0, 64)
	menu.pressed.connect(GameState.close_session)
	buttons.add_child(menu)
