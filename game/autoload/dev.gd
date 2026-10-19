extends Node
## Debug tools (docs/tech/godot-client.md «Отладка»): console (~), F3 overlay, F12 bug snapshot. Debug builds or `--dev`.

const MESSAGES_KEPT := 50

var enabled: bool = false
var overlay_on: bool = false

var _layer: CanvasLayer
var _console: DevConsole
var _overlay: DevOverlay
var _messages: PackedStringArray = []


func _ready() -> void:
	enabled = OS.is_debug_build() or LaunchArgs.has("--dev")
	if not enabled:
		return
	_layer = CanvasLayer.new()
	_layer.layer = 100
	add_child(_layer)
	var root_ui := Control.new()
	root_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_ui.theme = UiTheme.build()
	_layer.add_child(root_ui)
	root_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay = DevOverlay.new()
	_overlay.visible = false
	root_ui.add_child(_overlay)
	_console = DevConsole.new()
	root_ui.add_child(_console)
	EventBus.message.connect(_keep_message)


func _input(event: InputEvent) -> void:
	if not enabled or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match (event as InputEventKey).physical_keycode:
		KEY_QUOTELEFT:
			_console.toggle()
		KEY_F3:
			overlay_on = not overlay_on
			_overlay.visible = overlay_on
		KEY_F12:
			EventBus.message.emit(tr("DEV_SNAPSHOT").format({"path": ProjectSettings.globalize_path(snapshot())}))
		_:
			return
	get_viewport().set_input_as_handled()


func _keep_message(text: String) -> void:
	_messages.append(text)
	if _messages.size() > MESSAGES_KEPT:
		_messages = _messages.slice(_messages.size() - MESSAGES_KEPT)


# --- console commands ---------------------------------------------------------


## Runs one console line and returns its output.
func run(line: String) -> String:
	var parts := line.strip_edges().split(" ", false)
	if parts.is_empty():
		return ""
	var args := parts.slice(1)
	match parts[0]:
		"help":
			return "help · backend · reconnect · say <text> · retry · cancel · save <slot> · load <slot> · seed · snapshot · clear
" 				+ "мир: room [id] · rooms · quests · items [поиск] · npc <id|имя> · state"
		"backend":
			var c := Backend.client
			return "%s %s reason=%s server=%s last_ms=%s" % [BackendClient.State.keys()[c.state], Backend.config.describe(),
				c.reason, c.server_info, Backend.last_ms]
		"reconnect":
			Backend.reconnect()
			return "reconnecting"
		"say":
			return "sent" if GameState.submit(" ".join(args)) else "not sent (no session, busy or offline)"
		"retry":
			GameState.retry()
			return "retrying" if GameState.is_busy() else "nothing to retry"
		"cancel":
			GameState.cancel_turn()
			return "cancel requested"
		"save":
			return "saved" if GameState.save_to(_slot(args)) else "save failed"
		"load":
			var err := GameState.load_from(_slot(args))
			return "loaded" if err.is_empty() else err
		"seed":
			return str(GameState.session.game_seed) if GameState.has_session() else "no session"
		"snapshot":
			return ProjectSettings.globalize_path(snapshot())
		"clear":
			_console.clear()
			return ""
		"room", "rooms", "quests", "items", "npc", "state":
			if not GameState.has_session():
				return "no session"
			return _world_report(parts[0], " ".join(args))
	return "unknown command: %s (help)" % parts[0]


## The world inspection commands (WorldReport): the pack's data and what this game already knows about it.
func _world_report(cmd: String, arg: String) -> String:
	var s: GameSession = GameState.session
	match cmd:
		"room":
			return WorldReport.room(s, Catalog.data, arg if not arg.is_empty() else s.room_id)
		"rooms":
			return WorldReport.rooms(s, Catalog.data)
		"quests":
			return WorldReport.quests(s, Catalog.data)
		"items":
			return WorldReport.items(s, Catalog.data, arg)
		"npc":
			return WorldReport.npc(s, Catalog.data, arg) if not arg.is_empty() else "npc <id или часть имени>"
	return WorldReport.state(s)


func _slot(args: PackedStringArray) -> String:
	if args.is_empty():
		return "slot_1"
	return args[0] if args[0].begins_with("slot_") or args[0] == SaveManager.AUTOSAVE else "slot_" + args[0]


# --- bug snapshot (F12) ---------------------------------------------------------


## <profile>/bugs/<time>/: save, screenshot, protocol log tail, recent messages, the Godot log. No token inside.
func snapshot() -> String:
	var dir := SaveManager.path_in_profile("bugs/" + Time.get_datetime_string_from_system().replace(":", "-"))
	DirAccess.make_dir_recursive_absolute(dir)
	if GameState.has_session():
		_write(dir + "/save.json", JSON.stringify(SaveManager.build_save(GameState.session), "\t"))
	_write(dir + "/protocol.jsonl", "\n".join(Backend.protocol_log.recent))
	_write(dir + "/messages.txt", "\n".join(_messages))
	_write(dir + "/backend.txt", run("backend"))
	var image := get_viewport().get_texture().get_image()
	if image != null:
		image.save_png(dir + "/screenshot.png")
	var log_path := "user://logs/godot.log"
	if FileAccess.file_exists(log_path):
		DirAccess.copy_absolute(log_path, dir + "/godot.log")
	return dir


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(text)
