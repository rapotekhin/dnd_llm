class_name BrushButton
extends Button
## The square brush right of the input (v0.7.35): draws the last event. The icon is drawn, not a glyph — the game's
## font has no brush; while a frame is drawn the bristles pulse.

var busy := false:
	set(v):
		busy = v
		queue_redraw()


func _init() -> void:
	name = "BrushButton"
	custom_minimum_size = Vector2(60, 60)
	tooltip_text = "BTN_DRAW_EVENT"


func _process(_delta: float) -> void:
	if busy:
		queue_redraw()


func _draw() -> void:
	var c := get_theme_color("font_disabled_color" if disabled else "font_color")
	if busy:
		c.a = 0.45 + 0.4 * sin(Time.get_ticks_msec() / 180.0)
	var s := minf(size.x, size.y)
	var a := size / 2.0 + Vector2(0.3, -0.3) * s  # the handle's end, top right
	var u := Vector2(-0.6, 0.6) * s  # along the brush to its tip, bottom left
	var n := Vector2(u.y, -u.x).normalized() * s
	var at := func(t: float, w: float) -> Vector2: return a + u * t + n * w
	draw_line(at.call(0.0, 0.0), at.call(0.46, 0.0), c, s * 0.06, true)  # the handle
	draw_colored_polygon(PackedVector2Array([at.call(0.44, -0.05), at.call(0.44, 0.05), at.call(0.56, 0.06), at.call(0.56, -0.06)]), c)  # the ferrule
	draw_colored_polygon(PackedVector2Array([at.call(0.58, -0.065), at.call(0.58, 0.065), at.call(0.7, 0.09), at.call(0.84, 0.07),
		at.call(1.0, 0.0), at.call(0.84, -0.06), at.call(0.7, -0.085)]), c)  # the bristles
