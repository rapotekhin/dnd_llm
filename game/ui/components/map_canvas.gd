class_name MapCanvas
extends Control
## The map scheme (roadmap v0.7.6): visited rooms as named points grouped by location, the open exits out of them
## as «?», the hero's room, quest marks; the wheel zooms around the cursor, a drag pans, a click picks a room.
## Positions come from WorldMap.layout (0..1); the view (zoom, pan) is kept by the owner between rebuilds.

signal picked(room_id: String)
signal view_changed(zoom: float, pan: Vector2)

const R_ROOM := 13.0
const R_FRONTIER := 9.0
const PAD := 60.0
const STRETCH := 1.8  # how much wider than tall the scheme may be drawn
const ZOOM_MIN := 0.6
const ZOOM_MAX := 3.0
const LABEL_MAX := 190.0  # px; a longer name wraps onto the next lines
const MIN_SPAN := 0.12  # of the whole layout: the smallest piece shown across the canvas

var layout: Dictionary = {}  # room id → Vector2 0..1
var known: Dictionary = {"rooms": [], "frontier": [], "edges": []}
var names: Dictionary = {}  # room id → name
var locations: Dictionary = {}  # room id → location name
var marks: Dictionary = {}  # room id → [quest titles]
var here := ""
var selected := ""
var zoom := 1.0
var pan := Vector2.ZERO

var _drag_from := Vector2.ZERO
var _dragging := false
var _pressed := false


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE


## Screen point of a room: the known part of the layout fits the canvas (a lone room is not blown up), then the
## zoom and the pan of the view.
func point(room_id: String) -> Vector2:
	var p: Vector2 = layout.get(room_id, Vector2(0.5, 0.5))
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for r: String in known["rooms"] + known["frontier"]:
		lo = lo.min(layout.get(r, Vector2(0.5, 0.5)))
		hi = hi.max(layout.get(r, Vector2(0.5, 0.5)))
	if lo.x == INF:
		lo = Vector2.ZERO
		hi = Vector2.ONE
	var span := (hi - lo).max(Vector2(MIN_SPAN, MIN_SPAN))
	var area := size - Vector2(PAD, PAD) * 2
	var sx := area.x / span.x
	var sy := area.y / span.y
	var k := Vector2(minf(sx, sy * STRETCH), minf(sy, sx * STRETCH))  # use the wide canvas, but not too flat
	var mid := (lo + hi) / 2
	return ((p - mid) * k) * zoom + size / 2 + pan


## The room under a screen point (visited or «?»), "" if none.
func room_at(pos: Vector2) -> String:
	var best := ""
	var best_d := (R_ROOM + 8.0) * maxf(1.0, zoom)
	for r: String in known["rooms"] + known["frontier"]:
		var d := point(r).distance_to(pos)
		if d < best_d:
			best_d = d
			best = r
	return best


func set_zoom(z: float, around: Vector2) -> void:
	var nz := clampf(z, ZOOM_MIN, ZOOM_MAX)
	if is_equal_approx(nz, zoom):
		return
	pan = around - (around - size / 2 - pan) * (nz / zoom) - size / 2
	zoom = nz
	view_changed.emit(zoom, pan)
	queue_redraw()


func reset_view() -> void:
	zoom = 1.0
	pan = Vector2.ZERO
	view_changed.emit(zoom, pan)
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			set_zoom(zoom * 1.15, mb.position)
			accept_event()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			set_zoom(zoom / 1.15, mb.position)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_pressed = true
				_dragging = false
				_drag_from = mb.position
			else:
				if _pressed and not _dragging:
					var r := room_at(mb.position)
					if not r.is_empty():
						selected = r
						picked.emit(r)
						queue_redraw()
				_pressed = false
				if _dragging:
					view_changed.emit(zoom, pan)
				_dragging = false
			accept_event()
	elif event is InputEventMouseMotion and _pressed:
		var mm := event as InputEventMouseMotion
		if _dragging or mm.position.distance_to(_drag_from) > 6.0:
			_dragging = true
			pan += mm.relative
			queue_redraw()
		accept_event()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), UiTheme.BG)
	var font := UiTheme.font(UiTheme.FONT_UI, 500)
	var fs := UiTheme.SIZE_SMALL
	for e: Array in known["edges"]:
		var to_unknown: bool = (known["frontier"] as Array).has(e[0]) or (known["frontier"] as Array).has(e[1])
		draw_line(point(e[0]), point(e[1]), UiTheme.BORDER if to_unknown else UiTheme.MUTED, 2.0 if to_unknown else 3.0, true)
	for r: String in known["frontier"]:
		var p := point(r)
		draw_circle(p, R_FRONTIER, UiTheme.PANEL_RAISED)
		draw_arc(p, R_FRONTIER, 0, TAU, 24, UiTheme.BORDER, 2.0, true)
		var q := font.get_string_size("?", HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		draw_string(font, p + Vector2(-q.x / 2, q.y / 3), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTheme.MUTED)
		if r == selected:
			draw_arc(p, R_FRONTIER + 6, 0, TAU, 32, UiTheme.ACCENT_BRIGHT, 2.0, true)
	for r: String in known["rooms"]:
		var p := point(r)
		var now := r == here
		draw_circle(p, R_ROOM, UiTheme.ACCENT_BRIGHT if now else UiTheme.PANEL_RAISED)
		draw_arc(p, R_ROOM, 0, TAU, 32, UiTheme.ACCENT if not now else UiTheme.TEXT, 2.0, true)
		if r == selected:
			draw_arc(p, R_ROOM + 7, 0, TAU, 32, UiTheme.ACCENT_BRIGHT, 2.5, true)
		if marks.has(r):
			var m := p + Vector2(R_ROOM, -R_ROOM)
			draw_circle(m, 9, UiTheme.WARN)
			var ex := font.get_string_size("!", HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
			draw_string(font, m + Vector2(-ex.x / 2, ex.y / 3), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTheme.BG)
	_draw_labels(font, fs)


## Room names without overlaps: the hero's room and the picked one first, then the rest; each name goes under its
## point, or over it when that spot is taken; a name with no free spot waits for a closer zoom (or a pick).
func _draw_labels(font: Font, fs: int) -> void:
	var order: Array = (known["rooms"] as Array).duplicate()
	order.sort_custom(func(a: String, b: String) -> bool: return _rank(a) < _rank(b))
	var taken: Array[Rect2] = []
	for r: String in known["rooms"] + known["frontier"]:  # the points themselves are never covered
		taken.append(Rect2(point(r) - Vector2(R_ROOM, R_ROOM), Vector2(R_ROOM, R_ROOM) * 2))
	var placed_locations := false
	for r: String in order:
		if _rank(r) > 1 and not placed_locations:
			placed_locations = true
			_draw_locations(font, taken)
		var p := point(r)
		var lines := _wrap(font, str(names.get(r, r)), fs, LABEL_MAX)
		var w := 0.0
		for line: String in lines:
			w = maxf(w, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
		var h := lines.size() * (fs + 4.0)
		var own := Rect2(p - Vector2(R_ROOM, R_ROOM), Vector2(R_ROOM, R_ROOM) * 2)
		var spot := Rect2()
		for top: float in [p.y + R_ROOM + 3.0, p.y - R_ROOM - 3.0 - h]:
			var box := Rect2(p.x - w / 2 - 4, top, w + 8, h)
			if not taken.any(func(t: Rect2) -> bool: return t != own and t.intersects(box)):
				spot = box
				break
		if spot.size == Vector2.ZERO and _rank(r) > 1:
			continue
		if spot.size == Vector2.ZERO:
			spot = Rect2(p.x - w / 2 - 4, p.y + R_ROOM + 3.0, w + 8, h)
		taken.append(spot)
		draw_rect(spot, Color(UiTheme.BG, 0.85))
		var y := spot.position.y
		for line: String in lines:
			var lw := font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(font, Vector2(p.x - lw / 2, y + fs), line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTheme.ACCENT_BRIGHT if r == here else UiTheme.TEXT)
			y += fs + 4
	if not placed_locations:
		_draw_locations(font, taken)


## Location names over their visited rooms (under them when that spot is taken), kept clear of what is placed.
func _draw_locations(font: Font, taken: Array[Rect2]) -> void:
	var fs := UiTheme.SIZE_UI
	var groups := {}
	for r: String in known["rooms"]:
		var g: Array = groups.get(str(locations.get(r, "")), [])
		g.append(point(r))
		groups[str(locations.get(r, ""))] = g
	for loc: String in groups:
		if loc.is_empty():
			continue
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for q: Vector2 in groups[loc]:
			lo = lo.min(q)
			hi = hi.max(q)
		var w := font.get_string_size(loc, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var cx := (lo.x + hi.x) / 2
		var spot := Rect2()
		for top: float in [lo.y - R_ROOM - fs - 30.0, hi.y + R_ROOM + 44.0, lo.y - R_ROOM - fs - 60.0]:
			var box := Rect2(cx - w / 2 - 6, top, w + 12, fs + 8)
			if not taken.any(func(t: Rect2) -> bool: return t.intersects(box)):
				spot = box
				break
		if spot.size == Vector2.ZERO:
			continue
		taken.append(spot)
		draw_rect(spot, Color(UiTheme.BG, 0.85))
		draw_string(font, Vector2(cx - w / 2, spot.position.y + fs), loc, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTheme.ACCENT)


## Who gets a name first: the hero's room, the picked one, the rest.
func _rank(r: String) -> int:
	return 0 if r == here else (1 if r == selected else 2)


## The name in lines of at most `max_w` pixels, broken between words; a single long word keeps its own line.
static func _wrap(font: Font, text: String, fs: int, max_w: float) -> Array[String]:
	var lines: Array[String] = []
	var cur := ""
	for word: String in text.split(" ", false):
		var tryline := word if cur.is_empty() else cur + " " + word
		if cur.is_empty() or font.get_string_size(tryline, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= max_w:
			cur = tryline
		else:
			lines.append(cur)
			cur = word
	if not cur.is_empty():
		lines.append(cur)
	return lines

