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
	text_changed.connect(refit)
	text_set.connect(refit)
	resized.connect(refit)


## Fits on the next frame, never inside the frame that lays the screen out anew (v0.8.4.43.53): the input shrunk from
## the fight's long hint to the short one in the frame a fight ends — while the screen hid the fight's parts and showed
## the world's — crashed Godot 4.7.2 natively (signal 11, no script on the stack) at the end of the «consequences» fight.
func refit() -> void:
	if is_inside_tree() and not get_tree().process_frame.is_connected(fit):
		get_tree().process_frame.connect(fit, CONNECT_ONE_SHOT)


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
		var room := size.x - box.x - get_v_scroll_bar().get_combined_minimum_size().x  # the hint wraps short of the scroll bar's place
		var drawn := font.get_multiline_string_size(tr(placeholder_text), HORIZONTAL_ALIGNMENT_LEFT, room, get_theme_font_size("font_size"))
		lines = ceili(drawn.y / font.get_height(get_theme_font_size("font_size")))
	var want := clampf(lines * get_line_height() + box.y, _min_height, MAX_HEIGHT)
	if not is_equal_approx(custom_minimum_size.y, want):
		custom_minimum_size.y = want
