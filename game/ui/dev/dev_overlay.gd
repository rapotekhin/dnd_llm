class_name DevOverlay
extends PanelContainer
## F3: FPS, master connection, the turn in flight, last round-trip times, session counters.

var _label: Label


func _ready() -> void:
	theme_type_variation = UiTheme.CARD
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 16)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_label = Label.new()
	_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_label.theme_type_variation = UiTheme.MUTED_LABEL
	add_child(_label)


func _process(_delta: float) -> void:
	if not visible:
		return
	var c := Backend.client
	var lines: PackedStringArray = [
		"FPS %d" % Engine.get_frames_per_second(),
		"backend %s %s" % [BackendClient.State.keys()[c.state], c.reason],
		"model %s · server %s" % [c.server_info.get("model", "—"), c.server_info.get("server_version", "—")],
		"turn %s" % (GameState.busy_turn if GameState.is_busy() else "idle"),
		"ms %s" % Backend.last_ms,
	]
	if GameState.has_session():
		var s := GameState.session
		lines.append("seed %d · turns %d · checks %d · chat %d" % [s.game_seed, s.turn_counter, s.check_counter, s.chat.size()])
	if not SaveManager.profile.is_empty():
		lines.append("profile %s" % SaveManager.profile)
	_label.text = "\n".join(lines)
