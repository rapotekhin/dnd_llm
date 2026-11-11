class_name GearPanel
extends ModalFrame
## The «Снаряжение» window of one who walks with the hero (v0.8.4.40; two grids as in BG3 since v0.8.4.43.6): its doll
## (DollView) and its things on the left, the hero's things on the right. A thing dragged from one grid onto the other is
## handed over (Shift asks how many), onto its doll is put on; a double click puts a thing on, the right button lists the
## acts (ItemActs, ItemMenu). Every act is Equip's through GameState: the same rules as the hero's own window.

const SCENE := "res://ui/components/gear_panel.tscn"

var who := ""
var _doll: DollView
var _mate: ItemGrid
var _hero: ItemGrid
var _menu: ActsMenu
var _mate_view := {}
var _hero_view := {}


func required() -> Dictionary:
	var nodes := super()
	nodes.merge({"%GearSplit": "HBoxContainer", "%MateDoll": "VBoxContainer", "%MateBox": "VBoxContainer", "%MateHead": "Label",
		"%MateCoins": "Label", "%HeroBox": "VBoxContainer", "%HeroHead": "Label", "%HeroCoins": "Label", "%GearActsBox": "VBoxContainer"})
	return nodes


func _ready() -> void:
	super()
	close_requested.connect(func() -> void: visible = false)
	close_x.name = "CloseGearButton"
	fill_body(UiScenes.need(self, "%GearSplit"))
	for n: Node in get_tree().get_nodes_in_group("editor_sample"):
		if is_ancestor_of(n):
			n.queue_free()
	var details := DetailsPanel.new(Vector2(0, 160), true)
	details.name = "GearDetails"
	add_child(details)
	_doll = DollView.new()
	_doll.details = details
	_doll.act.connect(_do)
	_doll.menu.connect(_open_menu)
	(UiScenes.need(self, "%MateDoll") as Control).add_child(_doll)
	_mate = _grid("Mate", "GearItem_", "%MateBox", _mate_view)
	_hero = _grid("Hero", "GearHero_", "%HeroBox", _hero_view)
	EventBus.state_changed.connect(_rebuild)
	visibility_changed.connect(_rebuild)


## A grid under its caption and coins: a drop from the other grid hands the thing over.
func _grid(tag: String, prefix: String, host: String, view: Dictionary) -> ItemGrid:
	var g := ItemGrid.new(tag, prefix, 5)
	var box: VBoxContainer = UiScenes.need(self, host)
	box.add_child(g)
	box.move_child(g, 1)
	g.view = view
	g.view_changed.connect(_rebuild)
	g.accepts = func(drag: Dictionary) -> bool:
		var from: Dictionary = drag.get("from", {})
		return str(from.get("kind", "")) == "things" and str(from.get("who", "")) != str(g.where.get("who", ""))
	g.dropped = func(drag: Dictionary) -> void:
		var to_mate := g == _mate
		ItemGrid.with_qty(self, drag, func(n: int) -> void: _do({"act": "give" if to_mate else "take", "item": str(drag["item"]), "to": who, "qty": n}, Being.HERO if to_mate else who))
	g.setup = func(cell: ItemCell) -> void:
		var whose := str(g.where.get("who", ""))
		var id := cell.item
		var rows := func() -> Array: return _rows(whose, id)
		cell.on_double = func() -> void:
			var main := ItemActs.main(rows.call())
			if not main.is_empty():
				_do(main, whose)
		cell.on_menu = func(at: ItemCell) -> void: _open_menu(at, rows.call(), whose)
	return g


func open(id: String) -> void:
	who = id
	visible = true
	_rebuild()


func _rebuild() -> void:
	if not visible or not GameState.has_session():
		return
	var s := GameState.session
	var data := Catalog.data
	if not Being.follows(s, who):
		visible = false
		return
	var name_of := WorldView.name_of(data, who)
	title.text = tr("GEAR_TITLE").format({"name": name_of})
	_doll.show_of(who)
	var c := Gear.of(s, data, who)
	_mate.where = {"kind": "things", "who": who}
	_mate.show_items(Gear.loose(c, data, s.items))
	_hero.where = {"kind": "things", "who": Being.HERO}
	_hero.show_items(Gear.loose(s.character, data, s.items))
	(UiScenes.need(self, "%MateHead") as Label).text = tr("GEAR_THINGS_OF").format({"name": name_of})
	(UiScenes.need(self, "%MateCoins") as Label).text = tr("SIDE_COINS").format({"coins": Money.format(Gear.coins(s, data, who))})
	(UiScenes.need(self, "%HeroHead") as Label).text = tr("GEAR_HERO_THINGS")
	(UiScenes.need(self, "%HeroCoins") as Label).text = tr("SIDE_COINS").format({"coins": Money.format(Gear.coins(s, data, Being.HERO))})


## A thing's acts in this window: the companion's own (put on, give back), the hero's — only to hand to this one.
func _rows(whose: String, item: String) -> Array:
	var rows := ItemActs.of(GameState.session, Catalog.data, whose, item)
	if whose != Being.HERO:
		return rows
	return rows.filter(func(r: Dictionary) -> bool: return str(r["act"]) == "give" and str(r.get("to", "")) == who)


func _do(row: Dictionary, whose: String = "") -> String:
	var err := GameState.item_act(row, who if whose.is_empty() else whose)
	if not err.is_empty():
		EventBus.message.emit(tr(err))
	return err


func _open_menu(cell: Control, rows: Array, whose: String = "") -> void:
	var on := who if whose.is_empty() else whose
	var box := ItemMenu.stage(UiScenes.need(self, "%GearActsBox"), str(cell.get("tip_title")) if cell != null else "", rows,
		func(r: Dictionary) -> void: _do(r, on))
	_menu = ItemMenu.show(self, box as Container, _menu)


## The acts of a thing staged by name (Equip_main_hand_longsword, GearTake_dagger, Give_<who>_longsword): a playtest
## presses them as the list would. `whose` — the hero's things or the companion's.
func stage(item: String, whose: String = "") -> Control:
	var on := who if whose.is_empty() else whose
	var s := GameState.session
	return ItemMenu.stage(UiScenes.need(self, "%GearActsBox"), ItemRules.display_name(Catalog.data["items"], s.items, item), _rows(on, item),
		func(r: Dictionary) -> void: _do(r, on))
