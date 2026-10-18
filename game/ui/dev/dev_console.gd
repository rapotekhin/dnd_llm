class_name DevConsole
extends PanelContainer
## Dev console (~): a command line over the top of the screen. Commands live in Dev.run().

var _log: Label
var _input: LineEdit
var _scroll: ScrollContainer


func _ready() -> void:
	visible = false
	theme_type_variation = UiTheme.SIDE
	set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	custom_minimum_size = Vector2(0, 420)
	var col := VBoxContainer.new()
	add_child(col)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(_scroll)
	_log = Label.new()
	_log.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log.theme_type_variation = UiTheme.MUTED_LABEL
	_scroll.add_child(_log)
	_input = LineEdit.new()
	_input.placeholder_text = "help"
	_input.text_submitted.connect(_on_submitted)
	col.add_child(_input)


func toggle() -> void:
	visible = not visible
	if visible:
		_input.grab_focus.call_deferred()


func clear() -> void:
	_log.text = ""


func _on_submitted(line: String) -> void:
	_input.clear()
	if line.strip_edges() == "`":
		return
	var out := Dev.run(line)
	_log.text += "> %s\n%s\n" % [line, out] if not out.is_empty() else "> %s\n" % line
	await get_tree().process_frame
	_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)
