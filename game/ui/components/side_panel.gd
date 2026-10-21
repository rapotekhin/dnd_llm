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
signal long_rest_requested
signal pockets_requested(npc_id: String)

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
	var next_xp := LevelUp.xp_for(Catalog.data, int(c.get("level", 1)) + 1)
	if int(c.get("level", 1)) < LevelUp.max_level(c, Catalog.data):
		_line(tr("SIDE_XP").format({"xp": int(c.get("xp", 0)), "next": next_xp}), true)
	if LevelUp.can_level_up(c, Catalog.data):
		var lv := _button(tr("BTN_LEVEL_UP"), level_up_requested.emit, not GameState.is_busy())
		lv.name = "LevelUpButton"
		lv.theme_type_variation = UiTheme.ACCENT_BUTTON
		lv.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_line(tr("SIDE_DAY_TIME").format({"day": s.day, "part": TimeRules.part_name(s, Catalog.data), "clock": TimeRules.clock(s)}), true)
	if TimeRules.dark(s, Catalog.data):
		_line(tr("SIDE_DARK"), true).add_theme_color_override("font_color", UiTheme.WARN)
	var room := world.room(s.room_id)
	_subheading("SIDE_PLACE")
	_line("%s — %s" % [world.location(world.location_id(s.room_id)).get("name", ""), room.get("name", s.room_id)], false)
	if not s.in_conversation() and CrimeRules.held(s):
		_arrest(s, can_act)
	if not s.in_conversation():
		var npcs := s.npcs_here(world.world, s.room_id)
		if not npcs.is_empty():
			_subheading("SIDE_PEOPLE")
			for id: String in npcs:
				var n := world.npc(id)
				var refuses := SocialRules.refuses(s, Catalog.data, id)  # v0.7.15.3
				var b := _button(tr("BTN_TALK_TO").format({"name": str(n.get("name", id)).get_slice(" ", 0)}), GameState.talk_to.bind(id, false), can_act and not refuses)
				b.tooltip_text = tr("TALK_REFUSED") if refuses else "%s — %s" % [n.get("name", id), n.get("role", "")]
				b.name = "Talk_" + id
				var pk := _button(tr("BTN_POCKETS").format({"name": str(n.get("name", id)).get_slice(" ", 0)}), pockets_requested.emit.bind(id),
					can_act and TheftRules.can_steal(s, Catalog.data, id).is_empty())
				pk.name = "Pockets_" + id
				if bool(n.get("trader", false)):
					var closed := TimeRules.shops_closed(s, Catalog.data) or TheftRules.shop_closed_for(s, id, Catalog.data) or refuses
					var t := _button(tr("BTN_TRADE_WITH").format({"name": str(n.get("name", id)).get_slice(" ", 0)}), GameState.talk_to.bind(id, true), can_act and not closed)
					t.name = "Trade_" + id
					if closed:
						t.tooltip_text = tr("SHOP_CLOSED_WANTED" if CrimeRules.shunned_by(s, Catalog.data, id) else "TALK_REFUSED" if refuses else
							"SHOP_CLOSED_FOR_YOU" if TheftRules.shop_closed_for(s, id) else "SHOP_CLOSED")
		for away: String in SceneRules.absent(s, Catalog.data["world"], s.room_id):  # v0.7.14.2: their hours
			_line(away, true)
		for body: Dictionary in CrimeRules.bodies_here(s, Catalog.data):  # v0.7.14: the body of a killed NPC
			if bool(body["searched"]):
				_line(str(body["name"]), true)
				continue
			var bid := str(body["npc_id"])
			var bb := _button(tr("BTN_SEARCH_BODY").format({"name": body["name"]}), func() -> void:
				var err := GameState.search_body(bid)
				if not err.is_empty():
					EventBus.message.emit(tr(err)), can_act)
			bb.name = "Body_" + bid
		for qid: String in XpRules.quests_here(s, Catalog.data["world"]):
			var q: Dictionary = XpRules.quests(Catalog.data["world"])[qid]
			var qb := _button(tr("BTN_QUEST").format({"action": q["action"]}), func() -> void:
				var err := GameState.complete_quest(qid)
				if not err.is_empty():
					EventBus.message.emit(tr(err)), can_act)
			qb.name = "Quest_" + qid
			qb.tooltip_text = str(q["title"])
		_quest_buttons(s, can_act, "")
		for ch: Dictionary in QuestRules.choices_here(s, Catalog.data["world"]):
			var qid2 := str(ch["quest_id"])
			var cid := str(ch["choice_id"])
			var cb := _button(tr("BTN_QUEST").format({"action": ch["action"]}), func() -> void:
				var err := GameState.quest_choose(qid2, cid)
				if not err.is_empty():
					EventBus.message.emit(tr(err)), can_act)
			cb.name = "QuestChoice_%s_%s" % [qid2, cid]
			cb.theme_type_variation = UiTheme.ACCENT_BUTTON
		_subheading("SIDE_EXITS")
		var sneak := CheckButton.new()
		sneak.name = "SneakToggle"
		sneak.text = "BTN_SNEAK"
		sneak.tooltip_text = "BTN_SNEAK_TIP"
		sneak.button_pressed = s.sneaking
		sneak.disabled = not can_act or s.sneak_noticed == s.room_id
		if s.sneak_noticed == s.room_id:
			sneak.tooltip_text = "SNEAK_NOTICED"
		sneak.toggled.connect(func(on: bool) -> void:
			var err := GameState.set_sneaking(on)
			if not err.is_empty():
				EventBus.message.emit(tr(err)))
		_content.add_child(sneak)
		var look_row := HBoxContainer.new()
		look_row.add_theme_constant_override("separation", 8)
		_content.add_child(look_row)
		for spec: Array in [["LookButton", "BTN_LOOK", "perception"], ["SearchButton", "BTN_SEARCH", "investigation"]]:
			var lb := Button.new()
			lb.name = spec[0]
			lb.text = tr(spec[1])
			lb.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			lb.disabled = not can_act
			lb.tooltip_text = tr(spec[1] + "_TIP")
			var skill: String = spec[2]
			lb.pressed.connect(func() -> void:
				var err := GameState.search_room(skill)
				if not err.is_empty():
					EventBus.message.emit(tr(err)))
			look_row.add_child(lb)
		# «Забрать всё» (v0.7.8): what nobody owns and the hero can carry, after a search.
		var takeable: Array = PropRules.take_all_plan(s, Catalog.data)["take"]
		var tb := Button.new()
		tb.name = "TakeAllButton"
		tb.text = tr("BTN_TAKE_ALL")
		tb.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tb.disabled = not can_act or takeable.is_empty()
		tb.tooltip_text = tr("TAKE_ALL_TIP").format({"list": ", ".join(takeable.map(func(p: Dictionary) -> String: return str(p["name"])))}) 			if not takeable.is_empty() else tr("TAKE_ALL_NOTHING")
		tb.pressed.connect(func() -> void:
			var err := GameState.take_all()
			if not err.is_empty():
				EventBus.message.emit(tr(err)))
		_content.add_child(tb)  # its own row under the look buttons: three in one row widen the panel
		var trapped := {}
		for ft: Dictionary in ExplorationRules.found_traps(s, Catalog.data["world"], s.room_id):
			trapped[ft["to"]] = ft["secret"]
		for e: String in ExplorationRules.open_exits(s, Catalog.data["world"], s.room_id):
			if trapped.has(e):
				var to := e
				var by := _button(tr("BTN_TRAP_BYPASS").format({"room": world.room(e).get("name", e)}), func() -> void: _trap(to, false), can_act)
				by.name = "Exit_" + e
				by.tooltip_text = str(trapped[e]["text"]) + "
" + tr("TRAP_BYPASS_TIP")
				var dis := _button(tr("BTN_TRAP_DISARM"), func() -> void: _trap(to, true), can_act)
				dis.name = "Disarm_" + e
				dis.tooltip_text = str(trapped[e]["text"]) + "
" + tr("TRAP_DISARM_TIP")
				continue
			var b := _button("→ " + str(world.room(e).get("name", e)), GameState.go.bind(e), can_act and not CrimeRules.held(s))
			b.name = "Exit_" + e
			if CrimeRules.held(s):
				b.tooltip_text = tr("CRIME_HELD")
		# A show on a stage of the pack (v0.7.11): a Performance check for coins, an entertainer's free room.
		if (world.room(s.room_id).get("tags", []) as Array).has("stage"):
			var perform_why := BackgroundRules.can_perform(s, Catalog.data)
			var do_perform := func() -> void:
				var err := GameState.perform()
				if not err.is_empty():
					EventBus.message.emit(tr(err))
			var pf := _button(tr("BTN_PERFORM"), do_perform, can_act)
			pf.name = "PerformButton"
			pf.disabled = not can_act or not perform_why.is_empty()
			pf.tooltip_text = tr(perform_why) if not perform_why.is_empty() else tr("PERFORM_TIP")
		var ammo_left: Dictionary = c.get("ammo_left", {})  # v0.7.12: arrows after a fight
		if not ammo_left.is_empty() and str(ammo_left.get("room", "")) == s.room_id:
			var n := 0
			for k: String in ammo_left.get("items", {}):
				n += int(ammo_left["items"][k])
			var do_collect := func() -> void:
				var err := GameState.collect_ammo()
				if not err.is_empty():
					EventBus.message.emit(tr(err))
			var ca := _button(tr("BTN_COLLECT_AMMO").format({"n": n}), do_collect, can_act)
			ca.name = "CollectAmmo"
		# The long rest (v0.7.8): the inn's room or a camp with food — chosen in the dialog.
		var inn_ok := ExplorationRules.can_rest(s, Catalog.data["world"], Catalog.data).is_empty()
		var camp_why := ExplorationRules.can_camp(s, Catalog.data)
		var rest := _button(tr("BTN_LONG_REST_OPEN"), long_rest_requested.emit, can_act)
		rest.name = "RestButton"
		rest.disabled = not can_act or (not inn_ok and not camp_why.is_empty())
		rest.tooltip_text = tr(camp_why) if not inn_ok and not camp_why.is_empty() else ""
		var wait := MenuButton.new()
		wait.name = "WaitButton"
		wait.text = tr("BTN_WAIT")
		wait.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		wait.alignment = HORIZONTAL_ALIGNMENT_LEFT
		wait.flat = false
		wait.disabled = not can_act
		var targets: Array[String] = ["hour", "morning", "day", "evening", "night"]
		for i in targets.size():
			var mins := TimeRules.minutes_until(s, Catalog.data, targets[i])
			wait.get_popup().add_item(tr("WAIT_" + targets[i].to_upper()).format({"clock": TimeRules.clock_after(s, mins)}), i)
		wait.get_popup().id_pressed.connect(func(id: int) -> void:
			var err := GameState.wait(targets[id])
			if not err.is_empty():
				EventBus.message.emit(tr(err)))
		_content.add_child(wait)
		var short := _button(tr("BTN_SHORT_REST"), short_rest_requested.emit, not GameState.is_busy())
		short.name = "ShortRestButton"
		var why := ExplorationRules.can_short_rest(s, Catalog.data)
		short.disabled = GameState.is_busy() or not why.is_empty()
		short.tooltip_text = tr(why) if not why.is_empty() else ""
	else:
		_quest_buttons(s, can_act, s.npc_id)  # take the quest from, or hand the thing to, the one you talk to (v0.7.2)

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


func _trap(to: String, disarm: bool) -> void:
	var err := GameState.trap_action(to, disarm)
	if not err.is_empty():
		EventBus.message.emit(tr(err))


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


## The guard holds the hero (v0.7.14): the wergild, the stocks or a fight.
func _arrest(s: GameSession, can_act: bool) -> void:
	_subheading("SIDE_ARREST")
	var loc := GameState.world().location_id(s.room_id)
	var specs := [["pay", tr("BTN_CRIME_PAY").format({"cost": Money.format(CrimeRules.fine(s, Catalog.data, loc))}), ""],
		["stocks", tr("BTN_CRIME_STOCKS").format({"days": CrimeRules.stocks_days(s, Catalog.data, loc)}), ""],
		["resist", tr("BTN_CRIME_RESIST"), tr("BTN_CRIME_RESIST_TIP")]]
	for spec: Array in specs:
		var how: String = spec[0]
		var why := CrimeRules.can_answer(s, Catalog.data, how)
		var b := _button(spec[1], func() -> void:
			var err := GameState.crime_answer(how)
			if not err.is_empty():
				EventBus.message.emit(tr(err)), can_act and why.is_empty())
		b.name = "Crime_" + how
		b.theme_type_variation = UiTheme.ACCENT_BUTTON
		b.tooltip_text = tr(why) if not why.is_empty() else spec[2]


## «Взять задание» from a giver here and «Отдать …» of a talk step; in a conversation only those of its NPC
## (playtest-2: the buttons vanished while talking to the captain, and the master drew a fake one as an option).
func _quest_buttons(s: GameSession, can_act: bool, only_npc: String) -> void:
	var world: Dictionary = Catalog.data["world"]
	for qid: String in QuestRules.offers_here(s, world):
		var q := QuestRules.quest(world, qid)
		if not only_npc.is_empty() and str(q.get("giver", "")) != only_npc:
			continue
		var ab := _button(tr("BTN_QUEST_TAKE").format({"title": q["title"]}), func() -> void:
			var err := GameState.accept_quest(qid)
			if not err.is_empty():
				EventBus.message.emit(tr(err)), can_act)
		ab.name = "QuestTake_" + qid
		ab.tooltip_text = str(q.get("description", ""))
		ab.theme_type_variation = UiTheme.ACCENT_BUTTON
	for t: Dictionary in QuestRules.talks_here(s, world):
		if not only_npc.is_empty() and str(t["npc_id"]) != only_npc:
			continue
		var tid := str(t["quest_id"])
		var why := QuestRules.can_talk(s, world, tid)
		var tb := _button(tr("BTN_QUEST").format({"action": t["action"]}), func() -> void:
			var err := GameState.quest_talk(tid)
			if not err.is_empty():
				EventBus.message.emit(tr(err)), can_act and why.is_empty())
		tb.name = "QuestStep_" + tid
		tb.tooltip_text = tr(why) if not why.is_empty() else str(QuestRules.quest(world, tid)["title"])
