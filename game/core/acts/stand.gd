extends Act
## Getting up: half the speed (5e).


func title() -> String:
	return "Встать"


func order() -> int:
	return 14


func tip() -> String:
	return "Подняться на ноги — на это уходит половина скорости"


func cost(_s: GameSession, _data: Dictionary, _f: Dictionary, _how: Dictionary) -> String:
	return "move"


func amount(s: GameSession, data: Dictionary, f: Dictionary, _how: Dictionary) -> int:
	return maxi(1, Move.steps(s, data, f) / 2)


func shown(s: GameSession, _data: Dictionary, f: Dictionary) -> bool:
	return ConditionRules.has(Sheet.holder(s, f), "prone")


func why(s: GameSession, data: Dictionary, f: Dictionary, _to: String, _how: Dictionary) -> String:
	if not shown(s, data, f):
		return "COMBAT_NOT_PRONE"
	return "COMBAT_NO_MOVE" if Sheet.speed(s, data, f) <= 0 else ""


func run(s: GameSession, _data: Dictionary, f: Dictionary, _to: String, _how: Dictionary) -> Array[String]:
	ConditionRules.remove(Sheet.holder(s, f), "prone")
	return ["%s поднимается на ноги" % _name(s, f)]


func worth(s: GameSession, data: Dictionary, f: Dictionary) -> float:
	return _weight(data) if shown(s, data, f) else 0.0
