extends Act
## Picking up a thrown weapon that lies on its square or beside (v0.8.4.31, the author's feedback): the free interaction
## with a thing of 5e, once a turn; what it threw goes back to its hand. Anybody's: a foe picks up its own dagger.


func title() -> String:
	return "Подобрать"


func order() -> int:
	return 15


func tip() -> String:
	return "Поднять брошенное оружие рядом — раз за ход, бесплатно"


func cost(_s: GameSession, _data: Dictionary, _f: Dictionary, _how: Dictionary) -> String:
	return "free"


func shown(s: GameSession, _data: Dictionary, f: Dictionary) -> bool:
	return not Gear.dropped_near(s, f).is_empty()


func why(s: GameSession, data: Dictionary, f: Dictionary, _to: String, _how: Dictionary) -> String:
	if not shown(s, data, f):
		return "COMBAT_NOTHING_TO_PICK"
	return "COMBAT_PICKED" if bool(CombatRules.points(s, data, f).get("picked", false)) else ""


func run(s: GameSession, data: Dictionary, f: Dictionary, _to: String, _how: Dictionary) -> Array[String]:
	CombatRules.points(s, data, f)["picked"] = true
	var lines: Array[String] = []
	Gear.pick_up(s, data, f, lines)
	return lines


## Its own thrown weapon beside it is worth a pick to the AI.
func worth(s: GameSession, data: Dictionary, f: Dictionary) -> float:
	for i: int in Gear.dropped_near(s, f):
		if str(s.combat["dropped"][i].get("by", "")) == str(f.get("id", "")):
			return _weight(data)
	return 0.0
