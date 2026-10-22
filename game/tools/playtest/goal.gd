extends "res://tools/playtest/playtest_base.gd"
## Life goal playtest (python tools/godot_playtest.py --scenario goal), v0.7.22: the field on the Development tab of
## the sheet — the goal written, sent to the master, shown with its assessment, cleared.


func run() -> void:
	var gs := node("GameState")
	if not step("master connected", await wait_until(func() -> bool: return node("Backend").is_ready(), 30.0)):
		return
	await tap("NewGameButton")
	await tap("NextButton")
	await tap("Preset_fighter_aira")
	await press(find(screen(), "StartButton"))
	if not step("game started", await wait_until(func() -> bool: return screen_is("GameScreen") and not gs.is_busy(), 60.0)):
		return
	var s: GameSession = gs.session
	var game := screen()
	await press(find(game, "SheetButton"))
	await frames(3)
	var sheet := find(game, "CloseSheetButton").get_parent().get_parent().get_parent()
	sheet.open_tab(3)
	await frames(3)
	var edit: LineEdit = find(game, "GoalEdit")
	if not step("the goal field is on the Development tab", edit != null):
		return
	edit.text = "Убить дракона и повесить его голову над воротами"
	var turns: Array = []
	node("EventBus").turn_started.connect(func(id: String) -> void: turns.append(id))
	await press(find(game, "GoalSave"))
	step("the goal is written", str(GoalRules.goal(s.character).get("text", "")).begins_with("Убить дракона"))
	await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
	step("the master was asked for its assessment", turns.size() == 1, str(turns))
	await frames(3)
	var shown: Label = find(game, "GoalText")
	step("the sheet shows the goal", shown != null and shown.text.contains("Убить дракона"), shown.text if shown != null else "")
	await shot("goal")
	await press(find(game, "GoalClear"))
	await frames(3)
	step("the goal is cleared", GoalRules.goal(s.character).is_empty())
