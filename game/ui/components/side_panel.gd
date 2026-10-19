class_name SidePanel
extends PanelContainer
## Right panel of the game screen: the character (HP, AC, coins, inventory), where the player is,
## and the deterministic buttons the engine builds itself (ADR-0009 §4): exits and the NPCs of the room.

signal menu_requested
signal sheet_requested
signal map_requested
signal journal_requested
signal level_up_requested
signal short_rest_requested

var _content: VBoxContainer


func _ready() -> void:
	theme_type_variation = UiTheme.SIDE
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	add_child(col)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 10)
	scroll.add_child(_content)
	col.add_child(BackendStatus.new())
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 8)
	col.add_child(tools)
	for spec: Array in [["SheetButton", "BTN_CHARACTER_SHEET", sheet_requested], ["MapButton", "BTN_MAP", map_requested],
			["JournalButton", "BTN_JOURNAL", journal_requested]]:
		var b := Button.new()
		b.name = spec[0]
		b.text = spec[1]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 56)
		b.pressed.connect((spec[2] as Signal).emit)
		tools.add_child(b)
	var menu := Button.new()
	menu.text = "BTN_MENU"
	menu.custom_minimum_size = Vector2(0, 56)
	menu.pressed.connect(menu_requested.emit)
	col.add_child(menu)
	EventBus.state_changed.connect(_rebuild)
	EventBus.turn_started.connect(_on_turn)
	EventBus.turn_finished.connect(_on_turn_finished)
	EventBus.backend_state_changed.connect(_on_backend)
	_rebuild()


func _on_turn(_id: String) -> void:
	_rebuild()


func _on_turn_finished(_id: String, _ok: bool) -> void:
	_rebuild()


func _on_backend(_s: int, _d: String) -> void:
	_rebuild()


func _rebuild() -> void:
	# Detach before freeing: a queued node keeps its name, and the rebuilt button would get renamed.
	for c in _content.get_children():
		_content.remove_child(c)
		c.queue_free()
	if not GameState.has_session():
		return
	var s := GameState.session
	var c := s.character
	var items: Dictionary = Catalog.data["items"]
	var world := GameState.world()
	var can_act := Backend.is_ready() and not GameState.is_busy()

	_heading(str(c.get("name", "")))
	_line(tr("SIDE_RACE_CLASS").format({"race": c.get("race_name", ""), "class": c.get("class_name", ""), "level": int(c.get("level", 1))}), true)
	var hp := _line(tr("SIDE_HP_AC").format({"hp": c["hp"], "max": c["max_hp"], "ac": c["ac"]}), false)
	if int(c["hp"]) * 2 <= int(c["max_hp"]):
		hp.add_theme_color_override("font_color", UiTheme.BAD)
	_line(tr("SIDE_COINS").format({"coins": Money.format(int(c["gold_cp"]))}), false)
	var conditions: Array = c.get("conditions", [])
	if not conditions.is_empty():
		var cond := _line(tr("SIDE_CONDITIONS").format({"list": ", ".join(conditions.map(func(x: Variant) -> String: return tr("COND_" + str(x).to_upper())))}), false)
		cond.add_theme_color_override("font_color", UiTheme.WARN)
	if not str(c.get("concentration", "")).is_empty():
		_line(tr("SIDE_CONCENTRATION").format({"spell": Catalog.data["spells"].get(str(c["concentration"]), {}).get("name", "")}), true)
	var next_xp := LevelUp.xp_for(Catalog.data, int(c.get("level", 1)) + 1)
	if int(c.get("level", 1)) < LevelUp.max_level(c, Catalog.data):
		_line(tr("SIDE_XP").format({"xp": int(c.get("xp", 0)), "next": next_xp}), true)
	if LevelUp.can_level_up(c, Catalog.data):
		var lv := _button(tr("BTN_LEVEL_UP"), level_up_requested.emit, not GameState.is_busy())
		lv.name = "LevelUpButton"
		lv.theme_type_variation = UiTheme.ACCENT_BUTTON
		lv.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_line(tr("SIDE_DAY").format({"day": s.day}), true)
	var room := world.room(s.room_id)
	_subheading("SIDE_PLACE")
	_line("%s — %s" % [world.location(world.location_id(s.room_id)).get("name", ""), room.get("name", s.room_id)], false)
	if not s.in_conversation():
		var npcs := world.npcs_in(s.room_id)
		if not npcs.is_empty():
			_subheading("SIDE_PEOPLE")
			for id: String in npcs:
				var n := world.npc(id)
				var b := _button(tr("BTN_TALK_TO").format({"name": str(n.get("name", id)).get_slice(" ", 0)}), GameState.talk_to.bind(id, false), can_act)
				b.tooltip_text = "%s — %s" % [n.get("name", id), n.get("role", "")]
				b.name = "Talk_" + id
				if bool(n.get("trader", false)):
					var t := _button(tr("BTN_TRADE_WITH").format({"name": str(n.get("name", id)).get_slice(" ", 0)}), GameState.talk_to.bind(id, true), can_act)
					t.name = "Trade_" + id
		for qid: String in XpRules.quests_here(s, Catalog.data["world"]):
			var q: Dictionary = XpRules.quests(Catalog.data["world"])[qid]
			var qb := _button(tr("BTN_QUEST").format({"action": q["action"]}), func() -> void:
				var err := GameState.complete_quest(qid)
				if not err.is_empty():
					EventBus.message.emit(tr(err)), can_act)
			qb.name = "Quest_" + qid
			qb.tooltip_text = str(q["title"])
		_subheading("SIDE_EXITS")
		for e: String in world.exits(s.room_id):
			var b := _button("→ " + str(world.room(e).get("name", e)), GameState.go.bind(e), can_act)
			b.name = "Exit_" + e
		var place := ExplorationRules.rest_place(Catalog.data["world"], s.room_id)
		if not place.is_empty():
			var cost := int(place["cost_cp"])
			var rest := _button(tr("BTN_LONG_REST_COST").format({"cost": Money.format(cost)}) if cost > 0 else tr("BTN_LONG_REST"),
				func() -> void:
					var err := GameState.long_rest()
					if not err.is_empty():
						EventBus.message.emit(tr(err)), can_act)
			rest.name = "RestButton"
			rest.disabled = not can_act or not ExplorationRules.can_rest(s, Catalog.data["world"]).is_empty()
		var short := _button(tr("BTN_SHORT_REST"), short_rest_requested.emit, not GameState.is_busy())
		short.name = "ShortRestButton"
		var why := ExplorationRules.can_short_rest(s, Catalog.data)
		short.disabled = GameState.is_busy() or not why.is_empty()
		short.tooltip_text = tr(why) if not why.is_empty() else ""

	# Only what is worn and wielded; the full inventory is on the character sheet.
	_subheading("SIDE_INVENTORY")
	var inv: Dictionary = c.get("inventory", {})
	var shown := 0
	for slot: String in CharacterRules.SLOTS:
		var id := str(c.get("equipped", {}).get(slot, ""))
		if not id.is_empty():
			_line("◆ " + ItemRules.display_name(items, s.items, id), true)
			shown += 1
	if inv.size() > shown:
		_line(tr("SIDE_MORE_ITEMS").format({"n": inv.size() - shown}), true)


func _heading(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.theme_type_variation = UiTheme.HEADING
	_content.add_child(l)


func _subheading(key: String) -> void:
	var l := Label.new()
	l.text = key
	l.theme_type_variation = UiTheme.MUTED_LABEL
	l.add_theme_color_override("font_color", UiTheme.ACCENT)
	_content.add_child(l)


func _line(text: String, muted: bool) -> Label:
	var l := Label.new()
	l.text = text
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if muted:
		l.theme_type_variation = UiTheme.MUTED_LABEL
	_content.add_child(l)
	return l


func _button(text: String, action: Callable, enabled: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.disabled = not enabled
	b.pressed.connect(func() -> void: action.call())
	_content.add_child(b)
	return b
