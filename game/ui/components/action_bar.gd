class_name ActionBar
extends PanelContainer
## The hotbar as in BG3 (v0.8.4.43, the author's layout of 2026-11-10), one in a fight and out of it, left to right:
## the hero's portrait — the weapons of both hands with the set switch under them — the grid of icons in rows, cut into
## sections by dividers that move — the round button (end the turn in a fight, wait out of it) — the short and the long
## rest. Over the grid the counters: the action, the bonus action, the reaction, the move, the class's own stocks, the
## spell slots by circle (a press picks the circle in a fight); under it the tabs of kinds. Only icons: what a cell is
## shows at the cursor. Cells go where `HotbarLayout` puts them; one is dragged to another slot, off the bar, or onto it
## from the sheet; the layout is the profile's (SaveManager.hotbar). The side panel fills the peace's cells, `FightUi`
## the fight's: each into `section(key)`, then `tidy()`; the passives (v0.8.4.43.7) the bar lays itself, in both. In a
## conversation the bar gives way to the acts with the partner.
## v0.8.4.43.14, as in BG3: one layout in a fight and out of it (`HotbarLayout.BAR`), a cell by one key in both
## (`HotbarLayout.key_of`); the fight's acts have a section of their own, «Боевые». What the other mode offers stands in its
## slot grey with why: out of a fight the fight's acts (`rules.combat.bar`) «только в бою», in a fight the place's acts
## «не в бою». A cell is dragged in any tab of kinds; a divider follows the mouse and snaps to the nearest column.
## v0.8.4.43.33 (the author: «много пустого места», «иконки мелкие»): larger cells with an icon of its own frame laid edge
## to edge (IconSlot), the empty slots faint, no scroll bar beside the grid, the tabs of kinds in the drawn tab's frame,
## the end of the turn an hourglass as in BG3.

signal circle_picked(circle: int)

## The keys owners fill → [mode, kind of the grid].
const GROUP := "hotbar"  ## the bar's group: a window that keeps it in sight (the sheet) finds it
const KEYS := {"BAR_PLACE": ["peace", "common"], "BAR_CLASS": ["peace", "class"], "BAR_ITEMS": ["peace", "items"],
	"BAR_DEEDS": ["peace", "deeds"], "BAR_REST": ["peace", "rest"], "COMBAT_TAB_WEAPONS": ["fight", "combat"],
	"COMBAT_TAB_COMMON": ["fight", "combat"], "COMBAT_TAB_SPELLS": ["fight", "class"], "COMBAT_TAB_FEATURES": ["fight", "class"],
	"COMBAT_TAB_ITEMS": ["fight", "items"], "COMBAT_TAB_WATCH": ["fight", "combat"], "BAR_PASSIVE": ["both", "passive"]}
const PLACE := "BAR_PLACE"
const CLASS := "BAR_CLASS"
const ITEMS := "BAR_ITEMS"
const DEEDS := "BAR_DEEDS"
const REST := "BAR_REST"
const PASSIVE := "BAR_PASSIVE"
const KIND_TITLES := {"common": "BAR_KIND_COMMON", "combat": "BAR_KIND_COMBAT", "class": "BAR_KIND_CLASS", "items": "BAR_KIND_ITEMS",
	"deeds": "BAR_DEEDS", "passive": "BAR_KIND_PASSIVE"}
const TABS := ["", "common", "combat", "class", "items", "deeds", "passive"]
const CELL := 64
const GAP := 4
const ROMAN := ["", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX"]

var windows: GridContainer  ## the sheet, the map, the journal, the menu — icons in the corner
var talk: HBoxContainer  ## the acts of a conversation
var talk_acts: VBoxContainer
var end_turn: Button  ## the round button of a fight
var picked_circle := 0  ## the circle the next spell is cast at in a fight; 0 — the lowest that fits
## Whose bar it is (v0.8.4.43.11): the hero, or in a fight the one of its party whose turn the player plays — its face, its
## hands and sets, its points, stocks and slots, its passives. `FightUi` sets it before it fills the cells; out of a fight
## the hero.
var who: Dictionary = Sheet.HERO

var _body: HBoxContainer
var _portrait: Portrait
var _hands: GridContainer
var _sets: HBoxContainer
var _counters: HBoxContainer
var _centre: VBoxContainer  # the counters, the grid and the tabs
var _rows_box: VBoxContainer  # «+» and «−» of the rows
var _grid_scroll: ScrollContainer
var _grid: HBoxContainer
var _tabs: HBoxContainer
var _round: CenterContainer
var _rests: VBoxContainer
var _stage := {}  # key of KEYS → hidden Container the owner fills
var _laid_cols := -1  # the columns of the last laying
var _park: Control  # hidden: the cells not on the grid now wait here, never freed with a slot
var _fight := false
var _talking := false
var _filter := ""  # a kind shown alone, "" — the player's own bar
var _toggles := {}  # id of rules.toggles → its cell, kept while the hero has it
var _ghosts: Array[Control] = []  # the other mode's acts drawn grey this laying, freed by the next
var _drawn_kinds := {}  # the kinds of the sections on the bar now: their tabs
var _dragging_divider := false  # a divider in the hand: the grid is not laid again under it


func _init() -> void:
	name = "ActionBar"
	add_to_group(GROUP)
	_park = Control.new()
	_park.name = "Parked"
	_park.visible = false
	add_child(_park)
	theme_type_variation = UiTheme.CARD
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	add_child(col)
	_body = HBoxContainer.new()
	_body.name = "Hotbar"
	_body.add_theme_constant_override("separation", 10)
	col.add_child(_body)
	_portrait = Portrait.of("", 112)  # one drawing with the left column's portraits (v0.8.4.43.4)
	_portrait.name = "HeroPortrait"
	_portrait.numbers = true
	_portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_body.add_child(_portrait)
	var weapons := VBoxContainer.new()
	weapons.add_theme_constant_override("separation", GAP)
	weapons.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_body.add_child(weapons)
	_hands = GridContainer.new()
	_hands.name = "Hands"
	_hands.columns = 2
	_hands.add_theme_constant_override("h_separation", GAP)
	weapons.add_child(_hands)
	_sets = HBoxContainer.new()
	_sets.name = "Sets"
	_sets.add_theme_constant_override("separation", GAP)
	weapons.add_child(_sets)
	var centre := VBoxContainer.new()
	centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	centre.add_theme_constant_override("separation", 4)
	_body.add_child(centre)
	_centre = centre
	_counters = HBoxContainer.new()
	_counters.name = "Counters"
	_counters.add_theme_constant_override("separation", 14)
	_counters.custom_minimum_size = Vector2(0, 26)
	_counters.alignment = BoxContainer.ALIGNMENT_CENTER
	centre.add_child(_counters)
	var grid_row := HBoxContainer.new()
	grid_row.add_theme_constant_override("separation", 4)
	grid_row.alignment = BoxContainer.ALIGNMENT_CENTER
	centre.add_child(grid_row)
	_grid_scroll = ScrollContainer.new()
	_grid_scroll.name = "Cells"
	_grid_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_grid_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER  # the rows a wheel away: no bar beside the grid
	_grid_scroll.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN  # as wide as its cells: the bar hugs them (v0.8.4.43.33)
	grid_row.add_child(_grid_scroll)
	_grid = HBoxContainer.new()
	_grid.name = "Grid"
	_grid.add_theme_constant_override("separation", 0)
	_grid_scroll.add_child(_grid)
	var rows := VBoxContainer.new()  # more or fewer rows of slots, as the BG3 forum asked
	_rows_box = rows
	rows.add_theme_constant_override("separation", 2)
	grid_row.add_child(rows)
	for spec: Array in [["RowsMore", "+", 1, "BAR_ROWS_MORE"], ["RowsLess", "−", -1, "BAR_ROWS_LESS"]]:
		var b := Button.new()
		b.name = spec[0]
		b.text = spec[1]
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = spec[3]
		b.custom_minimum_size = Vector2(22, 22)
		var d: int = spec[2]
		b.pressed.connect(func() -> void:
			HotbarLayout.set_rows(SaveManager.hotbar, HotbarLayout.rows(SaveManager.hotbar) + d)
			SaveManager.save_settings()
			_relay())
		rows.add_child(b)
	_tabs = HBoxContainer.new()
	_tabs.name = "KindTabs"
	_tabs.add_theme_constant_override("separation", 6)
	_tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	centre.add_child(_tabs)
	_round = CenterContainer.new()
	_round.name = "Round"
	_round.custom_minimum_size = Vector2(92, 0)
	_body.add_child(_round)
	end_turn = Button.new()
	end_turn.name = "EndTurnButton"
	end_turn.tooltip_text = "BTN_END_TURN"  # an hourglass as in BG3, its words at the cursor
	end_turn.expand_icon = true
	end_turn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_turn.add_theme_constant_override("icon_max_width", 64)
	end_turn.focus_mode = Control.FOCUS_NONE
	end_turn.theme_type_variation = UiTheme.ACCENT_BUTTON
	end_turn.custom_minimum_size = Vector2(88, 88)
	end_turn.add_theme_stylebox_override("normal", UiTheme.box(UiTheme.ACCENT.darkened(0.55), UiTheme.ACCENT, 3, 6, 44))
	end_turn.add_theme_stylebox_override("hover", UiTheme.box(UiTheme.ACCENT.darkened(0.4), UiTheme.ACCENT_BRIGHT, 3, 6, 44))
	end_turn.add_theme_stylebox_override("pressed", UiTheme.box(UiTheme.ACCENT.darkened(0.3), UiTheme.ACCENT_BRIGHT, 3, 6, 44))
	end_turn.add_theme_stylebox_override("disabled", UiTheme.box(UiTheme.PANEL, UiTheme.BORDER, 3, 6, 44))
	_round.add_child(end_turn)
	_rests = VBoxContainer.new()
	_rests.name = "Rests"
	_rests.add_theme_constant_override("separation", GAP)
	_rests.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_body.add_child(_rests)
	windows = GridContainer.new()
	windows.name = "Windows"
	windows.columns = 2
	windows.add_theme_constant_override("h_separation", GAP)
	windows.add_theme_constant_override("v_separation", GAP)
	windows.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_body.add_child(windows)
	talk = HBoxContainer.new()
	talk.name = "TalkActs"
	talk.add_theme_constant_override("separation", 8)
	talk.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(talk)
	var acts := ScrollContainer.new()
	acts.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	acts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	acts.custom_minimum_size = Vector2(0, 150)
	talk.add_child(acts)
	talk_acts = VBoxContainer.new()
	talk_acts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	acts.add_child(talk_acts)
	_show()


func _mode() -> String:
	return "fight" if _fight else "peace"


## The hidden box an owner fills with the cells of `key` (a key of KEYS); `tidy` lays them on the grid.
func section(key: String) -> Container:
	if not _stage.has(key):
		var f := VBoxContainer.new()
		f.name = "Section_" + key.to_lower()
		f.visible = false
		add_child(f)
		_stage[key] = f
	return _stage[key]


## Empties the boxes of `keys` — the peace's when none — and the talk. A cell is freed wherever it stands now.
func clear(keys: Array = []) -> void:
	var which: Array = keys if not keys.is_empty() else KEYS.keys().filter(func(k: String) -> bool: return KEYS[k][0] == "peace")
	for k: String in which:
		_free_cells(k)
	if keys.is_empty():
		for c: Node in talk_acts.get_children():
			talk_acts.remove_child(c)
			c.queue_free()


## The fight's boxes are filled again each redraw.
func clear_fight() -> void:
	for k: String in KEYS:
		if KEYS[k][0] == "fight":
			_free_cells(k)


func _free_cells(key: String) -> void:
	var box := section(key)
	for c: Variant in (box.get_meta("cells", []) as Array) + box.get_children():
		if is_instance_valid(c) and not (c as Node).is_queued_for_deletion():
			if (c as Node).get_parent() != null:
				(c as Node).get_parent().remove_child(c)
			(c as Node).queue_free()
	box.set_meta("cells", [])


func set_fight(on: bool) -> void:
	if not on:
		who = Sheet.HERO
	if on != _fight:
		_fight = on
		_show()
		_relay()


func set_talk(on: bool) -> void:
	if on != _talking:
		_talking = on
		_show()


## A kind of the grid shown alone (the playtests too; an old tab key works); "" — the player's own bar.
func set_filter(key: String) -> void:
	_filter = str(KEYS[key][1]) if KEYS.has(key) else key
	_relay()


func current() -> String:
	return _filter


## After a fill: the cells take their icons and their slots.
func tidy() -> void:
	for k: String in _stage:
		var box: Control = _stage[k]
		var cells: Array = box.get_meta("cells", [])
		for c: Node in box.get_children():
			if c is Control and not cells.has(c):
				cells.append(c)
		cells = cells.filter(func(c: Variant) -> bool: return is_instance_valid(c) and not (c as Node).is_queued_for_deletion())
		box.set_meta("cells", cells)
		for c: Node in cells:
			if c is IconSlot and str((c as IconSlot).spec.get("ref", "")).is_empty():
				(c as IconSlot).set_icon(IconRules.button(Catalog.data, str(c.name)))
	for b: Node in talk_acts.find_children("*", "Button", true, false):
		var button := b as Button
		button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		button.clip_text = false
		button.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		button.autowrap_mode = TextServer.AUTOWRAP_OFF
	_show()
	_relay()


## The bar as wide as what it holds, in the middle under the map as in BG3; a conversation's acts take the whole width.
func _ready() -> void:
	if get_parent() is Control:
		(get_parent() as Control).resized.connect(func() -> void:  # only a new count of columns lays the bar again: a
			if _columns() != _laid_cols:  # laying that changes a size by a pixel must not lay it once more, for ever
				_relay())


func _show() -> void:
	size_flags_horizontal = Control.SIZE_FILL if _talking else Control.SIZE_SHRINK_CENTER
	_body.visible = not _talking
	talk.visible = _talking
	end_turn.visible = _fight


func _relay() -> void:
	if not is_queued_for_deletion():
		_lay.call_deferred()


## The cells of the grid now: the layout's key → [kind, cell]. The mode's own first; then what the other mode offers,
## grey in its slot (`_ghost`): in a fight the place's acts the side panel has made, out of it the fight's acts of
## `rules.combat.bar`.
func _cells() -> Dictionary:
	var out := {}
	var other := []
	for k: String in _stage:
		var m := str(KEYS.get(k, ["", ""])[0])
		if m.is_empty() or str(KEYS[k][1]) == "rest":
			continue
		for c: Variant in _cells_of(k):
			var key := HotbarLayout.key_of(str((c as Node).name))
			if key in ["Attack_main", "Attack_off"]:  # they stand in the hands
				continue
			if m in [_mode(), "both"]:
				out[key] = [str(KEYS[k][1]), c]
			else:
				other.append([key, str(KEYS[k][1]), c])
	for o: Array in other:
		if not out.has(o[0]) and o[2] is IconSlot:
			var src := o[2] as IconSlot
			out[o[0]] = [str(o[1]), _ghost(str(o[0]), src.spec, src.tip_title if not src.tip_title.is_empty() else src.text.get_slice("\n", 0), src.tip_body, src.card)]
	if not _fight:
		for id: Variant in CombatRules.cfg(Catalog.data).get("bar", {}).get("acts", []):
			var act := Acts.one(str(id))
			if act != null and not out.has("Do_" + str(id)):
				out["Do_" + str(id)] = ["combat", _ghost("Do_" + str(id), IconRules.of(Catalog.data, {}, "acts/" + str(id)), act.title(), act.tip(),
					CardInfo.act(GameState.session, Catalog.data, Sheet.HERO, act))]
	return out


## A grey cell of an act the other mode offers: its look, «только в бою» or «не в бою»; dragged like any cell.
func _ghost(key: String, look: Dictionary, title: String, body: String, card: Dictionary = {}) -> IconSlot:
	var g := IconSlot.new()
	g.name = "Ghost_" + key.replace(":", "_")
	g.spec = look
	g.tip_title = title
	g.tip_body = body
	g.card = card
	g.text = title
	g.tooltip_text = "%s\n%s" % [title, tr("BAR_NOT_IN_FIGHT" if _fight else "BAR_ONLY_FIGHT")]
	g.disabled = true
	g.focus_mode = Control.FOCUS_NONE
	g.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_park.add_child(g)
	_ghosts.append(g)
	return g


func _cells_of(key: String) -> Array:
	if not _stage.has(key):
		return []
	return ((_stage[key] as Node).get_meta("cells", []) as Array).filter(func(c: Variant) -> bool: return is_instance_valid(c) and not (c as Node).is_queued_for_deletion())


## The hero's big portrait at the bar's left (v0.8.4.43.8: in a fight a target of the picked act, as in BG3).
func hero_portrait() -> Portrait:
	return _portrait


## Lays the whole bar out again: portrait, hands, counters, grid, tabs, round button, rests.
func _lay() -> void:
	if not is_inside_tree() or GameState.session == null:
		return
	_portrait.show_of(GameState.session, Catalog.data, who, str(Sheet.holder(GameState.session, who).get("name", "")))
	_lay_hands()
	_lay_counters()
	_lay_passives()
	_lay_grid()
	_lay_tabs()
	_lay_rests()


func _detach(cell: Node) -> void:
	if cell.get_parent() != null:
		cell.get_parent().remove_child(cell)


func _lay_grid() -> void:
	if _dragging_divider or _whole() < CELL * 4:  # under the hand, or not sized yet: `resized` lays it then
		return
	for slot: Node in _grid.find_children("*", "HotSlot", true, false):  # every cell out before its slot goes: the
		for ch: Node in slot.get_children():  # other mode's too — a cell is freed only by the box that made it
			slot.remove_child(ch)
			_park.add_child(ch)
	for c: Node in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	for g: Control in _ghosts:
		if is_instance_valid(g):
			_detach(g)
			g.queue_free()
	_ghosts.clear()
	var cells := _cells()
	var total := _columns()
	_laid_cols = total
	var rows := HotbarLayout.rows(SaveManager.hotbar)
	_grid_scroll.custom_minimum_size = Vector2(0, rows * (CELL + GAP))
	var kinds := {}
	for key: String in cells:
		kinds[key] = cells[key][0]
	var sections := HotbarLayout.place(SaveManager.hotbar, HotbarLayout.BAR, kinds, total, "fight" if _fight else "peace")
	_drawn_kinds = {}
	var shown := []  # [the section's index in the layout, the section] to draw
	for i in sections.size():
		_drawn_kinds[str(sections[i]["kind"])] = true
		if _filter.is_empty() or str(sections[i]["kind"]) == _filter:
			shown.append([i, sections[i]])
	if shown.is_empty():
		_filter = ""
		shown = []
		for i in sections.size():
			shown.append([i, sections[i]])
	for n in shown.size():
		var at := int(shown[n][0])  # a drop goes into the layout's own section and slot, whichever tab shows it
		var sec: Dictionary = shown[n][1]
		var slots: Array = (sec["slots"] as Array).duplicate()
		var cols := int(sec["cols"])
		if not _filter.is_empty():  # one kind alone: its own slots in their order, the bar's whole width
			cols = total
			while slots.size() < rows * total or slots.size() % total != 0:
				slots.append("")
		if n > 0:
			_grid.add_child(_divider(at - 1))
		var g := GridContainer.new()
		g.name = "Kind_" + str(sec["kind"])
		g.columns = cols
		g.add_theme_constant_override("h_separation", GAP)
		g.add_theme_constant_override("v_separation", GAP)
		_grid.add_child(g)
		for j in slots.size():
			var slot := HotSlot.new()
			slot.custom_minimum_size = Vector2(CELL, CELL)
			slot.section = at
			slot.index = j
			slot.dropped.connect(_on_drop)
			g.add_child(slot)
			var key := str(slots[j])
			if cells.has(key):
				var cell: Control = cells[key][1]
				cell.custom_minimum_size = Vector2(CELL, CELL)
				if cell is Button:  # one square whatever its owner set: a cell's text is never drawn (v0.8.4.43.14)
					(cell as Button).clip_text = true
				_detach(cell)
				slot.add_child(cell)
				cell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
				if cell is IconSlot:
					var ic := cell as IconSlot
					ic.drag_key = key
					if not ic.dropped_off.is_connected(_on_off):
						ic.dropped_off.connect(_on_off)


## The columns the grid has room for.
func _columns() -> int:
	var others := size.x - _centre.size.x + _rows_box.size.x + 4  # the portrait, the hands, the round button, the rests, the windows
	return maxi(1, int((_whole() - others - 8) / (CELL + GAP)) - 1)


## The width the bar may take: its place under the map.
func _whole() -> float:
	return (get_parent() as Control).size.x if get_parent() is Control else size.x


## The divider after the layout's section `i` (v0.8.4.43.14, the author: «плавными как в BG3, лёгкими на движение»): the
## line follows the mouse while it is held — the grid is not laid again under it — and when let go it goes to the
## nearest boundary of a column, as far as each side keeps one.
func _divider(i: int) -> Control:
	var pad := MarginContainer.new()
	pad.name = "Divider_%d" % i
	pad.add_theme_constant_override("margin_left", 3)
	pad.add_theme_constant_override("margin_right", 3)
	var d := ColorRect.new()
	d.name = "Line"
	d.color = UiTheme.BAD.darkened(0.3)
	d.custom_minimum_size = Vector2(5, 0)
	d.mouse_default_cursor_shape = Control.CURSOR_HSIZE
	d.tooltip_text = tr("BAR_DIVIDER_TIP")
	pad.add_child(d)
	var held := ColorRect.new()  # the line in the hand, over the grid
	held.name = "Held"
	held.top_level = true
	held.visible = false
	held.mouse_filter = Control.MOUSE_FILTER_IGNORE
	held.color = UiTheme.ACCENT_BRIGHT
	pad.add_child(held)
	var start := [0.0]
	d.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			var x := (e as InputEventMouseButton).global_position.x
			if (e as InputEventMouseButton).pressed:
				start[0] = x
				_dragging_divider = true
				var seen := _grid_scroll.get_global_rect()  # the line as tall as the grid in sight, not the rows under it
				held.size = Vector2(d.size.x, minf(d.size.y, seen.size.y))
				held.global_position = Vector2(d.global_position.x, maxf(d.global_position.y, seen.position.y))
				held.visible = true
				d.modulate.a = 0.35
			elif _dragging_divider:
				_dragging_divider = false
				held.visible = false
				d.modulate.a = 1.0
				var cols := HotbarLayout.reach(SaveManager.hotbar, HotbarLayout.BAR, i, snap(x - start[0]))
				if cols != 0:
					HotbarLayout.shift(SaveManager.hotbar, HotbarLayout.BAR, i, cols)
					SaveManager.save_settings()
				_relay()
		elif e is InputEventMouseMotion and _dragging_divider:
			var step := float(CELL + GAP)
			var lo := HotbarLayout.reach(SaveManager.hotbar, HotbarLayout.BAR, i, -99) * step
			var hi := HotbarLayout.reach(SaveManager.hotbar, HotbarLayout.BAR, i, 99) * step
			var dx := clampf((e as InputEventMouseMotion).global_position.x - start[0], lo, hi)
			held.global_position.x = d.global_position.x + dx)
	return pad


## The columns a divider let go `dx` pixels away moves: to the nearest boundary of a column.
static func snap(dx: float) -> int:
	return roundi(dx / float(CELL + GAP))


func _on_drop(key: String, sec: int, index: int) -> void:
	HotbarLayout.move(SaveManager.hotbar, HotbarLayout.BAR, cell_key(key), sec, index, not _filter.is_empty())
	SaveManager.save_settings()
	_relay()


## The layout's key of a cell dragged onto the bar — from a slot, from the sheet's book («spell:<id>»,
## «feature:<resource>», «item:<id>») or an act's button name («Do_dash»): one in a fight and out of it.
static func cell_key(key: String) -> String:
	return HotbarLayout.key_of(key)


func _on_off(key: String) -> void:
	HotbarLayout.hide(SaveManager.hotbar, HotbarLayout.BAR, key)
	SaveManager.save_settings()
	_relay()


func _lay_tabs() -> void:
	var kinds := _drawn_kinds
	if end_turn.icon == null:
		end_turn.icon = IconSlot.texture(str(IconRules.of(Catalog.data, {}, "ui/end_turn").get("path", "")))
		end_turn.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if _tabs.get_child_count() == 0:  # made once: a filter pressed is never freed under its own signal
		for k: String in TABS:
			var b := Button.new()
			b.name = "Filter_" + (k if k != "" else "all")
			b.text = KIND_TITLES.get(k, "BAR_ALL")
			for look: Array in [["normal", "tab_unselected"], ["hover", "tab_hovered"], ["pressed", "tab_selected"], ["hover_pressed", "tab_selected"]]:
				b.add_theme_stylebox_override(look[0], get_theme_stylebox(look[1], "TabContainer"))  # the drawn tab's frame
			b.toggle_mode = true
			b.focus_mode = Control.FOCUS_NONE
			b.add_theme_font_size_override("font_size", UiTheme.SIZE_SMALL)
			b.add_theme_color_override("font_color", UiTheme.MUTED)
			b.add_theme_color_override("font_pressed_color", UiTheme.ACCENT_BRIGHT)
			b.set_meta("kind", k)
			b.pressed.connect(func() -> void:
				_filter = k
				_relay.call_deferred())
			_tabs.add_child(b)
	for b: Button in _tabs.get_children():
		var k := str(b.get_meta("kind"))
		b.visible = k == "" or kinds.has(k)
		b.set_pressed_no_signal(k == _filter)


## The hero's passives as switches (v0.8.4.43.7, ToggleRules), the same in a fight and out of it: a cell lit while it is on,
## a press switches it, the card says what it does; one fixed by the moment (a bout to surrender) is grey and lit.
func _lay_passives() -> void:
	var s := GameState.session
	var box := section(PASSIVE)
	var cells: Array = box.get_meta("cells", [])
	var have := {}
	for t: Dictionary in ToggleRules.of(s, Catalog.data, who):
		var id := str(t["id"])
		have[id] = true
		if not _toggles.has(id) or not is_instance_valid(_toggles[id]):
			var made := IconSlot.make("toggles/" + id, str(t["name"]), CELL)
			made.name = "Toggle_" + id
			made.toggle_mode = true
			made.pressed.connect(func() -> void:  # the engine's state turned round, whatever the button shows; whose bar it is now
				var mine := str(who.get("id", Being.HERO))
				var why := GameState.set_toggle(id, not ToggleRules.on(GameState.session, Catalog.data, who, id), mine)
				if not why.is_empty():
					EventBus.message.emit(tr(why))
				_relay())
			box.add_child(made)
			cells.append(made)
			_toggles[id] = made
		var cell: IconSlot = _toggles[id]
		cell.set_pressed_no_signal(bool(t["on"]))
		cell.disabled = not str(t["why"]).is_empty()
		cell.tip_title = str(t["name"])
		cell.tip_body = str(t["tip"])
		cell.tooltip_text = tr("TOGGLE_ON" if bool(t["on"]) else "TOGGLE_OFF") + ("" if str(t["why"]).is_empty() else " · " + tr(str(t["why"])))
		cell.queue_redraw()
	for id: String in _toggles.keys():
		if not have.has(id):
			var gone: Node = _toggles[id]
			_toggles.erase(id)
			cells.erase(gone)
			if is_instance_valid(gone):
				_detach(gone)
				gone.queue_free()
	box.set_meta("cells", cells)


## The weapons of both hands of the set in hand — in a fight a press strikes with it (the fight's own cell) — and the
## set switch under them, as in BG3: the set in hand lit, the other a press away.
func _lay_hands() -> void:
	var s := GameState.session
	var c := Sheet.holder(s, who)
	var fight: Array = _cells_of("COMBAT_TAB_WEAPONS") if _fight else []
	for n: Node in _hands.get_children():
		_hands.remove_child(n)
		if not fight.has(n):
			n.queue_free()
	var held: Dictionary = c.get("equipped", {})
	for spec: Array in [["main_hand", "Attack_main", "HeldMain"], ["off_hand", "Attack_off", "HeldOff"]]:
		var cell: Control = null
		for f: Control in fight:
			if str(f.name) == spec[1]:
				cell = f
		if cell != null:
			_detach(cell)
		else:
			var id := str(held.get(spec[0], ""))
			var shown := IconSlot.make("items/" + id if not id.is_empty() else IconRules.EMPTY_HAND,
				ItemRules.display_name(Catalog.data["items"], s.items, id) if not id.is_empty() else tr("SLOT_EMPTY_HAND"), CELL + 8)
			shown.name = spec[2]
			if not id.is_empty():
				shown.set_card(CardInfo.item(c, Catalog.data, s.items, id))
			cell = shown
		cell.custom_minimum_size = Vector2(CELL + 8, CELL + 8)
		_hands.add_child(cell)
	for n: Node in _sets.get_children():
		_sets.remove_child(n)
		n.queue_free()
	var why := Acts.one("swap").can(s, Catalog.data, who)
	for i in 2:
		var b := Button.new()
		b.name = "WeaponSetHeld" if i == 0 else "WeaponSetStowed"
		var hands: Dictionary = held if i == 0 else CharacterRules.stowed(c)
		b.text = "➶" if CharacterRules.hands_kind(hands, Catalog.data, s.items) == "ranged" else "⚔"
		for slot: String in CharacterRules.HANDS:  # the shots at hand of the set's bow (v0.8.4.42.6)
			var shots := Gear.ready_shots(Catalog.data, s.items, c, str(hands.get(slot, ""))) if str(hands.get(slot, "")) != "" else -1
			if shots >= 0:
				b.text += " · %d" % shots
				break
		b.toggle_mode = true
		b.button_pressed = i == 0
		b.focus_mode = Control.FOCUS_NONE
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		b.custom_minimum_size = Vector2(CELL + 8, 26)
		b.tooltip_text = _set_tip(hands) + "\n" + (tr("SET_IN_HAND") if i == 0 else (Hotkeys.tip(tr("SWAP_WEAPONS"), "swap_weapons", SaveManager.keys) if why.is_empty() else tr(why)))
		if i == 0:
			b.pressed.connect(func() -> void: b.button_pressed = true)
		else:
			b.disabled = not why.is_empty()
			b.pressed.connect(func() -> void:
				(func() -> void:  # the hands are laid again: never under the press
					var err := GameState.swap_weapons()
					if not err.is_empty():
						EventBus.message.emit(tr(err))).call_deferred())
		_sets.add_child(b)


func _set_tip(hands: Dictionary) -> String:
	var names: Array[String] = []
	for slot: String in CharacterRules.HANDS:
		var id := str(hands.get(slot, ""))
		if not id.is_empty():
			names.append(ItemRules.display_name(Catalog.data["items"], GameState.session.items, id))
	return ", ".join(names) if not names.is_empty() else "—"


## Over the grid: in a fight the action, the bonus action, the reaction and the move; the class's stocks; the spell
## slots by circle.
func _lay_counters() -> void:
	for n: Node in _counters.get_children():
		_counters.remove_child(n)
		n.queue_free()
	var s := GameState.session
	var c := Sheet.holder(s, who)
	if _fight and CombatRules.active(s):
		var f := who if who.has("side") else CombatRules.player(s)  # the fighter whose bar it is
		var e: Dictionary = f.get("points", {})
		_counter("EcoAction", "●", int(e.get("action", 0)) + int(e.get("attacks", 0)), UiTheme.OK, tr("COMBAT_ACTION"))
		_counter("EcoBonus", "▲", int(e.get("bonus", 0)), UiTheme.WARN, tr("COMBAT_BONUS"))
		_counter("EcoReaction", "◆", 0 if bool(f.get("reacted", false)) else 1, Color("#b98fd8"), tr("BAR_REACTION"))
		var mv := int(e.get("move", 0))
		_counter("EcoMove", "➜ %d" % mv, mv, UiTheme.ACCENT_BRIGHT, tr("COMBAT_MOVE").format({"n": mv}))
	for r: Dictionary in Stock.lines(c, Catalog.data):
		_counter("Stock_" + str(r["id"]), "◈ %d/%d" % [int(r["left"]), int(r["max"])], int(r["left"]), UiTheme.TEMP_HP,
			"%s: %d/%d" % [r["name"], r["left"], r["max"]])
	var most: Array = c.get("slots_max", [])
	for lv in range(1, mini(6, most.size() + 1)):
		var full := int(most[lv - 1])
		if full <= 0:
			continue
		var left := SpellRules.slots_left(c, lv)
		var b := Button.new()
		b.name = "CastCircle_%d" % lv
		b.flat = true
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		b.text = "%s %s%s" % [ROMAN[lv], "●".repeat(left), "○".repeat(maxi(0, full - left))]
		b.button_pressed = _fight and picked_circle == lv
		b.add_theme_font_size_override("font_size", UiTheme.SIZE_SMALL)
		b.add_theme_color_override("font_color", UiTheme.TEMP_HP)
		b.tooltip_text = tr("COMBAT_SLOT_CIRCLE").format({"n": lv, "left": left}) + ("\n" + tr("COMBAT_SLOT_PICK_TIP") if _fight else "")
		b.disabled = not _fight
		b.pressed.connect(func() -> void:
			picked_circle = 0 if picked_circle == lv else lv
			circle_picked.emit.call_deferred(picked_circle))  # the counters are laid again: never under the press
		_counters.add_child(b)


func _counter(node_name: String, text: String, n: int, color: Color, tip: String) -> void:
	var l := Label.new()
	l.name = node_name
	l.text = text.repeat(n) if text.length() == 1 and n > 1 else text
	l.tooltip_text = tip
	l.mouse_filter = Control.MOUSE_FILTER_STOP
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.add_theme_color_override("font_color", color if n > 0 else UiTheme.MUTED.darkened(0.4))
	_counters.add_child(l)


## The round button: the end of the turn in a fight, the wait out of it; the short and the long rest beside.
func _lay_rests() -> void:
	for n: Node in _rests.get_children():
		_rests.remove_child(n)
	for n: Node in _round.get_children():
		if n != end_turn:
			_round.remove_child(n)
	for cell: Control in _cells_of(REST):
		_detach(cell)
		if str(cell.name) == "WaitButton":
			if not _fight:
				cell.custom_minimum_size = Vector2(80, 80)
				_round.add_child(cell)
			continue
		cell.custom_minimum_size = Vector2(CELL - 8, CELL - 8)
		if _fight and cell is BaseButton:
			(cell as BaseButton).disabled = true
		_rests.add_child(cell)

