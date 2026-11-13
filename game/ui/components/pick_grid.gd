class_name PickGrid
extends VBoxContainer
## «Pick N of these» as in BG3 (v0.8.4.43.34, the author: «сетки иконок вместо списков»): the list's name with «Выбрано 1
## из 3» beside it, a row of the picked ones over it — a picked icon or an empty cell for each pick left, a click on a picked
## one takes it back — and the choices as icons by groups (a spell's circle) under it; what a choice is shows as its card
## at the cursor (`IconSlot`), the right button pins it. One part for the character creation and the level-up: a choice
## of an icon (a spell, a feature, a subclass) is a tile here; a choice of one by its picture and name (a race, a class) is
## a row of `rows`. `changed` gives the whole new list of picks; a single pick (`limit` 1) switches instead of adding.
## A list of few choices told apart by their names (a fighting style, a subclass) is `named`: its name under each icon.

signal changed(picked: Array)

const TILE := 72
const ROW := Vector2(200, 60)
const NAMED := 112  # the width of an icon with its name under it

var _picked: Array = []
var _limit := 0
var _fixed: Array = []
var _named := false


## A list of `options` [{id, ref, label, card?, tip?, group?}] picked up to `limit`: `picked` — the picks now, `fixed` — shown
## picked and locked, `blocked` — taken in another list (shown, closed); a tile's node is `prefix` + its id.
static func make(title_text: String, options: Array, limit: int, picked: Array, fixed: Array = [], blocked: Array = [], prefix := "Pick_", named := false) -> PickGrid:
	var g := PickGrid.new()
	g._picked = picked.duplicate()
	g._limit = limit
	g._fixed = fixed
	g._named = named
	g.add_theme_constant_override("separation", 8)
	g._head(title_text)
	if limit > 1:
		g._chosen_row(options)
	var flow: HFlowContainer = null
	var group := ""
	for o: Dictionary in options:
		if flow == null or str(o.get("group", "")) != group:
			group = str(o.get("group", ""))
			if group != "":
				UiParts.label(g, group, UiTheme.MUTED_LABEL)
			flow = HFlowContainer.new()
			flow.add_theme_constant_override("h_separation", 12 if named else 8)
			flow.add_theme_constant_override("v_separation", 8)
			g.add_child(flow)
		var tile := g._tile(o, prefix, blocked)
		flow.add_child(g._with_name(tile, str(o["label"])) if named else tile)
	return g


## The rows of a single choice by a picture and a name (`options` [{id, label, ref?, picture?, tip?}]); `on_pick` gets the id.
static func rows(options: Array, current: String, prefix: String, on_pick: Callable, info: DetailsPanel = null, columns := 3) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	for o: Dictionary in options:
		var b := Button.new()
		b.name = prefix + str(o["id"])
		b.text = str(o["label"])
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		b.toggle_mode = true
		b.button_pressed = current == str(o["id"])
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = ROW
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL  # the rows share the column: a long name is not cut
		b.add_theme_font_size_override("font_size", UiTheme.SIZE_UI - 2)
		var path := str(o.get("picture", ""))
		if path.is_empty() and str(o.get("ref", "")) != "":
			path = str(IconRules.of(Catalog.data, {}, str(o["ref"])).get("path", ""))
		var tex := IconSlot.texture(path)
		if tex != null:
			b.icon = tex
			b.expand_icon = true
			b.add_theme_constant_override("icon_max_width", int(ROW.y) - 12)
			b.add_theme_constant_override("h_separation", 10)
		if info != null and str(o.get("tip", "")) != "":
			InfoBox.hook(b, info, b.text, str(o["tip"]))
		b.pressed.connect(func() -> void: on_pick.call(str(o["id"])))
		grid.add_child(b)
	return grid


## The name of the list and how many are picked of how many.
func _head(title_text: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	add_child(row)
	UiParts.label(row, title_text.trim_suffix(":"), UiTheme.ACCENT_LABEL)
	if _limit > 1:
		var n := _picked.size()
		var count := UiParts.label(row, tr("PICK_COUNT").format({"n": n, "m": _limit}), UiTheme.OK_LABEL if n >= _limit else UiTheme.WARN_LABEL, true)
		count.name = "PickCount"
		count.size_flags_horizontal = Control.SIZE_SHRINK_END


## The picked ones in a row, an empty cell for each pick left; a click on a picked one takes it back.
func _chosen_row(options: Array) -> void:
	var row := HBoxContainer.new()
	row.name = "Chosen"
	row.add_theme_constant_override("separation", 6)
	add_child(row)
	var by_id := {}
	for o: Dictionary in options:
		by_id[str(o["id"])] = o
	for id: Variant in _picked:
		var o: Dictionary = by_id.get(str(id), {})
		if o.is_empty():
			continue
		var cell := IconSlot.make(str(o.get("ref", "")), str(o["label"]), TILE - 8)
		cell.name = "Chosen_" + str(id)
		_card_of(cell, o)
		cell.pressed.connect(func() -> void: _pick(id, false))
		row.add_child(cell)
	for i in maxi(0, _limit - _picked.size()):
		var empty := IconSlot.new()
		empty.custom_minimum_size = Vector2(TILE - 8, TILE - 8)
		empty.disabled = true
		empty.modulate = Color(1, 1, 1, 0.4)
		empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(empty)


## An icon with its name under it (`named`).
func _with_name(tile: IconSlot, text: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(NAMED, 0)
	box.add_theme_constant_override("separation", 4)
	tile.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(tile)
	var l := UiParts.label(box, text, UiTheme.MUTED_LABEL if tile.disabled and not tile.button_pressed else "")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(NAMED, 0)
	l.add_theme_font_size_override("font_size", UiTheme.SIZE_SMALL)
	if tile.button_pressed:
		l.add_theme_color_override("font_color", UiTheme.ACCENT_BRIGHT)
	return box


func _tile(o: Dictionary, prefix: String, blocked: Array) -> IconSlot:
	var id: Variant = o["id"]
	var cell := IconSlot.make(str(o.get("ref", "")), str(o["label"]), TILE)
	cell.name = prefix + str(id)
	cell.toggle_mode = true
	_card_of(cell, o)
	if _fixed.has(id):
		cell.button_pressed = true
		cell.disabled = true
		return cell
	if blocked.has(id):
		cell.disabled = true
		cell.tip_body = tr("CC_TAKEN_ELSEWHERE") + ("\n\n" + cell.tip_body if cell.tip_body != "" else "")
		return cell
	cell.button_pressed = _picked.has(id)
	cell.disabled = not _picked.has(id) and _limit > 1 and _picked.size() >= _limit
	cell.toggled.connect(func(on: bool) -> void: _pick(id, on))
	return cell


## What a choice is at the cursor: its card of `CardInfo`, else its name and words.
func _card_of(cell: IconSlot, o: Dictionary) -> void:
	if o.get("card", {}) is Dictionary and not (o.get("card", {}) as Dictionary).is_empty():
		cell.set_card(o["card"])
	else:
		cell.tip_title = str(o["label"])
		cell.tip_body = str(o.get("tip", ""))


func _pick(id: Variant, on: bool) -> void:
	var next := _picked.duplicate()
	if on and not next.has(id):
		if _limit == 1:
			next = [id]
		elif next.size() < _limit:
			next.append(id)
	elif not on:
		next.erase(id)
	if next != _picked:
		_picked = next
		changed.emit(next)
