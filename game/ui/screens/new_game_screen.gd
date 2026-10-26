class_name NewGameScreen
extends Control
## New game (ADR-0010 §1, §3, §5): the world pack, the master's style, the death mode and the content limits.
## Defaults come from the picked pack; «Далее» activates the pack and opens character creation.

var settings: Dictionary = {}

var _worlds: VBoxContainer
var _form: VBoxContainer


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
	title.text = "NG_TITLE"
	title.theme_type_variation = UiTheme.HEADING
	col.add_child(title)
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 24)
	col.add_child(row)
	var left := PanelContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left)
	var lscroll := ScrollContainer.new()
	lscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(lscroll)
	_worlds = VBoxContainer.new()
	_worlds.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_worlds.add_theme_constant_override("separation", 12)
	lscroll.add_child(_worlds)
	var right := PanelContainer.new()
	right.theme_type_variation = UiTheme.SIDE
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	var rscroll := ScrollContainer.new()
	rscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(rscroll)
	_form = VBoxContainer.new()
	_form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_form.add_theme_constant_override("separation", 10)
	rscroll.add_child(_form)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 16)
	col.add_child(bottom)
	var back := Button.new()
	back.text = "BTN_TO_MENU"
	back.custom_minimum_size = Vector2(0, 56)
	back.pressed.connect(func() -> void: EventBus.navigate.emit("menu", {}))
	bottom.add_child(back)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(spacer)
	var next := Button.new()
	next.name = "NextButton"
	next.text = "CC_NEXT"
	next.theme_type_variation = UiTheme.ACCENT_BUTTON
	next.custom_minimum_size = Vector2(200, 56)
	next.pressed.connect(_next)
	bottom.add_child(next)

	var playable := Catalog.playable()
	if not playable.is_empty():
		_pick_world(str(Catalog.active_world if not Catalog.bundle(Catalog.active_world).is_empty() else playable[0]["id"]))
	else:
		_redraw()
		next.disabled = true


func _pick_world(id: String) -> void:
	settings = WorldPack.default_settings(Catalog.bundle(id)["pack"])
	_redraw()


func _next() -> void:
	if not Catalog.activate(str(settings.get("world", ""))):
		return
	EventBus.navigate.emit("creation", {"settings": settings})


func _redraw() -> void:
	for box: Control in [_worlds, _form]:
		for c in box.get_children():
			box.remove_child(c)
			c.queue_free()
	_label(_worlds, "NG_WORLD", UiTheme.MUTED_LABEL)
	for b: Dictionary in Catalog.bundles:
		var p: Dictionary = b["pack"]
		var ok: bool = b["errors"].is_empty()
		var btn := Button.new()
		btn.name = "World_" + str(b["id"])
		btn.toggle_mode = true
		btn.button_pressed = str(settings.get("world", "")) == str(b["id"])
		btn.disabled = not ok
		btn.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		btn.text = str(p.get("name", b["id"])) + ("" if b["source"] == "builtin" else "  " + tr("NG_MOD"))
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(0, 56)
		btn.pressed.connect(_pick_world.bind(str(b["id"])))
		_worlds.add_child(btn)
		if ok:
			_text(_worlds, str(p.get("description", "")), true)
		else:
			var err := _text(_worlds, tr("NG_PACK_BROKEN").format({"errors": "; ".join(b["errors"].slice(0, 3))}), true)
			err.add_theme_color_override("font_color", UiTheme.BAD)
	if settings.is_empty():
		return
	var pack: Dictionary = Catalog.bundle(str(settings["world"]))["pack"]
	_label(_form, str(pack.get("name", "")), UiTheme.HEADING)
	_text(_form, tr("NG_TONE").format({"tone": pack.get("tone", ""), "magic": pack.get("magic", "")}), true)

	_label(_form, "NG_DM_STYLE", UiTheme.MUTED_LABEL)
	_choice(_form, "dm_style", WorldPack.DM_STYLES, "DM_STYLE_")
	_text(_form, tr("DM_STYLE_%s_HINT" % str(settings["dm_style"]).to_upper()), true)

	_label(_form, "NG_DIFFICULTY", UiTheme.MUTED_LABEL)
	_choice(_form, "difficulty", DifficultyRules.levels(Catalog.data), "DIFFICULTY_")
	_text(_form, tr("DIFFICULTY_%s_HINT" % str(settings.get("difficulty", "normal")).to_upper()), true)

	# «Одна жизнь» comes with the roguelike loop (M5): until then every game is «История» (v0.7.7).

	var needs := CheckButton.new()  # v0.7.23: hunger, thirst, sleep
	needs.name = "NeedsToggle"
	needs.text = "NG_NEEDS"
	needs.button_pressed = bool(settings.get("needs", true))
	needs.toggled.connect(func(on: bool) -> void: settings["needs"] = on)
	_form.add_child(needs)
	_text(_form, tr("NG_NEEDS_HINT"), true)

	var slaves := CheckButton.new()  # v0.7.27: a hard world, off by default
	slaves.name = "SlaveryToggle"
	slaves.text = "NG_SLAVERY"
	slaves.button_pressed = bool(settings.get("slavery", false))
	slaves.toggled.connect(func(on: bool) -> void: settings["slavery"] = on)
	_form.add_child(slaves)
	_text(_form, tr("NG_SLAVERY_HINT"), true)

	_label(_form, "NG_VIOLENCE", UiTheme.MUTED_LABEL)
	_choice(_form, "violence", WorldPack.VIOLENCE, "VIOLENCE_")
	_list_field(_form, "lines", "NG_LINES")
	_list_field(_form, "veils", "NG_VEILS")
	_list_field(_form, "wishes", "NG_WISHES")


func _label(parent: Control, text: String, variation: String) -> void:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = variation
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)


func _text(parent: Control, text: String, muted: bool) -> Label:
	var l := Label.new()
	l.text = text
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if muted:
		l.theme_type_variation = UiTheme.MUTED_LABEL
	parent.add_child(l)
	return l


func _choice(parent: Control, key: String, values: Array, prefix: String) -> void:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 10)
	row.add_theme_constant_override("v_separation", 10)
	parent.add_child(row)
	for v: Variant in values:
		var b := Button.new()
		b.name = "%s_%s" % [key, v]
		b.text = prefix + str(v).to_upper()
		b.toggle_mode = true
		b.button_pressed = str(settings.get(key, "")) == str(v)
		b.custom_minimum_size = Vector2(160, 48)
		b.pressed.connect(func() -> void:
			settings[key] = v
			_redraw())
		row.add_child(b)


## Lines, veils and wishes as comma-separated text.
func _list_field(parent: Control, key: String, label_key: String) -> void:
	_label(parent, label_key, UiTheme.MUTED_LABEL)
	var edit := LineEdit.new()
	edit.name = "Edit_" + key
	edit.text = ", ".join(settings.get(key, []))
	edit.placeholder_text = "NG_%s_PLACEHOLDER" % key.to_upper()
	edit.custom_minimum_size = Vector2(0, 52)
	edit.text_changed.connect(func(t: String) -> void:
		var items: Array = []
		for part in t.split(","):
			if not part.strip_edges().is_empty():
				items.append(part.strip_edges())
		settings[key] = items)
	parent.add_child(edit)
