extends Control
## Entry point and the only scene: owns the theme and swaps screens on EventBus.navigate.

var _screen: Control


func _ready() -> void:
	theme = UiTheme.build()
	var bg := Panel.new()
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var overlay := CanvasLayer.new()
	overlay.layer = 10
	add_child(overlay)
	var toast_box := Control.new()
	toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_box.theme = theme
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


func _go(screen: String, args: Dictionary) -> void:
	var next: Control
	match screen:
		"menu":
			next = MainMenu.new()
		"game":
			next = GameScreen.new()
		"new_game":
			next = NewGameScreen.new()
		"creation":
			next = CreationScreen.new(args.get("settings", {}))
		"slots":
			next = SlotsScreen.new(str(args.get("mode", SlotsScreen.MODE_LOAD)), str(args.get("back", "menu")))
		"settings":
			next = SettingsScreen.new(str(args.get("back", "menu")), int(args.get("tab", 0)))
		"offline":
			next = OfflineScreen.new(args.get("action", {}))
		_:
			push_error("main: unknown screen %s" % screen)
			return
	if is_instance_valid(_screen):
		_screen.queue_free()
	_screen = next
	add_child(next)
	next.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
