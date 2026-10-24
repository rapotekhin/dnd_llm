class_name DetailsPanel
extends PanelContainer
## What the picked thing is (v0.7.7 fixes, the author: «a separate panel for the selected item, not stats on every
## row»): a title and the text in a box of a fixed size that scrolls inside — a long description never grows it.
## v0.7.22.21 (the author's fixes check #2–#5): the one description panel of every screen — at the top of the right
## column (`column`), above the chat; the text can be selected. The right mouse button pins what is under it: hovering
## others no longer changes the panel, the pinned control is lit; the right button on it again or the lock in the
## corner unpins, on another — pins that one.
## v0.7.22.23 (the UI audit П4): the lock pins too — it shows whenever a text is up and pins the one shown, so the
## right button can open acts elsewhere (the side panel's rows); on the rows of a description it still pins.

var _title: Label
var _body: RichTextLabel
var _lock: Button
var _pinned := ""  # the title of the pinned text ("" — nothing pinned): kept across a rebuild of the rows
var _pinned_body := ""
var _lit: Control
var _shown: Control  # whose text is up — the lock pins it


func _init(min_size: Vector2 = Vector2(0, 180)) -> void:
	name = "DetailsPanel"
	theme_type_variation = UiTheme.SIDE
	custom_minimum_size = min_size
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	_title = Label.new()
	_title.name = "DetailsTitle"
	_title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.add_theme_color_override("font_color", UiTheme.ACCENT)
	head.add_child(_title)
	_lock = Button.new()
	_lock.name = "DetailsUnpin"
	_lock.flat = true
	_lock.visible = false
	_lock.pressed.connect(_on_lock)
	head.add_child(_lock)
	_body = RichTextLabel.new()
	_body.name = "DetailsText"
	_body.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_body.selection_enabled = true
	_body.scroll_active = true
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.custom_minimum_size = Vector2(0, maxf(60.0, min_size.y - 60.0))
	_body.add_theme_color_override("default_color", UiTheme.MUTED)
	col.add_child(_body)
	show_text(TranslationServer.translate("DETAILS_HINT"), "")
	_lock.visible = false  # the hint is nothing to pin


## The right column of a screen: this panel on top (a third of the height), `lower` (the chat, a summary) below.
func column(lower: Control, width: int = 440) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.name = "DetailsColumn"
	col.custom_minimum_size = Vector2(width, 0)
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 12)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_stretch_ratio = 1.0
	col.add_child(self)
	if lower != null:
		var under := lower
		if not (lower is PanelContainer):  # a chat over an overlay needs its own ground
			under = PanelContainer.new()
			under.theme_type_variation = UiTheme.SIDE
			under.add_child(lower)
		under.size_flags_vertical = Control.SIZE_EXPAND_FILL
		under.size_flags_stretch_ratio = 2.0
		col.add_child(under)
	return col


## Shows a text unless another one is pinned.
func show_text(title: String, body: String) -> void:
	if not _pinned.is_empty():
		return
	_put(title, body)


func _put(title: String, body: String) -> void:
	_title.text = title
	_body.text = body
	_body.scroll_to_line(0)
	_lock.visible = true
	_lock.text = "DETAILS_UNPIN" if not _pinned.is_empty() else "DETAILS_PIN"
	_lock.tooltip_text = "DETAILS_UNPIN_TIP" if not _pinned.is_empty() else "DETAILS_PIN_TIP"


func _on_lock() -> void:
	if not _pinned.is_empty():
		unpin()
	else:
		pin(_shown, _title.text, _body.text)


func title() -> String:
	return _title.text


func body() -> String:
	return _body.text


func pinned() -> String:
	return _pinned


## Pins this text (the right button): it stays until unpinned, `control` is lit.
func pin(control: Control, title_text: String, body_text: String) -> void:
	_unlight()
	_pinned = title_text
	_pinned_body = body_text
	_put(title_text, body_text)
	_light(control)


func unpin() -> void:
	_unlight()
	_pinned = ""
	_pinned_body = ""
	_lock.text = "DETAILS_PIN"
	_lock.tooltip_text = "DETAILS_PIN_TIP"


func _light(control: Control) -> void:
	if control != null and is_instance_valid(control):
		_lit = control
		control.modulate = UiTheme.ACCENT_BRIGHT


func _unlight() -> void:
	if _lit != null and is_instance_valid(_lit):
		_lit.modulate = Color.WHITE
	_lit = null


## Shows this text when `control` is hovered, focused or pressed; the right button pins it (or unpins it again).
func hook(control: Control, title_text: String, body_text: String) -> void:
	if body_text.is_empty() and title_text.is_empty():
		return
	var shown := func() -> void:
		if _pinned.is_empty():
			_shown = control
		show_text(title_text, body_text)
	control.mouse_entered.connect(shown)
	control.focus_entered.connect(shown)
	if control is BaseButton:
		(control as BaseButton).pressed.connect(shown)
	control.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT:
			if _pinned == title_text and _pinned_body == body_text:
				unpin()
			else:
				pin(control, title_text, body_text)
			control.accept_event())
	if _pinned == title_text and _pinned_body == body_text:  # the rows were rebuilt: the pinned one is lit again
		_light(control)


# --- texts ----------------------------------------------------------------------------------------------------


static func item_text(c: Dictionary, data: Dictionary, session_items: Dictionary, id: String) -> String:
	var lines := ItemInfo.lines(c, data, session_items, id)
	var cmp := ItemInfo.compare(c, data, session_items, id)
	if not cmp.is_empty():
		lines.append(cmp)
	return "\n".join(lines)


static func spell_text(data: Dictionary, id: String, slot: int = 0) -> String:
	var s: Dictionary = data["spells"].get(id, {})
	if s.is_empty():
		return ""
	var lv := int(s.get("level", 0))
	var head: String = TranslationServer.translate("DETAILS_CANTRIP") if lv == 0 else TranslationServer.translate("DETAILS_CIRCLE").format({"n": lv})
	var school := str(s.get("school", ""))
	var lines: Array[String] = ["%s%s · %s · %s · %s%s" % [head, (" · " + school) if not school.is_empty() else "", s.get("casting_time", ""), s.get("range", ""),
		s.get("duration", ""), (" · " + TranslationServer.translate("DETAILS_CONCENTRATION")) if bool(s.get("concentration", false)) else ""]]
	if not str(s.get("desc", "")).is_empty():
		lines.append(str(s["desc"]))
	var grown := SpellRules.at_slot(data, id, slot)  # v0.7.22.19: what the chosen slot gives
	if not grown.is_empty():
		lines.append(grown)
	return "\n".join(lines)


## A class feature or a race trait by id, or a resource of FeatureUses (its first feature).
static func feature_text(data: Dictionary, id: String) -> String:
	for pool: Dictionary in [data["classes"]["features"], data["races"]["traits"]]:
		if pool.has(id):
			return str(pool[id].get("desc", ""))
	var res: Dictionary = data["rules"]["resources"].get(id, {})
	for f: Variant in res.get("features", []):
		var t := feature_text(data, str(f))
		if not t.is_empty():
			return t
	return ""
