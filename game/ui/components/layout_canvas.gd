class_name LayoutCanvas
extends Control
## Draws a layout from LayoutGen: squares, doors, marks and ways out, plain tiles from code. The field of the one screen
## (v0.8.1) grows from it.

const MIN_TILE := 4.0

var map: Dictionary = {}


func show_map(m: Dictionary) -> void:
	map = m
	queue_redraw()


func _tile() -> float:
	if map.is_empty():
		return MIN_TILE
	return maxf(MIN_TILE, minf(size.x / float(map["w"]), size.y / float(map["h"])))


func _draw() -> void:
	if map.is_empty():
		return
	var t := _tile()
	var rows: Array[String] = map["rows"]
	for y: int in rows.size():
		for x: int in rows[y].length():
			var c: String = rows[y][x]
			if c != LayoutGen.BLANK:
				draw_rect(Rect2(x * t, y * t, t, t), UiTheme.TILES.get(c, UiTheme.TILES["."]))
	for e: Dictionary in map["exits"]:
		draw_rect(Rect2(int(e["x"]) * t, int(e["y"]) * t, t, t), UiTheme.ACCENT_BRIGHT)
	var font := get_theme_default_font()
	for m: Dictionary in map["marks"]:
		draw_circle(Vector2((int(m["x"]) + 0.5) * t, (int(m["y"]) + 0.5) * t), t * 0.3, UiTheme.OK if str(m["name"]) == LayoutGen.ENTRY else UiTheme.ACCENT)
	if t >= 12.0:
		for e: Dictionary in map["exits"]:
			draw_string(font, Vector2(int(e["x"]) * t, int(e["y"]) * t), str(e["to"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UiTheme.TEXT)
