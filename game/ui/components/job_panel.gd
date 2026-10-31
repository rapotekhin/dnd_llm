class_name JobPanel
extends ModalFrame
## The work window (roadmap v0.7.26): the jobs of one employer — the check of a shift, its hours and pay by rank, what
## the job asks; hire after an interview, a shift while the employer is here, the way to a promotion, quitting. Every
## act is GameState.job_act: the engine decides, the master narrates only a shift's event.

const SCENE := "res://ui/components/job_panel.tscn"

var _box: VBoxContainer
var _npc := ""


func _ready() -> void:
	super()
	close_requested.connect(func() -> void: visible = false)
	close_x.name = "CloseJobButton"
	_box = body
	EventBus.state_changed.connect(_rebuild)
	visibility_changed.connect(_rebuild)


func open(npc_id: String) -> void:
	_npc = npc_id
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


func _button(parent: Control, node_name: String, text: String, why: String, action: Callable) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.disabled = not why.is_empty() or GameState.is_busy()
	b.tooltip_text = tr(why) if not why.is_empty() else ""
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
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
	title.text = tr("JOB_TITLE_AT").format({"name": GameState.world().npc(_npc).get("name", _npc)})
	var ids := JobRules.of(s, data, _npc)
	if ids.is_empty():
		_label(_box, tr("JOB_NONE"), UiTheme.MUTED_LABEL)
	for i in ids.size():
		if i > 0:
			_box.add_child(HSeparator.new())
		_job(s, data, ids[i])


func _job(s: GameSession, data: Dictionary, id: String) -> void:
	var j := JobRules.job(s, data, id)
	var c := s.character
	var row := HBoxContainer.new()
	row.name = "Job_" + id
	row.add_theme_constant_override("separation", 10)
	_box.add_child(row)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 2)
	row.add_child(col)
	var job_name := _label(col, str(j.get("name", id)))
	job_name.add_theme_color_override("font_color", UiTheme.ACCENT)
	var check := CraftRules.tr_skill(data, str(j["skill"])) if j.has("skill") else BackgroundRules.tool_name(data, str(j.get("tool", "")))
	if j.has("skill") and j.has("tool"):
		check += " (" + tr("JOB_TOOL_HELPS").format({"tool": BackgroundRules.tool_name(data, str(j["tool"]))}) + ")"
	var pays: Array[String] = []
	for r in JobRules.top_rank(data) + 1:
		pays.append("%s — %s" % [JobRules.rank_name(s, data, id, r), Money.format(JobRules.pay(s, data, id, r))])
	_label(col, tr("JOB_META").format({"check": check, "time": TimeRules.span(JobRules.hours(s, data, id) * 60)}), UiTheme.MUTED_LABEL)
	_label(col, tr("JOB_PAY").format({"list": ", ".join(pays)}), UiTheme.MUTED_LABEL)
	var req := JobRules.requirements(s, data, id)
	if not req.is_empty():
		var parts: Array[String] = []
		for r: Dictionary in req:
			parts.append(("✓ " if bool(r["ok"]) else "✗ ") + str(r["text"]))
		var rl := _label(col, tr("JOB_REQUIRES").format({"list": ", ".join(parts)}), UiTheme.MUTED_LABEL)
		if req.any(func(r: Dictionary) -> bool: return not bool(r["ok"])):
			rl.add_theme_color_override("font_color", UiTheme.WARN)
	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	row.add_child(buttons)
	if not JobRules.hired(c, id):
		_label(col, tr("JOB_HIRE_CHANCE").format({"chance": JobRules.hire_chance(s, data, id), "dc": JobRules.hire_dc(s, data, id)}), UiTheme.MUTED_LABEL)
		_button(buttons, "JobHire_" + id, tr("BTN_JOB_HIRE"), JobRules.hire_why(s, data, id), GameState.job_act.bind("hire", id))
		return
	var st: Dictionary = JobRules.state(c)[id]
	var line := tr("JOB_RANK").format({"rank": JobRules.rank_name(s, data, id, int(st["rank"])), "shifts": int(st.get("shifts", 0))})
	if int(st["rank"]) < JobRules.top_rank(data):
		line += " · " + tr("JOB_TO_PROMOTE").format({"n": int(st.get("good", 0)), "of": JobRules.promote_after(s, data)})
	_label(col, line)
	_label(col, tr("JOB_SHIFT_CHANCE").format({"dc": JobRules.dc(s, data, id), "chance": JobRules.shift_chance(s, data, id)}), UiTheme.MUTED_LABEL)
	_button(buttons, "JobShift_" + id, tr("BTN_JOB_SHIFT").format({"time": TimeRules.span(JobRules.hours(s, data, id) * 60)}),
		JobRules.shift_why(s, data, id), GameState.job_act.bind("shift", id))
	var name := str(j.get("name", id))
	var q := _button(buttons, "JobQuit_" + id, tr("BTN_JOB_QUIT"), "", func() -> String:
		ConfirmBox.ask(self, tr("CONFIRM_JOB_QUIT_TITLE").format({"name": name}), tr("CONFIRM_JOB_QUIT"), tr("BTN_JOB_QUIT"),
			func() -> void: GameState.job_act("quit", id))
		return "")
	q.add_theme_color_override("font_color", UiTheme.BAD)
