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
var _track: Button  # the followed quest's step over the chat (v0.7.22.32)
var _theft: TheftPanel
var _container: ContainerPanel
var _place: PlacePanel
var _board: BoardPanel
var _craft: CraftPanel
var _jobs: JobPanel
var _property: PropertyPanel
var _bank: BankPanel
var _shop: ShopPanel
var _study: StudyPanel
var _bond: BondPanel
var _family: FamilyPanel
var _heists: HeistPanel
var _org: OrgPanel
var _office: OfficePanel
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
var _typed := true  # the last turn came from the input: its focus comes back after the turn (v0.7.22.27)


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
	_track = Button.new()
	_track.name = "QuestTrack"
	_track.flat = true
	_track.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_track.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_track.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_track.add_theme_color_override("font_color", UiTheme.ACCENT)
	_track.tooltip_text = "QUEST_TRACK_TIP"
	_track.pressed.connect(func() -> void:
		var qid := QuestRules.tracked(GameState.session, Catalog.data["world"])
		var rooms := WorldMap.step_rooms(GameState.session, Catalog.data["world"], qid)
		_map.open_at(rooms[0] if not rooms.is_empty() else ""))
	left.add_child(_track)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 20)
	left.add_child(body)
	chat = ChatView.new()
	chat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(chat)

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
	side.container_requested.connect(func(prop: String) -> void: _container.open(prop))
	side.place_requested.connect(func() -> void: _place.open())  # v0.7.22.7
	side.board_requested.connect(func(prop: String) -> void: _board.open(prop))  # v0.7.22.13
	side.development_requested.connect(func() -> void: _sheet.open_tab(3))  # v0.7.19.1
	side.craft_requested.connect(func() -> void: _craft.open())  # v0.7.24
	side.job_requested.connect(func(npc: String) -> void: _jobs.open(npc))  # v0.7.26
	side.property_requested.connect(func(mode: String, npc: String) -> void: _property.open(mode, npc))  # v0.7.27
	side.bank_requested.connect(func(npc: String) -> void: _bank.open(npc))  # v0.7.28
	side.shop_requested.connect(func(mode: String, id: String) -> void: _shop.open(mode, id))  # v0.7.29
	side.study_requested.connect(func(npc: String) -> void: _study.open(npc))  # v0.7.30
	side.bond_requested.connect(func(npc: String) -> void: _bond.open(npc))  # v0.7.31
	side.family_requested.connect(func() -> void: _family.open())  # v0.7.32
	side.heist_requested.connect(func() -> void: _heists.open())  # v0.7.33
	side.org_requested.connect(func(org: String) -> void: _org.open(org))
	side.office_requested.connect(func(chief: String) -> void: _office.open(chief))  # v0.7.34
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
	_container = ContainerPanel.new()  # v0.7.18.1
	_container.name = "ContainerView"
	_container.visible = false
	add_child(_container)
	_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	trade_panel = TradePanel.new()  # a screen of its own over everything (v0.7.22.10, the author: «как в BG3»)
	trade_panel.name = "TradePanel"
	trade_panel.visible = false
	add_child(trade_panel)
	trade_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_place = PlacePanel.new()  # v0.7.22.7: the things of the room
	_place.name = "PlaceView"
	_place.visible = false
	add_child(_place)
	_place.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_place.container_requested.connect(func(prop: String) -> void:
		_place.visible = false
		_container.open(prop))
	move_child(_container, -1)  # the container opens over the place window
	_board = BoardPanel.new()  # v0.7.22.13: a notice board's orders
	_board.name = "BoardView"
	_board.visible = false
	add_child(_board)
	_board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_craft = CraftPanel.new()  # v0.7.24
	_craft.name = "CraftView"
	_craft.visible = false
	add_child(_craft)
	_craft.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_jobs = JobPanel.new()  # v0.7.26
	_jobs.name = "JobView"
	_jobs.visible = false
	add_child(_jobs)
	_jobs.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_property = PropertyPanel.new()  # v0.7.27
	_property.name = "PropertyView"
	_property.visible = false
	add_child(_property)
	_property.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bank = BankPanel.new()  # v0.7.28
	_bank.name = "BankView"
	_bank.visible = false
	add_child(_bank)
	_bank.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shop = ShopPanel.new()  # v0.7.29
	_shop.name = "ShopView"
	_shop.visible = false
	add_child(_shop)
	_shop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_study = StudyPanel.new()  # v0.7.30
	_study.name = "StudyView"
	_study.visible = false
	add_child(_study)
	_study.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bond = BondPanel.new()  # v0.7.31
	_bond.name = "BondView"
	_bond.visible = false
	add_child(_bond)
	_bond.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_family = FamilyPanel.new()  # v0.7.32
	_family.name = "FamilyView"
	_family.visible = false
	add_child(_family)
	_family.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_heists = HeistPanel.new()  # v0.7.33
	_heists.name = "HeistView"
	_heists.visible = false
	add_child(_heists)
	_heists.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_org = OrgPanel.new()
	_org.name = "OrgView"
	_org.visible = false
	add_child(_org)
	_org.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_office = OfficePanel.new()  # v0.7.34
	_office.name = "OfficeView"
	_office.visible = false
	add_child(_office)
	_office.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sheet.bag_requested.connect(func(bag: String) -> void: _container.open(bag))  # v0.7.18.2
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
	for o: Control in _overlays() + [_pause]:
		o.visibility_changed.connect(func() -> void:  # an open window takes the keys from the input
			if o.visible:
				input.release_focus())


func _overlays() -> Array[Control]:
	return [_sheet, _map, _journal, _level_up, _short_rest, _prepare, _long_rest, _theft, _container, _craft, _jobs, _property, _bank, _shop, _study, _bond, _family, _heists, _org, _office]


# _input, not _unhandled_input: the focused chat LineEdit would swallow Esc.
# v0.7.22.27 (as in BG3): the keys work outside the input; Esc leaves the input, Enter or a letter comes back to it.
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.is_pressed() or event.is_echo():
		return
	var open := _overlays().filter(func(o: Control) -> bool: return o.visible)
	if get_window().get_node_or_null("ConfirmBox") != null:
		return
	if event.is_action_pressed("quick_save"):
		var err := GameState.quick_save()
		EventBus.message.emit(tr(err if not err.is_empty() else "MSG_QUICK_SAVED"))
	elif event.is_action_pressed("quick_load"):
		if GameState.is_busy() or not SaveManager.has_slot(SaveManager.QUICKSAVE):
			EventBus.message.emit(tr("MSG_NO_QUICKSAVE" if not GameState.is_busy() else "REST_BUSY"))
		else:
			GameEntry.enter({"kind": "load", "slot": SaveManager.QUICKSAVE})
	elif event.is_action_pressed("pause_menu"):
		if input.has_focus() and open.is_empty() and not _pause.visible:
			input.release_focus()
		elif not open.is_empty():
			for o: Control in open:
				o.visible = false
		else:
			_pause.toggle()
	elif input.has_focus() and input.text.is_empty() and open.is_empty() and _option_key(event) >= 0:  # 1–3 over an empty input
		_hotkey(event, true)
	elif input.has_focus() or _pause.visible or get_viewport().gui_get_focus_owner() is LineEdit:
		return
	elif _hotkey(event, open.is_empty()):
		pass
	elif (event as InputEventKey).keycode in [KEY_ENTER, KEY_KP_ENTER] and open.is_empty():
		input.grab_focus()
	elif (event as InputEventKey).unicode >= 32 and open.is_empty() and input.editable:  # typing goes to the input
		input.grab_focus()
		input.insert_text_at_caret(char((event as InputEventKey).unicode))
	else:
		return
	get_viewport().set_input_as_handled()


func _option_key(event: InputEvent) -> int:
	for i in 3:
		if event.is_action_pressed("option_%d" % (i + 1)):
			return i
	return -1


## A key of the game screen; false — not one.
func _hotkey(event: InputEvent, nothing_open: bool) -> bool:
	for tab: Array in [["character_sheet", 0], ["spells", 1], ["inventory", 2]]:
		if event.is_action_pressed(tab[0]):
			if _sheet.visible and _sheet.current_tab() == int(tab[1]):
				_sheet.visible = false
			else:
				_sheet.open_tab(int(tab[1]))
			return true
	for view: Array in [["map", _map], ["journal", _journal]]:
		if event.is_action_pressed(view[0]):
			if (view[1] as WorldNotes).visible:
				(view[1] as WorldNotes).visible = false
			else:
				(view[1] as WorldNotes).open()
			return true
	for i in 3:
		if event.is_action_pressed("option_%d" % (i + 1)):
			if nothing_open and not GameState.is_busy() and Backend.is_ready() and i < GameState.session.options.size():
				_typed = false
				var err := GameState.choose_option(i)
				if not err.is_empty():
					EventBus.message.emit(tr(err))
			return true
	return false


func _on_turn_started(_turn_id: String) -> void:
	_refresh()


func _on_turn_finished(_turn_id: String, _ok: bool) -> void:
	_refresh()
	if Backend.is_ready() and _typed and not _pause.visible and _overlays().all(func(o: Control) -> bool: return not o.visible):
		input.grab_focus()


func _on_options_changed(_options_list: Array[String]) -> void:
	_refresh()


func _on_backend_state_changed(_state: int, _detail: String) -> void:
	_refresh()


func _send() -> void:
	if GameState.submit(input.text):
		_typed = true
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
	var qid := QuestRules.tracked(s, Catalog.data["world"]) if s != null else ""
	_track.visible = not qid.is_empty()
	if _track.visible:
		_track.text = tr("QUEST_TRACK").format({"title": QuestRules.quest(Catalog.data["world"], qid).get("title", qid),
			"step": QuestRules.step_text(s, Catalog.data["world"], qid)})
	_mode_bar.visible = s != null and s.in_conversation()
	trade_panel.visible = s != null and s.mode == GameSession.MODE_TRADE
	if _mode_bar.visible:
		var npc := GameState.world().npc(s.npc_id)
		var npc_name := str(npc.get("name", s.npc_id))
		_mode_label.text = npc_name
		var bounds := GameSession.attitude_bounds(Catalog.data)
		var att := clampi(s.attitude(s.npc_id), bounds.x, bounds.y)
		_partner_line.text = tr("PARTNER_LINE").format({"role": npc.get("role", ""), "race": npc.get("race", ""),
			"body": BodyRules.npc_text(Catalog.data, s.npc_id, npc),
			"attitude": tr("ATTITUDE_" + ("M%d" % -att if att < 0 else "P%d" % att if att > 0 else "0"))})
		var bw := BondRules.word(s.character, Catalog.data, s.npc_id)  # v0.7.31
		if not bw.is_empty():
			_partner_line.text += " · " + bw
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
		var pv := GameState.option_preview(i)
		var tag := ("[%s] " % tr("SKILL_" + str(pv["skill"]).to_upper())) if not pv.is_empty() else ""
		var b := _option_button("%d. %s%s%s" % [i + 1, tag, o, (" (%s)" % Money.format(cost)) if cost > 0 else ""], func() -> void:
			_typed = false
			var err := GameState.choose_option(i)
			if not err.is_empty():
				EventBus.message.emit(tr(err)), false)
		b.disabled = not online or (cost > 0 and int(GameState.session.character["gold_cp"]) < cost)
		b.name = "Option_%d" % i
		var tip := ""
		if not pv.is_empty():  # the engine's DC and chance (v0.7.22.28, П5)
			tip = tr("OPTION_CHECK_TIP").format({"skill": tr("SKILL_" + str(pv["skill"]).to_upper()), "bonus": "%+d" % int(pv["bonus"]),
				"dc": int(pv["dc"]), "chance": int(pv["chance"])}) + ((" (%s)" % pv["dc_reason"]) if not str(pv["dc_reason"]).is_empty() else "")
		b.tooltip_text = Hotkeys.tip(tip, "option_%d" % (i + 1), SaveManager.keys) if i < 3 else tip
		if not pv.is_empty():
			b.add_theme_color_override("font_color", UiTheme.ACCENT_BRIGHT)


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
