class_name ShopPanel
extends Control
## The own trade window (roadmap v0.7.29): "venue" — the hero's shelf in a place or at a stall: the goods with their
## prices (−/+), the till, the hero's shift and what to put out; "registry" — the charter and a stall at the market;
## "supplier" — wholesale lots. Every act is GameState.shop_act: the engine decides.

var _box: VBoxContainer
var frame: ModalFrame
var _mode := "venue"
var _id := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame = ModalFrame.new(tr("SHOP_TITLE"), 860.0)
	add_child(frame)
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.close_requested.connect(func() -> void: visible = false)
	frame.close_x.name = "CloseShopButton"
	_box = frame.body
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
	_label(_box, text).add_theme_color_override("font_color", UiTheme.ACCENT)


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
	frame.clear_body()
	var s := GameState.session
	var data := Catalog.data
	_label(_box, tr("BANK_PURSE").format({"money": Money.format(int(s.character.get("gold_cp", 0)))}), UiTheme.MUTED_LABEL)
	match _mode:
		"registry": _registry(s, data)
		"supplier": _supplier(s, data)
		_: _venue(s, data)


func _venue(s: GameSession, data: Dictionary) -> void:
	frame.title.text = tr("SHOP_TITLE_AT").format({"name": ShopRules.name_of(s, data, _id)})
	var loc := ShopRules.loc_of(s, data, _id)
	var bits: Array[String] = [tr("SHOP_HAS_CHARTER") if ShopRules.has_charter(s, loc) else tr("SHOP_NO_CHARTER"),
		tr("SHOP_REP").format({"word": ShopRules.rep_word(data, ShopRules.rep(s, loc))})]
	if ShopRules.is_stall(_id):
		bits.append(tr("SHOP_STALL_UNTIL").format({"day": int(ShopRules.state(s.character)["stalls"].get(ShopRules.room_of(s, data, _id), 0))}))
	elif ShopRules.staffed(s, _id):
		bits.append(tr("SHOP_STAFFED"))
	else:
		bits.append(tr("SHOP_UNSTAFFED"))
	var info := _label(_box, " · ".join(bits), UiTheme.MUTED_LABEL)
	if not ShopRules.has_charter(s, loc):
		info.add_theme_color_override("font_color", UiTheme.WARN)
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
	frame.title.text = tr("SHOP_TITLE_REGISTRY").format({"name": PropertyRules.npc_name(data, _id)})
	var sc: Dictionary = ShopRules.cfg(data)
	var held := ShopRules.has_charter(s, GameState.world().location_id(s.room_id))
	var ch := _row("CharterRow", tr("SHOP_CHARTER_HINT").format({"fee": Money.format(int(sc["charter"]["fee_cp"])), "tax": int(sc["charter"]["tax_pct"])})
		+ (" · " + tr("SHOP_HAS_CHARTER") if held else ""))
	_button(ch, "CharterBuy", tr("BTN_SHOP_CHARTER").format({"fee": Money.format(int(sc["charter"]["fee_cp"]))}), ShopRules.charter_why(s, data, _id), _act("charter", _id))
	_box.add_child(HSeparator.new())
	var room := ShopRules.market_room(data, GameState.world().location_id(s.room_id))
	if room.is_empty():
		_label(_box, tr("SHOP_NO_MARKET"), UiTheme.MUTED_LABEL)
		return
	var until := int(ShopRules.state(s.character)["stalls"].get(room, 0))
	_label(_box, tr("SHOP_STALL_HINT").format({"place": GameState.world().room_short(room), "rent": Money.format(int(sc["stall"]["rent_cp_day"]))})
		+ (" · " + tr("SHOP_STALL_UNTIL").format({"day": until}) if until >= s.day else ""))
	var stall := HBoxContainer.new()
	stall.name = "StallRow"
	stall.alignment = BoxContainer.ALIGNMENT_END
	stall.add_theme_constant_override("separation", 10)
	_box.add_child(stall)
	for d: Variant in sc["stall"]["days"]:
		_button(stall, "StallRent_%d" % int(d), tr("BTN_SHOP_RENT").format({"days": tr("BANK_DAYS").format({"n": int(d)}), "money": Money.format(int(d) * int(sc["stall"]["rent_cp_day"]))}),
			ShopRules.rent_why(s, data, _id, int(d)), _act("rent", _id, "", int(d)))


func _supplier(s: GameSession, data: Dictionary) -> void:
	frame.title.text = tr("SHOP_TITLE_SUPPLIER").format({"name": PropertyRules.npc_name(data, _id)})
	if not ShopRules.has_charter(s, GameState.world().location_id(s.room_id)):
		_label(_box, tr("SHOP_NEED_CHARTER")).add_theme_color_override("font_color", UiTheme.WARN)
	var lot := ShopRules.lot(data)
	for id: String in ShopRules.goods(s, data, _id):
		var p := ShopRules.wholesale_price(s, data, _id, id)
		var row := _row("Supply_" + id, tr("SHOP_SUPPLY_ROW").format({"item": _item(s, id), "price": Money.format(p), "value": Money.format(ShopRules.value(s, data, id))}))
		_button(row, "SupplyBuy_" + id, tr("BTN_SHOP_LOT").format({"n": lot, "money": Money.format(p * lot)}), ShopRules.wholesale_why(s, data, _id, id), _act("wholesale", _id, id))
