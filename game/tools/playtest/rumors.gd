extends "res://tools/playtest/playtest_base.gd"
## Rumours (python tools/godot_playtest.py --scenario rumors), v0.7.47: «Слухи» at Bruno — a gossip tells two, the
## button greys for the day; the journal's «Слухи» tab with the tips; the mill marked on the map; a rumour bought
## from Bruno; walked to the mill — the tip comes true and the coins are found; a murder in the Pushcha — Brod does
## not know until the rumour comes a day later, then the hero is wanted there.

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
	s.settings["weather"] = false
	s.minute = 12 * 60
	step("the pack's talk is in the world", not RumorRules.known_at(s, data, "brod").is_empty(),
		", ".join(RumorRules.known_at(s, data, "brod").map(func(r: Dictionary) -> String: return str(r["id"]))))
	if s.room_id != HALL:
		await _go(gs, HALL)

	await open_row("More_" + BRUNO)
	var ask: Button = find(screen(), "Rumors_" + BRUNO)
	if step("«Слухи» at Bruno", ask != null and not ask.disabled, ask.tooltip_text if ask != null else ""):
		await press(ask)
		await frames(4)
		var told := _last_effects(s)
		step("Bruno tells two rumours", told.count("Слух (Бруно") == 2, told)
		await open_row("More_" + BRUNO)
		ask = find(screen(), "Rumors_" + BRUNO)
		step("asked once a day — the button greys", ask != null and ask.disabled and ask.tooltip_text.contains("уже"), ask.tooltip_text if ask != null else "")
		await shot("rumors_asked")

	s.mode = GameSession.MODE_TRADE
	s.npc_id = BRUNO
	var gold := int(s.character["gold_cp"])
	var err: String = gs.buy_service("rumor")
	step("a rumour bought for a coin", err.is_empty() and int(s.character["gold_cp"]) == gold - 20 and _last_effects(s).contains("(Бруно"), err + " " + _last_effects(s))
	s.mode = GameSession.MODE_EXPLORATION
	s.npc_id = ""
	if not RumorRules.heard(s, "mill_coins"):
		RumorRules.hear(s, data, ["mill_coins"])
	node("EventBus").state_changed.emit()
	await frames(2)

	var game := screen()
	await press(find(game, "JournalButton"))
	var tab: Button = find(game, "JournalTab_rumors")
	if step("the rumours tab", tab != null and tab.text.contains("Слухи")):
		await press(tab)
		await frames(3)
		var box: Node = find(game, "JournalTab_rumors").get_parent().get_parent()
		var text := " ".join(box.find_children("*", "Label", true, false).map(func(l: Node) -> String: return (l as Label).text))
		step("the tip to the mill in the journal", text.contains("мельниц"), text.left(300))
		await shot("journal_rumors")
	await _close_notes(game)
	step("the mill marked on the map", RumorRules.marks(s, data).has("brod-mill") and (WorldMap.known(s, data["world"])["rooms"] as Array).has("brod-mill"))
	await press(find(game, "MapButton"))
	await frames(3)
	for n: Node in find_all(game, "WorldNotes"):
		if (n as Control).visible:
			n.call("open_at", "brod-mill")
	await frames(5)
	var mark: Label = find(game, "MapRumor")
	step("the rumour under the picked mill", mark != null and mark.text.contains("мельниц"), mark.text if mark != null else "")
	await shot("map_rumor")
	await _close_notes(game)

	await _go(gs, "brod-square")
	await _go(gs, "brod-gate")
	await _go(gs, "brod-mill")
	var fx := " ".join(s.chat.filter(func(e: Dictionary) -> bool: return e["kind"] == GameSession.KIND_EFFECT).slice(-3).map(
		func(e: Dictionary) -> String: return " · ".join(e.get("lines", []))))
	step("the tip came true at the mill", fx.contains("Слух подтвердился") and (s.revealed.get("brod-mill", []) as Array).has("sacks"), fx.right(300))
	await shot("tip_true")

	# a murder in the Pushcha: Brod knows nothing until the rumour comes
	var crime := {"id": "cr%d" % (s.crimes.size() + 1), "kind": "murder", "victim": "npc_hermit", "room": "pushcha-glade", "location": "pushcha",
		"at": TimeRules.abs_minute(s), "witnesses": [], "known": false, "settled": false}
	s.crimes.append(crime)
	CrimeRules._known(s, data, crime)
	step("not wanted in Brod before the rumour", not s.wanted.has("brod"))
	var lines := TimeRules.advance(s, data, 1440)
	gs.call("_quiet_lines", lines)
	step("the rumour came — wanted in Brod", s.wanted.has("brod") and " ".join(lines).contains("дошёл слух"), " ".join(lines).right(300))
	await frames(3)
	await shot("rumor_wanted")


func _close_notes(game: Node) -> void:
	for n: Node in find_all(game, "WorldNotes"):
		(n as Control).visible = false
	await frames(2)


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
