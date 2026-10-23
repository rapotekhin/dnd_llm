class_name PlacePanel
extends Control
## «Взаимодействие с местом» (roadmap v0.7.22.7, big test #17): every thing of the room in one window — take one,
## open a container, look closer — and «Забрать всё» on top; the bodies to search. Built like the container window.

signal container_requested(prop_id: String)

var _box: VBoxContainer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 260)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 80)
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	margin.add_child(col)
	var panel := PanelContainer.new()
	panel.theme_type_variation = UiTheme.SIDE
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override("separation", 10)
	scroll.add_child(_box)
	var close := Button.new()
	close.name = "ClosePlaceButton"
	close.text = "BTN_CLOSE"
	close.custom_minimum_size = Vector2(0, 56)
	close.pressed.connect(func() -> void: visible = false)
	col.add_child(close)
	EventBus.state_changed.connect(_rebuild)
	visibility_changed.connect(_rebuild)


func open() -> void:
	visible = true
	_rebuild()


func _label(text: String, variation: String = "") -> Label:
	var l := Label.new()
	l.text = text
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not variation.is_empty():
		l.theme_type_variation = variation
	return l


func _button(row: Control, node_name: String, text: String, enabled: bool, action: Callable) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.disabled = not enabled
	b.pressed.connect(func() -> void:
		var err: String = action.call()
		if err.is_empty():
			visible = false
		else:
			EventBus.message.emit(tr(err)))
	row.add_child(b)
	return b


func _rebuild() -> void:
	if not visible or not GameState.has_session():
		return
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	var s := GameState.session
	var data := Catalog.data
	var can_act := Backend.is_ready() and not GameState.is_busy() and not s.in_conversation() and not CombatRules.active(s)
	_box.add_child(_label(str(GameState.world().room(s.room_id).get("name", s.room_id)), UiTheme.HEADING))
	var takeable: Array = PropRules.take_all_plan(s, data)["take"]
	var top := HBoxContainer.new()
	_box.add_child(top)
	var tb := _button(top, "TakeAllButton", tr("BTN_TAKE_ALL"), can_act and not takeable.is_empty(), GameState.take_all)
	tb.tooltip_text = tr("TAKE_ALL_TIP").format({"list": ", ".join(takeable.map(func(p: Dictionary) -> String: return str(p["name"])))}) \
		if not takeable.is_empty() else tr("TAKE_ALL_NOTHING")
	var props := PropRules.room_props(s, s.room_id)
	var bodies := CrimeRules.bodies_here(s, data)
	if props.is_empty() and bodies.is_empty():
		_box.add_child(_label(tr("PLACE_EMPTY"), UiTheme.MUTED_LABEL))
	for p: Dictionary in props:
		_box.add_child(HSeparator.new())
		var pid := str(p["id"])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		_box.add_child(row)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		var owner := str(p.get("owner", ""))
		var head := str(p["name"])
		if not owner.is_empty():
			head += " · " + tr("PLACE_OWNER").format({"name": GameState.world().npc(owner).get("name", owner)})
		if not str(p.get("state", "")).is_empty():
			head += " · " + tr("PROP_STATE_" + str(p["state"]).to_upper())
		info.add_child(_label(head))
		if not str(p.get("description", "")).is_empty():
			info.add_child(_label(str(p["description"]), UiTheme.MUTED_LABEL))
		if ContainerRules.is_container(p):
			_button(row, "Container_" + pid, tr("BTN_OPEN_SHORT"), not GameState.is_busy(), func() -> String:
				container_requested.emit(pid)
				return "")
		var take_why := str(PropRules.plan_take(s, data, {"prop_id": pid}).get("reason", ""))
		if not str(p.get("item_id", "")).is_empty():
			var t := _button(row, "Take_" + pid, tr("BTN_TAKE"), can_act and take_why.is_empty(), GameState.take_prop.bind(pid))
			t.tooltip_text = take_why if not take_why.is_empty() else (tr("PLACE_TAKE_OWNED") if not owner.is_empty() else "")
		_button(row, "Look_" + pid, tr("BTN_LOOK_AT"), can_act, func() -> String:
			return "" if GameState.submit(tr("PLACE_LOOK_SAY").format({"name": p["name"]})) else "WAIT_BUSY")
	for body: Dictionary in bodies:
		_box.add_child(HSeparator.new())
		var row := HBoxContainer.new()
		_box.add_child(row)
		row.add_child(_label(str(body["name"]) + (" · " + tr("PLACE_SEARCHED") if bool(body["searched"]) else "")))
		var bid := str(body["npc_id"])
		if not bool(body["searched"]):
			_button(row, "PlaceBody_" + bid, tr("BTN_SEARCH_SHORT"), can_act, GameState.search_body.bind(bid))
