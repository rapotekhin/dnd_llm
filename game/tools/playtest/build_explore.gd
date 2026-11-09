extends "res://tools/playtest/playtest_base.gd"
## «Обустройство» as a player tries it (python tools/godot_playtest.py --scenario build_explore), the author's feedback of
## 2026-11-09: the house grown past its walls, split by a wall with a door in the doorway, a room built on behind the north
## wall and walked into, stairs up and a room furnished there and grown; in the yard a building like the pack's, a plot
## past the edge, the yard grown east and west with its ways where they were, all walked by clicks; one line in the chat.
## Every refusal is written down; the steps go on after a failure.


var gs: Node
var s: GameSession
var data: Dictionary


func run() -> void:
	gs = node("GameState")
	if not step("master connected", await wait_until(func() -> bool: return node("Backend").is_ready(), 30.0)):
		return
	await tap("NewGameButton")
	await tap("NextButton")
	await tap("Preset_fighter_aira")
	await press(find(screen(), "StartButton"))
	if not step("game started", await wait_until(func() -> bool: return screen_is("GameScreen") and not gs.is_busy(), 90.0)):
		return
	s = gs.session
	data = node("Catalog").data
	s.character["gold_cp"] = 500000
	s.settings["needs"] = false
	s.minute = 12 * 60
	s.room_id = "brod-townhall"
	PropertyRules.buy(s, data, "river_house")
	PropertyRules.state(s.character)["river_house"]["deed"] = true
	for r: String in ["brod-square", "brod-townhall", "brod-river-yard", "brod-river-house"]:
		if not s.visited.has(r):
			s.visited.append(r)
	s.room_id = "brod-river-house"
	node("EventBus").state_changed.emit()
	await frames(3)
	await _house()
	await _yard()


# --- the house ---------------------------------------------------------------------------------------------------------


func _house() -> void:
	var view := await _open_build()
	if view == null:
		return
	var map := _map()
	_log_map("house", map)
	var w0 := int(map["w"])
	_survey("house: outside the room", [Vector2i(-1, 3), Vector2i(w0, 3)], ["wall", BuildRules.PASSAGE])
	# v0.8.4.42.7: the room grows past a square clicked beyond its wall; west, where the door to the yard is, too
	await _pick(view, BuildRules.GROW)
	var east := Vector2i(w0 + 1, int(map["h"]) / 2)
	var gwhy := BuildRules.build_why(s, data, BuildRules.GROW, east)
	await _click(view, east)
	step("the house grows east past the clicked square", int(_map()["w"]) == w0 + 3, "%d → %d %s" % [w0, int(_map()["w"]), tr(gwhy)])
	var west := Vector2i(0, 2)
	gwhy = BuildRules.build_why(s, data, BuildRules.GROW, west)
	await _click(view, west)
	step("the house grows west by its wall", int(_map()["w"]) == w0 + 4, "%d %s" % [int(_map()["w"]), tr(gwhy)])
	map = _map()
	_log_map("house grown", map)
	step("the way to the yard moved with the west wall", (map["exits"] as Array).any(func(e: Dictionary) -> bool:
		return str(e["to"]) == "brod-river-yard" and int(e["x"]) == 0 and _char(Vector2i(int(e["x"]), int(e["y"]))) == "+"), str(map["exits"]))
	# split the room by a wall across, a doorway left and a door put in it
	var mid := -1
	var door_at := Vector2i(-1, -1)
	for x: int in range(int(map["w"]) / 2, int(map["w"]) - 2):
		var free := true
		for y: int in range(1, int(map["h"]) - 1):
			free = free and _char(Vector2i(x, y)) == "."
		var gap := Vector2i(-1, -1)
		for y: int in range(2, int(map["h"]) - 2):  # a doorway with floor on both sides of it
			if gap.x < 0 and _char(Vector2i(x - 1, y)) == "." and _char(Vector2i(x + 1, y)) == ".":
				gap = Vector2i(x, y)
		if free and gap.x >= 0:
			mid = x
			door_at = gap
			break
	step("info: a free column for the wall across: %d, the doorway at %s" % [mid, str(door_at)], mid >= 0)
	var drawn := 0
	for y: int in range(1, int(map["h"]) - 1):
		var at := Vector2i(mid, y)
		if at == door_at:
			continue
		var why := BuildRules.build_why(s, data, "wall", at)
		if why.is_empty():
			await _pick(view, "wall")
			await _click(view, at)
			drawn += 1
		else:
			step("info: a wall across at %s — %s" % [at, tr(why)], true)
	step("a wall across the room drawn but for the doorway", drawn == int(map["h"]) - 3, "%d of %d" % [drawn, int(map["h"]) - 3])
	await _pick(view, "door")
	var dwhy := BuildRules.build_why(s, data, "door", door_at)
	await _click(view, door_at)
	step("a door in the doorway", _char(door_at) == "+", tr(dwhy))
	await shot("house_split")
	# a room built on behind the north wall: on this map, a door into it
	await _pick(view, BuildRules.PASSAGE)
	(find(view, "BuildName") as LineEdit).text = "Кладовая"
	var north := Vector2i(mid + 2, 0)
	var rwhy := BuildRules.build_why(s, data, BuildRules.PASSAGE, north, "Кладовая")
	await _click(view, north)
	var store := _room_named("Кладовая")
	step("«Кладовая» behind the north wall", not store.is_empty(), tr(rwhy))
	if not store.is_empty():
		map = _map()
		_log_map("house with «Кладовая»", map)
		step("«Кладовая» is on the house's map, a door between", (map["ids"] as Array).has(store) and (map["doors"] as Array).size() >= 1, str(map["ids"]))
	# stairs up on the far side of the wall
	(find(view, "BuildName") as LineEdit).text = "Мансарда"
	var stairs := _first(BuildRules.PASSAGE, "Мансарда", func(at: Vector2i) -> bool: return at.x > mid and WalkRules.room_of(_map(), at) == "brod-river-house")
	if step("a square for stairs past the wall", stairs.x >= 0):
		await _click(view, stairs)
	var attic := _room_named("Мансарда")
	step("stairs into «Мансарда»", not attic.is_empty())
	var before := s.chat.size()
	await _done(view)
	var said := ""
	for e: Dictionary in s.chat.slice(before):
		said += str(e.get("lines", e.get("text", ""))) + " "
	step("one line of what was built when the screen closed", said.contains("стена ×") and not said.contains("стена — "), said)
	await shot("house_after")
	if not store.is_empty():
		await _walk_into(store, "house → «Кладовая» through its door")
		if s.room_id == store:
			var sv := await _open_build()
			if sv != null:
				var chest := _first("chest")
				await _pick(sv, "chest")
				if chest.x >= 0:
					await _click(sv, chest)
				step("«Кладовая»: a chest placed", chest.x >= 0, _reasons("chest"))
				await _done(sv)
			await _walk_into("brod-river-house", "«Кладовая» → back to the house")
	if not attic.is_empty():
		await _walk_out(attic, "house → «Мансарда» through the door of the wall across")
		if s.room_id == attic:
			await _attic(attic)


func _attic(attic: String) -> void:
	await shot("attic_enter")
	var map := _map()
	_log_map("attic", map)
	var view := await _open_build()
	if view == null:
		return
	for id: String in ["bed", "workbench"]:
		var at := _first(id)
		await _pick(view, id)
		var why := BuildRules.build_why(s, data, id, at) if at.x >= 0 else "no square"
		if at.x >= 0:
			await _click(view, at)
		step("«Мансарда»: %s placed" % id, at.x >= 0 and BuildRules.tokens(data, _map()).any(func(t: Dictionary) -> bool: return int(t["x"]) == at.x and int(t["y"]) == at.y), tr(why))
	await _pick(view, BuildRules.GROW)
	var h0 := int(_map()["h"])
	await _click(view, Vector2i(2, h0))
	step("«Мансарда» grows south", int(_map()["h"]) == h0 + 2, "%d → %d" % [h0, int(_map()["h"])])
	await _done(view)
	await shot("attic_after")
	await _walk_out("brod-river-house", "«Мансарда» → back down to the house")
	await shot("house_back")


# --- the yard ----------------------------------------------------------------------------------------------------------


func _yard() -> void:
	if s.room_id != "brod-river-yard":
		await _walk_out("brod-river-yard", "house → the yard")
	if s.room_id != "brod-river-yard":
		s.room_id = "brod-river-yard"
		node("EventBus").state_changed.emit()
		await frames(3)
	var view := await _open_build()
	if view == null:
		return
	var map := _map()
	var w0 := int(map["w"])
	var house_way := _way_to("brod-river-house")
	# a building on free ground: a box like the pack's, its door on the square clicked
	await _pick(view, BuildRules.PASSAGE)
	(find(view, "BuildName") as LineEdit).text = "Сарай"
	var spot := _first(BuildRules.PASSAGE, "Сарай", func(at: Vector2i) -> bool: return at.x > 4 and at.y > 4 and at.x < int(map["w"]) - 5 and at.y < int(map["h"]) - 5)
	if step("info: a square for a building's door at %s" % str(spot), spot.x >= 0, _reasons(BuildRules.PASSAGE, "Сарай")):
		await _click(view, spot)
	var shed := _room_named("Сарай")
	var box: Array = _way_to(shed).get("box", [])
	step("«Сарай» stands as a box with its door", not shed.is_empty() and box.size() == 4 and _char(spot) == "+", str(_way_to(shed)))
	# a plot past the edge: the click outside the map stands on the edge
	(find(view, "BuildName") as LineEdit).text = "Огород"
	var past := Vector2i(-1, int(map["h"]) / 3)
	var ewhy := BuildRules.build_why(s, data, BuildRules.PASSAGE, past, "Огород")
	await _click(view, past)
	var garden := _room_named("Огород")
	step("«Огород» past the west edge", not garden.is_empty(), tr(ewhy))
	await shot("yard_built")
	# the yard grows east and west past its edge
	await _pick(view, BuildRules.GROW)
	var gwhy := BuildRules.build_why(s, data, BuildRules.GROW, Vector2i(w0 + 2, 10))
	await _click(view, Vector2i(w0 + 2, 10))
	step("the yard grows east", int(_map()["w"]) == w0 + 3, "%d %s" % [int(_map()["w"]), tr(gwhy)])
	gwhy = BuildRules.build_why(s, data, BuildRules.GROW, Vector2i(-3, 10))
	await _click(view, Vector2i(-3, 10))
	step("the yard grows west", int(_map()["w"]) == w0 + 6, "%d %s" % [int(_map()["w"]), tr(gwhy)])
	map = _map()
	var house_now := _way_to("brod-river-house")
	step("the house's door is where it was on the ground", not house_now.is_empty() and int(house_now["x"]) == int(house_way["x"]) + 3 and int(house_now["y"]) == int(house_way["y"]),
		"%s → %s" % [str(house_way), str(house_now)])
	step("the plot's way moved with the west edge", int(_way_to(garden).get("x", -1)) == 0, str(_way_to(garden)))
	await _done(view)
	await shot("yard_after")
	if not shed.is_empty():
		await _walk_out(shed, "yard → «Сарай» by its door")
		await shot("shed_enter")
		if s.room_id == shed:
			_log_map("shed", _map())
			await _walk_out("brod-river-yard", "«Сарай» → back out to the yard")
			await shot("yard_back")
	if not garden.is_empty():
		await _walk_out(garden, "yard → «Огород»")
		if s.room_id == garden:
			await _walk_out("brod-river-yard", "«Огород» → back to the yard")
	await _walk_out("brod-river-house", "yard → the grown house")
	# a load keeps it all: the built rooms, their ways and the hands' squares
	var sm := node("SaveManager")
	step("saved to a slot", sm.save_slot("slot_9", s))
	var back: Variant = sm.read_slot("slot_9")
	step("the slot reads back", back != null)


func _way_to(to: String) -> Dictionary:
	for e: Dictionary in _map()["exits"]:
		if str(e["to"]) == to:
			return e
	return {}


## The hero walks into another room of the same map by a click on a square of it.
func _walk_into(to: String, what: String) -> void:
	var map := _map()
	var target := Vector2i(-1, -1)
	for y: int in int(map["h"]):
		for x: int in int(map["w"]):
			if target.x < 0 and WalkRules.room_of(map, Vector2i(x, y)) == to and WalkRules.passable(map, data["layouts"], Vector2i(x, y)) and _char(Vector2i(x, y)) == ".":
				target = Vector2i(x, y)
	if not step("%s: a square of it" % what, target.x >= 0):
		return
	await click_cell(target)
	await wait_until(func() -> bool: return s.room_id == to and not gs.is_busy(), 20.0)
	step("%s: walked by clicks" % what, s.room_id == to, "stands in %s at %s" % [s.room_id, str(WalkRules.settle(s, data, _map()))])
	await frames(4)


# --- helpers -----------------------------------------------------------------------------------------------------------


func _open_build() -> Control:
	await press(find(screen(), "PropertyButton"))
	await frames(4)
	var furnish: Button = find(screen(), "PropertyFurnish_river_house")
	if not step("«Обустроить» in %s" % s.room_id, furnish != null and not furnish.disabled, tr(BuildRules.where_why(s, data))):
		await shot("no_furnish_" + s.room_id)
		var close: Button = find(screen(), "ClosePropertyButton")
		if close != null:
			await press(close)
		await key(KEY_ESCAPE)
		return null
	await press(furnish)
	await frames(6)
	return find(screen(), "BuildView")


func _done(view: Control) -> void:
	await press(find(view, "BuildDone"))
	await frames(4)


func _map() -> Dictionary:
	return LayoutRules.map_of(s, data, s.room_id)


func _char(at: Vector2i) -> String:
	var map := _map()
	if at.x < 0 or at.y < 0 or at.x >= int(map["w"]) or at.y >= int(map["h"]):
		return ""
	return str(map["rows"][at.y])[at.x]


func _room_named(name: String) -> String:
	for id: String in data["world"]["rooms"]:
		if str(data["world"]["rooms"][id].get("name", "")) == name:
			return id
	return ""


func _first(id: String, name: String = "", ok: Callable = Callable()) -> Vector2i:
	var map := _map()
	for y: int in int(map["h"]):
		for x: int in int(map["w"]):
			var at := Vector2i(x, y)
			if (not ok.is_valid() or ok.call(at)) and BuildRules.build_why(s, data, id, at, name).is_empty():
				return at
	return Vector2i(-1, -1)


## Why `id` goes nowhere: the reasons over the map, counted.
func _reasons(id: String, name: String = "") -> String:
	var map := _map()
	var by := {}
	for y: int in int(map["h"]):
		for x: int in int(map["w"]):
			var why := BuildRules.build_why(s, data, id, Vector2i(x, y), name)
			by[why] = int(by.get(why, 0)) + 1
	return ", ".join(by.keys().map(func(k: String) -> String: return "%s ×%d" % [tr(k) if not k.is_empty() else "можно", int(by[k])]))


func _survey(what: String, cells: Array, ids: Array) -> void:
	for at: Vector2i in cells:
		for id: String in ids:
			var why := BuildRules.build_why(s, data, id, at, "Комната")
			step("info: %s %s, %s — %s" % [what, str(at), id, tr(why) if not why.is_empty() else "можно"], true)


func _log_map(what: String, map: Dictionary) -> void:
	step("info: map of %s %dx%d, rooms %s, exits %s" % [what, int(map["w"]), int(map["h"]), str(map["ids"]),
		str((map["exits"] as Array).map(func(e: Dictionary) -> String: return "%s@%d,%d(%s)" % [e["to"], int(e["x"]), int(e["y"]), e.get("kind", "")]))], true)
	for row: Variant in map["rows"]:
		step("info:   " + str(row), true)


func _pick(view: Control, id: String) -> void:
	var b: BaseButton = find(view, "BuildItem_" + id.validate_node_name())
	if b == null:
		await press(find(view, "BuildGroup_all"))
		await frames(2)
		b = find(view, "BuildItem_" + id.validate_node_name())
	if b != null:
		await press(b)
	await frames(2)


func _click(view: Control, cell: Vector2i) -> void:
	(find(view, "BuildField") as Control).emit_signal("cell_clicked", cell)
	await frames(3)


## The hero walks to the way into `to` by a click on its square, as the player does.
func _walk_out(to: String, what: String) -> void:
	var map := _map()
	var ways: Array = (map["exits"] as Array).filter(func(e: Dictionary) -> bool: return str(e["to"]) == to)
	if not step("%s: a way on the map" % what, not ways.is_empty(), str((map["exits"] as Array).map(func(e: Dictionary) -> String: return str(e["to"])))):
		return
	var from := s.room_id
	await click_cell(Vector2i(int(ways[0]["x"]), int(ways[0]["y"])))
	await wait_until(func() -> bool: return s.room_id != from and not gs.is_busy(), 20.0)
	if s.room_id == from:  # the walk may stop at the way: a second click passes
		await click_cell(Vector2i(int(ways[0]["x"]), int(ways[0]["y"])))
		await wait_until(func() -> bool: return s.room_id != from and not gs.is_busy(), 20.0)
	step("%s: walked by clicks" % what, s.room_id == to, "stands in %s at %s" % [s.room_id, str(WalkRules.settle(s, data, _map()))])
	await frames(4)
