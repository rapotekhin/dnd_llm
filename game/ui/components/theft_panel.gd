class_name TheftPanel
extends ModalFrame
## The pockets window (roadmap v0.7.0, like in BG3): what the NPC carries — the purse, small things, worn weapons —
## each with its DC and the chance by the player's Sleight of Hand. «Стащить» rolls it (GameState.steal); a failure
## closes the window: the NPC noticed.

const SCENE := "res://ui/components/theft_panel.tscn"

var npc_id := ""
var _box: VBoxContainer


func _ready() -> void:
	super()
	close_requested.connect(func() -> void: visible = false)
	_box = body
	EventBus.state_changed.connect(_rebuild)
	visibility_changed.connect(_rebuild)


func open(npc: String) -> void:
	npc_id = npc
	visible = true
	_rebuild()


func _label(text: String, variation: String = "") -> Label:
	var l := Label.new()
	l.text = text
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not variation.is_empty():
		l.theme_type_variation = variation
	return l


func _rebuild() -> void:
	if not visible or not GameState.has_session() or npc_id.is_empty():
		return
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	var s := GameState.session
	var data := Catalog.data
	var who := str(GameState.world().npc(npc_id).get("name", npc_id))
	title.text = tr("THEFT_TITLE").format({"name": who})
	_box.add_child(_label(tr("THEFT_HINT"), UiTheme.MUTED_LABEL))
	var why := TheftRules.can_steal(s, data, npc_id)
	if not why.is_empty():
		_box.add_child(_label(tr(why)))
		return
	var list: Array = TheftRules.pockets(s, data, npc_id)
	if list.is_empty():
		_box.add_child(_label(tr("THEFT_EMPTY"), UiTheme.MUTED_LABEL))
		return
	var bonus := int(s.character.get("skills", {}).get("sleight_of_hand", 0))
	var can_act := Backend.is_ready() and not GameState.is_busy()
	for e: Dictionary in list:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		_box.add_child(row)
		var name := str(e["name"]) + ((" (%s)" % Money.format(int(e["cp"]))) if int(e.get("cp", 0)) > 0 else "")
		var chance := CombatRules.hit_chance(bonus, int(e["dc"]), s.sneaking, false)
		row.add_child(_label(tr("THEFT_ROW").format({"name": name, "dc": int(e["dc"]), "p": chance})))
		var b := Button.new()
		b.name = "Steal_" + str(e["id"])
		b.text = "BTN_STEAL"
		b.disabled = not can_act
		var entry := str(e["id"])
		b.pressed.connect(func() -> void:
			var err := GameState.steal(npc_id, entry)
			if not err.is_empty():
				EventBus.message.emit(tr(err))
			elif int(s.caught_by.get(npc_id, 0)) == s.day:
				visible = false)
		row.add_child(b)
