extends Act
## «Уйти» by the way out it stands at. Those beside it strike as it goes. For the hero the place changes, those near run after it
## (FightField.leave); anyone else is simply gone. `how.lost` — it got out of sight, no way out needed.


func title() -> String:
	return "Уйти"


func tip() -> String:
	return "Покинуть место боя через выход, у которого вы стоите. Кто рядом, ударит вдогонку, а кто близко к выходу, побежит следом"


func order() -> int:
	return 20


func cost(_s: GameSession, _data: Dictionary, _f: Dictionary, _how: Dictionary) -> String:
	return "move"


func why(s: GameSession, data: Dictionary, f: Dictionary, _to: String, how: Dictionary) -> String:
	if bool(how.get("lost", false)):
		return ""
	var stop := Move.why(s, data, f)
	if not stop.is_empty():
		return stop
	if s.combat.has("arena"):
		return "COMBAT_ARENA_RING"
	return FightField.way_out_shut(s, data, FightGrid.cell(f))


func run(s: GameSession, data: Dictionary, f: Dictionary, _to: String, how: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	if not bool(how.get("lost", false)):
		CombatRules.leaving(s, data, f, FightGrid.NONE, lines)
	if CombatRules.stopped(s, f):
		return lines
	if Sheet.is_hero(f):
		FightField.leave(s, data, lines)
	else:
		f["status"] = "fled"
		lines.append("%s сбежал" % f["name"])
	return lines
