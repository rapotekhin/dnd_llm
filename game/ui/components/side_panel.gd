class_name SidePanel
extends PanelContainer
## Right panel of the game screen: the character (HP, AC, coins, inventory), where the player is,
## and the deterministic buttons the engine builds itself (ADR-0009 §4): exits and the NPCs of the room.
## v0.7.22.23 (the UI audit С1, И2–И4, П4): a person or a creature is one row — the name talks, «▾» or the right
## button opens the rest of its acts under it; the exits, «Осмотреться» and «Обыскать» stay pinned under the list.

signal menu_requested
signal sheet_requested
signal map_requested
signal journal_requested
signal level_up_requested
signal short_rest_requested
signal long_rest_requested
signal pockets_requested(npc_id: String)
signal container_requested(prop_id: String)
signal place_requested
signal board_requested(prop_id: String)
signal development_requested
signal craft_requested
signal job_requested(npc_id: String)  # v0.7.26
signal property_requested(mode: String, npc_id: String)  # v0.7.27
signal bank_requested(npc_id: String)  # v0.7.28
signal shop_requested(mode: String, id: String)  # v0.7.29
signal study_requested(npc_id: String)  # v0.7.30: "" — the hero's own courses
signal bond_requested(npc_id: String)  # v0.7.31
signal family_requested  # v0.7.32
signal heist_requested  # v0.7.33
signal org_requested(org_id: String)  # v0.7.33
signal office_requested(chief: String)  # v0.7.34

var _content: VBoxContainer
var _scroll: ScrollContainer
var _footer: VBoxContainer
var _exit_list: VBoxContainer  # the exits scroll under the pinned look buttons: many ways must not push the panel up
const EXIT_ROWS := 4  # the exits' fixed height in rows (v0.7.39)
var _open := ""  # the row whose acts are open ("npc:<id>", "cr:<id>"), closed when the hero leaves the room
var _open_room := ""


func _ready() -> void:
	theme_type_variation = UiTheme.SIDE
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	add_child(col)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_scroll = scroll
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 10)
	scroll.add_child(_content)
	_footer = VBoxContainer.new()
	_footer.name = "SideFooter"
	_footer.add_theme_constant_override("separation", 6)
	col.add_child(_footer)
	col.add_child(BackendStatus.new())
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 8)
	col.add_child(tools)
	for spec: Array in [["SheetButton", "BTN_CHARACTER_SHEET", sheet_requested, "character_sheet"], ["MapButton", "BTN_MAP", map_requested, "map"],
			["JournalButton", "BTN_JOURNAL", journal_requested, "journal"]]:
		var b := Button.new()
		b.name = spec[0]
		b.text = spec[1]
		b.tooltip_text = Hotkeys.tip(tr(spec[1]), spec[3], SaveManager.keys)  # v0.7.22.27
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 56)
		b.pressed.connect((spec[2] as Signal).emit)
		tools.add_child(b)
	var menu := Button.new()
	menu.text = "BTN_MENU"
	menu.tooltip_text = Hotkeys.tip(tr("BTN_MENU"), "pause_menu", SaveManager.keys)
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
	for box: Container in [_content, _footer]:
		for c in box.get_children():
			box.remove_child(c)
			c.queue_free()
	if not GameState.has_session():
		return
	var s := GameState.session
	if s.room_id != _open_room:
		_open = ""
		_open_room = s.room_id
	if not _open.is_empty():
		_show_open.call_deferred()
	var c := s.character
	var items: Dictionary = Catalog.data["items"]
	var world := GameState.world()
	var can_act := Backend.is_ready() and not GameState.is_busy()

	_heading(str(c.get("name", "")))
	var hp := _line(tr("SIDE_HERO_LINE").format({"race": c.get("race_name", ""), "class": c.get("class_name", ""), "level": int(c.get("level", 1)),
		"hp": c["hp"], "max": c["max_hp"], "ac": c["ac"]}) + ((" · +%d врем." % int(c["temp_hp"])) if int(c.get("temp_hp", 0)) > 0 else ""), false)  # big test #19 (v0.7.22.3)
	hp.name = "HeroHp"
	if int(c["hp"]) * 2 <= int(c["max_hp"]):
		hp.add_theme_color_override("font_color", UiTheme.BAD)
	var next_xp := LevelUp.xp_for(Catalog.data, int(c.get("level", 1)) + 1)
	var xp := tr("SIDE_HERO_XP").format({"xp": int(c.get("xp", 0)), "next": next_xp}) if int(c.get("level", 1)) < LevelUp.max_level(c, Catalog.data) else ""
	_line(" · ".join([Money.format(int(c["gold_cp"])), xp, tr("SIDE_HERO_TIME").format({"day": s.day, "part": TimeRules.part_name(s, Catalog.data),
		"clock": TimeRules.clock(s)})].filter(func(x: String) -> bool: return not x.is_empty())), true)
	if NeedRules.on(s):
		_needs(s, can_act)
	_craft_row(s, can_act)
	_work_row(s, can_act)
	_study_row(s, can_act)
	_family_row(s, can_act)
	_underworld_row(s, can_act)
	_office_row(s, can_act)
	_property_row(s)
	if LevelUp.can_level_up(c, Catalog.data):
		var lv := _button(tr("BTN_LEVEL_UP"), level_up_requested.emit, not GameState.is_busy())
		lv.name = "LevelUpButton"
		lv.theme_type_variation = UiTheme.ACCENT_BUTTON
		lv.alignment = HORIZONTAL_ALIGNMENT_CENTER
	var dev := DevelopmentRules.any_pick(c, Catalog.data)  # v0.7.19.1: a peaceful level not yet paid with a skill
	if not dev.is_empty():
		var db := _button(tr("BTN_DEV_LEVEL").format({"name": DevelopmentRules.direction(Catalog.data, dev)["name"]}), development_requested.emit, true)
		db.name = "DevelopmentButton"
		db.theme_type_variation = UiTheme.ACCENT_BUTTON
	if TimeRules.dark(s, Catalog.data):
		_line(tr("SIDE_DARK"), true).add_theme_color_override("font_color", UiTheme.WARN)
	var room := world.room(s.room_id)
	_subheading("SIDE_PLACE")
	_line(world.place_path(s.room_id), false).name = "PlacePath"  # v0.7.22.24: location › site › room
	if not s.in_conversation() and CrimeRules.held(s):
		_arrest(s, can_act)
	if not s.in_conversation():
		_meeting(s, can_act)  # v0.7.22.12: the foes did not notice the hero; the hero is a captive
	if not s.in_conversation():
		var npcs := s.npcs_here(world.world, s.room_id)
		if not npcs.is_empty():
			_subheading("SIDE_PEOPLE")
			for id: String in npcs:
				_npc_row(s, world, id, can_act)
		if not s.summons.is_empty():  # v0.7.22.22: the creatures a spell called
			_subheading("SIDE_WITH_YOU")
			var texts := AllyRules.summon_lines(s, Catalog.data)
			for i in s.summons.size():
				var srow := HBoxContainer.new()
				srow.add_theme_constant_override("separation", 6)
				_content.add_child(srow)
				var sl := Label.new()
				sl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
				sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				sl.text = texts[i]
				srow.add_child(sl)
				var sid := str(s.summons[i]["id"])
				var db := _small(srow, tr("BTN_SUMMON_DISMISS"), func() -> void:
					var err := GameState.dismiss_summon(sid)
					if not err.is_empty():
						EventBus.message.emit(tr(err)), can_act)
				db.name = "Dismiss_" + sid
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
		var here := CreatureRules.here(s, s.room_id)  # v0.7.22.11: the foes a fight left here
		var beasts := here.filter(func(cr: Dictionary) -> bool: return str(cr["state"]) == PropertyRules.TAME)
		var beaten := here.filter(func(cr: Dictionary) -> bool: return str(cr["state"]) != PropertyRules.TAME)
		if not beaten.is_empty():
			_subheading("SIDE_CREATURES")
		for cr: Dictionary in beaten:
			_creature_row(s, cr, can_act)
		if not beasts.is_empty():  # v0.7.27: the hero's own animals
			_subheading("SIDE_ANIMALS")
		for cr: Dictionary in beasts:
			_creature_row(s, cr, can_act)
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
		# «Взаимодействие с местом» (v0.7.22.7, big test #17): every thing of the room in its own window — take one,
		# open, look closer, «Забрать всё».
		PropRules.ensure_wares(s, Catalog.data, s.room_id)  # the trader's wares (v0.7.22.8)
		var n_things := PropRules.room_props(s, s.room_id).size() + CrimeRules.bodies_here(s, Catalog.data).size()
		var pb := Button.new()
		pb.name = "PlaceButton"
		pb.text = tr("BTN_PLACE").format({"n": n_things})
		pb.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pb.disabled = GameState.is_busy()
		pb.pressed.connect(place_requested.emit)
		_content.add_child(pb)
		for bp: Dictionary in PropRules.room_props(s, s.room_id):  # a notice board — its own window (v0.7.22.13)
			if QuestGen.is_board(Catalog.data, bp):
				var bpid := str(bp["id"])
				var n_orders := QuestGen.offered_by(s, "board:%s:%s" % [s.room_id, bpid]).size()
				var label := tr("BTN_BOARD_UNREAD") if QuestGen.board_unread(s, s.room_id, bpid) else tr("BTN_BOARD") if n_orders > 0 else tr("BTN_BOARD_NONE")
				var bb := _button(label.format({"name": bp["name"], "n": n_orders}), board_requested.emit.bind(bpid), not GameState.is_busy())
				bb.name = "Board_" + bpid
		_exits(s, world, can_act)
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
		if bool(ExplorationRules.rest_place(Catalog.data["world"], s.room_id, s, Catalog.data).get("own", false)):  # v0.7.39.5
			var sleep := func() -> void:
				var err := GameState.long_rest()
				if not err.is_empty():
					EventBus.message.emit(tr(err))
			var bed := _button(tr("BTN_OWN_BED"), sleep, can_act and inn_ok)
			bed.name = "OwnBedButton"
			bed.tooltip_text = tr("OWN_BED_TIP")
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


## A person of the scene in one row (v0.7.22.23): the full name talks, «Торговать» for a trader, «▾» (or the right
## button on the name) opens the rest under it — pockets, a follower's acts, attack.
func _npc_row(s: GameSession, world: WorldView, id: String, can_act: bool) -> void:
	var n := world.npc(id)
	var key := "npc:" + id
	var refuses := SocialRules.refuses(s, Catalog.data, id)  # v0.7.15.3
	var a := s.attitude(id)
	var att := tr("ATTITUDE_0" if a == 0 else ("ATTITUDE_P%d" % a if a > 0 else "ATTITUDE_M%d" % -a))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_content.add_child(row)
	var b := _row_button(row, str(n.get("name", id)), GameState.talk_to.bind(id, false), can_act and not refuses)
	b.name = "Talk_" + id
	b.tooltip_text = tr("TALK_REFUSED") if refuses else tr("SIDE_TALK_TIP").format({"name": n.get("name", id), "role": n.get("role", ""), "attitude": att})
	if a <= -2:
		b.add_theme_color_override("font_color", UiTheme.BAD)
	elif a >= 2:
		b.add_theme_color_override("font_color", UiTheme.OK)
	_on_right(b, key)
	if bool(n.get("trader", false)):
		var closed := TimeRules.shops_closed(s, Catalog.data) or TheftRules.shop_closed_for(s, id, Catalog.data) or refuses
		var tb := _small(row, tr("BTN_TRADE_SHORT"), GameState.talk_to.bind(id, true), can_act and not closed)
		tb.name = "Trade_" + id
		tb.size_flags_horizontal = Control.SIZE_SHRINK_END
		tb.tooltip_text = tr("SHOP_CLOSED_WANTED" if CrimeRules.shunned_by(s, Catalog.data, id) else "TALK_REFUSED" if refuses else
			"SHOP_CLOSED_FOR_YOU" if TheftRules.shop_closed_for(s, id) else "SHOP_CLOSED") if closed else tr("BTN_TRADE_WITH").format({"name": n.get("name", id)})
	_more(row, "More_" + id, key)
	if _open != key:
		return
	var bw := BondRules.word(s.character, Catalog.data, id)  # v0.7.31
	var role := _line("%s · %s%s" % [n.get("role", ""), att, (" · " + bw) if not bw.is_empty() else ""], true)
	role.name = "Role_" + id
	var acts := _acts("Acts_" + id)
	var pk := _flow(acts, tr("BTN_POCKETS_SHORT"), pockets_requested.emit.bind(id), can_act and TheftRules.can_steal(s, Catalog.data, id).is_empty())
	pk.name = "Pockets_" + id
	pk.tooltip_text = tr("BTN_POCKETS").format({"name": n.get("name", id)})
	if not JobRules.of(s, Catalog.data, id).is_empty():  # v0.7.26
		var jb := _flow(acts, tr("BTN_JOB"), job_requested.emit.bind(id), can_act)
		jb.name = "Jobs_" + id
		jb.tooltip_text = tr("BTN_JOB_TIP").format({"name": n.get("name", id)})
	var undeeded := PropertyRules.is_registry(Catalog.data, id) and PropertyRules.state(s.character).values().any(func(p: Dictionary) -> bool: return not bool(p.get("deed", false)))
	if not PropertyRules.of_seller(s, Catalog.data, id).is_empty() or undeeded:  # v0.7.27
		var sb := _flow(acts, tr("BTN_PROPERTY"), property_requested.emit.bind("seller", id), can_act)
		sb.name = "PropertySale_" + id
		sb.tooltip_text = tr("BTN_PROPERTY_SALE_TIP").format({"name": n.get("name", id)})
	if PropertyRules.is_registry(Catalog.data, id) and Catalog.data["rules"].has("shop"):  # v0.7.29: the charter and the stalls
		var tb := _flow(acts, tr("BTN_SHOP_REGISTRY"), shop_requested.emit.bind("registry", id), can_act)
		tb.name = "ShopRegistry_" + id
		tb.tooltip_text = tr("BTN_SHOP_REGISTRY_TIP")
	if ShopRules.is_supplier(s, Catalog.data, id):
		var wb := _flow(acts, tr("BTN_WHOLESALE"), shop_requested.emit.bind("supplier", id), can_act)
		wb.name = "Wholesale_" + id
		wb.tooltip_text = tr("BTN_WHOLESALE_TIP").format({"name": n.get("name", id)})
	if StudyRules.is_teacher(s, Catalog.data, id):  # v0.7.30
		var lb := _flow(acts, tr("BTN_STUDY"), study_requested.emit.bind(id), can_act)
		lb.name = "Study_" + id
		lb.tooltip_text = tr("BTN_STUDY_TIP").format({"name": n.get("name", id)})
	if not SiteRules.closed_to_hero(s, Catalog.data, id).is_empty():  # v0.7.39.2: the owner's leave
		var pw := SiteRules.ask_why(s, Catalog.data, id)
		var pb := _flow(acts, tr("BTN_PERMIT"), func() -> void:
			var err := GameState.permit_ask(id)
			if not err.is_empty():
				EventBus.message.emit(tr(err)), can_act and pw.is_empty())
		pb.name = "Permit_" + id
		pb.tooltip_text = tr(pw) if not pw.is_empty() else tr("BTN_PERMIT_TIP").format({"dc": SiteRules.ask_dc(s, Catalog.data, id),
			"chance": SiteRules.ask_chance(s, Catalog.data, id)})
	if not FamilyRules.engaged(s).is_empty() and not FamilyRules.officiant(s, Catalog.data, id).is_empty():  # v0.7.32
		var why := FamilyRules.wedding_why(s, Catalog.data, id)
		var wd := _flow(acts, tr("BTN_WEDDING"), func() -> void:
			var err := GameState.family_act("wedding", id)
			if not err.is_empty():
				EventBus.message.emit(tr(err)), can_act and why.is_empty())
		wd.name = "Wedding_" + id
		wd.tooltip_text = tr(why) if not why.is_empty() else tr("BTN_WEDDING_TIP").format({"money": Money.format(FamilyRules.fee(Catalog.data, FamilyRules.officiant(s, Catalog.data, id)))})
	if Catalog.data["rules"].has("office") and not OfficeRules.of_chief(Catalog.data, id).is_empty():  # v0.7.34
		var fb := _flow(acts, tr("BTN_OFFICES"), office_requested.emit.bind(id), can_act)
		fb.name = "Office_" + id
		fb.tooltip_text = tr("BTN_OFFICES_TIP")
	if Catalog.data["rules"].has("underworld"):  # v0.7.33
		for org: String in OrgRules.of_head(s, Catalog.data, id):
			var ob := _flow(acts, str(OrgRules.word(s, Catalog.data, org)["nom"]).capitalize(), org_requested.emit.bind(org), can_act)
			ob.name = "Org_" + id
			ob.tooltip_text = tr("BTN_ORG_HEAD_TIP").format({"org": OrgRules.org_name(s, Catalog.data, org)})
		var rw := OrgRules.recruit_why(s, Catalog.data, id)
		if not OrgRules.own(s, Catalog.data).is_empty() and not rw in ["ORG_NOT_FOR_HIM", "ORG_MEMBER"]:
			var rb := _flow(acts, tr("BTN_RECRUIT"), func() -> void:
				var err := GameState.org_act("recruit", id)
				if not err.is_empty():
					EventBus.message.emit(tr(err)), can_act and rw.is_empty())
			rb.name = "Recruit_" + id
			rb.tooltip_text = tr(rw).format({"at": int(OrgRules.cfg(Catalog.data)["recruit_bond"])}) if not rw.is_empty() else tr("BTN_RECRUIT_TIP")
	var bo := _flow(acts, tr("BTN_BOND"), bond_requested.emit.bind(id), can_act)  # v0.7.31
	bo.name = "Bond_" + id
	bo.tooltip_text = tr("BTN_BOND_TIP").format({"name": n.get("name", id)})
	if BankRules.is_bank(s, Catalog.data, id):  # v0.7.28
		var bb := _flow(acts, tr("BTN_BANK"), bank_requested.emit.bind(id), can_act)
		bb.name = "Bank_" + id
		bb.tooltip_text = tr("BTN_BANK_TIP").format({"name": n.get("name", id)})
	if not PropertyRules.animals_of(Catalog.data, id).is_empty():
		var ab := _flow(acts, tr("BTN_ANIMALS"), property_requested.emit.bind("animals", id), can_act)
		ab.name = "Animals_" + id
	var follow: Array = []  # v0.7.22.22 (#25): a follower by the buttons, as the prisoners
	if s.followers.has(id):
		follow = [["stay", "BTN_FOLLOWER_STAY"], ["let_go", "BTN_FOLLOWER_LET_GO"]]
	elif str(s.npc_at.get(id, "")) == s.room_id:
		follow = [["lead", "BTN_FOLLOWER_LEAD"], ["let_go", "BTN_FOLLOWER_LET_GO"]]
	for fa: Array in follow:
		var what: String = fa[0]
		var fb := _flow(acts, tr(fa[1]), func() -> void:
			var err := GameState.follower_act(id, what)
			if not err.is_empty():
				EventBus.message.emit(tr(err)), can_act)
		fb.name = "Follower_%s_%s" % [what, id]
		if tr(fa[1] + "_TIP") != fa[1] + "_TIP":
			fb.tooltip_text = tr(fa[1] + "_TIP")
	var who := str(n.get("name", id))
	var at := _flow(acts, tr("BTN_ATTACK_SHORT"), func() -> void:
		ConfirmBox.ask(self, tr("CONFIRM_ATTACK_TITLE").format({"name": who}), tr("CONFIRM_ATTACK") + _law_line(s), tr("BTN_ATTACK_SHORT"), func() -> void:
			var err := GameState.attack_npc(id)
			if not err.is_empty():
				EventBus.message.emit(tr(err))), can_act)
	at.name = "Attack_" + id  # the fight at once, without the master: last and red, apart from the peaceful acts
	at.tooltip_text = tr("BTN_ATTACK_NPC").format({"name": n.get("name", id)})
	at.add_theme_color_override("font_color", UiTheme.BAD)


## A creature a fight left (v0.7.22.11) in one row: its state, «▾» (or the right button) opens its acts.
func _creature_row(s: GameSession, cr: Dictionary, can_act: bool) -> void:
	var cid := str(cr["id"])
	var key := "cr:" + cid
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_content.add_child(row)
	var l := Label.new()
	l.name = "CreatureLine_" + cid
	l.text = CreatureRules.text(cr, Catalog.data)
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.mouse_filter = Control.MOUSE_FILTER_STOP
	row.add_child(l)
	_on_right(l, key)
	_more(row, "CreatureMore_" + cid, key)
	if _open != key:
		return
	if str(cr["state"]) == PropertyRules.TAME:  # v0.7.27: an own beast goes along or stays, or is let go
		_animal_acts(s, cr, can_act)
		return
	var specs: Array = [["talk", "BTN_CREATURE_TALK"]] if str(cr["state"]) != "unconscious" else []  # v0.7.22.16: one knocked out does not talk
	if not bool(cr.get("bound", false)) and str(cr["state"]) != "truce":
		specs.append(["bind", "BTN_CREATURE_BIND"])
	if bool(cr.get("bound", false)):
		specs.append(["lead", "BTN_CREATURE_STAY" if bool(cr.get("led", false)) else "BTN_CREATURE_LEAD"])
	if not str(cr.get("npc_id", "")).is_empty() and not bool(cr.get("searched", false)):
		specs.append(["search", "BTN_CREATURE_SEARCH"])  # v0.7.22.16: a knocked-out person's pockets
	if CreatureRules.can(s, cid, "hand_over", Catalog.data).is_empty():
		specs.append(["hand_over", "BTN_CREATURE_HAND_OVER"])  # v0.7.22.17: the law takes the prisoner
	specs.append(["free", "BTN_CREATURE_FREE"])
	specs.append(["finish", "BTN_CREATURE_FINISH"] if CreatureRules.helpless(cr) else ["attack", "BTN_CREATURE_ATTACK"])
	var acts := _acts("CreatureActs_" + cid)
	for sp: Array in specs:
		var what: String = sp[0]
		var run := func() -> void:
			var err := GameState.creature_act(cid, what)
			if not err.is_empty():
				EventBus.message.emit(tr(err))
		var cr_name := str(cr.get("name", cid))
		var cb := _flow(acts, tr(sp[1]), func() -> void:
			if what == "finish":  # v0.7.22.27: a kill is not undone
				ConfirmBox.ask(self, tr("CONFIRM_FINISH_TITLE").format({"name": cr_name}), tr("CONFIRM_FINISH") + _law_line(s), tr(sp[1]), run)
			else:
				run.call(), can_act)
		cb.name = "Creature_%s_%s" % [what, cid]
		if what == "hand_over":
			cb.tooltip_text = tr("CREATURE_HAND_OVER_TIP")
		if what in ["attack", "finish"]:
			cb.add_theme_color_override("font_color", UiTheme.BAD)


## The pinned part under the list (v0.7.22.23, the UI audit С1): sneaking, «Осмотреться» and «Обыскать» side by side,
## the exits one to a row in the small font — never under the scroll.
func _exits(s: GameSession, world: WorldView, can_act: bool) -> void:
	var head := Label.new()
	head.text = "SIDE_EXITS"
	head.theme_type_variation = UiTheme.MUTED_LABEL
	head.add_theme_color_override("font_color", UiTheme.ACCENT)
	_footer.add_child(head)
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
	_footer.add_child(sneak)
	var looks := HBoxContainer.new()
	looks.add_theme_constant_override("separation", 6)
	_footer.add_child(looks)
	for spec: Array in [["LookButton", "BTN_LOOK", "perception"], ["SearchButton", "BTN_SEARCH", "investigation"]]:
		var skill: String = spec[2]
		var lb := _row_button(looks, tr(spec[1]), func() -> void:
			var err := GameState.search_room(skill)
			if not err.is_empty():
				EventBus.message.emit(tr(err)), can_act)
		lb.name = spec[0]
		lb.alignment = HORIZONTAL_ALIGNMENT_CENTER
		lb.tooltip_text = tr(spec[1] + "_TIP")
	var exits_scroll := ScrollContainer.new()
	exits_scroll.name = "ExitsScroll"
	exits_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_footer.add_child(exits_scroll)
	_exit_list = VBoxContainer.new()
	_exit_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_exit_list.add_theme_constant_override("separation", 6)
	exits_scroll.add_child(_exit_list)
	_exit_list.minimum_size_changed.connect(_fit_exits.bind(exits_scroll))
	_fit_exits.call_deferred(exits_scroll)
	var trapped := {}
	for ft: Dictionary in ExplorationRules.found_traps(s, Catalog.data["world"], s.room_id):
		trapped[ft["to"]] = ft["secret"]
	var shut := CrimeRules.held(s) or EncounterRules.captive(s)
	for e: String in ExplorationRules.open_exits(s, Catalog.data["world"], s.room_id):
		var room_name := str(world.room(e).get("name", e))
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 6)
		_exit_list.add_child(line)
		if trapped.has(e):
			var to := e
			var by := _exit_button(line, tr("BTN_TRAP_BYPASS").format({"room": room_name}), func() -> void: _trap(to, false), can_act)
			by.name = "Exit_" + e
			by.tooltip_text = str(trapped[e]["text"]) + "\n" + tr("TRAP_BYPASS_TIP")
			var dis := _exit_button(line, tr("BTN_TRAP_DISARM"), func() -> void: _trap(to, true), can_act)
			dis.name = "Disarm_" + e
			dis.tooltip_text = str(trapped[e]["text"]) + "\n" + tr("TRAP_DISARM_TIP")
			continue
		var private := not world.is_public(e)  # v0.7.22.24: the player knows before the step
		var why := DoorRules.blocked(s, Catalog.data, s.room_id, e)
		var door_key := "door:" + e
		var go_or_door := GameState.go.bind(e) if why.is_empty() else _toggle.bind(door_key)  # a shut door opens its ways
		var b := _exit_button(line, "→ " + room_name + (tr("EXIT_PRIVATE") if private else "") + DoorRules.label(s, Catalog.data, s.room_id, e),
			go_or_door, can_act and not shut)
		b.name = "Exit_" + e
		b.tooltip_text = tr("CRIME_HELD") if CrimeRules.held(s) else room_name
		if not why.is_empty():
			b.tooltip_text = "%s
%s" % [room_name, tr(why)]
		var ways := DoorRules.ways(s, Catalog.data, s.room_id, e)
		if not ways.is_empty() and not shut:
			_more(line, "Door_" + e, door_key)
			if _open == door_key:
				_door_acts(e, ways, can_act)
		var owner := str(world.site_of(e).get("owner", ""))
		if private and not CrimeRules.held(s) and not owner.is_empty():
			b.tooltip_text = "%s
%s" % [room_name, tr("EXIT_PRIVATE_WELCOME" if SiteRules.unwelcome(s, Catalog.data, e).is_empty() else
				"EXIT_PRIVATE_TIP").format({"owner": world.npc(owner).get("name", owner)})]


## Food, water, sleep as three small bars under the hero (v0.7.23), «Поесть» and «Попить» beside them.
func _needs(s: GameSession, can_act: bool) -> void:
	var data := Catalog.data
	var row := HBoxContainer.new()
	row.name = "Needs"
	row.add_theme_constant_override("separation", 10)
	_content.add_child(row)
	for need: String in NeedRules.KINDS:
		var v := NeedRules.value(s, data, need)
		var st := NeedRules.stage(s, data, need)
		var col := VBoxContainer.new()
		col.name = "Need_" + need
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 2)
		col.mouse_filter = Control.MOUSE_FILTER_STOP
		col.tooltip_text = "%s %d/100%s" % [NeedRules.cfg(data)[need]["name"], roundi(v), (" — " + str(st["chip"])) if not st.is_empty() else ""]
		row.add_child(col)
		var l := Label.new()
		l.text = str(st.get("chip", NeedRules.cfg(data)[need]["name"]))
		l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		l.theme_type_variation = UiTheme.MUTED_LABEL
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		if not st.is_empty():
			l.add_theme_color_override("font_color", UiTheme.WARN if v >= 20.0 else UiTheme.BAD)
		col.add_child(l)
		var bar := ProgressBar.new()
		bar.max_value = 100.0
		bar.value = v
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 6)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var fill_col := UiTheme.OK if v >= 50.0 else UiTheme.WARN if v >= 20.0 else UiTheme.BAD
		bar.add_theme_stylebox_override("fill", UiTheme.box(fill_col, fill_col, 0, 0, 2))
		bar.add_theme_stylebox_override("background", UiTheme.box(UiTheme.BG, UiTheme.BORDER, 1, 0, 2))
		col.add_child(bar)
	# Only the acts that do good now: the row takes no height when there is nothing to do.
	var specs: Array = []
	if NeedRules.can_eat(s, data).is_empty():
		specs.append(["EatButton", "BTN_EAT", "eat"])
	if NeedRules.can_drink(s, data).is_empty():
		specs.append(["DrinkButton", "BTN_DRINK", "drink"])
	if NeedRules.can_fill(s, data).is_empty():
		specs.append(["FillWater", "BTN_FILL_WATER", "fill"])
	if specs.is_empty():
		return
	var acts := HBoxContainer.new()
	acts.add_theme_constant_override("separation", 6)
	_content.add_child(acts)
	for spec: Array in specs:
		var b := _row_button(acts, tr(spec[1]), _need.bind(spec[2]), can_act)
		b.name = spec[0]
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.add_theme_font_size_override("font_size", UiTheme.SIZE_SMALL)
		b.tooltip_text = tr(spec[1] + "_TIP")


## Crafting (v0.7.24): «Ремесло» when the hero knows a recipe, has work begun or a thing to break down; the room's
## gathering spots as buttons. No row when there is nothing of it.
func _craft_row(s: GameSession, can_act: bool) -> void:
	var data := Catalog.data
	var craft := not CraftRules.known(s, data).is_empty() or not CraftRules.project(s.character).is_empty()
	var spots := CraftRules.gather_here(s, data)
	if not craft and spots.is_empty():
		return
	var acts := HFlowContainer.new()  # the gathering spots wrap rather than cut their names (v0.7.25)
	acts.name = "CraftActs"
	acts.add_theme_constant_override("h_separation", 6)
	acts.add_theme_constant_override("v_separation", 6)
	_content.add_child(acts)
	if craft:
		var p := CraftRules.project(s.character)
		var label := tr("BTN_CRAFT") if p.is_empty() else tr("BTN_CRAFT_WORK").format({"n": CraftRules.progress(s.character)})
		var cb := _row_button(acts, label, craft_requested.emit, not GameState.is_busy())
		cb.name = "CraftButton"
		cb.alignment = HORIZONTAL_ALIGNMENT_CENTER
		cb.add_theme_font_size_override("font_size", UiTheme.SIZE_SMALL)
		cb.tooltip_text = tr("BTN_CRAFT_TIP")
	for tag: String in spots:
		var g: Dictionary = CraftRules.cfg(data)["gather"][tag]
		var why := CraftRules.gather_why(s, data, tag)
		var gb := _row_button(acts, str(g["name"]), func() -> void:
			var err := GameState.craft_act("gather", tag)
			if not err.is_empty():
				EventBus.message.emit(tr(err)), can_act and why.is_empty())
		gb.name = "Gather_" + tag
		gb.alignment = HORIZONTAL_ALIGNMENT_CENTER
		gb.clip_text = false
		gb.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		gb.add_theme_font_size_override("font_size", UiTheme.SIZE_SMALL)
		gb.tooltip_text = tr(why) if not why.is_empty() else tr("GATHER_TIP").format({"time": TimeRules.span(int(g["minutes"])),
			"skill": CraftRules.tr_skill(data, str(g["skill"])), "dc": int(g["dc"])})


## Work (v0.7.26): a shift of each job whose employer is here, the employer's window by the right button.
func _work_row(s: GameSession, can_act: bool) -> void:
	var data := Catalog.data
	var ids: Array[String] = []
	for id: String in JobRules.state(s.character):
		if JobRules.employer_here(s, data, id):
			ids.append(id)
	if ids.is_empty():
		return
	var acts := HFlowContainer.new()
	acts.name = "WorkActs"
	acts.add_theme_constant_override("h_separation", 6)
	acts.add_theme_constant_override("v_separation", 6)
	_content.add_child(acts)
	for id: String in ids:
		var j := JobRules.job(s, data, id)
		var b := _row_button(acts, tr("BTN_WORK_SHIFT").format({"name": JobRules.rank_name(s, data, id, JobRules.rank(s.character, id))}), func() -> void:
			var err := GameState.job_act("shift", id)
			if not err.is_empty():
				EventBus.message.emit(tr(err)), can_act and JobRules.shift_why(s, data, id).is_empty())
		b.name = "WorkShift_" + id
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.clip_text = false
		b.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		b.add_theme_font_size_override("font_size", UiTheme.SIZE_SMALL)
		b.tooltip_text = tr("BTN_WORK_SHIFT_TIP").format({"job": j.get("name", id), "time": TimeRules.span(JobRules.hours(s, data, id) * 60),
			"chance": JobRules.shift_chance(s, data, id), "pay": Money.format(JobRules.pay(s, data, id))})
		var npc := str(j.get("employer", ""))
		b.gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and e.pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT:
				job_requested.emit(npc))


func _animal_acts(_s: GameSession, cr: Dictionary, can_act: bool) -> void:
	var cid := str(cr["id"])
	var acts := _acts("CreatureActs_" + cid)
	var lb := _flow(acts, tr("BTN_CREATURE_STAY" if bool(cr.get("led", false)) else "BTN_ANIMAL_LEAD"), func() -> void:
		var err := GameState.creature_act(cid, "lead")
		if not err.is_empty():
			EventBus.message.emit(tr(err)), can_act)
	lb.name = "Creature_lead_" + cid
	var name := str(cr.get("name", cid))
	var rb := _flow(acts, tr("BTN_ANIMAL_RELEASE"), func() -> void:
		ConfirmBox.ask(self, tr("CONFIRM_ANIMAL_RELEASE_TITLE").format({"name": name}), tr("CONFIRM_ANIMAL_RELEASE"), tr("BTN_ANIMAL_RELEASE"), func() -> void:
			var err := GameState.property_act("release", cid)
			if not err.is_empty():
				EventBus.message.emit(tr(err))), can_act)
	rb.name = "Creature_release_" + cid
	rb.add_theme_color_override("font_color", UiTheme.BAD)


## Study (v0.7.30): «Учёба» when a lesson may go here — a teacher of the hero's course is here or a study book is carried.
func _study_row(s: GameSession, can_act: bool) -> void:
	var data := Catalog.data
	var ready := not StudyRules.books(s, data).is_empty()
	for id: String in StudyRules.view(s.character)["courses"]:
		if StudyRules.here(s, data, str(StudyRules.course(s, data, id).get("teacher", ""))):
			ready = true
	if not ready:
		return
	var acts := HFlowContainer.new()
	acts.name = "StudyActs"
	_content.add_child(acts)
	var b := _row_button(acts, tr("BTN_STUDY_MINE"), study_requested.emit.bind(""), can_act)
	b.name = "StudyButton"
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_theme_font_size_override("font_size", UiTheme.SIZE_SMALL)
	b.tooltip_text = tr("BTN_STUDY_MINE_TIP")


## Family (v0.7.32): «Семья» when the hero is engaged, married or has kin.
func _family_row(s: GameSession, can_act: bool) -> void:
	var f := FamilyRules.view(s.character)
	if FamilyRules.engaged(s).is_empty() and FamilyRules.spouse(s).is_empty() and FamilyRules.children(s).is_empty() and (f.get("kin", []) as Array).is_empty():
		return
	var acts := HFlowContainer.new()
	acts.name = "FamilyActs"
	_content.add_child(acts)
	var b := _row_button(acts, tr("BTN_FAMILY"), family_requested.emit, can_act)
	b.name = "FamilyButton"
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_theme_font_size_override("font_size", UiTheme.SIZE_SMALL)
	b.tooltip_text = tr("BTN_FAMILY_TIP")


## The underworld (v0.7.33): «Дела» while a criminal job is on, «Братство» for the hero's organizations (or to found one
## once the hero owns a place and has done a job).
func _underworld_row(s: GameSession, can_act: bool) -> void:
	if not Catalog.data["rules"].has("underworld"):
		return
	var mine := OrgRules.mine(s, Catalog.data)
	var done := HeistRules.view(s.character).values().any(func(h: Dictionary) -> bool: return str(h.get("status", "")) == "done")
	var founding := not (s.character.get("property", {}) as Dictionary).is_empty() and done
	var entry := OrgRules.entry_here(s, Catalog.data)  # v0.7.39.2: a hideout's door here, paid to walk in
	var ew := OrgRules.entry_why(s, Catalog.data, entry) if not entry.is_empty() else "ORG_NO_ENTRY"
	if ew in ["ORG_NO_ENTRY", "ORG_ENTRY_OPEN"]:
		entry = ""
	var jobs := HeistRules.followed(s, Catalog.data)  # v0.7.39.3: a done job stays until sold and paid
	if jobs.is_empty() and mine.is_empty() and not founding and entry.is_empty():
		return
	var acts := HFlowContainer.new()
	acts.name = "UnderworldActs"
	_content.add_child(acts)
	if not entry.is_empty():
		var eb := _row_button(acts, tr("BTN_ORG_ENTRY").format({"money": Money.format(int(OrgRules.def(s, Catalog.data, entry)["entry_cp"]))}), func() -> void:
			var err := GameState.org_act("entry", entry)
			if not err.is_empty():
				EventBus.message.emit(tr(err)), can_act and ew.is_empty())
		eb.name = "OrgEntry_" + entry
		eb.alignment = HORIZONTAL_ALIGNMENT_CENTER
		eb.add_theme_font_size_override("font_size", UiTheme.SIZE_SMALL)
		eb.tooltip_text = tr(ew) if not ew.is_empty() else tr("BTN_ORG_ENTRY_TIP").format({"org": OrgRules.org_name(s, Catalog.data, entry)})
	if not jobs.is_empty():
		var h := _row_button(acts, tr("BTN_HEISTS"), heist_requested.emit, can_act)
		h.name = "HeistButton"
		h.alignment = HORIZONTAL_ALIGNMENT_CENTER
		h.add_theme_font_size_override("font_size", UiTheme.SIZE_SMALL)
		h.tooltip_text = tr("BTN_HEISTS_TIP")
	if not mine.is_empty() or founding:
		var label := tr("BTN_ORG") if mine.size() != 1 else str(OrgRules.word(s, Catalog.data, str(mine[0]))["nom"]).capitalize()  # v0.7.39.1: «Артель»
		var o := _row_button(acts, label, org_requested.emit.bind(mine[0] if not mine.is_empty() else ""), can_act)
		o.name = "OrgButton"
		o.alignment = HORIZONTAL_ALIGNMENT_CENTER
		o.add_theme_font_size_override("font_size", UiTheme.SIZE_SMALL)
		o.tooltip_text = tr("BTN_ORG_TIP")


## Offices (v0.7.34): «Служба» while the hero holds one or the room holds an election.
func _office_row(s: GameSession, can_act: bool) -> void:
	if not Catalog.data["rules"].has("office"):
		return
	if OfficeRules.held(s.character).is_empty() and OfficeRules.of_room(Catalog.data, s.room_id).is_empty():
		return
	var acts := HFlowContainer.new()
	acts.name = "OfficeActs"
	_content.add_child(acts)
	var b := _row_button(acts, tr("BTN_OFFICE"), office_requested.emit.bind(""), can_act)
	b.name = "OfficeButton"
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_theme_font_size_override("font_size", UiTheme.SIZE_SMALL)
	b.tooltip_text = tr("BTN_OFFICE_TIP")


## Property (v0.7.27): «Имущество» when the hero owns a place or a beast; the window of the hero's places.
func _property_row(s: GameSession) -> void:
	var venue := ShopRules.here(s, Catalog.data)  # v0.7.29
	if PropertyRules.state(s.character).is_empty() and PropertyRules.animals(s).is_empty() and venue.is_empty():
		return
	var acts := HFlowContainer.new()
	acts.name = "PropertyActs"
	acts.add_theme_constant_override("h_separation", 6)
	_content.add_child(acts)
	if not venue.is_empty():
		var sb := _row_button(acts, tr("BTN_SHOP"), shop_requested.emit.bind("venue", venue), not GameState.is_busy())
		sb.name = "ShopButton"
		sb.alignment = HORIZONTAL_ALIGNMENT_CENTER
		sb.add_theme_font_size_override("font_size", UiTheme.SIZE_SMALL)
		sb.tooltip_text = tr("BTN_SHOP_TIP")
	if PropertyRules.state(s.character).is_empty() and PropertyRules.animals(s).is_empty():
		return
	var here := PropertyRules.here(s, Catalog.data)
	var label := tr("BTN_PROPERTY") if here.is_empty() else tr("BTN_PROPERTY_HERE").format({"name": PropertyRules.name_of(s, Catalog.data, here)})
	var b := _row_button(acts, label, property_requested.emit.bind("mine", ""), not GameState.is_busy())
	b.name = "PropertyButton"
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.clip_text = false
	b.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	b.add_theme_font_size_override("font_size", UiTheme.SIZE_SMALL)
	b.tooltip_text = tr("BTN_PROPERTY_TIP")


func _need(act: String) -> void:
	var err := GameState.need_act(act)
	if not err.is_empty():
		EventBus.message.emit(tr(err))


## The exits have a fixed height of EXIT_ROWS rows whatever their number (v0.7.39: the panel grew with a room of many
## ways); the rest scroll by the wheel.
func _fit_exits(scroll: ScrollContainer) -> void:
	if not is_instance_valid(scroll) or not is_instance_valid(_exit_list):
		return
	var row := 0.0
	for line: Node in _exit_list.get_children():
		row = maxf(row, (line as Control).get_combined_minimum_size().y)
	if row <= 0.0:
		row = 28.0
	scroll.custom_minimum_size.y = row * EXIT_ROWS + float(_exit_list.get_theme_constant("separation")) * (EXIT_ROWS - 1)


## A button that fills its place and cuts a long text with «…» (the whole one is in the tooltip).
func _row_button(parent: Container, text: String, action: Callable, enabled: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.clip_text = true
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(60, 0)
	b.disabled = not enabled
	b.pressed.connect(func() -> void: action.call())
	parent.add_child(b)
	return b


## An exit: a row-filling button in the small font, a little lower than the others.
func _exit_button(parent: Container, text: String, action: Callable, enabled: bool) -> Button:
	var b := _row_button(parent, text, action, enabled)
	b.add_theme_font_size_override("font_size", UiTheme.SIZE_SMALL)
	b.custom_minimum_size = Vector2(60, 34)
	return b


## The open acts of a row: buttons as wide as their text, wrapping.
func _acts(node_name: String) -> HFlowContainer:
	var acts := HFlowContainer.new()
	acts.name = node_name
	acts.add_theme_constant_override("h_separation", 6)
	acts.add_theme_constant_override("v_separation", 6)
	_content.add_child(acts)
	return acts


func _flow(parent: Container, text: String, action: Callable, enabled: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.disabled = not enabled
	b.pressed.connect(func() -> void: action.call())
	parent.add_child(b)
	return b


## «▾» / «▴»: opens or closes the row's acts.
func _more(row: HBoxContainer, node_name: String, key: String) -> void:
	var m := Button.new()
	m.name = node_name
	m.text = "▴" if _open == key else "▾"
	m.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	m.tooltip_text = tr("SIDE_MORE_TIP")
	m.custom_minimum_size = Vector2(40, 0)
	m.pressed.connect(_toggle.bind(key))
	row.add_child(m)


## The right button on a row opens its acts, as in BG3 (the UI audit П4).
func _on_right(control: Control, key: String) -> void:
	control.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT:
			control.accept_event()
			_toggle(key))


## Opens a row (one at a time) or closes it; the panel is rebuilt after the click is done.
func _toggle(key: String) -> void:
	_open = "" if _open == key else key
	_rebuild.call_deferred()


## The opened acts may fall under a long footer: scroll them into view once laid out (after every rebuild while a row
## is open — that row is where the player looks).
func _show_open() -> void:
	for i in 2:  # a flow of buttons settles its height a frame after it is laid out
		await get_tree().process_frame
	for n: Node in _content.get_children():
		if n is HFlowContainer and is_instance_valid(n):
			_scroll.ensure_control_visible(n as Control)


## The ways with a door (v0.7.22.25) under its exit: a key, thieves' tools, force, blows, a spell, a torch, waiting.
func _door_acts(to: String, ways: Array[Dictionary], can_act: bool) -> void:
	var s := GameState.session
	var acts := HFlowContainer.new()
	acts.name = "DoorActs_" + to
	acts.add_theme_constant_override("h_separation", 6)
	acts.add_theme_constant_override("v_separation", 6)
	_exit_list.add_child(acts)
	var dcs := DoorRules.dcs(s, Catalog.data, s.room_id, to)
	var d := DoorRules.def(Catalog.data, s.room_id, to)
	var mat: Dictionary = DoorRules.cfg(Catalog.data)["materials"].get(str(d.get("material", "wood")), {})
	for w: Dictionary in ways:
		var how := str(w["how"])
		var sp := str(w.get("spell", ""))
		var text := tr("DOOR_WAY_" + how.to_upper())
		if how == "spell":
			text = text.format({"spell": str(Catalog.data["spells"].get(sp, {}).get("name", sp))})
		var btn := _flow(acts, text, func() -> void:
			var err := GameState.door_act(to, how, sp)
			if not err.is_empty():
				EventBus.message.emit(tr(err)), can_act)
		btn.name = "DoorWay_%s%s" % [how, "_" + sp if not sp.is_empty() else ""]
		btn.add_theme_font_size_override("font_size", UiTheme.SIZE_SMALL)
		btn.tooltip_text = tr("DOOR_WAY_%s_TIP" % how.to_upper()).format({"dc": dcs.get(how, 0), "ac": int(mat.get("ac", 15)),
			"hp": DoorRules.hp(s, Catalog.data, s.room_id, to), "max": DoorRules.max_hp(Catalog.data, d)})
	if ways.any(func(w: Dictionary) -> bool: return str(w["how"]) == "force") and not ways.any(func(w: Dictionary) -> bool: return str(w["how"]) == "pick"):
		var pb := _flow(acts, tr("DOOR_WAY_PICK"), func() -> void: pass, false)  # v0.7.39.3: seen, grey without the tools
		pb.name = "DoorWay_pick"
		pb.add_theme_font_size_override("font_size", UiTheme.SIZE_SMALL)
		pb.tooltip_text = _no_picks(s)


## Why «Взломать» is grey: no thieves' tools, and where to get them (v0.7.39.3).
func _no_picks(s: GameSession) -> String:
	var hint := FenceRules.tool_hint(s, Catalog.data, "thieves_tools")
	return tr("PICK_NO_TOOLS") + ("" if hint.is_empty() else ": " + hint)


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
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # big test #25 (v0.7.22.5): the whole text, on two lines if need be
	b.disabled = not enabled
	b.pressed.connect(func() -> void: action.call())
	_content.add_child(b)
	return b


## A short button of a row (v0.7.22.16): it shares the row with the others.
func _small(row: HBoxContainer, text: String, action: Callable, enabled: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.disabled = not enabled
	b.pressed.connect(func() -> void: action.call())
	row.add_child(b)
	return b


## The foes lurking unaware (attack by surprise, talk first) and the captivity (break free, slip, talk), v0.7.22.12.
func _meeting(s: GameSession, can_act: bool) -> void:
	var data := Catalog.data
	var specs: Array = []
	if not EncounterRules.lurking(s, s.room_id).is_empty():
		var enc := EncounterRules.lurking_encounter(s, data, s.room_id)
		_subheading("SIDE_UNSEEN")
		for e: Dictionary in enc.get("enemies", []):
			_line("%s ×%d" % [e.get("name", e["monster"]), int(e.get("count", 1))], false)
		var why := EncounterRules.talkable(s, data, enc.get("enemies", []))
		specs = [["Encounter_attack", tr("BTN_ENCOUNTER_ATTACK"), "", func() -> String: return GameState.encounter_attack()],
			["Encounter_persuasion", tr("BTN_ENCOUNTER_TALK").format({"skill": tr("SKILL_PERSUASION")}), why, func() -> String: return GameState.encounter_parley("persuasion")],
			["Encounter_intimidation", tr("BTN_ENCOUNTER_TALK").format({"skill": tr("SKILL_INTIMIDATION")}),
				EncounterRules.talkable(s, data, enc.get("enemies", []), "intimidation"), func() -> String: return GameState.encounter_parley("intimidation")]]
	elif EncounterRules.captive(s):
		_subheading("SIDE_CAPTIVE")
		for e: Dictionary in s.captive.get("foes", []):
			_line(str(e.get("name", e["monster"])), false)
		specs = [["Escape_athletics", tr("BTN_ESCAPE_ATHLETICS").format({"dc": int(EncounterRules.cfg(data)["escape_dc"])}), "", func() -> String: return GameState.escape_captivity("escape_athletics")],
			["Escape_sleight", tr("BTN_ESCAPE_SLEIGHT").format({"dc": int(EncounterRules.cfg(data)["escape_dc"])}), "", func() -> String: return GameState.escape_captivity("escape_sleight")],
			["Escape_talk", tr("BTN_ESCAPE_TALK"), EncounterRules.can_escape(s, data, "talk"), func() -> String: return GameState.escape_captivity("talk")]]
	for sp: Array in specs:
		var act: Callable = sp[3]
		var why: String = sp[2]
		var b := _button(sp[1], func() -> void:
			var err: String = act.call()
			if not err.is_empty():
				EventBus.message.emit(tr(err)), can_act and why.is_empty())
		b.name = sp[0]
		b.theme_type_variation = UiTheme.ACCENT_BUTTON
		if not why.is_empty():
			b.tooltip_text = tr(why)


## The guard holds the hero (v0.7.14): the wergild, the stocks or a fight.
func _arrest(s: GameSession, can_act: bool) -> void:
	_subheading("SIDE_ARREST")
	var loc := GameState.world().location_id(s.room_id)
	var specs := [["pay", tr("BTN_CRIME_PAY").format({"cost": Money.format(CrimeRules.fine(s, Catalog.data, loc))}), ""],
		["stocks", tr("BTN_CRIME_STOCKS").format({"days": CrimeRules.stocks_days(s, Catalog.data, loc), "name": CrimeRules.sentence(s, Catalog.data, loc)["name"]}), tr("BTN_CRIME_STOCKS_TIP")],
		["resist", tr("BTN_CRIME_RESIST"), tr("BTN_CRIME_RESIST_TIP")]]
	var dc := int(Catalog.rules()["dc_tiers"][CrimeRules.talk_tier(s, Catalog.data, loc)])  # v0.7.22.2: as in BG3
	for how: String in CrimeRules.TALK:
		specs.append([how, tr("BTN_CRIME_" + how.to_upper()).format({"dc": dc}), tr("BTN_CRIME_TALK_TIP")])
	specs.append(["bribe", tr("BTN_CRIME_BRIBE").format({"cost": Money.format(CrimeRules.bribe(s, Catalog.data, loc))}), tr("BTN_CRIME_BRIBE_TIP")])
	for spec: Array in specs:
		var how: String = spec[0]
		var why := CrimeRules.can_answer(s, Catalog.data, how)
		var answer := func() -> void:
			var err := GameState.crime_answer(how)
			if not err.is_empty():
				EventBus.message.emit(tr(err))
		var b := _button(spec[1], func() -> void:
			if how == "resist":  # v0.7.22.27: a fight with the guard
				ConfirmBox.ask(self, tr("CONFIRM_RESIST_TITLE"), tr("CONFIRM_RESIST"), tr("BTN_CRIME_RESIST"), answer)
			else:
				answer.call(), can_act and why.is_empty())
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


## «Здесь действует закон (…)» under a question when the hero's location keeps the law (v0.7.22.27).
func _law_line(s: GameSession) -> String:
	var loc := GameState.world().location_id(s.room_id)
	if CrimeRules.law(Catalog.data, loc).is_empty():
		return ""
	return "\n\n" + tr("CONFIRM_LAW").format({"place": GameState.world().location(loc).get("name", loc)})
