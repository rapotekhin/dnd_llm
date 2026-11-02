class_name FightUi
extends Control
## The fight on the one screen (v0.8.4): the place's own map is the field. The queue over it, the hero and those in the fight
## on the left, the acts on tabs under it, the log on the right; the windows of a choice and the results stand over all.
## An act that needs a target lights it: a click on a body or a line of the list does it, an area follows the mouse and a
## click lays it on the square. A click on a free square walks, on a foe opens its acts. The screen only shows and sends:
## every rule is in `core/`, FightGrid and CombatRules.

var _screen: Control
var _field: MapField
var _details: DetailsPanel  # v0.7.7 fixes: what a spell, feature, item or foe is (hover or press)
var _queue: HBoxContainer
var _foes: VBoxContainer
var _portrait: VBoxContainer
var _economy: VBoxContainer
var _tabs: TabContainer
var _fx_layer: Control  # floating numbers over the field
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
var _act_tab := ""  # the tab being drawn, and the list inside it for a foe's menu
var _act_sub := ""
var _pop: PopupMenu  # a foe's menu
var _pop_acts: Array[Dictionary] = []  # what its lines do
var _second := {}  # {act, to}: the next click picks a square of the act
var _tab := 0
var _on := false
var _parts: Array[Control] = []  # shown only in a fight
var _peace: Array[Control] = []  # hidden in a fight
const TEMP_HP := Color("#6f9fc8")
var _cast_circle := 0  # v0.7.22.19 (#19): the slot circle the player picked; 0 — the lowest that fits


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
	_queue = UiScenes.need(screen, "%Queue")
	_foes = UiScenes.need(screen, "%FoeList")
	_portrait = UiScenes.need(screen, "%Portrait")
	_economy = UiScenes.need(screen, "%Economy")
	_tabs = UiScenes.need(screen, "%Tabs")
	_tabs.tab_changed.connect(func(t: int) -> void: _tab = t)
	_hint = UiScenes.need(screen, "%Hint")
	_hint.add_theme_color_override("font_color", UiTheme.ACCENT_BRIGHT)
	end_turn = UiScenes.need(screen, "%EndTurnButton")
	end_turn.pressed.connect(func() -> void: _do(GameState.combat_end_turn()))
	_parts.assign([UiScenes.need(screen, "%FightSide"), UiScenes.need(screen, "%FightBar"), _queue, _hint, UiScenes.need(screen, "%FightLogBox")])
	_peace.assign([UiScenes.need(screen, "%Side"), UiScenes.need(screen, "%Bar"), UiScenes.need(screen, "%Strip"), UiScenes.need(screen, "%Chat")])
	var box: VBoxContainer = UiScenes.need(screen, "%FightLogBox")
	# The right side: a third — the static details, two thirds — the log (the author, v0.7.22.13).
	_details = DetailsPanel.new(Vector2(0, 120))
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
	return active() and CombatRules.player_can_act(GameState.session) and not GameState.is_busy() and Backend.is_ready()


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
	var l := Label.new()
	l.text = text
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.theme_type_variation = UiTheme.DM_TEXT if master else UiTheme.MUTED_LABEL
	if not master and GameState.has_session():  # the roll's breakdown on hover (v0.7.49.4)
		var tip := CombatRules.tip_for(GameState.session, text)
		if not tip.is_empty():
			l.tooltip_text = tip
			l.mouse_filter = Control.MOUSE_FILTER_STOP
	if master:
		_log_box.add_child(l)
	else:
		var hit := _roll_color(text)
		if hit != Color.TRANSPARENT:
			l.add_theme_color_override("font_color", hit)
		_round_block().get_node("Lines").add_child(l)
		_count_block()
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
		_fold(_block, true)
	_block = VBoxContainer.new()
	_block.name = "Rolls_%d" % rnd
	_block_round = rnd
	var head := Button.new()
	head.name = "Head"
	head.flat = true
	head.alignment = HORIZONTAL_ALIGNMENT_LEFT
	head.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	head.add_theme_color_override("font_color", UiTheme.MUTED)
	_block.add_child(head)
	var lines := VBoxContainer.new()
	lines.name = "Lines"
	lines.add_theme_constant_override("separation", 4)
	_block.add_child(lines)
	var block := _block
	head.pressed.connect(func() -> void: _fold(block, lines.visible))
	_log_box.add_child(_block)
	return _block


func _fold(block: VBoxContainer, folded: bool) -> void:
	block.get_node("Lines").visible = not folded
	block.set_meta("folded", folded)
	_count_block(block)


func _count_block(block: VBoxContainer = null) -> void:
	if block == null:
		block = _block
	var n := block.get_node("Lines").get_child_count()
	(block.get_node("Head") as Button).text = tr("COMBAT_ROLLS").format({"n": n, "fold": "▸" if bool(block.get_meta("folded", false)) else "▾"})


## A hit is red (the damage), a miss is grey; other lines keep the muted colour.
static func _roll_color(text: String) -> Color:
	if text.contains("— промах") or text.contains("— провал"):
		return UiTheme.MUTED.darkened(0.25)
	if text.contains("— попадание") or text.contains("критическ"):
		return UiTheme.BAD
	return Color.TRANSPARENT


## v0.7.22.27 (as in BG3), outside the input: Space ends the turn, 1–0 press the buttons of the open tab, Tab picks
## the next foe that can be hit (Enter strikes it). True — the key was the fight's.
func key(event: InputEvent) -> bool:
	if event.is_action_pressed("end_turn"):
		if not end_turn.disabled:
			end_turn.pressed.emit()
		return true
	if event.is_action_pressed("next_target"):
		_next_target()
		return true
	var buttons := _tab_buttons()
	var hit := false
	for i in buttons.size():
		if event.is_action_pressed("action_%d" % (i + 1)):
			hit = true
			if not buttons[i].disabled:
				if buttons[i] is CheckButton:
					buttons[i].button_pressed = not buttons[i].button_pressed
				else:
					buttons[i].pressed.emit()
	return hit


## Esc lets a picked act go. True — there was one.
func cancel() -> bool:
	if not _pending.is_valid() and _second.is_empty():
		return false
	_pending = Callable()
	_second = {}
	refresh()
	return true


## The buttons of a tab (the open one by default) in their order: the keys 1–0.
func _tab_buttons(page: Control = null) -> Array[BaseButton]:
	var out: Array[BaseButton] = []
	if page == null:
		page = _tabs.get_current_tab_control()
	if page == null:
		return out
	for b: Node in page.find_children("*", "BaseButton", true, false):
		if (b as BaseButton).visible and out.size() < 10:
			out.append(b as BaseButton)
	return out


func _number_actions() -> void:
	for page: Node in _tabs.get_children():
		var buttons := _tab_buttons(page as Control)
		for i in buttons.size():
			buttons[i].tooltip_text = Hotkeys.tip(buttons[i].tooltip_text, "action_%d" % (i + 1), SaveManager.keys)


## Opens the tab by its title key; the playtests call it too.
func set_filter(key: String) -> void:
	for i in _tabs.get_tab_count():
		if _tabs.get_tab_title(i) == tr(key):
			_tabs.current_tab = i


## The focus to the next foe card that can be pressed now.
func _next_target() -> void:
	var cards: Array[Button] = []
	for n: Node in _foes.find_children("Foe_*", "Button", true, false):
		cards.append(n as Button)  # a disabled card still takes focus: Tab reads a foe before the attack is picked
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
	if not on:
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
		_pending_aim = ""
		_pending_feet = int(data["spells"].get(str(CombatRules.volley(s)["spell"]), {}).get("range_ft", 0))
	end_turn.disabled = not me
	_draw_queue(s)
	_draw_list(s, data, me)
	_draw_map(s, data, me)
	_play_fx(s)
	_draw_portrait(s, data)
	_draw_actions(s, data, me)
	_number_actions()
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
	_field.routes = Move.routes(s, data, CombatRules.player(s)) if me and not _pending.is_valid() and _second.is_empty() else {}
	_field.lit = Acts.one(str(_second["act"])).squares(s, data, CombatRules.player(s), str(_second["to"])) if not _second.is_empty() else {}
	_field.reach = _in_range(s, data) if _pending.is_valid() and _pending_feet > 0 else {}
	_field.over = _over(s)
	_field.zones = SpellEffects.zone_view(s, data)
	_field.blast = {}
	_field.way = []
	_field.queue_redraw()


## The squares the picked act gets to from the hero, a clear line to them (v0.8.4.3).
func _in_range(s: GameSession, data: Dictionary) -> Dictionary:
	var g := FightGrid.grid(s, data)
	var me := CombatRules.player(s)
	var from := FightGrid.cell(me)
	var far := FightGrid.squares_of(data, _pending_feet)
	var out := {}
	for y: int in range(maxi(0, from.y - far), mini(int(g["map"]["h"]), from.y + far + 1)):
		for x: int in range(maxi(0, from.x - far), mini(int(g["map"]["w"]), from.x + far + 1)):
			var at := Vector2i(x, y)
			if FightGrid.dist_to(me, at) <= far and FightGrid.clear(g, from, at):
				out[at] = true
	return out


## What the fight changed on the map, by colour: {square: Color}.
func _over(s: GameSession) -> Dictionary:
	var out := {}
	for key: String in s.combat.get("cleared", {}):
		out[FightGrid.y_x(key)] = UiTheme.TILES["."]
	for key: String in s.combat.get("oil", {}):
		out[FightGrid.y_x(key)] = UiTheme.TILES["o"]
	for key: String in s.combat.get("blocks", {}):
		out[FightGrid.y_x(key)] = UiTheme.TILES["B"]
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
		if not fighting.has(str(t["ref"])) and (now.has(cell) or str(t["kind"]) in ["station", "prop"]):
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
			"colour": UiTheme.ACCENT_BRIGHT if hero else UiTheme.OK if side == "ally" else UiTheme.BAD,
			"span": int(f.get("span", 1)), "x": at.x, "y": at.y, "hp": int(s.character["hp"]) if hero else int(f.get("hp", 0)),
			"most": int(s.character["max_hp"]) if hero else int(f.get("max_hp", 1)), "out": status != "active" or (hero and int(s.character["hp"]) <= 0),
			"now": id == cur, "dim": bool(f.get("hidden", false)) or heard})
	return out


## The fighter on a square, "" — nobody. Those who lie are in the list: a foe down is no target.
func _id_at(cell: Vector2i) -> String:
	for f: Dictionary in _field.fighters:
		if FightGrid.body_at(Vector2i(int(f["x"]), int(f["y"])), int(f["span"])).has(cell):
			return str(f["id"])
	return ""


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
		var target := FightGrid.aim_id(cell) if not _pending_aim.is_empty() else id
		if target.is_empty():
			return
		var why := str(_pending_check.call(target))
		if not why.is_empty():
			EventBus.message.emit(tr(why))
			return
		_press(target)
		return
	if not id.is_empty() and str(CombatRules.fighter(s, id).get("side")) == "enemy":
		_foe_menu(id)
		return
	var way := _way_out_at(s, data, cell)
	if way != FightGrid.NONE:
		if way == FightGrid.cell(CombatRules.player(s)):
			_do(GameState.combat_act("flee"))
		else:
			_do(GameState.combat_act("walk", FightGrid.aim_id(way)))
		return
	if _field.routes.has(cell):
		_do(GameState.combat_act("walk", FightGrid.aim_id(cell)))


## The right button lets the picked act go.
func on_right(_cell: Vector2i) -> void:
	cancel()


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
	_pop = PopupMenu.new()
	_pop.name = "FoeMenu"
	_pop.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	add_child(_pop)
	_pop.add_separator(str(f.get("name", "")))
	_pop_acts = []
	var lists := {}
	for row: Dictionary in _acts:
		var target := aim if not str(row["aims"]).is_empty() else id
		var why := str((row["check"] as Callable).call(target))
		if not bool(row["on"]) or why == "COMBAT_BAD_TARGET":
			continue
		var list := _pop_list(_pop_list(_pop, lists, tr(str(row["tab"]))), lists, str(row["sub"]))
		list.add_item(str(row["text"]), _pop_acts.size())
		var at := list.item_count - 1
		list.set_item_disabled(at, not why.is_empty())
		list.set_item_tooltip(at, tr(why) if not why.is_empty() else _preview_text((row["preview"] as Callable).call(target)))
		_pop_acts.append({"act": row["act"], "target": target})
	var cell := FightGrid.shown(f)
	_pop.popup(Rect2i(Vector2i(_field.get_screen_position() + _field.cell_point(cell) + Vector2(_field.tile() / 2.0, 0)), Vector2i.ZERO))


## The list `title` inside `parent`, made at first need; no title — `parent` itself.
func _pop_list(parent: PopupMenu, lists: Dictionary, title: String) -> PopupMenu:
	if title.is_empty():
		return parent
	var key := str(parent.get_instance_id()) + title
	if not lists.has(key):
		var list := PopupMenu.new()
		list.name = "FoeList_" + title
		list.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		list.id_pressed.connect(_foe_pick)
		parent.add_child(list)
		parent.add_submenu_node_item(title, list)
		lists[key] = list
	return lists[key]


func _foe_pick(i: int) -> void:
	_pending = _pop_acts[i]["act"]
	_press(str(_pop_acts[i]["target"]))


## The mouse over a square: the path and its cost, the area of the picked spell, what a blow would do.
func on_hover(cell: Vector2i) -> void:
	if not active():
		return
	var s := GameState.session
	var data := Catalog.data
	var me := mine()
	var id := _id_at(cell)
	var text := _base_hint(me)
	_field.blast = {}
	_field.way = []
	if not _pending_aim.is_empty() and _pending.is_valid():
		text = _aim_hint(s, data, cell, id, text)
	elif _pending.is_valid() and not id.is_empty():
		var why := str(_pending_check.call(id))
		text = "%s: %s" % [_name_of(s, id), tr(why) if not why.is_empty() else _preview_text(_pending_preview.call(id)).replace("\n", " · ")]
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
	var reach := Acts.one("attack").can(s, data, CombatRules.player(s), id)
	if reach in ["COMBAT_OUT_OF_REACH", "COMBAT_OUT_OF_RANGE", "COMBAT_NO_LINE"]:
		return tr(reach)
	return _preview_text(CombatRules.attack_preview(s, data, id)).replace("\n", " · ")


## The area of the picked spell under the mouse: its squares lit, who is caught in them.
func _aim_hint(s: GameSession, data: Dictionary, cell: Vector2i, id: String, text: String) -> String:
	var aim := FightGrid.aim_id(cell)
	var why := str(_pending_check.call(aim))
	if not why.is_empty():
		return tr(why)
	var sp: Dictionary = data["spells"].get(_pending_aim, {})
	if not sp.has("area"):
		return text
	var caught: Array[String] = []
	var cells := CombatRules.area_cells(s, data, sp, CombatRules.aimed(s, aim))
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
		var node := _foes.find_child("Foe_" + who, true, false) as Control
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
	var card := _foes.find_child("Foe_" + id, true, false) as Control
	pin.size = Vector2(_field.tile(), _field.tile())
	if at != FightGrid.NONE:
		pin.global_position = _field.global_position + _field.cell_point(at) - pin.size / 2.0
	elif card != null:
		pin.global_position = card.global_position
	return pin


func _base_hint(me: bool) -> String:
	if not _second.is_empty():
		return tr("COMBAT_PICK_JUMP" if str(_second["to"]).is_empty() else "COMBAT_PICK_SIDE")
	if me and not _pending.is_valid() and Move.why(GameState.session, Catalog.data, CombatRules.player(GameState.session)) == "COMBAT_PRONE":
		return tr("COMBAT_PRONE")
	return tr("COMBAT_PICK_TARGET") if _pending.is_valid() else (tr("COMBAT_YOUR_TURN") if me else tr("COMBAT_WAIT"))


## The hint text: «Попадание 65% · урон 4–11» (or the chance the foe fails its save), why advantage / disadvantage.
func _preview_text(pv: Dictionary) -> String:
	if pv.is_empty():
		return ""
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
## side (foes red). No sprites yet — the token of its look.
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
		_face(id, f, id == cur, str(f.get("status", "active")) != "active")


func _face(id: String, f: Dictionary, now: bool, out: bool) -> void:
	var side := str(f.get("side", "enemy"))
	var col := UiTheme.ACCENT_BRIGHT if side == "player" else UiTheme.OK if side == "ally" else UiTheme.BAD
	var p := PanelContainer.new()
	p.name = "Turn_" + id
	p.tooltip_text = str(f["name"])
	p.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.PANEL_RAISED if now else UiTheme.PANEL, col if not out else UiTheme.MUTED, 3 if now else 2, 4, 8))
	p.custom_minimum_size = Vector2(64, 64) if now else Vector2(46, 46)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var l := Label.new()
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	var nm := str(f["name"])
	var tail := nm.get_slice(" ", nm.get_slice_count(" ") - 1)
	l.text = Look.token(f, nm) + (tail if tail.is_valid_int() else "")  # «В1», «В2» for the numbered ones
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 32 if now else 22)
	l.add_theme_color_override("font_color", UiTheme.MUTED if out else col)
	p.add_child(l)
	_queue.add_child(p)
	if now:
		var name_l := Label.new()
		name_l.name = "TurnName"
		name_l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		name_l.text = str(f["name"])
		name_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		name_l.add_theme_color_override("font_color", col)
		_queue.add_child(name_l)


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


## The list of those in the fight: the hero, the allies, the foes with what is known of them. The animations play on its lines.
func _draw_list(s: GameSession, data: Dictionary, me: bool) -> void:
	_clear(_foes)
	var chip := PanelContainer.new()
	chip.name = "Foe_" + CombatRules.PLAYER
	_foes.add_child(chip)
	var hero := Label.new()
	hero.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	hero.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hero.text = "(%s)" % s.character["name"]
	hero.add_theme_color_override("font_color", UiTheme.ACCENT_BRIGHT)
	chip.add_child(hero)
	if bool(CombatRules.player(s).get("hidden", false)):
		CombatFx.look(chip, "hidden")
	_friend_pick(s, data, _foes, CombatRules.PLAYER, me)
	for id: String in CombatRules.allies(s, false):  # v0.7.22.22: the hero's side, not a target of the buttons
		if str(CombatRules.fighter(s, id)["status"]) in ["gone", "left", "away"]:
			continue
		_ally_row(s, data, id, me)
	for id: String in s.combat.get("order", []):
		var f := CombatRules.fighter(s, id)
		if str(f.get("side")) == "enemy" and not str(f.get("status")) in ["left", "away"]:
			_foe_row(s, data, id, f, me)
	for w: Dictionary in s.combat.get("incoming", []):
		var ghost := Label.new()
		ghost.name = "Incoming"
		ghost.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		ghost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ghost.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ghost.add_theme_color_override("font_color", UiTheme.MUTED)
		ghost.text = tr("COMBAT_INCOMING").format({"names": "\n".join(w["names"]), "n": maxi(1, int(w["at"]) - int(s.combat.get("round", 1)))})
		_foes.add_child(ghost)


func _ally_row(s: GameSession, data: Dictionary, id: String, me: bool) -> void:
	var a := CombatRules.fighter(s, id)
	var ally := PanelContainer.new()
	ally.name = "Foe_" + id
	_foes.add_child(ally)
	var al := Label.new()
	al.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	al.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	al.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	al.mouse_filter = Control.MOUSE_FILTER_STOP
	al.text = "%s\nHP %d/%d · КД %d%s" % [a["name"], int(a["hp"]), int(a["max_hp"]), CombatRules.ac_of(a),
		("\n" + tr("COMBAT_ALLY_DOWN")) if str(a["status"]) == "down" else ""]
	al.add_theme_color_override("font_color", UiTheme.OK if str(a["status"]) == "active" else UiTheme.MUTED)
	var ally_name := str(a["name"])
	var ally_about := tr("COMBAT_ALLY_ABOUT").format({"monster": CombatRules.monster_card(s, data, a)}) + \
		("\n\n" + str(a["desc"]) if not str(a.get("desc", "")).is_empty() else "")
	al.mouse_entered.connect(func() -> void: _details.show_text(ally_name, ally_about))
	ally.add_child(al)
	_friend_pick(s, data, _foes, id, me)


func _foe_row(s: GameSession, data: Dictionary, id: String, f: Dictionary, me: bool) -> void:
	var card := Button.new()
	card.name = "Foe_" + id
	if bool(f.get("hidden", false)) and str(f.get("status")) == "active":
		CombatFx.look(card, "hidden")
	card.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.custom_minimum_size = Vector2(0, 76)
	var conds: Array = CombatRules.foe_conditions(GameState.session, data, f)
	if bool(f.get("surprised", false)):
		conds.append(tr("COMBAT_FOE_SURPRISED"))
	card.text = "%s\n%s" % [f["name"], tr(CombatRules.health_key(f))]
	if str(f.get("status")) == "active":
		var fbar := UiParts.hp_bar(int(f["hp"]), int(f["max_hp"]), 8.0)
		fbar.name = "FoeHp"
		card.add_child(fbar)
		fbar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		fbar.offset_left = 10
		fbar.offset_right = -10
		fbar.offset_top = -16
		fbar.offset_bottom = -8
	card.tooltip_text = ""  # what the foe is — in the details panel only (big test #35, v0.7.22.5)
	var lore := CombatRules.monster_card(s, data, f)
	var about := lore if not lore.is_empty() else tr("COMBAT_FOE_UNKNOWN")
	var fa := FactionRules.def(s, data, FactionRules.of_foe(data, SceneRules.room(s, data["world"], s.room_id).get("encounter", {}), f))  # v0.7.50
	if not fa.is_empty():
		about += "\n\n" + tr("COMBAT_FOE_FACTION").format({"name": fa["name"]})
	if not str(f.get("desc", "")).is_empty():
		about += "\n\n" + str(f["desc"])
	var foe_name := str(f["name"])
	card.mouse_entered.connect(func() -> void: _details.show_text(foe_name, about))
	if not lore.is_empty():
		card.text += "\nHP %d/%d · КД %d" % [int(f["hp"]), int(f["max_hp"]), CombatRules.ac_of(f)]
	var why := "COMBAT_NO_ACTION"
	if _pending.is_valid() and str(f.get("status")) == "active":
		why = str(_pending_check.call(id))
	card.disabled = not (me and _pending.is_valid() and why.is_empty())
	if _pending.is_valid() and not why.is_empty() and str(f.get("status")) == "active":
		card.tooltip_text = tr(why)
	elif str(f.get("status")) == "active":
		var hint := _preview_text(_pending_preview.call(id)) if _pending_preview.is_valid() and _pending.is_valid() else _foe_hint(s, data, id)
		if not hint.is_empty():
			card.tooltip_text = hint + ("\n\n" + card.tooltip_text if not card.tooltip_text.is_empty() else "")
			var title := str(f["name"])
			card.mouse_entered.connect(func() -> void: _hint.text = title)
			card.mouse_exited.connect(func() -> void: _hint.text = _base_hint(me))
	card.pressed.connect(_press.bind(id))
	_foes.add_child(card)
	if card.has_node("FoeHp"):  # the text ends above the bar (the theme's boxes are known only in the tree)
		for st: String in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
			var sb := card.get_theme_stylebox(st).duplicate() as StyleBox
			sb.content_margin_bottom = maxf(sb.content_margin_bottom, 0.0) + 18.0
			card.add_theme_stylebox_override(st, sb)
	if not conds.is_empty():  # the foe's conditions as small chips (Б1)
		var cflow := HFlowContainer.new()
		cflow.name = "FoeConds_" + id
		cflow.add_theme_constant_override("h_separation", 4)
		cflow.add_theme_constant_override("v_separation", 4)
		for cn: Variant in conds:
			var cl := Label.new()
			cl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			cl.text = str(cn)
			cl.add_theme_font_size_override("font_size", 15)
			cl.add_theme_color_override("font_color", UiTheme.WARN)
			cl.add_theme_stylebox_override("normal", UiTheme.box(UiTheme.PANEL_RAISED, UiTheme.BORDER, 1, 3, 4))
			cflow.add_child(cl)
		_foes.add_child(cflow)


func _draw_portrait(s: GameSession, data: Dictionary) -> void:
	_clear(_portrait)
	var c := s.character
	var name_l := Label.new()
	name_l.text = str(c["name"])
	name_l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	name_l.theme_type_variation = UiTheme.HEADING
	_portrait.add_child(name_l)
	var bars := HBoxContainer.new()
	bars.name = "HeroHp"
	bars.add_theme_constant_override("separation", 2)
	_portrait.add_child(bars)
	var bar := UiParts.hp_bar(int(c["hp"]), int(c["max_hp"]))
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_stretch_ratio = maxf(1.0, int(c["max_hp"]))
	bars.add_child(bar)
	if int(c.get("temp_hp", 0)) > 0:  # the temporary hits: a blue piece of their own
		var tb := ProgressBar.new()
		tb.name = "TempHp"
		tb.max_value = 1
		tb.value = 1
		tb.show_percentage = false
		tb.custom_minimum_size = Vector2(0, 14)
		tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tb.size_flags_stretch_ratio = float(c["temp_hp"])
		tb.add_theme_stylebox_override("fill", UiTheme.box(TEMP_HP, TEMP_HP, 0, 0, 3))
		bars.add_child(tb)
	_line(_portrait, tr("SIDE_HP_AC").format({"hp": c["hp"], "max": c["max_hp"], "ac": c["ac"]}) \
		+ ((" · +%d врем." % int(c["temp_hp"])) if int(c.get("temp_hp", 0)) > 0 else ""))
	if Guise.has_body(c):  # v0.7.10
		_line(_portrait, tr("COMBAT_WILD_SHAPE_LINE").format({"beast": data["monsters"].get(str(Guise.body(c)["monster"]), {}).get("name", ""),
			"hp": int(Guise.body(c)["hp"]), "max": int(Guise.body(c)["max_hp"])})).add_theme_color_override("font_color", UiTheme.ACCENT)
	if bool(CombatRules.player(s).get("reckless", false)):
		_line(_portrait, tr("COMBAT_RECKLESS")).add_theme_color_override("font_color", UiTheme.BAD)
	_portrait.add_child(WeaponSets.new())
	var chips := EffectChips.new()  # conditions, boons, exhaustion, concentration (v0.7.8)
	chips.compact = true  # small, the description in the panel (Б3)
	_portrait.add_child(chips)
	chips.refresh()
	for chip: Node in chips.get_children():
		var title := str(chip.get_meta("title", ""))
		var about := str(chip.get_meta("about", ""))
		(chip as Control).mouse_entered.connect(func() -> void: _details.show_text(title, about))
	if bool(CombatRules.player(s).get("raging", false)):
		_line(_portrait, tr("COMBAT_RAGING")).add_theme_color_override("font_color", UiTheme.BAD)
	if bool(CombatRules.player(s).get("hidden", false)):
		_line(_portrait, tr("COMBAT_HIDDEN")).add_theme_color_override("font_color", UiTheme.ACCENT)
	if bool(CombatRules.player(s).get("surprised", false)):
		_line(_portrait, tr("COMBAT_SURPRISED")).add_theme_color_override("font_color", UiTheme.WARN)
	if int(c["hp"]) <= 0:
		var ds: Dictionary = s.combat.get("death_saves", {})
		_line(_portrait, tr("COMBAT_DEATH_SAVES").format({"ok": int(ds.get("ok", 0)), "fail": int(ds.get("fail", 0))})).add_theme_color_override("font_color", UiTheme.BAD)


## The button that picks the hero or an ally for an armed spell of the hero's side (v0.7.50.1).
func _friend_pick(s: GameSession, data: Dictionary, box: Control, id: String, me: bool) -> void:
	var vol := CombatRules.volley(s)
	var spell := str(vol.get("spell", "")) if _pending_name == "Volley" else _pending_name.trim_prefix("Cast_")
	if not _pending.is_valid() or not SpellEffects.picks_side(data, spell) in ["friend", "any"]:
		return
	box.add_theme_constant_override("separation", 2)  # a column of three friends and their buttons still fits
	var why := str(_pending_check.call(id))
	var b := _button(box, "Pick_" + id, tr("COMBAT_PICK_FRIEND"), me and why.is_empty())
	if not why.is_empty():
		b.tooltip_text = tr(why)
	b.pressed.connect(_press.bind(id))


func _line(parent: Control, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)
	return l


func _draw_actions(s: GameSession, data: Dictionary, me: bool) -> void:
	_acts.clear()
	var e := CombatRules.economy(s)
	_clear(_economy)
	if ArenaRules.watching(s):  # v0.8.4.5: from the fence nothing is in the hero's hands
		_clear(_tabs)
		var note := Label.new()
		note.name = "WatchNote"
		note.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		note.text = tr("COMBAT_WATCHING").format({"name": str(s.combat["arena"]["pick"])})
		_tab_box("COMBAT_TAB_WATCH").add_child(note)
		return
	for spec: Array in [["EcoAction", "● " + tr("COMBAT_ACTION"), int(e.get("action", 0)) + int(e.get("attacks", 0))],
			["EcoBonus", "▲ " + tr("COMBAT_BONUS"), int(e.get("bonus", 0))],
			["EcoMove", tr("COMBAT_MOVE").format({"n": int(e.get("move", 0))}), int(e.get("move", 0))]]:
		var el := Label.new()
		el.name = spec[0]
		el.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		el.text = spec[1]
		el.add_theme_color_override("font_color", UiTheme.ACCENT_BRIGHT if int(spec[2]) > 0 else UiTheme.MUTED.darkened(0.35))
		_economy.add_child(el)
	_clear(_tabs)
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
		func(t: String) -> Dictionary: return CombatRules.attack_preview(s, data, t, false), "", _far(main))
	if not main_id.is_empty():
		_details.hook(main_b, str(main["name"]), DetailsPanel.item_text(c, data, s.items, main_id))
	var spare_id := str(CharacterRules.stowed(c).get("main_hand", ""))
	if not spare_id.is_empty():  # the weapon put away: one click, the set changes for nothing (v0.8.4.1, as in BG3)
		var spare: Dictionary = CombatRules.as_stowed(s, func() -> Dictionary: return CombatRules.weapon_profile(c, data, s.items, spare_id))
		var spare_b := _action(w, "Attack_stowed", tr("COMBAT_ATTACK").format({"name": spare["name"], "hit": "%+d" % int(spare["to_hit"]), "dmg": _dmg_text(spare)}), me,
			func(t: String) -> String: return GameState.combat_act("attack", t, {"hand": "stowed"}),
			func(t: String) -> String: return Acts.one("attack").can(s, data, CombatRules.player(s), t, {"hand": "stowed"}),
			func(t: String) -> Dictionary: return CombatRules.as_stowed(s, func() -> Dictionary: return CombatRules.attack_preview(s, data, t, false)), "", _far(spare))
		_details.hook(spare_b, str(spare["name"]), DetailsPanel.item_text(c, data, s.items, spare_id))
	if not main_id.is_empty():  # fists with a weapon in hand (v0.7.22.11, big test #45)
		var fist := CombatRules.weapon_profile(c, data, s.items, "")
		_action(w, "Attack_unarmed", tr("COMBAT_ATTACK").format({"name": fist["name"], "hit": "%+d" % int(fist["to_hit"]), "dmg": _dmg_text(fist)}), me,
			func(t: String) -> String: return GameState.combat_act("attack", t, {"hand": "fists"}),
			func(t: String) -> String: return Acts.one("attack").can(s, data, CombatRules.player(s), t, {"hand": "fists"}),
			func(t: String) -> Dictionary: return CombatRules.attack_preview(s, data, t, false, true))
	var nl := CheckButton.new()  # knock out, not kill (v0.7.22.11, big test #44)
	nl.name = "NonlethalToggle"
	nl.text = "COMBAT_NONLETHAL"
	nl.tooltip_text = "COMBAT_NONLETHAL_TIP"
	nl.button_pressed = bool(s.combat.get("nonlethal", false))
	if ArenaRules.yield_bout(s):  # v0.7.45: a bout to surrender — only knocking out
		nl.disabled = true
		nl.tooltip_text = "COMBAT_NONLETHAL_ARENA"
	nl.toggled.connect(func(on: bool) -> void: GameState.combat_nonlethal(on))
	w.add_child(nl)
	var off := str(c.get("equipped", {}).get("off_hand", ""))
	if not off.is_empty():
		var ow := CombatRules.weapon_profile(c, data, s.items, off, true)
		_action(w, "Attack_off", tr("COMBAT_ATTACK_OFF").format({"name": ow["name"], "dmg": _dmg_text(ow)}), me,
			func(t: String) -> String: return GameState.combat_act("attack", t, {"hand": "off"}),
			func(t: String) -> String: return Acts.one("attack").can(s, data, CombatRules.player(s), t, {"hand": "off"}),
			func(t: String) -> Dictionary: return CombatRules.attack_preview(s, data, t, true), "", _far(ow))
	if bool(CombatRules.player(s).get("frenzy", false)):
		_action(w, "Attack_frenzy", tr("COMBAT_ATTACK_FRENZY").format({"name": main["name"], "dmg": _dmg_text(main)}), me,
			func(t: String) -> String: return GameState.combat_act("attack", t, {"hand": "frenzy"}),
			func(t: String) -> String: return Acts.one("attack").can(s, data, CombatRules.player(s), t, {"hand": "frenzy"}),
			func(t: String) -> Dictionary: return CombatRules.attack_preview(s, data, t, false))
	# Spells.
	if not SpellRules.ready(c).is_empty() and not Guise.has_body(c):
		var sp := _tab_box("COMBAT_TAB_SPELLS")
		for mm: Dictionary in FeatureRules.metamagic(c, data):  # v0.7.10: metamagic toggles of the next spell
			var mid := str(mm["id"])
			var mb := _button(sp, "Meta_" + mid, "✦ %s (%d)" % [mm["name"], int(mm["cost"])], me and Stock.left(c, data, "sorcery_points") >= int(mm["cost"]))
			mb.toggle_mode = true
			mb.button_pressed = str(CombatRules.player(s).get("metamagic", "")) == mid
			mb.tooltip_text = tr("META_TIP_" + mid.to_upper())
			mb.pressed.connect(func() -> void: GameState.combat_metamagic(mid))
		var circles: Array[int] = []
		for lv in range(1, 6):
			if SpellRules.slots_left(c, lv) > 0:
				circles.append(lv)
		if circles.size() > 1:
			var cp := OptionButton.new()
			cp.name = "CastCircle"
			cp.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			cp.add_item(tr("COMBAT_SLOT_LOWEST"), 0)
			for lv: int in circles:
				cp.add_item(tr("COMBAT_SLOT_CIRCLE").format({"n": lv, "left": SpellRules.slots_left(c, lv)}), lv)
			cp.select(maxi(0, cp.get_item_index(_cast_circle)))
			cp.item_selected.connect(func(i: int) -> void:
				_cast_circle = cp.get_item_id(i)
				refresh())
			sp.add_child(cp)
		for id: String in SpellRules.ready(c):
			var spell: Dictionary = data["spells"].get(id, {})
			var lv := int(spell.get("level", 0))
			var free := SpellRules.is_free(c, id)  # an invocation's spell at will (v0.7.22.4)
			var slot := 0 if lv == 0 or free else _slot_for(c, data, id)
			var cost := tr("COMBAT_BONUS_SHORT") if CombatRules.spell_cost(data, id) == "bonus" else ""
			var label := "%s%s%s%s" % [spell.get("name", id), (" (%d)" % slot) if slot > 0 else "", tr("SPELL_AT_WILL_SHORT") if free else "", cost]
			if lv > 0 and slot == 0 and not free:
				_disabled(sp, label)
				continue
			var side := SpellEffects.picks_side(data, id)  # v0.7.50.1: a choice of friends, or of either side
			var friends := side == "any" or (side == "friend" and not CombatRules.allies(s, false).is_empty())
			var alone := side == "friend" and not friends
			var jump := SpellEffects.spec(data, id).has("teleport")  # Misty Step: a square, not a body
			if not jump and (alone or not friends and spell.has("heal_at_slot") or not friends and SpellEffects.self_spell(data, id) \
					or int(spell.get("range_ft", 0)) == 0 and not spell.has("area") or not AllyRules.summon_spec(data, id).is_empty()):
				var b := _button(sp, "Cast_" + id, label, me)
				_details.hook(b, str(spell.get("name", id)), DetailsPanel.spell_text(data, id, slot))
				b.pressed.connect(func() -> void: _do(_conc_guard(id, func() -> String: return GameState.combat_cast(id, slot, ""))))
			else:
				_act_sub = tr("DETAILS_CANTRIP") if lv == 0 else tr("DETAILS_CIRCLE").format({"n": lv})
				var ab := _action(sp, "Cast_" + id, label, me,
					func(t: String) -> String: return _conc_guard(id, func() -> String: return GameState.combat_cast(id, slot, t)),
					func(t: String) -> String: return Acts.one("cast").can(s, data, CombatRules.player(s), t, {"spell": id, "slot": slot}),
					func(t: String) -> Dictionary: return {} if FightGrid.is_aim(t) else CombatRules.cast_preview(s, data, id, slot, t),
					id if spell.has("area") or jump else "", int(spell.get("range_ft", 0)))
				_details.hook(ab, str(spell.get("name", id)), DetailsPanel.spell_text(data, id, slot))
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
	# Features: limited uses with an action of their own, then the feature actions (v0.7.10).
	var res := Stock.lines(c, data).filter(func(r: Dictionary) -> bool:
		return str(Stock.table(data).get(str(r["id"]), {}).get("combat_cost", "action")) != "never")
	var feats := FeatureRules.actions(s, data).filter(func(a: Dictionary) -> bool: return not str(a["id"]).begins_with("spell_"))
	if not res.is_empty() or not feats.is_empty():
		var fb := _tab_box("COMBAT_TAB_FEATURES")
		for fa: Dictionary in feats:
			var fid := str(fa["id"])
			var label := "%s%s" % [fa["name"], tr("COMBAT_BONUS_SHORT") if str(fa["cost"]) == "bonus" else ""]
			if bool(fa["target"]):
				var tb := _action(fb, "Feat_" + fid, label, me, func(t: String) -> String: return GameState.combat_feature(fid, t),
					func(t: String) -> String: return Acts.one("feature").can(s, data, CombatRules.player(s), t, {"id": fid}), func(_t: String) -> Dictionary: return {})
				tb.tooltip_text = str(fa["tip"])
				_details.hook(tb, str(fa["name"]), str(fa["tip"]))
			else:
				var why := Acts.one("feature").can(s, data, CombatRules.player(s), "", {"id": fid})
				var ub := _button(fb, "Feat_" + fid, label, me and why.is_empty())
				ub.tooltip_text = str(fa["tip"]) + (("\n" + tr(why)) if not why.is_empty() and why != "COMBAT_NOT_YOUR_TURN" else "")
				_details.hook(ub, str(fa["name"]), str(fa["tip"]))
				ub.pressed.connect(func() -> void: _do(GameState.combat_feature(fid)))
		for r: Dictionary in res:
			var b := _button(fb, "Feature_" + str(r["id"]), "%s (%d/%d)" % [r["name"], r["left"], r["max"]], me and int(r["left"]) > 0)
			var rid := str(r["id"])
			_details.hook(b, str(r["name"]), DetailsPanel.feature_text(data, rid))
			b.pressed.connect(func() -> void: _do(GameState.combat_use_feature(rid)))
	# Items.
	var usable: Array[String] = []
	for id: String in c.get("inventory", {}):
		if not ItemRules.consumable(data, id, s.items).is_empty():
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
				var spills: bool = fx["throw"].has("oiled") or fx["throw"].has("burning")  # v0.8.4: a flask goes on a square too
				item_btn = _action(ib, "Item_" + id, label, me, func(t: String) -> String: return GameState.combat_act("throw", t, {"item": id}),
					func(t: String) -> String: return Acts.one("throw").can(s, data, CombatRules.player(s), t, {"item": id}), func(_t: String) -> Dictionary: return {}, id if spills else "",
					60 if bool(fx["throw"].get("improvised", false)) else int(fx["throw"].get("range", 15)))
			elif not sp_id.is_empty() and CombatRules.is_engine_spell(data, sp_id) and not sp.has("heal_at_slot") 					and (int(sp.get("range_ft", 0)) > 0 or sp.has("area")):
				item_btn = _action(ib, "Item_" + id, label, me, func(t: String) -> String: return GameState.combat_act("item_spell", t, {"item": id}),
					func(t: String) -> String: return Acts.one("item_spell").can(s, data, CombatRules.player(s), t, {"item": id}), func(_t: String) -> Dictionary: return {}, "", int(sp.get("range_ft", 0)))
			elif not sp_id.is_empty():
				item_btn = _button(ib, "Item_" + id, label, me)
				item_btn.pressed.connect(func() -> void: _do(GameState.combat_act("item_spell", "", {"item": id})))
			else:
				if ItemRules.is_potion(data, s.items, id) and str(CombatRules.cfg(data).get("potion_cost", "action")) == "bonus":
					label += tr("COMBAT_BONUS_SHORT")  # v0.7.22.3: a potion — a bonus action
				item_btn = _button(ib, "Item_" + id, label, me)
				item_btn.pressed.connect(func() -> void: _do(GameState.combat_act("use_item", "", {"item": id})))
			_details.hook(item_btn, str(d.get("name", id)), DetailsPanel.item_text(c, data, s.items, id))
	# Common.
	var g := _tab_box("COMBAT_TAB_COMMON")
	var hero := CombatRules.player(s)
	for act: Act in Acts.on_tab(s, data, hero, "common"):
		for row: Dictionary in act.buttons(s, data, hero):
			_act_button(g, act, row, me)
	_tabs.current_tab = clampi(_tab, 0, _tabs.get_tab_count() - 1)


## The picked circle when it fits the spell and has a slot left, else the lowest that fits.
func _slot_for(c: Dictionary, data: Dictionary, id: String) -> int:
	if _cast_circle >= maxi(1, SpellRules.level_of(data, id)) and SpellRules.slots_left(c, _cast_circle) > 0:
		return _cast_circle
	return SpellRules.lowest_slot(c, data, id)


func _dmg_text(w: Dictionary) -> String:
	var b := int(w["bonus"])
	return "%s%s" % [str(w["dice"]).replace("d", tr("DICE_D")), ("%+d" % b) if b != 0 else ""]


func _tab_box(title: String) -> HFlowContainer:
	_act_tab = title
	_act_sub = ""
	var scroll := ScrollContainer.new()
	scroll.name = tr(title)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.add_theme_constant_override("h_separation", 10)
	flow.add_theme_constant_override("v_separation", 10)
	scroll.add_child(flow)
	_tabs.add_child(scroll)
	return flow


func _button(parent: Control, node_name: String, text: String, enabled: bool) -> Button:
	var b := Button.new()
	if not node_name.is_empty():
		b.name = node_name
	b.text = text
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.custom_minimum_size = Vector2(0, 52)
	b.disabled = not enabled
	parent.add_child(b)
	return b


func _disabled(parent: Control, text: String) -> void:
	_button(parent, "", text, false)


## The button of an act: at once, or armed for a foe, or for a square after it.
func _act_button(parent: Control, act: Act, row: Dictionary, me: bool) -> void:
	var s := GameState.session
	var data := Catalog.data
	var hero := CombatRules.player(s)
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
			func(t: String) -> String: return act.can(s, data, hero, t, how), func(_t: String) -> Dictionary: return {})
	elif act.second():
		b = _button(parent, str(row["name"]), text, me and stop.is_empty())
		b.toggle_mode = true
		b.button_pressed = str(_second.get("act", "")) == id
		b.pressed.connect(func() -> void:
			_second = {} if str(_second.get("act", "")) == id else {"act": id, "to": ""}
			_pending = Callable()
			refresh())
	else:
		b = _button(parent, str(row["name"]), text, me and stop.is_empty())
		var ask := act.confirm()
		b.pressed.connect(func() -> void:
			if ask.is_empty():
				_do(GameState.combat_act(id, "", how))
			else:
				ConfirmBox.ask(self, ask[0], ask[1], ask[2], func() -> void: _do(GameState.combat_act(id, "", how))))
	b.tooltip_text = tr(stop) if not stop in ["", "COMBAT_BAD_TARGET", "COMBAT_NOT_YOUR_TURN"] else str(row["tip"])


## A button that needs a target: pressing it lights the bodies that can be hit. `aims` — the spell whose target is a square.
func _action(parent: Control, node_name: String, text: String, enabled: bool, act: Callable, check: Callable, preview: Callable, aims := "", feet := 0) -> Button:
	var b := _button(parent, node_name, text, enabled)
	_acts.append({"tab": _act_tab, "sub": _act_sub, "text": text, "on": enabled, "act": act, "check": check, "preview": preview, "aims": aims})
	b.toggle_mode = true
	b.button_pressed = _pending.is_valid() and _pending_name == node_name
	b.pressed.connect(func() -> void:
		if _pending.is_valid() and _pending_name == node_name:
			_pending = Callable()
		else:
			_pending = act
			_pending_check = check
			_pending_preview = preview
			_pending_name = node_name
			_pending_aim = aims
			_pending_feet = feet
		refresh())
	return b


## How far a weapon shoots or is thrown, feet; 0 — a blade.
func _far(w: Dictionary) -> int:
	return int(w["range"][1]) if not (w.get("range", []) as Array).is_empty() else 0


var _pending_name := ""


## A concentration spell while another one is held (v0.7.13.1, as in BG3): «Прервать «Благословение»?» first.
func _conc_guard(spell_id: String, go: Callable) -> String:
	var held := GameState.concentration_conflict(spell_id)
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
	var go := _results.add_button("BTN_CONTINUE", func() -> void: GameState.finish_combat(), true)
	go.name = "FinishCombat"
