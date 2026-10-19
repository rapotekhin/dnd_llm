class_name WorldNotes
extends Control
## Map and journal over the game screen (roadmap v0.5.2). Map: visited places by location, the current room
## marked, where one can go from here. Journal: quests, location and conversation summaries, found secrets.
## Read-only; built from the session (visited, summaries, revealed) on every open.

const MAP := "map"
const JOURNAL := "journal"

var kind: String
var _box: VBoxContainer


func _init(view_kind: String) -> void:
	kind = view_kind


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 120)
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	margin.add_child(col)
	var panel := PanelContainer.new()
	panel.theme_type_variation = UiTheme.SIDE
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override("separation", 8)
	scroll.add_child(_box)
	var close := Button.new()
	close.text = "BTN_CLOSE"
	close.custom_minimum_size = Vector2(0, 56)
	close.pressed.connect(func() -> void: visible = false)
	col.add_child(close)
	visibility_changed.connect(_rebuild)
	EventBus.state_changed.connect(_rebuild)


func open() -> void:
	visible = true


func _rebuild() -> void:
	if not visible or not GameState.has_session():
		return
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	if kind == MAP:
		_draw_map()
	else:
		_draw_journal()


func _text(text: String, variation: String = "") -> Label:
	var l := Label.new()
	l.text = text
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not variation.is_empty():
		l.theme_type_variation = variation
	_box.add_child(l)
	return l


func _draw_map() -> void:
	var s := GameState.session
	var w := GameState.world()
	_text(tr("MAP_TITLE"), UiTheme.HEADING)
	var by_location: Dictionary = {}
	var order: Array[String] = []
	for room_id: String in s.visited:
		var loc := w.location_id(room_id)
		if not by_location.has(loc):
			by_location[loc] = []
			order.append(loc)
		(by_location[loc] as Array).append(room_id)
	for loc: String in order:
		_text(str(w.location(loc).get("name", loc))).add_theme_color_override("font_color", UiTheme.ACCENT)
		for room_id: String in by_location[loc]:
			var here := room_id == s.room_id
			var line := _text(("◆ " if here else "• ") + str(w.room(room_id).get("name", room_id)) + ("  — " + tr("MAP_HERE") if here else ""),
				"" if here else UiTheme.MUTED_LABEL)
			if here:
				line.add_theme_color_override("font_color", UiTheme.ACCENT_BRIGHT)
	var exits: Array = ExplorationRules.open_exits(s, Catalog.data["world"], s.room_id).map(func(e: String) -> String: return str(w.room(e).get("name", e)))
	_box.add_child(HSeparator.new())
	_text(tr("MAP_EXITS").format({"list": ", ".join(exits)}), UiTheme.MUTED_LABEL)


func _draw_journal() -> void:
	var s := GameState.session
	var w := GameState.world()
	_text(tr("JOURNAL_TITLE"), UiTheme.HEADING)
	var places: Array[String] = []
	var people: Array[String] = []
	for key: String in s.summaries:
		var text := str(s.summaries[key])
		if key.begins_with("location:"):
			places.append("%s — %s" % [w.location(key.get_slice(":", 1)).get("name", key), text])
		elif key.begins_with("dialogue:"):
			people.append("%s — %s" % [w.npc(key.get_slice(":", 1)).get("name", key), text])
	var found: Array[String] = []
	for room_id: String in s.visited:
		for t: String in ExplorationRules.found_texts(s, Catalog.data["world"], room_id):
			found.append("%s: %s" % [w.room(room_id).get("name", room_id), t])
	var quests: Array[String] = []
	for q: Dictionary in XpRules.quest_list(s, Catalog.data["world"]):
		quests.append(("✓ " if q["done"] else "") + "%s — %s" % [q["title"], q["description"]]
			+ (("
   " + tr("JOURNAL_STEP").format({"step": q["step"]})) if not str(q.get("step", "")).is_empty() else ""))
	if quests.is_empty() and places.is_empty() and people.is_empty() and found.is_empty():
		_text(tr("JOURNAL_EMPTY"), UiTheme.MUTED_LABEL)
		return
	for section: Array in [["JOURNAL_QUESTS", quests], ["JOURNAL_PLACES", places], ["JOURNAL_PEOPLE", people], ["JOURNAL_FOUND", found]]:
		if (section[1] as Array).is_empty():
			continue
		_text(tr(section[0])).add_theme_color_override("font_color", UiTheme.ACCENT)
		for line: String in section[1]:
			_text("• " + line, UiTheme.MUTED_LABEL)
