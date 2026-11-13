class_name DollView
extends VBoxContainer
## The doll of the character window (v0.8.4.43.6, as in BG3) for anybody who wears things — the hero or a companion: the
## worn slots in two columns round a figure, the two weapon sets with the AC on a shield between them and under each set
## its attack bonus and damage (Gear.set_blow), the belt under it all. A slot is a cell: a drag from the grid puts the
## thing on, a drag back takes it off, the left button lists what fits, the right one the thing's acts (ItemActs). The
## window does every act (`act`) and shows every menu (`menu`); the rules are Equip's and ItemRules'.

signal act(row: Dictionary)  ## a row of ItemActs to do now
signal menu(cell: ItemCell, rows: Array)  ## the right button's acts of a cell

const LEFT: Array[String] = ["head", "cloak", "armor", "hands", "feet"]
const RIGHT: Array[String] = ["eyes", "neck", "ring1", "ring2"]
const SIDE := 60

var who := Being.HERO
var details: DetailsPanel  ## the window's card at the cursor: the numbers' breakdown


func _init() -> void:
	name = "Doll"
	add_theme_constant_override("separation", 10)


## Builds it again for `who` (Being.HERO or a companion's id).
func show_of(id: String) -> void:
	who = id
	for ch in get_children():
		remove_child(ch)
		ch.queue_free()
	var s := GameState.session
	var data := Catalog.data
	var c := Gear.of(s, data, who)
	var body := HBoxContainer.new()
	body.name = "DollBody"
	body.add_theme_constant_override("separation", 12)
	body.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(body)
	for side: Array in [["DollLeft", LEFT], ["DollFigure", []], ["DollRight", RIGHT]]:
		if (side[1] as Array).is_empty():
			var fig := DollFigure.new()
			fig.name = "DollFigure"
			fig.custom_minimum_size = Vector2(150, 0)
			fig.size_flags_vertical = Control.SIZE_EXPAND_FILL
			body.add_child(fig)
			continue
		var col := VBoxContainer.new()
		col.name = side[0]
		col.add_theme_constant_override("separation", 6)
		body.add_child(col)
		for slot: String in side[1]:
			col.add_child(_slot(c, slot, false))
	add_child(_sets(c))
	add_child(_belt(c))


## A slot of the doll: what is worn there, or its faded picture; `spare` — a hand of the set put away.
func _slot(c: Dictionary, slot: String, spare: bool) -> ItemCell:
	var s := GameState.session
	var data := Catalog.data
	var hands: Dictionary = CharacterRules.stowed(c) if spare else c.get("equipped", {})
	var id := str(hands.get(slot, ""))
	var where := {"kind": "slot", "who": who, "slot": slot, "spare": spare}
	var held := not spare and slot == "off_hand" and id.is_empty() and CharacterRules.two_hand_grip(c, data, s.items)
	var cell := ItemCell.of(IconRules.ref("items", id) if not id.is_empty() else "slots/" + slot, id, 1, where, SIDE)
	cell.name = ("Stowed_" if spare else "Slot_") + slot
	cell.faded = id.is_empty()
	cell.tip_title = tr("SLOT_" + slot.to_upper())
	if held:  # the main hand's weapon in both hands: the off hand is taken by it
		var main := str(hands.get("main_hand", ""))
		cell.set_icon(IconRules.ref("items", main))
		cell.text = tr("SLOT_HELD_BY").format({"name": ItemRules.display_name(data["items"], s.items, main)})
	elif id.is_empty():
		cell.text = tr("STOWED_EMPTY_TIP") if spare else tr("SLOT_EMPTY")
	else:
		cell.tip_title = ItemRules.display_name(data["items"], s.items, id)
		cell.text = tr("SLOT_" + slot.to_upper())
		cell.set_card(CardInfo.item(c, data, s.items, id))
		var shots := Gear.ready_shots(data, s.items, c, id)
		if shots >= 0:  # v0.8.4.42.6: the shots at hand on the bow's cell
			cell.badge = str(shots)
			cell.text += " · " + tr("AMMO_READY").format({"n": shots})
	cell.tooltip_text = cell.text
	cell.accept = func(drag: Dictionary) -> bool:
		return Equip.why(s, data, who, str(drag["item"]), slot, spare).is_empty() and _mine(drag)
	cell.take = func(drag: Dictionary) -> void:
		act.emit({"act": "equip", "item": str(drag["item"]), "slot": slot, "spare": spare})
	cell.pressed.connect(_list.bind(cell, slot, spare))
	if not id.is_empty():
		cell.on_double = func() -> void: act.emit({"act": "unequip", "item": id, "slot": slot, "spare": spare})  # off, as in BG3
		cell.on_menu = func(at: ItemCell) -> void: menu.emit(at, ItemActs.of(s, data, who, id, slot, spare))
	return cell


## A thing of this character's own (its grid, its doll): what the doll takes.
func _mine(drag: Dictionary) -> bool:
	var from: Dictionary = drag.get("from", {})
	return str(from.get("who", "")) == who and str(from.get("kind", "")) in ["things", "slot"]


## The left button on a slot: what may be worn there, grey with why (BG3: the list stays as things are put on).
func _list(cell: ItemCell, slot: String, spare: bool) -> void:
	var s := GameState.session
	var data := Catalog.data
	var c := Gear.of(s, data, who)
	var pop := ActsMenu.new()
	pop.name = "SlotList_" + slot
	var top := pop.list_of([])
	var any := false
	for id: String in c.get("inventory", {}):
		if not CharacterRules.slots_of(ItemRules.def_of(data["items"], s.items, id), data).has(slot):
			continue
		if str((CharacterRules.stowed(c) if spare else c.get("equipped", {})).get(slot, "")) == id:
			continue
		any = true
		var why := Equip.why(s, data, who, id, slot, spare)
		pop.add_act(top, ItemRules.display_name(data["items"], s.items, id), tr(why) if not why.is_empty() else "", not why.is_empty(),
			func() -> void: act.emit({"act": "equip", "item": id, "slot": slot, "spare": spare}))
	if not any:
		pop.add_act(top, tr("SLOT_PICK_NONE"), "", true, Callable())
	cell.add_child(pop)
	pop.popup_hide.connect(pop.queue_free)
	pop.popup(Rect2i(Vector2i(cell.get_screen_position() + Vector2(0, cell.size.y)), Vector2i.ZERO))


## The two weapon sets as in BG3: the two hands of each (a shield in the off hand, v0.8.4.43.13), the AC on a shield
## between, the attack bonus and the damage under each.
func _sets(c: Dictionary) -> Control:
	var s := GameState.session
	var data := Catalog.data
	var row := HBoxContainer.new()
	row.name = "WeaponSets"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	for spare: bool in [false, true]:
		var col := VBoxContainer.new()
		col.name = "SetStowed" if spare else "SetHeld"
		col.add_theme_constant_override("separation", 4)
		var head := UiParts.label(col, tr("SET_STOWED" if spare else "SET_IN_HAND"), UiTheme.MUTED_LABEL)
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		head.autowrap_mode = TextServer.AUTOWRAP_OFF  # two hands are narrower than the words over them
		head.add_theme_font_size_override("font_size", UiTheme.SIZE_SMALL - 2)
		var frame := PanelContainer.new()  # the set in the hands is lit
		frame.add_theme_stylebox_override("panel", UiTheme.box(Color(0, 0, 0, 0), UiTheme.ACCENT if not spare else UiTheme.BORDER.darkened(0.2), 2, 4, 5))
		col.add_child(frame)
		var hands := HBoxContainer.new()
		hands.add_theme_constant_override("separation", 4)
		frame.add_child(hands)
		for slot: String in CharacterRules.HANDS:
			hands.add_child(_slot(c, slot, spare))
		col.add_child(_numbers(Gear.set_blow(s, data, who, spare), spare))
		row.add_child(col)
		if not spare:
			row.add_child(_shield(c))
	return row


## «+5» and «4~11» under a set, the breakdown at the cursor.
func _numbers(b: Dictionary, spare: bool) -> Control:
	var grid := GridContainer.new()
	grid.name = "SetNumbersStowed" if spare else "SetNumbers"
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	if b.is_empty():
		return grid
	for spec: Array in [["SetHit", "%+d" % int(b["to_hit"]), "SET_ATTACK"], ["SetDamage", "%d~%d" % [int(b["low"]), int(b["high"])], "SET_DAMAGE"]]:
		var v := UiParts.label(grid, str(spec[1]))
		v.name = str(spec[0]) + ("Stowed" if spare else "")
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_theme_font_size_override("font_size", UiTheme.SIZE_BODY)
		v.add_theme_color_override("font_color", UiTheme.ACCENT_BRIGHT)
		v.mouse_filter = Control.MOUSE_FILTER_STOP
		var body := _parts_text(b["parts"], int(b["to_hit"])) if str(spec[0]) == "SetHit" else str(b["damage"])
		if details != null:
			details.hook(v, "%s · %s" % [tr(str(spec[2])), b["name"]], body)
		else:
			v.tooltip_text = body
	for key: String in ["SET_ATTACK", "SET_DAMAGE"]:
		var cap := UiParts.label(grid, tr(key), UiTheme.MUTED_LABEL)
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cap.add_theme_font_size_override("font_size", UiTheme.SIZE_SMALL - 4)
	return grid


## «+3 Сила\n+2 владение оружием\n= +5».
static func _parts_text(parts: Array, total: int) -> String:
	var lines: Array[String] = []
	for p: Variant in parts:
		lines.append("%+d %s" % [int(p["value"]), p["label"]])
	lines.append("= %+d" % total)
	return "\n".join(lines)


## The AC on a shield between the sets, the swap of the sets under it.
func _shield(c: Dictionary) -> Control:
	var s := GameState.session
	var data := Catalog.data
	var col := VBoxContainer.new()
	col.name = "ArmorClass"
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 6)
	var ac := Sheet.ac(s, Sheet.who(s, data, who), data)
	var shield := Control.new()
	shield.name = "AcShield"
	shield.custom_minimum_size = Vector2(64, 74)
	shield.mouse_filter = Control.MOUSE_FILTER_STOP
	shield.draw.connect(func() -> void:
		var w := shield.size.x
		var h := shield.size.y
		var pts := PackedVector2Array([Vector2(4, 4), Vector2(w - 4, 4), Vector2(w - 4, h * 0.55), Vector2(w / 2, h - 3), Vector2(4, h * 0.55)])
		shield.draw_colored_polygon(pts, UiTheme.PANEL_RAISED)
		shield.draw_polyline(pts + PackedVector2Array([pts[0]]), UiTheme.ACCENT, 2.0, true)
		var font := shield.get_theme_font("font", "Label")
		var t := str(ac)
		var sz := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 30)
		shield.draw_string(font, Vector2((w - sz.x) / 2, h * 0.52), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, UiTheme.ACCENT_BRIGHT)
		var cap := tr("SHEET_AC_SHORT")
		var cs := font.get_string_size(cap, HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
		shield.draw_string(font, Vector2((w - cs.x) / 2, h * 0.75), cap, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UiTheme.MUTED))
	var worn: Array[String] = []
	var eq: Dictionary = c.get("equipped", {})
	for id: String in [str(eq.get("armor", "")), CharacterRules.shield_in(eq, data, s.items)]:
		if not id.is_empty():
			worn.append(ItemRules.display_name(data["items"], s.items, id))
	if details != null:
		details.hook(shield, tr("SHEET_AC_TITLE").format({"ac": ac}), tr("SHEET_AC_WORN").format({"list": ", ".join(worn) if not worn.is_empty() else tr("SHEET_AC_BARE")}))
	col.add_child(shield)
	var why := Equip.swap_why(s, data, who)
	var swap := IconSlot.make(IconRules.button(data, "SwapSets"), tr("SWAP_WEAPONS"), 40)
	swap.name = "SwapWeapons"
	swap.disabled = not why.is_empty()
	swap.tooltip_text = Hotkeys.tip(tr("SWAP_WEAPONS"), "swap_weapons", SaveManager.keys) if why.is_empty() else tr(why)
	swap.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	swap.pressed.connect(func() -> void:
		(func() -> void:  # the doll is laid again: never under the press
			var err := GameState.swap_weapons() if who == Being.HERO else GameState.gear_act("swap", who, "")
			if not err.is_empty():
				EventBus.message.emit(tr(err))).call_deferred())
	col.add_child(swap)
	return col


## The belt under the doll (v0.8.4.24, as in Pathfinder): five cells of the things at hand; a drag from the grid lays a
## thing there, a drag back takes it off, a double click uses it.
func _belt(c: Dictionary) -> Control:
	var s := GameState.session
	var data := Catalog.data
	var box := VBoxContainer.new()
	box.name = "BeltBox"
	box.add_theme_constant_override("separation", 4)
	var head := UiParts.label(box, tr("SHEET_BELT"), UiTheme.MUTED_LABEL)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.tooltip_text = tr("BELT_USE_TIP")
	head.mouse_filter = Control.MOUSE_FILTER_PASS
	var cells := HBoxContainer.new()
	cells.name = "BeltCells"
	cells.alignment = BoxContainer.ALIGNMENT_CENTER
	cells.add_theme_constant_override("separation", 4)
	box.add_child(cells)
	var belt := ItemRules.belt(c, data, s.items)
	var mine := who == Being.HERO  # the belt of a companion is read only: it uses what is there by itself
	for i: int in belt.size():
		var id := belt[i]
		var qty := int(c.get("inventory", {}).get(id, 0))
		var cell := ItemCell.of(IconRules.ref("items", id) if not id.is_empty() else "slots/belt", id, qty, {"kind": "belt", "who": who, "at": i}, SIDE)
		cell.name = "Belt_%d" % i
		cell.faded = id.is_empty()
		if id.is_empty():
			cell.tip_title = tr("SHEET_BELT")
			cell.text = tr("BELT_EMPTY_TIP")
		else:
			cell.tip_title = ItemRules.display_name(data["items"], s.items, id)
			cell.text = ItemGrid.line(id, qty)
			cell.set_card(CardInfo.item(c, data, s.items, id))
		cell.tooltip_text = cell.text
		if mine:
			var at := i
			cell.accept = func(drag: Dictionary) -> bool:
				return str(drag.get("from", {}).get("kind", "")) == "things" and ItemRules.belt_why(c, data, s.items, str(drag["item"]), at).is_empty()
			cell.take = func(drag: Dictionary) -> void: act.emit({"act": "belt", "item": str(drag["item"]), "at": at})
			if not id.is_empty():
				var rows := _belt_rows(c, id, at)
				cell.on_double = func() -> void:
					if str(rows[0]["why"]).is_empty() and str(rows[0]["act"]) == "use":
						act.emit(rows[0])
				cell.on_menu = func(at_cell: ItemCell) -> void: menu.emit(at_cell, rows)
		cells.add_child(cell)
	var unfed := Gear.unfed(data, s.items, c)  # a bow with nothing to shoot on the belt (v0.8.4.42.1)
	if not unfed.is_empty():
		var warn := UiParts.label(box, tr("BELT_NO_AMMO").format({"weapons": ", ".join(unfed.map(func(x: String) -> String:
			return ItemRules.display_name(data["items"], s.items, x)))}), UiTheme.WARN_LABEL)
		warn.name = "BeltNoAmmo"
		warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return box


## A belt cell's acts: use it (grey with why), take it off the belt.
func _belt_rows(c: Dictionary, id: String, at: int) -> Array[Dictionary]:
	var s := GameState.session
	var rows: Array[Dictionary] = []
	if not ItemRules.consumable(Catalog.data, id, s.items).is_empty():
		var why := ItemRules.can_use(c, Catalog.data, s.items, id)
		rows.append({"act": "use", "item": id, "name": "BeltUse_%d" % at, "label": "BTN_USE", "args": {}, "group": "",
			"why": why if not why.is_empty() else ("" if Backend.is_ready() else "ABILITY_BUSY")})
	rows.append({"act": "belt_take", "item": id, "at": at, "name": "BeltTake_%d" % at, "label": "BTN_BELT_TAKE", "args": {}, "group": "", "why": ""})
	return rows
