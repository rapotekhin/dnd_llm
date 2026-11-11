class_name CharacterSheet
extends ModalFrame
## The character window as in BG3 (v0.8.4.43.6; the sheet since v0.5.0): not the whole screen — the world shows at its
## sides and the hotbar under it. On top the party's portraits (a click shows that one, a thing dropped on one is handed
## over) and the name on the left, the sections — «Снаряжение» (C, I), «Книга» (K), «Развитие» — in the middle with the
## level and its experience under them, the coins on the right (v0.8.4.43.13, as in BG3); the window in the middle of the
## screen. Left the sheet in three tabs (SheetColumn); in «Снаряжение» the doll (DollView) and the grid of things
## (ItemGrid) with the weight bar under it. A thing: a drag onto the doll or the belt puts it on, back onto
## the grid takes it off, onto a companion's portrait hands it over, past the window's edge drops it, Shift asks how many;
## a double click puts it on or uses it, the right button lists its acts (ItemActs). Every act is the engine's through
## GameState.item_act; anybody of the party is read by Sheet.who (ADR-0016) and shown without closing the window.

signal prepare_requested
signal bag_requested(bag_id: String)

const SCENE := "res://ui/components/character_sheet.tscn"
const SECTIONS: Array[String] = ["gear", "book", "dev"]
const PORTRAIT := 52
const BOOK_TABS: Array[String] = ["class", "common", "react"]
const SPELL_CELL := 48

var who := Being.HERO  ## whose things and sheet are shown
var section := "gear"
var _conc_armed := ""  # a concentration spell pressed once while another is held (v0.7.13.1)
var _details: DetailsPanel  # the card at the cursor (v0.8.4.43.3)
var _column: SheetColumn
var _doll: DollView
var _grid: ItemGrid
var _menu: ActsMenu
var _mate_view := {}  # a companion's grid: its filter and sort, kept while the window lives
var book_tab := "class"  ## the book's tab (v0.8.4.43.13): the class, the common acts of a fight, the reactions


func required() -> Dictionary:
	var nodes := super()
	nodes.merge({
		"%SheetSplit": "HBoxContainer", "%ColumnBox": "PanelContainer", "%GearPage": "HBoxContainer", "%DollBox": "VBoxContainer",
		"%InvBox": "VBoxContainer", "%WeightRow": "HBoxContainer", "%CarriedWeight": "Label", "%WeightBar": "ProgressBar",
		"%AttunedCount": "Label", "%BookPage": "ScrollContainer", "%FeaturesBox": "VBoxContainer",
		"%DevPage": "ScrollContainer", "%DevBox": "VBoxContainer", "%ItemActsBox": "VBoxContainer", "%PartyStrip": "HBoxContainer",
		"%HeadLeft": "HBoxContainer", "%HeadMid": "VBoxContainer", "%HeadRight": "HBoxContainer", "%Sections": "HBoxContainer", "%LevelBox": "VBoxContainer", "%LevelLabel": "Label", "%XpBar": "ProgressBar", "%HeadCoins": "Label",
	})
	return nodes


func _ready() -> void:
	super()
	close_requested.connect(func() -> void: visible = false)
	close_x.name = "CloseSheetButton"
	var split: HBoxContainer = UiScenes.need(self, "%SheetSplit")
	fill_body(split)
	title.reparent(UiScenes.need(self, "%HeadLeft"))  # the party and the name | the sections and the level | the coins and «✕»
	close_x.reparent(UiScenes.need(self, "%HeadRight"))
	for n: Node in get_tree().get_nodes_in_group("editor_sample"):
		if is_ancestor_of(n):
			n.queue_free()
	_details = DetailsPanel.new(Vector2(0, 160), true)
	_details.name = "ItemDetails"
	add_child(_details)
	_column = SheetColumn.new()
	_column.details = _details
	(UiScenes.need(self, "%ColumnBox") as Control).add_child(_column)
	_doll = DollView.new()
	_doll.details = _details
	_doll.act.connect(_do)
	_doll.menu.connect(_open_menu)
	(UiScenes.need(self, "%DollBox") as Control).add_child(_doll)
	_grid = ItemGrid.new("Inv", "Item_", 6)
	var inv: VBoxContainer = UiScenes.need(self, "%InvBox")
	inv.add_child(_grid)
	inv.move_child(_grid, 0)
	_grid.view_changed.connect(func() -> void:
		if who == Being.HERO:
			SaveManager.save_settings()
		_rebuild())
	_grid.setup = _setup_cell
	_grid.accepts = func(drag: Dictionary) -> bool: return _from(drag) == who and _kind(drag) in ["slot", "belt"]
	_grid.dropped = _back_to_grid
	var away := DropTarget.new()  # the world round the window: a thing dragged past its edge is dropped (BG3)
	away.name = "DropAway"
	away.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	away.accept = func(drag: Dictionary) -> bool: return _from(drag) == Being.HERO and _kind(drag) in ["things", "slot", "belt"]
	away.take = func(drag: Dictionary) -> void: ItemGrid.with_qty(self, drag, func(n: int) -> void: _do({"act": "drop", "item": str(drag["item"]), "qty": n}))
	add_child(away)
	move_child(away, 1)  # over the dim, under the panel
	EventBus.state_changed.connect(_rebuild)
	visibility_changed.connect(_rebuild)


func open() -> void:
	visible = true


## Opens a section by the old tab's number: 0 the sheet and 2 the things — «Снаряжение», 1 «Книга», 3 «Развитие».
func open_tab(i: int) -> void:
	section = SECTIONS[[0, 1, 0, 2][clampi(i, 0, 3)]]
	if section != "gear":
		who = Being.HERO
	visible = true
	_rebuild()


## The section shown as the old tab's number (the keys C, I, K toggle by it).
func current_tab() -> int:
	return {"gear": 0, "book": 1, "dev": 3}[section]


## Shows `id` of the party (a portrait's click, a companion's «Снаряжение»): the window stays open.
func show_of(id: String) -> void:
	who = id
	if id != Being.HERO:
		section = "gear"
	visible = true
	_rebuild()


func _rebuild() -> void:
	if not visible or not GameState.has_session():
		return
	var s := GameState.session
	if who != Being.HERO and not Being.follows(s, who):
		who = Being.HERO
	title.text = CreatureCard.name_of(s, Catalog.data, Sheet.who(s, Catalog.data, who))
	_party()
	_sections()
	_level()
	_column.show_of(who)
	for page: Array in [["%GearPage", "gear"], ["%BookPage", "book"], ["%DevPage", "dev"]]:
		(UiScenes.need(self, page[0]) as Control).visible = section == page[1]
	match section:
		"book":
			_book(s.character)
		"dev":
			_development(s.character)
		_:
			_gear()


# --- the head -----------------------------------------------------------------------------------------------------


## The hero and those who walk with it: a click shows one, a thing dropped on one is handed over.
func _party() -> void:
	var strip: HBoxContainer = UiScenes.need(self, "%PartyStrip")
	for ch in strip.get_children():
		strip.remove_child(ch)
		ch.queue_free()
	var s := GameState.session
	var data := Catalog.data
	var ids: Array[String] = [Being.HERO]
	ids.append_array(Being.followers(s))
	for id: String in ids:
		var drop := DropTarget.new()
		drop.name = "PartyDrop_" + id
		strip.add_child(drop)
		var w := Sheet.who(s, data, id)
		var p := Portrait.of(CreatureCard.name_of(s, data, w), PORTRAIT)
		p.name = "Party_" + id
		p.show_of(s, data, w, CreatureCard.name_of(s, data, w))
		p.toggle_mode = true
		p.button_pressed = id == who
		p.mouse_filter = Control.MOUSE_FILTER_PASS  # a drop on it goes to its place
		p.pressed.connect(show_of.bind(id))
		drop.add_child(p)
		drop.accept = func(drag: Dictionary) -> bool:
			var from := _from(drag)
			return from != id and (from == Being.HERO or id == Being.HERO) and _kind(drag) == "things"
		drop.take = func(drag: Dictionary) -> void:
			var from := _from(drag)
			ItemGrid.with_qty(self, drag, func(n: int) -> void:
				var row := {"act": "give", "item": str(drag["item"]), "to": id, "qty": n} if from == Being.HERO else {"act": "take", "item": str(drag["item"]), "qty": n}
				_report(GameState.item_act(row, from)))
	strip.visible = ids.size() > 1


## The sections as icons: a companion has only its things.
func _sections() -> void:
	var box: HBoxContainer = UiScenes.need(self, "%Sections")
	for ch in box.get_children():
		box.remove_child(ch)
		ch.queue_free()
	for sec: String in SECTIONS:
		var b := IconSlot.make(IconRules.button(Catalog.data, "SheetSection_" + sec), tr("SHEET_SECTION_" + sec.to_upper()), 48)
		b.name = "SheetSection_" + sec
		b.toggle_mode = true
		b.button_pressed = sec == section
		b.disabled = who != Being.HERO and sec == "dev"
		b.tooltip_text = Hotkeys.tip(tr("SHEET_SECTION_" + sec.to_upper()), {"gear": "inventory", "book": "spells"}.get(sec, ""), SaveManager.keys) \
			if not b.disabled else tr("SHEET_HERO_ONLY")
		b.pressed.connect(func() -> void:
			section = sec
			_rebuild())
		box.add_child(b)


## «Уровень 3 · опыт 900 из 2700» and its bar; the coins on the right.
func _level() -> void:
	var s := GameState.session
	var data := Catalog.data
	var label: Label = UiScenes.need(self, "%LevelLabel")
	var bar: ProgressBar = UiScenes.need(self, "%XpBar")
	var coins: Label = UiScenes.need(self, "%HeadCoins")
	coins.text = Money.format(Gear.coins(s, data, who))
	var hero := who == Being.HERO
	bar.visible = hero
	if not hero:
		var lv := int(Sheet.holder(s, Sheet.who(s, data, who)).get("level", 0))
		label.text = tr("SHEET_LEVEL").format({"n": lv}) if lv > 0 else ""
		return
	var c := s.character
	var lv := int(c.get("level", 1))
	var xp := int(c.get("xp", 0))
	if lv >= LevelUp.max_level(c, data):
		label.text = tr("SHEET_LEVEL").format({"n": lv})
		bar.value = 1.0
		return
	var low := LevelUp.xp_for(data, lv)
	var high := LevelUp.xp_for(data, lv + 1)
	label.text = tr("SHEET_LEVEL_XP").format({"n": lv, "xp": xp, "next": high})
	bar.value = clampf(float(xp - low) / maxf(1.0, float(high - low)), 0.0, 1.0)
	bar.add_theme_stylebox_override("fill", UiTheme.box(UiTheme.ACCENT, UiTheme.ACCENT, 0, 0, 3))
	bar.add_theme_stylebox_override("background", UiTheme.box(UiTheme.BG, UiTheme.BORDER, 1, 0, 3))


# --- «Снаряжение»: the doll and the grid --------------------------------------------------------------------------


func _gear() -> void:
	var s := GameState.session
	var data := Catalog.data
	var c := Gear.of(s, data, who)
	var hero := who == Being.HERO
	_doll.show_of(who)
	_grid.where = {"kind": "things", "who": who}
	_grid.view = SaveManager.inventory_view if hero else _mate_view
	_grid.show_items(Gear.loose(c, data, s.items))
	(UiScenes.need(self, "%WeightRow") as Control).visible = hero
	var att: Label = UiScenes.need(self, "%AttunedCount")
	att.visible = hero
	if not hero:
		return
	att.text = tr("SHEET_ATTUNED").format({"n": ItemRules.attuned(c).size()})  # v0.7.12
	var weight: Label = UiScenes.need(self, "%CarriedWeight")
	var load := CharacterRules.carried_weight(c, data, s.items)
	var most := CharacterRules.capacity(c, data)
	weight.text = tr("SHEET_WEIGHT").format({"n": int(ceilf(load)), "max": most})
	weight.remove_theme_color_override("font_color")
	if CharacterRules.overloaded(c, data, s.items):
		weight.text += " — " + tr("TOO_HEAVY")
		weight.add_theme_color_override("font_color", UiTheme.WARN)
	var share := load / maxf(1.0, most)
	var bar: ProgressBar = UiScenes.need(self, "%WeightBar")
	bar.value = minf(share, 1.0)
	var col := UiTheme.OK if share < 0.75 else UiTheme.WARN if share <= 1.0 else UiTheme.BAD
	bar.add_theme_stylebox_override("fill", UiTheme.box(col, col, 0, 0, 3))
	bar.add_theme_stylebox_override("background", UiTheme.box(UiTheme.BG, UiTheme.BORDER, 1, 0, 3))


## A cell of the grid: a double click puts it on or uses it, the right button lists its acts.
func _setup_cell(cell: ItemCell) -> void:
	var id := cell.item
	cell.on_double = func() -> void:
		var main := ItemActs.main(ItemActs.of(GameState.session, Catalog.data, who, id))
		if not main.is_empty():
			_do(main)
	cell.on_menu = func(at: ItemCell) -> void: _open_menu(at, ItemActs.of(GameState.session, Catalog.data, who, id))


## A thing of the doll or the belt dragged back onto the grid: it comes off.
func _back_to_grid(drag: Dictionary) -> void:
	var from: Dictionary = drag["from"]
	if _kind(drag) == "slot":
		_do({"act": "unequip", "item": str(drag["item"]), "slot": str(from["slot"]), "spare": bool(from.get("spare", false))})
	elif _kind(drag) == "belt":
		_do({"act": "belt_take", "item": str(drag["item"]), "at": int(from["at"])})


static func _from(drag: Dictionary) -> String:
	return str((drag.get("from", {}) as Dictionary).get("who", ""))


static func _kind(drag: Dictionary) -> String:
	return str((drag.get("from", {}) as Dictionary).get("kind", ""))


# --- the acts of a thing ------------------------------------------------------------------------------------------


## Does a row of ItemActs: the bag's window and the letter's are the window's own, the rest is GameState's. "" or a reason.
func _do(row: Dictionary) -> String:
	if str(row.get("act", "")) == "open":
		bag_requested.emit(str(row["bag"]))
		return ""
	if str(row.get("act", "")) == "letter":
		EventBus.letter_requested.emit("")
		return ""
	var err := GameState.item_act(row, who)
	if err.is_empty() and str(row["act"]) == "use":
		visible = false  # the master tells it in the chat
	_report(err)
	return err


func _report(err: String) -> void:
	if not err.is_empty():
		EventBus.message.emit(tr(err))


## The right button's menu of a thing: its acts as a list with lists inside (ItemMenu), grey with why.
func _open_menu(cell: Control, rows: Array) -> void:
	_menu = ItemMenu.show(self, stage_rows(str(cell.get("tip_title")) if cell != null else "", rows), _menu)


## The acts of a thing staged by name for the menu (Equip_main_hand_longsword, BeltPut_candle, Drink_ale…): a playtest
## presses them as the list would.
func stage(item: String, worn := "", spare := false) -> Control:
	var s := GameState.session
	return stage_rows(ItemRules.display_name(Catalog.data["items"], s.items, item), ItemActs.of(s, Catalog.data, who, item, worn, spare))


func stage_rows(head: String, rows: Array) -> Container:
	return ItemMenu.stage(UiScenes.need(self, "%ItemActsBox"), head, rows, _do) as Container


# --- «Книга» as in BG3 (v0.8.4.43.13): the class, the common acts, the reactions — icons dragged onto the hotbar ------


## The box of a page, emptied for its rows.
func _page(path: String) -> VBoxContainer:
	var box: VBoxContainer = UiScenes.need(self, path)
	for ch in box.get_children():
		box.remove_child(ch)
		ch.queue_free()
	return box


func _text(parent: Control, text: String, variation: String = "", fit := false) -> Label:
	return UiParts.label(parent, text, variation, fit)


## The book of `who`: the hero's three tabs — its class (cantrips, class actions, the prepared spells and all of them by
## circle with the slots), the common acts of a fight, the reactions; a companion's reactions alone (it acts by itself).
## Every icon is dragged onto the hotbar by its key (`ActionBar.cell_key`): one taken off the bar by chance comes back.
func _book(c: Dictionary) -> void:
	var box := _page("%FeaturesBox")
	var hero := who == Being.HERO
	if not hero:
		book_tab = "react"
	var bar := HBoxContainer.new()
	bar.name = "BookTabs"
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", 6)
	box.add_child(bar)
	for t: String in BOOK_TABS:
		if not hero and t != "react":
			continue
		var b := Button.new()
		b.name = "BookTab_" + t
		b.toggle_mode = true
		b.button_pressed = t == book_tab
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		b.text = _book_tab_title(c, t)
		b.custom_minimum_size = Vector2(200, 40)
		b.pressed.connect(func() -> void:
			book_tab = t
			_rebuild())
		bar.add_child(b)
	match book_tab:
		"common":
			_book_common(box)
		"react":
			_reactions(box)
		_:
			_book_class(box, c)


## «Друид (4/5)» — the class and its spells prepared, «Общие», «Реакции».
func _book_tab_title(c: Dictionary, t: String) -> String:
	match t:
		"common":
			return tr("BAR_KIND_COMMON")
		"react":
			return tr("SHEET_REACTIONS")
	var name := str(c.get("class_name", ""))
	if SpellRules.prepares(c, Catalog.data):
		name += " (%d/%d)" % [(c.get("spells", {}).get("prepared", []) as Array).size(), int(SpellRules.prepare_pool(c, Catalog.data)["count"])]
	return name


## The class's page: its numbers on top, the cantrips beside the class actions, the strip of prepared spells, every spell by
## circle with the slots of the circle on the right.
func _book_class(box: VBoxContainer, c: Dictionary) -> void:
	var d := Catalog.data
	var can_act := Backend.is_ready() and not GameState.is_busy()
	var head := HBoxContainer.new()
	head.name = "BookHead"
	head.add_theme_constant_override("separation", 18)
	box.add_child(head)
	var sub: Dictionary = d["classes"]["subclasses"].get(str(c.get("subclass", "")), {})
	_text(head, tr("SHEET_CLASS_LEVEL").format({"class": c.get("class_name", ""), "level": int(c.get("level", 1))})
		+ (" · " + str(sub["name"]) if not sub.is_empty() else ""), UiTheme.ACCENT_LABEL, true)
	if not str(c.get("spell_ability", "")).is_empty():
		_text(head, tr("SHEET_SPELLCASTING").format({"ability": tr("ABILITY_" + str(c["spell_ability"]).to_upper()),
			"dc": c.get("spell_dc", 0), "attack": "%+d" % int(c.get("spell_attack", 0))}), UiTheme.MUTED_LABEL, true)
	_text(head, tr("SHEET_HIT_DICE").format({"left": ExplorationRules.hit_dice_left(c), "max": int(c.get("level", 1))}), UiTheme.MUTED_LABEL, true)
	if not str(c.get("concentration", "")).is_empty():
		_text(box, tr("SHEET_CONCENTRATION").format({"spell": d["spells"].get(str(c["concentration"]), {}).get("name", "")}))
	var ready_ids := SpellRules.ready(c)
	var sp: Dictionary = c.get("spells", {})
	var top := HBoxContainer.new()
	top.name = "BookTop"
	top.add_theme_constant_override("separation", 40)
	box.add_child(top)
	var cantrips := _book_group(top, "SHEET_SPELLS_CANTRIPS", "BookCantrips")
	var seen: Array[String] = []
	for list: String in ["cantrips", "tome", "free"]:  # what is cast at will: cantrips, the tome's, an invocation's spell
		for id: Variant in _by_circle(sp.get(list, [])):
			if not seen.has(str(id)):
				seen.append(str(id))
				_spell_cell(cantrips, c, str(id), ready_ids.has(str(id)))
	cantrips.get_parent().visible = cantrips.get_child_count() > 0
	var acts := _book_group(top, "BOOK_CLASS_ACTS", "BookClassActs")
	_class_acts(acts, c, can_act)
	acts.get_parent().visible = acts.get_child_count() > 0
	_pact_rows(box, c, can_act)
	_familiar_rows(box, c, can_act)
	if str(c.get("spell_ability", "")).is_empty():
		return
	var spells_head := HBoxContainer.new()
	spells_head.name = "BookSpellsHead"
	spells_head.add_theme_constant_override("separation", 14)
	box.add_child(spells_head)
	_text(spells_head, tr("BOOK_SPELLS"), UiTheme.CAPTION_LABEL, true).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var always: Array = sp.get("always", [])
	var pool: Array = []
	if SpellRules.prepares(c, d):
		var p := SpellRules.prepare_pool(c, d)
		var prepared: Array = sp.get("prepared", [])
		_text(spells_head, tr("BOOK_PREPARED").format({"n": prepared.size(), "max": int(p["count"])}), UiTheme.MUTED_LABEL, true).size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var why := SpellRules.can_prepare(c, d)
		var prep := Button.new()
		prep.name = "PrepareButton"
		prep.text = "BTN_PREPARE"
		prep.disabled = not why.is_empty() or GameState.is_busy()
		prep.tooltip_text = tr(why) if not why.is_empty() else ""
		prep.pressed.connect(prepare_requested.emit)
		spells_head.add_child(prep)
		var strip := PanelContainer.new()  # BG3: the prepared ones in a strip, the empty places to fill after them
		strip.name = "PreparedStrip"
		strip.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.PANEL_RAISED, UiTheme.BORDER, 1, 8, 6))
		box.add_child(strip)
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 4)
		flow.add_theme_constant_override("v_separation", 4)
		strip.add_child(flow)
		for id: Variant in _by_circle(prepared):
			_spell_cell(flow, c, str(id), true)
		for i in maxi(0, int(p["count"]) - prepared.size()):
			var empty := IconSlot.make("slots/spell", tr("BOOK_PREPARE_EMPTY"), SPELL_CELL)
			empty.name = "PreparedEmpty_%d" % i
			empty.disabled = true
			flow.add_child(empty)
		for id: Variant in _by_circle(always):
			_spell_cell(flow, c, str(id), true)
		pool = (p["pool"] as Array) + always
	else:
		for list: String in ["known", "prepared", "always"]:
			for id: Variant in sp.get(list, []):
				if not pool.has(id):
					pool.append(id)
	for lv in range(1, 6):
		var ids := _by_circle(pool.filter(func(id: Variant) -> bool: return SpellRules.level_of(d, str(id)) == lv))
		var most := int(c.get("slots_max", [0, 0, 0, 0, 0])[lv - 1])
		if ids.is_empty() and most <= 0:
			continue
		var row := HBoxContainer.new()
		row.name = "Circle_%d" % lv
		row.add_theme_constant_override("separation", 10)
		box.add_child(row)
		var roman := _text(row, str(ActionBar.ROMAN[lv]), UiTheme.ACCENT_LABEL, true)
		roman.custom_minimum_size = Vector2(34, 0)
		roman.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		roman.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var flow := HFlowContainer.new()
		flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		flow.add_theme_constant_override("h_separation", 4)
		flow.add_theme_constant_override("v_separation", 4)
		row.add_child(flow)
		for id: Variant in ids:
			_spell_cell(flow, c, str(id), ready_ids.has(str(id)))
		if most > 0:  # the slots of the circle as pips, as in BG3
			var left := SpellRules.slots_left(c, lv)
			var pips := _text(row, "●".repeat(left) + "○".repeat(maxi(0, most - left)), UiTheme.ACCENT_LABEL, true)
			pips.name = "Slots_%d" % lv
			pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			pips.mouse_filter = Control.MOUSE_FILTER_STOP
			pips.tooltip_text = tr("SHEET_SLOT").format({"level": lv, "left": left, "max": most})


## A titled group of icons in a row; its flow.
func _book_group(parent: Control, key: String, node_name: String) -> HFlowContainer:
	var col := VBoxContainer.new()
	col.name = node_name
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)
	parent.add_child(col)
	_text(col, tr(key), UiTheme.CAPTION_LABEL, true)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 4)
	flow.add_theme_constant_override("v_separation", 4)
	col.add_child(flow)
	return flow


## Spell ids by circle, then by name.
func _by_circle(ids: Array) -> Array:
	var d := Catalog.data
	var out := ids.duplicate()
	out.sort_custom(func(a: Variant, b: Variant) -> bool:
		var la := SpellRules.level_of(d, str(a))
		var lb := SpellRules.level_of(d, str(b))
		return la < lb or (la == lb and str(d["spells"].get(str(a), {}).get("name", a)) < str(d["spells"].get(str(b), {}).get("name", b))))
	return out


## A spell's icon: its card at the cursor (the right button pins it), dragged onto the hotbar; a click lists the circles
## to cast it with. One not prepared is dim and only told.
func _spell_cell(parent: Control, c: Dictionary, id: String, ready: bool) -> IconSlot:
	var d := Catalog.data
	var sp: Dictionary = d["spells"].get(id, {})
	var cell := IconSlot.make(IconRules.ref("spells", id), "", SPELL_CELL)
	cell.name = "Spell_" + id
	cell.text = "%s · %s" % [sp.get("casting_time", ""), sp.get("range", "")]
	if not ready:
		cell.text += "\n" + tr("BOOK_NOT_PREPARED")
		cell.disabled = true  # drawn faded by the cell itself; its card still comes on the hover
	cell.tooltip_text = cell.text
	parent.add_child(cell)
	_details.hook(cell, str(sp.get("name", id)), DetailsPanel.spell_text(d, id))
	if ready:
		cell.drag_key = "spell:" + id
		cell.pressed.connect(_cast_menu.bind(cell, c, id))
	return cell


## The circles to cast a spell with (the lowest fitting one first) and what each gives: [[circle, label]].
func _cast_options(c: Dictionary, id: String) -> Array:
	var d := Catalog.data
	var level := SpellRules.level_of(d, id)
	if SpellRules.free_now(c, d, id):
		return [[0, tr("SLOT_AT_WILL")]]  # an invocation's spell (v0.7.22.4)
	if level == 0:
		return [[0, tr("SLOT_CANTRIP")]]
	var out: Array = []
	for lv in range(level, 6):
		var left := SpellRules.slots_left(c, lv)
		if left > 0:
			var grown := SpellRules.at_slot(d, id, lv)  # v0.7.22.19 (#19): what the slot gives
			out.append([lv, tr("SLOT_CIRCLE").format({"n": lv, "left": left}) + (" — " + grown.get_slice(": ", 1) if not grown.is_empty() else "")])
	return out


## A click on a spell: «Колдовать» with each circle it may be cast with, grey with why.
func _cast_menu(cell: Control, c: Dictionary, id: String) -> void:
	var pop := ActsMenu.new()
	pop.name = "CastList_" + id
	var top := pop.list_of([])
	var can_act := Backend.is_ready() and not GameState.is_busy()
	var opts := _cast_options(c, id)
	if opts.is_empty():
		pop.add_act(top, tr("BOOK_NO_SLOTS"), "", true, Callable())
	for o: Array in opts:
		var circle := int(o[0])
		pop.add_act(top, "%s: %s" % [tr("BTN_CAST"), o[1]], "" if can_act else tr("ABILITY_BUSY"), not can_act, func() -> void: cast_spell(id, circle))
	cell.add_child(pop)
	pop.popup_hide.connect(pop.queue_free)
	pop.popup(Rect2i(Vector2i(cell.get_screen_position() + Vector2(0, cell.size.y)), Vector2i.ZERO))


## Casts a spell of the book with `circle` (0 — a cantrip or at will): a held concentration asks a second pick, Sending
## opens the letter (v0.8.4.26.3); done — the window closes, else a toast. "" or the reason.
func cast_spell(id: String, circle: int) -> String:
	var held := GameState.concentration_conflict(id)  # v0.7.13.1: the second pick breaks the old concentration
	var err := ""
	if not held.is_empty() and _conc_armed != id:
		_conc_armed = id
		err = tr("CONC_SWITCH_AGAIN").format({"old": held})
	elif not LetterRules.way_by(Catalog.data, "spell", id).is_empty():
		_conc_armed = ""
		EventBus.letter_requested.emit("")
	else:
		_conc_armed = ""
		err = GameState.cast(id, circle)
	if err.is_empty():
		visible = false
	else:
		EventBus.message.emit(tr(err))
	return err


## The class actions: each feature with uses (Stock) as an icon with what is left — a click uses it, sorcery points list
## their conversions; one spent by casting its spell only shows its uses.
func _class_acts(flow: HFlowContainer, c: Dictionary, can_act: bool) -> void:
	var d := Catalog.data
	for r: Dictionary in Stock.lines(c, d):
		var rid := str(r["id"])
		var feat := str((d["rules"]["resources"].get(rid, {}).get("features", [rid]) as Array)[0])
		var cell := IconSlot.make(IconRules.ref("features", feat), "", SPELL_CELL)
		cell.name = "Use_" + rid
		cell.badge = "%d/%d" % [int(r["left"]), int(r["max"])]
		cell.text = tr("SHEET_RESOURCE").format({"name": r["name"], "left": r["left"], "max": r["max"], "rest": tr("REST_KIND_" + str(r["recharge"]).to_upper())})
		cell.tooltip_text = cell.text
		cell.drag_key = "feature:" + rid
		flow.add_child(cell)
		_details.hook(cell, str(r["name"]), str(d["classes"]["features"].get(feat, {}).get("desc", "")))
		if Stock.table(d, c)[rid].has("spell"):  # spent by casting its spell (v0.8.4.26.1)
			continue
		var opts: Array = []  # [[label, why, do]]
		if rid == "sorcery_points":  # Font of Magic: slots and points (v0.7.10)
			for o: Dictionary in FeatureRules.font_options(c, d):
				opts.append([str(o["label"]), "", GameState.font_convert.bind(str(o["id"]))])
		else:
			opts.append([tr("BTN_USE"), "" if int(r["left"]) > 0 else tr("BOOK_NO_USES"), GameState.use_feature.bind(rid)])
		cell.pressed.connect(_use_menu.bind(cell, rid, opts, can_act))


## A click on a class action: its uses as a list, grey with why.
func _use_menu(cell: Control, rid: String, opts: Array, can_act: bool) -> void:
	var pop := ActsMenu.new()
	pop.name = "UseList_" + rid
	var top := pop.list_of([])
	for o: Array in opts:
		var stop := str(o[1]) if not str(o[1]).is_empty() else ("" if can_act else tr("ABILITY_BUSY"))
		var act: Callable = o[2]
		pop.add_act(top, str(o[0]), stop, not stop.is_empty(), func() -> void:
			var err: String = act.call()
			if err.is_empty():
				visible = false
			else:
				EventBus.message.emit(tr(err)))
	cell.add_child(pop)
	pop.popup_hide.connect(pop.queue_free)
	pop.popup(Rect2i(Vector2i(cell.get_screen_position() + Vector2(0, cell.size.y)), Vector2i.ZERO))


## «Общие» (as in BG3's book): the acts of a fight anybody has, by `Act.book`, under their buttons' keys — dragged onto the
## hotbar, one taken off it by chance comes back from here.
func _book_common(box: VBoxContainer) -> void:
	_text(box, tr("BOOK_COMMON_HINT"), UiTheme.MUTED_LABEL)
	var flow := HFlowContainer.new()
	flow.name = "BookCommon"
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	box.add_child(flow)
	var acts := Acts.all().filter(func(a: Act) -> bool: return a.tab() == "common" and a.book())
	acts.sort_custom(func(x: Act, y: Act) -> bool: return x.order() < y.order())
	for a: Act in acts:
		var cell := IconSlot.make(IconRules.ref("acts", a.id), "", SPELL_CELL + 8)
		cell.name = "BookAct_" + a.id
		cell.text = a.title()
		cell.tooltip_text = a.title()
		cell.drag_key = "Do_" + a.id
		flow.add_child(cell)
		_details.hook(cell, a.title(), a.tip())


## The reactions as in BG3's book (v0.8.4.43.7): each its icon and its own «Спрашивать / Всегда / Никогда», kept on the
## character (FeatureRules.reaction_list, GameState.choose_reaction); one not chosen yet goes by the settings' common
## choice. A companion is never asked: «Всегда» or «Никогда».
func _reactions(box: VBoxContainer) -> void:
	var s := GameState.session
	var me := Sheet.who(s, Catalog.data, who)
	_text(box, tr("SHEET_REACTIONS_HINT" if who == Being.HERO else "SHEET_REACTIONS_HINT_MATE"), UiTheme.MUTED_LABEL)
	var grid := GridContainer.new()
	grid.name = "ReactionRows"
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 6)
	box.add_child(grid)
	for r: Dictionary in FeatureRules.reaction_list(s, Catalog.data, me):
		var id := str(r["id"])
		var icon := IconSlot.make(str(r["icon"]), str(r["name"]), 44)
		icon.name = "Reaction_" + id
		grid.add_child(icon)
		_details.hook(icon, str(r["name"]), str(r["tip"]))
		var name_l := _text(grid, str(r["name"]))
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var row := HBoxContainer.new()
		row.name = "ReactionChoice_" + id
		row.add_theme_constant_override("separation", 4)
		row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		grid.add_child(row)
		for p: String in FeatureRules.POLICIES:
			if p == "ask" and who != Being.HERO:
				continue
			var b := Button.new()
			b.name = "React_%s_%s" % [id, p]
			b.text = "REACT_" + p.to_upper()
			b.toggle_mode = true
			b.button_pressed = str(r["policy"]) == p
			b.pressed.connect(func() -> void:
				var why := GameState.choose_reaction(id, p, who)
				if not why.is_empty():
					EventBus.message.emit(tr(why))
				_rebuild())
			row.add_child(b)


## Pact of the Blade (v0.8.4.33, as in BG3): what the pact weapon is, the forms to call and the weapons to bind, nested.
func _pact_rows(box: VBoxContainer, c: Dictionary, can_act: bool) -> void:
	var d := Catalog.data
	var opts := FeatureRules.pact_options(c, d, GameState.session.items)
	if opts.is_empty():
		return
	var now := FeatureRules.pact_item(c)
	_text(box, tr("PACT_NOW").format({"weapon": ItemRules.display_name(d["items"], GameState.session.items, now)}) if not now.is_empty() else tr("PACT_NONE"), UiTheme.MUTED_LABEL)
	var in_fight := CombatRules.active(GameState.session)
	var flow := HFlowContainer.new()
	flow.name = "PactOptions"
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 6)
	box.add_child(flow)
	for o: Dictionary in opts:
		var b := UiParts.act_button(flow, "Pact_" + str(o["id"]).replace(":", "_"), str(o["label"]), "" if can_act and not in_fight else ("PACT_IN_FIGHT" if in_fight else "ABILITY_BUSY"),
			GameState.pact_weapon.bind(str(o["id"])))
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED


## The form of the next familiar (v0.8.4.33): the special ones of Pact of the Chain among them.
func _familiar_rows(box: VBoxContainer, c: Dictionary, can_act: bool) -> void:
	var d := Catalog.data
	var opts := AllyRules.familiar_options(GameState.session, d, c)
	if opts.is_empty():
		return
	var now := AllyRules.familiar_form(GameState.session, d, c)
	_text(box, tr("FAMILIAR_FORM").format({"form": d["monsters"].get(now, {}).get("name", now)}), UiTheme.MUTED_LABEL)
	var flow := HFlowContainer.new()
	flow.name = "FamiliarForms"
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 6)
	box.add_child(flow)
	for o: Dictionary in opts:
		UiParts.act_button(flow, "Familiar_" + str(o["id"]), str(o["label"]), "" if can_act else "ABILITY_BUSY", GameState.choose_familiar.bind(str(o["id"])))


# --- «Развитие»: the life goal, faith, the peaceful directions ------------------------------------------------------


## The life goal (v0.7.22): the player's own words, the master's assessment, a field to change or clear it.
func _goal_section(box: VBoxContainer, c: Dictionary) -> void:
	_text(box, tr("GOAL_TITLE"), UiTheme.HEADING)
	_text(box, tr("GOAL_HINT"), UiTheme.MUTED_LABEL)
	var shown := GoalRules.text_of(c, Catalog.data, false)
	if not shown.is_empty():
		var l := _text(box, shown)
		l.name = "GoalText"
	var v := WorldView.new(Catalog.data["world"])
	var qid := GoalRules.quest_of(c)
	if not qid.is_empty():  # v0.8.4.36: the quest the clues led to
		var q := QuestRules.quest(Catalog.data["world"], qid)
		_text(box, tr("GOAL_QUEST").format({"title": q.get("title", qid), "giver": v.npc_name(str(q.get("giver", "")))})).name = "GoalQuest"
	if not GoalRules.clues(c).is_empty():
		_text(box, tr("GOAL_CLUES"), UiTheme.MUTED_LABEL)
		var i := 0
		for k: Dictionary in GoalRules.clues(c):
			var who_said := v.npc_name(str(k.get("npc", ""))) if not str(k.get("npc", "")).is_empty() else ""
			_text(box, tr("GOAL_CLUE").format({"day": int(k.get("day", 0)), "who": (who_said + ": ") if not who_said.is_empty() else "", "text": k["text"]})).name = "GoalClue%d" % i
			i += 1
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	var edit := LineEdit.new()
	edit.name = "GoalEdit"
	edit.placeholder_text = tr("GOAL_PLACEHOLDER")
	edit.text = str(GoalRules.goal(c).get("text", ""))
	edit.max_length = 240
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.custom_minimum_size = Vector2(0, 48)
	row.add_child(edit)
	var save := Button.new()
	save.name = "GoalSave"
	save.text = "BTN_GOAL_SAVE"
	save.disabled = GameState.is_busy()
	save.pressed.connect(func() -> void: GameState.set_goal(edit.text))
	row.add_child(save)
	var clear := Button.new()
	clear.name = "GoalClear"
	clear.text = "BTN_GOAL_CLEAR"
	clear.disabled = GameState.is_busy() or GoalRules.goal(c).is_empty()
	clear.pressed.connect(func() -> void: GameState.set_goal(""))
	row.add_child(clear)


## Faith (v0.7.49): the god and the favor, the vows with their gifts, what waits for the atonement.
func _faith_section(box: VBoxContainer, c: Dictionary) -> void:
	var s := GameState.session
	var data := Catalog.data
	if not FaithRules.on(data):
		return
	_text(box, tr("FAITH_SHEET_TITLE"), UiTheme.HEADING)
	var mine := FaithRules.hero_god(c)
	var l := _text(box, tr("FAITH_SHEET_GOD").format({"god": FaithRules.god_name(s, data, mine, true), "step": FaithRules.step_of(c, data, mine).get("name", ""),
		"favor": FaithRules.favor(c, mine), "law": FaithRules.god(s, data, mine).get("commandment", "")}) if not mine.is_empty() else tr("FAITH_SHEET_NO_GOD"))
	l.name = "FaithSheetGod"
	for vw: Dictionary in FaithRules.vows(c):
		var d := FaithRules.vow(data, str(vw["id"]))
		_text(box, "• %s — %s%s" % [d.get("name", vw["id"]), d.get("text", ""), tr("FAITH_SHEET_BROKEN") if int(vw.get("broken", -1)) >= 0 else ""])
	if FaithRules.lapsed(c):
		_text(box, tr("FAITH_SHEET_LAPSED"), UiTheme.MUTED_LABEL)
	var known := FaithRules.shrines_known(s, data)
	if not known.is_empty():
		var where: Array[String] = []
		for gid: String in known:
			where.append("%s — %s" % [FaithRules.god_name(s, data, gid), ", ".join((known[gid] as Array).map(func(r: Variant) -> String: return str(GameState.world().room(str(r)).get("name", r))))])
		_text(box, tr("FAITH_SHEET_SHRINES").format({"list": "; ".join(where)}), UiTheme.MUTED_LABEL)


## Peaceful development (v0.7.19.1): each direction — its level and experience, the skills taken, and on a level not
## yet paid — the skills to pick from, like the class's level-up.
func _development(c: Dictionary) -> void:
	var box := _page("%DevBox")
	var data := Catalog.data
	_goal_section(box, c)  # v0.7.22
	_faith_section(box, c)  # v0.7.49
	_text(box, tr("DEV_HINT"), UiTheme.MUTED_LABEL)
	for dir: String in DevelopmentRules.cfg(data)["directions"]:
		var d := DevelopmentRules.direction(data, dir)
		var next := DevelopmentRules.next_xp(c, data, dir)
		_text(box, tr("DEV_DIRECTION").format({"name": d["name"], "level": DevelopmentRules.level(c, data, dir), "xp": DevelopmentRules.xp(c, dir),
			"next": next if next >= 0 else "—"}), UiTheme.HEADING)
		for id: Variant in DevelopmentRules.skills(c, dir):
			var sk: Dictionary = d["skills"].get(str(id), {})
			_text(box, "• %s — %s" % [sk.get("name", id), sk.get("desc", "")])
		var choices := DevelopmentRules.choices(c, data, dir)
		if not choices.is_empty():
			_text(box, tr("DEV_PICK"), UiTheme.MUTED_LABEL)
		for id: String in choices:
			var sk: Dictionary = d["skills"][id]
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 12)
			box.add_child(row)
			_text(row, "%s — %s" % [sk["name"], sk.get("desc", "")])
			var b := Button.new()
			b.name = "DevPick_%s_%s" % [dir, id]
			b.text = "BTN_DEV_PICK"
			b.disabled = GameState.is_busy()
			var pick_dir := dir
			var pick_id := id
			b.pressed.connect(func() -> void:
				var err := GameState.pick_development(pick_dir, pick_id)
				if not err.is_empty():
					EventBus.message.emit(tr(err)))
			row.add_child(b)
