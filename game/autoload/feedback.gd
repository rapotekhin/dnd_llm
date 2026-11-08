extends Node
## The «Баг / идея» button over every screen: opens the author's feedback form in the browser.

const FORM_URL := "https://docs.google.com/forms/d/e/1FAIpQLScsW5hjbGIXwoS8gJAxUrnwiFbkVn00JWoUQ_8jMC8kV6ZiNw/viewform?usp=dialog"


func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 90
	add_child(layer)
	var b := Button.new()
	b.text = tr("FEEDBACK_BUTTON")
	b.tooltip_text = tr("FEEDBACK_TIP")
	b.focus_mode = Control.FOCUS_NONE
	b.modulate.a = 0.75
	layer.add_child(b)
	b.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 6)
	b.grow_vertical = Control.GROW_DIRECTION_BEGIN
	b.pressed.connect(_open)


func _open() -> void:
	OS.shell_open(FORM_URL)
