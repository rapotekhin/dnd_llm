extends "res://tools/playtest/playtest_base.gd"
## Doors (python tools/godot_playtest.py --scenario doors), v0.7.22.25: the smithy at night says «заперто до 08:00»,
## its ways open under the exit, «Ждать открытия» waits till morning; the cellar door in the tavern's kitchen is
## locked — «Выбить» until it breaks, then the way is open.


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
	s.room_id = "brod-square"
	s.minute = 22 * 60
	node("EventBus").state_changed.emit()
	await frames(3)
	var smithy: Button = find(screen(), "Exit_brod-smithy")
	step("the smithy at night is locked till 08:00", smithy != null and smithy.text.contains("08:00"), smithy.text if smithy else "")
	await press(smithy)
	await frames(4)
	var wait_btn: Button = find(screen(), "DoorWay_wait")
	step("the door's ways open under the exit", wait_btn != null and find(screen(), "DoorWay_force") != null)
	await shot("smithy_night")
	if wait_btn != null:
		await press(wait_btn)
		await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
		await frames(3)
		smithy = find(screen(), "Exit_brod-smithy")
		step("waited till the opening — the way is open", s.minute >= 8 * 60 and s.minute < 9 * 60 and smithy != null
			and not smithy.text.contains("заперто"), "%d %s" % [s.minute, smithy.text if smithy else ""])
	s.room_id = "brod-tavern-kitchen"
	s.minute = 12 * 60
	node("EventBus").state_changed.emit()
	await frames(3)
	var cellar: Button = find(screen(), "Exit_brod-tavern-cellar")
	step("the cellar door is locked", cellar != null and cellar.text.contains("заперто"), cellar.text if cellar else "")
	await press(find(screen(), "Door_brod-tavern-cellar"))
	await frames(4)
	await shot("cellar_ways")
	for i in 8:
		var force: Button = find(screen(), "DoorWay_force")
		if force == null:
			break
		await press(force)
		await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
		await frames(3)
	cellar = find(screen(), "Exit_brod-tavern-cellar")
	step("forced — the door is broken", cellar != null and cellar.text.contains("выбита"), cellar.text if cellar else "")
	await shot("cellar_broken")
	if cellar != null:
		await press(cellar)
		await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
		step("through the broken door into the cellar", s.room_id == "brod-tavern-cellar", s.room_id)
