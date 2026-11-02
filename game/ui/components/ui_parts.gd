class_name UiParts
extends RefCounted
## The small parts every window builds (v0.8.4.19): a line of the game's text, a heading, the button of an act, an HP bar.
## A window takes them from here and keeps no copy of its own.


## A wrapped line of the game's own words (never translated) in `parent`; with a null parent it is only made.
static func label(parent: Control, text: String, variation: String = "") -> Label:
	var l := Label.new()
	l.text = text
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not variation.is_empty():
		l.theme_type_variation = variation
	if parent != null:
		parent.add_child(l)
	return l


static func heading(parent: Control, text: String) -> Label:
	return label(parent, text, UiTheme.ACCENT_LABEL)


## The button of an act: grey with its reason on the hover while `why` is a key or the game is busy; `action` gives ""
## or the key of a refusal, which goes to the message line.
static func act_button(parent: Control, node_name: String, text: String, why: String, action: Callable) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.disabled = not why.is_empty() or GameState.is_busy()
	b.tooltip_text = str(TranslationServer.translate(why)) if not why.is_empty() else ""
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(func() -> void:
		var err: Variant = action.call()
		if err is String and not (err as String).is_empty():
			EventBus.message.emit(str(TranslationServer.translate(err))))
	parent.add_child(b)
	return b


## An HP bar: green, yellow, red by the share left (Б2).
static func hp_bar(value: int, most: int, height: float = 14.0, corner: int = 3) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.max_value = maxi(1, most)
	bar.value = clampi(value, 0, maxi(1, most))
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, height)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := UiTheme.hp_color(float(value) / maxf(1.0, most))
	bar.add_theme_stylebox_override("fill", UiTheme.box(col, col, 0, 0, corner))
	bar.add_theme_stylebox_override("background", UiTheme.box(UiTheme.BG, UiTheme.BORDER, 1, 0, corner))
	return bar
