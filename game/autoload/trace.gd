extends Node
## The full trace of a play session (v0.7.1, for playtests): one JSON-lines file per game in
## <profile>/traces/<created_at>_<seed>.jsonl — a loaded save continues its file. Every line: {ts (unix ms),
## day, clock, room, mode, ev, ...}. Events: session (start / load / close), click (any button: node name, text,
## screen), input (a submitted line edit), nav (screen), chat (every chat entry as is), combat (engine lines),
## state (a digest whenever it changes: room, time, HP, coins, XP, level, mode, quests, inventory, conditions),
## turn (started / finished), rpc (every JSON-RPC message to and from the backend, snapshots included), toast.
## The backend writes the model side (prompts, tool calls) to llm_server/var/traces; tools/trace_report.py joins
## both. Never holds the token (it is only in the connection header).

var path := ""
var _file: FileAccess
var _last_digest := ""
var _screen := ""


## Off under the unit tests: their sessions must not land among the player's traces.
var enabled: bool = not " ".join(OS.get_cmdline_args()).contains("GdUnit")


func _ready() -> void:
	EventBus.session_started.connect(_on_session_started)
	EventBus.session_closed.connect(func() -> void:
		_write({"ev": "session", "what": "close"})
		_close())
	EventBus.chat_appended.connect(func(e: Dictionary) -> void: _write({"ev": "chat", "entry": e}))
	EventBus.navigate.connect(func(screen: String, args: Dictionary) -> void:
		_screen = screen
		_write({"ev": "nav", "screen": screen, "args": args}))
	EventBus.combat_lines.connect(func(lines: Array[String]) -> void: _write({"ev": "combat", "lines": lines}))
	EventBus.state_changed.connect(_on_state_changed)
	EventBus.turn_started.connect(func(id: String) -> void: _write({"ev": "turn", "what": "started", "turn_id": id}))
	EventBus.turn_finished.connect(func(id: String, ok: bool) -> void: _write({"ev": "turn", "what": "finished", "turn_id": id, "ok": ok}))
	EventBus.message.connect(func(text: String) -> void: _write({"ev": "toast", "text": text}))
	get_tree().node_added.connect(_hook)


## Every JSON-RPC message (Backend wires each new client's traffic here). ">" sent, "<" received.
func record_rpc(direction: String, text: String) -> void:
	var msg: Variant = JSON.parse_string(text)
	_write({"ev": "rpc", "dir": direction, "msg": msg if msg != null else text})


func _on_session_started() -> void:
	var s: GameSession = GameState.session
	if s == null or not enabled:
		return
	var name := "%s_%d" % [s.created_at.replace(":", "-").replace("T", "_"), s.game_seed]
	var p := SaveManager.path_in_profile("traces/%s.jsonl" % name)
	if p != path:
		_close()
		path = p
		DirAccess.make_dir_recursive_absolute(p.get_base_dir())
		var existed := FileAccess.file_exists(p)
		_file = FileAccess.open(p, FileAccess.READ_WRITE if existed else FileAccess.WRITE)
		if _file != null:
			_file.seek_end()
	_last_digest = ""
	_screen = "game"  # main.gd opens the game screen on session_started itself, not through navigate
	_write({"ev": "session", "what": "start" if s.turn_counter == 0 else "load", "version": str(ProjectSettings.get_setting("application/config/version")),
		"world": s.world_id, "seed": s.game_seed, "character": {"name": s.character.get("name", ""), "race": s.character.get("race_name", ""),
		"class": s.character.get("class_name", ""), "level": s.character.get("level", 1)}, "settings": s.settings})
	_on_state_changed()


func _digest(s: GameSession) -> Dictionary:
	var c := s.character
	return {"room": s.room_id, "day": s.day, "minute": s.minute, "mode": s.mode, "npc": s.npc_id, "hp": c.get("hp", 0),
		"max_hp": c.get("max_hp", 0), "gold_cp": c.get("gold_cp", 0), "xp": c.get("xp", 0), "level": c.get("level", 1),
		"conditions": c.get("conditions", []), "quests": s.quests_active, "done": s.quests_done, "inventory": c.get("inventory", {}),
		"sneaking": s.sneaking, "combat": {"round": s.combat.get("round", 0), "outcome": s.combat.get("outcome", "")} if CombatRules.active(s) else {}}


func _on_state_changed() -> void:
	if GameState.session == null:
		return
	var d := _digest(GameState.session)
	var text := JSON.stringify(d)
	if text == _last_digest:
		return
	_last_digest = text
	_write({"ev": "state", "state": d})


## Buttons and line edits anywhere in the UI are recorded as they are pressed (no per-screen code). A click is
## written on button_down: `pressed` handlers are connected by the screens before the node enters the tree, so
## ours would run after them and the click would land in the trace after its own consequences.
func _hook(node: Node) -> void:
	if node is BaseButton:
		var b := node as BaseButton
		b.button_down.connect(func() -> void:
			if b.disabled:
				return
			var text := str(b.get("text")) if "text" in b else ""
			_write({"ev": "click", "node": str(b.name), "text": tr(text), "screen": _screen_of(b), "pressed": (not b.button_pressed) if b.toggle_mode else null}))
	elif node is LineEdit:
		var l := node as LineEdit
		l.text_submitted.connect(func(t: String) -> void: _write({"ev": "input", "node": str(l.name), "text": t, "screen": _screen_of(l)}))


## The screen or overlay a control belongs to: the nearest ancestor with a class_name (GameScreen, TheftPanel…).
func _screen_of(n: Node) -> String:
	var p := n.get_parent()
	while p != null:
		var sc: Script = p.get_script()
		if sc != null and not sc.get_global_name().is_empty():
			return str(sc.get_global_name())
		p = p.get_parent()
	return _screen


func _write(e: Dictionary) -> void:
	if _file == null:
		return
	var s: GameSession = GameState.session
	var line := {"ts": int(Time.get_unix_time_from_system() * 1000.0)}
	if s != null:
		line.merge({"day": s.day, "clock": TimeRules.clock(s), "room": s.room_id, "mode": s.mode}, true)
	line.merge(e, true)
	_file.store_line(JSON.stringify(line))
	_file.flush()


func _close() -> void:
	if _file != null:
		_file.close()
	_file = null
	path = ""
