class_name LevelUpView
extends ModalFrame
## The level-up screen over the game (roadmap v0.5.4): what the next level brings (HP by the average, new
## features) and the picks it needs — subclass, feature options, expertise, ability increase, spells.
## Rules and checks are LevelUp's; «Подтвердить» calls GameState.level_up.
## v0.8.4.43.34 (the author, as in BG3): two columns — the picks on the left as icons with the row of the picked ones
## (`PickGrid`: spells by circle, a feature's options, the subclass), what the level gives on the right («Уровень 2 → 3»,
## the hit points, the new features as icons, the slots by circle with the new ones lit); what a choice is shows as a card
## at the cursor, the right button pins it.

const SCENE := "res://ui/components/level_up_view.tscn"
const WIDE := 1300.0
const COMPACT := 620.0
const FEATURE_ICON := 52

var picks := {}
var _box: VBoxContainer
var _gains: VBoxContainer
var confirm: Button
## The rules text of a hovered choice that has no icon of its own (a skill), a card at the cursor.
var _info: DetailsPanel


static func create() -> LevelUpView:
	var view := UiScenes.open(SCENE) as LevelUpView
	view.setup("", WIDE)
	view.bind()
	return view


func required() -> Dictionary:
	var nodes := super()
	nodes.merge({"%LevelBox": "VBoxContainer", "%LevelGains": "VBoxContainer", "%LaterButton": "Button", "%LevelUpConfirm": "Button"})
	return nodes


func bind() -> void:
	close_requested.connect(func() -> void: visible = false)
	_box = UiScenes.need(self, "%LevelBox")  # the choices on the left, what the level gives on the right
	_gains = UiScenes.need(self, "%LevelGains")
	_info = DetailsPanel.new(Vector2.ZERO, true)
	add_child(_info)
	(UiScenes.need(self, "%LaterButton") as Button).pressed.connect(func() -> void: visible = false)
	confirm = UiScenes.need(self, "%LevelUpConfirm")
	confirm.pressed.connect(_on_confirm)
	note.name = "LevelUpError"
	visibility_changed.connect(func() -> void:
		if visible:
			picks = {}
		_rebuild())


func open() -> void:
	visible = true


func _rebuild() -> void:
	if not visible or not GameState.has_session():
		return
	for box: Control in [_box, _gains]:
		for ch in box.get_children():
			box.remove_child(ch)
			ch.queue_free()
	var c := GameState.session.character
	var data := Catalog.data
	if not LevelUp.can_level_up(c, data):
		visible = false
		return
	var p := LevelUp.plan(c, data, picks)
	var choices := bool(p["subclass"]) or not (p["options"] as Array).is_empty() or int(p["expertise"]) > 0 or bool(p["asi"]) \
		or int(p["cantrips"]) > 0 or int(p["spells"]) > 0 or int(p["prepared"]) > 0 or int(p["tome"]) > 0
	set_width(WIDE if choices else COMPACT)  # a level with nothing to pick is a small window (О3)
	_box.visible = choices
	title.text = tr("LVL_TITLE").format({"level": p["level"], "class": c.get("class_name", "")})
	_gains_of(c, data, p)

	if bool(p["subclass"]):
		var subs: Dictionary = data["classes"]["subclasses"]
		var opts: Array = (p["subclasses"] as Array).map(func(id: Variant) -> Dictionary:
			return {"id": id, "label": str(subs.get(str(id), {}).get("name", id)), "ref": "subclasses/" + str(id), "tip": InfoBox.subclass_text(data, str(id))})
		_grid(tr("LVL_SUBCLASS"), "subclass", opts, 1, [str(picks["subclass"])] if picks.has("subclass") else [], func(sel: Array) -> void:
			if sel.is_empty():
				picks.erase("subclass")
			else:
				picks["subclass"] = sel[0]
			picks.erase("options"))
	var feats: Dictionary = data["classes"]["features"]
	for o: Dictionary in p["options"]:
		var fid := str(o["id"])
		var opts: Array = (o["from"] as Array).map(func(id: Variant) -> Dictionary:
			return {"id": id, "label": str(feats.get(str(id), {}).get("name", id)), "ref": "features/" + str(id), "card": CardInfo.feature(data, str(id), c)})
		_grid(tr("LVL_OPTION").format({"name": o["name"], "n": o["choose"]}), "opt_" + fid, opts, int(o["choose"]),
			picks.get("options", {}).get(fid, []), func(sel: Array) -> void:
				var chosen: Dictionary = picks.get("options", {})
				chosen[fid] = sel
				picks["options"] = chosen)
	if int(p["expertise"]) > 0:
		_checks(tr("LVL_EXPERTISE").format({"n": p["expertise"]}), "exp", p["expertise_pool"], func(id: String) -> String: return CharacterRules.expertise_word(data, id),
			int(p["expertise"]), picks.get("expertise", []), func(sel: Array) -> void: picks["expertise"] = sel)
	if bool(p["asi"]):
		_asi(c)
	if int(p["cantrips"]) > 0:
		_grid(tr("LVL_CANTRIPS").format({"n": p["cantrips"]}), "cantrip", _spells(c, p["cantrip_list"]), int(p["cantrips"]),
			picks.get("cantrips", []), func(sel: Array) -> void: picks["cantrips"] = sel)
	if int(p["tome"]) > 0:  # Pact of the Tome: cantrips of any class (v0.8.4.33)
		_grid(tr("LVL_TOME").format({"n": p["tome"]}), "tome", _spells(c, p["tome_list"]), int(p["tome"]),
			picks.get("tome", []), func(sel: Array) -> void: picks["tome"] = sel)
	if int(p["spells"]) > 0:
		_grid(tr("LVL_SPELLS_SPELLBOOK" if p["spell_mode"] == "spellbook" else "LVL_SPELLS").format({"n": p["spells"]}), "spell",
			_spells(c, p["spell_list"]), int(p["spells"]), picks.get("spells", []), func(sel: Array) -> void:
				picks["spells"] = sel
				picks.erase("prepared"))
	var prep := mini(int(p["prepared"]), (p["prepared_list"] as Array).size())
	if prep > 0:
		_grid(tr("LVL_PREPARED").format({"n": prep}), "prep", _spells(c, p["prepared_list"]), prep,
			picks.get("prepared", []), func(sel: Array) -> void: picks["prepared"] = sel)

	var errs := LevelUp.errors(c, data, _clean(p))
	set_note(tr(errs[0]) if not errs.is_empty() else "")
	confirm.disabled = not errs.is_empty() or GameState.is_busy()


## What the level gives, on the right: «Уровень 2 → 3», the hit points, the new features as icons with their cards, the
## spell slots by circle — the new ones lit.
func _gains_of(c: Dictionary, data: Dictionary, p: Dictionary) -> void:
	var lv := int(p["level"])
	var head := UiParts.label(_gains, tr("LVL_FROM_TO").format({"from": lv - 1, "to": lv}), UiTheme.HEADING)
	head.name = "LevelFromTo"
	UiParts.heading(_gains, tr("LVL_GAINS"))
	var hp := HBoxContainer.new()
	hp.add_theme_constant_override("separation", 10)
	_gains.add_child(hp)
	var hp_l := UiParts.label(hp, tr("LVL_HP_GAIN").format({"gain": p["hp_gain"]}), UiTheme.OK_LABEL, true)
	hp_l.add_theme_font_size_override("font_size", UiTheme.SIZE_HEADING - 6)
	UiParts.label(hp, tr("LVL_HP_NOTE"), UiTheme.MUTED_LABEL).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var feats: Array = p["features"]
	if not feats.is_empty():
		_gains.add_child(HSeparator.new())
		UiParts.label(_gains, tr("LVL_NEW_FEATURES"), UiTheme.ACCENT_LABEL)
		for f: Variant in feats:
			var card := CardInfo.feature(data, str(f), c)
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 10)
			_gains.add_child(row)
			var icon := IconSlot.make(str(card.get("icon", "features/" + str(f))), str(card.get("title", f)), FEATURE_ICON)
			icon.name = "Gain_" + str(f)
			icon.set_card(card)
			row.add_child(icon)
			var name_l := UiParts.label(row, str(card.get("title", f)))
			name_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if int(p["max_spell_level"]) > 0:
		var levels: Dictionary = CharacterRules.class_def(c, data)["levels"]
		var now: Array = levels[str(lv)].get("slots", [])
		var was: Array = levels.get(str(lv - 1), {}).get("slots", [])
		_gains.add_child(HSeparator.new())
		UiParts.label(_gains, tr("LVL_SLOTS_HEAD"), UiTheme.ACCENT_LABEL)
		for i in now.size():
			if int(now[i]) <= 0:
				continue
			var old := int(was[i]) if i < was.size() else 0
			var line := RichTextLabel.new()
			line.name = "Slots_%d" % (i + 1)
			line.bbcode_enabled = true
			line.fit_content = true
			line.scroll_active = false
			line.autowrap_mode = TextServer.AUTOWRAP_OFF
			line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			line.text = "[color=#%s]%s[/color]   [color=#%s]%s[/color][color=#%s]%s[/color]" % [UiTheme.MUTED.to_html(false),
				tr("DETAILS_CIRCLE").format({"n": i + 1}), DetailsPanel.COST_COLORS["slot"], "■ ".repeat(mini(old, int(now[i]))),
				UiTheme.ACCENT_BRIGHT.to_html(false), "■ ".repeat(maxi(0, int(now[i]) - old))]
			_gains.add_child(line)


## The spells of `ids` as icons, by circle, each with its card for the hero.
func _spells(c: Dictionary, ids: Array) -> Array:
	var spells: Dictionary = Catalog.data["spells"]
	var out: Array = []
	for id: Variant in ids:
		var sp: Dictionary = spells.get(str(id), {})
		var lv := int(sp.get("level", 0))
		out.append({"id": id, "label": str(sp.get("name", id)), "ref": "spells/" + str(id), "card": CardInfo.spell(Catalog.data, str(id), 0, c), "lv": lv,
			"group": tr("DETAILS_CANTRIP") if lv == 0 else tr("DETAILS_CIRCLE").format({"n": lv})})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["lv"]) < int(b["lv"]) or (int(a["lv"]) == int(b["lv"]) and str(a["label"]) < str(b["label"])))
	return out


## Picks without empty lists the plan does not ask for (errors() wants exact counts).
func _clean(p: Dictionary) -> Dictionary:
	var out := picks.duplicate(true)
	for key: String in ["cantrips", "spells", "prepared", "expertise", "tome"]:
		if not out.has(key):
			out[key] = []
	if not bool(p["asi"]):
		out.erase("asi")
	return out


## A «pick n of these» list of icons (`PickGrid`); a tile is `Pick_<group>_<id>`.
func _grid(title_text: String, group: String, options: Array, n: int, chosen: Array, on_change: Callable) -> void:
	_box.add_child(HSeparator.new())
	var g := PickGrid.make(title_text, options, n, chosen, [], [], "Pick_%s_" % group)
	g.changed.connect(func(sel: Array) -> void:
		on_change.call(sel)
		_rebuild.call_deferred())
	_box.add_child(g)


## A «pick n of these» list of what has no icon (skills): check boxes, a full list ignores more ticks.
func _checks(title_text: String, group: String, ids: Array, label: Callable, n: int, chosen: Array, on_change: Callable) -> void:
	_box.add_child(HSeparator.new())
	UiParts.label(_box, title_text, UiTheme.ACCENT_LABEL)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 16)
	_box.add_child(flow)
	for id: Variant in ids:
		var cb := CheckBox.new()
		cb.name = "Pick_%s_%s" % [group, id]
		cb.text = label.call(str(id))
		cb.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		cb.button_pressed = chosen.has(id)
		cb.toggled.connect(func(on: bool) -> void:
			var sel := chosen.duplicate()
			if on and not sel.has(id) and sel.size() < n:
				sel.append(id)
			elif not on:
				sel.erase(id)
			on_change.call(sel)
			_rebuild.call_deferred())
		flow.add_child(cb)


func _asi(c: Dictionary) -> void:
	_box.add_child(HSeparator.new())
	UiParts.label(_box, tr("LVL_ASI"), UiTheme.ACCENT_LABEL)
	var asi: Dictionary = picks.get("asi", {})
	var used := 0
	for a: String in asi:
		used += int(asi[a])
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 16)
	_box.add_child(grid)
	for a: String in CharacterRules.ABILITIES:
		var score := int(c["abilities"].get(a, 10))
		var add := int(asi.get(a, 0))
		var name_l := Label.new()
		name_l.text = tr("ABILITY_" + a.to_upper())
		grid.add_child(name_l)
		var value := Label.new()
		value.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		value.text = "%d → %d" % [score, score + add] if add > 0 else str(score)
		var font := value.get_theme_font("font")  # the column as wide as «20 → 20»: the buttons stay where they were when a
		if font != null:  # raise is picked (the author, 2026-11-13: «UI сдвигается из-за появления нового текста»)
			value.custom_minimum_size.x = ceilf(font.get_string_size("20 → 20", HORIZONTAL_ALIGNMENT_LEFT, -1, value.get_theme_font_size("font_size")).x) + 4.0
		grid.add_child(value)
		var minus := Button.new()
		minus.name = "Asi_minus_" + a
		minus.text = "−"
		minus.disabled = add <= 0
		minus.pressed.connect(_asi_change.bind(a, -1))
		grid.add_child(minus)
		var plus := Button.new()
		plus.name = "Asi_plus_" + a
		plus.text = "+"
		plus.disabled = used >= 2 or add >= 2 or score + add >= 20
		plus.pressed.connect(_asi_change.bind(a, 1))
		grid.add_child(plus)


func _asi_change(a: String, delta: int) -> void:
	var asi: Dictionary = picks.get("asi", {})
	var v := int(asi.get(a, 0)) + delta
	if v <= 0:
		asi.erase(a)
	else:
		asi[a] = v
	picks["asi"] = asi
	_rebuild()


func _on_confirm() -> void:
	var err := GameState.level_up(_clean(LevelUp.plan(GameState.session.character, Catalog.data, picks)))
	if err.is_empty():
		visible = false
	else:
		set_note(tr(err))
