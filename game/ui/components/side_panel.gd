class_name SidePanel
extends PanelContainer
## Right panel of the game screen: the character (HP, AC, coins, inventory), where the player is,
## and the deterministic buttons the engine builds itself (ADR-0009 §4): exits and the NPCs of the room.

signal menu_requested
signal sheet_requested

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
	var sheet := Button.new()
	sheet.name = "SheetButton"
	sheet.text = "BTN_CHARACTER_SHEET"
	sheet.custom_minimum_size = Vector2(0, 56)
	sheet.pressed.connect(sheet_requested.emit)
	col.add_child(sheet)
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
					_button(tr("BTN_TRADE_WITH").format({"name": str(n.get("name", id)).get_slice(" ", 0)}), GameState.talk_to.bind(id, true), can_act)
		_subheading("SIDE_EXITS")
		for e: String in world.exits(s.room_id):
			var b := _button("→ " + str(world.room(e).get("name", e)), GameState.go.bind(e), can_act)
			b.name = "Exit_" + e

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
