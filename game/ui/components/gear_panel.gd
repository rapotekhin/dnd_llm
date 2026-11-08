class_name GearPanel
extends ModalFrame
## The «Снаряжение» window of one who walks with the hero (v0.8.4.40, as a companion in BG3): what it wears and holds in
## both sets, its things with the slots they go to, the hero's things to hand over. Every act is Equip's through
## GameState (`equip`, `unequip`, `gear_act`): the same rules as the hero's sheet.

const SCENE := "res://ui/components/gear_panel.tscn"

var who := ""
var _box: VBoxContainer


func _ready() -> void:
	super()
	close_requested.connect(func() -> void: visible = false)
	close_x.name = "CloseGearButton"
	_box = body
	EventBus.state_changed.connect(_rebuild)
	visibility_changed.connect(_rebuild)


func open(id: String) -> void:
	who = id
	visible = true
	_rebuild()


func _row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_box.add_child(row)
	return row


## The name on the left and a flow of its buttons on the right: they wrap under one another, the name keeps its width.
func _line(row: HBoxContainer, text: String) -> HFlowContainer:
	var l := UiParts.label(row, text)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_stretch_ratio = 2.0
	l.custom_minimum_size = Vector2(180, 0)
	var acts := HFlowContainer.new()
	acts.alignment = FlowContainer.ALIGNMENT_END
	acts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	acts.size_flags_stretch_ratio = 3.0
	acts.add_theme_constant_override("h_separation", 8)
	acts.add_theme_constant_override("v_separation", 6)
	row.add_child(acts)
	return acts


func _button(row: Control, node_name: String, text: String, why: String, act: Callable) -> void:
	var b := UiParts.act_button(row, node_name, text, why, act)
	b.size_flags_horizontal = Control.SIZE_SHRINK_END


func _rebuild() -> void:
	if not visible or not GameState.has_session():
		return
	clear_body()
	var s := GameState.session
	var data := Catalog.data
	if not Being.follows(s, who):
		visible = false
		return
	var items: Dictionary = data["items"]
	var c := Gear.of(s, data, who)
	title.text = tr("GEAR_TITLE").format({"name": WorldView.name_of(data, who)})
	for spare: bool in [false, true]:
		var row_of: Dictionary = CharacterRules.stowed(c) if spare else c.get("equipped", {})
		UiParts.heading(_box, tr("GEAR_STOWED" if spare else "GEAR_WORN"))
		var any := false
		for slot: String in CharacterRules.HANDS if spare else CharacterRules.SLOTS:
			var id := str(row_of.get(slot, ""))
			if id.is_empty():
				continue
			any = true
			var row := _line(_row(), tr("GEAR_SLOT_LINE").format({"slot": tr("SLOT_" + slot.to_upper()), "item": ItemRules.display_name(items, s.items, id)}))
			var sl := slot
			var sp := spare
			_button(row, "GearOff_%s%s" % ["stowed_" if spare else "", slot], tr("BTN_GEAR_OFF"), Equip.off_why(s, data, who, slot, spare),
				func() -> String:
					GameState.unequip(sl, who, sp)
					return "")
		if not any:
			UiParts.label(_box, tr("GEAR_NONE"), UiTheme.MUTED_LABEL)
	var swap := _row()
	swap.alignment = BoxContainer.ALIGNMENT_END
	_button(swap, "GearSwap", tr("BTN_GEAR_SWAP"), Equip.swap_why(s, data, who), GameState.gear_act.bind("swap", who, ""))
	UiParts.heading(_box, tr("GEAR_THINGS"))
	var mine: Dictionary = c.get("inventory", {})
	for id: String in mine:
		var def := ItemRules.def_of(items, s.items, id)
		var row := _line(_row(), "%s%s" % [ItemRules.display_name(items, s.items, id), " ×%d" % int(mine[id]) if int(mine[id]) > 1 else ""])
		for slot: String in CharacterRules.slots_of(def, data):
			for spare: bool in ([false, true] if CharacterRules.HANDS.has(slot) else [false]):
				if str((CharacterRules.stowed(c) if spare else c.get("equipped", {})).get(slot, "")) == id:
					continue
				var sl := slot
				var sp := spare
				var text := tr("BTN_EQUIP_STOWED" if spare and slot != "off_hand" else "BTN_EQUIP_STOWED_OFF" if spare else "BTN_EQUIP_" + slot.to_upper())
				_button(row, "GearOn_%s%s_%s" % ["stowed_" if spare else "", slot, id], text, Equip.why(s, data, who, id, slot, spare),
					func() -> String: return GameState.equip(id, sl, false, sp, who))
		_button(row, "GearTake_" + id, tr("BTN_GEAR_TAKE"), Equip.hand_why(s, data, who, Being.HERO, id), GameState.gear_act.bind("take", who, id))
	if mine.is_empty():
		UiParts.label(_box, tr("GEAR_NONE"), UiTheme.MUTED_LABEL)
	UiParts.heading(_box, tr("GEAR_HERO_THINGS"))
	var hero: Dictionary = s.character.get("inventory", {})
	var shown := 0
	for id: String in hero:
		if CharacterRules.slots_of(ItemRules.def_of(items, s.items, id), data).is_empty():
			continue  # what may be worn or held: the rest goes by the bond's gift
		shown += 1
		var row := _line(_row(), ItemRules.display_name(items, s.items, id))
		_button(row, "GearGive_" + id, tr("BTN_GEAR_GIVE"), Equip.hand_why(s, data, Being.HERO, who, id), GameState.gear_act.bind("give", who, id))
	if shown == 0:
		UiParts.label(_box, tr("GEAR_NONE"), UiTheme.MUTED_LABEL)
