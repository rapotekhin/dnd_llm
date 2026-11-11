class_name SheetColumn
extends VBoxContainer
## The left column of the character window (v0.8.4.43.6, the sheet as in BG3): three icon tabs — the summary (race, class,
## the six abilities in a row with a star over the class's main one and a dot under a save it knows, the statuses, the
## defenses, the features as icons), the skills (frames by ability, ★ proficiency, ★★ expertise, values by colour), and
## the details (HP, AC, class, race, background, god; initiative, speed, darkvision, size, carrying; proficiencies; saves).
## Anybody's: the numbers are CreatureCard's and Sheet's for `who` (ADR-0016), the breakdown at the cursor is the roll's
## own parts (RollParts, Roll.odds).

const TABS: Array[String] = ["summary", "skills", "detail"]

var who := Being.HERO
var details: DetailsPanel  ## the window's card at the cursor
var tab := "summary"
var _bar: HBoxContainer
var _scroll: ScrollContainer
var _page: VBoxContainer


func _init() -> void:
	name = "SheetColumn"
	add_theme_constant_override("separation", 8)
	_bar = HBoxContainer.new()
	_bar.name = "SheetTabs"
	_bar.add_theme_constant_override("separation", 6)
	_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(_bar)
	_scroll = ScrollContainer.new()
	_scroll.name = "SheetPage"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_scroll)
	_page = VBoxContainer.new()
	_page.name = "SheetPageBox"
	_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page.add_theme_constant_override("separation", 8)
	_scroll.add_child(_page)


## Builds it again for `id` on the tab shown.
func show_of(id: String) -> void:
	who = id
	_tabs()
	for ch in _page.get_children():
		_page.remove_child(ch)
		ch.queue_free()
	var s := GameState.session
	var data := Catalog.data
	var w := Sheet.who(s, data, who)
	var card := CreatureCard.of(s, data, w)
	match tab:
		"skills":
			_skills(s, data, w)
		"detail":
			_detail(s, data, w, card)
		_:
			_summary(s, data, w, card)


func _tabs() -> void:
	for ch in _bar.get_children():
		_bar.remove_child(ch)
		ch.queue_free()
	for t: String in TABS:
		var b := IconSlot.make(IconRules.button(Catalog.data, "SheetTab_" + t), tr("SHEET_TAB_" + t.to_upper()), 44)
		b.name = "SheetTab_" + t
		b.toggle_mode = true
		b.button_pressed = t == tab
		b.pressed.connect(func() -> void:
			tab = t
			show_of(who))
		_bar.add_child(b)


# --- the summary --------------------------------------------------------------------------------------------------


func _summary(s: GameSession, data: Dictionary, w: Dictionary, card: Dictionary) -> void:
	var hero := Sheet.is_hero(w)
	var c := s.character
	if hero:
		_line(_page, str(c.get("race_name", "")), UiTheme.MUTED_LABEL).name = "HeroRace"
		var sub: Dictionary = data["classes"]["subclasses"].get(str(c.get("subclass", "")), {})
		var cls := _line(_page, tr("SHEET_CLASS_LEVEL").format({"class": c.get("class_name", ""), "level": int(c.get("level", 1))}), UiTheme.HEADING)
		cls.name = "HeroClass"
		if not sub.is_empty():
			_line(_page, str(sub["name"]), UiTheme.ACCENT_LABEL).name = "HeroSubclass"
		if not (c.get("body", {}) as Dictionary).is_empty():  # v0.7.22.5
			_line(_page, BodyRules.text(data, c["body"], str(c.get("gender", "other"))), UiTheme.MUTED_LABEL).name = "HeroBody"
	else:
		var npc := WorldView.new(data["world"]).npc(who)
		_line(_page, " · ".join([str(npc.get("role", "")), str(npc.get("race", ""))].filter(func(x: String) -> bool: return not x.is_empty())), UiTheme.MUTED_LABEL)
	_abilities(s, data, w, card)
	_page.add_child(UiParts.hp_line(int(card.get("hp", 0)), int(card.get("max_hp", 1)), int(card.get("temp_hp", 0)), 10.0))
	var chips := EffectChips.new()  # the statuses as icons, the time and the cause at the cursor
	chips.icons = 40
	chips.who = {} if hero else w
	_page.add_child(chips)
	chips.refresh()
	_heading(_page, "SHEET_DEFENSES")
	var defs: Array = card.get("defenses", [])
	if defs.is_empty():
		_line(_page, tr("SHEET_NONE"), UiTheme.MUTED_LABEL)
	for d: Dictionary in defs:
		var l := _line(_page, "%s: %s" % [d["word"], d["what"]])
		l.name = "Defense_" + str(d["kind"])
		if not str(d["source"]).is_empty():
			l.text += " (%s)" % d["source"]
	_heading(_page, "SHEET_FEATURES")
	_features(s, data, w, card)
	if hero:
		var boons := CharacterRules.item_boons(c, data, s.items)  # what the worn things give (v0.7.49.4)
		if not boons.is_empty():
			_line(_page, tr("SHEET_ITEM_BOONS") + "\n" + "\n".join(boons.map(func(b: String) -> String: return "    " + b))).name = "SheetItemBoons"
		if NeedRules.on(s):  # v0.7.23: the needs with their stage
			var parts: Array[String] = []
			for need: String in NeedRules.KINDS:
				var st := NeedRules.stage(s, data, need)
				parts.append("%s %d/100%s" % [NeedRules.cfg(data)[need]["name"], roundi(NeedRules.value(s, data, need)), (" — " + str(st["chip"])) if not st.is_empty() else ""])
			_line(_page, tr("SHEET_NEEDS") + ": " + " · ".join(parts), UiTheme.MUTED_LABEL).name = "SheetNeeds"


## The six abilities in a row (BG3): the short name, the score big; a star over the class's main one, a dot under a save it
## knows; the modifier and the save at the cursor.
func _abilities(s: GameSession, data: Dictionary, w: Dictionary, card: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.name = "AbilityRow"
	row.add_theme_constant_override("separation", 4)
	_page.add_child(row)
	var main := ""
	var cls := str(Sheet.holder(s, w).get("class", ""))
	if not cls.is_empty():
		main = str(data["rules"]["creation"]["main_ability"].get(cls, ""))
	for a: Dictionary in card.get("abilities", []):
		var ab := str(a["id"])
		var col := VBoxContainer.new()
		col.name = "Ability_" + ab
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 0)
		col.mouse_filter = Control.MOUSE_FILTER_STOP
		row.add_child(col)
		var star := _line(col, "★" if ab == main else " ", UiTheme.ACCENT_LABEL)
		star.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		star.add_theme_font_size_override("font_size", UiTheme.SIZE_SMALL - 4)
		var name_l := _line(col, CombatRules.ab_name(ab).to_upper(), UiTheme.MUTED_LABEL)
		name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_l.add_theme_font_size_override("font_size", UiTheme.SIZE_SMALL - 2)
		var v := _line(col, str(int(a["score"])))
		v.name = "Score_" + ab
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_theme_font_size_override("font_size", UiTheme.SIZE_HEADING - 6)
		var saved := Sheet.save_bonus(s, data, w, ab) > Sheet.ability_mod(s, data, w, ab)
		var dot := _line(col, "●" if saved else " ", UiTheme.MUTED_LABEL)
		dot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		dot.add_theme_font_size_override("font_size", UiTheme.SIZE_SMALL - 6)
		for l: Label in [star, name_l, v, dot]:
			l.mouse_filter = Control.MOUSE_FILTER_PASS
		_hook(col, tr("ABILITY_" + ab.to_upper()), tr("SHEET_ABILITY_TIP").format({"mod": "%+d" % int(a["mod"]), "save": "%+d" % Sheet.save_bonus(s, data, w, ab)})
			+ ("\n" + tr("SHEET_MAIN_ABILITY") if ab == main else "") + ("\n" + tr("SHEET_SAVE_PROF") if saved else ""))


## Notable features as in BG3 (v0.8.4.43.13: a list, not a strip of icons — the author: the empty bottom of the sheet): a row
## each — its icon, its name, the uses left; the hero's class features and race traits by id, the background's, the text at
## the cursor; a feature with uses is dragged onto the hotbar by its icon. Another's by its card.
func _features(s: GameSession, data: Dictionary, w: Dictionary, card: Dictionary) -> void:
	var list := VBoxContainer.new()
	list.name = "FeatureList"
	list.add_theme_constant_override("separation", 4)
	_page.add_child(list)
	if not Sheet.is_hero(w):
		var i := 0
		for f: Dictionary in card.get("features", []):
			_feature_row(list, "features/_", "Feature_%d" % i, str(f["name"]), str(f["text"]), {}, "")
			i += 1
		return
	var c := s.character
	var res_of := {}  # a feature → the stock it spends: a drag onto the hotbar and its uses on the row
	var uses := {}
	for r: Dictionary in Stock.lines(c, data):
		uses[str(r["id"])] = r
		for f: Variant in data["rules"]["resources"].get(str(r["id"]), {}).get("features", [r["id"]]):
			res_of[str(f)] = str(r["id"])
	for pair: Array in [["features", data["classes"]["features"], "features"], ["traits", data["races"]["traits"], "traits"]]:
		for id: Variant in c.get(pair[0], []):
			var f: Dictionary = (pair[1] as Dictionary).get(str(id), {})
			if f.is_empty() or f.has("options"):
				continue
			var res := str(res_of.get(str(id), ""))
			_feature_row(list, IconRules.ref(str(pair[2]), str(id)), "Feature_" + str(id), str(f["name"]), str(f.get("desc", "")),
				uses.get(res, {}), "feature:" + res if not res.is_empty() else "")
	var bg: Dictionary = data["backgrounds"].get(str(c.get("background", "")), {})
	if not bg.is_empty():
		var rule := str(BackgroundRules.spec(c, data).get("master", ""))
		_feature_row(list, "features/_background", "Feature_background", str(bg["feature"]["name"]),
			str(bg["feature"]["desc"]) + (("\n\n" + tr("SHEET_BG_IN_GAME").format({"rule": rule})) if not rule.is_empty() else ""), {}, "")


## One row of the notable features: the icon (the drag onto the hotbar when `drag` is set), the name, the uses left of
## its stock (`uses` — a line of Stock.lines, {} — none).
func _feature_row(list: VBoxContainer, icon: String, cell_name: String, title: String, body: String, uses: Dictionary, drag: String) -> void:
	var row := HBoxContainer.new()
	row.name = "Row" + cell_name
	row.add_theme_constant_override("separation", 8)
	list.add_child(row)
	var cell := IconSlot.make(icon, title, 34)
	cell.name = cell_name
	cell.tip_title = title
	cell.tip_body = body
	if not drag.is_empty():
		cell.drag_key = drag
	if not uses.is_empty():
		cell.text = tr("SHEET_RESOURCE").format({"name": uses["name"], "left": uses["left"], "max": uses["max"], "rest": tr("REST_KIND_" + str(uses["recharge"]).to_upper())})
		cell.tooltip_text = cell.text
	row.add_child(cell)
	var name_l := _line(row, title)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_l.mouse_filter = Control.MOUSE_FILTER_PASS
	if not uses.is_empty():
		var left := _line(row, "%d/%d" % [int(uses["left"]), int(uses["max"])], UiTheme.MUTED_LABEL)
		left.name = "Uses"
		left.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_hook(row, title, body)


# --- the skills ---------------------------------------------------------------------------------------------------


func _skills(s: GameSession, data: Dictionary, w: Dictionary) -> void:
	var pb := Sheet.prof(s, data, w)
	_line(_page, tr("SHEET_PROF_LEGEND").format({"n": "%+d" % pb}), UiTheme.MUTED_LABEL).name = "SkillLegend"
	var ids: Array = (data["rules"]["skills"] as Dictionary).keys()
	ids.sort_custom(func(x: String, y: String) -> bool: return tr("SKILL_" + x.to_upper()) < tr("SKILL_" + y.to_upper()))
	for ab: String in CharacterRules.ABILITIES:
		var mine := ids.filter(func(id: String) -> bool: return str(data["rules"]["skills"][id]) == ab)
		if mine.is_empty():
			continue
		var frame := PanelContainer.new()
		frame.name = "Ability_" + ab
		frame.theme_type_variation = UiTheme.CARD
		_page.add_child(frame)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 2)
		frame.add_child(col)
		var mod := Sheet.ability_mod(s, data, w, ab)
		var head := _line(col, "%s (%+d)" % [tr("ABILITY_" + ab.to_upper()), mod], UiTheme.ACCENT_LABEL)
		head.add_theme_color_override("font_color", _sign_color(mod, UiTheme.ACCENT_BRIGHT))
		for id: String in mine:
			var row := HBoxContainer.new()
			row.name = "Skill_" + id
			row.mouse_filter = Control.MOUSE_FILTER_STOP
			row.add_theme_constant_override("separation", 6)
			col.add_child(row)
			var rank := Sheet.skill_rank(s, data, w, id)
			var mark := _line(row, ["", "★", "★★"][rank], UiTheme.ACCENT_LABEL)
			mark.name = "Mark"
			mark.autowrap_mode = TextServer.AUTOWRAP_OFF
			mark.custom_minimum_size = Vector2(34, 0)
			mark.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			var nm := _line(row, tr("SKILL_" + id.to_upper()))
			var v := Sheet.skill(s, data, w, id)
			var val := _line(row, "%+d" % v)
			val.name = "Value"
			val.autowrap_mode = TextServer.AUTOWRAP_OFF
			val.size_flags_horizontal = Control.SIZE_SHRINK_END
			val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			val.add_theme_color_override("font_color", _sign_color(v, UiTheme.TEXT))
			for l: Label in [mark, nm, val]:
				l.mouse_filter = Control.MOUSE_FILTER_PASS
			var parts := RollParts.cached(s.character, data, "skill", id, s.items) if Sheet.is_hero(w) else [RollParts.part(tr("SKILL_" + id.to_upper()), v)]
			_hook(row, tr("SKILL_" + id.to_upper()), _parts_text(parts, v))


# --- the details --------------------------------------------------------------------------------------------------


func _detail(s: GameSession, data: Dictionary, w: Dictionary, card: Dictionary) -> void:
	var hero := Sheet.is_hero(w)
	var c := s.character
	var grid := _table("DetailMain")
	_pair(grid, "SHEET_HP", "%d/%d%s" % [int(card.get("hp", 0)), int(card.get("max_hp", 1)), (" +%d" % int(card["temp_hp"])) if int(card.get("temp_hp", 0)) > 0 else ""])
	_pair(grid, "SHEET_AC", str(int(card.get("ac", 10))))
	if hero:
		var sub: Dictionary = data["classes"]["subclasses"].get(str(c.get("subclass", "")), {})
		_pair(grid, "SHEET_CLASS", tr("SHEET_CLASS_LEVEL").format({"class": c.get("class_name", ""), "level": int(c.get("level", 1))}) + ("\n" + str(sub["name"]) if not sub.is_empty() else ""))
		_pair(grid, "SHEET_RACE", str(c.get("race_name", "")))
		_pair(grid, "SHEET_BACKGROUND", str(data["backgrounds"].get(str(c.get("background", "")), {}).get("name", "")))
		if FaithRules.on(data) and not FaithRules.hero_god(c).is_empty():
			_pair(grid, "SHEET_DEITY", FaithRules.god_name(s, data, FaithRules.hero_god(c), true))
	else:
		var npc := WorldView.new(data["world"]).npc(who)
		_pair(grid, "SHEET_RACE", str(npc.get("race", "")))
		_pair(grid, "SHEET_ROLE", str(npc.get("role", "")))
	_heading(_page, "SHEET_ATTRIBUTES")
	var attrs := _table("DetailAttributes")
	var init := Roll.odds(s, data, w, {"ability": "dex", "about": "initiative"})
	_hook(_pair(attrs, "SHEET_INITIATIVE", "%+d" % int(init["bonus"])), tr("SHEET_INITIATIVE"), _parts_text(init["parts"], int(init["bonus"])))
	_pair(attrs, "SHEET_SPEED", CreatureCard.speed_text(card) if card.has("speed") else "—")
	var dark := SightRules.dark_sight(s, data, w)
	_pair(attrs, "SHEET_DARKVISION", tr("SHEET_FEET").format({"n": dark}) if dark > 0 else "—")
	_pair(attrs, "SHEET_SIZE", tr("SIZE_" + str(card.get("size", "medium")).to_upper()))
	_pair(attrs, "SHEET_PASSIVE_SHORT", str(int(card.get("passive", 10))))
	if hero:
		_pair(attrs, "SHEET_CARRY", tr("SHEET_POUNDS").format({"n": CharacterRules.capacity(c, data)}))
		_pair(attrs, "SHEET_HIT_DICE_SHORT", "%d/%d" % [ExplorationRules.hit_dice_left(c), int(c.get("level", 1))])
	_heading(_page, tr("SHEET_PROF_BONUS").format({"n": "%+d" % Sheet.prof(s, data, w)}), true)
	var profs := _table("DetailProfs")
	if hero:
		var armor: Array = (c.get("armor_profs", []) as Array).map(func(a: Variant) -> String:
			return tr("SLOT_SHIELD") if str(a) == "shield" else tr("ITEM_ARMOR_" + str(a).to_upper()))
		var cats: Dictionary = data["misc"]["categories"]
		var weapons: Array = (c.get("weapon_profs", []) as Array).map(func(x: Variant) -> String:
			var k := str(x) + "_weapons"
			return str(cats[k]["name"]) if cats.has(k) else ItemRules.display_name(data["items"], s.items, str(x)))
		_pair(profs, "SHEET_PROF_ARMOR", ", ".join(armor) if not armor.is_empty() else "—")
		_pair(profs, "SHEET_PROF_WEAPONS", ", ".join(weapons) if not weapons.is_empty() else "—")
		var tools: Array = (c.get("tools", []) as Array).map(func(t: Variant) -> String: return BackgroundRules.tool_name(data, str(t)))
		if not tools.is_empty():
			var tl := _line(_page, tr("SHEET_TOOLS").format({"list": ", ".join(tools)}), UiTheme.MUTED_LABEL)
			tl.mouse_filter = Control.MOUSE_FILTER_STOP
			tl.tooltip_text = tr("SHEET_TOOLS_TIP")
	var langs: Array = LanguageRules.of(s, data, w).map(func(l: String) -> String: return LanguageRules.name_of(data, l))
	var ll := _line(_page, tr("SHEET_LANGUAGES").format({"list": ", ".join(langs)}), UiTheme.MUTED_LABEL)
	ll.mouse_filter = Control.MOUSE_FILTER_STOP
	ll.tooltip_text = tr("SHEET_LANGUAGES_TIP")
	_heading(_page, "SHEET_SAVES")
	var saves := HBoxContainer.new()
	saves.name = "SaveRow"
	_page.add_child(saves)
	for ab: String in CharacterRules.ABILITIES:
		var col := VBoxContainer.new()
		col.name = "Save_" + ab
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.mouse_filter = Control.MOUSE_FILTER_STOP
		saves.add_child(col)
		var n := _line(col, CombatRules.ab_name(ab).to_upper(), UiTheme.MUTED_LABEL)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		n.add_theme_font_size_override("font_size", UiTheme.SIZE_SMALL - 2)
		var bonus := Sheet.save_bonus(s, data, w, ab)
		var v := _line(col, "%+d" % bonus)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_theme_color_override("font_color", _sign_color(bonus, UiTheme.TEXT))
		for l: Label in [n, v]:
			l.mouse_filter = Control.MOUSE_FILTER_PASS
		var parts := RollParts.cached(c, data, "save", ab, s.items) if hero else [RollParts.part(tr("ABILITY_" + ab.to_upper()), bonus)]
		_hook(col, tr("SHEET_SAVE_OF").format({"ability": tr("ABILITY_" + ab.to_upper())}), _parts_text(parts, bonus))


# --- parts --------------------------------------------------------------------------------------------------------


func _table(node_name: String) -> VBoxContainer:
	var g := VBoxContainer.new()
	g.name = node_name
	g.add_theme_constant_override("separation", 4)
	_page.add_child(g)
	return g


## A row of a table: the name muted on the left, the value on the right taking the rest of the row (a long list wraps
## there). The value's label.
func _pair(table: VBoxContainer, key: String, value: String) -> Label:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	table.add_child(row)
	var k := _line(row, tr(key), UiTheme.MUTED_LABEL)
	k.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	k.autowrap_mode = TextServer.AUTOWRAP_OFF  # the name keeps its width, the value wraps
	var v := _line(row, value)
	v.name = key.trim_prefix("SHEET_").capitalize().replace(" ", "")
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return v


func _heading(parent: Control, key: String, done := false) -> void:
	var h := UiParts.label(parent, key if done else tr(key), UiTheme.CAPTION_LABEL)
	h.add_theme_constant_override("line_spacing", 0)


func _line(parent: Control, text: String, variation := "") -> Label:
	return UiParts.label(parent, text, variation)


## The breakdown at the cursor: the window's card, else a plain tooltip.
func _hook(c: Control, title: String, body: String) -> void:
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	if details != null:
		details.hook(c, title, body)
	else:
		c.tooltip_text = body


static func _parts_text(parts: Array, total: int) -> String:
	return DollView._parts_text(parts, total)


## Plus green, minus red, zero as `zero` (BG3's sheet).
static func _sign_color(v: int, zero: Color) -> Color:
	return UiTheme.OK if v > 0 else UiTheme.BAD if v < 0 else zero
