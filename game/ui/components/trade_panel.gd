class_name TradePanel
extends Control
## The trade screen (roadmap v0.5.3; a screen of its own since v0.7.22.10, the author: «как в BG3», the talk is not
## needed there): the trader's goods on the left, the hero's things on the right — two grids of icons (ItemGrid, v0.8.4.43.6)
## with the price in a thing's card at the cursor — the deal in the middle: what is bought and sold, the total,
## «Торговаться», «Заключить сделку», the trader's services. A click puts one into the deal (Shift ten, Ctrl all), a
## thing dragged onto the other side's grid too (Shift asks how many). The engine (TradeRules via GameState.deal /
## haggle) checks and makes the deal; the master narrates it in the chat behind.

const SCENE := "res://ui/components/trade_panel.tscn"

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
var _info: DetailsPanel  # the chat's column, its card at the cursor
var _stock_grid: ItemGrid
var _yours_grid: ItemGrid
var _views := {"buy": {}, "sell": {}}  # each side's filter and sort while the screen lives
var _lines := {"buy": {}, "sell": {}}  # a thing's line of TradeRules.info shown now: its price, wanted
var _can_act := false


func required() -> Dictionary:
	return {
		"%Split": "HBoxContainer", "%TradeTitle": "Label", "%TradePartner": "Label", "%TradePurse": "Label",
		"%TradeCoins": "Label", "%DealState": "Label", "%TradeStock": "VBoxContainer", "%TradeYours": "VBoxContainer",
		"%TradeBuyRows": "VBoxContainer", "%TradeSellRows": "VBoxContainer", "%TradeServices": "VBoxContainer",
		"%TradeTotal": "Label", "%TradeError": "Label", "%HaggleButton": "Button", "%ClearCartButton": "Button",
		"%DealButton": "Button", "%TradeToTalk": "Button", "%TradeLeave": "Button",
	}


func _ready() -> void:
	_title = UiScenes.need(self, "%TradeTitle")
	_partner = UiScenes.need(self, "%TradePartner")
	_purse = UiScenes.need(self, "%TradePurse")
	_coins = UiScenes.need(self, "%TradeCoins")
	_haggle_state = UiScenes.need(self, "%DealState")
	_stock = UiScenes.need(self, "%TradeStock")
	_yours = UiScenes.need(self, "%TradeYours")
	_buy_rows = UiScenes.need(self, "%TradeBuyRows")
	_sell_rows = UiScenes.need(self, "%TradeSellRows")
	_services = UiScenes.need(self, "%TradeServices")
	_total = UiScenes.need(self, "%TradeTotal")
	_error = UiScenes.need(self, "%TradeError")
	_error.text = ""
	_to_talk = UiScenes.need(self, "%TradeToTalk")
	_to_talk.pressed.connect(func() -> void: GameState.set_trade(false))
	_leave = UiScenes.need(self, "%TradeLeave")
	_leave.pressed.connect(GameState.leave_conversation)
	haggle_button = UiScenes.need(self, "%HaggleButton")
	haggle_button.pressed.connect(_on_haggle)
	_clear = UiScenes.need(self, "%ClearCartButton")
	_clear.pressed.connect(func() -> void:
		cart = {"buy": {}, "sell": {}}
		_error.text = ""
		_rebuild())
	deal_button = UiScenes.need(self, "%DealButton")
	deal_button.pressed.connect(_on_deal)

	_info = DetailsPanel.new(Vector2(0, 160), true)  # a card at the cursor (v0.8.4.43.3)
	_info.name = "TradeItemInfo"
	var chat := ChatView.new()  # the talk with the trader stays in view (the author)
	chat.name = "TradeChat"
	UiScenes.need(self, "%Split").add_child(_info.column(chat, 420))

	_stock_grid = _trade_grid("Stock", "Buy_", _stock, "buy")
	_yours_grid = _trade_grid("Yours", "Sell_", _yours, "sell")
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
	t.theme_type_variation = UiTheme.CAPTION_LABEL
	parent.add_child(t)


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
		_info.unpin()
		_info.show_text(tr("TRADE_INFO_HINT"), "")
	var data := Catalog.data
	var m := TradeRules.merchant(s, data, _npc)
	var info := TradeRules.info(s, data, _npc)
	var can_act := Backend.is_ready() and not GameState.is_busy()
	var npc := GameState.world().npc(_npc)
	_title.text = str(npc.get("name", _npc))
	_partner.text = UiParts.partner_line(s, data, _npc)
	_to_talk.disabled = not can_act
	_leave.disabled = not can_act
	_purse.text = tr("TRADE_PURSE").format({"coins": Money.format(Gear.coins(s, data, _npc))})
	_coins.text = tr("TRADE_COINS").format({"coins": Money.format(Ledger.balance(s))})
	var pct := int(m["haggle_pct"])
	var states: Array[String] = []
	if pct > 0:
		states.append(tr("TRADE_HAGGLE_ACTIVE").format({"pct": pct}))
	if int(info["discount_pct"]) > 0:  # a discount by words (v0.7.15.2)
		states.append(tr("TRADE_DISCOUNT").format({"pct": int(info["discount_pct"]), "day": int(Being.of(s, _npc)["discount"]["until_day"])}))
	if not str(info["wants"]).is_empty():  # v0.7.17.1: what the trader buys gladly
		states.append(tr("TRADE_WANTS").format({"tags": info["wants"]}))
	if not str(info["shuns"]).is_empty():
		states.append(tr("TRADE_SHUNS").format({"tags": info["shuns"]}))
	_haggle_state.text = " · ".join(states)

	_can_act = can_act
	_fill(_stock_grid, info["stock"], "buy", "TRADE_SOLD_OUT")
	_fill(_yours_grid, info["buys"], "sell", "TRADE_NOTHING_TO_SELL")

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
			var q := TradeRules.buy_quote(s, data, _npc, id) if side == "buy" else TradeRules.sell_quote(s, data, _npc, id)
			var price := int(q["cp"])
			var line_cp := price * qty if side == "buy" else TradeRules.sell_total(s, data, _npc, id, qty)  # the deal's own sum (v0.8.4.29.3)
			var row := HBoxContainer.new()
			rows.add_child(row)
			var l := _label(row, false)
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.text = "%s%s — %s" % [ItemRules.display_name(items, s.items, id), " ×%d" % qty if qty > 1 else "", Money.format(line_cp)]
			l.mouse_filter = Control.MOUSE_FILTER_STOP
			l.tooltip_text = Price.text(q, price)  # why the price is what it is (v0.7.60)
			var minus := Button.new()
			minus.name = ("Unbuy_" if side == "buy" else "Unsell_") + id
			minus.text = "−"
			minus.custom_minimum_size = Vector2(48, 40)
			minus.disabled = not can_act
			minus.tooltip_text = "TRADE_QTY_TIP"
			minus.pressed.connect(func() -> void: _change(side, id, -_step()))
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
	var svs := ServiceRules.of(s, data, _npc)
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
			var err := GameState.service(_npc, sid)
			if not err.is_empty():
				_error.text = tr(err))
		_services.add_child(b)
	var skill := TradeRules.best_skill(s, data)
	haggle_button.text = tr("BTN_HAGGLE").format({"skill": tr("SKILL_" + skill.to_upper())})
	var why := TradeRules.can_haggle(s, data, _npc)
	haggle_button.disabled = not can_act or not why.is_empty()
	haggle_button.tooltip_text = tr(why) if not why.is_empty() else ""


## A side's grid: a click puts one into the deal, a thing of the other side dropped on it too.
func _trade_grid(tag: String, prefix: String, host: Control, side: String) -> ItemGrid:
	var g := ItemGrid.new(tag, prefix, 5)
	g.min_rows = 6
	g.view = _views[side]
	g.where = {"kind": "trade", "side": side}
	host.add_child(g)
	g.view_changed.connect(_rebuild)
	g.accepts = func(drag: Dictionary) -> bool:
		var from: Dictionary = drag.get("from", {})
		return str(from.get("kind", "")) == "trade" and str(from.get("side", "")) != side and _can_act
	g.dropped = func(drag: Dictionary) -> void:
		var from := str((drag["from"] as Dictionary)["side"])
		ItemGrid.with_qty(self, drag, func(n: int) -> void: _change(from, str(drag["item"]), mini(n, int(drag.get("qty", 1)))))
	g.setup = func(cell: ItemCell) -> void:
		var line: Dictionary = _lines[side].get(cell.item, {})
		cell.text = Money.format(int(line.get("price_cp", 0)))
		if bool(line.get("wanted", false)):  # bought gladly (v0.7.17.1)
			cell.text += " · " + tr("TRADE_WANTED_TIP")
		cell.disabled = not _can_act
		var id := cell.item
		var left := cell.qty
		cell.pressed.connect(func() -> void: _change(side, id, mini(left, _step())))
	return g


## The things of a side not yet in the deal; «nothing» over an empty grid.
func _fill(grid: ItemGrid, lines: Array, side: String, empty_key: String) -> void:
	var inv := {}
	_lines[side] = {}
	for line: Dictionary in lines:
		var id := str(line["item_id"])
		var left := int(line["qty"]) - int(cart[side].get(id, 0))
		_lines[side][id] = line
		if left > 0:
			inv[id] = left
	grid.show_items(inv)
	var none := grid.get_parent().get_node_or_null("TradeNone_" + side)
	if lines.is_empty() and none == null:
		none = _label(grid.get_parent(), true)
		none.name = "TradeNone_" + side
		none.text = tr(empty_key)
		grid.get_parent().move_child(none, grid.get_index())
	elif not lines.is_empty() and none != null:
		none.queue_free()


## Shift — ten at once, Ctrl — all of them (v0.7.22.31, Т1).
static func _step() -> int:
	if Input.is_key_pressed(KEY_CTRL):
		return 1 << 20
	return 10 if Input.is_key_pressed(KEY_SHIFT) else 1


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
