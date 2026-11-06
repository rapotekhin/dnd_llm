extends Act
## Pact of the Chain (v0.8.4.33, 5e): one with the pact gives up one attack of its Attack action, and its familiar strikes with
## its own reaction at a foe in its reach. Anybody's familiar: the hero's called by its spell, another's by `called_by`.

const FAMILIAR_SPELL := "find_familiar"


func title() -> String:
	return "Удар фамильяра"


func tip() -> String:
	return "Пакт цепи: вместо одной своей атаки фамильяр атакует реакцией"


func order() -> int:
	return 22


func aim() -> String:
	return FOE


func cost(_s: GameSession, _data: Dictionary, _f: Dictionary, _how: Dictionary) -> String:
	return "attack"


func shown(s: GameSession, _data: Dictionary, f: Dictionary) -> bool:
	return FeatureRules.has(Sheet.holder(s, f), "pact_of_the_chain") and not familiar(s, f).is_empty()


func why(s: GameSession, data: Dictionary, f: Dictionary, to: String, _how: Dictionary) -> String:
	if not FeatureRules.has(Sheet.holder(s, f), "pact_of_the_chain"):
		return "COMBAT_NO_PACT"
	var fam := familiar(s, f)
	if fam.is_empty():
		return "COMBAT_NO_FAMILIAR"
	if bool(fam.get("reacted", false)) or ConditionRules.incapacitated(Sheet.holder(s, fam)):
		return "COMBAT_FAMILIAR_BUSY"
	return Acts.one("attack").why(s, data, fam, to, {})  # its own reach and its own blow


func run(s: GameSession, data: Dictionary, f: Dictionary, to: String, _how: Dictionary) -> Array[String]:
	var fam := familiar(s, f)
	fam["reacted"] = true
	var lines: Array[String] = ["%s отдаёт атаку фамильяру" % _name(s, f)]
	lines.append_array(Acts.one("attack").run(s, data, fam, to, {}))
	return lines


## The familiar of `f` standing in the fight: a creature of Find Familiar on its side, {} — none.
static func familiar(s: GameSession, f: Dictionary) -> Dictionary:
	for id: String in CombatRules.friends_of(s, f):
		var a := CombatRules.fighter(s, id)
		if str(a.get("spell", "")) != FAMILIAR_SPELL or not Attack.up(s, a):
			continue
		var by := str(a.get("called_by", ""))
		if by == str(f.get("id", "")) or (by.is_empty() and Sheet.is_hero(f)):
			return a
	return {}
