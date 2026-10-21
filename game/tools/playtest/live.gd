extends "res://tools/playtest/playtest_base.gd"
## Live playtest with the real model (python tools/godot_playtest.py --scenario live --real): enter the
## tavern, act, talk to the innkeeper through the side panel, order an ale, leave the conversation, trade with
## him (ask a price in words, buy through the deal panel, haggle in words), walk to the kitchen and search. Hard checks are on the engine side (modes, rooms, protocol); what the master writes is dumped
## into the report for a human (or agent) to judge.

const INNKEEPER := "npc_innkeeper"
const KITCHEN := "brod-tavern-kitchen"
const TURN_TIMEOUT := 200.0  # the server waits up to 180 s (v0.7.14.5)


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
	step("info: coins after ordering", true, "%d → %d cp, mode %s" % [gold_before, gs.session.character["gold_cp"], gs.session.mode])
	await shot("social_ale")

	if gs.session.in_conversation():
		await press(find(screen(), "LeaveButton"))
		step("left the conversation", gs.session.mode == GameSession.MODE_EXPLORATION)
		step("resume turn", await _turn_done(gs))
		await shot("resume")

	await _trade(gs)

	var exit: Button = find(screen(), "Exit_" + KITCHEN)
	if step("exit to the kitchen", exit != null):
		await press(exit)
		step("in the kitchen", gs.session.room_id == KITCHEN)
		step("kitchen enter turn", await _turn_done(gs))
		await shot("kitchen")
		await _say(gs, "Внимательно осматриваю люк в погреб и новый засов")
		var checks: Array = gs.session.chat.filter(func(e: Dictionary) -> bool: return e["kind"] == GameSession.KIND_CHECK)
		step("info: search check", true, str(checks[-1]) if not checks.is_empty() else "без проверки")
		step("info: found here", true, str(ExplorationRules.found_texts(gs.session, node("Catalog").data["world"], gs.session.room_id)))
		await shot("kitchen_search")

	await _say(gs, "Перевожу дух и пользуюсь Вторым дыханием")
	step("info: feature uses", true, str(gs.session.character.get("resources_used", {})))
	await shot("feature")

	step("no failed turns", not gs.session.chat.any(func(e: Dictionary) -> bool: return e["kind"] == GameSession.KIND_SYSTEM),
		_systems(gs))
	_dump(gs)


func _trade(gs: Node) -> void:
	var trade: Button = find(screen(), "Trade_" + INNKEEPER)
	if not step("trade button", trade != null and not trade.disabled):
		return
	await press(trade)
	step("trade greeting", await _turn_done(gs) and gs.session.mode == GameSession.MODE_TRADE)
	await shot("trade_greeting")
	var gold: int = gs.session.character["gold_cp"]
	await _say(gs, "Почём у тебя хлеб? Беру две краюхи")
	step("words alone do not buy", gs.session.character["gold_cp"] == gold, "%d → %d" % [gold, gs.session.character["gold_cp"]])
	await shot("trade_words")
	var panel: Control = find(screen(), "TradePanel")
	await press(find(panel, "Buy_bread"))
	await press(find(panel, "Buy_bread"))
	await press(find(panel, "DealButton"))
	step("deal narration", await _turn_done(gs) and gs.session.character["gold_cp"] < gold)
	await shot("trade_deal")
	await _say(gs, "Слушай, я ведь у тебя каждый вечер. Сбавь цену на пайки, а?")
	var m: Dictionary = gs.session.merchants[INNKEEPER]
	step("info: haggle in words", true, "pct %d, failed day %d, result %s" % [m["haggle_pct"], m["haggle_failed_day"], m["haggle_result"]])
	await shot("trade_haggle")
	await press(find(screen(), "LeaveButton"))
	step("left the merchant", gs.session.mode == GameSession.MODE_EXPLORATION and await _turn_done(gs))


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
