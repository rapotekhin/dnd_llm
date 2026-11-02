extends Act
## The next dart, ray or chosen target of the hero's spell (v0.7.22.4, as in BG3). Paid with the spell; one who is not the
## hero picks all its targets at once (`ActionRules.more_picks`).


func title() -> String:
	return "Следующая цель"


func tab() -> String:
	return ""


func cost(_s: GameSession, _data: Dictionary, _f: Dictionary, _how: Dictionary) -> String:
	return "free"


func shown(s: GameSession, _data: Dictionary, f: Dictionary) -> bool:
	return Sheet.is_hero(f) and not CombatRules.volley(s).is_empty()


func why(s: GameSession, data: Dictionary, _f: Dictionary, to: String, _how: Dictionary) -> String:
	return CombatRules.can_volley(s, data, to)


func run(s: GameSession, data: Dictionary, _f: Dictionary, to: String, _how: Dictionary) -> Array[String]:
	return CombatRules.volley_shot(s, data, to)
