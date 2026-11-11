class_name ContainerPanel
extends ModalFrame
## The contents window (roadmap v0.7.18.1; two grids as in BG3 since v0.8.4.43.6): what lies in a container of the room,
## a body or a bag of the hero on the left, the hero's own things on the right. A thing dragged from one grid onto the
## other is taken or put in (Shift asks how many), a double click moves the whole stack, the right button lists «Взять» /
## «Взять все» or «Положить» / «Положить всё»; within its capacity. A locked one shows the ways to open it (a key,
## thieves' tools, force). Every move is ContainerRules' through GameState.container_move.

const SCENE := "res://ui/components/container_panel.tscn"

var prop_id := ""
var _box: ItemGrid
var _mine: ItemGrid
var _menu: ActsMenu
var _box_view := {}
var _mine_view := {}


func required() -> Dictionary:
	var nodes := super()
	nodes.merge({"%ChestSplit": "VBoxContainer", "%ChestTop": "VBoxContainer", "%ChestGrids": "HBoxContainer", "%BoxCol": "VBoxContainer",
		"%BoxHead": "HBoxContainer", "%MineCol": "VBoxContainer", "%ChestActsBox": "VBoxContainer"})
	return nodes


func _ready() -> void:
	super()
	close_requested.connect(func() -> void: visible = false)
	close_x.name = "CloseContainerButton"
	fill_body(UiScenes.need(self, "%ChestSplit"))
	for n: Node in get_tree().get_nodes_in_group("editor_sample"):
		if is_ancestor_of(n):
			n.queue_free()
	_box = _grid("Box", "In_", "%BoxCol", _box_view, true)
	_mine = _grid("Mine", "Mine_", "%MineCol", _mine_view, false)
	EventBus.state_changed.connect(_rebuild)
	visibility_changed.connect(_rebuild)


## A grid of one side: `take` — the container's (its things are taken), else the hero's (its things are put in).
func _grid(tag: String, prefix: String, host: String, view: Dictionary, take: bool) -> ItemGrid:
	var g := ItemGrid.new(tag, prefix, 6)
	g.min_rows = 4
	var col: VBoxContainer = UiScenes.need(self, host)
	col.add_child(g)
	g.view = view
	g.view_changed.connect(_rebuild)
	g.accepts = func(drag: Dictionary) -> bool:
		var from: Dictionary = drag.get("from", {})
		return str(from.get("kind", "")) == ("things" if take else "box")
	g.dropped = func(drag: Dictionary) -> void:
		ItemGrid.with_qty(self, drag, func(n: int) -> void: _move(str(drag["item"]), n, not take))
	g.setup = func(cell: ItemCell) -> void:
		var id := cell.item
		var n := cell.qty
		cell.on_double = func() -> void: _move(id, n, take)  # the whole stack, as a click in BG3's loot
		cell.on_menu = func(at: ItemCell) -> void:
			_menu = ItemMenu.show(self, stage_rows(at.tip_title, _rows(id, n, take)) as Container, _menu)
	return g


func open(prop: String) -> void:
	prop_id = prop
	visible = true
	_rebuild()


func _move(item: String, qty: int, take: bool) -> String:
	var err := GameState.container_move(prop_id, item, qty, take)
	if not err.is_empty():
		EventBus.message.emit(tr(err))
	return err


## «Взять» and «Взять все» of the container's thing, «Положить» and «Положить всё» of the hero's.
func _rows(item: String, n: int, take: bool) -> Array:
	var rows: Array = [{"act": "move", "name": ("TakeOut_" if take else "PutIn_") + item, "label": "BTN_TAKE_OUT" if take else "BTN_PUT_IN", "qty": 1}]
	if n > 1:
		rows.append({"act": "move", "name": ("TakeStack_" if take else "PutInStack_") + item, "label": "BTN_TAKE_STACK" if take else "BTN_PUT_IN_STACK", "qty": n})
	for r: Dictionary in rows:
		r["item"] = item
		r["take"] = take
		r["why"] = "" if not GameState.is_busy() else "ABILITY_BUSY"
	return rows


func stage_rows(head: String, rows: Array) -> Control:
	return ItemMenu.stage(UiScenes.need(self, "%ChestActsBox"), head, rows, func(r: Dictionary) -> void: _move(str(r["item"]), int(r["qty"]), bool(r["take"])))


## The rows of a thing staged by name (TakeOut_rope, TakeStack_arrows, PutIn_dagger): a playtest presses them as the
## list would. `take` — the container's thing, else the hero's.
func stage(item: String, take: bool = true) -> Control:
	var grid := _box if take else _mine
	var cell := grid.find_child(grid.prefix + item, true, false) as ItemCell
	var n := cell.qty if cell != null else 1
	return stage_rows(ItemRules.display_name(Catalog.data["items"], GameState.session.items, item), _rows(item, n, take))


func _row_button(row: HBoxContainer, node_name: String, text: String, enabled: bool, action: Callable) -> Button:
	var b := UiParts.act_button(row, node_name, text, "", action)  # v0.8.4.29.6: grey while busy too
	b.disabled = b.disabled or not enabled
	return b


func _rebuild() -> void:
	if not visible or not GameState.has_session() or prop_id.is_empty():
		return
	var top: VBoxContainer = UiScenes.need(self, "%ChestTop")
	for ch in top.get_children():
		top.remove_child(ch)
		ch.queue_free()
	var head: HBoxContainer = UiScenes.need(self, "%BoxHead")
	for ch in head.get_children():
		if ch.name != "BoxCaption":
			head.remove_child(ch)
			ch.queue_free()
	var s := GameState.session
	var data := Catalog.data
	var p := ContainerRules.target(s, data, prop_id)  # a thing of the room, a body or a bag of the hero (v0.7.18.2)
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
		meta += " · " + tr("CONTAINER_OWNER").format({"name": OwnerRules.name_of(s, data, owner)})
	top.add_child(UiParts.label(null, meta, UiTheme.MUTED_LABEL))
	if is_bag:  # leave it here with what is in it
		var drop_row := HBoxContainer.new()
		top.add_child(drop_row)
		_row_button(drop_row, "DropBag", tr("BTN_DROP_BAG"), can_act and not session_busy(), func() -> String:
			visible = false
			return GameState.drop_item(prop_id))
	var locked := bool(p.get("locked", false))
	(UiScenes.need(self, "%ChestGrids") as Control).visible = not locked
	if locked:
		top.add_child(UiParts.label(null, tr("CONTAINER_LOCKED")))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		top.add_child(row)
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
		top.add_child(lrow)
		for how: String in locks:
			var h := how
			_row_button(lrow, "Lock_" + how, tr("BTN_LOCK_" + how.to_upper()), can_act, func() -> String: return GameState.container_lock(prop_id, h))
	if not contents.is_empty():  # v0.7.49.4: everything at once
		_row_button(head, "TakeAll", tr("BTN_TAKE_ALL_CONTAINER"), can_act, func() -> String: return GameState.container_take_all(prop_id))
	_box.where = {"kind": "box", "prop": prop_id}
	_box.show_items(contents)
	var mine := {}
	for id: String in s.character.get("inventory", {}):
		var free := TradeRules.sellable(s, id, data)
		if is_bag and id == str(p["kind"]):
			free -= ContainerRules.bags_of(s.character, id).size() - ContainerRules.full_bags(s.character, id)  # not into itself
		if free > 0:
			mine[id] = free
	_mine.where = {"kind": "things", "who": Being.HERO}
	_mine.show_items(mine)


func _num(x: float) -> String:
	return str(int(x)) if is_equal_approx(x, roundf(x)) else str(snappedf(x, 0.1))


func session_busy() -> bool:
	return GameState.session.in_conversation() or CombatRules.active(GameState.session)
