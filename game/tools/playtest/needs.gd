extends "res://tools/playtest/playtest_base.gd"
## Needs (python tools/godot_playtest.py --scenario needs), v0.7.23: the toggle at a new game, three bars on the
## panel, hunger and thirst after a day on the road, «Поесть» from the pack, «Набрать воды» and a drink on the
## square, the innkeeper's meal, the needs on the sheet, the setting off hides the bars.


func run() -> void:
	var gs := node("GameState")
	if not step("master connected", await wait_until(func() -> bool: return node("Backend").is_ready(), 30.0)):
		return
	await tap("NewGameButton")
	var toggle: CheckButton = find(screen(), "NeedsToggle")
	step("the needs toggle at a new game, on", toggle != null and toggle.button_pressed)
	await shot("new_game")
	await tap("NextButton")
	await tap("Preset_fighter_aira")
	await press(find(screen(), "StartButton"))
	if not step("game started", await wait_until(func() -> bool: return screen_is("GameScreen") and not gs.is_busy(), 60.0)):
		return
	var s: GameSession = gs.session
	var data: Dictionary = node("Catalog").data
	s.room_id = "brod-gate"
	node("EventBus").state_changed.emit()
	await frames(3)
	step("three bars on the panel", find(screen(), "Need_food") != null and find(screen(), "Need_water") != null
		and find(screen(), "Need_sleep") != null)
	await shot("full")

	TimeRules.advance(s, data, 14 * 60)
	s.character["inventory"]["rations"] = 2
	s.character["inventory"]["waterskin"] = 1
	NeedRules.state(s, data)["skin"] = 0
	node("EventBus").state_changed.emit()
	await frames(3)
	var shown := NeedRules.shown(s, data).map(func(n: Dictionary) -> String: return str(n["chip"]))
	step("hungry and thirsty after 14 hours", shown.has("Голоден") and shown.has("Хочет пить"), str(shown))
	await shot("hungry")

	var eat: Button = find(screen(), "EatButton")
	if step("«Поесть» is on", eat != null and not eat.disabled, eat.tooltip_text if eat != null else ""):
		await press(eat)
		await frames(3)
		step("fed", NeedRules.value(s, data, "food") >= 75.0 and int(s.character["inventory"].get("rations", 0)) == 1,
			"%d" % NeedRules.value(s, data, "food"))
	var drink: Button = find(screen(), "DrinkButton")
	step("no water here: no «Попить»", drink == null)

	s.room_id = "brod-square"
	node("EventBus").state_changed.emit()
	await frames(3)
	var fill: Button = find(screen(), "FillWater")
	if step("«Набрать воды» on the square", fill != null and not fill.disabled):
		await press(fill)
		await frames(3)
		step("the skin is full", NeedRules.drinks(s, data) == NeedRules.capacity(s.character, data))
	drink = find(screen(), "DrinkButton")
	if step("«Попить» on the square", drink != null and not drink.disabled):
		await press(drink)
		await frames(3)
		step("drunk", NeedRules.value(s, data, "water") >= 75.0, "%d" % NeedRules.value(s, data, "water"))
	step("nothing to do: no acts row", find(screen(), "EatButton") == null and find(screen(), "DrinkButton") == null)
	await shot("fed_and_watered")

	NeedRules.set_value(s, data, "food", 30.0)
	s.room_id = "brod-tavern-hall"
	s.minute = 13 * 60
	node("EventBus").state_changed.emit()
	await frames(3)
	var trade: Button = find(screen(), "Trade_npc_innkeeper")
	if step("trade with the innkeeper", trade != null and not trade.disabled):
		await press(trade)
		await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
		await frames(3)
		var meal: Button = find(screen(), "Service_meal")
		step("the meal service", meal != null and not meal.disabled, meal.text if meal != null else "")
		await shot("meal_service")
		if meal != null:
			await press(meal)
			await frames(3)
		step("fed at the inn", NeedRules.value(s, data, "food") >= 99.0, "%d" % NeedRules.value(s, data, "food"))
		var leave: Button = find(screen(), "LeaveButton")
		if leave != null:
			await press(leave)
			await wait_until(func() -> bool: return not gs.is_busy(), 60.0)

	var sheet: Control = find(screen(), "CharacterSheet")
	if sheet != null:
		sheet.call("open")
		await frames(4)
		var line: Label = find(sheet, "SheetNeeds")
		step("the needs on the sheet", line != null and line.text.contains("Еда"), line.text if line != null else "")
		await shot("sheet")
		sheet.visible = false

	gs.set_needs(false)
	await frames(3)
	step("off: no bars", find(screen(), "Need_food") == null)
	await shot("off")
