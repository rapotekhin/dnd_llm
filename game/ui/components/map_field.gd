class_name MapField
extends Control
## The field of the one screen (v0.8.1): a map of squares, plain tiles from code, tokens that walk. The wheel zooms around
## the cursor, a drag moves the view; a small room fits whole, a big one follows the hero until the view is dragged away.
## The field knows nothing of rooms and rules: it says which square was clicked and which were reached. In a fight it also
## shows the bodies, where the hero can walk, the zones and the area under the mouse (v0.8.4); FightUi fills them.

signal cell_clicked(cell: Vector2i)
signal cell_hovered(cell: Vector2i)
signal cell_right(cell: Vector2i)  ## the right button without a drag
signal stepped(cell: Vector2i)  ## the hero reached a square of the path
signal arrived  ## the hero reached the end of the path

const MIN_TILE := 10.0
const MAX_TILE := 76.0  ## the closest view on a small field; a bigger one comes to CLOSE_CELLS
const CLOSE_CELLS := 8.0  ## the closest view: this many squares across the field's shorter side (v0.8.4.43.21)
const BASE_TILE := 38.0
const SPEED := 7.0  ## squares a second
const DRAG_FROM := 6.0  ## pixels: less is a click
const ZOOM_STEP := 1.15
const LABEL_FROM := 20.0  ## a tile under this has no names on it
const FONT_SIZE := 15
const FIGHT_SPEED := 14.0  ## squares a second

var map: Dictionary = {}
var lib: Dictionary = {}
var names: Dictionary = {}  ## the name of a way out by the room it leads to
var hero_mark := ""  ## the hero's letter; empty — no hero on this map (the author's preview)
var hero_face := ""  ## the hero's face (PortraitRules.of, v0.8.4.43.5.2); "" — its letter
var pointed := Vector2i(-1, -1)  ## a token pointed at from its portrait (v0.8.4.43.8): a bright ring and its name
var clicks := true  ## false while a conversation holds the field
var things: Array[Dictionary] = []  ## those who stand on the map and what lies on it: MapSpots.of (v0.8.2)
var labels := false  ## every name is written while the key is held
var reach: Dictionary = {}  ## the squares the picked shot or spell gets to: tinted, with a rim
var instant := false  ## a walk ends at once: the playtests' game time does not come from frames
var dim := false  ## what is out of view is dimmed (the author's preview has none)
var fit_most := BASE_TILE  ## the biggest tile a whole map is fitted at (the build screen comes closer, v0.8.4.42)
var now: Dictionary = {}  ## the squares seen right now: SightRules (v0.8.3)
var cones: Dictionary = {}  ## the squares under watch while sneaking
var fighters: Array[Dictionary] = []  ## the bodies of a fight: {"id", "mark", "portrait", "name", "colour", "span", "x", "y", "hp", "most", "out", "now", "dim", "gear", "states"}
var anim_lib: Dictionary = {}  ## data/anims.json: the art of a weapon, a shield and a state over a token (v0.8.4.23)
var routes: Dictionary = {}  ## where the hero can walk this turn: FightGrid.reach
var way: Array[Vector2i] = []  ## the path under the mouse
var blast: Dictionary = {}  ## the squares of the area under the mouse
var lit: Dictionary = {}  ## the squares of a choice (a shove's side, a jump)
var over: Dictionary = {}  ## what a fight changed on the map: {square: Color}
var zones: Array[Dictionary] = []:  ## SpellEffects.zone_view
	set(v):
		zones = v
		_flicker = v.any(func(z: Dictionary) -> bool: return bool(z.get("look", {}).get("moves", false)))
		if _flicker:
			set_process(true)
var _flicker := false  ## a zone whose look moves: the map is drawn each frame (v0.8.4.30)
var _clock := 0.0

var _tile := BASE_TILE
var _corner := Vector2.ZERO  ## where the map's corner is on the field
var _follow := true
var _own_view := false  ## the player zoomed or dragged: no resize takes that back, until another map
var _in_fight := false  ## a fight's close view: only the player moves it then
var _pos := Vector2.ZERO  ## the hero, in squares
var _path: Array[Vector2i] = []
var _trail: Array[Vector2] = []
var _tokens: Array[Dictionary] = []  ## those who walk with the hero: {"ref", "mark", "portrait", "name", "pos"}
var _names: Array[Dictionary] = []  ## the names of this drawing, laid last so none covers another: {"at", "text", "first"}
var laid_names: Array[Rect2] = []  ## where the last drawing wrote its names (a playtest checks that none covers another)
var _exit_boxes: Array[Rect2] = []  ## the ways out's labels of this drawing: a name does not go over them
var _hover := Vector2i(-1, -1)
var _pressed := false
var _dragged := false
var _press_at := Vector2.ZERO
var _moves: Dictionary = {}  ## a body's squares still to walk, by id
var _body_at: Dictionary = {}  ## where a body is drawn now, by id
var _ground := MapGround.new()  ## the squares' grounds and things on a dual grid, under everything the field draws


func _ready() -> void:
	var back := ColorRect.new()  # the field's own ground: a child behind the parent, so the map's ground lies over it
	back.color = UiTheme.BG
	back.show_behind_parent = true
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(back)
	add_child(_ground)
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(_on_resized)
	set_process(false)


func show_map(m: Dictionary, world_lib: Dictionary) -> void:
	var same: bool = not map.is_empty() and map["id"] == m["id"]
	map = m
	lib = world_lib
	_ground.lay(lib, map)
	if not same:
		_own_view = false
		if _in_fight:
			close_up()
		else:
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
		_follow = _may_follow()
		_seat(walkers)
	else:
		for i: int in walkers.size():
			_tokens[i].merge({"ref": walkers[i]["ref"], "mark": walkers[i]["mark"], "portrait": str(walkers[i].get("portrait", "")), "name": walkers[i]["name"]}, true)
	_aim()
	queue_redraw()


func _seat(walkers: Array[Dictionary]) -> void:
	_tokens.clear()
	var spots := WalkRules.around(map, lib, Vector2i(_pos), walkers.size()) if not map.is_empty() else ([] as Array[Vector2i])
	for i: int in walkers.size():
		var at := Vector2(spots[i]) if i < spots.size() else _pos
		_tokens.append({"ref": walkers[i]["ref"], "mark": walkers[i]["mark"], "portrait": str(walkers[i].get("portrait", "")), "name": walkers[i]["name"], "pos": at})


func walking() -> bool:
	return not _path.is_empty()


func walk(steps: Array[Vector2i]) -> void:
	_path = steps.duplicate()
	if instant and not _path.is_empty():
		while not _path.is_empty():
			var cell: Vector2i = _path.pop_front()
			_pos = Vector2(cell)
			stepped.emit(cell)
		_aim()
		queue_redraw()
		arrived.emit()
		return
	_follow = _may_follow()
	set_process(not _path.is_empty() or _flicker)
	if _path.is_empty():
		arrived.emit()


func stop() -> void:
	_path.clear()
	set_process(not _moves.is_empty() or _flicker)


## The bodies walk the squares of what happened (FightField.take_moves), one by one on their own.
func play(moves: Array) -> void:
	if instant:
		_moves.clear()
		return
	for m: Dictionary in moves:
		var left: Array = _moves.get(str(m["who"]), [])
		for tag: Variant in m["path"]:
			left.append(Vector2(FightGrid.y_x(str(tag))))
		_moves[str(m["who"])] = left
	set_process(not _moves.is_empty() or not _path.is_empty() or _flicker)


func _walk_bodies(delta: float) -> void:
	for id: String in _moves.keys():
		var left: Array = _moves[id]
		var pos: Vector2 = _body_at.get(id, left[0])
		pos = pos.move_toward(left[0], FIGHT_SPEED * delta)
		_body_at[id] = pos
		if pos == left[0]:
			left.pop_front()
		if left.is_empty():
			_moves.erase(id)
	queue_redraw()


func _process(delta: float) -> void:
	_clock += delta
	if _flicker:
		queue_redraw()
	if not _moves.is_empty():
		_walk_bodies(delta)
	if _path.is_empty():
		set_process(not _moves.is_empty() or _flicker)
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
			set_process(not _moves.is_empty() or _flicker)
			arrived.emit()


func _on_resized() -> void:
	if map.is_empty():
		return
	if _own_view:
		_aim()
		_hold()
	elif _in_fight:
		_aim()
	else:
		_fit()


## In a fight the view the player set stays, wherever the hero goes (v0.8.4.3, the author).
func _may_follow() -> bool:
	return not (_in_fight and _own_view)


## The tile the whole map fits at, never bigger than the base one; then the view goes to the hero.
func _fit() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var whole := minf(size.x / float(map["w"]), size.y / float(map["h"]))
	_tile = clampf(whole, MIN_TILE, fit_most)
	_follow = true
	_aim()


## Close on the hero: a fight is read by squares, not by the whole map.
func close_up() -> void:
	_in_fight = true
	if _own_view:
		return
	_tile = BASE_TILE
	_follow = true
	_aim()
	queue_redraw()


## The fight is over: the whole map again, unless the player has set a view of its own.
func release() -> void:
	_in_fight = false
	if not _own_view and not map.is_empty():
		_fit()
		queue_redraw()


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
	_tile = clampf(_tile * pow(ZOOM_STEP, steps), MIN_TILE, most_tile())
	_corner = around_point - at * _tile
	_follow = false
	_own_view = true
	_hold()
	queue_redraw()


func tile() -> float:
	return _tile


## The biggest tile the wheel comes to: CLOSE_CELLS squares across the shorter side, never under MAX_TILE.
func most_tile() -> float:
	return maxf(MAX_TILE, minf(size.x, size.y) / CLOSE_CELLS)


## The ground's pictures are the sharp set now (v0.8.4.43.21).
func sharp() -> bool:
	return _ground.sharp()


func corner() -> Vector2:
	return _corner


func hero_cell() -> Vector2i:
	return Vector2i(_pos.round())


## The point of a square's middle, on the field.
func cell_point(cell: Vector2i) -> Vector2:
	return _corner + (Vector2(cell) + Vector2(0.5, 0.5)) * _tile


## Who or what is on a square: its ref, "" — nothing.
func ref_at(cell: Vector2i) -> String:
	for f: Dictionary in fighters:
		if FightGrid.body_at(Vector2i(int(f["x"]), int(f["y"])), int(f["span"])).has(cell):
			return str(f["ref"])
	for tok: Dictionary in _tokens:
		if Vector2i((tok["pos"] as Vector2).round()) == cell:
			return str(tok["ref"])
	for th: Dictionary in things:
		if Vector2i(int(th["x"]), int(th["y"])) == cell:
			return str(th["ref"])
	return ""


## The square of a ref, (-1, -1) — not on the map.
func cell_of(ref: String) -> Vector2i:
	for f: Dictionary in fighters:
		if str(f["ref"]) == ref:
			return Vector2i(int(f["x"]), int(f["y"]))
	for tok: Dictionary in _tokens:
		if str(tok["ref"]) == ref:
			return Vector2i((tok["pos"] as Vector2).round())
	for th: Dictionary in things:
		if str(th["ref"]) == ref:
			return Vector2i(int(th["x"]), int(th["y"]))
	return Vector2i(-1, -1)


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
			_own_view = true
			_corner += m.relative
			_hold()
			queue_redraw()
		var cell := cell_at(m.position)
		if cell != _hover:
			_hover = cell
			cell_hovered.emit(cell)
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
	elif not _dragged and b.button_index == MOUSE_BUTTON_RIGHT and not map.is_empty():
		cell_right.emit(cell_at(b.position))


func _draw() -> void:
	_names.clear()
	_exit_boxes.clear()
	if map.is_empty():
		_ground.visible = false
		return
	var t := _tile
	_ground.visible = true
	_ground.position = _corner
	_ground.size = Vector2(int(map["w"]), int(map["h"])) * t
	_ground.detail(t)
	_ground.light(dim, now, cones, 0.45)
	var rows: Array[String] = map["rows"]
	var first := Vector2i((-_corner / t).floor()).max(Vector2i.ZERO)
	var last := Vector2i(((size - _corner) / t).ceil()).min(Vector2i(int(map["w"]), int(map["h"])))
	var squares := _in_fight and t >= LABEL_FROM  # the squares are counted in a fight only: out of it the ground is whole
	for y: int in range(first.y, last.y):
		for x: int in range(first.x, last.x):
			var c: String = rows[y][x]
			if c == LayoutGen.BLANK:
				continue
			var at := _corner + Vector2(x, y) * t
			if c == "^":  # a hazard seen on its square
				draw_rect(Rect2(at, Vector2(t, t)).grow(-t * 0.12), Color(UiTheme.TILES["^"], 0.55))
			elif c == "w":  # a window: glass across the wall
				var across := y > 0 and rows[y - 1][x] in [LayoutGen.WALL, "w"]
				var glass := Rect2(at + Vector2(t * 0.38, t * 0.1), Vector2(t * 0.24, t * 0.8)) if across else Rect2(at + Vector2(t * 0.1, t * 0.38), Vector2(t * 0.8, t * 0.24))
				draw_rect(glass, UiTheme.TILES["w"])
			if squares and c != LayoutGen.WALL:
				draw_rect(Rect2(at, Vector2(t, t)), Color(0, 0, 0, 0.14), false, 1.0)
	_draw_fight_squares(t)
	if clicks and _hover.x >= 0 and _hover.y >= 0 and _hover.x < int(map["w"]) and _hover.y < int(map["h"]):
		draw_rect(Rect2(_corner + Vector2(_hover) * t, Vector2(t, t)), UiTheme.ACCENT_BRIGHT, false, 1.5)
	for e: Dictionary in map["exits"]:
		draw_rect(Rect2(_corner + Vector2(int(e["x"]), int(e["y"])) * t, Vector2(t, t)), UiTheme.ACCENT)
	_draw_path(t)
	for e: Dictionary in map["exits"]:
		_exit_label(e, t)
	for th: Dictionary in things:
		_thing(th)
	for tok: Dictionary in _tokens:
		_token(tok["pos"], str(tok["mark"]), str(tok["name"]), UiTheme.OK, 0.34, str(tok.get("portrait", "")))
	if not hero_mark.is_empty():
		_token(_pos, hero_mark, "", UiTheme.ACCENT_BRIGHT, 0.4, hero_face)
	for f: Dictionary in fighters:
		_fighter(f)
	_lay_names()


## The zones under the bodies, where the hero can walk, the area and the path under the mouse.
func _draw_fight_squares(t: float) -> void:
	for at: Variant in over:
		_tint(at, over[at], t)
	for z: Dictionary in zones:
		var tint := Color(UiTheme.BAD if bool(z["hurts"]) else UiTheme.WARN, 0.26)
		var tile := str(z.get("tile", ""))
		if UiTheme.TILES.has(tile):  # a puddle in its liquid's colour (v0.8.4.28.2), as the oil was before
			for at: Vector2i in z["cells"]:
				_tint(at, UiTheme.TILES[tile], t)
			if not bool(z["hurts"]):
				continue
		for at: Vector2i in z["cells"]:
			_tint(at, tint, t)
	for z: Dictionary in zones:  # the sprite of a surface over its tint (v0.8.4.30)
		var look: Dictionary = z.get("look", {})
		if not look.is_empty():
			for at: Vector2i in z["cells"]:
				SurfaceArt.draw(self, Rect2(_corner + Vector2(at) * t, Vector2(t, t)), look, _clock, at)
	for at: Variant in routes:
		_tint(at, Color(UiTheme.ACCENT, 0.16), t)
	for at: Variant in reach:
		_tint(at, Color(UiTheme.ACCENT_BRIGHT, 0.08), t)
		_rim(at, t)
	for at: Variant in lit:
		_tint(at, Color(UiTheme.ACCENT_BRIGHT, 0.45), t)
	for at: Variant in blast:
		_tint(at, Color(UiTheme.BAD, 0.42), t)
	var from := Vector2(way[0]) if not way.is_empty() else Vector2.ZERO
	for cell: Vector2i in way:
		draw_line(_corner + (from + Vector2(0.5, 0.5)) * t, _corner + (Vector2(cell) + Vector2(0.5, 0.5)) * t, UiTheme.ACCENT_BRIGHT, maxf(2.0, t * 0.08))
		from = Vector2(cell)


## The edge of `reach` on the sides of `at` that look out of it.
func _rim(at: Vector2i, t: float) -> void:
	var box := Rect2(_corner + Vector2(at) * t, Vector2(t, t))
	var ends := [[Vector2i.UP, box.position, box.position + Vector2(t, 0)], [Vector2i.RIGHT, box.position + Vector2(t, 0), box.end],
		[Vector2i.DOWN, box.end, box.position + Vector2(0, t)], [Vector2i.LEFT, box.position + Vector2(0, t), box.position]]
	for side: Array in ends:
		if not reach.has(at + (side[0] as Vector2i)):
			draw_line(side[1], side[2], Color(UiTheme.ACCENT_BRIGHT, 0.6), 1.5)


func _tint(at: Vector2i, tint: Color, t: float) -> void:
	draw_rect(Rect2(_corner + Vector2(at) * t, Vector2(t, t)), tint)


## A body of a fight: round, as wide as its squares, with its HP bar; the one whose turn it is has a double ring.
func _fighter(f: Dictionary) -> void:
	var id := str(f["id"])
	var cell := Vector2(int(f["x"]), int(f["y"]))
	var pos: Vector2 = _body_at.get(id, cell) if _moves.has(id) else cell
	_body_at[id] = pos
	var span := int(f["span"])
	var t := _tile
	var mid := _corner + (pos + Vector2(span, span) / 2.0) * t
	var r := t * span * 0.42
	if bool(f.get("shares", false)) and _crowded(f):  # a swarm in another's square: small, in its corner
		r *= 0.55
		mid += Vector2(t, -t) * span * 0.24
	var states: Array = f.get("states", [])
	var colour: Color = UiTheme.MUTED if bool(f["out"]) else f["colour"]
	if bool(f["dim"]):
		colour = Color(colour, 0.5)
	if states.has("invisible"):
		colour = Color(colour, 0.35)
	if states.has("flying"):  # a shadow on the ground, the body above it
		draw_set_transform(mid + Vector2(0, r * 0.55), 0.0, Vector2(1.0, 0.4))
		draw_circle(Vector2.ZERO, r * 0.8, Color(0, 0, 0, 0.3))
		draw_set_transform(Vector2.ZERO)
		mid.y -= r * 0.35
	if bool(f["now"]):
		draw_arc(mid, r + maxf(3.0, t * 0.1), 0.0, TAU, 40, UiTheme.ACCENT_BRIGHT, maxf(1.5, t * 0.05), true)
	if Vector2i(cell) == pointed:
		_ring(mid, r)
	var flat := states.has("prone") or states.has("down") or states.has("dead")
	draw_set_transform(mid, 0.0, Vector2(1.0, 0.6 if flat else 1.0))  # one who lies is a flattened token
	draw_circle(Vector2.ZERO, r, Color(UiTheme.PANEL, colour.a))
	var shade := Color(0.55, 0.55, 0.55, colour.a) if bool(f["out"]) else Color(1, 1, 1, colour.a)
	var drawn := t >= LABEL_FROM and Portrait.face(self, str(f.get("portrait", "")), Vector2.ZERO, r, shade)
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, colour, maxf(1.5, t * 0.08), true)
	draw_set_transform(Vector2.ZERO)
	_gear(f, mid, r)
	_states(states, mid, r)
	if bool(f["out"]):
		draw_line(mid - Vector2(r, r) * 0.7, mid + Vector2(r, r) * 0.7, UiTheme.MUTED, maxf(1.5, t * 0.06))
		if states.has("dead"):
			draw_line(mid + Vector2(-r, r) * 0.7, mid + Vector2(r, -r) * 0.7, UiTheme.MUTED, maxf(1.5, t * 0.06))
	elif int(f["most"]) > 0:
		var w := r * 1.8
		var share := clampf(float(f["hp"]) / float(f["most"]), 0.0, 1.0)
		var bar := Rect2(mid + Vector2(-w / 2.0, r + 2.0), Vector2(w, maxf(3.0, t * 0.1)))
		draw_rect(bar, UiTheme.BG)
		draw_rect(Rect2(bar.position, Vector2(w * share, bar.size.y)), UiTheme.hp_color(share))
	if t >= LABEL_FROM:
		var mark := str(f["mark"])
		if not drawn:
			var font := get_theme_default_font()
			var size_px := int(r * 0.9 if mark.length() > 1 else r)
			var w2 := font.get_string_size(mark, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
			draw_string(font, mid + Vector2(-w2 / 2.0, r * 0.38), mark, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, colour)
		elif mark.length() > 1 and mark.right(1).is_valid_int():  # «В2» of the numbered ones: the number over the face
			_tag(mid + Vector2(r * 0.62, -r * 0.62), mark.substr(1), colour)
		if labels or Vector2i(cell) == _hover or Vector2i(cell) == pointed:
			_name(mid + Vector2(0.0, r + 22.0), str(f["name"]), Vector2i(cell) == _hover or Vector2i(cell) == pointed)


## What is in the hands (v0.8.4.23): a shield as a stick on the left, the weapon's sprite on the right — the row's texture, else
## a stub of its length and head. Empty hands and a beast's jaws show nothing: they are seen only while they strike.
func _gear(f: Dictionary, mid: Vector2, r: float) -> void:
	var g: Dictionary = f.get("gear", {})
	if g.is_empty() or bool(f["out"]):
		return
	if bool(g.get("shield", false)):
		var box := Rect2(mid + Vector2(-r * 1.25, -r * 0.6), Vector2(r * 0.32, r * 1.2))
		if not _texture(str(anim_lib.get("sprites", {}).get("shield", {}).get("texture", "")), box):
			draw_rect(box, Color(str(anim_lib.get("palette", {}).get("shield", "#9a7448"))))
			draw_rect(box, Color(0, 0, 0, 0.6), false, 1.0)
	if not str(g.get("sprite", "")).is_empty():
		AnimArt.weapon(self, anim_lib, str(g["sprite"]), mid + Vector2(r * 0.85, r * 0.45), Vector2(0.45, -1.0).angle(), _tile)


## The lasting states over a token: a row's texture, else a stub (the dim of one hidden is the token's own colour).
func _states(states: Array, mid: Vector2, r: float) -> void:
	var kinds: Dictionary = anim_lib.get("kinds", {})
	var w := maxf(1.5, _tile * 0.05)
	for st: Variant in states:
		if _texture(str(kinds.get(str(st), {}).get("texture", "")), Rect2(mid - Vector2(r, r), Vector2(r, r) * 2.0)):
			continue
		match str(st):
			"invisible":
				for i in 8:
					draw_arc(mid, r * 1.12, i * TAU / 8.0, i * TAU / 8.0 + TAU / 16.0, 4, Color(UiTheme.TEXT, 0.7), w, true)
			"grappled":
				for i in 3:
					var x := (i - 1) * r * 0.55
					draw_line(mid + Vector2(x - r * 0.3, -r * 0.7), mid + Vector2(x + r * 0.3, r * 0.7), Color(UiTheme.WARN, 0.85), w)
			"concentrating":
				draw_arc(mid + Vector2(0, -r * 1.25), r * 0.22, 0.0, TAU, 16, UiTheme.ACCENT_BRIGHT, w, true)
			"dodging":
				for i in 12:
					draw_arc(mid, r * 1.2, i * TAU / 12.0, i * TAU / 12.0 + TAU / 30.0, 3, UiTheme.OK, w, true)
			"raging":
				draw_arc(mid, r * 1.12, 0.0, TAU, 40, Color(UiTheme.BAD, 0.9), w * 1.6, true)


## Draws an author's texture into `box`; false when the row has none (the stub is drawn).
func _texture(path: String, box: Rect2) -> bool:
	var tex := AnimArt.texture(path)
	if tex == null:
		return false
	draw_texture_rect(tex, box, false)
	return true


## A person is a round token, a beast a smaller one, a thing a square. The name shows under the cursor or while the key is held.
func _thing(th: Dictionary) -> void:
	var cell := Vector2i(int(th["x"]), int(th["y"]))
	var name_on := labels or cell == _hover or cell == pointed
	var label := str(th["name"]) if name_on else ""
	match str(th["kind"]):
		"npc":
			var a := int(th["attitude"])
			_token(Vector2(cell), str(th["mark"]), label, UiTheme.BAD if a <= -2 else UiTheme.OK if a >= 2 else UiTheme.TEXT, 0.38, str(th.get("portrait", "")))
		"creature":
			_token(Vector2(cell), str(th["mark"]), label, UiTheme.WARN, 0.32, str(th.get("portrait", "")))
		"foe":
			_token(Vector2(cell), str(th["mark"]), label, UiTheme.BAD, 0.36, str(th.get("portrait", "")))
		"trap":
			var mid := cell_point(cell)
			var half := _tile * 0.28
			draw_line(mid - Vector2(half, half), mid + Vector2(half, half), UiTheme.BAD, maxf(2.0, _tile * 0.08))
			draw_line(mid + Vector2(-half, half), mid + Vector2(half, -half), UiTheme.BAD, maxf(2.0, _tile * 0.08))
			if not label.is_empty():
				_name(mid + Vector2(0.0, half + 16.0), label, cell == _hover)
		_:
			var mid := cell_point(cell)
			var half := _tile * 0.24
			var colour := UiTheme.ACCENT if str(th["kind"]) == "prop" else UiTheme.BAD if str(th["kind"]) == "body" else UiTheme.MUTED
			draw_rect(Rect2(mid - Vector2(half, half), Vector2(half, half) * 2.0), Color(UiTheme.PANEL, 0.9))
			draw_rect(Rect2(mid - Vector2(half, half), Vector2(half, half) * 2.0), colour, false, maxf(1.5, _tile * 0.06))
			if not label.is_empty():
				_name(mid + Vector2(0.0, half + 16.0), label, cell == _hover)


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
	_exit_boxes.append(box)
	draw_rect(box, Color(UiTheme.BG, 0.88))
	draw_string(font, Vector2(box.position.x + 6.0, box.position.y + 16.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, UiTheme.ACCENT_BRIGHT)


## A round token: its face in the ring (PortraitRules), else its letter; its name under it while hovered or the key is held.
func _token(pos: Vector2, mark: String, label: String, colour: Color, part: float, face := "") -> void:
	var t := _tile
	var mid := _corner + (pos + Vector2(0.5, 0.5)) * t
	var r := t * part
	draw_circle(mid, r, UiTheme.PANEL)
	var drawn := t >= LABEL_FROM and Portrait.face(self, face, mid, r)
	draw_arc(mid, r, 0.0, TAU, 32, colour, maxf(1.5, t * 0.07), true)
	if Vector2i(pos.round()) == pointed:
		_ring(mid, r)
	if t < LABEL_FROM:
		return
	if not drawn:
		var font := get_theme_default_font()
		var size_px := int(r)
		var w := font.get_string_size(mark, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
		draw_string(font, mid + Vector2(-w / 2.0, r * 0.38), mark, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, colour)
	if not label.is_empty():
		_name(mid + Vector2(0.0, r + 16.0), label, Vector2i(pos.round()) in [_hover, pointed])


## A name to write under a token at `at` (its baseline's middle); `first` — the hovered one, laid first and always.
func _name(at: Vector2, text: String, first := false) -> void:
	_names.append({"at": at, "text": text, "first": first})


## The names of this drawing so that none covers another or a way out's label (v0.8.4.43.5.2, the author: «имена не
## наезжают»): the hovered one first where it belongs, each other at its place or a line or two lower, and one with no
## room left unwritten — a crowd under the key shows those it can.
func _lay_names() -> void:
	var font := get_theme_default_font()
	var fs := FONT_SIZE - 2
	var line := float(fs) + 3.0
	var laid: Array[Rect2] = []
	laid_names = laid
	var order := _names.filter(func(n: Dictionary) -> bool: return bool(n["first"]))
	order.append_array(_names.filter(func(n: Dictionary) -> bool: return not bool(n["first"])))
	for n: Dictionary in order:
		var text := str(n["text"])
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var at: Vector2 = n["at"]
		var free := false
		for k in 3:
			var box := Rect2(at.x - w / 2.0 - 2.0, at.y - fs + k * line, w + 4.0, line)
			if bool(n["first"]) or not (laid + _exit_boxes).any(func(o: Rect2) -> bool: return o.intersects(box)):
				at.y += k * line
				laid.append(box)
				free = true
				break
		if not free:
			continue
		draw_string_outline(font, at - Vector2(w / 2.0, 0.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, UiTheme.BG)
		draw_string(font, at - Vector2(w / 2.0, 0.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTheme.TEXT)
	_names.clear()


## The bright ring of a token pointed at from its portrait.
func _ring(mid: Vector2, r: float) -> void:
	draw_arc(mid, r + maxf(5.0, _tile * 0.16), 0.0, TAU, 40, UiTheme.ACCENT_BRIGHT, maxf(2.5, _tile * 0.08), true)


## A small number on a token's corner (a numbered foe whose face hides its letter).
func _tag(at: Vector2, text: String, colour: Color) -> void:
	var font := get_theme_default_font()
	var fs := maxi(10, int(_tile * 0.28))
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_circle(at, fs * 0.62, UiTheme.BG)
	draw_string(font, at + Vector2(-w / 2.0, fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, colour)


## Another body stands in the square of `f`.
func _crowded(f: Dictionary) -> bool:
	return fighters.any(func(o: Dictionary) -> bool: return str(o["id"]) != str(f["id"]) and int(o["x"]) == int(f["x"]) and int(o["y"]) == int(f["y"]))
