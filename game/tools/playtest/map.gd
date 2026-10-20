extends "res://tools/playtest/playtest_base.gd"
## Map 2.0 playtest (python tools/godot_playtest.py --scenario map), v0.7.6: the fighter walks the hall → the square
## → the gate, opens the map — a scheme of the three rooms and the «?» behind their exits; picks the hall and goes
## there by «Идти сюда»: no master turn, the line «Путь: …» in the chat, 20 minutes passed. Then the woodcutters'
## trail with its wolves stands between the edge and the glade: a fast travel stops there and the fight starts.


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
	for room: String in ["brod-square", "brod-gate"]:
		if not await _go(gs, room):
			return
	# The whole Mark at once (layout check): every room visited, then back to the three real ones.
	var real := s.visited.duplicate()
	for r: String in (node("Catalog").data["world"]["rooms"] as Dictionary):
		if not s.visited.has(r):
			s.visited.append(r)
	await tap("MapButton")
	await frames(3)
	await shot("map_whole_mark")
	s.visited = real
	node("EventBus").state_changed.emit()
	await frames(3)
	var canvas: Control = find(screen(), "MapCanvas")
	if not step("the map is a scheme", canvas != null):
		await shot("no_canvas")
		return
	var known: Dictionary = canvas.get("known")
	step("three rooms known, the rest behind exits as «?»", (known["rooms"] as Array).size() == 3 and (known["frontier"] as Array).size() >= 5,
		"%d rooms, %d «?»" % [(known["rooms"] as Array).size(), (known["frontier"] as Array).size()])
	await shot("map")
	canvas.emit_signal("picked", "brod-tavern-hall")
	await frames(3)
	var go: Button = find(screen(), "TravelButton")
	step("the travel button names the way", go != null and not go.disabled and go.text.contains("20 мин"), go.text if go != null else "")
	await shot("map_picked")
	var minute := s.minute
	var turns := s.turn_counter
	await press(go)
	await frames(5)
	step("arrived in the hall", s.room_id == "brod-tavern-hall", s.room_id)
	step("no master turn on the way", not gs.is_busy() and s.turn_counter == turns, "turns %d → %d" % [turns, s.turn_counter])
	step("20 minutes passed", s.minute - minute == 20, "%d → %d" % [minute, s.minute])
	step("the way is in the chat", _last_effect(s).begins_with("Путь: Ворота") or _last_effect(s).contains("→"), _last_effect(s))
	await shot("arrived")

	# The trail's wolves are alive: the edge → the glade stops on the trail and the fight starts.
	for r: String in ["pushcha-edge", "pushcha-trail", "pushcha-glade"]:
		s.visited.append(r)
	s.room_id = "pushcha-edge"
	var err: String = gs.travel("pushcha-glade")
	step("travel accepted", err.is_empty(), err)
	var fought := await wait_until(func() -> bool: return screen_is("CombatScreen") or s.mode == GameSession.MODE_COMBAT, 60.0)
	step("stopped on the trail: the fight", fought and s.room_id == "pushcha-trail", "%s, mode %s" % [s.room_id, s.mode])
	await shot("stopped_by_wolves")


func _go(gs: Node, room: String) -> bool:
	if gs.session.in_conversation():
		var leave: Button = find(screen(), "LeaveButton")
		if leave != null:
			await press(leave)
			await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
	var exit: Button = find(screen(), "Exit_" + room)
	if not step("walk to " + room, exit != null and not exit.disabled):
		await shot("no_exit_" + room)
		return false
	await press(exit)
	await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
	return true


func _last_effect(s: GameSession) -> String:
	for i in range(s.chat.size() - 1, -1, -1):
		if str(s.chat[i]["kind"]) == GameSession.KIND_EFFECT:
			return " · ".join(s.chat[i].get("lines", []))
	return ""
