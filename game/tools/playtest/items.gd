extends "res://tools/playtest/playtest_base.gd"
## «Правила 5e: предметы» playtest (python tools/godot_playtest.py --scenario items), v0.7.12: a found ring comes
## unidentified; the sheet attunes the Gauntlets of Ogre Power (an hour, STR 19); the priestess identifies the ring
## for coins; in a fight the Items tab throws alchemist's fire and fires the wand of magic missiles; arrows are spent
## and half of them are picked up after the fight.

var _seen: Array[String] = []


func run() -> void:
	var gs := node("GameState")
	var data: Dictionary = node("Catalog").data
	node("EventBus").combat_lines.connect(func(l: Array) -> void:
		for x: Variant in l:
			_seen.append(str(x)))
	if not step("master connected", await wait_until(func() -> bool: return node("Backend").is_ready(), 30.0)):
		return
	await tap("NewGameButton")
	await tap("NextButton")
	await tap("Preset_ranger_velena")
	await press(find(screen(), "StartButton"))
	if not step("game started", await wait_until(func() -> bool: return screen_is("GameScreen") and not gs.is_busy(), 60.0)):
		return
	var s: GameSession = gs.session
	var c := s.character
	var ring := ItemRules.found(c, data, s.items, "ring_of_warmth")
	c["inventory"]["gauntlets_of_ogre_power"] = 1
	c["inventory"]["alchemists_fire_flask"] = 2
	c["inventory"]["wand_of_magic_missiles"] = 1
	c["gold_cp"] = int(c["gold_cp"]) + 5000
	CharacterRules.refresh(c, data, s.items)
	node("EventBus").state_changed.emit()
	step("the ring is unidentified", ring.begins_with("unk_") and ItemRules.display_name(data["items"], s.items, ring) == "Кольцо, свойства неизвестны")

	# The sheet: attunement.
	var game := screen()
	await press(find(game, "SheetButton"))
	var sheet: Control = find(game, "CharacterSheet")
	await frames(3)
	_gear_tab(sheet)
	await frames(2)
	var wear: Button = find(sheet, "Equip_hands_gauntlets_of_ogre_power")  # v0.7.22.9: worn on the hands
	if step("the gauntlets go on the hands", wear != null and not wear.disabled, wear.tooltip_text if wear != null else ""):
		await press(wear)
		await frames(3)
		_gear_tab(find(screen(), "CharacterSheet"))
		await frames(2)
	sheet = find(screen(), "CharacterSheet")
	if not sheet.visible:
		await press(find(game, "SheetButton"))
		await frames(3)
		_gear_tab(sheet)
		await frames(2)
	await shot("sheet_worn")
	var att: Button = find(sheet, "Attune_gauntlets_of_ogre_power")
	step("the attune button", att != null and not att.disabled, att.tooltip_text if att != null else "")
	await shot("sheet_attune")
	var str_before := CharacterRules.ability(c, "str")
	var minute := s.minute
	if att != null:
		await press(att)
		await frames(3)
	step("attuned: STR 19, an hour passed", CharacterRules.ability(c, "str") == 19 and s.minute != minute,
		"STR %d → %d, %d → %d min" % [str_before, CharacterRules.ability(c, "str"), minute, s.minute])

	# The priestess identifies the ring.
	for room: String in ["brod-square", "brod-temple"]:
		var exit: Button = find(screen(), "Exit_" + room)
		if step("walk to " + room, exit != null and not exit.disabled):
			await press(exit)
			await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
	game = screen()
	var trade: Button = find(game, "Trade_npc_priestess")
	if step("trade with the priestess", trade != null and not trade.disabled):
		await press(trade)
		await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
		await frames(3)
		var panel: Control = find(game, "TradePanel")
		var ident: Button = find(panel, "Service_identify")
		step("the identify service", ident != null and not ident.disabled, ident.text if ident != null else "")
		await shot("trade_services")
		if ident != null:
			await press(ident)
			await frames(3)
		step("the ring is known now", c["inventory"].has("ring_of_warmth") and not c["inventory"].has(ring))
		await press(find(game, "LeaveButton"))
		await wait_until(func() -> bool: return not gs.is_busy(), 60.0)

	# The fight: the Items tab.
	c["inventory"]["arrows"] = 20
	gs.start_combat([{"monster": "ogre", "col": 1}])
	if not step("a fight with an ogre", await wait_until(func() -> bool: return screen_is("CombatScreen") and not gs.is_busy(), 60.0)):
		return
	await wait_until(func() -> bool: return CombatRules.player_can_act(s) or not str(s.combat.get("outcome", "")).is_empty(), 60.0)
	var ogre := CombatRules.fighter(s, CombatRules.enemies(s)[0])
	ogre["ac"] = 1
	var cs := screen()
	_items_tab(cs)
	await frames(2)
	await shot("items_tab")
	var flask: Button = find(cs, "Item_alchemists_fire_flask")
	step("a flask on the Items tab", flask != null)
	if flask != null:
		await press(flask)
		await frames(2)
		await press(find(cs, "Foe_" + str(ogre["id"])))
		await frames(4)
	step("the flask was thrown", _seen.any(func(l: String) -> bool: return l.contains("бросает")), _tail(3))
	await press(find(screen(), "EndTurnButton"))
	await wait_until(func() -> bool: return not gs.combat_playing and (CombatRules.player_can_act(s) or not str(s.combat.get("outcome", "")).is_empty()), 120.0)
	if str(s.combat.get("outcome", "")).is_empty():
		cs = screen()
		_items_tab(cs)
		await frames(2)
		var hp := int(ogre["hp"])
		var wand: Button = find(cs, "Item_wand_of_magic_missiles")
		if step("the wand on the Items tab", wand != null, wand.text if wand != null else ""):
			await press(wand)
			await frames(2)
			await press(find(cs, "Foe_" + str(ogre["id"])))
			await frames(4)
		step("the wand hit and spent a charge", int(ogre["hp"]) < hp and ItemRules.charges_left(c, ItemRules.def_of(data["items"], s.items, "wand_of_magic_missiles"), "wand_of_magic_missiles") == 6, _tail(3))
		await shot("wand")
	step("info: burning", true, ", ".join(_seen.filter(func(l: String) -> bool: return l.contains("горит") or l.contains("пламя"))))


func _gear_tab(sheet: Control) -> void:
	for t: Node in sheet.find_children("*", "TabContainer", true, false):
		var tabs := t as TabContainer
		for i in tabs.get_tab_count():
			if tabs.get_tab_title(i) == tr("SHEET_TAB_GEAR"):
				tabs.current_tab = i


func _items_tab(cs: Control) -> void:
	cs.call("set_filter", "COMBAT_TAB_ITEMS")


func _tail(n: int) -> String:
	return " · ".join(_seen.slice(maxi(0, _seen.size() - n)))
