extends "res://tools/playtest/playtest_base.gd"
## Every `--preview` screen opens and draws (python tools/godot_playtest.py --scenario preview): a screenshot of each.


func run() -> void:
	var gs := node("GameState")
	var main := current_scene
	for name: String in main.call("preview_names"):
		if gs.has_session():
			gs.close_session()
			await frames(3)
		main.call("preview", name)
		await frames(8)
		var errors := screen() != null
		step("preview %s" % name, errors, str(screen().get_class()) + " " + str(screen().get_script().get_global_name()) if screen() != null else "")
		await shot(name)
