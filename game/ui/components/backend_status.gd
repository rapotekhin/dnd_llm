class_name BackendStatus
extends HBoxContainer
## Master connection indicator: colored dot + short state; tooltip shows server, model and details.

var _dot: ColorRect
var _label: Label


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	_dot = ColorRect.new()
	_dot.custom_minimum_size = Vector2(14, 14)
	_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(_dot)
	_label = Label.new()
	_label.theme_type_variation = UiTheme.MUTED_LABEL
	add_child(_label)
	mouse_filter = Control.MOUSE_FILTER_PASS
	EventBus.backend_state_changed.connect(_on_state_changed)
	_on_state_changed(Backend.state(), "")


func _on_state_changed(state: int, detail: String) -> void:
	match state:
		BackendClient.State.READY:
			_dot.color = UiTheme.OK
			_label.text = tr("BACKEND_READY")
			var info := Backend.client.server_info
			tooltip_text = tr("BACKEND_TOOLTIP_READY").format({
				"url": Backend.config.url, "model": info.get("model", "?"), "version": info.get("server_version", "?")})
		BackendClient.State.CONNECTING, BackendClient.State.HANDSHAKE, BackendClient.State.WAITING_RETRY:
			_dot.color = UiTheme.WARN
			_label.text = tr("BACKEND_CONNECTING")
			tooltip_text = "%s\n%s" % [Backend.config.url, detail]
		_:
			_dot.color = UiTheme.BAD
			_label.text = tr("BACKEND_OFFLINE")
			tooltip_text = "%s\n%s" % [Backend.config.url, detail]
