class_name GameScreen
extends Control
## The game: chat on the left (narration, checks, options, input), side panel on the right.
## Input is locked while the master thinks or the connection is down; Esc opens the pause menu.

var chat: ChatView
var input: LineEdit
var send_button: Button
var _options: HFlowContainer
var _thinking: Label
var _cancel: Button
var _offline_banner: Label
var _pause: PauseMenu


func _ready() -> void:
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 32)
	margin.add_child(row)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 3.0
	left.add_theme_constant_override("separation", 14)
	row.add_child(left)
	_offline_banner = Label.new()
	_offline_banner.text = "BANNER_NO_MASTER"
	_offline_banner.add_theme_color_override("font_color", UiTheme.WARN)
	_offline_banner.visible = false
	left.add_child(_offline_banner)
	chat = ChatView.new()
	chat.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(chat)

	var status_row := HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 16)
	left.add_child(status_row)
	_thinking = Label.new()
	_thinking.text = "MSG_MASTER_THINKING"
	_thinking.theme_type_variation = UiTheme.MUTED_LABEL
	status_row.add_child(_thinking)
	_cancel = Button.new()
	_cancel.text = "BTN_CANCEL_TURN"
	_cancel.pressed.connect(GameState.cancel_turn)
	status_row.add_child(_cancel)

	_options = HFlowContainer.new()
	_options.add_theme_constant_override("h_separation", 12)
	_options.add_theme_constant_override("v_separation", 12)
	left.add_child(_options)

	var input_row := HBoxContainer.new()
	input_row.add_theme_constant_override("separation", 12)
	left.add_child(input_row)
	input = LineEdit.new()
	input.name = "Input"
	input.placeholder_text = "PLACEHOLDER_ACTION"
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.custom_minimum_size = Vector2(0, 60)
	input.text_submitted.connect(func(_t: String) -> void: _send())
	input_row.add_child(input)
	send_button = Button.new()
	send_button.text = "BTN_SEND"
	send_button.theme_type_variation = UiTheme.ACCENT_BUTTON
	send_button.custom_minimum_size = Vector2(180, 60)
	send_button.pressed.connect(_send)
	input_row.add_child(send_button)

	row.add_child(_side_panel())

	_pause = PauseMenu.new()
	_pause.visible = false
	add_child(_pause)
	_pause.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	EventBus.turn_started.connect(_on_turn_started)
	EventBus.turn_finished.connect(_on_turn_finished)
	EventBus.options_changed.connect(_on_options_changed)
	EventBus.backend_state_changed.connect(_on_backend_state_changed)
	_refresh()
	input.grab_focus.call_deferred()


func _side_panel() -> Control:
	var panel := PanelContainer.new()
	panel.theme_type_variation = UiTheme.SIDE
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 1.0
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	panel.add_child(col)
	var heading := Label.new()
	heading.text = "SIDE_CHARACTER"
	heading.theme_type_variation = UiTheme.HEADING
	col.add_child(heading)
	var placeholder := Label.new()
	placeholder.text = "SIDE_CHARACTER_SOON"
	placeholder.theme_type_variation = UiTheme.MUTED_LABEL
	placeholder.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(placeholder)
	var filler := Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(filler)
	col.add_child(BackendStatus.new())
	var menu := Button.new()
	menu.text = "BTN_MENU"
	menu.custom_minimum_size = Vector2(0, 56)
	menu.pressed.connect(func() -> void: _pause.open())
	col.add_child(menu)
	return panel


# _input, not _unhandled_input: the focused chat LineEdit would swallow Esc.
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause_menu"):
		_pause.toggle()
		get_viewport().set_input_as_handled()


func _on_turn_started(_turn_id: String) -> void:
	_refresh()


func _on_turn_finished(_turn_id: String, _ok: bool) -> void:
	_refresh()
	if Backend.is_ready():
		input.grab_focus()


func _on_options_changed(_options_list: Array[String]) -> void:
	_refresh()


func _on_backend_state_changed(_state: int, _detail: String) -> void:
	_refresh()


func _send() -> void:
	if GameState.submit(input.text):
		input.clear()


func _refresh() -> void:
	var busy := GameState.is_busy()
	var online := Backend.is_ready()
	_thinking.visible = busy
	_cancel.visible = busy and online
	_offline_banner.visible = not online
	input.editable = online and not busy
	send_button.disabled = not online or busy
	for c in _options.get_children():
		c.queue_free()
	if busy or not GameState.has_session():
		return
	if GameState.can_retry():
		_option_button("BTN_RETRY_TURN", GameState.retry, true).disabled = not online
	for o: String in GameState.session.options:
		var b := _option_button(o, func() -> void: GameState.submit(o), false)
		b.disabled = not online


func _option_button(text: String, action: Callable, translate: bool) -> Button:
	var b := Button.new()
	b.text = text
	if not translate:
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.custom_minimum_size = Vector2(0, 52)
	b.pressed.connect(action)
	_options.add_child(b)
	return b
