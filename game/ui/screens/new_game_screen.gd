class_name NewGameScreen
extends Control
## New game (ADR-0010 §1, §3, §5): the world pack, the master's style, the death mode and the content limits.
## Defaults come from the picked pack; «Далее» activates the pack and opens character creation.

const SCENE := "res://ui/screens/new_game_screen.tscn"
const TOGGLES := {"%NeedsToggle": "needs", "%SlaveryToggle": "slavery", "%AdultToggle": "adult"}
const DEFAULT_ON := {"needs": true}
const LISTS := {"%Edit_lines": "lines", "%Edit_veils": "veils", "%Edit_wishes": "wishes"}

var settings: Dictionary = {}

var _worlds: VBoxContainer


func required() -> Dictionary:
	var nodes := {
		"%Worlds": "VBoxContainer", "%Form": "VBoxContainer", "%PackName": "Label", "%PackTone": "Label",
		"%DmStyleChoices": "HFlowContainer", "%DmStyleHint": "Label", "%DifficultyChoices": "HFlowContainer",
		"%DifficultyHint": "Label", "%ViolenceChoices": "HFlowContainer", "%ToMenu": "Button", "%NextButton": "Button",
	}
	for path: String in TOGGLES:
		nodes[path] = "CheckButton"
	for path: String in LISTS:
		nodes[path] = "LineEdit"
	return nodes


func _ready() -> void:
	_worlds = UiScenes.need(self, "%Worlds")
	(UiScenes.need(self, "%ToMenu") as Button).pressed.connect(func() -> void: EventBus.navigate.emit("menu", {}))
	var next: Button = UiScenes.need(self, "%NextButton")
	next.pressed.connect(_next)
	for path: String in TOGGLES:  # v0.7.23 needs, v0.7.27 slavery (a hard world), v0.7.38.7 18+
		var key: String = TOGGLES[path]
		(UiScenes.need(self, path) as CheckButton).toggled.connect(func(on: bool) -> void: settings[key] = on)
	for path: String in LISTS:
		_list_field(path, LISTS[path])
	var playable := Catalog.playable()
	if not playable.is_empty():
		_pick_world(str(Catalog.active_world if not Catalog.bundle(Catalog.active_world).is_empty() else playable[0]["id"]))
	else:
		_redraw()
		next.disabled = true


func _pick_world(id: String) -> void:
	settings = WorldPack.default_settings(Catalog.bundle(id)["pack"])
	_redraw()


func _next() -> void:
	if not Catalog.activate(str(settings.get("world", ""))):
		return
	EventBus.navigate.emit("creation", {"settings": settings})


func _redraw() -> void:
	for c in _worlds.get_children():
		_worlds.remove_child(c)
		c.queue_free()
	_label(_worlds, "NG_WORLD", UiTheme.MUTED_LABEL)
	for b: Dictionary in Catalog.bundles:
		var p: Dictionary = b["pack"]
		var ok: bool = b["errors"].is_empty()
		var btn := Button.new()
		btn.name = "World_" + str(b["id"])
		btn.toggle_mode = true
		btn.button_pressed = str(settings.get("world", "")) == str(b["id"])
		btn.disabled = not ok
		btn.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		btn.text = str(p.get("name", b["id"])) + ("" if b["source"] == "builtin" else "  " + tr("NG_MOD"))
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(0, 56)
		btn.pressed.connect(_pick_world.bind(str(b["id"])))
		_worlds.add_child(btn)
		if ok:
			_text(_worlds, str(p.get("description", "")))
		else:
			_text(_worlds, tr("NG_PACK_BROKEN").format({"errors": "; ".join(b["errors"].slice(0, 3))})).theme_type_variation = UiTheme.BAD_LABEL
	(UiScenes.need(self, "%Form") as Control).visible = not settings.is_empty()
	if settings.is_empty():
		return
	var pack: Dictionary = Catalog.bundle(str(settings["world"]))["pack"]
	(UiScenes.need(self, "%PackName") as Label).text = str(pack.get("name", ""))
	(UiScenes.need(self, "%PackTone") as Label).text = tr("NG_TONE").format({"tone": pack.get("tone", ""), "magic": pack.get("magic", "")})
	_choice("%DmStyleChoices", "dm_style", WorldPack.DM_STYLES, "DM_STYLE_")
	(UiScenes.need(self, "%DmStyleHint") as Label).text = tr("DM_STYLE_%s_HINT" % str(settings["dm_style"]).to_upper())
	_choice("%DifficultyChoices", "difficulty", DifficultyRules.levels(Catalog.data), "DIFFICULTY_")
	(UiScenes.need(self, "%DifficultyHint") as Label).text = tr("DIFFICULTY_%s_HINT" % str(settings.get("difficulty", "normal")).to_upper())
	# «Одна жизнь» comes with the roguelike loop (M5): until then every game is «История» (v0.7.7).
	for path: String in TOGGLES:
		var key: String = TOGGLES[path]
		(UiScenes.need(self, path) as CheckButton).set_pressed_no_signal(bool(settings.get(key, DEFAULT_ON.get(key, false))))
	_choice("%ViolenceChoices", "violence", WorldPack.VIOLENCE, "VIOLENCE_")
	for path: String in LISTS:
		var edit: LineEdit = UiScenes.need(self, path)
		var text := ", ".join(settings.get(LISTS[path], []))
		if edit.text != text and not edit.has_focus():  # the player's own spaces stay while typing
			edit.text = text


func _label(parent: Control, text: String, variation: String) -> void:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = variation
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)


func _text(parent: Control, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.theme_type_variation = UiTheme.MUTED_LABEL
	parent.add_child(l)
	return l


func _choice(path: String, key: String, values: Array, prefix: String) -> void:
	var row: Control = UiScenes.need(self, path)
	for c in row.get_children():
		row.remove_child(c)
		c.queue_free()
	for v: Variant in values:
		var b := Button.new()
		b.name = "%s_%s" % [key, v]
		b.text = prefix + str(v).to_upper()
		b.toggle_mode = true
		b.button_pressed = str(settings.get(key, "")) == str(v)
		b.custom_minimum_size = Vector2(160, 48)
		b.pressed.connect(func() -> void:
			settings[key] = v
			_redraw())
		row.add_child(b)


## Lines, veils and wishes as comma-separated text.
func _list_field(path: String, key: String) -> void:
	(UiScenes.need(self, path) as LineEdit).text_changed.connect(func(t: String) -> void:
		var items: Array = []
		for part in t.split(","):
			if not part.strip_edges().is_empty():
				items.append(part.strip_edges())
		settings[key] = items)
