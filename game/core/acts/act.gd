class_name Act
extends RefCounted
## One thing a fighter can do in a fight (v0.8.4.7, ADR-0016). One act is one file in core/acts/: the folder is read by itself,
## so a new file is at once a button of the player, a choice of the AI and a line of the test over `Acts.all()`. `f` is any
## fighter, the hero differs only in who chooses. The name and the text of an act live in its file: nothing else to touch.

var id := ""


func title() -> String:
	return id


func tip() -> String:
	return ""


## The tab of the fight's buttons; "" — no button, a click on the map does it.
func tab() -> String:
	return "common"


## What it is aimed at: "" nothing, "square" a square of the map (`to` is "@x,y").
func aim() -> String:
	return ""


## What it costs now: "action", "bonus", "move" or "free". An action unless `rules.combat.act_bonus` gives it as a bonus.
func cost(s: GameSession, data: Dictionary, f: Dictionary) -> String:
	return "bonus" if _by_bonus(s, data, f) else "action"


## How many of the cost: squares of the move.
func amount(_s: GameSession, _data: Dictionary, _f: Dictionary) -> int:
	return 1


## A button at all: «Встать» is there only for one who lies.
func shown(_s: GameSession, _data: Dictionary, _f: Dictionary) -> bool:
	return true


## Why it cannot, by this act's own rule: a key or "". The turn and the points are `can`'s.
func why(_s: GameSession, _data: Dictionary, _f: Dictionary, _to: String) -> String:
	return ""


## What it does; the points are paid already. Lines.
func run(_s: GameSession, _data: Dictionary, _f: Dictionary, _to: String) -> Array[String]:
	return []


## What it is worth to the AI, 0 — not now. The weights are in `rules.combat.ai.acts`.
func worth(_s: GameSession, _data: Dictionary, _f: Dictionary) -> float:
	return 0.0


## When the AI does a thing that costs no action: "first" before it walks and strikes, "last" after.
func when() -> String:
	return "first"


## "" when `f` can do it now, else a key.
func can(s: GameSession, data: Dictionary, f: Dictionary, to: String = "") -> String:
	if not CombatRules.can_act(s, f):
		return "COMBAT_NOT_YOUR_TURN"
	var stop := why(s, data, f, to)
	return stop if not stop.is_empty() else CombatRules.short_of(f, cost(s, data, f), amount(s, data, f))


## Pays and does (`can` first). Lines.
func go(s: GameSession, data: Dictionary, f: Dictionary, to: String = "") -> Array[String]:
	CombatRules.pay(f, cost(s, data, f), amount(s, data, f))
	return run(s, data, f, to)


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
