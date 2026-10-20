extends "res://tools/playtest/playtest_base.gd"
## Pinned spells with the real master (python tools/godot_playtest.py --scenario attach --real), v0.7.7: the bard
## Yas pins «Очарование личности» on Bruno and asks for ale on credit, then «Малая иллюзия» to distract the serving
## girl. Each cast goes in one turn with the words; the slot is spent once (the master does not cast it again);
## the master's narration is kept for reading.


func run() -> void:
	var gs := node("GameState")
	if not step("master connected", await wait_until(func() -> bool: return node("Backend").is_ready(), 30.0)):
		return
	await tap("NewGameButton")
	await tap("NextButton")
	await tap("Preset_bard_yas")
	await press(find(screen(), "StartButton"))
	if not step("game started", await wait_until(func() -> bool: return screen_is("GameScreen") and not gs.is_busy(), 90.0)):
		return
	var s: GameSession = gs.session
	await _pinned(gs, s, "spell", "charm_person", "npc_innkeeper", "Улыбаюсь Бруно и прошу налить мне кружку в долг — до завтра верну", true)
	await shot("charm")
	await _pinned(gs, s, "spell", "minor_illusion", "npc_serving", "Создаю в дальнем углу иллюзию крысы, чтобы Мира отвлеклась", false)
	await shot("illusion")


func _pinned(gs: Node, s: GameSession, kind: String, id: String, target: String, words: String, slot_spell: bool) -> void:
	var game := screen()
	var used_before := int((s.character["slots_used"] as Array)[0])
	gs.attach(kind, id, 1 if slot_spell else 0, target)
	await frames(2)
	step("pinned: " + id, find(game, "AttachName") != null)
	var turns := s.turn_counter
	game.get("input").text = words
	game.get("send_button").pressed.emit()
	await wait_until(func() -> bool: return gs.is_busy(), 5.0)
	await wait_until(func() -> bool: return not gs.is_busy(), 150.0)
	var at := -1
	for i in s.chat.size():
		if str(s.chat[i]["kind"]) == GameSession.KIND_PLAYER and str(s.chat[i].get("text", "")) == words:
			at = i
	var before: Dictionary = s.chat[at - 1] if at > 0 else {}
	step("the cast right before the words", str(before.get("kind", "")) == GameSession.KIND_EFFECT, " · ".join(before.get("lines", [])))
	var again := 0
	for i in range(at + 1, s.chat.size()):
		if str(s.chat[i]["kind"]) == GameSession.KIND_EFFECT and " ".join(s.chat[i].get("lines", [])).contains("Заклинание:"):
			again += 1
	step("no cast of its own after the words", again == 0, "turns %d → %d (a talk the words began may add one)" % [turns, s.turn_counter])
	var used := int((s.character["slots_used"] as Array)[0])
	step("slot spent exactly once" if slot_spell else "a cantrip spends no slot", used - used_before == (1 if slot_spell else 0), "slots used %d → %d" % [used_before, used])
	step("info: the master", true, _after(s, at))


func _after(s: GameSession, at: int) -> String:
	var out: Array[String] = []
	for i in range(at + 1, s.chat.size()):
		var e: Dictionary = s.chat[i]
		if str(e["kind"]) in [GameSession.KIND_DM, GameSession.KIND_NPC]:
			out.append(str(e["text"]))
		elif str(e["kind"]) == GameSession.KIND_EFFECT:
			out.append("[" + " · ".join(e.get("lines", [])) + "]")
	return "\n".join(out)
