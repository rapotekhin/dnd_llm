class_name BuildPanel
extends ModalFrame
## The build screen (v0.8.4.42, «Имущество как в Sims»): a copy of the map of the room the hero owns, where a row of the
## catalog picked on the right goes on a clicked square — a wall, a window or a door, a thing that works by its rules, a
## passage into a new room of its own name; «Убрать» takes back what the hands built. The list filters by a group and a
## search. Every act is GameState.build_act: BuildRules decides, this window only shows.

const SCENE := "res://ui/components/build_panel.tscn"

var _field: MapField
var _hint: Label
var _search: LineEdit
var _groups: HFlowContainer
var _list: VBoxContainer
var _name: LineEdit
var _info: Label
var _remove: Button
var _group := ""  # the filter: "" — all
var _pick := ""  # the row of the catalog picked


func required() -> Dictionary:
	var nodes := super()
	nodes.merge({
		"%BuildSplit": "HBoxContainer", "%BuildField": "Control", "%BuildSide": "VBoxContainer", "%BuildHint": "Label",
		"%BuildSearch": "LineEdit", "%BuildGroups": "HFlowContainer", "%BuildList": "VBoxContainer", "%BuildName": "LineEdit",
		"%BuildInfo": "Label", "%BuildRemove": "Button", "%BuildDone": "Button",
	})
	return nodes


func _ready() -> void:
	super()
	close_requested.connect(func() -> void: visible = false)
	close_x.name = "CloseBuildButton"
	fill_body(UiScenes.need(self, "%BuildSplit"))
	_field = UiScenes.need(self, "%BuildField") as MapField
	_hint = UiScenes.need(self, "%BuildHint")
	_search = UiScenes.need(self, "%BuildSearch")
	_groups = UiScenes.need(self, "%BuildGroups")
	_list = UiScenes.need(self, "%BuildList")
	_name = UiScenes.need(self, "%BuildName")
	_info = UiScenes.need(self, "%BuildInfo")
	_remove = UiScenes.need(self, "%BuildRemove")
	(UiScenes.need(self, "%BuildDone") as Button).pressed.connect(func() -> void: visible = false)
	for edit: LineEdit in [_name, _search]:  # what the player types is never translated; the hint is
		edit.placeholder_text = tr(edit.placeholder_text)
		edit.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_info.text = ""
	if _field != null:
		_field.fit_most = MapField.MAX_TILE * 0.85
		_field.cell_clicked.connect(_on_cell)
		_field.cell_hovered.connect(_on_hover)
	_search.text_changed.connect(func(_t: String) -> void: _fill_list())
	_remove.toggled.connect(_on_remove)
	EventBus.state_changed.connect(_rebuild)
	visibility_changed.connect(_rebuild)


func open() -> void:
	visible = true
	_rebuild()


## The row of the catalog picked (a playtest picks it as the player does).
func pick(id: String) -> void:
	_pick = id
	_remove.set_pressed_no_signal(false)
	_fill_list()


func _rebuild() -> void:
	if not visible or not GameState.has_session() or _field == null:
		return
	var s := GameState.session
	var data := Catalog.data
	var pid := BuildRules.place_of(s, data)
	title.text = tr("BUILD_TITLE").format({"name": PropertyRules.name_of(s, data, pid)}) if not pid.is_empty() else tr("BUILD_TITLE_NONE")
	var map := LayoutRules.map_of(s, data, s.room_id)
	var names := {}
	for e: Dictionary in map["exits"]:
		names[e["to"]] = GameState.world().room(str(e["to"])).get("name", e["to"])
	_field.names = names
	_field.show_map(map, data["layouts"])
	_field.things = BuildRules.tokens(data, map)
	_field.place_hero(WalkRules.settle(s, data, map), str(s.character.get("name", "?")).left(1), [] as Array[Dictionary])
	var why := BuildRules.where_why(s, data)
	set_note(tr(why) if not why.is_empty() else "")
	_fill_groups(s, data, pid)
	_fill_list()


func _fill_groups(s: GameSession, data: Dictionary, pid: String) -> void:
	for ch: Node in _groups.get_children():
		_groups.remove_child(ch)
		ch.queue_free()
	var rows := BuildRules.catalog(s, data, pid) if not pid.is_empty() else ([] as Array[Dictionary])
	var ids: Array[String] = [""]
	ids.append_array(BuildRules.groups(data))
	for g: String in ids:
		var n := BuildRules.view(rows, "", g).size()
		if n == 0 and not g.is_empty():
			continue
		var b := Button.new()
		b.name = "BuildGroup_" + (g if not g.is_empty() else "all")
		b.text = "%s (%d)" % [tr("BUILD_GROUP_" + (g if not g.is_empty() else "all").to_upper()), n]
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		b.toggle_mode = true
		b.button_pressed = g == _group
		b.add_theme_font_size_override("font_size", UiTheme.SIZE_SMALL)
		b.pressed.connect(func() -> void:
			_group = g
			_rebuild.call_deferred())
		_groups.add_child(b)


func _fill_list() -> void:
	for ch: Node in _list.get_children():
		_list.remove_child(ch)
		ch.queue_free()
	var s := GameState.session
	var data := Catalog.data
	var pid := BuildRules.place_of(s, data)
	if pid.is_empty():
		_name.visible = false
		return
	for r: Dictionary in BuildRules.view(BuildRules.catalog(s, data, pid), _search.text, _group):
		var id := str(r["id"])
		var b := Button.new()
		b.name = "BuildItem_" + id.validate_node_name()
		var cost := Money.format(int(r["price_cp"]))
		b.text = "%s — %s" % [r["name"], tr("BUILD_FROM").format({"price": cost}) if str(r["kind"]) == BuildRules.PASSAGE else cost]
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		b.button_pressed = id == _pick and not _remove.button_pressed
		b.tooltip_text = "%s\n%s" % [r["text"], Price.text(BuildRules.quote(data, r), int(r["price_cp"]))]
		b.add_theme_font_size_override("font_size", UiTheme.SIZE_SMALL)
		b.pressed.connect(pick.bind(id))
		_list.add_child(b)
	var passage := _pick == BuildRules.PASSAGE and not _remove.button_pressed
	_name.visible = passage
	_hint.text = tr("BUILD_HINT_REMOVE" if _remove.button_pressed else "BUILD_HINT_PASSAGE" if passage else "BUILD_HINT")


func _on_remove(on: bool) -> void:
	if on:
		_pick = ""
	_fill_list()


func _on_cell(cell: Vector2i) -> void:
	var err := ""
	if _remove.button_pressed:
		err = GameState.build_act("remove", "", cell)
	elif _pick.is_empty():
		err = "BUILD_PICK_FIRST"
	else:
		err = GameState.build_act("build", _pick, cell, _name.text)
	set_note(tr(err) if not err.is_empty() else "")


## What the square under the mouse would cost, or why not.
func _on_hover(cell: Vector2i) -> void:
	if not GameState.has_session() or (_pick.is_empty() and not _remove.button_pressed):
		_info.text = ""
		return
	var s := GameState.session
	var data := Catalog.data
	if _remove.button_pressed:
		var why := BuildRules.remove_why(s, data, cell)
		_info.text = tr("BUILD_REMOVE_HERE") if why.is_empty() else tr(why)
		return
	var why := BuildRules.build_why(s, data, _pick, cell, _name.text if not _name.text.is_empty() else "?")
	var cost := BuildRules.price(s, data, _pick, cell)
	_info.text = tr("BUILD_HERE").format({"price": Money.format(cost)}) if why.is_empty() else tr(why)
