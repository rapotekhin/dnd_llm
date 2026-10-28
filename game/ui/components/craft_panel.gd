class_name CraftPanel
extends Control
## The craft window (roadmap v0.7.24): the work in hand with its progress and the shifts, the recipes the hero knows —
## the tool, the station, the time, the DC and the chance, the materials had and needed — and the things that can be
## broken into materials. Every act is GameState.craft_act: the engine passes the time, no master turn.

var _box: VBoxContainer
var frame: ModalFrame


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame = ModalFrame.new(tr("CRAFT_TITLE"), 900.0)
	add_child(frame)
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.close_requested.connect(func() -> void: visible = false)
	frame.close_x.name = "CloseCraftButton"
	_box = frame.body
	EventBus.state_changed.connect(_rebuild)
	visibility_changed.connect(_rebuild)


func open() -> void:
	visible = true
	_rebuild()


func _label(parent: Control, text: String, variation: String = "") -> Label:
	var l := Label.new()
	l.text = text
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not variation.is_empty():
		l.theme_type_variation = variation
	parent.add_child(l)
	return l


func _button(parent: Control, node_name: String, text: String, why: String, action: Callable) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.disabled = not why.is_empty() or GameState.is_busy()
	b.tooltip_text = tr(why) if not why.is_empty() else ""
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(func() -> void:
		var err: String = action.call()
		if not err.is_empty():
			EventBus.message.emit(tr(err)))
	parent.add_child(b)
	return b


func _heading(text: String) -> void:
	var l := _label(_box, text)
	l.add_theme_color_override("font_color", UiTheme.ACCENT)


func _rebuild() -> void:
	if not visible or not GameState.has_session():
		return
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	var s := GameState.session
	var data := Catalog.data
	_project(s, data)
	_recipes(s, data)
	_salvage(s, data)


func _project(s: GameSession, data: Dictionary) -> void:
	var p := CraftRules.project(s.character)
	if p.is_empty():
		return
	_heading(tr("CRAFT_IN_HAND"))
	var r := CraftRules.recipe(s, data, str(p["recipe"]))
	_label(_box, "%s — %d%%, %s" % [CraftRules.recipe_name(s, data, str(p["recipe"])), CraftRules.progress(s.character),
		tr("CRAFT_LEFT").format({"time": TimeRules.span(int(p["total"]) - int(p["done"]))})])
	var bar := ProgressBar.new()
	bar.name = "CraftProgress"
	bar.max_value = 100.0
	bar.value = CraftRules.progress(s.character)
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 8)
	bar.add_theme_stylebox_override("fill", UiTheme.box(UiTheme.ACCENT, UiTheme.ACCENT, 0, 0, 2))
	bar.add_theme_stylebox_override("background", UiTheme.box(UiTheme.BG, UiTheme.BORDER, 1, 0, 2))
	_box.add_child(bar)
	var why := CraftRules.can_work(s, data)
	var rent := CraftRules.rent(s, data, str(r.get("station", "")))
	var meta: Array[String] = [_where(s, data, r)]
	if not rent.is_empty():
		meta.append(tr("CRAFT_RENT").format({"cp": Money.format(int(rent["cp"])), "who": GameState.world().npc(str(rent["npc"])).get("name", "")}))
	_label(_box, " · ".join(meta), UiTheme.MUTED_LABEL)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_box.add_child(row)
	var hours: Array = CraftRules.cfg(data)["work_hours"]
	for h: Variant in hours:
		var mins := CraftRules.shift_minutes(s, data, int(h))
		var text := tr("BTN_CRAFT_SHIFT").format({"time": TimeRules.span(mins)}) if mins > 0 else tr("BTN_CRAFT_SHIFT").format({"time": "—"})
		_button(row, "CraftWork_%d" % int(h), text, why if not why.is_empty() else ("" if mins > 0 else "CRAFT_NO_RENT"),
			GameState.craft_act.bind("work", "", int(h)))
	var drop := _button(row, "CraftAbandon", tr("BTN_CRAFT_ABANDON"), "", func() -> String:
		ConfirmBox.ask(self, tr("CONFIRM_CRAFT_ABANDON_TITLE"), tr("CONFIRM_CRAFT_ABANDON"), tr("BTN_CRAFT_ABANDON"),
			func() -> void: GameState.craft_act("abandon"))
		return "")
	drop.add_theme_color_override("font_color", UiTheme.BAD)
	_box.add_child(HSeparator.new())


func _where(s: GameSession, data: Dictionary, r: Dictionary) -> String:
	var tool := BackgroundRules.tool_name(data, CraftRules.tool_of(r)) if CraftRules.needs_tool(r) 		else tr("CRAFT_CHECK_SKILL").format({"skill": CraftRules.check_label(data, r)})
	var parts: Array[String] = [tr("CRAFT_SIMPLE") if CraftRules.simple(r) else tool]
	if not str(r.get("station", "")).is_empty():
		parts.append(CraftRules.station_name(data, str(r["station"])) + ("" if CraftRules.station_here(s, data, str(r["station"])) else " — " + tr("CRAFT_NOT_HERE")))
	return " · ".join(parts)


func _recipes(s: GameSession, data: Dictionary) -> void:
	var ids := CraftRules.known(s, data)
	_heading(tr("CRAFT_RECIPES"))
	if ids.is_empty():
		_label(_box, tr("CRAFT_NO_RECIPES"), UiTheme.MUTED_LABEL)
		return
	for id: String in ids:
		var r := CraftRules.recipe(s, data, id)
		var row := HBoxContainer.new()
		row.name = "Recipe_" + id.validate_node_name()  # a template id has «:»
		row.add_theme_constant_override("separation", 10)
		_box.add_child(row)
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 2)
		row.add_child(col)
		var qty := int(r.get("qty", 1))
		_label(col, CraftRules.recipe_name(s, data, id) + (" ×%d" % qty if qty > 1 else ""))
		var out_def := ItemRules.def_of(data["items"], s.items, str(r["output"]))
		var kind := ItemInfo.kind_line(data, out_def)
		var meta: Array[String] = [_where(s, data, r), TimeRules.span(CraftRules.work_minutes(s.character, data, r)),
			tr("CRAFT_DC").format({"dc": int(r.get("dc", 10)), "chance": CraftRules.chance(s, data, id)})]
		if not kind.is_empty():
			meta.push_front(kind)
		_label(col, " · ".join(meta), UiTheme.MUTED_LABEL)
		var mats: Array[String] = []
		var inv: Dictionary = s.character.get("inventory", {})
		for m: String in r.get("materials", {}):
			mats.append("%s %d/%d" % [ItemRules.display_name(data["items"], s.items, m), int(inv.get(m, 0)), int(r["materials"][m])])
		var ml := _label(col, tr("CRAFT_MATERIALS").format({"list": ", ".join(mats)}), UiTheme.MUTED_LABEL)
		if not CraftRules.missing(s, r).is_empty():
			ml.add_theme_color_override("font_color", UiTheme.WARN)
		var lacks := CraftRules.skills_missing(s.character, data, r)
		if not lacks.is_empty():
			_label(col, tr("CRAFT_NEEDS_SKILLS").format({"list": ", ".join(lacks)}), UiTheme.MUTED_LABEL).add_theme_color_override("font_color", UiTheme.WARN)
		_button(row, "CraftStart_" + id.validate_node_name(), tr("BTN_CRAFT_START"), CraftRules.why_not(s, data, id), GameState.craft_act.bind("start", id, 1))


func _salvage(s: GameSession, data: Dictionary) -> void:
	var ids := CraftRules.salvageable(s, data)
	if ids.is_empty():
		return
	_box.add_child(HSeparator.new())
	_heading(tr("CRAFT_SALVAGE"))
	_label(_box, tr("CRAFT_SALVAGE_HINT").format({"time": TimeRules.span(int(CraftRules.cfg(data)["salvage"]["minutes"]))}), UiTheme.MUTED_LABEL)
	for id: String in ids:
		var got := CraftRules.salvage_yield(s, data, id)
		var parts: Array[String] = []
		for m: String in got:
			parts.append("%s ×%d" % [ItemRules.display_name(data["items"], s.items, m), int(got[m])])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		_box.add_child(row)
		var n := int(s.character["inventory"].get(id, 1))
		_label(row, "%s%s → %s" % [ItemRules.display_name(data["items"], s.items, id), " (%d)" % n if n > 1 else "", ", ".join(parts)])
		var name := ItemRules.display_name(data["items"], s.items, id)
		_button(row, "Salvage_" + id, tr("BTN_SALVAGE"), "", func() -> String:
			ConfirmBox.ask(self, tr("CONFIRM_SALVAGE_TITLE").format({"name": name}), tr("CONFIRM_SALVAGE"), tr("BTN_SALVAGE"),
				func() -> void:
					var err := GameState.craft_act("salvage", id)
					if not err.is_empty():
						EventBus.message.emit(tr(err)))
			return "")
