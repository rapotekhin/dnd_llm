class_name SmallDialog
extends Control
## Small overlays of v0.6.0 over the game screen: the short rest (how many hit dice to spend) and the prepared
## spells of the day. Rules are ExplorationRules / SpellRules; the dialog only collects the choice.

const SHORT_REST := "short_rest"
const PREPARE := "prepare"

var kind: String
var picks: Array = []
var dice: SpinBox
var confirm: Button
var _box: VBoxContainer
var _error: Label


func _init(dialog_kind: String) -> void:
	kind = dialog_kind


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	var side := 360 if kind == SHORT_REST else 160
	for s in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + s, side)
	for s in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + s, 260 if kind == SHORT_REST else 100)
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	margin.add_child(col)
	var panel := PanelContainer.new()
	panel.theme_type_variation = UiTheme.SIDE
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override("separation", 10)
	scroll.add_child(_box)
	_error = Label.new()
	_error.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_error.add_theme_color_override("font_color", UiTheme.WARN)
	col.add_child(_error)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	col.add_child(buttons)
	var close := Button.new()
	close.text = "BTN_CANCEL"
	close.custom_minimum_size = Vector2(0, 56)
	close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close.pressed.connect(func() -> void: visible = false)
	buttons.add_child(close)
	confirm = Button.new()
	confirm.name = "DialogConfirm"
	confirm.text = "BTN_REST_CONFIRM" if kind == SHORT_REST else "BTN_PREP_CONFIRM"
	confirm.theme_type_variation = UiTheme.ACCENT_BUTTON
	confirm.custom_minimum_size = Vector2(0, 56)
	confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	confirm.pressed.connect(_on_confirm)
	buttons.add_child(confirm)
	visibility_changed.connect(func() -> void:
		if visible:
			picks = []
			_error.text = ""
			if kind == PREPARE and GameState.has_session():
				picks = (GameState.session.character.get("spells", {}).get("prepared", []) as Array).duplicate()
		_rebuild())


func open() -> void:
	visible = true


func _text(text: String, variation: String = "") -> Label:
	var l := Label.new()
	l.text = text
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not variation.is_empty():
		l.theme_type_variation = variation
	_box.add_child(l)
	return l


func _rebuild() -> void:
	if not visible or not GameState.has_session():
		return
	for ch in _box.get_children():
		_box.remove_child(ch)
		ch.queue_free()
	var s := GameState.session
	var c := s.character
	var data := Catalog.data
	if kind == SHORT_REST:
		_text(tr("SHORT_REST_TITLE"), UiTheme.HEADING)
		_text(tr("SIDE_HP_AC").format({"hp": c["hp"], "max": c["max_hp"], "ac": c["ac"]}))
		var left := ExplorationRules.hit_dice_left(c)
		_text(tr("SHORT_REST_DICE").format({"die": int(CharacterRules.class_def(c, data).get("hit_die", 8)), "left": left}))
		dice = SpinBox.new()
		dice.name = "HitDice"
		dice.min_value = 0
		dice.max_value = left
		dice.value = mini(left, 1) if int(c["hp"]) < int(c["max_hp"]) else 0
		_box.add_child(dice)
		_text(tr("SHORT_REST_UNTIL").format({"clock": TimeRules.clock_after(s, int(TimeRules.cfg(data)["short_rest_minutes"]))}))
		_text(tr("SHORT_REST_HINT").format({"left": int(data["rules"]["rest"]["short_rests_per_day"]) - s.short_rests}), UiTheme.MUTED_LABEL)
		confirm.disabled = GameState.is_busy()
		return
	var p := SpellRules.prepare_pool(c, data)
	var n := mini(int(p["count"]), (p["pool"] as Array).size())
	picks = picks.filter(func(id: Variant) -> bool: return (p["pool"] as Array).has(id))
	_text(tr("PREP_TITLE").format({"n": n}), UiTheme.HEADING)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 16)
	_box.add_child(flow)
	for id: Variant in p["pool"]:
		var sp: Dictionary = data["spells"].get(str(id), {})
		var cb := CheckBox.new()
		cb.name = "Prep_" + str(id)
		cb.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		cb.text = "%s (%d)" % [sp.get("name", id), int(sp.get("level", 1))]
		cb.tooltip_text = str(sp.get("desc", "")).left(600)
		cb.button_pressed = picks.has(id)
		cb.toggled.connect(func(on: bool) -> void:
			if on and not picks.has(id) and picks.size() < n:
				picks.append(id)
			elif not on:
				picks.erase(id)
			_rebuild.call_deferred())
		flow.add_child(cb)
	var err := SpellRules.prepare_error(c, data, s.day, picks)
	_error.text = tr(err) if not err.is_empty() and picks.size() == n else ""
	confirm.disabled = not err.is_empty() or GameState.is_busy()


func _on_confirm() -> void:
	var err := GameState.short_rest(int(dice.value)) if kind == SHORT_REST else GameState.prepare_spells(picks)
	if err.is_empty():
		visible = false
	else:
		_error.text = tr(err)
