class_name PetPanel
extends Control
## The pet window (roadmap v0.7.43): a wild or beaten beast — the taming with its DC and the hero's bonus, by hand or
## with a treat of its taste (advantage); the hero's pet — its name, closeness, what it gives, feeding by hand and the
## scouting of an exit not yet walked. Every act is GameState.pet_act: the engine decides.

var cid := ""
var _box: VBoxContainer
var frame: ModalFrame


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame = ModalFrame.make(tr("PET_TITLE"), 640.0)
	add_child(frame)
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.close_requested.connect(func() -> void: visible = false)
	frame.close_x.name = "ClosePetButton"
	_box = frame.body
	EventBus.state_changed.connect(_rebuild)
	visibility_changed.connect(_rebuild)


func open(id: String) -> void:
	cid = id
	visible = true
	_rebuild()


func _label(parent: Control, text: String, variation: String = "") -> Label:
	var l := Label.new()
	l.text = text
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not variation.is_empty():
		l.theme_type_variation = variation
	parent.add_child(l)
	return l


func _row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_box.add_child(row)
	return row


func _act(parent: Control, node_name: String, text: String, why: String, what: String, arg: Callable = Callable()) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.disabled = not why.is_empty() or GameState.is_busy()
	b.tooltip_text = tr(why) if not why.is_empty() else ""
	b.size_flags_horizontal = Control.SIZE_SHRINK_END
	b.pressed.connect(func() -> void:
		var err := GameState.pet_act(what, cid, str(arg.call()) if arg.is_valid() else "")
		if not err.is_empty():
			EventBus.message.emit(tr(err)))
	parent.add_child(b)
	return b


func _rebuild() -> void:
	if not visible or not GameState.has_session():
		return
	frame.clear_body()
	var s := GameState.session
	var data := Catalog.data
	var cr := CreatureRules.find(s, s.room_id, cid)
	if cr.is_empty():
		_label(_box, tr("PET_GONE"), UiTheme.MUTED_LABEL)
		return
	var items: Dictionary = data["items"]
	if not bool(cr.get("pet", false)):
		frame.title.text = tr("PET_TAME_TITLE").format({"name": cr["name"]})
		var k := PetRules.kind(data, str(cr["monster"]))
		_label(_box, tr("PET_WILL_GIVE").format({"what": k.get("text", "")}))
		var skill := str(PetRules.cfg(data)["skill"])
		var b := int(s.character.get("skills", {}).get(skill, 0)) + DifficultyRules.bonus(s, data)
		_label(_box, tr("PET_TAME_CHECK").format({"skill": CraftRules.tr_skill(data, skill), "bonus": "%+d" % b, "dc": PetRules.dc(data, cr)}), UiTheme.MUTED_LABEL).name = "PetTameCheck"
		var eats: Array = k.get("eats", [])
		_label(_box, tr("PET_EATS").format({"what": ", ".join(eats.map(func(t: Variant) -> String: return str(PetRules.cfg(data)["tastes"].get(str(t), {}).get("name", t))))}), UiTheme.MUTED_LABEL)
		var why := PetRules.tame_why(s, data, cid)
		var row := _row()
		row.alignment = BoxContainer.ALIGNMENT_END
		_act(row, "PetTame", tr("BTN_PET_TAME"), why, "tame", func() -> String: return "")
		for food: String in PetRules.foods(s, data, str(cr["monster"])):
			var f := food
			_act(row, "PetTame_" + food, tr("BTN_PET_TAME_WITH").format({"food": ItemRules.display_name(items, s.items, food)}), why, "tame", func() -> String: return f)
		return
	frame.title.text = tr("PET_TITLE")
	_label(_box, PetRules.text(data, cr)).name = "PetInfo"
	var name_row := _row()
	var edit := LineEdit.new()
	edit.name = "PetName"
	edit.placeholder_text = tr("PET_NEW_NAME")
	edit.custom_minimum_size = Vector2(220, 0)
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(edit)
	_act(name_row, "PetRename", tr("BTN_PET_RENAME"), "", "rename", func() -> String: return edit.text)
	var foods := PetRules.foods(s, data, str(cr["monster"]))
	if foods.is_empty():
		_label(_box, tr("PET_NO_FOOD"), UiTheme.MUTED_LABEL).name = "PetNoFood"
	else:
		var row := _row()
		row.alignment = BoxContainer.ALIGNMENT_END
		for food: String in foods:
			var f := food
			_act(row, "PetFeed_" + food, tr("BTN_PET_FEED").format({"food": ItemRules.display_name(items, s.items, food)}),
				PetRules.feed_why(s, data, cid, food), "feed", func() -> String: return f)
	if bool(PetRules.kind(data, str(cr["monster"])).get("scout", false)):
		_box.add_child(HSeparator.new())
		_label(_box, tr("PET_SCOUT_HINT"), UiTheme.MUTED_LABEL)
		var targets := PetRules.scout_targets(s, data)
		if targets.is_empty():
			_label(_box, tr("PET_SCOUT_NONE"), UiTheme.MUTED_LABEL).name = "PetScoutNone"
		for room: String in targets:
			var row := _row()
			_label(row, str(WorldView.new(data["world"]).room(room).get("name", room)))
			var r := room
			_act(row, "PetScout_" + room, tr("BTN_PET_SCOUT"), PetRules.scout_why(s, data, cid, room), "scout", func() -> String: return r)
