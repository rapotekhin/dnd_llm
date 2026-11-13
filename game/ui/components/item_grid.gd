class_name ItemGrid
extends VBoxContainer
## The grid of things (v0.8.4.43.6, the inventory as in BG3): over it the group filters as icons, the search, the sort and
## its order in one row; under it the cells — a thing's icon, the stack's number, its rarity's frame, the rest at the
## cursor — padded with empty ones to whole rows. One grid for the character window, a chest or a body, the trade and a
## companion's things; the owner says what is in it (`show_items`), what its cells do (`setup`) and what a drop on it
## does (`accepts`, `dropped`). The groups, the sort and the search are ItemGroups'. A `bare` grid has no row over it:
## the two columns of a deal in the trade (v0.8.4.43.12). How many of a stack a drop moves — `with_qty`, a slider.

signal view_changed  ## a filter, the sort or its order changed: the owner keeps it when it is the hero's

var tag := "Inv"  ## the names of its controls: «InvGroup_all», «InvSearch», «InvSort»…
var prefix := "Item_"  ## a cell's name before the thing's id
var columns := 8
var min_rows := 5
var min_columns := 4
var bare := false:  ## no filters, search or sort over the cells
	set(v):
		bare = v
		if _bar != null:
			_bar.visible = not v
const CELL := 64  ## a thing's cell, larger than a plain icon (v0.8.4.43.35, the author: «в панели персонажа сделать иконки больше»)
var cell_side := CELL
var where: Dictionary = {}  ## the `from` its cells carry
var view: Dictionary = {}  ## group, sort, reverse — the hero's are SaveManager.inventory_view
var setup := Callable()  ## (cell: ItemCell) — the owner's double click, menu and card line
var accepts := Callable()  ## (drag: Dictionary) -> bool
var dropped := Callable()  ## (drag: Dictionary) -> void
var _find := ""
var _bar: HBoxContainer
var _filters: HFlowContainer
var _search: LineEdit
var _sort: OptionButton
var _reverse: Button
var _scroll: ScrollContainer
var _cells: GridContainer
var shown: Array[String] = []  ## the ids in the cells now, in their order


func _init(grid_tag: String = "Inv", cell_prefix: String = "Item_", cols: int = 8) -> void:
	tag = grid_tag
	prefix = cell_prefix
	columns = cols
	name = tag + "Grid"
	add_theme_constant_override("separation", 6)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var bar := HBoxContainer.new()
	bar.name = tag + "Bar"
	bar.add_theme_constant_override("separation", 4)
	add_child(bar)
	_bar = bar
	_filters = HFlowContainer.new()  # the icons wrap onto a second line rather than widen the window
	_filters.name = tag + "Filters"
	_filters.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_filters.size_flags_stretch_ratio = 1.6
	_filters.add_theme_constant_override("h_separation", 2)
	_filters.add_theme_constant_override("v_separation", 2)
	bar.add_child(_filters)
	_search = LineEdit.new()
	_search.name = tag + "Search"
	_search.placeholder_text = "INV_SEARCH"
	_search.clear_button_enabled = true
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.custom_minimum_size = Vector2(120, 0)
	_search.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_search.text_changed.connect(func(t: String) -> void:
		_find = t
		view_changed.emit())
	bar.add_child(_search)
	_sort = OptionButton.new()
	_sort.name = tag + "Sort"
	_sort.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_sort.tooltip_text = "INV_SORT_TIP"
	_sort.fit_to_longest_item = false
	_sort.custom_minimum_size = Vector2(132, 0)
	_sort.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_sort.clip_text = true
	_sort.item_selected.connect(func(i: int) -> void:
		view["sort"] = str(_sort.get_item_metadata(i))
		view_changed.emit())
	bar.add_child(_sort)
	_reverse = Button.new()
	_reverse.name = tag + "Reverse"
	_reverse.text = "⇅"
	_reverse.toggle_mode = true
	_reverse.tooltip_text = "INV_REVERSE_TIP"
	_reverse.custom_minimum_size = Vector2(36, 0)
	_reverse.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_reverse.pressed.connect(func() -> void:
		view["reverse"] = not bool(view.get("reverse", false))
		view_changed.emit())
	bar.add_child(_reverse)
	_scroll = ScrollContainer.new()
	_scroll.name = tag + "List"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_scroll)
	_cells = GridContainer.new()
	_cells.name = tag + "Cells"
	_cells.columns = columns
	_cells.add_theme_constant_override("h_separation", 4)
	_cells.add_theme_constant_override("v_separation", 4)
	_cells.mouse_filter = Control.MOUSE_FILTER_PASS
	_scroll.add_child(_cells)


func _ready() -> void:
	var sorts := ItemGroups.sorts(Catalog.data)
	var keys := sorts.keys()
	for i in keys.size():
		_sort.add_item(str(sorts[keys[i]]), i)
		_sort.set_item_metadata(i, str(keys[i]))


## Shows the things of `inv` {id: qty} by the filter, the search and the sort. `owner_c` — whose sheet a thing is compared to.
func show_items(inv: Dictionary) -> void:
	var data := Catalog.data
	var items: Dictionary = GameState.session.items
	var group := _group(inv)
	var sort := str(view.get("sort", ItemGroups.TYPE))
	if not ItemGroups.sorts(data).has(sort):
		sort = ItemGroups.TYPE
	for i in _sort.item_count:
		if str(_sort.get_item_metadata(i)) == sort:
			_sort.select(i)
	_reverse.set_pressed_no_signal(bool(view.get("reverse", false)))
	for ch in _cells.get_children():
		_cells.remove_child(ch)
		ch.queue_free()
	shown = ItemGroups.view(data, items, inv, group, sort, _find, bool(view.get("reverse", false)))
	for id: String in shown:
		var cell := ItemCell.of(IconRules.ref("items", id), id, int(inv[id]), where, cell_side)
		cell.name = prefix + id
		cell.area = self
		cell.tip_title = ItemRules.display_name(data["items"], items, id)
		cell.text = line(id, int(inv[id]))
		cell.tooltip_text = cell.text if not cell.text.is_empty() else cell.tip_title
		cell.set_card(CardInfo.item(GameState.session.character, data, items, id))
		if setup.is_valid():
			setup.call(cell)
		_cells.add_child(cell)
	_pad()
	var none_name := tag + "None"
	var old := get_node_or_null(none_name)
	if old != null:
		remove_child(old)
		old.queue_free()
	if shown.is_empty() and not inv.is_empty():  # the search found nothing
		var nl := UiParts.label(self, tr("INV_NONE"), UiTheme.MUTED_LABEL)
		nl.name = none_name
		move_child(nl, 1)


## The empty cells of the grid to whole rows, as in BG3.
func _pad() -> void:
	for ch in _cells.get_children():
		if ch is Panel:
			_cells.remove_child(ch)
			ch.queue_free()
	var pad := maxi(min_rows * columns, int(ceil(float(shown.size()) / columns)) * columns) - shown.size()
	_scroll.custom_minimum_size.y = min_rows * (cell_side + 4)  # a window that shrinks to its content still shows the rows
	for i in pad:
		var empty := Panel.new()
		empty.custom_minimum_size = Vector2(cell_side, cell_side)
		empty.mouse_filter = Control.MOUSE_FILTER_PASS
		empty.add_theme_stylebox_override("panel", UiTheme.box(Color(0, 0, 0, 0.25), UiTheme.BORDER.darkened(0.35), 1, 0, 3))
		_cells.add_child(empty)


## As many columns as its width holds: the grid fills its side of a window.
func _notification(what: int) -> void:
	if what != NOTIFICATION_RESIZED or _cells == null:
		return
	var fit := maxi(min_columns, int((size.x - 16.0 + 4.0) / (cell_side + 4.0)))
	if fit != columns:
		columns = fit
		_cells.columns = fit
		_pad()


## «2 фнт · 5 зм» of a stack; the price of a thing not identified is «?».
static func line(id: String, n: int) -> String:
	var data := Catalog.data
	var items: Dictionary = GameState.session.items
	var w := ItemGroups.weight(data, items, id, n)
	var v := ItemGroups.value(data, items, id, n)
	var parts: Array[String] = []
	if w > 0.0:
		parts.append(TranslationServer.translate("INV_WEIGHT").format({"n": str(int(w)) if is_equal_approx(w, roundf(w)) else String.num(w, 2)}))
	parts.append("?" if v < 0 else Money.format(v) if v > 0 else "—")
	return " · ".join(parts)


## The group icons with how many kinds each holds; the group shown ("" — all; a group emptied shows all).
func _group(inv: Dictionary) -> String:
	for ch in _filters.get_children():
		_filters.remove_child(ch)
		ch.queue_free()
	var data := Catalog.data
	var counts := ItemGroups.counts(data, GameState.session.items, inv)
	var group := str(view.get("group", ItemGroups.ALL))
	if not counts.has(group):
		group = ItemGroups.ALL
	var add := func(gid: String, ref: String, title: String, n: int) -> void:
		var b := IconSlot.make(ref, title, 34)
		b.name = tag + "Group_" + (gid if not gid.is_empty() else "all")
		b.toggle_mode = true
		b.button_pressed = gid == group
		b.badge = str(n)
		b.tip_title = title
		b.tooltip_text = "%s · %d" % [title, n]
		b.pressed.connect(func() -> void:
			view["group"] = gid
			view_changed.emit())
		_filters.add_child(b)
	add.call(ItemGroups.ALL, "ui/all", tr("INV_ALL"), inv.size())
	for gid: String in counts:
		add.call(gid, IconRules.ref("groups", gid), ItemGroups.name_of(data, gid), int(counts[gid]))
	return group


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	return data is Dictionary and (data as Dictionary).has("item") and (data as Dictionary).get("from") != where \
		and accepts.is_valid() and bool(accepts.call(data))


func _drop_data(_at: Vector2, data: Variant) -> void:
	if dropped.is_valid():
		dropped.call(data)


## The stack a drag carries, or the question how many of it (as in BG3): with Shift, or always with `ask` (a deal in the
## trade, the author: «полоску, сколько из них переместить»). `done` gets the number.
static func with_qty(near: Control, drag: Dictionary, done: Callable, ask := false) -> void:
	if (ask or bool(drag.get("split", false))) and int(drag.get("qty", 1)) > 1:
		ask_qty(near, int(drag["qty"]), done)
	else:
		done.call(maxi(1, int(drag.get("qty", 1))))


## How many of a stack: a slider with the number beside it and «OK» (Enter in the number too), `done` gets it.
static func ask_qty(near: Control, most: int, done: Callable) -> void:
	var pop := PopupPanel.new()
	pop.name = "QtyBox"
	pop.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.PANEL_RAISED, UiTheme.ACCENT, 1, 12, 4))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	pop.add_child(col)
	UiParts.label(col, TranslationServer.translate("QTY_HOW_MANY"), UiTheme.CAPTION_LABEL).autowrap_mode = TextServer.AUTOWRAP_OFF  # a wrapping line makes a popup tall
	var slider := HSlider.new()
	slider.name = "QtySlider"
	slider.min_value = 1
	slider.max_value = most
	slider.step = 1
	slider.value = most
	slider.tick_count = most if most <= 10 else 0  # a mark per thing of a small stack
	slider.ticks_on_borders = true
	slider.custom_minimum_size = Vector2(280, 28)
	col.add_child(slider)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)
	var spin := SpinBox.new()
	spin.name = "QtySpin"
	spin.min_value = 1
	spin.max_value = most
	spin.value = most
	spin.suffix = "/ %d" % most
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spin)
	slider.value_changed.connect(func(v: float) -> void: spin.set_value_no_signal(v))
	spin.value_changed.connect(func(v: float) -> void: slider.set_value_no_signal(v))
	var ok := Button.new()
	ok.name = "QtyOk"
	ok.text = "BTN_OK"
	ok.custom_minimum_size = Vector2(72, 0)
	var typed := [false]  # the number typed in by hand: its text, not yet the value (Godot updates the text later)
	spin.get_line_edit().text_changed.connect(func(_t: String) -> void: typed[0] = true)
	var finish := func() -> void:
		if typed[0]:
			spin.apply()
		pop.hide()
		done.call(int(spin.value))
	ok.pressed.connect(finish)
	spin.get_line_edit().text_submitted.connect(func(_t: String) -> void: finish.call())
	row.add_child(ok)
	pop.popup_hide.connect(pop.queue_free)
	near.add_child(pop)
	var box := Vector2i(320, 136)
	var at := Vector2i(near.get_global_mouse_position()).clamp(Vector2i.ZERO, Vector2i(near.get_viewport_rect().size) - box)  # never past the screen's edge
	pop.popup(Rect2i(at, box))
	slider.grab_focus.call_deferred()
