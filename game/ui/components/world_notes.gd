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


## Journal tabs (v0.6.6, playtest-1): quests, places, conversations, finds; inside — groups by location that fold.
const TABS: Array[String] = ["quests", "places", "people", "found"]
var _tab := "quests"
var _folded := {}


func _draw_journal() -> void:
	var s := GameState.session
	var w := GameState.world()
	_text(tr("JOURNAL_TITLE"), UiTheme.HEADING)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	_box.add_child(bar)
	for t: String in TABS:
		var b := Button.new()
		b.name = "JournalTab_" + t
		b.text = tr("JOURNAL_TAB_" + t.to_upper())
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		b.toggle_mode = true
		b.button_pressed = t == _tab
		b.custom_minimum_size = Vector2(0, 48)
		b.pressed.connect(func() -> void:
			_tab = t
			_rebuild())
		bar.add_child(b)
	_box.add_child(HSeparator.new())
	var groups := _groups(s, w)
	if groups.is_empty():
		_text(tr("JOURNAL_EMPTY_" + _tab.to_upper()), UiTheme.MUTED_LABEL)
		return
	for g: Dictionary in groups:
		var key := "%s|%s" % [_tab, g["title"]]
		var folded := bool(_folded.get(key, g.get("folded", false)))
		var head := Button.new()
		head.name = "JournalGroup_" + str(g["title"]).md5_text().left(6)
		head.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		head.flat = true
		head.alignment = HORIZONTAL_ALIGNMENT_LEFT
		head.text = ("▸ " if folded else "▾ ") + "%s (%d)" % [g["title"], (g["lines"] as Array).size()]
		head.add_theme_color_override("font_color", UiTheme.ACCENT)
		head.pressed.connect(func() -> void:
			_folded[key] = not folded
			_rebuild())
		_box.add_child(head)
		if folded:
			continue
		for line: String in g["lines"]:
			_text("   " + line, UiTheme.MUTED_LABEL)


## The groups of the current tab: [{title, lines, folded?}], by location (quests: taken, then done — folded).
func _groups(s: GameSession, w: WorldView) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	match _tab:
		"quests":
			var open: Array[String] = []
			var done: Array[String] = []
			for q: Dictionary in XpRules.quest_list(s, Catalog.data["world"]):
				var line := "%s — %s" % [q["title"], q["description"]]
				if not str(q.get("step", "")).is_empty():
					line += "\n      " + tr("JOURNAL_STEP").format({"step": q["step"]})
				(done if bool(q["done"]) else open).append(("✓ " if bool(q["done"]) else "• ") + line)
			if not open.is_empty():
				out.append({"title": tr("JOURNAL_QUESTS_OPEN"), "lines": open})
			if not done.is_empty():
				out.append({"title": tr("JOURNAL_QUESTS_DONE"), "lines": done, "folded": true})
		"places":
			var by_loc := {}
			for room_id: String in s.visited:
				var loc := w.location_id(room_id)
				if not by_loc.has(loc):
					by_loc[loc] = []
					var summary := str(s.summaries.get("location:" + loc, ""))
					if not summary.is_empty():
						(by_loc[loc] as Array).append(summary)
				(by_loc[loc] as Array).append("• " + str(w.room(room_id).get("name", room_id)) + ("  — " + tr("MAP_HERE") if room_id == s.room_id else ""))
			for loc: String in by_loc:
				out.append({"title": str(w.location(loc).get("name", loc)), "lines": by_loc[loc]})
		"people":
			var by_loc := {}
			for key: String in s.summaries:
				if not key.begins_with("dialogue:"):
					continue
				var npc := key.get_slice(":", 1)
				var loc := w.location_id(_npc_room(w, npc))
				if not by_loc.has(loc):
					by_loc[loc] = []
				(by_loc[loc] as Array).append("%s — %s" % [w.npc(npc).get("name", npc), s.summaries[key]])
			for loc: String in by_loc:
				out.append({"title": str(w.location(loc).get("name", loc)) if not loc.is_empty() else tr("JOURNAL_ELSEWHERE"), "lines": by_loc[loc]})
		"found":
			var by_loc := {}
			for room_id: String in s.visited:
				for t: String in ExplorationRules.found_texts(s, Catalog.data["world"], room_id):
					var loc := w.location_id(room_id)
					if not by_loc.has(loc):
						by_loc[loc] = []
					(by_loc[loc] as Array).append("%s: %s" % [w.room(room_id).get("name", room_id), t])
			for loc: String in by_loc:
				out.append({"title": str(w.location(loc).get("name", loc)), "lines": by_loc[loc]})
	return out


func _npc_room(w: WorldView, npc_id: String) -> String:
	for room_id: String in Catalog.data["world"]["rooms"]:
		if w.npcs_in(room_id).has(npc_id):
			return room_id
	return ""
