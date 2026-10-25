extends "res://tools/playtest/playtest_base.gd"
## «Правила 5e: особенности классов» playtest (python tools/godot_playtest.py --scenario features), v0.7.10, as in
## Baldur's Gate 3: the paladin hits — the window «Использовать?» offers Divine Smite by slot; the ogre hits back —
## the window offers a reaction; the dragonborn's breath is a button of the features tab; a druid takes a beast's
## shape from the list and fights in it.

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
	await tap("Preset_paladin_gordey")
	await press(find(screen(), "StartButton"))
	if not step("game started", await wait_until(func() -> bool: return screen_is("GameScreen") and not gs.is_busy(), 60.0)):
		return
	var s: GameSession = gs.session
	var c := s.character
	_level(c, data, 2)
	(c["features"] as Array).append("uncanny_dodge")  # a reaction to see the window (a rogue's, lent for the test)
	s.settings["reactions"] = "ask"

	# The paladin's hit: Divine Smite is asked.
	gs.start_combat([{"monster": "ogre", "col": 0}])
	if not step("a fight with an ogre", await _my_turn(gs, s)):
		return
	var ogre := CombatRules.fighter(s, CombatRules.enemies(s)[0])
	ogre["ac"] = 1
	var cs := screen()
	for i in 4:  # a natural 1 misses even AC 1: the next turn tries again
		await press(find(cs, "Attack_main"))
		await frames(2)
		await press(find(cs, "Foe_" + str(ogre["id"])))
		await frames(4)
		if s.combat.has("prompt"):
			break
		await press(find(screen(), "EndTurnButton"))
		await wait_until(func() -> bool: return s.combat.has("pending") or _ready_for_me(gs, s), 60.0)
		if s.combat.has("pending"):
			gs.combat_react("none")
		await _my_turn(gs, s)
		cs = screen()
	cs = screen()
	var ask: Control = find(cs, "CombatAsk")
	step("the smite window after the hit", ask != null and ask.visible and find(cs, "Ask_smite_1") != null, _text_of(ask).left(200) if ask != null else "")
	await shot("smite_window")
	var hp := int(ogre["hp"])
	var slots := SpellRules.slots_left(c, 1)
	await press(find(cs, "Ask_smite_1"))
	await frames(4)
	step("the smite spent a slot and hurt", SpellRules.slots_left(c, 1) == slots - 1 and int(ogre["hp"]) < hp, "%d → %d HP" % [hp, int(ogre["hp"])])

	# The breath on the features tab.
	cs = screen()
	var breath: Button = find(cs, "Feat_breath")
	step("the breath is a button of the features tab", breath != null, breath.tooltip_text if breath != null else "")
	cs.call("set_filter", "COMBAT_TAB_FEATURES")
	await frames(2)
	await shot("features_tab")

	# The ogre's hit: the reaction is asked.
	c["ac"] = 1
	await press(find(cs, "EndTurnButton"))
	var asked := await wait_until(func() -> bool: return s.combat.has("pending") or CombatRules.player_can_act(s), 60.0)
	await frames(4)
	cs = screen()
	step("the reaction window on the ogre's hit", asked and s.combat.has("pending") and find(cs, "Ask_uncanny_dodge") != null, _tail(4))
	await shot("reaction_window")
	if find(cs, "Ask_uncanny_dodge") != null:
		await press(find(cs, "Ask_uncanny_dodge"))
		await _my_turn(gs, s)
		step("the dodge halved the blow", _tail(12).contains("Невероятное уклонение"), _tail(5))

	# A druid's beast.
	gs.close_session()
	await frames(3)
	var druid := {}
	for p: Dictionary in data["presets"]:
		if p["id"] == "druid_olha":
			druid = CharacterBuilder.build_preset(p, data)
	var ds := GameSession.create(7, "now", "pushcha-edge", druid)
	_level(ds.character, data, 2)
	ds.settings = WorldPack.default_settings(data["pack"])
	gs.start(ds)
	ds.settings["reactions"] = "ask"
	await frames(5)
	gs.start_combat([{"monster": "goblin", "col": 2}])
	if not step("a druid's fight", await _my_turn(gs, ds)):
		return
	gs.combat_feature("wild_shape")
	await frames(4)
	cs = screen()
	step("the beasts to choose from", find(cs, "CombatAsk") != null and (find(cs, "CombatAsk") as Control).visible, _text_of(find(cs, "CombatAsk")).left(300))
	await shot("wild_shape_window")
	var beast := str(FeatureRules.beasts(ds.character, data)[0])
	await press(find(cs, "Ask_" + beast))
	await frames(4)
	step("the druid is a beast now", ds.character.has("wild_shape") and int(ds.character["ac"]) == int(data["monsters"][beast]["ac"]), _tail(2))
	await shot("wild_shape")


func _level(c: Dictionary, data: Dictionary, lv: int) -> void:
	while int(c["level"]) < lv:
		c["xp"] = LevelUp.xp_for(data, int(c["level"]) + 1)
		LevelUp.apply(c, data, LevelUp.default_picks(c, data))
		CharacterRules.refresh(c, data)
	c["hp"] = int(c["max_hp"])


func _my_turn(gs: Node, s: GameSession) -> bool:
	return await wait_until(func() -> bool: return _ready_for_me(gs, s), 120.0)


func _ready_for_me(gs: Node, s: GameSession) -> bool:
	return screen_is("CombatScreen") and not gs.is_busy() and not gs.combat_playing \
		and (CombatRules.player_can_act(s) or not str(s.combat.get("outcome", "")).is_empty())


func _tail(n: int) -> String:
	return " · ".join(_seen.slice(maxi(0, _seen.size() - n)))


func _text_of(n: Node) -> String:
	if n == null:
		return ""
	var out := ""
	for l: Node in n.find_children("*", "Label", true, false):
		out += (l as Label).text + "\n"
	for b: Node in n.find_children("*", "Button", true, false):
		out += (b as Button).text + " | "
	return out
