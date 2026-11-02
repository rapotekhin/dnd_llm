extends Act
## Walking to a square by any way it has: `Move`. A click on the map; the AI chooses the square by its plan.


func title() -> String:
	return "Идти"


func tab() -> String:
	return ""


func aim() -> String:
	return "square"


func cost(_s: GameSession, _data: Dictionary, _f: Dictionary) -> String:
	return "free"  # Move.go pays by the squares of the way


func why(s: GameSession, data: Dictionary, f: Dictionary, to: String) -> String:
	var stop := Move.stuck(s, data, f)
	if not stop.is_empty():
		return stop
	var at := FightGrid.aim_of(to)
	var here := FightGrid.cell(f)
	if at != here and FightGrid.stops(s, f, Move.routes(s, data, f)).has(at):
		return ""
	var src := CombatRules.fear_source(s, f)
	if not src.is_empty() and WalkRules.distance(at, FightGrid.cell(src)) < WalkRules.distance(here, FightGrid.cell(src)):
		return "COMBAT_FRIGHTENED"
	return "COMBAT_BAD_MOVE"


func run(s: GameSession, data: Dictionary, f: Dictionary, to: String) -> Array[String]:
	var lines: Array[String] = []
	Move.go(s, data, f, FightGrid.aim_of(to), lines)
	return lines
