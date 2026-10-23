extends "res://tools/playtest/playtest_base.gd"
## «Правила 5e: заклинания» — every caster (python tools/godot_playtest.py --scenario casters), v0.7.13.9: the
## eight ready-made casters (the paladin and the ranger at level 2) each cast once from the sheet, once by words
## (a spell pinned to the message) and once in a fight with a goblin. The slot goes once, the line lands in the
## chat or the combat log; the stub master narrates (--real for the live one).

const CASTERS := ["bard_yas", "cleric_branko", "druid_olha", "paladin_gordey", "ranger_velena", "sorcerer_zlata", "warlock_fiber", "wizard_yalika"]
const LEVEL_TWO := ["paladin_gordey", "ranger_velena"]

var _seen: Array[String] = []


func run() -> void:
	var gs := node("GameState")
	var data: Dictionary = node("Catalog").data
	node("EventBus").combat_lines.connect(func(l: Array) -> void:
		for x: Variant in l:
			_seen.append(str(x)))
	if not step("master connected", await wait_until(func() -> bool: return node("Backend").is_ready(), 30.0)):
		return
	for id: String in CASTERS:
		await _hero(gs, data, id)


func _hero(gs: Node, data: Dictionary, preset_id: String) -> void:
	var preset: Dictionary = {}
	for p: Dictionary in data["presets"]:
		if str(p["id"]) == preset_id:
			preset = p
	var c := CharacterBuilder.build_preset(preset, data)
	if LEVEL_TWO.has(preset_id):
		c["xp"] = LevelUp.xp_for(data, 2)
		LevelUp.apply(c, data, LevelUp.default_picks(c, data))
	gs.new_game(c)
	if not step(preset_id + ": game started", await wait_until(func() -> bool: return screen_is("GameScreen") and not gs.is_busy(), 90.0)):
		return
	var s: GameSession = gs.session
	c = s.character
	var ready := SpellRules.ready(c)
	step(preset_id + ": spells", not ready.is_empty(), ", ".join(ready))

	# The sheet: a levelled spell out of a fight (the engine's own first, if the hero has one).
	var sheet := _pick(data, ready, func(id: String) -> bool: return SpellRules.level_of(data, id) > 0 and SpellEffects.spec(data, id).size() > 0 		and not SpellEffects.spec(data, id).has("reaction"))
	if sheet.is_empty():
		sheet = _pick(data, ready, func(id: String) -> bool: return SpellRules.level_of(data, id) > 0)
	if not sheet.is_empty():
		var used := _used(c)
		var chat := s.chat.size()
		var err: String = gs.cast(sheet, 0)
		await wait_until(func() -> bool: return not gs.is_busy(), 90.0)
		step("%s: the sheet — %s" % [preset_id, data["spells"][sheet]["name"]], err.is_empty() and _used(c) == used + 1,
			"%s · slots %d → %d · %s" % [err, used, _used(c), _effects(s, chat)])
		await shot(preset_id + "_sheet")
		ConditionRules.end_concentration(s, data, "проба")
	_rest(c)

	# Words: a cantrip pinned to the message (a levelled spell for the half-casters), the slot goes once.
	var words := _pick(data, ready, func(id: String) -> bool: return SpellRules.level_of(data, id) == 0)
	if words.is_empty():
		words = _pick(data, ready, func(id: String) -> bool: return id != sheet and SpellRules.level_of(data, id) > 0)
	if not words.is_empty():
		var slot := 0 if SpellRules.level_of(data, words) == 0 else SpellRules.lowest_slot(c, data, words)
		var used := _used(c)
		var chat := s.chat.size()
		gs.attach("spell", words, slot, "")
		await frames(2)
		var game := screen()
		var text := "Колдую «%s», как учили." % data["spells"][words]["name"]
		game.get("input").text = text
		game.get("send_button").pressed.emit()
		await wait_until(func() -> bool: return gs.is_busy(), 5.0)
		await wait_until(func() -> bool: return not gs.is_busy(), 150.0)
		step("%s: words — %s" % [preset_id, data["spells"][words]["name"]],
			_used(c) == used + (1 if slot > 0 else 0) and _effects(s, chat).contains(str(data["spells"][words]["name"])),
			"slots %d → %d · %s" % [used, _used(c), _effects(s, chat)])
		await shot(preset_id + "_words")
		ConditionRules.end_concentration(s, data, "проба")
	_rest(c)

	# The fight: the first spell the engine lets the hero cast at the goblin or on itself.
	c["temp_hp"] = 300
	gs.start_combat([{"monster": "goblin", "col": 2}])
	if not step(preset_id + ": a fight", await _my_turn(gs, s)):
		return
	var foe := str(CombatRules.enemies(s)[0])
	CombatRules.fighter(s, foe)["hidden"] = false
	var cast := {}
	for id: String in ready:
		for target: String in [foe, ""]:
			var slot := 0 if SpellRules.level_of(data, id) == 0 else SpellRules.lowest_slot(c, data, id)
			if cast.is_empty() and CombatRules.can_cast(s, data, id, slot, target).is_empty() and CombatRules.is_engine_spell(data, id):
				cast = {"id": id, "slot": slot, "target": target}
	if step(preset_id + ": a spell for the fight", not cast.is_empty(), ", ".join(ready)):
		var seen := _seen.size()
		var err: String = gs.combat_cast(str(cast["id"]), int(cast["slot"]), str(cast["target"]))
		await wait_until(func() -> bool: return not gs.is_busy() and not gs.combat_playing, 60.0)
		var log := " · ".join(_seen.slice(seen))
		step("%s: in the fight — %s" % [preset_id, data["spells"][cast["id"]]["name"]], err.is_empty() and not log.is_empty(), "%s · %s" % [err, log])
		await shot(preset_id + "_combat")
	for id: String in CombatRules.enemies(s):
		var g := CombatRules.fighter(s, id)
		g["hp"] = 0
		g["status"] = "dead"
	if CombatRules.player_can_act(s):
		await press(find(screen(), "EndTurnButton"))
	await wait_until(func() -> bool: return not str(s.combat.get("outcome", "")).is_empty() and not gs.combat_playing and not gs.is_busy(), 60.0)
	gs.finish_combat([])
	await wait_until(func() -> bool: return screen_is("GameScreen") and not gs.is_busy(), 60.0)


## The first id of `ids` that passes `ok`, "" if none.
func _pick(_data: Dictionary, ids: Array, ok: Callable) -> String:
	for id: Variant in ids:
		if ok.call(str(id)):
			return str(id)
	return ""


func _used(c: Dictionary) -> int:
	var n := 0
	for x: Variant in c.get("slots_used", []):
		n += int(x)
	return n


func _rest(c: Dictionary) -> void:
	c["slots_used"] = [0, 0, 0, 0, 0]


## The engine lines in the chat since `from`.
func _effects(s: GameSession, from: int) -> String:
	var out: Array[String] = []
	for i in range(from, s.chat.size()):
		if str(s.chat[i]["kind"]) == GameSession.KIND_EFFECT:
			out.append(" · ".join(s.chat[i].get("lines", [])))
	return " | ".join(out)


func _my_turn(gs: Node, s: GameSession) -> bool:
	return await wait_until(func() -> bool: return screen_is("CombatScreen") and not gs.is_busy() and not gs.combat_playing \
		and (CombatRules.player_can_act(s) or not str(s.combat.get("outcome", "")).is_empty()), 120.0)
