extends Act
## Parry and the like of a template: +AC against one melee hit it sees, wielding a melee weapon (v0.7.9). A reaction: no button.


func title() -> String:
	return "Парирование"


func tab() -> String:
	return ""


func cost(_s: GameSession, _data: Dictionary, _f: Dictionary, _how: Dictionary) -> String:
	return "reaction"


func shown(_s: GameSession, _data: Dictionary, _f: Dictionary) -> bool:
	return false


func reacts(s: GameSession, data: Dictionary, f: Dictionary, when: String, ctx: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if when != "hit" or not bool(ctx.get("melee", false)) or ConditionRules.invisible(Sheet.holder(s, CombatRules.fighter(s, str(ctx["foe"]))), data):
		return out
	if not (Sheet.template(data, f).get("actions", []) as Array).any(func(a: Dictionary) -> bool: return str(a.get("kind")) == "melee"):
		return out
	for r: Dictionary in Sheet.template(data, f).get("reactions", []):
		if r.has("ac") and int(ctx["total"]) < CombatRules.ac_of(f) + int(r["ac"]):
			out.append({"act": id, "to": str(ctx["foe"]), "how": {"ac": int(r["ac"])}, "worth": 2.0})
	return out


func run(_s: GameSession, _data: Dictionary, f: Dictionary, _to: String, how: Dictionary) -> Array[String]:
	return ["%s парирует (+%d КД)" % [f["name"], int(how["ac"])]]
