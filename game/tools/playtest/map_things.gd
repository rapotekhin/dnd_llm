extends "res://tools/playtest/playtest_base.gd"
## New things of a map (python tools/godot_playtest.py --scenario map_things), v0.8.4.43.44: a garden of farmland in its
## wattle fence on a town's square, graves on a graveyard's spots in the ruined outpost, the deep middle of a pond, the needles trap
## of the outpost's yard drawn once found, the timbers of a mine; whole and close up.

var field: Control
var s: GameSession
var data: Dictionary


func run() -> void:
	var gs := node("GameState")
	gs.instant_walk = true
	if not step("master connected", await wait_until(func() -> bool: return node("Backend").is_ready(), 30.0)):
		return
	await tap("NewGameButton")
	await tap("NextButton")
	await tap("Preset_fighter_aira")
	await press(find(screen(), "StartButton"))
	if not step("game started", await wait_until(func() -> bool: return screen_is("GameScreen") and not gs.is_busy(), 60.0)):
		return
	s = gs.session
	data = node("Catalog").data
	still_sky(s)
	field = find(screen(), "Field")
	for c: Dictionary in data["layouts"]["chunks"]:
		if str(c["id"]) in ["garden", "graves"]:
			c["weight"] = 80
	var lib: Dictionary = data["layouts"]
	var at := await _seek("brod-square", [], func(map: Dictionary) -> Vector2i: return _char(map, "f"))
	step("a fenced garden on the square", at.x >= 0)
	await _show(at, "garden")
	at = await _seek("pushcha-trail", ["shore"], func(map: Dictionary) -> Vector2i: return _char(map, "$"))
	step("a pond's deep middle", at.x >= 0)
	await _show(at, "deep_water")
	at = await _seek("outpost-yard", [], func(map: Dictionary) -> Vector2i: return _body(map, "grave"))
	step("graves in the ruined outpost", at.x >= 0)
	await _show(at, "graves")
	s.game_seed = 1
	Knows.add(s, Knows.SECRET, "outpost-yard", "needles")
	at = await _seek("outpost-yard", [], func(map: Dictionary) -> Vector2i: return _body(map, "trap"))
	step("the found trap is drawn", at.x >= 0)
	await _show(at, "trap")
	at = await _seek("mine-deep", [], func(map: Dictionary) -> Vector2i: return _body(map, "timber"))
	step("mine timbers", at.x >= 0)
	await _show(at, "timber")
	data["world"]["sites"]["pushcha-trail"]["tags"] = ["wild"]


## The first seed whose map of `room` has what `find` looks for: its square, else (-1, -1).
func _seek(room: String, tags: Array, find: Callable) -> Vector2i:
	for n: int in 24:
		s.game_seed = 3000 + n
		if not tags.is_empty():
			data["world"]["sites"]["pushcha-trail"]["tags"] = tags
		s.layout_cache.clear()
		s.layouts.erase("picks")  # what a save kept would stand for every seed
		s.room_id = room
		node("EventBus").state_changed.emit()
		await frames(3)
		var at: Vector2i = find.call(field.map)
		if at.x >= 0:
			return at
	return Vector2i(-1, -1)


func _char(map: Dictionary, c: String) -> Vector2i:
	var rows: Array = map["rows"]
	for y: int in range(2, rows.size() - 2):
		var x := str(rows[y]).find(c)
		if x >= 2:
			return Vector2i(x, y)
	return Vector2i(-1, -1)


func _body(map: Dictionary, body: String) -> Vector2i:
	var all: Array[Dictionary] = MapSpots.of(s, data, map) + MapSpots.traps(s, data, map)
	for t: Dictionary in all:
		if str(t.get("body", "")) == body:
			return Vector2i(int(t["x"]), int(t["y"]))
	return Vector2i(-1, -1)


func _show(at: Vector2i, name: String) -> void:
	if at.x < 0:
		return
	field.zoom(-20, field.size / 2.0)
	await frames(3)
	await shot(name + "_map")
	field.zoom(22, field.cell_point(at))
	await frames(3)
	await shot(name)
