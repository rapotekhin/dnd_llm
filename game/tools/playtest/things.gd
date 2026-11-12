extends "res://tools/playtest/playtest_base.gd"
## Things of many squares drawn from above (python tools/godot_playtest.py --scenario things), v0.8.4.43.23: the hall
## furnished with tables, benches, a counter, a shelf, barrels and a chest — each a picture on its squares, turned; a
## table's squares are not walked; the smithy's forge, anvil and workbench stand on their marks; close up, the sharp set.

var field: Control


func run() -> void:
	var gs := node("GameState")
	gs.instant_walk = true
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
	still_sky(s)
	s.room_id = "brod-tavern-hall"
	s.props[s.room_id] = []  # the hall's own things on its spots, before the master's (v0.8.4.43.26)
	node("EventBus").state_changed.emit()
	await frames(4)
	field = find(screen(), "Field")
	var own: Array = field.things.filter(func(t: Dictionary) -> bool: return str(t["kind"]) == "thing")
	step("the hall stands its own tables and benches", own.any(func(t: Dictionary) -> bool: return str(t["body"]) == "table") 		and own.any(func(t: Dictionary) -> bool: return str(t["body"]) == "bench"), str(own.map(func(t: Dictionary) -> String: return str(t["body"]))))
	await shot("hall_own")
	var furniture := []
	for i: int in 12:
		var body: String = ["table", "table", "bench", "bench", "bench", "counter", "shelf", "barrel", "barrel", "chest", "plant_pot", "stool"][i]
		furniture.append({"id": "f%d" % i, "name": str(data["rules"]["things"]["bodies"][body]["name"]).capitalize(), "item_id": "", "owner": "",
			"text": "", "state": "", "body": body})
	s.props[s.room_id] = furniture
	node("EventBus").state_changed.emit()
	await frames(4)
	field = find(screen(), "Field")
	var tables: Array = field.things.filter(func(t: Dictionary) -> bool: return str(t.get("body", "")) == "table" and str(t["kind"]) == "prop")
	step("two tables of the master on the map", tables.size() == 2)
	step("a table takes two squares", tables.all(func(t: Dictionary) -> bool: return (t["cells"] as Array).size() == 2))
	step("a counter takes three", field.things.any(func(t: Dictionary) -> bool: return str(t.get("body", "")) == "counter" and (t["cells"] as Array).size() == 3))
	var view := WalkRules.view(s, data)
	step("a table's squares are not walked", tables.all(func(t: Dictionary) -> bool:
		return (t["cells"] as Array).all(func(c: Vector2i) -> bool: return not WalkRules.passable(view, data["layouts"], c))))
	var all := {}
	var overlap := false
	for t: Dictionary in field.things:
		for c: Vector2i in t.get("cells", []):
			overlap = overlap or all.has(c)
			all[c] = true
	step("no two things on one square", not overlap)
	await shot("hall")
	field.zoom(30, field.cell_point((tables[0]["cells"] as Array)[0]))
	await frames(3)
	await shot("hall_close")

	s.room_id = "brod-smithy"
	s.props[s.room_id] = []
	node("EventBus").state_changed.emit()
	await frames(4)
	var forge: Array = field.things.filter(func(t: Dictionary) -> bool: return str(t.get("body", "")) == "forge")
	step("the forge stands on its mark, two by two", forge.size() == 1 and (forge[0]["cells"] as Array).size() == 4, str(forge))
	await shot("smithy")
	for room: String in ["brod-temple", "brod-tavern-cellar", "brod-school-hall"]:  # other rooms with their own spots
		if data["world"]["rooms"].has(room):
			s.room_id = room
			s.props[room] = []
			node("EventBus").state_changed.emit()
			await frames(4)
			await shot(room)
