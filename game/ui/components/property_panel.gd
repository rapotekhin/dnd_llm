class_name PropertyPanel
extends Control
## The property window (roadmap v0.7.27): at a seller — its places on sale and the price; at the registry — the deed
## for what the hero bought; at a dealer — animals; from the panel — the hero's own places: the deed, the condition,
## the till, the worker, upgrades and building, and the acts of the place while the hero is in it. Every act is
## GameState.property_act: the engine decides.

var _box: VBoxContainer
var frame: ModalFrame
var _npc := ""
var _mode := "mine"


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame = ModalFrame.new(tr("PROPERTY_TITLE"), 860.0)
	add_child(frame)
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.close_requested.connect(func() -> void: visible = false)
	frame.close_x.name = "ClosePropertyButton"
	_box = frame.body
	EventBus.state_changed.connect(_rebuild)
	visibility_changed.connect(_rebuild)


## "mine" — the hero's places; "seller" / "animals" — at an NPC.
func open(mode: String, npc_id: String = "") -> void:
	_mode = mode
	_npc = npc_id
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


func _button(parent: Control, node_name: String, text: String, why: String, action: Callable) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.disabled = not why.is_empty() or GameState.is_busy()
	b.tooltip_text = tr(why) if not why.is_empty() else ""
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(func() -> void:
		var err: String = action.call()
		if not err.is_empty():
			EventBus.message.emit(tr(err)))
	parent.add_child(b)
	return b


func _act(what: String, id: String, arg: String = "") -> Callable:
	return func() -> String: return GameState.property_act(what, id, arg)


func _rebuild() -> void:
	if not visible or not GameState.has_session():
		return
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	var s := GameState.session
	var data := Catalog.data
	var who := str(GameState.world().npc(_npc).get("name", _npc))
	match _mode:
		"seller":
			frame.title.text = tr("PROPERTY_TITLE_AT").format({"name": who})
			var ids := PropertyRules.of_seller(s, data, _npc)
			var deeds: Array[String] = []
			var debts: Array[String] = []
			if PropertyRules.is_registry(data, _npc):
				for id: String in PropertyRules.state(s.character):
					if not bool(PropertyRules.state(s.character)[id].get("deed", false)):
						deeds.append(id)
					if int(PropertyRules.state(s.character)[id].get("debt", 0)) > 0:
						debts.append(id)
			if ids.is_empty() and deeds.is_empty() and debts.is_empty():
				_label(_box, tr("PROPERTY_NONE_ON_SALE"), UiTheme.MUTED_LABEL)
			for id: String in deeds:
				_deed_row(s, data, id)
			for id: String in debts:
				_tax_row(s, data, id)
			for id: String in ids:
				_sale_row(s, data, id)
		"animals":
			frame.title.text = tr("PROPERTY_ANIMALS_AT").format({"name": who})
			for m: String in PropertyRules.animals_of(data, _npc):
				_animal_row(s, data, m)
		_:
			frame.title.text = tr("PROPERTY_TITLE")
			var mine := PropertyRules.state(s.character).keys()
			if mine.is_empty():
				_label(_box, tr("PROPERTY_NONE_OWNED"), UiTheme.MUTED_LABEL)
			for i in mine.size():
				if i > 0:
					_box.add_child(HSeparator.new())
				_own(s, data, str(mine[i]))
			var beasts := PropertyRules.animals(s)
			if not beasts.is_empty():
				_box.add_child(HSeparator.new())
				var names: Array[String] = []
				for cr: Dictionary in beasts:
					names.append("%s — %s" % [cr["name"], tr("PROPERTY_ANIMAL_WITH_YOU") if bool(cr.get("led", false)) else
						GameState.world().room_short(PropertyRules.room_of(s, str(cr["id"])))])
				_label(_box, tr("PROPERTY_ANIMALS").format({"list": "; ".join(names)}))


func _row(id: String) -> Array:
	var row := HBoxContainer.new()
	row.name = "Property_" + id
	row.add_theme_constant_override("separation", 10)
	_box.add_child(row)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 2)
	row.add_child(col)
	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	row.add_child(buttons)
	return [col, buttons]


func _title(col: Control, text: String) -> void:
	var t := _label(col, text)
	t.add_theme_color_override("font_color", UiTheme.ACCENT)


func _sale_row(s: GameSession, data: Dictionary, id: String) -> void:
	var parts := _row(id)
	var col: Control = parts[0]
	var p := PropertyRules.prop(s, data, id)
	var k: Dictionary = PropertyRules.kinds(data).get(str(p.get("kind", "")), {})
	_title(col, str(p.get("name", id)))
	var site := GameState.world().site(str(p.get("site", "")))
	if not str(site.get("description", "")).is_empty():
		_label(col, str(site["description"]), UiTheme.MUTED_LABEL)
	var bits: Array[String] = [tr("PROPERTY_KIND").format({"kind": k.get("name", "")})]
	var inc := int(p.get("income_cp_day", k.get("income_cp_day", 0)))
	if inc > 0:
		bits.append(tr("PROPERTY_INCOME").format({"money": Money.format(inc)}))
	if p.has("condition"):
		bits.append(tr("PROPERTY_COND").format({"n": int(p["condition"])}))
	if bool(k.get("buildable", false)):
		bits.append(tr("PROPERTY_BUILDABLE"))
	_label(col, " · ".join(bits), UiTheme.MUTED_LABEL)
	_label(col, tr("PROPERTY_PRICE").format({"price": Money.format(PropertyRules.price(s, data, id)), "fee": Money.format(PropertyRules.deed_fee(s, data, id)),
		"tax": Money.format(PropertyRules.tax(s, data, id))}), UiTheme.MUTED_LABEL)
	_button(parts[1], "PropertyBuy_" + id, tr("BTN_PROPERTY_BUY").format({"price": Money.format(PropertyRules.price(s, data, id))}),
		PropertyRules.buy_why(s, data, id), _act("buy", id))


func _deed_row(s: GameSession, data: Dictionary, id: String) -> void:
	var parts := _row(id)
	_title(parts[0], PropertyRules.name_of(s, data, id))
	_label(parts[0], tr("PROPERTY_DEED_HINT").format({"tax": Money.format(PropertyRules.tax(s, data, id))}), UiTheme.MUTED_LABEL)
	_button(parts[1], "PropertyDeed_" + id, tr("BTN_PROPERTY_DEED").format({"fee": Money.format(PropertyRules.deed_fee(s, data, id))}),
		PropertyRules.deed_why(s, data, id), _act("deed", id))


func _tax_row(s: GameSession, data: Dictionary, id: String) -> void:
	var parts := _row(id + "_tax")
	_title(parts[0], PropertyRules.name_of(s, data, id))
	_label(parts[0], tr("PROPERTY_DEBT").format({"money": Money.format(int(PropertyRules.state(s.character)[id]["debt"]))})).add_theme_color_override("font_color", UiTheme.WARN)
	_button(parts[1], "PropertyTax_" + id, tr("BTN_PROPERTY_TAX"), PropertyRules.pay_tax_why(s, data, id), _act("tax", id))


func _animal_row(s: GameSession, data: Dictionary, m: String) -> void:
	var parts := _row(m)
	var a := PropertyRules.animal_cfg(data, m)
	_title(parts[0], str(data["monsters"][m]["name"]))
	_label(parts[0], "%s · %s" % [str(a.get("text", "")), tr("PROPERTY_FEED").format({"money": Money.format(int(a["feed_cp_day"]))})], UiTheme.MUTED_LABEL)
	_button(parts[1], "AnimalBuy_" + m, tr("BTN_PROPERTY_BUY").format({"price": Money.format(int(a["price_cp"]))}),
		PropertyRules.animal_why(s, data, _npc, m), _act("animal", _npc, m))


func _own(s: GameSession, data: Dictionary, id: String) -> void:
	var parts := _row(id)
	var col: Control = parts[0]
	var buttons: Control = parts[1]
	var st: Dictionary = PropertyRules.state(s.character)[id]
	var k := PropertyRules.kind(s, data, id)
	var here := PropertyRules.here(s, data) == id
	_title(col, "%s (%s)" % [PropertyRules.name_of(s, data, id), k.get("name", "")])
	var bits: Array[String] = [tr("PROPERTY_HAS_DEED") if bool(st.get("deed", false)) else tr("PROPERTY_NO_DEED")]
	if bool(k.get("decay", true)):
		bits.append(tr("PROPERTY_COND").format({"n": int(st.get("cond", 100))}))
	if PropertyRules.income_day(s, data, id) > 0:
		bits.append(tr("PROPERTY_INCOME").format({"money": Money.format(PropertyRules.income_day(s, data, id))}))
	bits.append(tr("PROPERTY_TILL").format({"money": Money.format(int(st.get("cash", 0)))}))
	if int(st.get("debt", 0)) > 0:
		bits.append(tr("PROPERTY_DEBT").format({"money": Money.format(int(st["debt"]))}))
	var dl := _label(col, " · ".join(bits), UiTheme.MUTED_LABEL)
	if not bool(st.get("deed", false)) or int(st.get("debt", 0)) > 0:
		dl.add_theme_color_override("font_color", UiTheme.WARN)
	if st.has("rent_until"):
		var rl := _label(col, tr("PROPERTY_RENT_UNTIL").format({"day": int(st["rent_until"])}), UiTheme.MUTED_LABEL)
		if PropertyRules.lapsed(s, id):
			rl.add_theme_color_override("font_color", UiTheme.WARN)
	for h: Dictionary in PropertyRules.staff(s, id):  # the staff (v0.7.39.5): each person with the role
		var who := str(h.get("npc", h.get("cid", "")))
		var hr := HBoxContainer.new()
		hr.name = "Hand_" + who.validate_node_name()
		hr.add_theme_constant_override("separation", 8)
		col.add_child(hr)
		_label(hr, tr("PROPERTY_SERF" if bool(h.get("serf", false)) else "PROPERTY_WORKER").format({"name": PropertyRules.hand_name(s, data, h),
			"role": h.get("role", ""), "wage": Money.format(int(h.get("wage", 0)))}))
		if here:
			_offer(hr, "PropertyFire_" + who.validate_node_name(), tr("BTN_PROPERTY_FIRE"), PropertyRules.fire_why(s, data, id, who), _act("fire", id, who))
	var ups: Array[String] = []
	for u: Variant in st.get("upgrades", []):
		ups.append(str(PropertyRules.ups(data).get(str(u), {}).get("name", u)))
	for pd: Dictionary in st.get("pending", []):
		ups.append(tr("PROPERTY_PENDING").format({"name": PropertyRules.ups(data)[str(pd["up"])]["name"], "day": int(pd["ready"])}))
	var b: Dictionary = st.get("building", {})
	if not b.is_empty():
		ups.append(tr("PROPERTY_PENDING").format({"name": PropertyRules.cfg(data)["build"][str(b["id"])]["name"], "day": int(b["ready"])}))
	if not ups.is_empty():
		_label(col, tr("PROPERTY_UPGRADES").format({"list": ", ".join(ups)}), UiTheme.MUTED_LABEL)
	if int(st.get("debt", 0)) > 0:
		_button(buttons, "PropertyTax_" + id, tr("BTN_PROPERTY_TAX"), PropertyRules.pay_tax_why(s, data, id), _act("tax", id))
	if not here:
		_label(col, tr("PROPERTY_GO_THERE"), UiTheme.MUTED_LABEL)
		return
	_button(buttons, "PropertyCollect_" + id, tr("BTN_PROPERTY_COLLECT"), PropertyRules.collect_why(s, data, id), _act("collect", id))
	if PropertyRules.income_day(s, data, id) > 0:
		var sb := _button(buttons, "PropertyShift_" + id, tr("BTN_PROPERTY_SHIFT").format({"time": TimeRules.span(PropertyRules.shift_hours(s, data, id) * 60)}),
			PropertyRules.shift_why(s, data, id), _act("shift", id))
		sb.tooltip_text = tr("PROPERTY_SHIFT_TIP").format({"skill": CraftRules.tr_skill(data, str(k.get("skill", "athletics"))),
			"dc": PropertyRules.shift_dc(data), "chance": PropertyRules.shift_chance(s, data, id)}) if sb.tooltip_text.is_empty() else sb.tooltip_text
	for cr: Dictionary in CreatureRules.here(s, s.room_id):
		if PropertyRules.serf_why(s, data, id, str(cr["id"])).is_empty():
			_button(buttons, "PropertySerf_" + str(cr["id"]), tr("BTN_PROPERTY_SERF").format({"name": cr["name"]}), "", _act("serf", id, str(cr["id"])))
	if bool(k.get("decay", true)) and float(st.get("cond", 100.0)) < 100.0:
		var lost := 100.0 - float(st.get("cond", 100.0))
		_button(buttons, "PropertyRepair_" + id, tr("BTN_PROPERTY_REPAIR").format({"cost": Money.format(PropertyRules.repair_cost(s, data, id, lost)),
			"time": TimeRules.span(PropertyRules.repair_hours(s, data, id) * 60)}), PropertyRules.repair_why(s, data, id), _act("repair", id))
	var offers := VBoxContainer.new()
	offers.name = "PropertyOffers_" + id
	offers.add_theme_constant_override("separation", 4)
	col.add_child(offers)
	for p: Dictionary in PropertyRules.places(s, data, id):  # a hire per role while its places are free
		if int(p["taken"]) < int(p["max"]):
			_offer(offers, "PropertyHire_" + str(p["role"]).validate_node_name(), tr("BTN_PROPERTY_HIRE").format({"role": p["role"],
				"wage": Money.format(int(p["wage"])), "taken": int(p["taken"]), "max": int(p["max"])}), PropertyRules.worker_why(s, data, id, str(p["role"])),
				_act("hire", id, str(p["role"])))
	if bool(k.get("buildable", false)):
		for bid: String in PropertyRules.cfg(data)["build"]:
			var bc: Dictionary = PropertyRules.cfg(data)["build"][bid]
			_offer(offers, "PropertyBuild_" + bid, tr("BTN_PROPERTY_BUILD").format({"name": bc["name"], "price": Money.format(int(bc["price_cp"])),
				"days": int(bc["days"])}), PropertyRules.build_why(s, data, id, bid), _act("build", id, bid))
	for up: String in PropertyRules.upgrades_for(s, data, id):
		if PropertyRules.has_upgrade(s.character, id, up) or not PropertyRules.pending(s.character, id, up).is_empty():
			continue
		var u: Dictionary = PropertyRules.ups(data)[up]
		var ob := _offer(offers, "PropertyUpgrade_" + up, tr("BTN_PROPERTY_UPGRADE").format({"name": u["name"], "price": Money.format(int(u["price_cp"])),
			"days": int(u.get("days", 0))}), PropertyRules.upgrade_why(s, data, id, up), _act("upgrade", id, up))
		if ob.tooltip_text.is_empty():
			ob.tooltip_text = str(u.get("text", ""))


## An upgrade or a building as a small row: its button and price; the reason in the tooltip.
func _offer(parent: Control, node_name: String, text: String, why: String, action: Callable) -> Button:
	var b := _button(parent, node_name, text, why, action)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", UiTheme.SIZE_SMALL)
	return b
