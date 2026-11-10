class_name SidePanel
extends PanelContainer
## The left column of the game screen: the hero, those who are here and the deterministic buttons the engine builds itself
## (ADR-0009 §4). v0.8.1: where the hero is and the hour go to the strip over the field, the acts of the place, the ways
## out and the deeds to the bar under it.
## v0.7.22.23 (the UI audit С1, И2–И4, П4): a person or a creature is one row — the name talks, «▾» or the right
## button opens the rest of its acts under it; the exits, «Осмотреться» and «Обыскать» stay pinned under the list.

signal menu_requested
signal approach_requested(ref: String, reach: String, act: Callable)  ## v0.8.2: the hero walks up, then the act
signal walk_out_requested(to: String)  ## v0.8.4.2: the exit button walks there
signal touch_requested(ref: String)  ## v0.8.4.2: the hero walks up to a thing of the map, its menu opens
signal wait_requested
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
signal wilds_requested(kind: String)  # v0.7.41
signal job_requested(npc_id: String)  # v0.7.26
signal property_requested(mode: String, npc_id: String)  # v0.7.27
signal bank_requested(npc_id: String)  # v0.7.28
signal shop_requested(mode: String, id: String)  # v0.7.29
signal study_requested(npc_id: String)  # v0.7.30: "" — the hero's own courses
signal bond_requested(npc_id: String)  # v0.7.31
signal contest_requested(npc_id: String)  # v0.7.40
signal family_requested  # v0.7.32
signal heist_requested  # v0.7.33
signal org_requested(org_id: String)  # v0.7.33
signal office_requested(chief: String)  # v0.7.34
signal pet_requested(creature_id: String)  # v0.7.43
signal gear_requested(npc_id: String)  # v0.8.4.40: a follower's «Снаряжение»
signal letter_requested(npc_id: String)  # v0.7.48
signal faith_requested  # v0.7.49
signal arena_requested(site_id: String)  # v0.7.45

## What a mark of the map offers: the buttons of the bar it stands for, by the start of their names (v0.8.2).
const MARK_ACTS := {"forge": ["CraftButton"], "anvil": ["CraftButton"], "bench": ["CraftButton"], "hearth": ["CraftButton"], "altar": ["FaithButton"],
	"stage": ["PerformButton"], "vein": ["Gather_"], "water": ["FillWater", "DrinkButton"], "bed": ["OwnBedButton", "RestButton"], "camp": ["RestButton"]}

var _content: Container
var _scroll: ScrollContainer
var _bar: ActionBar
var _strip: HBoxContainer  # over the field: the place, the hour, the weather
var _exit_list: Container  ## the ways out, under «Выходы ▾» on the strip
var _open := ""  # the row whose acts are open ("npc:<id>", "cr:<id>"), closed when the hero leaves the room
var _open_room := ""
var _near_ref := ""  # the person whose acts are being built: its buttons walk up first


func _ready() -> void:
	theme_type_variation = UiTheme.SIDE
	if owner != null:
		_bar = owner.get_node_or_null("%Bar")
		_strip = owner.get_node_or_null("%Strip")
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	add_child(col)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(_scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 10)
	_scroll.add_child(_content)
	if _bar == null:  # the panel alone
		_bar = ActionBar.new()
		col.add_child(_bar)
	if _strip == null:
		_strip = HBoxContainer.new()
		col.add_child(_strip)
	for spec: Array in [["SheetButton", "BTN_CHARACTER_SHEET", sheet_requested, "character_sheet"], ["MapButton", "BTN_MAP", map_requested, "map"],
			["JournalButton", "BTN_JOURNAL", journal_requested, "journal"], ["GameMenuButton", "BTN_MENU", menu_requested, "pause_menu"]]:
		var b := IconSlot.make(IconRules.button(Catalog.data, spec[0]), tr(spec[1]), 52)  # v0.8.4.43: icons in the corner
		b.name = spec[0]
		b.tooltip_text = Hotkeys.tip(tr(spec[1]), spec[3], SaveManager.keys)  # v0.7.22.27
		b.pressed.connect((spec[2] as Signal).emit)
		_bar.windows.add_child(b)
	EventBus.state_changed.connect(_rebuild)
	EventBus.turn_started.connect(_on_turn)
	EventBus.turn_finished.connect(_on_turn_finished)
	EventBus.backend_state_changed.connect(_on_backend)
	_rebuild()


## The act behind a button of a person or a thing: the hero walks up first (v0.8.2). Without the screen — at once.
func _near(ref: String, reach: String, act: Callable) -> Callable:
	return func() -> void:
		if approach_requested.get_connections().is_empty():
			act.call()
		else:
			approach_requested.emit(ref, reach, act)


## The menu of a person or a creature on the map: its row with all the acts. False — nothing to show.
func menu(box: Container, ref: String) -> bool:
	var s := GameState.session if GameState.has_session() else null
	if s == null:
		return false
	var can_act := not GameState.is_busy() and Backend.is_ready()
	var column := _content
	_content = box
	var id := ref.get_slice(":", 1)
	var ok := false
	if ref.begins_with("npc:") and s.npcs_here(Catalog.data["world"], s.room_id).has(id):
		var n := GameState.world().npc(id)
		var a := s.attitude(id)
		var att := GameSession.attitude_word(Catalog.data, a)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		box.add_child(row)
		_npc_head(row, s, n, id, a, att, SocialRules.refuses(s, Catalog.data, id), can_act)
		_line("%s · %s" % [n.get("role", ""), att], true)
		_npc_acts(s, n, id, can_act)
		ok = true
	elif ref.begins_with("cr:"):
		for cr: Dictionary in CreatureRules.here(s, s.room_id):
			if str(cr["id"]) == id:
				_line(CreatureRules.text(cr, Catalog.data), false)
				_creature_acts(s, cr, can_act)
				ok = true
	elif ref.begins_with("foe:"):
		ok = _foe_menu(s, id, can_act)
	elif ref.begins_with("body:"):
		ok = _body_menu(box, s, id, can_act)
	elif ref.begins_with("station:"):
		ok = _mark_acts(box, ref)
	elif ref.begins_with("door:"):
		ok = _door_menu(box, s, ref.trim_prefix("door:"), can_act)
	elif ref.begins_with("trap:"):
		ok = _trap_menu(box, s, ref.trim_prefix("trap:"), can_act)
	_content = column
	return ok


## A foe seen before the fight (v0.8.4.30, the author's feedback): its name and card, then the blow, a look and the spells
## aimed at it.
func _foe_menu(s: GameSession, id: String, can_act: bool) -> bool:
	for e: Dictionary in GameState.foes_here():
		if EncounterRules.foe_id(e) != id:
			continue
		_line(str(e.get("name", e.get("monster", ""))), false)
		var mx := int(e.get("max_hp", Sheet.template(Catalog.data, e).get("hp", 0)))
		var card := CombatRules.monster_card(s, Catalog.data, e.merged({"hp": int(e.get("hp", mx)), "max_hp": mx}))
		if not card.is_empty():
			_line(card, true)
		var acts := _acts("FoeActs_" + id)
		var word := bool(EncounterRules.lurking(s, s.room_id).get("word", false))
		_flow(acts, tr("BTN_FOE_ATTACK"), _near("foe:" + id, "touch", _try.bind(GameState.encounter_attack)), can_act, "FoeAttack_" + id,
			tr("BTN_FOE_ATTACK_WORD_TIP") if word else "")
		var looked := GameState.inspect_why(id)  # the one knowledge check (v0.8.4.41: anybody's)
		_flow(acts, tr("BTN_FOE_INSPECT"), _try.bind(GameState.inspect.bind(id)), can_act and looked.is_empty(), "FoeInspect_" + id,
			tr("BTN_FOE_INSPECT_TIP") if looked.is_empty() else tr(looked))
		UiParts.card_button(acts, id)
		_spell_acts(acts, id, can_act)
		return true
	return false


## The spells the hero may aim at `target` out of a fight, a button each: cast at once (v0.8.4.30).
func _spell_acts(acts: Container, target: String, can_act: bool) -> void:
	for ch: Dictionary in GameState.spells_at(target):
		_flow(acts, "✦ " + str(ch["name"]), _try.bind(GameState.cast_at.bind(str(ch["id"]), target)), can_act, "CastAt_%s_%s" % [ch["id"], target],
			tr("BTN_CAST_AT_TIP"))


## The body of a person on the map (v0.8.4.4): what can be done with it.
func _body_menu(box: Container, s: GameSession, id: String, can_act: bool) -> bool:
	for body: Dictionary in CrimeRules.bodies_here(s, Catalog.data):
		if str(body["npc_id"]) == id:
			_line(str(body["name"]), false)
			var acts := _acts("BodyActs")
			if not bool(body["searched"]):
				_flow(acts, tr("BTN_CREATURE_SEARCH"), _try.bind(GameState.search_body.bind(id)), can_act, "BodySearch_" + id)
			if CrimeRules.can_hide(s, Catalog.data, id).is_empty():
				_flow(acts, tr("BTN_HIDE_BODY"), _try.bind(GameState.hide_body.bind(id)), can_act, "BodyHide_" + id).tooltip_text = tr("BTN_HIDE_BODY_TIP")
			return acts.get_child_count() > 0 or bool(body["searched"])
	return false


## The ways with a door on the map (v0.8.4.2): where it leads and why it is shut, «Пройти» when it lets through.
func _door_menu(box: Container, s: GameSession, to: String, can_act: bool) -> bool:
	if not WayRules.open_exits(s, Catalog.data["world"], s.room_id).has(to):
		return false
	var why := WayRules.blocked(s, Catalog.data, s.room_id, to)
	_line(str(GameState.world().room(to).get("name", to)), false)
	if not why.is_empty():
		_line(tr(why), true)
	else:
		_flow(_acts("DoorPass"), tr("BTN_PASS"), _leave.bind(to), can_act, "DoorPass_" + to)
	_door_acts(box, to, WayRules.ways(s, Catalog.data, s.room_id, to), can_act)
	return true


## A found trap on the map (v0.8.4.2): disarm it, or go round when it guards a way.
func _trap_menu(box: Container, s: GameSession, id: String, can_act: bool) -> bool:
	var sec := ExplorationRules.found_trap(s, Catalog.data["world"], s.room_id, id)
	if sec.is_empty():
		return false
	var to := str(sec["trap"].get("guards", ""))
	_line(str(sec["text"]), false)
	var acts := _acts("TrapActs")
	var picks := BackgroundRules.has_tool(s.character, "thieves_tools")  # v0.8.4.29.1: grey without the tools, as a lock
	_flow(acts, tr("BTN_TRAP_DISARM"), _trap.bind(to, true, id), can_act and picks, "TrapDisarm_" + id, tr("TRAP_DISARM_TIP") if picks else _no_picks(s))
	if not to.is_empty():
		var room_name := str(GameState.world().room(to).get("name", to))
		_flow(acts, tr("BTN_TRAP_BYPASS").format({"room": room_name}), _trap.bind(to, false, id), can_act, "TrapBypass_" + id, tr("TRAP_BYPASS_TIP"))
	return box.get_child_count() > 0


## The hero walks to the way out (v0.8.4.2); a screen-less panel goes at once.
func _leave(to: String) -> void:
	if walk_out_requested.get_connections().is_empty():
		GameState.go(to)
	else:
		walk_out_requested.emit(to)


## The hero's quest offers refresh as the hero walks: a giver is in reach or not.
func refresh() -> void:
	_rebuild()


## True when a mark offers something now.
func mark_has_acts(mark: String) -> bool:
	return not _mark_buttons(mark).is_empty()


func _mark_buttons(mark: String) -> Array[BaseButton]:
	var out: Array[BaseButton] = []
	for start: String in MARK_ACTS.get(mark, []):
		for b: Node in _bar.find_children(start + "*", "BaseButton", true, false):
			if not b.is_queued_for_deletion():
				out.append(b as BaseButton)
	return out


## A button of the bar stands in the menu by the mark: the same act after the walk.
func _mark_acts(box: Container, ref: String) -> bool:
	var buttons := _mark_buttons(ref.get_slice(":", 1))
	for b: BaseButton in buttons:
		var copy := Button.new()
		copy.text = (b as Button).text
		copy.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		copy.disabled = b.disabled
		copy.tooltip_text = b.tooltip_text
		copy.pressed.connect(_near(ref, "touch", b.pressed.emit))
		box.add_child(copy)
	return not buttons.is_empty()


## A thing of the map: its own window, a body or a plain thing — the place's.
func use_thing(ref: String) -> void:
	var s := GameState.session
	var id := ref.get_slice(":", 1)
	if ref.begins_with("prop:"):
		var p := PropRules.find(s, s.room_id, id)
		if QuestGen.is_board(Catalog.data, p):
			board_requested.emit(id)
			return
		if not str(p.get("container", "")).is_empty():
			container_requested.emit(id)
			return
	place_requested.emit()


func _on_turn(_id: String) -> void:
	_rebuild()


func _on_turn_finished(_id: String, _ok: bool) -> void:
	_rebuild()


func _on_backend(_s: int, _d: String) -> void:
	_rebuild()


func _rebuild() -> void:
	# Detach before freeing: a queued node keeps its name, and the rebuilt button would get renamed.
	for box: Container in [_content, _strip]:
		for c in box.get_children():
			box.remove_child(c)
			c.queue_free()
	_bar.clear()
	if not GameState.has_session():
		return
	var s := GameState.session
	if s.room_id != _open_room:
		_open = ""
		_open_room = s.room_id
	if not _open.is_empty():
		_show_open.call_deferred()
	var c := s.character
	var world := GameState.world()
	var can_act := Backend.is_ready() and not GameState.is_busy()

	_heading(str(c.get("name", "")))
	var hp := _line(tr("SIDE_HERO_LINE").format({"race": c.get("race_name", ""), "class": c.get("class_name", ""), "level": int(c.get("level", 1)),
		"hp": c["hp"], "max": c["max_hp"], "ac": c["ac"]}) + ((" · +%d врем." % int(c["temp_hp"])) if int(c.get("temp_hp", 0)) > 0 else ""), false)  # big test #19 (v0.7.22.3)
	hp.name = "HeroHp"
	if int(c["hp"]) * 2 <= int(c["max_hp"]):
		hp.add_theme_color_override("font_color", UiTheme.BAD)
	_hp_bar(c)
	var next_xp := LevelUp.xp_for(Catalog.data, int(c.get("level", 1)) + 1)
	var xp := tr("SIDE_HERO_XP").format({"xp": int(c.get("xp", 0)), "next": next_xp}) if int(c.get("level", 1)) < LevelUp.max_level(c, Catalog.data) else ""
	_line(" · ".join([Money.format(Ledger.balance(s)), xp].filter(func(x: String) -> bool: return not x.is_empty())), true).name = "HeroMoney"
	_festival_line(s, world)
	if NeedRules.on(s):
		_needs(s, can_act)
	var chips := EffectChips.new()  # what is on the hero, under the hero (v0.8.1)
	_content.add_child(chips)
	chips.refresh()
	var column := _content
	_content = _bar.section(ActionBar.DEEDS)
	_craft_row(s, can_act)
	_work_row(s, can_act)
	_study_row(s, can_act)
	_family_row(s, can_act)
	_underworld_row(s, can_act)
	_office_row(s, can_act)
	_faith_row(s, can_act)
	_property_row(s)
	_content = column
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
	_strip_lines(s, world)
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
		var called := AllyRules.called(s)
		if not called.is_empty():  # v0.7.22.22: the creatures a spell called
			_subheading("SIDE_WITH_YOU")
			var texts := AllyRules.summon_lines(s, Catalog.data)
			for i in called.size():
				var srow := HBoxContainer.new()
				srow.add_theme_constant_override("separation", 6)
				_content.add_child(srow)
				var sl := Label.new()
				sl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
				sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				sl.text = texts[i]
				srow.add_child(sl)
				var sid := str(called[i]["id"])
				var db := _small(srow, tr("BTN_SUMMON_DISMISS"), _try.bind(GameState.dismiss_summon.bind(sid)), can_act)
				db.name = "Dismiss_" + sid
		for away: String in SceneRules.absent(s, Catalog.data["world"], s.room_id):  # v0.7.14.2: their hours
			_line(away, true)
		for body: Dictionary in CrimeRules.bodies_here(s, Catalog.data):  # v0.7.14: the body of a killed NPC
			if bool(body["searched"]):
				_line(str(body["name"]), true)
				continue
			var bid := str(body["npc_id"])
			var bb := _button(tr("BTN_SEARCH_BODY").format({"name": body["name"]}), _try.bind(GameState.search_body.bind(bid)), can_act)
			bb.name = "Body_" + bid
		var here := CreatureRules.here(s, s.room_id)  # v0.7.22.11: the foes a fight left here
		var beasts := here.filter(func(cr: Dictionary) -> bool: return str(cr["state"]) == PropertyRules.TAME)
		var beaten := here.filter(func(cr: Dictionary) -> bool: return not str(cr["state"]) in [PropertyRules.TAME, PetRules.WILD])
		var wild := here.filter(func(cr: Dictionary) -> bool: return str(cr["state"]) == PetRules.WILD)
		if not beaten.is_empty():
			_subheading("SIDE_CREATURES")
		for cr: Dictionary in beaten:
			_creature_row(s, cr, can_act)
		if not wild.is_empty():  # v0.7.43: wild beasts to tame
			_subheading("SIDE_WILD")
		for cr: Dictionary in wild:
			_creature_row(s, cr, can_act)
		if not beasts.is_empty():  # v0.7.27: the hero's own animals
			_subheading("SIDE_ANIMALS")
		for cr: Dictionary in beasts:
			_creature_row(s, cr, can_act)
		for qid: String in XpRules.quests_here(s, Catalog.data["world"]):
			var q: Dictionary = XpRules.quests(Catalog.data["world"])[qid]
			var qb := _button(tr("BTN_QUEST").format({"action": q["action"]}), _try.bind(GameState.complete_quest.bind(qid)), can_act)
			qb.name = "Quest_" + qid
			qb.tooltip_text = str(q["title"])
		_quest_buttons(s, can_act, "")
		for ch: Dictionary in QuestRules.choices_here(s, Catalog.data["world"]):
			var qid2 := str(ch["quest_id"])
			var cid := str(ch["choice_id"])
			var cb := _button(tr("BTN_QUEST").format({"action": ch["action"]}), _try.bind(GameState.quest_choose.bind(qid2, cid)), can_act)
			cb.name = "QuestChoice_%s_%s" % [qid2, cid]
			cb.theme_type_variation = UiTheme.ACCENT_BUTTON
		# «Взаимодействие с местом» (v0.7.22.7, big test #17): every thing of the room in its own window — take one,
		# open, look closer, «Забрать всё».
		PropRules.ensure(s, Catalog.data, s.room_id)  # the pack's fixed things, the trader's wares (v0.7.22.8)
		_content = _bar.section(ActionBar.PLACE)
		var n_things := PropRules.room_props(s, s.room_id).size() + CrimeRules.bodies_here(s, Catalog.data).size()
		var pb := IconSlot.make(IconRules.button(Catalog.data, "PlaceButton"), tr("BTN_PLACE").format({"n": n_things}), ActionBar.CELL)
		pb.name = "PlaceButton"
		pb.badge = str(n_things) if n_things > 0 else ""
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
			var lute := BackgroundRules.tool_with(c, Catalog.data, "perform")  # v0.8.4.26.4: «Сыграть на лютне»
			var pf := _button(tr("BTN_PERFORM") if lute.is_empty() else tr("BTN_PERFORM_ON").format({"tool": ItemRules.display_name(Catalog.data["items"], s.items, lute).to_lower()}), do_perform, can_act)
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
		_hotbar_pins(s, can_act)
		# The rests and the wait sit at the hotbar's right (v0.8.4.43, as in BG3).
		_content = _bar.section(ActionBar.REST)
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
		var wait := IconSlot.make(IconRules.button(Catalog.data, "WaitButton"), tr("BTN_WAIT"), ActionBar.CELL)
		wait.name = "WaitButton"
		wait.disabled = not can_act
		var pop := PopupMenu.new()  # the times to wait till, under the cell
		pop.name = "WaitTimes"
		wait.add_child(pop)
		wait.pressed.connect(func() -> void: pop.popup(Rect2i(Vector2i(wait.get_screen_position()) + Vector2i(0, -8 - pop.get_contents_minimum_size().y as int), Vector2i.ZERO)))
		var targets: Array[String] = ["hour", "morning", "day", "evening", "night"]
		for i in targets.size():
			var mins := TimeRules.minutes_until(s, Catalog.data, targets[i])
			pop.add_item(tr("WAIT_" + targets[i].to_upper()).format({"clock": TimeRules.clock_after(s, mins)}), i)
		pop.add_item(tr("WAIT_CUSTOM"), targets.size())
		pop.id_pressed.connect(func(id: int) -> void:
			if id >= targets.size():
				wait_requested.emit()
				return
			var err := GameState.wait(targets[id])
			if not err.is_empty():
				EventBus.message.emit(tr(err)))
		_content.add_child(wait)
		var short := _button(tr("BTN_SHORT_REST"), short_rest_requested.emit, not GameState.is_busy())
		short.name = "ShortRestButton"
		var why := ExplorationRules.can_short_rest(s, Catalog.data)
		short.disabled = GameState.is_busy() or not why.is_empty()
		short.tooltip_text = tr(why) if not why.is_empty() else ""
		_content = column
	else:
		_content = _bar.talk_acts
		_quest_buttons(s, can_act, s.npc_id)  # take the quest from, or hand the thing to, the one you talk to (v0.7.2)
		_npc_acts(s, world.npc(s.npc_id), s.npc_id, can_act)
		_content = column
	_bar.set_talk(s.in_conversation())
	_bar.tidy()
	var ways_b := _strip.get_node_or_null("ExitsButton") as Button
	if ways_b != null:
		ways_b.text = tr("SIDE_EXITS_N").format({"n": _exit_list.get_child_count()})
		for b: Node in _exit_list.get_children():
			(b as Button).alignment = HORIZONTAL_ALIGNMENT_LEFT
			(b as Button).custom_minimum_size = Vector2(300, 34)
		(_exit_list.get_parent() as Control).custom_minimum_size = Vector2(330, mini(_exit_list.get_child_count() * 38, 420))


## The hero's life as a bar under the line of numbers.
func _hp_bar(c: Dictionary) -> void:
	var bar := UiParts.hp_line(int(c["hp"]), int(c["max_hp"]), int(c.get("temp_hp", 0)), 10.0, 2)  # temporary hits in blue (v0.8.4.30)
	bar.name = "HeroBar"
	_content.add_child(bar)


## Out of a fight the hotbar's class and items (v0.8.4.43, as in BG3): the ready spells, the uses of features and the
## things at hand — a press pins it to the next words to the master, as the ✦ menu does (`GameState.attach_choices`).
func _hotbar_pins(s: GameSession, can_act: bool) -> void:
	var c := s.character
	for ch: Dictionary in GameState.attach_choices():
		var kind := str(ch["kind"])
		if not kind in ["spell", "feature", "item"]:
			continue
		var id := str(ch["id"])
		if kind == "item" and not ItemRules.at_hand(c, Catalog.data, s.items).has(id):
			continue
		var box := _bar.section(ActionBar.ITEMS if kind == "item" else ActionBar.CLASS)
		var ref: String = str({"spell": "spells/", "feature": "features/", "item": "items/"}[kind]) + id
		var cell := IconSlot.make(ref, str(ch["name"]), ActionBar.CELL)
		cell.name = "Pin_%s_%s" % [kind, id]
		cell.disabled = not can_act or bool(ch["off"])
		cell.toggle_mode = true
		cell.button_pressed = str(GameState.attached.get("kind", "")) == kind and str(GameState.attached.get("id", "")) == id
		var slots: Array = ch["slots"]
		cell.pressed.connect(func() -> void:
			if cell.button_pressed:
				GameState.attach(kind, id, int(slots[0]) if not slots.is_empty() else 0)
			else:
				GameState.detach())
		var count := RegEx.create_from_string("\\((\\d+/\\d+)\\)|×(\\d+)").search(str(ch["name"]))
		if count != null:
			cell.badge = count.get_string(1) if count.get_string(1) != "" else "×" + count.get_string(2)
		match kind:
			"spell":
				cell.tip_title = str(Catalog.data["spells"][id]["name"])
				cell.tip_body = DetailsPanel.spell_text(Catalog.data, id, int(slots[0]) if not slots.is_empty() else 0)
			"feature":
				cell.tip_body = DetailsPanel.feature_text(Catalog.data, id)
			"item":
				cell.tip_body = DetailsPanel.item_text(c, Catalog.data, s.items, id)
		cell.tooltip_text = str(ch["name"]) + "\n" + tr("BAR_PIN_TIP")
		box.add_child(cell)


## The strip over the field: the place path, the date and hour, the weather; one line, the long path cut by «…».
func _strip_lines(s: GameSession, world: WorldView) -> void:
	var column := _content
	_content = _strip
	var path := _line(world.place_path(s.room_id), false)  # v0.7.22.24: location › site › room
	path.name = "PlacePath"
	path.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	path.clip_text = true
	path.mouse_filter = Control.MOUSE_FILTER_STOP
	path.tooltip_text = path.text
	_line(tr("SIDE_HERO_TIME").format({"day": CalendarRules.text(world.world, s.day), "part": TimeRules.part_name(s, Catalog.data),
		"clock": TimeRules.clock(s)}), true).name = "HeroTime"
	_weather_line(s)
	for l: Node in _strip.get_children():
		(l as Label).autowrap_mode = TextServer.AUTOWRAP_OFF
	path.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_content = column


## A person of the scene in one row (v0.7.22.23): the full name talks, «Торговать» for a trader, «▾» (or the right
## button on the name) opens the rest under it — pockets, a follower's acts, attack.
func _npc_row(s: GameSession, world: WorldView, id: String, can_act: bool) -> void:
	var n := world.npc(id)
	var key := "npc:" + id
	var refuses := SocialRules.refuses(s, Catalog.data, id)  # v0.7.15.3
	var a := s.attitude(id)
	var att := GameSession.attitude_word(Catalog.data, a)
	if not _being_row(key, "More_" + id, _npc_head.bind(s, n, id, a, att, refuses, can_act)):
		return
	var bw := BondRules.word(s.character, Catalog.data, id)  # v0.7.31
	var role := _line("%s · %s%s" % [n.get("role", ""), att, (" · " + bw) if not bw.is_empty() else ""], true)
	role.name = "Role_" + id
	_npc_acts(s, n, id, can_act)


## What can be done with a person, under its row or on the bar while talking to it.
func _npc_acts(s: GameSession, n: Dictionary, id: String, can_act: bool) -> void:
	var acts := _acts("Acts_" + id)
	var groups := {}  # v0.8.4.31: the acts in nested lists — deals, talk, life, spells
	_near_ref = "npc:" + id
	UiParts.card_button(acts, id)  # v0.8.4.41: its card, as in BG3
	_flow(acts, tr("BTN_POCKETS_SHORT"), _near("npc:" + id, "touch", pockets_requested.emit.bind(id)), can_act and TheftRules.can_steal(s, Catalog.data, id).is_empty(), "Pockets_" + id, tr("BTN_POCKETS").format({"name": n.get("name", id)}))
	if not JobRules.of(s, Catalog.data, id).is_empty():  # v0.7.26
		_flow(_group(groups, "deals", id), tr("BTN_JOB"), job_requested.emit.bind(id), can_act, "Jobs_" + id, tr("BTN_JOB_TIP").format({"name": n.get("name", id)}))
	var undeeded := PropertyRules.is_registry(Catalog.data, id) and PropertyRules.state(s.character).values().any(func(p: Dictionary) -> bool: return not bool(p.get("deed", false)))
	if not PropertyRules.of_seller(s, Catalog.data, id).is_empty() or undeeded:  # v0.7.27
		_flow(_group(groups, "deals", id), tr("BTN_PROPERTY"), property_requested.emit.bind("seller", id), can_act, "PropertySale_" + id, tr("BTN_PROPERTY_SALE_TIP").format({"name": n.get("name", id)}))
	if PropertyRules.is_registry(Catalog.data, id) and ShopRules.on(Catalog.data):  # v0.7.29: the charter and the stalls
		_flow(_group(groups, "deals", id), tr("BTN_SHOP_REGISTRY"), shop_requested.emit.bind("registry", id), can_act, "ShopRegistry_" + id, tr("BTN_SHOP_REGISTRY_TIP"))
	if ShopRules.is_supplier(s, Catalog.data, id):
		_flow(_group(groups, "deals", id), tr("BTN_WHOLESALE"), shop_requested.emit.bind("supplier", id), can_act, "Wholesale_" + id, tr("BTN_WHOLESALE_TIP").format({"name": n.get("name", id)}))
	if StudyRules.is_teacher(s, Catalog.data, id):  # v0.7.30
		_flow(_group(groups, "deals", id), tr("BTN_STUDY"), study_requested.emit.bind(id), can_act, "Study_" + id, tr("BTN_STUDY_TIP").format({"name": n.get("name", id)}))
	if not SiteRules.closed_to_hero(s, Catalog.data, id).is_empty():  # v0.7.39.2: the owner's leave
		var pw := SiteRules.ask_why(s, Catalog.data, id)
		var pb := _flow(_group(groups, "talk", id), tr("BTN_PERMIT"), _try.bind(GameState.permit_ask.bind(id)), can_act and pw.is_empty())
		pb.name = "Permit_" + id
		pb.tooltip_text = tr(pw) if not pw.is_empty() else tr("BTN_PERMIT_TIP").format({"dc": SiteRules.ask_dc(s, Catalog.data, id),
			"chance": SiteRules.ask_chance(s, Catalog.data, id)})
	if not FamilyRules.engaged(s).is_empty() and not FamilyRules.officiant(s, Catalog.data, id).is_empty():  # v0.7.32
		var why := FamilyRules.wedding_why(s, Catalog.data, id)
		_flow(_group(groups, "life", id), tr("BTN_WEDDING"), _try.bind(GameState.family_act.bind("wedding", id)), can_act and why.is_empty(), "Wedding_" + id, tr(why) if not why.is_empty() else tr("BTN_WEDDING_TIP").format({"money": Money.format(FamilyRules.fee(Catalog.data, FamilyRules.officiant(s, Catalog.data, id)))}))
	if OfficeRules.on(Catalog.data) and not OfficeRules.of_chief(Catalog.data, id).is_empty():  # v0.7.34
		_flow(_group(groups, "deals", id), tr("BTN_OFFICES"), office_requested.emit.bind(id), can_act, "Office_" + id, tr("BTN_OFFICES_TIP"))
	if Catalog.data["rules"].has("underworld"):  # v0.7.33
		for org: String in OrgRules.of_head(s, Catalog.data, id):
			_flow(_group(groups, "deals", id), str(OrgRules.word(s, Catalog.data, org)["nom"]).capitalize(), org_requested.emit.bind(org), can_act, "Org_" + id, tr("BTN_ORG_HEAD_TIP").format({"org": OrgRules.org_name(s, Catalog.data, org)}))
		var rw := OrgRules.recruit_why(s, Catalog.data, id)
		if not OrgRules.own(s, Catalog.data).is_empty() and not rw in ["ORG_NOT_FOR_HIM", "ORG_MEMBER"]:
			_flow(_group(groups, "life", id), tr("BTN_RECRUIT"), _try.bind(GameState.org_act.bind("recruit", id)), can_act and rw.is_empty(), "Recruit_" + id, tr(rw).format({"at": int(OrgRules.cfg(Catalog.data)["recruit_bond"])}) if not rw.is_empty() else tr("BTN_RECRUIT_TIP"))
	if Catalog.data["rules"].has("contests"):  # v0.7.40
		var playing := str(ContestRules.state(s).get("npc", "")) == id
		var cw := "" if playing else ContestRules.why_not(s, Catalog.data, id)
		_flow(_group(groups, "talk", id), tr("BTN_CONTEST"), contest_requested.emit.bind(id), can_act and cw.is_empty(), "Contest_" + id, cw if not cw.is_empty() else tr("BTN_CONTEST_TIP").format({"name": n.get("name", id)}))
	if RumorRules.on(Catalog.data):  # v0.7.47: what they say around here
		var rw := RumorRules.ask_why(s, Catalog.data, id)
		_flow(_group(groups, "talk", id), tr("BTN_RUMORS"), _try.bind(GameState.rumor_ask.bind(id)), can_act and rw.is_empty(), "Rumors_" + id, tr(rw) if not rw.is_empty() else tr("BTN_RUMORS_TIP").format({"name": n.get("name", id)}))
	if not PrepareRules.quest_of(s, id).is_empty():  # v0.8.4.25: a quest it readied ahead, given when asked
		_flow(_group(groups, "talk", id), tr("BTN_ASK_WORK"), _try.bind(GameState.ask_work.bind(id)), can_act, "AskWork_" + id, tr("BTN_ASK_WORK_TIP").format({"name": n.get("name", id)}))
	if not LetterRules.ways_of(Catalog.data, id).is_empty():  # v0.7.48: a person with a post sends letters
		_flow(_group(groups, "deals", id), tr("BTN_LETTER"), letter_requested.emit.bind(id), can_act, "Letter_" + id, tr("BTN_LETTER_TIP").format({"name": n.get("name", id)}))
	_service_acts(s, _group(groups, "services", id) if not ServiceRules.ids_of(Catalog.data, id).is_empty() else null, id, can_act)
	_spell_acts(_group(groups, "spells", id), id, can_act)  # v0.8.4.30: a spell aimed at it, as in BG3
	var arena_site := ArenaRules.of_manager(Catalog.data, id)  # v0.7.45
	if not arena_site.is_empty():
		_flow(_group(groups, "deals", id), tr("BTN_ARENA"), arena_requested.emit.bind(arena_site), can_act, "Arena_" + id, tr("BTN_ARENA_TIP").format({"name": ArenaRules.site_name(Catalog.data, arena_site)}))
	var bo := _flow(_group(groups, "life", id), tr("BTN_BOND"), bond_requested.emit.bind(id), can_act)  # v0.7.31
	bo.name = "Bond_" + id
	bo.tooltip_text = tr("BTN_BOND_TIP").format({"name": n.get("name", id)})
	if BankRules.is_bank(s, Catalog.data, id):  # v0.7.28
		_flow(_group(groups, "deals", id), tr("BTN_BANK"), bank_requested.emit.bind(id), can_act, "Bank_" + id, tr("BTN_BANK_TIP").format({"name": n.get("name", id)}))
	if not PropertyRules.animals_of(Catalog.data, id).is_empty():
		_flow(_group(groups, "deals", id), tr("BTN_ANIMALS"), property_requested.emit.bind("animals", id), can_act, "Animals_" + id)
	var follow: Array = []  # v0.7.22.22 (#25): a follower by the buttons, as the prisoners
	if Being.follows(s, id):
		follow = [["stay", "BTN_FOLLOWER_STAY"], ["let_go", "BTN_FOLLOWER_LET_GO"]]
	elif str(Being.view(s, id).get("at", "")) == s.room_id:
		follow = [["lead", "BTN_FOLLOWER_LEAD"], ["let_go", "BTN_FOLLOWER_LET_GO"]]
	if Being.follows(s, id):  # v0.8.4.40: what it wears, by the hero's rules
		_flow(_group(groups, "life", id), tr("BTN_GEAR"), gear_requested.emit.bind(id), can_act, "Gear_" + id, tr("BTN_GEAR_TIP"))
	if Being.follows(s, id) and GrowthRules.ready(s, Catalog.data, id):  # v0.8.4.42.2: its level by the player, as the hero's — in the row itself, seen at once
		_flow(acts, tr("BTN_GROW"), _try.bind(GameState.follower_grow.bind(id)), can_act, "Grow_" + id, tr("BTN_GROW_TIP").format({"name": n.get("name", id)}))
	for fa: Array in follow:
		var what: String = fa[0]
		var fb := _flow(_group(groups, "life", id), tr(fa[1]), _try.bind(GameState.follower_act.bind(id, what)), can_act, "Follower_%s_%s" % [what, id])
		if tr(fa[1] + "_TIP") != fa[1] + "_TIP":
			fb.tooltip_text = tr(fa[1] + "_TIP")
	var who := str(n.get("name", id))
	var at := _flow(acts, tr("BTN_ATTACK_SHORT"), func() -> void:
		ConfirmBox.ask(self, tr("CONFIRM_ATTACK_TITLE").format({"name": who}), tr("CONFIRM_ATTACK") + _law_line(s), tr("BTN_ATTACK_SHORT"), _try.bind(GameState.attack_npc.bind(id))), can_act)
	at.name = "Attack_" + id  # the fight at once, without the master: last and red, apart from the peaceful acts
	at.tooltip_text = tr("BTN_ATTACK_NPC").format({"name": n.get("name", id)})
	at.add_theme_color_override("font_color", UiTheme.BAD)
	_fold(acts, groups, id)
	_near_ref = ""


## The groups of a person's acts (v0.8.4.31, the author's feedback): a header «Дела ▸» opens its list under the row; a group of
## one act shows it in the row itself.
const ACT_GROUPS: Array[String] = ["talk", "deals", "services", "life", "spells"]


## The services of any person (v0.8.4.35): a button each, a mark on a thing one per thing it fits when there are several.
func _service_acts(s: GameSession, box: HFlowContainer, id: String, can_act: bool) -> void:
	if box == null:
		return
	for sv: Dictionary in ServiceRules.of(s, Catalog.data, id):
		var sid := str(sv["id"])
		var on: Array = sv["targets"] if str(sv["op"]) == "enchant" and (sv["targets"] as Array).size() > 1 else [""]
		for item: Variant in on:
			var name := str(sv["name"]) if str(item).is_empty() else "%s: %s" % [sv["name"], ItemRules.display_name(Catalog.data["items"], s.items, str(item))]
			var why := str(sv["why"])
			_flow(box, tr("SERVICE_BUTTON").format({"name": name, "cost": Money.format(int(sv["cost_cp"]))}),
				_try.bind(GameState.service.bind(id, sid, str(item))), can_act and why.is_empty(),
				"Service_%s_%s%s" % [sid, id, "" if str(item).is_empty() else "_" + str(item)], tr(why) if not why.is_empty() else "")


func _group(groups: Dictionary, key: String, id: String) -> HFlowContainer:
	if not groups.has(key):
		var box := HFlowContainer.new()
		box.name = "Group_%s_%s" % [key, id]
		box.add_theme_constant_override("h_separation", 6)
		box.add_theme_constant_override("v_separation", 6)
		groups[key] = box
	return groups[key]


func _fold(acts: HFlowContainer, groups: Dictionary, id: String) -> void:
	var attack := acts.get_child(acts.get_child_count() - 1)  # the attack stays last and apart
	var at := acts.get_child_count() - 1
	for key: String in ACT_GROUPS:
		if not groups.has(key):
			continue
		var box: HFlowContainer = groups[key]
		if box.get_child_count() == 1:
			var only := box.get_child(0)
			box.remove_child(only)
			acts.add_child(only)
			acts.move_child(only, at)
			at += 1
			box.queue_free()
			continue
		var head := Button.new()
		head.name = "Fold_%s_%s" % [key, id]
		head.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		head.toggle_mode = true
		var title := tr("ACT_GROUP_" + key.to_upper())
		head.text = "%s ▸" % title
		head.tooltip_text = tr("ACT_GROUP_TIP")
		box.visible = false
		head.toggled.connect(func(on: bool) -> void:
			box.visible = on
			head.text = "%s %s" % [title, "▾" if on else "▸"])
		acts.add_child(head)
		acts.move_child(head, at)
		at += 1
		_content.add_child(box)
	acts.move_child(attack, acts.get_child_count() - 1)


func _npc_head(row: HBoxContainer, s: GameSession, n: Dictionary, id: String, a: int, att: String, refuses: bool, can_act: bool) -> Control:
	var b := _row_button(row, str(n.get("name", id)), _near("npc:" + id, "talk", GameState.talk_to.bind(id, false)), can_act and not refuses)
	b.name = "Talk_" + id
	b.tooltip_text = tr("TALK_REFUSED") if refuses else tr("SIDE_TALK_TIP").format({"name": n.get("name", id), "role": n.get("role", ""), "attitude": att})
	if a <= -2:
		b.add_theme_color_override("font_color", UiTheme.BAD)
	elif a >= 2:
		b.add_theme_color_override("font_color", UiTheme.OK)
	if bool(n.get("trader", false)):
		var closed := TimeRules.shops_closed(s, Catalog.data) or TheftRules.shop_closed_for(s, id, Catalog.data) or refuses
		var tb := _small(row, tr("BTN_TRADE_SHORT"), _near("npc:" + id, "touch", GameState.talk_to.bind(id, true)), can_act and not closed)
		tb.name = "Trade_" + id
		tb.size_flags_horizontal = Control.SIZE_SHRINK_END
		tb.tooltip_text = tr("SHOP_CLOSED_WANTED" if CrimeRules.shunned_by(s, Catalog.data, id) else "TALK_REFUSED" if refuses else
			"SHOP_CLOSED_FOR_YOU" if TheftRules.shop_closed_for(s, id) else "SHOP_CLOSED") if closed else tr("BTN_TRADE_WITH").format({"name": n.get("name", id)})
	return b


## A creature a fight left (v0.7.22.11) in one row: its state, «▾» (or the right button) opens its acts.
func _creature_row(s: GameSession, cr: Dictionary, can_act: bool) -> void:
	var cid := str(cr["id"])
	if not _being_row("cr:" + cid, "CreatureMore_" + cid, _creature_head.bind(s, cr)):
		return
	_creature_acts(s, cr, can_act)


func _creature_acts(s: GameSession, cr: Dictionary, can_act: bool) -> void:
	var cid := str(cr["id"])
	if str(cr["state"]) == PropertyRules.TAME:  # v0.7.27: an own beast goes along or stays, or is let go
		_animal_acts(s, cr, can_act)
		return
	var acts := _acts("CreatureActs_" + cid)
	UiParts.card_button(acts, cid)  # v0.8.4.41
	for sp: Array in CreatureRules.acts(s, Catalog.data, cr):  # what `can` allows, no list of the panel's own (v0.8.4.29.6)
		var what: String = sp[0]
		var run := func() -> void:
			if what == "tame":
				pet_requested.emit(cid)
				return
			var err := GameState.creature_act(cid, what)
			if not err.is_empty():
				EventBus.message.emit(tr(err))
			elif what == "search" and CreatureRules.lootable(cr):
				container_requested.emit(CreatureRules.BOX + cid)
		var cr_name := str(cr.get("name", cid))
		var cb := _flow(acts, tr(sp[1]), _near("cr:" + cid, "touch", func() -> void:
			if what == "finish":  # v0.7.22.27: a kill is not undone
				ConfirmBox.ask(self, tr("CONFIRM_FINISH_TITLE").format({"name": cr_name}), tr("CONFIRM_FINISH") + _law_line(s), tr(sp[1]), run)
			else:
				run.call()), can_act)
		cb.name = "Creature_%s_%s" % [what, cid]
		if what == "hand_over":
			cb.tooltip_text = tr("CREATURE_HAND_OVER_TIP")
		if what in ["attack", "finish"]:
			cb.add_theme_color_override("font_color", UiTheme.BAD)


func _creature_head(row: HBoxContainer, s: GameSession, cr: Dictionary) -> Control:
	var cid := str(cr["id"])
	var l := Label.new()
	l.name = "CreatureLine_" + cid
	l.text = CreatureRules.text(cr, Catalog.data)
	if bool(cr.get("pet", false)) and int(cr.get("hungry", 0)) > 0:
		l.text += " · " + tr("PET_HUNGRY_SHORT")  # v0.7.43
	if str(cr["state"]) == PropertyRules.TAME and MountRules.on(Catalog.data) and not MountRules.load_text(s, Catalog.data, cr).is_empty():
		l.text += " (%s)" % MountRules.load_text(s, Catalog.data, cr)  # v0.7.42: its pack, its cart
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.mouse_filter = Control.MOUSE_FILTER_STOP
	row.add_child(l)
	return l


## The pinned part under the list (v0.7.22.23, the UI audit С1): sneaking, «Осмотреться» and «Обыскать» side by side,
## the exits one to a row in the small font — never under the scroll.
func _exits(s: GameSession, world: WorldView, can_act: bool) -> void:
	var place := _bar.section(ActionBar.PLACE)
	var sneak := IconSlot.make(IconRules.button(Catalog.data, "SneakToggle"), tr("BTN_SNEAK"), ActionBar.CELL)  # a switch as in BG3
	sneak.name = "SneakToggle"
	sneak.toggle_mode = true
	sneak.tooltip_text = tr("BTN_SNEAK_TIP")
	sneak.button_pressed = s.sneaking
	sneak.disabled = not can_act or s.sneak_noticed == s.room_id
	if s.sneak_noticed == s.room_id:
		sneak.tooltip_text = tr("SNEAK_NOTICED")
	sneak.toggled.connect(func(on: bool) -> void:
		var err := GameState.set_sneaking(on)
		if not err.is_empty():
			EventBus.message.emit(tr(err)))
	place.add_child(sneak)
	if s.sneaking and EncounterRules.sighted(s, s.room_id):  # the hero stands a round out, those who watch turn (v0.8.3)
		var wait := _row_button(place, tr("BTN_SNEAK_WAIT"), GameState.sneak_round, can_act)
		wait.name = "SneakWait"
		wait.tooltip_text = tr("BTN_SNEAK_WAIT_TIP")
	for spec: Array in [["LookButton", "BTN_LOOK", "perception"], ["SearchButton", "BTN_SEARCH", "investigation"]]:
		var skill: String = spec[2]
		var lb := _row_button(place, tr(spec[1]), _try.bind(GameState.search_room.bind(skill)), can_act)
		lb.name = spec[0]
		lb.alignment = HORIZONTAL_ALIGNMENT_CENTER
		lb.tooltip_text = tr(spec[1] + "_TIP")
	# The ways out (v0.8.4.43): on the map, and as a list under «Выходы ▾» on the strip over it — not on the hotbar.
	var ways := Button.new()
	ways.name = "ExitsButton"
	ways.flat = true
	ways.focus_mode = Control.FOCUS_NONE
	ways.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	ways.add_theme_color_override("font_color", UiTheme.ACCENT)
	_strip.add_child(ways)
	var pop := PopupPanel.new()
	pop.name = "ExitsPopup"
	ways.add_child(pop)
	var scroll := ScrollContainer.new()  # many ways scroll inside the list, it never runs off the screen
	scroll.name = "ExitsScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pop.add_child(scroll)
	_exit_list = VBoxContainer.new()
	_exit_list.name = "ExitsList"
	_exit_list.custom_minimum_size = Vector2(320, 0)
	scroll.add_child(_exit_list)
	ways.pressed.connect(func() -> void:
		pop.popup(Rect2i(Vector2i(ways.get_screen_position()) + Vector2i(0, int(ways.size.y)), Vector2i.ZERO)))
	var trapped := {}
	for ft: Dictionary in ExplorationRules.found_traps(s, Catalog.data["world"], s.room_id):
		trapped[ft["to"]] = ft["secret"]
	var shut := CrimeRules.held(s) or EncounterRules.captive(s)
	for e: String in WayRules.open_exits(s, Catalog.data["world"], s.room_id):
		var room_name := str(world.room(e).get("name", e))
		var line := _exit_list
		if trapped.has(e):  # the trap's acts are on the map: its button walks up to it
			var by := _exit_button(line, "→ " + room_name + tr("EXIT_TRAPPED"), touch_requested.emit.bind("trap:" + str(trapped[e]["id"])), can_act and not shut)
			by.name = "Exit_" + e
			by.tooltip_text = str(trapped[e]["text"])
			continue
		var private := not world.is_public(e)  # v0.7.22.24: the player knows before the step
		var why := WayRules.blocked(s, Catalog.data, s.room_id, e)
		var b := _exit_button(line, "→ " + room_name + (tr("EXIT_PRIVATE") if private else "") + WayRules.label(s, Catalog.data, s.room_id, e),
			_leave.bind(e), can_act and not shut)
		b.name = "Exit_" + e
		b.tooltip_text = tr("CRIME_HELD") if CrimeRules.held(s) else room_name
		if not why.is_empty():
			b.tooltip_text = "%s\n%s" % [room_name, tr(why)]
		var owner := str(world.site_of(e).get("owner", ""))
		if private and not CrimeRules.held(s) and not owner.is_empty():
			b.tooltip_text = "%s\n%s" % [room_name, tr("EXIT_PRIVATE_WELCOME" if SiteRules.unwelcome(s, Catalog.data, e).is_empty() else
				"EXIT_PRIVATE_TIP").format({"owner": world.npc_name(owner)})]
	for w: Dictionary in WayRules.shut_exits(s, Catalog.data["world"], s.room_id):  # a flooded ford, greyed with why (v0.7.46)
		var b := _exit_button(_exit_list, "→ %s (%s)" % [world.room(str(w["to"])).get("name", w["to"]), tr("EXIT_SHUT")], func() -> void: pass, false)
		b.name = "Exit_" + str(w["to"])
		b.tooltip_text = str(w["text"])


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
	for spec: Array in specs:
		# which vessel: «Набрать воды» asks with a menu of those that take water here (v0.8.4.30, the author's feedback)
		var b := _row_button(_bar.section(ActionBar.PLACE), tr(spec[1]), _fill_menu if spec[2] == "fill" else _need.bind(spec[2]), can_act)
		b.name = spec[0]
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.add_theme_font_size_override("font_size", UiTheme.SIZE_SMALL)
		b.tooltip_text = tr(spec[1] + "_TIP")


## Crafting (v0.7.24): «Ремесло» when the hero knows a recipe, has work begun or a thing to break down; the room's
## gathering spots as buttons; v0.7.41: its hunting grounds and fishing waters. No row when there is nothing of it.
func _craft_row(s: GameSession, can_act: bool) -> void:
	var data := Catalog.data
	var craft := not CraftRules.known(s, data).is_empty() or not CraftRules.project(s.character).is_empty()
	var spots := CraftRules.gather_here(s, data)
	var grounds := WildsRules.here(s, data)
	if not craft and spots.is_empty() and grounds.is_empty():
		return
	var acts := _content
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
		var gb := _row_button(acts, str(g["name"]), _try.bind(GameState.craft_act.bind("gather", tag)), can_act and why.is_empty())
		gb.name = "Gather_" + tag
		gb.alignment = HORIZONTAL_ALIGNMENT_CENTER
		gb.clip_text = false
		gb.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		gb.add_theme_font_size_override("font_size", UiTheme.SIZE_SMALL)
		gb.tooltip_text = tr(why) if not why.is_empty() else tr("GATHER_TIP").format({"time": TimeRules.span(int(g["minutes"])),
			"skill": CraftRules.tr_skill(data, str(g["skill"])), "dc": int(g["dc"])})
	for k: String in grounds:
		var wd := WildsRules.kind(data, k)
		var wwhy := WildsRules.why_not(s, data, k)
		var wb := _row_button(acts, str(wd["act"]), wilds_requested.emit.bind(k), can_act and wwhy.is_empty())
		wb.name = "Wilds_" + k
		wb.alignment = HORIZONTAL_ALIGNMENT_CENTER
		wb.clip_text = false
		wb.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		wb.add_theme_font_size_override("font_size", UiTheme.SIZE_SMALL)
		wb.tooltip_text = wwhy if not wwhy.is_empty() else tr("WILDS_TIP").format({"skill": CraftRules.tr_skill(data, str(wd["skill"])),
			"dc": int(wd["dc"]), "n": WildsRules.stock(s, data, k)})


## Work (v0.7.26): a shift of each job whose employer is here, the employer's window by the right button.
func _work_row(s: GameSession, can_act: bool) -> void:
	var data := Catalog.data
	var ids: Array[String] = []
	for id: String in JobRules.state(s.character):
		if JobRules.employer_here(s, data, id):
			ids.append(id)
	if ids.is_empty():
		return
	var acts := _content
	for id: String in ids:
		var j := JobRules.job(s, data, id)
		var b := _row_button(acts, tr("BTN_WORK_SHIFT").format({"name": JobRules.rank_name(s, data, id, JobRules.rank(s.character, id))}), _try.bind(GameState.job_act.bind("shift", id)), can_act and JobRules.shift_why(s, data, id).is_empty())
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


func _animal_acts(s: GameSession, cr: Dictionary, can_act: bool) -> void:
	var cid := str(cr["id"])
	var acts := _acts("CreatureActs_" + cid)
	UiParts.card_button(acts, cid)  # v0.8.4.41: one's own beast is seen whole
	if MountRules.on(Catalog.data):  # v0.7.42: the pack and the cart open as containers
		for spec: Array in [[MountRules.PACK, "BTN_MOUNT_PACK"], [MountRules.CART, "BTN_MOUNT_CART"]]:
			if MountRules.container(s, Catalog.data, str(spec[0]) + cid).is_empty():
				continue
			_flow(acts, tr(spec[1]), container_requested.emit.bind(str(spec[0]) + cid), can_act, "Mount_%s%s" % [str(spec[0]).trim_suffix(":"), cid])
	if bool(cr.get("pet", false)):  # v0.7.43: its name, feeding, scouting
		_flow(acts, tr("BTN_PET_OPEN"), pet_requested.emit.bind(cid), can_act, "Pet_" + cid)
	_flow(acts, tr("BTN_CREATURE_STAY" if bool(cr.get("led", false)) else "BTN_ANIMAL_LEAD"), _try.bind(GameState.creature_act.bind(cid, "lead")), can_act, "Creature_lead_" + cid)
	var name := str(cr.get("name", cid))
	var rb := _flow(acts, tr("BTN_ANIMAL_RELEASE"), func() -> void:
		ConfirmBox.ask(self, tr("CONFIRM_ANIMAL_RELEASE_TITLE").format({"name": name}), tr("CONFIRM_ANIMAL_RELEASE"), tr("BTN_ANIMAL_RELEASE"), _try.bind(GameState.property_act.bind("release", cid))), can_act)
	rb.name = "Creature_release_" + cid
	rb.add_theme_color_override("font_color", UiTheme.BAD)


## Study (v0.7.30): «Учёба» when a lesson may go here — a teacher of the hero's course is here or a study book is carried;
## v0.7.39.7 — or a course the master pointed to waits at a teacher elsewhere (where to go).
func _study_row(s: GameSession, can_act: bool) -> void:
	var data := Catalog.data
	var ready := not StudyRules.books(s, data).is_empty() or not StudyRules.waiting(s, data).is_empty()
	for id: String in StudyRules.view(s.character)["courses"]:
		if StudyRules.here(s, data, str(StudyRules.course(s, data, id).get("teacher", ""))):
			ready = true
	if not ready:
		return
	var acts := _content
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
	var acts := _content
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
	var acts := _content
	if not entry.is_empty():
		var eb := _row_button(acts, tr("BTN_ORG_ENTRY").format({"money": Money.format(int(OrgRules.def(s, Catalog.data, entry)["entry_cp"]))}), _try.bind(GameState.org_act.bind("entry", entry)), can_act and ew.is_empty())
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
	if not OfficeRules.on(Catalog.data):
		return
	if OfficeRules.held(s.character).is_empty() and OfficeRules.of_room(Catalog.data, s.room_id).is_empty():
		return
	var acts := _content
	var b := _row_button(acts, tr("BTN_OFFICE"), office_requested.emit.bind(""), can_act)
	b.name = "OfficeButton"
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_theme_font_size_override("font_size", UiTheme.SIZE_SMALL)
	b.tooltip_text = tr("BTN_OFFICE_TIP")


## Faith (v0.7.49): «Святилище: бог» in a room with a shrine.
func _faith_row(s: GameSession, can_act: bool) -> void:
	if not FaithRules.on(Catalog.data) or s.in_conversation():
		return
	var sh := FaithRules.shrine(s, Catalog.data, s.room_id)
	if sh.is_empty():
		return
	var acts := _content
	var b := _row_button(acts, tr("BTN_FAITH").format({"god": FaithRules.god_name(s, Catalog.data, str(sh["god"]))}), faith_requested.emit, can_act)
	b.name = "FaithButton"
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_theme_font_size_override("font_size", UiTheme.SIZE_SMALL)
	b.tooltip_text = tr("BTN_FAITH_TIP").format({"name": sh.get("name", "")})


## Property (v0.7.27): «Имущество» when the hero owns a place or a beast; the window of the hero's places.
func _property_row(s: GameSession) -> void:
	var venue := ShopRules.here(s, Catalog.data)  # v0.7.29
	if PropertyRules.state(s.character).is_empty() and PropertyRules.animals(s).is_empty() and venue.is_empty():
		return
	var acts := _content
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


## «Набрать воды»: one kind of vessel fills at once; more — a menu of each kind and «all of them».
func _fill_menu() -> void:
	var s := GameState.session
	var data := Catalog.data
	var ids: Array[String] = []
	for v: Dictionary in LiquidRules.to_fill(s.character, data, NeedRules.foul_here(s, data)):
		if not ids.has(str(v["id"])):
			ids.append(str(v["id"]))
	if ids.size() <= 1:
		_need("fill")
		return
	var pop := PopupMenu.new()
	pop.name = "FillMenu"
	add_child(pop)
	pop.add_item(tr("FILL_ALL"), 0)
	for i in ids.size():
		pop.add_item(" · ".join(LiquidRules.lines(s.character, data, s.items, ids[i])), i + 1)
	pop.id_pressed.connect(func(i: int) -> void:
		var err := GameState.need_act("fill", "" if i == 0 else ids[i - 1])
		if not err.is_empty():
			EventBus.message.emit(tr(err)))
	pop.popup_hide.connect(pop.queue_free)
	pop.popup(Rect2i(Vector2i(get_global_mouse_position()), Vector2i.ZERO))


func _need(act: String) -> void:
	var err := GameState.need_act(act)
	if not err.is_empty():
		EventBus.message.emit(tr(err))


## The exits have a fixed height of EXIT_ROWS rows whatever their number (v0.7.39: the panel grew with a room of many
## ways); the rest scroll by the wheel.
## A button that fills its place and cuts a long text with «…» (the whole one is in the tooltip).
func _row_button(parent: Container, text: String, action: Callable, enabled: bool) -> Button:
	if str(parent.name).begins_with("Section_"):  # a cell of the hotbar (v0.8.4.43): its icon by its name, set by the bar
		var cell := IconSlot.make("", text, ActionBar.CELL)
		cell.disabled = not enabled
		cell.pressed.connect(func() -> void: action.call())
		parent.add_child(cell)
		return cell
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
	if b is IconSlot:
		return b
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


func _flow(parent: Container, text: String, action: Callable, enabled: bool, node_name := "", tip := "") -> Button:
	var b := Button.new()
	b.text = text
	if not node_name.is_empty():
		b.name = node_name
	b.tooltip_text = tip
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.disabled = not enabled
	var act := _near(_near_ref, "talk", action) if not _near_ref.is_empty() else action
	b.pressed.connect(func() -> void: act.call())
	parent.add_child(b)
	return b


## A button's act: its refusal goes to the message line.
func _try(act: Callable) -> void:
	var err: String = act.call()
	if not err.is_empty():
		EventBus.message.emit(tr(err))


## One row of a person or a creature (v0.7.70): `head` fills it and gives what the right button opens, then «▾». True
## when its acts are open.
func _being_row(key: String, more_name: String, head: Callable) -> bool:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_content.add_child(row)
	_on_right(head.call(row), key)
	_more(row, more_name, key)
	return _open == key


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


## The ways with a door (v0.7.22.25) in its menu: a key, thieves' tools, force, blows, a spell, a torch, waiting, a knock.
func _door_acts(parent: Container, to: String, ways: Array[Dictionary], can_act: bool) -> void:
	var s := GameState.session
	var acts := HFlowContainer.new()
	acts.name = "DoorActs_" + to
	acts.add_theme_constant_override("h_separation", 6)
	acts.add_theme_constant_override("v_separation", 6)
	parent.add_child(acts)
	var dcs := WayRules.dcs(s, Catalog.data, s.room_id, to)
	var d := WayRules.def(Catalog.data, s.room_id, to)
	var mat := ThingRules.material(Catalog.data, d)
	for w: Dictionary in ways:
		var how := str(w["how"])
		var sp := str(w.get("spell", ""))
		var text := tr("DOOR_WAY_" + how.to_upper())
		if how == "spell":
			text = text.format({"spell": str(Catalog.data["spells"].get(sp, {}).get("name", sp))})
		var btn := _flow(acts, text, _try.bind(GameState.door_act.bind(to, how, sp)), can_act)
		btn.name = "DoorWay_%s%s" % [how, "_" + sp if not sp.is_empty() else ""]
		btn.add_theme_font_size_override("font_size", UiTheme.SIZE_SMALL)
		var ask_dc := SiteRules.ask_dc(s, Catalog.data, SiteRules.unwelcome(s, Catalog.data, to)) if how == "ask" else 0
		btn.tooltip_text = tr("DOOR_WAY_%s_TIP" % how.to_upper()).format({"dc": dcs.get(how, ask_dc), "ac": ThingRules.ac_of(mat),
			"hp": WayRules.hp(s, Catalog.data, s.room_id, to), "max": WayRules.max_hp(Catalog.data, d)})
	if ways.any(func(w: Dictionary) -> bool: return str(w["how"]) == "force") and not ways.any(func(w: Dictionary) -> bool: return str(w["how"]) == "pick"):
		var pb := _flow(acts, tr("DOOR_WAY_PICK"), func() -> void: pass, false)  # v0.7.39.3: seen, grey without the tools
		pb.name = "DoorWay_pick"
		pb.add_theme_font_size_override("font_size", UiTheme.SIZE_SMALL)
		pb.tooltip_text = _no_picks(s)


## Why «Взломать» is grey: no thieves' tools, and where to get them (v0.7.39.3).
func _no_picks(s: GameSession) -> String:
	var hint := FenceRules.tool_hint(s, Catalog.data, "thieves_tools")
	return tr("PICK_NO_TOOLS") + ("" if hint.is_empty() else ": " + hint)


func _trap(to: String, disarm: bool, id: String) -> void:
	var err := GameState.trap_action(to, disarm, id)
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


## The weather under the date (v0.7.46): «Погода: ливень», what it means and what guards the hero in the hint.
func _weather_line(s: GameSession) -> void:
	var k := WeatherRules.at(s, Catalog.data, WorldView.new(Catalog.data["world"]).location_id(s.room_id))
	if k.is_empty():
		return
	var l := _line(tr("SIDE_WEATHER").format({"name": WeatherRules.kind_name(Catalog.data, k)}) + (tr("SIDE_WEATHER_ROOF") if WeatherRules.sheltered(s, Catalog.data) else ""), true)
	l.name = "WeatherLine"
	l.mouse_filter = Control.MOUSE_FILTER_STOP
	l.tooltip_text = "\n".join(WeatherRules.effects(s, Catalog.data, k))


## The nearest festival under the date (v0.7.44): «★ Бродская ярмарка — через 5 дней»; all near ones in the hint.
func _festival_line(s: GameSession, world: WorldView) -> void:
	var near := CalendarRules.upcoming(s, Catalog.data, world.world)
	if near.is_empty():
		return
	var e: Dictionary = near[0]
	var when := tr("SIDE_FESTIVAL_ON").format({"left": CalendarRules.days_word(int(e["left"]))}) if bool(e["on"]) \
		else tr("SIDE_FESTIVAL_IN").format({"in": int(e["in"]), "days": CalendarRules.days_noun(int(e["in"]))})
	var l := _line("★ %s — %s" % [e["name"], when], not bool(e["on"]))
	l.name = "FestivalLine"
	if bool(e["on"]):
		l.add_theme_color_override("font_color", UiTheme.ACCENT)
	l.mouse_filter = Control.MOUSE_FILTER_STOP
	l.tooltip_text = "\n".join(near.map(func(x: Dictionary) -> String: return CalendarRules.line(world.world, x, true)))


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
	if str(_content.name).begins_with("Section_"):  # a cell of the hotbar
		return _row_button(_content, text, action, enabled)
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
	if EncounterRules.sighted(s, s.room_id):
		var enc := EncounterRules.lurking_encounter(s, data, s.room_id)
		_subheading("SIDE_WORD" if bool(EncounterRules.lurking(s, s.room_id).get("word", false)) else "SIDE_UNSEEN")  # v0.7.50.1
		for e: Dictionary in enc.get("enemies", []):
			_line(str(e["name"]), false)
		var why := EncounterRules.talkable(s, data, enc.get("enemies", []))
		var hid := WatchRules.sneaky(s, data) or not EncounterRules.lurking(s, s.room_id).has("encounter") or bool(EncounterRules.lurking(s, s.room_id).get("word", false))
		specs = [["Encounter_attack", tr("BTN_ENCOUNTER_ATTACK" if hid else "BTN_ENCOUNTER_CHARGE"), "", func() -> String: return GameState.encounter_attack()],
			["Encounter_persuasion", tr("BTN_ENCOUNTER_TALK").format({"skill": tr("SKILL_PERSUASION")}), why, func() -> String: return GameState.encounter_parley("persuasion")],
			["Encounter_intimidation", tr("BTN_ENCOUNTER_TALK").format({"skill": tr("SKILL_INTIMIDATION")}),
				EncounterRules.talkable(s, data, enc.get("enemies", []), "intimidation"), func() -> String: return GameState.encounter_parley("intimidation")]]
		if EncounterRules.all_beasts(data, enc.get("enemies", [])):  # v0.7.50
			specs.append(["Encounter_calm", tr("BTN_ENCOUNTER_CALM").format({"dc": EncounterRules.calm_dc(data, enc["enemies"])}), "", func() -> String: return GameState.encounter_parley("animal_handling")])
	elif EncounterRules.captive(s):
		_subheading("SIDE_CAPTIVE")
		for e: Dictionary in EncounterRules.captors(s):
			_line(str(e["name"]), false)
		specs = [["Escape_athletics", tr("BTN_ESCAPE_ATHLETICS").format({"dc": EncounterRules.escape_dc(data, str(s.captive.get("bonds", "")), "escape_athletics")}), "", func() -> String: return GameState.escape_captivity("escape_athletics")],
			["Escape_sleight", tr("BTN_ESCAPE_SLEIGHT").format({"dc": EncounterRules.escape_dc(data, str(s.captive.get("bonds", "")), "escape_sleight")}), "", func() -> String: return GameState.escape_captivity("escape_sleight")],
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
	var tier := CrimeRules.talk_tier(s, Catalog.data, loc)  # v0.7.22.2: as in BG3
	for how: String in CrimeRules.TALK:  # the DC of the roll's own spec: the listener's template may set it (v0.8.4.29.3)
		var dc := int(CheckEngine.preview(s, Catalog.data, {"skill": CrimeRules.TALK[how], "dc_tier": tier}).get("dc", 0))
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
		var giver := str(q.get("giver", ""))  # v0.8.4.2: taken at talking distance, in sight of the giver
		var near := not only_npc.is_empty() or giver.is_empty() or MapSpots.in_reach(s, Catalog.data, giver, "talk")
		var ab := _button(tr("BTN_QUEST_TAKE").format({"title": q["title"]}), func() -> void:
			var err := ConfirmBox.take_quests(self, [qid], GameState.accept_quest.bind(qid))  # the near-impossible asks first
			if not err.is_empty():
				EventBus.message.emit(tr(err)), can_act and near)
		ab.name = "QuestTake_" + qid
		var line := QuestGen.difficulty_line(Catalog.data, q)
		ab.tooltip_text = str(q.get("description", "")) + ("\n" + line if not line.is_empty() else "") + ("" if near else "\n" + tr("QUEST_TAKE_FAR"))
		ab.theme_type_variation = UiTheme.ACCENT_BUTTON
	for t: Dictionary in QuestRules.talks_here(s, world):
		if not only_npc.is_empty() and str(t["npc_id"]) != only_npc:
			continue
		var tid := str(t["quest_id"])
		var why := QuestRules.can_talk(s, world, tid)
		var tb := _button(tr("BTN_QUEST").format({"action": t["action"]}), _try.bind(GameState.quest_talk.bind(tid)), can_act and why.is_empty())
		tb.name = "QuestStep_" + tid
		tb.tooltip_text = tr(why) if not why.is_empty() else str(QuestRules.quest(world, tid)["title"])


## «Здесь действует закон (…)» under a question when the hero's location keeps the law (v0.7.22.27).
func _law_line(s: GameSession) -> String:
	var loc := GameState.world().location_id(s.room_id)
	if CrimeRules.law(Catalog.data, loc).is_empty():
		return ""
	return "\n\n" + tr("CONFIRM_LAW").format({"place": GameState.world().location(loc).get("name", loc)})
