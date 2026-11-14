class_name FightUi
extends Control
## The fight on the one screen (v0.8.4): the place's own map is the field. The queue over it — every fighter's face, the foes
## too; on the left the party column of the peace (v0.8.4.43.10, as in BG3: the hero and its party, never a foe), the acts on
## the hotbar under it, the log on the right; the windows of a choice and the results stand over all.
## An act that needs a target lights it: a click on a body or a line of the list does it, an area follows the mouse and a
## click lays it on the square. A click on a free square walks, on a foe opens its acts. The screen only shows and sends:
## every rule is in `core/`, FightGrid and CombatRules.

var _screen: Control
var _field: MapField
var _details: DetailsPanel  # v0.7.7 fixes: what a spell, feature, item or foe is (hover or press)
var _queue: HBoxContainer
var _party: PartyColumn  ## the hero and its party, the same column as out of a fight (v0.8.4.43.10)
var _incoming: VBoxContainer  ## who is on the way to the fight
var _bar: ActionBar  # the hotbar under the map, one in a fight and out of it (v0.8.4.43)
var _fx_layer: Control  # floating numbers over the field
var _anims: FightAnims  # the strikes, spells and moves on the map (v0.8.4.23)
var _block: VBoxContainer  # the round's engine lines (Б6)
var _block_round := -1
var _hint: Label
var _log_box: VBoxContainer
var _log_scroll: ScrollContainer
var end_turn: Button
var _results: ModalFrame
var _results_box: VBoxContainer
## «Использовать?» — a choice of a feature or a reaction, as in Baldur's Gate 3 (v0.7.10).
var _ask: PanelContainer
var _conc_ask: Dictionary = {}  # v0.7.13.1: the «Прервать …?» question
var _ask_box: VBoxContainer
## The action waiting for a target: Callable(target_id) -> String (a reason or ""), and its check.
var _pending: Callable
var _pending_check: Callable
## Callable(target_id) -> Dictionary: the hint of the pending action (CombatRules.attack_preview / cast_preview).
var _pending_preview: Callable
var _pending_aim := ""  # the spell whose target is a square: its area follows the mouse
var _pending_feet := 0  # how far the picked act gets, 0 — no rim on the map
var _acts: Array[Dictionary] = []  # the acts with a target of this redraw: the tabs below and a foe's menu
var _throws: Array[Dictionary] = []  # what may be thrown this redraw: the «Бросить» cell's list (v0.8.4.43.49)
var _act_tab := ""  # the tab being drawn, and the list inside it for a foe's menu
var _act_sub := ""
var _pop: ActsMenu  # a foe's menu, the one menu's builder (v0.8.4.43.4)
var _second := {}  # {act, to}: the next click picks a square of the act
var _redrawing := false
var _on := false
var _parts: Array[Control] = []  # shown only in a fight
var _peace: Array[Control] = []  # hidden in a fight
  # v0.7.22.19 (#19): the slot circle the player picked; 0 — the lowest that fits


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_layer = Control.new()
	_fx_layer.name = "FxLayer"
	_fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fx_layer)
	_fx_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_results = ModalFrame.make("", 820.0)  # in the middle, one window template (v0.7.22.29, С4, Б5)
	_results.name = "CombatResults"
	_results.visible = false
	_results.close_x.visible = false  # a fight ends by «Продолжить»
	add_child(_results)
	_results.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_results_box = _results.body
	_ask = PanelContainer.new()
	_ask.name = "CombatAsk"
	_ask.theme_type_variation = UiTheme.SIDE
	_ask.visible = false
	add_child(_ask)
	_ask.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_ask.custom_minimum_size = Vector2(720, 0)
	_ask_box = VBoxContainer.new()
	_ask_box.add_theme_constant_override("separation", 10)
	_ask.add_child(_ask_box)


## The nodes of the one screen this fight uses (its scene holds them hidden).
func setup(screen: Control) -> void:
	_screen = screen
	_field = UiScenes.need(screen, "%Field")
	_anims = FightAnims.new()
	_anims.name = "FightAnims"
	_field.add_child(_anims)
	_anims.setup(_field, Catalog.data.get("anims", {}))
	_field.anim_lib = Catalog.data.get("anims", {})
	_queue = UiScenes.need(screen, "%Queue")
	_party = UiScenes.need(screen, "%Party")
	_party.clicked.connect(func(id: String) -> void:  # a target by its portrait, else its card (v0.8.4.43.8)
		if active():
			on_fighter(id))
	_party.context.connect(func(id: String) -> void:
		if active() and id != CombatRules.PLAYER:
			EventBus.card_requested.emit(id))
	_party.pointed.connect(func(id: String) -> void:
		if active():
			point_at("" if id == "-" else id))
	_incoming = UiScenes.need(screen, "%Incoming")
	_bar = UiScenes.need(screen, "%Bar")
	_bar.circle_picked.connect(func(_c: int) -> void: refresh())
	_hint = UiScenes.need(screen, "%Hint")
	_hint.add_theme_color_override("font_color", UiTheme.ACCENT_BRIGHT)
	end_turn = _bar.end_turn  # the round button of the hotbar
	var face := _bar.hero_portrait()  # whose bar it is by its portrait (v0.8.4.43.8; one of the party in its turn, v0.8.4.43.11)
	face.mouse_entered.connect(func() -> void: point_at(_bar_id()))
	face.mouse_exited.connect(func() -> void: point_at(""))
	face.pressed.connect(func() -> void:
		if active():
			on_fighter(_bar_id()))
	end_turn.pressed.connect(func() -> void: _do(GameState.combat_end_turn()))
	_parts.assign([UiScenes.need(screen, "%FightSide"), _queue, _hint, UiScenes.need(screen, "%FightLogBox")])
	_peace.assign([UiScenes.need(screen, "%Side"), UiScenes.need(screen, "%Strip"), UiScenes.need(screen, "%Chat")])
	var box: VBoxContainer = UiScenes.need(screen, "%FightLogBox")
	# The right side: a third — the static details, two thirds — the log (the author, v0.7.22.13).
	_details = DetailsPanel.new(Vector2(0, 120), true)  # a card at the cursor, the column is the log's (v0.8.4.43.3)
	_details.name = "CombatDetails"
	_details.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_details.size_flags_stretch_ratio = 1.0
	box.add_child(_details)
	_log_scroll = ScrollContainer.new()
	_log_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log_scroll.size_flags_stretch_ratio = 2.0
	_log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(_log_scroll)
	_log_box = VBoxContainer.new()
	_log_box.name = "CombatLog"
	_log_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log_box.add_theme_constant_override("separation", 6)
	_log_scroll.add_child(_log_box)
	EventBus.combat_lines.connect(_on_lines)
	EventBus.chat_appended.connect(_on_chat)


func active() -> bool:
	return GameState.has_session() and CombatRules.active(GameState.session)


func mine() -> bool:
	return active() and not CombatRules.actor(GameState.session).is_empty() and not GameState.is_busy() and Backend.is_ready()


## The fighter of the bar's portrait: the one whose turn the player plays, else the hero.
func _bar_id() -> String:
	return str(_bar.who.get("id", CombatRules.PLAYER))


func _on_lines(lines: Array[String]) -> void:
	if _on:
		for l: String in lines:
			_add_log(l, false)


func _on_chat(e: Dictionary) -> void:
	if not _on:
		return
	if str(e["kind"]) == GameSession.KIND_DM:
		_add_log(str(e["text"]), true)
	elif str(e["kind"]) == GameSession.KIND_SYSTEM:
		_add_log(tr(str(e["key"])), false)


## The fight came to this screen, or the screen came to a fight on a load: the log from what was.
func _enter() -> void:
	_on = true
	_clear(_log_box)
	_block = null
	_last_fx = {}
	var s := GameState.session
	for i in range(maxi(0, s.chat.size() - 4), s.chat.size()):
		var e := s.chat[i]
		if str(e["kind"]) == GameSession.KIND_DM:
			_add_log(str(e["text"]), true)
	for l: Variant in s.combat.get("log", []):
		_add_log(str(l), false)
	_pending = Callable()
	_field.stop()
	_field.close_up()
	_field.reach = {}


func _add_log(text: String, master: bool) -> void:
	if master:
		UiParts.label(_log_box, text, UiTheme.DM_TEXT)
	else:
		UiParts.roll_line(_round_block().get_node("Lines"), text, CombatRules.tip_for(GameState.session, text) if GameState.has_session() else "")
		UiParts.fold_rolls(_block, false)
	while _log_box.get_child_count() > 120:
		var old := _log_box.get_child(0)
		_log_box.remove_child(old)
		old.queue_free()
	await get_tree().process_frame
	_log_scroll.scroll_vertical = int(_log_scroll.get_v_scroll_bar().max_value)


## «Броски раунда ▸» (Б6): the engine's lines of a round in one block under a fold; a new round or the master's
## words start the next block and fold the old one.
func _round_block() -> VBoxContainer:
	var rnd := int(GameState.session.combat.get("round", 1)) if GameState.has_session() else 0
	var last := _log_box.get_child(_log_box.get_child_count() - 1) if _log_box.get_child_count() > 0 else null
	if _block != null and is_instance_valid(_block) and last == _block and rnd == _block_round:
		return _block
	if _block != null and is_instance_valid(_block):
		UiParts.fold_rolls(_block, true)
	_block = UiParts.rolls_block(false)
	_block.name = "Rolls_%d" % rnd
	_block_round = rnd
	_log_box.add_child(_block)
	return _block


## v0.7.22.27 (as in BG3), outside the input: Space ends the turn, Tab picks the next foe that can be hit (Enter strikes
## it); the acts have no keys (v0.8.4.43, the author: «не нужны»). True — the key was the fight's.
func key(event: InputEvent) -> bool:
	if event.is_action_pressed("end_turn"):
		if not end_turn.disabled:
			end_turn.pressed.emit()
		return true
	if event.is_action_pressed("next_target"):
		_next_target()
		return true
	return false


## Esc lets a picked act go. True — there was one.
func cancel() -> bool:
	if not _pending.is_valid() and _second.is_empty():
		return false
	_pending = Callable()
	_second = {}
	refresh()
	return true


## Opens a section of the hotbar by its title key; the playtests call it too.
func set_filter(key: String) -> void:
	_bar.set_filter(key)


## The focus to the next foe's face in the queue (Tab, as in BG3).
func _next_target() -> void:
	var cards: Array[Button] = []
	for n: Node in _queue.find_children("Turn_*", "Button", true, false):
		if str(CombatRules.fighter(GameState.session, str(n.name).trim_prefix("Turn_")).get("side", "")) == "enemy" and not bool(n.get_meta("out", false)):
			cards.append(n as Button)
	if cards.is_empty():
		return
	var card := cards[(cards.find(get_viewport().gui_get_focus_owner()) + 1) % cards.size()]
	card.grab_focus()
	card.mouse_entered.emit()  # its description into the panel


func _do(err: String) -> void:
	_pending = Callable()
	_second = {}
	if not err.is_empty():
		EventBus.message.emit(tr(err))
	refresh()


static func _clear(n: Node) -> void:
	for ch in n.get_children():
		n.remove_child(ch)
		ch.queue_free()


## The screen's redraw: the parts of a fight in or out, then all of it.
func refresh() -> void:
	var on := active()
	if on and not _on:
		_enter()
	elif not on:
		if _on:
			_field.release()
		_on = false
	for p: Control in _parts:
		p.visible = on
	for p: Control in _peace:
		p.visible = not on
	visible = on
	_bar.set_fight(on)
	if not on:
		_bar.clear_fight()
		_bar.hero_portrait().modulate = Color.WHITE
		_field.fighters = []
		_field.routes = {}
		_field.zones = []
		_field.blast = {}
		_field.way = []
		_field.reach = {}
		return
	var s := GameState.session
	var data := Catalog.data
	var me := mine()
	if me and not _pending.is_valid() and not CombatRules.volley(s).is_empty():  # v0.7.22.4: the next dart is armed at once
		_pending = func(t: String) -> String: return GameState.combat_act("volley", t)
		_pending_check = func(t: String) -> String: return Acts.one("volley").can(s, data, CombatRules.player(s), t)
		_pending_preview = func(_t: String) -> Dictionary: return {}
		_pending_name = "Volley"
		_pending_text = ""
		_pending_aim = ""
		_pending_feet = int(data["spells"].get(str(CombatRules.volley(s)["spell"]), {}).get("range_ft", 0))
	end_turn.disabled = not me
	_bar.who = GameState.fight_actor()  # whose turn the player plays: its face, hands and points (v0.8.4.43.11)
	_draw_queue(s)
	_draw_incoming(s)
	var face := _bar.hero_portrait()  # grey while the picked act cannot go at the one of the bar
	face.modulate = Color(1, 1, 1, 0.42) if _pending.is_valid() and not str(_pending_check.call(_target_of(_bar_id()))).is_empty() else Color.WHITE
	_draw_map(s, data, me)
	_draw_party(s)
	_play_fx(s)
	_draw_actions(s, data, me)
	end_turn.tooltip_text = Hotkeys.tip("", "end_turn", SaveManager.keys)
	_hint.text = _base_hint(me)
	_draw_results(s, data)
	_draw_ask(s)


# --- the map ---------------------------------------------------------------------------------------------------


func _draw_map(s: GameSession, data: Dictionary, me: bool) -> void:
	var map := FightGrid.map(s, data)
	var open := s.combat.has("field")
	var names := {}
	for e: Dictionary in map.get("exits", []):
		names[e["to"]] = GameState.world().room(str(e["to"])).get("name", e["to"])
	_field.names = names
	_field.clicks = true
	_field.show_map(map, data["layouts"])
	var at := FightGrid.cell(CombatRules.player(s))
	_field.dim = not open
	var now := {}
	if not open:
		now = SightRules.look(s, data, map, at)
		_field.now = now
		_field.cones = {}
	_field.place_hero(at, "", [] as Array[Dictionary])
	_field.fighters = _bodies(s, now, open)
	_field.things = _scene(s, data, map, now, open)
	_field.play(FightField.take_moves(s))
	_field.routes = Move.routes(s, data, GameState.fight_actor()) if me and not _pending.is_valid() and _second.is_empty() else {}
	_field.lit = Acts.one(str(_second["act"])).squares(s, data, GameState.fight_actor(), str(_second["to"])) if not _second.is_empty() else {}
	_field.reach = _in_range(s, data) if _pending.is_valid() and _pending_feet > 0 else {}
	_field.over = _over(s)
	_field.zones = SpellEffects.zone_view(s, data)
	_field.blast = {}
	_field.way = []
	_field.queue_redraw()


## The squares the picked act gets to from the one who moves, not behind total cover (v0.8.4.3; FightGrid.reaches, the
## act's own rule, v0.8.4.43.50).
func _in_range(s: GameSession, data: Dictionary) -> Dictionary:
	var g := FightGrid.grid(s, data)
	var me := GameState.fight_actor()
	var from := FightGrid.cell(me)
	var far := FightGrid.squares_of(data, _pending_feet)
	var out := {}
	for y: int in range(maxi(0, from.y - far), mini(int(g["map"]["h"]), from.y + far + 1)):
		for x: int in range(maxi(0, from.x - far), mini(int(g["map"]["w"]), from.x + far + 1)):
			var at := Vector2i(x, y)
			if FightGrid.dist_to(me, at) <= far and FightGrid.reaches(s, data, me, at):
				out[at] = true
	return out


## What the fight changed on the map, by colour: {square: Color}. A thing of the field is a colour only where no picture
## of it lies: a square of a thing of the room is its picture's, a barrel of the map's rows the ground's (the author,
## 2026-11-13: the priest's chest, a stone table and a boulder's square were brown squares in a fight).
func _over(s: GameSession) -> Dictionary:
	var out := {}
	for key: String in s.combat.get("cleared", {}):
		out[FightGrid.y_x(key)] = UiTheme.TILES["."]
	var drawn := {}
	for th: Dictionary in _field.things:
		for c: Variant in th.get("cells", []):
			drawn[c] = true
	var rows: Array = _field.map.get("rows", [])
	var cell := str(FightField.cfg(Catalog.data)["blocks"]["cell"])
	for key: String in s.combat.get("blocks", {}):
		var at := FightGrid.y_x(key)
		if drawn.has(at) or (at.y < rows.size() and at.x < str(rows[at.y]).length() and str(rows[at.y])[at.x] == cell):
			continue
		out[at] = UiTheme.TILES["B"]
	for key: String in s.combat.get("doors", {}):
		var d: Dictionary = s.combat["doors"][key]
		var open := bool(d.get("open", false)) or bool(d.get("gone", false))
		out[FightGrid.y_x(key)] = UiTheme.TILES["."] if bool(d.get("gone", false)) else UiTheme.TILES["."].lerp(UiTheme.TILES["+"], 0.4) if open else UiTheme.TILES["+"].darkened(0.4)
	return out


## What stands on the map beside the fight: things, and those who take no part.
func _scene(s: GameSession, data: Dictionary, map: Dictionary, now: Dictionary, open: bool) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if open:
		return out
	var fighting := {}
	for id: Variant in s.combat.get("scared", []):
		fighting["npc:" + str(id)] = true
	for id: String in s.combat.get("fighters", []):
		var npc := str(CombatRules.fighter(s, id).get("npc_id", ""))
		if not npc.is_empty():
			fighting["npc:" + npc] = true
	for t: Dictionary in MapSpots.of(s, data, map):
		var cell := Vector2i(int(t["x"]), int(t["y"]))
		if not fighting.has(str(t["ref"])) and (now.has(cell) or str(t["kind"]) in ["station", "prop", "thing"]):
			out.append(t)
	out.append_array(MapSpots.crowd(s))
	return out


## The bodies on the map: those the hero sees, dim those it only hears, an invisible one where it was last seen.
func _bodies(s: GameSession, now: Dictionary, open: bool) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var cur := CombatRules.current(s)
	for id: String in s.combat.get("fighters", []):
		var f := CombatRules.fighter(s, id)
		var status := str(f.get("status", "active"))
		if status in ["gone", "fled", "away", "left"]:
			continue
		var at := FightGrid.shown(f)
		var hero := id == CombatRules.PLAYER
		var heard := not hero and status == "active" and FightGrid.heard(s, Catalog.data, f)
		if not open and not hero and not now.has(at) and not heard:
			continue
		var side := str(f.get("side", "enemy"))
		var nm := str(f.get("name", s.character.get("name", "?")))
		var tail := nm.get_slice(" ", nm.get_slice_count(" ") - 1)
		out.append({"id": id, "ref": "fight:" + id, "mark": nm.left(1) if hero else Look.token(f, nm) + (tail if tail.is_valid_int() else ""), "name": nm,
			"portrait": PortraitRules.of(s, Catalog.data, f),
			"colour": UiTheme.ACCENT_BRIGHT if hero else UiTheme.OK if side == "ally" else UiTheme.BAD,
			"span": int(f.get("span", 1)), "x": at.x, "y": at.y, "hp": int(s.character["hp"]) if hero else int(f.get("hp", 0)),
			"most": int(s.character["max_hp"]) if hero else int(f.get("max_hp", 1)), "out": status != "active" or (hero and int(s.character["hp"]) <= 0),
			"now": id == cur, "dim": bool(f.get("hidden", false)) or heard, "gear": AnimRules.gear(s, Catalog.data, f), "states": AnimRules.states(s, Catalog.data, f),
			"shares": FightGrid.shares(s, Catalog.data, f)})  # a swarm in another's square: drawn small in its corner (v0.8.4.27.1)
	# In the order of drawing: those who lie first, the living over them, the hero last (the author, 2026-11-13: the hero
	# standing on a body was drawn under it).
	var rank := func(b: Dictionary) -> int: return 2 if str(b["id"]) == CombatRules.PLAYER else 0 if bool(b["out"]) else 1
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return rank.call(a) < rank.call(b))
	return out


## The fighter on a square, "" — nobody: the first of `_ids_at`.
func _id_at(cell: Vector2i) -> String:
	var ids := _ids_at(cell)
	return ids[0] if not ids.is_empty() else ""


## The fighters on a square, the one a click means first: one on its feet (a swarm in the hero's square — the swarm,
## v0.8.4.27.1), then the hero, then those who lie (v0.8.4.42.20, the author: the hero on a body could not cast on itself,
## the body took the click).
func _ids_at(cell: Vector2i) -> Array[String]:
	var up: Array[String] = []
	var hero: Array[String] = []
	var down: Array[String] = []
	for f: Dictionary in _field.fighters:
		if FightGrid.body_at(Vector2i(int(f["x"]), int(f["y"])), int(f["span"])).has(cell):
			if str(f["id"]) == CombatRules.PLAYER:
				hero.append(CombatRules.PLAYER)
			else:
				(down if bool(f.get("out", false)) else up).append(str(f["id"]))
	return up + hero + down


## The target of the picked act on a square: the first there it may go at, else the first there ("" — nobody).
func _target_at(cell: Vector2i) -> String:
	var ids := _ids_at(cell)
	for id: String in ids:
		if str(_pending_check.call(id)).is_empty():
			return id
	return ids[0] if not ids.is_empty() else ""


## Shift + a click walks onto the square whoever or whatever lies there (v0.8.4.42.20, the author).
static func onto() -> bool:
	return Input.is_key_pressed(KEY_SHIFT)


## A click on the field: the picked act goes at the square or the body, a foe opens its acts, else the hero walks.
func on_cell(cell: Vector2i) -> void:
	if not mine():
		return
	var s := GameState.session
	var data := Catalog.data
	var id := _id_at(cell)
	if not _second.is_empty():
		if _field.lit.has(cell):
			_do(GameState.combat_act(str(_second["act"]), str(_second["to"]), {"at": FightGrid.aim_id(cell)}))
		return
	if _pending.is_valid():
		var target := FightGrid.aim_id(cell) if not _pending_aim.is_empty() else _target_at(cell)
		if not target.is_empty():
			_aim(target)
		return
	if onto() and _field.routes.has(cell):
		_do(GameState.combat_act("walk", FightGrid.aim_id(cell)))
		return
	if not id.is_empty() and str(CombatRules.fighter(s, id).get("side")) == "enemy":
		_foe_menu(id)
		return
	if not id.is_empty() and id != CombatRules.PLAYER:  # one of the hero's side: its card (v0.8.4.41)
		EventBus.card_requested.emit(id)
		return
	var way := _way_out_at(s, data, cell)
	if way != FightGrid.NONE:
		if way == FightGrid.cell(GameState.fight_actor()):
			_do(GameState.combat_act("flee"))
		else:
			_do(GameState.combat_act("walk", FightGrid.aim_id(way)))
		return
	if _field.routes.has(cell):
		_do(GameState.combat_act("walk", FightGrid.aim_id(cell)))


## The right button lets the picked act go.
func on_right(_cell: Vector2i) -> void:
	cancel()


## A fighter picked by its portrait — in the queue, the fight's list or the hotbar (v0.8.4.43.8, as in BG3): the picked act
## goes at it as at its token (an area at its square), else what a click on its token does — a foe's menu, an ally's card.
func on_fighter(id: String) -> void:
	if id.is_empty() or not _second.is_empty():
		return
	var f := CombatRules.fighter(GameState.session, id)
	if _pending.is_valid() and mine():
		_aim(_target_of(id))
	elif str(f.get("side")) == "enemy":
		if mine():
			_foe_menu(id)
	elif id != CombatRules.PLAYER:  # an ally's card is a look, free at any turn
		EventBus.card_requested.emit(id)


## What the picked act aims at for a fighter: its square for an area, else the fighter.
func _target_of(id: String) -> String:
	return FightGrid.aim_id(FightGrid.shown(CombatRules.fighter(GameState.session, id))) if not _pending_aim.is_empty() else id


## The picked act at `target` (a fighter or a square): the one road of a click on a token and on a portrait.
func _aim(target: String) -> void:
	var why := str(_pending_check.call(target))
	if not why.is_empty():
		EventBus.message.emit(tr(why))
		return
	_press(target)


## The mouse over a fighter's portrait (v0.8.4.43.8): its token ringed on the map, the hint says what the picked act would
## do to it — its chance, the area and who is caught, or why not; "" — the mouse left it.
func point_at(id: String) -> void:
	if not active():
		return
	var s := GameState.session
	_field.blast = {}
	_field.way = []
	if id.is_empty():
		_field.pointed = FightGrid.NONE
		_hint.text = _base_hint(mine())
	else:
		var cell := FightGrid.shown(CombatRules.fighter(s, id))
		_field.pointed = cell
		var text := _about(s, Catalog.data, cell, id)
		_hint.text = text if not text.is_empty() else _name_of(s, id)
	_field.queue_redraw()


## What the picked act would do at `id` on `cell`: the area and who is caught, its chance, or why not; "" — no act picked.
func _about(s: GameSession, data: Dictionary, cell: Vector2i, id: String) -> String:
	if not _pending.is_valid():
		return ""
	if not _pending_aim.is_empty():
		return _aim_hint(s, data, cell, id, _base_hint(mine()))
	if id.is_empty():
		return ""
	return "%s: %s" % [_name_of(s, id), _said_at(id).replace("\n", " · ")]


## What the picked act says at `id`: why not, its chance or what it gives, else the act's own caption.
func _said_at(id: String) -> String:
	var why := str(_pending_check.call(id))
	var said := tr(why) if not why.is_empty() else _preview_text(_pending_preview.call(id))
	return said if not said.is_empty() else _pending_text


## The square before the way out shown at `cell`, FightGrid.NONE — no way out there.
func _way_out_at(s: GameSession, data: Dictionary, cell: Vector2i) -> Vector2i:
	for e: Dictionary in FightGrid.map(s, data).get("exits", []):
		if Vector2i(int(e["x"]), int(e["y"])) == cell:
			return Vector2i(int(e["ax"]), int(e["ay"]))
	return FightGrid.NONE


## The acts at a foe clicked on the map (v0.8.4.3, the author): the tabs' own, as a context menu with lists inside: a tab,
## then a spell's circle. Nothing is done by the click itself. What cannot reach it now is grey with why; what is not for a
## foe at all is not shown.
func _foe_menu(id: String) -> void:
	if _pop != null:
		remove_child(_pop)
		_pop.queue_free()
	var f := CombatRules.fighter(GameState.session, id)
	var aim := FightGrid.aim_id(FightGrid.shown(f))
	_pop = ActsMenu.new()
	_pop.name = "FoeMenu"
	add_child(_pop)
	_pop.add_separator(str(f.get("name", "")))
	_pop.add_act(_pop, tr("BTN_CARD"), tr("BTN_CARD_TIP"), false, _foe_pick.bind(func(to: String) -> String:  # v0.8.4.41: its card,
		EventBus.card_requested.emit(to)  # free — a look is no act
		return "", id))
	for row: Dictionary in _acts:
		var target := aim if not str(row["aims"]).is_empty() else id
		var why := str((row["check"] as Callable).call(target))
		if not bool(row["on"]) or why == "COMBAT_BAD_TARGET":
			continue
		_pop.add_act(_pop.list_of([tr(str(row["tab"])), str(row["sub"])]), str(row["text"]),
			tr(why) if not why.is_empty() else _preview_text((row["preview"] as Callable).call(target)), not why.is_empty(), _foe_pick.bind(row["act"], target))
	var cell := FightGrid.shown(f)
	_pop.popup(Rect2i(Vector2i(_field.get_screen_position() + _field.cell_point(cell) + Vector2(_field.tile() / 2.0, 0)), Vector2i.ZERO))


func _foe_pick(act: Callable, target: String) -> void:
	_pending = act
	_press(target)


## The mouse over a square: the path and its cost, the area of the picked spell, what a blow would do.
func on_hover(cell: Vector2i) -> void:
	if not active():
		return
	var s := GameState.session
	var data := Catalog.data
	var me := mine()
	var id := _target_at(cell) if _pending.is_valid() else _id_at(cell)
	var text := _base_hint(me)
	_field.blast = {}
	_field.way = []
	var about := _about(s, data, cell, id)
	if not about.is_empty():
		text = about
	elif onto() and _field.routes.has(cell):
		_field.way = FightGrid.route(_field.routes, cell)
		text = tr("COMBAT_WALK_COST").format({"ft": int(_field.routes[cell][0]) * int(FightGrid.cfg(data)["ft"])})
	elif not id.is_empty() and str(CombatRules.fighter(s, id).get("side")) == "enemy":
		text = _name_of(s, id)
	elif _field.routes.has(cell):
		_field.way = FightGrid.route(_field.routes, cell)
		text = tr("COMBAT_WALK_COST").format({"ft": int(_field.routes[cell][0]) * int(FightGrid.cfg(data)["ft"])})
	elif _way_out_at(s, data, cell) != FightGrid.NONE:
		text = tr("COMBAT_WAY_OUT")
	_hint.text = text
	_field.queue_redraw()


func _name_of(s: GameSession, id: String) -> String:
	return str(CombatRules.fighter(s, id).get("name", s.character.get("name", "")))


func _foe_hint(s: GameSession, data: Dictionary, id: String) -> String:
	var me := GameState.fight_actor()  # the hero's main blow, or the blow of the one of the party in its turn
	var reach := Acts.one("attack").can(s, data, me, id)
	if reach in ["COMBAT_OUT_OF_REACH", "COMBAT_OUT_OF_RANGE", "COMBAT_NO_LINE"]:
		return tr(reach)
	return _preview_text(CombatRules.blow_preview(s, data, me, id, {})).replace("\n", " · ")


## The area of the picked spell under the mouse: its squares lit, who is caught in them.
func _aim_hint(s: GameSession, data: Dictionary, cell: Vector2i, id: String, text: String) -> String:
	var aim := FightGrid.aim_id(cell)
	var why := str(_pending_check.call(aim))
	if not why.is_empty():
		return tr(why)
	var sp: Dictionary = data["spells"].get(_pending_aim, {})
	var cells: Array[Vector2i] = []
	if sp.has("area"):
		cells = CombatRules.area_cells(s, data, sp, CombatRules.aimed(s, aim))
	elif FeatureRules.aims(data, _pending_aim):  # a feature laid as an area: a dragonborn's breath (v0.8.4.24)
		cells = FeatureRules.aim_cells(s, data, GameState.fight_actor(), _pending_aim, aim)
	else:
		return text
	var caught: Array[String] = []
	for at: Vector2i in cells:
		_field.blast[at] = true
	for f: Dictionary in _field.fighters:
		if not bool(f["out"]) and FightGrid.in_cells(CombatRules.fighter(s, str(f["id"])), cells):
			caught.append(str(f["name"]))
	var pv := _preview_text(_pending_preview.call(id)).replace("\n", " · ") if not id.is_empty() else ""
	return tr("COMBAT_AREA_CAUGHT").format({"names": ", ".join(caught) if not caught.is_empty() else "—"}) + ("  " + pv if not pv.is_empty() else "")


## The picked act goes at `target`.
func _press(target: String) -> void:
	var act := _pending
	_pending = Callable()
	_do(str(act.call(target)))


## The animations of what just happened (v0.7.22.14, CombatFx): the engine's events (a dodge, a crit, a spell) and
## the difference from the last refresh — HP down is a hit, up a heal, out of the fight — down.
var _last_fx: Dictionary = {}


func _play_fx(s: GameSession) -> void:
	var snap := {CombatRules.PLAYER: {"hp": int(s.character.get("hp", 0)), "down": int(s.character.get("hp", 0)) <= 0}}
	for id: String in CombatRules.enemies(s, false):
		var f := CombatRules.fighter(s, id)
		snap[id] = {"hp": int(f.get("hp", 0)), "down": str(f.get("status")) != "active"}
	_anims.speed = SaveManager.combat_delay() / FightAnims.NORMAL_DELAY if not GameState.instant_walk else 0.0
	_anims.play(AnimRules.take(s))
	var kinds := {}
	for e: Dictionary in CombatRules.take_fx(s):
		var list: Array = kinds.get(str(e["who"]), [])
		list.append(str(e["kind"]))
		kinds[str(e["who"])] = list
	for id: String in snap:
		if not _last_fx.has(id):
			continue
		var was: Dictionary = _last_fx[id]
		var now: Dictionary = snap[id]
		var list: Array = kinds.get(id, [])
		if int(now["hp"]) < int(was["hp"]) and not list.has("crit"):
			list.append("hit")
		elif int(now["hp"]) > int(was["hp"]):
			list.append("heal")
		if bool(now["down"]) and not bool(was["down"]):
			list.append("down")
		if not list.is_empty():
			kinds[id] = list
	var deltas := {}
	for id: String in snap:
		if _last_fx.has(id) and int(snap[id]["hp"]) != int(_last_fx[id]["hp"]):
			deltas[id] = int(snap[id]["hp"]) - int(_last_fx[id]["hp"])
	_last_fx = snap
	if not deltas.is_empty():
		_numbers(deltas)
	for who: String in kinds:
		var node := _portrait_of(who)
		for k: Variant in kinds[who]:
			CombatFx.play(node, str(k))


## After the redraw is laid out: «−6» over the body that lost HP, «+4» over the one healed (П9).
func _numbers(deltas: Dictionary) -> void:
	await get_tree().process_frame
	for id: String in deltas:
		var pin := _pin(id)
		CombatFx.number(_fx_layer, pin, int(deltas[id]))
		get_tree().create_timer(1.5).timeout.connect(pin.queue_free)


## An empty box on the body of the fighter: the number flies from it. A body off the view — from the line of the list.
func _pin(id: String) -> Control:
	var pin := Control.new()
	pin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_layer.add_child(pin)
	var at := FightGrid.NONE
	for f: Dictionary in _field.fighters:
		if str(f["id"]) == id:
			at = Vector2i(int(f["x"]), int(f["y"]))
	var card := _portrait_of(id)
	pin.size = Vector2(_field.tile(), _field.tile())
	if at != FightGrid.NONE:
		pin.global_position = _field.global_position + _field.cell_point(at) - pin.size / 2.0
	elif card != null:
		pin.global_position = card.global_position
	return pin


func _base_hint(me: bool) -> String:
	if not _second.is_empty():
		return tr("COMBAT_PICK_JUMP" if str(_second["to"]).is_empty() else "COMBAT_PICK_SIDE")
	var who := GameState.fight_actor()
	if me and not _pending.is_valid() and Move.why(GameState.session, Catalog.data, who) == "COMBAT_PRONE":
		return tr("COMBAT_PRONE")
	if _pending.is_valid():
		return tr("COMBAT_PICK_TARGET")
	if me and not Sheet.is_hero(who):  # one of the party in its turn (v0.8.4.43.11)
		return tr("COMBAT_TURN_OF").format({"name": str(who.get("name", ""))})
	return tr("COMBAT_YOUR_TURN") if me else tr("COMBAT_WAIT")


## The hint text: «Попадание 65% · урон 4–11» (or the chance the foe fails its save), why advantage / disadvantage.
func _preview_text(pv: Dictionary) -> String:
	if pv.is_empty():
		return ""
	if bool(pv.get("heal", false)):
		return tr("HINT_HEAL").format({"min": int(pv["min"]), "max": int(pv["max"])})
	if pv.has("condition"):
		if bool(pv.get("immune", false)):
			return tr("HINT_IMMUNE")
		if bool(pv.get("pool", false)):
			return tr("HINT_POOL").format({"min": int(pv["min"]), "max": int(pv["max"]), "cond": pv["condition"]})
		return tr("HINT_COND").format({"p": int(pv["chance"]), "cond": pv["condition"]})
	var t := tr("HINT_SAVE" if bool(pv.get("save", false)) else "HINT_HIT").format({"p": int(pv["chance"]), "min": int(pv["min"]), "max": int(pv["max"])})
	if int(pv.get("count", 1)) > 1:
		t += " ×%d" % int(pv["count"])
	if bool(pv.get("half", false)):
		t += tr("HINT_HALF")
	if bool(pv.get("sneak", false)):
		t += tr("HINT_SNEAK")
	if not (pv.get("adv", []) as Array).is_empty():
		t += "\n" + tr("HINT_ADV").format({"why": ", ".join(pv["adv"])})
	if not (pv.get("dis", []) as Array).is_empty():
		t += "\n" + tr("HINT_DIS").format({"why": ", ".join(pv["dis"])})
	return t


## The queue as portraits (Б4, П3): the current one larger and first, then the order; the colour of the frame is the
## side (foes red). Its face (PortraitRules, v0.8.4.43.5.2), else the token of its look; a bar of its HP under it, as in BG3.
## The foes are here and on the map only (v0.8.4.43.10): the left column is the hero's party.
func _draw_queue(s: GameSession) -> void:
	_clear(_queue)
	var cur := CombatRules.current(s)
	_chip(_queue, tr("COMBAT_ROUND").format({"n": int(s.combat.get("round", 1))}), false, true)
	var order: Array = s.combat.get("order", [])
	var at := maxi(0, order.find(cur))
	for k in order.size():
		var id := str(order[(at + k) % order.size()])
		var f := CombatRules.fighter(s, id)
		if str(f.get("status", "active")) in ["gone", "left", "away"]:
			continue
		_face(s, id, f, id == cur, str(f.get("status", "active")) != "active")


func _face(s: GameSession, id: String, f: Dictionary, now: bool, out: bool) -> void:
	var data := Catalog.data
	var side := str(f.get("side", "enemy"))
	var col := UiTheme.ACCENT_BRIGHT if side == "player" else UiTheme.OK if side == "ally" else UiTheme.BAD
	var p := Button.new()
	p.name = "Turn_" + id
	p.set_meta("out", out)
	p.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	p.focus_mode = Control.FOCUS_ALL  # Tab walks the foes' faces
	var frame := UiTheme.box(UiTheme.PANEL_RAISED if now else UiTheme.PANEL, col if not out else UiTheme.MUTED, 3 if now else 2, 4, 8)
	for st: String in ["normal", "hover", "pressed", "disabled", "hover_pressed"]:
		p.add_theme_stylebox_override(st, frame)
	p.add_theme_stylebox_override("focus", UiTheme.box(Color.TRANSPARENT, UiTheme.ACCENT_BRIGHT, 2, 0, 8))
	p.custom_minimum_size = Vector2(64, 64) if now else Vector2(46, 46)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.tooltip_text = _face_tip(s, data, id, f)
	var l := Label.new()
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nm := str(f["name"])
	var tail := nm.get_slice(" ", nm.get_slice_count(" ") - 1)
	l.text = Look.token(f, nm) + (tail if tail.is_valid_int() else "")  # «В1», «В2» for the numbered ones
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 32 if now else 22)
	l.add_theme_color_override("font_color", UiTheme.MUTED if out else col)
	var pic := Portrait.square(PortraitRules.of(s, data, f), 0.0, out)
	if pic != null:
		p.add_child(pic)
		_fill(pic, 3)
		if l.text.right(1).is_valid_int():  # «В2»: the number stays over the face
			l.text = l.text.substr(1)
			l.add_theme_font_size_override("font_size", 16)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
			l.add_theme_constant_override("outline_size", 4)
			l.add_theme_color_override("font_outline_color", UiTheme.BG)
			p.add_child(l)
			_fill(l, 4)
		else:
			l.free()
	else:
		p.add_child(l)
		_fill(l, 3)
	if not out:  # its health at a glance, as BG3's queue shows it
		var bar := UiParts.hp_bar(Sheet.hp(s, data, f), Sheet.max_hp(s, data, f), 5.0, 1)
		bar.name = "FaceHp"
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(bar)
		bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		bar.offset_left = 4
		bar.offset_right = -4
		bar.offset_top = -9
		bar.offset_bottom = -4
	if bool(f.get("hidden", false)) and not out:
		CombatFx.look(p, "hidden")
	if side == "enemy":  # what it is, in the card at the cursor (big test #35)
		var about := _foe_about(s, data, f)
		p.mouse_entered.connect(func() -> void: _details.show_text(nm, about))
	_targets(p, id, out)  # v0.8.4.43.8: a target by its portrait, as in BG3
	_queue.add_child(p)
	if now:
		var name_l := Label.new()
		name_l.name = "TurnName"
		name_l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		name_l.text = str(f["name"])
		name_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		name_l.add_theme_color_override("font_color", col)
		_queue.add_child(name_l)


## A child of a face fills it, `inset` pixels in from the frame.
static func _fill(c: Control, inset: int) -> void:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.offset_left = inset
	c.offset_top = inset
	c.offset_right = -inset
	c.offset_bottom = -inset


## The line of a face: the name; of a foe its health, its numbers once known, its conditions, what the main blow would do.
func _face_tip(s: GameSession, data: Dictionary, id: String, f: Dictionary) -> String:
	var lines: Array[String] = [str(f["name"])]
	if str(f.get("side", "")) != "enemy":
		return lines[0]
	lines.append(tr(CombatRules.health_key(f)))
	if not CombatRules.monster_card(s, data, f).is_empty():
		lines.append("HP %d/%d · КД %d" % [int(f["hp"]), int(f["max_hp"]), CombatRules.ac_of(f)])
	var conds: Array = CombatRules.foe_conditions(s, data, f)
	if bool(f.get("surprised", false)):
		conds.append(tr("COMBAT_FOE_SURPRISED"))
	if not conds.is_empty():
		lines.append(", ".join(conds))
	if str(f.get("status")) == "active" and not _pending.is_valid():
		var hint := _foe_hint(s, data, id)
		if not hint.is_empty():
			lines.append(hint)
	return "\n".join(lines)


## What a foe is: what the hero knows of its kind, its faction, its own words.
func _foe_about(s: GameSession, data: Dictionary, f: Dictionary) -> String:
	var lore := CombatRules.monster_card(s, data, f)
	var about := lore if not lore.is_empty() else tr("COMBAT_FOE_UNKNOWN")
	var fa := FactionRules.def(s, data, FactionRules.of_foe(data, SceneRules.room(s, data["world"], s.room_id).get("encounter", {}), f))  # v0.7.50
	if not fa.is_empty():
		about += "\n\n" + tr("COMBAT_FOE_FACTION").format({"name": fa["name"]})
	if not str(f.get("desc", "")).is_empty():
		about += "\n\n" + str(f["desc"])
	return about


## A portrait of a fighter as a target (v0.8.4.43.8): the mouse over it rings its token and says the chance, a click aims the
## picked act at it (on_fighter).
func _targets(c: BaseButton, id: String, out: bool) -> void:
	c.mouse_entered.connect(point_at.bind(id))
	c.mouse_exited.connect(point_at.bind(""))
	c.pressed.connect(on_fighter.bind(id))
	_target_look(c, id, out)


## A fighter's portrait while an act is picked: grey with why when the act cannot go at it, its line says why or what it gives.
func _target_look(c: Control, id: String, out: bool) -> void:
	if not _pending.is_valid() or out:
		return
	var why := str(_pending_check.call(_target_of(id)))
	if not why.is_empty():
		c.modulate = Color(1, 1, 1, 0.42)
	if not why.is_empty() or _pending_aim.is_empty():
		c.tooltip_text = "%s\n%s" % [c.tooltip_text, tr(why) if not why.is_empty() else _said_at(id)]


func _chip(parent: Control, text: String, now: bool, dim: bool) -> void:
	var p := PanelContainer.new()
	p.theme_type_variation = UiTheme.CARD
	var l := Label.new()
	l.text = text
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	if now:
		l.add_theme_color_override("font_color", UiTheme.ACCENT_BRIGHT)
	elif dim:
		l.add_theme_color_override("font_color", UiTheme.MUTED)
	p.add_child(l)
	parent.add_child(p)


## The party column in a fight (v0.8.4.43.10): the same as out of it; the one whose turn it is lit, each a target of the
## picked act.
func _draw_party(s: GameSession) -> void:
	_party.now = CombatRules.current(s)
	_party.refresh(func(p: Portrait, id: String) -> void:
		var f := CombatRules.fighter(s, id)
		_target_look(p, id, not Sheet.is_hero(f) and not str(f.get("status", "")) in ["active", "down"]))


## Who is on the way: the reinforcements and the round they come in.
func _draw_incoming(s: GameSession) -> void:
	_clear(_incoming)
	for w: Dictionary in s.combat.get("incoming", []):
		var ghost := Label.new()
		ghost.name = "Incoming"
		ghost.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		ghost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ghost.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ghost.add_theme_color_override("font_color", UiTheme.MUTED)
		ghost.text = tr("COMBAT_INCOMING").format({"names": "\n".join(w["names"]), "n": maxi(1, int(w["at"]) - int(s.combat.get("round", 1)))})
		_incoming.add_child(ghost)


## A fighter's portrait on the screen: its face in the party column, else in the queue (an animation plays on it).
func _portrait_of(id: String) -> Control:
	var key := "hero" if id == CombatRules.PLAYER else id
	var p := _party.find_child("Portrait_" + key, true, false) as Control
	return p if p != null else _queue.find_child("Turn_" + id, true, false) as Control


func _line(parent: Control, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)
	return l


func _draw_actions(s: GameSession, data: Dictionary, me: bool) -> void:
	_acts.clear()
	_throws.clear()
	_redrawing = true  # removing the pages switches the tab: the player's pick is kept by its title
	if ArenaRules.watching(s):  # v0.8.4.5: from the fence nothing is in the hero's hands
		_bar.clear_fight()
		var note := Label.new()
		note.name = "WatchNote"
		note.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		note.text = tr("COMBAT_WATCHING").format({"name": str(s.combat["arena"]["pick"])})
		_tab_box("COMBAT_TAB_WATCH").add_child(note)
		_bar.tidy()
		_redrawing = false
		return
	_bar.clear_fight()
	var who := GameState.fight_actor()
	var c := Sheet.holder(s, who)
	if not Sheet.is_hero(who):  # one of the party in its turn: its template's blows and spells (v0.8.4.43.11)
		_draw_companion(s, data, who, me)
	else:
		_draw_hero(s, data, me)
	_draw_shared(s, data, who, c, me)
	_bar.tidy()  # the open filter is kept by its key however the sections changed
	_redrawing = false


## The hero's weapons by its hands and its spells by its sheet.
func _draw_hero(s: GameSession, data: Dictionary, me: bool) -> void:
	var c := s.character
	# Weapons.
	var w := _tab_box("COMBAT_TAB_WEAPONS")
	var vol := CombatRules.volley(s)
	if not vol.is_empty():  # v0.7.22.4: the next dart or ray — pick its target (armed at once)
		var vname := str(data["spells"][str(vol["spell"])]["name"])
		var vb := _action(w, "Volley", tr("COMBAT_VOLLEY").format({"spell": vname, "n": int(vol["left"])}), me,
			func(t: String) -> String: return GameState.combat_act("volley", t),
			func(t: String) -> String: return Acts.one("volley").can(s, data, CombatRules.player(s), t), func(_t: String) -> Dictionary: return {}, "",
			int(data["spells"][str(vol["spell"])].get("range_ft", 0)))
		vb.theme_type_variation = UiTheme.ACCENT_BUTTON
	var main := CombatRules.weapon_profile(c, data, s.items, str(c.get("equipped", {}).get("main_hand", "")))
	var main_id := str(c.get("equipped", {}).get("main_hand", ""))
	var main_b := _action(w, "Attack_main", tr("COMBAT_ATTACK").format({"name": main["name"], "hit": "%+d" % int(main["to_hit"]), "dmg": _dmg_text(main)}), me,
		func(t: String) -> String: return GameState.combat_act("attack", t),
		func(t: String) -> String: return Acts.one("attack").can(s, data, CombatRules.player(s), t),
		func(t: String) -> Dictionary: return CombatRules.attack_preview(s, data, t, false), "", _blow_far(main))
	if not main_id.is_empty():
		_details.hook(main_b, str(main["name"]), "", CardInfo.item(c, data, s.items, main_id))
	if Attack.throwable(Attack.of_weapon(main)):  # v0.8.4.31: a dagger or a spear thrown, it leaves the hand
		_throw("Throw_main", main_id, tr("COMBAT_THROW").format({"name": main["name"], "hit": "%+d" % int(main["to_hit"]), "dmg": _dmg_text(main)}), me,
			func(t: String) -> String: return GameState.combat_act("attack", t, {"throw": true}),
			func(t: String) -> String: return Acts.one("attack").can(s, data, CombatRules.player(s), t, {"throw": true}),
			func(t: String) -> Dictionary: return CombatRules.attack_preview(s, data, t, false, false, true), "", _far(main))
	var fists := _strikes(s, data, c, w, me, main, main_id)
	if not main_id.is_empty() and not fists:  # fists with a weapon in hand (v0.7.22.11, big test #45), unless «Атака» is them
		var fist := CombatRules.weapon_profile(c, data, s.items, "")
		_action(w, "Attack_unarmed", tr("COMBAT_ATTACK").format({"name": fist["name"], "hit": "%+d" % int(fist["to_hit"]), "dmg": _dmg_text(fist)}), me,
			func(t: String) -> String: return GameState.combat_act("attack", t, {"hand": "fists"}),
			func(t: String) -> String: return Acts.one("attack").can(s, data, CombatRules.player(s), t, {"hand": "fists"}),
			func(t: String) -> Dictionary: return CombatRules.attack_preview(s, data, t, false, true))
	var off := CharacterRules.off_weapon(c.get("equipped", {}), data, s.items)  # a shield there strikes not
	if not off.is_empty():
		var ow := CombatRules.weapon_profile(c, data, s.items, off, true)
		_action(w, "Attack_off", tr("COMBAT_ATTACK_OFF").format({"name": ow["name"], "dmg": _dmg_text(ow)}), me,
			func(t: String) -> String: return GameState.combat_act("attack", t, {"hand": "off"}),
			func(t: String) -> String: return Acts.one("attack").can(s, data, CombatRules.player(s), t, {"hand": "off"}),
			func(t: String) -> Dictionary: return CombatRules.attack_preview(s, data, t, true), "", _blow_far(ow))
		if Attack.throwable(Attack.of_weapon(ow)):
			_throw("Throw_off", off, tr("COMBAT_THROW_OFF").format({"name": ow["name"], "dmg": _dmg_text(ow)}), me,
				func(t: String) -> String: return GameState.combat_act("attack", t, {"hand": "off", "throw": true}),
				func(t: String) -> String: return Acts.one("attack").can(s, data, CombatRules.player(s), t, {"hand": "off", "throw": true}),
				func(t: String) -> Dictionary: return CombatRules.attack_preview(s, data, t, true, false, true), "", _far(ow))
	if bool(CombatRules.player(s).get("frenzy", false)):
		_action(w, "Attack_frenzy", tr("COMBAT_ATTACK_FRENZY").format({"name": main["name"], "dmg": _dmg_text(main)}), me,
			func(t: String) -> String: return GameState.combat_act("attack", t, {"hand": "frenzy"}),
			func(t: String) -> String: return Acts.one("attack").can(s, data, CombatRules.player(s), t, {"hand": "frenzy"}),
			func(t: String) -> Dictionary: return CombatRules.attack_preview(s, data, t, false), "", 0, "acts/frenzy")
	# Spells.
	if not SpellRules.ready(c).is_empty() and not Guise.has_body(c):
		var sp := _tab_box("COMBAT_TAB_SPELLS")
		for mm: Dictionary in FeatureRules.metamagic(c, data):  # v0.7.10: metamagic toggles of the next spell
			var mid := str(mm["id"])
			var cost := tr("META_COST_CIRCLE") if bool(mm["per_circle"]) else str(int(mm["cost"]))
			var mb := _button(sp, "Meta_" + mid, "✦ %s (%s)" % [mm["name"], cost], me and Stock.left(c, data, "sorcery_points") >= int(mm["cost"]))
			mb.toggle_mode = true
			mb.button_pressed = str(CombatRules.player(s).get("metamagic", "")) == mid
			mb.tooltip_text = tr("META_TIP_" + mid.to_upper())
			mb.pressed.connect(func() -> void: GameState.combat_metamagic(mid))
		for id: String in SpellRules.ready(c):
			var spell: Dictionary = data["spells"].get(id, {})
			var lv := int(spell.get("level", 0))
			var free := SpellRules.free_now(c, data, id)  # an invocation's spell at will (v0.7.22.4)
			var slot := 0 if lv == 0 or free else _slot_for(c, data, id)
			var cost := tr("COMBAT_BONUS_SHORT") if CombatRules.spell_cost(data, id) == "bonus" else ""
			var label := "%s%s%s%s" % [spell.get("name", id), (" (%d)" % slot) if slot > 0 else "", tr("SPELL_AT_WILL_SHORT") if free else "", cost]
			if lv > 0 and slot == 0 and not free:
				_disabled(sp, label, "spells/" + id)
				continue
			_act_sub = tr("DETAILS_CANTRIP") if lv == 0 else tr("DETAILS_CIRCLE").format({"n": lv})
			var ab := _spell_action(s, data, sp, "Cast_" + id, label, me, id,
				func(t: String) -> String: return GameState.combat_cast(id, slot, t),
				func(t: String) -> String: return Acts.one("cast").can(s, data, CombatRules.player(s), t, {"spell": id, "slot": slot}),
				func(t: String) -> Dictionary: return CombatRules.cast_preview(s, data, id, slot, t))
			_details.hook(ab, str(spell.get("name", id)), "", CardInfo.spell(data, id, slot, c))
		_act_sub = ""
		for sa: Dictionary in SpellEffects.actions(s, data):  # v0.7.13.5: the spells that go on each turn
			var said := str(sa["id"])
			var slabel := "%s%s" % [sa["name"], tr("COMBAT_BONUS_SHORT") if str(sa["cost"]) == "bonus" else ""]
			if bool(sa["target"]):
				var stb := _action(sp, "Feat_" + said, slabel, me, func(t: String) -> String: return GameState.combat_feature(said, t),
					func(t: String) -> String: return Acts.one("feature").can(s, data, CombatRules.player(s), t, {"id": said}), func(_t: String) -> Dictionary: return {})
				stb.tooltip_text = str(sa["tip"])
			else:
				var swhy := Acts.one("feature").can(s, data, CombatRules.player(s), "", {"id": said})
				var sub := _button(sp, "Feat_" + said, slabel, me and swhy.is_empty())
				sub.tooltip_text = str(sa["tip"])
				sub.pressed.connect(func() -> void: _do(GameState.combat_feature(said)))


## One of the hero's party in its turn (v0.8.4.43.11, as in BG3): its template's blows by what it holds (`Gear.actions`), a
## Multiattack one press; the spells its template casts (`MonsterRules.castable`) — the same the AI picks from, on the same acts.
func _draw_companion(s: GameSession, data: Dictionary, who: Dictionary, me: bool) -> void:
	var w := _tab_box("COMBAT_TAB_WEAPONS")
	for a: Dictionary in Sheet.template(data, who).get("actions", []):
		var kind := str(a.get("kind", ""))
		if not kind in ["melee", "ranged", "save"] or (kind == "save" and not MonsterRules.available(who, a)):
			continue
		var en := str(a["name_en"])
		var b := Attack.of_action(data, who, a)
		var n := FightAI.blows(data, who, a)
		var dmg := " + ".join((b["pieces"] as Array).map(func(p: Dictionary) -> String: return str(p["dice"]).replace("d", tr("DICE_D"))))
		var nm := str(a.get("name", en)) + (" ×%d" % n if n > 1 else "")
		var text := tr("COMBAT_ATTACK").format({"name": nm, "hit": "%+d" % int(b["to_hit"]), "dmg": dmg}) if kind != "save" else nm
		var rider := MonsterRules.effect_text(data, a)
		var icon := "items/" + str(a["item"]) if not str(a.get("item", "")).is_empty() else "acts/attack"
		var far := 0 if kind != "ranged" else int((a.get("range", [0, 0]) as Array)[1])
		for how: Dictionary in [{"action": en}, {"action": en, "throw": true}]:
			var thrown := bool(how.get("throw", false))
			if thrown and not (kind == "melee" and Attack.throwable(b)):
				continue
			if thrown:  # into the «Бросить» list (v0.8.4.43.49)
				_throw("BlowThrow_" + en, str(a.get("item", "")), tr("COMBAT_THROW").format({"name": nm, "hit": "%+d" % int(b["to_hit"]), "dmg": dmg}), me,
					func(t: String) -> String: return GameState.combat_act("attack", t, how),
					func(t: String) -> String: return Acts.one("attack").can(s, data, who, t, how),
					func(t: String) -> Dictionary: return CombatRules.blow_preview(s, data, who, t, how), "", int((a.get("range", [0, 0]) as Array)[1]))
				continue
			var cell := _action(w, "Blow_" + en, text, me,
				func(t: String) -> String: return GameState.combat_act("attack", t, how),
				func(t: String) -> String: return Acts.one("attack").can(s, data, who, t, how),
				func(t: String) -> Dictionary: return CombatRules.blow_preview(s, data, who, t, how), "", far, icon)
			_details.hook(cell, nm, text + ("\n" + rider if not rider.is_empty() else ""))
	var casts := MonsterRules.castable(data, who)
	if casts.is_empty() or Guise.has_body(who):
		return
	var sp := _tab_box("COMBAT_TAB_SPELLS")
	for o: Dictionary in casts:
		var id := str(o["id"])
		var spell: Dictionary = data["spells"][id]
		var slot := int(o["slot"])
		var how := {"spell": id, "slot": slot, "per_day": bool(o.get("per_day", false))}
		var label := "%s%s%s" % [spell.get("name", id), (" (%d)" % slot) if slot > 0 else "", tr("COMBAT_BONUS_SHORT") if CombatRules.spell_cost(data, id) == "bonus" else ""]
		_act_sub = tr("DETAILS_CANTRIP") if int(spell.get("level", 0)) == 0 else tr("DETAILS_CIRCLE").format({"n": int(spell.get("level", 0))})
		var ab := _spell_action(s, data, sp, "Cast_" + id, label, me, id,
			func(t: String) -> String: return GameState.combat_act("cast", t, how),
			func(t: String) -> String: return Acts.one("cast").can(s, data, who, t, how),
			func(t: String) -> Dictionary: return ActionRules.as_by(s, data, who, id, {}, func() -> Dictionary: return CombatRules.cast_preview(s, data, id, slot, t)))
		_details.hook(ab, str(spell.get("name", id)), "", CardInfo.spell(data, id, slot, Sheet.holder(s, who)))
	_act_sub = ""


## What anybody of the bar has alike: its features and stocks, the things at hand, the common acts.
func _draw_shared(s: GameSession, data: Dictionary, who: Dictionary, c: Dictionary, me: bool) -> void:
	# Features: limited uses with an action of their own, then the feature actions (v0.7.10).
	var res := Stock.lines(c, data).filter(func(r: Dictionary) -> bool:
		return str(Stock.table(data, c).get(str(r["id"]), {}).get("combat_cost", "action")) != "never")
	var feats := FeatureRules.actions(s, data, who).filter(func(a: Dictionary) -> bool: return not Sheet.is_hero(who) or not str(a["id"]).begins_with("spell_"))
	if not res.is_empty() or not feats.is_empty():
		var fb := _tab_box("COMBAT_TAB_FEATURES")
		for fa: Dictionary in feats:
			var fid := str(fa["id"])
			var label := "%s%s" % [fa["name"], tr("COMBAT_BONUS_SHORT") if str(fa["cost"]) == "bonus" else ""]
			if bool(fa["target"]):
				var area := FeatureRules.aims(data, fid)
				var tb := _action(fb, "Feat_" + fid, label, me, func(t: String) -> String: return GameState.combat_feature(fid, t),
					func(t: String) -> String: return Acts.one("feature").can(s, data, who, t, {"id": fid}), func(_t: String) -> Dictionary: return {},
					fid if area else "", FeatureRules.aim_ft(s, data, who, fid) if area else 0)
				tb.tooltip_text = str(fa["tip"])
				_details.hook(tb, str(fa["name"]), str(fa["tip"]))
			else:
				var why := Acts.one("feature").can(s, data, who, "", {"id": fid})
				var ub := _button(fb, "Feat_" + fid, label, me and why.is_empty())
				ub.tooltip_text = str(fa["tip"]) + (("\n" + tr(why)) if not why.is_empty() and why != "COMBAT_NOT_YOUR_TURN" else "")
				_details.hook(ub, str(fa["name"]), str(fa["tip"]))
				ub.pressed.connect(func() -> void: _do(GameState.combat_feature(fid)))
		for r: Dictionary in res:
			var b := _button(fb, "Feature_" + str(r["id"]), "%s (%d/%d)" % [r["name"], r["left"], r["max"]], me and int(r["left"]) > 0)
			var rid := str(r["id"])
			_details.hook(b, str(r["name"]), "", CardInfo.feature(data, rid, c))
			b.pressed.connect(func() -> void: _do(GameState.combat_use_feature(rid)))
	# Items.
	var usable: Array[String] = []
	for id: String in ItemRules.at_hand(c, data, s.items):  # only the belt's and the worn things are at hand (v0.8.4.24, v0.8.4.26)
		var use := ItemRules.consumable(data, id, s.items) if not id.is_empty() else {}
		if not use.is_empty() and int(use.get("minutes", 0)) == 0:  # work of a while (a disguise) is not for a fight
			usable.append(id)
	if not usable.is_empty():
		var ib := _tab_box("COMBAT_TAB_ITEMS")
		for id: String in usable:
			var d := ItemRules.def_of(data["items"], s.items, id)
			var fx := ItemRules.consumable(data, id, s.items)
			var label := "%s ×%d" % [d.get("name", id), int(c["inventory"][id])]
			if ItemRules.charges_max(d) > 0:
				label = "%s (%d/%d)" % [d.get("name", id), ItemRules.charges_left(c, d, id), ItemRules.charges_all(c, d, id)]
			var sp_id := str(fx.get("spell", ""))
			var sp: Dictionary = data["spells"].get(sp_id, {})
			var item_btn: Button
			if fx.has("throw"):  # v0.7.12: flasks and the net at a foe
				var spills := ItemRules.spills(fx["throw"])  # v0.8.4: a flask goes on a square too
				var far := 60 if bool(fx["throw"].get("improvised", false)) else int(fx["throw"].get("range", 15))
				item_btn = _action(ib, "Item_" + id, label, me, func(t: String) -> String: return GameState.combat_act("throw", t, {"item": id}),
					func(t: String) -> String: return Acts.one("throw").can(s, data, who, t, {"item": id}), func(_t: String) -> Dictionary: return {}, id if spills else "", far)
				_throw("Item_" + id, id, label, me, func(t: String) -> String: return GameState.combat_act("throw", t, {"item": id}),
					func(t: String) -> String: return Acts.one("throw").can(s, data, who, t, {"item": id}), func(_t: String) -> Dictionary: return {}, id if spills else "", far, false)
			elif not sp_id.is_empty() and CombatRules.is_engine_spell(data, sp_id):  # v0.8.4.29.6: aimed as the spell is — a square, a friend, the chance
				var by := ItemRules.spell_numbers(c, data, s.items, id)
				item_btn = _spell_action(s, data, ib, "Item_" + id, label, me, sp_id,
					func(t: String) -> String: return GameState.combat_act("item_spell", t, {"item": id}),
					func(t: String) -> String: return Acts.one("item_spell").can(s, data, who, t, {"item": id}),
					func(t: String) -> Dictionary: return ActionRules.as_by(s, data, who, sp_id, by,
						func() -> Dictionary: return CombatRules.cast_preview(s, data, sp_id, int(by["level"]), t)))
			elif not sp_id.is_empty():
				item_btn = _button(ib, "Item_" + id, label, me)
				item_btn.pressed.connect(func() -> void: _do(GameState.combat_act("item_spell", "", {"item": id})))
			else:
				if ItemRules.is_potion(data, s.items, id) and str(CombatRules.cfg(data).get("potion_cost", "action")) == "bonus":
					label += tr("COMBAT_BONUS_SHORT")  # v0.7.22.3: a potion — a bonus action
				item_btn = _button(ib, "Item_" + id, label, me)
				item_btn.pressed.connect(func() -> void: _do(GameState.combat_act("use_item", "", {"item": id})))
			_details.hook(item_btn, str(d.get("name", id)), "", CardInfo.item(c, data, s.items, id))
	_throw_cell(_tab_box("COMBAT_TAB_WEAPONS"), me)
	# Common.
	var g := _tab_box("COMBAT_TAB_COMMON")
	for act: Act in Acts.on_tab(s, data, who, "common"):
		for row: Dictionary in act.buttons(s, data, who):
			_act_button(g, act, row, me)


## The button of a spell of the hero or of a thing (v0.8.4.29.6, one maker for the Spells and the Items tab): no target — a press
## casts it; a friend's pick, a square of an area or a jump, a foe — armed until the target with the roll's own chance. `cast`,
## `can` — Callable(target) -> String, `preview` — Callable(target) -> Dictionary.
func _spell_action(s: GameSession, data: Dictionary, box: Control, node: String, label: String, me: bool, id: String, cast: Callable, can: Callable, preview: Callable) -> Button:
	var spell: Dictionary = data["spells"].get(id, {})
	var side := SpellEffects.picks_side(data, id)  # v0.7.50.1: a choice of friends, or of either side
	var friends := side == "any" or (side == "friend" and (not CombatRules.allies(s, false).is_empty() or not Sheet.is_hero(GameState.fight_actor())))
	var alone := side == "friend" and not friends
	var jump := SpellEffects.spec(data, id).has("teleport")  # Misty Step: a square, not a body
	if not jump and (alone or not friends and spell.has("heal_at_slot") or not friends and SpellEffects.self_spell(data, id) \
			or int(spell.get("range_ft", 0)) == 0 and not spell.has("area") or not AllyRules.summon_spec(data, id).is_empty()):
		var b := _button(box, node, label, me)
		b.pressed.connect(func() -> void: _do(_conc_guard(id, func() -> String: return str(cast.call("")))))
		return b
	return _action(box, node, label, me, func(t: String) -> String: return _conc_guard(id, func() -> String: return str(cast.call(t))), can,
		func(t: String) -> Dictionary: return {} if FightGrid.is_aim(t) else preview.call(t),
		id if spell.has("area") or jump else "", int(spell.get("range_ft", 0)))


## The spell a pending button casts: a spell's own, a thing's (v0.8.4.29.6), a volley's.
func _pending_spell(s: GameSession, data: Dictionary) -> String:
	if _pending_name == "Volley":
		return str(CombatRules.volley(s).get("spell", ""))
	if _pending_name.begins_with("Item_"):
		return str(ItemRules.consumable(data, _pending_name.trim_prefix("Item_"), s.items).get("spell", ""))
	return _pending_name.trim_prefix("Cast_")


## The picked circle when it fits the spell and has a slot left, else the lowest that fits.
func _slot_for(c: Dictionary, data: Dictionary, id: String) -> int:
	if _bar.picked_circle >= maxi(1, SpellRules.level_of(data, id)) and SpellRules.slots_left(c, _bar.picked_circle) > 0:
		return _bar.picked_circle
	return SpellRules.lowest_slot(c, data, id)


func _dmg_text(w: Dictionary) -> String:
	var b := int(w["bonus"])
	return "%s%s" % [str(w["dice"]).replace("d", tr("DICE_D")), ("%+d" % b) if b != 0 else ""]


## A section of the hotbar by its title key (v0.8.4.43): the cells of one kind, its filter beside.
func _tab_box(title: String) -> Container:
	_act_tab = title
	_act_sub = ""
	return _bar.section(title)


## A button of the fight: in a section of the hotbar a cell with its icon and short name (v0.8.4.43) — the whole line,
## its chance and why not in the tooltip; elsewhere (a friend's pick, a question) a plain button.
func _button(parent: Control, node_name: String, text: String, enabled: bool, icon := "") -> Button:
	var b: Button
	if str(parent.name).begins_with("Section_"):
		var look := _icon_of(node_name, text) if icon.is_empty() else [icon, text.get_slice(" (", 0).trim_suffix(tr("COMBAT_BONUS_SHORT"))]
		var cell := IconSlot.make(str(look[0]), str(look[1]), ActionBar.CELL)
		cell.tooltip_text = text
		if text.ends_with(tr("COMBAT_BONUS_SHORT")):
			cell.cost = "bonus"
		var count := RegEx.create_from_string("(\\d+/\\d+)\\)|×(\\d+)").search(text)  # charges or uses «(1/3)», a stack «×2»
		if count != null:
			cell.badge = count.get_string(1) if count.get_string(1) != "" else "×" + count.get_string(2)
		b = cell
	else:
		b = Button.new()
		b.text = text
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		b.custom_minimum_size = Vector2(0, 52)
	if not node_name.is_empty():
		b.name = node_name
	b.disabled = not enabled
	parent.add_child(b)
	return b


## [icon ref, short name] of a cell by its node: what a weapon blow strikes with, the spell, the thing, the feature.
func _icon_of(node_name: String, text: String) -> Array:
	var s := GameState.session
	var data := Catalog.data
	var c := Sheet.holder(s, GameState.fight_actor())
	var kind := node_name.get_slice("_", 0)
	var rest := node_name.trim_prefix(kind + "_")
	var short := text.get_slice(" (", 0).trim_suffix(tr("COMBAT_BONUS_SHORT"))
	var held: Dictionary = c.get("equipped", {})
	match kind:
		"Attack", "Throw":
			var item := str({"main": held.get("main_hand", ""), "frenzy": held.get("main_hand", ""), "off": held.get("off_hand", ""),
				"stowed": CharacterRules.stowed(c).get("main_hand", "")}.get(rest, ""))
			if item.is_empty():
				return [IconRules.EMPTY_HAND, short.get_slice(": ", 1) if short.contains(": ") else short]
			return ["items/" + item, ItemRules.display_name(data["items"], s.items, item)]
		"Cast", "Feat":
			if data["spells"].has(rest):
				return ["spells/" + rest, str(data["spells"][rest].get("name", rest))]
			return ["features/" + rest, short]
		"Item":
			return ["items/" + rest, ItemRules.display_name(data["items"], s.items, rest)]
		"Feature", "Meta":
			return ["features/" + rest, short.trim_prefix("✦ ")]
		"Volley":
			return ["spells/" + str(CombatRules.volley(s).get("spell", "")), short]
	return ["ui/" + node_name.to_snake_case(), short]


func _disabled(parent: Control, text: String, icon := "") -> void:
	_button(parent, "", text, false, icon)


## The button of an act: at once, or armed for a foe, or for a square after it.
func _act_button(parent: Control, act: Act, row: Dictionary, me: bool) -> void:
	var s := GameState.session
	var data := Catalog.data
	var hero := GameState.fight_actor()
	var id := act.id
	var how: Dictionary = row["how"]
	var text := str(row["text"]) + (tr("COMBAT_BONUS_SHORT") if act.cost(s, data, hero, how) == "bonus" else "")
	var stop := act.can(s, data, hero, "", how)
	var b: Button
	if act.aim() == Act.FOE:
		b = _action(parent, str(row["name"]), text, me and stop in ["", "COMBAT_BAD_TARGET"],
			func(t: String) -> String:
				if act.second():
					_second = {"act": id, "to": t}
					return ""
				return GameState.combat_act(id, t, how),
			func(t: String) -> String: return act.can(s, data, hero, t, how), func(_t: String) -> Dictionary: return {}, "", 0, "acts/" + id)
	elif act.second():
		b = _button(parent, str(row["name"]), text, me and stop.is_empty(), "acts/" + id)
		b.toggle_mode = true
		b.button_pressed = str(_second.get("act", "")) == id
		b.pressed.connect(func() -> void:
			_second = {} if str(_second.get("act", "")) == id else {"act": id, "to": ""}
			_pending = Callable()
			refresh())
	else:
		b = _button(parent, str(row["name"]), text, me and stop.is_empty(), "acts/" + id)
		var ask := act.confirm()
		b.pressed.connect(func() -> void:
			if ask.is_empty():
				_do(GameState.combat_act(id, "", how))
			else:
				ConfirmBox.ask(self, ask[0], ask[1], ask[2], func() -> void: _do(GameState.combat_act(id, "", how))))
	b.tooltip_text = tr(stop) if not stop in ["", "COMBAT_BAD_TARGET", "COMBAT_NOT_YOUR_TURN"] else str(row["tip"])
	if b is IconSlot:  # its card as in BG3: what it does and what it costs (v0.8.4.43.33); the line under the name only why not
		(b as IconSlot).set_card(CardInfo.act(s, data, hero, act, str(row["tip"])))
		(b as IconSlot).tip_title = str(row["text"]).trim_suffix(tr("COMBAT_BONUS_SHORT"))
		if b.tooltip_text == str(row["tip"]):
			b.tooltip_text = (b as IconSlot).tip_title


## A button that needs a target: pressing it lights the bodies that can be hit. `aims` — the spell whose target is a square.
func _action(parent: Control, node_name: String, text: String, enabled: bool, act: Callable, check: Callable, preview: Callable, aims := "", feet := 0, icon := "") -> Button:
	var b := _button(parent, node_name, text, enabled, icon)
	_acts.append({"tab": _act_tab, "sub": _act_sub, "text": text, "on": enabled, "act": act, "check": check, "preview": preview, "aims": aims})
	b.toggle_mode = true
	b.button_pressed = _pending.is_valid() and _pending_name == node_name
	b.pressed.connect(_arm.bind(node_name, text, act, check, preview, aims, feet))
	return b


## Picks an act to aim — a cell's press and a pick of the «Бросить» list alike; picked again, it is let go.
func _arm(node_name: String, text: String, act: Callable, check: Callable, preview: Callable, aims: String, feet: int) -> void:
	if _pending.is_valid() and _pending_name == node_name:
		_pending = Callable()
	else:
		_pending = act
		_pending_check = check
		_pending_preview = preview
		_pending_name = node_name
		_pending_text = text
		_pending_aim = aims
		_pending_feet = feet
	refresh()


## «Атака» and «Стрельба» as in BG3 (the author, 2026-11-13: «вместо иконок надетого оружия в бою — общие «Атака» и
## «Стрельба»»): a blow with the melee weapon of either set and a shot with the ranged one, the set changed for nothing as
## the stowed weapon's blow always was (v0.8.4.1); with no blade in either set «Атака» strikes with the fists. The weapons
## themselves stand in the hands at the bar's left. True when «Атака» is the fists.
func _strikes(s: GameSession, data: Dictionary, c: Dictionary, w: Control, me: bool, main: Dictionary, main_id: String) -> bool:
	var held: Dictionary = c.get("equipped", {})
	var spare_id := str(CharacterRules.stowed(c).get("main_hand", ""))
	var kinds := {"held": CharacterRules.hands_kind(held, data, s.items), "stowed": CharacterRules.hands_kind(CharacterRules.stowed(c), data, s.items)}
	var fists := false
	for kind: String in ["melee", "ranged"]:
		var hand := "held" if kinds["held"] == kind and not main_id.is_empty() else "stowed" if kinds["stowed"] == kind and not spare_id.is_empty() else ""
		if hand.is_empty() and kind == "ranged":
			continue
		var how := {} if hand == "held" else {"hand": "stowed"} if hand == "stowed" else {"hand": "fists"}
		fists = fists or hand.is_empty()
		var id := main_id if hand == "held" else spare_id if hand == "stowed" else ""
		var prof: Dictionary = main if hand == "held" else CombatRules.as_stowed(s, func() -> Dictionary: return CombatRules.weapon_profile(c, data, s.items, spare_id)) \
			if hand == "stowed" else CombatRules.weapon_profile(c, data, s.items, "")
		var key := "COMBAT_ATTACK" if kind == "melee" else "COMBAT_SHOOT"
		var b := _action(w, "Attack_" + kind, tr(key).format({"name": prof["name"], "hit": "%+d" % int(prof["to_hit"]), "dmg": _dmg_text(prof)}), me,
			func(t: String) -> String: return GameState.combat_act("attack", t, how),
			func(t: String) -> String: return Acts.one("attack").can(s, data, CombatRules.player(s), t, how),
			func(t: String) -> Dictionary: return CombatRules.as_stowed(s, func() -> Dictionary: return CombatRules.attack_preview(s, data, t, false)) if hand == "stowed" \
				else CombatRules.attack_preview(s, data, t, false, hand.is_empty()), "", _blow_far(prof) if kind == "melee" else _far(prof),
			"acts/attack" if kind == "melee" else "acts/shoot")
		if not id.is_empty():
			_details.hook(b, str(prof["name"]), "", CardInfo.item(c, data, s.items, id))
	return fists


## A thing to throw for the «Бросить» list (v0.8.4.43.49): the weapon of a hand, a flask or a net of the belt — what
## `_action` takes, with the thing's own picture for the list; `row` — also a row of a foe's menu (a flask's own cell
## makes its row itself).
func _throw(node_name: String, item: String, text: String, enabled: bool, act: Callable, check: Callable, preview: Callable, aims := "", feet := 0, row := true) -> void:
	if row:
		_acts.append({"tab": _act_tab, "sub": _act_sub, "text": text, "on": enabled, "act": act, "check": check, "preview": preview, "aims": aims})
	_throws.append({"name": node_name, "item": item, "text": text, "on": enabled, "act": act, "check": check, "preview": preview, "aims": aims, "feet": feet})


## «Бросить» as one cell (the author, 2026-11-13: «выбор открывает меню, как инвентарь, — что бросить из рук и с пояса»):
## a press lists what may be thrown with its picture, a pick aims it as its own cell would.
func _throw_cell(parent: Control, me: bool) -> void:
	if _throws.is_empty():
		return
	var b := _button(parent, "ThrowMenu", tr("COMBAT_THROW_MENU"), me and _throws.any(func(o: Dictionary) -> bool: return bool(o["on"])), "acts/throw")
	b.tooltip_text = tr("COMBAT_THROW_MENU") + "\n" + tr("COMBAT_THROW_MENU_TIP")
	b.toggle_mode = true
	b.button_pressed = _pending.is_valid() and _throws.any(func(o: Dictionary) -> bool: return _pending_name == str(o["name"]))
	b.pressed.connect(_throw_menu.bind(b))


func _throw_menu(b: Control) -> void:
	if _pop != null:
		remove_child(_pop)
		_pop.queue_free()
	_pop = ActsMenu.new()
	_pop.name = "ThrowList"
	add_child(_pop)
	_pop.add_separator(tr("COMBAT_THROW_MENU"))
	var s := GameState.session
	for o: Dictionary in _throws:
		var at := _pop.add_act(_pop, str(o["text"]), "", not bool(o["on"]), _arm.bind(str(o["name"]), str(o["text"]), o["act"], o["check"], o["preview"], str(o["aims"]), int(o["feet"])))
		var tex := IconSlot.texture(str(IconRules.of(Catalog.data, s.items if s != null else {}, "items/" + str(o["item"]))["path"]))
		if tex != null:
			_pop.set_item_icon(_pop.get_item_index(at), tex)
			_pop.set_item_icon_max_width(_pop.get_item_index(at), 40)
	refresh()  # the cell's own toggle undone: it stays lit only while a throw is picked
	_pop.popup(Rect2i(Vector2i(b.get_screen_position() + Vector2(0, -8)), Vector2i.ZERO))


## How far a weapon shoots or is thrown, feet; 0 — a blade.
func _far(w: Dictionary) -> int:
	return int(w["range"][1]) if not (w.get("range", []) as Array).is_empty() else 0


## How far a blow of the weapon reaches: a blade only at arm's length — its throw is another button (v0.8.4.31).
func _blow_far(w: Dictionary) -> int:
	return 0 if bool(w.get("melee", false)) else _far(w)


var _pending_name := ""
var _pending_text := ""  ## the picked act's caption: what a hint says at a target it has no numbers for (v0.8.4.43.8)


## A concentration spell while another one is held (v0.7.13.1, as in BG3): «Прервать «Благословение»?» first.
func _conc_guard(spell_id: String, go: Callable) -> String:
	var held := GameState.concentration_conflict(spell_id, GameState.fight_actor())
	if held.is_empty():
		return go.call()
	_conc_ask = {"text": tr("CONC_SWITCH").format({"old": held, "new": Catalog.data["spells"][spell_id]["name"]}), "go": go}
	_draw_ask(GameState.session)
	return ""


func _draw_conc_ask() -> void:
	_ask.visible = true
	_clear(_ask_box)
	var title := Label.new()
	title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	title.theme_type_variation = UiTheme.HEADING
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.text = str(_conc_ask["text"])
	_ask_box.add_child(title)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 10)
	_ask_box.add_child(flow)
	for yes: bool in [true, false]:
		var b := Button.new()
		b.name = "Ask_conc_" + ("yes" if yes else "no")
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		b.text = tr("CONC_YES" if yes else "CONC_NO")
		b.custom_minimum_size = Vector2(0, 56)
		if yes:
			b.theme_type_variation = UiTheme.ACCENT_BUTTON
		b.pressed.connect(func() -> void:
			var go: Callable = _conc_ask.get("go", Callable())
			_conc_ask = {}
			_ask.visible = false
			if yes and go.is_valid():
				_do(go.call())
			else:
				_draw_ask(GameState.session))
		flow.add_child(b)


## The window of a choice: a prompt of the hero's turn (Divine Smite, Wild Shape, Font of Magic) or a reaction to a
## foe's hit; the buttons answer it. The concentration question comes first.
func _draw_ask(s: GameSession) -> void:
	if not _conc_ask.is_empty():
		_draw_conc_ask()
		return
	var prompt: Dictionary = s.combat.get("prompt", {})
	var pending: Dictionary = s.combat.get("pending", {})
	_ask.visible = not prompt.is_empty() or not pending.is_empty()
	if not _ask.visible:
		return
	_clear(_ask_box)
	var title := Label.new()
	title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	title.theme_type_variation = UiTheme.HEADING
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ask_box.add_child(title)
	var options: Array = prompt.get("options", []) if not prompt.is_empty() else pending.get("options", [])
	if not prompt.is_empty():
		title.text = str(prompt.get("text", tr("COMBAT_ASK_TITLE")))
	else:
		title.text = tr("COMBAT_REACTION_TITLE")
		if str(pending.get("kind", "")) == "counter":  # a foe's spell (v0.7.13.7)
			_line(_ask_box, tr("COMBAT_REACTION_SPELL_CAST").format({"line": str(pending.get("line", ""))}))
		else:
			_line(_ask_box, tr("COMBAT_REACTION_HIT").format({"line": str(pending.get("line", "")), "dmg": int(pending.get("dmg", 0))}))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 10)
	flow.add_theme_constant_override("v_separation", 10)
	_ask_box.add_child(flow)
	if prompt.is_empty():
		options = options.duplicate()
		options.append({"id": "none", "label": tr("COMBAT_REACTION_NO")})
	for o: Dictionary in options:
		var b := Button.new()
		b.name = "Ask_" + str(o["id"])
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		b.text = str(o["label"])
		b.custom_minimum_size = Vector2(0, 56)
		if str(o["id"]) != "none":
			b.theme_type_variation = UiTheme.ACCENT_BUTTON
		var id := str(o["id"])
		var is_prompt := not prompt.is_empty()
		b.pressed.connect(func() -> void: _do(GameState.combat_answer(id) if is_prompt else GameState.combat_react(id)))
		flow.add_child(b)


func _draw_results(s: GameSession, data: Dictionary) -> void:
	var outcome := str(s.combat.get("outcome", ""))
	var show := not outcome.is_empty() and outcome != "dead" and bool(s.combat.get("narrated", false)) and not GameState.is_busy()
	_results.visible = show
	if not show:
		return
	_clear(_results_box)
	for b in _results.footer.get_children():
		_results.footer.remove_child(b)
		b.queue_free()
	_results.title.text = tr("COMBAT_OUTCOME_" + outcome.to_upper())
	if int(s.combat.get("xp", 0)) > 0:
		_line(_results_box, tr("COMBAT_XP").format({"xp": int(s.combat["xp"])}))
	if outcome == "victory":
		_line(_results_box, tr("COMBAT_ON_BODIES"))
	var shot := 0
	for id: String in CombatRules.player(s).get("ammo_spent", {}):
		shot += int(CombatRules.player(s)["ammo_spent"][id])
	var gather := CheckBox.new()  # v0.8.4.30: the spent shots picked up as the fight ends, by the player's choice
	gather.name = "GatherAmmo"
	gather.text = tr("COMBAT_GATHER_AMMO").format({"n": shot, "pct": roundi(float(ItemRules.cfg(data)["recover"]) * 100.0)})
	var lying := Gear.left_on_field(s)  # thrown weapons on the field (v0.8.4.31)
	if not lying.is_empty():
		var names: Array[String] = []
		for item: String in lying:
			names.append("%s ×%d" % [ItemRules.display_name(data["items"], s.items, item), int(lying[item])])
		gather.text = (gather.text + "; " if shot > 0 else "") + tr("COMBAT_GATHER_THROWN").format({"things": ", ".join(names)})
	gather.button_pressed = true
	gather.visible = (shot > 0 or not lying.is_empty()) and outcome in ["victory", "truce"]
	_results_box.add_child(gather)
	var go := _results.add_button("BTN_CONTINUE", func() -> void: GameState.finish_combat(gather.visible and gather.button_pressed), true)
	go.name = "FinishCombat"
