extends "res://tools/playtest/playtest_base.gd"
## Live playtest with the real model (python tools/godot_playtest.py --scenario live --real): enter the
## tavern, act, talk to the innkeeper through the side panel, order an ale, leave the conversation, walk to
## the kitchen. Hard checks are on the engine side (modes, rooms, protocol); what the master writes is dumped
## into the report for a human (or agent) to judge.

const INNKEEPER := "a1f3c7c2-6b1e-4e92-9e2a-111111111111"
const KITCHEN := "tavern-room-002"
const TURN_TIMEOUT := 120.0


func run() -> void:
	var backend := node("Backend")
	var gs := node("GameState")
	if not step("master connected", await wait_until(func() -> bool: return backend.is_ready(), 60.0), backend.config.describe()):
		return
	step("server model", true, str(backend.client.server_info.get("model", "?")))
	if not step("random character created", await quick_character()):
		return
	var c: Dictionary = gs.session.character
	step("info: character", true, "%s — %s %s, HP %d, КД %d" % [c["name"], c["race_name"], c["class_name"], c["max_hp"], c["ac"]])
	if not step("enter turn", await _turn_done(gs)):
		return
	await shot("enter")

	await _say(gs, "Осматриваю зал и прислушиваюсь к разговорам за столами")
	step("action turn", not gs.can_retry())
	step("info: checks so far", true, str(_count(gs, GameSession.KIND_CHECK)))
	await shot("action")

	var talk: Button = find(screen(), "Talk_" + INNKEEPER)
	if not step("talk button for the innkeeper", talk != null and not talk.disabled):
		return
	await press(talk)
	step("social mode with the innkeeper", gs.session.mode == GameSession.MODE_SOCIAL and gs.session.npc_id == INNKEEPER)
	step("greeting turn", await _turn_done(gs) and _count(gs, GameSession.KIND_NPC) >= 1)
	await shot("social_greeting")

	var gold_before: int = gs.session.character["gold_cp"]
	await _say(gs, "Налей мне кружку эля. Сколько с меня?")
	step("info: coins after ordering", true, "%d → %d cp" % [gold_before, gs.session.character["gold_cp"]])
	await shot("social_ale")

	if gs.session.in_conversation():
		await press(find(screen(), "LeaveButton"))
		step("left the conversation", gs.session.mode == GameSession.MODE_EXPLORATION)
		step("resume turn", await _turn_done(gs))
		await shot("resume")

	var exit: Button = find(screen(), "Exit_" + KITCHEN)
	if step("exit to the kitchen", exit != null):
		await press(exit)
		step("in the kitchen", gs.session.room_id == KITCHEN)
		step("kitchen enter turn", await _turn_done(gs))
		await shot("kitchen")

	step("no failed turns", not gs.session.chat.any(func(e: Dictionary) -> bool: return e["kind"] == GameSession.KIND_SYSTEM),
		_systems(gs))
	_dump(gs)


func _turn_done(gs: Node) -> bool:
	await frames(2)
	return await wait_until(func() -> bool: return not gs.is_busy(), TURN_TIMEOUT) and not gs.can_retry()


func _say(gs: Node, text: String) -> void:
	var game := screen()
	game.get("input").text = text
	game.get("send_button").pressed.emit()
	await _turn_done(gs)


func _count(gs: Node, kind: String) -> int:
	return gs.session.chat.filter(func(e: Dictionary) -> bool: return e["kind"] == kind).size()


func _systems(gs: Node) -> String:
	return ", ".join(gs.session.chat.filter(func(e: Dictionary) -> bool: return e["kind"] == GameSession.KIND_SYSTEM)
		.map(func(e: Dictionary) -> String: return str(e["key"])))


func _dump(gs: Node) -> void:
	_report.append("----- chat -----")
	for e: Dictionary in gs.session.chat:
		match str(e["kind"]):
			GameSession.KIND_DM:
				_report.append("МАСТЕР: " + str(e["text"]))
			GameSession.KIND_NPC:
				_report.append("%s: %s" % [e["name"], e["text"]])
			GameSession.KIND_PLAYER:
				_report.append("ИГРОК: " + str(e["text"]))
			GameSession.KIND_CHECK:
				_report.append("ПРОВЕРКА: %s%s %d+%d=%d vs %d %s" % [e.get("skill", ""), e.get("save", ""), e["nat"], e["bonus"], e["total"], e["dc"], "✓" if e["success"] else "✗"])
			GameSession.KIND_EFFECT:
				_report.append("ЭФФЕКТЫ: " + " · ".join(e["lines"]))
			GameSession.KIND_SYSTEM:
				_report.append("СИСТЕМА: " + str(e["key"]))
	_report.append("options: %s" % [gs.session.options])
	_report.append("summaries: %s" % [gs.session.summaries])
