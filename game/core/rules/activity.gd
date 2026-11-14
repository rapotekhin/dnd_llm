class_name Activity
extends RefCounted
## An occupation's round (v0.7.67, the audit's «Занятие»): a shift, a lesson, the act of a job, a shift at the counter, a
## finished work are one cycle — a check, a step of its ladder, the line of the result. What each pays or counts after
## that is its own. A ladder is data: rows with `from`, the last reached by the margin.


## The step of `ladder` by a margin.
static func step(ladder: Array, margin: int) -> Dictionary:
	return Scale.step(ladder, margin, "from", ladder[0])


## The check of `spec` (Roll.check's keys) by `who`, with `ladder` and `label`, the word of the check for the line.
## {roll, step, line}.
static func attempt(s: GameSession, data: Dictionary, spec: Dictionary, who: String = Being.HERO) -> Dictionary:
	var r := Roll.check(s, data, Sheet.who(s, data, who), spec)
	var o := step(spec["ladder"], int(r["margin"]))
	return {"roll": r, "step": o, "line": line(str(spec["what"]), str(spec.get("label", "")), r, str(o["name"]))}


## «Смена: Убеждение 12 + 3 = 15 против Сл 12 — хорошо».
## `note` — what is said after the DC: «(угощение: мясо)», «(с преимуществом)» (v0.8.4.29.5: one line for every check of a window).
static func line(what: String, label: String, r: Dictionary, result: String, note: String = "") -> String:
	var check := Roll.sum_versus(int(r["nat"]), int(r["total"]), int(r["dc"]), r.get("ok"))
	return "%s: %s%s%s — %s" % [what, "" if label.is_empty() else label + " ", check, note, result]
