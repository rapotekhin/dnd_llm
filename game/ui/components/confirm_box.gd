class_name ConfirmBox
extends Control
## «Точно?» before an irreversible act (v0.7.22.27, UI audit С3): attacking a person, finishing off, surrendering,
## resisting the guard. «Больше не показывать» (off by default) turns the questions off; the settings bring them
## back (SaveManager.confirm_risky).

signal answered(yes: bool)

var title_text: String
var body_text: String
var yes_text: String
var never: CheckBox
var yes: Button


func _init(title: String, body: String, yes_label: String) -> void:
	title_text = title
	body_text = body
	yes_text = yes_label


## Runs `go` at once when the questions are off (null), else after «yes» in the box it returns.
static func ask(host: Node, title: String, body: String, yes_label: String, go: Callable) -> ConfirmBox:
	if not SaveManager.confirm_risky:
		go.call()
		return null
	var box := ConfirmBox.new(title, body, yes_label)
	box.name = "ConfirmBox"
	var scene := host.get_tree().current_scene as Control
	box.theme = scene.theme if scene != null and scene.theme != null else UiTheme.build()  # the window root has no theme
	box.answered.connect(func(ok: bool) -> void:
		if ok:
			go.call())
	host.get_window().add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return box


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 100
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.theme_type_variation = UiTheme.SIDE
	panel.custom_minimum_size = Vector2(640, 0)
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	panel.add_child(col)
	var title := Label.new()
	title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	title.theme_type_variation = UiTheme.HEADING
	title.text = title_text
	col.add_child(title)
	var body := Label.new()
	body.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(600, 0)
	body.text = body_text
	col.add_child(body)
	never = CheckBox.new()
	never.name = "NeverAsk"
	never.text = "CONFIRM_NEVER"
	never.button_pressed = false
	col.add_child(never)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 12)
	col.add_child(row)
	var no := Button.new()
	no.name = "ConfirmNo"
	no.text = "BTN_CANCEL"
	no.custom_minimum_size = Vector2(180, 56)
	no.pressed.connect(_answer.bind(false))
	row.add_child(no)
	yes = Button.new()
	yes.name = "ConfirmYes"
	yes.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	yes.text = yes_text
	yes.custom_minimum_size = Vector2(220, 56)
	yes.add_theme_color_override("font_color", UiTheme.BAD)
	yes.pressed.connect(_answer.bind(true))
	row.add_child(yes)
	no.grab_focus.call_deferred()  # Enter must not do the irreversible thing by accident


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause_menu"):
		_answer(false)
		get_viewport().set_input_as_handled()


func _answer(ok: bool) -> void:
	if ok and never.button_pressed:  # «больше не показывать» counts only with «yes»
		SaveManager.confirm_risky = false
		SaveManager.save_settings()
	answered.emit(ok)
	queue_free()
