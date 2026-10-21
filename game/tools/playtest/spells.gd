extends "res://tools/playtest/playtest_base.gd"
## «Правила 5e: заклинания» playtest (python tools/godot_playtest.py --scenario spells), grows with the batches of
## v0.7.13: the cleric casts Bless by a button without a target (+к4 in the attack line), then Bane — the window
## «Прервать «Благословение»?» comes first; the foes keep the minus die.

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
	await tap("Preset_cleric_branko")
	await press(find(screen(), "StartButton"))
	if not step("game started", await wait_until(func() -> bool: return screen_is("GameScreen") and not gs.is_busy(), 60.0)):
		return
	var s: GameSession = gs.session
	var c := s.character
	_learn(c, ["bless", "bane", "guiding_bolt"])
	c["temp_hp"] = 500  # the hero lasts the whole scenario

	# v0.7.13.1: Bless, then Bane over it.
	gs.start_combat([{"monster": "goblin", "col": 1}, {"monster": "goblin", "col": 1}])
	if not step("a fight with goblins", await _my_turn(gs, s)):
		return
	var cs := screen()
	_tab(cs, "COMBAT_TAB_SPELLS")
	await frames(2)
	var bless: Button = find(cs, "Cast_bless")
	step("Bless is a button without a target", bless != null and not bless.toggle_mode, bless.text if bless != null else "")
	if bless != null:
		await press(bless)
		await frames(4)
	step("Bless held", str(c.get("concentration", "")) == "bless", _tail(2))
	await shot("bless")
	var foe := CombatRules.fighter(s, CombatRules.enemies(s)[0])
	var lines: Array[String] = []
	CombatRules._attack(s, data, str(c["name"]), "проба", 3, false, false, foe, "1d4", 0, "bludgeoning", lines)
	step("the d4 of Bless in an attack roll", lines[0].contains("(Благословение)"), lines[0])
	await press(find(screen(), "EndTurnButton"))
	await _my_turn(gs, s)
	cs = screen()
	_tab(cs, "COMBAT_TAB_SPELLS")
	await frames(2)
	var bane: Button = find(cs, "Cast_bane")
	var near := CombatRules.enemies(s).map(func(id: String) -> Dictionary: return CombatRules.fighter(s, id))
	near.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return CombatRules.cols_between(a, CombatRules.player(s)) < CombatRules.cols_between(b, CombatRules.player(s)))
	var goblin: Dictionary = near[0]
	goblin["hidden"] = false
	if step("Bane on the tab", bane != null):
		await press(bane)
		await frames(2)
		await press(find(cs, "Foe_" + str(goblin["id"])))
		await frames(4)
	var ask: Control = find(screen(), "CombatAsk")
	step("the concentration question", ask != null and ask.visible and find(ask, "Ask_conc_yes") != null, "")
	await shot("conc_question")
	if ask != null and find(ask, "Ask_conc_yes") != null:
		await press(find(ask, "Ask_conc_yes"))
		await frames(4)
	step("Bane now, Bless gone", str(c.get("concentration", "")) == "bane", _tail(4))
	await shot("bane")


func _learn(c: Dictionary, ids: Array) -> void:
	var sp: Dictionary = c["spells"]
	var always: Array = sp.get("always", [])
	for id: Variant in ids:
		if not always.has(id):
			always.append(id)
	sp["always"] = always
	c["slots_max"] = [4, 3, 2, 0, 0]
	c["slots_used"] = [0, 0, 0, 0, 0]


func _tab(cs: Control, key: String) -> void:
	for t: Node in cs.find_children("*", "TabContainer", true, false):
		var tabs := t as TabContainer
		for i in tabs.get_tab_count():
			if tabs.get_tab_title(i) == tr(key):
				tabs.current_tab = i


func _my_turn(gs: Node, s: GameSession) -> bool:
	return await wait_until(func() -> bool: return screen_is("CombatScreen") and not gs.is_busy() and not gs.combat_playing \
		and (CombatRules.player_can_act(s) or not str(s.combat.get("outcome", "")).is_empty()), 120.0)


func _tail(n: int) -> String:
	return " · ".join(_seen.slice(maxi(0, _seen.size() - n)))
