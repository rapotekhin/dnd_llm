class_name Act
extends RefCounted
## One thing a fighter can do in a fight (v0.8.4.7, ADR-0016). One act is one file in core/acts/: the folder is read by itself,
## so a new file is at once a button of the player, a choice of the AI and a line of the test over `Acts.all()`. `f` is any
## fighter, the hero differs only in who chooses. The name and the text of an act live in its file: nothing else to touch.
## `to` is what it is aimed at: a fighter's id or "@x,y". `how` is which way of it: the hand of a blow, a spell, a side, a thing.

const FOE := "foe"
const SQUARE := "square"

var id := ""


func title() -> String:
	return id


func tip() -> String:
	return ""


## The tab of the fight's buttons; "" — no button of `buttons`: a click on the map, or a tab that draws its own by the numbers.
func tab() -> String:
	return "common"


## Its place on the tab.
func order() -> int:
	return 50


## What it is aimed at: "" nothing, `FOE` a foe, `SQUARE` a square of the map (`to` is "@x,y").
func aim() -> String:
	return ""


## The button asks a second click: a square lit by `squares`, it comes in `how.at`.
func second() -> bool:
	return false


## The squares of the second click: {square: true}.
func squares(_s: GameSession, _data: Dictionary, _f: Dictionary, _to: String) -> Dictionary:
	return {}


## The question before an irreversible act: [title, text, the button], [] — none.
func confirm() -> Array[String]:
	return []


## Its buttons: {name, text, how, tip}. One by default; a parley has one for each skill.
func buttons(_s: GameSession, _data: Dictionary, _f: Dictionary) -> Array[Dictionary]:
	return [{"name": "Do_" + id, "text": title(), "how": {}, "tip": tip()}]


## What it costs now: "action", "attack" (one attack of the Attack action), "bonus", "move" or "free". An action unless
## `rules.combat.act_bonus` gives it as a bonus.
func cost(s: GameSession, data: Dictionary, f: Dictionary, _how: Dictionary) -> String:
	return "bonus" if _by_bonus(s, data, f) else "action"


## How many of the cost: squares of the move.
func amount(_s: GameSession, _data: Dictionary, _f: Dictionary, _how: Dictionary) -> int:
	return 1


## A button at all: «Встать» is there only for one who lies.
func shown(_s: GameSession, _data: Dictionary, _f: Dictionary) -> bool:
	return true


## Why it cannot, by this act's own rule: a key or "". The turn and the points are `can`'s.
func why(_s: GameSession, _data: Dictionary, _f: Dictionary, _to: String, _how: Dictionary) -> String:
	return ""


## What it does; the points are paid already. Lines.
func run(_s: GameSession, _data: Dictionary, _f: Dictionary, _to: String, _how: Dictionary) -> Array[String]:
	return []


## What it is worth to the AI with no aim, 0 — not now. The weights are in `rules.combat.ai.acts`.
func worth(_s: GameSession, _data: Dictionary, _f: Dictionary) -> float:
	return 0.0


## What the AI could do with it at `targets`: {act, to, how, t, kind, far, power, touch, short}. `far` — squares it reaches,
## `touch` — by a blade's reach, `power` — what it is worth.
func offers(_s: GameSession, _data: Dictionary, _f: Dictionary, _targets: Array[Dictionary]) -> Array[Dictionary]:
	return []


## What it can do as a reaction when `when` happens («hit», «damage», «spell»; `ctx` says what): [{act, to, how, worth}] (`Acts.react`).
func reacts(_s: GameSession, _data: Dictionary, _f: Dictionary, _when: String, _ctx: Dictionary) -> Array[Dictionary]:
	return []


## What it would do now for nothing but points when more than one way of it can be wanted, at `moment` («first», «last»): [{to, how}].
func spare(_s: GameSession, _data: Dictionary, _f: Dictionary, _moment: String) -> Array[Dictionary]:
	return []


## When the AI does a thing that costs no action: "first" before it walks and strikes, "last" after.
func when() -> String:
	return "first"


## A check the game rolls after it is paid, with its card and its share of the master: {} — none.
func check(_how: Dictionary) -> Dictionary:
	return {}


## "" when `f` can do it now, else a key.
func can(s: GameSession, data: Dictionary, f: Dictionary, to: String = "", how: Dictionary = {}) -> String:
	if not CombatRules.can_act(s, f):
		return "COMBAT_NOT_YOUR_TURN"
	CombatRules.points(s, data, f)
	var stop := why(s, data, f, to, how)
	return stop if not stop.is_empty() else CombatRules.short_of(f, cost(s, data, f, how), amount(s, data, f, how))


## Pays and does (`can` first). Lines.
func go(s: GameSession, data: Dictionary, f: Dictionary, to: String = "", how: Dictionary = {}) -> Array[String]:
	CombatRules.points(s, data, f)
	var price := cost(s, data, f, how)
	if price == "attack":
		CombatRules.pay_attack(s, data, f)
	else:
		CombatRules.pay(f, price, amount(s, data, f, how))
	return run(s, data, f, to, how)


func _by_bonus(s: GameSession, data: Dictionary, f: Dictionary) -> bool:
	var e := CombatRules.points(s, data, f)
	if int(e.get("bonus", 0)) <= 0:
		return false
	for row: Dictionary in CombatRules.cfg(data)["act_bonus"].get(id, []):
		if bool(row.get("last", false)) and int(e.get("action", 0)) > 0:
			continue
		if Sheet.has_trait(s, data, f, str(row.get("has", ""))) or SpellEffects.has(Sheet.holder(s, f), str(row.get("status", ""))):
			return true
	return false


func _weight(data: Dictionary) -> float:
	return float(FightAI.cfg(data)["acts"][id])


func _name(s: GameSession, f: Dictionary) -> String:
	return str(Sheet.holder(s, f)["name"])


## The foe of `f` that `to` names, {} — none.
func _foe(s: GameSession, f: Dictionary, to: String) -> Dictionary:
	return CombatRules.fighter(s, to) if CombatRules.foes_of(s, f).has(to) else {}
