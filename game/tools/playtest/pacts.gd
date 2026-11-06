extends "res://tools/playtest/playtest_base.gd"
## The warlock's pacts (python tools/godot_playtest.py --scenario pacts), v0.8.4.33: Pact of the Blade on the sheet — a
## longsword called into the hand, then the dagger carried bound as it is (the called one gone, no copy), let go; Pact of
## the Chain — the familiar's form picked and the familiar called in it; in a fight the act of the blade and the familiar's blow.


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
	c["class"] = "warlock"
	c["level"] = 3
	c["abilities"]["cha"] = 18
	(c["features"] as Array).append_array(["pact_of_the_blade", "pact_of_the_chain"])
	ItemRules.add(c, "dagger", 1)
	CharacterRules.refresh(c, data, s.items)
	node("EventBus").state_changed.emit()
	var game := screen()
	await press(find(game, "SheetButton"))
	await frames(3)
	var sheet := find(game, "CharacterSheet")
	sheet.open_tab(1)
	await frames(4)
	if not step("the pact's buttons on the sheet", find(game, "Pact_make_longsword") != null and find(game, "Pact_bind_dagger") != null):
		await shot("sheet_no_pact")
		return
	await shot("pact_options")
	await press(find(game, "Pact_make_longsword"))
	await frames(4)
	step("a longsword called into the hand", str(c["equipped"]["main_hand"]) == "pact_longsword" and FeatureRules.pact_item(c) == "pact_longsword", str(c["equipped"]["main_hand"]))
	var p := CombatRules.weapon_profile(c, data, s.items, "pact_longsword")
	step("magical and by Charisma", bool(p["magical"]) and int(p["to_hit"]) >= 4 + 2, str(p["to_hit"]))
	await shot("pact_longsword")
	await press(find(game, "Pact_bind_dagger"))
	await frames(4)
	step("the dagger itself is the pact weapon, no copy", FeatureRules.pact_item(c) == "dagger" and not (c["inventory"] as Dictionary).has("pact_longsword") and not s.items.keys().any(func(k: String) -> bool: return k.contains("dagger") and k != "dagger"))
	step("the dagger is magical now", bool(CombatRules.weapon_profile(c, data, s.items, "dagger")["magical"]))
	await shot("pact_dagger")
	await press(find(game, "Pact_drop"))
	await frames(4)
	step("let go: the dagger is a dagger", FeatureRules.pact_item(c).is_empty() and not bool(CombatRules.weapon_profile(c, data, s.items, "dagger")["magical"]) and int(c["inventory"].get("dagger", 0)) > 0)
	var imp: Button = find(game, "Familiar_imp")
	if step("the chain's forms on the sheet", imp != null):
		await press(imp)
		await frames(4)
		step("the imp picked", AllyRules.familiar_form(s, data, c) == "imp")
	await shot("familiar_forms")
	await key(KEY_ESCAPE)
	AllyRules.summon(s, data, "find_familiar")
	step("the familiar came as an imp", not AllyRules.called(s).is_empty() and str(AllyRules.called(s)[0]["monster"]) == "imp")
	FeatureRules.pact_weapon(s, data, Sheet.HERO, "make:greatsword")
	TestUtils.fight(s, data, [{"monster": "goblin", "col": 3}])
	node("EventBus").state_changed.emit()
	await frames(6)
	var hero := CombatRules.player(s)
	step("in a fight: the act of the blade and the familiar's blow", Acts.one("familiar_strike").shown(s, data, hero) and FeatureRules.actions(s, data).any(func(a: Dictionary) -> bool: return str(a["id"]) == "pact_weapon"))
	await shot("fight")
