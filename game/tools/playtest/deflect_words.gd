extends "res://tools/playtest/playtest_base.gd"
## Deflect Missiles and Cutting Words by 5e (python tools/godot_playtest.py --scenario deflect_words, v0.8.4.43.46): a monk
## of the 3rd level is shot by a goblin archer — the reaction window offers to catch, the arrow is caught and thrown back
## for 1 ki; a bard is struck by a goblin — the window offers Cutting Words, a die of inspiration off the roll or the
## damage; a bandit bard of the foes cuts the hero's own blow by itself (anybody's reaction).

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
	await tap("Preset_monk_taras")
	await press(find(screen(), "StartButton"))
	if not step("game started", await wait_until(func() -> bool: return screen_is("GameScreen") and not gs.is_busy(), 60.0)):
		return
	var s: GameSession = gs.session
	var c := s.character
	_level(c, data, 3)
	s.settings["reactions"] = "ask"
	step("a monk of the 3rd level with Deflect Missiles and its passive on", FeatureRules.has(c, "deflect_missiles")
		and ToggleRules.on(s, data, Sheet.HERO, "deflect_throw") and Stock.left(c, data, "ki") >= 1)

	# The goblin archer: its scimitar gone, the bow in its hands, far from the monk.
	gs.start_combat([{"monster": "goblin"}])
	if not step("a fight with a goblin archer", await _my_turn(gs, s)):
		return
	var gob := CombatRules.fighter(s, CombatRules.enemies(s)[0])
	gob["hp"] = 200
	gob["max_hp"] = 200
	Gear.take(s, data, str(gob["id"]), "scimitar")
	if Equip.swap_why(s, data, str(gob["id"])).is_empty() and not str(Gear.of(s, data, str(gob["id"]))["equipped"].get("main_hand", "")).contains("bow"):
		Equip.swap(s, data, str(gob["id"]))
	c["ac"] = 1  # the arrow hits but on a natural 1
	var ki := Stock.left(c, data, "ki")
	var asked := false
	for i in 5:
		await press(find(screen(), "EndTurnButton"))
		await wait_until(func() -> bool: return s.combat.has("pending") or _ready_for_me(gs, s), 60.0)
		await frames(4)
		if find(screen(), "Ask_deflect_missiles") != null:
			asked = true
			break
		if s.combat.has("pending"):
			gs.combat_react("none")
		await _my_turn(gs, s)
	var cs := screen()
	step("the shot asks for Deflect Missiles", asked, _tail(5))
	if not asked:
		return
	step("the window says it catches and throws back", _text_of(find(cs, "CombatAsk")).contains("поймать"), _text_of(find(cs, "CombatAsk")).left(300))
	await shot("deflect_window")
	var hp := int(gob["hp"])
	await press(find(cs, "Ask_deflect_missiles"))
	await _my_turn(gs, s)
	await frames(4)
	var caught := _seen.any(func(l: String) -> bool: return l.contains("ловит на лету"))
	var thrown := _seen.any(func(l: String) -> bool: return l.contains("мечет"))
	step("the arrow caught", caught, _tail(8))
	step("thrown back for 1 ki", thrown and Stock.left(c, data, "ki") == ki - 1, "ки %d → %d · %s" % [ki, Stock.left(c, data, "ki"), _tail(6)])
	var lying: Array = (s.combat.get("dropped", []) as Array).filter(func(d: Dictionary) -> bool: return str(d.get("item", "")) == "arrows")
	step("the arrow lies on the field or struck the goblin", not lying.is_empty() or int(gob["hp"]) < hp, "%d → %d HP, на поле %d" % [hp, int(gob["hp"]), lying.size()])
	await shot("deflect_thrown")

	# The bard struck: Cutting Words in its window.
	gs.close_session()
	await frames(3)
	var bard := {}
	for p: Dictionary in data["presets"]:
		if p["id"] == "bard_yas":
			bard = CharacterBuilder.build_preset(p, data)
	var bs := GameSession.create(11, "now", "brod-square", bard)
	_level(bs.character, data, 3)
	bs.settings = WorldPack.default_settings(data["pack"])
	gs.start(bs)
	bs.settings["reactions"] = "ask"
	await frames(5)
	var bc := bs.character
	step("a bard of the 3rd level with Cutting Words", FeatureRules.has(bc, "cutting_words") and Stock.left(bc, data, "bardic_inspiration") >= 1)
	gs.start_combat([{"monster": "goblin", "beside": true}])
	if not step("a fight with a goblin beside", await _my_turn(gs, bs)):
		return
	var g2 := CombatRules.fighter(bs, CombatRules.enemies(bs)[0])
	g2["hp"] = 200
	g2["max_hp"] = 200
	bc["ac"] = 1
	var dice := Stock.left(bc, data, "bardic_inspiration")
	asked = false
	for i in 6:
		await press(find(screen(), "EndTurnButton"))
		await wait_until(func() -> bool: return bs.combat.has("pending") or _ready_for_me(gs, bs), 60.0)
		await frames(4)
		if find(screen(), "Ask_cutting_words") != null:
			asked = true
			break
		if bs.combat.has("pending"):
			gs.combat_react("none")
		await _my_turn(gs, bs)
	cs = screen()
	step("the goblin's blow asks for Cutting Words", asked, _tail(5))
	if not asked:
		return
	step("the window names the die and what it cuts", _text_of(find(cs, "CombatAsk")).contains("Язвительные слова"), _text_of(find(cs, "CombatAsk")).left(300))
	await shot("words_window")
	await press(find(cs, "Ask_cutting_words"))
	await _my_turn(gs, bs)
	await frames(4)
	step("the words spoken: a die of inspiration spent", _seen.any(func(l: String) -> bool: return l.contains("Язвительные слова"))
		and Stock.left(bc, data, "bardic_inspiration") == dice - 1, _tail(6))
	await shot("words_spoken")

	# A bard of the foes: the hero's blow cut by itself.
	gs.close_session()
	await frames(3)
	var fighter := {}
	for p: Dictionary in data["presets"]:
		if p["id"] == "fighter_aira":
			fighter = CharacterBuilder.build_preset(p, data)
	var fs := GameSession.create(13, "now", "brod-square", fighter)
	fs.settings = WorldPack.default_settings(data["pack"])
	gs.start(fs)
	fs.settings["reactions"] = "ask"
	await frames(5)
	_seen.clear()  # the bard's own words above must not count
	gs.start_combat([{"monster": "bandit", "class": "bard", "subclass": "lore", "level": 3, "beside": true}])  # Cutting Words: the College of Lore
	if not step("a fight with a bandit bard", await _my_turn(gs, fs)):
		return
	var bandit := CombatRules.fighter(fs, CombatRules.enemies(fs)[0])
	bandit["hp"] = 300
	bandit["max_hp"] = 300
	step("the bandit has Cutting Words of its class", FeatureRules.has(bandit, "cutting_words"))
	var spoke := false
	for i in 8:
		bandit["reacted"] = false
		await press(find(screen(), "Attack_main"))
		await frames(2)
		await press(find(screen(), "Turn_" + str(bandit["id"])))
		await frames(6)
		spoke = _seen.any(func(l: String) -> bool: return l.contains("Язвительные слова"))
		if spoke:
			break
		await press(find(screen(), "EndTurnButton"))
		await wait_until(func() -> bool: return fs.combat.has("pending") or _ready_for_me(gs, fs), 60.0)
		if fs.combat.has("pending"):
			gs.combat_react("none")
		await _my_turn(gs, fs)
	step("the bandit bard cut the hero's blow by itself", spoke, _tail(6))
	await shot("foe_words")


func _level(c: Dictionary, data: Dictionary, lv: int) -> void:
	while int(c["level"]) < lv:
		c["xp"] = LevelUp.xp_for(data, int(c["level"]) + 1)
		LevelUp.apply(c, data, LevelUp.default_picks(c, data))
		CharacterRules.refresh(c, data)
	c["hp"] = int(c["max_hp"])


func _my_turn(gs: Node, s: GameSession) -> bool:
	return await wait_until(func() -> bool: return _ready_for_me(gs, s), 120.0)


func _ready_for_me(gs: Node, s: GameSession) -> bool:
	return screen_is("fight") and not gs.is_busy() and not gs.combat_playing \
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
