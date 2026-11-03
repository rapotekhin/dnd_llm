extends Act
## A jump by the SRD: the Strength score in feet after a run of 10 feet, half from a stand, no further than the move left; over a
## pit, water, the ground that hurts, not through a wall or a body. Where to — the second click, `how.at`.


func title() -> String:
	return "Прыжок"


func tip() -> String:
	return "Перепрыгнуть яму, воду или опасную клетку. Длина по Силе, с разбега вдвое дальше, тратит движение"


func order() -> int:
	return 21


func second() -> bool:
	return true


func cost(_s: GameSession, _data: Dictionary, _f: Dictionary, _how: Dictionary) -> String:
	return "move"


func amount(_s: GameSession, _data: Dictionary, f: Dictionary, how: Dictionary) -> int:
	return FightGrid.dist_to(f, FightGrid.aim_of(str(how["at"]))) if how.has("at") else 1


## How far it jumps, in squares.
func _reach(s: GameSession, data: Dictionary, f: Dictionary) -> int:
	if not Move.why(s, data, f).is_empty():
		return 0
	var e := CombatRules.points(s, data, f)
	var ft := Sheet.ability(s, data, f, "str")
	if int(e.get("walked", 0)) < 2:
		ft /= 2
	else:  # a running jump goes further by a status (Second-Story Work, v0.8.4.26.1)
		for x: Dictionary in ConditionRules.effects(Sheet.holder(s, f)):
			ft += int(x.get("jump_ft", 0))
	return mini(int(ft / int(FightGrid.cfg(data)["ft"])), int(e.get("move", 0)))


func squares(s: GameSession, data: Dictionary, f: Dictionary, _to: String) -> Dictionary:
	var out := {}
	var n := _reach(s, data, f)
	var g := FightGrid.grid(s, data)
	var from := FightGrid.cell(f)
	var bodies := FightGrid.bodies(s, str(f["id"]))
	for y: int in range(-n, n + 1):
		for x: int in range(-n, n + 1):
			var at := from + Vector2i(x, y)
			if maxi(absi(x), absi(y)) < 2 or bodies.has(at) or not FightGrid.walkable(g, at) or FightGrid.shut(s, g, at):
				continue
			if FightGrid.line_of(from, at).all(func(c: Vector2i) -> bool: return FightGrid.flags_at(g, c) & FightGrid.SOLID == 0 and not bodies.has(c) and not FightGrid.shut(s, g, c)):
				out[at] = true
	return out


func why(s: GameSession, data: Dictionary, f: Dictionary, _to: String, how: Dictionary) -> String:
	var stop := Move.why(s, data, f)
	if not stop.is_empty():
		return stop
	var can_go := squares(s, data, f, "")
	if how.has("at"):
		return "" if can_go.has(FightGrid.aim_of(str(how["at"]))) else "COMBAT_BAD_MOVE"
	return "COMBAT_BAD_MOVE" if can_go.is_empty() else ""


func run(s: GameSession, data: Dictionary, f: Dictionary, _to: String, how: Dictionary) -> Array[String]:
	var at := FightGrid.aim_of(str(how["at"]))
	var lines: Array[String] = []
	var n := FightGrid.dist_to(f, at)
	CombatRules.leaving(s, data, f, at, lines)
	if CombatRules.stopped(s, f):
		return lines
	FightGrid.put(f, at)
	lines.append("%s прыгает" % _name(s, f))
	var e := CombatRules.points(s, data, f)
	e["walked"] = int(e.get("walked", 0)) + n
	FightField.note_walk(s, str(f["id"]), [FightGrid.tag(at)])
	FightField.stepped(s, data, f, lines)
	Move.arrived(s, data, f, lines)
	return lines
