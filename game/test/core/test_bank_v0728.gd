extends GdUnitTestSuite
## The bank (v0.7.28): the moneychanger's deposits with interest by days, early withdrawal without it, loans against
## a thing or a place with a deed, overdue — the penalty and the collateral to the bank, a lost place — the debt as a
## crime, the vault safe from captivity, the master's lender.

var data: Dictionary


func before_test() -> void:
	data = TestUtils.data()


func _at_bank() -> GameSession:
	var s := TestUtils.new_session()
	s.settings["needs"] = false
	s.room_id = "brod-exchange"
	s.minute = 12 * 60
	s.character["gold_cp"] = 100000
	return s


func _days(s: GameSession, n: int) -> Array[String]:
	return TimeRules.advance(s, data, n * 1440)


func _first(s: GameSession) -> Dictionary:
	return BankRules.open_of(s.character)[0]


func test_the_moneychanger_is_a_bank_in_its_room() -> void:
	var s := _at_bank()
	assert_bool(BankRules.is_bank(s, data, "npc_changer")).is_true()
	assert_bool(BankRules.is_bank(s, data, "npc_clerk")).is_false()
	assert_str(BankRules.deposit_why(s, data, "npc_changer", "demand", 1000)).is_empty()
	s.room_id = "brod-townhall"
	assert_str(BankRules.deposit_why(s, data, "npc_changer", "demand", 1000)).is_equal("BANK_NOT_HERE")


func test_a_demand_deposit_grows_by_days() -> void:
	var s := _at_bank()
	BankRules.deposit(s, data, "npc_changer", "demand", 10000)
	assert_int(int(s.character["gold_cp"])).is_equal(90000)
	_days(s, 28)
	var k := _first(s)
	assert_int(int(k["balance"])).is_greater(10000)
	assert_int(int(k["balance"])).is_less(10200)
	BankRules.withdraw(s, data, str(k["id"]))
	assert_int(int(s.character["gold_cp"])).is_equal(90000 + int(k["balance"]))
	assert_array(BankRules.open_of(s.character)).is_empty()


func test_a_term_deposit_taken_early_loses_the_interest() -> void:
	var s := _at_bank()
	BankRules.deposit(s, data, "npc_changer", "month", 10000)
	_days(s, 14)
	var k := _first(s)
	assert_bool(BankRules.early(s, k)).is_true()
	assert_int(BankRules.payout(s, k)).is_equal(10000)
	_days(s, 14)
	assert_bool(BankRules.early(s, k)).is_false()
	assert_int(BankRules.payout(s, k)).is_greater_equal(10400)


func test_a_loan_against_a_thing_in_pawn() -> void:
	var s := _at_bank()
	s.character["inventory"]["silver_ring"] = 1
	var opts := BankRules.collaterals(s, data, "npc_changer")
	assert_bool(opts.any(func(o: Dictionary) -> bool: return str(o["id"]) == "silver_ring" and int(o["max"]) == 1250)).is_true()
	assert_str(BankRules.loan_why(s, data, "npc_changer", "item", "silver_ring", 28)).is_empty()
	BankRules.loan(s, data, "npc_changer", "item", "silver_ring", 28)
	assert_bool(s.character["inventory"].has("silver_ring")).is_false()
	assert_int(int(s.character["gold_cp"])).is_equal(101250)
	_days(s, 7)
	var k := _first(s)
	assert_int(int(k["balance"])).is_greater(1250)
	BankRules.repay(s, data, str(k["id"]))
	assert_int(int(s.character["inventory"].get("silver_ring", 0))).is_equal(1)


func test_overdue_the_pawn_stays_with_the_bank() -> void:
	var s := _at_bank()
	s.character["inventory"]["silver_ring"] = 1
	BankRules.loan(s, data, "npc_changer", "item", "silver_ring", 14)
	var lines := _days(s, 15)
	assert_str(" ".join(lines)).contains("долг просрочен")
	_days(s, 14)
	assert_array(BankRules.open_of(s.character)).is_empty()
	assert_str(BankRules.loan_why(s, data, "npc_changer", "item", "silver_ring", 14)).is_equal("BANK_REFUSED")


func test_a_place_with_a_deed_is_pledged_and_taken_overdue() -> void:
	var s := _at_bank()
	s.room_id = "brod-townhall"
	PropertyRules.buy(s, data, "river_house")
	assert_bool(BankRules.collaterals(s, data, "npc_changer").any(func(o: Dictionary) -> bool: return str(o["id"]) == "river_house")).is_false()
	PropertyRules.deed(s, data, "river_house")
	s.room_id = "brod-exchange"
	assert_str(BankRules.loan_why(s, data, "npc_changer", "property", "river_house", 14)).is_empty()
	BankRules.loan(s, data, "npc_changer", "property", "river_house", 14)
	assert_bool(BankRules.collaterals(s, data, "npc_changer").any(func(o: Dictionary) -> bool: return str(o["id"]) == "river_house")).is_false()
	_days(s, 29)
	assert_bool(PropertyRules.owned(s.character, "river_house")).is_false()


func test_a_lost_pledge_makes_the_debt_a_crime() -> void:
	var s := _at_bank()
	s.room_id = "brod-townhall"
	PropertyRules.buy(s, data, "river_house")
	PropertyRules.deed(s, data, "river_house")
	s.room_id = "brod-exchange"
	BankRules.loan(s, data, "npc_changer", "property", "river_house", 14)
	PropertyRules._lose(s, data, "river_house", "сгорел")
	_days(s, 29)
	var k := _first(s)
	assert_str(str(k["state"])).is_equal(BankRules.WANTED)
	assert_bool(s.wanted.has("brod")).is_true()
	assert_int(CrimeRules.fine(s, data, "brod")).is_equal(int(k["balance"]))
	s.arrest = ""
	s.room_id = "brod-exchange"
	BankRules.repay(s, data, str(k["id"]))
	assert_bool(s.wanted.has("brod")).is_false()


func test_the_vault_keeps_things_and_takes_a_fee() -> void:
	var s := _at_bank()
	s.character["inventory"]["silver_ring"] = 1
	BankRules.vault_move(s, data, "npc_changer", "in", "silver_ring", 0)
	BankRules.vault_move(s, data, "npc_changer", "in", "", 100)
	assert_bool(s.character["inventory"].has("silver_ring")).is_false()
	_days(s, 21)
	var v := BankRules.vault(s.character, "npc_changer")
	assert_int(int(v["coins"])).is_equal(0)
	assert_int(Ledger.owed(s, "vault:npc_changer")).is_equal(50)
	assert_str(BankRules.vault_why(s, data, "npc_changer", "out", "silver_ring", 0)).is_empty()
	BankRules.vault_move(s, data, "npc_changer", "out", "silver_ring", 0)
	assert_int(Ledger.owed(s, "vault:npc_changer")).is_equal(0)
	assert_int(int(s.character["inventory"]["silver_ring"])).is_equal(1)


func test_the_master_makes_a_lender() -> void:
	var s := TestUtils.new_session()
	s.room_id = "brod-tavern-hall"
	var engine := EffectEngine.new()
	var greedy := engine.validate(s, data, "t-1", {"kind": "bank", "npc_id": "npc_innkeeper", "services": ["loan"], "loan_rate_pct_week": 30.0})
	assert_bool(bool(greedy["accepted"])).is_false()
	var none := engine.validate(s, data, "t-1", {"kind": "bank", "npc_id": "npc_innkeeper", "services": []})
	assert_bool(bool(none["accepted"])).is_false()
	var r := engine.validate(s, data, "t-1", {"kind": "bank", "npc_id": "npc_innkeeper", "services": ["loan", "vault"], "loan_rate_pct_week": 5.0, "name": "Подвал Горма"})
	assert_bool(bool(r["accepted"])).override_failure_message(str(r.get("reason", ""))).is_true()
	engine.apply(s, "t-1", [r["effect_id"]])
	assert_bool(BankRules.is_bank(s, data, "npc_innkeeper")).is_true()
	assert_bool(BankRules.offers(s, data, "npc_innkeeper", BankRules.DEPOSIT)).is_false()
	assert_float(float(BankRules.terms(s, data, "npc_innkeeper")["loan_rate"])).is_equal(5.0)
	assert_str(str(TurnSnapshot.build(s, data, 1000)["character"]["bank"])).contains("кредит под залог 5% в неделю")


func test_the_master_sees_the_contracts() -> void:
	var s := _at_bank()
	BankRules.deposit(s, data, "npc_changer", "demand", 5000)
	var text := str(TurnSnapshot.build(s, data, 1000)["character"]["bank"])
	assert_str(text).contains("вклад (Ефим Весов): 50 зм")
	assert_str(text).contains("здесь банк — Ефим Весов")
