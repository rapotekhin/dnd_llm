class_name PlacePanel
extends ModalFrame
## «Взаимодействие с местом» (roadmap v0.7.22.7, big test #17): every thing of the room in one window — take one,
## open a container, look closer — and «Забрать всё» on top; the bodies to search. Built like the container window.
## v0.7.39.5: on top — the object the room belongs to (ObjectRules): its kind, owner, staff, upgrades, hours, chronicle.

const SCENE := "res://ui/components/place_panel.tscn"

signal container_requested(prop_id: String)

var _box: VBoxContainer


func _ready() -> void:
	super()
	close_requested.connect(func() -> void: visible = false)
	close_x.name = "ClosePlaceButton"
	_box = body
	EventBus.state_changed.connect(_rebuild)
	visibility_changed.connect(_rebuild)


func open() -> void:
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


func _button(row: Control, node_name: String, text: String, enabled: bool, action: Callable) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.disabled = not enabled
	b.pressed.connect(func() -> void:
		var err: String = action.call()
		if err.is_empty():
			visible = false
		else:
			EventBus.message.emit(tr(err)))
	row.add_child(b)
	return b


## The object card: «Кузница (мастерская) · хозяин Горан» and its staff, upgrades, hours and chronicle.
func _object(s: GameSession, data: Dictionary) -> void:
	var sid := GameState.world().site_id(s.room_id)
	if sid.is_empty():
		return
	var i := ObjectRules.info(s, data, sid)
	var card := VBoxContainer.new()
	card.name = "ObjectCard"
	_box.add_child(card)
	var head := str(i["name"]) + ((" (%s)" % i["kind"]) if not str(i["kind"]).is_empty() else "")
	if not str(i["owner"]).is_empty():
		head += " · " + tr("PLACE_OWNER").format({"name": i["owner"]})
	var h := _label(head)  # under the window's title: the object, not a second title
	h.add_theme_color_override("font_color", UiTheme.ACCENT)
	card.add_child(h)
	var bits: Array[String] = []
	var people: Array = (i["staff"] as Array).filter(func(x: Dictionary) -> bool: return str(x["source"]) != "owner")
	if not people.is_empty():
		bits.append(tr("OBJECT_STAFF").format({"list": ", ".join(people.map(func(x: Dictionary) -> String: return "%s — %s" % [x["name"], x["role"]]))}))
	if not (i["upgrades"] as Array).is_empty():
		bits.append(tr("OBJECT_UPGRADES").format({"list": ", ".join(i["upgrades"])}))
	if not str(i["hours"]).is_empty():
		bits.append(tr("OBJECT_HOURS").format({"hours": i["hours"]}))
	if not bool(i["public"]):
		bits.append(tr("OBJECT_PRIVATE"))
	for b: String in bits:
		card.add_child(_label(b, UiTheme.MUTED_LABEL))
	var f: Array = i["facts"]
	if not f.is_empty():
		card.add_child(_label(tr("OBJECT_FACTS").format({"list": "; ".join(f.slice(maxi(0, f.size() - 3)))}), UiTheme.MUTED_LABEL))


func _rebuild() -> void:
	if not visible or not GameState.has_session():
		return
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	var s := GameState.session
	var data := Catalog.data
	PropRules.ensure_wares(s, data, s.room_id)  # the trader's wares (v0.7.22.8)
	var can_act := Backend.is_ready() and not GameState.is_busy() and not s.in_conversation() and not CombatRules.active(s)
	title.text = str(GameState.world().room(s.room_id).get("name", s.room_id))
	_object(s, data)
	var takeable: Array = PropRules.take_all_plan(s, data)["take"]
	var top := HBoxContainer.new()
	_box.add_child(top)
	var tb := _button(top, "TakeAllButton", tr("BTN_TAKE_ALL"), can_act and not takeable.is_empty(), GameState.take_all)
	tb.tooltip_text = tr("TAKE_ALL_TIP").format({"list": ", ".join(takeable.map(func(p: Dictionary) -> String: return str(p["name"])))}) \
		if not takeable.is_empty() else tr("TAKE_ALL_NOTHING")
	var props := PropRules.room_props(s, s.room_id)
	var bodies := CrimeRules.bodies_here(s, data)
	if props.is_empty() and bodies.is_empty():
		_box.add_child(_label(tr("PLACE_EMPTY"), UiTheme.MUTED_LABEL))
	for p: Dictionary in props:
		_box.add_child(HSeparator.new())
		var pid := str(p["id"])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		_box.add_child(row)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		var owner := str(p.get("owner", ""))
		var head := str(p["name"])
		if not owner.is_empty():
			head += " · " + tr("PLACE_OWNER").format({"name": GameState.world().npc(owner).get("name", owner)})
		if not str(p.get("state", "")).is_empty():
			head += " · " + tr("PROP_STATE_" + str(p["state"]).to_upper())
		info.add_child(_label(head))
		if not str(p.get("description", "")).is_empty():
			info.add_child(_label(str(p["description"]), UiTheme.MUTED_LABEL))
		if ContainerRules.is_container(p):
			_button(row, "Container_" + pid, tr("BTN_OPEN_SHORT"), not GameState.is_busy(), func() -> String:
				container_requested.emit(pid)
				return "")
		var take_why := str(PropRules.plan_take(s, data, {"prop_id": pid}).get("reason", ""))
		if not str(p.get("item_id", "")).is_empty():
			var t := _button(row, "Take_" + pid, tr("BTN_TAKE"), can_act and take_why.is_empty(), GameState.take_prop.bind(pid))
			t.tooltip_text = take_why if not take_why.is_empty() else (tr("PLACE_TAKE_OWNED") if not owner.is_empty() else "")
		_button(row, "Look_" + pid, tr("BTN_LOOK_AT"), can_act, func() -> String:
			return "" if GameState.submit(tr("PLACE_LOOK_SAY").format({"name": p["name"]})) else "WAIT_BUSY")
	for corpse: Dictionary in bodies:
		_box.add_child(HSeparator.new())
		var row := HBoxContainer.new()
		_box.add_child(row)
		row.add_child(_label(str(corpse["name"]) + (" · " + tr("PLACE_SEARCHED") if bool(corpse["searched"]) else "")))
		var bid := str(corpse["npc_id"])
		if not bool(corpse["searched"]):
			_button(row, "PlaceBody_" + bid, tr("BTN_SEARCH_SHORT"), can_act, GameState.search_body.bind(bid))
		if CrimeRules.can_hide(s, data, bid).is_empty():  # v0.7.22.10: a secret murder — hide the body
			var hb := _button(row, "HideBody_" + bid, tr("BTN_HIDE_BODY"), can_act, GameState.hide_body.bind(bid))
			hb.tooltip_text = tr("BTN_HIDE_BODY_TIP")
