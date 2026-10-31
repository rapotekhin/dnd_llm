class_name KeyBox
extends ModalFrame
## «Нужен ключ OpenRouter» (ADR-0014): the master runs on the player's own key, kept only in the settings on this
## computer. Asked on the title screen when there is none or OpenRouter refused it. «✕» and Esc leave the question for later.

const SCENE := "res://ui/components/key_box.tscn"
const KEYS_URL := "https://openrouter.ai/keys"

var _edit: LineEdit


static func ask(host: Node) -> KeyBox:
	var box := UiScenes.open(SCENE) as KeyBox
	host.get_window().add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return box


func required() -> Dictionary:
	var nodes := super()
	nodes.merge({"%KeyText": "Label", "%KeyEdit": "LineEdit", "%KeyLater": "Button", "%KeySave": "Button", "%KeySite": "Button"})
	return nodes


func _ready() -> void:
	super()
	(UiScenes.need(self, "%KeyText") as Label).text = "KEY_REJECTED" if Backend.diagnosis_now() == Backend.DIAG_KEY_REJECTED else "KEY_NEEDED"
	_edit = UiScenes.need(self, "%KeyEdit")
	_edit.text_submitted.connect(func(_text: String) -> void: _save())
	(UiScenes.need(self, "%KeySite") as Button).pressed.connect(func() -> void: OS.shell_open(KEYS_URL))
	(UiScenes.need(self, "%KeySave") as Button).pressed.connect(_save)
	(UiScenes.need(self, "%KeyLater") as Button).pressed.connect(queue_free)
	close_requested.connect(queue_free)
	_edit.grab_focus.call_deferred()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause_menu"):
		queue_free()
		get_viewport().set_input_as_handled()


func _save() -> void:
	var key := _edit.text.strip_edges()
	if key.is_empty():
		set_note(tr("KEY_EMPTY"))
		return
	Backend.save_key(key)
	queue_free()
