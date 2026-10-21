class_name GameScreen
extends Control
## The game: chat on the left (narration, NPC lines, checks, effects, options, input), side panel on the right.
## In social / trade mode a bar above the chat shows the partner card (name, role, race, attitude — no portraits),
## switches a trader between talk and the deal panel, and ends the conversation. In trade mode the deal panel
## stands next to the chat.
## Input is locked while the master thinks or the connection is down; Esc opens the pause menu.

var chat: ChatView
var input: LineEdit
var send_button: Button
var _options: HFlowContainer
var _thinking: Label
var _cancel: Button
var _offline_banner: Label
var _pause: PauseMenu
var _sheet: CharacterSheet
var _map: WorldNotes
var _journal: WorldNotes
var _level_up: LevelUpView
var _short_rest: SmallDialog
var _long_rest: SmallDialog
var _chips: EffectChips
var _theft: TheftPanel
var _prepare: SmallDialog
var _mode_bar: HBoxContainer
var _mode_label: Label
var _partner_line: Label
var trade_toggle: Button
var leave_button: Button
var trade_panel: TradePanel
var _attach_menu: MenuButton  # v0.7.7: a spell, feature or consumable pinned to the message
var _attach_chip: HBoxContainer
var _attach_choices: Array[Dictionary] = []


func _ready() -> void:
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 32)
	margin.add_child(row)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 3.0
	left.add_theme_constant_override("separation", 14)
	row.add_child(left)
	_offline_banner = Label.new()
	_offline_banner.text = "BANNER_NO_MASTER"
	_offline_banner.add_theme_color_override("font_color", UiTheme.WARN)
	_offline_banner.visible = false
	left.add_child(_offline_banner)
	_mode_bar = HBoxContainer.new()
	_mode_bar.add_theme_constant_override("separation", 16)
	left.add_child(_mode_bar)
	var card := VBoxContainer.new()
	card.name = "PartnerCard"
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_constant_override("separation", 2)
	_mode_bar.add_child(card)
	_mode_label = Label.new()
	_mode_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_mode_label.theme_type_variation = UiTheme.HEADING
	card.add_child(_mode_label)
	_partner_line = Label.new()
	_partner_line.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_partner_line.theme_type_variation = UiTheme.MUTED_LABEL
	card.add_child(_partner_line)
	trade_toggle = Button.new()
	trade_toggle.name = "TradeToggle"
	trade_toggle.pressed.connect(func() -> void: GameState.set_trade(GameState.session.mode != GameSession.MODE_TRADE))
	_mode_bar.add_child(trade_toggle)
	leave_button = Button.new()
	leave_button.name = "LeaveButton"
	leave_button.text = "BTN_LEAVE_CONVERSATION"
	leave_button.pressed.connect(GameState.leave_conversation)
	_mode_bar.add_child(leave_button)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 20)
	left.add_child(body)
	chat = ChatView.new()
	chat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(chat)
	trade_panel = TradePanel.new()
	trade_panel.name = "TradePanel"
	trade_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	trade_panel.size_flags_stretch_ratio = 1.2
	trade_panel.visible = false
	body.add_child(trade_panel)

	var status_row := HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 16)
	left.add_child(status_row)
	_thinking = Label.new()
	_thinking.text = "MSG_MASTER_THINKING"
	_thinking.theme_type_variation = UiTheme.MUTED_LABEL
	status_row.add_child(_thinking)
	_cancel = Button.new()
	_cancel.text = "BTN_CANCEL_TURN"
	_cancel.pressed.connect(GameState.cancel_turn)
	status_row.add_child(_cancel)

	_options = HFlowContainer.new()
	_options.add_theme_constant_override("h_separation", 12)
	_options.add_theme_constant_override("v_separation", 12)
	left.add_child(_options)

	_chips = EffectChips.new()  # what is on the hero, over the input (v0.7.8)
	left.add_child(_chips)
	var input_row := HBoxContainer.new()
	input_row.add_theme_constant_override("separation", 12)
	left.add_child(input_row)
	# The pin button sits in the input row like «attach a file» in a messenger (v0.7.7 fixes, the author).
	_attach_menu = MenuButton.new()
	_attach_menu.name = "AttachButton"
	_attach_menu.text = "✦"
	_attach_menu.flat = false
	_attach_menu.tooltip_text = "BTN_ATTACH"
	_attach_menu.custom_minimum_size = Vector2(60, 60)
	_attach_menu.add_theme_font_size_override("font_size", 28)
	_attach_menu.about_to_popup.connect(_fill_attach_menu)
	input_row.add_child(_attach_menu)
	input = LineEdit.new()
	input.name = "Input"
	input.placeholder_text = "PLACEHOLDER_ACTION"
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.custom_minimum_size = Vector2(0, 60)
	input.text_submitted.connect(func(_t: String) -> void: _send())
	input_row.add_child(input)
	send_button = Button.new()
	send_button.text = "BTN_SEND"
	send_button.theme_type_variation = UiTheme.ACCENT_BUTTON
	send_button.custom_minimum_size = Vector2(180, 60)
	send_button.pressed.connect(_send)
	input_row.add_child(send_button)
	# What is pinned: a chip under the input, out of the chat.
	_attach_chip = HBoxContainer.new()
	_attach_chip.name = "AttachChip"
	_attach_chip.add_theme_constant_override("separation", 8)
	left.add_child(_attach_chip)

	var side := SidePanel.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.size_flags_stretch_ratio = 1.0
	side.menu_requested.connect(func() -> void: _pause.open())
	side.sheet_requested.connect(func() -> void: _sheet.open())
	side.map_requested.connect(func() -> void: _map.open())
	side.journal_requested.connect(func() -> void: _journal.open())
	side.level_up_requested.connect(func() -> void: _level_up.open())
	side.short_rest_requested.connect(func() -> void: _short_rest.open())
	side.long_rest_requested.connect(func() -> void: _long_rest.open())
	side.pockets_requested.connect(func(npc: String) -> void: _theft.open(npc))
	row.add_child(side)

	_sheet = CharacterSheet.new()
	_sheet.name = "CharacterSheet"
	_sheet.visible = false
	add_child(_sheet)
	_sheet.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_map = WorldNotes.new(WorldNotes.MAP)
	_map.name = "MapView"
	_journal = WorldNotes.new(WorldNotes.JOURNAL)
	_journal.name = "JournalView"
	for v: WorldNotes in [_map, _journal]:
		v.visible = false
		add_child(v)
		v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_short_rest = SmallDialog.new(SmallDialog.SHORT_REST)
	_short_rest.name = "ShortRestView"
	_prepare = SmallDialog.new(SmallDialog.PREPARE)
	_prepare.name = "PrepareView"
	_long_rest = SmallDialog.new(SmallDialog.LONG_REST)
	_long_rest.name = "LongRestView"
	for v: SmallDialog in [_short_rest, _prepare, _long_rest]:
		v.visible = false
		add_child(v)
		v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_theft = TheftPanel.new()
	_theft.name = "TheftView"
	_theft.visible = false
	add_child(_theft)
	_theft.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sheet.prepare_requested.connect(func() -> void:
		_sheet.visible = false
		_prepare.open())

	_level_up = LevelUpView.new()
	_level_up.name = "LevelUpView"
	_level_up.visible = false
	add_child(_level_up)
	_level_up.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_pause = PauseMenu.new()
	_pause.visible = false
	add_child(_pause)
	_pause.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	EventBus.turn_started.connect(_on_turn_started)
	EventBus.turn_finished.connect(_on_turn_finished)
	EventBus.options_changed.connect(_on_options_changed)
	EventBus.backend_state_changed.connect(_on_backend_state_changed)
	EventBus.state_changed.connect(_refresh)
	_refresh()
	input.grab_focus.call_deferred()


# _input, not _unhandled_input: the focused chat LineEdit would swallow Esc.
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause_menu"):
		var overlays: Array[Control] = [_sheet, _map, _journal, _level_up, _short_rest, _prepare, _long_rest, _theft]
		var open := overlays.filter(func(o: Control) -> bool: return o.visible)
		if not open.is_empty():
			for o: Control in open:
				o.visible = false
		else:
			_pause.toggle()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("character_sheet") and not input.has_focus():
		_sheet.visible = not _sheet.visible
		get_viewport().set_input_as_handled()


func _on_turn_started(_turn_id: String) -> void:
	_refresh()


func _on_turn_finished(_turn_id: String, _ok: bool) -> void:
	_refresh()
	if Backend.is_ready():
		input.grab_focus()


func _on_options_changed(_options_list: Array[String]) -> void:
	_refresh()


func _on_backend_state_changed(_state: int, _detail: String) -> void:
	_refresh()


func _send() -> void:
	if GameState.submit(input.text):
		input.clear()


func _refresh() -> void:
	var busy := GameState.is_busy()
	var online := Backend.is_ready()
	_thinking.visible = busy
	_cancel.visible = busy and online
	_offline_banner.visible = not online
	input.editable = online and not busy
	send_button.disabled = not online or busy
	var s := GameState.session if GameState.has_session() else null
	_chips.refresh()
	_mode_bar.visible = s != null and s.in_conversation()
	trade_panel.visible = s != null and s.mode == GameSession.MODE_TRADE
	if _mode_bar.visible:
		var npc := GameState.world().npc(s.npc_id)
		var npc_name := str(npc.get("name", s.npc_id))
		_mode_label.text = npc_name
		var bounds := GameSession.attitude_bounds(Catalog.data)
		var att := clampi(s.attitude(s.npc_id), bounds.x, bounds.y)
		_partner_line.text = tr("PARTNER_LINE").format({"role": npc.get("role", ""), "race": npc.get("race", ""),
			"attitude": tr("ATTITUDE_" + ("M%d" % -att if att < 0 else "P%d" % att if att > 0 else "0"))})
		trade_toggle.visible = GameState.world().is_trader(s.npc_id)
		trade_toggle.text = tr("BTN_TO_TALK" if s.mode == GameSession.MODE_TRADE else "BTN_TO_TRADE")
		trade_toggle.disabled = busy or (s.mode != GameSession.MODE_TRADE and TimeRules.shops_closed(s, Catalog.data))
		trade_toggle.tooltip_text = tr("SHOP_CLOSED") if trade_toggle.disabled and not busy else ""
		leave_button.disabled = busy or not online
		input.placeholder_text = tr("PLACEHOLDER_SAY").format({"name": npc_name.get_slice(" ", 0)})
	else:
		input.placeholder_text = tr("PLACEHOLDER_ACTION")
	_refresh_attach(s, busy, online)
	for c in _options.get_children():
		_options.remove_child(c)
		c.queue_free()
	if busy or not GameState.has_session():
		return
	if GameState.can_retry():
		_option_button("BTN_RETRY_TURN", GameState.retry, true).disabled = not online
	for i in GameState.session.options.size():
		var o := GameState.session.options[i]
		var cost := GameState.session.option_costs[i] if i < GameState.session.option_costs.size() else 0
		var b := _option_button(o + ((" (%s)" % Money.format(cost)) if cost > 0 else ""), func() -> void:
			var err := GameState.choose_option(i)
			if not err.is_empty():
				EventBus.message.emit(tr(err)), false)
		b.disabled = not online or (cost > 0 and int(GameState.session.character["gold_cp"]) < cost)


func _option_button(text: String, action: Callable, translate: bool) -> Button:
	var b := Button.new()
	b.text = text
	if not translate:
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.custom_minimum_size = Vector2(0, 52)
	b.pressed.connect(action)
	_options.add_child(b)
	return b


# --- attached spells, features, consumables (v0.7.7) ---------------------------------------------------------


## The menu of what can be pinned: three submenus — spells, features, items (v0.7.7 fixes: all of them).
func _fill_attach_menu() -> void:
	var pop := _attach_menu.get_popup()
	pop.clear()
	for child in pop.get_children():
		pop.remove_child(child)
		child.queue_free()
	_attach_choices = GameState.attach_choices()
	for group: Array in [["ATTACH_GROUP_SPELL", ["spell"]], ["ATTACH_GROUP_FEATURE", ["feature", "feature_note"]], ["ATTACH_GROUP_ITEM", ["item", "item_note"]]]:
		var sub := PopupMenu.new()
		sub.name = "AttachSub_" + str(group[0])
		sub.id_pressed.connect(_on_attach_picked)
		for i in _attach_choices.size():
			var ch: Dictionary = _attach_choices[i]
			if (group[1] as Array).has(str(ch["kind"])):
				sub.add_item(str(ch["name"]), i)
				sub.set_item_disabled(sub.item_count - 1, bool(ch.get("off", false)))
		if sub.item_count == 0:
			sub.add_item(tr("ATTACH_NOTHING"), -1)
			sub.set_item_disabled(0, true)
		pop.add_submenu_node_item(tr(str(group[0])), sub)


func _on_attach_picked(index: int) -> void:
	if index < 0 or index >= _attach_choices.size():
		return
	var ch: Dictionary = _attach_choices[index]
	var slots: Array = ch["slots"]
	GameState.attach(str(ch["kind"]), str(ch["id"]), int(slots[0]) if not slots.is_empty() else 0)
	input.grab_focus()


## The chip of the pinned thing: its name, the slot circle (spells), the target (an NPC here or none), «✕».
func _refresh_attach(s: GameSession, busy: bool, online: bool) -> void:
	for c in _attach_chip.get_children():
		_attach_chip.remove_child(c)
		c.queue_free()
	var usable := s != null and s.mode != GameSession.MODE_COMBAT
	_attach_menu.visible = usable
	_attach_menu.disabled = busy or not online
	var a := GameState.attached
	if not usable or a.is_empty():
		return
	var choice := {}
	for ch: Dictionary in GameState.attach_choices():
		if str(ch["kind"]) == str(a["kind"]) and str(ch["id"]) == str(a["id"]):
			choice = ch
	if choice.is_empty():  # spent or gone meanwhile
		GameState.attached = {}
		return
	var label := Label.new()
	label.name = "AttachName"
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.text = tr("ATTACH_PINNED").format({"name": choice["name"]})
	label.add_theme_color_override("font_color", UiTheme.ACCENT_BRIGHT)
	_attach_chip.add_child(label)
	var slots: Array = choice["slots"]
	if slots.size() > 1:
		var pick := OptionButton.new()
		pick.name = "AttachSlot"
		for circle: Variant in slots:
			pick.add_item(tr("ATTACH_SLOT").format({"n": int(circle)}), int(circle))
		pick.select(maxi(0, slots.find(int(a.get("slot", 0)))))
		pick.item_selected.connect(func(i: int) -> void:
			GameState.attached["slot"] = pick.get_item_id(i))
		_attach_chip.add_child(pick)
	var npcs := s.npcs_here(GameState.world().world, s.room_id)
	if not npcs.is_empty():
		var who := OptionButton.new()
		who.name = "AttachTarget"
		who.add_item(tr("ATTACH_NO_TARGET"))
		var ids: Array[String] = [""]
		for id: String in npcs:
			who.add_item(str(GameState.world().npc(id).get("name", id)))
			ids.append(id)
		who.select(maxi(0, ids.find(str(a.get("target", "")))))
		who.item_selected.connect(func(i: int) -> void:
			GameState.attached["target"] = ids[i])
		_attach_chip.add_child(who)
	var drop := Button.new()
	drop.name = "AttachRemove"
	drop.text = "✕"
	drop.tooltip_text = "ATTACH_REMOVE"
	drop.pressed.connect(GameState.detach)
	_attach_chip.add_child(drop)
	input.placeholder_text = tr("PLACEHOLDER_ATTACHED")
