class_name OrgPanel
extends ModalFrame
## The organization window (roadmap v0.7.33): joining at the head, the rank and points, the cut owed, the jobs on
## offer; for the hero's own band — its place, members and their income; founding one in an owned place. Every act is
## GameState.org_act: the engine decides.

const SCENE := "res://ui/components/org_panel.tscn"

var _box: VBoxContainer
var _org := ""


func _ready() -> void:
	super()
	close_requested.connect(func() -> void: visible = false)
	close_x.name = "CloseOrgButton"
	_box = body
	EventBus.state_changed.connect(_rebuild)
	visibility_changed.connect(_rebuild)


## `org_id` "" — the hero's organizations, or founding one.
func open(org_id: String = "") -> void:
	_org = org_id
	title.text = tr("ORG_TITLE") if org_id.is_empty() else str(OrgRules.word(GameState.session, Catalog.data, org_id)["nom"]).capitalize()
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


func _act(parent: Control, node_name: String, text: String, why: String, what: String, id: String, arg: Callable = Callable(), sure: String = "") -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.disabled = not why.is_empty() or GameState.is_busy()
	b.tooltip_text = tr(why) if not why.is_empty() else ""
	b.size_flags_horizontal = Control.SIZE_SHRINK_END
	var go := func() -> void:
		var err := GameState.org_act(what, id, str(arg.call()) if arg.is_valid() else "")
		if not err.is_empty():
			EventBus.message.emit(tr(err))
	if sure.is_empty():
		b.pressed.connect(go)
	else:
		b.pressed.connect(func() -> void: ConfirmBox.ask(self, sure, tr("CONFIRM_ORG_LEAVE"), text, go))
	parent.add_child(b)
	return b


func _rebuild() -> void:
	if not visible or not GameState.has_session():
		return
	clear_body()
	var s := GameState.session
	var data := Catalog.data
	var list: Array[String] = []
	if not _org.is_empty() and not OrgRules.def(s, data, _org).is_empty():
		list.append(_org)
	for id: String in OrgRules.mine(s, data):
		if not list.has(id):
			list.append(id)
	for id: String in list:
		if _box.get_child_count() > 0:
			_box.add_child(HSeparator.new())
		_org_block(s, data, id)
	if OrgRules.own(s, data).is_empty() and not OrgRules.places(s, data).is_empty():
		if _box.get_child_count() > 0:
			_box.add_child(HSeparator.new())
		_found_block(s, data)


func _org_block(s: GameSession, data: Dictionary, id: String) -> void:
	var d := OrgRules.def(s, data, id)
	_label(_box, OrgRules.org_name(s, data, id)).theme_type_variation = UiTheme.ACCENT_LABEL
	if not str(d.get("description", "")).is_empty():
		_label(_box, str(d["description"]), UiTheme.MUTED_LABEL)
	if str(d.get("head", "")) == OwnerRules.HERO:
		_label(_box, tr("ORG_OWN_LINE").format({"place": PropertyRules.name_of(s, data, str(d.get("place", "")))})).name = "OrgOwn"
		var names: Array[String] = []
		for m: String in OrgRules.members(s, data, id):
			names.append(BondRules.npc_name(s, data, m))
		_label(_box, tr("ORG_MEMBERS").format({"names": ", ".join(names) if not names.is_empty() else "—",
			"income": Money.format(names.size() * int(OrgRules.cfg(data)["member_income_cp"]))})).name = "OrgMembers"
		_label(_box, tr("ORG_RECRUIT_HINT").format({"at": int(OrgRules.cfg(data)["recruit_bond"])}), UiTheme.MUTED_LABEL)
		return
	_label(_box, tr("ORG_HEAD").format({"name": OrgRules.head_name(s, data, id)}), UiTheme.MUTED_LABEL)
	var st: Dictionary = OrgRules.view(s.character).get(id, {})
	if OrgRules.member(s.character, id):
		var nx := OrgRules.next_at(s, data, id)
		_label(_box, tr("ORG_RANK").format({"rank": OrgRules.rank_name(s, data, id), "points": int(st.get("points", 0)),
			"next": tr("ORG_NEXT").format({"at": nx}) if nx > 0 else ""})).name = "OrgRank"
		if Ledger.owed(s, "cut:" + id) > 0:
			var orow := HBoxContainer.new()
			_box.add_child(orow)
			var left := int(OrgRules.cfg(data)["owe_days"]) - (s.day - Ledger.since(s, "cut:" + id))
			_label(orow, tr("ORG_OWED").format({"cp": Money.format(Ledger.owed(s, "cut:" + id)), "days": maxi(0, left)})).name = "OrgOwed"
			_act(orow, "OrgPay_" + id, tr("BTN_ORG_PAY"), OrgRules.pay_why(s, data, id), "pay", id)
		var work := OrgRules.jobs_of(s, data, id)
		if not work.is_empty():  # v0.7.39.1: the organization's work is hired at its head (the «Работа» button)
			_label(_box, tr("ORG_WORK").format({"list": ", ".join(work.map(func(j: String) -> String: return str(JobRules.job(s, data, j).get("name", j))))}),
				UiTheme.MUTED_LABEL).name = "OrgWork"
		var offers := OrgRules.offered(s, data, id)
		if not offers.is_empty():
			_label(_box, tr("ORG_JOBS")).theme_type_variation = UiTheme.ACCENT_LABEL
		for h: String in offers:
			var hd := HeistRules.def(s, data, h)
			var hrow := HBoxContainer.new()
			hrow.add_theme_constant_override("separation", 10)
			_box.add_child(hrow)
			_label(hrow, "«%s» — %s, %s. %s" % [hd["name"], HeistRules.kind(data, str(hd["kind"]))["name"], HeistRules.target_name(s, data, h), hd.get("text", "")])
			_act(hrow, "OrgTake_" + h, tr("BTN_ORG_TAKE"), OrgRules.take_why(s, data, id, h), "take", id, func() -> String: return h)
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_END
		_box.add_child(row)
		_act(row, "OrgLeave_" + id, tr("BTN_ORG_LEAVE"), "", "leave", id, Callable(), tr("CONFIRM_ORG_LEAVE_TITLE").format({"name": OrgRules.org_name(s, data, id)})).add_theme_color_override("font_color", UiTheme.BAD)
	elif OrgRules.candidate(s.character, id):
		_label(_box, tr("ORG_TRIAL").format({"job": HeistRules.def(s, data, str(d.get("trial", ""))).get("name", "")})).name = "OrgTrial"
	else:
		var hint := tr("ORG_JOIN_HINT").format({"cut": int(d.get("cut_pct", 0))}) if not (d.get("heists", []) as Array).is_empty() else tr("ORG_JOIN_HINT_WORK")
		_label(_box, hint, UiTheme.MUTED_LABEL)
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_END
		_box.add_child(row)
		_act(row, "OrgJoin_" + id, tr("BTN_ORG_JOIN"), OrgRules.join_why(s, data, id), "join", id)


func _found_block(s: GameSession, data: Dictionary) -> void:
	_label(_box, tr("ORG_FOUND_TITLE")).theme_type_variation = UiTheme.ACCENT_LABEL
	_label(_box, tr("ORG_FOUND_HINT").format({"fee": Money.format(int(OrgRules.cfg(data)["found_fee_cp"]))}), UiTheme.MUTED_LABEL)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_box.add_child(row)
	var edit := LineEdit.new()
	edit.name = "OrgFoundName"
	edit.placeholder_text = tr("ORG_FOUND_NAME")
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(edit)
	var pick := OptionButton.new()
	pick.name = "OrgFoundPlace"
	pick.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	var places := OrgRules.places(s, data)
	for p: String in places:
		pick.add_item(PropertyRules.name_of(s, data, p))
	row.add_child(pick)
	var b := Button.new()
	b.name = "OrgFound"
	b.text = tr("BTN_ORG_FOUND")
	b.disabled = GameState.is_busy()
	b.pressed.connect(func() -> void:
		var err := GameState.org_act("found", places[maxi(0, pick.selected)], edit.text)
		if not err.is_empty():
			EventBus.message.emit(tr(err)))
	row.add_child(b)
