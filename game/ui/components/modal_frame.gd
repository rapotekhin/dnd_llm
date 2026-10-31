class_name ModalFrame
extends Control
## One window template (v0.7.22.29, UI audit С4; a scene since v0.7.51): a dimmed backdrop, a panel in the middle with
## the title and «✕» in the corner, the body and the buttons on the right at the bottom. The height follows the content
## up to most of the screen, then the body scrolls. `width` 0 — the whole screen but a margin (the sheet, the map).
## Windows are made by `make`, or inherit the scene.

signal close_requested

const SCENE := "res://ui/components/modal_frame.tscn"
const MARGIN := 24

var title: Label
var close_x: Button
var body: VBoxContainer
var note: Label  ## an error or a hint over the buttons
var footer: HBoxContainer
var _scroll: ScrollContainer
var _panel: PanelContainer
var _width: float
var _queued := false


static func make(title_text: String = "", width: float = 640.0) -> ModalFrame:
	var frame := UiScenes.open(SCENE) as ModalFrame
	frame.setup(title_text, width)
	return frame


func required() -> Dictionary:
	return {
		"%ModalDim": "ColorRect", "%ModalPanel": "PanelContainer", "%ModalTitle": "Label", "%CloseX": "Button",
		"%ModalScroll": "ScrollContainer", "%ModalBody": "VBoxContainer", "%ModalNote": "Label",
		"%ModalFooter": "HBoxContainer",
	}


func setup(title_text: String, width: float) -> void:
	_width = width
	var dim: ColorRect = UiScenes.need(self, "%ModalDim")
	if width <= 0.0:
		dim.color = Color(UiTheme.BG, 0.94)  # a full window hides what is under it (Л1)
	_panel = UiScenes.need(self, "%ModalPanel")
	title = UiScenes.need(self, "%ModalTitle")
	title.text = title_text
	close_x = UiScenes.need(self, "%CloseX")
	close_x.pressed.connect(func() -> void: close_requested.emit())
	_scroll = UiScenes.need(self, "%ModalScroll")
	body = UiScenes.need(self, "%ModalBody")
	note = UiScenes.need(self, "%ModalNote")
	note.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	note.visible = false
	footer = UiScenes.need(self, "%ModalFooter")
	footer.visible = footer.get_child_count() > 0  # a window without buttons has no empty strip
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
