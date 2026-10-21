class_name WorldNotes
extends Control
## Map and journal over the game screen (roadmap v0.5.2). Map (v0.7.6): the scheme of visited places and the «?»
## behind their exits (MapCanvas), the picked place, its quests and the fast travel there. Journal: quests,
## location and conversation summaries, found secrets.
## Read-only; built from the session (visited, summaries, revealed) on every open.

const MAP := "map"
const JOURNAL := "journal"

var kind: String
var _box: VBoxContainer
var _selected := ""  # the picked room on the map
var _zoom := 1.0
var _pan := Vector2.ZERO


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
	var world: Dictionary = Catalog.data["world"]
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	_box.add_child(head)
	_text(tr("MAP_TITLE"), UiTheme.HEADING).reparent(head)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	_box.add_child(body)
	var canvas := MapCanvas.new()
	canvas.name = "MapCanvas"
	canvas.custom_minimum_size = Vector2(0, maxf(420.0, get_viewport_rect().size.y - 480.0))  # the overlay height without its header, legend and margins
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.layout = WorldMap.layout(world)
	canvas.known = WorldMap.known(s, world)
	canvas.marks = WorldMap.quest_marks(s, world)
	canvas.here = s.room_id
	canvas.selected = _selected if not _selected.is_empty() else s.room_id
	canvas.zoom = _zoom
	canvas.pan = _pan
	for r: String in canvas.known["rooms"] + canvas.known["frontier"]:
		canvas.names[r] = str(w.room(r).get("name", r))
		canvas.locations[r] = str(w.location(w.location_id(r)).get("name", ""))
	for z: Array in [["MapZoomIn", "+", 1.25], ["MapZoomOut", "−", 0.8]]:
		var b := Button.new()
		b.name = z[0]
		b.text = z[1]
		b.custom_minimum_size = Vector2(48, 44)
		b.pressed.connect(func() -> void: canvas.set_zoom(canvas.zoom * float(z[2]), canvas.size / 2))
		head.add_child(b)
	var reset := Button.new()
	reset.name = "MapReset"
	reset.text = "MAP_RESET"
	reset.pressed.connect(canvas.reset_view)
	head.add_child(reset)
	body.add_child(canvas)
	canvas.view_changed.connect(func(z: float, p: Vector2) -> void:
		_zoom = z
		_pan = p)
	canvas.picked.connect(func(r: String) -> void:
		_selected = r
		_rebuild())
	var info := VBoxContainer.new()
	info.name = "MapPlace"
	info.custom_minimum_size = Vector2(400, 0)
	info.add_theme_constant_override("separation", 10)
	body.add_child(info)
	_draw_place(info, canvas.selected, canvas.known, canvas.marks)
	_text(tr("MAP_LEGEND"), UiTheme.MUTED_LABEL)


## What the picked room is and the fast travel there: «Идти сюда · N мин» or why not.
func _draw_place(info: VBoxContainer, room_id: String, known: Dictionary, marks: Dictionary) -> void:
	var s := GameState.session
	var w := GameState.world()
	if (known["frontier"] as Array).has(room_id):
		_text(tr("MAP_UNKNOWN"), UiTheme.HEADING).reparent(info)
		_text(tr("MAP_UNKNOWN_HINT"), UiTheme.MUTED_LABEL).reparent(info)
		return
	_text(str(w.room(room_id).get("name", room_id)), UiTheme.HEADING).reparent(info)
	_text(str(w.location(w.location_id(room_id)).get("name", "")), UiTheme.MUTED_LABEL).reparent(info)
	for q: Variant in marks.get(room_id, []):
		var ql := _text(tr("MAP_QUEST").format({"quest": str(q)}))
		ql.add_theme_color_override("font_color", UiTheme.WARN)
		ql.reparent(info)
	if room_id == s.room_id:
		var exits: Array = ExplorationRules.open_exits(s, Catalog.data["world"], s.room_id).map(func(e: String) -> String:
			return str(w.room(e).get("name", e)) if s.visited.has(e) else "?")
		_text(tr("MAP_HERE_EXITS").format({"list": ", ".join(exits)}), UiTheme.MUTED_LABEL).reparent(info)
		return
	var path := WorldMap.route(s, Catalog.data["world"], s.room_id, room_id)
	var go := Button.new()
	go.name = "TravelButton"
	go.theme_type_variation = UiTheme.ACCENT_BUTTON
	go.custom_minimum_size = Vector2(0, 52)
	go.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	go.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if path.is_empty():
		go.text = tr("TRAVEL_NO_ROUTE")
		go.disabled = true
	else:
		go.text = tr("BTN_TRAVEL").format({"steps": path.size(), "min": WorldMap.minutes(Catalog.data, s.room_id, path)})
		go.disabled = GameState.is_busy() or not Backend.is_ready() or s.mode == GameSession.MODE_COMBAT
		go.pressed.connect(func() -> void:
			var err := GameState.travel(room_id)
			if err.is_empty():
				_selected = ""
				visible = false
			else:
				EventBus.message.emit(tr(err)))
	info.add_child(go)


## Journal tabs (v0.6.6, playtest-1): quests, places, conversations, finds; inside — groups by location that fold.
const TABS: Array[String] = ["quests", "places", "people", "found", "chronicle"]
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
				if bool(q.get("failed", false)):  # v0.7.14: its NPC died
					done.append("✗ %s — %s" % [q["title"], tr("JOURNAL_FAILED")])
					continue
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
			if not s.notes.is_empty():  # the master's memory of events (v0.7.4)
				out.append({"title": tr("JOURNAL_NOTES"), "lines": s.notes.map(func(n: Dictionary) -> String:
					return "День %d, %s, %s — %s" % [int(n["day"]), n.get("clock", ""), w.room(str(n["room"])).get("name", n["room"]), n["text"]])})
		"chronicle":  # v0.7.14.4: the facts of the engine by day, the newest day first and open
			var by_day := {}
			for e: Dictionary in s.chronicle:
				var d := int(e["day"])
				if not by_day.has(d):
					by_day[d] = []
				(by_day[d] as Array).append("%02d:%02d · %s — %s" % [int(e["minute"]) / 60, int(e["minute"]) % 60, w.room(str(e["room"])).get("name", e["room"]), e["text"]])
			var days := by_day.keys()
			days.sort()
			days.reverse()
			for d: int in days:
				out.append({"title": tr("JOURNAL_DAY").format({"day": d}), "lines": by_day[d], "folded": d != days[0]})
	return out


func _npc_room(w: WorldView, npc_id: String) -> String:
	for room_id: String in Catalog.data["world"]["rooms"]:
		if w.npcs_in(room_id).has(npc_id):
			return room_id
	return ""
