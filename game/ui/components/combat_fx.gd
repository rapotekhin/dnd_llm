class_name CombatFx
extends RefCounted
## Simple combat animations (roadmap v0.7.22.14, the author: «so that it is easy to swap for sprites later»): the one
## entry point is `play(node, kind)` on a fighter's chip and `look(node, state)` for a lasting state; the combat
## screen decides WHAT happened (from the engine's fx events and the difference of HP and states between two
## refreshes), this class only decides HOW it looks. To use sprites, replace the bodies of the `_<kind>` functions
## (or route `play` to an AnimatedSprite on the chip) — the screen and the engine stay as they are.
##   hit — a red flash; crit — a stronger red flash with a shake; dodge — a quick step aside with a motion trail and
##   back; heal — a green flash; down — fades dark; spell — a violet glint. States: hidden — grey in a haze.

const RED := Color(1.0, 0.35, 0.3)
const GREEN := Color(0.45, 1.0, 0.5)
const VIOLET := Color(0.75, 0.55, 1.0)


static func play(node: Control, kind: String) -> void:
	if node == null or not is_instance_valid(node) or not node.is_inside_tree():
		return
	match kind:
		"hit":
			_flash(node, RED, 0.35)
		"crit":
			_flash(node, RED, 0.55)
			_shake(node, 6.0, 0.3)
		"dodge":
			_dodge(node)
		"heal":
			_flash(node, GREEN, 0.5)
		"down":
			_fade(node, Color(0.4, 0.4, 0.4, 0.6), 0.5)
		"spell":
			_flash(node, VIOLET, 0.45)


## A number over the chip that rises and fades (v0.7.22.30, П9): «−6» red, «+4» green. `host` is a free-placed layer
## over the screen, so the number does not shove the chip's container.
static func number(host: Control, node: Control, amount: int) -> void:
	if host == null or node == null or not is_instance_valid(node) or not node.is_inside_tree() or amount == 0:
		return
	var l := Label.new()
	l.name = "FxNumber"
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.text = ("+%d" if amount > 0 else "−%d") % absi(amount)
	l.add_theme_font_size_override("font_size", 40)
	l.add_theme_color_override("font_color", GREEN if amount > 0 else RED)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 8)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(l)
	var at := node.get_global_rect()
	l.global_position = Vector2(at.get_center().x - 24, at.position.y - 44)
	var tw := l.create_tween()
	tw.tween_property(l, "position:y", l.position.y - 56, 0.9).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.9).set_delay(0.35)
	tw.tween_callback(l.queue_free)


## A lasting look of a state, set on every redraw: hidden — grey in a haze; "" — as is.
static func look(node: Control, state: String) -> void:
	if node == null:
		return
	match state:
		"hidden":
			node.modulate = Color(0.65, 0.65, 0.7, 0.55)
		_:
			pass


static func _flash(node: Control, color: Color, time: float) -> void:
	var base := node.modulate
	var tw := node.create_tween()
	tw.tween_property(node, "modulate", color, time * 0.3)
	tw.tween_property(node, "modulate", base, time * 0.7)


static func _shake(node: Control, amount: float, time: float) -> void:
	var start := node.position
	var tw := node.create_tween()
	for i in 4:
		tw.tween_property(node, "position", start + Vector2(amount * (1 if i % 2 == 0 else -1), 0), time / 5.0)
	tw.tween_property(node, "position", start, time / 5.0)


## A step aside and back, with a fading copy left behind for a motion blur.
static func _dodge(node: Control) -> void:
	var start := node.position
	var parent := node.get_parent()
	if parent != null and not (parent is Container):  # a free-placed chip: a ghost copy for the trail
		var ghost := node.duplicate(0) as Control
		parent.add_child(ghost)
		ghost.position = start
		ghost.modulate = Color(1, 1, 1, 0.4)
		var gt := ghost.create_tween()
		gt.tween_property(ghost, "modulate:a", 0.0, 0.25)
		gt.tween_callback(ghost.queue_free)
	var tw := node.create_tween()
	tw.tween_property(node, "position", start + Vector2(18, -4), 0.08).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(node, "modulate:a", 0.45, 0.08)
	tw.tween_property(node, "position", start, 0.22).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_property(node, "modulate:a", 1.0, 0.22)


static func _fade(node: Control, to: Color, time: float) -> void:
	var tw := node.create_tween()
	tw.tween_property(node, "modulate", to, time)
