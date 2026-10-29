class_name LetterPanel
extends Control
## The letter window (roadmap v0.7.48), opened by «Письмо» at a person with a post: to whom (the people the hero
## met, not here), the purpose with its hint, where to come (a helper) or on whom (a denunciation, with the evidence
## the hero has), the text, the way with its price, days and risk. «Отправить» is GameState.send_letter: the engine
## checks and sends; the master answers on the reply day.

var poster := ""
var _to := ""
var _purpose := ""
var _way := ""
var _room := ""
var _about := ""
var _text := ""
var _box: VBoxContainer
var frame: ModalFrame
var _send: Button


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame = ModalFrame.new(tr("LETTER_TITLE"), 720.0)
	add_child(frame)
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.close_requested.connect(func() -> void: visible = false)
	frame.close_x.name = "CloseLetterButton"
	_box = frame.body
	visibility_changed.connect(_rebuild)


func open(npc_id: String) -> void:
	poster = npc_id
	_text = ""
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


## A labelled pick: ids with their texts, the current one selected; a change rebuilds the window.
func _pick(node_name: String, caption: String, ids: Array[String], texts: Array[String], current: String, on_pick: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_box.add_child(row)
	var l := _label(row, caption)
	l.size_flags_horizontal = Control.SIZE_FILL
	l.custom_minimum_size = Vector2(150, 0)
	var ob := OptionButton.new()
	ob.name = node_name
	ob.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in ids.size():
		ob.add_item(texts[i], i)
		if ids[i] == current:
			ob.select(i)
	ob.item_selected.connect(func(i: int) -> void:
		on_pick.call(ids[i])
		_rebuild.call_deferred())
	row.add_child(ob)


func _extra() -> Dictionary:
	return {"room": _room, "about": _about}


func _refresh_send() -> void:
	if _send == null or not is_instance_valid(_send):
		return
	var why := LetterRules.send_why(GameState.session, Catalog.data, poster, _to, _purpose, _text, _way, _extra())
	_send.disabled = not why.is_empty() or GameState.is_busy()
	_send.tooltip_text = why
	frame.set_note(why)


func _rebuild() -> void:
	if not visible or not GameState.has_session():
		return
	frame.clear_body()
	for b in frame.footer.get_children():
		frame.footer.remove_child(b)
		b.queue_free()
	var s := GameState.session
	var data := Catalog.data
	var w := WorldView.new(data["world"])
	var people := LetterRules.recipients(s, data)
	if people.is_empty():
		_label(_box, tr("LETTER_NOBODY"), UiTheme.MUTED_LABEL).name = "LetterNobody"
		return
	var ways := LetterRules.ways_of(data, poster)
	if not people.has(_to):
		_to = people[0]
	var purposes: Array[String] = []
	for pid: String in LetterRules.cfg(data)["purposes"]:
		purposes.append(pid)
	if not purposes.has(_purpose):
		_purpose = purposes[0]
	if not ways.has(_way):
		_way = ways[0] if not ways.is_empty() else ""
	var p := LetterRules.purpose(data, _purpose)
	_pick("LetterPurpose", tr("LETTER_PURPOSE"), purposes, _strs(purposes.map(func(id: String) -> String: return str(LetterRules.purpose(data, id)["name"]))),
		_purpose, func(id: String) -> void: _purpose = id)
	_label(_box, str(p.get("hint", "")), UiTheme.MUTED_LABEL).name = "LetterHint"
	var to_list := people.filter(func(id: String) -> bool: return not bool(p.get("law", false)) or LetterRules.law_people(data).has(id))
	if to_list.is_empty():
		_label(_box, tr("LETTER_NO_LAW"), UiTheme.MUTED_LABEL)
		return
	if not to_list.has(_to):
		_to = to_list[0]
	_pick("LetterTo", tr("LETTER_TO"), to_list, _strs(to_list.map(func(id: String) -> String:
		return "%s — %s" % [w.npc(id).get("name", id), LetterRules._loc_name(data, LetterRules.npc_loc(s, data, id))])), _to,
		func(id: String) -> void: _to = id)
	match str(p.get("does", "")):
		"ally":
			var rooms: Array[String] = []
			for r: String in s.visited:
				if data["world"]["rooms"].has(r):
					rooms.append(r)
			if not rooms.has(_room):
				_room = rooms[0] if not rooms.is_empty() else ""
			_pick("LetterRoom", tr("LETTER_ROOM"), rooms, _strs(rooms.map(func(r: String) -> String: return w.place_path(r))), _room,
				func(id: String) -> void: _room = id)
		"arrest":
			var about: Array[String] = []
			for id: String in people + s.npcs_here(data["world"], s.room_id):
				if id != _to and id != poster and not about.has(id) and not w.npc(id).is_empty():
					about.append(id)
			if not about.has(_about):
				_about = about[0] if not about.is_empty() else ""
			_pick("LetterAbout", tr("LETTER_ABOUT"), about, _strs(about.map(func(id: String) -> String: return str(w.npc(id).get("name", id)))), _about,
				func(id: String) -> void: _about = id)
			var proof := LetterRules.evidence(s, data, _about, LetterRules._evidence_item(s, data, _about))
			_label(_box, tr("LETTER_EVIDENCE").format({"what": proof}) if not proof.is_empty() else tr("LETTER_NO_EVIDENCE"), UiTheme.MUTED_LABEL).name = "LetterEvidence"
	var edit := TextEdit.new()
	edit.name = "LetterText"
	edit.placeholder_text = tr("LETTER_TEXT_HINT")
	edit.custom_minimum_size = Vector2(0, 120)
	edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	edit.text = _text
	edit.text_changed.connect(func() -> void:
		_text = edit.text
		_refresh_send())
	_box.add_child(edit)
	var way_texts: Array[String] = []
	for way: String in ways:
		var q := LetterRules.quote(s, data, way, _to)
		way_texts.append(tr("LETTER_WAY").format({"way": LetterRules.cfg(data)["ways"][way]["name"], "cost": Money.format(int(q.get("cost", 0))),
			"days": int(q.get("days", 0)), "risk": int(q.get("risk", 0))}) if not q.is_empty() else str(LetterRules.cfg(data)["ways"][way]["name"]))
	_pick("LetterWay", tr("LETTER_WAY_CAPTION"), ways, way_texts, _way, func(id: String) -> void: _way = id)
	_send = frame.add_button(tr("BTN_LETTER_SEND"), func() -> void:
		var err := GameState.send_letter(poster, _to, _purpose, _text, _way, _extra())
		if not err.is_empty():
			EventBus.message.emit(tr(err))
			return
		visible = false, true)
	_send.name = "LetterSend"
	_refresh_send()


static func _strs(a: Array) -> Array[String]:
	var out: Array[String] = []
	for x: Variant in a:
		out.append(str(x))
	return out
