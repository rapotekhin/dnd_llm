extends "res://tools/playtest/playtest_base.gd"
## The player's own check (python tools/godot_playtest.py --scenario pinned_check; --real — the real master), v0.7.36:
## «Навык проверки» in the ✦ menu, the chip with the bonus, the words sent — the engine rolls the pinned skill
## whatever the master asked for; the chip is gone after the send.


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
	var game := screen()
	var pin: MenuButton = find(game, "AttachButton")
	pin.show_popup()  # fills the menu anew
	await frames(2)
	var checks: PopupMenu = null
	for sub: Node in pin.get_popup().get_children():
		if sub.name == "AttachSub_ATTACH_GROUP_CHECK":
			checks = sub
	if not step("the ✦ menu has «Навык проверки»", checks != null and checks.item_count >= 24, str(checks.item_count if checks else 0)):
		return
	checks.popup(Rect2i(Vector2i(80, 200), Vector2i(0, 0)))
	await frames(3)
	await shot("menu")
	checks.hide()
	pin.get_popup().hide()
	var choices: Array = game.get("_check_choices")
	var at := choices.find_custom(func(c: Dictionary) -> bool: return c["id"] == "athletics")
	checks.id_pressed.emit(checks.get_item_id(checks.get_item_index(at)))
	await frames(3)
	var chip: Label = find(game, "CheckPinName")
	step("the chip shows the skill and its bonus", chip != null and chip.text.contains("Атлетика"), chip.text if chip else "")
	await shot("chip")
	game.get("input").text = "Подтягиваюсь на балку под потолком, чтобы разглядеть зал сверху"
	game.get("send_button").pressed.emit()
	await wait_until(func() -> bool: return gs.is_busy(), 5.0)
	await wait_until(func() -> bool: return not gs.is_busy(), 120.0)
	var rolled := s.chat.filter(func(e: Dictionary) -> bool: return str(e.get("kind", "")) == GameSession.KIND_CHECK)
	step("the check went by Атлетика", not rolled.is_empty() and str(rolled[-1].get("skill", "")) == "athletics",
		str(rolled[-1].get("skill", "")) if not rolled.is_empty() else "no check")
	step("the chip is gone after the send", gs.pinned_check.is_empty() and find(game, "CheckPinName") == null)
	await shot("rolled")
	# A bare ability: Сила.
	gs.pin_check("ability", "str")
	await frames(3)
	game.get("input").text = "Отодвигаю тяжёлый стол от стены"
	game.get("send_button").pressed.emit()
	await wait_until(func() -> bool: return gs.is_busy(), 5.0)
	await wait_until(func() -> bool: return not gs.is_busy(), 120.0)
	rolled = s.chat.filter(func(e: Dictionary) -> bool: return str(e.get("kind", "")) == GameSession.KIND_CHECK)
	step("a bare ability is rolled as Сила", not rolled.is_empty() and str(rolled[-1].get("ability", "")) == "str",
		str(rolled[-1]) if not rolled.is_empty() else "no check")
	await shot("ability")
