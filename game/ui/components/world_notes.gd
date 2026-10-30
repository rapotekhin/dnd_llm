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
var frame: ModalFrame
var _selected := ""  # the picked room on the map
var _zoom := 1.0
var _pan := Vector2.ZERO


func _init(view_kind: String) -> void:
	kind = view_kind


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame = ModalFrame.new(tr("MAP_TITLE") if kind == MAP else tr("JOURNAL_TITLE"), 0.0)  # one window template (v0.7.22.29, С4)
	frame.name = "NotesFrame"
	add_child(frame)
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.close_requested.connect(func() -> void: visible = false)
	_box = frame.body
	visibility_changed.connect(func() -> void:
		if visible and kind == JOURNAL and GameState.has_session() and _count(GameState.session, GameState.world(), _tab) == 0:
			for t: String in TABS:  # an empty tab hides that the others are not (К2)
				if _count(GameState.session, GameState.world(), t) > 0:
					_tab = t
					break
		_rebuild())
	EventBus.state_changed.connect(_rebuild)


func open() -> void:
	visible = true


## The map on a room (the followed quest's step); "" — on the hero.
func open_at(room_id: String) -> void:
	_selected = room_id
	visible = true
	_rebuild()


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
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	_box.add_child(body)
	var canvas := MapCanvas.new()
	canvas.clip_contents = true  # the drawing stays out of the info column
	canvas.name = "MapCanvas"
	canvas.custom_minimum_size = Vector2(0, maxf(420.0, get_viewport_rect().size.y - 480.0))  # the overlay height without its header, legend and margins
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bx := WorldMap.boxes(world)  # v0.7.22.24: frames of locations, boxes of sites, rooms in them
	canvas.layout = bx["rooms"]
	canvas.unit = float(bx["unit"])
	canvas.known = WorldMap.known(s, world)
	canvas.focus = bx["locations"].get(w.location_id(s.room_id), Rect2())  # the view opens on the hero's location
	canvas.marks = WorldMap.quest_marks(s, world)
	for r: String in RumorRules.marks(s, Catalog.data):  # v0.7.47: a heard tip marks its room too
		if not canvas.marks.has(r):
			canvas.marks[r] = []
	canvas.here = s.room_id
	canvas.selected = _selected if not _selected.is_empty() else s.room_id
	canvas.zoom = _zoom
	canvas.pan = _pan
	for r: String in canvas.known["rooms"] + canvas.known["frontier"]:
		canvas.names[r] = w.room_short(r)
		canvas.site_of[r] = w.site_id(r)
	for r: String in canvas.known["rooms"]:  # a site or a location is drawn once the hero has been in it
		var sid := w.site_id(r)
		var loc := w.location_id(r)
		if bx["sites"].has(sid):
			canvas.site_boxes[sid] = bx["sites"][sid]
			canvas.site_names[sid] = str(w.site(sid).get("name", sid))
			if str(w.site(sid).get("owner", "")) == OwnerRules.HERO:  # v0.7.27: the hero's own
				canvas.site_names[sid] += tr("MAP_OWN_SUFFIX")
				canvas.own_sites[sid] = true
			canvas.single[sid] = w.site_rooms(sid).size() == 1
		if bx["locations"].has(loc):
			canvas.loc_boxes[loc] = bx["locations"][loc]
			canvas.loc_names[loc] = str(w.location(loc).get("name", loc))
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


## What the picked room is and the fast travel there: «Идти сюда · N мин» or why not. A picked site («site:<id>»,
## v0.7.22.24) — its name, its known rooms and the way to its entry (or the nearest room of it the hero knows).
func _draw_place(info: VBoxContainer, room_id: String, known: Dictionary, marks: Dictionary) -> void:
	var s := GameState.session
	var w := GameState.world()
	if room_id.begins_with("site:"):
		var sid := room_id.trim_prefix("site:")
		_text(str(w.site(sid).get("name", sid)), UiTheme.HEADING).reparent(info)
		_text(str(w.location(str(w.site(sid).get("location_id", ""))).get("name", "")), UiTheme.MUTED_LABEL).reparent(info)
		if not str(w.site(sid).get("description", "")).is_empty():
			_text(str(w.site(sid)["description"])).reparent(info)
		var seen: Array = w.site_rooms(sid).filter(func(r: String) -> bool: return s.visited.has(r))
		_text(tr("MAP_SITE_ROOMS").format({"list": ", ".join(seen.map(func(r: String) -> String: return w.room_short(r)))}), UiTheme.MUTED_LABEL).reparent(info)
		if seen.has(s.room_id):
			return
		var to := w.site_entry(sid) if s.visited.has(w.site_entry(sid)) else str(seen[0]) if not seen.is_empty() else ""
		if not to.is_empty():
			_travel_button(info, to)
		return
	if (known["frontier"] as Array).has(room_id):
		_text(tr("MAP_UNKNOWN"), UiTheme.HEADING).reparent(info)
		_text(tr("MAP_UNKNOWN_HINT"), UiTheme.MUTED_LABEL).reparent(info)
		return
	_text(str(w.room(room_id).get("name", room_id)), UiTheme.HEADING).reparent(info)
	_text(w.place_path(room_id), UiTheme.MUTED_LABEL).reparent(info)
	for q: Variant in marks.get(room_id, []):
		var ql := _text(tr("MAP_QUEST").format({"quest": str(q)}))
		ql.add_theme_color_override("font_color", UiTheme.WARN)
		ql.reparent(info)
	for t: Variant in RumorRules.marks(s, Catalog.data).get(room_id, []):  # v0.7.47
		var rl := _text(tr("MAP_RUMOR").format({"text": str(t)}))
		rl.name = "MapRumor"
		rl.add_theme_color_override("font_color", UiTheme.WARN)
		rl.reparent(info)
	if room_id == s.room_id:
		var exits: Array = ExplorationRules.open_exits(s, Catalog.data["world"], s.room_id).map(func(e: String) -> String:
			return w.room_short(e))
		_text(tr("MAP_HERE_EXITS").format({"list": ", ".join(exits)}), UiTheme.MUTED_LABEL).reparent(info)
		return
	_travel_button(info, room_id)


## «Идти сюда · N шагов, M мин» to a visited room, or why not.
func _travel_button(info: VBoxContainer, room_id: String) -> void:
	var s := GameState.session
	var path := WorldMap.route(s, Catalog.data["world"], s.room_id, room_id, Catalog.data)
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
		go.text = tr("BTN_TRAVEL").format({"steps": path.size(), "min": WorldMap.minutes(Catalog.data, s.room_id, path, PropertyRules.travel_mult(s, Catalog.data, s.room_id) * WeatherRules.travel_mult(s, Catalog.data, s.room_id, path[-1]))})
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
const TABS: Array[String] = ["quests", "places", "people", "factions", "found", "rumors", "letters", "chronicle", "calendar"]
var _tab := "quests"
var _folded := {}
var _person_open := ""  # v0.7.22.21 (#18): the person whose card is open in the people tab


func _draw_journal() -> void:
	var s := GameState.session
	var w := GameState.world()
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	_box.add_child(bar)
	for t: String in TABS:
		var b := Button.new()
		b.name = "JournalTab_" + t
		var n := _count(s, w, t)
		b.text = tr("JOURNAL_TAB_" + t.to_upper()) + (" %d" % n if n > 0 else "")  # how much is there without opening it (К2)
		if n == 0:
			b.add_theme_color_override("font_color", UiTheme.MUTED)
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		b.toggle_mode = true
		b.button_pressed = t == _tab
		b.custom_minimum_size = Vector2(0, 48)
		b.pressed.connect(func() -> void:
			_tab = t
			_rebuild())
		bar.add_child(b)
	_box.add_child(HSeparator.new())
	if _tab == "people":
		_draw_people(s, w)
		return
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
		var ids: Array = g.get("ids", [])
		var followed := QuestRules.tracked(s, Catalog.data["world"])
		for i in (g["lines"] as Array).size():
			var line_l := _text("   " + str(g["lines"][i]), UiTheme.MUTED_LABEL)
			var qid := str(ids[i]) if i < ids.size() else ""
			if qid.is_empty():
				continue
			var row := HBoxContainer.new()  # «Следить» beside a quest with a step (П11)
			row.add_theme_constant_override("separation", 12)
			_box.add_child(row)
			line_l.reparent(row)
			line_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var tb := Button.new()
			tb.name = "Track_" + qid
			tb.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			tb.text = tr("QUEST_TRACKED") if qid == followed else tr("BTN_TRACK")
			tb.disabled = qid == followed
			tb.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			tb.pressed.connect(GameState.track_quest.bind(qid))
			row.add_child(tb)


## The entries of a tab: the people met, or the lines of its groups.
func _count(s: GameSession, w: WorldView, tab: String) -> int:
	if tab == "people":
		return _met(s, w).size()
	if tab == "factions":  # v0.7.50
		return FactionRules.met(s, Catalog.data).size()
	if tab == "calendar":  # v0.7.44: the festivals on now
		return CalendarRules.active(s, w.world).size()
	if tab == "rumors":  # v0.7.47: the tips and the heard ones, not the checked
		return RumorRules.count(s, Catalog.data)
	if tab == "letters":  # v0.7.48: what we wait for, the helpers on their way
		return LetterRules.count(s, Catalog.data)
	var n := 0
	for g: Dictionary in _groups(s, w, tab):
		n += (g["lines"] as Array).size()
	return n


## The groups of the current tab: [{title, lines, folded?}], by location (quests: taken, then done — folded).
func _groups(s: GameSession, w: WorldView, tab: String = "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	match tab if not tab.is_empty() else _tab:
		"quests":
			var open: Array[String] = []
			var open_ids: Array[String] = []
			var done: Array[String] = []
			for q: Dictionary in XpRules.quest_list(s, Catalog.data["world"]):
				var line := ("%s — %s" % [q["title"], q["description"]]) if not str(q["description"]).is_empty() else str(q["title"])
				for h: String in QuestRules.history(s, Catalog.data["world"], str(q["id"])):  # what was done (v0.7.22.7)
					line += "\n      " + h
				if not str(q.get("step", "")).is_empty():
					line += "\n      " + tr("JOURNAL_STEP").format({"step": q["step"]})
				if bool(q.get("failed", false)):  # v0.7.14: its NPC died
					done.append("✗ %s — %s" % [q["title"], tr("JOURNAL_FAILED")])
					continue
				(done if bool(q["done"]) else open).append(("✓ " if bool(q["done"]) else "• ") + line)
				if not bool(q["done"]):
					open_ids.append(str(q["id"]) if not str(q.get("step", "")).is_empty() else "")
			var following := HeistRules.followed(s, Catalog.data)
			for hid: String in HeistRules.view(s.character):  # a criminal job is a quest too (v0.7.39.3, the author)
				var hd := HeistRules.def(s, Catalog.data, hid)
				var title := "%s «%s»" % [tr("JOURNAL_HEIST"), hd.get("name", hid)]
				if HeistRules.status(s.character, hid) == "failed":
					done.append("✗ %s — %s" % [title, tr("JOURNAL_FAILED")])
				elif not following.has(hid):
					done.append("✓ " + title)
				else:
					var hl := "• " + title
					for p: Dictionary in HeistRules.path(s, Catalog.data, hid):
						var mark: String = {"done": "✓", "now": "→", "failed": "✗"}.get(str(p["state"]), "·")
						hl += "
      %s %s" % [mark, p["title"]]
					open.append(hl)
					open_ids.append("")
			if not open.is_empty():
				out.append({"title": tr("JOURNAL_QUESTS_OPEN"), "lines": open, "ids": open_ids})
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
				var rep := ReputationRules.text(s, Catalog.data, loc)  # v0.7.17
				out.append({"title": rep if not rep.is_empty() else str(w.location(loc).get("name", loc)), "lines": by_loc[loc]})
		"factions":  # v0.7.50: who the hero has met and how they stand
			for c: Dictionary in FactionRules.met(s, Catalog.data, _met(s, w)):
				var lines: Array = []
				if not str(c["description"]).is_empty():
					lines.append(str(c["description"]))
				if not (c["members"] as Array).is_empty():
					lines.append(tr("JOURNAL_FACTION_MEMBERS").format({"names": ", ".join(c["members"])}))
				lines.append_array(c["why"])
				out.append({"title": "%s — %s" % [c["name"], c["step"]], "lines": lines})
		"people":  # everyone met (v0.7.22.7, big test #2): attitude, looks, what they gave, their quests, what they remember
			var by_loc := {}
			for npc: String in _met(s, w):
				var loc := w.location_id(_npc_room(w, npc))
				if not by_loc.has(loc):
					by_loc[loc] = []
				(by_loc[loc] as Array).append_array(_person(s, w, npc))
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
				var title := tr("JOURNAL_DAY").format({"day": d})
				if CalendarRules.on(w.world):  # v0.7.44: the date beside the day's number
					title += " — " + CalendarRules.text(w.world, d)
				out.append({"title": title, "lines": by_day[d], "folded": d != days[0]})
		"rumors":  # v0.7.47: the tips to check, the heard rumours, the checked ones
			return RumorRules.groups(s, Catalog.data)
		"letters":  # v0.7.48: the helpers on their way, what we wait for, the answers, the lost
			return LetterRules.groups(s, Catalog.data)
		"calendar":  # v0.7.44: today, the festivals on and ahead, the months of the year
			if not CalendarRules.on(w.world):
				return out
			var today: Array[String] = [CalendarRules.season_text(w.world, s.day)]
			var near: Array[String] = []
			for e: Dictionary in CalendarRules.upcoming(s, Catalog.data, w.world, CalendarRules.year_days(w.world)):
				(today if bool(e["on"]) else near).append("★ " + CalendarRules.line(w.world, e, true))
			out.append({"title": tr("JOURNAL_TODAY").format({"date": CalendarRules.text(w.world, s.day)}), "lines": today})
			if not near.is_empty():
				out.append({"title": tr("JOURNAL_FESTIVALS"), "lines": near})
			var months: Array[String] = []
			for m: Dictionary in CalendarRules.cal(w.world)["months"]:
				months.append("%s — %s, %d %s" % [m["name"], CalendarRules.cal(w.world).get("seasons", {}).get(str(m.get("season", "")), ""),
					int(m["days"]), CalendarRules._plural(int(m["days"]))])
			out.append({"title": tr("JOURNAL_MONTHS"), "lines": months, "folded": true})
	return out


## People (v0.7.22.21, the author's fixes check #18): a settlement → its names → the card of the one picked, in the
## description panel on the right (hover shows, a click or the right button keeps it).
func _draw_people(s: GameSession, w: WorldView) -> void:
	var met := _met(s, w)
	if met.is_empty():
		_text(tr("JOURNAL_EMPTY_PEOPLE"), UiTheme.MUTED_LABEL)
		return
	var split := HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", 16)
	_box.add_child(split)
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.add_theme_constant_override("separation", 4)
	split.add_child(names)
	var card := DetailsPanel.new(Vector2(560, 360))
	card.name = "PersonCard"
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.show_text(tr("JOURNAL_PICK_PERSON"), "")
	split.add_child(card)
	var by_loc := {}
	for npc: String in met:
		var loc := w.location_id(_npc_room(w, npc))
		if not by_loc.has(loc):
			by_loc[loc] = []
		(by_loc[loc] as Array).append(npc)
	for loc: String in by_loc:
		var key := "people|" + loc
		var folded := bool(_folded.get(key, false))
		var head := Button.new()
		head.name = "JournalGroup_" + str(loc).md5_text().left(6)
		head.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		head.flat = true
		head.alignment = HORIZONTAL_ALIGNMENT_LEFT
		head.text = ("▸ " if folded else "▾ ") + "%s (%d)" % [str(w.location(loc).get("name", loc)) if not loc.is_empty() else tr("JOURNAL_ELSEWHERE"), (by_loc[loc] as Array).size()]
		head.add_theme_color_override("font_color", UiTheme.ACCENT)
		head.pressed.connect(func() -> void:
			_folded[key] = not folded
			_rebuild())
		names.add_child(head)
		if folded:
			continue
		for npc: String in by_loc[loc]:
			var lines := _person(s, w, npc)
			var who := Button.new()
			who.name = "Person_" + npc
			who.flat = true
			who.alignment = HORIZONTAL_ALIGNMENT_LEFT
			who.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			who.text = "   " + str(w.npc(npc).get("name", npc)) + ("  ✝" if s.dead_npcs.has(npc) else "")
			var title := str(w.npc(npc).get("name", npc))
			var body := "\n".join(lines.map(func(l: String) -> String: return l.strip_edges()))
			card.hook(who, title, body)
			who.pressed.connect(func() -> void:
				_person_open = npc
				card.pin(who, title, body))
			names.add_child(who)
			if npc == _person_open:
				card.pin(who, title, body)


## The NPCs the hero has met: talked to, remembered by, going along, or seen in a visited room.
func _met(s: GameSession, w: WorldView) -> Array[String]:
	var met: Array[String] = []
	for key: String in s.summaries:
		if key.begins_with("dialogue:") and not met.has(key.get_slice(":", 1)):
			met.append(key.get_slice(":", 1))
	for npc: String in s.npc_memory.keys() + s.followers:
		if not met.has(npc):
			met.append(npc)
	for room_id: String in s.visited:
		for npc: String in w.npcs_in(room_id):
			if not met.has(npc):
				met.append(npc)
	return met.filter(func(id: String) -> bool: return not w.npc(id).is_empty())


## A person in the journal: «Бруно Хмель — хозяин таверны, человек · дружески · средних лет, полный, невысокий» and
## what they gave, their quests, the last talk and what they remember of the hero.
func _person(s: GameSession, w: WorldView, npc: String) -> Array[String]:
	var data := Catalog.data
	var n := w.npc(npc)
	var bounds := GameSession.attitude_bounds(data)
	var att := clampi(s.attitude(npc), bounds.x, bounds.y)
	var head := "%s — %s%s · %s · %s" % [n.get("name", npc), n.get("role", ""), (", " + str(n["race"])) if not str(n.get("race", "")).is_empty() else "",
		tr("ATTITUDE_" + ("M%d" % -att if att < 0 else "P%d" % att if att > 0 else "0")), BodyRules.npc_text(data, npc, n)]
	var bw := BondRules.word(s.character, data, npc)  # v0.7.31
	if not bw.is_empty():
		head += " · " + bw
	var fa := FactionRules.def(s, data, FactionRules.of_npc(s, data, npc))  # v0.7.50
	if not fa.is_empty():
		head += " · " + str(fa["name"])
	if s.dead_npcs.has(npc):
		head += " · " + tr("JOURNAL_DEAD")
	var out: Array[String] = [head]
	var deal := SocialRules.deal_text(s, data, npc)
	if not deal.is_empty():
		out.append("    · " + tr("JOURNAL_GAVE").format({"deal": deal}))
	for qid: String in XpRules.quests(data["world"]):
		var q: Dictionary = XpRules.quests(data["world"])[qid]
		if str(q.get("giver", "")) != npc:
			continue
		var state := "JOURNAL_Q_DONE" if s.quests_done.has(qid) else "JOURNAL_Q_FAILED" if s.quests_failed.has(qid) \
			else "JOURNAL_Q_TAKEN" if s.quests_active.has(qid) else ""
		if not state.is_empty():
			out.append("    · " + tr(state).format({"title": q["title"]}))
	var summary := str(s.summaries.get("dialogue:" + npc, ""))
	if not summary.is_empty():
		out.append("    · " + tr("JOURNAL_LAST_TALK").format({"text": summary}))
	for m: String in s.memory_of(npc):
		out.append("    · " + tr("JOURNAL_REMEMBERS").format({"fact": m}))
	return out


func _npc_room(w: WorldView, npc_id: String) -> String:
	for room_id: String in Catalog.data["world"]["rooms"]:
		if w.npcs_in(room_id).has(npc_id):
			return room_id
	return ""
