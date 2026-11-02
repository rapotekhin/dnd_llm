extends Act
## Disengage: its walk gives no attacks of opportunity this turn.


func title() -> String:
	return "Отход"


func order() -> int:
	return 11


func tip() -> String:
	return "В этот ход ваше движение не провоцирует атаки вдогонку"


func run(s: GameSession, _data: Dictionary, f: Dictionary, _to: String, _how: Dictionary) -> Array[String]:
	f["disengaged"] = true
	return ["%s отходит осторожно" % _name(s, f)]


## One who does not want to stand beside a foe.
func worth(s: GameSession, data: Dictionary, f: Dictionary) -> float:
	if float(FightAI.role(data, f)["adjacent"]) <= 0.0 or not CombatRules._foe_beside(s, data, f):
		return 0.0
	return _weight(data)
