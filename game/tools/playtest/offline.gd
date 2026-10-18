extends "res://tools/playtest/playtest_base.gd"
## Offline playtest (no llm_server running): the menu works, character creation works without the master,
## «Начать игру» leads to the «Мастер недоступен» screen with the «server does not answer» diagnosis, «В меню» returns.


func run() -> void:
	var backend := node("Backend")
	step("master not connected", not backend.is_ready())
	step("menu shown", screen_is("MainMenu"))
	await shot("menu_offline")
	step("random character created", await quick_character())
	if not step("offline screen instead of the game", screen_is("OfflineScreen") and not node("GameState").has_session()):
		return
	var reason: Label = find(screen(), "Reason")
	var expected := tr("OFFLINE_SERVER_DOWN")
	step("diagnosis: server does not answer", await wait_until(func() -> bool: return reason.text == expected, 15.0), reason.text)
	await shot("offline_screen")
	await press(find_button_by_text(screen(), "В меню"))
	step("back to the menu", screen_is("MainMenu"))
