extends "res://tools/playtest/playtest_base.gd"
## The calendar and festivals (python tools/godot_playtest.py --scenario festival), v0.7.44: the date and the nearest
## festival on the panel; the night passes into the fair — the pedlar on the square, the merchant pays more; the
## journal's calendar; the harvest in the tavern — the feast's hall, cheap food and Bruno's quest; after it the flags
## are off.

const SQUARE := "brod-square"
const HALL := "brod-tavern-hall"


func run() -> void:
	var gs := node("GameState")
	if not step("master connected", await wait_until(func() -> bool: return node("Backend").is_ready(), 30.0)):
		return
	await tap("NewGameButton")
	await tap("NextButton")
	await tap("Preset_fighter_aira")
	await press(find(screen(), "StartButton"))
	if not step("game started", await wait_until(func() -> bool: return screen_is("GameScreen") and not gs.is_busy(), 90.0)):
		return
	var s: GameSession = gs.session
	var data: Dictionary = node("Catalog").data
	var world: Dictionary = data["world"]
	s.settings["needs"] = false
	node("EventBus").state_changed.emit()
	await frames(3)
	var time_l: Label = find(screen(), "HeroTime")
	step("the date on the panel", time_l != null and time_l.text.contains("3 Жатвеня, день Пряжи"), time_l.text if time_l != null else "")
	var fest: Label = find(screen(), "FestivalLine")
	step("the market day ahead on the panel", fest != null and fest.text.contains("Торговый день — через 4 дня"), fest.text if fest != null else "")
	await shot("market_day")

	await _go(gs, SQUARE)
	var sell_usual := TradeRules.sell_price(s, data, "npc_merchant", "longsword")
	_to_day(s, data, 6)  # the night before the fair passes
	node("EventBus").state_changed.emit()
	await frames(3)
	step("the fair is on", s.flags.has("fair"), ", ".join(s.flags))
	step("the pedlar on the square", s.npcs_here(world, SQUARE).has("npc_pedlar") and find(screen(), "Trade_npc_pedlar") != null)
	step("the merchant pays more at the fair", TradeRules.sell_price(s, data, "npc_merchant", "longsword") > sell_usual,
		"%d → %d" % [sell_usual, TradeRules.sell_price(s, data, "npc_merchant", "longsword")])
	fest = find(screen(), "FestivalLine")
	step("the fair on the panel", fest != null and fest.text.contains("ярмарка"), fest.text if fest != null else "")
	await shot("fair")

	var game := screen()
	await press(find(game, "JournalButton"))
	var tab: Button = find(game, "JournalTab_calendar")
	if step("the calendar tab", tab != null):
		await press(tab)
		await frames(3)
		var box: Node = find(game, "JournalTab_calendar").get_parent().get_parent()
		var text := " ".join(box.find_children("*", "Label", true, false).map(func(l: Node) -> String: return (l as Label).text))
		step("the harvest ahead in the journal", text.contains("Дожинки"), text.left(300))
		await shot("journal_calendar")
		await press(find(game, "JournalButton"))
		await frames(2)

	_to_day(s, data, 10)
	await _go(gs, HALL)
	step("the harvest is on, the fair is over", s.flags.has("harvest_feast") and not s.flags.has("fair"), ", ".join(s.flags))
	step("the feast's hall", str(SceneRules.room(s, world, HALL)["description"]).contains("Дожинки"))
	step("Bruno's harvest quest offered", find(screen(), "QuestTake_harvest_table") != null)
	await shot("harvest")

	_to_day(s, data, 12)
	node("EventBus").state_changed.emit()
	await frames(3)
	step("after the harvest the flag is off", not s.flags.has("harvest_feast"), ", ".join(s.flags))
	step("the quest is not offered any more", find(screen(), "QuestTake_harvest_table") == null)


## Moves the clock to 10:00 of a game day through the engine's own time, a day at a time with the nights slept.
func _to_day(s: GameSession, data: Dictionary, day: int) -> void:
	while s.day < day:
		TimeRules.advance(s, data, 1440 - s.minute + 10 * 60)
		s.rested_at = TimeRules.abs_minute(s)  # slept through the night: not a test of exhaustion
		s.awake_saves = 0


func _go(gs: Node, to: String) -> void:
	await wait_until(func() -> bool: return not gs.is_busy(), 30.0)
	var ok: bool = gs.go(to)
	step("walked to %s" % to, ok)
	await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
	await frames(3)
