class_name MapCanvas
extends Control
## The map scheme (roadmap v0.7.6; nested boxes — v0.7.22.24, the author): a known location is a frame with its name,
## its known sites are boxes inside it, the rooms are points in their site; the open exits out of the visited rooms
## lead to «?»; the hero's room, quest marks. The wheel zooms around the cursor, a drag pans, a click picks a room —
## or a site, clicked in its box off the rooms («site:<id>»). Positions come from WorldMap.boxes (0..1); the view
## (zoom, pan) is kept by the owner between rebuilds.

signal picked(room_id: String)
signal view_changed(zoom: float, pan: Vector2)

const R_ROOM := 11.0
const R_FRONTIER := 8.0
const PAD := 40.0
const ZOOM_MIN := 0.2
const ZOOM_MAX := 4.0
const MIN_SPAN := 0.12  # of the whole layout: the smallest piece shown across the canvas

var layout: Dictionary = {}  # room id → Vector2 0..1
var site_boxes: Dictionary = {}  # site id → Rect2 0..1 (the known ones)
var loc_boxes: Dictionary = {}  # location id → Rect2 0..1 (the known ones)
var site_names: Dictionary = {}
var loc_names: Dictionary = {}
var single: Dictionary = {}  # site id → true when it is one room: its name is the room's
var site_of: Dictionary = {}  # room id → site id
var known: Dictionary = {"rooms": [], "frontier": [], "edges": []}
var names: Dictionary = {}  # room id → its own name (without the site's)
var unit := 0.03  # one map unit of WorldMap in 0..1
var focus := Rect2()  # the hero's location: the view at zoom 1 fits it, so its names read; the wheel shows the rest
var marks: Dictionary = {}  # room id → [quest titles]
var here := ""
var selected := ""
var zoom := 1.0
var pan := Vector2.ZERO

var _drawn := {}  # room id → where it was drawn (a far «?» sits at the canvas edge)
var _drag_from := Vector2.ZERO
var _dragging := false
var _pressed := false


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE


## The known part of the layout: the frames of the known locations and the visited rooms (a «?» far off does not
## shrink the map — it is drawn at the edge, `_edge_point`).
func _bounds() -> Rect2:
	if focus.has_area():
		return focus.grow(focus.size.length() * 0.04)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for loc: String in loc_boxes:
		lo = lo.min((loc_boxes[loc] as Rect2).position)
		hi = hi.max((loc_boxes[loc] as Rect2).end)
	for r: String in known["rooms"]:
		lo = lo.min(layout.get(r, Vector2(0.5, 0.5)))
		hi = hi.max(layout.get(r, Vector2(0.5, 0.5)))
	if lo.x == INF:
		return Rect2(Vector2.ZERO, Vector2.ONE)
	return Rect2(lo, (hi - lo).max(Vector2(MIN_SPAN, MIN_SPAN)))


## The scale of the layout on the canvas before the zoom: the known part fits.
func _scale() -> float:
	var b := _bounds()
	var area := size - Vector2(PAD, PAD) * 2
	return minf(area.x / b.size.x, area.y / b.size.y)


## A layout point on the screen.
func tx(v: Vector2) -> Vector2:
	var b := _bounds()
	return (v - b.get_center()) * _scale() * zoom + size / 2 + pan


func tx_rect(r: Rect2) -> Rect2:
	var a := tx(r.position)
	return Rect2(a, tx(r.end) - a)


## Screen point of a room.
func point(room_id: String) -> Vector2:
	return tx(layout.get(room_id, Vector2(0.5, 0.5)))


## Where a «?» is drawn: its spot, or — off the canvas — where the line to it from `from` meets the canvas edge.
func _edge_point(r: String, from: String) -> Vector2:
	var p := point(r)
	var area := Rect2(Vector2(PAD, PAD) / 2, size - Vector2(PAD, PAD))
	if area.has_point(p) or from.is_empty():
		return p
	var a := point(from)
	var t := 1.0
	for axis in 2:
		var d := p[axis] - a[axis]
		if absf(d) > 0.001:
			var lim := area.position[axis] if d < 0 else area.end[axis]
			t = minf(t, (lim - a[axis]) / d)
	return a + (p - a) * clampf(t, 0.0, 1.0)


## The room under a screen point (visited or «?»), "" if none.
func room_at(pos: Vector2) -> String:
	var best := ""
	var best_d := (R_ROOM + 8.0) * maxf(1.0, zoom)
	for r: String in known["rooms"] + known["frontier"]:
		var d := (_drawn.get(r, point(r)) as Vector2).distance_to(pos)
		if d < best_d:
			best_d = d
			best = r
	return best


## The known site whose box is under a screen point, "" if none.
func site_at(pos: Vector2) -> String:
	for sid: String in site_boxes:
		if tx_rect(site_boxes[sid]).has_point(pos):
			return sid
	return ""


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
					if r.is_empty() and not site_at(mb.position).is_empty():
						r = "site:" + site_at(mb.position)
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


## A map unit in pixels now: the fonts and the points follow it, so a name fits its box at any zoom.
func _pxu() -> float:
	return unit * _scale() * zoom


func _fs(units: float, k: float, lo: int, hi: int) -> int:
	return clampi(int(units * _pxu() * k), lo, hi)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), UiTheme.BG)
	var font := UiTheme.font(UiTheme.FONT_UI, 500)
	var fs := _fs(WorldMap.ROOM_CELL.y, 0.3, 11, UiTheme.SIZE_SMALL)
	var rr := clampf(WorldMap.ROOM_CELL.y * _pxu() * 0.16, 5.0, R_ROOM)
	var here_site := str(site_of.get(here, ""))
	for loc: String in loc_boxes:  # the frames of the locations
		var r := tx_rect(loc_boxes[loc])
		draw_rect(r, Color(UiTheme.PANEL, 0.55))
		draw_rect(r, Color(UiTheme.ACCENT, 0.55), false, 2.0)
		_title(font, _fs(WorldMap.TITLE_H, 0.9, 12, UiTheme.SIZE_UI), str(loc_names.get(loc, loc)), r, UiTheme.ACCENT)
	for sid: String in site_boxes:  # the boxes of the sites
		var r := tx_rect(site_boxes[sid])
		var lit := sid == here_site or selected == "site:" + sid
		draw_rect(r, UiTheme.PANEL_RAISED)
		draw_rect(r, UiTheme.ACCENT_BRIGHT if lit else UiTheme.BORDER, false, 2.0 if lit else 1.5)
		_title(font, _fs(WorldMap.TITLE_H, 0.75, 11, UiTheme.SIZE_SMALL), str(site_names.get(sid, sid)), r, UiTheme.ACCENT_BRIGHT if sid == here_site else UiTheme.TEXT)
	_drawn = {}
	for r: String in known["rooms"]:
		_drawn[r] = point(r)
	for e: Array in known["edges"]:  # a «?» goes where its first line puts it
		for i in 2:
			if (known["frontier"] as Array).has(e[i]) and not _drawn.has(e[i]):
				_drawn[e[i]] = _edge_point(e[i], e[1 - i])
	for e: Array in known["edges"]:
		var to_unknown: bool = (known["frontier"] as Array).has(e[0]) or (known["frontier"] as Array).has(e[1])
		draw_line(_drawn.get(e[0], point(e[0])), _drawn.get(e[1], point(e[1])), UiTheme.BORDER if to_unknown else UiTheme.MUTED, 1.5 if to_unknown else 2.5, true)
	for r: String in known["frontier"]:
		var p: Vector2 = _drawn.get(r, point(r))
		draw_circle(p, rr * 0.75, UiTheme.PANEL_RAISED)
		draw_arc(p, rr * 0.75, 0, TAU, 24, UiTheme.BORDER, 2.0, true)
		var q := font.get_string_size("?", HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		draw_string(font, p + Vector2(-q.x / 2, q.y / 3), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTheme.MUTED)
		if r == selected:
			draw_arc(p, rr + 5, 0, TAU, 32, UiTheme.ACCENT_BRIGHT, 2.0, true)
	for r: String in known["rooms"]:
		var p := point(r)
		var now := r == here
		draw_circle(p, rr, UiTheme.ACCENT_BRIGHT if now else UiTheme.PANEL)
		draw_arc(p, rr, 0, TAU, 32, UiTheme.ACCENT if not now else UiTheme.TEXT, 2.0, true)
		if r == selected:
			draw_arc(p, rr + 5, 0, TAU, 32, UiTheme.ACCENT_BRIGHT, 2.5, true)
		if marks.has(r):
			var m := p + Vector2(rr, -rr)
			draw_circle(m, 8, UiTheme.WARN)
			var ex := font.get_string_size("!", HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
			draw_string(font, m + Vector2(-ex.x / 2, ex.y / 3), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTheme.BG)
	_draw_labels(font, fs, rr)


## A box's name in its top band, cut with «…» to the box's width.
func _title(font: Font, fs: int, text: String, box: Rect2, color: Color) -> void:
	var w := box.size.x - 12
	if w < 24:
		return
	var band := WorldMap.TITLE_H * _pxu()
	var line := _fit(font, text, fs, w)
	draw_string(font, box.position + Vector2(6, maxf(fs + 2.0, band * 0.5 + fs * 0.45)), line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)


## Room names under their points, in the width of a room's cell (two lines at most); a site of one room shows only
## the site's name. Too small to read — only the hero's room and the picked one.
func _draw_labels(font: Font, fs: int, rr: float) -> void:
	var cell := WorldMap.ROOM_CELL.x * _pxu() - 6
	for r: String in known["rooms"]:
		if single.get(str(site_of.get(r, "")), false):
			continue
		if cell < 50 and r != here and r != selected:
			continue
		var p := point(r)
		var lines := _wrap(font, str(names.get(r, r)), fs, maxf(cell, 60.0))
		var y := p.y + rr + 3
		for i in mini(lines.size(), 2):
			var line := lines[i] if i == 0 or lines.size() <= 2 else _fit(font, lines[i] + "…", fs, maxf(cell, 60.0))
			var lw := font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(font, Vector2(p.x - lw / 2, y + fs), line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTheme.ACCENT_BRIGHT if r == here else UiTheme.TEXT)
			y += fs + 3


## The text cut with «…» to `max_w` pixels.
static func _fit(font: Font, text: String, fs: int, max_w: float) -> String:
	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= max_w:
		return text
	var t := text
	while t.length() > 1 and font.get_string_size(t + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > max_w:
		t = t.left(t.length() - 1)
	return t + "…"


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
