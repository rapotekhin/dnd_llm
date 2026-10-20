extends "res://tools/playtest/playtest_base.gd"
## «Правила 5e: состояния» playtest (python tools/godot_playtest.py --scenario conditions [--real]), v0.7.8, with the
## dwarf cleric Бранко: a poisoned drink as a chip over the input that runs out in an hour of waiting; the dwarf's
## poison resistance on the sheet; a long march past eight hours calls for CON saves; a camp eats food from the pack
## and takes all exhaustion away; in a fight — prone (Встать takes the move), frightened (no step towards the wolf),
## grappled (Вырваться). With --real the master lays a condition with a save and a duration when the hero drinks a
## vial of poison from the pack. Also «Забрать всё»: the things nobody owns go to the pack in one turn.


func run() -> void:
	var gs := node("GameState")
	var data: Dictionary = node("Catalog").data
	if not step("master connected", await wait_until(func() -> bool: return node("Backend").is_ready(), 30.0)):
		return
	await tap("NewGameButton")
	await tap("NextButton")
	await tap("Preset_cleric_branko")
	await press(find(screen(), "StartButton"))
	if not step("game started", await wait_until(func() -> bool: return screen_is("GameScreen") and not gs.is_busy(), 60.0)):
		return
	var s: GameSession = gs.session
	var c := s.character
	var game := screen()

	# A poisoned drink: a chip over the input with the time left; an hour of waiting ends it.
	ConditionRules.add_effect(c, {"condition": "poisoned", "ends": ConditionRules.ends_for(s, data, "hour"),
		"source": {"kind": "master", "name": "яд в кружке"}})
	node("EventBus").state_changed.emit()
	await frames(3)
	var chips: Control = find(game, "EffectChips")
	step("the poison chip over the input", chips != null and chips.visible and _text_of(chips).contains("Отравлен · 1 ч 0 мин"), _text_of(chips) if chips != null else "")
	var chip: Control = find(chips, "Chip_poisoned") if chips != null else null
	step("its tooltip names the cause", chip != null and chip.tooltip_text.contains("яд в кружке"), chip.tooltip_text if chip != null else "")
	await shot("poison_chip")
	step("wait an hour", str(gs.wait("hour")).is_empty())
	await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
	step("the poison is gone after an hour", not ConditionRules.has(c, "poisoned"), ", ".join(c["conditions"]))
	step("the chat says it passed", _effects_text(s).contains("прошло: отравлен"))

	# «Забрать всё»: the things nobody owns go to the pack in one turn.
	s.props[s.room_id] = [{"id": "pt1", "name": "Сальная свеча", "item_id": "candle", "owner": "", "state": ""},
		{"id": "pt2", "name": "Моток верёвки", "item_id": "rope", "owner": "", "state": ""},
		{"id": "pt3", "name": "Кружка Горма", "item_id": "ale", "owner": "npc_innkeeper", "state": ""}]
	node("EventBus").state_changed.emit()
	await frames(3)
	var take: Button = find(game, "TakeAllButton")
	step("the take-all button names what it takes", take != null and not take.disabled and take.tooltip_text.contains("верёвки")
		and not take.tooltip_text.contains("Кружка"), take.tooltip_text if take != null else "")
	var scroll := take.get_parent()
	while scroll != null and not (scroll is ScrollContainer):
		scroll = scroll.get_parent()
	if scroll != null:
		(scroll as ScrollContainer).ensure_control_visible(take)
		await frames(3)
	await shot("take_all_button")
	if take != null and not take.disabled:
		await press(take)
		await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
	step("the rope and the candle in the pack, the mug stays", int(c["inventory"].get("rope", 0)) >= 1
		and PropRules.room_props(s, s.room_id).size() == 1, _effects_text(s).right(120))

	# The dwarf on the sheet.
	await press(find(game, "SheetButton"))
	var sheet: Control = find(game, "CharacterSheet")
	await frames(3)
	step("the sheet shows the dwarf's poison resistance", _text_of(sheet).contains("Сопротивление урону: яд"), "")
	await shot("sheet_resist")
	await press(find(sheet, "CloseSheetButton"))

	# A long march: the ninth hour on the way calls for a CON save.
	for room: String in ["brod-square", "brod-gate"]:
		var exit: Button = find(game, "Exit_" + room)
		if step("walk to " + room, exit != null and not exit.disabled):
			await press(exit)
			await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
	s.march_day = s.day
	s.march_minutes = 8 * 60  # the whole day already on the way: the next hour is the ninth
	var far: Button = null
	for b: Node in game.find_children("Exit_*", "Button", true, false):
		var to := str(b.name).trim_prefix("Exit_")
		if WorldView.new(data["world"]).location_id(to) != WorldView.new(data["world"]).location_id(s.room_id):
			far = b
			break
	if step("a way into another location", far != null):
		await press(far)
		await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
	step("the march calls for a save", _effects_text(s).contains("Марш 9 ч"), _effects_text(s).right(200))
	step("info: exhaustion after the march", true, "%d, room %s, march %d min on day %d (day %d), mode %s" % [ConditionRules.exhaustion(c), s.room_id, s.march_minutes, s.march_day, s.day, s.mode])

	# A camp: food from the pack, exhaustion gone.
	if ConditionRules.exhaustion(c) == 0:
		ConditionRules.add_exhaustion(s, data, 2, "проверка")
	c["inventory"]["rations"] = 3
	c["inventory"]["bread"] = 1
	node("EventBus").state_changed.emit()
	await frames(2)
	step("the exhaustion chip", _text_of(find(game, "EffectChips")).contains("Истощение"), _text_of(find(game, "EffectChips")))
	var rest: Button = find(game, "RestButton")
	if step("the long rest button", rest != null and not rest.disabled, rest.tooltip_text if rest != null else ""):
		await press(rest)
		await frames(3)
		var dialog: Control = find(game, "LongRestView")
		step("the dialog offers a camp with food", dialog != null and dialog.visible and _text_of(dialog).contains("Припасы: 3 из 2"), _text_of(dialog).left(300) if dialog != null else "")
		await shot("camp_dialog")
		var day := s.day
		await press(find(dialog, "DialogConfirm"))
		await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
		step("a new day in the camp", s.day == day + 1, "%d → %d" % [day, s.day])
		step("the food is eaten", int(c["inventory"].get("bread", 0)) == 0 and int(c["inventory"].get("rations", 0)) == 2,
			"bread %d, rations %d" % [int(c["inventory"].get("bread", 0)), int(c["inventory"].get("rations", 0))])
		step("exhaustion is gone", ConditionRules.exhaustion(c) == 0)

	# The fight: prone, frightened, grappled.
	gs.start_combat([{"monster": "wolf", "col": 2}])
	if not step("a fight", await wait_until(func() -> bool: return screen_is("CombatScreen") and not gs.is_busy(), 60.0)):
		return
	await wait_until(func() -> bool: return CombatRules.player_can_act(s) or not str(s.combat.get("outcome", "")).is_empty(), 60.0)
	if not CombatRules.player_can_act(s):
		step("info: the fight ended before the hero's turn", true, str(s.combat.get("outcome", "")))
		return
	var wolf := CombatRules.enemies(s)[0]
	ConditionRules.add_effect(c, {"condition": "prone", "ends": {}, "source": {"kind": "master", "name": "сбит с ног"}})
	ConditionRules.add_effect(c, {"condition": "frightened", "ends": {"at": ConditionRules.now(s) + 10}, "by": wolf,
		"source": {"kind": "master", "name": "вой"}})
	node("EventBus").state_changed.emit()
	await frames(4)
	var cs := screen()
	var right: Button = find(cs, "MoveRight" if int(CombatRules.fighter(s, wolf)["col"]) > 0 else "MoveLeft")
	step("prone: no step until standing", right != null and right.disabled and right.tooltip_text.contains("встаньте"), right.tooltip_text if right != null else "")
	step("the hero card shows the chips", _text_of(cs).contains("Лежит ничком") and _text_of(cs).contains("Испуган"), "")
	await shot("prone_frightened")
	var stand: Button = find(cs, "Do_stand")
	if step("the stand button", stand != null and not stand.disabled):
		await press(stand)
		await frames(3)
	step("standing up took the move", not ConditionRules.has(c, "prone") and int(CombatRules.economy(s).get("move", 0)) == 0)
	ConditionRules.remove(c, "frightened")
	ConditionRules.add_effect(c, {"condition": "grappled", "ends": {}, "by": wolf, "source": {"kind": "monster", "name": "волчья хватка"}})
	CharacterRules.refresh(c, data, s.items)
	node("EventBus").state_changed.emit()
	await frames(4)
	cs = screen()
	var escape: Button = find(cs, "Do_escape")
	step("grappled: the escape button", escape != null and not escape.disabled)
	await shot("grappled")
	if escape != null and not escape.disabled:
		await press(escape)
		await frames(3)
		step("info: the escape", true, " · ".join(s.combat.get("log", []).slice(-1)))

	if OS.get_environment("BTR_PLAYTEST_REAL") != "1":
		return
	# The real master: a suspicious vial — a condition with a save or the hero's own cause, a duration.
	gs.finish_combat([])
	await wait_until(func() -> bool: return screen_is("GameScreen") and not gs.is_busy(), 120.0)
	c["inventory"]["poison_basic_vial"] = 1  # a real thing in the pack: the master invents no vials
	var before := s.chat.size()
	game = screen()
	game.get("input").text = "Достаю из рюкзака флакон базового яда и выпиваю его — хочу знать, каково это"
	game.get("send_button").pressed.emit()
	await wait_until(func() -> bool: return gs.is_busy(), 5.0)
	await wait_until(func() -> bool: return not gs.is_busy(), 120.0)
	var lines := ""
	for i in range(before, s.chat.size()):
		if str(s.chat[i]["kind"]) == GameSession.KIND_EFFECT:
			lines += " · ".join(s.chat[i].get("lines", [])) + "\n"
	step("the master's condition went through the engine", lines.contains("Отравлен") or lines.contains("устоял") or lines.contains("не действует"), lines)
	step("info: the master's words", true, _last_dm(s).left(300))
	await shot("real_vial")


func _text_of(n: Node) -> String:
	if n == null:
		return ""
	var out := ""
	for l: Node in n.find_children("*", "Label", true, false):
		out += (l as Label).text + "\n"
	return out


func _effects_text(s: GameSession) -> String:
	var out := ""
	for e: Dictionary in s.chat:
		if str(e["kind"]) == GameSession.KIND_EFFECT:
			out += " · ".join(e.get("lines", [])) + "\n"
	return out


func _last_dm(s: GameSession) -> String:
	for i in range(s.chat.size() - 1, -1, -1):
		if str(s.chat[i]["kind"]) in [GameSession.KIND_DM, GameSession.KIND_NPC]:
			return str(s.chat[i].get("text", ""))
	return ""
