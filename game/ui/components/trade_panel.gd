class_name TradePanel
extends PanelContainer
## The deal panel of trade mode (roadmap v0.5.3): the merchant's goods with prices and quantities, the player's
## things at the merchant's buying price, the cart with the total, «Торговаться» and «Заключить сделку».
## The engine (TradeRules via GameState.deal / haggle) checks and makes the deal; the master narrates it in the chat.

## {"buy": {item_id: qty}, "sell": {item_id: qty}}
var cart := {"buy": {}, "sell": {}}
var _npc := ""
var _purse: Label
var _coins: Label
var _haggle_state: Label
var _stock: VBoxContainer
var _yours: VBoxContainer
var _cart_rows: VBoxContainer
var _total: Label
var _error: Label
var haggle_button: Button
var deal_button: Button
var _clear: Button
var _info: InfoBox  # v0.7.7: what the item under the mouse is


func _ready() -> void:
	theme_type_variation = UiTheme.SIDE
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	add_child(col)
	var purses := HBoxContainer.new()
	purses.add_theme_constant_override("separation", 24)
	col.add_child(purses)
	_purse = _label(purses, true)
	_coins = _label(purses, false)
	_haggle_state = _label(col, false)
	_haggle_state.add_theme_color_override("font_color", UiTheme.ACCENT_BRIGHT)

	var lists := HBoxContainer.new()
	lists.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lists.add_theme_constant_override("separation", 16)
	col.add_child(lists)
	_stock = _list(lists, "TRADE_STOCK")
	_yours = _list(lists, "TRADE_YOURS")
	_info = InfoBox.new(120)
	_info.name = "TradeItemInfo"
	col.add_child(_info)

	var cart_title := Label.new()
	cart_title.text = "TRADE_CART"
	cart_title.theme_type_variation = UiTheme.MUTED_LABEL
	cart_title.add_theme_color_override("font_color", UiTheme.ACCENT)
	col.add_child(cart_title)
	var cart_scroll := ScrollContainer.new()
	cart_scroll.custom_minimum_size = Vector2(0, 96)
	cart_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(cart_scroll)
	_cart_rows = VBoxContainer.new()
	_cart_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cart_scroll.add_child(_cart_rows)
	_total = _label(col, false)
	_total.name = "TradeTotal"
	_error = _label(col, false)
	_error.name = "TradeError"
	_error.add_theme_color_override("font_color", UiTheme.WARN)
	_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	col.add_child(buttons)
	haggle_button = _action(buttons, "HaggleButton", _on_haggle)
	_clear = _action(buttons, "ClearCartButton", func() -> void:
		cart = {"buy": {}, "sell": {}}
		_error.text = ""
		_rebuild())
	_clear.text = "BTN_CLEAR_CART"
	deal_button = _action(buttons, "DealButton", _on_deal)
	deal_button.text = "BTN_DEAL"
	deal_button.theme_type_variation = UiTheme.ACCENT_BUTTON

	EventBus.state_changed.connect(_rebuild)
	EventBus.turn_started.connect(func(_id: String) -> void: _rebuild())
	EventBus.turn_finished.connect(func(_id: String, _ok: bool) -> void: _rebuild())
	EventBus.backend_state_changed.connect(func(_s: int, _d: String) -> void: _rebuild())
	visibility_changed.connect(_rebuild)
	_rebuild()


func _label(parent: Control, muted: bool) -> Label:
	var l := Label.new()
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	if muted:
		l.theme_type_variation = UiTheme.MUTED_LABEL
	parent.add_child(l)
	return l


func _list(parent: Control, title: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(box)
	var t := Label.new()
	t.text = title
	t.theme_type_variation = UiTheme.MUTED_LABEL
	t.add_theme_color_override("font_color", UiTheme.ACCENT)
	box.add_child(t)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 6)
	scroll.add_child(rows)
	return rows


func _action(parent: Control, node_name: String, action: Callable) -> Button:
	var b := Button.new()
	b.name = node_name
	b.custom_minimum_size = Vector2(0, 56)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(action)
	parent.add_child(b)
	return b


func _active() -> bool:
	return visible and GameState.has_session() and GameState.session.mode == GameSession.MODE_TRADE


func _rebuild() -> void:
	if not _active():
		return
	var s := GameState.session
	if s.npc_id != _npc:
		_npc = s.npc_id
		cart = {"buy": {}, "sell": {}}
		_error.text = ""
	var data := Catalog.data
	var m := TradeRules.merchant(s, data, _npc)
	var info := TradeRules.info(s, data, _npc)
	var can_act := Backend.is_ready() and not GameState.is_busy()
	_purse.text = tr("TRADE_PURSE").format({"coins": Money.format(int(m["purse_cp"]))})
	_coins.text = tr("TRADE_COINS").format({"coins": Money.format(int(s.character["gold_cp"]))})
	var pct := int(m["haggle_pct"])
	_haggle_state.text = tr("TRADE_HAGGLE_ACTIVE").format({"pct": pct}) if pct > 0 else ""
	_haggle_state.visible = pct > 0

	_fill(_stock, info["stock"], "buy", "Buy_", "TRADE_SOLD_OUT", can_act)
	_fill(_yours, info["buys"], "sell", "Sell_", "TRADE_NOTHING_TO_SELL", can_act)

	_clear_children(_cart_rows)
	var items: Dictionary = data["items"]
	var empty := true
	for side: String in ["buy", "sell"]:
		for id: String in cart[side]:
			var qty := int(cart[side][id])
			if qty <= 0:
				continue
			empty = false
			var price := TradeRules.buy_price(s, data, _npc, id) if side == "buy" else TradeRules.sell_price(s, data, _npc, id)
			var item_name := ItemRules.display_name(items, s.items, id) + (" ×%d" % qty if qty > 1 else "")
			var row := HBoxContainer.new()
			_cart_rows.add_child(row)
			var l := _label(row, false)
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			l.text = tr("TRADE_CART_BUY" if side == "buy" else "TRADE_CART_SELL").format({"item": item_name, "coins": Money.format(price * qty)})
			var minus := Button.new()
			minus.name = ("Unbuy_" if side == "buy" else "Unsell_") + id
			minus.text = "−"
			minus.custom_minimum_size = Vector2(52, 44)
			minus.disabled = not can_act
			minus.pressed.connect(_change.bind(side, id, -1))
			row.add_child(minus)
	if empty:
		var hint := _label(_cart_rows, true)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.text = tr("TRADE_CART_EMPTY")

	var q := TradeRules.quote(s, data, _npc, cart)
	var net := int(q["net_cp"])
	if empty:
		_total.text = ""
	elif net > 0:
		_total.text = tr("TRADE_PAY").format({"coins": Money.format(net)})
	elif net < 0:
		_total.text = tr("TRADE_GET").format({"coins": Money.format(-net)})
	else:
		_total.text = tr("TRADE_EVEN")
	var cart_error := str(q["error"]) if not empty else ""
	if not cart_error.is_empty():
		_error.text = tr(cart_error).format(q["args"])
	deal_button.disabled = not can_act or not cart_error.is_empty() or empty
	_clear.disabled = empty
	var skill := TradeRules.best_skill(s, data)
	haggle_button.text = tr("BTN_HAGGLE").format({"skill": tr("SKILL_" + skill.to_upper())})
	var why := TradeRules.can_haggle(s, data, _npc)
	haggle_button.disabled = not can_act or not why.is_empty()
	haggle_button.tooltip_text = tr(why) if not why.is_empty() else ""


func _fill(box: VBoxContainer, lines: Array, side: String, prefix: String, empty_key: String, can_act: bool) -> void:
	_clear_children(box)
	if lines.is_empty():
		_label(box, true).text = tr(empty_key)
		return
	for line: Dictionary in lines:
		var id := str(line["item_id"])
		var left := int(line["qty"]) - int(cart[side].get(id, 0))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		box.add_child(row)
		var names := VBoxContainer.new()
		names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		names.add_theme_constant_override("separation", 0)
		names.mouse_filter = Control.MOUSE_FILTER_STOP
		row.add_child(names)
		var title := _label(names, false)
		title.text = "%s ×%d" % [line["name"], left]
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var s := GameState.session
		var short: Array[String] = []
		var data: Dictionary = Catalog.data
		var def := ItemRules.def_of(data["items"], s.items, id)
		for part: String in [ItemInfo.kind_line(data, def), ItemInfo.proficiency_line(s.character, def, id), ItemInfo.compare(s.character, data, s.items, id)]:
			if not part.is_empty():
				short.append(part)
		if not short.is_empty():
			var sub := _label(names, true)
			sub.name = "TradeItemStats_" + id
			sub.text = "\n".join(short)
			sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var full := ItemInfo.lines(s.character, data, s.items, id)
		var cmp := ItemInfo.compare(s.character, data, s.items, id)
		if not cmp.is_empty():
			full.append(cmp)
		InfoBox.hook(names, _info, str(line["name"]), "\n".join(full))
		var price := _label(row, true)
		price.text = Money.format(int(line["price_cp"]))
		var plus := Button.new()
		plus.name = prefix + id
		plus.text = "+"
		plus.custom_minimum_size = Vector2(52, 44)
		plus.disabled = not can_act or left <= 0
		plus.pressed.connect(_change.bind(side, id, 1))
		row.add_child(plus)


func _change(side: String, id: String, delta: int) -> void:
	var qty := maxi(0, int(cart[side].get(id, 0)) + delta)
	if qty == 0:
		cart[side].erase(id)
	else:
		cart[side][id] = qty
	_error.text = ""
	_rebuild()


func _on_deal() -> void:
	var res := GameState.deal(cart)
	if str(res["error"]).is_empty():
		cart = {"buy": {}, "sell": {}}
		_error.text = ""
	else:
		_error.text = tr(str(res["error"])).format(res["args"])
	_rebuild()


func _on_haggle() -> void:
	var err := GameState.haggle()
	if not err.is_empty():
		_error.text = tr(err)


static func _clear_children(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()
