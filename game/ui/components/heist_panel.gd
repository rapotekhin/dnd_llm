class_name HeistPanel
extends Control
## The jobs window (roadmap v0.7.33): the hero's criminal jobs in progress — the target, the hours, the victim, the
## loot; the preparations with their chance (each once a day) and the act itself. Every act is GameState.heist_act:
## the engine decides.

var _box: VBoxContainer
var frame: ModalFrame


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame = ModalFrame.make(tr("HEIST_TITLE"), 720.0)
	add_child(frame)
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.close_requested.connect(func() -> void: visible = false)
	frame.close_x.name = "CloseHeistButton"
	_box = frame.body
	EventBus.state_changed.connect(_rebuild)
	visibility_changed.connect(_rebuild)


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


func _act(parent: Control, node_name: String, text: String, why: String, what: String, id: String, arg: String = "") -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.disabled = not why.is_empty() or GameState.is_busy()
	b.tooltip_text = tr(why) if not why.is_empty() else ""
	b.size_flags_horizontal = Control.SIZE_SHRINK_END
	b.pressed.connect(func() -> void:
		var err := GameState.heist_act(what, id, arg)
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
	var list := HeistRules.followed(s, data)  # v0.7.39.3: done jobs stay while the loot is unsold or the cut owed
	if list.is_empty():
		_label(_box, tr("HEIST_NONE_ACTIVE"), UiTheme.MUTED_LABEL)
		return
	for id: String in list:
		var d := HeistRules.def(s, data, id)
		var k := HeistRules.kind(data, str(d["kind"]))
		if _box.get_child_count() > 0:
			_box.add_child(HSeparator.new())
		_label(_box, "«%s» — %s" % [d["name"], k["name"]]).add_theme_color_override("font_color", UiTheme.ACCENT)
		if not HeistRules.victim_name(s, data, id).is_empty():
			_label(_box, tr("HEIST_VICTIM").format({"name": HeistRules.victim_name(s, data, id)}), UiTheme.MUTED_LABEL)
		var n := 0
		for p: Dictionary in HeistRules.path(s, data, id):  # v0.7.39.3: the job as numbered steps
			n += 1
			var st := str(p["state"])
			var mark: String = {"done": "✓", "now": "→", "failed": "✗"}.get(st, "%d." % n)
			var t := _label(_box, "%s %s" % [mark, p["title"]], "" if st in ["now", "todo"] else UiTheme.MUTED_LABEL)
			t.name = "HeistStep_%s_%d" % [id, n]
			if st == "now":
				t.add_theme_color_override("font_color", UiTheme.ACCENT)
			if not str(p["text"]).is_empty():
				_label(_box, str(p["text"]), UiTheme.MUTED_LABEL)
		if HeistRules.status(s.character, id) != "active":
			continue
		for st: Dictionary in HeistRules.steps(s, data, id):
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 10)
			_box.add_child(row)
			var sid := str(st["id"])
			var ok := HeistRules.step_ok(s.character, id, sid)
			if not ok:
				var text := str(st["name"])
				if st.has("skill"):
					text += " (%d%%)" % HeistRules.step_chance(s, data, id, sid)
				_act(row, "Step_%s_%s" % [id, sid], text, HeistRules.step_why(s, data, id, sid), "step", id, sid)
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_END
		row.add_theme_constant_override("separation", 10)
		_box.add_child(row)
		var gu := Button.new()
		gu.name = "GiveUp_" + id
		gu.text = tr("BTN_HEIST_GIVE_UP")
		gu.disabled = GameState.is_busy()
		gu.add_theme_color_override("font_color", UiTheme.BAD)
		var hid := id
		gu.pressed.connect(func() -> void:
			ConfirmBox.ask(self, tr("CONFIRM_HEIST_GIVE_UP_TITLE").format({"name": str(d["name"])}), tr("CONFIRM_HEIST_GIVE_UP"), tr("BTN_HEIST_GIVE_UP"),
				func() -> void: GameState.heist_act("give_up", hid)))
		row.add_child(gu)
		var a := _act(row, "Act_" + id, tr("BTN_HEIST_ACT").format({"chance": HeistRules.act_chance(s, data, id)}), HeistRules.act_why(s, data, id), "act", id)
		if a.tooltip_text.is_empty():
			a.tooltip_text = tr("BTN_HEIST_ACT_TIP").format({"min": HeistRules.act_minutes(s, data, id)})
