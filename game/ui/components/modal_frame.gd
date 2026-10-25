class_name ModalFrame
extends Control
## One window template (v0.7.22.29, UI audit С4): a dimmed backdrop, a panel in the middle with the title and «✕» in the
## corner, the body and the buttons on the right at the bottom. The height follows the content up to most of the
## screen, then the body scrolls. `width` 0 — the whole screen but a margin (the sheet, the map).

signal close_requested

const MARGIN := 24

var title: Label
var close_x: Button
var body: VBoxContainer
var note: Label  ## an error or a hint over the buttons
var footer: HBoxContainer
var _scroll: ScrollContainer
var _panel: PanelContainer
var _width: float
var _title_text: String
var _queued := false


func _init(title_text: String = "", width: float = 640.0) -> void:
	_title_text = title_text
	_width = width
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(UiTheme.BG, 0.94) if width <= 0.0 else Color(0, 0, 0, 0.6)  # a full window hides what is under it (Л1)
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel = PanelContainer.new()
	_panel.theme_type_variation = UiTheme.SIDE
	add_child(_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	_panel.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	col.add_child(head)
	title = Label.new()
	title.theme_type_variation = UiTheme.HEADING
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.text = title_text
	head.add_child(title)
	close_x = Button.new()
	close_x.name = "CloseX"
	close_x.text = "✕"
	close_x.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	close_x.tooltip_text = "BTN_CLOSE"
	close_x.flat = true
	close_x.custom_minimum_size = Vector2(48, 48)
	close_x.pressed.connect(func() -> void: close_requested.emit())
	head.add_child(close_x)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_scroll)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	_scroll.add_child(body)
	note = Label.new()
	note.name = "ModalNote"
	note.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override("font_color", UiTheme.WARN)
	note.visible = false
	col.add_child(note)
	footer = HBoxContainer.new()
	footer.name = "ModalFooter"
	footer.alignment = BoxContainer.ALIGNMENT_END
	footer.add_theme_constant_override("separation", 12)
	footer.visible = false  # until a button: a window without buttons has no empty strip
	col.add_child(footer)
	body.minimum_size_changed.connect(_refit)
	resized.connect(_refit)
	_panel.minimum_size_changed.connect(_refit)  # a panel grown past the screen on a first layout shrinks back
	footer.visibility_changed.connect(_refit)
	visibility_changed.connect(func() -> void:
		if is_visible_in_tree():
			_refit())


## A body that fills the window (a TabContainer of its own): no outer scroll, the whole height.
func fill_body(content: Control) -> void:
	body.minimum_size_changed.disconnect(_refit)
	_scroll.get_parent().remove_child(_scroll)
	_scroll.queue_free()  # the old body goes with it
	var col := note.get_parent()
	col.add_child(content)
	col.move_child(content, 1)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll = null
	_fit()


func set_width(width: float) -> void:
	if width != _width:
		_width = width
		_refit()


func add_button(text: String, action: Callable, accent: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(160, 52)
	if accent:
		b.theme_type_variation = UiTheme.ACCENT_BUTTON
	b.pressed.connect(action)
	footer.add_child(b)
	footer.visible = true
	return b


func set_note(text: String) -> void:
	note.text = text
	note.visible = not text.is_empty()


func clear_body() -> void:
	for ch in body.get_children():
		body.remove_child(ch)
		ch.queue_free()


## Wrapped labels learn their height only after a layout at the new width: fit once a frame until it settles.
func _refit() -> void:
	if not _queued:
		_queued = true
		_fit.call_deferred()


func _fit() -> void:
	_queued = false
	if size.y <= 0.0:
		return
	var full := _width <= 0.0
	var w := size.x - 2 * MARGIN if full else minf(_width, size.x - 2 * MARGIN)
	var cap := size.y - 2 * MARGIN
	if full:
		_panel.size = Vector2(w, cap)
		_panel.position = Vector2(MARGIN, MARGIN)
		return
	if _scroll != null:
		var chrome := _panel.get_combined_minimum_size().y - _scroll.custom_minimum_size.y
		var want := clampf(body.get_combined_minimum_size().y, 60.0, maxf(60.0, cap - chrome))
		if absf(want - _scroll.custom_minimum_size.y) > 0.5:
			_scroll.custom_minimum_size.y = want
	_panel.size = Vector2(w, 0)  # shrinks to its minimum height
	_panel.reset_size()
	_panel.size.x = w
	_panel.position = ((size - _panel.size) / 2.0).floor()
