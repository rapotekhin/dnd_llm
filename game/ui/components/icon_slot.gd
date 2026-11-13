class_name IconSlot
extends Button
## A square cell with an icon (v0.8.4.43, as in BG3): the hotbar, the inventory's grid, the window buttons. What to draw
## is `IconRules.of` — this only paints it: the picture (tinted by a spell's school), the marks of element, material and
## shape as dots, the frame of rarity, a count or charges in the corner, the mark of a bonus action. Only the icon, never
## a caption (the author, 2026-11-10: «никаких подписей нет. Только значки»): what it is shows at the cursor — a card
## with the name, the line of the act (its chance, why not) and its description. It stays a Button: pressed, toggled,
## disabled, its `text` and found by its name as before; its text is the card's line, never drawn on the cell.
## A cell with a `drag_key` is dragged: onto a slot of the hotbar, or off the bar (`dropped_off`).
## v0.8.4.43.15 (the author: «описание не содержит названия способности»): the card's title is the name — `tip_title`, else
## the cell's own text, never the line of its tooltip; the card is `DetailsPanel.tip_card`, one size; the right button
## pins it (`pin_card`) so it stays when the cursor goes.
## v0.8.4.43.33 (the author: «разрешение иконок ужасное, они все мелкие и детали потеряны»): an icon that carries its own
## frame (`framed`, the lines style) is laid edge to edge with no frame of the cell around it, a lit edge when hovered; a
## picture is shrunk through its mipmaps, so thin lines stay whole; the card is the one of `CardInfo` when the cell has it.

signal dropped_off(key: String)

const SIZE := 56

static var _textures := {}  # path → Texture2D with its mipmaps

var spec: Dictionary = {}:
	set(v):
		spec = v
		_restyle()
var card: Dictionary = {}  ## the card of `CardInfo` at the cursor ({} — the plain `tip_body`)
var badge := ""  ## «×2», «1/3» — the corner's number
var cost := ""  ## "bonus" — a triangle in the corner, as the bonus action's mark
var tip_title := ""  ## the card's title; the text's first line when empty
var tip_body := ""  ## the card's description under the line
var drag_key := ""  ## the hotbar's key of this cell; "" — not dragged
var meter := -1.0  ## 0…1: a bar along the bottom — a need's fill (v0.8.4.43.4); below 0 — none
var meter_color := Color.WHITE
var _dragging := false


## A cell of `ref` named `name_text`; `side` — its side in pixels.
static func make(ref: String, name_text: String, side: int = SIZE) -> IconSlot:
	var b := IconSlot.new()
	b.set_icon(ref)
	b.text = name_text
	b.tooltip_text = name_text
	b.custom_minimum_size = Vector2(side, side)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER  # a square: beside a wrapped name it stands in the middle, not stretched (v0.8.4.43.35)
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.focus_mode = Control.FOCUS_NONE
	return b


func _init() -> void:
	clip_text = true  # the button's own text adds nothing to its size and is not drawn
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_restyle()
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for k: String in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color", "font_disabled_color"]:
		add_theme_color_override(k, Color.TRANSPARENT)


## The cell's frame: the drawn cell (not the theme's long button stretched square, v0.8.4.43.23) — none under an icon
## that has its own.
func _restyle() -> void:
	var cell: StyleBox = StyleBoxEmpty.new() if bool(spec.get("framed", false)) else UiTheme.cell_box()
	if cell == null:
		return
	for k: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		add_theme_stylebox_override(k, cell)


## A picture by its path with its mipmaps made (an icon is drawn far smaller than its file: without them a thin line
## breaks into dots); null — none.
static func texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if not _textures.has(path):
		var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
		if tex != null and not tex.has_mipmaps():
			var img := tex.get_image()
			if img != null:
				if img.is_compressed():
					img.decompress()
				img.generate_mipmaps()
				tex = ImageTexture.create_from_image(img)
		_textures[path] = tex
	return _textures[path]


## Gives the cell its card of `CardInfo`: the title, the plain words for the tests and the chat, the card at the cursor.
func set_card(c: Dictionary) -> void:
	card = c
	if not c.is_empty():
		tip_title = str(c.get("title", tip_title))
		tip_body = CardInfo.plain(c)


func set_icon(ref: String) -> void:
	var root := (Engine.get_main_loop() as SceneTree).root  # no autoload names: a playtest's script compiles this first
	var session: GameSession = root.get_node("GameState").session
	spec = IconRules.of(root.get_node("Catalog").data, session.items if session != null else {}, ref)
	queue_redraw()


## The card at the cursor: the name, the act's line when it says more, the description.
func _make_custom_tooltip(for_text: String) -> Object:
	return DetailsPanel.tip_card(card_title(for_text), card_line(for_text), tip_body, card, spec)


## The name on the card: `tip_title`, else the cell's own text (its name), else the first line of its tooltip.
func card_title(for_text: String) -> String:
	if tip_title != "":
		return tip_title
	return text.get_slice("\n", 0) if text != "" else for_text.get_slice("\n", 0)


## The act's line under the name: the tooltip without the name it begins with. Under a card the circle «(2)» and the marks
## «[бонус]», «[по желанию]» of a button's label go too: the card says them in its head and its band.
func card_line(for_text: String) -> String:
	var title := card_title(for_text)
	var line := for_text.strip_edges()
	line = line.substr(title.length()).strip_edges() if line.begins_with(title) else line
	if not card.is_empty():
		for mark: String in [tr("COMBAT_BONUS_SHORT"), tr("SPELL_AT_WILL_SHORT")]:
			line = line.replace(mark.strip_edges(), "")
		line = RegEx.create_from_string("^\\(\\d+\\)").sub(line.strip_edges(), "").strip_edges()
	return line


## Pins this cell's card (the right button): it stays on the screen until the right button on it again or its lock.
func pin_card(left := false) -> void:
	var line := card_line(tooltip_text)
	DetailsPanel.pin_card(self, card_title(tooltip_text), "\n\n".join([line, tip_body].filter(func(x: String) -> bool: return x != "")), left, card, spec)


func _gui_input(ev: InputEvent) -> void:
	var mb := ev as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT and (tooltip_text != "" or tip_body != ""):
		pin_card()
		accept_event()


func _get_drag_data(_at: Vector2) -> Variant:
	if drag_key.is_empty():
		return null
	var ghost := IconSlot.new()
	ghost.spec = spec
	ghost.size = Vector2(SIZE, SIZE)
	ghost.modulate = Color(1, 1, 1, 0.8)
	set_drag_preview(ghost)
	_dragging = true
	return {"hotbar": drag_key}


## A drop on a cell is a drop on its slot.
func _can_drop_data(at: Vector2, data: Variant) -> bool:
	return get_parent() is HotSlot and (get_parent() as HotSlot)._can_drop_data(at, data)


func _drop_data(at: Vector2, data: Variant) -> void:
	(get_parent() as HotSlot)._drop_data(at, data)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and _dragging:
		_dragging = false
		if not get_viewport().gui_is_drag_successful():
			dropped_off.emit(drag_key)


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var framed := bool(spec.get("framed", false))
	var inner := r if framed else r.grow(-3 if flat or UiTheme.cell_box() == null else -roundf(minf(size.x, size.y) * 0.1))  # inside the drawn cell's lines
	var dim := Color(1, 1, 1, 0.35) if disabled else Color.WHITE
	var tex := texture(str(spec.get("path", "")))
	if tex != null:
		var tint: Color = Color(str(spec["tint"])) if str(spec.get("tint", "")) != "" else Color.WHITE
		draw_texture_rect(tex, inner, false, tint * dim)
		if framed and is_hovered() and not disabled:  # its own frame lit: the cell has none to light
			draw_texture_rect(tex, inner, false, Color(1, 0.95, 0.8, 0.35))
	var frame := str(spec.get("frame", ""))
	if frame != "":
		draw_rect(r.grow(-1), Color(frame) * dim, false, 2.0)
	if button_pressed:
		draw_rect(r.grow(-1), UiTheme.ACCENT_BRIGHT, false, 3.0)
	var font := get_theme_font("font")
	var small := clampi(int(size.y / 4.6), 10, 15)
	var at := Vector2(inner.position.x + 2, inner.end.y - 6)
	for m: Dictionary in spec.get("marks", []):  # bottom-left, a dot or the mark's own picture
		var mt := texture(str(m.get("path", "")))
		if mt != null:
			draw_texture_rect(mt, Rect2(at - Vector2(0, 10), Vector2(14, 14)), false, dim)
		else:
			draw_circle(at + Vector2(5, -1), 5.0, Color(str(m["color"])) * dim)
			draw_arc(at + Vector2(5, -1), 5.0, 0, TAU, 16, Color(0, 0, 0, 0.6), 1.0)
		at.x += 13
	if badge != "":
		var w := font.get_string_size(badge, HORIZONTAL_ALIGNMENT_LEFT, -1, small).x
		var p := Vector2(r.end.x - w - 5, r.end.y - 5)
		draw_rect(Rect2(p - Vector2(2, small), Vector2(w + 4, small + 3)), Color(0, 0, 0, 0.6))
		draw_string(font, p, badge, HORIZONTAL_ALIGNMENT_LEFT, -1, small, UiTheme.ACCENT_BRIGHT * dim)
	if meter >= 0.0:
		var bar := Rect2(inner.position.x, r.end.y - 6, inner.size.x, 4)
		draw_rect(bar, Color(0, 0, 0, 0.6))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(meter, 0.0, 1.0), bar.size.y)), meter_color * dim)
	if cost == "bonus":
		var o := Vector2(5, 5)
		draw_colored_polygon(PackedVector2Array([o + Vector2(5, 0), o + Vector2(10, 9), o + Vector2(0, 9)]), UiTheme.WARN * dim)
