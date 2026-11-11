extends "res://tools/playtest/playtest_base.gd"
## Two weapon sets and sight in a fight (python tools/godot_playtest.py --scenario weapon_sets), v0.8.4.1: a bow goes to its
## row, the sets change by the button and the key for nothing, in a fight a shot with the bow put away is one click, a Fog
## Cloud closes the view but a foe in it is heard and shot, a blind hero shoots with disadvantage.


func run() -> void:
	var gs := node("GameState")
	var data: Dictionary = node("Catalog").data
	if not step("master connected", await wait_until(func() -> bool: return node("Backend").is_ready(), 30.0)):
		return
	await tap("NewGameButton")
	await tap("NextButton")
	await tap("Preset_fighter_aira")
	await press(find(screen(), "StartButton"))
	if not step("game started", await wait_until(func() -> bool: return screen_is("GameScreen") and not gs.is_busy(), 60.0)):
		return
	var s: GameSession = gs.session
	var c := s.character
	var sword := str(c["equipped"]["main_hand"])
	c["inventory"]["longbow"] = 1
	c["inventory"]["arrows"] = 20
	node("EventBus").state_changed.emit()
	await frames(3)
	step("nothing in the other set yet", (find(screen(), "WeaponSetStowed") as Button).disabled)
	step("a bow to the set put away by its own button", gs.equip("longbow", "main_hand", false, true).is_empty() and str(c["equipped"]["main_hand"]) == sword and str(CharacterRules.stowed(c)["main_hand"]) == "longbow")
	await frames(3)
	await shot("sets_on_the_panel")
	var ac := int(c["ac"])
	await press(find(screen(), "WeaponSetStowed"))
	await frames(3)
	step("the button brings the bow to hand", str(c["equipped"]["main_hand"]) == "longbow", str(c["equipped"]["main_hand"]))
	step("the shield went with the set", int(c["ac"]) < ac or str(CharacterRules.stowed(c).get("off_hand", "")).is_empty(), "AC %d" % int(c["ac"]))
	await key(KEY_ESCAPE)  # the input holds the keys until Esc
	await key(KEY_F)
	await frames(3)
	step("the key brings the sword back", str(c["equipped"]["main_hand"]) == sword, str(c["equipped"]["main_hand"]))
	await key(KEY_I)
	await frames(4)
	await shot("sheet")
	var sheet: Control = find(screen(), "CharacterSheet")
	step("the other set on the doll", find(screen(), "Stowed_main_hand") != null and find(screen(), "SwapWeapons") != null)
	# v0.8.4.24: a javelin to the set put away by its own button, the sheet drawn again at once; the belt under the doll
	c["inventory"]["javelin"] = 1
	c["inventory"]["candle"] = 5
	c["belt"] = ["", "", "", "", ""]
	node("EventBus").state_changed.emit()
	await frames(4)
	sheet.call("stage", "javelin")  # v0.8.4.43.6: a thing's acts as its menu shows them
	var spare: Button = find(screen(), "EquipStowed_main_hand_javelin")
	if step("a javelin may go to the set put away", spare != null and not spare.disabled):
		await press(spare)
		await frames(3)
		step("the javelin lies in the set and shows at once", str(CharacterRules.stowed(c)["main_hand"]) == "javelin" and str(find(screen(), "Stowed_main_hand").get("item")) == "javelin")
	sheet.call("stage", "longbow")
	var bow_back: Button = find(screen(), "EquipStowed_main_hand_longbow")
	step("the bow's button says where it goes", bow_back != null and bow_back.text == tr("BTN_EQUIP_STOWED"))
	sheet.call("stage", "candle")
	var belt: Button = find(screen(), "BeltPut_candle")
	if step("candles go to the belt", belt != null and not belt.disabled):
		await press(belt)
		await frames(3)
		step("the candles in a cell of the belt", ItemRules.on_belt(c, data, s.items, "candle") and find(screen(), "Belt_0") != null)
	var row: Control = find(screen(), "BeltCells")
	if step("the belt's row", row != null):
		var scroll := row.get_parent()
		while scroll != null and not scroll is ScrollContainer:
			scroll = scroll.get_parent()
		if scroll != null:
			(scroll as ScrollContainer).ensure_control_visible(row)
		await frames(3)
		var widths: Array[float] = []
		for cell: Control in row.get_children():
			widths.append(cell.size.x)
		# five square cells alike under the doll (v0.8.4.43.6: icons of the size of the doll's slots), none squeezed
		step("the belt's cells alike", widths.size() == 5 and widths.max() - widths.min() <= 2.0 and widths.min() >= 48.0, str(widths) + " of " + str(row.size.x))
	await shot("sheet_belt")
	var said := []
	var hear := func(m: String) -> void: said.append(m)
	node("EventBus").message.connect(hear)
	sheet.call("stage", "longbow")
	var again: Button = find(screen(), "EquipStowed_main_hand_longbow")
	if again != null:
		await press(again)
		await frames(3)
	node("EventBus").message.disconnect(hear)
	step("the bow back in the set", str(CharacterRules.stowed(c)["main_hand"]) == "longbow", "%s %s" % [str(CharacterRules.stowed(c)), str(said)])
	# v0.8.4.42.1: a shot only from the belt — a bow in a set warns until the arrows are on it
	step("the bow in a set without arrows on the belt warns", find(screen(), "BeltNoAmmo") != null)
	sheet.call("stage", "arrows")
	var arrows: Button = find(screen(), "BeltPut_arrows")
	if step("arrows go to the belt", arrows != null and not arrows.disabled):
		await press(arrows)
		await frames(3)
		step("the warning gone with the arrows on the belt", ItemRules.on_belt(c, data, s.items, "arrows") and find(screen(), "BeltNoAmmo") == null)
		var shots: Control = find(screen(), "Stowed_main_hand")  # v0.8.4.42.6: the shots at hand on the bow's cell
		step("the bow says its shots at hand", shots != null and str(shots.get("badge")) == "20", str(shots.get("badge")) if shots != null else "")
		var set_b: Button = find(screen(), "WeaponSetStowed")
		step("and so does its weapon set", set_b == null or set_b.text.ends_with("· 20"), set_b.text if set_b != null else "")
	await shot("sheet_belt_arrows")
	# v0.8.4.25.1: the one sword is never in both sets — to the set put away it leaves the hands, and back
	c["inventory"][sword] = 1
	sheet.call("stage", sword, "main_hand")
	var one := find(screen(), "EquipStowed_main_hand_" + sword)
	if step("the sword may go to the set put away", one != null and not (one as Button).disabled):
		await press(one)
		await frames(3)
		step("the one sword left the hands", str(CharacterRules.stowed(c)["main_hand"]) == sword and str(c["equipped"]["main_hand"]).is_empty() and CharacterRules.held_copies(c, sword) == 1, "%s / %s" % [str(c["equipped"]), str(CharacterRules.stowed(c))])
		step("back to the hands it leaves the set", gs.equip(sword, "main_hand").is_empty() and str(c["equipped"]["main_hand"]) == sword and str(CharacterRules.stowed(c)["main_hand"]).is_empty() and CharacterRules.held_copies(c, sword) == 1, "%s / %s" % [str(c["equipped"]), str(CharacterRules.stowed(c))])
		gs.equip("longbow", "main_hand", false, true)
		await frames(3)
	await press(find(screen(), "SwapWeapons"))
	await frames(3)
	step("the sheet's button swaps", str(c["equipped"]["main_hand"]) == "longbow")
	await press(find(screen(), "SwapWeapons"))
	await frames(3)
	await key(KEY_I)
	await frames(3)
	gs.start_combat([{"monster": "goblin", "name": "Гоблин", "x": 1, "y": 1}], {})
	if not step("the fight", await wait_until(func() -> bool: return screen_is("fight"), 10.0)):
		return
	await wait_until(func() -> bool: return CombatRules.is_player_turn(s) and not gs.is_busy(), 60.0)
	await frames(3)
	var foe := CombatRules.fighter(s, CombatRules.enemies(s)[0])
	var hero := FightGrid.cell(CombatRules.player(s))
	var at := Vector2i.ZERO
	for cell: Vector2i in SightRules.look(s, data, FightGrid.map(s, data), hero):
		if WalkRules.distance(cell, hero) in range(3, 7) and FightGrid.walkable(FightGrid.grid(s, data), cell) and FightGrid.clear(FightGrid.grid(s, data), hero, cell) and not FightGrid.bodies(s).has(cell):
			at = cell
			break
	FightGrid.put(foe, at)
	FightGrid.changed(s)
	node("EventBus").state_changed.emit()
	await frames(4)
	var e := CombatRules.economy(s)
	var money: Dictionary = e.duplicate()
	await key(KEY_F)
	await frames(3)
	step("the key works in a fight", str(c["equipped"]["main_hand"]) == "longbow", str(c["equipped"]["main_hand"]))
	await press(find(screen(), "WeaponSetStowed"))
	await frames(3)
	step("two swaps cost nothing", CombatRules.economy(s).hash() == money.hash(), str(CombatRules.economy(s)))
	await shot("fight_sets")
	var shoot: Button = find(screen(), "Attack_stowed")
	if step("the bow's attack among the sword's", shoot != null and not shoot.disabled, shoot.text if shoot != null else ""):
		await press(shoot)
		await frames(2)
		await click_cell(at)
		await frames(4)
		step("a click took up the bow and shot", str(c["equipped"]["main_hand"]) == "longbow" and int(CombatRules.economy(s).get("action", 1)) == 0, str(c["equipped"]["main_hand"]))
	await shot("shot")
	var z := {"spell": "fog_cloud", "name": str(data["spells"]["fog_cloud"]["name"]), "shape": data["spells"]["fog_cloud"]["area"], "follow": false, "on": [],
		"obscure": true, "veil": "fog", "dice": "", "type": "", "save": "", "dc": 0, "slow": false}
	SpellEffects._lay(s, data, z, at)
	s.combat["zones"] = [z]
	e["action"] = 1
	node("EventBus").state_changed.emit()
	await frames(4)
	step("a shot into the fog goes, neither side sees", Acts.one("attack").can(s, data, CombatRules.player(s), str(foe["id"])).is_empty() and not str(CombatRules.sight_mods(s, data, CombatRules.player(s), foe)["adv"]).is_empty())
	step("the fog hides the square, the foe is heard", not SightRules.look(s, data, FightGrid.map(s, data), hero).has(at) and FightGrid.heard(s, data, foe))
	step("a spell of sight does not reach it", bool(data["spells"]["magic_missile"]["needs_sight"]) and CombatRules._blind_aim(s, data, "magic_missile", foe))
	await shot("fog")
	s.combat["zones"] = []
	ConditionRules.add_effect(c, {"condition": "blinded", "ends": {}})
	node("EventBus").state_changed.emit()
	await frames(4)
	step("a blind hero shoots with disadvantage", Acts.one("attack").can(s, data, CombatRules.player(s), str(foe["id"])).is_empty() and not Attack.mods(s, data, CombatRules.player(s), foe, {"melee": true})["dis"].is_empty())
	await shot("blind")
