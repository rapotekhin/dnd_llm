class_name MainMenu
extends Control
## Title screen (a scene since v0.7.51): continue the latest save, new game, load, settings, quit; master status in the
## corner, the project's pages as icons at the bottom.

const SCENE := "res://ui/screens/main_menu.tscn"
const LINKS: Array[Dictionary] = [
	{"id": "subscribestar", "name": "SubscribeStar", "url": "https://subscribestar.adult/between-the-rolls"},
	{"id": "itch", "name": "itch.io", "url": "https://rapotekhin.itch.io/between-the-rolls"},
	{"id": "discord", "name": "Discord", "url": "https://discord.gg/vmpFtkChY"},
]


func required() -> Dictionary:
	var nodes := {
		"%ContinueButton": "Button", "%NewGameButton": "Button", "%LoadButton": "Button", "%SettingsButton": "Button",
		"%QuitButton": "Button", "%VersionLabel": "Label",
	}
	for l: Dictionary in LINKS:
		nodes["%%Link_%s" % l["id"]] = "TextureButton"
	return nodes


func _ready() -> void:
	var latest := SaveManager.latest_slot()
	var cont: Button = UiScenes.need(self, "%ContinueButton")
	cont.visible = not latest.is_empty()
	if cont.visible:
		cont.tooltip_text = _slot_hint(latest)
		cont.pressed.connect(func() -> void: GameEntry.enter({"kind": "load", "slot": latest}))
	_on_press("%NewGameButton", func() -> void: EventBus.navigate.emit("new_game", {}))
	_on_press("%LoadButton", func() -> void: EventBus.navigate.emit("slots", {"mode": SlotsScreen.MODE_LOAD, "back": "menu"}))
	_on_press("%SettingsButton", func() -> void: EventBus.navigate.emit("settings", {"back": "menu"}))
	_on_press("%QuitButton", func() -> void: get_tree().quit())
	var version: Label = UiScenes.need(self, "%VersionLabel")
	version.text = "v%s" % ProjectSettings.get_setting("application/config/version", "")
	for l: Dictionary in LINKS:
		var b: TextureButton = UiScenes.need(self, "%%Link_%s" % l["id"])
		b.tooltip_text = str(l["name"])
		b.pressed.connect(func() -> void: OS.shell_open(str(l["url"])))


func _on_press(path: String, action: Callable) -> void:
	var b: Button = UiScenes.need(self, path)
	b.pressed.connect(action)


func _slot_hint(slot: String) -> String:
	var meta := SaveManager.slot_meta(slot)
	return tr("SLOT_HINT").format({"turns": meta.get("turns", 0), "date": str(meta.get("saved_at", "")).replace("T", " ")})
