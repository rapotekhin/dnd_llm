class_name OfflineScreen
extends Control
## «Мастер недоступен»: why (server down / token / certificate, ADR-0009 §9), retry, connection settings.
## When the backend becomes READY the pending action (new game / load) runs by itself.

const SCENE := "res://ui/screens/offline_screen.tscn"

var action: Dictionary
var _reason: Label
var _status: Label


static func make(pending: Dictionary) -> OfflineScreen:
	var screen := UiScenes.open(SCENE) as OfflineScreen
	screen.action = pending
	return screen


func required() -> Dictionary:
	return {"%Reason": "Label", "%StatusLabel": "Label", "%RetryButton": "Button", "%ConnectionButton": "Button", "%ToMenu": "Button"}


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
	_reason = UiScenes.need(self, "%Reason")
	_status = UiScenes.need(self, "%StatusLabel")
	(UiScenes.need(self, "%RetryButton") as Button).pressed.connect(_retry)
	(UiScenes.need(self, "%ConnectionButton") as Button).pressed.connect(func() -> void:
		EventBus.navigate.emit("settings", {"back": "menu", "tab": SettingsScreen.TAB_MASTER}))
	(UiScenes.need(self, "%ToMenu") as Button).pressed.connect(func() -> void: EventBus.navigate.emit("menu", {}))
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
