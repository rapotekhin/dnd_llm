extends "res://tools/playtest/playtest_base.gd"
## Open places of open chunks (python tools/godot_playtest.py --scenario open_tiles), v0.8.4.43.27: the Pushcha's trail
## (wild) laid of glades, groves, high ground and streams, the whole map and close up; the same place as a forest and as
## hills — high ground with its cliffs; a cliff is not walked, high ground is.

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
	for kind: String in ["wild", "forest", "hills", "swamp"]:
		data["world"]["sites"]["pushcha-trail"]["tags"] = [kind]
		s.layout_cache.clear()
		s.room_id = "pushcha-trail"
		node("EventBus").state_changed.emit()
		await frames(4)
		var rows: Array = field.map["rows"]
		var text := "".join(rows)
		step("%s: laid of chunks" % kind, LayoutRules.kind_of(WorldView.new(data["world"]), data, s.room_id) == kind)
		if kind == "hills":
			step("hills: high ground and its cliffs", text.contains(LayoutGen.HIGH) and text.contains(LayoutGen.CLIFF))
			var cliff := _first(rows, LayoutGen.CLIFF)
			var high := _first(rows, LayoutGen.HIGH)
			step("a cliff is not walked, high ground is", not WalkRules.passable(field.map, data["layouts"], cliff)
				and WalkRules.passable(field.map, data["layouts"], high), "%s %s" % [cliff, high])
		field.zoom(-20, field.size / 2.0)
		await frames(3)
		await shot(kind)
		field.zoom(6, field.size / 2.0)
		await frames(3)
		await shot(kind + "_close")
		if kind == "hills":  # right at a cliff: its drawn face and the shadow at its foot
			field.zoom(-20, field.size / 2.0)
			var at := _cliff_mid(rows)
			field.zoom(30, field.cell_point(at))
			await frames(3)
			await shot("cliff")
	data["world"]["sites"]["pushcha-trail"]["tags"] = ["wild"]


func _first(rows: Array, c: String) -> Vector2i:
	for y: int in rows.size():
		var x := str(rows[y]).find(c)
		if x >= 0:
			return Vector2i(x, y)
	return Vector2i(-1, -1)


## A cliff square with lowland beside it, near the map's middle.
func _cliff_mid(rows: Array) -> Vector2i:
	var mid := Vector2i(str(rows[0]).length() / 2, rows.size() / 2)
	var best := Vector2i(-1, -1)
	for y: int in range(1, rows.size() - 1):
		for x: int in range(1, str(rows[y]).length() - 1):
			if str(rows[y])[x] == LayoutGen.CLIFF and str(rows[y])[x + 1] == LayoutGen.FLOOR 					and (best.x < 0 or WalkRules.distance(Vector2i(x, y), mid) < WalkRules.distance(best, mid)):
				best = Vector2i(x, y)
	return best
