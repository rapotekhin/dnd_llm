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
## v0.8.4.43.3 (as in BG3, the author: «подсказка у курсора»): a panel made `floating` is no part of its column — it
## is a card at the cursor while the thing is hovered (beside a button that has the focus, as Tab's foe) and gone
## when the cursor leaves; the right button pins it where it stands, with the lock to let it go, its text then
## selectable and scrolled. A floating panel shows nothing for a hint without a body: the place goes to the chat.
## v0.8.4.43.15 (the author: «прямоугольником фиксированного размера с возможностью скроллить его вниз»; «щелчок правой
## кнопкой … будет блокировать окно описания»): a card is one width and at most `CARD_MAX_BODY` of text high — a longer
## text says that the right button pins it, and pinned it scrolls; `tip_card` is the same card for an icon's own tooltip;
## `pin_card` pins an icon's card in the one card of the screen for icons (`_pins`), the right button on it again or the
## lock lets it go, as on any card.

var _title: Label
var _body: RichTextLabel
var _lock: Button
var _pinned := ""  # the title of the pinned text ("" — nothing pinned): kept across a rebuild of the rows
var _pinned_body := ""
var _lit: Control
var _shown: Control  # whose text is up — the lock pins it
var floating := false  ## a card at the cursor, not a part of the column
var _anchor := Vector2.ZERO  # where the card stands: by the cursor, or beside the focused button
var _beside := false  # stands beside its thing (a focused button, Tab; a pin without the cursor on it), not by the cursor
var _left := false  # beside its thing on the left (a thing whose menu opens at the cursor)
var _more: Label  # «the right button pins it» under a text longer than the card
var _icons := false  # the screen's card for icons: shown pinned only, gone with its screen
var _screen: WeakRef  # the screen of the pinned icon

static var _pins: DetailsPanel  # the one card an icon is pinned in (`pin_card`)

const CARD_WIDTH := 380.0
const CARD_MAX_BODY := 280.0  # a longer text is cut at this height and scrolls inside a pinned card


func _init(min_size: Vector2 = Vector2(0, 180), at_cursor: bool = false) -> void:
	name = "DetailsPanel"
	theme_type_variation = UiTheme.SIDE
	custom_minimum_size = min_size
	floating = at_cursor
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
	_more = _more_label()
	col.add_child(_more)
	show_text(TranslationServer.translate("DETAILS_HINT"), "")
	_lock.visible = false  # the hint is nothing to pin
	if floating:
		theme_type_variation = UiTheme.CARD
		top_level = true  # no part of the column's layout: drawn over it where the cursor is
		z_index = 50
		visible = false
		custom_minimum_size = Vector2(CARD_WIDTH, 0)
		_body.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		_body.fit_content = true
		_body.scroll_active = false
		_body.custom_minimum_size = Vector2(CARD_WIDTH - 24, 0)
		_title.custom_minimum_size = Vector2(CARD_WIDTH - 140, 0)  # a wrapped title has a width before it is laid out
		_hold(false)


## A card follows only the eye: it takes no click until pinned (the cursor reaches what is under it).
func _hold(pinned_now: bool) -> void:
	for n: Node in [self] + find_children("*", "Control", true, false):
		(n as Control).mouse_filter = Control.MOUSE_FILTER_STOP if pinned_now and (n == _lock or n == _body or n == self) else Control.MOUSE_FILTER_IGNORE
	_body.selection_enabled = pinned_now
	_cap(pinned_now)
	_cap.call_deferred(pinned_now)  # the text's height is known once it is laid out


## One size of a card: a text longer than `CARD_MAX_BODY` is cut there — pinned it scrolls, else it says the right
## button pins it.
func _cap(pinned_now: bool) -> void:
	if not floating or not is_instance_valid(_body):
		return
	var long := _body.get_content_height() > CARD_MAX_BODY + 4
	_body.fit_content = not long
	_body.scroll_active = pinned_now and long
	_body.custom_minimum_size.y = CARD_MAX_BODY if long else 0.0
	_more.visible = long and not pinned_now
	if visible and is_inside_tree():
		_place()


## Where the card stands: by the cursor (down and right, turned back at the screen's edge), or beside the focused button.
func _place() -> void:
	var screen := get_viewport_rect().size
	var sz := get_combined_minimum_size()
	size = sz
	var at := _anchor + Vector2(20, 20)
	if _beside and _shown != null and is_instance_valid(_shown):
		var r := _shown.get_global_rect()
		at = Vector2(r.end.x + 8, r.position.y)
		if _left and r.position.x - sz.x - 8 >= 0.0 or at.x + sz.x > screen.x:
			at.x = r.position.x - sz.x - 8
	elif at.x + sz.x > screen.x:
		at.x = _anchor.x - sz.x - 12
	position = Vector2(clampf(at.x, 0.0, maxf(0.0, screen.x - sz.x)), clampf(at.y, 0.0, maxf(0.0, screen.y - sz.y - 4)))


func _process(_delta: float) -> void:
	if not floating or not visible:
		return
	if _icons and (_pinned.is_empty() or _screen == null or not is_instance_valid(_screen.get_ref()) or not (_screen.get_ref() as Node).is_inside_tree()):
		unpin()  # its screen is gone (a load, the menu): the card goes with it
		return
	if _pinned.is_empty() and not _still_wanted():
		visible = false
		return
	if _pinned.is_empty():
		_place()


## The card stays while its thing is hovered, or focused when it came by the focus.
func _still_wanted() -> bool:
	if _shown == null or not is_instance_valid(_shown) or not _shown.is_visible_in_tree():
		return false
	if _beside:
		return _shown.has_focus()
	var hovered := get_viewport().gui_get_hovered_control()
	return hovered != null and (hovered == _shown or _shown.is_ancestor_of(hovered))


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


## Shows a text unless another one is pinned; a floating card at what is hovered now, or beside the focused button.
func show_text(title: String, body: String) -> void:
	if not _pinned.is_empty():
		return
	_put(title, body)
	if floating:
		_float_up(body)


func _float_up(body: String) -> void:
	if body.is_empty() or not is_inside_tree():  # a hint: nothing at the cursor, the place is the chat's
		visible = false
		return
	var hovered := get_viewport().gui_get_hovered_control()
	var focused := get_viewport().gui_get_focus_owner()
	if _shown != null and is_instance_valid(_shown) and hovered != null and (hovered == _shown or _shown.is_ancestor_of(hovered)):
		_beside = false
	elif focused is BaseButton:
		_shown = focused
		_beside = true
	else:
		_shown = hovered
		_beside = false
	_anchor = get_viewport().get_mouse_position()
	visible = true
	_hold(false)
	_place()


func _put(title: String, body: String) -> void:
	_title.text = title
	_body.text = body
	_body.scroll_to_line(0)
	_lock.visible = not floating or not _pinned.is_empty()  # an unpinned card takes no click: the right button pins it
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
	if floating and is_inside_tree():
		if not visible:  # pinned straight away: by the cursor over its thing, else beside the thing
			var hovered := get_viewport().gui_get_hovered_control()
			_shown = control
			_beside = control != null and is_instance_valid(control) and not (hovered != null and (hovered == control or control.is_ancestor_of(hovered)))
			_anchor = get_viewport().get_mouse_position()
		visible = true
		_hold(true)
		_place()
		_place.call_deferred()  # the body's scroll is laid out a frame later


func unpin() -> void:
	_unlight()
	_pinned = ""
	_pinned_body = ""
	_lock.text = "DETAILS_PIN"
	_lock.tooltip_text = "DETAILS_PIN_TIP"
	if floating:
		_lock.visible = false
		_hold(false)
		visible = visible and _still_wanted() and not _icons


## Pins the card of an icon (the right button on an IconSlot, v0.8.4.43.15) in the one card of the screen for icons; on
## the same one again lets it go. `left` — beside the icon on its left, where a menu opened at the cursor leaves room.
static func pin_card(control: Control, title_text: String, body_text: String, left := false) -> void:
	if control == null or not control.is_inside_tree():
		return
	if _pins == null or not is_instance_valid(_pins):
		var layer := CanvasLayer.new()  # over every window
		layer.name = "PinnedCards"
		layer.layer = 90
		control.get_tree().root.add_child(layer)
		_pins = DetailsPanel.new(Vector2.ZERO, true)
		_pins.name = "PinnedCard"
		_pins._icons = true
		layer.add_child(_pins)
	if _pins._pinned == title_text and _pins._pinned_body == body_text:
		_pins.unpin()
		return
	var top: Node = control  # the screen it is on: the child of the scene's root
	var scene := control.get_tree().current_scene
	while top.get_parent() != null and top.get_parent() != scene and top.get_parent() != control.get_tree().root:
		top = top.get_parent()
	_pins._screen = weakref(top)
	_pins._left = left
	_pins.visible = false  # stands anew by this icon
	_pins.pin(control, title_text, body_text)
	if left:
		_pins._beside = true
		_pins._place()


## The pinned card of icons (a playtest looks at it), or null.
static func pinned_card() -> DetailsPanel:
	return _pins if _pins != null and is_instance_valid(_pins) and _pins.visible else null


## The card an icon shows at the cursor (IconSlot's tooltip, v0.8.4.43.15): the name on top, the act's line, the text —
## one width, a long text cut at `CARD_MAX_BODY` with «the right button pins it» under it.
static func tip_card(title_text: String, line: String, body_text: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "TipCard"
	panel.theme_type_variation = UiTheme.CARD
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	panel.add_child(col)
	var head := Label.new()
	head.name = "TipTitle"
	head.text = title_text
	head.theme_type_variation = UiTheme.ACCENT_LABEL
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.custom_minimum_size = Vector2(CARD_WIDTH - 24, 0)
	col.add_child(head)
	if line != "" and line != title_text:
		var l := Label.new()
		l.name = "TipLine"
		l.text = line
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(CARD_WIDTH - 24, 0)
		col.add_child(l)
	if body_text != "":
		var body := RichTextLabel.new()
		body.name = "TipText"
		body.bbcode_enabled = true
		body.fit_content = true
		body.scroll_active = false
		body.custom_minimum_size = Vector2(CARD_WIDTH - 24, 0)
		body.text = body_text
		body.add_theme_color_override("default_color", UiTheme.MUTED)
		col.add_child(body)
		var more := _more_label()
		col.add_child(more)
		var cut := func() -> void:
			body.fit_content = false
			body.custom_minimum_size.y = CARD_MAX_BODY
			more.visible = true
		# A tooltip takes its size when it comes up: the text's height by its font, before it is laid out …
		var font := body.get_theme_font("normal_font")
		var plain := RegEx.create_from_string("\\[[^\\]]*\\]").sub(body_text, "", true)
		if font != null and font.get_multiline_string_size(plain, HORIZONTAL_ALIGNMENT_LEFT, CARD_WIDTH - 24,
				body.get_theme_font_size("normal_font_size")).y > CARD_MAX_BODY:
			cut.call()
		body.resized.connect(func() -> void:  # … and once it is, should the font have told less
			if is_instance_valid(body) and body.fit_content and body.get_content_height() > CARD_MAX_BODY + 4:
				cut.call())
	return panel


static func _more_label() -> Label:
	var more := Label.new()
	more.name = "DetailsMore"
	more.text = TranslationServer.translate("DETAILS_MORE")
	more.visible = false
	more.add_theme_font_size_override("font_size", UiTheme.SIZE_SMALL)
	more.add_theme_color_override("font_color", UiTheme.ACCENT)
	return more


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
	if control is IconSlot:  # an icon tells what it is at the cursor (v0.8.4.43, as in BG3)
		(control as IconSlot).tip_title = title_text
		(control as IconSlot).tip_body = body_text
	var shown := func() -> void:
		if _pinned.is_empty():
			_shown = control
		show_text(title_text, body_text)
	if not (floating and control is IconSlot):  # an icon's own card is at the cursor already
		control.mouse_entered.connect(shown)
		if control is BaseButton:
			(control as BaseButton).pressed.connect(shown)
	if not floating:  # a card comes by the cursor, not by the keyboard's focus passing
		control.focus_entered.connect(shown)
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
	if SpellRules.by_master(data, id):
		lines.append(TranslationServer.translate("DETAILS_BY_MASTER"))
	var grown := SpellRules.at_slot(data, id, slot)  # v0.7.22.19: what the chosen slot gives
	if not grown.is_empty():
		lines.append(grown)
	return "\n".join(lines)


## A class feature or a race trait by id, or a resource of Stock (its first feature).
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
