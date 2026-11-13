extends "res://tools/playtest/playtest_base.gd"
## The look of the things of a map (python tools/godot_playtest.py --scenario things_look), v0.8.4.43.37: the Pushcha's
## trail as a forest and as hills — trees of three kinds, a grove where four trees stand together, a ridge or a pair of
## boulders, their shades merged; close up at each; the squares of a group still not walked.

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
	var keys: Array[String] = ["open", "*"]
	for want: String in ["grove", "boulder_ridge", "boulder_pair", "tree_pair"]:
		var found := false
		for game_seed: int in 16:
			s.game_seed = 2000 + game_seed
			data["world"]["sites"]["pushcha-trail"]["tags"] = [["forest", "hills", "wild"][game_seed % 3]]
			s.layout_cache.clear()
			s.room_id = "pushcha-trail"
			node("EventBus").state_changed.emit()
			await frames(3)
			var rows: Array = field.map["rows"]
			var laid := LayoutGen.props_laid(lib, keys, rows, int(field.map.get("seed", 0)))
			var w := str(rows[0]).length()
			for i: int in laid.size():
				var at := Vector2i(i % w, i / w)
				if LayoutGen.prop_base(lib, str(laid[i]["id"])) != want or at.x < 3 or at.y < 3 or at.x > w - 4 or at.y > rows.size() - 4:
					continue
				found = true
				step("%s: its squares not walked" % want, not WalkRules.passable(field.map, lib, at) and not WalkRules.passable(field.map, lib, at + Vector2i(1, 0)) or int(laid[i]["turn"]) % 2 == 1, "seed %d at %s" % [s.game_seed, at])
				field.zoom(-20, field.size / 2.0)
				await frames(2)
				field.zoom(24, field.cell_point(at))
				await frames(3)
				await shot(want)
				break
			if found:
				break
		step("a %s on a map" % want, found)
	data["world"]["sites"]["pushcha-trail"]["tags"] = ["wild"]
