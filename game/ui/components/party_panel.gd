class_name PartyPanel
extends ModalFrame
## The party window on Tab (v0.8.4.44.10, as in BG3; the author: «на кнопку Tab … открывались одновременно в ряд
## инвентари всех спутников и игрока для удобного перемещения предметов между инвентарями»): a column for the hero and
## each one who walks with it (AllyRules.party, those who carry things) — the face, the name and the coins, the load and
## its most, the grid of all its things: the worn and the belt's too, each with a small mark of its place (v0.8.4.44.11,
## the author: «помечать маленькой иконкой на предмете, что он на кукле или на поясе»); handed over, it goes into the
## other's pack (Equip.hand takes it off first). A thing dragged from one column onto another is handed over (a stack asks how many
## by the slider, as in the trade), a double click does its main act, the right button lists its acts (ItemActs,
## ItemMenu). Every move is Equip.hand's through GameState.item_act: the same rules as the «Снаряжение» window.

const SCENE := "res://ui/components/party_panel.tscn"
const COLUMNS := 5  ## cells in a row of a member's grid
const FACE := 52

var _order: Array[String] = []  # the members shown, in their order: a change builds the columns anew
var _cols := {}  # id → {grid, face, name, coins, weight, bar}
var _views := {}  # id → its grid's filter and sort, kept while the window lives
var _menu: ActsMenu


func required() -> Dictionary:
	var nodes := super()
	nodes.merge({"%PartySplit": "VBoxContainer", "%PartyCols": "HBoxContainer", "%PartyAlone": "Label", "%PartyActsBox": "VBoxContainer"})
	return nodes


func _ready() -> void:
	super()
	close_requested.connect(func() -> void: visible = false)
	close_x.name = "ClosePartyButton"
	fill_body(UiScenes.need(self, "%PartySplit"))
	for n: Node in get_tree().get_nodes_in_group("editor_sample"):
		if is_ancestor_of(n):
			n.queue_free()
	EventBus.state_changed.connect(_rebuild)
	visibility_changed.connect(_rebuild)


## Opens it, or says why not: in a fight Tab is the next target and nothing is handed over.
func open() -> String:
	if not GameState.has_session():
		return "PROPERTY_NOT_NOW"
	if CombatRules.active(GameState.session):
		return "GEAR_NOT_IN_COMBAT"
	visible = true
	_rebuild()
	return ""


## The ids of those whose things are shown: the hero and its followers (a summon or a beast carries nothing of its own).
static func members(s: GameSession, data: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for m: Dictionary in AllyRules.party(s, data):
		var ref := str(m["ref"])
		if ref.is_empty():
			out.append(Being.HERO)
		elif ref.begins_with("npc:"):
			out.append(ref.substr(4))
	return out


func _rebuild() -> void:
	if not visible or not GameState.has_session():
		return
	var s := GameState.session
	var data := Catalog.data
	if CombatRules.active(s):
		visible = false
		return
	var ids := members(s, data)
	if ids != _order:
		_build(ids)
	(UiScenes.need(self, "%PartyAlone") as Control).visible = ids.size() < 2
	for id: String in ids:
		_fill(s, data, id)


## The columns anew, one for each member.
func _build(ids: Array[String]) -> void:
	_order = ids.duplicate()
	_cols.clear()
	var host: HBoxContainer = UiScenes.need(self, "%PartyCols")
	for ch in host.get_children():
		host.remove_child(ch)
		ch.queue_free()
	for id: String in ids:
		host.add_child(_column(id))


func _column(id: String) -> PanelContainer:
	var box := PanelContainer.new()
	box.name = "PartyCol_" + id
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.PANEL_RAISED, UiTheme.BORDER, 1, 10, 4))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	box.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	col.add_child(head)
	var face := Portrait.of("", FACE)
	face.name = "PartyFace_" + id
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(face)
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_child(names)
	var name_label := UiParts.label(names, "", UiTheme.CAPTION_LABEL)
	name_label.name = "PartyName_" + id
	var coins := UiParts.label(names, "", UiTheme.MUTED_LABEL)
	coins.name = "PartyCoins_" + id
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)
	var weight := UiParts.label(row, "", UiTheme.MUTED_LABEL)
	weight.name = "PartyWeight_" + id
	var bar := ProgressBar.new()
	bar.name = "PartyWeightBar_" + id
	bar.custom_minimum_size = Vector2(0, 10)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(bar)
	var grid := ItemGrid.new("Party_" + id, "PartyItem_%s_" % id, COLUMNS)
	grid.min_rows = 6
	grid.min_columns = COLUMNS
	grid.where = {"kind": "things", "who": id}
	if not _views.has(id):
		_views[id] = {}
	grid.view = _views[id]
	grid.view_changed.connect(_rebuild)
	grid.accepts = func(drag: Dictionary) -> bool:
		var from: Dictionary = drag.get("from", {})
		return str(from.get("kind", "")) == "things" and str(from.get("who", "")) != id
	grid.dropped = func(drag: Dictionary) -> void: give(str((drag["from"] as Dictionary)["who"]), id, str(drag["item"]), int(drag.get("qty", 1)))
	grid.setup = func(cell: ItemCell) -> void:
		var item := cell.item
		cell.set_place(place_of(GameState.session, Catalog.data, id, item))
		cell.on_double = func() -> void:
			var main := ItemActs.main(_rows(id, item))
			if not main.is_empty():
				_do(main, id)
		cell.on_menu = func(at: ItemCell) -> void:
			_menu = ItemMenu.show(self, _stage_rows(at.tip_title, _rows(id, item), id), _menu)
	col.add_child(grid)
	_cols[id] = {"grid": grid, "face": face, "name": name_label, "coins": coins, "weight": weight, "bar": bar}
	return box


func _fill(s: GameSession, data: Dictionary, id: String) -> void:
	var parts: Dictionary = _cols[id]
	var who := Sheet.who(s, data, id)
	var name_text := CreatureCard.name_of(s, data, who)
	(parts["face"] as Portrait).show_of(s, data, who, name_text)
	(parts["name"] as Label).text = name_text
	(parts["coins"] as Label).text = tr("SIDE_COINS").format({"coins": Money.format(Gear.coins(s, data, id))})
	var c := Gear.of(s, data, id)  # a person's pockets filled the first time it is looked into
	UiParts.weight(parts["weight"], parts["bar"], Sheet.carried(s, data, who), Sheet.capacity(s, data, who))
	var all := {}
	for item: String in c.get("inventory", {}):
		if int(c["inventory"][item]) > 0:
			all[item] = int(c["inventory"][item])
	(parts["grid"] as ItemGrid).show_items(all)


## The icon of where a copy of `item` is on `id`: the doll's slot or the hands (`slots/<slot>`), the belt (`slots/belt`); "" — loose.
static func place_of(s: GameSession, data: Dictionary, id: String, item: String) -> String:
	var c := Gear.of(s, data, id)
	for at: Array in CharacterRules.worn_at(c, item).slice(0, 1):
		return "slots/" + str(at[0])
	return "slots/belt" if ItemRules.on_belt(c, data, s.items, item) else ""


## `qty` of `item` from one member to another (`ask` — the slider for a stack, as in the trade); a refusal in the chat.
func give(from: String, to: String, item: String, qty: int, ask := true) -> void:
	ItemGrid.with_qty(self, {"item": item, "qty": qty}, func(n: int) -> void:
		_do({"act": "give", "item": item, "to": to, "qty": n}, from), ask)


## A thing's acts in this window: what the character window gives its owner, but a bag's or a letter's own window.
func _rows(whose: String, item: String) -> Array:
	return ItemActs.of(GameState.session, Catalog.data, whose, item).filter(func(r: Dictionary) -> bool:
		return not str(r.get("act", "")) in ["open", "letter"])


func _do(row: Dictionary, whose: String) -> String:
	var err := GameState.item_act(row, whose)
	if not err.is_empty():
		EventBus.message.emit(tr(err))
	elif str(row.get("act", "")) == "use":
		visible = false  # the master tells it in the chat
	return err


func _stage_rows(head: String, rows: Array, whose: String) -> Container:
	return ItemMenu.stage(UiScenes.need(self, "%PartyActsBox"), head, rows, func(r: Dictionary) -> void: _do(r, whose)) as Container


## The acts of a member's thing staged by name (Give_<who>_rope, GearTake_dagger, Equip_main_hand_longsword…): a playtest
## presses them as the list would.
func stage(whose: String, item: String) -> Container:
	return _stage_rows(ItemRules.display_name(Catalog.data["items"], GameState.session.items, item), _rows(whose, item), whose)


## A member's grid, for a playtest's drag.
func grid_of(id: String) -> ItemGrid:
	return _cols.get(id, {}).get("grid") as ItemGrid
