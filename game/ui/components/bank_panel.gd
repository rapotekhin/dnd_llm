class_name BankPanel
extends ModalFrame
## The bank window (roadmap v0.7.28), opened by «Банк» among a bank NPC's acts: deposits (a sum and a term), loans
## against a collateral (a place with a deed or a thing in pawn) and the vault (coins and things). Every act is
## GameState.bank_act: the engine decides.

const SCENE := "res://ui/components/bank_panel.tscn"

var _box: VBoxContainer
var _npc := ""
var _deposit_gp := 5
var _days := 28
var _coins_gp := 1


func _ready() -> void:
	super()
	close_requested.connect(func() -> void: visible = false)
	close_x.name = "CloseBankButton"
	_box = body
	EventBus.state_changed.connect(_rebuild)
	visibility_changed.connect(_rebuild)


func open(npc_id: String) -> void:
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


func _heading(text: String) -> void:
	_label(_box, text).theme_type_variation = UiTheme.ACCENT_LABEL


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


func _row(node_name: String, text: String, variation: String = "") -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = node_name
	row.add_theme_constant_override("separation", 10)
	_box.add_child(row)
	_label(row, text, variation)
	return row


func _spin(parent: Control, node_name: String, value: int, max_value: int, changed: Callable) -> SpinBox:
	var spin := SpinBox.new()
	spin.name = node_name
	spin.min_value = 1
	spin.max_value = maxi(1, max_value)
	spin.value = clampi(value, 1, maxi(1, max_value))
	spin.suffix = tr("BANK_GP")
	spin.value_changed.connect(func(v: float) -> void:
		changed.call(int(v))
		_rebuild.call_deferred())
	parent.add_child(spin)
	return spin


func _act(what: String, arg: String = "", amount: int = 0, days: int = 0) -> Callable:
	return func() -> String: return GameState.bank_act(what, _npc, arg, amount, days)


func _rebuild() -> void:
	if not visible or not GameState.has_session():
		return
	clear_body()
	var s := GameState.session
	var data := Catalog.data
	title.text = tr("BANK_TITLE_AT").format({"name": BankRules.npc_name(data, _npc)})
	var gold := int(s.character.get("gold_cp", 0))
	_label(_box, tr("BANK_PURSE").format({"money": Money.format(gold)}), UiTheme.MUTED_LABEL)
	var mine := BankRules.open_of(s.character, _npc)
	if BankRules.offers(s, data, _npc, BankRules.DEPOSIT):
		_deposits(s, data, mine, gold)
	if BankRules.offers(s, data, _npc, BankRules.LOAN):
		_box.add_child(HSeparator.new())
		_loans(s, data, mine)
	if BankRules.offers(s, data, _npc, "vault"):
		_box.add_child(HSeparator.new())
		_vault(s, data, gold)


func _deposits(s: GameSession, data: Dictionary, mine: Array[Dictionary], gold: int) -> void:
	_heading(tr("BANK_DEPOSITS"))
	for k: Dictionary in mine:
		if str(k["kind"]) != BankRules.DEPOSIT:
			continue
		var t: Dictionary = BankRules.cfg(data)["deposit"]["terms"].get(str(k.get("term", "")), {})
		var text := tr("BANK_DEPOSIT_ROW").format({"money": Money.format(int(k["balance"])), "term": t.get("name", ""), "rate": BankRules.rate_text(float(k["rate"]))})
		if int(k["due"]) > 0:
			text += " · " + tr("BANK_UNTIL").format({"day": int(k["due"])})
		var row := _row("Deposit_" + str(k["id"]), text)
		var early := BankRules.early(s, k)
		_button(row, "Withdraw_" + str(k["id"]), tr("BTN_BANK_WITHDRAW_EARLY" if early else "BTN_BANK_WITHDRAW").format({"money": Money.format(BankRules.payout(s, k))}),
			BankRules.withdraw_why(s, data, str(k["id"])), _act("withdraw", str(k["id"])))
	_label(_box, tr("BANK_DEPOSIT_NEW").format({"min": Money.format(int(BankRules.cfg(data)["deposit"]["min_cp"]))}), UiTheme.MUTED_LABEL)
	var row := HBoxContainer.new()
	row.name = "DepositNew"
	row.add_theme_constant_override("separation", 10)
	_box.add_child(row)
	_spin(row, "DepositAmount", _deposit_gp, gold / 100, func(v: int) -> void: _deposit_gp = v)
	var rates: Dictionary = BankRules.terms(s, data, _npc)["deposit_rates"]
	for term: String in rates:
		var t: Dictionary = BankRules.cfg(data)["deposit"]["terms"][term]
		_button(row, "DepositPut_" + term, tr("BTN_BANK_DEPOSIT").format({"term": t["name"], "rate": BankRules.rate_text(float(rates[term]))}),
			BankRules.deposit_why(s, data, _npc, term, _deposit_gp * 100), _act("deposit", term, _deposit_gp * 100))


func _loans(s: GameSession, data: Dictionary, mine: Array[Dictionary]) -> void:
	_heading(tr("BANK_LOANS").format({"rate": BankRules.rate_text(float(BankRules.terms(s, data, _npc)["loan_rate"]))}))
	for k: Dictionary in mine:
		if str(k["kind"]) != BankRules.LOAN:
			continue
		var late := s.day > int(k["due"])
		var row := _row("Loan_" + str(k["id"]), tr("BANK_LOAN_ROW").format({"money": Money.format(int(k["balance"])), "day": int(k["due"]),
			"what": k.get("collateral", {}).get("name", "")}) + (" · " + tr("BANK_OVERDUE_MARK") if late else ""))
		if late:
			(row.get_child(0) as Label).add_theme_color_override("font_color", UiTheme.WARN)
		_button(row, "Repay_" + str(k["id"]), tr("BTN_BANK_REPAY").format({"money": Money.format(int(k["balance"]))}),
			BankRules.repay_why(s, data, str(k["id"])), _act("repay", str(k["id"])))
	var term_row := _row("LoanTerm", tr("BANK_LOAN_TERM"), UiTheme.MUTED_LABEL)
	var pick := OptionButton.new()
	pick.name = "LoanDays"
	var list: Array = BankRules.cfg(data)["loan"]["terms_days"]
	for i in list.size():
		pick.add_item(tr("BANK_DAYS").format({"n": int(list[i])}), int(list[i]))
		if int(list[i]) == _days:
			pick.select(i)
	pick.item_selected.connect(func(i: int) -> void:
		_days = pick.get_item_id(i)
		_rebuild.call_deferred())
	term_row.add_child(pick)
	var options := BankRules.collaterals(s, data, _npc)
	if options.is_empty():
		_label(_box, tr("BANK_NO_COLLATERAL_HINT").format({"min": Money.format(int(BankRules.cfg(data)["loan"]["item_min_cp"]))}), UiTheme.MUTED_LABEL)
	for o: Dictionary in options:
		var key := "%s:%s" % [o["kind"], o["id"]]
		var row := _row("Pledge_" + str(o["id"]), tr("BANK_PLEDGE_ROW").format({"what": o["name"], "value": Money.format(int(o["value"])), "max": Money.format(int(o["max"]))}))
		_button(row, "PledgeBtn_" + str(o["id"]), tr("BTN_BANK_LOAN").format({"money": Money.format(int(o["max"]))}),
			BankRules.loan_why(s, data, _npc, str(o["kind"]), str(o["id"]), _days), _act("loan", key, 0, _days))


func _vault(s: GameSession, data: Dictionary, gold: int) -> void:
	_heading(tr("BANK_VAULT").format({"fee": Money.format(int(BankRules.cfg(data)["vault"]["fee_cp_week"]))}))
	var v: Dictionary = BankRules.state(s.character)["vaults"].get(_npc, {"coins": 0, "contents": {}})
	if Ledger.owed(s, "vault:" + _npc) > 0:
		_label(_box, tr("BANK_VAULT_OWED").format({"money": Money.format(Ledger.owed(s, "vault:" + _npc))})).theme_type_variation = UiTheme.WARN_LABEL
	var coins := _row("VaultCoins", tr("BANK_VAULT_COINS").format({"money": Money.format(int(v.get("coins", 0)))}))
	_spin(coins, "VaultAmount", _coins_gp, maxi(gold, int(v.get("coins", 0))) / 100, func(n: int) -> void: _coins_gp = n)
	_button(coins, "VaultCoinsIn", tr("BTN_BANK_PUT"), BankRules.vault_why(s, data, _npc, "in", "", _coins_gp * 100), _act("put", "", _coins_gp * 100))
	_button(coins, "VaultCoinsOut", tr("BTN_BANK_TAKE"), BankRules.vault_why(s, data, _npc, "out", "", _coins_gp * 100), _act("take", "", _coins_gp * 100))
	var contents: Dictionary = v.get("contents", {})
	for id: String in contents:
		var row := _row("VaultItem_" + id, "%s%s" % [ItemRules.display_name(data["items"], s.items, id), " ×%d" % int(contents[id]) if int(contents[id]) > 1 else ""])
		_button(row, "VaultTake_" + id, tr("BTN_BANK_TAKE"), BankRules.vault_why(s, data, _npc, "out", id, 0), _act("take", id))
	_label(_box, tr("BANK_VAULT_YOURS"), UiTheme.MUTED_LABEL)
	var any := false
	for id: String in (s.character.get("inventory", {}) as Dictionary).keys():
		if TradeRules.sellable(s, str(id), data) <= 0:
			continue
		any = true
		var row := _row("HeroItem_" + str(id), "%s ×%d" % [ItemRules.display_name(data["items"], s.items, str(id)), TradeRules.sellable(s, str(id), data)])
		_button(row, "VaultPut_" + str(id), tr("BTN_BANK_PUT"), BankRules.vault_why(s, data, _npc, "in", str(id), 0), _act("put", str(id)))
	if not any:
		_label(_box, tr("BANK_VAULT_NOTHING"), UiTheme.MUTED_LABEL)
