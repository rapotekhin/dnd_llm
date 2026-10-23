class_name CombatScreen
extends Control
## The fight (roadmap v0.6.1, ADR-0010 §7): the initiative order on top, the field of 7 columns of 30 ft, the
## player's panel below like in BG3 (portrait block, action / bonus / move, tabs of actions, «Конец хода»), the
## log and free input on the right. An action that needs a target lights the cards that can be hit; a click on a
## card does it, hovering it shows the chance to hit and the damage (v0.6.2). Reinforcements wait grey at the edge
## column with the rounds left. The results (XP, loot to take) or the death screen come when the fight ends.

var _details: DetailsPanel  # v0.7.7 fixes: what a spell, feature, item or foe is (hover or press)
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
## «Использовать?» — a choice of a feature or a reaction, as in Baldur's Gate 3 (v0.7.10).
var _ask: PanelContainer
var _conc_ask: Dictionary = {}  # v0.7.13.1: the «Прервать …?» question
var _ask_box: VBoxContainer
## The action waiting for a target: Callable(target_id) -> String (a reason or ""), and its check.
var _pending: Callable
var _pending_check: Callable
## Callable(target_id) -> Dictionary: the hint of the pending action (CombatRules.attack_preview / cast_preview).
var _pending_preview: Callable
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
	_hint.name = "Hint"
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
	_details = DetailsPanel.new(Vector2(0, 240))
	_details.name = "CombatDetails"
	rcol.add_child(_details)
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
	var mine := CombatRules.player_can_act(s) and not GameState.is_busy() and Backend.is_ready()
	if mine and not _pending.is_valid() and not CombatRules.volley(s).is_empty():  # v0.7.22.4: the next dart is armed at once
		_pending = func(t: String) -> String: return GameState.combat_volley(t)
		_pending_check = func(t: String) -> String: return CombatRules.can_volley(s, data, t)
		_pending_preview = func(_t: String) -> Dictionary: return {}
		_pending_name = "Volley"
	_thinking.visible = not GameState.busy_turn.is_empty()
	_retry.visible = GameState.can_retry()
	input.editable = mine
	send_button.disabled = not mine
	end_turn.disabled = not mine
	for b: String in ["MoveLeft", "MoveRight"]:
		var mb := find_child(b, true, false) as Button
		var why := CombatRules.can_move(s, data, -1 if b == "MoveLeft" else 1)  # prone, held, afraid (v0.7.8)
		mb.disabled = not mine or not why.is_empty()
		mb.tooltip_text = tr(why) if not why.is_empty() and why != "COMBAT_NOT_YOUR_TURN" else ""
	_draw_queue(s)
	_draw_field(s, data, mine)
	_draw_portrait(s, data)
	_draw_actions(s, data, mine)
	_hint.text = _base_hint(mine)
	_draw_results(s, data)
	_draw_ask(s)


func _base_hint(mine: bool) -> String:
	return tr("COMBAT_PICK_TARGET") if _pending.is_valid() else (tr("COMBAT_YOUR_TURN") if mine else tr("COMBAT_WAIT"))


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
		var zone_names := SpellEffects.zone_names(s, col)  # v0.7.13.5: Moonbeam, Spirit Guardians…
		if not zone_names.is_empty():
			head.text += "\n" + ", ".join(zone_names)
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
			if str(f.get("side")) != "enemy" or CombatRules.shown_col(f) != col:
				continue
			var card := Button.new()
			card.name = "Foe_" + id
			card.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			card.custom_minimum_size = Vector2(0, 76)
			var conds: Array = CombatRules.foe_conditions(data, f)
			if bool(f.get("surprised", false)):
				conds.append(tr("COMBAT_FOE_SURPRISED"))
			card.text = "%s\n%s%s" % [f["name"], tr(CombatRules.health_key(f)), ("\n" + ", ".join(conds)) if not conds.is_empty() else ""]
			card.tooltip_text = str(f.get("desc", ""))
			var lore := CombatRules.monster_card(s, data, f)
			var about := lore if not lore.is_empty() else tr("COMBAT_FOE_UNKNOWN")
			if not str(f.get("desc", "")).is_empty():
				about += "\n\n" + str(f["desc"])
			var foe_name := str(f["name"])
			card.mouse_entered.connect(func() -> void: _details.show_text(foe_name, about))
			if not lore.is_empty():
				card.tooltip_text = lore + "\n\n" + card.tooltip_text
				card.text += "\nHP %d/%d · КД %d" % [int(f["hp"]), int(f["max_hp"]), int(f["ac"])]
			var why := "COMBAT_NO_ACTION"
			if _pending.is_valid() and str(f.get("status")) == "active":
				why = str(_pending_check.call(id))
			card.disabled = not (mine and _pending.is_valid() and why.is_empty())
			if _pending.is_valid() and not why.is_empty() and str(f.get("status")) == "active":
				card.tooltip_text = tr(why)
			elif str(f.get("status")) == "active":
				var hint := ""
				if _pending_preview.is_valid() and _pending.is_valid():
					hint = _preview_text(_pending_preview.call(id))
				else:  # no action picked: the main weapon, or why it cannot reach
					var reach := CombatRules.can_attack(s, data, id)
					hint = tr(reach) if reach in ["COMBAT_OUT_OF_REACH", "COMBAT_OUT_OF_RANGE"] else _preview_text(CombatRules.attack_preview(s, data, id))
				if not hint.is_empty():
					card.tooltip_text = hint + ("\n\n" + card.tooltip_text if not card.tooltip_text.is_empty() else "")
					var title := str(f["name"])
					card.mouse_entered.connect(func() -> void: _hint.text = "%s: %s" % [title, hint.replace("\n", " · ")])
					card.mouse_exited.connect(func() -> void: _hint.text = _base_hint(mine))
			card.pressed.connect(func() -> void:
				var act := _pending
				_pending = Callable()
				_do(str(act.call(id))))
			box.add_child(card)
		for w: Dictionary in s.combat.get("incoming", []):
			if int(w["col"]) != col:
				continue
			var ghost := Label.new()
			ghost.name = "Incoming_%d" % col
			ghost.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			ghost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			ghost.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			ghost.add_theme_color_override("font_color", UiTheme.MUTED)
			ghost.text = tr("COMBAT_INCOMING").format({"names": "\n".join(w["names"]), "n": maxi(1, int(w["at"]) - int(s.combat.get("round", 1)))})
			box.add_child(ghost)


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
	_line(_portrait, tr("SIDE_HP_AC").format({"hp": c["hp"], "max": c["max_hp"], "ac": c["ac"]}) \
		+ ((" · +%d врем." % int(c["temp_hp"])) if int(c.get("temp_hp", 0)) > 0 else ""))
	if c.has("wild_shape"):  # v0.7.10
		_line(_portrait, tr("COMBAT_WILD_SHAPE_LINE").format({"beast": data["monsters"].get(str(c["wild_shape"]["monster"]), {}).get("name", ""),
			"hp": int(c["wild_shape"]["hp"]), "max": int(c["wild_shape"]["max_hp"])})).add_theme_color_override("font_color", UiTheme.ACCENT)
	if bool(s.combat.get("reckless", false)):
		_line(_portrait, tr("COMBAT_RECKLESS")).add_theme_color_override("font_color", UiTheme.BAD)
	var chips := EffectChips.new()  # conditions, boons, exhaustion, concentration (v0.7.8)
	_portrait.add_child(chips)
	chips.refresh()
	if bool(s.combat.get("raging", false)):
		_line(_portrait, tr("COMBAT_RAGING")).add_theme_color_override("font_color", UiTheme.BAD)
	if bool(CombatRules.player(s).get("hidden", false)):
		_line(_portrait, tr("COMBAT_HIDDEN")).add_theme_color_override("font_color", UiTheme.ACCENT)
	if bool(CombatRules.player(s).get("surprised", false)):
		_line(_portrait, tr("COMBAT_SURPRISED")).add_theme_color_override("font_color", UiTheme.WARN)
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
	var vol := CombatRules.volley(s)
	if not vol.is_empty():  # v0.7.22.4: the next dart or ray — pick its target (armed at once)
		var vname := str(data["spells"][str(vol["spell"])]["name"])
		var vb := _action(w, "Volley", tr("COMBAT_VOLLEY").format({"spell": vname, "n": int(vol["left"])}), mine,
			func(t: String) -> String: return GameState.combat_volley(t),
			func(t: String) -> String: return CombatRules.can_volley(s, data, t), func(_t: String) -> Dictionary: return {})
		vb.theme_type_variation = UiTheme.ACCENT_BUTTON
	var main := CombatRules.weapon_profile(c, data, s.items, str(c.get("equipped", {}).get("main_hand", "")))
	var main_id := str(c.get("equipped", {}).get("main_hand", ""))
	var main_b := _action(w, "Attack_main", tr("COMBAT_ATTACK").format({"name": main["name"], "hit": "%+d" % int(main["to_hit"]), "dmg": _dmg_text(main)}), mine,
		func(t: String) -> String: return GameState.combat_attack(t, false),
		func(t: String) -> String: return CombatRules.can_attack(s, data, t, false),
		func(t: String) -> Dictionary: return CombatRules.attack_preview(s, data, t, false))
	if not main_id.is_empty():
		_details.hook(main_b, str(main["name"]), DetailsPanel.item_text(c, data, s.items, main_id))
	var off := str(c.get("equipped", {}).get("off_hand", ""))
	if not off.is_empty():
		var ow := CombatRules.weapon_profile(c, data, s.items, off, true)
		_action(w, "Attack_off", tr("COMBAT_ATTACK_OFF").format({"name": ow["name"], "dmg": _dmg_text(ow)}), mine,
			func(t: String) -> String: return GameState.combat_attack(t, true),
			func(t: String) -> String: return CombatRules.can_attack(s, data, t, true),
			func(t: String) -> Dictionary: return CombatRules.attack_preview(s, data, t, true))
	# Spells.
	if not SpellRules.ready(c).is_empty() and not c.has("wild_shape"):
		var sp := _tab_box("COMBAT_TAB_SPELLS")
		for mm: Dictionary in FeatureRules.metamagic(c, data):  # v0.7.10: metamagic toggles of the next spell
			var mid := str(mm["id"])
			var mb := _button(sp, "Meta_" + mid, "✦ %s (%d)" % [mm["name"], int(mm["cost"])], mine and FeatureUses.left(c, data, "sorcery_points") >= int(mm["cost"]))
			mb.toggle_mode = true
			mb.button_pressed = str(s.combat.get("metamagic", "")) == mid
			mb.tooltip_text = tr("META_TIP_" + mid.to_upper())
			mb.pressed.connect(func() -> void: GameState.combat_metamagic(mid))
		for id: String in SpellRules.ready(c):
			var spell: Dictionary = data["spells"].get(id, {})
			var lv := int(spell.get("level", 0))
			var free := SpellRules.is_free(c, id)  # an invocation's spell at will (v0.7.22.4)
			var slot := 0 if lv == 0 or free else SpellRules.lowest_slot(c, data, id)
			var cost := tr("COMBAT_BONUS_SHORT") if CombatRules.spell_cost(data, id) == "bonus" else ""
			var label := "%s%s%s%s" % [spell.get("name", id), (" (%d)" % slot) if slot > 0 else "", tr("SPELL_AT_WILL_SHORT") if free else "", cost]
			if lv > 0 and slot == 0 and not free:
				_disabled(sp, label)
				continue
			if spell.has("heal_at_slot") or SpellEffects.self_spell(data, id) or int(spell.get("range_ft", 0)) == 0 and not spell.has("area"):
				var b := _button(sp, "Cast_" + id, label, mine)
				_details.hook(b, str(spell.get("name", id)), DetailsPanel.spell_text(data, id))
				b.pressed.connect(func() -> void: _do(_conc_guard(id, func() -> String: return GameState.combat_cast(id, slot, ""))))
			else:
				var ab := _action(sp, "Cast_" + id, label, mine,
					func(t: String) -> String: return _conc_guard(id, func() -> String: return GameState.combat_cast(id, slot, t)),
					func(t: String) -> String: return CombatRules.can_cast(s, data, id, slot, t),
					func(t: String) -> Dictionary: return CombatRules.cast_preview(s, data, id, slot, t))
				_details.hook(ab, str(spell.get("name", id)), DetailsPanel.spell_text(data, id))
		for sa: Dictionary in SpellEffects.actions(s, data):  # v0.7.13.5: the spells that go on each turn
			var said := str(sa["id"])
			var slabel := "%s%s" % [sa["name"], tr("COMBAT_BONUS_SHORT") if str(sa["cost"]) == "bonus" else ""]
			if bool(sa["target"]):
				var stb := _action(sp, "Feat_" + said, slabel, mine, func(t: String) -> String: return GameState.combat_feature(said, t),
					func(t: String) -> String: return FeatureRules.can_act(s, data, said, t), func(_t: String) -> Dictionary: return {})
				stb.tooltip_text = str(sa["tip"])
			else:
				var swhy := FeatureRules.can_act(s, data, said)
				var sub := _button(sp, "Feat_" + said, slabel, mine and swhy.is_empty())
				sub.tooltip_text = str(sa["tip"])
				sub.pressed.connect(func() -> void: _do(GameState.combat_feature(said)))
	# Features: limited uses with an action of their own, then the feature actions (v0.7.10).
	var res := FeatureUses.lines(c, data).filter(func(r: Dictionary) -> bool:
		return str(FeatureUses.table(data).get(str(r["id"]), {}).get("combat_cost", "action")) != "never")
	var feats := FeatureRules.actions(s, data).filter(func(a: Dictionary) -> bool: return not str(a["id"]).begins_with("spell_"))
	if not res.is_empty() or not feats.is_empty():
		var fb := _tab_box("COMBAT_TAB_FEATURES")
		for fa: Dictionary in feats:
			var fid := str(fa["id"])
			var label := "%s%s" % [fa["name"], tr("COMBAT_BONUS_SHORT") if str(fa["cost"]) == "bonus" else ""]
			if bool(fa["target"]):
				var tb := _action(fb, "Feat_" + fid, label, mine, func(t: String) -> String: return GameState.combat_feature(fid, t),
					func(t: String) -> String: return FeatureRules.can_act(s, data, fid, t), func(_t: String) -> Dictionary: return {})
				tb.tooltip_text = str(fa["tip"])
				_details.hook(tb, str(fa["name"]), str(fa["tip"]))
			else:
				var why := FeatureRules.can_act(s, data, fid)
				var ub := _button(fb, "Feat_" + fid, label, mine and why.is_empty())
				ub.tooltip_text = str(fa["tip"]) + (("\n" + tr(why)) if not why.is_empty() and why != "COMBAT_NOT_YOUR_TURN" else "")
				_details.hook(ub, str(fa["name"]), str(fa["tip"]))
				ub.pressed.connect(func() -> void: _do(GameState.combat_feature(fid)))
		for r: Dictionary in res:
			var b := _button(fb, "Feature_" + str(r["id"]), "%s (%d/%d)" % [r["name"], r["left"], r["max"]], mine and int(r["left"]) > 0)
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
				label = "%s (%d/%d)" % [d.get("name", id), ItemRules.charges_left(c, d, id), ItemRules.charges_max(d)]
			var sp_id := str(fx.get("spell", ""))
			var sp: Dictionary = data["spells"].get(sp_id, {})
			var item_btn: Button
			if fx.has("throw"):  # v0.7.12: flasks and the net at a foe
				item_btn = _action(ib, "Item_" + id, label, mine, func(t: String) -> String: return GameState.combat_throw(id, t),
					func(t: String) -> String: return CombatRules.can_throw(s, data, id, t), func(_t: String) -> Dictionary: return {})
			elif not sp_id.is_empty() and CombatRules.is_engine_spell(data, sp_id) and not sp.has("heal_at_slot") 					and (int(sp.get("range_ft", 0)) > 0 or sp.has("area")):
				item_btn = _action(ib, "Item_" + id, label, mine, func(t: String) -> String: return GameState.combat_item_spell(id, t),
					func(t: String) -> String: return CombatRules.can_item_spell(s, data, id, t), func(_t: String) -> Dictionary: return {})
			elif not sp_id.is_empty():
				item_btn = _button(ib, "Item_" + id, label, mine)
				item_btn.pressed.connect(func() -> void: _do(GameState.combat_item_spell(id, "")))
			else:
				if ItemRules.is_potion(data, s.items, id) and str(CombatRules.cfg(data).get("potion_cost", "action")) == "bonus":
					label += tr("COMBAT_BONUS_SHORT")  # v0.7.22.3: a potion — a bonus action
				item_btn = _button(ib, "Item_" + id, label, mine)
				item_btn.pressed.connect(func() -> void: _do(GameState.combat_use_item(id)))
			_details.hook(item_btn, str(d.get("name", id)), DetailsPanel.item_text(c, data, s.items, id))
	# Common.
	var g := _tab_box("COMBAT_TAB_COMMON")
	for what: String in ["dash", "dodge", "disengage"]:
		var b := _button(g, "Do_" + what, tr("COMBAT_DO_" + what.to_upper()), mine)
		b.pressed.connect(func() -> void: _do(GameState.combat_simple(what)))
	var ib := _action(g, "Do_inspect", tr("COMBAT_DO_INSPECT"), mine,
		func(t: String) -> String: return GameState.combat_inspect(t),
		func(t: String) -> String: return CombatRules.can_inspect(s, data, t),
		func(_t: String) -> Dictionary: return {})
	ib.tooltip_text = tr("COMBAT_INSPECT_TIP")
	for shove: bool in [false, true]:
		var gb := _action(g, "Do_shove" if shove else "Do_grapple", tr("COMBAT_DO_SHOVE" if shove else "COMBAT_DO_GRAPPLE"), mine,
			func(t: String) -> String: return GameState.combat_grapple(t, shove),
			func(t: String) -> String: return CombatRules.can_grapple(s, data, t),
			func(_t: String) -> Dictionary: return {})
		gb.tooltip_text = tr("COMBAT_SHOVE_TIP" if shove else "COMBAT_GRAPPLE_TIP")
	if ConditionRules.has(c, "prone"):
		var sw := CombatRules.can_stand(s)
		var sb := _button(g, "Do_stand", tr("COMBAT_DO_STAND"), mine and sw.is_empty())
		sb.tooltip_text = tr(sw) if not sw.is_empty() else tr("COMBAT_STAND_TIP")
		sb.pressed.connect(func() -> void: _do(GameState.combat_stand()))
	if ConditionRules.has(c, "grappled") or ConditionRules.has(c, "restrained"):
		var ew := CombatRules.can_escape(s)
		var eb := _button(g, "Do_escape", tr("COMBAT_DO_ESCAPE"), mine and ew.is_empty())
		eb.tooltip_text = tr(ew) if not ew.is_empty() else tr("COMBAT_ESCAPE_TIP")
		eb.pressed.connect(func() -> void: _do(GameState.combat_escape()))
	if CharacterRules.has_feature(c, "frenzy") and bool(s.combat.get("raging", false)):
		if not bool(s.combat.get("frenzy", false)):
			var fw := CombatRules.can_frenzy(s)
			var frb := _button(g, "Do_frenzy", tr("COMBAT_DO_FRENZY"), mine and fw.is_empty())
			frb.tooltip_text = tr("COMBAT_FRENZY_TIP")
			frb.pressed.connect(func() -> void: _do(GameState.combat_frenzy()))
		else:
			_action(w, "Attack_frenzy", tr("COMBAT_ATTACK_FRENZY").format({"name": main["name"], "dmg": _dmg_text(main)}), mine,
				func(t: String) -> String: return GameState.combat_frenzy_attack(t),
				func(t: String) -> String: return CombatRules.can_frenzy_attack(s, data, t),
				func(t: String) -> Dictionary: return CombatRules.attack_preview(s, data, t, false))
	var hide_why := CombatRules.can_hide(s, data)
	var hb := _button(g, "Do_hide", tr("COMBAT_DO_HIDE"), mine and hide_why.is_empty())
	hb.tooltip_text = tr(hide_why) if not hide_why.is_empty() else tr("COMBAT_HIDE_TIP")
	hb.pressed.connect(func() -> void: _do(GameState.combat_hide()))
	for skill: String in CombatRules.cfg(data)["parley"]["skills"]:
		var why := CombatRules.can_parley(s, data, skill)
		if why.is_empty() and int(e.get("action", 0)) <= 0:
			why = "COMBAT_NO_ACTION"
		var pb := _button(g, "Parley_" + skill, tr("COMBAT_PARLEY").format({"skill": tr("SKILL_" + skill.to_upper())}), mine and why.is_empty())
		pb.tooltip_text = tr(why) if not why.is_empty() else "%s\n%s" % [tr("COMBAT_PARLEY_TIP_" + skill.to_upper()),
			tr("COMBAT_PARLEY_PROGRESS").format({"progress": CombatRules.parley_progress(s, data)})]
		pb.pressed.connect(func() -> void: _do(GameState.combat_parley(skill)))
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


## A button that needs a target: pressing it lights the cards that can be hit.
func _action(parent: Control, node_name: String, text: String, enabled: bool, act: Callable, check: Callable, preview: Callable) -> Button:
	var b := _button(parent, node_name, text, enabled)
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
		_refresh())
	return b


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
