class_name MainMenu
extends Control
## Title screen: continue the latest save, new game, load, settings, quit; master status in the corner.


func _ready() -> void:
	var center := CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	col.custom_minimum_size = Vector2(520, 0)
	center.add_child(col)

	var title := Label.new()
	title.text = "GAME_TITLE"
	title.theme_type_variation = UiTheme.TITLE
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "GAME_SUBTITLE"
	subtitle.theme_type_variation = UiTheme.MUTED_LABEL
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(subtitle)
	col.add_child(_spacer(36))

	var latest := SaveManager.latest_slot()
	if not latest.is_empty():
		var cont := _button(col, "BTN_CONTINUE", func() -> void: GameEntry.enter({"kind": "load", "slot": latest}))
		cont.theme_type_variation = UiTheme.ACCENT_BUTTON
		cont.name = "ContinueButton"
		cont.tooltip_text = _slot_hint(latest)
	_button(col, "BTN_NEW_GAME", func() -> void: EventBus.navigate.emit("creation", {})).name = "NewGameButton"
	_button(col, "BTN_LOAD", func() -> void: EventBus.navigate.emit("slots", {"mode": SlotsScreen.MODE_LOAD, "back": "menu"}))
	_button(col, "BTN_SETTINGS", func() -> void: EventBus.navigate.emit("settings", {"back": "menu"}))
	_button(col, "BTN_QUIT", func() -> void: get_tree().quit())

	var status := BackendStatus.new()
	add_child(status)
	status.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 32)
	status.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	status.grow_vertical = Control.GROW_DIRECTION_BEGIN

	var version := Label.new()
	version.text = "v%s" % ProjectSettings.get_setting("application/config/version", "")
	version.theme_type_variation = UiTheme.MUTED_LABEL
	add_child(version)
	version.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 32)
	version.grow_vertical = Control.GROW_DIRECTION_BEGIN


func _button(parent: Control, key: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = key
	b.custom_minimum_size = Vector2(0, 64)
	b.pressed.connect(action)
	parent.add_child(b)
	return b


func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func _slot_hint(slot: String) -> String:
	var meta := SaveManager.slot_meta(slot)
	return tr("SLOT_HINT").format({"turns": meta.get("turns", 0), "date": str(meta.get("saved_at", "")).replace("T", " ")})
