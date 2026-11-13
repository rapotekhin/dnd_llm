extends "res://tools/playtest/playtest_base.gd"
## Lava (python tools/godot_playtest.py --scenario lava), v0.8.4.43.32: the Pushcha's trail tagged `lava` gets a lake of
## it with its drawn crust; a cave of the pack tagged `lava` takes a hall of lava; whole and close up; lava is not walked.

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
	var trail: Dictionary = data["world"]["sites"]["pushcha-trail"]
	var was: Array = trail.get("tags", []).duplicate()
	trail["tags"] = ["rocks", "lava"]
	await _show(s, "pushcha-trail", "open")
	trail["tags"] = was
	var world := WorldView.new(data["world"])
	var cave := ""
	for id: String in data["world"]["rooms"]:
		if LayoutRules.shape_of(world, data, id) == "tunnels":
			cave = id
			break
	if not step("a cave of the pack", not cave.is_empty(), cave):
		return
	var room: Dictionary = data["world"]["rooms"][cave]
	room["tags"] = (room.get("tags", []) as Array) + ["lava"]
	await _show(s, cave, "cave")


func _show(s: GameSession, room: String, name: String) -> void:
	s.layout_cache.clear()
	s.room_id = room
	node("EventBus").state_changed.emit()
	await frames(4)
	var rows: Array = field.map["rows"]
	var lava := _first(rows, "&")
	step("%s: lava on the map" % name, lava.x >= 0)
	if lava.x < 0:
		return
	step("%s: lava is not walked" % name, not WalkRules.passable(field.map, node("Catalog").data["layouts"], lava))
	field.zoom(-20, field.size / 2.0)
	await frames(3)
	await shot(name)
	field.zoom(30, field.cell_point(lava))
	await frames(3)
	await shot(name + "_close")


func _first(rows: Array, c: String) -> Vector2i:
	for y: int in rows.size():
		var x := str(rows[y]).find(c)
		if x >= 0:
			return Vector2i(x, y)
	return Vector2i(-1, -1)
