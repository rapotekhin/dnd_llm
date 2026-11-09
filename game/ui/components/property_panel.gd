class_name PropertyPanel
extends ModalFrame
## The property window (roadmap v0.7.27): at a seller — its places on sale and the price; at the registry — the deed
## for what the hero bought; at a dealer — animals; from the panel — the hero's own places: the deed, the condition,
## the tax, what was set up there, the repair and «Обустроить» while the hero is in it (v0.8.4.42.9: every thing and
## upgrade is set in the build screen at once; hiring and income are out of the game for a while). Every act is
## GameState.property_act: the engine decides.

signal furnish_requested  ## the build screen of the place the hero stands in (v0.8.4.42)

const SCENE := "res://ui/components/property_panel.tscn"

var _box: VBoxContainer
var _npc := ""
var _mode := "mine"
var _rent_days := 3  # v0.7.42: the days of a beast's rent


func _ready() -> void:
	super()
	close_requested.connect(func() -> void: visible = false)
	close_x.name = "ClosePropertyButton"
	_box = body
	EventBus.state_changed.connect(_rebuild)
	visibility_changed.connect(_rebuild)


## "mine" — the hero's places; "seller" / "animals" — at an NPC.
func open(mode: String, npc_id: String = "") -> void:
	_mode = mode
	_npc = npc_id
	visible = true
	_rebuild()


func _act(what: String, id: String, arg: String = "") -> Callable:
	return func() -> String: return GameState.property_act(what, id, arg)


func _rebuild() -> void:
	if not visible or not GameState.has_session():
		return
	clear_body()
	var s := GameState.session
	var data := Catalog.data
	var who := str(GameState.world().npc(_npc).get("name", _npc))
	match _mode:
		"seller":
			title.text = tr("PROPERTY_TITLE_AT").format({"name": who})
			var ids := PropertyRules.of_seller(s, data, _npc)
			var deeds: Array[String] = []
			var debts: Array[String] = []
			if PropertyRules.is_registry(data, _npc):
				for id: String in PropertyRules.state(s.character):
					if not bool(PropertyRules.state(s.character)[id].get("deed", false)):
						deeds.append(id)
					if Ledger.owed(s, "tax:" + id) > 0:
						debts.append(id)
			if ids.is_empty() and deeds.is_empty() and debts.is_empty():
				UiParts.label(_box, tr("PROPERTY_NONE_ON_SALE"), UiTheme.MUTED_LABEL)
			for id: String in deeds:
				_deed_row(s, data, id)
			for id: String in debts:
				_tax_row(s, data, id)
			for id: String in ids:
				_sale_row(s, data, id)
		"animals":
			title.text = tr("PROPERTY_ANIMALS_AT").format({"name": who})
			if MountRules.on(data):  # v0.7.42: the days of a rent by «−/+»
				_rent_row(data)
			for m: String in PropertyRules.animals_of(data, _npc):
				_animal_row(s, data, m)
			if MountRules.on(data):  # v0.7.42: carts, and the hero's own beasts bought back
				for v: String in MountRules.vehicles_of(data, _npc):
					_vehicle_row(s, data, v)
				for cr: Dictionary in MountRules.sellable(s, data, _npc):
					_sell_animal_row(s, data, cr)
		_:
			title.text = tr("PROPERTY_TITLE")
			var mine := PropertyRules.state(s.character).keys()
			if mine.is_empty():
				UiParts.label(_box, tr("PROPERTY_NONE_OWNED"), UiTheme.MUTED_LABEL)
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
				UiParts.label(_box, tr("PROPERTY_ANIMALS").format({"list": "; ".join(names)}))


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
	var t := UiParts.label(col, text)
	t.add_theme_color_override("font_color", UiTheme.ACCENT)


func _sale_row(s: GameSession, data: Dictionary, id: String) -> void:
	var parts := _row(id)
	var col: Control = parts[0]
	var p := PropertyRules.prop(s, data, id)
	var k: Dictionary = PropertyRules.kinds(data).get(str(p.get("kind", "")), {})
	_title(col, str(p.get("name", id)))
	var site := GameState.world().site(str(p.get("site", "")))
	if not str(site.get("description", "")).is_empty():
		UiParts.label(col, str(site["description"]), UiTheme.MUTED_LABEL)
	var bits: Array[String] = [tr("PROPERTY_KIND").format({"kind": k.get("name", "")})]
	var inc := int(p.get("income_cp_day", k.get("income_cp_day", 0)))
	if inc > 0:
		bits.append(tr("PROPERTY_INCOME").format({"money": Money.format(inc)}))
	if p.has("condition"):
		bits.append(tr("PROPERTY_COND").format({"n": int(p["condition"])}))
	if bool(k.get("buildable", false)):
		bits.append(tr("PROPERTY_BUILDABLE"))
	UiParts.label(col, " · ".join(bits), UiTheme.MUTED_LABEL)
	UiParts.label(col, tr("PROPERTY_PRICE").format({"price": Money.format(PropertyRules.price(s, data, id)), "fee": Money.format(PropertyRules.deed_fee(s, data, id)),
		"tax": Money.format(PropertyRules.tax(s, data, id))}), UiTheme.MUTED_LABEL)
	UiParts.act_button(parts[1], "PropertyBuy_" + id, tr("BTN_PROPERTY_BUY").format({"price": Money.format(PropertyRules.price(s, data, id))}),
		PropertyRules.buy_why(s, data, id), _act("buy", id))


func _deed_row(s: GameSession, data: Dictionary, id: String) -> void:
	var parts := _row(id)
	_title(parts[0], PropertyRules.name_of(s, data, id))
	UiParts.label(parts[0], tr("PROPERTY_DEED_HINT").format({"tax": Money.format(PropertyRules.tax(s, data, id))}), UiTheme.MUTED_LABEL)
	UiParts.act_button(parts[1], "PropertyDeed_" + id, tr("BTN_PROPERTY_DEED").format({"fee": Money.format(PropertyRules.deed_fee(s, data, id))}),
		PropertyRules.deed_why(s, data, id), _act("deed", id))


func _tax_row(s: GameSession, data: Dictionary, id: String) -> void:
	var parts := _row(id + "_tax")
	_title(parts[0], PropertyRules.name_of(s, data, id))
	UiParts.label(parts[0], tr("PROPERTY_DEBT").format({"money": Money.format(Ledger.owed(s, "tax:" + id))})).theme_type_variation = UiTheme.WARN_LABEL
	UiParts.act_button(parts[1], "PropertyTax_" + id, tr("BTN_PROPERTY_TAX"), PropertyRules.pay_tax_why(s, data, id), _act("tax", id))


func _animal_row(s: GameSession, data: Dictionary, m: String) -> void:
	var parts := _row(m)
	var a := PropertyRules.animal_cfg(data, m)
	_title(parts[0], str(data["monsters"][m]["name"]))
	UiParts.label(parts[0], "%s · %s" % [str(a.get("text", "")), tr("PROPERTY_FEED").format({"money": Money.format(int(a["feed_cp_day"]))})], UiTheme.MUTED_LABEL)
	UiParts.act_button(parts[1], "AnimalBuy_" + m, tr("BTN_PROPERTY_BUY").format({"price": Money.format(int(a["price_cp"]))}),
		PropertyRules.animal_why(s, data, _npc, m), _act("animal", _npc, m))
	if not MountRules.on(data):
		return
	var cap := MountRules.capacity(data, {"monster": m})
	if cap > 0:
		UiParts.label(parts[0], tr("MOUNT_CARRIES").format({"lb": roundi(cap), "pull": int(a.get("pull", 0))}), UiTheme.MUTED_LABEL)
	var days := _rent_days
	UiParts.act_button(parts[1], "AnimalRent_" + m, tr("BTN_MOUNT_RENT").format({"days": days, "price": Money.format(MountRules.rent_price(data, m, days))}),
		MountRules.rent_why(s, data, _npc, m, days), _act("rent", _npc, "%s:%d" % [m, days]))


func _rent_row(data: Dictionary) -> void:
	var span: Array = MountRules.cfg(data)["rent_days"]
	var row := HBoxContainer.new()
	row.name = "RentDays"
	row.add_theme_constant_override("separation", 8)
	_box.add_child(row)
	var l := UiParts.label(row, tr("MOUNT_RENT_DAYS_LABEL").format({"days": _rent_days}))
	l.name = "RentDaysLabel"
	for spec: Array in [["RentMinus", "−", -1], ["RentPlus", "+", 1]]:
		var b := Button.new()
		b.name = spec[0]
		b.text = spec[1]
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		b.custom_minimum_size = Vector2(44, 0)
		var step := int(spec[2])
		b.disabled = (step < 0 and _rent_days <= int(span[0])) or (step > 0 and _rent_days >= int(span[1]))
		b.pressed.connect(func() -> void:
			_rent_days = clampi(_rent_days + step, int(span[0]), int(span[1]))
			_rebuild.call_deferred())
		row.add_child(b)


func _vehicle_row(s: GameSession, data: Dictionary, v: String) -> void:
	var parts := _row(v)
	var d := MountRules.vehicle(data, v)
	_title(parts[0], str(d["name"]))
	UiParts.label(parts[0], tr("MOUNT_VEHICLE").format({"lb": int(d["capacity_lb"]), "pull": int(d["pull"])}), UiTheme.MUTED_LABEL)
	UiParts.act_button(parts[1], "VehicleBuy_" + v, tr("BTN_PROPERTY_BUY").format({"price": Money.format(int(d["price_cp"]))}),
		MountRules.vehicle_why(s, data, _npc, v), _act("vehicle", _npc, v))


func _sell_animal_row(s: GameSession, data: Dictionary, cr: Dictionary) -> void:
	var cid := str(cr["id"])
	var parts := _row("own_" + cid)
	_title(parts[0], tr("MOUNT_YOURS").format({"name": cr["name"]}))
	UiParts.act_button(parts[1], "AnimalSell_" + cid, tr("BTN_MOUNT_SELL").format({"price": Money.format(MountRules.sell_price(data, cr))}),
		MountRules.sell_why(s, data, _npc, cid), _act("sell_animal", _npc, cid))


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
	if int(st.get("cash", 0)) > 0:
		bits.append(tr("PROPERTY_TILL").format({"money": Money.format(int(st.get("cash", 0)))}))
	var debt := Ledger.owed(s, "tax:" + id)
	if debt > 0:
		bits.append(tr("PROPERTY_DEBT").format({"money": Money.format(debt)}))
	var dl := UiParts.label(col, " · ".join(bits), UiTheme.MUTED_LABEL)
	if not bool(st.get("deed", false)) or debt > 0:
		dl.add_theme_color_override("font_color", UiTheme.WARN)
	if st.has("rent_day"):
		var rl := UiParts.label(col, tr("PROPERTY_RENT_UNTIL").format({"day": int(st["rent_day"])}), UiTheme.MUTED_LABEL)
		if PropertyRules.lapsed(s, id):
			rl.add_theme_color_override("font_color", UiTheme.WARN)
	for h: Dictionary in PropertyRules.staff(s, id):  # the staff (v0.7.39.5): each person with the role
		var who := str(h.get("npc", h.get("cid", "")))
		var hr := HBoxContainer.new()
		hr.name = "Hand_" + who.validate_node_name()
		hr.add_theme_constant_override("separation", 8)
		col.add_child(hr)
		UiParts.label(hr, tr("PROPERTY_SERF" if bool(h.get("serf", false)) else "PROPERTY_WORKER").format({"name": PropertyRules.hand_name(s, data, h),
			"role": h.get("role", ""), "wage": Money.format(int(h.get("wage", 0)))}))
		if here:
			_offer(hr, "PropertyFire_" + who.validate_node_name(), tr("BTN_PROPERTY_FIRE"), PropertyRules.fire_why(s, data, id, who), _act("fire", id, who))
	var ups: Array[String] = []
	for u: Variant in st.get("upgrades", []):
		ups.append(str(PropertyRules.ups(data).get(str(u), {}).get("name", u)))
	if not ups.is_empty():
		UiParts.label(col, tr("PROPERTY_UPGRADES").format({"list": ", ".join(ups)}), UiTheme.MUTED_LABEL)
	if debt > 0:
		UiParts.act_button(buttons, "PropertyTax_" + id, tr("BTN_PROPERTY_TAX"), PropertyRules.pay_tax_why(s, data, id), _act("tax", id))
	if not here:
		UiParts.label(col, tr("PROPERTY_GO_THERE"), UiTheme.MUTED_LABEL)
		return
	UiParts.act_button(buttons, "PropertyFurnish_" + id, tr("BTN_PROPERTY_FURNISH"), BuildRules.where_why(s, data), func() -> String:
		furnish_requested.emit()
		return "").tooltip_text = tr("BTN_PROPERTY_FURNISH_TIP")
	if PropertyRules.collect_why(s, data, id).is_empty():  # what a beast gave, what is left in the till
		UiParts.act_button(buttons, "PropertyCollect_" + id, tr("BTN_PROPERTY_COLLECT"), "", _act("collect", id))
	if PropertyRules.income_day(s, data, id) > 0:
		var sb := UiParts.act_button(buttons, "PropertyShift_" + id, tr("BTN_PROPERTY_SHIFT").format({"time": TimeRules.span(PropertyRules.shift_hours(s, data, id) * 60)}),
			PropertyRules.shift_why(s, data, id), _act("shift", id))
		sb.tooltip_text = tr("PROPERTY_SHIFT_TIP").format({"skill": CraftRules.tr_skill(data, str(k.get("skill", "athletics"))),
			"dc": PropertyRules.shift_dc(data), "chance": PropertyRules.shift_chance(s, data, id)}) if sb.tooltip_text.is_empty() else sb.tooltip_text
	for cr: Dictionary in CreatureRules.here(s, s.room_id):
		if PropertyRules.serf_why(s, data, id, str(cr["id"])).is_empty():
			UiParts.act_button(buttons, "PropertySerf_" + str(cr["id"]), tr("BTN_PROPERTY_SERF").format({"name": cr["name"]}), "", _act("serf", id, str(cr["id"])))
	if bool(k.get("decay", true)) and float(st.get("cond", 100.0)) < 100.0:
		var lost := 100.0 - float(st.get("cond", 100.0))
		UiParts.act_button(buttons, "PropertyRepair_" + id, tr("BTN_PROPERTY_REPAIR").format({"cost": Money.format(PropertyRules.repair_cost(s, data, id, lost)),
			"time": TimeRules.span(PropertyRules.repair_hours(s, data, id) * 60)}), PropertyRules.repair_why(s, data, id), _act("repair", id))
	var offers := VBoxContainer.new()
	offers.name = "PropertyOffers_" + id
	offers.add_theme_constant_override("separation", 4)
	col.add_child(offers)
	for p: Dictionary in PropertyRules.places(s, data, id):  # a hire per role while its places are free (none while staff is off)
		if int(p["taken"]) < int(p["max"]):
			_offer(offers, "PropertyHire_" + str(p["role"]).validate_node_name(), tr("BTN_PROPERTY_HIRE").format({"role": p["role"],
				"wage": Money.format(int(p["wage"])), "taken": int(p["taken"]), "max": int(p["max"])}), PropertyRules.worker_why(s, data, id, str(p["role"])),
				_act("hire", id, str(p["role"])))


## A hire as a small row: its button and wage; the reason in the tooltip.
func _offer(parent: Control, node_name: String, text: String, why: String, action: Callable) -> Button:
	var b := UiParts.act_button(parent, node_name, text, why, action)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", UiTheme.SIZE_SMALL)
	return b
