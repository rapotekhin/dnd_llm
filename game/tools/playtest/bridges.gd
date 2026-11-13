extends "res://tools/playtest/playtest_base.gd"
## Bridges and falls (python tools/godot_playtest.py --scenario bridges), v0.8.4.43.36: the Pushcha's trail laid with the
## ford and the stream's step made likely, over games of other seeds — a bridge where the path crosses the water, its
## deck of planks walked; a waterfall of two squares where the stream goes over a cliff to the south, a band of foam not walked, its two
## ends of one picture; the whole map and close up.

var field: Control


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
	var s: GameSession = gs.session
	var data: Dictionary = node("Catalog").data
	still_sky(s)
	field = find(screen(), "Field")
	for c: Dictionary in data["layouts"]["chunks"]:
		if str(c["id"]) in ["tile_path_ford", "tile_stream_falls_a", "tile_stream_falls_b"]:
			c["weight"] = 60
	var lib: Dictionary = data["layouts"]
	var keys: Array[String] = ["open", "*"]
	var bridge := false
	var fall := false
	for game_seed: int in 24:
		s.game_seed = 1000 + game_seed
		data["world"]["sites"]["pushcha-trail"]["tags"] = [["wild", "forest"][game_seed % 2]]
		s.layout_cache.clear()
		s.room_id = "pushcha-trail"
		node("EventBus").state_changed.emit()
		await frames(3)
		var rows: Array = field.map["rows"]
		var at := _bridge_inside(rows) if not bridge else Vector2i(-1, -1)
		if at.x >= 0:
			bridge = true
			step("a bridge is walked", WalkRules.passable(field.map, lib, at), "seed %d at %s" % [s.game_seed, at])
			await _show(at, "bridge")
		var down := _fall_south(lib, keys, rows) if not fall else Vector2i(-1, -1)
		if down.x >= 0:
			fall = true
			step("a waterfall is not walked", not WalkRules.passable(field.map, lib, down), "seed %d at %s" % [s.game_seed, down])
			await _show(down, "waterfall")
		if bridge and fall:
			break
	step("a bridge inside the map", bridge)
	step("a waterfall of two squares falling south", fall)
	data["world"]["sites"]["pushcha-trail"]["tags"] = ["wild"]


func _show(at: Vector2i, name: String) -> void:
	field.zoom(-20, field.size / 2.0)
	await frames(3)
	await shot(name + "_map")
	field.zoom(30, field.cell_point(at))
	await frames(3)
	await shot(name)


## A bridge square away from the map's rim.
func _bridge_inside(rows: Array) -> Vector2i:
	for y: int in range(3, rows.size() - 3):
		var line := str(rows[y])
		for x: int in range(3, line.length() - 3):
			if line[x] == "_":
				return Vector2i(x, y)
	return Vector2i(-1, -1)


## The left end of a waterfall two squares wide falling south, away from the rim.
func _fall_south(lib: Dictionary, keys: Array[String], rows: Array) -> Vector2i:
	for y: int in range(3, rows.size() - 3):
		for x: int in range(3, str(rows[y]).length() - 3):
			var thing := LayoutGen.prop_at(lib, keys, rows, x, y)
			if str(thing["id"]) == "waterfall_left" and int(thing["turn"]) == 0:
				return Vector2i(x, y)
	return Vector2i(-1, -1)
