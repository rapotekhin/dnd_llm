class_name ItemCell
extends IconSlot
## A thing in a cell (v0.8.4.43.6, the character window as in BG3): its icon by IconRules.of, the stack's number, the frame
## of its rarity; the name, the weight and price and the description in the card at the cursor. It is dragged with
## {"item", "qty", "from"} (`from` — where it lies: a character's things, a slot of its doll, a cell of its belt, a chest,
## a trader's goods) and passes a drop on it to its `area`, the grid or the slot it is part of. A double click and the
## right button call the owner's `on_double` and `on_menu`; an empty cell (a slot with nothing in it) shows its slot's
## faded picture and takes drops only.

var item := ""
var qty := 0
var from: Dictionary = {}  ## where the thing lies, carried in the drag
var area: Control  ## who takes a drop on this cell: its grid
var accept := Callable()  ## (drag) -> bool: a cell that takes a drop itself — a slot of the doll, a cell of the belt
var take := Callable()  ## (drag)
var on_double := Callable()
var on_menu := Callable()  ## (cell) — the right button
var faded := false  ## an empty slot's picture
var lit := false  ## a slot that would take the thing dragged now
var _shift_drag := false


static func of(ref: String, item_id: String, n: int, where: Dictionary, side: int = SIZE) -> ItemCell:
	var c := ItemCell.new()
	c.item = item_id
	c.qty = n
	c.from = where
	c.set_icon(ref)
	c.badge = str(n) if n > 1 else ""
	c.custom_minimum_size = Vector2(side, side)
	c.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	c.focus_mode = Control.FOCUS_NONE
	c.mouse_filter = Control.MOUSE_FILTER_PASS  # a drop on it goes up to its area
	return c


func _gui_input(ev: InputEvent) -> void:
	var mb := ev as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	if mb.button_index == MOUSE_BUTTON_LEFT and mb.double_click and on_double.is_valid():
		on_double.call()
		accept_event()
	elif mb.button_index == MOUSE_BUTTON_RIGHT and on_menu.is_valid():
		on_menu.call(self)
		accept_event()


## The double click's act, as a playtest takes it.
func double() -> void:
	if on_double.is_valid():
		on_double.call()


func _get_drag_data(_at: Vector2) -> Variant:
	if item.is_empty() or disabled:
		return null
	var ghost := IconSlot.new()
	ghost.spec = spec
	ghost.badge = badge
	ghost.size = Vector2(SIZE, SIZE)
	ghost.modulate = Color(1, 1, 1, 0.85)
	set_drag_preview(ghost)
	_shift_drag = Input.is_key_pressed(KEY_SHIFT)
	return {"item": item, "qty": qty, "from": from, "split": _shift_drag and qty > 1}


func _can_drop_data(at: Vector2, data: Variant) -> bool:
	if accept.is_valid():
		return data is Dictionary and (data as Dictionary).has("item") and (data as Dictionary).get("from") != from and bool(accept.call(data))
	return area != null and area.has_method("_can_drop_data") and area._can_drop_data(at, data)


func _drop_data(at: Vector2, data: Variant) -> void:
	if take.is_valid():
		take.call(data)
	elif area != null:
		area._drop_data(at, data)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN or what == NOTIFICATION_DRAG_END:
		var drag: Variant = get_viewport().gui_get_drag_data()
		lit = what == NOTIFICATION_DRAG_BEGIN and accept.is_valid() and _can_drop_data(Vector2.ZERO, drag)  # the slots it fits light up
		queue_redraw()


func _draw() -> void:
	if faded:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.35))
		var tex := IconSlot.texture(str(spec.get("path", "")))
		if tex != null:
			draw_texture_rect(tex, Rect2(Vector2.ZERO, size).grow(-8), false, Color(1, 1, 1, 0.16))
		draw_rect(Rect2(Vector2.ZERO, size).grow(-1), UiTheme.BORDER, false, 1.0)
	else:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.3))
		super()
	if lit:
		draw_rect(Rect2(Vector2.ZERO, size).grow(-1), UiTheme.ACCENT_BRIGHT, false, 2.0)
