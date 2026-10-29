extends "res://tools/playtest/playtest_base.gd"
## Letters (python tools/godot_playtest.py --scenario letters), v0.7.48: «Письмо» at the clerk in the townhall —
## the window with the purpose, the person, the place and the way's price; a call for help to Bruno (a friend) to the
## north gate and a denunciation of Fern to the captain with Mira's word; the journal's «Письма» tab; two days
## later the master's `letter` turns answer both one after the other; Fern under guard; Bruno waits at the gate
## and joins the hero there.

const BRUNO := "npc_innkeeper"
const CLERK := "npc_clerk"


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
	s.minute = 11 * 60
	BondRules.add(s, data, BRUNO, 60, "")
	s.secrets_told.append("npc_serving:fern_casks")  # Mira told what she saw at the mill
	for r: String in ["brod-tavern-hall", "brod-gate"]:
		if not s.visited.has(r):
			s.visited.append(r)
	if s.room_id != "brod-square":
		await _go(gs, "brod-square")
	await _go(gs, "brod-townhall")

	await open_row("More_" + CLERK)
	var lb: Button = find(screen(), "Letter_" + CLERK)
	if not step("«Письмо» at the clerk", lb != null and not lb.disabled, lb.tooltip_text if lb != null else ""):
		return
	await press(lb)
	await frames(4)
	var view: Control = find(screen(), "LetterView")
	step("the letter window", view != null and view.visible)
	await _pick(view, "LetterPurpose", "help")
	await _pick(view, "LetterTo", BRUNO)
	await _pick(view, "LetterRoom", "brod-gate")
	var edit: TextEdit = find(view, "LetterText")
	edit.text = "Бруно, дружище, приходи к Серой заставе — одному мне там не сладить."
	edit.text_changed.emit()
	await frames(2)
	var way: OptionButton = find(view, "LetterWay")
	step("the way with its price and days", way != null and way.text.contains("почтой") and way.text.contains("дней"), way.text if way != null else "")
	await shot("letter_window")
	var send: Button = find(view, "LetterSend")
	step("send enabled", send != null and not send.disabled, send.tooltip_text if send != null else "")
	await press(send)
	await frames(3)
	step("the help letter on its way", LetterRules.letters(s).size() == 1 and str(LetterRules.letters(s)[0]["status"]) == "en_route", _last_effects(s))

	await open_row("More_" + CLERK)
	await press(find(screen(), "Letter_" + CLERK))
	await frames(3)
	view = find(screen(), "LetterView")
	await _pick(view, "LetterPurpose", "denounce")
	await _pick(view, "LetterAbout", "npc_merchant")
	var proof: Label = find(view, "LetterEvidence")
	step("the evidence shown", proof != null and proof.text.contains("Мира"), proof.text if proof != null else "")
	edit = find(view, "LetterText")
	edit.text = "Капитан, Ферн Кривой возит бочонки мимо пошлины — Мира видела лодку у мельницы."
	edit.text_changed.emit()
	await frames(2)
	await shot("letter_denounce")
	await press(find(view, "LetterSend"))
	await frames(3)
	step("the denunciation on its way", LetterRules.letters(s).size() == 2)

	var game := screen()
	await press(find(game, "JournalButton"))
	var tab: Button = find(game, "JournalTab_letters")
	if step("the letters tab", tab != null and tab.text.contains("Письма"), tab.text if tab != null else ""):
		await press(tab)
		await frames(3)
		var box: Node = find(game, "JournalTab_letters").get_parent().get_parent()
		var text := " ".join(box.find_children("*", "Label", true, false).map(func(l: Node) -> String: return (l as Label).text))
		step("what we wait for in the journal", text.contains("в пути") and text.contains("донос"), text.left(300))
		await shot("journal_letters")
	for n: Node in find_all(game, "WorldNotes"):
		(n as Control).visible = false
	await frames(2)

	gs.call("_quiet_lines", TimeRules.advance(s, data, 2 * 1440))
	gs.call("_after_turn", s, "")
	var answered := func() -> bool: return LetterRules.letters(s).all(func(l: Dictionary) -> bool: return str(l["status"]) == "answered")
	step("both letters answered by the master's turns", await wait_until(func() -> bool: return answered.call() and not gs.is_busy(), 60.0),
		", ".join(LetterRules.letters(s).map(func(l: Dictionary) -> String: return "%s:%s" % [l["id"], l["status"]])))
	var chat := " ".join(s.chat.map(func(e: Dictionary) -> String: return str(e.get("name", "")) + " " + str(e.get("text", "")) + " " + " ".join(e.get("lines", []))))
	step("Bruno's letter in the chat", chat.contains("Бруно Хмель — письмо") and chat.contains("придёт"), chat.right(400))
	step("Fern under guard", str(s.npc_at.get("npc_merchant", "")) == "brod-lockup" and LetterRules.jailed(s, "npc_merchant"))
	await shot("letter_answers")

	gs.call("_quiet_lines", TimeRules.advance(s, data, 1440))
	await _go(gs, "brod-square")
	await _go(gs, "brod-gate")
	step("Bruno came to the gate and goes with the hero", s.followers.has(BRUNO), _last_effects(s))
	await shot("ally_joined")


## Picks `id` in the window's OptionButton `node_name` (the window rebuilds after a pick).
func _pick(view: Node, node_name: String, id: String) -> void:
	var ob: OptionButton = find(view, node_name)
	if not step("pick %s in %s" % [id, node_name], ob != null):
		return
	var s: GameSession = node("GameState").session
	var name := id
	if node("Catalog").data["world"]["npcs"].has(id):
		name = str(node("Catalog").data["world"]["npcs"][id]["name"])
	elif node("Catalog").data["world"]["rooms"].has(id):
		name = str(node("Catalog").data["world"]["rooms"][id]["name"])
	elif LetterRules.purpose(node("Catalog").data, id).has("name"):
		name = str(LetterRules.purpose(node("Catalog").data, id)["name"])
	for i in ob.item_count:
		if ob.get_item_text(i).contains(name):
			ob.select(i)
			ob.item_selected.emit(i)
			await frames(3)
			return
	step("found %s in %s" % [name, node_name], false, str(s.day))


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
