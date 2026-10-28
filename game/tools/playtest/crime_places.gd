extends "res://tools/playtest/playtest_base.gd"
## Crime and private places (python tools/godot_playtest.py --scenario crime_places), v0.7.39.2: «Впустить» at Bruno
## and the kitchen without a warning; the Night Rats' den — the entry paid at the mill and walked in; a stranger
## warned in the den and the Rats' guards on the second time, no guard of the town.


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
	var s: GameSession = gs.session
	var c := s.character
	c.erase("orgs")
	c["gold_cp"] = 1000
	s.minute = 12 * 60
	s.room_id = "brod-tavern-hall"
	s.shift_attitude("npc_innkeeper", 1, node("Catalog").data)  # an easier ask
	node("EventBus").state_changed.emit()
	await frames(3)

	await open_row("More_npc_innkeeper")
	var pb: Button = find(screen(), "Permit_npc_innkeeper")
	if not step("«Впустить» among Bruno's acts", pb != null and not pb.disabled, pb.tooltip_text if pb != null else ""):
		await shot("no_permit")
		return
	await shot("permit_button")
	for i in 5:  # a refusal waits a day: try again on the next
		pb = find(screen(), "Permit_npc_innkeeper")
		if pb == null or SiteRules.permitted(s, node("Catalog").data, "brod-tavern"):
			break
		if pb.disabled:
			s.day += 1
			node("EventBus").state_changed.emit()
			await frames(2)
			await open_row("More_npc_innkeeper")
			pb = find(screen(), "Permit_npc_innkeeper")
		await press(pb)
		await frames(3)
	step("Bruno lets the hero in", SiteRules.permitted(s, node("Catalog").data, "brod-tavern"), _chat(s))
	await press(find(screen(), "Exit_brod-tavern-kitchen"))
	await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
	await frames(3)
	step("the kitchen without a warning", s.room_id == "brod-tavern-kitchen" and not _chat(s).contains("Предупреждение") and s.crimes.is_empty(), _chat(s))
	await shot("kitchen_allowed")

	s.room_id = "brod-mill"
	node("EventBus").state_changed.emit()
	await frames(3)
	var eb: Button = find(screen(), "OrgEntry_night_rats")
	if not step("«Вход в логово» at the mill", eb != null and not eb.disabled, eb.text if eb != null else ""):
		await shot("no_entry")
		return
	await shot("entry_button")
	await press(eb)
	await frames(3)
	step("the entry paid", int(c["gold_cp"]) == 950 and find(screen(), "OrgEntry_night_rats") == null, _chat(s))
	await press(find(screen(), "Exit_brod-den"))
	await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
	await frames(3)
	step("the den walked in, no warning", s.room_id == "brod-den" and not _chat(s).contains("Чужим тут не место"), _chat(s))
	await shot("den_paid")

	s.permits.clear()  # a stranger now
	s.room_id = "brod-mill"
	node("EventBus").state_changed.emit()
	await frames(3)
	await press(find(screen(), "Exit_brod-den"))
	await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
	await frames(3)
	step("a stranger warned, no crime", _chat(s).contains("Чужим тут не место") and s.crimes.is_empty(), _chat(s))
	await shot("den_warned")
	await press(find(screen(), "Exit_brod-mill"))
	await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
	await frames(3)
	await press(find(screen(), "Exit_brod-den"))
	var fought := await wait_until(func() -> bool: return screen_is("CombatScreen") or s.mode == GameSession.MODE_COMBAT, 60.0)
	step("the Rats' guards fall on the hero, the town's guard not", fought and s.crimes.is_empty() and s.wanted.is_empty(), _chat(s))
	await frames(6)
	await shot("den_fight")


func _chat(s: GameSession) -> String:
	var out: Array[String] = []
	for i in range(maxi(0, s.chat.size() - 4), s.chat.size()):
		if str(s.chat[i].get("kind", "")) == GameSession.KIND_EFFECT:
			out.append(" · ".join(s.chat[i]["lines"]))
	return " | ".join(out)
