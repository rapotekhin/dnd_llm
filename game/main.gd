extends Control
## Entry point: swaps screens on EventBus.navigate.

var _screen: Control


func _ready() -> void:
	var bg := Panel.new()
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var overlay := CanvasLayer.new()
	overlay.layer = 10
	add_child(overlay)
	var toast_box := Control.new()
	toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(toast_box)
	toast_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var toast := Toast.new()
	toast_box.add_child(toast)
	toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 140)
	toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	toast.grow_vertical = Control.GROW_DIRECTION_BEGIN
	EventBus.navigate.connect(_go)
	EventBus.session_started.connect(_go.bind("game", {}))
	EventBus.session_closed.connect(_go.bind("menu", {}))
	_go("menu", {})
	if Preview.requested():  # straight into a screen with a ready state (--preview=<name>)
		preview.call_deferred("")


## Opens a preview screen (Preview.SCREENS); the playtest «preview» goes through here.
func preview(which: String) -> void:
	Preview.open(self, which)


func preview_names() -> Array:
	return Preview.SCREENS.keys()


func _go(screen: String, args: Dictionary) -> void:
	var next: Control
	match screen:
		"menu":
			next = UiScenes.open(MainMenu.SCENE)
		"game":
			next = CombatScreen.new() if GameState.has_session() and CombatRules.active(GameState.session) else GameScreen.new()
		"combat":
			next = CombatScreen.new()
		"death":
			next = DeathScreen.make(str(args.get("epitaph", "")))
		"new_game":
			next = UiScenes.open(NewGameScreen.SCENE)
		"creation":
			next = CreationScreen.make(args.get("settings", {}), args.get("heir", {}))
		"slots":
			next = SlotsScreen.make(str(args.get("mode", SlotsScreen.MODE_LOAD)), str(args.get("back", "menu")))
		"settings":
			next = SettingsScreen.make(str(args.get("back", "menu")), int(args.get("tab", 0)))
		"offline":
			next = OfflineScreen.make(args.get("action", {}))
		_:
			push_error("main: unknown screen %s" % screen)
			return
	if is_instance_valid(_screen):
		_screen.queue_free()
	_screen = next
	add_child(next)
	next.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
