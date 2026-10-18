extends SceneTree
## Writes res://test/fixtures/saves/save_v<SAVE_VERSION>.json from a fresh start session with a short chat.
## Run once when SAVE_VERSION goes up (keep the old fixtures):
##   godot --headless --path game -s res://tools/make_save_fixture.gd


func _init() -> void:
	var data := SaveFormat.build(TestUtils.session_with_chat(), "0.5.0", "2026-10-18T12:00:00", 500)
	var path := "res://test/fixtures/saves/save_v%d.json" % SaveFormat.SAVE_VERSION
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	print("wrote ", path)
	quit()
