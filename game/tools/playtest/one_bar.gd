extends "res://tools/playtest/playtest_base.gd"
## One bar in a fight and out of it (python tools/godot_playtest.py --scenario one_bar, v0.8.4.43.14), the author's
## findings on 0.8.4.43.8: «вся эта панель должна быть идентична как в бою, так и вне боя. Как в BG3» — the section
## «Боевые» out of a fight with the fight's acts grey in their slots; «Дела» at the Pushcha edge — square cells inside the
## grid, each gathering spot by its own thing; a cell dragged on a tab that shows one kind; a divider that follows the
## mouse while held and snaps to the nearest column when let go; in a fight a spell and «Рывок» in the same slots, the
## place's acts grey there, a cell dragged on the fight's tab.

const FOREST := "pushcha-edge"


func run() -> void:
	var gs := node("GameState")
	node("SaveManager").hotbar = {}  # the bar as a new player sees it
	if not step("master connected", await wait_until(func() -> bool: return node("Backend").is_ready(), 30.0)):
		return
	await tap("NewGameButton")
	await tap("NextButton")
	await tap("Preset_cleric_branko")
	await press(find(screen(), "StartButton"))
	if not step("game started", await wait_until(func() -> bool: return screen_is("GameScreen") and not gs.is_busy(), 90.0)):
		return
	var s: GameSession = gs.session
	s.settings["needs"] = false
	still_sky(s)
	s.minute = 10 * 60
	s.room_id = FOREST
	node("EventBus").state_changed.emit()
	await frames(8)
	var bar := screen().get_tree().get_first_node_in_group("hotbar") as Control
	bar.call("set_filter", "")
	await frames(4)

	# «Боевые» out of a fight.
	var dash := find(bar, "Ghost_Do_dash") as IconSlot
	var tab := find(bar, "Filter_combat") as Button
	step("«Боевые» out of a fight: the fight's acts grey in their own section", dash != null and dash.disabled and dash.is_visible_in_tree()
		and tab != null and tab.visible and _section_of(dash) == _layout_section("combat"),
		"нет «Рывка»" if dash == null else "секция %d из %d" % [_section_of(dash), _layout_section("combat")])
	step("its card names it and says «Только в бою»", dash != null and dash.tip_title == Acts.one("dash").title() and dash.tooltip_text.contains("Только в бою"),
		dash.tooltip_text if dash != null else "")
	var dash_at := _where(dash)
	var spell := _first_spell()
	var spell_at := _where(find(bar, "Pin_spell_" + spell) as Control)
	step("a spell of the hero in a slot of its own", not spell.is_empty() and spell_at[0] >= 0, spell)
	await shot("bar_peace")

	# «Дела» at the Pushcha edge.
	bar.call("set_filter", "deeds")
	await frames(4)
	var grid := find(bar, "Kind_deeds") as Control
	var deeds: Array = grid.find_children("*", "IconSlot", true, false) if grid != null else []
	var scroll := find(bar, "Cells") as Control
	var square := deeds.all(func(c: IconSlot) -> bool: return c.size.x <= _const(bar, "CELL") + 1 and c.size.y <= _const(bar, "CELL") + 1)
	var inside := deeds.all(func(c: IconSlot) -> bool: return c.get_global_rect().end.x <= scroll.get_global_rect().end.x + 1)
	step("«Дела»: every cell one square inside the grid", not deeds.is_empty() and square and inside,
		", ".join(deeds.map(func(c: IconSlot) -> String: return "%s %dx%d" % [c.name, c.size.x, c.size.y])))
	var gather := deeds.filter(func(c: IconSlot) -> bool: return str(c.name).begins_with("Gather_"))
	var refs := {}
	for c: IconSlot in gather:
		refs[str(c.spec.get("ref", ""))] = true
	step("each gathering spot by its own thing's icon", gather.size() > 1 and refs.size() == gather.size(),
		", ".join(gather.map(func(c: IconSlot) -> String: return "%s → %s" % [c.name, c.spec.get("ref", "")])))
	var names := {}
	for c: IconSlot in deeds:
		names[str(c.drag_key)] = int(names.get(str(c.drag_key), 0)) + 1
	step("no act twice", names.values().all(func(n: int) -> bool: return n == 1), str(names))
	await shot("deeds_tab")

	# A cell dragged on the tab that shows «Дела» alone.
	var cell: IconSlot = deeds[0] if not deeds.is_empty() else null
	var empty := _empty_slot(grid)
	if step("a cell of the tab can be dragged", cell != null and not cell.drag_key.is_empty() and empty != null):
		var key := cell.drag_key
		var at := [empty.section, empty.index]
		empty._drop_data(Vector2.ZERO, {"hotbar": cell.drag_key})  # what the cell's drag carries
		await frames(4)
		step("the tab is still «Дела»", str(bar.call("current")) == "deeds")
		await shot("deeds_dragged")
		bar.call("set_filter", "")
		await frames(4)
		var moved := find(bar, key) as Control  # v0.8.4.43.49: a slot past the bar's sight gives the first free one in it
		step("dropped past the bar's sight on the tab, it stands in sight of the whole bar in its section", moved != null and moved.is_visible_in_tree()
			and int(_where(moved)[0]) == int(at[0]), "%s: %s, с вкладки %s" % [key, str(_where(moved)), str(at)])
		await shot("whole_bar_after_drop")

	# A divider: the edge of the card on its right — the card and its icons go with the mouse (v0.8.4.43.51).
	bar.call("set_filter", "")
	await frames(4)
	var di := 0  # the first divider with a column to take from its right neighbour (cells of 72 leave fewer to share)
	while di + 2 < _drawn().size() and HotbarLayout.reach(node("SaveManager").hotbar, HotbarLayout.BAR, di, 2) <= 0:
		di += 1
	var pad := find(bar, "Divider_%d" % di) as Control
	var line := find(pad, "Line") as Control if pad != null else null
	if step("a divider with room to move", line != null and HotbarLayout.reach(node("SaveManager").hotbar, HotbarLayout.BAR, di, 2) > 0, "Divider_%d" % di):
		var stepw := float(_const(bar, "CELL") + _const(bar, "GAP"))
		var cols0 := _cols(di)
		var can := HotbarLayout.reach(node("SaveManager").hotbar, HotbarLayout.BAR, di, 2)
		var right := _first_icon(di + 1)  # the right card's first icon: it goes with the edge
		var x_icon := right.get_global_rect().position.x if right != null else 0.0
		var right_name := str(right.name) if right != null else ""  # a ghost cell is made anew by every laying: by its name
		var x0 := line.get_global_rect().get_center().x
		var y := pad.get_global_rect().get_center().y  # the strip is laid anew under the mouse: its height kept
		_mouse(pad, x0, true)  # v0.8.4.43.49: the whole strip takes the mouse
		for k in 8:
			bar.call("held_input", _move_event(Vector2(x0 + stepw * 1.6 * (k + 1) / 8.0, y)))
			await frames(2)
		await frames(3)
		var moved := find(bar, right_name) as Control if not right_name.is_empty() else null  # the same icon, wherever it went
		step("held: the card goes with the mouse column by column, its icons with it", _cols(di) == cols0 + can and moved != null
			and absf(moved.get_global_rect().position.x - x_icon - can * stepw) < 2.0,
			"%d → %d; %.0f → %.0f" % [cols0, _cols(di), x_icon, moved.get_global_rect().position.x if moved != null else -1.0])
		await shot("divider_held")
		bar.call("held_input", _up_event(Vector2(x0 + stepw * 1.6, y)))
		await frames(5)
		step("let go it stays at the nearest column", _cols(di) == cols0 + can, "%d → %d (можно %d)" % [cols0, _cols(di), can])
		pad = find(bar, "Divider_%d" % di) as Control
		line = find(pad, "Line") as Control if pad != null else null
		var cols1 := _cols(di)
		if line != null:
			var x1 := line.get_global_rect().get_center().x
			_mouse(pad, x1, true)
			bar.call("held_input", _move_event(Vector2(x1 + stepw * 0.4, y)))
			bar.call("held_input", _up_event(Vector2(x1 + stepw * 0.4, y)))
			await frames(5)
		step("a little nudge stays where it was", _cols(di) == cols1, "%d → %d" % [cols1, _cols(di)])
		var sec: Dictionary = _drawn()[di]
		step("the width is the player's: kept", bool(sec.get("fixed", false)) and int(sec.get("width", 0)) == cols0 + can, str(sec))
		await shot("divider_let_go")
	dash_at = _where(find(bar, "Ghost_Do_dash") as Control)
	spell_at = _where(find(bar, "Pin_spell_" + spell) as Control)

	# The fight: the same bar.
	gs.start_combat([{"monster": "wolf", "beside": true}])
	if not step("a fight with a wolf", await wait_until(func() -> bool: return _my_turn(gs, s), 120.0)):
		return
	bar = screen().get_tree().get_first_node_in_group("hotbar") as Control
	bar.call("set_filter", "")
	await frames(6)
	var real_dash := find(bar, "Do_dash") as Control
	step("in the fight «Рывок» stands in the slot it stood in grey", real_dash != null and _where(real_dash) == dash_at,
		"%s ≠ %s" % [str(_where(real_dash)), str(dash_at)])
	var cast := find(bar, "Cast_" + spell) as Control
	step("the spell in the same slot as out of the fight", cast != null and _where(cast) == spell_at, "%s ≠ %s" % [str(_where(cast)), str(spell_at)])
	var ghosts := bar.find_children("Ghost_*", "IconSlot", true, false).filter(func(g: Node) -> bool: return (g as Control).is_visible_in_tree())
	step("the place's acts grey in the fight, «Не в бою»", not ghosts.is_empty() and ghosts.all(func(g: IconSlot) -> bool: return g.disabled and g.tooltip_text.contains("Не в бою")),
		", ".join(ghosts.map(func(g: Node) -> String: return str(g.name))))
	await shot("bar_fight")

	var fight_cols := _drawn().map(func(sec: Dictionary) -> int: return int(sec["cols"]))
	bar.call("set_filter", "combat")
	await frames(4)
	var cgrid := find(bar, "Kind_combat") as Control
	real_dash = find(bar, "Do_dash") as Control
	var spot := _empty_slot(cgrid)
	if step("the fight's tab «Боевые»: a cell can be dragged", real_dash is IconSlot and not (real_dash as IconSlot).drag_key.is_empty() and spot != null):
		var to := [spot.section, spot.index]
		spot._drop_data(Vector2.ZERO, {"hotbar": (real_dash as IconSlot).drag_key})
		await frames(4)
		await shot("fight_tab_dragged")
		bar.call("set_filter", "")
		await frames(4)
		var dash_cell := find(bar, "Do_dash") as Control
		step("«Рывок» moved on the fight's tab stands in sight of the whole bar", dash_cell != null and dash_cell.is_visible_in_tree() and int(_where(dash_cell)[0]) == int(to[0]), str(_where(dash_cell)))

	# The fight over: the dividers where they stood in it.
	var data: Dictionary = node("Catalog").data
	for fid: String in CombatRules.enemies(s):
		var lines: Array[String] = []
		Harm.take(s, data, CombatRules.fighter(s, fid), 999, lines)
	CombatRules.after_player_action(s, data)
	await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
	gs.finish_combat()
	await wait_until(func() -> bool: return screen_is("GameScreen") and not gs.is_busy(), 60.0)
	bar = screen().get_tree().get_first_node_in_group("hotbar") as Control
	bar.call("set_filter", "")
	await frames(6)
	var peace_cols := _drawn().map(func(sec: Dictionary) -> int: return int(sec["cols"]))
	step("after the fight the sections as wide as in it", peace_cols == fight_cols, "%s / %s" % [str(peace_cols), str(fight_cols)])
	await shot("bar_after_fight")


func _my_turn(gs: Node, s: GameSession) -> bool:
	return screen_is("fight") and not gs.is_busy() and not gs.combat_playing and CombatRules.player_can_act(s)


## A constant of the bar's script: its class name is not known to a playtest's script while the autoloads are not.
func _const(bar: Node, c: String) -> int:
	return int((bar.get_script() as Script).get_script_constant_map()[c])


func _hb() -> Dictionary:
	return node("SaveManager").hotbar


## [the layout's section, its slot] of a cell of the bar; [-1, -1] off the grid.
func _where(c: Control) -> Array:
	if c == null or not (c.get_parent() is HotSlot):
		return [-1, -1]
	var slot := c.get_parent() as HotSlot
	return [slot.section, slot.index]


func _section_of(c: Control) -> int:
	return int(_where(c)[0])


## The sections drawn now: the index a slot's `section` means.
func _drawn() -> Array:
	return (HotbarLayout.mode(_hb(), HotbarLayout.BAR)["sections"] as Array).filter(func(sec: Dictionary) -> bool: return int(sec["cols"]) > 0)


func _layout_section(kind: String) -> int:
	var secs: Array = _drawn()
	for i in secs.size():
		if str(secs[i]["kind"]) == kind:
			return i
	return -1


func _cols(i: int) -> int:
	var g := find(screen(), "Kind_" + str(_drawn()[i]["kind"])) as GridContainer
	return g.columns if g != null else -1


func _first_spell() -> String:
	var bar := screen().get_tree().get_first_node_in_group("hotbar") as Control
	for c: Node in bar.find_children("Pin_spell_*", "", true, false):
		if c.get_parent() is HotSlot:
			return str(c.name).trim_prefix("Pin_spell_")
	return ""


func _empty_slot(grid: Control) -> HotSlot:
	if grid == null:
		return null
	var slots := grid.get_children().filter(func(n: Node) -> bool: return n is HotSlot and n.get_child_count() == 0)
	return slots.back() if not slots.is_empty() else null


func _mouse(on: Control, x: float, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.global_position = Vector2(x, on.get_global_rect().get_center().y)
	on.gui_input.emit(e)


## A move of the mouse with the button held, as a real drag; the bar takes it wherever it is (ActionBar.held_input).
func _move_event(at: Vector2) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	e.global_position = at
	return e


func _up_event(at: Vector2) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = false
	e.global_position = at
	return e


## The first icon in sight of drawn section `i`: the cell in its slot of the lowest index.
func _first_icon(i: int) -> Control:
	var g := find(screen(), "Kind_" + str(_drawn()[i]["kind"])) as GridContainer
	if g == null:
		return null
	for slot: Node in g.get_children():
		for c: Node in slot.get_children():
			if c is Control and (c as Control).visible:
				return c as Control
	return null
