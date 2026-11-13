extends "res://tools/playtest/playtest_base.gd"
## A ground with no repeat (python tools/godot_playtest.py --scenario ground_blend), v0.8.4.43.41: the Pushcha's trail as
## a meadow and the square's cobbles, each shot with `grounds.blend` off and on — the texture mixed with itself mirrored
## by a wide noise and its tone in wide patches; a swamp's still water; the drawn edges of v0.8.4.43.41 — cobbles with grass,
## still water with reeds and a cave's floor, the cave floor at its rock, a shaft's pit.

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
	var blend: Dictionary = lib["grounds"]["blend"].duplicate()
	step("the blend is in the data", float(blend.get("scale", 0.0)) > 0.0)
	for case: Array in [["pushcha-trail", ["wild"], "meadow"], ["brod-square", [], "cobbles"], ["pushcha-trail", ["swamp"], "swamp"], ["mine-flooded", [], "cave_pool"], ["mine-deep", [], "mine"]]:
		if not (case[1] as Array).is_empty():
			data["world"]["sites"]["pushcha-trail"]["tags"] = case[1]
		s.layout_cache.clear()
		s.room_id = case[0]
		node("EventBus").state_changed.emit()
		await frames(3)
		field.zoom(-20, field.size / 2.0)
		await frames(2)
		field.zoom(6, field.size / 2.0)
		for on: bool in [false, true]:
			lib["grounds"]["blend"] = blend if on else {"scale": 0.0, "macro": 0.0}
			field._ground.lay(lib, field.map)
			await frames(3)
			await shot("%s_%s" % [case[2], "on" if on else "off"])
	lib["grounds"]["blend"] = blend
	data["world"]["sites"]["pushcha-trail"]["tags"] = ["wild"]
