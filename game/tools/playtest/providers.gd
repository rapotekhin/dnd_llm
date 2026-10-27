extends "res://tools/playtest/playtest_base.gd"
## Provider list playtest (python tools/godot_playtest.py --scenario providers --real; no turn, no cost), v0.7.34.1:
## every provider of the model with its cost of 1000 turns and our speed, sorted by our choice and by speed.


func run() -> void:
	if not step("master connected", await wait_until(func() -> bool: return node("Backend").is_ready(), 30.0)):
		return
	node("EventBus").navigate.emit("settings", {"back": "menu", "tab": 1})  # SettingsScreen.TAB_MASTER
	await frames(5)
	var list: OptionButton = find(screen(), "ProviderOption")
	var sort: OptionButton = find(screen(), "ProviderSortOption")
	if not step("the provider list and its order are on the master tab", list != null and sort != null):
		return
	sort.select(0)
	sort.item_selected.emit(0)
	await frames(3)
	await shot("providers_closed")
	var real := OS.get_environment("BTR_PLAYTEST_REAL") == "1"
	step("every provider of the model is listed", list.item_count > (5 if real else 1), "%d rows" % list.item_count)
	if real:
		step("a row has the cost of 1000 turns", list.get_item_text(1).contains("1000"), list.get_item_text(1))
		step("the first rows are the server's picks", list.get_item_text(1).contains(tr("OPT_PROVIDER_PICKED").strip_edges()),
			list.get_item_text(1))
	list.show_popup()
	await frames(5)
	await shot("providers_ours")
	list.get_popup().hide()
	sort.select(2)
	sort.item_selected.emit(2)  # speed
	await frames(3)
	if real:
		step("by speed the measured ones come first", not list.get_item_text(1).contains(tr("OPT_PROVIDER_SPEED_NONE")), list.get_item_text(1))
	list.show_popup()
	await frames(5)
	await shot("providers_speed")
	list.get_popup().hide()
	sort.select(0)
	sort.item_selected.emit(0)
