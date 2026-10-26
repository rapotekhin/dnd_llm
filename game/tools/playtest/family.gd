extends "res://tools/playtest/playtest_base.gd"
## Family (python tools/godot_playtest.py --scenario family), v0.7.32: Aira with a house and a bed proposes to Bruno,
## the wedding at the priestess, Bruno at home by night, a child at home, the birth, a name in the «Семья» window,
## the child grown to the heir; the death screen offers to play on as the heir and the heir wakes at home.


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
	var data: Dictionary = node("Catalog").data
	var s: GameSession = gs.session
	var c := s.character
	c["gender"] = "female"
	c["gold_cp"] = 100000
	s.settings["needs"] = false
	s.rested_at = TimeRules.abs_minute(s) + 400 * 1440  # the days fly by: no sleep debt
	PropertyRules.buy(s, data, "river_house")
	PropertyRules.state(c)["river_house"]["deed"] = true  # without a deed the house is lost in a dispute over the days
	PropertyRules.upgrade(s, data, "river_house", "bed")
	TimeRules.advance(s, data, 1440)
	s.room_id = "brod-tavern-hall"
	s.minute = 12 * 60
	c["bonds"] = {"npc_innkeeper": {"kind": "romance", "points": 112}}
	node("EventBus").state_changed.emit()
	await frames(3)

	await open_row("More_npc_innkeeper")
	await press(find(screen(), "Bond_npc_innkeeper"))
	await frames(4)
	var bond: Control = find(screen(), "BondView")
	var pr: Button = find(bond, "Propose_npc_innkeeper")
	if not step("«Сделать предложение» in the bond window", pr != null and not pr.disabled):
		await shot("no_propose")
		return
	await shot("propose")
	await press(pr)
	await frames(4)
	step("Bruno says yes", FamilyRules.engaged(s) == "npc_innkeeper", _last_effects(s))
	bond.visible = false

	s.room_id = "brod-temple"
	node("EventBus").state_changed.emit()
	await frames(3)
	step("«Семья» on the panel", find(screen(), "FamilyButton") != null)
	await open_row("More_npc_priestess")
	var wd: Button = find(screen(), "Wedding_npc_priestess")
	if not step("«Свадьба» at the priestess", wd != null and not wd.disabled):
		await shot("no_wedding")
		return
	await shot("temple")
	await press(wd)
	await frames(4)
	step("married", FamilyRules.spouse(s) == "npc_innkeeper", _last_effects(s))
	await shot("wedding")

	s.room_id = str(FamilyRules.view(c)["home_room"])
	s.minute = 21 * 60
	node("EventBus").state_changed.emit()
	await frames(3)
	step("Bruno at home at night", SceneRules.npcs(s, data["world"], s.room_id).has("npc_innkeeper"))
	await press(find(screen(), "FamilyButton"))
	await frames(4)
	var fam: Control = find(screen(), "FamilyView")
	for i in 20:
		if FamilyRules.view(c).has("pregnant"):
			break
		FamilyRules.view(c).erase("tried_day")
		node("EventBus").state_changed.emit()
		await frames(2)
		await press(find(fam, "ChildTry"))
		await frames(3)
	step("expecting a child", FamilyRules.view(c).has("pregnant"), _last_effects(s))
	await shot("expecting")

	var adv := TimeRules.advance(s, data, 27 * 1440)
	step("the family's help pays the house's tax", not adv.any(func(l: String) -> bool: return l.contains("налог")))
	s.minute = 21 * 60
	node("EventBus").state_changed.emit()
	await frames(3)
	var kids := FamilyRules.children(s)
	if not step("a child is born", kids.size() == 1):
		await shot("no_child")
		return
	var kid := kids[0]
	var edit: LineEdit = find(fam, "ChildName_" + kid)
	edit.text = "Светозар"
	await press(find(fam, "Rename_" + kid))
	await frames(3)
	step("the child named", BondRules.npc_name(s, data, kid) == "Светозар")
	await shot("family")

	s.day += 160
	node("EventBus").state_changed.emit()
	await frames(3)
	step("the grown child is the heir", FamilyRules.heir(s, data) == kid)
	step("the house still ours", (c.get("property", {}) as Dictionary).has("river_house"), str(FamilyRules.view(c)))
	await shot("heir")
	fam.visible = false

	node("EventBus").navigate.emit("death", {"epitaph": "Айра пала у Пущи."})
	await frames(6)
	var hb: Button = find(screen(), "HeirButton")
	if not step("«Играть наследником» on the death screen", hb != null):
		await shot("no_heir_button")
		return
	await shot("death")
	await press(hb)
	await frames(6)
	var cs: Node = screen()
	step("creation for the heir", "choices" in cs and str(cs.get("choices")["name"]) == "Светозар")
	await shot("heir_creation")
	var pre := CharacterBuilder.preset_choices(data["presets"][0])
	for k: String in pre:
		if not k in ["name", "gender", "race", "subrace"]:
			cs.get("choices")[k] = pre[k]
	step("the house before the heir", (gs.session.character.get("property", {}) as Dictionary).has("river_house"), str(gs.session.character.get("name")))
	cs.call("_finish")
	if not step("the heir plays", await wait_until(func() -> bool: return screen_is("GameScreen") and not gs.is_busy(), 60.0)):
		await shot("no_game")
		return
	s = gs.session
	step("the heir at home with the house", s.character["name"] == "Светозар" and s.room_id == str(FamilyRules.view(s.character)["home_room"])
		and (s.character.get("property", {}) as Dictionary).has("river_house"), "%s %s %s" % [s.character["name"], s.room_id, s.character.get("property", {}).keys()])
	step("the father at home", SceneRules.npcs(s, data["world"], s.room_id).has("npc_innkeeper"))
	await shot("heir_home")


func _last_effects(s: GameSession) -> String:
	for i in range(s.chat.size() - 1, -1, -1):
		if str(s.chat[i].get("kind", "")) == GameSession.KIND_EFFECT:
			return " · ".join(s.chat[i]["lines"])
	return ""
