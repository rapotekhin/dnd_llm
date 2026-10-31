class_name BondPanel
extends ModalFrame
## The bond window (roadmap v0.7.31): the step and the closeness with an NPC, what it gives, the tastes learned from
## gifts, the romance; acts — a gift from the hero's things, a confession, breaking up, hiding from the guard. Every
## act is GameState.bond_act: the engine decides.

const SCENE := "res://ui/components/bond_panel.tscn"

var _box: VBoxContainer
var _npc := ""


func _ready() -> void:
	super()
	close_requested.connect(func() -> void: visible = false)
	close_x.name = "CloseBondButton"
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


func _heading(text: String) -> void:
	_label(_box, text).theme_type_variation = UiTheme.ACCENT_LABEL


func _button(parent: Control, node_name: String, text: String, why: String, what: String, item: String = "") -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.disabled = not why.is_empty() or GameState.is_busy()
	b.tooltip_text = tr(why) if not why.is_empty() else ""
	b.size_flags_horizontal = Control.SIZE_SHRINK_END
	b.pressed.connect(func() -> void:
		var err := GameState.bond_act(what, _npc, item)
		if not err.is_empty():
			EventBus.message.emit(tr(err)))
	parent.add_child(b)
	return b


func _rebuild() -> void:
	if not visible or not GameState.has_session() or _npc.is_empty():
		return
	clear_body()
	var s := GameState.session
	var data := Catalog.data
	var c := s.character
	var who := BondRules.npc_name(s, data, _npc)
	title.text = tr("BOND_TITLE_AT").format({"name": who})
	var cfg := BondRules.cfg(data)
	var p := BondRules.points(c, _npc)
	var w := BondRules.word(c, data, _npc)
	var nx := BondRules.next_at(c, data, _npc)
	var head := _label(_box, "%s · %s · %s" % [str(cfg["kinds"][BondRules.kind(c, _npc)]["name"]).capitalize(),
		w if not w.is_empty() else tr("BOND_NO_STEP"), tr("BOND_POINTS").format({"n": p}) + (" / %d" % nx if nx > 0 else "")])
	head.name = "BondStep"
	if BondRules.rival(c, data, _npc):
		head.add_theme_color_override("font_color", UiTheme.BAD)
	var bar := ProgressBar.new()
	bar.name = "BondBar"
	var from := int(BondRules.step(c, data, _npc).get("at", 0)) if p >= 0 else 0
	bar.min_value = from if nx > 0 else 0
	bar.max_value = nx if nx > 0 else maxi(1, p)
	bar.value = p
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 8)
	bar.add_theme_stylebox_override("fill", UiTheme.box(UiTheme.ACCENT, UiTheme.ACCENT, 0, 0, 2))
	bar.add_theme_stylebox_override("background", UiTheme.box(UiTheme.BG, UiTheme.BORDER, 1, 0, 2))
	_box.add_child(bar)
	var perks := BondRules.perks_text(s, data, _npc)
	var pl := _label(_box, tr("BOND_GIVES").format({"list": ", ".join(perks)}) if not perks.is_empty() else tr("BOND_GIVES_NOTHING"), UiTheme.MUTED_LABEL)
	pl.name = "BondPerks"
	var k := BondRules.known(c, _npc)
	var tastes: Array[String] = []
	if not (k["likes"] as Array).is_empty():
		tastes.append(tr("BOND_LIKES").format({"list": ", ".join((k["likes"] as Array).map(func(t: Variant) -> String: return BondRules.taste_name(s, data, str(t))))}))
	if not (k["dislikes"] as Array).is_empty():
		tastes.append(tr("BOND_DISLIKES").format({"list": ", ".join((k["dislikes"] as Array).map(func(t: Variant) -> String: return BondRules.taste_name(s, data, str(t))))}))
	_label(_box, " · ".join(tastes) if not tastes.is_empty() else tr("BOND_TASTES_UNKNOWN"), UiTheme.MUTED_LABEL).name = "BondTastes"
	_romance(s, data)
	_gifts(s, data)


func _romance(s: GameSession, data: Dictionary) -> void:
	var c := s.character
	var row := HBoxContainer.new()
	row.name = "BondActs"
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 10)
	var closed := BondRules.romance_closed(s, data, _npc)
	var text := ""
	if BondRules.kind(c, _npc) == "romance":
		text = tr("BOND_ROMANCE_ON")
	elif not closed.is_empty():
		text = tr("BOND_ROMANCE_CLOSED_WHY").format({"why": closed})
	else:
		text = tr("BOND_CONFESS_HINT").format({"at": int(BondRules.cfg(data)["confess"]["at"]), "dc": BondRules.confess_dc(s, data, _npc),
			"chance": BondRules.confess_chance(s, data, _npc)})
	_label(_box, text, UiTheme.MUTED_LABEL).name = "BondRomance"
	_box.add_child(row)
	if BondRules.kind(c, _npc) == "romance" and FamilyRules.spouse(s) != _npc and FamilyRules.engaged(s) != _npc:  # v0.7.32
		var pr := Button.new()
		pr.name = "Propose_" + _npc
		pr.text = tr("BTN_FAMILY_PROPOSE")
		var pw := FamilyRules.propose_why(s, data, _npc)
		pr.disabled = not pw.is_empty() or GameState.is_busy()
		pr.tooltip_text = tr(pw).format({"at": int(FamilyRules.cfg(data)["propose_at"])}) if not pw.is_empty() else ""
		pr.pressed.connect(func() -> void:
			var err := GameState.family_act("propose", _npc)
			if not err.is_empty():
				EventBus.message.emit(tr(err)))
		row.add_child(pr)
	if BondRules.kind(c, _npc) == "romance" and FamilyRules.spouse(s) != _npc:
		var b := _button(row, "Break_" + _npc, tr("BTN_BOND_BREAK"), BondRules.break_why(s, data, _npc), "break")
		b.add_theme_color_override("font_color", UiTheme.BAD)
	elif closed.is_empty():
		_button(row, "Confess_" + _npc, tr("BTN_BOND_CONFESS"), BondRules.confess_why(s, data, _npc), "confess")
	if CrimeRules.wanted_at(s, data, s.room_id) and BondRules.close(s, data, _npc):
		_button(row, "Hide_" + _npc, tr("BTN_BOND_HIDE"), BondRules.hide_why(s, data, _npc), "hide").tooltip_text = tr("BTN_BOND_HIDE_TIP")


func _gifts(s: GameSession, data: Dictionary) -> void:
	_box.add_child(HSeparator.new())
	_heading(tr("BOND_GIFT_HEADING"))
	var why := BondRules.gift_why(s, data, _npc)
	if why == "BOND_GIFT_TODAY" or why == "BOND_NOT_HERE" or why == "BOND_REFUSES":
		_label(_box, tr(why), UiTheme.MUTED_LABEL).name = "GiftNote"
		return
	var list := BondRules.gifts(s, data)
	if list.is_empty():
		_label(_box, tr("BOND_GIFT_NONE"), UiTheme.MUTED_LABEL).name = "GiftNote"
		return
	var k := BondRules.known(s.character, _npc)
	for id: String in list:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		_box.add_child(row)
		var name := ItemRules.display_name(data["items"], s.items, id)
		var qty := int(s.character["inventory"][id])
		var taste := ""
		var t := BondRules.taste_of(s, data, _npc, id)
		if t["taste"] == "liked" and (k["likes"] as Array).has(t["by"]):
			taste = " — " + tr("BOND_TASTE_LIKED")
		elif t["taste"] == "disliked" and (k["dislikes"] as Array).has(t["by"]):
			taste = " — " + tr("BOND_TASTE_DISLIKED")
		var l := _label(row, "%s%s%s" % [name, " ×%d" % qty if qty > 1 else "", taste])
		if taste.ends_with(tr("BOND_TASTE_LIKED")):
			l.add_theme_color_override("font_color", UiTheme.OK)
		elif not taste.is_empty():
			l.add_theme_color_override("font_color", UiTheme.WARN)
		_button(row, "Gift_" + id, tr("BTN_BOND_GIFT"), why, "gift", id)
