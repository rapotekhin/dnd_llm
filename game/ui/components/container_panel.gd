class_name ContainerPanel
extends Control
## The contents window (roadmap v0.7.18.1): what lies in a container of the room — take each thing or put the hero's
## own in, within its capacity; a locked one shows the ways to open it (a key, thieves' tools, force). Built like the
## pockets window (TheftPanel).

var prop_id := ""
var _box: VBoxContainer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 300)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 100)
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
	close.name = "CloseContainerButton"
	close.text = "BTN_CLOSE"
	close.custom_minimum_size = Vector2(0, 56)
	close.pressed.connect(func() -> void: visible = false)
	col.add_child(close)
	EventBus.state_changed.connect(_rebuild)
	visibility_changed.connect(_rebuild)


func open(prop: String) -> void:
	prop_id = prop
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


func _row_button(row: HBoxContainer, node_name: String, text: String, enabled: bool, action: Callable) -> void:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.disabled = not enabled
	b.pressed.connect(func() -> void:
		var err: String = action.call()
		if not err.is_empty():
			EventBus.message.emit(tr(err)))
	row.add_child(b)


func _rebuild() -> void:
	if not visible or not GameState.has_session() or prop_id.is_empty():
		return
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	var s := GameState.session
	var data := Catalog.data
	var p := PropRules.find(s, s.room_id, prop_id)
	if p.is_empty() or not ContainerRules.is_container(p):
		visible = false
		return
	var can_act := not GameState.is_busy()
	var cap := float(ContainerRules.kind(data, str(p["container"]))["capacity_lb"])
	var contents: Dictionary = p.get("contents", {})
	_box.add_child(_label(str(p["name"]), UiTheme.HEADING))
	var owner := str(p.get("owner", ""))
	var meta := tr("CONTAINER_LOAD").format({"w": _num(ContainerRules.weight(data, s.items, contents)), "cap": _num(cap)})
	if not owner.is_empty():
		meta += " · " + tr("CONTAINER_OWNER").format({"name": GameState.world().npc(owner).get("name", owner)})
	_box.add_child(_label(meta, UiTheme.MUTED_LABEL))
	if bool(p.get("locked", false)):
		_box.add_child(_label(tr("CONTAINER_LOCKED")))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		_box.add_child(row)
		for how: String in ContainerRules.ways(s, data, p):
			var h := how
			_row_button(row, "Unlock_" + how, tr("BTN_UNLOCK_" + how.to_upper()), can_act and Backend.is_ready(),
				func() -> String: return GameState.container_unlock(prop_id, h))
		return
	_box.add_child(_label(tr("CONTAINER_INSIDE"), UiTheme.MUTED_LABEL))
	if contents.is_empty():
		_box.add_child(_label(tr("CONTAINER_EMPTY"), UiTheme.MUTED_LABEL))
	for id: String in contents:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		_box.add_child(row)
		row.add_child(_label("%s ×%d" % [ItemRules.display_name(data["items"], s.items, id), int(contents[id])]))
		var iid := id
		_row_button(row, "TakeOut_" + id, tr("BTN_TAKE_OUT"), can_act, func() -> String: return GameState.container_move(prop_id, iid, 1, true))
	_box.add_child(_label(tr("CONTAINER_YOURS"), UiTheme.MUTED_LABEL))
	for id: String in s.character.get("inventory", {}):
		var free := TradeRules.sellable(s, id, data)
		if free <= 0:
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		_box.add_child(row)
		row.add_child(_label("%s ×%d" % [ItemRules.display_name(data["items"], s.items, id), free]))
		var iid := id
		_row_button(row, "PutIn_" + id, tr("BTN_PUT_IN"), can_act, func() -> String: return GameState.container_move(prop_id, iid, 1, false))


func _num(x: float) -> String:
	return str(int(x)) if is_equal_approx(x, roundf(x)) else str(snappedf(x, 0.1))
