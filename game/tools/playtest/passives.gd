extends "res://tools/playtest/playtest_base.gd"
## The passives and the reactions as in BG3 (python tools/godot_playtest.py --scenario passives, v0.8.4.43.7): the
## hotbar's «Пассивные» of a barbarian — «Не убивать» and Reckless Attack as switches, the same in a fight and out of
## it; Reckless Attack switched on goes by itself on the first blow; the book's reactions — each its own «Спрашивать /
## Всегда / Никогда»: «Атака при отходе» set to «Никогда» lets a goblin walk off unharmed, «Всегда» strikes it.

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
	await tap("Preset_barbarian_urga")
	await press(find(screen(), "StartButton"))
	if not step("game started", await wait_until(func() -> bool: return screen_is("GameScreen") and not gs.is_busy(), 60.0)):
		return
	var s: GameSession = gs.session
	var c := s.character
	while int(c["level"]) < 2:  # Reckless Attack comes at the 2nd level
		c["xp"] = LevelUp.xp_for(data, int(c["level"]) + 1)
		LevelUp.apply(c, data, LevelUp.default_picks(c, data))
		CharacterRules.refresh(c, data)
	c["hp"] = int(c["max_hp"])
	(c["features"] as Array).append("uncanny_dodge")  # a second reaction to choose apart (a rogue's, lent for the test)
	s.settings["reactions"] = "ask"
	node("EventBus").state_changed.emit()
	await frames(4)

	var game := screen()
	var bar := game.get_tree().get_first_node_in_group("hotbar") as Control
	bar.call("set_filter", "BAR_PASSIVE")
	await frames(4)
	var reckless: BaseButton = find(bar, "Toggle_reckless")
	var spare: BaseButton = find(bar, "Toggle_nonlethal")
	step("«Пассивные»: «Не убивать» and Reckless Attack, no captions", reckless != null and spare != null and reckless.is_visible_in_tree()
		and find(bar, "Filter_passive") != null and (find(bar, "Filter_passive") as Button).button_pressed)
	step("both off at first", reckless != null and not reckless.button_pressed and not ToggleRules.on(s, data, Sheet.HERO, "reckless"))
	await press(reckless)
	await frames(4)
	reckless = find(bar, "Toggle_reckless")
	step("a press switches it on: lit and kept on the hero", reckless.button_pressed and ToggleRules.on(s, data, Sheet.HERO, "reckless")
		and bool(c.get("toggles", {}).get("reckless", false)))
	step("its card says what it does", str(reckless.get("tip_body")).contains("Силой") and str(reckless.get("tip_title")) == "Безрассудная атака")
	await shot("passives_peace")

	# The book: each reaction its own choice.
	(game.get("input") as Control).release_focus()  # the chat input takes letters while it has the focus
	await frames(2)
	await key(KEY_K)
	var sheet: Control = find(screen(), "CharacterSheet")
	if not step("K opens the book", sheet != null and sheet.visible and str(sheet.get("section")) == "book"):
		return
	await frames(3)
	var never: BaseButton = find(sheet, "React_opportunity_never")
	step("«Атака при отходе» with its own three choices", never != null and find(sheet, "React_opportunity_ask") != null and find(sheet, "React_opportunity_always") != null
		and (find(sheet, "React_opportunity_ask") as BaseButton).button_pressed)
	await press(never)
	await frames(4)
	step("«Никогда» kept on the hero", str(c.get("reacts", {}).get("opportunity", "")) == "never"
		and (find(sheet, "React_opportunity_never") as BaseButton).button_pressed)
	step("the other reaction keeps its own choice", (find(sheet, "React_uncanny_dodge_ask") as BaseButton).button_pressed
		and FeatureRules.policy(s, Sheet.HERO, "uncanny_dodge") == "ask")
	await shot("reactions_never")
	sheet.visible = false
	await frames(2)


	gs.start_combat([{"monster": "goblin", "beside": true}])
	if not step("a fight with a goblin", await _my_turn(gs, s)):
		return
	var cs := screen()
	bar = cs.get_tree().get_first_node_in_group("hotbar") as Control
	bar.call("set_filter", "BAR_PASSIVE")
	await frames(4)
	reckless = find(bar, "Toggle_reckless")
	step("the same switches in the fight, still on", reckless != null and reckless.is_visible_in_tree() and reckless.button_pressed)
	await shot("passives_fight")
	var goblin := CombatRules.fighter(s, CombatRules.enemies(s)[0])
	goblin["hp"] = 200
	goblin["max_hp"] = 200
	bar.call("set_filter", "")
	await frames(2)
	await press(find(cs, "Attack_main"))
	await frames(2)
	await press(find(cs, "Foe_" + str(goblin["id"])))
	await frames(6)
	step("the first blow is reckless by itself", bool(CombatRules.player(s).get("reckless", false)) and _seen.any(func(l: String) -> bool: return l.contains("безрассудно")),
		_tail(4))

	var me := CombatRules.player(s)
	me["reacted"] = false
	var lines: Array[String] = []
	CombatRules.leaving(s, data, goblin, _away(me, goblin), lines)
	step("the goblin walks off unharmed: no blow after it", not bool(me.get("reacted", false)) and not lines.any(func(l: String) -> bool: return l.contains("вдогонку")),
		" · ".join(lines))
	gs.choose_reaction("opportunity", "always")
	lines.clear()
	CombatRules.leaving(s, data, goblin, _away(me, goblin), lines)
	step("set to «Всегда» the hero strikes after it", bool(me.get("reacted", false)) and lines.any(func(l: String) -> bool: return l.contains("вдогонку")), " · ".join(lines))


## A square one step further from `me` than the goblin stands.
func _away(me: Dictionary, f: Dictionary) -> Vector2i:
	var at := FightGrid.cell(f)
	var d := at - FightGrid.cell(me)
	return at + Vector2i(signi(d.x), signi(d.y))


func _my_turn(gs: Node, s: GameSession) -> bool:
	return await wait_until(func() -> bool: return _ready_for_me(gs, s), 120.0)


func _ready_for_me(gs: Node, s: GameSession) -> bool:
	return screen_is("fight") and not gs.is_busy() and not gs.combat_playing 		and (CombatRules.player_can_act(s) or not str(s.combat.get("outcome", "")).is_empty())


func _tail(n: int) -> String:
	return " · ".join(_seen.slice(maxi(0, _seen.size() - n)))
