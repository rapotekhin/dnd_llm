extends "res://tools/playtest/playtest_base.gd"
## Bonds (python tools/godot_playtest.py --scenario bonds), v0.7.31: «Связь» at Bruno, an ale given by taste, Mira's
## confession, Bruno a close friend — the step on the panel, a free bed, hiding the wanted hero; the captain's word.


func run() -> void:
	var gs := node("GameState")
	if not step("master connected", await wait_until(func() -> bool: return node("Backend").is_ready(), 30.0)):
		return
	await tap("NewGameButton")
	await tap("NextButton")
	await tap("Preset_fighter_aira")
	await press(find(screen(), "StartButton"))
	if not step("game started", await wait_until(func() -> bool: return screen_is("GameScreen") and not gs.is_busy(), 60.0)):
		return
	var data: Dictionary = node("Catalog").data
	var s: GameSession = gs.session
	var c := s.character
	c["gender"] = "female"
	c["skills"]["persuasion"] = 40
	c["inventory"]["ale"] = 2
	c["inventory"]["book"] = 1
	s.settings["needs"] = false
	s.room_id = "brod-tavern-hall"
	s.minute = 12 * 60
	node("EventBus").state_changed.emit()
	await frames(3)

	await open_row("More_npc_innkeeper")
	var bb: Button = find(screen(), "Bond_npc_innkeeper")
	if not step("«Связь» among Bruno's acts", bb != null and not bb.disabled):
		await shot("no_bond")
		return
	await press(bb)
	await frames(4)
	var win: Control = find(screen(), "BondView")
	await shot("bruno")
	await press(find(win, "Gift_ale"))
	await frames(4)
	step("the ale given by taste", BondRules.points(c, "npc_innkeeper") == 10 and (BondRules.known(c, "npc_innkeeper")["likes"] as Array).has("drink"), _last_effects(s))
	await shot("gift")
	win.visible = false

	c["bonds"]["npc_serving"] = {"kind": "friend", "points": 45}
	node("EventBus").state_changed.emit()
	await open_row("More_npc_serving")
	await press(find(screen(), "Bond_npc_serving"))
	await frames(4)
	await shot("mira")
	for i in 4:
		if BondRules.kind(c, "npc_serving") == "romance":
			break
		c["bonds"]["npc_serving"]["confess_day"] = -999
		c["bonds"]["npc_serving"]["points"] = 45
		node("EventBus").state_changed.emit()
		await frames(2)
		await press(find(win, "Confess_npc_serving"))
		await frames(4)
	step("Mira says yes", BondRules.kind(c, "npc_serving") == "romance", _last_effects(s))
	await shot("romance")
	win.visible = false

	c["bonds"]["npc_innkeeper"]["points"] = 65
	s.wanted["brod"] = TimeRules.abs_minute(s) - 10000
	s.let_go["brod"] = TimeRules.abs_minute(s) + 60
	node("EventBus").state_changed.emit()
	await frames(3)
	await open_row("More_npc_innkeeper")
	var role: Label = find(screen(), "Role_npc_innkeeper")
	step("the step on the panel", role != null and role.text.contains("друг"), role.text if role != null else "")
	step("a friend's bed", int(ExplorationRules.rest_place(data["world"], s.room_id, s, data).get("cost_cp", -1)) == 0)
	await press(find(screen(), "Bond_npc_innkeeper"))
	await frames(4)
	var hide: Button = find(win, "Hide_npc_innkeeper")
	if step("«Укрыться» for the wanted", hide != null and not hide.disabled):
		await press(hide)
		await frames(4)
		step("hidden from the patrol", int(s.let_go.get("brod", 0)) > TimeRules.abs_minute(s) + 600, _last_effects(s))
	await shot("hidden")
	win.visible = false
	s.wanted.erase("brod")
	s.let_go.erase("brod")

	c["bonds"]["npc_captain"] = {"kind": "friend", "points": 60}
	s.crimes.append({"id": "cr1", "kind": "assault", "victim": "npc_merchant", "room": "brod-square", "location": "brod",
		"at": 0, "witnesses": [], "known": true, "settled": false})
	step("the captain speaks for the hero", BondRules.intercessor(s, data, "brod") == "npc_captain")
	s.crimes.clear()
	node("EventBus").state_changed.emit()
	await frames(2)


func _last_effects(s: GameSession) -> String:
	for i in range(s.chat.size() - 1, -1, -1):
		if str(s.chat[i].get("kind", "")) == GameSession.KIND_EFFECT:
			return " · ".join(s.chat[i]["lines"])
	return ""
