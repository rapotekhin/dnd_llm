extends "res://tools/playtest/playtest_base.gd"
## Sites (python tools/godot_playtest.py --scenario sites), v0.7.22.24: location → site → room. The side panel says
## «Ольховый Брод › Таверна «Хромой олень» › общий зал»; the kitchen unasked — the cook sees a trespass, the innkeeper
## hears it; the map draws Brod as a frame with the tavern, the square and the rest as boxes, a site picked — the way
## to its entry.


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
	var data: Dictionary = node("Catalog").data
	s.room_id = "brod-tavern-hall"
	node("EventBus").state_changed.emit()
	await frames(3)
	var path: Label = find(screen(), "PlacePath")
	step("the place path names the site", path != null and path.text.contains("Таверна «Хромой олень» › общий зал"), path.text if path else "")
	var kitchen: Button = find(screen(), "Exit_brod-tavern-kitchen")
	if step("the way to the kitchen says it is private", kitchen != null and not kitchen.disabled and kitchen.text.contains("частная"), kitchen.text if kitchen else ""):
		await press(kitchen)
		await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
		await frames(3)
		step("the first time — a warning", _chat(s).contains("Предупреждение") and s.crimes.is_empty(), _chat(s))
		await shot("kitchen_warned")
		await press(find(screen(), "Exit_brod-tavern-hall"))
		await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
		await frames(3)
		await press(find(screen(), "Exit_brod-tavern-kitchen"))
		await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
		await frames(3)
		var crime := s.crimes.any(func(c: Dictionary) -> bool: return str(c.get("kind")) == "trespass")
		step("the second time — a trespass", _chat(s).contains("без спроса") and crime, _chat(s))
		await shot("kitchen")
	for r: String in ["brod-square", "brod-smithy", "brod-temple", "brod-gate", "pushcha-edge", "pushcha-trail", "outpost-road", "outpost-yard", "mine-entrance"]:
		if not s.visited.has(r):
			s.visited.append(r)
	s.room_id = "brod-tavern-hall"
	node("EventBus").state_changed.emit()
	await frames(3)
	await press(find(screen(), "MapButton"))
	await frames(5)
	var canvas: MapCanvas = find(screen(), "MapCanvas")
	step("the map draws locations and sites", canvas != null and canvas.loc_boxes.has("brod") and canvas.site_boxes.has("brod-tavern")
		and canvas.site_boxes.has("outpost-fort"), str(canvas.site_boxes.keys()) if canvas else "")
	await shot("map_sites")
	if canvas != null:
		canvas.selected = "site:brod-smithy"
		canvas.picked.emit("site:brod-smithy")
		await frames(4)
		var go: Button = find(screen(), "TravelButton")
		step("a picked site offers the way in", go != null and not go.disabled and go.text.contains("Идти"), go.text if go else "")
		await shot("map_site_picked")

	# Many ways out (the author, after v0.7.22.33): the exits scroll, the panel's buttons stay on screen.
	var map_view: Control = find(screen(), "MapView")
	if map_view != null:
		map_view.visible = false
	var room: Dictionary = data["world"]["rooms"]["brod-square"]
	var exits_before: Array = (room["exits"] as Array).duplicate()
	for r: String in data["world"]["rooms"]:
		if room["exits"].size() >= 16:
			break
		if r != "brod-square" and not room["exits"].has(r):
			room["exits"].append(r)
	s.room_id = "brod-square"
	node("EventBus").state_changed.emit()
	await frames(6)
	var ex: ScrollContainer = find(screen(), "ExitsScroll")
	var side: Control = find(screen(), "SideFooter").get_parent().get_parent() if find(screen(), "SideFooter") != null else null
	var sheet_b: Button = find(screen(), "SheetButton")
	step("16 exits scroll in a third of the panel", ex != null and side != null and ex.size.y <= side.size.y / 3.0 + 1.0 and ex.get_v_scroll_bar().visible,
		"%s of %s" % [ex.size if ex else Vector2.ZERO, side.size if side else Vector2.ZERO])
	step("the sheet button stays on screen", sheet_b != null and sheet_b.get_global_rect().end.y <= sheet_b.get_viewport_rect().size.y)
	await shot("many_exits")
	room["exits"] = exits_before


func _chat(s: GameSession) -> String:
	var out: Array[String] = []
	for e: Dictionary in s.chat.slice(maxi(0, s.chat.size() - 4)):
		out.append(" · ".join(e.get("lines", [])) if e.has("lines") else str(e.get("text", "")))
	return " | ".join(out).left(400)
