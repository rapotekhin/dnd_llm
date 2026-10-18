class_name CreationScreen
extends Control
## Character creation (roadmap v0.5.0): steps on the left, the current step in the middle, a live summary on
## the right. All rules live in CharacterBuilder; this screen only edits `choices` and redraws.
## «Случайный» fills every step (seeded by --seed when given), «Начать игру» builds the character.

var choices: Dictionary = CharacterBuilder.empty_choices()
var step: String = CharacterBuilder.STEP_RACE

var _steps_box: VBoxContainer
var _body: VBoxContainer
var _summary: VBoxContainer
var _errors: Label
var _back: Button
var _next: Button
var _start: Button


func _ready() -> void:
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	margin.add_child(col)
	var title := Label.new()
	title.text = "CC_TITLE"
	title.theme_type_variation = UiTheme.HEADING
	col.add_child(title)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(row)
	_steps_box = VBoxContainer.new()
	_steps_box.custom_minimum_size = Vector2(300, 0)
	_steps_box.add_theme_constant_override("separation", 8)
	row.add_child(_steps_box)

	var body_panel := PanelContainer.new()
	body_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_panel.size_flags_stretch_ratio = 2.2
	row.add_child(body_panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body_panel.add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 12)
	scroll.add_child(_body)

	var side := PanelContainer.new()
	side.theme_type_variation = UiTheme.SIDE
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(side)
	var side_scroll := ScrollContainer.new()
	side_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side.add_child(side_scroll)
	_summary = VBoxContainer.new()
	_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_summary.add_theme_constant_override("separation", 6)
	side_scroll.add_child(_summary)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 16)
	col.add_child(bottom)
	_button(bottom, "BTN_TO_MENU", func() -> void: EventBus.navigate.emit("menu", {}))
	var rnd := _button(bottom, "CC_RANDOM", _randomize)
	rnd.name = "RandomButton"
	_errors = Label.new()
	_errors.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_errors.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_errors.add_theme_color_override("font_color", UiTheme.WARN)
	bottom.add_child(_errors)
	_back = _button(bottom, "BTN_BACK", func() -> void: _move(-1))
	_next = _button(bottom, "CC_NEXT", func() -> void: _move(1))
	_next.name = "NextButton"
	_start = _button(bottom, "CC_START", _finish)
	_start.name = "StartButton"
	_start.theme_type_variation = UiTheme.ACCENT_BUTTON
	_redraw()


func data() -> Dictionary:
	return Catalog.data


func _button(parent: Control, key: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = key
	b.custom_minimum_size = Vector2(0, 56)
	b.pressed.connect(action)
	parent.add_child(b)
	return b


func _randomize() -> void:
	var rng := RandomNumberGenerator.new()
	var seed_arg := LaunchArgs.value("--seed")
	if seed_arg.is_empty():
		rng.randomize()
	else:
		rng.seed = int(seed_arg)
	choices = CharacterBuilder.random_choices(data(), rng)
	step = CharacterBuilder.STEP_DETAILS
	_redraw()


func _move(delta: int) -> void:
	var list := CharacterBuilder.steps(choices, data())
	var i := clampi(list.find(step) + delta, 0, list.size() - 1)
	step = list[i]
	_redraw()


func _finish() -> void:
	if not CharacterBuilder.complete(choices, data()):
		return
	GameEntry.enter({"kind": "new", "character": CharacterBuilder.build(choices, data())})


## A callback that stores a multi-pick (Array) into choices[key].
func _setter(key: String) -> Callable:
	return func(value: Variant) -> void: _changed(key, value)


## A choice changed: drop picks that depend on it, then redraw.
func _changed(key: String, value: Variant) -> void:
	choices[key] = value
	match key:
		"race":
			choices["subrace"] = ""
			for k: String in ["ability_choice", "extra_skills", "race_cantrips", "languages", "skills"]:
				choices[k] = []
			choices["options"] = {}
		"subrace":
			choices["race_cantrips"] = []
			choices["languages"] = []
		"class":
			choices["subclass"] = ""
			for k: String in ["skills", "expertise", "cantrips", "spells", "equipment"]:
				choices[k] = []
			choices["options"] = {}
		"subclass":
			choices["options"] = {}
		"background":
			for k: String in ["skills", "extra_skills", "expertise", "languages"]:
				choices[k] = []
	_redraw()


# --- drawing -------------------------------------------------------------------------


func _redraw() -> void:
	var list := CharacterBuilder.steps(choices, data())
	if not list.has(step):
		step = list[0]
	_clear(_steps_box)
	for s: String in list:
		var ok := CharacterBuilder.errors(choices, data(), s).is_empty()
		var b := Button.new()
		b.text = ("✓ " if ok else "• ") + tr("CC_STEP_" + s.to_upper())
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		b.button_pressed = s == step
		b.custom_minimum_size = Vector2(0, 48)
		b.pressed.connect(func() -> void: step = s; _redraw())
		_steps_box.add_child(b)
	_clear(_body)
	call("_draw_" + step)
	var errs := CharacterBuilder.errors(choices, data(), step)
	_errors.text = " · ".join(errs.map(func(e: String) -> String: return tr(e)))
	var i := list.find(step)
	_back.disabled = i <= 0
	_next.visible = i < list.size() - 1
	_next.disabled = not errs.is_empty()
	_start.visible = i == list.size() - 1
	_start.disabled = not CharacterBuilder.complete(choices, data())
	_draw_summary()


func _clear(box: Control) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


func _heading(parent: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = UiTheme.HEADING
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)


func _text(parent: Control, text: String, muted: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	if not (parent is GridContainer):
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if muted:
		l.theme_type_variation = UiTheme.MUTED_LABEL
	parent.add_child(l)
	return l


## Single choice from `options` [{id, label}] into choices[key].
func _radio(parent: Control, key: String, options: Array, columns: int = 3) -> void:
	var grid := GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	parent.add_child(grid)
	for o: Dictionary in options:
		var b := Button.new()
		b.text = str(o["label"])
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		b.toggle_mode = true
		b.button_pressed = str(choices.get(key, "")) == str(o["id"])
		b.custom_minimum_size = Vector2(220, 52)
		b.name = "Pick_" + str(o["id"])
		if o.has("tooltip"):
			b.tooltip_text = str(o["tooltip"])
		b.pressed.connect(_changed.bind(key, o["id"]))
		grid.add_child(b)


## Several choices (up to `limit`) from `options` [{id, label, tooltip?}]; `fixed` are shown checked and locked.
func _checks(parent: Control, picked: Array, options: Array, limit: int, on_change: Callable, fixed: Array = [], columns: int = 3) -> void:
	var grid := GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", 16)
	parent.add_child(grid)
	for o: Dictionary in options:
		var cb := CheckBox.new()
		cb.text = str(o["label"])
		cb.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		cb.name = "Check_" + str(o["id"])
		if o.has("tooltip"):
			cb.tooltip_text = str(o["tooltip"])
		var id: Variant = o["id"]
		if fixed.has(id):
			cb.button_pressed = true
			cb.disabled = true
		else:
			cb.button_pressed = picked.has(id)
			cb.disabled = not picked.has(id) and picked.size() >= limit
			cb.toggled.connect(func(on: bool) -> void:
				var next := picked.duplicate()
				if on and not next.has(id):
					next.append(id)
				elif not on:
					next.erase(id)
				on_change.call(next))
		grid.add_child(cb)


func _skill_label(id: String) -> String:
	return tr("SKILL_" + id.to_upper())


func _ability_label(id: String) -> String:
	return tr("ABILITY_" + id.to_upper())


func _bonuses_text(bonuses: Dictionary) -> String:
	var parts: Array[String] = []
	for a: String in bonuses:
		parts.append("%s %+d" % [_ability_label(a), int(bonuses[a])])
	return ", ".join(parts)


func _traits_block(parent: Control, ids: Array) -> void:
	var traits: Dictionary = data()["races"]["traits"]
	for t: Variant in ids:
		var d: Dictionary = traits.get(str(t), {})
		if d.is_empty():
			continue
		_text(parent, "%s. %s" % [d["name"], d.get("desc", "")], true)


func _features_block(parent: Control, ids: Array) -> void:
	var feats: Dictionary = data()["classes"]["features"]
	for f: Variant in ids:
		var d: Dictionary = feats.get(str(f), {})
		if not d.is_empty():
			_text(parent, "%s. %s" % [d["name"], d.get("desc", "")], true)


func _draw_race() -> void:
	_heading(_body, "CC_STEP_RACE")
	var races: Dictionary = data()["races"]["races"]
	var opts: Array = []
	for id: String in races:
		opts.append({"id": id, "label": races[id]["name"]})
	_radio(_body, "race", opts)
	var r := CharacterBuilder.race(choices, data())
	if r.is_empty():
		return
	_text(_body, tr("CC_RACE_LINE").format({"bonuses": _bonuses_text(r["ability_bonuses"]), "speed": int(r["speed"])}))
	if r.has("ability_choice"):
		_text(_body, tr("CC_RACE_ABILITY_CHOICE").format({"n": r["ability_choice"]["choose"]}), true)
	_traits_block(_body, r["traits"])


func _draw_subrace() -> void:
	_heading(_body, "CC_STEP_SUBRACE")
	var subs: Dictionary = data()["races"]["subraces"]
	var opts: Array = []
	for id: Variant in CharacterBuilder.race(choices, data()).get("subraces", []):
		opts.append({"id": id, "label": subs[str(id)]["name"]})
	_radio(_body, "subrace", opts)
	var s := CharacterBuilder.subrace(choices, data())
	if s.is_empty():
		return
	_text(_body, str(s.get("desc", "")), true)
	_text(_body, _bonuses_text(s["ability_bonuses"]))
	_traits_block(_body, s["traits"])


func _draw_class() -> void:
	_heading(_body, "CC_STEP_CLASS")
	var classes: Dictionary = data()["classes"]["classes"]
	var opts: Array = []
	for id: String in classes:
		opts.append({"id": id, "label": classes[id]["name"]})
	_radio(_body, "class", opts, 4)
	var k := CharacterBuilder.klass(choices, data())
	if k.is_empty():
		return
	var saves: Array = (k["saves"] as Array).map(func(a: Variant) -> String: return _ability_label(str(a)))
	_text(_body, tr("CC_CLASS_LINE").format({"die": int(k["hit_die"]), "saves": ", ".join(saves),
		"skills": int(k["skill_choice"]["choose"]) if k.get("skill_choice") is Dictionary else 0}))
	if k.has("spellcasting"):
		_text(_body, tr("CC_CLASS_CASTER").format({"ability": _ability_label(str(k["spellcasting"]["ability"]))}), true)
	_features_block(_body, k["levels"]["1"]["features"])


func _draw_subclass() -> void:
	var k := CharacterBuilder.klass(choices, data())
	_heading(_body, str(k.get("subclass_flavor", tr("CC_STEP_SUBCLASS"))))
	var subs: Dictionary = data()["classes"]["subclasses"]
	var opts: Array = []
	for id: Variant in k.get("subclasses", []):
		opts.append({"id": id, "label": subs[str(id)]["name"]})
	_radio(_body, "subclass", opts)
	var s: Dictionary = subs.get(str(choices.get("subclass", "")), {})
	if not s.is_empty():
		_text(_body, str(s.get("desc", "")), true)
		_features_block(_body, s.get("features", {}).get("1", []))


func _draw_background() -> void:
	_heading(_body, "CC_STEP_BACKGROUND")
	var bgs: Dictionary = data()["backgrounds"]
	var opts: Array = []
	for id: String in bgs:
		opts.append({"id": id, "label": bgs[id]["name"]})
	_radio(_body, "background", opts)
	var b := CharacterBuilder.background(choices, data())
	if b.is_empty():
		return
	_text(_body, str(b["desc"]))
	var skills: Array = (b["skills"] as Array).map(func(s: Variant) -> String: return _skill_label(str(s)))
	_text(_body, tr("CC_BACKGROUND_SKILLS").format({"skills": ", ".join(skills)}))
	_text(_body, "%s. %s" % [b["feature"]["name"], b["feature"]["desc"]], true)


func _draw_abilities() -> void:
	_heading(_body, "CC_STEP_ABILITIES")
	var pb: Dictionary = data()["rules"]["point_buy"]
	var left := int(pb["budget"]) - CharacterBuilder.point_cost(choices, data())
	_text(_body, tr("CC_POINTS_LEFT").format({"n": left}))
	var final := CharacterBuilder.final_abilities(choices, data())
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 8)
	_body.add_child(grid)
	for a: String in CharacterRules.ABILITIES:
		var base := int(choices["base_abilities"][a])
		_text(grid, _ability_label(a))
		var minus := Button.new()
		minus.text = "−"
		minus.name = "Minus_" + a
		minus.disabled = base <= int(pb["min"])
		minus.pressed.connect(_set_ability.bind(a, base - 1))
		grid.add_child(minus)
		_text(grid, str(base))
		var plus := Button.new()
		plus.text = "+"
		plus.name = "Plus_" + a
		var next_cost := int(pb["cost"].get(str(base + 1), 99)) - int(pb["cost"][str(base)])
		plus.disabled = base >= int(pb["max"]) or next_cost > left
		plus.pressed.connect(_set_ability.bind(a, base + 1))
		grid.add_child(plus)
		_text(grid, "→ %d" % int(final[a]))
		_text(grid, "%+d" % CharacterRules.mod(int(final[a])), true)
	var choice: Variant = CharacterBuilder.race(choices, data()).get("ability_choice")
	if choice is Dictionary:
		_text(_body, tr("CC_RACE_ABILITY_CHOICE").format({"n": choice["choose"]}))
		var opts: Array = (choice["from"] as Array).map(func(a: Variant) -> Dictionary: return {"id": a, "label": _ability_label(str(a))})
		_checks(_body, choices["ability_choice"], opts, int(choice["choose"]), _setter("ability_choice"), [], 6)


func _set_ability(a: String, value: int) -> void:
	choices["base_abilities"][a] = value
	_redraw()


func _draw_skills() -> void:
	_heading(_body, "CC_STEP_SKILLS")
	var fixed := CharacterBuilder.fixed_skills(choices, data())
	if not fixed.is_empty():
		_text(_body, tr("CC_SKILLS_FIXED").format({"skills": ", ".join(fixed.map(_skill_label))}), true)
	var sc := CharacterBuilder.class_skill_choice(choices, data())
	_text(_body, tr("CC_SKILLS_CLASS").format({"n": sc["choose"]}))
	var opts: Array = (sc["from"] as Array).map(func(s: Variant) -> Dictionary: return {"id": s, "label": _skill_label(str(s))})
	_checks(_body, choices["skills"], opts, int(sc["choose"]), _setter("skills"))
	var rc := CharacterBuilder.race_skill_choice(choices, data())
	if int(rc["choose"]) > 0:
		_text(_body, tr("CC_SKILLS_RACE").format({"n": rc["choose"]}))
		var ropts: Array = (rc["from"] as Array).map(func(s: Variant) -> Dictionary: return {"id": s, "label": _skill_label(str(s))})
		_checks(_body, choices["extra_skills"], ropts, int(rc["choose"]), _setter("extra_skills"))


func _draw_features() -> void:
	_heading(_body, "CC_STEP_FEATURES")
	var feats: Dictionary = data()["classes"]["features"]
	var traits: Dictionary = data()["races"]["traits"]
	for fc: Dictionary in CharacterBuilder.feature_choices(choices, data()):
		_text(_body, str(fc["name"]))
		var pool: Dictionary = feats if fc["kind"] == "feature" else traits
		var opts: Array = []
		for o: Variant in fc["from"]:
			var d: Dictionary = pool.get(str(o), {})
			opts.append({"id": o, "label": str(d.get("name", o)).get_slice(": ", 1) if ": " in str(d.get("name", "")) else str(d.get("name", o)),
				"tooltip": str(d.get("desc", ""))})
		var picked: Array = choices["options"].get(fc["id"], [])
		_checks(_body, picked, opts, int(fc["choose"]), func(next: Array) -> void:
			choices["options"][fc["id"]] = next
			_redraw(), [], 2)
	var n := CharacterBuilder.expertise_count(choices, data())
	if n > 0:
		_text(_body, tr("CC_EXPERTISE").format({"n": n}))
		var pool := CharacterBuilder.fixed_skills(choices, data()) + CharacterBuilder.all_skills(choices)
		var opts: Array = pool.map(func(s: Variant) -> Dictionary: return {"id": s, "label": _skill_label(str(s))})
		_checks(_body, choices["expertise"], opts, n, _setter("expertise"))


func _spell_options(ids: Array) -> Array:
	var spells: Dictionary = data()["spells"]
	var out: Array = []
	for id: Variant in ids:
		var s: Dictionary = spells[str(id)]
		out.append({"id": id, "label": str(s["name"]), "tooltip": "%s · %s · %s\n%s" % [s["school"], s["casting_time"], s["range"], s["desc"]]})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["label"]) < str(b["label"]))
	return out


func _draw_spells() -> void:
	_heading(_body, "CC_STEP_SPELLS")
	var sp := CharacterBuilder.spell_choices(choices, data())
	if int(sp["cantrips"]) > 0:
		_text(_body, tr("CC_CANTRIPS").format({"n": sp["cantrips"]}))
		_checks(_body, choices["cantrips"], _spell_options(sp["cantrip_list"]), int(sp["cantrips"]), _setter("cantrips"))
	if int(sp["spells"]) > 0:
		_text(_body, tr("CC_SPELLS_" + str(sp["mode"]).to_upper()).format({"n": sp["spells"]}))
		_checks(_body, choices["spells"], _spell_options(sp["spell_list"]), int(sp["spells"]), _setter("spells"))
	if int(sp["race_cantrips"]) > 0:
		_text(_body, tr("CC_RACE_CANTRIP"))
		_checks(_body, choices["race_cantrips"], _spell_options(sp["race_list"]), int(sp["race_cantrips"]), _setter("race_cantrips"))


func _item_name(id: String) -> String:
	return ItemRules.display_name(data()["items"], {}, id)


func _alt_text(alt: Dictionary) -> String:
	var parts: Array[String] = []
	for e: Dictionary in alt["items"]:
		parts.append(_item_name(str(e["id"])) + (" ×%d" % int(e["qty"]) if int(e["qty"]) > 1 else ""))
	for p: Dictionary in alt["picks"]:
		var what := str(data()["misc"]["categories"].get(str(p.get("category", "")), {}).get("name", tr("CC_ITEM_OF_CHOICE")))
		parts.append(("%d × %s" % [int(p["count"]), what]) if int(p["count"]) > 1 else what)
	return ", ".join(parts)


func _draw_equipment() -> void:
	_heading(_body, "CC_STEP_EQUIPMENT")
	var sets: Array = CharacterBuilder.klass(choices, data()).get("equipment_choices", [])
	var picked: Array = choices["equipment"]
	while picked.size() < sets.size():
		picked.append({"alt": -1, "picks": []})
	for i in sets.size():
		var alts: Array = sets[i]["alternatives"]
		var box := HFlowContainer.new()
		box.add_theme_constant_override("h_separation", 10)
		box.add_theme_constant_override("v_separation", 10)
		_body.add_child(box)
		for a in alts.size():
			var b := Button.new()
			b.text = _alt_text(alts[a])
			b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			b.toggle_mode = true
			b.name = "Equip_%d_%d" % [i, a]
			b.button_pressed = int(picked[i]["alt"]) == a
			b.pressed.connect(func() -> void:
				picked[i] = {"alt": a, "picks": _default_picks(alts[a]["picks"])}
				_redraw())
			box.add_child(b)
		var cur := int(picked[i]["alt"])
		if cur >= 0:
			var k := 0
			for p: Dictionary in alts[cur]["picks"]:
				var opts := CharacterBuilder.pick_options(data(), p)
				for n in int(p["count"]):
					var ob := OptionButton.new()
					ob.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
					for o: Variant in opts:
						ob.add_item(_item_name(str(o)))
					var slot := k
					ob.selected = maxi(0, opts.find((picked[i]["picks"] as Array)[slot]))
					ob.item_selected.connect(func(idx: int) -> void:
						picked[i]["picks"][slot] = opts[idx]
						_redraw())
					_body.add_child(ob)
					k += 1
		_body.add_child(HSeparator.new())
	_text(_body, tr("CC_EQUIPMENT_BACKGROUND").format({"items": _alt_text({"items": CharacterBuilder.background(choices, data()).get("equipment", []), "picks": []})}), true)


func _default_picks(picks: Array) -> Array:
	var out: Array = []
	for p: Dictionary in picks:
		var opts := CharacterBuilder.pick_options(data(), p)
		for n in int(p["count"]):
			out.append(opts[0] if not opts.is_empty() else "")
	return out


func _draw_details() -> void:
	_heading(_body, "CC_STEP_DETAILS")
	var name_edit := LineEdit.new()
	name_edit.name = "NameEdit"
	name_edit.placeholder_text = "CC_NAME"
	name_edit.text = str(choices.get("name", ""))
	name_edit.custom_minimum_size = Vector2(0, 56)
	name_edit.text_changed.connect(func(t: String) -> void:
		choices["name"] = t
		_errors.text = " · ".join(CharacterBuilder.errors(choices, data(), step).map(func(e: String) -> String: return tr(e)))
		_start.disabled = not CharacterBuilder.complete(choices, data()))
	name_edit.text_submitted.connect(func(_t: String) -> void: _redraw())
	_body.add_child(name_edit)
	_radio(_body, "gender", [{"id": "male", "label": tr("CC_GENDER_MALE")}, {"id": "female", "label": tr("CC_GENDER_FEMALE")}], 2)
	var n := CharacterBuilder.language_count(choices, data())
	if n > 0:
		_text(_body, tr("CC_LANGUAGES").format({"n": n}))
		var langs: Dictionary = data()["misc"]["languages"]
		var opts: Array = CharacterBuilder.language_options(choices, data()).map(func(l: String) -> Dictionary: return {"id": l, "label": langs[l]["name"]})
		_checks(_body, choices["languages"], opts, n, _setter("languages"))


func _draw_summary() -> void:
	_clear(_summary)
	var d := data()
	var lines: Array[String] = []
	var r := CharacterBuilder.race(choices, d)
	var k := CharacterBuilder.klass(choices, d)
	_text(_summary, str(choices.get("name", "")) if not str(choices.get("name", "")).is_empty() else tr("CC_UNNAMED"))
	var sub := CharacterBuilder.subrace(choices, d)
	lines.append("%s, %s" % [sub.get("name", r.get("name", "—")), k.get("name", "—")])
	var bg := CharacterBuilder.background(choices, d)
	if not bg.is_empty():
		lines.append(str(bg["name"]))
	for l: String in lines:
		_text(_summary, l, true)
	var final := CharacterBuilder.final_abilities(choices, d)
	for a: String in CharacterRules.ABILITIES:
		_text(_summary, "%s %d (%+d)" % [_ability_label(a), int(final[a]), CharacterRules.mod(int(final[a]))])
	if not CharacterBuilder.complete(choices, d):
		return
	var c := CharacterBuilder.build(choices, d)
	_summary.add_child(HSeparator.new())
	_text(_summary, tr("SIDE_HP_AC").format({"hp": c["hp"], "max": c["max_hp"], "ac": c["ac"]}))
	_text(_summary, tr("SHEET_PROF_SPEED").format({"prof": c["prof_bonus"], "speed": c["speed"]}), true)
	var skills: Array[String] = []
	for s: Variant in c["skill_profs"]:
		skills.append("%s %+d" % [_skill_label(str(s)), int(c["skills"][str(s)])])
	_text(_summary, ", ".join(skills), true)
	_text(_summary, tr("SIDE_COINS").format({"coins": Money.format(int(c["gold_cp"]))}), true)
