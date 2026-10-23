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
	_learn(c, ["bless", "bane", "guiding_bolt", "shield_of_faith", "sanctuary", "fly", "haste", "hunters_mark", "moonbeam", "spiritual_weapon", "grease"])
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
	step("Bane now, Bless gone", str(c.get("concentration", "")) == "bane" and not SpellEffects.has(c, "die") or 		SpellEffects.hero_effects(c, "die").all(func(e: Dictionary) -> bool: return str(e["source"]["id"]) != "bless"), _tail(4))
	step("Bane on the goblins", _seen.any(func(l: String) -> bool: return l.contains("Бедствие:") and l.contains("спасбросок")), _tail(6))
	await shot("bane")

	# v0.7.13.2: Shield of Faith asks too — «no» keeps Bane; Sanctuary (a bonus action) goes on.
	await press(find(screen(), "EndTurnButton"))
	await _my_turn(gs, s)
	cs = screen()
	_tab(cs, "COMBAT_TAB_SPELLS")
	await frames(2)
	c["slots_used"] = [0, 0, 0, 0, 0]  # the level-1 cleric spent both slots on Bless and Bane
	node("EventBus").state_changed.emit()
	await frames(3)
	cs = screen()
	_tab(cs, "COMBAT_TAB_SPELLS")
	await frames(2)
	var ac := int(c["ac"])
	var sof: Button = find(cs, "Cast_shield_of_faith")
	if step("Shield of Faith on the tab", sof != null):
		await press(sof)
		await frames(3)
		var no: Button = find(screen(), "Ask_conc_no")
		step("asked again", no != null)
		if no != null:
			await press(no)
			await frames(3)
	step("«no» keeps Bane and the AC", str(c.get("concentration", "")) == "bane" and int(c["ac"]) == ac)
	var sanct: Button = find(screen(), "Cast_sanctuary")
	if step("Sanctuary on the tab", sanct != null):
		await press(sanct)
		await frames(4)
	step("Sanctuary on the hero", not SpellEffects.hero_effects(c, "sanctuary").is_empty(), _tail(2))
	await shot("sanctuary")

	# v0.7.13.3: Fly over wolves — they cannot reach; Haste gives one more attack.
	for id: String in CombatRules.enemies(s):
		var g := CombatRules.fighter(s, id)
		g["hp"] = 0
		g["status"] = "dead"
	await press(find(screen(), "EndTurnButton"))
	await wait_until(func() -> bool: return not str(s.combat.get("outcome", "")).is_empty() and not gs.combat_playing and not gs.is_busy(), 60.0)
	gs.finish_combat([])
	await wait_until(func() -> bool: return screen_is("GameScreen") and not gs.is_busy(), 60.0)
	c["slots_used"] = [0, 0, 0, 0, 0]
	ConditionRules.end_concentration(s, data, "новый бой")
	c["hp"] = int(c["max_hp"])
	c["temp_hp"] = 500
	ConditionRules.remove(c, "unconscious")
	ConditionRules.remove(c, "prone")
	gs.start_combat([{"monster": "wolf", "col": 0}])
	if not step("a fight with a wolf", await _my_turn(gs, s)):
		return
	c["slots_max"] = [4, 3, 3, 0, 0]  # a level-1 cleric lent third-circle slots for the test
	c["slots_used"] = [0, 0, 0, 0, 0]
	node("EventBus").state_changed.emit()
	await frames(3)
	cs = screen()
	_tab(cs, "COMBAT_TAB_SPELLS")
	await frames(2)
	var fly: Button = find(cs, "Cast_fly")
	if step("Fly on the tab", fly != null):
		await press(fly)
		await frames(4)
	step("flying", SpellEffects.has(c, "flying"), _tail(2))
	_seen.clear()
	await press(find(screen(), "EndTurnButton"))
	await _my_turn(gs, s)
	step("the wolf cannot reach", _seen.any(func(l: String) -> bool: return l.contains("не достаёт летящего")), _tail(3))
	await shot("fly")


	# v0.7.13.4: Hunter's Mark on the wolf (the question about Fly first), then a hit adds the d6.
	await _my_turn(gs, s)
	cs = screen()
	_tab(cs, "COMBAT_TAB_SPELLS")
	await frames(2)
	var wolf := CombatRules.fighter(s, CombatRules.enemies(s)[0])
	wolf["ac"] = 1
	wolf["hp"] = 200
	var hm: Button = find(cs, "Cast_hunters_mark")
	if step("Hunter's Mark on the tab", hm != null):
		await press(hm)
		await frames(2)
		await press(find(cs, "Foe_" + str(wolf["id"])))
		await frames(3)
		var yes: Button = find(screen(), "Ask_conc_yes")
		if yes != null:
			await press(yes)
			await frames(4)
	step("the wolf is marked", SpellEffects.hit_extras(s.character, wolf, "bludgeoning").size() == 1,
		"%s | %s | wolf %s" % [_tail(3), str(SpellEffects.hero_effects(s.character, "mark")), wolf["id"]])
	var probe: Array[String] = []
	for i in 4:
		probe.clear()
		CombatRules._attack(s, data, str(c["name"]), "проба", 10, false, false, wolf, "1d6", 0, "bludgeoning", probe)
		if probe[0].contains("попадание"):
			CombatRules._item_extras(s, data, {"type": "bludgeoning", "id": ""}, wolf, false, probe)
			break
	step("the mark's d6 on a hit", probe.any(func(l: String) -> bool: return l.contains("Метка охотника: ещё")), " · ".join(probe))
	await shot("hunters_mark")

	# v0.7.13.5: Moonbeam on the wolf's column (the question about the mark), the label on the field; Spiritual Weapon's button.
	await press(find(screen(), "EndTurnButton"))
	await _my_turn(gs, s)
	c["slots_max"] = [4, 3, 3, 0, 0]
	c["slots_used"] = [0, 0, 0, 0, 0]
	node("EventBus").state_changed.emit()
	await frames(3)
	cs = screen()
	_tab(cs, "COMBAT_TAB_SPELLS")
	await frames(2)
	var mb: Button = find(cs, "Cast_moonbeam")
	if step("Moonbeam on the tab", mb != null):
		await press(mb)
		await frames(2)
		await press(find(cs, "Foe_" + str(wolf["id"])))
		await frames(3)
		var yes2: Button = find(screen(), "Ask_conc_yes")
		if yes2 != null:
			await press(yes2)
			await frames(4)
	step("the beam on the field", not SpellEffects.zone_names(s, int(wolf["col"])).is_empty(), _tail(3))
	c["slots_max"] = [4, 3, 3, 0, 0]  # the cast refreshed the sheet (a level-1 cleric again)
	node("EventBus").state_changed.emit()
	await frames(3)
	_tab(screen(), "COMBAT_TAB_SPELLS")
	await frames(2)
	var sw: Button = find(screen(), "Cast_spiritual_weapon")
	if step("Spiritual Weapon on the tab", sw != null):
		await press(sw)
		await frames(2)
		await press(find(screen(), "Foe_" + str(wolf["id"])))
		await frames(4)
	_tab(screen(), "COMBAT_TAB_SPELLS")
	await frames(2)
	step("its button for the next turns", find(screen(), "Feat_spell_spiritual_weapon") != null, _tail(3))
	await shot("moonbeam")
	_seen.clear()
	await press(find(screen(), "EndTurnButton"))
	await _my_turn(gs, s)
	step("the wolf burns in the beam", _seen.any(func(l: String) -> bool: return l.contains("Лунный луч: Волк")), _tail(4))
	# v0.7.13.6: Grease under the wolf (no concentration: Moonbeam stays) — the label and a save.
	c["slots_max"] = [4, 3, 3, 0, 0]
	c["slots_used"] = [0, 0, 0, 0, 0]
	node("EventBus").state_changed.emit()
	await frames(3)
	cs = screen()
	_tab(cs, "COMBAT_TAB_SPELLS")
	await frames(2)
	var gr: Button = find(cs, "Cast_grease")
	if step("Grease on the tab", gr != null):
		await press(gr)
		await frames(2)
		await press(find(cs, "Foe_" + str(wolf["id"])))
		await frames(4)
	step("Grease on the field, Moonbeam kept", SpellEffects.zone_names(s, int(wolf["col"])).size() >= 2 and str(c.get("concentration", "")) == "moonbeam",
		", ".join(SpellEffects.zone_names(s, int(wolf["col"]))) + " | " + _tail(3))
	await shot("grease")
	# v0.7.13.7: the reaction window lists Shield next to the hit (the window itself is the features playtest's).
	_learn(c, ["shield"])
	c["slots_used"] = [0, 0, 0, 0, 0]
	var rx := FeatureRules.reactions(s, data, wolf, data["monsters"]["wolf"]["actions"][0], false, 5)
	step("Shield among the reactions", rx.any(func(r: Dictionary) -> bool: return str(r["id"]) == "spell_shield"), str(rx))


	# v0.7.13.8: out of the fight, in the dark gallery of the mine: Find Traps from the sheet, then Light.
	for id: String in CombatRules.enemies(s):
		var g := CombatRules.fighter(s, id)
		g["hp"] = 0
		g["status"] = "dead"
	await press(find(screen(), "EndTurnButton"))
	await wait_until(func() -> bool: return not str(s.combat.get("outcome", "")).is_empty() and not gs.combat_playing and not gs.is_busy(), 60.0)
	gs.finish_combat([])
	await wait_until(func() -> bool: return screen_is("GameScreen") and not gs.is_busy(), 60.0)
	ConditionRules.end_concentration(s, data, "конец боя")
	s.room_id = "mine-gallery"
	_learn(c, ["find_traps", "light"])
	c["slots_max"] = [4, 3, 3, 0, 0]
	c["slots_used"] = [0, 0, 0, 0, 0]
	var err: String = gs.cast("find_traps", 2)
	await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
	step("Find Traps finds the deadfall", err.is_empty() and s.chat.any(func(e: Dictionary) -> bool:
		return " ".join(e.get("lines", [])).contains("ловушка:")), err)
	var err2: String = gs.cast("light", 0)
	await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
	step("Light — the gallery is not dark", err2.is_empty() and SpellEffects.has(c, "light"), err2)
	await shot("world_spells")

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
