extends "res://tools/playtest/playtest_base.gd"
## The build screen (python tools/godot_playtest.py --scenario build_home), v0.8.4.42 «Имущество как в Sims»: the river
## house bought, «Обустроить» in «Имущество» opens the map of the room; the list filtered by a group and a search; a wall,
## a window in it, a door; a bed that rests the hero, a chest on its square, a workbench that crafts; stairs into
## «Мансарда»; in the yard a plot «Огород» at the edge and a shed «Сарай» on free ground; the master's chest of 50 pounds
## placed by hand; a thing taken back for half its price.


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
	var c := s.character
	var fx: EffectEngine = gs.effects
	c["gold_cp"] = 200000
	s.settings["needs"] = false
	s.minute = 12 * 60
	s.room_id = "brod-townhall"
	PropertyRules.buy(s, data, "river_house")
	PropertyRules.state(c)["river_house"]["deed"] = true
	s.room_id = "brod-river-house"
	for r: String in ["brod-square", "brod-townhall", "brod-river-yard", "brod-river-house"]:
		if not s.visited.has(r):
			s.visited.append(r)
	node("EventBus").state_changed.emit()
	await frames(3)

	await press(find(screen(), "PropertyButton"))
	await frames(4)
	var furnish: Button = find(screen(), "PropertyFurnish_river_house")
	if not step("«Обустроить» in «Имущество» at home", furnish != null and not furnish.disabled):
		await shot("no_furnish")
		return
	await press(furnish)
	await frames(6)
	var view: Control = find(screen(), "BuildView")
	if not step("the build screen opens over the map of the room", view != null and view.visible and not (find(screen(), "PropertyView") as Control).visible):
		return
	await shot("build_screen")

	var groups := find(view, "BuildGroups")
	step("the groups: walls, craft, rest, storage, trade, ways", find(groups, "BuildGroup_walls") != null and find(groups, "BuildGroup_craft") != null
		and find(groups, "BuildGroup_rest") != null and find(groups, "BuildGroup_storage") != null and find(groups, "BuildGroup_ways") != null)
	await press(find(groups, "BuildGroup_craft"))
	await frames(4)
	var list := find(view, "BuildList")
	step("«Ремесло» shows the stations only", find(list, "BuildItem_forge") != null and find(list, "BuildItem_bed") == null, _items(list))
	await shot("group_craft")
	await press(find(view, "BuildGroup_all"))
	await frames(3)
	var search: LineEdit = find(view, "BuildSearch")
	search.text = "сунд"
	search.text_changed.emit(search.text)
	await frames(3)
	step("a search by name: «сунд» — the chest", find(list, "BuildItem_chest") != null and find(list, "BuildItem_bed") == null, _items(list))
	search.text = ""
	search.text_changed.emit("")
	await frames(2)

	var gold := int(c["gold_cp"])
	var wall := await _put(view, s, data, "wall", 2)
	step("a wall drawn on a square", wall.x >= 0 and _char(s, data, wall) == "#", str(wall))
	await _pick(view, "window")
	await _click(view, wall)
	step("a window put in it", _char(s, data, wall) == "w")
	var door := await _put(view, s, data, "wall", 2, [wall, wall + Vector2i.LEFT, wall + Vector2i.RIGHT, wall + Vector2i.UP, wall + Vector2i.DOWN])
	await _pick(view, "door")
	await _click(view, door)
	step("a door in another wall, floor to floor", _char(s, data, door) == "+", BuildRules.build_why(s, data, "door", door))
	step("the walls paid by the engine's prices", int(c["gold_cp"]) == gold - 10 - 40 - 10 - 60, "%d" % (gold - int(c["gold_cp"])))
	await shot("walls_window_door")

	var bed := await _put(view, s, data, "bed", 1)
	step("a bed on its square: the hero rests at home free", bed.x >= 0 and ExplorationRules.can_rest(s, data["world"], data).is_empty())
	var chest := await _put(view, s, data, "chest", 1)
	step("a chest on its square, its own window", (s.props.get(s.room_id, []) as Array).any(func(p: Dictionary) -> bool:
		return ContainerRules.is_container(p) and p.get("at") is Array))
	var bench := await _put(view, s, data, "workbench", 1)
	step("a workbench: crafting here", bench.x >= 0 and CraftRules.station_here(s, data, "workbench"))
	await shot("things_placed")

	await _pick(view, BuildRules.PASSAGE)
	var name: LineEdit = find(view, "BuildName")
	step("the passage asks a name", name.visible)
	name.text = "Мансарда"
	var stairs := _spot(s, data, BuildRules.PASSAGE, 1, [], "Мансарда")
	await _click(view, stairs)
	var attic := _room_named(data, "Мансарда")
	step("stairs into «Мансарда», a new room upstairs", not attic.is_empty() and (LayoutRules.map_of(s, data, s.room_id)["exits"] as Array).any(func(e: Dictionary) -> bool:
		return str(e["to"]) == attic and str(e["kind"]) == "stairs"))
	await shot("stairs")

	(find(view, "BuildRemove") as Button).button_pressed = true  # a toggle: the click flips it
	await frames(2)
	gold = int(c["gold_cp"])
	await _click(view, chest)
	step("«Убрать» takes the chest back for half", int(c["gold_cp"]) == gold + 100 and not (s.props.get(s.room_id, []) as Array).any(func(p: Dictionary) -> bool:
		return ContainerRules.is_container(p)), "%d" % (int(c["gold_cp"]) - gold))
	(find(view, "BuildRemove") as Button).button_pressed = false
	await frames(2)
	await press(find(view, "BuildDone"))
	await frames(4)
	step("«Готово» back to the game", not view.visible)
	var tokens := MapSpots.of(s, data, LayoutRules.map_of(s, data, s.room_id))
	step("the bed on the game's map where it was put", tokens.any(func(t: Dictionary) -> bool:
		return str(t["ref"]) == "station:bed" and int(t["x"]) == bed.x and int(t["y"]) == bed.y))
	step("«Спать дома» on the panel", find(screen(), "OwnBedButton") != null)
	await shot("home_after")

	if not attic.is_empty():
		gs.go(attic)
		await wait_until(func() -> bool: return not gs.is_busy(), 30.0)
		await frames(4)
		step("walked up into «Мансарда»", s.room_id == attic)
		await shot("attic")

	s.room_id = "brod-river-yard"
	node("EventBus").state_changed.emit()
	await frames(3)
	await press(find(screen(), "PropertyButton"))
	await frames(4)
	await press(find(screen(), "PropertyFurnish_river_house"))
	await frames(6)
	await _pick(view, BuildRules.PASSAGE)
	name.text = "Огород"
	var map := LayoutRules.map_of(s, data, s.room_id)
	var edge := Vector2i(-1, -1)
	for x: int in range(3, int(map["w"]) - 3):
		if BuildRules.build_why(s, data, BuildRules.PASSAGE, Vector2i(x, int(map["h"]) - 1), "Огород").is_empty():
			edge = Vector2i(x, int(map["h"]) - 1)
			break
	await _click(view, edge)
	var garden := _room_named(data, "Огород")
	step("a plot «Огород» at the edge of the yard, under the sky", not garden.is_empty() and LayoutRules.is_open(s, data, garden))
	await _pick(view, BuildRules.PASSAGE)
	name.text = "Сарай"
	var shed_door := Vector2i(-1, -1)  # v0.8.4.42.7: a building on free ground, a box like the pack's, its door on the square
	for y: int in range(5, int(map["h"]) - 5):
		for x: int in range(5, int(map["w"]) - 5):
			if shed_door.x < 0 and BuildRules.build_why(s, data, BuildRules.PASSAGE, Vector2i(x, y), "Сарай").is_empty():
				shed_door = Vector2i(x, y)
	await _click(view, shed_door)
	var shed := _room_named(data, "Сарай")
	step("a shed «Сарай» on free ground, a building", not shed.is_empty() and SceneRules.indoor(s, data["world"], shed)
		and _char(s, data, shed_door) == "+")
	await shot("yard_passages")

	var a := fx.validate(s, data, "bh-1", {"kind": "create", "what": "upgrade", "name": "Сундук на 50 фунтов", "text": "Окованный сундук",
		"gives": {"storage": true, "capacity_lb": 50}})
	if step("the master's chest of 50 pounds, priced by the engine", bool(a["accepted"]), str(a.get("summary", a.get("reason", "")))):
		fx.apply(s, "bh-1", [a["effect_id"]])
		node("EventBus").state_changed.emit()
		await frames(3)
		var made := ""
		for up: String in PropertyRules.ups(data):
			if str(PropertyRules.ups(data)[up]["name"]) == "Сундук на 50 фунтов":
				made = up
		step("it is in the list of the build screen", find(list, "BuildItem_" + made) != null, _items(list))
		var spot := await _put(view, s, data, made, 3)
		var big: Array = (s.props.get(s.room_id, []) as Array).filter(func(p: Dictionary) -> bool: return int(p.get("capacity_lb", 0)) == 50)
		step("placed by hand: a chest that holds 50 pounds", spot.x >= 0 and big.size() == 1)
		await shot("masters_chest")


func _items(list: Node) -> String:
	return ", ".join(list.get_children().map(func(n: Node) -> String: return str(n.name)))


func _char(s: GameSession, data: Dictionary, at: Vector2i) -> String:
	if at.x < 0:
		return ""
	return str(LayoutRules.map_of(s, data, s.room_id)["rows"][at.y])[at.x]


func _room_named(data: Dictionary, name: String) -> String:
	for id: String in data["world"]["rooms"]:
		if str(data["world"]["rooms"][id].get("name", "")) == name:
			return id
	return ""


## The first square `id` may go on, `margin` squares from the map's edge; (-1, -1) — none.
func _spot(s: GameSession, data: Dictionary, id: String, margin: int, skip: Array[Vector2i] = [], name: String = "") -> Vector2i:
	var map := LayoutRules.map_of(s, data, s.room_id)
	for y: int in range(margin, int(map["h"]) - margin):
		for x: int in range(margin, int(map["w"]) - margin):
			var at := Vector2i(x, y)
			if not skip.has(at) and BuildRules.build_why(s, data, id, at, name).is_empty():
				return at
	return Vector2i(-1, -1)


func _pick(view: Control, id: String) -> void:
	var b: BaseButton = find(view, "BuildItem_" + id.validate_node_name())
	if b != null:
		await press(b)
	await frames(2)


func _click(view: Control, cell: Vector2i) -> void:
	(find(view, "BuildField") as Control).emit_signal("cell_clicked", cell)
	await frames(3)


## Picks `id` in the list and puts it on its first free square, as the player's click.
func _put(view: Control, s: GameSession, data: Dictionary, id: String, margin: int, skip: Array[Vector2i] = []) -> Vector2i:
	await _pick(view, id)
	var at := _spot(s, data, id, margin, skip)
	if at.x >= 0:
		await _click(view, at)
	return at
