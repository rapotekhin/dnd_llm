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
	return Sheet.is_hero(f) and CharacterRules.has_feature(s.character, "frenzy") and bool(s.combat.get("raging", false)) and not bool(s.combat.get("frenzy", false))


func cost(_s: GameSession, _data: Dictionary, _f: Dictionary, _how: Dictionary) -> String:
	return "free"


func why(s: GameSession, data: Dictionary, f: Dictionary, _to: String, _how: Dictionary) -> String:
	return "" if shown(s, data, f) else "COMBAT_NO_FRENZY"


func run(s: GameSession, _data: Dictionary, f: Dictionary, _to: String, _how: Dictionary) -> Array[String]:
	s.combat["frenzy"] = true
	return ["%s впадает в неистовство: удар бонусным действием каждый ход, после боя — истощение" % _name(s, f)]
