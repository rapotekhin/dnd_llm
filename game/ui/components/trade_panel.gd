class_name TradePanel
extends Control
## The trade screen (roadmap v0.5.3; a screen of its own since v0.7.22.10, the author: «как в BG3», the talk is not
## needed there): the trader's goods on the left, the hero's things on the right — two grids of icons (ItemGrid, v0.8.4.43.6)
## with the price in a thing's card at the cursor — and the deal in the middle as BG3's barter (v0.8.4.43.12): two columns
## of cells, what the hero takes beside the trader's goods and what it gives beside its own things, each with its sum,
## then the total, «Торговаться», «Заключить сделку» and the trader's services. A thing goes into the deal by a drag onto
## its column (or onto the other side's grid), out of it by a drag back; a stack asks how many by a slider
## (ItemGrid.with_qty). A click moves one (Shift ten, Ctrl all). The engine (TradeRules via GameState.deal / haggle)
## checks and makes each deal at once; the master tells the visit once, when the panel closes.

const SCENE := "res://ui/components/trade_panel.tscn"

## {"buy": {item_id: qty}, "sell": {item_id: qty}}
var cart := {"buy": {}, "sell": {}}
var _npc := ""
var _title: Label
var _partner: Label
var _purse: Label
var _coins: Label
var _haggle_state: Label
var _sums := {}  # side → its sum under the deal's column
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
var _offer := {}  # side → the grid of the deal's column
var _views := {"buy": {}, "sell": {}}  # each side's filter and sort while the screen lives
var _lines := {"buy": {}, "sell": {}}  # a thing's line of TradeRules.info shown now: its price, wanted
var _quotes := {"buy": {}, "sell": {}}  # a thing in the deal: {q, line_cp} for its cell
var _can_act := false


func required() -> Dictionary:
	return {
		"%Split": "HBoxContainer", "%TradeTitle": "Label", "%TradePartner": "Label", "%TradePurse": "Label",
		"%TradeCoins": "Label", "%DealState": "Label", "%TradeStock": "VBoxContainer", "%TradeYours": "VBoxContainer",
		"%TradeOfferBuy": "VBoxContainer", "%TradeOfferSell": "VBoxContainer", "%TradeBuySum": "Label",
		"%TradeSellSum": "Label", "%ServicesScroll": "ScrollContainer", "%TradeServices": "VBoxContainer",
		"%TradeTotal": "Label", "%TradeError": "Label", "%HaggleButton": "Button", "%ClearCartButton": "Button",
		"%DealButton": "Button", "%TradeToTalk": "Button", "%TradeLeave": "Button",
	}


func _ready() -> void:
	_title = UiScenes.need(self, "%TradeTitle")
	_partner = UiScenes.need(self, "%TradePartner")
	_purse = UiScenes.need(self, "%TradePurse")
	_coins = UiScenes.need(self, "%TradeCoins")
	_haggle_state = UiScenes.need(self, "%DealState")
	_sums = {"buy": UiScenes.need(self, "%TradeBuySum"), "sell": UiScenes.need(self, "%TradeSellSum")}
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

	_stock_grid = _trade_grid("Stock", "Buy_", UiScenes.need(self, "%TradeStock"), "buy", false)
	_yours_grid = _trade_grid("Yours", "Sell_", UiScenes.need(self, "%TradeYours"), "sell", false)
	_offer = {"buy": _trade_grid("OfferBuy", "Unbuy_", UiScenes.need(self, "%TradeOfferBuy"), "buy", true),
		"sell": _trade_grid("OfferSell", "Unsell_", UiScenes.need(self, "%TradeOfferSell"), "sell", true)}
	EventBus.state_changed.connect(_rebuild)
	EventBus.turn_started.connect(func(_id: String) -> void: _rebuild())
	EventBus.turn_finished.connect(func(_id: String, _ok: bool) -> void: _rebuild())
	EventBus.backend_state_changed.connect(func(_s: int, _d: String) -> void: _rebuild())
	visibility_changed.connect(_rebuild)
	_rebuild()


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
	var can_talk := Backend.is_ready() and not GameState.is_busy()
	var npc := GameState.world().npc(_npc)
	_title.text = str(npc.get("name", _npc))
	_partner.text = UiParts.partner_line(s, data, _npc)
	_to_talk.disabled = not can_talk
	_leave.disabled = not can_talk
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

	_can_act = not GameState.is_busy()  # the engine makes a deal, the master waits for the panel to close (v0.8.4.43.12)
	_fill(_stock_grid, info["stock"], "buy", "TRADE_SOLD_OUT")
	_fill(_yours_grid, info["buys"], "sell", "TRADE_NOTHING_TO_SELL")

	var empty := true
	for side: String in ["buy", "sell"]:
		_quotes[side] = {}
		var sum := 0
		var in_deal := {}
		for id: String in cart[side]:
			var qty := int(cart[side][id])
			if qty <= 0:
				continue
			empty = false
			in_deal[id] = qty
			var q := TradeRules.buy_quote(s, data, _npc, id) if side == "buy" else TradeRules.sell_quote(s, data, _npc, id)
			var line_cp := int(q["cp"]) * qty if side == "buy" else TradeRules.sell_total(s, data, _npc, id, qty)  # the deal's own sum (v0.8.4.29.3)
			_quotes[side][id] = {"q": q, "line_cp": line_cp}
			sum += line_cp
		(_offer[side] as ItemGrid).show_items(in_deal)
		(_sums[side] as Label).text = tr("TRADE_SIDE_SUM").format({"coins": Money.format(sum)}) if sum > 0 else tr("TRADE_DROP_HERE")

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
	deal_button.disabled = not _can_act or not cart_error.is_empty() or empty
	_clear.disabled = empty
	_clear_children(_services)
	var svs := ServiceRules.of(s, data, _npc)
	_services.get_parent().visible = not svs.is_empty()
	if not svs.is_empty():
		UiParts.label(_services, tr("TRADE_SERVICES"), UiTheme.CAPTION_LABEL)
	for sv: Dictionary in svs:
		var sid := str(sv["id"])
		var b := UiParts.act_button(_services, "Service_" + sid, tr("SERVICE_BUTTON").format({"name": sv["name"], "cost": Money.format(int(sv["cost_cp"]))}),
			str(sv["why"]), func() -> String: return GameState.service(_npc, sid))
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.size_flags_vertical = Control.SIZE_FILL
	var skill := TradeRules.best_skill(s, data)
	haggle_button.text = tr("BTN_HAGGLE").format({"skill": tr("SKILL_" + skill.to_upper())})
	var why := TradeRules.can_haggle(s, data, _npc)
	haggle_button.disabled = not _can_act or not why.is_empty()
	haggle_button.tooltip_text = tr(why) if not why.is_empty() else ""


## A grid of the screen: a side's things (`deal` false) or its column of the deal. A click moves one across, a thing
## dropped on it moves by `_drop` — how many of a stack the slider says.
func _trade_grid(tag: String, prefix: String, host: Control, side: String, deal: bool) -> ItemGrid:
	var g := ItemGrid.new(tag, prefix, 3 if deal else 5)
	g.bare = deal
	g.min_columns = 3 if deal else 4
	g.min_rows = 5 if deal else 6
	g.view = {} if deal else _views[side]
	g.where = {"kind": "trade", "side": side, "deal": deal}
	host.add_child(g)
	g.view_changed.connect(_rebuild)
	g.accepts = func(drag: Dictionary) -> bool: return _can_act and _drop(g.where, drag.get("from", {})) != 0
	g.dropped = func(drag: Dictionary) -> void:
		var from: Dictionary = drag["from"]
		var dir := _drop(g.where, from)
		var id := str(drag["item"])
		ItemGrid.with_qty(self, drag, func(n: int) -> void: _change(str(from["side"]), id, dir * mini(n, int(drag.get("qty", 1)))), true)
	g.setup = func(cell: ItemCell) -> void:
		var id := cell.item
		var left := cell.qty
		cell.disabled = not _can_act
		if deal:
			var dq: Dictionary = _quotes[side].get(id, {})
			cell.text = Money.format(int(dq.get("line_cp", 0)))
			cell.tooltip_text = "%s\n%s\n%s" % [cell.text, Price.text(dq["q"], int(dq["q"]["cp"])), tr("TRADE_QTY_TIP")] if not dq.is_empty() else cell.text
			cell.pressed.connect(func() -> void: _change(side, id, -mini(left, _step())))
			return
		var line: Dictionary = _lines[side].get(id, {})
		cell.text = Money.format(int(line.get("price_cp", 0)))
		if bool(line.get("wanted", false)):  # bought gladly (v0.7.17.1)
			cell.text += " · " + tr("TRADE_WANTED_TIP")
		cell.tooltip_text = "%s\n%s" % [cell.text, tr("TRADE_QTY_TIP")]
		cell.pressed.connect(func() -> void: _change(side, id, mini(left, _step())))
	return g


## What a drop of a thing from `from` onto the grid `onto` does to the deal of the thing's side: +1 — into it (onto its
## column, or across onto the other side's grid, as BG3's Trade), −1 — out of it (back onto its own side), 0 — nothing.
static func _drop(onto: Dictionary, from: Dictionary) -> int:
	if str(from.get("kind", "")) != "trade":
		return 0
	var same := str(onto["side"]) == str(from.get("side", ""))
	if bool(onto["deal"]):
		return 1 if same and not bool(from.get("deal", false)) else 0
	if bool(from.get("deal", false)):
		return -1 if same else 0
	return 0 if same else 1


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
		none = UiParts.label(grid.get_parent(), tr(empty_key), UiTheme.MUTED_LABEL)
		none.name = "TradeNone_" + side
		grid.get_parent().move_child(none, grid.get_index())
	elif not lines.is_empty() and none != null:
		none.queue_free()


## Shift — ten at once, Ctrl — all of them (v0.7.22.31, Т1).
static func _step() -> int:
	if Input.is_key_pressed(KEY_CTRL):
		return 1 << 20
	return 10 if Input.is_key_pressed(KEY_SHIFT) else 1


func _change(side: String, id: String, delta: int) -> void:
	var have := int(cart[side].get(id, 0))
	var most := int((_lines[side] as Dictionary).get(id, {}).get("qty", have))  # never more than the side has
	var qty := clampi(have + delta, 0, maxi(most, have))
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
