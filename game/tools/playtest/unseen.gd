extends "res://tools/playtest/playtest_base.gd"
## Playtest-4 with the real master (python tools/godot_playtest.py --scenario unseen --real), v0.7.5: the hero under
## «Невидимость» sneaks to the gate past the captain (his passive Perception has disadvantage), looks around for
## valuables (no attitude change), then talks to him — invisibility stays, the master gives a voice from nowhere.

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
	await _walk(gs, "brod-square")
	s.character["concentration"] = "invisibility"  # as if cast: the engine reads invisibility from the held spell
	s.character["equipped"]["armor"] = ""  # no mail: the roll is about invisibility, not the armour's disadvantage
	CharacterRules.refresh(s.character, data, s.items)
	step("invisible", ConditionRules.invisible(s.character, data))
	var sneak: CheckButton = find(screen(), "SneakToggle")
	sneak.button_pressed = true
	await frames(2)
	await _walk(gs, "brod-gate")
	step("info: at the gate", true, _last_effect(s))
	step("not noticed by the captain", s.sneaking and s.sneak_noticed != "brod-gate", _last_effect(s))
	var att := s.attitude("npc_captain")
	await _say(gs, "Осматриваюсь у ворот: что тут плохо лежит?")
	step("no attitude change for looking", s.attitude("npc_captain") == att, "attitude %d → %d" % [att, s.attitude("npc_captain")])
	step("info: the master", true, _last_master(s))
	await press(find(screen(), "Talk_npc_captain"))
	await wait_until(func() -> bool: return not gs.is_busy(), 120.0)
	await _say(gs, "Капитан, не оборачивайтесь — я здесь, просто вы меня не видите.")
	step("still invisible in the conversation", ConditionRules.invisible(s.character, data))
	step("info: the captain", true, _last_master(s))
	await shot("voice_from_nowhere")


func _walk(gs: Node, room: String) -> void:
	var exit: Button = find(screen(), "Exit_" + room)
	if step("walk to " + room, exit != null and not exit.disabled):
		await press(exit)
		await wait_until(func() -> bool: return not gs.is_busy(), 120.0)


func _say(gs: Node, text: String) -> void:
	var game := screen()
	game.get("input").text = text
	game.get("send_button").pressed.emit()
	await wait_until(func() -> bool: return gs.is_busy(), 5.0)
	await wait_until(func() -> bool: return not gs.is_busy(), 120.0)


func _last_effect(s: GameSession) -> String:
	for i in range(s.chat.size() - 1, -1, -1):
		if str(s.chat[i]["kind"]) == GameSession.KIND_EFFECT:
			return " · ".join(s.chat[i].get("lines", []))
	return ""


func _last_master(s: GameSession) -> String:
	for i in range(s.chat.size() - 1, -1, -1):
		if str(s.chat[i]["kind"]) in [GameSession.KIND_DM, GameSession.KIND_NPC]:
			return str(s.chat[i]["text"]).left(400)
	return ""
