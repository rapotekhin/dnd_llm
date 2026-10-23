class_name TradePanel
extends Control
## The trade screen (roadmap v0.5.3; a screen of its own since v0.7.22.10, the author: «как в BG3», the talk is not
## needed there): the trader's goods on the left, the hero's things on the right, the deal in the middle — what is
## bought and sold, the total, «Торговаться», «Заключить сделку», the trader's services; what the picked thing is —
## a thin strip at the bottom. The engine (TradeRules via GameState.deal / haggle) checks and makes the deal; the
## master narrates it in the chat behind.

## {"buy": {item_id: qty}, "sell": {item_id: qty}}
var cart := {"buy": {}, "sell": {}}
var _npc := ""
var _title: Label
var _partner: Label
var _purse: Label
var _coins: Label
var _haggle_state: Label
var _stock: VBoxContainer
var _yours: VBoxContainer
var _buy_rows: VBoxContainer
var _sell_rows: VBoxContainer
var _total: Label
var _error: Label
var haggle_button: Button
var _services: VBoxContainer
var deal_button: Button
var _clear: Button
var _to_talk: Button
var _leave: Button
var _info: DetailsPanel  # what the picked item is (a click on its name), a thin strip at the bottom


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = UiTheme.BG
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	margin.add_child(col)

	# The head: the trader, the purses, the deal's state, back to the talk or away.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	col.add_child(head)
	var who := VBoxContainer.new()
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(who)
	_title = _label(who, false)
	_title.theme_type_variation = UiTheme.HEADING
	_partner = _label(who, true)
	_to_talk = Button.new()
	_to_talk.name = "TradeToTalk"
	_to_talk.text = "BTN_TO_TALK"
	_to_talk.custom_minimum_size = Vector2(0, 52)
	_to_talk.pressed.connect(func() -> void: GameState.set_trade(false))
	head.add_child(_to_talk)
	_leave = Button.new()
	_leave.name = "TradeLeave"
	_leave.text = "BTN_LEAVE_CONVERSATION"
	_leave.custom_minimum_size = Vector2(0, 52)
	_leave.pressed.connect(GameState.leave_conversation)
	head.add_child(_leave)
	var purses := HBoxContainer.new()
	purses.add_theme_constant_override("separation", 24)
	col.add_child(purses)
	_purse = _label(purses, true)
	_coins = _label(purses, false)
	_haggle_state = _label(purses, false)
	_haggle_state.name = "DealState"
	_haggle_state.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_haggle_state.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_haggle_state.add_theme_color_override("font_color", UiTheme.ACCENT_BRIGHT)

	# The three columns: the goods, the deal, the hero's things.
	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 16)
	col.add_child(cols)
	_stock = _list(cols, "TRADE_STOCK", 1.0)
	var deal := PanelContainer.new()
	deal.theme_type_variation = UiTheme.SIDE
	deal.custom_minimum_size = Vector2(400, 0)
	cols.add_child(deal)
	var dcol := VBoxContainer.new()
	dcol.add_theme_constant_override("separation", 8)
	deal.add_child(dcol)
	var dscroll := ScrollContainer.new()
	dscroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	dcol.add_child(dscroll)
	var dbox := VBoxContainer.new()
	dbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dbox.add_theme_constant_override("separation", 6)
	dscroll.add_child(dbox)
	_heading(dbox, "TRADE_YOU_BUY")
	_buy_rows = VBoxContainer.new()
	dbox.add_child(_buy_rows)
	_heading(dbox, "TRADE_YOU_SELL")
	_sell_rows = VBoxContainer.new()
	dbox.add_child(_sell_rows)
	_services = VBoxContainer.new()  # v0.7.12: identify, remove a curse, silver a weapon
	_services.name = "TradeServices"
	_services.add_theme_constant_override("separation", 6)
	dbox.add_child(_services)
	_total = _label(dcol, false)
	_total.name = "TradeTotal"
	_total.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error = _label(dcol, false)
	_error.name = "TradeError"
	_error.add_theme_color_override("font_color", UiTheme.WARN)
	_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	haggle_button = _action(dcol, "HaggleButton", _on_haggle)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	dcol.add_child(row)
	_clear = _action(row, "ClearCartButton", func() -> void:
		cart = {"buy": {}, "sell": {}}
		_error.text = ""
		_rebuild())
	_clear.text = "BTN_CLEAR_CART"
	deal_button = _action(row, "DealButton", _on_deal)
	deal_button.text = "BTN_DEAL"
	deal_button.theme_type_variation = UiTheme.ACCENT_BUTTON
	_yours = _list(cols, "TRADE_YOURS", 1.0)

	_info = DetailsPanel.new(Vector2(0, 96))  # a thin strip, not half the window (the author)
	_info.name = "TradeItemInfo"
	_info.custom_minimum_size = Vector2(0, 96)
	_info.size_flags_vertical = Control.SIZE_SHRINK_END
	col.add_child(_info)

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


func _heading(parent: Control, key: String) -> void:
	var t := Label.new()
	t.text = key
	t.theme_type_variation = UiTheme.MUTED_LABEL
	t.add_theme_color_override("font_color", UiTheme.ACCENT)
	parent.add_child(t)


func _list(parent: Control, title: String, ratio: float) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = UiTheme.SIDE
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = ratio
	parent.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	_heading(box, title)
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
		_info.show_text(tr("TRADE_INFO_HINT"), "")
	var data := Catalog.data
	var m := TradeRules.merchant(s, data, _npc)
	var info := TradeRules.info(s, data, _npc)
	var can_act := Backend.is_ready() and not GameState.is_busy()
	var npc := GameState.world().npc(_npc)
	var bounds := GameSession.attitude_bounds(data)
	var att := clampi(s.attitude(_npc), bounds.x, bounds.y)
	_title.text = str(npc.get("name", _npc))
	_partner.text = tr("PARTNER_LINE").format({"role": npc.get("role", ""), "race": npc.get("race", ""), "body": BodyRules.npc_text(data, _npc, npc),
		"attitude": tr("ATTITUDE_" + ("M%d" % -att if att < 0 else "P%d" % att if att > 0 else "0"))})
	_to_talk.disabled = not can_act
	_leave.disabled = not can_act
	_purse.text = tr("TRADE_PURSE").format({"coins": Money.format(int(m["purse_cp"]))})
	_coins.text = tr("TRADE_COINS").format({"coins": Money.format(int(s.character["gold_cp"]))})
	var pct := int(m["haggle_pct"])
	var states: Array[String] = []
	if pct > 0:
		states.append(tr("TRADE_HAGGLE_ACTIVE").format({"pct": pct}))
	if int(info["discount_pct"]) > 0:  # a discount by words (v0.7.15.2)
		states.append(tr("TRADE_DISCOUNT").format({"pct": int(info["discount_pct"]), "day": int(s.discounts[_npc]["until_day"])}))
	if not str(info["wants"]).is_empty():  # v0.7.17.1: what the trader buys gladly
		states.append(tr("TRADE_WANTS").format({"tags": info["wants"]}))
	if not str(info["shuns"]).is_empty():
		states.append(tr("TRADE_SHUNS").format({"tags": info["shuns"]}))
	_haggle_state.text = " · ".join(states)

	_fill(_stock, info["stock"], "buy", "Buy_", "TRADE_SOLD_OUT", can_act)
	_fill(_yours, info["buys"], "sell", "Sell_", "TRADE_NOTHING_TO_SELL", can_act)

	var items: Dictionary = data["items"]
	var empty := true
	for side: String in ["buy", "sell"]:
		var rows := _buy_rows if side == "buy" else _sell_rows
		_clear_children(rows)
		var any := false
		for id: String in cart[side]:
			var qty := int(cart[side][id])
			if qty <= 0:
				continue
			empty = false
			any = true
			var price := TradeRules.buy_price(s, data, _npc, id) if side == "buy" else TradeRules.sell_price(s, data, _npc, id)
			var row := HBoxContainer.new()
			rows.add_child(row)
			var l := _label(row, false)
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.text = "%s%s — %s" % [ItemRules.display_name(items, s.items, id), " ×%d" % qty if qty > 1 else "", Money.format(price * qty)]
			var minus := Button.new()
			minus.name = ("Unbuy_" if side == "buy" else "Unsell_") + id
			minus.text = "−"
			minus.custom_minimum_size = Vector2(48, 40)
			minus.disabled = not can_act
			minus.pressed.connect(_change.bind(side, id, -1))
			row.add_child(minus)
		if not any:
			_label(rows, true).text = tr("TRADE_NOTHING_YET")

	var q := TradeRules.quote(s, data, _npc, cart)
	var net := int(q["net_cp"])
	_total.theme_type_variation = UiTheme.MUTED_LABEL if empty else UiTheme.HEADING
	if empty:
		_total.text = tr("TRADE_CART_EMPTY_SHORT")
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
	_clear_children(_services)
	var svs := TradeRules.services(s, data, _npc)
	if not svs.is_empty():
		_heading(_services, "TRADE_SERVICES")
	for sv: Dictionary in svs:
		var sid := str(sv["id"])
		var b := Button.new()
		b.name = "Service_" + sid
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		b.text = tr("SERVICE_BUTTON").format({"name": sv["name"], "cost": Money.format(int(sv["cost_cp"]))})
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.disabled = not can_act or not str(sv["why"]).is_empty()
		b.tooltip_text = tr(str(sv["why"])) if not str(sv["why"]).is_empty() else ""
		b.pressed.connect(func() -> void:
			var err := GameState.buy_service(sid)
			if not err.is_empty():
				_error.text = tr(err))
		_services.add_child(b)
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
		var title := Button.new()
		title.name = "TradeItem_" + id
		title.text = "%s ×%d" % [line["name"], left]
		title.flat = true
		title.alignment = HORIZONTAL_ALIGNMENT_LEFT
		title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var item_name := str(line["name"])
		var show := func() -> void:
			var s := GameState.session
			_info.show_text(item_name, DetailsPanel.item_text(s.character, Catalog.data, s.items, id))
		title.pressed.connect(show)
		title.mouse_entered.connect(show)
		row.add_child(title)
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
