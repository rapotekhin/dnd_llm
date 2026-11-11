extends "res://tools/playtest/playtest_base.gd"
## The prisoner's branch (python tools/godot_playtest.py --scenario captives), v0.7.22.17: «Сдаться» in a fight with
## bandits — a captive at once, the things in a chest of the room; broken free, the longsword taken back from it; a
## creature of a truce is talked to, not «a prisoner», and its replies go when it is let go; a goblin bound in Brod is
## handed to the guard for a bounty; a goblin knocked out and bound comes to within 1d4 hours, still bound (v0.8.4.42.21).


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
	var s: GameSession = gs.session
	var data: Dictionary = node("Catalog").data
	s.room_id = "outpost-yard"
	s.encounters_done.append("yard_dead")
	gs.start_combat([{"monster": "bandit", "name": "Разбойник", "count": 2}], {"room_from": "outpost-road"})
	if not step("the fight with the bandits", await wait_until(func() -> bool:
			return screen_is("fight") and not gs.is_busy() and CombatRules.is_player_turn(s), 90.0)):
		return
	await frames(3)
	var give_up: Button = find(screen(), "Do_surrender")
	if not step("the «Сдаться» button", give_up != null and not give_up.disabled):
		return
	await shot("fight")
	await press(give_up)
	await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
	step("given up — captured at once", str(s.combat.get("outcome", "")) == "captured", str(s.combat.get("log", [])))
	gs.finish_combat()
	await wait_until(func() -> bool: return screen_is("GameScreen") and not gs.is_busy(), 60.0)
	await frames(3)
	var chest := {}
	for p: Dictionary in PropRules.room_props(s, s.room_id):
		if bool(p.get("seized", false)) or (ContainerRules.is_container(p) and (p.get("contents", {}) as Dictionary).has("longsword")):
			chest = p
	step("a captive, the things taken into a chest", EncounterRules.captive(s) and (s.character["inventory"] as Dictionary).is_empty() and not chest.is_empty(), _chat(s))
	await shot("captive")
	s.character["skills"]["athletics"] = 40
	var free: Button = find(screen(), "Escape_athletics")
	if free != null:
		await press(free)
		await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
		await frames(3)
	if not step("broke free", not EncounterRules.captive(s), _chat(s)):
		return
	var place: Button = find(screen(), "PlaceButton")
	if step("the place window", place != null and not place.disabled and not chest.is_empty()):
		await press(place)
		await frames(3)
		await press(find(screen(), "Container_" + str(chest["id"])))
		await frames(3)
		var view: Control = find(screen(), "ContainerView")
		await shot("chest")
		if view != null:
			view.call("stage", "longsword")  # v0.8.4.43.6: a thing's menu of the chest's grid
		var take: Button = find(view, "TakeOut_longsword") if view != null else null
		if step("the longsword in the chest", take != null):
			await press(take)
			await frames(3)
			step("the longsword taken back", int(s.character["inventory"].get("longsword", 0)) == 1 and OwnerRules.foreign(s).is_empty())
		if view != null:
			await press(find(view, "CloseContainerButton"))
			await frames(3)

	# A truce is no captivity: talked to as an equal, its replies go with it.
	s.lurking.erase(s.room_id)
	s.sneaking = false
	EncounterRules.as_creatures(s, s.room_id, [{"monster": "bandit", "name": "Разбойник"}], "truce")
	var truce: Dictionary = CreatureRules.here(s, s.room_id).back()
	node("EventBus").state_changed.emit()
	await frames(3)
	await open_row("CreatureMore_" + str(truce["id"]))  # v0.7.22.23: the acts under the line
	var talk: Button = find(screen(), "Creature_talk_" + str(truce["id"]))
	if step("talk to the creature of the truce", talk != null and not talk.disabled and find(screen(), "Creature_bind_" + str(truce["id"])) == null):
		await press(talk)
		await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
		await frames(3)
		step("not «a prisoner»", _chat(s).contains("Обращаюсь к: Разбойник") and not _chat(s).contains("пленнику"), _chat(s))
		await shot("truce_talk")
		await press(find(screen(), "Creature_free_" + str(truce["id"])))
		await frames(3)
		step("let go — its replies are gone", s.options.is_empty() and s.talk_creature.is_empty(), str(s.options))

	# A goblin bound in Brod goes to the guard.
	s.room_id = "brod-square"
	s.visited.append("brod-square")
	EncounterRules.as_creatures(s, s.room_id, [{"monster": "goblin", "name": "Гоблин"}], "surrendered")
	var gob: Dictionary = CreatureRules.here(s, s.room_id).back()
	node("EventBus").state_changed.emit()
	await frames(3)
	await open_row("CreatureMore_" + str(gob["id"]))
	var bind: Button = find(screen(), "Creature_bind_" + str(gob["id"]))
	if step("bind the goblin", bind != null and not bind.disabled):
		await press(bind)
		await frames(3)
	await open_row("CreatureMore_" + str(gob["id"]))  # v0.8.4.43.4: its menu built again, as the right button builds it
	var hand: Button = find(screen(), "Creature_hand_over_" + str(gob["id"]))
	step("bound — the hero's prisoner, the guard can take it", str(gob.get("owner", "")) == OwnerRules.HERO and hand != null and not hand.disabled)
	await shot("prisoner")
	if hand != null:
		var gold := int(s.character["gold_cp"])
		await press(hand)
		await frames(3)
		step("handed to the guard for a bounty", CreatureRules.find(s, s.room_id, str(gob["id"])).is_empty() and int(s.character["gold_cp"]) > gold, _chat(s))
		await shot("handed_over")

	await _wakes_bound(gs, s, data)


## v0.8.4.42.21 (the author: «пленники остаются без сознания даже после долгого отдыха»): a goblin knocked out in a fight,
## bound by the button, comes to within 1d4 hours of the «Ждать» window — still bound, the hero's prisoner, and it talks.
func _wakes_bound(gs: Node, s: GameSession, data: Dictionary) -> void:
	s.room_id = "outpost-yard"
	gs.start_combat([{"monster": "goblin", "name": "Гоблин-лазутчик"}], {"room_from": "outpost-road"})
	if not step("a fight with a goblin", await wait_until(func() -> bool:
			return screen_is("fight") and not gs.is_busy() and CombatRules.is_player_turn(s), 90.0)):
		return
	var fid: String = CombatRules.enemies(s)[0]
	var f := CombatRules.fighter(s, fid)
	FightGrid.put(f, FightGrid.free_near(s, data, FightGrid.cell(CombatRules.player(s)), int(f.get("span", 1))))
	s.combat["nonlethal"] = true
	s.combat["melee_strike"] = true
	var lines: Array[String] = []
	Harm.take(s, data, f, 999, lines)
	s.combat.erase("melee_strike")
	CombatRules.after_player_action(s, data)
	await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
	gs.finish_combat()
	await wait_until(func() -> bool: return screen_is("GameScreen") and not gs.is_busy(), 60.0)
	await frames(3)
	var c := CreatureRules.find(s, s.room_id, fid)
	if not step("knocked out — it lies at 0 HP", str(c.get("state", "")) == "unconscious" and int(c.get("hp", -1)) == 0, str(c)):
		return
	await open_row("CreatureMore_" + fid)
	var bind: Button = find(screen(), "Creature_bind_" + fid)
	if not step("bind the knocked-out goblin", bind != null and not bind.disabled):
		return
	await press(bind)
	await frames(3)
	step("no talk while it lies", find(screen(), "Creature_talk_" + fid) == null)
	await shot("bound_unconscious")
	var game := screen()
	game.get("_side").wait_requested.emit()
	await frames(3)
	var dialog: Control = find(game, "WaitView")
	(find(dialog, "WaitMinutes") as SpinBox).value = 241
	await frames(2)
	await press(find(dialog, "DialogConfirm"))
	await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
	await frames(3)
	c = CreatureRules.find(s, s.room_id, fid)
	step("came to within 1d4 hours — bound, the hero's prisoner, 1 HP",
		str(c.get("state", "")) == "surrendered" and bool(c.get("bound", false)) and str(c.get("owner", "")) == OwnerRules.HERO and int(c.get("hp", 0)) >= 1, str(c))
	step("the chat says it came to bound", _chat(s).contains("приходит в себя — связан"), _chat(s))
	await open_row("CreatureMore_" + fid)
	step("awake, it can be talked to", find(screen(), "Creature_talk_" + fid) != null)
	await shot("bound_awake")


func _chat(s: GameSession) -> String:
	var out: Array[String] = []
	for e: Dictionary in s.chat.slice(maxi(0, s.chat.size() - 4)):
		out.append(str(e.get("text", " · ".join(e.get("lines", [])))))
	return " | ".join(out).left(400)
