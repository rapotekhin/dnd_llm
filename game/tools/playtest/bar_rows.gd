extends "res://tools/playtest/playtest_base.gd"
## The hotbar's rows by «+» and «−» (python tools/godot_playtest.py --scenario bar_rows, v0.8.4.43.39), the author: «что
## происходит с UI при увеличении … по щелчку +. Ничего не ломается?» — from two rows to four and down to one, in the
## world and in a fight: every cell inside the grid, the tabs and the plaque on the frame's edge, the bar on the screen,
## the map not crushed, the character window still ending over the bar.

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
	var bar := _bar()
	var tall := bar.size.y
	await _check(2, "peace")

	for n in [3, 4]:
		await press(find(bar, "RowsMore") as BaseButton)
		await frames(8)
		await _check(n, "peace")
		await shot("rows_%d" % n)
	step("the bar grows with its rows", _bar().size.y > tall, "%d → %d" % [tall, _bar().size.y])
	await press(find(bar, "RowsMore") as BaseButton)  # past the most
	await frames(6)
	step("«+» past four rows keeps four", _rows() == 4, str(_rows()))

	# The character window ends over the taller bar.
	await tap("SheetButton")
	await frames(10)
	var sheet := screen().get_tree().root.find_child("CharacterSheet", true, false) as Control
	var panel: Control = sheet.get("_panel") if sheet != null else null
	step("the character window ends over the bar of four rows", panel != null and panel.get_global_rect().end.y <= _bar().get_global_rect().position.y + 1,
		"окно до %d, панель с %d" % [panel.get_global_rect().end.y if panel != null else -1, _bar().get_global_rect().position.y])
	await shot("sheet_over_four_rows")
	if sheet != null:
		sheet.visible = false
	await frames(4)

	# A fight with four rows.
	gs.start_combat([{"monster": "wolf", "beside": true}])
	if not step("a fight with a wolf", await wait_until(func() -> bool: return screen_is("fight") and not gs.is_busy() and not gs.combat_playing and CombatRules.player_can_act(s), 120.0)):
		return
	await frames(8)
	await _check(4, "fight")
	var end := find(_bar(), "EndTurnButton") as Control
	step("the hourglass inside the frame in a fight", end != null and end.is_visible_in_tree() and _inside(end), _rect(end))
	await shot("fight_rows_4")

	# Down to one row.
	for n in [3, 2, 1]:
		await press(find(_bar(), "RowsLess") as BaseButton)
		await frames(8)
		await _check(n, "fight")
	await press(find(_bar(), "RowsLess") as BaseButton)  # past the least
	await frames(6)
	step("«−» past one row keeps one", _rows() == 1, str(_rows()))
	await shot("fight_rows_1")
	await press(find(_bar(), "RowsMore") as BaseButton)
	await frames(8)
	await _check(2, "fight")
	await shot("fight_rows_2_again")


func _bar() -> Control:
	return screen().get_tree().get_first_node_in_group("hotbar") as Control


func _rows() -> int:
	return HotbarLayout.rows(node("SaveManager").hotbar)


func _const(c: String) -> int:
	return int((_bar().get_script() as Script).get_script_constant_map()[c])


## The frame's top line: the bar's top past the heads of its edge.
func _frame_top() -> float:
	return _bar().get_global_rect().position.y + float(_bar().get("line"))


func _inside(c: Control) -> bool:
	var r := c.get_global_rect()
	var b := _bar().get_global_rect()
	return r.position.y >= _frame_top() - 1 and r.end.y <= b.end.y + 1 and r.position.x >= b.position.x - 1 and r.end.x <= b.end.x + 1


func _rect(c: Control) -> String:
	return "нет" if c == null else "%s" % c.get_global_rect()


## Everything of the bar in its place with `n` rows.
func _check(n: int, mode: String) -> void:
	var bar := _bar()
	var cells := find(bar, "Cells") as Control
	var step_px := _const("CELL") + _const("GAP")
	step("%s: %d rows" % [mode, n], _rows() == n and absf(cells.size.y - n * step_px) <= 2.0, "рядов %d, сетка %d px" % [_rows(), cells.size.y])
	var seen := cells.get_global_rect().grow(1)
	var slots := find_all(cells, "HotSlot")
	var lost := slots.filter(func(sl: Control) -> bool:
		return sl.is_visible_in_tree() and not seen.encloses(sl.get_global_rect()) and sl.get_index() < n * int((sl.get_parent() as GridContainer).columns))
	step("%s, %d rows: every slot of the rows in sight inside the grid" % [mode, n], not slots.is_empty() and lost.is_empty(), "%d вне сетки" % lost.size())
	var screen_h := bar.get_viewport_rect().size.y
	step("%s, %d rows: the bar on the screen" % [mode, n], bar.get_global_rect().end.y <= screen_h + 1, "%s / %d" % [bar.get_global_rect(), screen_h])
	var field := screen().find_child("Field", true, false) as Control
	step("%s, %d rows: the map keeps its room" % [mode, n], field != null and field.size.y >= 280.0, "карта %d px" % (field.size.y if field != null else -1))
	var tabs := find(bar, "KindTabs") as Control
	var plaque := find(bar, "CountersPlaque") as Control
	var top := _frame_top()
	step("%s, %d rows: the tabs stand on the frame's edge" % [mode, n], tabs != null and absf(tabs.get_global_rect().end.y - (top + _const("OVERLAP"))) <= 2.0,
		"вкладки до %d, кромка %d" % [tabs.get_global_rect().end.y if tabs != null else -1, top])
	step("%s, %d rows: the plaque on the edge too" % [mode, n], plaque == null or not plaque.visible or absf(plaque.get_global_rect().end.y - (top + _const("OVERLAP"))) <= 2.0,
		_rect(plaque))
	var win := find(bar, "Windows") as GridContainer
	var want := 3 if n == 1 else 2
	step("%s, %d rows: the windows and the rests in %d columns" % [mode, n, want], win != null and win.columns == want and win.get_child_count() == 6,
		"%d колонок, %d значков" % [win.columns if win != null else -1, win.get_child_count() if win != null else -1])
	var parts := ["HeroPortrait", "Hands", "Windows", "RowsMore"].map(func(p: String) -> Control: return find(bar, p) as Control)
	var out := parts.filter(func(c: Control) -> bool: return c == null or not _inside(c))
	step("%s, %d rows: the portrait, the hands, the windows and the rests inside the frame" % [mode, n], out.is_empty(),
		", ".join(out.map(func(c: Control) -> String: return "?" if c == null else str(c.name) + " " + _rect(c))))
