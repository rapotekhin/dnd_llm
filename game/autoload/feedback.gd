extends Node
## The «Баг / идея» button over every screen, in its top right corner: opens the author's feedback form in the browser.

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
	# The top right corner: free on every screen — at the bottom left it covered the hotbar's portrait and the
	# creation's «К выбору мира» (v0.8.4.43.42).
	b.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 2)
	b.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	b.pressed.connect(_open)


func _open() -> void:
	OS.shell_open(FORM_URL)
