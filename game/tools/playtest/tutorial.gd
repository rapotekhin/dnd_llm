extends "res://tools/playtest/playtest_base.gd"
## The tutorial end to end (python tools/godot_playtest.py --scenario tutorial), v0.8.4.44.8: «Обучение» on the new game,
## the seven halls of the dream as a player goes through them — each hall's screens of teaching passed, the search, the
## chest, the body's armour, the fighter untied, the goblins and the guards fought by the buttons (a death there brings
## the hall back), the cleric talked into coming by her ready words, the sixth hall's sword made and taken in hand, the
## dragon fought by the buttons to the end whatever it is, «Проснуться» — a new game in Brod from the same choices.
## dream_cave and dream check each piece on its own; here nothing is counted done by hand.

const TRIES := 3  # a fight lost this many times is let go: the run goes on, the report says so


func _idle(gs: Node) -> void:
	await wait_until(func() -> bool: return not gs.is_busy(), 90.0)
	await frames(4)


func _go(gs: Node, to: String) -> void:
	await lessons("pass", 1.0)
	gs.go(to)
	await _idle(gs)


## Hurt — a potion by the pack's own act, as the screen «Рана» teaches (a double click in the grid of things).
func _heal(gs: Node, data: Dictionary, when: String) -> void:
	var s: GameSession = gs.session
	if int(s.character["hp"]) >= int(s.character["max_hp"]) or int(s.character["inventory"].get("healing_potion", 0)) <= 0:
		return
	var drunk: String = gs.item_act(ItemActs.main(ItemActs.of(s, data, Being.HERO, "healing_potion")))
	await _idle(gs)
	step("a potion " + when, drunk.is_empty() and int(s.character["hp"]) > 0, "%s, HP %d/%d" % [drunk, s.character["hp"], s.character["max_hp"]])


## The fight of the hall the hero stands in, by the buttons, until it is over; a death brings the hall back and the
## fight is tried again. The outcome, "" — no fight here.
func _fight(gs: Node, label: String) -> String:
	for attempt in TRIES:
		var s: GameSession = gs.session
		if not CombatRules.active(s):
			walk_to_foes()
			await wait_until(func() -> bool: return CombatRules.active(gs.session) or gs.session != s, 30.0)
		s = gs.session
		if not CombatRules.active(s):
			return ""
		await lessons("fight", 1.0)
		await shot("fight_%s_%d" % [label.get_slice(" ", 0).replace("'", ""), attempt + 1])
		step("info: the order", true, ", ".join((s.combat.get("order", []) as Array).map(func(id: String) -> String:
			var f := CombatRules.fighter(s, id)
			return "%s %d%s" % [f.get("name", id), int(f.get("init", 0)), " (сюрприз)" if bool(f.get("surprised", false)) else ""])) + " · current " + str(CombatRules.current(s)) + " · busy " + str(gs.is_busy()))
		var turns := 0
		while CombatRules.active(s) and str(s.combat.get("outcome", "")).is_empty() and turns < 40:
			if not await hero_turn(120.0):
				break
			turns += 1
			await strike_turn(s)
		await wait_until(func() -> bool: return not gs.is_busy(), 120.0)
		var outcome := str(s.combat.get("outcome", ""))
		var rolled: Array = s.chat.filter(func(e: Dictionary) -> bool: return str(e.get("kind", "")) in [GameSession.KIND_ROLLS, GameSession.KIND_EFFECT])
		step("info: the fight's lines", true, " | ".join(rolled.slice(-4).map(func(e: Dictionary) -> String: return str(e.get("log", e.get("lines", ""))).left(600))))
		step("info: %s, try %d" % [label, attempt + 1], true, "%s after %d turns, HP %d/%d" % [outcome, turns, s.character["hp"], s.character["max_hp"]])
		if outcome == "dead":  # the dream: back to the hall's entry (v0.8.4.44.7)
			if not step("a death in the %s brings the hall back" % label, await wait_until(func() -> bool: return gs.session != s and not gs.is_busy(), 90.0)):
				return outcome
			await frames(4)
			continue
		await frames(4)
		var finish: Button = find(screen(), "FinishCombat")
		if finish != null and finish.is_visible_in_tree():
			await press(finish)
		await _idle(gs)
		return outcome
	return "dead"


func run() -> void:
	var gs := node("GameState")
	var sm := node("SaveManager")
	var data: Dictionary = node("Catalog").data
	sm.tutorial_done = false
	if not step("master connected", await wait_until(func() -> bool: return node("Backend").is_ready(), 30.0)):
		return
	await tap("NewGameButton")
	await frames(3)
	var tick: CheckButton = find(screen(), "TutorialToggle")
	step("«Обучение» on", tick != null and tick.visible and tick.button_pressed)
	await tap("NextButton")
	await tap("Preset_fighter_aira")
	await press(find(screen(), "StartButton"))
	if not step("the dream began", await wait_until(func() -> bool: return screen_is("GameScreen") and not gs.is_busy(), 90.0)):
		return
	var s: GameSession = gs.session
	data = node("Catalog").data
	step("in the first hall, nothing on", s.room_id == "dream-1" and (s.character["inventory"] as Dictionary).is_empty())
	var seen: Array[String] = []
	seen.append_array(await lessons("teach"))
	var map := WalkRules.view(s, data)
	await click_cell(WalkRules.way_cell(map, "dream-1", "dream-2"))  # «Осмотреться» is taught at the way out (v0.8.4.44.9)
	seen.append_array(await lessons("teach", 15.0))
	await tap("LookButton")  # one button: the Perception search
	await _idle(gs)
	step("the search finds the trap", not ExplorationRules.found_traps(s, data["world"], "dream-1").is_empty())
	gs.container_take_all("f_chest")
	step("the chest emptied", int(s.character["inventory"].get("healing_potion", 0)) > 0, str(s.character["inventory"]))
	if not gs.go("dream-2"):
		gs.trap_action("dream-2", false)
	await _idle(gs)
	await shot("hall_1_done")

	seen.append_array(await lessons("teach"))
	for c: Dictionary in CreatureRules.here(s, "dream-2"):
		if str(c["state"]) == CreatureRules.DEAD:
			gs.creature_act(str(c["id"]), "search")
			gs.container_take_all(CreatureRules.BOX + str(c["id"]))
	seen.append_array(await lessons("teach"))
	gs.equip("leather_armor", "armor")
	for w: String in ["longsword", "shortsword"]:
		if int(s.character["inventory"].get(w, 0)) > 0 and str(s.character["equipped"].get("main_hand", "")).is_empty():
			gs.equip(w, "main_hand")
	step("armour on, a blade in hand", str(s.character["equipped"].get("armor", "")) == "leather_armor" and not str(s.character["equipped"].get("main_hand", "")).is_empty(),
		str(s.character["equipped"]))
	await _go(gs, "dream-3")
	s = gs.session
	seen.append_array(await lessons("teach"))
	await _heal(gs, data, "after the trap")
	gs.creature_act("npc_dream_fighter", "untie")
	await _idle(gs)
	step("the fighter goes along", Being.follows(s, "npc_dream_fighter"))
	await shot("hall_3_done")

	await _heal(gs, data, "before the den")  # the stub master's turns hurt by turn: a player drinks before a fight
	await _go(gs, "dream-4")
	step("the goblins' fight", await _fight(gs, "goblins' den") == "victory")
	s = gs.session
	gs.creature_act("npc_dream_cleric", "untie")
	await _idle(gs)
	var lessons4 := await lessons("teach")
	seen.append_array(lessons4)
	if lessons4.has("improvise") and not s.options.is_empty():
		gs.choose_option(0)
		await _idle(gs)
	step("info: the cleric after her ready words", true, "follows: %s" % Being.follows(s, "npc_dream_cleric"))
	await shot("hall_4_done")

	await _go(gs, "dream-5")
	var guards := await _fight(gs, "guards' grotto")
	s = gs.session
	step("the guards beaten — here or come to the den's noise", guards == "victory" or (guards.is_empty() and s.encounters_done.has("dream_guards")), guards)
	step("ready for the 2nd level", LevelUp.can_level_up(s.character, data), str(s.character["xp"]))
	await shot("hall_5_done")

	await _go(gs, "dream-6")
	s = gs.session
	var lessons6 := await lessons("teach")
	seen.append_array(lessons6)
	if not s.options.is_empty():
		gs.choose_option(0)
		await _idle(gs)
	var made: Array = (s.character["inventory"] as Dictionary).keys().filter(func(id: String) -> bool:
		return str(ItemRules.def_of(data["items"], s.items, id).get("rarity", "")) == "legendary")
	if step("the sixth hall's sword", not made.is_empty(), str(s.character["inventory"])):
		gs.equip(str(made[0]), "main_hand")
	await shot("hall_6_done")

	await _go(gs, "dream-7")
	s = gs.session
	var dragon := await _fight(gs, "dragon's lair")
	s = gs.session
	step("the dragon's fight ends the dream either way", dragon in ["victory", "dream_end"] and (s.flags.has("dream_end") or s.encounters_done.has("dream_dragon")),
		dragon)
	step("info: legendary actions in the fight", true, str(s.chat.any(func(e: Dictionary) -> bool: return str(e).contains("легендарное"))))
	var last := await lessons("teach")
	seen.append_array(last)
	step("the waking last", not last.is_empty() and last.back() == "wake", str(last))
	step("info: screens of teaching seen", true, ", ".join(seen))
	await shot("hall_7_wake")
	var boxes := find_all(get_root(), "HintBox")
	if boxes.is_empty():
		return
	await press(find(boxes[0], "WakeButton"))
	if not step("woke into Brod", await wait_until(func() -> bool: return gs.session != s and screen_is("GameScreen") and not gs.is_busy(), 90.0)):
		return
	var w: GameSession = gs.session
	step("the Mark, level 1, its kit, nothing of the dream", w.world_id == "frontier" and int(w.character["level"]) == 1
		and not (w.character["inventory"] as Dictionary).is_empty() and w.dream.is_empty(), "%s / %s" % [w.world_id, w.room_id])
	step("the profile remembers the tutorial", sm.tutorial_done)
	await shot("woke_in_brod")
	sm.tutorial_done = false
	sm.save_settings()
