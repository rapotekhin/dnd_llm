class_name StudyPanel
extends Control
## The study window (roadmap v0.7.30): at a teacher — the school's entrance exam (its head) and the courses it teaches;
## "" — the hero's courses with their progress and misses, the study books it carries and the finished courses. Every
## act is GameState.study_act: the engine decides.

var _box: VBoxContainer
var frame: ModalFrame
var _npc := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame = ModalFrame.new(tr("STUDY_TITLE"), 820.0)
	add_child(frame)
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.close_requested.connect(func() -> void: visible = false)
	frame.close_x.name = "CloseStudyButton"
	_box = frame.body
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


func _heading(text: String) -> void:
	_label(_box, text).add_theme_color_override("font_color", UiTheme.ACCENT)


func _buttons(node_name: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = node_name
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 10)
	_box.add_child(row)
	return row


func _button(parent: Control, node_name: String, text: String, why: String, what: String, id: String) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.disabled = not why.is_empty() or GameState.is_busy()
	b.tooltip_text = tr(why) if not why.is_empty() else ""
	b.pressed.connect(func() -> void:
		var err := GameState.study_act(what, id)
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
	_label(_box, tr("BANK_PURSE").format({"money": Money.format(int(s.character.get("gold_cp", 0)))}), UiTheme.MUTED_LABEL)
	if _npc.is_empty():
		_mine(s, data)
	else:
		_teacher(s, data)


func _teacher(s: GameSession, data: Dictionary) -> void:
	frame.title.text = tr("STUDY_TITLE_AT").format({"name": StudyRules.npc_name(s, data, _npc)})
	for sid: String in StudyRules.headed_by(data, _npc):
		var sc := StudyRules.school(data, sid)
		_heading(str(sc["name"]))
		var st: Dictionary = StudyRules.school_state(s.character).get(sid, {})
		if not st.is_empty():
			_label(_box, tr("STUDY_ADMITTED_STIPEND") if bool(st.get("stipend", false)) else tr("STUDY_ADMITTED"), UiTheme.MUTED_LABEL)
			continue
		var ex: Dictionary = sc.get("exam", {})
		_label(_box, tr("STUDY_EXAM_HINT").format({"skill": CraftRules.tr_skill(data, str(ex.get("skill", ""))), "dc": int(ex.get("dc", 0)),
			"chance": StudyRules.exam_chance(s, data, sid)}), UiTheme.MUTED_LABEL)
		_button(_buttons("ExamRow_" + sid), "ExamTake_" + sid, tr("BTN_STUDY_EXAM"), StudyRules.exam_why(s, data, sid), "exam", sid)
		_box.add_child(HSeparator.new())
	var list := StudyRules.offered_by(s, data, _npc)
	if list.is_empty():
		return
	_heading(tr("STUDY_COURSES"))
	for id: String in list:
		_course(s, data, id, true)


func _course(s: GameSession, data: Dictionary, id: String, _at_teacher: bool) -> void:
	var co := StudyRules.course(s, data, id)
	var c := s.character
	var head := _label(_box, "%s — %s" % [StudyRules.name_of(s, data, id), StudyRules.teaches_text(s, data, id)])
	head.name = "Course_" + id
	var bits: Array[String] = []
	var st: Dictionary = StudyRules.view(c)["courses"].get(id, {})
	var known := st.is_empty() and not StudyRules.done(c, id) and StudyRules.known_already(s, data, id)
	if StudyRules.done(c, id):
		bits.append(tr("STUDY_FINISHED"))
	elif known:
		bits.append(tr("STUDY_KNOWN"))
	elif not st.is_empty():
		bits.append(tr("STUDY_PROGRESS").format({"done": int(st["progress"]), "need": StudyRules.lessons_needed(s, data, id)}))
		if str(co.get("book", "")).is_empty():
			bits.append(tr("STUDY_MISSES").format({"n": int(st.get("misses", 0))}))
	else:
		bits.append(tr("STUDY_LESSONS").format({"n": StudyRules.lessons_needed(s, data, id)}))
		var f := StudyRules.fee(s, data, id)
		if str(co.get("book", "")).is_empty():
			bits.append(tr("STUDY_FEE").format({"money": Money.format(f)}) if f > 0 else tr("STUDY_FREE"))
	if str(co.get("teacher", "")) != _npc and not str(co.get("teacher", "")).is_empty():
		bits.append(tr("STUDY_TEACHER").format({"name": StudyRules.npc_name(s, data, str(co["teacher"]))}))
		var at := StudyRules.where(s, data, id)
		if st.is_empty() and not at.is_empty() and not StudyRules.here(s, data, str(co["teacher"])):
			bits.append(tr("STUDY_WHERE").format({"place": at}))
	if not StudyRules.done(c, id) and not known:
		bits.append(tr("STUDY_LESSON_HINT").format({"hours": StudyRules.lesson_hours(data), "chance": StudyRules.lesson_chance(s, data, id)}))
	_label(_box, " · ".join(bits), UiTheme.MUTED_LABEL)
	if StudyRules.done(c, id) or known:
		return
	var bad := StudyRules.requirements(s, data, id).filter(func(r: Dictionary) -> bool: return not bool(r["ok"]))
	if not bad.is_empty() and st.is_empty():
		var l := _label(_box, tr("STUDY_NEEDS").format({"list": ", ".join(bad.map(func(r: Dictionary) -> String: return str(r["text"])))}), UiTheme.MUTED_LABEL)
		l.add_theme_color_override("font_color", UiTheme.WARN)
	var row := _buttons("CourseActs_" + id)
	var book := not str(co.get("book", "")).is_empty()
	if book or not st.is_empty():
		_button(row, "Lesson_" + id, tr("BTN_STUDY_READ") if book else tr("BTN_STUDY_LESSON"), StudyRules.lesson_why(s, data, id), "lesson", id)
	if not book and st.is_empty():
		_button(row, "Enroll_" + id, tr("BTN_STUDY_ENROLL"), StudyRules.enroll_why(s, data, id), "enroll", id)
	if not book and not st.is_empty():
		var d := _button(row, "Drop_" + id, tr("BTN_STUDY_DROP"), "", "drop", id)
		d.add_theme_color_override("font_color", UiTheme.BAD)


func _mine(s: GameSession, data: Dictionary) -> void:
	frame.title.text = tr("STUDY_TITLE")
	var c := s.character
	var any := false
	if not (StudyRules.view(c)["courses"] as Dictionary).is_empty():
		_heading(tr("STUDY_MY_COURSES"))
		for id: String in StudyRules.view(c)["courses"]:
			if str(StudyRules.course(s, data, id).get("book", "")).is_empty():
				_course(s, data, id, false)
				any = true
	var books := StudyRules.books(s, data).filter(func(id: String) -> bool: return not StudyRules.done(c, id) and not StudyRules.known_already(s, data, id))
	if not books.is_empty():
		_heading(tr("STUDY_BOOKS"))
		for id: String in books:
			_course(s, data, id, false)
			any = true
	var waiting := StudyRules.waiting(s, data)
	if not waiting.is_empty():  # v0.7.39.7: courses the master pointed to, at teachers elsewhere
		_heading(tr("STUDY_WAITING"))
		for id: String in waiting:
			_course(s, data, id, false)
			any = true
	var done: Array = StudyRules.view(c)["done"]
	if not done.is_empty():
		_heading(tr("STUDY_DONE_LIST"))
		_label(_box, ", ".join(done.map(func(id: Variant) -> String: return StudyRules.name_of(s, data, str(id)))), UiTheme.MUTED_LABEL)
		any = true
	if not any:
		_label(_box, tr("STUDY_NOTHING"), UiTheme.MUTED_LABEL)
