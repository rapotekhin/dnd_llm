extends "res://tools/playtest/playtest_base.gd"
## Companions in a fight are the player's (python tools/godot_playtest.py --scenario party_turn), v0.8.4.43.11, the author:
## «спутники в бою — в руках игрока, один в один как в BG3». Keira follows Aira into a fight with two wolves and a militiaman
## on their side: in her turn nothing moves by itself — the hotbar is hers (her face, her blows), her portrait is lit, the
## hint says whose turn it is; a click on a square walks her, her blow picked and a wolf's face pressed strikes it,
## «Конец хода» gives the turn on. The militiaman's turn goes by the AI as before.

const FOLLOWER := "npc_mercenary"


func run() -> void:
	var gs := node("GameState")
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
	s.room_id = "brod-square"
	s.character["hp"] = 200  # the wolves' bites must not end the scenario
	s.character["max_hp"] = 200
	Being.follow(s, FOLLOWER)
	node("EventBus").state_changed.emit()
	await frames(3)
	gs.start_combat([{"monster": "wolf", "name": "Волк", "count": 2}], {"allies": [{"monster": "guard", "name": "Ополченец"}]})
	if not step("a fight: the wolves, Keira and the militiaman beside", await wait_until(func() -> bool:
			return screen_is("fight") and not gs.is_busy() and not CombatRules.actor(s).is_empty(), 120.0)):
		return
	await frames(4)
	var said: Array[String] = []
	node("EventBus").combat_lines.connect(func(l: Array[String]) -> void: said.append_array(l))
	var her := CombatRules.fighter(s, FOLLOWER)
	if not step("Keira fights on the hero's side", not her.is_empty() and str(her.get("side")) == "ally"):
		return
	# Up to Keira's turn: the hero's turns end by the button.
	var guard := 0
	while CombatRules.current(s) != FOLLOWER and guard < 12 and str(s.combat.get("outcome", "")).is_empty():
		guard += 1
		if not CombatRules.actor(s).is_empty():
			await press(find(screen(), "EndTurnButton"))
		await wait_until(func() -> bool: return not gs.is_busy() and (not CombatRules.actor(s).is_empty() or not str(s.combat.get("outcome", "")).is_empty()), 90.0)
		await frames(2)
	if not step("Keira's turn waits for the player", CombatRules.current(s) == FOLLOWER and CombatRules.actor(s) == her and not gs.is_busy(), CombatRules.current(s)):
		return
	await frames(4)
	var bar: Control = find(screen(), "Bar")
	step("the hotbar is hers", str(bar.get("who").get("id", "")) == FOLLOWER, str(bar.get("who").get("id", "")))
	var mine: Control = find(find(screen(), "Party"), "Portrait_" + FOLLOWER)
	step("her portrait in the party column is lit", mine != null and bool(mine.get("picked")))
	var hint: Label = find(screen(), "Hint")
	step("the hint says whose turn it is", hint != null and hint.text.contains(str(her["name"])), hint.text if hint != null else "")
	var blows: Array = []
	for b: Node in find(screen(), "Bar").find_children("Blow_*", "", true, false):
		blows.append(b)
	step("her blows on the bar, not the hero's sword", not blows.is_empty() and find(screen(), "Attack_main") == null, str(blows.map(func(b: Node) -> String: return str(b.name))))
	var end_turn: Button = find(screen(), "EndTurnButton")
	step("«Конец хода» is hers to press", end_turn != null and not end_turn.disabled)
	await shot("her_turn")

	# A click on a square walks her, not the hero.
	var field: Control = find(screen(), "Field")
	var from := FightGrid.cell(her)
	var hero_at := FightGrid.cell(CombatRules.player(s))
	var routes: Dictionary = field.get("routes")
	var to := Vector2i(-1, -1)
	for c: Vector2i in routes:
		if c != from and FightGrid.dist_to(her, c) <= 2 and (to.x < 0 or FightGrid.dist_to(her, c) > FightGrid.dist_to(her, to)):
			to = c
	if step("her routes on the map", to.x >= 0, str(routes.size())):
		field.cell_clicked.emit(to)
		await wait_until(func() -> bool: return not gs.is_busy() and not field.call("walking"), 30.0)
		await frames(4)
		step("a click walks her", FightGrid.cell(her) != from and FightGrid.cell(CombatRules.player(s)) == hero_at, "%s → %s" % [from, FightGrid.cell(her)])

	# Her blow at a wolf by its face in the queue.
	var wolf := ""
	for id: String in CombatRules.enemies(s):
		wolf = id
	FightGrid.put(CombatRules.fighter(s, wolf), FightGrid.free_near(s, data, FightGrid.cell(her) + Vector2i(1, 0), 1))
	node("EventBus").state_changed.emit()
	await frames(4)
	var blow: Button = null
	for b: Node in find(screen(), "Bar").find_children("Blow_*", "", true, false):
		if blow == null and not (b as Button).disabled:
			blow = b
	if step("her blow can be picked", blow != null):
		await press(blow)
		await frames(3)
		var face: Control = find(screen(), "Turn_" + wolf)
		face.mouse_entered.emit()
		await frames(2)
		step("the wolf's face says her chance", hint.text.contains("%"), hint.text)
		await shot("her_blow_aimed")
		face.mouse_exited.emit()
		var n := said.size()
		await press(face as BaseButton)
		await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
		await frames(4)
		var lines := said.slice(n)
		step("she strikes the wolf", lines.any(func(l: String) -> bool: return l.begins_with(str(her["name"])) and l.contains("Волк")), " | ".join(lines).left(300))
		await shot("her_blow")
	end_turn = find(screen(), "EndTurnButton")
	if step("«Конец хода»", end_turn != null and not end_turn.disabled):
		await press(end_turn)
		await wait_until(func() -> bool: return not gs.is_busy() and (not CombatRules.actor(s).is_empty() or not str(s.combat.get("outcome", "")).is_empty()), 90.0)
		await frames(3)
		step("the turn went on", CombatRules.current(s) != FOLLOWER or int(s.combat.get("round", 1)) > 1, CombatRules.current(s))
	# The militiaman strikes by the AI in his own turn: his line comes with nobody's press.
	step("the militiaman goes by the AI", said.any(func(l: String) -> bool: return l.begins_with("Ополченец")), "\n".join(said).right(400))
	await shot("after")
