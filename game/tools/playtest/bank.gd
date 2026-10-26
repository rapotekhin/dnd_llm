extends "res://tools/playtest/playtest_base.gd"
## The bank (python tools/godot_playtest.py --scenario bank), v0.7.28: the moneychanger in his room of the town hall,
## a deposit, a silver ring pawned for a loan, the other ring in the vault; a month later the deposit has grown and the
## unpaid pawn stays with the bank.


func run() -> void:
	var gs := node("GameState")
	if not step("master connected", await wait_until(func() -> bool: return node("Backend").is_ready(), 30.0)):
		return
	await tap("NewGameButton")
	await tap("NextButton")
	await tap("Preset_fighter_aira")
	await press(find(screen(), "StartButton"))
	if not step("game started", await wait_until(func() -> bool: return screen_is("GameScreen") and not gs.is_busy(), 60.0)):
		return
	var s: GameSession = gs.session
	var c := s.character
	c["gold_cp"] = 20000
	c["inventory"]["silver_ring"] = 2
	s.settings["needs"] = false
	s.room_id = "brod-exchange"
	s.minute = 12 * 60
	node("EventBus").state_changed.emit()
	await frames(3)

	await open_row("More_npc_changer")
	var bank: Button = find(screen(), "Bank_npc_changer")
	if not step("«Банк» among the moneychanger's acts", bank != null and not bank.disabled):
		await shot("no_bank")
		return
	await press(bank)
	await frames(4)
	var win: Control = find(screen(), "BankView")
	step("the bank window", win != null and win.visible)
	await shot("bank_open")

	await press(find(win, "DepositPut_demand"))
	await frames(4)
	step("a deposit of 5 gp", BankRules.open_of(c).any(func(k: Dictionary) -> bool: return str(k["kind"]) == BankRules.DEPOSIT and int(k["principal"]) == 500), _last_effects(s))
	await press(find(win, "PledgeBtn_silver_ring"))
	await frames(4)
	step("a loan against a ring", BankRules.open_of(c).any(func(k: Dictionary) -> bool: return str(k["kind"]) == BankRules.LOAN), _last_effects(s))
	await press(find(win, "VaultPut_silver_ring"))
	await frames(4)
	step("the other ring in the vault", int(BankRules.vault(c, "npc_changer")["contents"].get("silver_ring", 0)) == 1, _last_effects(s))
	await shot("bank_deals")
	win.visible = false

	s.rested_at = TimeRules.abs_minute(s) + 45 * 1440  # the skip is not days without sleep
	s.chat.append(GameSession.effect_entry(TimeRules.advance(s, node("Catalog").data, 45 * 1440)))
	node("EventBus").state_changed.emit()
	await frames(3)
	var dep: Array = BankRules.open_of(c).filter(func(k: Dictionary) -> bool: return str(k["kind"]) == BankRules.DEPOSIT)
	step("the deposit grew", not dep.is_empty() and int(dep[0]["balance"]) > 500)
	step("the overdue pawn stays with the bank", not BankRules.open_of(c).any(func(k: Dictionary) -> bool: return str(k["kind"]) == BankRules.LOAN), _last_effects(s))
	await shot("month_later")
	await open_row("More_npc_changer")
	await press(find(screen(), "Bank_npc_changer"))
	await frames(4)
	await shot("bank_after")


func _last_effects(s: GameSession) -> String:
	for i in range(s.chat.size() - 1, -1, -1):
		if str(s.chat[i].get("kind", "")) == GameSession.KIND_EFFECT:
			return " · ".join(s.chat[i]["lines"])
	return ""
