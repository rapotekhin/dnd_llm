extends "res://tools/playtest/playtest_base.gd"
## «Правила 5e: монстры» playtest (python tools/godot_playtest.py --scenario monsters [--real]), v0.7.9: a giant spider
## webs the hero (the card of an inspected spider tells it, «Вырваться» breaks the web), the spider's turn follows its
## rules; a ghoul's claws paralyse — the hero's turn passes by itself; a wolf left alone with a downed hero walks off.
## With --real the master narrates the rounds from the engine's lines.


var _seen: Array[String] = []  # every combat line, the log of the round is cleared when the master narrates it


func run() -> void:
	var gs := node("GameState")
	node("EventBus").combat_lines.connect(func(l: Array) -> void:
		for x: Variant in l:
			_seen.append(str(x)))
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

	# A giant spider: the web, the card, breaking free.
	s.known_monsters.append("giant_spider")
	gs.start_combat([{"monster": "giant_spider", "col": 2}])
	if not step("a fight with a spider", await _my_turn(gs, s)):
		return
	var spider := CombatRules.fighter(s, CombatRules.enemies(s)[0])
	var web := {}
	for a: Dictionary in data["monsters"]["giant_spider"]["actions"]:
		if str(a["name_en"]) == "Web":
			web = a
	var lines: Array[String] = []
	MonsterRules.apply_effect(s, data, spider, web, 0, lines)
	node("EventBus").state_changed.emit()
	await frames(4)
	var cs := screen()
	step("the web holds the hero", ConditionRules.has(c, "restrained"), ", ".join(lines))
	var card: Control = find(cs, "Foe_" + str(spider["id"]))
	if card != null:
		card.mouse_entered.emit()
	var details: Control = find(cs, "CombatDetails")
	step("the inspected spider's card tells the web", _text_of(details).contains("опутан (вырваться — Сл 12)"), _text_of(details).left(400))
	var escape: Button = find(cs, "Do_escape")
	step("the escape button", escape != null and not escape.disabled)
	await shot("spider_web")
	c["skills"]["athletics"] = 30  # the playtest wants the web broken
	if escape != null and not escape.disabled:
		await press(escape)
		await frames(3)
	step("the web is broken", not ConditionRules.has(c, "restrained"), " · ".join(s.combat.get("log", []).slice(-2)))
	await press(find(screen(), "EndTurnButton"))
	await _my_turn(gs, s)
	step("info: the spider's turn", true, _log_tail(s, 6))
	await shot("spider_turn")
	gs.finish_combat([])
	await wait_until(func() -> bool: return screen_is("GameScreen") and not gs.is_busy(), 120.0)

	# A ghoul: paralysis — the hero's turn passes by itself.
	c["hp"] = int(c["max_hp"])
	for cond: String in c["conditions"].duplicate():
		ConditionRules.remove(c, cond)
	gs.start_combat([{"monster": "ghoul", "col": 0}])
	if not step("a fight with a ghoul", await _my_turn(gs, s)):
		return
	var ghoul := CombatRules.fighter(s, CombatRules.enemies(s)[0])
	var claws := {}
	for a: Dictionary in data["monsters"]["ghoul"]["actions"]:
		if str(a["name_en"]) == "Claws":
			claws = a
	for ab: String in c["saves"]:
		c["saves"][ab] = -40
	lines.clear()
	MonsterRules.apply_effect(s, data, ghoul, claws, 0, lines)
	step("the claws paralyse", ConditionRules.has(c, "paralyzed"), ", ".join(lines))
	CharacterRules.refresh(c, data, s.items)
	node("EventBus").state_changed.emit()
	await frames(3)
	await shot("ghoul_paralysis")
	step("the paralysed hero has no buttons", (find(screen(), "EndTurnButton") as Button).disabled)
	s.combat["turn"] = (s.combat["order"] as Array).find(CombatRules.PLAYER)  # as if the claws came on the ghoul's turn
	gs.call("_combat_continue")
	await wait_until(func() -> bool: return not gs.combat_playing and not gs.is_busy(), 120.0)
	await _my_turn(gs, s)
	step("the paralysed hero's turn passed by itself", _log_all(s).contains("не может действовать"), _log_tail(s, 8))
	await shot("ghoul_after")


func _my_turn(gs: Node, s: GameSession) -> bool:
	return await wait_until(func() -> bool: return _ready_for_me(gs, s), 120.0)


func _ready_for_me(gs: Node, s: GameSession) -> bool:
	return screen_is("CombatScreen") and not gs.is_busy() and not gs.combat_playing \
		and (CombatRules.player_can_act(s) or not str(s.combat.get("outcome", "")).is_empty())


func _log_all(_s: GameSession) -> String:
	return " · ".join(_seen)


func _log_tail(_s: GameSession, n: int) -> String:
	return " · ".join(_seen.slice(maxi(0, _seen.size() - n)))


func _text_of(n: Node) -> String:
	if n == null:
		return ""
	var out := ""
	for l: Node in n.find_children("*", "Label", true, false):
		out += (l as Label).text + "\n"
	return out
