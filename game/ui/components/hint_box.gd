class_name HintBox
extends ModalFrame
## A screen of teaching (HintRules, v0.8.4.44.5): the whole screen darkened and held, the row's words in a window, an
## arrow at what the row points to — lighter inside a gold frame — and «Продолжить»; the dream's end has «Проснуться»
## instead (GameState.wake). No «✕», no Esc; the keys of the game wait under it. The window stands where it leaves the
## target in sight; the target is found anew each frame, so the arrow follows it at any interface size.

signal done

const SCENE := "res://ui/components/hint_box.tscn"
const VEIL := Color(0, 0, 0, 0.62)
const PAD := 8.0  ## the lighter frame round the target
const GAP := 48.0  ## from the target to the window put beside it
const HEAD := 20.0  ## the arrow's head

var row: Dictionary
var _aim: Callable  ## () -> Rect2: what the arrow points to, global; an empty one — nothing
var _at := Rect2()


## Opens over everything in the host's window: `aim` is asked each frame where the target is now.
static func open(host: Node, hint: Dictionary, aim: Callable) -> HintBox:
	var box := UiScenes.open(SCENE) as HintBox
	box.row = hint
	box._aim = aim
	host.get_window().add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return box


func required() -> Dictionary:
	var nodes := super()
	nodes.merge({"%HintText": "Label", "%HintContinue": "Button", "%WakeButton": "Button"})
	return nodes


func _ready() -> void:
	super()
	close_x.visible = false
	(UiScenes.need(self, "%ModalDim") as ColorRect).color = Color(0, 0, 0, 0)  # the veil is drawn round the target
	title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	title.text = str(row.get("title", "")) if not str(row.get("title", "")).is_empty() else tr("TEACH_TITLE")
	(UiScenes.need(self, "%HintText") as Label).text = str(row.get("text", ""))
	var wake := str(row.get("button", "")) == HintRules.WAKE
	var go: Button = UiScenes.need(self, "%HintContinue")
	var up: Button = UiScenes.need(self, "%WakeButton")
	go.visible = not wake
	up.visible = wake
	go.pressed.connect(func() -> void:
		done.emit()
		queue_free())
	up.pressed.connect(func() -> void:
		queue_free()
		GameState.wake())
	(up if wake else go).grab_focus.call_deferred()


## Enter or Space press the window's button; every other key waits until it is pressed.
func _input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var k := event as InputEventKey
	if k.pressed and not k.echo and k.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		for b: Button in [UiScenes.need(self, "%HintContinue") as Button, UiScenes.need(self, "%WakeButton") as Button]:
			if b.visible:
				b.pressed.emit()
				break
	get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	var r: Rect2 = _aim.call() if _aim.is_valid() else Rect2()
	if r.has_area():
		r.position -= global_position
	if r != _at:
		_at = r
		_refit()
		queue_redraw()


## The target in the window's own frame, an empty one — none.
func target() -> Rect2:
	return _at


## Centred, unless that covers the target: then over it, under it, or beside it — the first place on the screen.
func _fit() -> void:
	super()
	queue_redraw()
	if not _at.has_area() or _panel == null:
		return
	var box := Rect2(_panel.position, _panel.size)
	var keep := _at.grow(PAD + GAP / 2.0)
	if not box.intersects(keep):
		return
	var screen := Rect2(Vector2.ZERO, size).grow(-MARGIN)
	var mid := _at.get_center()
	for at: Vector2 in [Vector2(box.position.x, _at.position.y - GAP - box.size.y), Vector2(box.position.x, _at.end.y + GAP),
			Vector2(_at.position.x - GAP - box.size.x, mid.y - box.size.y / 2.0), Vector2(_at.end.x + GAP, mid.y - box.size.y / 2.0)]:
		var spot := Rect2(at.clamp(screen.position, screen.end - box.size), box.size)
		if screen.encloses(spot) and not spot.intersects(keep):
			_panel.position = spot.position.floor()
			return


func _draw() -> void:
	var all := Rect2(Vector2.ZERO, size)
	if not _at.has_area():
		draw_rect(all, VEIL)
		return
	var hole := _at.grow(PAD)
	for r: Rect2 in [Rect2(0, 0, size.x, hole.position.y), Rect2(0, hole.end.y, size.x, size.y - hole.end.y),
			Rect2(0, hole.position.y, hole.position.x, hole.size.y), Rect2(hole.end.x, hole.position.y, size.x - hole.end.x, hole.size.y)]:
		if r.has_area():
			draw_rect(r, VEIL)
	draw_rect(hole, Color(UiTheme.ACCENT_BRIGHT, 0.08))
	draw_rect(hole, UiTheme.ACCENT_BRIGHT, false, 3.0)
	if _panel == null:
		return
	var box := Rect2(_panel.position, _panel.size)
	var from := hole.get_center().clamp(box.position, box.end)
	var to := from.clamp(hole.grow(4.0).position, hole.grow(4.0).end)
	if from.distance_to(to) < HEAD * 1.5:
		return
	var d := (to - from).normalized()
	draw_line(from, to - d * HEAD * 0.6, UiTheme.ACCENT_BRIGHT, 4.0, true)
	var side := Vector2(-d.y, d.x) * HEAD * 0.55
	draw_colored_polygon(PackedVector2Array([to, to - d * HEAD + side, to - d * HEAD - side]), UiTheme.ACCENT_BRIGHT)
