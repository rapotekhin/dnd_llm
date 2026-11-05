class_name ContainerPanel
extends ModalFrame
## The contents window (roadmap v0.7.18.1): what lies in a container of the room — take each thing or put the hero's
## own in, within its capacity; a locked one shows the ways to open it (a key, thieves' tools, force). Built like the
## pockets window (TheftPanel).

const SCENE := "res://ui/components/container_panel.tscn"

var prop_id := ""
var _box: VBoxContainer


func _ready() -> void:
	super()
	close_requested.connect(func() -> void: visible = false)
	close_x.name = "CloseContainerButton"
	_box = body
	EventBus.state_changed.connect(_rebuild)
	visibility_changed.connect(_rebuild)


func open(prop: String) -> void:
	prop_id = prop
	visible = true
	_rebuild()


func _row_button(row: HBoxContainer, node_name: String, text: String, enabled: bool, action: Callable) -> Button:
	var b := UiParts.act_button(row, node_name, text, "", action)  # v0.8.4.29.6: grey while busy too
	b.disabled = b.disabled or not enabled
	return b


func _rebuild() -> void:
	if not visible or not GameState.has_session() or prop_id.is_empty():
		return
	clear_body()
	var s := GameState.session
	var data := Catalog.data
	var p := ContainerRules.target(s, data, prop_id)  # a thing of the room or a bag of the hero (v0.7.18.2)
	if p.is_empty():
		visible = false
		return
	var is_bag := ContainerRules.bags(s.character).has(prop_id)
	var can_act := not GameState.is_busy()
	var cap := float(p["capacity_lb"]) if p.has("capacity_lb") else float(ContainerRules.kind(data, str(p["container"]))["capacity_lb"])  # v0.7.42: a pack, a cart
	var contents: Dictionary = p.get("contents", {})
	title.text = str(p["name"])
	var owner := str(p.get("owner", ""))
	var meta := tr("CONTAINER_LOAD").format({"w": _num(ContainerRules.weight(data, s.items, contents)), "cap": _num(cap)})
	if not owner.is_empty():
		meta += " · " + tr("CONTAINER_OWNER").format({"name": GameState.world().npc(owner).get("name", owner)})
	_box.add_child(UiParts.label(null, meta, UiTheme.MUTED_LABEL))
	if is_bag:  # leave it here with what is in it
		var drop_row := HBoxContainer.new()
		_box.add_child(drop_row)
		_row_button(drop_row, "DropBag", tr("BTN_DROP_BAG"), can_act and not session_busy(), func() -> String:
			visible = false
			return GameState.drop_item(prop_id))
	if bool(p.get("locked", false)):
		_box.add_child(UiParts.label(null, tr("CONTAINER_LOCKED")))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		_box.add_child(row)
		var ways := ContainerRules.ways(s, data, p)
		for how: String in ways:
			var h := how
			_row_button(row, "Unlock_" + how, tr("BTN_UNLOCK_" + how.to_upper()), can_act and Backend.is_ready(),
				func() -> String: return GameState.container_unlock(prop_id, h))
		if not ways.has("pick"):  # v0.7.39.3: «Взломать» seen, grey without the tools
			var hint := FenceRules.tool_hint(s, data, "thieves_tools")
			var pb := _row_button(row, "Unlock_pick", tr("BTN_UNLOCK_PICK"), false, func() -> String: return "")
			pb.tooltip_text = tr("PICK_NO_TOOLS") + ("" if hint.is_empty() else ": " + hint)
		return
	var locks := ContainerRules.lock_ways(s, data, p)  # the hero's own lock (v0.8.4.27)
	if not locks.is_empty():
		var lrow := HBoxContainer.new()
		_box.add_child(lrow)
		for how: String in locks:
			var h := how
			_row_button(lrow, "Lock_" + how, tr("BTN_LOCK_" + how.to_upper()), can_act, func() -> String: return GameState.container_lock(prop_id, h))
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	_box.add_child(head)
	head.add_child(UiParts.label(null, tr("CONTAINER_INSIDE"), UiTheme.MUTED_LABEL))
	if contents.is_empty():
		_box.add_child(UiParts.label(null, tr("CONTAINER_EMPTY"), UiTheme.MUTED_LABEL))
	else:  # v0.7.49.4: everything at once
		_row_button(head, "TakeAll", tr("BTN_TAKE_ALL_CONTAINER"), can_act, func() -> String: return GameState.container_take_all(prop_id))
	for id: String in contents:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		_box.add_child(row)
		row.add_child(UiParts.label(null, "%s ×%d" % [ItemRules.display_name(data["items"], s.items, id), int(contents[id])]))
		var iid := id
		_row_button(row, "TakeOut_" + id, tr("BTN_TAKE_OUT"), can_act, func() -> String: return GameState.container_move(prop_id, iid, 1, true))
		if int(contents[id]) > 1:  # the whole stack (v0.7.49.4)
			var n := int(contents[id])
			_row_button(row, "TakeStack_" + id, tr("BTN_TAKE_STACK"), can_act, func() -> String: return GameState.container_move(prop_id, iid, n, true))
	_box.add_child(UiParts.label(null, tr("CONTAINER_YOURS"), UiTheme.MUTED_LABEL))
	for id: String in s.character.get("inventory", {}):
		var free := TradeRules.sellable(s, id, data)
		if is_bag and id == str(p["kind"]):
			free -= ContainerRules.bags_of(s.character, id).size() - ContainerRules.full_bags(s.character, id)  # not into itself
		if free <= 0:
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		_box.add_child(row)
		row.add_child(UiParts.label(null, "%s ×%d" % [ItemRules.display_name(data["items"], s.items, id), free]))
		var iid := id
		_row_button(row, "PutIn_" + id, tr("BTN_PUT_IN"), can_act, func() -> String: return GameState.container_move(prop_id, iid, 1, false))


func _num(x: float) -> String:
	return str(int(x)) if is_equal_approx(x, roundf(x)) else str(snappedf(x, 0.1))


func session_busy() -> bool:
	return GameState.session.in_conversation() or CombatRules.active(GameState.session)
