class_name Toast
extends PanelContainer
## EventBus.message at the bottom of the screen for a few seconds.

const SHOW_S := 3.0

var _label: Label
var _tween: Tween


func _ready() -> void:
	theme_type_variation = UiTheme.CARD
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	modulate.a = 0.0
	_label = Label.new()
	_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	add_child(_label)
	EventBus.message.connect(show_text)


func show_text(text: String) -> void:
	_label.text = text
	if _tween != null:
		_tween.kill()
	modulate.a = 1.0
	_tween = create_tween()
	_tween.tween_interval(SHOW_S)
	_tween.tween_property(self, "modulate:a", 0.0, 0.4)
