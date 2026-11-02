class_name Ledger
extends RefCounted
## One account book (v0.7.60, ADR-0012): the coins of anybody's own life change only here, each change with its cause, and
## whatever one owes is one kind of record. A loan keeps its contract in BankRules; the list of debts shows it with the rest.
## `who` — the hero or a person (v0.8.4.20, Life); the journal keeps the hero's changes.

## The journal keeps this many last changes.
const KEEP := 300


static func balance(s: GameSession, who: String = Being.HERO) -> int:
	return int(Life.of(s, who).get("gold_cp", 0))


## Coins in or out of a purse. `why` — the rule and the deed («arena:enlist»).
static func add(s: GameSession, cp: int, why: String, who: String = Being.HERO) -> void:
	if cp == 0:
		return
	if who != Being.HERO:
		purse(Life.of(s, who), balance(s, who) + cp)
		return
	s.character["gold_cp"] = balance(s) + cp
	s.ledger.append({"at": s.clock, "cp": cp, "why": why})
	if s.ledger.size() > KEEP:
		s.ledger = s.ledger.slice(s.ledger.size() - KEEP)


## The purse of anybody else — a trader's till, a person's coins (v0.8.4.10, Gear): written only here, never under nothing.
static func purse(c: Dictionary, cp: int) -> void:
	c["gold_cp"] = maxi(0, cp)


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


## `who` owes `cp` more. `key` — one debt: «tax:<place>», «cut:<org>», «vault:<npc>»; `kind` — its kind, `to` — to whom.
static func owe(s: GameSession, key: String, kind: String, cp: int, to: String, who: String = Being.HERO) -> void:
	if cp <= 0:
		return
	var book := _book(Life.of(s, who))
	if not book.has(key):
		book[key] = {"kind": kind, "cp": 0, "to": to, "day": s.day}
	book[key]["cp"] = int(book[key]["cp"]) + cp


static func owed(s: GameSession, key: String, who: String = Being.HERO) -> int:
	return int(Life.of(s, who).get("debts", {}).get(key, {}).get("cp", 0))


## The day the debt began; today when there is none.
static func since(s: GameSession, key: String, who: String = Being.HERO) -> int:
	return int(Life.of(s, who).get("debts", {}).get(key, {}).get("day", s.day))


## `cp` of the debt is gone (paid, forgiven): the rest stays, a debt at zero is closed. Coins move by `add`.
static func settle(s: GameSession, key: String, cp: int, who: String = Being.HERO) -> void:
	var book := _book(Life.of(s, who))
	if not book.has(key):
		return
	book[key]["cp"] = int(book[key]["cp"]) - cp
	if int(book[key]["cp"]) <= 0:
		book.erase(key)


## The debt is gone whole, whatever is left of it.
static func forgive(s: GameSession, key: String, who: String = Being.HERO) -> void:
	_book(Life.of(s, who)).erase(key)


## Everything `who` owes: [{key, kind, cp, to, day}], the loans too.
static func debts(s: GameSession, who: String = Being.HERO) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var c := Life.of(s, who)
	var book := _book(c)
	for key: String in book:
		out.append((book[key] as Dictionary).merged({"key": key}))
	for k: Dictionary in BankRules.open_of(c):
		if str(k["kind"]) == BankRules.LOAN:
			out.append({"key": "loan:" + str(k["id"]), "kind": "loan", "cp": int(k["balance"]), "to": str(k["bank"]), "day": int(k["start"])})
	return out
