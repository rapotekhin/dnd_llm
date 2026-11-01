class_name LayoutView
extends PanelContainer
## `--preview=layout`: every map of the world, for the author. Rooms on the left, the map on the right.

var _session: GameSession
var _canvas: MapField
var _title: Label


static func opened(s: GameSession, room_id: String) -> LayoutView:
	var view := LayoutView.new()
	view._session = s
	view.name = "LayoutView"
	view.set_anchors_preset(Control.PRESET_FULL_RECT)
	var row := HBoxContainer.new()
	view.add_child(row)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(260, 0)
	row.add_child(scroll)
	var list := VBoxContainer.new()
	scroll.add_child(list)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	view._title = Label.new()
	right.add_child(view._title)
	view._canvas = MapField.new()
	view._canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view._canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(view._canvas)
	var shown: Dictionary = {}
	for id: String in Catalog.data["world"]["rooms"]:
		var map_id := LayoutRules.map_id(s, Catalog.data, id)
		if shown.has(map_id):
			continue
		shown[map_id] = true
		var b := Button.new()
		b.text = map_id
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(view._show.bind(map_id))
		list.add_child(b)
	view._show(room_id)
	return view


func _show(room_id: String) -> void:
	var map := LayoutRules.map_of(_session, Catalog.data, room_id)
	_title.text = "%s: %d×%d, комнат %d, выходов %d" % [map["id"], map["w"], map["h"], (map["ids"] as Array).size(), (map["exits"] as Array).size()]
	_canvas.show_map(map, Catalog.data["layouts"])
