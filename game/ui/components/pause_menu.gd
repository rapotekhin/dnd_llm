class_name PauseMenu
extends Control
## In-game menu over a dimmed screen: continue, save, load, settings, exit to the main menu.


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.theme_type_variation = UiTheme.SIDE
	panel.custom_minimum_size = Vector2(480, 0)
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	panel.add_child(col)
	var title := Label.new()
	title.text = "TITLE_PAUSE"
	title.theme_type_variation = UiTheme.HEADING
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	_button(col, "BTN_RESUME", func() -> void: visible = false)
	_button(col, "BTN_SAVE", func() -> void: EventBus.navigate.emit("slots", {"mode": SlotsScreen.MODE_SAVE, "back": "game"}))
	_button(col, "BTN_LOAD", func() -> void: EventBus.navigate.emit("slots", {"mode": SlotsScreen.MODE_LOAD, "back": "game"}))
	_button(col, "BTN_SETTINGS", func() -> void: EventBus.navigate.emit("settings", {"back": "game"}))
	_button(col, "BTN_EXIT_TO_MENU", GameState.close_session)


func open() -> void:
	visible = true


func toggle() -> void:
	visible = not visible


func _button(parent: Control, key: String, action: Callable) -> void:
	var b := Button.new()
	b.text = key
	b.custom_minimum_size = Vector2(0, 56)
	b.pressed.connect(action)
	parent.add_child(b)
