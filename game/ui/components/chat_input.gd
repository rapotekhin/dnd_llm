class_name ChatInput
extends TextEdit
## The chat's input (v0.8.4.2, the author): it grows upward as the text wraps, so the whole message is seen. Enter sends,
## Shift+Enter breaks the line.

signal text_submitted(text: String)

const MAX_HEIGHT := 220.0

var _min_height := 54.0


func _ready() -> void:
	_min_height = custom_minimum_size.y
	wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	scroll_smooth = false
	text_changed.connect(fit.call_deferred)
	text_set.connect(fit.call_deferred)
	resized.connect(fit.call_deferred)


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.is_pressed():
		return
	var key := event as InputEventKey
	if key.keycode == KEY_TAB:
		accept_event()  # a tab in a message means nothing, the fight's keys take it when the input is empty
	elif key.keycode in [KEY_ENTER, KEY_KP_ENTER] and not key.shift_pressed:
		accept_event()
		text_submitted.emit(text)


## The height of the text, or of the hint while there is none: a long hint wraps too.
func fit() -> void:
	var box := get_theme_stylebox("normal").get_minimum_size()
	var lines := get_total_visible_line_count()
	if text.is_empty():
		var font := get_theme_font("font")
		var drawn := font.get_multiline_string_size(tr(placeholder_text), HORIZONTAL_ALIGNMENT_LEFT, size.x - box.x, get_theme_font_size("font_size"))
		lines = ceili(drawn.y / font.get_height(get_theme_font_size("font_size")))
	var want := clampf(lines * get_line_height() + box.y, _min_height, MAX_HEIGHT)
	if not is_equal_approx(custom_minimum_size.y, want):
		custom_minimum_size.y = want
