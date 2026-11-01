class_name MapField
extends Control
## The field of the one screen (v0.8.1): a map of squares, plain tiles from code, tokens that walk. The wheel zooms around
## the cursor, a drag moves the view; a small room fits whole, a big one follows the hero until the view is dragged away.
## The field knows nothing of rooms and rules: it says which square was clicked and which were reached. It is written to
## take the fight of v0.8.4 as well.

signal cell_clicked(cell: Vector2i)
signal stepped(cell: Vector2i)  ## the hero reached a square of the path
signal arrived  ## the hero reached the end of the path

const MIN_TILE := 10.0
const MAX_TILE := 76.0
const BASE_TILE := 38.0
const SPEED := 7.0  ## squares a second
const DRAG_FROM := 6.0  ## pixels: less is a click
const ZOOM_STEP := 1.15
const LABEL_FROM := 20.0  ## a tile under this has no names on it
const FONT_SIZE := 15

var map: Dictionary = {}
var lib: Dictionary = {}
var names: Dictionary = {}  ## the name of a way out by the room it leads to
var hero_mark := ""  ## the hero's letter; empty — no hero on this map (the author's preview)
var clicks := true  ## false while a conversation holds the field

var _tile := BASE_TILE
var _corner := Vector2.ZERO  ## where the map's corner is on the field
var _follow := true
var _pos := Vector2.ZERO  ## the hero, in squares
var _path: Array[Vector2i] = []
var _trail: Array[Vector2] = []
var _tokens: Array[Dictionary] = []  ## those who walk with the hero: {"mark", "name", "pos"}
var _hover := Vector2i(-1, -1)
var _pressed := false
var _dragged := false
var _press_at := Vector2.ZERO


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(_on_resized)
	set_process(false)


func show_map(m: Dictionary, world_lib: Dictionary) -> void:
	var same: bool = not map.is_empty() and map["id"] == m["id"]
	map = m
	lib = world_lib
	if not same:
		_fit()
	queue_redraw()


## The hero stands at `cell`: nothing to do while walking towards it, a jump otherwise.
func place_hero(cell: Vector2i, mark: String, walkers: Array[Dictionary]) -> void:
	hero_mark = mark
	if walking():
		return
	if Vector2(cell) != _pos or _tokens.size() != walkers.size():
		_pos = Vector2(cell)
		_trail.clear()
		_follow = true
		_seat(walkers)
	else:
		for i: int in walkers.size():
			_tokens[i]["mark"] = walkers[i]["mark"]
			_tokens[i]["name"] = walkers[i]["name"]
	_aim()
	queue_redraw()


func _seat(walkers: Array[Dictionary]) -> void:
	_tokens.clear()
	var spots := WalkRules.around(map, lib, Vector2i(_pos), walkers.size()) if not map.is_empty() else ([] as Array[Vector2i])
	for i: int in walkers.size():
		var at := Vector2(spots[i]) if i < spots.size() else _pos
		_tokens.append({"mark": walkers[i]["mark"], "name": walkers[i]["name"], "pos": at})


func walking() -> bool:
	return not _path.is_empty()


func walk(steps: Array[Vector2i]) -> void:
	_path = steps.duplicate()
	_follow = true
	set_process(not _path.is_empty())
	if _path.is_empty():
		arrived.emit()


func stop() -> void:
	_path.clear()
	set_process(false)


func _process(delta: float) -> void:
	if _path.is_empty():
		set_process(false)
		return
	var next := Vector2(_path[0])
	_pos = _pos.move_toward(next, SPEED * delta)
	for i: int in _tokens.size():  # each one a step behind the one before
		var wanted: Vector2 = _trail[-(i + 1) * 2] if _trail.size() >= (i + 1) * 2 else _tokens[i]["pos"]
		_tokens[i]["pos"] = (_tokens[i]["pos"] as Vector2).move_toward(wanted, SPEED * delta)
	_aim()
	queue_redraw()
	if _pos == next:
		_trail.append(next)
		var reached: Vector2i = _path.pop_front()
		stepped.emit(reached)
		if _path.is_empty():
			set_process(false)
			arrived.emit()


func _on_resized() -> void:
	if not map.is_empty():
		_fit()


## The tile the whole map fits at, never bigger than the base one; then the view goes to the hero.
func _fit() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var whole := minf(size.x / float(map["w"]), size.y / float(map["h"]))
	_tile = clampf(whole, MIN_TILE, BASE_TILE)
	_follow = true
	_aim()


func _map_size() -> Vector2:
	return Vector2(float(map["w"]), float(map["h"])) * _tile


## The view on the hero: what fits stands in the middle, what does not is held to its edges.
func _aim() -> void:
	if map.is_empty() or not _follow:
		return
	var want := size / 2.0 - (_pos + Vector2(0.5, 0.5)) * _tile
	var full := _map_size()
	_corner.x = (size.x - full.x) / 2.0 if full.x <= size.x else clampf(want.x, size.x - full.x, 0.0)
	_corner.y = (size.y - full.y) / 2.0 if full.y <= size.y else clampf(want.y, size.y - full.y, 0.0)


func _hold() -> void:  # a part of the map always stays in the frame
	var full := _map_size()
	var keep := size * 0.25
	_corner.x = clampf(_corner.x, keep.x - full.x, size.x - keep.x)
	_corner.y = clampf(_corner.y, keep.y - full.y, size.y - keep.y)


func cell_at(point: Vector2) -> Vector2i:
	return Vector2i(((point - _corner) / _tile).floor())


func zoom(steps: float, around_point: Vector2) -> void:
	var at := (around_point - _corner) / _tile
	_tile = clampf(_tile * pow(ZOOM_STEP, steps), MIN_TILE, MAX_TILE)
	_corner = around_point - at * _tile
	_follow = false
	_hold()
	queue_redraw()


func tile() -> float:
	return _tile


func corner() -> Vector2:
	return _corner


func hero_cell() -> Vector2i:
	return Vector2i(_pos.round())


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var b := event as InputEventMouseButton
		if b.pressed and b.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom(1.0, b.position)
		elif b.pressed and b.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom(-1.0, b.position)
		elif b.button_index == MOUSE_BUTTON_LEFT or b.button_index == MOUSE_BUTTON_RIGHT or b.button_index == MOUSE_BUTTON_MIDDLE:
			_press(b)
		accept_event()
	elif event is InputEventMouseMotion:
		var m := event as InputEventMouseMotion
		if _pressed and (_dragged or m.position.distance_to(_press_at) >= DRAG_FROM):
			_dragged = true
			_follow = false
			_corner += m.relative
			_hold()
			queue_redraw()
		var cell := cell_at(m.position)
		if cell != _hover:
			_hover = cell
			queue_redraw()


func _press(b: InputEventMouseButton) -> void:
	if b.pressed:
		_pressed = true
		_dragged = false
		_press_at = b.position
		return
	_pressed = false
	if not _dragged and b.button_index == MOUSE_BUTTON_LEFT and clicks and not map.is_empty():
		cell_clicked.emit(cell_at(b.position))


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), UiTheme.BG)
	if map.is_empty():
		return
	var t := _tile
	var rows: Array[String] = map["rows"]
	var first := Vector2i((-_corner / t).floor()).max(Vector2i.ZERO)
	var last := Vector2i(((size - _corner) / t).ceil()).min(Vector2i(int(map["w"]), int(map["h"])))
	for y: int in range(first.y, last.y):
		for x: int in range(first.x, last.x):
			var c: String = rows[y][x]
			if c == LayoutGen.BLANK:
				continue
			var at := _corner + Vector2(x, y) * t
			var fill: Color = UiTheme.TILES.get(c, UiTheme.TILES["."])
			if (x + y) % 2 == 1 and c != LayoutGen.WALL:
				fill = fill.darkened(0.05)
			draw_rect(Rect2(at, Vector2(t, t)), fill)
			if c == LayoutGen.WALL and y > 0 and rows[y - 1][x] != LayoutGen.WALL:
				draw_rect(Rect2(at, Vector2(t, maxf(2.0, t * 0.14))), UiTheme.TILES["#"].lightened(0.25))
			elif t >= LABEL_FROM:
				draw_rect(Rect2(at, Vector2(t, t)), Color(0, 0, 0, 0.14), false, 1.0)
	if clicks and _hover.x >= 0 and _hover.y >= 0 and _hover.x < int(map["w"]) and _hover.y < int(map["h"]):
		draw_rect(Rect2(_corner + Vector2(_hover) * t, Vector2(t, t)), UiTheme.ACCENT_BRIGHT, false, 1.5)
	for e: Dictionary in map["exits"]:
		draw_rect(Rect2(_corner + Vector2(int(e["x"]), int(e["y"])) * t, Vector2(t, t)), UiTheme.ACCENT)
	_draw_path(t)
	for e: Dictionary in map["exits"]:
		_exit_label(e, t)
	for tok: Dictionary in _tokens:
		_token(tok["pos"], str(tok["mark"]), str(tok["name"]), UiTheme.OK, 0.34)
	if not hero_mark.is_empty():
		_token(_pos, hero_mark, "", UiTheme.ACCENT_BRIGHT, 0.4)


func _draw_path(t: float) -> void:
	var at := _pos
	for cell: Vector2i in _path:
		var dot := (at + Vector2(cell)) / 2.0
		draw_circle(_corner + (dot + Vector2(0.5, 0.5)) * t, maxf(1.5, t * 0.05), UiTheme.ACCENT_BRIGHT)
		draw_circle(_corner + (Vector2(cell) + Vector2(0.5, 0.5)) * t, maxf(1.5, t * 0.05), UiTheme.ACCENT_BRIGHT)
		at = Vector2(cell)


func _exit_label(e: Dictionary, t: float) -> void:
	if t < LABEL_FROM:
		return
	var font := get_theme_default_font()
	var text := str(names.get(str(e["to"]), e["to"]))
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	var mid := _corner + Vector2(int(e["x"]) + 0.5, int(e["y"])) * t
	var box := Rect2(mid.x - w / 2.0 - 6.0, mid.y - 26.0, w + 12.0, 22.0)
	draw_rect(box, Color(UiTheme.BG, 0.88))
	draw_string(font, Vector2(box.position.x + 6.0, box.position.y + 16.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, UiTheme.ACCENT_BRIGHT)


func _token(pos: Vector2, mark: String, label: String, colour: Color, part: float) -> void:
	var t := _tile
	var mid := _corner + (pos + Vector2(0.5, 0.5)) * t
	var r := t * part
	draw_circle(mid, r, UiTheme.PANEL)
	draw_arc(mid, r, 0.0, TAU, 32, colour, maxf(1.5, t * 0.07), true)
	if t < LABEL_FROM:
		return
	var font := get_theme_default_font()
	var size_px := int(r)
	var w := font.get_string_size(mark, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
	draw_string(font, mid + Vector2(-w / 2.0, r * 0.38), mark, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, colour)
	if not label.is_empty():
		var lw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE - 2).x
		draw_string_outline(font, mid + Vector2(-lw / 2.0, r + 16.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE - 2, 3, UiTheme.BG)
		draw_string(font, mid + Vector2(-lw / 2.0, r + 16.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE - 2, UiTheme.TEXT)
