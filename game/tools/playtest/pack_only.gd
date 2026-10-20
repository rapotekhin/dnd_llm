extends "res://tools/playtest/playtest_base.gd"
## Playtest-3 findings with the real master (python tools/godot_playtest.py --scenario pack_only --real), v0.7.4:
## in Тёмная лощина with the burrow not found, «расширяю лаз и ползу внутрь» keeps the hero in the room — no new
## places, no summoned foes, the closed way stays closed; «раздеваюсь» takes the gear off in the engine (equip);
## an oath is kept as a note in Russian, not a made-up flag.

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
	s.encounters_done.append_array(["trail_wolves", "hollow_spiders"])  # the way down is not the test
	for room: String in ["brod-square", "brod-gate", "pushcha-edge", "pushcha-trail", "pushcha-hollow"]:
		var exit: Button = find(screen(), "Exit_" + room)
		if not step("walk to " + room, exit != null and not exit.disabled, "mode %s, busy %s" % [s.mode, gs.is_busy()]):
			await shot("no_exit_" + room)
			return
		await press(exit)
		await wait_until(func() -> bool: return not gs.is_busy(), 90.0)
		if s.in_conversation():
			await press(find(screen(), "LeaveButton"))
			await wait_until(func() -> bool: return not gs.is_busy(), 90.0)
	step("in the hollow, the burrow shut", s.room_id == "pushcha-hollow" and find(screen(), "Exit_pushcha-burrow") == null)

	await _say(gs, "Поддеваю корни мёртвого дуба ломиком, расширяю лаз и ползу внутрь, на запах дыма")
	step("still in the hollow, no fight", s.room_id == "pushcha-hollow" and not CombatRules.active(s) and s.pending_fight.is_empty(),
		"room %s, mode %s" % [s.room_id, s.mode])
	step("info: the master", true, _last_master(s))
	step("no made-up flags", s.flags.all(func(f: String) -> bool: return QuestRules.known_flags(node("Catalog").data["world"]).has(f)), str(s.flags))
	await shot("hollow_crawl")

	var armor := str(s.character["equipped"].get("armor", ""))
	var ac := int(s.character["ac"])
	await _say(gs, "Снимаю доспех и щит, остаюсь в одной рубахе")
	step("the armour is off in the engine", not armor.is_empty() and str(s.character["equipped"].get("armor", "")).is_empty() and int(s.character["ac"]) < ac,
		"armor %s → «%s», AC %d → %d" % [armor, s.character["equipped"].get("armor", ""), ac, s.character["ac"]])
	await shot("stripped")

	await _say(gs, "Клянусь у этого дуба: найду того, кто уводит лесорубов, и отомщу за них")
	step("info: notes", true, str(s.notes.map(func(n: Dictionary) -> String: return n["text"])))
	step("no made-up flags after the oath", s.flags.all(func(f: String) -> bool: return QuestRules.known_flags(node("Catalog").data["world"]).has(f)), str(s.flags))
	await shot("oath")


func _say(gs: Node, text: String) -> void:
	var game := screen()
	game.get("input").text = text
	game.get("send_button").pressed.emit()
	await wait_until(func() -> bool: return gs.is_busy(), 5.0)
	await wait_until(func() -> bool: return not gs.is_busy(), 120.0)


func _last_master(s: GameSession) -> String:
	for i in range(s.chat.size() - 1, -1, -1):
		if str(s.chat[i]["kind"]) in [GameSession.KIND_DM, GameSession.KIND_NPC]:
			return str(s.chat[i]["text"]).left(400)
	return ""
