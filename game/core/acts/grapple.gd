extends Act
## A grapple instead of one attack: Athletics against the better of Athletics and Acrobatics. It holds until the one who holds
## walks off, falls or lets go.


func title() -> String:
	return "Схватить"


func tip() -> String:
	return "Вместо одной атаки: Атлетика против Атлетики или Акробатики врага рядом. Схваченный не может отойти, пока вы его держите (до вашего шага прочь)"


func order() -> int:
	return 25


func aim() -> String:
	return FOE


func cost(_s: GameSession, _data: Dictionary, _f: Dictionary, _how: Dictionary) -> String:
	return "attack"


func why(s: GameSession, data: Dictionary, f: Dictionary, to: String, _how: Dictionary) -> String:
	return CombatRules.why_tussle(s, data, f, to)


func run(s: GameSession, data: Dictionary, f: Dictionary, to: String, _how: Dictionary) -> Array[String]:
	var t := CombatRules.fighter(s, to)
	var lines: Array[String] = []
	if not CombatRules.tussle(s, data, f, t, "пытается схватить", "grappled", lines):
		return lines
	CombatRules._hold(Sheet.holder(s, t), "grappled", str(f["id"]))
	if Sheet.is_hero(t):
		CharacterRules.refresh(s.character, data, s.items)
	lines.append("%s схвачен: не может отойти" % Sheet.holder(s, t)["name"])
	return lines


func offers(s: GameSession, data: Dictionary, f: Dictionary, targets: Array[Dictionary]) -> Array[Dictionary]:
	return CombatRules.tussle_offers(s, data, f, targets, id, _weight(data))
