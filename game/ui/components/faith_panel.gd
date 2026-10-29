class_name FaithPanel
extends Control
## The shrine window (roadmap v0.7.49), opened by «Святилище» in a room with a shrine: whose it is and its
## commandment, the hero's faith and favor, the acts (a service, a donation, the blessing, the atonement, taking the
## faith) and the vows with their gifts. Every act is GameState.faith_act: the engine checks and does it.

var _box: VBoxContainer
var frame: ModalFrame


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame = ModalFrame.new(tr("FAITH_TITLE"), 720.0)
	add_child(frame)
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.close_requested.connect(func() -> void: visible = false)
	frame.close_x.name = "CloseFaithButton"
	_box = frame.body
	visibility_changed.connect(_rebuild)
	EventBus.state_changed.connect(func() -> void:
		if visible:
			_rebuild())


func open() -> void:
	visible = true
	_rebuild()


func _label(parent: Control, text: String, variation: String = "") -> Label:
	var l := Label.new()
	l.text = text
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not variation.is_empty():
		l.theme_type_variation = variation
	parent.add_child(l)
	return l


## A button of an act: disabled with the reason in its tooltip.
func _act(parent: Control, node_name: String, text: String, what: String, why: String, arg: String = "", tip: String = "") -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.disabled = not why.is_empty() or GameState.is_busy()
	b.tooltip_text = tr(why) if not why.is_empty() else tip
	b.pressed.connect(func() -> void:
		var err := GameState.faith_act(what, arg)
		if not err.is_empty():
			EventBus.message.emit(tr(err)))
	parent.add_child(b)
	return b


func _rebuild() -> void:
	if not visible or not GameState.has_session():
		return
	frame.clear_body()
	var s := GameState.session
	var data := Catalog.data
	var c := s.character
	var sh := FaithRules.shrine(s, data, s.room_id)
	if sh.is_empty():
		_label(_box, tr("FAITH_NO_SHRINE"), UiTheme.MUTED_LABEL)
		return
	var gid := str(sh["god"])
	var g := FaithRules.god(s, data, gid)
	var cfg := FaithRules.cfg(data)
	_label(_box, "%s — %s" % [str(sh.get("name", "")).capitalize(), FaithRules.god_name(s, data, gid, true)]).name = "FaithShrine"
	_label(_box, tr("FAITH_GOD_TEXT").format({"text": g.get("text", ""), "domains": ", ".join(g.get("domains", [])), "law": g.get("commandment", "")}), UiTheme.MUTED_LABEL)
	var mine := FaithRules.hero_god(c)
	var st := FaithRules.step_of(c, data, gid)
	var standing := tr("FAITH_STANDING").format({"step": st.get("name", ""), "favor": FaithRules.favor(c, gid)})
	if mine.is_empty():
		standing = tr("FAITH_NO_GOD") + " " + standing
	elif mine != gid:
		standing = tr("FAITH_OTHER_GOD").format({"god": FaithRules.god_name(s, data, mine)}) + " " + standing
	_label(_box, standing).name = "FaithStanding"
	var fest := FaithRules.festival(s, data, gid)
	if not fest.is_empty():
		_label(_box, tr("FAITH_FESTIVAL").format({"name": fest}), UiTheme.MUTED_LABEL)

	var acts := HFlowContainer.new()
	acts.name = "FaithActs"
	acts.add_theme_constant_override("h_separation", 8)
	acts.add_theme_constant_override("v_separation", 8)
	_box.add_child(acts)
	_act(acts, "FaithService", tr("BTN_FAITH_SERVICE").format({"min": TimeRules.span(int(cfg["service"]["minutes"]))}), "service",
		FaithRules.service_why(s, data), "", tr("FAITH_SERVICE_TIP").format({"favor": int(cfg["service"]["favor"]), "days": int(cfg["service"]["every_days"])}))
	_act(acts, "FaithDonate", tr("BTN_FAITH_DONATE").format({"money": Money.format(int(cfg["donation"]["cost_cp"]))}), "donate",
		FaithRules.donate_why(s, data), "", tr("FAITH_DONATE_TIP").format({"favor": int(cfg["donation"]["favor"])}))
	if gid == mine:
		_act(acts, "FaithBless", tr("BTN_FAITH_BLESS"), "bless", FaithRules.bless_why(s, data), "", tr("FAITH_BLESS_TIP"))
	if not FaithRules.broken(c, data).is_empty():
		_act(acts, "FaithAtone", tr("BTN_FAITH_ATONE").format({"money": Money.format(FaithRules.atone_cost(c, data))}), "atone",
			FaithRules.atone_why(s, data), "", ", ".join(FaithRules.broken(c, data)))
	if gid != mine:
		var cost := FaithRules.convert_cost(c, data)
		_act(acts, "FaithConvert", (tr("BTN_FAITH_TAKE") if mine.is_empty() else tr("BTN_FAITH_CONVERT").format({"money": Money.format(cost)})).format({"god": g.get("name", gid)}),
			"convert", FaithRules.convert_why(s, data), "", tr("FAITH_CONVERT_TIP"))
	var steps: Array[String] = []
	for x: Dictionary in cfg["steps"]:
		if int(x["at"]) > 0:
			var gives: Array[String] = []
			if int(x.get("discount_pct", 0)) > 0:
				gives.append(tr("FAITH_GIVES_DISCOUNT").format({"pct": int(x["discount_pct"])}))
			if bool(x.get("blessing", false)):
				gives.append(tr("FAITH_GIVES_BLESSING"))
			if bool(x.get("shelter", false)):
				gives.append(tr("FAITH_GIVES_SHELTER"))
			steps.append("%d — %s: %s" % [int(x["at"]), x["name"], ", ".join(gives)])
	_label(_box, tr("FAITH_STEPS").format({"steps": "; ".join(steps)}), UiTheme.MUTED_LABEL)

	_label(_box, tr("FAITH_VOWS").format({"n": int(cfg["vows_max"])}))
	for id: String in cfg["vows"]:
		var v: Dictionary = cfg["vows"][id]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		_box.add_child(row)
		_label(row, "%s — %s" % [v["name"], v.get("text", "")])
		var have: Array = FaithRules.vows(c).filter(func(x: Dictionary) -> bool: return str(x["id"]) == id)
		if not have.is_empty():
			var state := tr("FAITH_VOW_BROKEN") if int((have[0] as Dictionary).get("broken", -1)) >= 0 else tr("FAITH_VOW_KEPT")
			var l := _label(row, state, UiTheme.MUTED_LABEL)
			l.size_flags_horizontal = Control.SIZE_FILL
			l.autowrap_mode = TextServer.AUTOWRAP_OFF
			l.custom_minimum_size = Vector2(120, 0)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.name = "FaithVowState_" + id
			continue
		_act(row, "FaithVow_" + id, tr("BTN_FAITH_VOW"), "vow", FaithRules.vow_why(s, data, id), id)
