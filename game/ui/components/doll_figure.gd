class_name DollFigure
extends Control
## A plain outline of a figure between the slots of the doll; a sprite can take its place.


func _draw() -> void:
	var k := minf(size.y / 400.0, size.x / 170.0)
	var cx := size.x / 2.0
	var top := maxf(0.0, (size.y - 400.0 * k) / 2.0)
	var col := Color(UiTheme.BORDER, 0.9)
	var p := func(x: float, y: float) -> Vector2: return Vector2(cx + x * k, top + y * k)
	draw_arc(p.call(0, 44), 26 * k, 0, TAU, 32, col, 3.0, true)
	draw_line(p.call(0, 70), p.call(0, 86), col, 3.0, true)
	draw_polyline(PackedVector2Array([p.call(-46, 96), p.call(46, 96), p.call(36, 226), p.call(-36, 226), p.call(-46, 96)]), col, 3.0, true)
	draw_line(p.call(-46, 96), p.call(-70, 222), col, 3.0, true)
	draw_line(p.call(46, 96), p.call(70, 222), col, 3.0, true)
	draw_line(p.call(-22, 226), p.call(-28, 380), col, 3.0, true)
	draw_line(p.call(22, 226), p.call(28, 380), col, 3.0, true)
