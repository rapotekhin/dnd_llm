class_name Ledger
extends RefCounted
## One account book (v0.7.60, ADR-0012): the hero's coins change only here, each change with its cause, and whatever the
## hero owes is one kind of record. A loan keeps its contract in BankRules; the list of debts shows it with the rest.

## The journal keeps this many last changes.
const KEEP := 300


static func balance(s: GameSession) -> int:
	return int(s.character.get("gold_cp", 0))


## Coins in or out of the hero's purse. `why` — the rule and the deed («arena:enlist»).
static func add(s: GameSession, cp: int, why: String) -> void:
	if cp == 0:
		return
	s.character["gold_cp"] = balance(s) + cp
	s.ledger.append({"at": s.clock, "cp": cp, "why": why})
	if s.ledger.size() > KEEP:
		s.ledger = s.ledger.slice(s.ledger.size() - KEEP)


## The sum of the journal's changes for causes starting with `prefix`.
static func total(s: GameSession, prefix: String = "") -> int:
	var n := 0
	for e: Dictionary in s.ledger:
		if str(e["why"]).begins_with(prefix):
			n += int(e["cp"])
	return n


# --- debts --------------------------------------------------------------------------------------------------------


static func _book(c: Dictionary) -> Dictionary:
	if not c.has("debts"):
		c["debts"] = {}
	return c["debts"]


## The hero owes `cp` more. `key` — one debt: «tax:<place>», «cut:<org>», «vault:<npc>»; `kind` — its kind, `to` — to whom.
static func owe(s: GameSession, key: String, kind: String, cp: int, to: String) -> void:
	if cp <= 0:
		return
	var book := _book(s.character)
	if not book.has(key):
		book[key] = {"kind": kind, "cp": 0, "to": to, "day": s.day}
	book[key]["cp"] = int(book[key]["cp"]) + cp


static func owed(s: GameSession, key: String) -> int:
	return int(s.character.get("debts", {}).get(key, {}).get("cp", 0))


## The day the debt began; today when there is none.
static func since(s: GameSession, key: String) -> int:
	return int(s.character.get("debts", {}).get(key, {}).get("day", s.day))


## `cp` of the debt is gone (paid, forgiven): the rest stays, a debt at zero is closed. Coins move by `add`.
static func settle(s: GameSession, key: String, cp: int) -> void:
	var book := _book(s.character)
	if not book.has(key):
		return
	book[key]["cp"] = int(book[key]["cp"]) - cp
	if int(book[key]["cp"]) <= 0:
		book.erase(key)


## The debt is gone whole, whatever is left of it.
static func forgive(s: GameSession, key: String) -> void:
	_book(s.character).erase(key)


## Everything the hero owes: [{key, kind, cp, to, day}], the loans too.
static func debts(s: GameSession) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var book := _book(s.character)
	for key: String in book:
		out.append((book[key] as Dictionary).merged({"key": key}))
	for k: Dictionary in BankRules.open_of(s.character):
		if str(k["kind"]) == BankRules.LOAN:
			out.append({"key": "loan:" + str(k["id"]), "kind": "loan", "cp": int(k["balance"]), "to": str(k["bank"]), "day": int(k["start"])})
	return out
