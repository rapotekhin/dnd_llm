class_name CharacterSheet
extends ModalFrame
## The character sheet over the game screen (roadmap v0.5.0): abilities, saves and skills; features, traits
## and spells; equipment with equip / unequip. Numbers come from the derived cache (CharacterRules.refresh).
## v0.6.0: «Использовать» for features with limited uses and consumables, «Колдовать» with a slot choice,
## «Подготовить заклинания» after a long rest. A cast or use closes the sheet: the master answers in the chat.

signal prepare_requested
signal bag_requested(bag_id: String)

const SCENE := "res://ui/components/character_sheet.tscn"
const TAB_TITLES: Array[String] = ["SHEET_TAB_STATS", "SHEET_TAB_FEATURES", "SHEET_TAB_GEAR", "SHEET_TAB_DEV"]

var _conc_armed := ""  # a concentration spell pressed once while another is held (v0.7.13.1)
var _tabs: TabContainer
var _picked_item := ""  # the item shown in the details panel of the gear tab (v0.7.7 fixes)
var _inv_find := ""  # the search of the gear tab (v0.8.4.32): kept only while the sheet lives
const DOLL_LEFT: Array[String] = ["head", "eyes", "neck", "cloak", "armor", "hands"]
const DOLL_RIGHT: Array[String] = ["main_hand", "off_hand", "shield", "stowed", "ring1", "ring2", "feet"]

var _details: DetailsPanel  # v0.7.22.21 (#2–#5): the one description panel of the sheet, over the chat


func required() -> Dictionary:
	var nodes := super()
	nodes.merge({
		"%SheetSplit": "HBoxContainer", "%SheetTabs": "TabContainer", "%StatsBox": "VBoxContainer",
		"%FeaturesBox": "VBoxContainer", "%DevBox": "VBoxContainer", "%DollLeft": "VBoxContainer",
		"%DollRight": "VBoxContainer", "%GearCoins": "Label", "%CarriedWeight": "Label", "%WeightBar": "ProgressBar",
		"%AttunedCount": "Label", "%GearRows": "VBoxContainer", "%BeltBox": "VBoxContainer",
		"%InvFilters": "HFlowContainer", "%InvSearch": "LineEdit", "%InvSort": "OptionButton", "%InvReverse": "Button",
	})
	return nodes


func _ready() -> void:
	super()
	close_requested.connect(func() -> void: visible = false)
	close_x.name = "CloseSheetButton"
	var split: HBoxContainer = UiScenes.need(self, "%SheetSplit")
	fill_body(split)  # the tabs scroll themselves, the whole screen on an opaque backdrop (v0.7.22.29, Л1)
	_tabs = UiScenes.need(self, "%SheetTabs")
	for i in TAB_TITLES.size():
		_tabs.set_tab_title(i, tr(TAB_TITLES[i]))
	_details = DetailsPanel.new(Vector2(0, 160), true)  # a card at the cursor (v0.8.4.43.3)
	_details.name = "ItemDetails"
	split.add_child(_details.column(ChatView.new(), 460))
	_inv_setup()
	EventBus.state_changed.connect(_rebuild)
	visibility_changed.connect(_rebuild)


func open() -> void:
	visible = true


func _rebuild() -> void:
	if not visible or not GameState.has_session():
		return
	var c := GameState.session.character
	_stats_tab(c)
	_abilities_tab(c)
	_gear_tab(c)
	_development_tab(c)  # v0.7.19.1


## Pact of the Blade (v0.8.4.33, as in BG3): what the pact weapon is, the forms to call and the weapons to bind, nested.
func _pact_rows(box: VBoxContainer, c: Dictionary, can_act: bool) -> void:
	var d := Catalog.data
	var opts := FeatureRules.pact_options(c, d, GameState.session.items)
	if opts.is_empty():
		return
	var now := FeatureRules.pact_item(c)
	_text(box, tr("PACT_NOW").format({"weapon": ItemRules.display_name(d["items"], GameState.session.items, now)}) if not now.is_empty() else tr("PACT_NONE"), UiTheme.MUTED_LABEL)
	var in_fight := CombatRules.active(GameState.session)
	var flow := HFlowContainer.new()
	flow.name = "PactOptions"
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 6)
	box.add_child(flow)
	for o: Dictionary in opts:
		var b := UiParts.act_button(flow, "Pact_" + str(o["id"]).replace(":", "_"), str(o["label"]), "" if can_act and not in_fight else ("PACT_IN_FIGHT" if in_fight else "ABILITY_BUSY"),
			GameState.pact_weapon.bind(str(o["id"])))
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED


## The form of the next familiar (v0.8.4.33): the special ones of Pact of the Chain among them.
func _familiar_rows(box: VBoxContainer, c: Dictionary, can_act: bool) -> void:
	var d := Catalog.data
	var opts := AllyRules.familiar_options(GameState.session, d, c)
	if opts.is_empty():
		return
	var now := AllyRules.familiar_form(GameState.session, d, c)
	_text(box, tr("FAMILIAR_FORM").format({"form": d["monsters"].get(now, {}).get("name", now)}), UiTheme.MUTED_LABEL)
	var flow := HFlowContainer.new()
	flow.name = "FamiliarForms"
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 6)
	box.add_child(flow)
	for o: Dictionary in opts:
		UiParts.act_button(flow, "Familiar_" + str(o["id"]), str(o["label"]), "" if can_act else "ABILITY_BUSY", GameState.choose_familiar.bind(str(o["id"])))


## The life goal (v0.7.22): the player's own words, the master's assessment, a field to change or clear it.
func _goal_section(box: VBoxContainer, c: Dictionary) -> void:
	_text(box, tr("GOAL_TITLE"), UiTheme.HEADING)
	_text(box, tr("GOAL_HINT"), UiTheme.MUTED_LABEL)
	var shown := GoalRules.text_of(c, Catalog.data, false)
	if not shown.is_empty():
		var l := _text(box, shown)
		l.name = "GoalText"
	var v := WorldView.new(Catalog.data["world"])
	var qid := GoalRules.quest_of(c)
	if not qid.is_empty():  # v0.8.4.36: the quest the clues led to
		var q := QuestRules.quest(Catalog.data["world"], qid)
		_text(box, tr("GOAL_QUEST").format({"title": q.get("title", qid), "giver": v.npc_name(str(q.get("giver", "")))})).name = "GoalQuest"
	if not GoalRules.clues(c).is_empty():
		_text(box, tr("GOAL_CLUES"), UiTheme.MUTED_LABEL)
		var i := 0
		for k: Dictionary in GoalRules.clues(c):
			var who := v.npc_name(str(k.get("npc", ""))) if not str(k.get("npc", "")).is_empty() else ""
			_text(box, tr("GOAL_CLUE").format({"day": int(k.get("day", 0)), "who": (who + ": ") if not who.is_empty() else "", "text": k["text"]})).name = "GoalClue%d" % i
			i += 1
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	var edit := LineEdit.new()
	edit.name = "GoalEdit"
	edit.placeholder_text = tr("GOAL_PLACEHOLDER")
	edit.text = str(GoalRules.goal(c).get("text", ""))
	edit.max_length = 240
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.custom_minimum_size = Vector2(0, 48)
	row.add_child(edit)
	var save := Button.new()
	save.name = "GoalSave"
	save.text = "BTN_GOAL_SAVE"
	save.disabled = GameState.is_busy()
	save.pressed.connect(func() -> void: GameState.set_goal(edit.text))
	row.add_child(save)
	var clear := Button.new()
	clear.name = "GoalClear"
	clear.text = "BTN_GOAL_CLEAR"
	clear.disabled = GameState.is_busy() or GoalRules.goal(c).is_empty()
	clear.pressed.connect(func() -> void: GameState.set_goal(""))
	row.add_child(clear)


## Faith (v0.7.49): the god and the favor, the vows with their gifts, what waits for the atonement.
func _faith_section(box: VBoxContainer, c: Dictionary) -> void:
	var s := GameState.session
	var data := Catalog.data
	if not FaithRules.on(data):
		return
	_text(box, tr("FAITH_SHEET_TITLE"), UiTheme.HEADING)
	var mine := FaithRules.hero_god(c)
	var l := _text(box, tr("FAITH_SHEET_GOD").format({"god": FaithRules.god_name(s, data, mine, true), "step": FaithRules.step_of(c, data, mine).get("name", ""),
		"favor": FaithRules.favor(c, mine), "law": FaithRules.god(s, data, mine).get("commandment", "")}) if not mine.is_empty() else tr("FAITH_SHEET_NO_GOD"))
	l.name = "FaithSheetGod"
	for v: Dictionary in FaithRules.vows(c):
		var d := FaithRules.vow(data, str(v["id"]))
		_text(box, "• %s — %s%s" % [d.get("name", v["id"]), d.get("text", ""), tr("FAITH_SHEET_BROKEN") if int(v.get("broken", -1)) >= 0 else ""])
	if FaithRules.lapsed(c):
		_text(box, tr("FAITH_SHEET_LAPSED"), UiTheme.MUTED_LABEL)
	var known := FaithRules.shrines_known(s, data)
	if not known.is_empty():
		var where: Array[String] = []
		for gid: String in known:
			where.append("%s — %s" % [FaithRules.god_name(s, data, gid), ", ".join((known[gid] as Array).map(func(r: Variant) -> String: return str(GameState.world().room(str(r)).get("name", r))))])
		_text(box, tr("FAITH_SHEET_SHRINES").format({"list": "; ".join(where)}), UiTheme.MUTED_LABEL)


## Peaceful development (v0.7.19.1): each direction — its level and experience, the skills taken, and on a level not
## yet paid — the skills to pick from, like the class's level-up.
func _development_tab(c: Dictionary) -> void:
	var box := _page("%DevBox")
	var data := Catalog.data
	_goal_section(box, c)  # v0.7.22
	_faith_section(box, c)  # v0.7.49
	_text(box, tr("DEV_HINT"), UiTheme.MUTED_LABEL)
	for dir: String in DevelopmentRules.cfg(data)["directions"]:
		var d := DevelopmentRules.direction(data, dir)
		var next := DevelopmentRules.next_xp(c, data, dir)
		_text(box, tr("DEV_DIRECTION").format({"name": d["name"], "level": DevelopmentRules.level(c, data, dir), "xp": DevelopmentRules.xp(c, dir),
			"next": next if next >= 0 else "—"}), UiTheme.HEADING)
		for id: Variant in DevelopmentRules.skills(c, dir):
			var sk: Dictionary = d["skills"].get(str(id), {})
			_text(box, "• %s — %s" % [sk.get("name", id), sk.get("desc", "")])
		var choices := DevelopmentRules.choices(c, data, dir)
		if not choices.is_empty():
			_text(box, tr("DEV_PICK"), UiTheme.MUTED_LABEL)
		for id: String in choices:
			var sk: Dictionary = d["skills"][id]
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 12)
			box.add_child(row)
			_text(row, "%s — %s" % [sk["name"], sk.get("desc", "")])
			var b := Button.new()
			b.name = "DevPick_%s_%s" % [dir, id]
			b.text = "BTN_DEV_PICK"
			b.disabled = GameState.is_busy()
			var pick_dir := dir
			var pick_id := id
			b.pressed.connect(func() -> void:
				var err := GameState.pick_development(pick_dir, pick_id)
				if not err.is_empty():
					EventBus.message.emit(tr(err)))
			row.add_child(b)


func current_tab() -> int:
	return _tabs.current_tab


## Opens the sheet on a tab (3 — development).
func open_tab(i: int) -> void:
	visible = true
	_tabs.current_tab = i


## The box of a page, emptied for its rows.
func _page(path: String) -> VBoxContainer:
	var box: VBoxContainer = UiScenes.need(self, path)
	for ch in box.get_children():
		box.remove_child(ch)
		ch.queue_free()
	return box


func _text(parent: Control, text: String, variation: String = "") -> Label:
	var l := Label.new()
	l.text = text
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not variation.is_empty():
		l.theme_type_variation = variation
	parent.add_child(l)
	return l


func _stats_tab(c: Dictionary) -> void:
	var box := _page("%StatsBox")
	var d := Catalog.data
	var sub: Dictionary = d["classes"]["subclasses"].get(str(c.get("subclass", "")), {})
	_text(box, str(c["name"]), UiTheme.HEADING)
	_text(box, tr("SHEET_LINE").format({"race": c["race_name"], "class": c["class_name"] + (" (%s)" % sub["name"] if not sub.is_empty() else ""),
		"level": c["level"], "background": d["backgrounds"].get(str(c["background"]), {}).get("name", "")}), UiTheme.MUTED_LABEL)
	if not (c.get("body", {}) as Dictionary).is_empty():  # v0.7.22.5
		_text(box, BodyRules.text(d, c["body"], str(c.get("gender", "other"))), UiTheme.MUTED_LABEL).name = "HeroBody"
	_text(box, tr("SIDE_HP_AC").format({"hp": c["hp"], "max": c["max_hp"], "ac": c["ac"]}) + ((" · +%d врем." % int(c["temp_hp"])) if int(c.get("temp_hp", 0)) > 0 else ""))
	var chips := EffectChips.new()  # conditions, boons, exhaustion, concentration (v0.7.8)
	box.add_child(chips)
	chips.refresh()
	var boons := CharacterRules.item_boons(c, d, GameState.session.items)  # what the worn things give (v0.7.49.4)
	if not boons.is_empty():
		_text(box, tr("SHEET_ITEM_BOONS") + "\n" + "\n".join(boons.map(func(b: String) -> String: return "    " + b))).name = "SheetItemBoons"
	var resist := HeroDefense.resistances(GameState.session, d)
	if not resist.is_empty():
		_text(box, tr("SHEET_RESIST").format({"list": ", ".join(resist.keys().map(func(t: Variant) -> String:
			return "%s (%s)" % [d["misc"]["damage_types"].get(str(t), t), resist[t]]))}))
	_text(box, tr("SHEET_PROF_SPEED").format({"prof": c["prof_bonus"], "speed": c["speed"]}) + " · " +
		tr("SHEET_PASSIVE").format({"n": c["passive_perception"]}))
	for hand: String in ["main_hand", "off_hand"]:
		var wid := str(c.get("equipped", {}).get(hand, ""))
		if hand == "off_hand" and wid.is_empty():
			continue
		var w := CombatRules.weapon_profile(c, d, GameState.session.items, wid, hand == "off_hand")
		_text(box, tr("SHEET_ATTACK").format({"name": w["name"], "hit": "%+d" % int(w["to_hit"]),
			"dmg": ItemInfo.damage(d, GameState.session.items, w)}))  # with what its properties add (v0.8.4.30)
	if NeedRules.on(GameState.session):  # v0.7.23: the needs with their stage
		var parts: Array[String] = []
		for need: String in NeedRules.KINDS:
			var st := NeedRules.stage(GameState.session, d, need)
			parts.append("%s %d/100%s" % [NeedRules.cfg(d)[need]["name"], roundi(NeedRules.value(GameState.session, d, need)),
				(" — " + str(st["chip"])) if not st.is_empty() else ""])
		var nl := _text(box, tr("SHEET_NEEDS") + ": " + " · ".join(parts), UiTheme.MUTED_LABEL)
		nl.name = "SheetNeeds"
	_text(box, tr("SHEET_ABILITIES") + " · " + tr("SHEET_SKILLS"), UiTheme.MUTED_LABEL)
	var grid := GridContainer.new()  # the skills under their abilities (v0.7.22.32, Л2, Л3)
	grid.name = "AbilityGrid"
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 48)
	grid.add_theme_constant_override("v_separation", 14)
	box.add_child(grid)
	var ids: Array = (d["rules"]["skills"] as Dictionary).keys()
	ids.sort_custom(func(x: String, y: String) -> bool: return tr("SKILL_" + x.to_upper()) < tr("SKILL_" + y.to_upper()))
	for a: String in CharacterRules.ABILITIES:
		var col := VBoxContainer.new()
		col.name = "Ability_" + a
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 2)
		grid.add_child(col)
		var score := int(c["abilities"][a])
		var saved := (c.get("save_profs", []) as Array).has(a)
		var head := _text(col, tr("SHEET_ABILITY_ROW").format({"name": tr("ABILITY_" + a.to_upper()), "score": score,
			"mod": "%+d" % CharacterRules.mod(score), "save": "%+d" % int(c["saves"][a])}) + (" ●" if saved else ""))
		head.add_theme_color_override("font_color", UiTheme.ACCENT_BRIGHT)
		for s: String in ids:
			if str(d["rules"]["skills"][s]) != a:
				continue
			var expert := (c.get("expertise", []) as Array).has(s)
			var prof := expert or (c.get("skill_profs", []) as Array).has(s)
			var sl := _text(col, "    %s %+d%s" % [tr("SKILL_" + s.to_upper()), int(c["skills"][s]), " ●●" if expert else (" ●" if prof else "")])
			sl.name = "Skill_" + s
			sl.add_theme_color_override("font_color", UiTheme.ACCENT_BRIGHT if expert else UiTheme.ACCENT if prof else UiTheme.MUTED)
	var langs: Array = LanguageRules.hero(c, d).map(func(l: String) -> String: return LanguageRules.name_of(d, l))
	var lang_line := _text(box, tr("SHEET_LANGUAGES").format({"list": ", ".join(langs)}), UiTheme.MUTED_LABEL)
	lang_line.mouse_filter = Control.MOUSE_FILTER_STOP
	lang_line.tooltip_text = tr("SHEET_LANGUAGES_TIP")
	var tools: Array = (c.get("tools", []) as Array).map(func(t: Variant) -> String: return BackgroundRules.tool_name(d, str(t)))
	if not tools.is_empty():
		var tool_line := _text(box, tr("SHEET_TOOLS").format({"list": ", ".join(tools)}), UiTheme.MUTED_LABEL)
		tool_line.mouse_filter = Control.MOUSE_FILTER_STOP
		tool_line.tooltip_text = tr("SHEET_TOOLS_TIP")


func _abilities_tab(c: Dictionary) -> void:
	var box := _page("%FeaturesBox")
	var d := Catalog.data
	var feats: Dictionary = d["classes"]["features"]
	var traits: Dictionary = d["races"]["traits"]
	for id: Variant in c.get("features", []):
		var f: Dictionary = feats.get(str(id), {})
		if not f.is_empty() and not f.has("options"):
			_entry(box, str(f["name"]), str(f.get("desc", "")))
	for id: Variant in c.get("traits", []):
		var t: Dictionary = traits.get(str(id), {})
		if not t.is_empty() and not t.has("options"):
			_entry(box, str(t["name"]), str(t.get("desc", "")))
	var bg: Dictionary = d["backgrounds"].get(str(c.get("background", "")), {})
	if not bg.is_empty():
		var rule := str(BackgroundRules.spec(c, d).get("master", ""))
		_entry(box, str(bg["feature"]["name"]), str(bg["feature"]["desc"]) + (("\n\n" + tr("SHEET_BG_IN_GAME").format({"rule": rule})) if not rule.is_empty() else ""))
	var can_act := Backend.is_ready() and not GameState.is_busy()
	box.add_child(HSeparator.new())
	_text(box, tr("SHEET_HIT_DICE").format({"left": ExplorationRules.hit_dice_left(c), "max": int(c.get("level", 1))}), UiTheme.MUTED_LABEL)
	var res := Stock.lines(c, d)
	if not res.is_empty():
		_text(box, tr("SHEET_RESOURCES"), UiTheme.MUTED_LABEL)
		for r: Dictionary in res:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 12)
			box.add_child(row)
			var rl := _text(row, tr("SHEET_RESOURCE").format({"name": r["name"], "left": r["left"], "max": r["max"],
				"rest": tr("REST_KIND_" + str(r["recharge"]).to_upper())}))
			rl.mouse_filter = Control.MOUSE_FILTER_STOP
			_hotbar_drag(rl, "feature", str(r["id"]), "features/" + str((d["rules"]["resources"].get(str(r["id"]), {}).get("features", [r["id"]]) as Array)[0]))
			if Stock.table(d, c)[str(r["id"])].has("spell"):  # spent by casting its spell (v0.8.4.26.1)
				continue
			if str(r["id"]) == "sorcery_points":  # Font of Magic: slots and points (v0.7.10)
				for o: Dictionary in FeatureRules.font_options(c, d):
					_action(row, "Font_" + str(o["id"]), str(o["label"]), can_act, GameState.font_convert.bind(str(o["id"])))
				continue
			_action(row, "Use_" + str(r["id"]), "BTN_USE", can_act and int(r["left"]) > 0, GameState.use_feature.bind(str(r["id"])))
	_pact_rows(box, c, can_act)
	_familiar_rows(box, c, can_act)
	if str(c.get("spell_ability", "")).is_empty():
		return
	box.add_child(HSeparator.new())
	_text(box, tr("SHEET_SPELLCASTING").format({"ability": tr("ABILITY_" + str(c["spell_ability"]).to_upper()),
		"dc": c.get("spell_dc", 0), "attack": "%+d" % int(c.get("spell_attack", 0))}))
	var slots: Array[String] = []
	for i in 5:
		var m := int(c["slots_max"][i])
		if m > 0:
			slots.append(tr("SHEET_SLOT").format({"level": i + 1, "left": SpellRules.slots_left(c, i + 1), "max": m}))
	if not slots.is_empty():
		_text(box, " · ".join(slots), UiTheme.MUTED_LABEL)
	if not str(c.get("concentration", "")).is_empty():
		_text(box, tr("SHEET_CONCENTRATION").format({"spell": d["spells"].get(str(c["concentration"]), {}).get("name", "")}))
	if SpellRules.prepares(c, d):
		var why := SpellRules.can_prepare(c, d)
		var prep := Button.new()
		prep.name = "PrepareButton"
		prep.text = "BTN_PREPARE"
		prep.disabled = not why.is_empty() or GameState.is_busy()
		prep.tooltip_text = tr(why) if not why.is_empty() else ""
		prep.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		prep.pressed.connect(prepare_requested.emit)
		box.add_child(prep)
	var ready_ids := SpellRules.ready(c)
	var sp: Dictionary = c.get("spells", {})
	for list: String in ["cantrips", "tome", "free", "prepared", "always", "known"]:
		var ids: Array = sp.get(list, [])
		if list == "known" and ids == sp.get("prepared", []):
			continue
		if ids.is_empty():
			continue
		_text(box, tr("SHEET_SPELLS_" + list.to_upper()), UiTheme.MUTED_LABEL)
		var sorted := ids.duplicate()  # v0.7.22.21 (#20): by circle, then by name
		sorted.sort_custom(func(a: Variant, b: Variant) -> bool:
			var la := SpellRules.level_of(d, str(a))
			var lb := SpellRules.level_of(d, str(b))
			return la < lb or (la == lb and str(d["spells"].get(str(a), {}).get("name", a)) < str(d["spells"].get(str(b), {}).get("name", b))))
		var circle := -1
		for id: Variant in sorted:
			var s: Dictionary = d["spells"].get(str(id), {})
			var lv := int(s.get("level", 0))
			if lv != circle and list != "cantrips":
				circle = lv
				_text(box, tr("DETAILS_CANTRIP") if lv == 0 else tr("DETAILS_CIRCLE").format({"n": lv})).add_theme_color_override("font_color", UiTheme.MUTED)
			var b := _entry(box, "%s — %s, %s" % [s.get("name", id), s.get("casting_time", ""), s.get("range", "")], DetailsPanel.spell_text(d, str(id)), str(s.get("name", id)))
			UiTheme.school_frame(b, str(s.get("school_id", "")))
			b.name = "Spell_" + str(id)
			_hotbar_drag(b, "spell", str(id), "spells/" + str(id))
			if list != "known" and ready_ids.has(str(id)):
				_cast_row(box, c, str(id), 0 if list == "free" else lv, can_act)


## «Колдовать» with the slot circle to spend (the lowest fitting one first).
func _cast_row(parent: Control, c: Dictionary, id: String, level: int, can_act: bool) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)
	var pick := OptionButton.new()
	pick.name = "Slot_" + id
	pick.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	if SpellRules.free_now(c, Catalog.data, id):
		pick.add_item(tr("SLOT_AT_WILL"), 0)  # an invocation's spell (v0.7.22.4)
	elif level == 0:
		pick.add_item(tr("SLOT_CANTRIP"), 0)
	else:
		for lv in range(level, 6):
			var left := SpellRules.slots_left(c, lv)
			if left > 0:
				pick.add_item(tr("SLOT_CIRCLE").format({"n": lv, "left": left}), lv)
	row.add_child(pick)
	var grown := Label.new()  # v0.7.22.19 (#19): what the chosen slot gives
	grown.name = "Grown_" + id
	grown.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	grown.add_theme_color_override("font_color", UiTheme.MUTED)
	var show_grown := func() -> void:
		grown.text = SpellRules.at_slot(Catalog.data, id, pick.get_selected_id()) if pick.item_count > 0 and level > 0 else ""
	show_grown.call()
	pick.item_selected.connect(func(_i: int) -> void: show_grown.call())
	_action(row, "Cast_" + id, "BTN_CAST", can_act and pick.item_count > 0,
		func() -> String:
			var held := GameState.concentration_conflict(id)  # v0.7.13.1: the second press breaks the old concentration
			if not held.is_empty() and _conc_armed != id:
				_conc_armed = id
				return tr("CONC_SWITCH_AGAIN").format({"old": held})
			_conc_armed = ""
			if not LetterRules.way_by(Catalog.data, "spell", id).is_empty():  # Sending: the letter's window, the slot goes with the letter (v0.8.4.26.3)
				EventBus.letter_requested.emit("")
				return ""
			return GameState.cast(id, pick.get_selected_id() if pick.item_count > 0 else 0))
	row.add_child(grown)


## A button that calls `action` (returns "" or a reason): on success the sheet closes, otherwise a toast.
func _action(parent: Control, node_name: String, text: String, enabled: bool, action: Callable) -> void:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.disabled = not enabled
	b.pressed.connect(func() -> void:
		var err: String = action.call()
		if err.is_empty():
			visible = false
		else:
			EventBus.message.emit(tr(err)))
	parent.add_child(b)


## What is in a vessel or a ready thing (v0.8.4.28): drink it, pour it out, pour it into another vessel of the list.
func _liquid_buttons(row: Control, c: Dictionary, id: String, busy: bool) -> void:
	var data := Catalog.data
	var lv := LiquidRules.first(c, data, id)
	if lv.is_empty() or float(lv["pints"]) <= 0.0:
		return
	var key := LiquidRules.key_of(lv)
	if LiquidRules.drink_why(data, lv).is_empty():
		_action(row, "Drink_" + id, "BTN_LIQUID_DRINK", not busy, GameState.liquid_act.bind("drink", key))
	var targets := LiquidRules.pour_targets(c, data, lv)
	var skill := LiquidRules.needs_why(c, data, str(lv["liquid"]))
	if not skill.is_empty():  # poured only with its tool (v0.8.4.28.3): greyed, the reason on hover
		var b := Button.new()
		b.name = "Pour_" + id
		b.text = "BTN_LIQUID_POUR"
		b.disabled = true
		b.tooltip_text = "%s: %s" % [tr(skill), BackgroundRules.tool_name(data, LiquidRules.needs(data, str(lv["liquid"])))]
		row.add_child(b)
	elif not targets.is_empty():
		var mb := MenuButton.new()
		mb.name = "Pour_" + id
		mb.text = "BTN_LIQUID_POUR"
		mb.disabled = busy
		mb.flat = false
		for t: Dictionary in targets:
			mb.get_popup().add_item(LiquidRules.line(data, GameState.session.items, t))
		mb.get_popup().id_pressed.connect(func(i: int) -> void:
			var err := GameState.liquid_act("pour", key, LiquidRules.key_of(targets[i]))
			if err.is_empty():
				visible = false
			else:
				EventBus.message.emit(tr(err)))
		row.add_child(mb)
	_action(row, "PourOut_" + id, "BTN_LIQUID_POUR_OUT", not busy, GameState.liquid_act.bind("pour_out", key))


## A spell or a feature's uses dragged from the sheet onto a slot of the hotbar (v0.8.4.43.1, as in BG3): the bar takes
## «<kind>:<id>» as its own cell (`ActionBar.cell_key`).
func _hotbar_drag(node: Control, kind: String, id: String, icon: String) -> void:
	node.set_drag_forwarding(func(_at: Vector2) -> Variant:
		var ghost := IconSlot.make(icon, "")
		ghost.size = Vector2(IconSlot.SIZE, IconSlot.SIZE)
		ghost.modulate = Color(1, 1, 1, 0.8)
		node.set_drag_preview(ghost)
		return {"hotbar": "%s:%s" % [kind, id]}, Callable(), Callable())


## A feature, a trait or a spell as one line: its text is in the description panel (hover; the right button pins it).
func _entry(parent: Control, title: String, body: String, short_title: String = "") -> Button:
	var b := Button.new()
	b.text = title
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.add_theme_color_override("font_color", UiTheme.ACCENT)
	parent.add_child(b)
	_details.hook(b, short_title if not short_title.is_empty() else title, body)
	return b


func _gear_tab(c: Dictionary) -> void:
	var box := _page("%GearRows")
	var details := _details
	var s := GameState.session
	var items: Dictionary = Catalog.data["items"]
	var busy := GameState.is_busy()
	for side: String in ["%DollLeft", "%DollRight"]:  # the worn slots around a figure (v0.7.22.32, П8)
		var col := _page(side)
		for slot: String in DOLL_LEFT if side == "%DollLeft" else DOLL_RIGHT:
			if slot == "stowed":
				_stowed_cards(col, details, c, busy)
			else:
				_slot_card(col, details, c, slot, busy)
	_belt_cells(details, c, busy)
	(UiScenes.need(self, "%GearCoins") as Label).text = tr("SIDE_COINS").format({"coins": Money.format(Ledger.balance(s))})
	var weight: Label = UiScenes.need(self, "%CarriedWeight")
	weight.text = tr("SHEET_WEIGHT").format({"n": int(ceilf(CharacterRules.carried_weight(c, Catalog.data, s.items))), "max": CharacterRules.capacity(c, Catalog.data)})
	weight.remove_theme_color_override("font_color")
	var carry := CharacterRules.carried_weight(c, Catalog.data, s.items) / maxf(1.0, CharacterRules.capacity(c, Catalog.data))
	var wbar: ProgressBar = UiScenes.need(self, "%WeightBar")  # П7
	wbar.value = minf(carry, 1.0)
	var wcol := UiTheme.OK if carry < 0.75 else UiTheme.WARN if carry <= 1.0 else UiTheme.BAD
	wbar.add_theme_stylebox_override("fill", UiTheme.box(wcol, wcol, 0, 0, 3))
	wbar.add_theme_stylebox_override("background", UiTheme.box(UiTheme.BG, UiTheme.BORDER, 1, 0, 3))
	(UiScenes.need(self, "%AttunedCount") as Label).text = tr("SHEET_ATTUNED").format({"n": ItemRules.attuned(c).size()})  # v0.7.12
	if CharacterRules.overloaded(c, Catalog.data, s.items):
		weight.text += " — " + tr("TOO_HEAVY")
		weight.add_theme_color_override("font_color", UiTheme.WARN)
	var inv: Dictionary = c.get("inventory", {})
	var group := _inv_filters(inv)
	var bags := ContainerRules.bags(c) if [ItemGroups.ALL, "container"].has(group) and _inv_find.is_empty() else {}
	for bag_id: String in bags:  # v0.7.18.2: the bags and what is in them
		var bag: Dictionary = ContainerRules.bags(c)[bag_id]
		var brow := HBoxContainer.new()
		brow.add_theme_constant_override("separation", 12)
		box.add_child(brow)
		_text(brow, tr("SHEET_BAG").format({"name": ContainerRules.bag_name(Catalog.data, c, bag_id),
			"w": int(ceilf(ContainerRules.weight(Catalog.data, s.items, bag["contents"]))),
			"cap": int(ContainerRules.kind(Catalog.data, str(bag["kind"]))["capacity_lb"])}))
		var ob := Button.new()
		ob.name = "OpenBag_" + bag_id
		ob.text = "BTN_OPEN_BAG"
		ob.disabled = busy
		ob.pressed.connect(func() -> void: bag_requested.emit(bag_id))
		brow.add_child(ob)
		_drop_button(brow, bag_id, 1, "DropBag_" + bag_id, "BTN_DROP", busy)
	var shown_ids := ItemGroups.view(Catalog.data, s.items, inv, group, _inv_sort(), _inv_find, bool(SaveManager.inventory_view.get("reverse", false)))
	var head := ""
	for id: String in shown_ids:
		var def := ItemRules.def_of(items, s.items, id)
		var qty := int(c["inventory"][id])
		var gid := ItemGroups.of(Catalog.data, s.items, id)
		if _inv_sort() == ItemGroups.TYPE and gid != head:  # sections by group, as in Pathfinder
			head = gid
			UiParts.heading(box, ItemGroups.name_of(Catalog.data, gid)).name = "InvHead_" + gid
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		box.add_child(row)
		var water := LiquidRules.summary(c, Catalog.data, id)  # v0.7.34.6: what each vessel holds
		(_item_button(row, details, c, id, "%s%s%s" % [def.get("name", id), " ×%d" % qty if qty > 1 else "", " (%s)" % water if not water.is_empty() else ""], "Item_" + id) as Button).size_flags_stretch_ratio = 2.0
		var info := UiParts.label(row, _inv_info(id, qty), UiTheme.MUTED_LABEL)  # the stack's weight and price
		info.name = "Info_" + id
		info.custom_minimum_size = Vector2(150, 0)
		info.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var acts := HFlowContainer.new()  # the buttons wrap under one another: a row never widens the window
		acts.name = "Acts_" + id
		acts.alignment = FlowContainer.ALIGNMENT_END
		acts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		acts.size_flags_stretch_ratio = 3.0
		acts.add_theme_constant_override("h_separation", 8)
		acts.add_theme_constant_override("v_separation", 6)
		row.add_child(acts)
		var fx := ItemRules.consumable(Catalog.data, id, s.items)
		_liquid_buttons(acts, c, id, busy)
		if not LetterRules.way_by(Catalog.data, "tool", id).is_empty():  # a forgery kit writes in the letter's window (v0.8.4.26.4)
			_action(acts, "Letter_" + id, "BTN_LETTER_WRITE", Backend.is_ready() and not busy, func() -> String:
				EventBus.letter_requested.emit("")
				return "")
		if fx.has("meal"):  # food from the pack; the rest is used from the belt (v0.8.4.24)
			_action(acts, "UseItem_" + id, "BTN_USE", Backend.is_ready() and not busy, GameState.use_item.bind(id))
		elif ItemRules.belt_fits(Catalog.data, s.items, id) and not ItemRules.on_belt(c, Catalog.data, s.items, id):
			var bw := ItemRules.belt_why(c, Catalog.data, s.items, id)
			var bb := Button.new()
			bb.name = "BeltPut_" + id
			bb.text = "BTN_BELT_PUT"
			bb.disabled = busy or not bw.is_empty()
			bb.tooltip_text = tr(bw) if not bw.is_empty() else tr("BELT_USE_TIP")
			bb.pressed.connect(func() -> void:
				var err := GameState.belt_put(id)
				if not err.is_empty():
					EventBus.message.emit(tr(err)))
			acts.add_child(bb)
		for into: Dictionary in ContainerRules.bags_for(s, Catalog.data, id):  # straight into a quiver or a case (v0.8.4.42.1)
			var bag := str(into["bag"])
			var n := mini(int(into["n"]), TradeRules.sellable(s, id, Catalog.data))
			if n <= 0:
				continue
			var name := ContainerRules.bag_name(Catalog.data, c, bag)
			var tb := Button.new()  # the sheet stays open, as with «На пояс»
			tb.name = "ToBag_%s_%s" % [bag, id]
			tb.text = tr("BTN_TO_BAG").format({"name": name.substr(0, 1).to_lower() + name.substr(1)})
			tb.tooltip_text = tr("BTN_TO_BAG_TIP").format({"n": n})
			tb.disabled = busy
			tb.pressed.connect(func() -> void:
				var err := GameState.container_move(bag, id, n, false)
				if not err.is_empty():
					EventBus.message.emit(tr(err)))
			acts.add_child(tb)
		var free := ContainerRules.droppable(s, Catalog.data, id)  # big test #10 (v0.7.22.2)
		if free > 0:
			_drop_button(acts, id, 1, "Drop_" + id, "BTN_DROP", busy)
			if free > 1:
				_drop_button(acts, id, free, "DropAll_" + id, "BTN_DROP_ALL", busy)
		if ItemRules.needs_attunement(def):  # v0.7.12
			if ItemRules.attuned(c).has(id):
				var un := Button.new()
				un.name = "Unattune_" + id
				un.text = "BTN_UNATTUNE"
				un.disabled = busy
				var un_why := ItemRules.can_unattune(c, Catalog.data, s.items, id)
				if not un_why.is_empty():
					un.disabled = true
					un.tooltip_text = tr(un_why)
				un.pressed.connect(func() -> void:
					var err := GameState.unattune(id)
					if not err.is_empty():
						EventBus.message.emit(tr(err)))
				acts.add_child(un)
			else:
				var at_why := ItemRules.can_attune(c, Catalog.data, s.items, id)
				_action(acts, "Attune_" + id, "BTN_ATTUNE", not busy and at_why.is_empty(), GameState.attune.bind(id))
				if not at_why.is_empty():
					(acts.get_child(acts.get_child_count() - 1) as Button).tooltip_text = tr(at_why)
		for o: Dictionary in ItemRules.storable(s, Catalog.data, id):  # a spell into a thing that keeps spells (v0.8.4.36)
			_action(acts, "Store_%s_%s" % [id, o["spell"]], tr("BTN_STORE_SPELL").format({"name": o["name"], "circle": o["circle"]}), not busy,
				GameState.store_spell.bind(id, str(o["spell"]), int(o["circle"])))
		for t: String in CharacterRules.slots_of(def, Catalog.data):
			if str(c["equipped"].get(t, "")) != id:
				_equip_button(acts, c, def, id, t, false, busy)
			if CharacterRules.HANDS.has(t) and str(CharacterRules.stowed(c).get(t, "")) != id:  # any weapon, either set (v0.8.4.24.1)
				_equip_button(acts, c, def, id, t, true, busy)
	if shown_ids.is_empty() and not inv.is_empty():
		UiParts.label(box, tr("INV_NONE"), UiTheme.MUTED_LABEL).name = "InvNone"
	var shown := _picked_item if (c.get("inventory", {}) as Dictionary).has(_picked_item) else ""
	if not shown.is_empty():
		details.show_text(ItemRules.display_name(items, s.items, shown), DetailsPanel.item_text(c, Catalog.data, s.items, shown))


## «В основную руку» or «В запасной набор» (`spare`): the thing to a slot of the hands' set or of the set put away.
func _equip_button(row: Control, c: Dictionary, def: Dictionary, id: String, t: String, spare: bool, busy: bool) -> void:
	var s := GameState.session
	var why := CharacterRules.can_equip(c, Catalog.data, s.items, id, t, spare)
	var b := Button.new()
	var two := t == "main_hand" and (def.get("properties", []) as Array).has("two_handed")
	if spare:
		b.text = tr("BTN_EQUIP_STOWED" if t != "off_hand" else "BTN_EQUIP_STOWED_OFF")
	else:
		b.text = tr("BTN_EQUIP_BOTH_HANDS" if two else "BTN_EQUIP_" + t.to_upper())
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.name = "%s_%s_%s" % ["EquipStowed" if spare else "Equip", t, id]
	b.disabled = busy or not why.is_empty()
	if not why.is_empty():
		b.tooltip_text = tr(why)
	b.pressed.connect(func() -> void:
		var err := GameState.equip(id, t, false, spare)
		if not err.is_empty():
			EventBus.message.emit(tr(err)))
	row.add_child(b)


## The belt under the doll (v0.8.4.24, as in Pathfinder): five cells of the things at hand, «Использовать» and «Снять».
func _belt_cells(details: DetailsPanel, c: Dictionary, busy: bool) -> void:
	var s := GameState.session
	var box := _page("%BeltBox")
	var head := _text(box, tr("SHEET_BELT"), UiTheme.MUTED_LABEL)
	head.tooltip_text = tr("BELT_USE_TIP")
	head.mouse_filter = Control.MOUSE_FILTER_PASS
	# The cells share the row's whole width alike: a name on top, the buttons under it, an empty one a dash in the middle.
	var cells := HBoxContainer.new()
	cells.name = "BeltCells"
	cells.add_theme_constant_override("separation", 6)
	box.add_child(cells)
	var belt := ItemRules.belt(c, Catalog.data, s.items)
	var unfed := Gear.unfed(Catalog.data, s.items, c)  # a bow with nothing to shoot on the belt (v0.8.4.42.1)
	if not unfed.is_empty():
		var names := unfed.map(func(id: String) -> String: return ItemRules.display_name(Catalog.data["items"], s.items, id))
		var warn := _text(box, tr("BELT_NO_AMMO").format({"weapons": ", ".join(names)}), UiTheme.WARN_LABEL)
		warn.name = "BeltNoAmmo"
	for i: int in belt.size():
		var id := belt[i]
		var card := PanelContainer.new()
		card.name = "BeltCell_%d" % i
		card.theme_type_variation = UiTheme.CARD
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.custom_minimum_size = Vector2(0, 64)
		cells.add_child(card)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 2)
		card.add_child(col)
		if id.is_empty():
			var none := _text(col, "—", UiTheme.MUTED_LABEL)
			none.autowrap_mode = TextServer.AUTOWRAP_OFF
			none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			none.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			none.size_flags_vertical = Control.SIZE_EXPAND_FILL
			none.tooltip_text = tr("BELT_EMPTY_TIP")
			none.mouse_filter = Control.MOUSE_FILTER_PASS
			continue
		var qty := int(c["inventory"].get(id, 0))
		var named := _item_button(col, details, c, id, "%s%s" % [ItemRules.display_name(Catalog.data["items"], s.items, id), " ×%d" % qty if qty > 1 else ""], "Belt_%d" % i)
		named.clip_text = true  # a long name is cut, the whole of it is in the description on hover
		named.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		col.add_child(row)
		if not ItemRules.consumable(Catalog.data, id, s.items).is_empty():
			var why := ItemRules.can_use(c, Catalog.data, s.items, id)
			_action(row, "BeltUse_%d" % i, "BTN_USE", Backend.is_ready() and not busy and why.is_empty(), GameState.use_item.bind(id))
		var off := Button.new()
		off.name = "BeltTake_%d" % i
		off.text = "BTN_UNEQUIP"
		off.disabled = busy
		off.pressed.connect(func() -> void:
			var err := GameState.belt_take(i)
			if not err.is_empty():
				EventBus.message.emit(tr(err)))
		row.add_child(off)


## The other weapon set under the hands (v0.8.4.1, as in BG3): the same three hands as the doll's, any weapon in them
## (v0.8.4.24.1), what is in each and the swap.
func _stowed_cards(parent: Control, details: DetailsPanel, c: Dictionary, busy: bool) -> void:
	var s := GameState.session
	var head := _text(parent, tr("SLOT_STOWED"), UiTheme.MUTED_LABEL)
	head.add_theme_font_size_override("font_size", UiTheme.SIZE_SMALL - 2)
	for slot: String in CharacterRules.HANDS:
		_slot_card(parent, details, c, slot, busy, true)
	var why := Acts.one("swap").can(s, Catalog.data, Sheet.HERO)
	var swap := Button.new()
	swap.name = "SwapWeapons"
	swap.text = "SWAP_WEAPONS"
	swap.tooltip_text = Hotkeys.tip(tr("SWAP_WEAPONS"), "swap_weapons", SaveManager.keys) if why.is_empty() else tr(why)
	swap.disabled = not why.is_empty()
	swap.pressed.connect(func() -> void:
		var err := GameState.swap_weapons()
		if not err.is_empty():
			EventBus.message.emit(tr(err)))
	parent.add_child(swap)


## A click on a slot's card: the list of what can be worn there (v0.8.4.2). What may not be worn now is grey with why.
## `spare` — a slot of the set put away: the same things as the doll's hand of that slot (v0.8.4.24.1).
func _slot_pick(card: PanelContainer, slot: String, busy: bool, spare: bool = false) -> void:
	var pop := PopupMenu.new()
	pop.name = "SlotList_" + slot
	card.add_child(pop)
	var s := GameState.session
	var c := s.character
	var ids: Array[String] = []
	for id: String in c.get("inventory", {}):
		if not CharacterRules.slots_of(ItemRules.def_of(Catalog.data["items"], s.items, id), Catalog.data).has(slot):
			continue
		if str((CharacterRules.stowed(c) if spare else c["equipped"]).get(slot, "")) != id:
			ids.append(id)
	for i in ids.size():
		var why := CharacterRules.can_equip(c, Catalog.data, s.items, ids[i], slot, spare)
		pop.add_item(ItemRules.display_name(Catalog.data["items"], s.items, ids[i]), i)
		pop.set_item_disabled(i, busy or not why.is_empty())
		pop.set_item_tooltip(i, tr(why) if not why.is_empty() else "")
	if ids.is_empty():
		pop.add_item(tr("SLOT_PICK_NONE"), -1)
		pop.set_item_disabled(0, true)
	pop.id_pressed.connect(func(i: int) -> void:
		var err := GameState.equip(ids[i], slot, false, spare)
		if not err.is_empty():
			EventBus.message.emit(tr(err)))
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			_open_slot(card))


func _open_slot(card: PanelContainer) -> void:
	var pop: PopupMenu = card.find_children("SlotList_*", "PopupMenu", false, false)[0]
	pop.position = Vector2i(card.get_screen_position() + Vector2(0, card.size.y))
	pop.popup()


func _slot_arrow(row: HBoxContainer, card: PanelContainer) -> void:
	var b := Button.new()
	b.name = card.name.replace("Card_", "Pick_")
	b.text = "▾"
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.tooltip_text = tr("SLOT_PICK_TIP")
	b.pressed.connect(_open_slot.bind(card))
	row.add_child(b)


## A worn slot of the doll: its name, the thing in it (or «—»), «▾» with what fits and «Снять». `spare` — the same hand
## of the set put away (v0.8.4.24.1: one card for both sets).
func _slot_card(parent: Control, details: DetailsPanel, c: Dictionary, slot: String, busy: bool, spare: bool = false) -> void:
	var tag := "Stowed" if spare else "Slot"
	var card := PanelContainer.new()
	card.name = tag + "Card_" + slot
	card.theme_type_variation = UiTheme.CARD
	parent.add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	card.add_child(col)
	var head := _text(col, tr("SLOT_" + slot.to_upper()), UiTheme.MUTED_LABEL)
	head.add_theme_font_size_override("font_size", UiTheme.SIZE_SMALL - 2)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)
	var hands: Dictionary = CharacterRules.stowed(c) if spare else c["equipped"]
	var id := str(hands.get(slot, ""))
	var grip := not spare and CharacterRules.two_hand_grip(c, Catalog.data, GameState.session.items)
	_slot_pick(card, slot, busy, spare)
	if id.is_empty():
		var main := str(hands.get("main_hand", ""))
		var held := slot == "off_hand" and grip
		var none := _text(row, tr("SLOT_HELD_BY").format({"name": ItemRules.display_name(Catalog.data["items"], GameState.session.items, main)}) if held else "—", UiTheme.MUTED_LABEL)
		none.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if spare:
			none.tooltip_text = tr("STOWED_EMPTY_TIP")
			none.mouse_filter = Control.MOUSE_FILTER_PASS
		_slot_arrow(row, card)
		return
	if slot == "main_hand" and grip:
		head.text += " · " + tr("SLOT_GRIP_BOTH")
	_item_button(row, details, c, id, ItemRules.display_name(Catalog.data["items"], GameState.session.items, id), ("Stowed_" if spare else "Slot_") + slot)
	var shots := Gear.ready_shots(Catalog.data, GameState.session.items, c, id)
	if shots >= 0:  # v0.8.4.42.6: the shots at hand, without opening the quiver
		var sl := _text(row, tr("AMMO_READY").format({"n": shots}), UiTheme.MUTED_LABEL if shots > 0 else UiTheme.WARN_LABEL)
		sl.name = ("StowedShots_" if spare else "Shots_") + slot
		sl.tooltip_text = tr("AMMO_READY_TIP")
		sl.mouse_filter = Control.MOUSE_FILTER_PASS
	var b := Button.new()
	b.text = "BTN_UNEQUIP"
	b.name = ("UnequipStowed_" if spare else "Unequip_") + slot
	b.disabled = busy
	b.pressed.connect((GameState.unequip_stowed if spare else GameState.unequip).bind(slot))
	row.add_child(b)
	var w := ItemRules.def_of(Catalog.data["items"], GameState.session.items, id)
	if not spare and slot == "main_hand" and not grip and (w.get("weapon", {}) as Dictionary).has("versatile"):
		var both := Button.new()  # 5e versatile: the bigger die, the shield and the off hand go to the pack
		both.name = "BothHands"
		both.text = "BTN_BOTH_HANDS"
		both.tooltip_text = tr("BOTH_HANDS_TIP").format({"dice": str(w["weapon"]["versatile"])})
		both.disabled = busy
		both.pressed.connect(func() -> void:
			var err := GameState.equip(id, "main_hand", true)
			if not err.is_empty():
				EventBus.message.emit(tr(err)))
		row.add_child(both)
	_slot_arrow(row, card)


## «Выбросить»: the thing (a bag — with what is in it) goes down in the room; the sheet stays open.
func _drop_button(row: Control, what: String, qty: int, node_name: String, text: String, busy: bool) -> void:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.disabled = busy
	b.tooltip_text = tr("BTN_DROP_TIP")
	b.pressed.connect(func() -> void:
		var err := GameState.drop_item(what, qty)
		if not err.is_empty():
			EventBus.message.emit(tr(err)))
	row.add_child(b)


# --- the things by groups, sorted and searched (v0.8.4.32, as in BG3 and Pathfinder) ----------------------------


## The sort list and the search of the gear tab: kept in the scene, so the search keeps its focus over a rebuild.
func _inv_setup() -> void:
	var sort: OptionButton = UiScenes.need(self, "%InvSort")
	sort.tooltip_text = tr("INV_SORT_TIP")
	var keys := ItemGroups.sorts(Catalog.data).keys()
	for i in keys.size():
		sort.add_item(str(ItemGroups.sorts(Catalog.data)[keys[i]]), i)
		sort.set_item_metadata(i, str(keys[i]))
	sort.select(maxi(0, keys.find(_inv_sort())))
	sort.item_selected.connect(func(i: int) -> void: _inv_keep("sort", str(sort.get_item_metadata(i))))
	var rev: Button = UiScenes.need(self, "%InvReverse")
	rev.pressed.connect(func() -> void: _inv_keep("reverse", not bool(SaveManager.inventory_view.get("reverse", false))))
	var find: LineEdit = UiScenes.need(self, "%InvSearch")
	find.text_changed.connect(func(text: String) -> void:
		_inv_find = text
		_rebuild())


func _inv_sort() -> String:
	var sort := str(SaveManager.inventory_view.get("sort", ItemGroups.TYPE))
	return sort if ItemGroups.sorts(Catalog.data).has(sort) else ItemGroups.TYPE


## A choice of the bar kept in the settings, the list built again.
func _inv_keep(key: String, value: Variant) -> void:
	SaveManager.inventory_view[key] = value
	SaveManager.save_settings()
	_rebuild()


## The group buttons with how many kinds of things each holds; the group shown ("" — all; a group emptied shows all).
func _inv_filters(inv: Dictionary) -> String:
	var bar: HFlowContainer = UiScenes.need(self, "%InvFilters")
	for ch in bar.get_children():
		bar.remove_child(ch)
		ch.queue_free()
	var counts := ItemGroups.counts(Catalog.data, GameState.session.items, inv)
	var group := str(SaveManager.inventory_view.get("group", ItemGroups.ALL))
	if not counts.has(group):
		group = ItemGroups.ALL
	(UiScenes.need(self, "%InvReverse") as Button).set_pressed_no_signal(bool(SaveManager.inventory_view.get("reverse", false)))
	var add := func(gid: String, text: String) -> void:
		var b := Button.new()
		b.name = "InvGroup_" + (gid if not gid.is_empty() else "all")
		b.text = text
		b.toggle_mode = true
		b.button_pressed = gid == group
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		b.pressed.connect(_inv_keep.bind("group", gid))
		bar.add_child(b)
	add.call(ItemGroups.ALL, "%s · %d" % [tr("INV_ALL"), inv.size()])
	for gid: String in counts:
		add.call(gid, "%s · %d" % [ItemGroups.name_of(Catalog.data, gid), int(counts[gid])])
	return group


## «2 фнт · 5 зм» of a stack; the price of a thing not identified is «?».
func _inv_info(id: String, qty: int) -> String:
	var s := GameState.session
	var w := ItemGroups.weight(Catalog.data, s.items, id, qty)
	var v := ItemGroups.value(Catalog.data, s.items, id, qty)
	var parts: Array[String] = []
	if w > 0.0:
		parts.append(tr("INV_WEIGHT").format({"n": str(int(w)) if is_equal_approx(w, roundf(w)) else String.num(w, 2)}))
	parts.append("?" if v < 0 else Money.format(v) if v > 0 else "—")
	return " · ".join(parts)


## The item's name as a flat button: a click shows what it is in the details panel (v0.7.7 fixes).
func _item_button(row: Control, details: DetailsPanel, c: Dictionary, id: String, text: String, node_name: String) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.flat = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if id == _picked_item:
		b.add_theme_color_override("font_color", UiTheme.ACCENT_BRIGHT)
	b.pressed.connect(func() -> void: _picked_item = id)
	details.hook(b, ItemRules.display_name(Catalog.data["items"], GameState.session.items, id), DetailsPanel.item_text(c, Catalog.data, GameState.session.items, id))
	row.add_child(b)
	return b
