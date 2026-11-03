extends Act
## Help: a foe beside it is hemmed in, the next blow of a friend at it has advantage.


func title() -> String:
	return "Помочь"


func tip() -> String:
	return "Отвлечь врага рядом с вами: союзник ударит его с преимуществом. Тратит действие"


func order() -> int:
	return 22


func aim() -> String:
	return FOE


func why(s: GameSession, data: Dictionary, f: Dictionary, to: String, _how: Dictionary) -> String:
	if not CombatRules.friends_of(s, f).any(func(x: String) -> bool: return x != str(f["id"])):
		return "COMBAT_NO_ALLY"
	var t := _foe(s, f, to)
	if t.is_empty():
		return "COMBAT_BAD_TARGET"
	return "" if CombatRules.blade_reaches(s, data, f, t) else "COMBAT_OUT_OF_REACH"


func run(s: GameSession, _data: Dictionary, f: Dictionary, to: String, _how: Dictionary) -> Array[String]:
	var t := CombatRules.fighter(s, to)
	ConditionRules.add_effect(Sheet.holder(s, t), {"condition": "helped", "by": str(f["id"]), "ends": {"turn": str(f["id"])}})  # until the helper's next turn
	return ["%s отвлекает: %s, союзник ударит с преимуществом" % [_name(s, f), Sheet.holder(s, t)["name"]]]


## One with nothing better: below any blow that can land.
func offers(s: GameSession, data: Dictionary, f: Dictionary, targets: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if Sheet.is_hero(f):
		return out
	for t: Dictionary in targets:
		if why(s, data, f, str(t["id"]), {}) != "COMBAT_NO_ALLY":
			out.append({"act": id, "to": str(t["id"]), "how": {}, "t": t, "kind": "help", "touch": true, "far": 1, "power": _weight(data)})
	return out
