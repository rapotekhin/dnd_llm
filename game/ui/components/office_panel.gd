class_name OfficePanel
extends ModalFrame
## The office window (roadmap v0.7.34): the hero's offices — rank, merit, wage, the whispers about bribes, today's
## cases with their options; a town for the headman — treasury, discontent, the tax, projects. Below — the offices
## on offer here (at the chief or the election's room): conditions, asking, the election, buying. Every act is
## GameState.office_act: the engine decides.

const SCENE := "res://ui/components/office_panel.tscn"

var _box: VBoxContainer
var _chief := ""


func _ready() -> void:
	super()
	close_requested.connect(func() -> void: visible = false)
	close_x.name = "CloseOfficeButton"
	_box = body
	EventBus.state_changed.connect(_rebuild)
	visibility_changed.connect(_rebuild)


## `chief` — the NPC whose offices to offer ("" — the hero's and the room's).
func open(chief: String = "") -> void:
	_chief = chief
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
	_label(_box, text).theme_type_variation = UiTheme.ACCENT_LABEL


func _act(parent: Control, node_name: String, text: String, why: String, what: String, id: String, arg: String = "") -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.disabled = not why.is_empty() or GameState.is_busy()
	b.tooltip_text = tr(why) if not why.is_empty() else ""
	b.size_flags_horizontal = Control.SIZE_SHRINK_END
	b.pressed.connect(func() -> void:
		var err := GameState.office_act(what, id, arg)
		if not err.is_empty():
			EventBus.message.emit(tr(err)))
	parent.add_child(b)
	return b


func _row(alignment: BoxContainer.AlignmentMode = BoxContainer.ALIGNMENT_BEGIN) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = alignment
	row.add_theme_constant_override("separation", 10)
	_box.add_child(row)
	return row


func _sep() -> void:
	if _box.get_child_count() > 0:
		_box.add_child(HSeparator.new())


func _rebuild() -> void:
	if not visible or not GameState.has_session():
		return
	clear_body()
	var s := GameState.session
	var data := Catalog.data
	for id: String in OfficeRules.held(s.character):
		_sep()
		_held(s, data, id)
	var offers: Array[String] = []
	if not _chief.is_empty():
		offers.append_array(OfficeRules.of_chief(data, _chief))
	offers.append_array(OfficeRules.of_room(data, s.room_id))
	for id: String in offers:
		if not OfficeRules.holds(s.character, id):
			_sep()
			_offer(s, data, id)
	if _box.get_child_count() == 0:
		_label(_box, tr("OFFICE_NONE"), UiTheme.MUTED_LABEL)


func _held(s: GameSession, data: Dictionary, id: String) -> void:
	var c := s.character
	var d := OfficeRules.def(data, id)
	_heading("%s — %s" % [OfficeRules.name_of(data, id), OfficeRules.rank_name(c, data, id)])
	var nx := OfficeRules.next_at(c, data, id)
	_label(_box, tr("OFFICE_STATUS").format({"merit": OfficeRules.merit(c, id), "next": tr("OFFICE_NEXT").format({"at": nx}) if nx > 0 else "",
		"pay": Money.format(OfficeRules.pay(c, data, id)), "talk": OfficeRules.suspicion_word(c, data, id)})).name = "OfficeStatus_" + id
	if bool(d.get("town", false)):
		_town(s, data, id)
	if s.room_id != str(d.get("room", "")):
		_label(_box, tr("OFFICE_GO_THERE").format({"place": WorldView.new(data["world"]).place_path(str(d["room"]))}), UiTheme.MUTED_LABEL)
	else:
		var list := OfficeRules.today(s, data, id)
		for i in list.size():
			var case: Dictionary = list[i]
			_label(_box, ("✓ " if bool(case["done"]) else "· ") + str(case["title"]), UiTheme.MUTED_LABEL if bool(case["done"]) else "").name = "Case_%s_%d" % [id, i]
			if bool(case["done"]):
				continue
			var row := HFlowContainer.new()
			row.add_theme_constant_override("h_separation", 8)
			row.alignment = FlowContainer.ALIGNMENT_END
			_box.add_child(row)
			for o: Dictionary in OfficeRules.cfg(data)["cases"][str(case["kind"])]["options"]:
				var text := str(o["name"])
				if o.has("check"):
					text += " (%d%%)" % OfficeRules.option_chance(s, data, o)
				var b := _act(row, "Decide_%s_%d_%s" % [id, i, o["id"]], text, OfficeRules.decide_why(s, data, id, i, str(o["id"])), "decide", id, "%d:%s" % [i, o["id"]])
				if b.tooltip_text.is_empty() and int(o.get("effects", {}).get("suspicion", 0)) > 0:
					b.tooltip_text = tr("OFFICE_BRIBE_TIP")
	var row := _row(BoxContainer.ALIGNMENT_END)
	var lv := Button.new()
	lv.name = "OfficeLeave_" + id
	lv.text = tr("BTN_OFFICE_LEAVE")
	lv.disabled = GameState.is_busy()
	lv.add_theme_color_override("font_color", UiTheme.BAD)
	lv.pressed.connect(func() -> void:
		ConfirmBox.ask(self, tr("CONFIRM_OFFICE_LEAVE_TITLE").format({"name": OfficeRules.name_of(data, id)}), tr("CONFIRM_OFFICE_LEAVE"), tr("BTN_OFFICE_LEAVE"),
			func() -> void: GameState.office_act("leave", id)))
	row.add_child(lv)


func _town(s: GameSession, data: Dictionary, id: String) -> void:
	var t := OfficeRules.town(s, data, str(OfficeRules.def(data, id)["location"]))
	var tc: Dictionary = OfficeRules.cfg(data)["town"]
	_label(_box, tr("OFFICE_TOWN").format({"treasury": Money.format(int(t["treasury"])), "mood": OfficeRules._word(OfficeRules.cfg(data)["discontent_words"], int(t["discontent"])),
		"n": int(t["discontent"])})).name = "OfficeTown_" + id
	var row := _row()
	_label(row, tr("OFFICE_TAX"))
	for lvl: String in tc["taxes"]:
		var tax: Dictionary = tc["taxes"][lvl]
		var b := _act(row, "Tax_%s_%s" % [id, lvl], str(tax["name"]), OfficeRules.tax_why(s, data, id, lvl), "tax", id, lvl)
		b.tooltip_text = tr("OFFICE_TAX_TIP").format({"income": Money.format(int(tax["income_cp"])), "mood": "%+d" % int(tax["discontent"])}) if b.tooltip_text.is_empty() else b.tooltip_text
	for p: Dictionary in OfficeRules.def(data, id).get("projects", []):
		var prow := _row()
		var builds: Dictionary = t["builds"]
		var pid := str(p["id"])
		var state := ""
		if builds.has(pid):
			state = tr("OFFICE_BUILT_ON").format({"day": int(builds[pid])}) if int(builds[pid]) > s.day else tr("OFFICE_BUILT_DONE")
		_label(prow, "%s — %s, %d дн.%s" % [p["name"], Money.format(int(p["cost_cp"])), int(p["days"]), " · " + state if not state.is_empty() else ""])
		if not builds.has(pid):
			_act(prow, "Build_%s_%s" % [id, pid], tr("BTN_OFFICE_BUILD"), OfficeRules.build_why(s, data, id, pid), "build", id, pid)


func _offer(s: GameSession, data: Dictionary, id: String) -> void:
	var d := OfficeRules.def(data, id)
	_heading(OfficeRules.name_of(data, id))
	if not str(d.get("text", "")).is_empty():
		_label(_box, str(d["text"]), UiTheme.MUTED_LABEL)
	var ranks: Array = d.get("ranks", [])
	if not ranks.is_empty():
		_label(_box, tr("OFFICE_OFFER_PAY").format({"rank": ranks[0]["name"], "pay": Money.format(int(ranks[0].get("pay_cp", 0)))}))
	for r: Dictionary in OfficeRules.requirements(s, data, id):
		_label(_box, ("✓ " if bool(r["ok"]) else "✗ ") + str(r["text"]), "" if bool(r["ok"]) else UiTheme.MUTED_LABEL)
	var row := _row(BoxContainer.ALIGNMENT_END)
	var ways: Array = d.get("ways", [])
	if ways.has("buy"):
		var bb := _act(row, "OfficeBuy_" + id, tr("BTN_OFFICE_BUY").format({"price": Money.format(int(d.get("price_cp", 0)))}), OfficeRules.buy_why(s, data, id), "buy", id)
		if bb.tooltip_text.is_empty():
			bb.tooltip_text = tr("OFFICE_BUY_TIP")
	if ways.has("election"):
		var eb := _act(row, "OfficeElect_" + id, tr("BTN_OFFICE_ELECT").format({"chance": OfficeRules.elect_chance(s, data, id)}), OfficeRules.elect_why(s, data, id), "elect", id)
		if eb.tooltip_text.is_empty():
			eb.tooltip_text = tr("OFFICE_ELECT_TIP").format({"fee": Money.format(int(OfficeRules.cfg(data)["election"]["fee_cp"]))})
	if ways.has("appoint"):
		_act(row, "OfficeAppoint_" + id, tr("BTN_OFFICE_APPOINT").format({"chance": OfficeRules.appoint_chance(s, data, id)}), OfficeRules.appoint_why(s, data, id), "appoint", id)
