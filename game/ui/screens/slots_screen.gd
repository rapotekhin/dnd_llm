class_name SlotsScreen
extends Control
## Save / load slot list: 10 manual slots, plus the autosave when loading.

const SCENE := "res://ui/screens/slots_screen.tscn"
const MODE_LOAD := "load"
const MODE_SAVE := "save"

var mode: String
var back: String
var _list: VBoxContainer


static func make(screen_mode: String, back_to: String) -> SlotsScreen:
	var screen := UiScenes.open(SCENE) as SlotsScreen
	screen.mode = screen_mode
	screen.back = back_to
	return screen


func required() -> Dictionary:
	return {"%Title": "Label", "%SlotList": "VBoxContainer", "%BackButton": "Button"}


func _ready() -> void:
	(UiScenes.need(self, "%Title") as Label).text = "TITLE_LOAD" if mode == MODE_LOAD else "TITLE_SAVE"
	_list = UiScenes.need(self, "%SlotList")
	(UiScenes.need(self, "%BackButton") as Button).pressed.connect(_back)
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
		b.custom_minimum_size = Vector2(0, 110)
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
	var slot_name := tr("SLOT_AUTOSAVE") if slot == SaveManager.AUTOSAVE else tr("SLOT_QUICKSAVE") if slot == SaveManager.QUICKSAVE \
		else tr("SLOT_N").format({"n": slot.trim_prefix("slot_")})
	if meta.is_empty():
		return "%s — %s" % [slot_name, tr("SLOT_EMPTY")]
	var head := "%s — %s" % [slot_name, str(meta.get("saved_at", "")).replace("T", " ")]
	if meta.has("day"):  # where, when and who (v0.7.22.27, Н6); older saves have only the turns
		head += "\n" + tr("SLOT_WHERE").format({"place": meta.get("place", meta.get("room_id", "")), "day": int(meta["day"]),
			"class": meta.get("class", ""), "level": int(meta.get("level", 1)), "name": meta.get("character", "")})
	else:
		head += " · " + tr("SLOT_TURNS").format({"n": meta.get("turns", 0)})
	return head + "\n" + str(meta.get("preview", ""))


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
