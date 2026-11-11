extends "res://tools/playtest/playtest_base.gd"
## The one screen (python tools/godot_playtest.py --scenario walk), v0.8.1: a click on the map walks the hero without a
## turn of the master; a door is crossed on the way; a way out takes the hero out; the wheel and a drag move the view;
## a conversation dims the map; fast travel puts the hero on a free square.

var field: Control


func run() -> void:
	var gs := node("GameState")
	gs.instant_walk = false
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
	var lib: Dictionary = data["layouts"]
	still_sky(s)
	s.room_id = "brod-tavern-hall"
	node("EventBus").state_changed.emit()
	await frames(3)
	field = find(screen(), "Field")
	if not step("the room's map is on the field", field != null and not field.map.is_empty() and WalkRules.room_of(field.map, field.hero_cell()) == s.room_id):
		return
	step("nothing sticks out", overflows().is_empty(), str(overflows()))
	await shot("hall")

	var chat_size := s.chat.size()
	var clock := TimeRules.clock(s)
	var far := _far(s.room_id, lib)
	await _click(far)
	step("the hero sets off", field.walking())
	await shot("walking")
	await wait_until(func() -> bool: return not field.walking(), 20.0)
	step("a click walks the hero there", field.hero_cell() == far, "%s of %s" % [field.hero_cell(), far])
	step("no turn and no time", s.chat.size() == chat_size and TimeRules.clock(s) == clock and not gs.is_busy())
	var kept := LayoutGen.on_grid(field.map, far)
	step("the spot is kept", int(s.layouts["at"]["x"]) == kept.x and int(s.layouts["at"]["y"]) == kept.y)
	await _click(Vector2i(0, 0))
	step("a wall is no way", not field.walking())

	var kitchen := _far("brod-tavern-kitchen", lib)
	WayRules.unlock(s, node("Catalog").data, "brod-tavern-hall", "brod-tavern-kitchen")  # as if its lock was picked
	await _click(kitchen)
	await wait_until(func() -> bool: return s.room_id == "brod-tavern-kitchen" and not field.walking() and not gs.is_busy(), 60.0)
	await frames(3)
	step("through the door into the next room", s.room_id == "brod-tavern-kitchen", s.room_id)
	step("on to the square that was clicked", field.hero_cell() == kitchen, "%s of %s" % [field.hero_cell(), kitchen])
	step("the door's rules hold: a warning", _chat(s).contains("Предупреждение"), _chat(s))
	await shot("kitchen")

	s.room_id = "brod-tavern-hall"
	node("EventBus").state_changed.emit()
	await frames(3)
	var way := _way("brod-square")
	if step("the way out is on the map", way != Vector2i(-1, -1)):
		await _click(way)
		await wait_until(func() -> bool: return s.room_id == "brod-square" and not gs.is_busy(), 60.0)
		await frames(5)
		step("a click on the way out leads out", s.room_id == "brod-square", s.room_id)
		step("on the street's own map", WalkRules.room_of(field.map, field.hero_cell()) == s.room_id)
		await shot("square")

	var tile: float = field.tile()
	var middle: Vector2 = field.size / 2.0
	_wheel(middle, MOUSE_BUTTON_WHEEL_UP)
	step("the wheel zooms", field.tile() > tile, "%s → %s" % [tile, field.tile()])
	var corner: Vector2 = field.corner()
	_button(middle, true)
	var motion := InputEventMouseMotion.new()
	motion.position = middle + Vector2(40, 24)
	motion.relative = Vector2(40, 24)
	field._gui_input(motion)
	_button(motion.position, false)
	await frames(1)
	step("a drag moves the view", field.corner() != corner, "%s → %s" % [corner, field.corner()])
	step("a drag is no click", not field.walking())
	await shot("zoomed")

	s.room_id = "brod-tavern-hall"
	node("EventBus").state_changed.emit()
	await frames(3)
	var person := {}
	for th: Dictionary in field.things:
		if str(th["kind"]) == "npc" and person.is_empty():
			person = th
	step("people stand on the map, not in the column", not person.is_empty() and screen().find_children("More_*", "Button", true, false).is_empty())
	if step("someone to talk to", not person.is_empty()):
		var at := Vector2i(int(person["x"]), int(person["y"]))
		await _click(at)  # v0.8.4.43.4, as in BG3: the left button talks
		await wait_until(func() -> bool: return s.in_conversation() and not gs.is_busy(), 60.0)
		await frames(3)
		step("a click on a person talks to it", s.in_conversation() and s.npc_id == str(person["id"]), s.npc_id)
		var reach := int(node("Catalog").data["rules"]["map"]["reach"]["talk"])
		step("the hero stopped in speaking reach", WalkRules.distance(field.hero_cell(), at) <= reach, str(WalkRules.distance(field.hero_cell(), at)))
		step("the map dims under the partner", (find(screen(), "Dim") as Control).is_visible_in_tree() and (find(screen(), "PartnerCard") as Control).is_visible_in_tree())
		step("the bar gives way to the talk", (find(screen(), "TalkActs") as Control).is_visible_in_tree() and not (find(screen(), "Hotbar") as Control).is_visible_in_tree())
		var cell: Vector2i = field.hero_cell()
		await _click(_far(s.room_id, lib))
		step("the map takes no clicks in a talk", not field.walking() and field.hero_cell() == cell)
		step("nothing sticks out in a talk", overflows().is_empty(), str(overflows()))
		await shot("talk")
		await press(find(screen(), "LeaveButton"))
		await frames(3)
		step("the map is back", not (find(screen(), "Dim") as Control).is_visible_in_tree() and field.clicks)

	await _people(s, gs, lib)

	var why: String = gs.travel("brod-square")  # a known place: the way goes only through those
	step("fast travel starts", why.is_empty(), why)
	await wait_until(func() -> bool: return s.room_id == "brod-square" and not gs.is_busy(), 20.0)
	step("fast travel arrives", s.room_id == "brod-square", s.room_id)
	await frames(5)
	step("fast travel puts the hero on a free square", WalkRules.room_of(field.map, field.hero_cell()) == s.room_id and WalkRules.passable(field.map, lib, field.hero_cell()))
	await shot("travelled")
	await _exits_list()
	await _folded(s, gs)


## v0.8.4.43.9, the author's finding: «Выходы ▾» shows up to five ways out whole (it showed two and a half), more scroll.
func _exits_list() -> void:
	var ways: Button = find(screen(), "ExitsButton")
	if not step("«Выходы ▾» over the map", ways != null):
		return
	await press(ways)
	await frames(3)
	var list: Control = find(screen(), "ExitsList")
	var scroll: Control = find(screen(), "ExitsScroll")
	var rows: Array = list.get_children() if list != null else []
	var shown := 0
	for r: Control in rows:
		if r.position.y + r.size.y <= scroll.size.y + 1.0:
			shown += 1
	step("up to five ways out seen whole", rows.size() > 0 and shown == mini(rows.size(), 5), "%d of %d seen" % [shown, rows.size()])
	await shot("exits_list")
	(find(screen(), "ExitsPopup") as Window).hide()
	await frames(2)


## v0.8.4.43.5.1: the engine's lines are quiet, one look; the same one said three times is one line «×3».
func _folded(s: GameSession, gs: Node) -> void:
	var chat: Node = screen().get("chat")
	var size := s.chat.size()
	for i in 3:
		gs._effect_lines(["Взято: оловянная кружка"] as Array[String])  # the engine's road of a deed into the chat
	await frames(3)
	step("the same engine line folds", s.chat.size() == size + 1 and GameSession.times(s.chat[-1]) == 3, "%d → %d" % [size, s.chat.size()])
	var lines: Array = chat.find_children("*", "RichTextLabel", true, false)
	var last: RichTextLabel = lines.back() if not lines.is_empty() else null
	step("one line «×3» in the chat", last != null and last.get_parsed_text().ends_with("×3"), last.get_parsed_text() if last else "")
	var quiet := lines.filter(func(l: RichTextLabel) -> bool: return GameSession.is_engine(l.get_meta("entry", {})))
	step("the engine's lines share one quiet look", not quiet.is_empty() and quiet.all(func(l: RichTextLabel) -> bool: return l.theme_type_variation == quiet[0].theme_type_variation),
		str(quiet.size()))
	await shot("chat_folded")


## v0.8.4.43.4: the right button on a person opens its one menu where the hero stands — a list with lists inside; a trade
## picked there walks right up (v0.8.2).
func _people(s: GameSession, gs: Node, lib: Dictionary) -> void:
	var trader := {}
	for th: Dictionary in field.things:
		if str(th["kind"]) == "npc" and gs.world().is_trader(str(th["id"])):
			trader = th
	if not step("the trader stands on the map", not trader.is_empty(), str(field.things.size())):
		return
	var at := Vector2i(int(trader["x"]), int(trader["y"]))
	await _click(_far_from(at, s.room_id, lib))
	await wait_until(func() -> bool: return not field.walking(), 20.0)
	field.labels = true
	field.queue_redraw()
	await frames(1)
	await shot("people")
	field.labels = false
	var stood: Vector2i = field.hero_cell()
	field.cell_right.emit(at)
	await frames(3)
	var menu := acts_menu() as ActsMenu
	step("the right button on a person opens its menu", menu != null)
	if menu == null:
		return
	step("the hero stays where it stood", not field.walking() and field.hero_cell() == stood)
	step("a title and lists inside", menu.is_item_separator(0) and not menu.find_children("List_*", "PopupMenu", false, false).is_empty())
	await shot("menu")
	var trade: Button = find(find(screen(), "ThingActs"), "Trade_" + str(trader["id"]))
	if not step("«Торговать» in the menu", trade != null and menu.id_of(trade) >= 0):
		return
	menu.id_pressed.emit(menu.id_of(trade))
	await wait_until(func() -> bool: return not field.walking() and s.mode == GameSession.MODE_TRADE and not gs.is_busy(), 30.0)
	await frames(2)
	step("trade: the hero walks right up", WalkRules.distance(field.hero_cell(), at) <= 1 and s.mode == GameSession.MODE_TRADE, str(WalkRules.distance(field.hero_cell(), at)))
	step("the menu closed", acts_menu() == null)
	gs.leave_conversation()
	await wait_until(func() -> bool: return not s.in_conversation() and not gs.is_busy(), 30.0)
	await frames(2)


func _far_from(cell: Vector2i, room: String, lib: Dictionary) -> Vector2i:
	var best: Vector2i = field.hero_cell()
	for y: int in int(field.map["h"]):
		for x: int in int(field.map["w"]):
			var at := Vector2i(x, y)
			if WalkRules.room_of(field.map, at) == room and WalkRules.passable(field.map, lib, at) and field.ref_at(at).is_empty() \
					and WalkRules.distance(at, cell) > WalkRules.distance(best, cell):
				best = at
	return best


## The farthest square of a room from the hero.
func _far(room: String, lib: Dictionary) -> Vector2i:
	var best := Vector2i(-1, -1)
	var length := -1
	for y: int in int(field.map["h"]):
		for x: int in int(field.map["w"]):
			var cell := Vector2i(x, y)
			if WalkRules.room_of(field.map, cell) != room or not WalkRules.passable(field.map, lib, cell) or cell == field.hero_cell():
				continue
			var steps := WalkRules.path(field.map, lib, field.hero_cell(), cell).size()
			if steps > length:
				length = steps
				best = cell
	return best


func _way(to: String) -> Vector2i:
	for e: Dictionary in field.map["exits"]:
		if str(e["to"]) == to:
			return Vector2i(int(e["x"]), int(e["y"]))
	return Vector2i(-1, -1)


func _click(cell: Vector2i) -> void:
	var at: Vector2 = field.corner() + (Vector2(cell) + Vector2(0.5, 0.5)) * field.tile()
	_button(at, true)
	_button(at, false)
	await frames(2)


func _button(at: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.position = at
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	field._gui_input(e)


func _wheel(at: Vector2, wheel: MouseButton) -> void:
	var e := InputEventMouseButton.new()
	e.position = at
	e.button_index = wheel
	e.pressed = true
	field._gui_input(e)


func _chat(s: GameSession) -> String:
	var out: Array[String] = []
	for e: Dictionary in s.chat.slice(maxi(0, s.chat.size() - 4)):
		out.append(" · ".join(e.get("lines", [])) if e.has("lines") else str(e.get("text", "")))
	return " | ".join(out).left(400)
