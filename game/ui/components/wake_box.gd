class_name WakeBox
extends ModalFrame
## The dream's end (v0.8.4.44.2, the tutorial): the pack's words of waking and «Проснуться» — no other way out of it, no
## «✕», no Esc. The button wakes the player into a new game of the world (GameState.wake).

const SCENE := "res://ui/components/wake_box.tscn"


static func open(host: Node, text: String) -> WakeBox:
	var box := UiScenes.open(SCENE) as WakeBox
	host.get_window().add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	(UiScenes.need(box, "%WakeText") as Label).text = text
	return box


func required() -> Dictionary:
	var nodes := super()
	nodes.merge({"%WakeText": "Label", "%WakeButton": "Button"})
	return nodes


func _ready() -> void:
	super()
	close_x.visible = false
	var wake: Button = UiScenes.need(self, "%WakeButton")
	wake.pressed.connect(func() -> void:
		queue_free()
		GameState.wake())
	wake.grab_focus.call_deferred()
