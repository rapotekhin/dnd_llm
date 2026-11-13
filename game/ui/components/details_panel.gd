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
## v0.8.4.43.33 (the author, as in BG3): a card of a spell, a feature, a thing or an act is drawn from its data (`CardInfo`):
## the name and what it is under it, its icon in the corner, the headline number with its dice by damage type, what it lays
## with the icon of the condition, the description, how it works (duration, range, area, attack or save, concentration)
## and a band at the bottom with what it takes (● an action, ▲ a bonus action, ◆ a reaction, ■ a slot) and a thing's
## weight and price. A text without a card is drawn as before, with the icon of its cell when it has one.

var _title: Label
var _sub: Label  # what it is, under the name: «Заклинание 1 круга · Воплощение»
var _icon: TextureRect
var _foot: VBoxContainer  # the band of what it takes, rebuilt with each card
var _card := {}  # the card shown now ({} — a plain text)
var _look := {}  # the icon of what is shown (IconRules.of), {} — none
var _plain := ""  # the plain text shown now: the pin's identity
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
var _moved := false  # a pinned card the player dragged stands where it was put
var _drag := Vector2(-1, -1)  # the grip of a drag (the cursor on the card), (-1, -1) — none

static var _pins: DetailsPanel  # the one card an icon is pinned in (`pin_card`)
static var _held: WeakRef  # the one floating card pinned now, of any screen (the author, 2026-11-13: «если я закрепил одну
# панель осмотра — вторая не должна появляться при наведении»)

const CARD_WIDTH := 460.0
const CARD_MAX_BODY := 340.0  # a longer text is cut at this height and scrolls inside a pinned card
const CARD_ICON := 72.0  # the icon in the corner of a card, as in BG3
const BIG_SIZE := 30  # the headline number
## The colours of a cost's glyph, as the counters over the hotbar.
const COST_COLORS := {"action": "8fb36f", "bonus": "d1a14a", "reaction": "b98fd8", "slot": "6f9fc8", "free": "9a8f7e", "time": "c9a45c", "move": "e6c47e"}


func _init(min_size: Vector2 = Vector2(0, 180), at_cursor: bool = false) -> void:
	name = "DetailsPanel"
	theme_type_variation = UiTheme.SIDE
	custom_minimum_size = min_size
	floating = at_cursor
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	col.add_child(head)
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.add_theme_constant_override("separation", 0)
	head.add_child(names)
	_title = Label.new()
	_title.name = "DetailsTitle"
	_title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.add_theme_color_override("font_color", UiTheme.ACCENT)
	names.add_child(_title)
	_sub = _sub_label("")
	_sub.name = "DetailsSub"
	names.add_child(_sub)
	_icon = _icon_rect({})
	_icon.name = "DetailsIcon"
	_lock = Button.new()
	_lock.name = "DetailsUnpin"
	_lock.flat = true
	_lock.visible = false
	_lock.pressed.connect(_on_lock)
	head.add_child(_lock)
	head.add_child(_icon)
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
	_foot = VBoxContainer.new()
	_foot.name = "DetailsFoot"
	col.add_child(_foot)
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
		_title.custom_minimum_size = Vector2(CARD_WIDTH - 140 - CARD_ICON, 0)  # a wrapped title has a width before it is laid out
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


## Where the card stands: by the cursor (down and right, turned back at the screen's edge), or beside the focused button;
## one the player dragged — where it was put, kept on the screen.
func _place() -> void:
	var screen := get_viewport_rect().size
	var sz := get_combined_minimum_size()
	size = sz
	if _moved:
		position = Vector2(clampf(position.x, 0.0, maxf(0.0, screen.x - sz.x)), clampf(position.y, 0.0, maxf(0.0, screen.y - sz.y)))
		return
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
	if _pinned.is_empty() or not size.is_equal_approx(get_combined_minimum_size()):  # a pinned one too, once its lines settle
		_place()


## While a card is pinned the right button anywhere lets it go — on the card, on its thing, past it (the author, 2026-11-13:
## «щелчок правой кнопкой вне закреплённой зоны так же должен откреплять», «второй щелчок правой кнопкой … должен»).
func _input(ev: InputEvent) -> void:
	var mb := ev as InputEventMouseButton
	if floating and visible and not _pinned.is_empty() and mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
		unpin()
		get_viewport().set_input_as_handled()


## A pinned card is dragged by the left button (the author, 2026-11-13: «двигать окно описания, если зажмём левую кнопку»);
## its text is still selected on the text itself.
func _gui_input(ev: InputEvent) -> void:
	if not floating or _pinned.is_empty():
		return
	var mb := ev as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		_drag = get_global_mouse_position() - position if mb.pressed else Vector2(-1, -1)
		accept_event()
	elif ev is InputEventMouseMotion and _drag.x >= 0.0 and (Input.get_mouse_button_mask() & MOUSE_BUTTON_MASK_LEFT) != 0:
		position = get_global_mouse_position() - _drag
		_moved = true
		_place()
		accept_event()


## A floating card is pinned now: no other card comes up at the cursor until it is let go.
static func holding() -> bool:
	var held: DetailsPanel = _held.get_ref() if _held != null else null
	return held != null and is_instance_valid(held) and held.is_inside_tree() and held.visible and not held._pinned.is_empty()


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
## `card` — a card of `CardInfo` drawn instead of the bare text, `look` — the icon (IconRules.of), by the card's own when {}.
func show_text(title: String, body: String, card: Dictionary = {}, look: Dictionary = {}) -> void:
	if not _pinned.is_empty() or (floating and holding()):
		return
	_put(title, body, card, look)
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


func _put(title: String, body: String, card: Dictionary = {}, look: Dictionary = {}) -> void:
	_title.text = title
	_plain = body
	_card = card
	_look = look if not look.is_empty() else look_of(card)
	_body.bbcode_enabled = not card.is_empty()
	_body.text = card_text(card) if not card.is_empty() else body
	_body.scroll_to_line(0)
	_sub.text = str(card.get("sub", ""))
	_sub.visible = not _sub.text.is_empty()
	_title.add_theme_color_override("font_color", Color(str(card["title_color"])) if str(card.get("title_color", "")) != "" else UiTheme.ACCENT)
	_set_icon(_icon, _look)
	for n: Node in _foot.get_children():
		_foot.remove_child(n)
		n.queue_free()
	var band := _foot_band(card)
	if band != null:
		_foot.add_child(band)
	_lock.visible = not floating or not _pinned.is_empty()  # an unpinned card takes no click: the right button pins it
	_lock.text = "DETAILS_UNPIN" if not _pinned.is_empty() else "DETAILS_PIN"
	_lock.tooltip_text = "DETAILS_UNPIN_TIP" if not _pinned.is_empty() else "DETAILS_PIN_TIP"


func _on_lock() -> void:
	if not _pinned.is_empty():
		unpin()
	else:
		pin(_shown, _title.text, _plain, _card, _look)


func title() -> String:
	return _title.text


## The plain text shown: a card's own words (`CardInfo.plain`) when a card is up.
func body() -> String:
	return _plain


func pinned() -> String:
	return _pinned


## Pins this text (the right button): it stays until unpinned, `control` is lit.
func pin(control: Control, title_text: String, body_text: String, card: Dictionary = {}, look: Dictionary = {}) -> void:
	_unlight()
	if floating:  # one card pinned on the screen: another one pinned lets it go
		var held: DetailsPanel = _held.get_ref() if _held != null else null
		if held != null and held != self and is_instance_valid(held) and not held._pinned.is_empty():
			held.unpin()
		_held = weakref(self)
		_moved = false
	_pinned = title_text
	_pinned_body = body_text
	_put(title_text, body_text, card, look)
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
	_moved = false
	_drag = Vector2(-1, -1)
	_lock.text = "DETAILS_PIN"
	_lock.tooltip_text = "DETAILS_PIN_TIP"
	if floating:
		_lock.visible = false
		_hold(false)
		visible = visible and _still_wanted() and not _icons


## Pins the card of an icon (the right button on an IconSlot, v0.8.4.43.15) in the one card of the screen for icons; on
## the same one again lets it go. `left` — beside the icon on its left, where a menu opened at the cursor leaves room.
static func pin_card(control: Control, title_text: String, body_text: String, left := false, card: Dictionary = {}, look: Dictionary = {}) -> void:
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
	_pins.pin(control, title_text, body_text, card, look)
	if left:
		_pins._beside = true
		_pins._place()


## The pinned card of icons (a playtest looks at it), or null.
static func pinned_card() -> DetailsPanel:
	return _pins if _pins != null and is_instance_valid(_pins) and _pins.visible else null


## The card an icon shows at the cursor (IconSlot's tooltip, v0.8.4.43.15): the name on top, the act's line, the text —
## one width, a long text cut at `CARD_MAX_BODY` with «the right button pins it» under it. With a `card` of `CardInfo`
## (v0.8.4.43.33) its body is the card's, the icon in the corner (`look`, else the card's own), the band of what it takes.
static func tip_card(title_text: String, line: String, body_text: String, card: Dictionary = {}, look: Dictionary = {}) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "TipCard"
	panel.theme_type_variation = UiTheme.CARD
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)
	var icon := look if not look.is_empty() else look_of(card)
	var head := HBoxContainer.new()
	head.name = "TipHead"
	head.add_theme_constant_override("separation", 10)
	col.add_child(head)
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.add_theme_constant_override("separation", 0)
	head.add_child(names)
	var title := Label.new()
	title.name = "TipTitle"
	title.text = title_text
	title.theme_type_variation = UiTheme.ACCENT_LABEL
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", UiTheme.SIZE_BODY)
	if str(card.get("title_color", "")) != "":
		title.add_theme_color_override("font_color", Color(str(card["title_color"])))
	var with_icon := not icon.is_empty() and IconSlot.texture(str(icon.get("path", ""))) != null
	title.custom_minimum_size = Vector2(CARD_WIDTH - 24 - (CARD_ICON + 10 if with_icon else 0.0), 0)
	names.add_child(title)
	if str(card.get("sub", "")) != "":
		names.add_child(_sub_label(str(card["sub"])))
	if with_icon:
		var rect := _icon_rect(icon)
		rect.name = "TipIcon"
		head.add_child(rect)
	if line != "" and line != title_text:
		var l := Label.new()
		l.name = "TipLine"
		l.text = line
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(CARD_WIDTH - 24, 0)
		col.add_child(l)
	var shown := card_text(card) if not card.is_empty() else body_text
	if shown != "":
		var body := RichTextLabel.new()
		body.name = "TipText"
		body.bbcode_enabled = true
		body.fit_content = true
		body.scroll_active = false
		body.custom_minimum_size = Vector2(CARD_WIDTH - 24, 0)
		body.text = shown
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
		var plain := CardInfo.plain(card) if not card.is_empty() else RegEx.create_from_string("\\[[^\\]]*\\]").sub(body_text, "", true)
		if font != null and font.get_multiline_string_size(plain, HORIZONTAL_ALIGNMENT_LEFT, CARD_WIDTH - 24,
				body.get_theme_font_size("normal_font_size")).y > CARD_MAX_BODY:
			cut.call()
		body.resized.connect(func() -> void:  # … and once it is, should the font have told less
			if is_instance_valid(body) and body.fit_content and body.get_content_height() > CARD_MAX_BODY + 4:
				cut.call())
	var band := _foot_band(card)
	if band != null:
		col.add_child(band)
	# The tooltip's window takes the size of the card's first layout, when the text had no width yet and stood a word a
	# line, and does not shrink by itself: it is made the card's size each time the card's own changes (the author,
	# 2026-11-13: «окно информации сильно больше написанного в нём текста»).
	panel.minimum_size_changed.connect(func() -> void: _fit_window(panel))
	panel.tree_entered.connect(func() -> void: (func() -> void: _fit_window(panel)).call_deferred())
	return panel


## The window a tooltip card stands in, the card's own size and its frame.
static func _fit_window(panel: Control) -> void:
	if not is_instance_valid(panel) or not panel.is_inside_tree():
		return
	var w := panel.get_window()
	if w == null or w == panel.get_tree().root:
		return
	var frame := (Vector2(w.size) - panel.size).max(Vector2.ZERO)
	var want := Vector2i((panel.get_combined_minimum_size() + frame).ceil())
	if want != w.size:
		w.size = want
		panel.size = panel.get_combined_minimum_size()


## The body of a card in BBCode: the headline number, its dice by damage type, what it lays with the condition's icon,
## how it works, the description, the notes.
static func card_text(card: Dictionary) -> String:
	var t: Array[String] = []
	var text := UiTheme.TEXT.to_html(false)
	var muted := UiTheme.MUTED.to_html(false)
	if str(card.get("big", "")) != "":
		t.append("[font_size=%d][color=#%s]%s[/color][/font_size]" % [BIG_SIZE, text, _esc(str(card["big"]))])
	for d: Dictionary in card.get("dice", []):
		var hue := str(d.get("color", "")).trim_prefix("#")
		var col := UiTheme.OK.to_html(false) if bool(d.get("heal", false)) else (hue if hue != "" else muted)
		t.append("[color=#%s]%s[/color]  [color=#%s]%s%s[/color]" % [text, _esc(str(d["text"])), col, "◆ " if hue != "" else "", _esc(str(d.get("type", "")))])
	for st: Dictionary in card.get("status", []):
		var path := str(look_of({"icon": st["icon"]}).get("path", ""))
		t.append(("[img=28x28]%s[/img] " % path if path != "" else "") + "[color=#%s]%s[/color]" % [text, _esc(str(st["text"]))])
	if not (card.get("props", []) as Array).is_empty():  # before the text: a long one is cut, how it works stays in sight
		var props: Array[String] = []
		for p: Variant in card["props"]:  # a glyph never left at a line's end without its words
			var one := str(p)
			var gap := one.find(" ")
			props.append(one.substr(0, gap) + "\u00a0" + one.substr(gap + 1) if gap > 0 and gap <= 2 else one)
		t.append("[color=#%s]%s[/color]" % [UiTheme.ACCENT.to_html(false), _esc("     ".join(props))])
	if str(card.get("desc", "")) != "":
		if not t.is_empty():
			t.append("")
		t.append("[color=#%s]%s[/color]" % [text, _esc(str(card["desc"]))])
	for n: Variant in card.get("notes", []):
		t.append("[color=#%s]%s[/color]" % [muted, _esc(str(n))])
	return "\n".join(t)


## The band at the bottom of a card: what it takes, glyph by glyph, and a thing's weight and price on the right; null — none.
static func _foot_band(card: Dictionary) -> PanelContainer:
	var costs: Array = card.get("cost", [])
	var foot: Array = card.get("foot", [])
	if costs.is_empty() and foot.is_empty():
		return null
	var band := PanelContainer.new()
	band.name = "CardFoot"
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, 0.35)
	box.border_color = UiTheme.BORDER
	box.border_width_top = 1
	box.set_content_margin_all(6)
	box.content_margin_left = 10
	box.content_margin_right = 10
	band.add_theme_stylebox_override("panel", box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	band.add_child(row)
	var left := RichTextLabel.new()
	left.name = "CardCost"
	left.bbcode_enabled = true
	left.fit_content = true
	left.scroll_active = false
	left.autowrap_mode = TextServer.AUTOWRAP_OFF
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_theme_color_override("default_color", UiTheme.TEXT)
	left.text = "    ".join(costs.map(func(c: Dictionary) -> String:
		return "[color=#%s]%s[/color] %s" % [COST_COLORS.get(str(c["kind"]), "9a8f7e"), CardInfo.GLYPH.get(str(c["kind"]), "•"), _esc(str(c["text"]))]))
	row.add_child(left)
	if not foot.is_empty():
		var right := Label.new()
		right.name = "CardFootRight"
		right.text = " · ".join(foot)
		right.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		right.add_theme_color_override("font_color", UiTheme.MUTED)
		row.add_child(right)
	return band


## The icon of a card by its ref (IconRules.of); {} — none.
static func look_of(card: Dictionary) -> Dictionary:
	var r := str(card.get("icon", ""))
	var root := (Engine.get_main_loop() as SceneTree).root  # no autoload names: a playtest's script compiles this first
	if r.is_empty() or not root.has_node("Catalog"):
		return {}
	var session: GameSession = root.get_node("GameState").session if root.has_node("GameState") else null
	return IconRules.of(root.get_node("Catalog").data, session.items if session != null else {}, r)


static func _icon_rect(look: Dictionary) -> TextureRect:
	var rect := TextureRect.new()
	rect.custom_minimum_size = Vector2(CARD_ICON, CARD_ICON)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_icon(rect, look)
	return rect


static func _set_icon(rect: TextureRect, look: Dictionary) -> void:
	rect.texture = IconSlot.texture(str(look.get("path", "")))
	rect.modulate = Color(str(look["tint"])) if str(look.get("tint", "")) != "" else Color.WHITE
	rect.visible = rect.texture != null


static func _sub_label(text: String) -> Label:
	var sub := Label.new()
	sub.name = "TipSub"
	sub.text = text
	sub.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.add_theme_font_size_override("font_size", UiTheme.SIZE_SMALL)
	sub.add_theme_color_override("font_color", UiTheme.MUTED)
	return sub


static func _esc(s: String) -> String:
	return s.replace("[", "[lb]")


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


## Shows this text when `control` is hovered, focused or pressed; the right button pins it (or unpins it again). `card` —
## a card of `CardInfo` drawn instead of the text (its plain words are the text when `body_text` is empty).
func hook(control: Control, title_text: String, body_text: String, card: Dictionary = {}) -> void:
	if body_text.is_empty() and not card.is_empty():
		body_text = CardInfo.plain(card)
	if body_text.is_empty() and title_text.is_empty():
		return
	var look: Dictionary = (control as IconSlot).spec if control is IconSlot else {}
	if control is IconSlot:  # an icon tells what it is at the cursor (v0.8.4.43, as in BG3)
		(control as IconSlot).tip_title = title_text
		(control as IconSlot).tip_body = body_text
		(control as IconSlot).card = card
	var shown := func() -> void:
		if _pinned.is_empty():
			_shown = control
		show_text(title_text, body_text, card, look)
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
				pin(control, title_text, body_text, card, look)
			control.accept_event())
	if _pinned == title_text and _pinned_body == body_text:  # the rows were rebuilt: the pinned one is lit again
		_light(control)
