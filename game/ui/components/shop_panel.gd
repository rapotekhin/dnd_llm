class_name ShopPanel
extends ModalFrame
## The own trade window (roadmap v0.7.29): "venue" — the hero's shelf in a place or at a stall: the goods with their
## prices (−/+), the till, the hero's shift and what to put out; "registry" — the charter and a stall at the market;
## "supplier" — wholesale lots. Every act is GameState.shop_act: the engine decides.

const SCENE := "res://ui/components/shop_panel.tscn"

var _box: VBoxContainer
var _mode := "venue"
var _id := ""


func _ready() -> void:
	super()
	close_requested.connect(func() -> void: visible = false)
	close_x.name = "CloseShopButton"
	_box = body
	EventBus.state_changed.connect(_rebuild)
	visibility_changed.connect(_rebuild)


func open(mode: String, id: String) -> void:
	_mode = mode
	_id = id
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


func _heading(text: String) -> void:
	_label(_box, text).theme_type_variation = UiTheme.ACCENT_LABEL


func _row(node_name: String, text: String, variation: String = "") -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = node_name
	row.add_theme_constant_override("separation", 10)
	_box.add_child(row)
	_label(row, text, variation)
	return row


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


func _act(what: String, id: String, arg: String = "", amount: int = 0) -> Callable:
	return func() -> String: return GameState.shop_act(what, id, arg, amount)


func _item(s: GameSession, id: String) -> String:
	return ItemRules.display_name(Catalog.data["items"], s.items, id)


func _rebuild() -> void:
	if not visible or not GameState.has_session():
		return
	clear_body()
	var s := GameState.session
	var data := Catalog.data
	_label(_box, tr("BANK_PURSE").format({"money": Money.format(int(s.character.get("gold_cp", 0)))}), UiTheme.MUTED_LABEL)
	match _mode:
		"registry": _registry(s, data)
		"supplier": _supplier(s, data)
		_: _venue(s, data)


func _venue(s: GameSession, data: Dictionary) -> void:
	title.text = tr("SHOP_TITLE_AT").format({"name": ShopRules.name_of(s, data, _id)})
	var loc := ShopRules.loc_of(s, data, _id)
	var bits: Array[String] = [tr("SHOP_HAS_CHARTER") if ShopRules.has_charter(s, loc) else tr("SHOP_NO_CHARTER"),
		tr("SHOP_REP").format({"word": ShopRules.rep_word(data, ShopRules.rep(s, loc))})]
	var st: Dictionary = PropertyRules.state(s.character).get(_id, {})
	if st.has("rent_until"):
		bits.append(tr("SHOP_STALL_UNTIL").format({"day": int(st["rent_until"])}))
	var info := _label(_box, " · ".join(bits), UiTheme.MUTED_LABEL)
	if not ShopRules.has_charter(s, loc):
		info.add_theme_color_override("font_color", UiTheme.WARN)
	_label(_box, tr("SHOP_STAFFED") if ShopRules.staffed(s, _id) else tr("SHOP_UNSTAFFED"), UiTheme.MUTED_LABEL)
	for h: Dictionary in PropertyRules.staff(s, _id):  # the object's staff (v0.7.39.5)
		var who := str(h.get("npc", h.get("cid", "")))
		var hr := _row("Hand_" + who.validate_node_name(), tr("PROPERTY_SERF" if bool(h.get("serf", false)) else "PROPERTY_WORKER").format({
			"name": PropertyRules.hand_name(s, data, h), "role": h.get("role", ""), "wage": Money.format(int(h.get("wage", 0)))}))
		_button(hr, "ShopFire_" + who.validate_node_name(), tr("BTN_PROPERTY_FIRE"), PropertyRules.fire_why(s, data, _id, who), _act("fire", _id, who))
	for p: Dictionary in PropertyRules.places(s, data, _id):
		if int(p["taken"]) < int(p["max"]):
			var pr := _row("ShopPlace_" + str(p["role"]).validate_node_name(), "", UiTheme.MUTED_LABEL)
			_button(pr, "ShopHire_" + str(p["role"]).validate_node_name(), tr("BTN_PROPERTY_HIRE").format({"role": p["role"], "wage": Money.format(int(p["wage"])),
				"taken": int(p["taken"]), "max": int(p["max"])}), PropertyRules.worker_why(s, data, _id, str(p["role"])), _act("hire", _id, str(p["role"])))
	var v := ShopRules.venue(s.character, _id)
	var till := _row("ShopTill", tr("SHOP_TILL").format({"money": Money.format(int(v["cash"]))}))
	_button(till, "ShopCollect", tr("BTN_SHOP_COLLECT"), ShopRules.collect_why(s, data, _id), _act("collect", _id))
	var last: Dictionary = v.get("last", {})
	if not last.is_empty() and int(last.get("cash", 0)) > 0:
		_label(_box, tr("SHOP_LAST").format({"day": int(last["day"]), "money": Money.format(int(last["cash"]))}), UiTheme.MUTED_LABEL)
	var shift := _row("ShopShiftRow", tr("SHOP_SHIFT_HINT").format({"hours": ShopRules.shift_hours(data), "chance": ShopRules.shift_chance(s, data)}), UiTheme.MUTED_LABEL)
	_button(shift, "ShopShift", tr("BTN_SHOP_SHIFT"), ShopRules.shift_why(s, data, _id), _act("shift", _id))
	_box.add_child(HSeparator.new())
	_heading(tr("SHOP_SHELF"))
	var stock: Dictionary = v["stock"]
	if stock.is_empty():
		_label(_box, tr("SHOP_SHELF_EMPTY"), UiTheme.MUTED_LABEL)
	for id: String in stock:
		var row := _row("Shelf_" + id, tr("SHOP_SHELF_ROW").format({"item": _item(s, id), "qty": int(stock[id]), "price": Money.format(ShopRules.price(s, data, _id, id)),
			"pct": ShopRules.price_pct(s, data, _id, id), "value": Money.format(ShopRules.value(s, data, id))}))
		_button(row, "PriceDown_" + id, "−", ShopRules.price_step_why(s, data, _id, id, -1), _act("price", _id, id, -1)).tooltip_text = tr("BTN_SHOP_CHEAPER")
		_button(row, "PriceUp_" + id, "+", ShopRules.price_step_why(s, data, _id, id, 1), _act("price", _id, id, 1)).tooltip_text = tr("BTN_SHOP_DEARER")
		_button(row, "ShelfTake_" + id, tr("BTN_SHOP_TAKE"), ShopRules.take_why(s, data, _id, id), _act("take", _id, id))
	_box.add_child(HSeparator.new())
	_heading(tr("SHOP_YOURS"))
	var any := false
	for id: String in (s.character.get("inventory", {}) as Dictionary).keys():
		var n := TradeRules.sellable(s, id, data)
		if n <= 0 or ShopRules.value(s, data, id) <= 0:
			continue
		var why := ShopRules.put_why(s, data, _id, id)
		if why == "SHOP_TAVERN_FOOD":
			continue
		any = true
		var row := _row("HeroGood_" + id, "%s ×%d · %s" % [_item(s, id), n, Money.format(ShopRules.value(s, data, id))])
		_button(row, "ShelfPut_" + id, tr("BTN_SHOP_PUT_ONE"), why, _act("put", _id, id, 1))
		if n > 1:
			_button(row, "ShelfPutAll_" + id, tr("BTN_SHOP_PUT_ALL").format({"n": n}), why, _act("put", _id, id, n))
	if not any:
		_label(_box, tr("SHOP_NOTHING_TO_PUT"), UiTheme.MUTED_LABEL)


func _registry(s: GameSession, data: Dictionary) -> void:
	title.text = tr("SHOP_TITLE_REGISTRY").format({"name": PropertyRules.npc_name(data, _id)})
	var sc: Dictionary = ShopRules.cfg(data)
	var held := ShopRules.has_charter(s, GameState.world().location_id(s.room_id))
	var ch := _row("CharterRow", tr("SHOP_CHARTER_HINT").format({"fee": Money.format(int(sc["charter"]["fee_cp"])), "tax": int(sc["charter"]["tax_pct"])})
		+ (" · " + tr("SHOP_HAS_CHARTER") if held else ""))
	_button(ch, "CharterBuy", tr("BTN_SHOP_CHARTER").format({"fee": Money.format(int(sc["charter"]["fee_cp"]))}), ShopRules.charter_why(s, data, _id), _act("charter", _id))
	_box.add_child(HSeparator.new())
	var loc := GameState.world().location_id(s.room_id)
	var room := PropertyRules.rent_room(data, "stall", loc)
	if room.is_empty():
		_label(_box, tr("SHOP_NO_MARKET"), UiTheme.MUTED_LABEL)
		return
	var rent: Dictionary = PropertyRules.kind_cfg(data, "stall")["rent"]  # the stall — an object rented (v0.7.39.5)
	var mine := PropertyRules.rented(s, data, "stall", loc)
	var until := int(PropertyRules.state(s.character)[mine]["rent_until"]) if not mine.is_empty() else 0
	_label(_box, tr("SHOP_STALL_HINT").format({"place": GameState.world().room_short(room), "rent": Money.format(int(rent["cp_day"]))})
		+ (" · " + tr("SHOP_STALL_UNTIL").format({"day": until}) if until >= s.day else ""))
	var stall := HBoxContainer.new()
	stall.name = "StallRow"
	stall.alignment = BoxContainer.ALIGNMENT_END
	stall.add_theme_constant_override("separation", 10)
	_box.add_child(stall)
	for d: Variant in rent["days"]:
		_button(stall, "StallRent_%d" % int(d), tr("BTN_SHOP_RENT").format({"days": tr("BANK_DAYS").format({"n": int(d)}), "money": Money.format(int(d) * int(rent["cp_day"]))}),
			PropertyRules.rent_why(s, data, _id, "stall", int(d)), _act("rent", _id, "stall", int(d)))


func _supplier(s: GameSession, data: Dictionary) -> void:
	title.text = tr("SHOP_TITLE_SUPPLIER").format({"name": PropertyRules.npc_name(data, _id)})
	if not ShopRules.has_charter(s, GameState.world().location_id(s.room_id)):
		_label(_box, tr("SHOP_NEED_CHARTER")).theme_type_variation = UiTheme.WARN_LABEL
	var lot := ShopRules.lot(data)
	for id: String in ShopRules.goods(s, data, _id):
		var p := ShopRules.wholesale_price(s, data, _id, id)
		var row := _row("Supply_" + id, tr("SHOP_SUPPLY_ROW").format({"item": _item(s, id), "price": Money.format(p), "value": Money.format(ShopRules.value(s, data, id))}))
		_button(row, "SupplyBuy_" + id, tr("BTN_SHOP_LOT").format({"n": lot, "money": Money.format(p * lot)}), ShopRules.wholesale_why(s, data, _id, id), _act("wholesale", _id, id))
