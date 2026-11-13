extends "res://tools/playtest/playtest_base.gd"
## The measure of the light interface (python tools/godot_playtest.py --scenario ui_count), v0.8.4.43.41: how many
## controls the player can click on the game screen in the world, in a talk, in a trade, at an open chest, with the
## character window open and in a fight; how many clicks the frequent acts take — talk to a person, open a trade, take a
## thing from a chest, put on a thing, strike a foe. Each path is clicked through as the player would, from the hero
## standing far off, and its clicks are counted: a press of the mouse is one, a drag one, a double click two; a key is
## not used. A control is counted when it is a button, a field or a cell (`BaseButton`, `LineEdit`, `TextEdit`), shown,
## and the mouse over its middle reaches it (nothing over it, inside the screen, not scrolled away). The numbers go to
## the report and to `ui_count.json` beside it; docs/design/ux/ui-count.md compares them with v0.8.4.42.27.

const HERO := "Preset_cleric_branko"  ## a caster: weapons, spells and things on the bar
const ROOM := "brod-tavern-hall"  ## people, a trader, room to walk
const RING := "ring_of_water_walking"  ## a ring worn without attunement

var field: Control
var _clicks := 0
var _how: Array[String] = []
var _out := {"screens": {}, "paths": {}}


func run() -> void:
	var gs := node("GameState")
	if not step("master connected", await wait_until(func() -> bool: return node("Backend").is_ready(), 30.0)):
		return
	await tap("NewGameButton")
	await tap("NextButton")
	await tap(HERO)
	await press(find(screen(), "StartButton"))
	if not step("game started", await wait_until(func() -> bool: return screen_is("GameScreen") and not gs.is_busy(), 60.0)):
		return
	var s: GameSession = gs.session
	still_sky(s)
	s.room_id = ROOM
	node("EventBus").state_changed.emit()
	await frames(5)
	field = find(screen(), "Field")
	if not step("the hall's map", field != null and WalkRules.room_of(field.map, field.hero_cell()) == ROOM):
		return
	(screen().get("input") as Control).release_focus()
	await _count("world", "в мире: зал таверны, ничего не открыто")
	await shot("world")
	var trader := _trader(s, gs)
	if step("a trader on the map", not trader.is_empty(), str(field.things.size())):
		await _talk(s, gs, trader)
		await _trade(s, gs, trader)
	await _chest(s, gs)
	await _wear(s)
	await _fight(s, gs)
	var f := FileAccess.open(out_dir.path_join("ui_count.json"), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_out, "  "))


## Talk: the left button on the person (v0.8.4.43.4: its main act), the hero walks up.
func _talk(s: GameSession, gs: Node, who: Dictionary) -> void:
	var at := Vector2i(int(who["x"]), int(who["y"]))
	await _stand_far(at)
	_begin()
	await _mouse(at, MOUSE_BUTTON_LEFT, "левая кнопка по %s" % who.get("name", who["id"]))
	await wait_until(func() -> bool: return s.in_conversation() and not gs.is_busy() and not field.walking(), 60.0)
	await frames(3)
	_end("talk", "заговорить", s.in_conversation() and s.npc_id == str(who["id"]))
	await _count("talk", "в разговоре")
	await shot("talk")
	gs.leave_conversation()
	await wait_until(func() -> bool: return not s.in_conversation() and not gs.is_busy(), 30.0)
	await frames(3)


## Trade: the right button on the trader opens its menu, «Торговать» there walks up and opens the trade.
func _trade(s: GameSession, gs: Node, who: Dictionary) -> void:
	var at := Vector2i(int(who["x"]), int(who["y"]))
	await _stand_far(at)
	_begin()
	await _mouse(at, MOUSE_BUTTON_RIGHT, "правая кнопка по %s" % who.get("name", who["id"]))
	var menu := acts_menu()
	var trade: Button = find(find(screen(), "ThingActs"), "Trade_" + str(who["id"]))
	if step("«Торговать» in its menu", menu != null and trade != null and (menu as ActsMenu).id_of(trade) >= 0):
		_click("«%s» в меню" % trade.text)
		menu.id_pressed.emit((menu as ActsMenu).id_of(trade))
		await wait_until(func() -> bool: return s.mode == GameSession.MODE_TRADE and not gs.is_busy() and not field.walking(), 60.0)
		await frames(3)
	_end("trade", "открыть торговлю", s.mode == GameSession.MODE_TRADE)
	await _count("trade", "в торговле", find(screen(), "TradePanel"))
	await shot("trade")
	gs.leave_conversation()
	await wait_until(func() -> bool: return not s.in_conversation() and not gs.is_busy(), 30.0)
	await frames(3)


## Take a thing from a chest: the left button on the chest opens it (the hero walks up), the candle dragged onto the
## hero's grid.
func _chest(s: GameSession, gs: Node) -> void:
	var list: Array = s.props.get(s.room_id, [])
	list.append({"id": "uchest", "name": "Сундук", "description": "Простой сундук.", "item_id": "", "owner": "", "text": "",
		"state": "", "container": "chest", "contents": {"candle": 1}, "locked": false})
	s.props[s.room_id] = list
	node("EventBus").state_changed.emit()
	await frames(4)
	var at: Vector2i = field.cell_of("prop:uchest")
	if not step("the chest on the map", at.x >= 0):
		return
	await _stand_far(at)
	var had := int(s.character["inventory"].get("candle", 0))
	_begin()
	await _mouse(at, MOUSE_BUTTON_LEFT, "левая кнопка по сундуку")
	var view: Control = find(screen(), "ContainerView")
	await wait_until(func() -> bool: return view != null and view.visible and not field.walking(), 20.0)
	await frames(3)
	if step("the chest opened", view != null and view.visible):
		await _drag(find(view, "In_candle"), find(view, "MineGrid"), "свеча перетащена в свои вещи")
	_end("take", "взять вещь из сундука", int(s.character["inventory"].get("candle", 0)) == had + 1)
	await _count("chest", "у открытого сундука", view)
	await shot("chest")
	if view != null:
		await press(find(view, "CloseContainerButton"))
	await frames(3)


## Put on a thing: the window's button, the ring dragged onto the doll.
func _wear(s: GameSession) -> void:
	ItemRules.add(s.character, RING, 1)
	node("EventBus").state_changed.emit()
	await frames(3)
	_begin()
	var sheet_button: BaseButton = find(screen(), "SheetButton")
	if not step("the character window's button", sheet_button != null and sheet_button.is_visible_in_tree()):
		return
	await _press(sheet_button, "кнопка «%s»" % _name(sheet_button))
	var sheet: Control = find(screen(), "CharacterSheet")
	if not step("the window opens on «Снаряжение»", sheet != null and sheet.visible and sheet.call("current_tab") == 0):
		return
	await frames(3)
	await _count("inventory", "окно персонажа на снаряжении", sheet)
	await shot("inventory")
	await _drag(find(sheet, "Item_" + RING), find(sheet, "Slot_ring1"), "кольцо перетащено на куклу")
	_end("wear", "надеть вещь", str(s.character["equipped"].get("ring1", "")) == RING)
	await press(find(sheet, "CloseSheetButton"))
	await frames(3)


## Strike a foe beside the hero in the hero's turn: the left button on it opens its acts, the weapon picked in
## «Оружие ▸».
func _fight(s: GameSession, gs: Node) -> void:
	var data: Dictionary = node("Catalog").data
	gs.start_combat([{"monster": "goblin", "name": "Гоблин", "x": 1, "y": 1}], {})
	if not step("the fight", await wait_until(func() -> bool: return screen_is("fight"), 10.0)):
		return
	await wait_until(func() -> bool: return CombatRules.is_player_turn(s) and not gs.is_busy(), 60.0)
	var id: String = CombatRules.enemies(s)[0]
	var foe := CombatRules.fighter(s, id)
	var hero := FightGrid.cell(CombatRules.player(s))
	var g := FightGrid.grid(s, data)
	for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]:
		if FightGrid.walkable(g, hero + d) and not FightGrid.bodies(s).has(hero + d):
			FightGrid.put(foe, hero + d)
			break
	FightGrid.changed(s)
	node("EventBus").state_changed.emit()
	await frames(5)
	var at := FightGrid.cell(foe)
	step("the goblin beside the hero", WalkRules.distance(at, hero) == 1, "%s / %s" % [at, hero])
	await _count("fight", "в бою: ход героя, гоблин рядом")
	await shot("fight")
	_begin()
	await _mouse(at, MOUSE_BUTTON_LEFT, "левая кнопка по гоблину")
	var menu: PopupMenu = find(screen(), "FoeMenu")
	var weapons: PopupMenu = find(menu, "List_" + tr("COMBAT_TAB_WEAPONS")) if menu != null else null
	var line := -1
	if weapons != null:
		for i: int in weapons.item_count:
			if line < 0 and not weapons.is_item_disabled(i) and not weapons.is_item_separator(i):
				line = i
	if step("a blow in its menu", menu != null and menu.visible and line >= 0):
		_click("«%s» в «%s ▸»" % [weapons.get_item_text(line), tr("COMBAT_TAB_WEAPONS")])
		weapons.id_pressed.emit(weapons.get_item_id(line))
		menu.hide()
		await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
		await frames(4)
	_end("attack", "ударить врага", int(CombatRules.economy(s).get("action", 1)) == 0)
	await shot("after_blow")


# --- counting -------------------------------------------------------------------------------------------------------


## The controls the player can click now, written under `key`; `inside` — those of a window counted apart.
func _count(key: String, what: String, inside: Node = null) -> void:
	await wait_until(func() -> bool: return not node("GameState").is_busy(), 30.0)  # a turn going on greys the buttons
	await frames(5)
	var view := Rect2(Vector2.ZERO, root.get_visible_rect().size)
	var all: Array[Dictionary] = []
	_collect(current_scene, all)
	var r := {"what": what, "on": 0, "grey": 0, "empty": 0, "icons": 0, "text": 0, "fields": 0, "tabs": 0, "rows": 0, "window": 0,
		"names": [], "greyed": [], "covered": []}
	for p: Dictionary in all:
		var c: Control = p["c"]
		var mid := (p["rect"] as Rect2).get_center()
		if not view.has_point(mid):
			continue
		_hover(mid)
		var h := root.gui_get_hovered_control()
		if h == null or not (h == c or c.is_ancestor_of(h)):  # shown but under something: not counted, named in the json
			(r["covered"] as Array).append("%s ← %s" % [p["name"], h.name if h != null else "-"])
			continue
		if bool(p["grey"]):
			r["grey"] += 1
			(r["greyed"] as Array).append(p["name"])
			continue
		if _derives(c, "ItemCell") and str(c.get("item")).is_empty():  # an empty slot of the doll or the belt: a place to drop
			r["empty"] += 1
			continue
		r["on"] += 1
		r[p["kind"]] += 1
		(r["names"] as Array).append("%s:%s" % [p["kind"], p["name"]])
		if inside != null and inside.is_ancestor_of(c):
			r["window"] += 1
	_hover(Vector2(view.size.x - 2, 2))
	await frames(2)
	_out["screens"][key] = r
	step("count %s: %d to click" % [key, r["on"]], r["on"] > 0, "%s; значков %d, кнопок с подписью %d, вкладок %d, строк и лиц %d, полей %d; серых %d, пустых ячеек %d%s" % [
		what, r["icons"], r["text"], r["tabs"], r["rows"], r["fields"], r["grey"], r["empty"], "" if inside == null else "; в окне %d" % r["window"]])


## What a click can reach: a button, a field, each tab of a tab bar, a panel that takes a click itself (a row, a face);
## the map is not one of them (its people and things are drawn, not controls, in both versions), nor a text that only
## shows a card at the cursor (a line of the chat, a description).
func _collect(n: Node, out: Array[Dictionary]) -> void:
	if (n is CanvasItem and not (n as CanvasItem).visible) or (n is CanvasLayer and not (n as CanvasLayer).visible) or n is Window:
		return
	var c := n as Control
	if c != null and c.mouse_filter != Control.MOUSE_FILTER_IGNORE and c.size.x >= 2.0 and c.size.y >= 2.0:
		var at := c.get_global_rect()
		if c is TabBar:
			var tb := c as TabBar
			for i: int in tb.tab_count:
				if not tb.is_tab_hidden(i):
					var tr_ := tb.get_tab_rect(i)
					out.append({"c": c, "rect": Rect2(at.position + tr_.position, tr_.size), "name": "%s/%s" % [c.name, tb.get_tab_title(i)],
						"kind": "tabs", "grey": tb.is_tab_disabled(i)})
		elif c is BaseButton or c is LineEdit or c is TextEdit:
			var grey := (c is BaseButton and (c as BaseButton).disabled) or (c is LineEdit and not (c as LineEdit).editable) 				or (c is TextEdit and not (c as TextEdit).editable)
			out.append({"c": c, "rect": at, "name": str(c.name), "kind": _kind(c), "grey": grey})
		elif not (c is ScrollBar or c is ScrollContainer or c is Label or c is RichTextLabel or _derives(c, "MapField") or _derives(c, "MapCanvas")) 				and (not c.gui_input.get_connections().is_empty() or _own_input(c)):
			out.append({"c": c, "rect": at, "name": str(c.name), "kind": "rows", "grey": false})
	for ch: Node in n.get_children(true):
		_collect(ch, out)


## A script of its own that takes the mouse (`_gui_input`): a clickable panel that is no button.
func _own_input(c: Control) -> bool:
	var sc := c.get_script() as Script
	if sc == null:
		return false
	for m: Dictionary in sc.get_script_method_list():
		if str(m["name"]) == "_gui_input":
			return true
	return false


## "icons" — a cell with a picture and no caption, "fields" — a line to type in, "text" — a button with a caption.
func _kind(c: Control) -> String:
	if c is LineEdit or c is TextEdit:
		return "fields"
	if _derives(c, "IconSlot") or c is TextureButton or (c is Button and (c as Button).text.strip_edges().is_empty()):
		return "icons"
	return "text"


func _derives(c: Object, cls: String) -> bool:
	var sc := c.get_script() as Script
	while sc != null:
		if sc.get_global_name() == cls:
			return true
		sc = sc.get_base_script()
	return false


func _hover(at: Vector2) -> void:
	var m := InputEventMouseMotion.new()
	m.position = at
	m.global_position = at
	root.push_input(m, true)


# --- clicks ---------------------------------------------------------------------------------------------------------


func _begin() -> void:
	_clicks = 0
	_how = []


func _click(how: String, n: int = 1) -> void:
	_clicks += n
	_how.append(how)


func _end(key: String, what: String, ok: bool) -> void:
	_out["paths"][key] = {"what": what, "clicks": _clicks, "how": _how.duplicate(), "ok": ok}
	step("path %s: %d clicks" % [key, _clicks], ok, "%s: %s" % [what, " → ".join(_how)])


func _press(b: BaseButton, how: String) -> void:
	_click(how)
	await press(b)
	await frames(2)


func _drag(cell: Control, onto: Control, how: String) -> void:
	_click(how)
	var names := "%s → %s" % [cell.name if cell != null else "-", onto.name if onto != null else "-"]
	step(how, await drag(cell, onto), names)


## A press and a release of `button` over the middle of `cell`, as the mouse does it on the map.
func _mouse(cell: Vector2i, button: MouseButton, how: String) -> void:
	_click(how)
	var at: Vector2 = field.corner() + (Vector2(cell) + Vector2(0.5, 0.5)) * field.tile()
	for down: bool in [true, false]:
		var e := InputEventMouseButton.new()
		e.position = at
		e.button_index = button
		e.pressed = down
		field._gui_input(e)
	await frames(3)
	await wait_until(func() -> bool: return not field.walking(), 20.0)
	await frames(2)


## The hero walks off to the square of its room farthest from `at` (not counted): each path starts away from its target.
func _stand_far(at: Vector2i) -> void:
	var s: GameSession = node("GameState").session
	var lib: Dictionary = node("Catalog").data["layouts"]
	var best: Vector2i = field.hero_cell()
	for y: int in int(field.map["h"]):
		for x: int in int(field.map["w"]):
			var c := Vector2i(x, y)
			if WalkRules.room_of(field.map, c) == s.room_id and WalkRules.passable(field.map, lib, c) and field.ref_at(c).is_empty() \
					and not WalkRules.path(field.map, lib, field.hero_cell(), c).is_empty() and WalkRules.distance(c, at) > WalkRules.distance(best, at):
				best = c
	var e := InputEventMouseButton.new()
	e.position = field.corner() + (Vector2(best) + Vector2(0.5, 0.5)) * field.tile()
	e.button_index = MOUSE_BUTTON_LEFT
	for down: bool in [true, false]:
		e.pressed = down
		field._gui_input(e.duplicate())
	await wait_until(func() -> bool: return not field.walking(), 20.0)
	await frames(3)


func _trader(s: GameSession, gs: Node) -> Dictionary:
	for th: Dictionary in field.things:
		if str(th["kind"]) == "npc" and gs.world().is_trader(str(th["id"])):
			return th
	return {}


func _name(b: BaseButton) -> String:
	var t: String = b.get("tip_title") if b.get("tip_title") != null and not str(b.get("tip_title")).is_empty() else (b as Button).text if b is Button else str(b.name)
	return t.get_slice("\n", 0)
