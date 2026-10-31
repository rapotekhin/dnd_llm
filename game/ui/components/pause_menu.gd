class_name PauseMenu
extends Control
## In-game menu over a dimmed screen: continue, save, load, settings, exit to the main menu.

const SCENE := "res://ui/components/pause_menu.tscn"


func required() -> Dictionary:
	return {"%ResumeButton": "Button", "%SaveButton": "Button", "%LoadButton": "Button", "%SettingsButton": "Button",
		"%ExitButton": "Button"}


func _ready() -> void:
	(UiScenes.need(self, "%ResumeButton") as Button).pressed.connect(func() -> void: visible = false)
	(UiScenes.need(self, "%SaveButton") as Button).pressed.connect(func() -> void: EventBus.navigate.emit("slots", {"mode": SlotsScreen.MODE_SAVE, "back": "game"}))
	(UiScenes.need(self, "%LoadButton") as Button).pressed.connect(func() -> void: EventBus.navigate.emit("slots", {"mode": SlotsScreen.MODE_LOAD, "back": "game"}))
	(UiScenes.need(self, "%SettingsButton") as Button).pressed.connect(func() -> void: EventBus.navigate.emit("settings", {"back": "game"}))
	(UiScenes.need(self, "%ExitButton") as Button).pressed.connect(GameState.close_session)


func open() -> void:
	visible = true


func toggle() -> void:
	visible = not visible
