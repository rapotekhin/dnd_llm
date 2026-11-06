extends Act
## Frenzy (v0.7.8): a raging berserker goes into it for nothing; a melee blow as a bonus action every turn, a level of exhaustion
## when the fight ends.


func title() -> String:
	return "Неистовство"


func tip() -> String:
	return "Пока вы в ярости: удар бонусным действием каждый ход; после боя — степень истощения"


func order() -> int:
	return 28


func shown(s: GameSession, _data: Dictionary, f: Dictionary) -> bool:
	return CharacterRules.has_feature(Sheet.holder(s, f), "frenzy") and bool(f.get("raging", false)) and not bool(f.get("frenzy", false))


func cost(_s: GameSession, _data: Dictionary, _f: Dictionary, _how: Dictionary) -> String:
	return "free"


func why(s: GameSession, data: Dictionary, f: Dictionary, _to: String, _how: Dictionary) -> String:
	return "" if shown(s, data, f) else "COMBAT_NO_FRENZY"


func worth(_s: GameSession, data: Dictionary, _f: Dictionary) -> float:
	return _weight(data)


func run(s: GameSession, _data: Dictionary, f: Dictionary, _to: String, _how: Dictionary) -> Array[String]:
	f["frenzy"] = true
	return ["%s впадает в неистовство: удар бонусным действием каждый ход, когда ярость кончится — истощение" % _name(s, f)]
