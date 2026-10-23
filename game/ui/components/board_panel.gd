class_name BoardPanel
extends Control
## A notice board as a window of its own (roadmap v0.7.22.13, big test #30, #31): the orders on it are real quests
## of the engine (QuestGen, made by the master on this board) — each with its customer and reward; take one, or all
## that fit under the limit of taken quests. A board with nothing on it yet — «Прочитать объявления»: a turn of the
## master, who puts its orders up (`create_quest` with this `board_prop_id`).

var prop_id := ""
var _box: VBoxContainer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 300)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 90)
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	margin.add_child(col)
	var panel := PanelContainer.new()
	panel.theme_type_variation = UiTheme.SIDE
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override("separation", 10)
	scroll.add_child(_box)
	var close := Button.new()
	close.name = "CloseBoardButton"
	close.text = "BTN_CLOSE"
	close.custom_minimum_size = Vector2(0, 56)
	close.pressed.connect(func() -> void: visible = false)
	col.add_child(close)
	EventBus.state_changed.connect(_rebuild)
	EventBus.turn_finished.connect(func(_id: String, _ok: bool) -> void: _rebuild())
	visibility_changed.connect(_rebuild)


func open(prop: String) -> void:
	prop_id = prop
	visible = true
	_rebuild()


func _label(text: String, variation: String = "") -> Label:
	var l := Label.new()
	l.text = text
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not variation.is_empty():
		l.theme_type_variation = variation
	_box.add_child(l)
	return l


func _button(parent: Control, node_name: String, text: String, enabled: bool, action: Callable) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.disabled = not enabled
	b.pressed.connect(func() -> void:
		var err: String = action.call()
		if not err.is_empty():
			EventBus.message.emit(tr(err)))
	parent.add_child(b)
	return b


func _rebuild() -> void:
	if not visible or not GameState.has_session():
		return
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	var s := GameState.session
	var data := Catalog.data
	var world := GameState.world()
	var p := PropRules.find(s, s.room_id, prop_id)
	if p.is_empty():
		visible = false
		return
	var can_act := Backend.is_ready() and not GameState.is_busy() and not s.in_conversation()
	_label(str(p["name"]), UiTheme.HEADING)
	if not str(p.get("text", "")).is_empty():
		_label(str(p["text"]), UiTheme.MUTED_LABEL)
	var orders := QuestGen.offered_by(s, "board:%s:%s" % [s.room_id, prop_id])
	if orders.is_empty():
		_label(tr("BOARD_EMPTY"), UiTheme.MUTED_LABEL)
		var rb := _button(_box, "BoardRead", tr("BTN_BOARD_READ"), can_act and QuestGen.board_why_not(s, data, prop_id).is_empty(),
			func() -> String: return GameState.read_board(prop_id))
		var why := QuestGen.board_why_not(s, data, prop_id)
		rb.tooltip_text = tr(why) if not why.is_empty() else ""
		return
	var room_left := int(QuestGen.cfg(data)["max_open"]) - QuestGen.open_made(s).size()
	_label(tr("BOARD_LIMIT").format({"n": maxi(0, room_left)}), UiTheme.MUTED_LABEL)
	for qid: String in orders:
		var q := QuestRules.quest(world.world, qid)
		_box.add_child(HSeparator.new())
		_label(str(q["title"]))
		_label(str(q.get("description", "")), UiTheme.MUTED_LABEL)
		var steps: Array = q.get("steps", [])
		var cp := int(steps[-1].get("reward_cp", 0)) if not steps.is_empty() else 0
		_label(tr("BOARD_ORDER_LINE").format({"who": world.npc(str(q.get("giver", ""))).get("name", "—"), "reward": Money.format(cp)}), UiTheme.MUTED_LABEL)
		var why := QuestGen.can_take(s, data, qid)
		var tb := _button(_box, "BoardTake_" + qid, tr("BTN_BOARD_TAKE"), can_act and why.is_empty(), GameState.accept_quest.bind(qid))
		tb.tooltip_text = tr(why) if not why.is_empty() else ""
	_box.add_child(HSeparator.new())
	_button(_box, "BoardTakeAll", tr("BTN_BOARD_TAKE_ALL"), can_act and room_left > 0, func() -> String: return GameState.take_board_all(orders))
