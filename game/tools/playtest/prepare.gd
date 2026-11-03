extends "res://tools/playtest/playtest_base.gd"
## The master readies ahead (python tools/godot_playtest.py --scenario prepare), v0.8.4.25: on the stub master the second
## line furnishes the rooms around the tavern hall while the hero stands; walked into one, its things are those readied,
## laid before the entry turn; a board's orders readied from afar go up when it is read, without a master's turn; Bruno's
## quest readied ahead is given by «Есть дело?» in his own words. v0.8.4.25.3: the room is told by the description readied
## with its things, without an entry turn.

const HALL := "brod-tavern-hall"
const BRUNO := "npc_innkeeper"


func run() -> void:
	var gs := node("GameState")
	if not step("master connected", await wait_until(func() -> bool: return node("Backend").is_ready(), 30.0)):
		return
	await tap("NewGameButton")
	await tap("NextButton")
	await tap("Preset_fighter_aira")
	await press(find(screen(), "StartButton"))
	if not step("game started", await wait_until(func() -> bool: return screen_is("GameScreen") and not gs.is_busy(), 90.0)):
		return
	var s: GameSession = gs.session
	var data: Dictionary = node("Catalog").data
	s.settings["needs"] = false
	s.minute = 12 * 60
	if s.room_id != HALL:
		await _go(gs, HALL)
	gs._prepare()
	var rooms := func() -> Dictionary: return PrepareRules.part(s, PrepareRules.ROOMS)
	var exits := WayRules.open_exits(s, data["world"], s.room_id).filter(func(r: String) -> bool: return WorldView.new(data["world"]).is_public(r))  # no trespass
	if not step("the rooms around are furnished ahead", await wait_until(func() -> bool: return exits.any(func(r: String) -> bool: return rooms.call().has(r)), 60.0),
			", ".join((rooms.call() as Dictionary).keys())):
		return
	var next: String = exits.filter(func(r: String) -> bool: return rooms.call().has(r))[0]
	var readied: Array = rooms.call()[next]["effect"]["props"].map(func(p: Dictionary) -> String: return p["name"])
	step("nothing laid before the hero comes", PropRules.needs_furnish(s, next))
	await wait_until(func() -> bool: return gs._ahead.is_empty(), 60.0)
	var turns := []
	var started := func(id: String) -> void: turns.append(id)
	node("EventBus").turn_started.connect(started)
	await _go(gs, next)
	node("EventBus").turn_started.disconnect(started)
	var told: Dictionary = s.chat[s.chat.size() - 1]
	step("the room told at once, readied with its things", turns.is_empty() and str(told["kind"]) == GameSession.KIND_DM and str(told["text"]).contains("заготовленные"),
		"%s %s" % [turns, told])  # v0.8.4.25.3
	var names: Array = PropRules.room_props(s, next).map(func(p: Dictionary) -> String: return p["name"])
	step("the room has the things readied for it", s.room_id == next and names == readied, "%s / %s" % [names, readied])
	step("the stash is used up", not rooms.call().has(next))
	await shot("entered_furnished")

	await _go(gs, HALL)
	var fx: EffectEngine = gs.effects
	var r := fx.validate(s, data, "t-board", {"kind": "furnish", "cause": "староста прибил доску у двери", "props": [{"name": "Доска объявлений", "text": "Заказы Брода"}]})
	if not step("a board is put up in the hall", bool(r["accepted"]), str(r)):
		return
	fx.apply(s, "t-board", [r["effect_id"]])
	var board := str(PropRules.room_props(s, HALL).filter(func(p: Dictionary) -> bool: return QuestGen.is_board(data, p))[0]["id"])
	gs._prepare()
	var key := "%s:%s" % [HALL, board]
	step("the board's orders are readied", await wait_until(func() -> bool: return PrepareRules.part(s, PrepareRules.BOARDS).has(key), 60.0))
	await wait_until(func() -> bool: return gs._ahead.is_empty(), 60.0)
	var err: String = gs.read_board(board)
	step("reading the board needs no master's turn", err.is_empty() and not gs.is_busy(), err)
	step("the order is on the board", QuestGen.offered_by(s, "board:" + key).size() == 1, _last_effects(s))
	await shot("board_read")

	step("Bruno's quest is readied", await wait_until(func() -> bool: return not PrepareRules.quest_of(s, BRUNO).is_empty(), 60.0),
		", ".join(PrepareRules.part(s, PrepareRules.QUESTS).keys()))
	await wait_until(func() -> bool: return gs._ahead.is_empty(), 60.0)
	node("EventBus").state_changed.emit()
	await frames(3)
	await open_row("More_" + BRUNO)
	var ask: Button = find(screen(), "AskWork_" + BRUNO)
	if step("«Есть дело?» at Bruno", ask != null and not ask.disabled):
		await press(ask)
		await frames(4)
		step("Bruno gives the quest without a master's turn", QuestGen.offered_by(s, BRUNO).size() == 1 and not gs.is_busy(), _last_effects(s))
		await open_row("More_" + BRUNO)
		step("asked once — the button is gone", find(screen(), "AskWork_" + BRUNO) == null)
		await shot("work_asked")


func _go(gs: Node, to: String) -> void:
	await wait_until(func() -> bool: return not gs.is_busy(), 30.0)
	step("walked to %s" % to, gs.go(to))
	await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
	await frames(3)


func _last_effects(s: GameSession) -> String:
	for i in range(s.chat.size() - 1, -1, -1):
		if str(s.chat[i].get("kind", "")) == GameSession.KIND_EFFECT:
			return " · ".join(s.chat[i]["lines"])
	return ""
