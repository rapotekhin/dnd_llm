extends "res://tools/playtest/playtest_base.gd"
## Interface and debts playtest (python tools/godot_playtest.py --scenario debts), v0.7.7 and its fixes: a click on
## an item in the sheet or in the trade shows what it is in a details panel of a fixed size; the carried weight;
## taking off the mail takes five minutes; the pin button in the input row offers spells, features and items;
## Second Wind pinned to a message goes in one turn with the words; the fight shows what an attack or a foe is.


func run() -> void:
	var gs := node("GameState")
	if not step("master connected", await wait_until(func() -> bool: return node("Backend").is_ready(), 30.0)):
		return
	await tap("NewGameButton")
	step("no «Одна жизнь» before M5", find(screen(), "death_mode_one_life") == null)
	await tap("NextButton")
	await tap("Preset_fighter_aira")
	await press(find(screen(), "StartButton"))
	if not step("game started", await wait_until(func() -> bool: return screen_is("GameScreen") and not gs.is_busy(), 60.0)):
		return
	var s: GameSession = gs.session
	var game := screen()

	# The sheet: item numbers, weight; the mail off takes minutes.
	await press(find(game, "SheetButton"))
	var sheet: Control = find(game, "CharacterSheet")
	var tabs: TabContainer = sheet.find_children("*", "TabContainer", true, false)[0]
	tabs.current_tab = 2
	await frames(3)
	var details: Control = find(sheet, "ItemDetails")
	var box_size: Vector2 = details.size if details != null else Vector2.ZERO
	await press(find(sheet, "Item_" + str(s.character["equipped"]["armor"])))
	await frames(2)
	step("a click on the mail shows its AC in the details", details != null and _text_of(details).contains("КД 16"), _text_of(details).left(160) if details != null else "")
	for id: String in s.character["inventory"]:
		var b: Button = find(sheet, "Item_" + id)
		if b != null:
			await press(b)
	await frames(2)
	step("the details panel keeps its size", details != null and details.size.is_equal_approx(box_size), "%s → %s" % [box_size, details.size if details != null else Vector2.ZERO])
	var weight: Label = find(sheet, "CarriedWeight")
	step("carried weight", weight != null and weight.text.contains("фнт"), weight.text if weight != null else "")
	await shot("sheet_gear")
	var minute := s.minute
	await press(find(sheet, "Unequip_armor"))
	await frames(2)
	step("taking the mail off takes 5 minutes", s.minute - minute == 5, "%d → %d" % [minute, s.minute])
	step("info: the chat line", true, _last_effect(s))
	await shot("sheet_unequipped")

	# Both hands (a fix after v0.7.22.32): the longsword gripped in two, a greatsword frees the shield hand; the sheet scrolls.
	var list: ScrollContainer = find(sheet, "GearList")
	step("the gear tab scrolls", list != null and list.size.y < sheet.get_viewport_rect().size.y and list.get_v_scroll_bar().visible,
		str(list.size) if list != null else "")
	var both: Button = find(sheet, "BothHands")
	if step("«Двумя руками» on the longsword with a shield", both != null and not both.disabled):
		await press(both)
		await frames(3)
		step("the shield went to the pack", str(s.character["equipped"]["shield"]).is_empty() and CombatRules.weapon_profile(s.character, node("Catalog").data, s.items, "longsword")["dice"] == "1d10")
		await shot("sheet_both_hands")
	await press(find(sheet, "Equip_shield_shield"))
	await frames(3)
	s.character["inventory"]["greatsword"] = 1
	node("EventBus").state_changed.emit()
	await frames(3)
	var great: Button = find(sheet, "Equip_main_hand_greatsword")
	step("a greatsword goes «В обе руки»", great != null and not great.disabled and great.text == "В обе руки", great.text if great != null else "")
	if great != null:
		await press(great)
		await frames(3)
		step("the greatsword took the shield off", str(s.character["equipped"]["main_hand"]) == "greatsword" and str(s.character["equipped"]["shield"]).is_empty())
		step("the off hand is held", _text_of(find(sheet, "SlotCard_off_hand")).contains("занята"), _text_of(find(sheet, "SlotCard_off_hand")))
		await shot("sheet_greatsword")
		s.character["equipped"]["main_hand"] = "longsword"  # the rest of the scenario fights with the longsword
		s.character["equipped"]["shield"] = "shield"
		CharacterRules.refresh(s.character, node("Catalog").data, s.items)
	await press(find(sheet, "CloseSheetButton"))

	# The smith's goods.
	for room: String in ["brod-square", "brod-smithy"]:
		var exit: Button = find(game, "Exit_" + room)
		if not step("walk to " + room, exit != null and not exit.disabled):
			return
		await press(exit)
		await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
	var trade: Button = find(game, "Trade_npc_smith")
	if step("the smith trades", trade != null and not trade.disabled):
		await press(trade)
		await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
		var panel: Control = find(game, "TradePanel")
		var info: Control = find(panel, "TradeItemInfo")
		var panel_size := panel.size
		await press(find(panel, "TradeItem_longsword"))
		await frames(2)
		step("a click on the sword shows its numbers", _text_of(info).contains("1к8"), _text_of(info).left(160))
		await press(find(panel, "TradeItem_chain_shirt"))
		await frames(2)
		step("the chain shirt compares with what is worn", _text_of(info).contains("→"), _text_of(info).left(200))
		step("the trade panel keeps its size", panel.size.is_equal_approx(panel_size), "%s → %s" % [panel_size, panel.size])
		await shot("trade_stats")
		await press(find(game, "LeaveButton"))
		await wait_until(func() -> bool: return not gs.is_busy(), 60.0)

	# The pin button in the input row: spells, features, items.
	var pin: MenuButton = find(game, "AttachButton")
	step("the pin button is in the input row", pin != null and pin.get_parent() == (game.get("input") as Control).get_parent())
	game.call("_fill_attach_menu")
	var subs: Array[String] = []
	for sub: Node in pin.get_popup().get_children():
		if sub is PopupMenu:
			subs.append("%s %d" % [sub.name, (sub as PopupMenu).item_count])
	step("four submenus with things in them (v0.7.36: the check)", subs.size() == 4 and not ", ".join(subs).contains(" 0"), ", ".join(subs))
	# Second Wind pinned to the words: one turn.
	s.character["hp"] = int(s.character["max_hp"]) - 6
	gs.attach("feature", "second_wind")
	await frames(3)
	step("the chip shows what is pinned", find(game, "AttachName") != null)
	await shot("attached")
	var turns := s.turn_counter
	game.get("input").text = "Перевязываю рану и оглядываю кузницу"
	game.get("send_button").pressed.emit()
	await wait_until(func() -> bool: return gs.is_busy(), 5.0)
	await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
	# The stub master may hit the hero afterwards (its random effects) — so the chat order is checked, not HP.
	var at := -1
	for i in s.chat.size():
		if str(s.chat[i]["kind"]) == GameSession.KIND_PLAYER and str(s.chat[i].get("text", "")).begins_with("Перевязываю"):
			at = i
	var before: Dictionary = s.chat[at - 1] if at > 0 else {}
	step("the cast goes right before the words, no turn of its own", str(before.get("kind", "")) == GameSession.KIND_EFFECT
		and " ".join(before.get("lines", [])).contains("Второе дыхание"), str(before))
	step("Second Wind spent", FeatureUses.left(s.character, node("Catalog").data, "second_wind") == 0)
	step("info: turns", true, "%d → %d (the stub may add a «downed» turn)" % [turns, s.turn_counter])
	step("the chip is gone", gs.attached.is_empty() and find(game, "AttachName") == null)
	await shot("after_attached")

	# The fight: what an attack and a foe are.
	if int(s.character["hp"]) <= 0:
		s.character["hp"] = 1
	gs.start_combat([{"monster": "wolf", "col": 1}])
	if not step("a fight", await wait_until(func() -> bool: return screen_is("CombatScreen") and not gs.is_busy(), 60.0)):
		return
	await frames(5)
	var cs := screen()
	var cd: Control = find(cs, "CombatDetails")
	var attack: Control = find(cs, "Attack_main")
	if attack != null:
		attack.mouse_entered.emit()
	step("the attack's weapon in the details", cd != null and _text_of(cd).contains("1к8"), _text_of(cd).left(160) if cd != null else "")
	for card: Node in cs.find_children("Foe_*", "Button", true, false):
		(card as Control).mouse_entered.emit()
		break
	step("an unknown foe says how to learn it", cd != null and _text_of(cd).contains("Осмотреть"), _text_of(cd).left(160) if cd != null else "")
	await shot("combat_details")


func _text_of(n: Node) -> String:
	var out := ""
	for l: Node in n.find_children("*", "Label", true, false) + n.find_children("*", "RichTextLabel", true, false):  # the panel's text is rich (v0.7.22.21)
		out += str(l.get("text")) + "\n"
	return out


func _last_effect(s: GameSession) -> String:
	for i in range(s.chat.size() - 1, -1, -1):
		if str(s.chat[i]["kind"]) == GameSession.KIND_EFFECT:
			return " · ".join(s.chat[i].get("lines", []))
	return ""
