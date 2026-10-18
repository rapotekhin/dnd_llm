extends SceneTree
## Base of live playtest scenarios for the Godot client (skill `playtest`, docs/tech/dev-tools.md).
## Runs the real game (main.tscn, autoloads) with rendering, a scenario drives it like a player and
## saves a screenshot per step. Usually started by tools/godot_playtest.py:
##   godot --path game --script res://tools/playtest/<name>.gd -- --profile=agent --out=<dir> --backend-url=...
## Refuses to run without --profile=agent: a scenario wipes the profile's saves.

const PROFILE := "agent"

var out_dir: String = ""
var _report: PackedStringArray = []
var _failed: bool = false
var _shot_n: int = 0


func _initialize() -> void:
	if LaunchArgs.value("--profile") != PROFILE:
		push_error("playtest scenarios need -- --profile=agent so the real saves stay untouched")
		quit(2)
		return
	out_dir = LaunchArgs.value("--out", "user://playtest")
	DirAccess.make_dir_recursive_absolute(out_dir)
	for f in DirAccess.get_files_at(out_dir):
		if f.ends_with(".png") or f == "report.txt":
			DirAccess.remove_absolute(out_dir.path_join(f))
	_wipe_saves()
	change_scene_to_file("res://main.tscn")
	_main.call_deferred()


## Override: the scenario. Use step() for checks; return early after a failed precondition.
func run() -> void:
	pass


func _main() -> void:
	await frames(5)
	await run()
	_report.append("RESULT %s" % ("FAIL" if _failed else "OK"))
	var f := FileAccess.open(out_dir.path_join("report.txt"), FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_report) + "\n")
	print("\n".join(_report))
	quit(1 if _failed else 0)


func _wipe_saves() -> void:
	var dir := "user://profiles/%s/saves" % PROFILE
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))


# --- helpers ---------------------------------------------------------------------


func node(autoload_name: String) -> Node:
	return root.get_node(autoload_name)


## The screen currently shown by main.gd.
func screen() -> Control:
	return current_scene.get("_screen") if current_scene != null else null


## Scenarios must not name UI classes directly: they use autoloads, which are not registered yet when
## a --script scenario compiles. Compare by the script's class_name instead.
func is_a(n: Object, cls: String) -> bool:
	return n != null and n.get_script() != null and (n.get_script() as Script).get_global_name() == cls


func screen_is(cls: String) -> bool:
	return is_a(screen(), cls)


func find_all(from: Node, cls: String) -> Array[Node]:
	var out: Array[Node] = []
	for n in from.find_children("*", "", true, false):
		if is_a(n, cls):
			out.append(n)
	return out


func frames(n: int) -> void:
	for i in n:
		await process_frame


## Polls `cond` every frame; false after `timeout_s`.
func wait_until(cond: Callable, timeout_s: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if cond.call():
			return true
		await process_frame
	return false


## Records a check; returns `ok` so a scenario can stop on a failed precondition.
func step(what: String, ok: bool, detail: String = "") -> bool:
	_report.append("%s %s%s" % ["OK  " if ok else "FAIL", what, "" if detail.is_empty() else " — " + detail])
	if not ok:
		_failed = true
	return ok


func shot(shot_name: String) -> void:
	await frames(3)
	_shot_n += 1
	var image := root.get_texture().get_image()
	var path := out_dir.path_join("%02d_%s.png" % [_shot_n, shot_name])
	if image != null:
		image.save_png(path)
	_report.append("     shot %s" % path.get_file())


## The first descendant of `from` named `node_name` (screens name their key controls).
func find(from: Node, node_name: String) -> Node:
	return from.find_child(node_name, true, false) if from != null else null


## A button whose text (as shown, translated) is `text`.
func find_button_by_text(from: Node, text: String) -> Button:
	for b in from.find_children("*", "Button", true, false):
		if (b as Button).text == text or tr((b as Button).text) == text:
			return b
	return null


func press(button: BaseButton) -> void:
	button.pressed.emit()
	await frames(2)


## Presses the control named `node_name` on the current screen; false if there is none or it is disabled.
## Screens that redraw on every change (creation) rebuild their controls, so look them up each time.
func tap(node_name: String) -> bool:
	var b := find(screen(), node_name) as BaseButton
	if b == null or b.disabled:
		return false
	await press(b)
	return true


## Ticks the check box named `node_name` on the current screen.
func tick(node_name: String) -> bool:
	var cb := find(screen(), node_name) as BaseButton
	if cb == null or cb.disabled:
		return false
	cb.button_pressed = not cb.button_pressed
	await frames(2)
	return true


## Menu → «Новая игра» → creation screen → «Случайный персонаж» (seeded by --seed) → «Начать игру».
func quick_character() -> bool:
	if not await tap("NewGameButton") or not screen_is("CreationScreen"):
		return false
	if not await tap("RandomButton"):
		return false
	return await tap("StartButton")


func key(keycode: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.physical_keycode = keycode
	ev.pressed = true
	root.push_input(ev)
	var up := ev.duplicate() as InputEventKey
	up.pressed = false
	root.push_input(up)
	await frames(2)
