extends Act
## Dodge: until its next turn attacks at it have disadvantage and its Dexterity saves advantage.


func title() -> String:
	return "Уклонение"


func order() -> int:
	return 12


func tip() -> String:
	return "До следующего хода атаки по вам с помехой, спасброски Ловкости с преимуществом"


func run(s: GameSession, _data: Dictionary, f: Dictionary, _to: String, _how: Dictionary) -> Array[String]:
	f["dodging"] = true
	return ["%s уходит в оборону" % _name(s, f)]


func worth(s: GameSession, data: Dictionary, f: Dictionary) -> float:
	return _weight(data) if not CombatRules.foes_of(s, f).is_empty() else 0.0
