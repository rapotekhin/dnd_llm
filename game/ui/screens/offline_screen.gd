class_name OfflineScreen
extends Control
## «Мастер недоступен»: why (server down / token / certificate, ADR-0009 §9), retry, connection settings.
## When the backend becomes READY the pending action (new game / load) runs by itself.

var action: Dictionary
var _reason: Label
var _status: Label


func _init(pending: Dictionary) -> void:
	action = pending


static func diagnosis_key(diag: String) -> String:
	match diag:
		Backend.DIAG_SERVER_DOWN:
			return "OFFLINE_SERVER_DOWN"
		Backend.DIAG_TOKEN:
			return "OFFLINE_TOKEN"
		Backend.DIAG_CERTIFICATE:
			return "OFFLINE_CERTIFICATE"
		_:
			return "OFFLINE_UNKNOWN"


func _ready() -> void:
	var center := CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.theme_type_variation = UiTheme.SIDE
	panel.custom_minimum_size = Vector2(900, 0)
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	panel.add_child(col)

	var title := Label.new()
	title.text = "OFFLINE_TITLE"
	title.theme_type_variation = UiTheme.HEADING
	col.add_child(title)
	_reason = Label.new()
	_reason.name = "Reason"
	_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reason.text = "OFFLINE_CHECKING"
	col.add_child(_reason)
	_status = Label.new()
	_status.theme_type_variation = UiTheme.MUTED_LABEL
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_status)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	col.add_child(row)
	var retry := Button.new()
	retry.text = "BTN_RETRY"
	retry.theme_type_variation = UiTheme.ACCENT_BUTTON
	retry.custom_minimum_size = Vector2(220, 56)
	retry.pressed.connect(_retry)
	row.add_child(retry)
	var settings := Button.new()
	settings.text = "BTN_CONNECTION_SETTINGS"
	settings.custom_minimum_size = Vector2(0, 56)
	settings.pressed.connect(func() -> void: EventBus.navigate.emit("settings", {"back": "menu", "tab": SettingsScreen.TAB_MASTER}))
	row.add_child(settings)
	var menu := Button.new()
	menu.text = "BTN_TO_MENU"
	menu.custom_minimum_size = Vector2(0, 56)
	menu.pressed.connect(func() -> void: EventBus.navigate.emit("menu", {}))
	row.add_child(menu)

	EventBus.backend_state_changed.connect(_on_state)
	Backend.diagnosed.connect(_on_diagnosed)
	_on_state(Backend.state(), "")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause_menu"):
		EventBus.navigate.emit("menu", {})
		get_viewport().set_input_as_handled()


func _retry() -> void:
	_reason.text = tr("OFFLINE_CHECKING")
	Backend.reconnect()


func _on_state(state: int, detail: String) -> void:
	_status.text = "%s\n%s" % [Backend.config.url, detail]
	match state:
		BackendClient.State.READY:
			GameEntry.perform(action)
		BackendClient.State.CONNECTING, BackendClient.State.HANDSHAKE:
			pass
		_:
			Backend.request_diagnosis()


func _on_diagnosed(diag: String) -> void:
	_reason.text = tr(diagnosis_key(diag))
