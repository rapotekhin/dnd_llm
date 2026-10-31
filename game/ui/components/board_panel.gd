class_name BoardPanel
extends ModalFrame
## A notice board as a window of its own (roadmap v0.7.22.13, big test #30, #31): the orders on it are real quests
## of the engine (QuestGen, made by the master on this board) — each with its customer and reward; take one, or all
## that fit under the limit of taken quests. A board with nothing on it yet — «Прочитать объявления»: a turn of the
## master, who puts its orders up (`create_quest` with this `board_prop_id`).

const SCENE := "res://ui/components/board_panel.tscn"

var prop_id := ""
var _box: VBoxContainer


func _ready() -> void:
	super()
	close_requested.connect(func() -> void: visible = false)
	close_x.name = "CloseBoardButton"
	_box = body
	EventBus.state_changed.connect(_rebuild)
	EventBus.turn_finished.connect(func(_id: String, _ok: bool) -> void: _rebuild())
	visibility_changed.connect(_rebuild)


func open(prop: String) -> void:
	prop_id = prop
	visible = true
	GameState.read_notices()  # v0.7.47: the notices are read as the board is
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
	title.text = str(p["name"])
	if not str(p.get("text", "")).is_empty():
		_label(str(p["text"]), UiTheme.MUTED_LABEL)
	_notices(s, data, world.world)
	var orders := QuestGen.offered_by(s, "board:%s:%s" % [s.room_id, prop_id])
	var read_why := QuestGen.board_why_not(s, data, prop_id)
	if QuestGen.board_unread(s, s.room_id, prop_id) or orders.is_empty():
		_label(tr("BOARD_UNREAD_HINT" if QuestGen.board_unread(s, s.room_id, prop_id) else "BOARD_EMPTY"), UiTheme.MUTED_LABEL)
		var rb := _button(_box, "BoardRead", tr("BTN_BOARD_READ"), can_act and read_why.is_empty(), func() -> String: return GameState.read_board(prop_id))
		rb.tooltip_text = tr(read_why) if not read_why.is_empty() else ""
	if orders.is_empty():
		return
	var room_left := int(QuestGen.cfg(data)["max_open"]) - QuestGen.open_made(s).size()
	_label(tr("BOARD_LIMIT").format({"n": maxi(0, room_left)}), UiTheme.MUTED_LABEL)
	for qid: String in orders:
		var q := QuestRules.quest(world.world, qid)
		_box.add_child(HSeparator.new())
		_label(str(q["title"]))
		_label(str(q.get("description", "")), UiTheme.MUTED_LABEL)
		_label(tr("BOARD_ORDER_LINE").format({"who": world.npc(str(q.get("giver", ""))).get("name", "—"), "reward": Money.format(QuestGen.reward_cp(q))}), UiTheme.MUTED_LABEL)
		if not QuestGen.difficulty_line(data, q).is_empty():
			_label(QuestGen.difficulty_line(data, q), UiTheme.MUTED_LABEL)
		var why := QuestGen.can_take(s, data, qid)
		var tb := _button(_box, "BoardTake_" + qid, tr("BTN_BOARD_TAKE"), can_act and why.is_empty(), func() -> String: return _take(qid, q))
		tb.tooltip_text = tr(why) if not why.is_empty() else ""
	_box.add_child(HSeparator.new())
	_button(_box, "BoardTakeAll", tr("BTN_BOARD_TAKE_ALL"), can_act and room_left > 0, func() -> String: return _take_all(orders))


## Notices beside the orders (v0.7.47): the place's rumours put up as notices and the festivals ahead.
func _notices(s: GameSession, data: Dictionary, world: Dictionary) -> void:
	var lines: Array[String] = []
	for r: Dictionary in RumorRules.notices(s, data):
		lines.append("• " + str(r["text"]).left(1).to_upper() + str(r["text"]).substr(1))
	if CalendarRules.on(world):
		for e: Dictionary in CalendarRules.upcoming(s, data, world):
			lines.append("★ " + CalendarRules.line(world, e, true))
	if lines.is_empty():
		return
	var head := _label(tr("BOARD_NOTICES"))
	head.name = "BoardNotices"
	for l: String in lines:
		_label(l, UiTheme.MUTED_LABEL)
	_box.add_child(HSeparator.new())


## The near-impossible asks «Точно?» first (v0.7.39.6).
## All orders at once: a deadly one among them asks first, as its own button does (v0.7.39.6).
func _take_all(orders: Array) -> String:
	var deadly := orders.filter(func(qid: Variant) -> bool: return QuestGen.warns(Catalog.data, QuestRules.quest(Catalog.data["world"], str(qid))))
	if deadly.is_empty():
		return GameState.take_board_all(orders)
	ConfirmBox.ask(self, tr("CONFIRM_QUEST_DEADLY_TITLE").format({"title": QuestRules.quest(Catalog.data["world"], str(deadly[0]))["title"]}),
		tr("CONFIRM_QUEST_DEADLY"), tr("BTN_QUEST_TAKE_DEADLY"), func() -> void:
			var err := GameState.take_board_all(orders)
			if not err.is_empty():
				EventBus.message.emit(tr(err)))
	return ""


func _take(qid: String, q: Dictionary) -> String:
	if not QuestGen.warns(Catalog.data, q):
		return GameState.accept_quest(qid)
	ConfirmBox.ask(self, tr("CONFIRM_QUEST_DEADLY_TITLE").format({"title": q["title"]}), tr("CONFIRM_QUEST_DEADLY"), tr("BTN_QUEST_TAKE_DEADLY"),
		func() -> void:
			var err := GameState.accept_quest(qid)
			if not err.is_empty():
				EventBus.message.emit(tr(err)))
	return ""
