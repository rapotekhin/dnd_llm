class_name CombatScreen
extends Control
## The fight (roadmap v0.6.1, ADR-0010 §7): the initiative order on top, the field of 7 columns of 30 ft, the
## player's panel below like in BG3 (portrait block, action / bonus / move, tabs of actions, «Конец хода»), the
## log and free input on the right. An action that needs a target lights the cards that can be hit; a click on a
## card does it. The results (XP, loot to take) or the death screen come when the fight ends.

var _queue: HBoxContainer
var _field: HBoxContainer
var _portrait: VBoxContainer
var _economy: Label
var _tabs: TabContainer
var _hint: Label
var _log_box: VBoxContainer
var _log_scroll: ScrollContainer
var _thinking: Label
var _retry: Button
var input: LineEdit
var send_button: Button
var end_turn: Button
var _results: PanelContainer
var _results_box: VBoxContainer
## The action waiting for a target: Callable(target_id) -> String (a reason or ""), and its check.
var _pending: Callable
var _pending_check: Callable
var _tab := 0


func _ready() -> void:
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	margin.add_child(row)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 2.6
	left.add_theme_constant_override("separation", 12)
	row.add_child(left)
	_queue = HBoxContainer.new()
	_queue.name = "Queue"
	_queue.add_theme_constant_override("separation", 8)
	left.add_child(_queue)
	_field = HBoxContainer.new()
	_field.name = "Field"
	_field.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_field.add_theme_constant_override("separation", 6)
	left.add_child(_field)
	_hint = Label.new()
	_hint.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_hint.add_theme_color_override("font_color", UiTheme.ACCENT_BRIGHT)
	left.add_child(_hint)

	var bottom := PanelContainer.new()
	bottom.theme_type_variation = UiTheme.SIDE
	bottom.custom_minimum_size = Vector2(0, 300)
	left.add_child(bottom)
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 18)
	bottom.add_child(brow)
	_portrait = VBoxContainer.new()
	_portrait.name = "Portrait"
	_portrait.custom_minimum_size = Vector2(300, 0)
	brow.add_child(_portrait)
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	brow.add_child(mid)
	_economy = Label.new()
	_economy.name = "Economy"
	_economy.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	mid.add_child(_economy)
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.tab_changed.connect(func(t: int) -> void: _tab = t)
	mid.add_child(_tabs)
	var right_btns := VBoxContainer.new()
	right_btns.custom_minimum_size = Vector2(200, 0)
	right_btns.add_theme_constant_override("separation", 10)
	brow.add_child(right_btns)
	end_turn = Button.new()
	end_turn.name = "EndTurnButton"
	end_turn.text = "BTN_END_TURN"
	end_turn.theme_type_variation = UiTheme.ACCENT_BUTTON
	end_turn.custom_minimum_size = Vector2(0, 80)
	end_turn.pressed.connect(func() -> void: _do(GameState.combat_end_turn()))
	right_btns.add_child(end_turn)
	for spec: Array in [["MoveLeft", "BTN_STEP_LEFT", -1], ["MoveRight", "BTN_STEP_RIGHT", 1]]:
		var b := Button.new()
		b.name = spec[0]
		b.text = spec[1]
		b.custom_minimum_size = Vector2(0, 56)
		var dir: int = spec[2]
		b.pressed.connect(func() -> void: _do(GameState.combat_move(dir)))
		right_btns.add_child(b)

	var right := PanelContainer.new()
	right.theme_type_variation = UiTheme.SIDE
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 1.0
	row.add_child(right)
	var rcol := VBoxContainer.new()
	rcol.add_theme_constant_override("separation", 10)
	right.add_child(rcol)
	_log_scroll = ScrollContainer.new()
	_log_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rcol.add_child(_log_scroll)
	_log_box = VBoxContainer.new()
	_log_box.name = "CombatLog"
	_log_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log_box.add_theme_constant_override("separation", 6)
	_log_scroll.add_child(_log_box)
	_thinking = Label.new()
	_thinking.text = "MSG_MASTER_THINKING"
	_thinking.theme_type_variation = UiTheme.MUTED_LABEL
	rcol.add_child(_thinking)
	_retry = Button.new()
	_retry.text = "BTN_RETRY_TURN"
	_retry.pressed.connect(GameState.retry)
	rcol.add_child(_retry)
	input = LineEdit.new()
	input.name = "CombatInput"
	input.placeholder_text = "PLACEHOLDER_COMBAT"
	input.text_submitted.connect(func(_t: String) -> void: _send())
	rcol.add_child(input)
	send_button = Button.new()
	send_button.text = "BTN_SEND"
	send_button.pressed.connect(_send)
	rcol.add_child(send_button)

	_results = PanelContainer.new()
	_results.name = "CombatResults"
	_results.theme_type_variation = UiTheme.SIDE
	_results.visible = false
	add_child(_results)
	_results.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_results.custom_minimum_size = Vector2(760, 0)
	_results_box = VBoxContainer.new()
	_results_box.add_theme_constant_override("separation", 10)
	_results.add_child(_results_box)

	if GameState.has_session() and CombatRules.active(GameState.session):
		for i in range(maxi(0, GameState.session.chat.size() - 4), GameState.session.chat.size()):
			var e := GameState.session.chat[i]
			if str(e["kind"]) == GameSession.KIND_DM:
				_add_log(str(e["text"]), true)
		for l: Variant in GameState.session.combat.get("log", []):
			_add_log(str(l), false)
	EventBus.combat_lines.connect(func(lines: Array[String]) -> void:
		for l: String in lines:
			_add_log(l, false))
	EventBus.chat_appended.connect(func(e: Dictionary) -> void:
		if str(e["kind"]) == GameSession.KIND_DM:
			_add_log(str(e["text"]), true)
		elif str(e["kind"]) == GameSession.KIND_SYSTEM:
			_add_log(tr(str(e["key"])), false))
	EventBus.state_changed.connect(_refresh)
	EventBus.turn_started.connect(func(_id: String) -> void: _refresh())
	EventBus.turn_finished.connect(func(_id: String, _ok: bool) -> void: _refresh())
	EventBus.backend_state_changed.connect(func(_s: int, _d: String) -> void: _refresh())
	_refresh()


func _add_log(text: String, master: bool) -> void:
	var l := Label.new()
	l.text = text
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.theme_type_variation = UiTheme.DM_TEXT if master else UiTheme.MUTED_LABEL
	_log_box.add_child(l)
	while _log_box.get_child_count() > 120:
		var old := _log_box.get_child(0)
		_log_box.remove_child(old)
		old.queue_free()
	await get_tree().process_frame
	_log_scroll.scroll_vertical = int(_log_scroll.get_v_scroll_bar().max_value)


func _send() -> void:
	if GameState.submit(input.text):
		input.clear()
		_pending = Callable()


func _do(err: String) -> void:
	_pending = Callable()
	if not err.is_empty():
		EventBus.message.emit(tr(err))
	_refresh()


static func _clear(n: Node) -> void:
	for ch in n.get_children():
		n.remove_child(ch)
		ch.queue_free()


func _refresh() -> void:
	if not GameState.has_session() or not CombatRules.active(GameState.session):
		return
	var s := GameState.session
	var data := Catalog.data
	var mine := CombatRules.is_player_turn(s) and not GameState.is_busy() and Backend.is_ready() and int(s.character["hp"]) > 0
	_thinking.visible = not GameState.busy_turn.is_empty()
	_retry.visible = GameState.can_retry()
	input.editable = mine
	send_button.disabled = not mine
	end_turn.disabled = not mine
	for b: String in ["MoveLeft", "MoveRight"]:
		(find_child(b, true, false) as Button).disabled = not mine or int(CombatRules.economy(s).get("move", 0)) <= 0
	_draw_queue(s)
	_draw_field(s, data, mine)
	_draw_portrait(s, data)
	_draw_actions(s, data, mine)
	_hint.text = tr("COMBAT_PICK_TARGET") if _pending.is_valid() else (tr("COMBAT_YOUR_TURN") if mine else tr("COMBAT_WAIT"))
	_draw_results(s, data)


func _draw_queue(s: GameSession) -> void:
	_clear(_queue)
	var cur := CombatRules.current(s)
	_chip(_queue, tr("COMBAT_ROUND").format({"n": int(s.combat.get("round", 1))}), false, true)
	for id: String in s.combat.get("order", []):
		var f := CombatRules.fighter(s, id)
		var gone := str(f.get("status", "active")) != "active"
		_chip(_queue, str(f["name"]), id == cur, gone)


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


func _draw_field(s: GameSession, data: Dictionary, mine: bool) -> void:
	_clear(_field)
	var edge := CombatRules.edge(data)
	var pcol := int(CombatRules.player(s)["col"])
	for col in range(-edge, edge + 1):
		var panel := PanelContainer.new()
		panel.name = "Col_%d" % col
		panel.theme_type_variation = UiTheme.SIDE if col == pcol else UiTheme.CARD
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_field.add_child(panel)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 8)
		panel.add_child(box)
		var head := Label.new()
		head.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		head.theme_type_variation = UiTheme.MUTED_LABEL
		var d := absi(col - pcol) * int(CombatRules.cfg(data)["col_ft"])
		head.text = tr("COMBAT_MELEE") if d == 0 else tr("COMBAT_FT").format({"ft": d})
		box.add_child(head)
		if col == pcol:
			var me := Label.new()
			me.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			me.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			me.text = "(%s)" % s.character["name"]
			me.add_theme_color_override("font_color", UiTheme.ACCENT_BRIGHT)
			box.add_child(me)
		for id: String in s.combat.get("order", []):
			var f := CombatRules.fighter(s, id)
			if str(f.get("side")) != "enemy" or int(f["col"]) != col:
				continue
			var card := Button.new()
			card.name = "Foe_" + id
			card.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			card.custom_minimum_size = Vector2(0, 76)
			var conds: Array = (f.get("conditions", []) as Array).map(func(x: Variant) -> String: return tr("COND_" + str(x).to_upper()))
			card.text = "%s\n%s%s" % [f["name"], tr(CombatRules.health_key(f)), ("\n" + ", ".join(conds)) if not conds.is_empty() else ""]
			card.tooltip_text = str(f.get("desc", ""))
			var why := "COMBAT_NO_ACTION"
			if _pending.is_valid() and str(f.get("status")) == "active":
				why = str(_pending_check.call(id))
			card.disabled = not (mine and _pending.is_valid() and why.is_empty())
			if _pending.is_valid() and not why.is_empty() and str(f.get("status")) == "active":
				card.tooltip_text = tr(why)
			card.pressed.connect(func() -> void:
				var act := _pending
				_pending = Callable()
				_do(str(act.call(id))))
			box.add_child(card)


func _draw_portrait(s: GameSession, data: Dictionary) -> void:
	_clear(_portrait)
	var c := s.character
	var name_l := Label.new()
	name_l.text = str(c["name"])
	name_l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	name_l.theme_type_variation = UiTheme.HEADING
	_portrait.add_child(name_l)
	var bar := ProgressBar.new()
	bar.max_value = int(c["max_hp"])
	bar.value = int(c["hp"])
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 14)
	_portrait.add_child(bar)
	_line(_portrait, tr("SIDE_HP_AC").format({"hp": c["hp"], "max": c["max_hp"], "ac": c["ac"]}))
	var conds: Array = c.get("conditions", [])
	if not conds.is_empty():
		_line(_portrait, ", ".join(conds.map(func(x: Variant) -> String: return tr("COND_" + str(x).to_upper())))).add_theme_color_override("font_color", UiTheme.WARN)
	if not str(c.get("concentration", "")).is_empty():
		_line(_portrait, tr("SIDE_CONCENTRATION").format({"spell": data["spells"].get(str(c["concentration"]), {}).get("name", "")}))
	if bool(s.combat.get("raging", false)):
		_line(_portrait, tr("COMBAT_RAGING")).add_theme_color_override("font_color", UiTheme.BAD)
	if int(c["hp"]) <= 0:
		var ds: Dictionary = s.combat.get("death_saves", {})
		_line(_portrait, tr("COMBAT_DEATH_SAVES").format({"ok": int(ds.get("ok", 0)), "fail": int(ds.get("fail", 0))})).add_theme_color_override("font_color", UiTheme.BAD)


func _line(parent: Control, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)
	return l


func _draw_actions(s: GameSession, data: Dictionary, mine: bool) -> void:
	var e := CombatRules.economy(s)
	var mark := func(n: int, ch: String, key: String) -> String: return ("%s %s" % [ch, tr(key)]) if n > 0 else ("○ " + tr(key))
	_economy.text = "  ".join([mark.call(int(e.get("action", 0)) + int(e.get("attacks", 0)), "●", "COMBAT_ACTION"),
		mark.call(int(e.get("bonus", 0)), "▲", "COMBAT_BONUS"), tr("COMBAT_MOVE").format({"n": int(e.get("move", 0))})])
	_clear(_tabs)
	var c := s.character
	# Weapons.
	var w := _tab_box("COMBAT_TAB_WEAPONS")
	var main := CombatRules.weapon_profile(c, data, s.items, str(c.get("equipped", {}).get("main_hand", "")))
	_action(w, "Attack_main", tr("COMBAT_ATTACK").format({"name": main["name"], "hit": "%+d" % int(main["to_hit"]), "dmg": _dmg_text(main)}), mine,
		func(t: String) -> String: return GameState.combat_attack(t, false),
		func(t: String) -> String: return CombatRules.can_attack(s, data, t, false))
	var off := str(c.get("equipped", {}).get("off_hand", ""))
	if not off.is_empty():
		var ow := CombatRules.weapon_profile(c, data, s.items, off, true)
		_action(w, "Attack_off", tr("COMBAT_ATTACK_OFF").format({"name": ow["name"], "dmg": _dmg_text(ow)}), mine,
			func(t: String) -> String: return GameState.combat_attack(t, true),
			func(t: String) -> String: return CombatRules.can_attack(s, data, t, true))
	# Spells.
	if not SpellRules.ready(c).is_empty():
		var sp := _tab_box("COMBAT_TAB_SPELLS")
		for id: String in SpellRules.ready(c):
			var spell: Dictionary = data["spells"].get(id, {})
			var lv := int(spell.get("level", 0))
			var slot := 0 if lv == 0 else SpellRules.lowest_slot(c, data, id)
			var cost := tr("COMBAT_BONUS_SHORT") if CombatRules.spell_cost(data, id) == "bonus" else ""
			var label := "%s%s%s" % [spell.get("name", id), (" (%d)" % slot) if slot > 0 else "", cost]
			if lv > 0 and slot == 0:
				_disabled(sp, label)
				continue
			if spell.has("heal_at_slot") or int(spell.get("range_ft", 0)) == 0 and not spell.has("area"):
				var b := _button(sp, "Cast_" + id, label, mine)
				b.tooltip_text = str(spell.get("desc", "")).left(500)
				b.pressed.connect(func() -> void: _do(GameState.combat_cast(id, slot, "")))
			else:
				var ab := _action(sp, "Cast_" + id, label, mine, func(t: String) -> String: return GameState.combat_cast(id, slot, t),
					func(t: String) -> String: return CombatRules.can_cast(s, data, id, slot, t))
				ab.tooltip_text = str(spell.get("desc", "")).left(500)
	# Features.
	var res := FeatureUses.lines(c, data)
	if not res.is_empty():
		var fb := _tab_box("COMBAT_TAB_FEATURES")
		for r: Dictionary in res:
			var b := _button(fb, "Feature_" + str(r["id"]), "%s (%d/%d)" % [r["name"], r["left"], r["max"]], mine and int(r["left"]) > 0)
			var rid := str(r["id"])
			b.pressed.connect(func() -> void: _do(GameState.combat_use_feature(rid)))
	# Items.
	var usable: Array[String] = []
	for id: String in c.get("inventory", {}):
		if not ItemRules.consumable(data, id).is_empty():
			usable.append(id)
	if not usable.is_empty():
		var ib := _tab_box("COMBAT_TAB_ITEMS")
		for id: String in usable:
			var b := _button(ib, "Item_" + id, "%s ×%d" % [ItemRules.display_name(data["items"], s.items, id), int(c["inventory"][id])], mine)
			b.pressed.connect(func() -> void: _do(GameState.combat_use_item(id)))
	# Common.
	var g := _tab_box("COMBAT_TAB_COMMON")
	for what: String in ["dash", "dodge", "disengage"]:
		var b := _button(g, "Do_" + what, tr("COMBAT_DO_" + what.to_upper()), mine)
		b.pressed.connect(func() -> void: _do(GameState.combat_simple(what)))
	_tabs.current_tab = clampi(_tab, 0, _tabs.get_tab_count() - 1)


func _dmg_text(w: Dictionary) -> String:
	var b := int(w["bonus"])
	return "%s%s" % [str(w["dice"]).replace("d", tr("DICE_D")), ("%+d" % b) if b != 0 else ""]


func _tab_box(title: String) -> HFlowContainer:
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
	b.name = node_name
	b.text = text
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.custom_minimum_size = Vector2(0, 52)
	b.disabled = not enabled
	parent.add_child(b)
	return b


func _disabled(parent: Control, text: String) -> void:
	_button(parent, "", text, false)


## A button that needs a target: pressing it lights the cards that can be hit.
func _action(parent: Control, node_name: String, text: String, enabled: bool, act: Callable, check: Callable) -> Button:
	var b := _button(parent, node_name, text, enabled)
	b.toggle_mode = true
	b.button_pressed = _pending.is_valid() and _pending_name == node_name
	b.pressed.connect(func() -> void:
		if _pending.is_valid() and _pending_name == node_name:
			_pending = Callable()
		else:
			_pending = act
			_pending_check = check
			_pending_name = node_name
		_refresh())
	return b


var _pending_name := ""


func _draw_results(s: GameSession, data: Dictionary) -> void:
	var outcome := str(s.combat.get("outcome", ""))
	var show := not outcome.is_empty() and outcome != "dead" and bool(s.combat.get("narrated", false)) and not GameState.is_busy()
	_results.visible = show
	if not show:
		return
	_clear(_results_box)
	var t := Label.new()
	t.text = tr("COMBAT_OUTCOME_" + outcome.to_upper())
	t.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	t.theme_type_variation = UiTheme.HEADING
	_results_box.add_child(t)
	if int(s.combat.get("xp", 0)) > 0:
		_line(_results_box, tr("COMBAT_XP").format({"xp": int(s.combat["xp"])}))
	if int(s.combat.get("coins_cp", 0)) > 0:
		_line(_results_box, tr("COMBAT_COINS").format({"coins": Money.format(int(s.combat["coins_cp"]))}))
	var picks: Array[CheckBox] = []
	if not (s.combat.get("loot", []) as Array).is_empty():
		_line(_results_box, tr("COMBAT_LOOT")).add_theme_color_override("font_color", UiTheme.ACCENT)
		for l: Dictionary in s.combat["loot"]:
			var cb := CheckBox.new()
			cb.name = "Loot_" + str(l["item_id"])
			cb.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			cb.text = "%s ×%d" % [ItemRules.display_name(data["items"], s.items, str(l["item_id"])), int(l["qty"])]
			cb.set_meta("item_id", str(l["item_id"]))
			cb.button_pressed = true
			_results_box.add_child(cb)
			picks.append(cb)
	var go := Button.new()
	go.name = "FinishCombat"
	go.text = "BTN_CONTINUE"
	go.theme_type_variation = UiTheme.ACCENT_BUTTON
	go.custom_minimum_size = Vector2(0, 60)
	go.pressed.connect(func() -> void:
		var take: Array = []
		for cb: CheckBox in picks:
			if cb.button_pressed:
				take.append(cb.get_meta("item_id"))
		GameState.finish_combat(take))
	_results_box.add_child(go)
