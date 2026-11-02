extends Act
## Dash: as many squares again this turn.


func title() -> String:
	return "Рывок"


func order() -> int:
	return 10


func tip() -> String:
	return "Ещё столько же клеток движения на этот ход"


func why(s: GameSession, data: Dictionary, f: Dictionary, _to: String, _how: Dictionary) -> String:
	return "COMBAT_NO_SPEED" if Move.steps(s, data, f) <= 0 else ""


func run(s: GameSession, data: Dictionary, f: Dictionary, _to: String, _how: Dictionary) -> Array[String]:
	var e := CombatRules.points(s, data, f)
	e["move"] = int(e["move"]) + Move.steps(s, data, f)
	return ["%s — рывок" % _name(s, f)]


func worth(s: GameSession, data: Dictionary, f: Dictionary) -> float:
	return _weight(data) if FightAI.far_off(s, data, f) else 0.0
