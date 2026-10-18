class_name SlotsScreen
extends Control
## Save / load slot list: 10 manual slots, plus the autosave when loading.

const MODE_LOAD := "load"
const MODE_SAVE := "save"

var mode: String
var back: String
var _list: VBoxContainer


func _init(screen_mode: String, back_to: String) -> void:
	mode = screen_mode
	back = back_to


func _ready() -> void:
	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 320)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 80)
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	margin.add_child(col)

	var title := Label.new()
	title.text = "TITLE_LOAD" if mode == MODE_LOAD else "TITLE_SAVE"
	title.theme_type_variation = UiTheme.HEADING
	col.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 10)
	scroll.add_child(_list)
	var back_btn := Button.new()
	back_btn.text = "BTN_BACK"
	back_btn.custom_minimum_size = Vector2(240, 56)
	back_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back_btn.pressed.connect(_back)
	col.add_child(back_btn)
	_fill()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause_menu"):
		_back()
		get_viewport().set_input_as_handled()


func _fill() -> void:
	for c in _list.get_children():
		c.queue_free()
	var slots := SaveManager.all_slots() if mode == MODE_LOAD else SaveManager.manual_slots()
	for slot: String in slots:
		var meta := SaveManager.slot_meta(slot)
		if mode == MODE_LOAD and meta.is_empty():
			continue
		var b := Button.new()
		b.name = slot
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 72)
		b.text = _label(slot, meta)
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.pressed.connect(_on_slot.bind(slot))
		_list.add_child(b)
	if _list.get_child_count() == 0:
		var empty := Label.new()
		empty.text = "MSG_NO_SAVES"
		empty.theme_type_variation = UiTheme.MUTED_LABEL
		_list.add_child(empty)


func _label(slot: String, meta: Dictionary) -> String:
	var slot_name := tr("SLOT_AUTOSAVE") if slot == SaveManager.AUTOSAVE else tr("SLOT_N").format({"n": slot.trim_prefix("slot_")})
	if meta.is_empty():
		return "%s — %s" % [slot_name, tr("SLOT_EMPTY")]
	return "%s — %s · %s   %s" % [slot_name, tr("SLOT_TURNS").format({"n": meta.get("turns", 0)}),
		str(meta.get("saved_at", "")).replace("T", " "), str(meta.get("preview", ""))]


func _on_slot(slot: String) -> void:
	if mode == MODE_LOAD:
		GameEntry.enter({"kind": "load", "slot": slot})
		return
	if GameState.save_to(slot):
		EventBus.message.emit(tr("MSG_SAVED"))
		_back()
	else:
		EventBus.message.emit(tr("MSG_SAVE_FAILED"))


func _back() -> void:
	EventBus.navigate.emit(back, {})
