extends "res://tools/playtest/playtest_base.gd"
## An experiment (not a test): the maps of some rooms dumped as JSON beside a shot of the field as the game draws it.

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
	var lib: Dictionary = data["layouts"]
	var order: Array = lib["grounds"]["order"]
	var out := {}
	var wanted := OS.get_environment("MAP_ROOMS")
	var list: Array = Array(wanted.split(",")) if wanted != "" else ["brod-tavern-hall", "brod-square", "pushcha-edge"]
	for room: String in list:
		s.room_id = room
		node("EventBus").state_changed.emit()
		root.size = Vector2i(2400, 1800)
		await frames(10)
		var map: Dictionary = field.map
		var laid := LayoutGen.props_laid(lib, LayoutGen.ground_keys(lib, map), map["rows"], int(map.get("seed", 0)), map["exits"])
		var things := MapSpots.of(s, data, map).filter(func(t: Dictionary) -> bool: return t.has("body"))
		var g := LayoutGen.grounds(lib, map)
		var gn: Array = []
		for i: int in g.size():
			gn.append(str(order[g[i]]) if g[i] < order.size() else "")
		var props: Array = []
		for i: int in laid.size():
			if laid[i] is Dictionary and not (laid[i] as Dictionary).is_empty():
				props.append({"i": i, "id": str(laid[i].get("id", ""))})
		var th: Array = []
		for t: Dictionary in things:
			th.append({"body": str(t["body"]), "x": t.get("x"), "y": t.get("y")})
		out[room] = {"w": map["w"], "rows": map["rows"], "ids": map["ids"], "rooms": Array(map["rooms"]), "grounds": gn,
			"props": props, "things": th, "kind": map.get("kind"), "shape": map.get("shape")}
		var W := int(map["w"])
		var H := (map["rows"] as Array).size()
		var r: Rect2 = field.get_global_rect()
		var T := minf(32.0, minf((r.size.x - 20.0) / W, (r.size.y - 200.0) / H))
		field._tile = T
		field._follow = false
		field._own_view = true
		field._corner = Vector2(4, 4)
		field.queue_redraw()
		await frames(6)
		var img := root.get_texture().get_image()
		var k := float(img.get_width()) / root.get_visible_rect().size.x
		var c: Vector2 = field._corner
		var part := img.get_region(Rect2i(Vector2i((r.position + c) * k), Vector2i(Vector2(W, H) * T * k)))
		part.save_png(out_dir.path_join("ours_%s.png" % room))
		step("%s: rect %s, tile %s, k %s, img %s" % [room, r, T, k, img.get_size()], true)
		step(room + " dumped", true)
	var f := FileAccess.open(out_dir.path_join("maps.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
	f.close()
