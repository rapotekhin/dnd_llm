class_name GameScreen
extends Control
## The one screen (v0.8.1): the hero and those here on the left, the map in its frame in the middle with the acts under it,
## the chat on the right. A conversation dims the map and puts the partner's big token on it; the deal panel opens over
## everything. A fight goes on this same field: FightUi takes the panels (v0.8.4).
## Input is locked while the master thinks or the connection is down; Esc opens the pause menu.

const SCENE := "res://ui/screens/game_screen.tscn"

var chat: ChatView
var input: ChatInput
var send_button: Button
var brush: BrushButton  # v0.7.35: the last event drawn
var _image: ImageCard
var _options: VBoxContainer
var _field: MapField
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
var _wilds: SmallDialog  # v0.7.41
var _wait: SmallDialog  # v0.8.4.2
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
var _contest: ContestPanel  # v0.7.40
var _arena: ArenaPanel  # v0.7.45
var _family: FamilyPanel
var _pet: PetPanel  # v0.7.43
var _letter: LetterPanel  # v0.7.48
var _faith: FaithPanel  # v0.7.49
var _heists: HeistPanel
var _org: OrgPanel
var _office: OfficePanel
var _prepare: SmallDialog
var _dim: ColorRect
var _talk_card: Control
var _partner_mark: Label
var _mode_label: Label
var _partner_line: Label
var trade_toggle: Button
var leave_button: Button
var trade_panel: TradePanel
var _attach_menu: MenuButton  # v0.7.7: a spell, feature or consumable pinned to the message
var _attach_chip: HBoxContainer
var _attach_choices: Array[Dictionary] = []
var _check_choices: Array[Dictionary] = []
var _typed := true  # the last turn came from the input: its focus comes back after the turn (v0.7.22.27)
var _was_fight := false  # a fight has just begun: the input lets go of the keys (v0.8.4.1)
var _goal := Vector2i.ZERO  # where the hero walks, past doors too
var _exit_to := ""  # the room beyond the way out at the end of the walk
var _beyond := ""  # the room behind the door the walk stops at
var _at_door := false  # the door waits for the end of the master's turn
var _things: Array[Dictionary] = []  # who and what stands on this map, seen or not
var _rounds := false  # a sneaking walk past those who watch goes by rounds (v0.8.3)
var _round_ends := false  # this walk is a round
var _after := Callable()  # the act at the end of the walk (v0.8.2)
var _menu: PanelContainer
var _menu_box: VBoxContainer
var _menu_ref := ""
var _side: SidePanel
var _field_room := ""  # the room the field showed last: a move inside it is walked, not jumped
var _fight: FightUi


func required() -> Dictionary:
	return {"%Side": "PanelContainer", "%Strip": "HBoxContainer", "%Field": "Control", "%Dim": "ColorRect", "%TalkCard": "CenterContainer",
		"%PartnerCard": "VBoxContainer", "%PartnerToken": "PanelContainer", "%PartnerMark": "Label", "%PartnerName": "Label", "%PartnerLine": "Label",
		"%Bar": "PanelContainer", "%OfflineBanner": "Label", "%QuestTrack": "Button", "%Chat": "ScrollContainer", "%Thinking": "Label", "%Cancel": "Button",
		"%Options": "VBoxContainer", "%AttachButton": "MenuButton", "%Input": "TextEdit", "%SendButton": "Button", "%BrushButton": "Button", "%AttachChip": "HBoxContainer", "%ThingMenu": "PanelContainer", "%ThingActs": "VBoxContainer",
		"%FightUi": "Control", "%FightSide": "PanelContainer", "%Portrait": "VBoxContainer", "%FoeList": "VBoxContainer", "%Queue": "HBoxContainer", "%Hint": "Label",
		"%FightBar": "PanelContainer", "%Economy": "VBoxContainer", "%Tabs": "TabContainer", "%EndTurnButton": "Button", "%FightLogBox": "VBoxContainer"}


func _ready() -> void:
	_field = UiScenes.need(self, "%Field")
	_field.cell_clicked.connect(_on_cell)
	_field.stepped.connect(_on_stepped)
	_field.arrived.connect(_on_arrived)
	_fight = UiScenes.need(self, "%FightUi")
	_fight.setup(self)
	_field.cell_hovered.connect(_fight.on_hover)
	_field.cell_right.connect(_fight.on_right)
	_dim = UiScenes.need(self, "%Dim")
	_talk_card = UiScenes.need(self, "%TalkCard")
	_partner_mark = UiScenes.need(self, "%PartnerMark")
	_partner_mark.add_theme_font_size_override("font_size", 84)
	(UiScenes.need(self, "%PartnerToken") as PanelContainer).add_theme_stylebox_override("panel", UiTheme.box(UiTheme.PANEL_RAISED, UiTheme.ACCENT, 3, 0, 95))
	_mode_label = UiScenes.need(self, "%PartnerName")
	_partner_line = UiScenes.need(self, "%PartnerLine")
	var bar: ActionBar = UiScenes.need(self, "%Bar")
	trade_toggle = Button.new()
	trade_toggle.name = "TradeToggle"
	trade_toggle.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	trade_toggle.pressed.connect(func() -> void: GameState.set_trade(GameState.session.mode != GameSession.MODE_TRADE))
	bar.talk.add_child(trade_toggle)
	bar.talk.move_child(trade_toggle, 0)
	leave_button = Button.new()
	leave_button.name = "LeaveButton"
	leave_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	leave_button.text = "BTN_LEAVE_CONVERSATION"
	leave_button.pressed.connect(GameState.leave_conversation)
	bar.talk.add_child(leave_button)
	_offline_banner = UiScenes.need(self, "%OfflineBanner")
	_offline_banner.add_theme_color_override("font_color", UiTheme.WARN)
	_track = UiScenes.need(self, "%QuestTrack")
	_track.add_theme_color_override("font_color", UiTheme.ACCENT)
	_track.pressed.connect(func() -> void:
		var qid := QuestRules.tracked(GameState.session, Catalog.data["world"])
		var rooms := WorldMap.step_rooms(GameState.session, Catalog.data, qid)
		_map.open_at(rooms[0] if not rooms.is_empty() else ""))
	chat = UiScenes.need(self, "%Chat")
	_thinking = UiScenes.need(self, "%Thinking")
	_cancel = UiScenes.need(self, "%Cancel")
	_cancel.pressed.connect(GameState.cancel_turn)
	_options = UiScenes.need(self, "%Options")
	# The pin button sits in the input row like «attach a file» in a messenger (v0.7.7 fixes, the author).
	_attach_menu = UiScenes.need(self, "%AttachButton")
	_attach_menu.about_to_popup.connect(_fill_attach_menu)
	input = UiScenes.need(self, "%Input")
	input.text_submitted.connect(func(_t: String) -> void: _send())
	send_button = UiScenes.need(self, "%SendButton")
	send_button.pressed.connect(_send)
	brush = UiScenes.need(self, "%BrushButton")
	brush.pressed.connect(GameState.draw_image)
	_attach_chip = UiScenes.need(self, "%AttachChip")

	_menu = UiScenes.need(self, "%ThingMenu")
	_menu_box = UiScenes.need(self, "%ThingActs")
	var side: SidePanel = UiScenes.need(self, "%Side")
	_side = side
	side.approach_requested.connect(_approach)
	side.walk_out_requested.connect(_leave_to)
	side.touch_requested.connect(_touch)
	side.wait_requested.connect(func() -> void: _wait.open())
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
	side.wilds_requested.connect(func(k: String) -> void:  # v0.7.41
		_wilds.ground = k
		_wilds.open())
	side.job_requested.connect(func(npc: String) -> void: _jobs.open(npc))  # v0.7.26
	side.property_requested.connect(func(mode: String, npc: String) -> void: _property.open(mode, npc))  # v0.7.27
	side.bank_requested.connect(func(npc: String) -> void: _bank.open(npc))  # v0.7.28
	side.shop_requested.connect(func(mode: String, id: String) -> void: _shop.open(mode, id))  # v0.7.29
	side.study_requested.connect(func(npc: String) -> void: _study.open(npc))  # v0.7.30
	side.bond_requested.connect(func(npc: String) -> void: _bond.open(npc))  # v0.7.31
	side.contest_requested.connect(func(npc: String) -> void: _contest.open(npc))  # v0.7.40
	side.arena_requested.connect(func(sid: String) -> void: _arena.open(sid))  # v0.7.45
	side.family_requested.connect(func() -> void: _family.open())  # v0.7.32
	side.pet_requested.connect(func(id: String) -> void: _pet.open(id))  # v0.7.43
	side.letter_requested.connect(func(id: String) -> void: _letter.open(id))  # v0.7.48
	side.faith_requested.connect(func() -> void: _faith.open())  # v0.7.49
	side.heist_requested.connect(func() -> void: _heists.open())  # v0.7.33
	side.org_requested.connect(func(org: String) -> void: _org.open(org))
	side.office_requested.connect(func(chief: String) -> void: _office.open(chief))  # v0.7.34

	_sheet = _window(CharacterSheet.SCENE, "CharacterSheet")
	_map = WorldNotes.create(WorldNotes.MAP)
	_map.name = "MapView"
	_journal = WorldNotes.create(WorldNotes.JOURNAL)
	_journal.name = "JournalView"
	for v: WorldNotes in [_map, _journal]:
		_mount(v)

	_short_rest = SmallDialog.create(SmallDialog.SHORT_REST)
	_short_rest.name = "ShortRestView"
	_prepare = SmallDialog.create(SmallDialog.PREPARE)
	_prepare.name = "PrepareView"
	_long_rest = SmallDialog.create(SmallDialog.LONG_REST)
	_long_rest.name = "LongRestView"
	_wilds = SmallDialog.create(SmallDialog.WILDS)
	_wilds.name = "WildsView"
	_wait = SmallDialog.create(SmallDialog.WAIT)
	_wait.name = "WaitView"
	for v: SmallDialog in [_short_rest, _prepare, _long_rest, _wilds, _wait]:
		_mount(v)
	_theft = _window(TheftPanel.SCENE, "TheftView")
	_container = _window(ContainerPanel.SCENE, "ContainerView")  # v0.7.18.1
	trade_panel = _window(TradePanel.SCENE, "TradePanel")  # a screen of its own over everything (v0.7.22.10, the author: «как в BG3»)
	_place = _window(PlacePanel.SCENE, "PlaceView")  # v0.7.22.7: the things of the room
	_place.container_requested.connect(func(prop: String) -> void:
		_place.visible = false
		_container.open(prop))
	move_child(_container, -1)  # the container opens over the place window
	_board = _window(BoardPanel.SCENE, "BoardView")  # v0.7.22.13: a notice board's orders
	_craft = _window(CraftPanel.SCENE, "CraftView")  # v0.7.24
	_jobs = _window(JobPanel.SCENE, "JobView")  # v0.7.26
	_property = _window(PropertyPanel.SCENE, "PropertyView")  # v0.7.27
	_bank = _window(BankPanel.SCENE, "BankView")  # v0.7.28
	_shop = _window(ShopPanel.SCENE, "ShopView")  # v0.7.29
	_study = _window(StudyPanel.SCENE, "StudyView")  # v0.7.30
	_bond = _window(BondPanel.SCENE, "BondView")  # v0.7.31
	_contest = _window(ContestPanel.SCENE, "ContestView")  # v0.7.40
	_arena = _window(ArenaPanel.SCENE, "ArenaView")  # v0.7.45
	_letter = _window(LetterPanel.SCENE, "LetterView")  # v0.7.48
	EventBus.letter_requested.connect(_letter.open)  # Sending from the sheet (v0.8.4.26.3)
	_faith = _window(FaithPanel.SCENE, "FaithView")  # v0.7.49
	_pet = _window(PetPanel.SCENE, "PetView")  # v0.7.43
	_family = _window(FamilyPanel.SCENE, "FamilyView")  # v0.7.32
	_heists = _window(HeistPanel.SCENE, "HeistView")  # v0.7.33
	_org = _window(OrgPanel.SCENE, "OrgView")
	_office = _window(OfficePanel.SCENE, "OfficeView")  # v0.7.34
	_sheet.bag_requested.connect(func(bag: String) -> void: _container.open(bag))  # v0.7.18.2
	_sheet.prepare_requested.connect(func() -> void:
		_sheet.visible = false
		_prepare.open())

	_level_up = LevelUpView.create()
	_level_up.name = "LevelUpView"
	_mount(_level_up)

	_image = _window(ImageCard.SCENE, "ImageView")
	chat.image_requested.connect(_open_image)
	EventBus.image_drawn.connect(func(entry: Dictionary) -> void: _open_image(ImageFrame.image_of(entry)))
	EventBus.image_busy.connect(func(b: bool) -> void:
		brush.busy = b
		_refresh())

	_pause = UiScenes.open(PauseMenu.SCENE) as PauseMenu
	_mount(_pause)

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


func _window(scene: String, node_name: String) -> Control:
	var w := UiScenes.open(scene) as Control
	w.name = node_name
	_mount(w)
	return w


func _mount(w: Control) -> void:
	w.visible = false
	add_child(w)
	w.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _overlays() -> Array[Control]:
	return [_menu, _sheet, _map, _journal, _level_up, _short_rest, _prepare, _long_rest, _wilds, _wait, _theft, _container, _craft, _jobs, _property, _bank, _shop, _study, _bond, _contest, _arena, _family, _pet, _heists, _org, _office, _image]


# _input, not _unhandled_input: the focused chat input would swallow Esc.
# v0.7.22.27 (as in BG3): the keys work outside the input; Esc leaves the input, Enter or a letter comes back to it.
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_action("map_labels"):
		_field.labels = event.is_pressed()
		_field.queue_redraw()
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
		elif not _fight.cancel():
			_pause.toggle()
	elif input.has_focus() and input.text.is_empty() and open.is_empty() and not _fight.active() and _option_key(event) >= 0:  # 1–3 over an empty input
		_hotkey(event, true)
	elif input.has_focus() and input.text.is_empty() and open.is_empty() and _fight.active() and (event.is_action_pressed("next_target") or event.is_action_pressed("end_turn")):
		_fight.key(event)  # an empty input does not hold the fight's keys
	elif input.has_focus() or _pause.visible or get_viewport().gui_get_focus_owner() is LineEdit or get_viewport().gui_get_focus_owner() is TextEdit:
		return
	elif _fight.active() and open.is_empty() and _fight.key(event):
		pass
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
	if event.is_action_pressed("swap_weapons"):
		var err := GameState.swap_weapons()
		if not err.is_empty():
			EventBus.message.emit(tr(err))
		return true
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
	if GameState.has_session() and not _field.walking() and not _field.map.is_empty():
		GameState.walked(_field.map)  # a danger met on the way waited for the master
	if _at_door:
		_at_door = false
		_on_arrived()
	var offer: Dictionary = GameState.session.character.get("contest_offer", {}) if GameState.has_session() else {}
	if not offer.is_empty():  # v0.7.40: the master's NPC offered a game
		GameState.session.character.erase("contest_offer")
		_contest.open(str(offer["npc"]), str(offer["kind"]))
		return
	if Backend.is_ready() and _typed and not _fight.active() and not _pause.visible and _overlays().all(func(o: Control) -> bool: return not o.visible):
		input.grab_focus()


# --- the field and walking (v0.8.1) ---------------------------------------------------------------------------


func _refresh_field(s: GameSession) -> void:
	if s == null or CombatRules.active(s):
		return
	var view := WalkRules.view(s, Catalog.data)
	var at := WalkRules.settle(s, Catalog.data, view)
	var names := {}
	for e: Dictionary in view["exits"]:
		names[e["to"]] = GameState.world().room(str(e["to"])).get("name", e["to"])
	_field.names = names
	_field.clicks = not s.in_conversation()
	_field.show_map(view, Catalog.data["layouts"])
	var walkers: Array[Dictionary] = []
	for id: String in Being.followers(s):
		var who := str(GameState.world().npc(id).get("name", id))
		walkers.append({"ref": "npc:" + id, "mark": who.left(1), "name": who.get_slice(" ", 0)})
	for cr: Dictionary in CreatureRules.here(s, s.room_id):  # the hero's animals walk along
		if str(cr["state"]) == PropertyRules.TAME or bool(cr.get("led", false)) or bool(cr.get("ally", false)):
			walkers.append({"ref": "cr:" + str(cr["id"]), "mark": str(cr["name"]).left(1), "name": str(cr["name"]).get_slice(" ", 0)})
	_things = MapSpots.of(s, Catalog.data, view).filter(func(t: Dictionary) -> bool:
		return str(t["kind"]) != "station" or _side.mark_has_acts(str(t["id"])))
	_things.append_array(MapSpots.foes(s, Catalog.data, view))
	_things.append_array(MapSpots.traps(s, Catalog.data, view))
	_things.append_array(MapSpots.others(s, Catalog.data, view))
	_field.dim = true
	if s.room_id == _field_room and at != _field.hero_cell() and not _field.walking():  # the master's words move the hero
		var steps := WalkRules.path(view, Catalog.data["layouts"], _field.hero_cell(), at)
		if not steps.is_empty():
			_beyond = ""
			_exit_to = ""
			_field.instant = GameState.instant_walk
			_field.walk(steps)
	_field_room = s.room_id
	_field.place_hero(at, str(s.character.get("name", "?")).left(1), walkers)
	_look(s, at if not _field.walking() else _field.hero_cell())
	if _menu.visible:
		_show_menu(_menu_ref)


## What the hero sees from `cell`: the rest of the map is dimmed (v0.8.3). A foe or a person shows only in view, a thing
## stays on the map.
func _look(s: GameSession, cell: Vector2i) -> void:
	var now := SightRules.look(s, Catalog.data, _field.map, cell)
	_field.now = now
	_field.cones = WatchRules.cones(s, Catalog.data, _field.map, now)
	_field.things = _things.filter(func(t: Dictionary) -> bool:
		var at := Vector2i(int(t["x"]), int(t["y"]))
		if str(t["kind"]) == "foe" and (EncounterRules.lurking(s, s.room_id).get("hidden", []) as Array).has(str(t["id"])):
			return false
		return now.has(at) or str(t["kind"]) in ["station", "prop", "trap"])
	_rounds = WatchRules.by_rounds(s, Catalog.data, _field.map, now)
	_field.queue_redraw()


## A click on the map: the hero walks there by himself; a door is crossed by GameState.go, as the buttons do.
func _on_cell(cell: Vector2i) -> void:
	var s := GameState.session if GameState.has_session() else null
	if s == null or s.in_conversation():
		return
	_menu.visible = false
	if _fight.active():
		_fight.on_cell(cell)
		return
	if _rounds and cell == _field.hero_cell():  # the hero stands the round out
		GameState.sneak_round()
		return
	var ref := _field.ref_at(cell)
	if not ref.is_empty() and not ref.begins_with("far:"):
		_touch(ref)
		return
	var door := WalkRules.way_at(_field.map, s.room_id, cell)
	if not door.is_empty() and not (WayRules.blocked(s, Catalog.data, s.room_id, door).is_empty() and WayRules.ways(s, Catalog.data, s.room_id, door).is_empty()):
		_touch("door:" + door)
		return
	var plan := WalkRules.plan(_field.map, Catalog.data["layouts"], _field.hero_cell(), cell)
	if plan.is_empty():
		return
	_field.stop()
	_after = Callable()
	_goal = cell
	_exit_to = str(plan["exit"])
	_at_door = false
	_walk(plan["path"])


## A click on someone or something: a person's menu opens from where it can be spoken to, a thing is used from beside it.
func _touch(ref: String) -> void:
	var thing := ref.begins_with("prop:")
	_menu.visible = false
	if ref.begins_with("door:") or ref.begins_with("trap:") or ref.begins_with("body:"):
		_approach(ref, "touch", _show_menu.bind(ref))
	elif thing:
		_approach(ref, "touch", _side.use_thing.bind(ref))
	elif ref.begins_with("foe:"):  # v0.8.4.30: its menu — the blow, a look, a spell aimed at it
		_show_menu(ref)
	else:
		_approach(ref, "touch" if ref.begins_with("station:") else "talk", _show_menu.bind(ref))


## The hero walks into reach of `ref`, then the act. No way there or a talk going on — the act from where the hero stands.
func _approach(ref: String, reach: String, act: Callable) -> void:
	var s := GameState.session
	var to := _cell_of(ref)
	var steps: Array[Vector2i] = []
	if to.x >= 0 and not s.in_conversation():
		steps = WalkRules.near(_field.map, Catalog.data["layouts"], _field.hero_cell(), to, MapSpots.reach(s, Catalog.data, reach, ref), s.room_id)
	if steps.is_empty():
		act.call()
		return
	_field.stop()
	_exit_to = ""
	_at_door = false
	_after = act
	_goal = steps[-1]
	_walk(steps)


## The square of a ref: a door by the room behind it, the rest as the field has it.
func _cell_of(ref: String) -> Vector2i:
	if ref.begins_with("door:"):
		return WalkRules.way_cell(_field.map, GameState.session.room_id, ref.trim_prefix("door:"))
	return _field.cell_of(ref)


## What stands on the way to `to` as a thing to deal with: a found trap, a shut door. "" — the way is free.
func _way_ref(to: String) -> String:
	var s := GameState.session
	var trap := ExplorationRules.trap_on_exit(s, Catalog.data["world"], s.room_id, to)
	if not trap.is_empty() and ExplorationRules.is_found(s, s.room_id, trap):
		return "trap:" + str(trap["id"])
	return "door:" + to if not WayRules.blocked(s, Catalog.data, s.room_id, to).is_empty() else ""


## The exit button (v0.8.4.2): the hero walks there by himself; a shut way is walked up to and opens its menu.
func _leave_to(to: String) -> void:
	var shut := _way_ref(to)
	if not shut.is_empty():
		_touch(shut)
		return
	_menu.visible = false
	var cell := WalkRules.way_cell(_field.map, GameState.session.room_id, to)
	var past := WalkRules.beyond(_field.map, Catalog.data["layouts"], cell, to)
	var target := past if past.x >= 0 else cell
	var plan := WalkRules.plan(_field.map, Catalog.data["layouts"], _field.hero_cell(), target) if target.x >= 0 else {}
	if plan.is_empty():
		GameState.go(to)
		return
	_field.stop()
	_after = Callable()
	_goal = target
	_exit_to = str(plan["exit"])
	_at_door = false
	_walk(plan["path"])


func _show_menu(ref: String) -> void:
	_menu_ref = ref
	for c: Node in _menu_box.get_children():
		_menu_box.remove_child(c)
		c.queue_free()
	if not _side.menu(_menu_box, ref):
		_menu.visible = false
		return
	for b: Node in _menu_box.find_children("*", "BaseButton", true, false):
		(b as BaseButton).pressed.connect(_close_menu)
	_menu.visible = true
	await get_tree().process_frame  # a flow knows its height only after a layout
	_menu.reset_size()
	var at := _field.global_position + _field.cell_point(_cell_of(ref)) + Vector2(28, -20)
	_menu.global_position = at.clamp(Vector2(8, 8), get_viewport_rect().size - _menu.size - Vector2(8, 8))


func _close_menu() -> void:
	_menu.visible = false


func _walk(steps: Array[Vector2i]) -> void:
	var leg := WalkRules.leg(_field.map, steps, GameState.session.room_id)
	var way: Array[Vector2i] = leg["steps"]
	_beyond = str(leg["room"])
	if not _beyond.is_empty() and not way.is_empty() and WalkRules.room_of(_field.map, way[-1]).is_empty() and not _way_ref(_beyond).is_empty():
		way.pop_back()  # a shut door is not a place to stand on
	_round_ends = _rounds
	var most := WatchRules.round_steps(GameState.session)
	if _rounds and way.size() > most:  # sneaking past those who watch: one round's squares to a click
		way = way.slice(0, most)
		_beyond = ""
		_exit_to = ""
		_after = Callable()
	_field.instant = GameState.instant_walk
	_field.walk(way)


func _on_stepped(cell: Vector2i) -> void:
	var s := GameState.session
	WalkRules.stand(s, _field.map, s.room_id, cell)
	_look(s, cell)
	if GameState.walked(_field.map):
		_field.stop()
		_after = Callable()
		_exit_to = ""
		_beyond = ""
		_at_door = false


func _on_arrived() -> void:
	_side.refresh()
	if _round_ends:
		_round_ends = false
		GameState.sneak_round()
		if CombatRules.active(GameState.session):
			return
	var to := _beyond if not _beyond.is_empty() else _exit_to
	if to.is_empty() and _after.is_valid():
		var act := _after
		_after = Callable()
		act.call()
		return
	if to.is_empty() or not GameState.has_session():
		return
	if GameState.is_busy():  # ходить можно, а дверь ждёт конца хода мастера
		_at_door = true
		return
	var through := _beyond.is_empty()
	_beyond = ""
	if through:
		_exit_to = ""
	var shut := _way_ref(to)
	if not shut.is_empty():
		_exit_to = ""
		_show_menu(shut)
		return
	var map_id := str(_field.map["id"])
	if not GameState.go(to) or through or not is_inside_tree():
		return
	var s := GameState.session
	if s.in_conversation() or CombatRules.active(s) or s.room_id != to or str(LayoutRules.map_id(s, Catalog.data, to)) != map_id:
		return
	_refresh_field(s)
	var plan := WalkRules.plan(_field.map, Catalog.data["layouts"], _field.hero_cell(), _goal)  # on behind the door
	if not plan.is_empty():
		_exit_to = str(plan["exit"])
		_walk(plan["path"])


func _on_options_changed(_options_list: Array[String]) -> void:
	_refresh()


func _on_backend_state_changed(_state: int, _detail: String) -> void:
	_refresh()


func _open_image(path: String) -> void:
	if not _image.open(path):
		EventBus.message.emit(tr("MSG_IMAGE_GONE"))


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
	input.editable = _fight.mine() if _fight.active() else online and not busy
	send_button.disabled = not input.editable
	_fight.refresh()
	if _fight.active() and not _was_fight and input.has_focus():
		input.release_focus()  # the fight's keys are not letters of the chat; typing still lands in the input
	_was_fight = _fight.active()
	var s0 := GameState.session if GameState.has_session() else null
	brush.visible = SaveManager.images_enabled() and not Backend.image_models().is_empty()
	brush.disabled = not online or GameState.drawing or s0 == null or ImageFrame.event_index(s0) < 0
	brush.tooltip_text = "BTN_DRAW_EVENT_BUSY" if GameState.drawing else "BTN_DRAW_EVENT"
	var s := GameState.session if GameState.has_session() else null
	var qid := QuestRules.tracked(s, Catalog.data["world"]) if s != null else ""
	_track.visible = not qid.is_empty()
	if _track.visible:
		_track.text = tr("QUEST_TRACK").format({"title": QuestRules.quest(Catalog.data["world"], qid).get("title", qid),
			"step": QuestRules.step_text(s, Catalog.data["world"], qid)})
	_talk_card.visible = s != null and s.in_conversation()
	_dim.visible = _talk_card.visible
	trade_panel.visible = s != null and s.mode == GameSession.MODE_TRADE
	_refresh_field(s)
	if _talk_card.visible:
		var npc := GameState.world().npc(s.npc_id)
		var npc_name := str(npc.get("name", s.npc_id))
		_mode_label.text = npc_name
		_partner_mark.text = npc_name.left(1)
		_partner_line.text = UiParts.partner_line(s, Catalog.data, s.npc_id)
		trade_toggle.visible = GameState.world().is_trader(s.npc_id)
		trade_toggle.text = tr("BTN_TO_TALK" if s.mode == GameSession.MODE_TRADE else "BTN_TO_TRADE")
		trade_toggle.disabled = busy or (s.mode != GameSession.MODE_TRADE and TimeRules.shops_closed(s, Catalog.data))
		trade_toggle.tooltip_text = tr("SHOP_CLOSED") if trade_toggle.disabled and not busy else ""
		leave_button.disabled = busy or not online
		input.placeholder_text = tr("PLACEHOLDER_SAY").format({"name": npc_name.get_slice(" ", 0)})
	else:
		input.placeholder_text = tr("PLACEHOLDER_COMBAT" if _fight.active() else "PLACEHOLDER_ACTION")
	_refresh_attach(s, busy, online)
	input.fit()
	for c in _options.get_children():
		_options.remove_child(c)
		c.queue_free()
	if busy or not GameState.has_session():
		return
	if GameState.can_retry():
		_option_button("BTN_RETRY_TURN", GameState.retry, true).disabled = not online
	for i in GameState.session.options.size() if not _fight.active() else 0:
		var o := GameState.session.options[i]
		var cost := GameState.session.option_costs[i] if i < GameState.session.option_costs.size() else 0
		var pv := GameState.option_preview(i)
		var tag := ("[%s] " % tr("SKILL_" + str(pv["skill"]).to_upper())) if not pv.is_empty() else ""
		var b := _option_button("%d. %s%s%s" % [i + 1, tag, o, (" (%s)" % Money.format(cost)) if cost > 0 else ""], func() -> void:
			_typed = false
			var err := GameState.choose_option(i)
			if not err.is_empty():
				EventBus.message.emit(tr(err)), false)
		b.disabled = not online or (cost > 0 and Ledger.balance(GameState.session) < cost)
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
	b.custom_minimum_size = Vector2(0, 44)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
	var checks := PopupMenu.new()  # v0.7.36: the check the player picks, not the master
	checks.name = "AttachSub_ATTACH_GROUP_CHECK"
	_check_choices = GameState.check_choices()
	checks.id_pressed.connect(func(i: int) -> void:
		GameState.pin_check(str(_check_choices[i]["kind"]), str(_check_choices[i]["id"]))
		input.grab_focus())
	for i in _check_choices.size():
		var ch: Dictionary = _check_choices[i]
		if i > 0 and ch["kind"] == "ability" and _check_choices[i - 1]["kind"] == "skill":
			checks.add_separator(tr("ATTACH_CHECK_ABILITIES"))
		checks.add_item(("• " if bool(ch["prof"]) else "   ") + GameState.check_label(ch), i)
	pop.add_submenu_node_item(tr("ATTACH_GROUP_CHECK"), checks)


func _on_attach_picked(index: int) -> void:
	if index < 0 or index >= _attach_choices.size():
		return
	var ch: Dictionary = _attach_choices[index]
	var slots: Array = ch["slots"]
	GameState.attach(str(ch["kind"]), str(ch["id"]), int(slots[0]) if not slots.is_empty() else 0)
	input.grab_focus()


## The pinned check (v0.7.36): «Проверка: Атлетика +5» and «✕».
func _check_chip() -> void:
	var pin := GameState.pinned_check
	for ch: Dictionary in GameState.check_choices():
		if pin.get(str(ch["kind"])) == ch["id"]:
			var label := Label.new()
			label.name = "CheckPinName"
			label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			label.text = tr("ATTACH_CHECK_PINNED").format({"name": GameState.check_label(ch)})
			label.tooltip_text = "ATTACH_CHECK_TIP"
			label.mouse_filter = Control.MOUSE_FILTER_PASS
			label.add_theme_color_override("font_color", UiTheme.ACCENT_BRIGHT)
			_attach_chip.add_child(label)
			var drop := Button.new()
			drop.name = "CheckPinRemove"
			drop.text = "✕"
			drop.tooltip_text = "ATTACH_REMOVE"
			drop.pressed.connect(GameState.unpin_check)
			_attach_chip.add_child(drop)
			input.placeholder_text = tr("PLACEHOLDER_CHECK_PINNED")


## The boxes of the targets of a pinned spell: the hero and the NPCs here, no more than `limit` ticked.
func _attach_boxes(npcs: Array, limit: int, names: Dictionary) -> void:
	var a := GameState.attached
	var picked: Array = a.get("targets", [])
	for id: String in [GameState.SELF_TARGET] + npcs:
		var box := CheckBox.new()
		box.name = "AttachPick_" + id
		box.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		box.text = tr("ATTACH_SELF") if id == GameState.SELF_TARGET else str(names.get(id, id))
		box.button_pressed = picked.has(id)
		box.disabled = not picked.has(id) and picked.size() >= limit
		box.toggled.connect(func(on: bool) -> void:
			var now: Array = GameState.attached.get("targets", [])
			if on and not now.has(id):
				now.append(id)
			elif not on:
				now.erase(id)
			GameState.attached["targets"] = now
			EventBus.state_changed.emit())
		_attach_chip.add_child(box)


## The chip of the pinned thing: its name, the slot circle (spells), the target (an NPC here or none), «✕».
func _refresh_attach(s: GameSession, busy: bool, online: bool) -> void:
	for c in _attach_chip.get_children():
		_attach_chip.remove_child(c)
		c.queue_free()
	var usable := s != null and s.mode != GameSession.MODE_COMBAT
	_attach_menu.visible = usable
	_attach_menu.disabled = busy or not online
	if usable and not GameState.pinned_check.is_empty():
		_check_chip()
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
	var targets := GameState.attach_targets()  # the people here and the foes seen (v0.8.4.30)
	var npcs: Array = targets.map(func(t: Dictionary) -> String: return str(t["id"]))
	var names := {}
	for t: Dictionary in targets:
		names[t["id"]] = t["name"]
	var many := str(a["kind"]) == "spell" and SpellEffects.picks_side(Catalog.data, str(a["id"])) in ["friend", "any"] \
		and SpellEffects.picks_count(Catalog.data, str(a["id"]), int(a.get("slot", 0))) > 1
	if many and not npcs.is_empty():  # v0.7.50.1: several targets — boxes; none ticked is the hero
		_attach_boxes(npcs, SpellEffects.picks_count(Catalog.data, str(a["id"]), int(a.get("slot", 0))), names)
	elif not npcs.is_empty():
		var who := OptionButton.new()
		who.name = "AttachTarget"
		who.add_item(tr("ATTACH_NO_TARGET"))
		var ids: Array[String] = [""]
		for id: String in npcs:
			who.add_item(str(names[id]))
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
