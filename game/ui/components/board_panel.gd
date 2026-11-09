class_name BoardPanel
extends ModalFrame
## A notice board as a window of its own (roadmap v0.7.22.13, big test #30, #31): the orders on it are real quests
## of the engine (QuestGen, made by the master on this board) — each with its customer and reward; take one, or all
## that fit under the limit of taken quests. A board with nothing on it yet — «Прочитать объявления»: a turn of the
## master, who puts its orders up (`create:quest` with this `board_prop_id`).

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


func _button(parent: Control, node_name: String, text: String, enabled: bool, action: Callable) -> Button:
	var b := UiParts.act_button(parent, node_name, text, "", action)  # v0.8.4.29.6: grey while busy too
	b.disabled = b.disabled or not enabled
	return b


func _rebuild() -> void:
	if not visible or not GameState.has_session():
		return
	clear_body()
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
		UiParts.label(_box, str(p["text"]), UiTheme.MUTED_LABEL)
	_notices(s, data, world.world)
	var orders := QuestGen.offered_by(s, "board:%s:%s" % [s.room_id, prop_id])
	var read_why := QuestGen.board_why_not(s, data, prop_id)
	if QuestGen.board_unread(s, s.room_id, prop_id) or orders.is_empty():
		UiParts.label(_box, tr("BOARD_UNREAD_HINT" if QuestGen.board_unread(s, s.room_id, prop_id) else "BOARD_EMPTY"), UiTheme.MUTED_LABEL)
		var rb := _button(_box, "BoardRead", tr("BTN_BOARD_READ"), can_act and read_why.is_empty(), func() -> String: return GameState.read_board(prop_id))
		rb.tooltip_text = tr(read_why) if not read_why.is_empty() else ""
	if orders.is_empty():
		return
	var room_left := int(QuestGen.cfg(data)["max_open"]) - QuestGen.open_made(s).size()
	UiParts.label(_box, tr("BOARD_LIMIT").format({"n": maxi(0, room_left)}), UiTheme.MUTED_LABEL)
	for qid: String in orders:
		var q := QuestRules.quest(world.world, qid)
		_box.add_child(HSeparator.new())
		UiParts.label(_box, str(q["title"]))
		UiParts.label(_box, str(q.get("description", "")), UiTheme.MUTED_LABEL)
		UiParts.label(_box, tr("BOARD_ORDER_LINE").format({"who": world.npc(str(q.get("giver", ""))).get("name", "—"), "reward": Money.format(DifficultyRules.reward(s, Catalog.data, QuestGen.reward_cp(q)))}), UiTheme.MUTED_LABEL)
		if not QuestGen.difficulty_line(data, q).is_empty():
			UiParts.label(_box, QuestGen.difficulty_line(data, q), UiTheme.MUTED_LABEL)
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
	var head := UiParts.label(_box, tr("BOARD_NOTICES"))
	head.name = "BoardNotices"
	for l: String in lines:
		UiParts.label(_box, l, UiTheme.MUTED_LABEL)
	_box.add_child(HSeparator.new())


## All orders at once: a deadly one among them asks first, as its own button does (v0.7.39.6).
func _take_all(orders: Array) -> String:
	return ConfirmBox.take_quests(self, orders, GameState.take_board_all.bind(orders))


func _take(qid: String, _q: Dictionary) -> String:
	return ConfirmBox.take_quests(self, [qid], GameState.accept_quest.bind(qid))
