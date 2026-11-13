extends "res://tools/playtest/playtest_base.gd"
## What stands at the marks, the floors and the ways out (python tools/godot_playtest.py --scenario marks_look),
## v0.8.4.43.40: the tavern's hall with its stage and counter, its kitchen and cellar of flagstones with the stairs, the
## square's stalls and well, the mine's veins, the flooded drift's water with no well, a signpost at the rim of the
## Pushcha trail; the whole map and close up at each.

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
	for room: String in ["brod-tavern-hall", "brod-tavern-cellar", "brod-tavern-kitchen", "brod-square", "mine-gallery", "mine-flooded", "pushcha-trail"]:
		s.room_id = room
		node("EventBus").state_changed.emit()
		await frames(3)
		var map: Dictionary = field.map
		var laid := LayoutGen.props_laid(lib, LayoutGen.ground_keys(lib, map), map["rows"], int(map.get("seed", 0)), map["exits"])
		var things := MapSpots.of(s, data, map).filter(func(t: Dictionary) -> bool: return t.has("body"))
		var bodies := things.map(func(t: Dictionary) -> String: return str(t["body"]))
		var exits := laid.filter(func(t: Dictionary) -> bool: return str(t["id"]) in ["signpost", "stairs_up", "stairs_down"]).map(func(t: Dictionary) -> String: return str(t["id"]))
		var grounds := LayoutGen.grounds(lib, map)
		var at := (map["ids"] as Array).find(room)
		var floor := ""
		for i: int in grounds.size():
			if (map["rooms"] as PackedInt32Array)[i] == at and str(map["rows"][i / int(map["w"])])[i % int(map["w"])] == LayoutGen.FLOOR:
				floor = str(order[grounds[i]])
				break
		step("%s: things %s, ways %s, floor %s" % [room, bodies, exits, floor], true)
		match room:
			"brod-tavern-hall":
				step("the hall has its stage", bodies.has("stage"))
			"brod-tavern-cellar":
				step("the cellar is of flagstones", floor == "flagstone")
				step("stairs up from the cellar", exits.has("stairs_up"))
			"brod-square":
				step("the square has its stalls and well", bodies.has("stall") and bodies.has("well"))
			"mine-gallery":
				step("the gallery has its vein", bodies.has("vein"))
			"mine-flooded":
				step("no well in a mine", not bodies.has("well"))
			"pushcha-trail":
				step("a signpost at the rim", exits.has("signpost"))
		field.zoom(-20, field.size / 2.0)
		await frames(3)
		await shot(room + "_map")
		var focus := Vector2i(-1, -1)
		for t: Dictionary in things:
			if str(t["body"]) in ["stage", "stall", "vein", "desk", "millstone", "standing_stone"]:
				focus = Vector2i(int(t["x"]), int(t["y"]))
				break
		if focus.x < 0:
			for i: int in laid.size():
				if str(laid[i]["id"]) in ["signpost", "stairs_up", "stairs_down"]:
					focus = Vector2i(i % int(map["w"]), i / int(map["w"]))
					break
		if focus.x >= 0:
			field.zoom(20, field.cell_point(focus))
			await frames(3)
			await shot(room)
