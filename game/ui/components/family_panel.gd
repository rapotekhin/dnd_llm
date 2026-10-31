class_name FamilyPanel
extends Control
## The family window (roadmap v0.7.32): the engagement or the spouse and the home, the children with their age and
## stage (a name changed here), the expected child, the upkeep and the help of a day, the heir. Acts — a child at
## home with the spouse, a new name; every act is GameState.family_act: the engine decides.

var _box: VBoxContainer
var frame: ModalFrame


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame = ModalFrame.make(tr("FAMILY_TITLE"), 720.0)
	add_child(frame)
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.close_requested.connect(func() -> void: visible = false)
	frame.close_x.name = "CloseFamilyButton"
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


func _heading(text: String) -> void:
	_label(_box, text).add_theme_color_override("font_color", UiTheme.ACCENT)


func _act(parent: Control, node_name: String, text: String, why: String, what: String, id: String = "", arg: Callable = Callable()) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.disabled = not why.is_empty() or GameState.is_busy()
	b.tooltip_text = tr(why) if not why.is_empty() else ""
	b.size_flags_horizontal = Control.SIZE_SHRINK_END
	b.pressed.connect(func() -> void:
		var err := GameState.family_act(what, id, str(arg.call()) if arg.is_valid() else "")
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
	var f := FamilyRules.view(s.character)
	if not FamilyRules.engaged(s).is_empty():
		_label(_box, tr("FAMILY_ENGAGED_TO").format({"name": BondRules.npc_name(s, data, FamilyRules.engaged(s))})).name = "FamilyEngaged"
		_label(_box, tr("FAMILY_WEDDING_HINT"), UiTheme.MUTED_LABEL)
	var sp := FamilyRules.spouse(s)
	if not sp.is_empty():
		_heading(tr("FAMILY_SPOUSE_F" if str(BondRules.npc_def(s, data, sp).get("gender", "")) == "female" else "FAMILY_SPOUSE"))
		_label(_box, tr("FAMILY_SPOUSE_LINE").format({"name": BondRules.npc_name(s, data, sp), "day": int(f.get("married_day", 0)),
			"home": PropertyRules.name_of(s, data, str(f.get("home", ""))) if not str(f.get("home", "")).is_empty() else "—"})).name = "FamilySpouse"
		var h: Array = f.get("hours", [20, 7])
		_label(_box, tr("FAMILY_HOME_HOURS").format({"from": int(h[0]), "to": int(h[1])}), UiTheme.MUTED_LABEL)
	for k: Variant in f.get("kin", []):
		_label(_box, "%s — %s" % [BondRules.npc_name(s, data, str(k["npc"])), k["rel"]])
	if f.has("pregnant"):
		var p: Dictionary = f["pregnant"]
		_label(_box, tr("FAMILY_EXPECTING_LINE").format({"days": maxi(0, int(p["due"]) - s.day)})).name = "FamilyExpecting"
	if not sp.is_empty() and not f.has("pregnant"):
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_END
		_box.add_child(row)
		var cb := _act(row, "ChildTry", tr("BTN_FAMILY_CHILD"), FamilyRules.child_why(s, data), "child")
		if cb.tooltip_text.is_empty():
			cb.tooltip_text = tr("BTN_FAMILY_CHILD_TIP")
	var kids := FamilyRules.children(s)
	if not kids.is_empty():
		_box.add_child(HSeparator.new())
		_heading(tr("FAMILY_CHILDREN"))
	for id: String in kids:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		_box.add_child(row)
		var heir := " · " + tr("FAMILY_HEIR") if FamilyRules.heir(s, data) == id else ""
		_label(row, "%s — %s, %s%s" % [BondRules.npc_name(s, data, id), BondRules.npc_def(s, data, id).get("role", ""),
			tr("FAMILY_YEARS").format({"n": FamilyRules.years(s, data, id)}), heir]).name = "Child_" + id
		var edit := LineEdit.new()
		edit.name = "ChildName_" + id
		edit.placeholder_text = tr("FAMILY_NEW_NAME")
		edit.custom_minimum_size = Vector2(160, 0)
		row.add_child(edit)
		_act(row, "Rename_" + id, tr("BTN_FAMILY_RENAME"), "", "rename", id, func() -> String: return edit.text)
	var home := FamilyRules.household(s, data)
	if not home.is_empty():
		_box.add_child(HSeparator.new())
		var l := _label(_box, tr("FAMILY_ECONOMY").format({"upkeep": Money.format(FamilyRules.upkeep(s, data)), "help": Money.format(FamilyRules.help(s, data))}), UiTheme.MUTED_LABEL)
		l.name = "FamilyEconomy"
	if int(f.get("hungry", 0)) > 0:
		_label(_box, tr("FAMILY_HUNGRY").format({"n": int(f["hungry"])})).add_theme_color_override("font_color", UiTheme.BAD)
