extends Act
## «Сдаться»: while a thinking foe still fights. The hero's fight ends at once: a captive, or held by the law's guard; a bout to
## surrender is lost, the blood pit does not allow it. Anyone else lays down its weapon and is out of the fight.


func title() -> String:
	return "Сдаться"


func tip() -> String:
	return "Бросить оружие: бой окончен, вы в плену у разумных врагов, вещи отберут; страже — задержание"


func order() -> int:
	return 90


func confirm() -> Array[String]:
	return ["Сдаться?", "Бой окончится, вы окажетесь в плену, вещи отберут.", title()]


func cost(_s: GameSession, _data: Dictionary, _f: Dictionary, _how: Dictionary) -> String:
	return "free"


func why(s: GameSession, data: Dictionary, f: Dictionary, _to: String, _how: Dictionary) -> String:
	if s.combat.has("arena"):  # v0.7.45: a bout to surrender may be given up, the blood pit may not
		return "" if ArenaRules.yield_bout(s) else "COMBAT_NO_SURRENDER_PIT"
	if not CombatRules.foes_of(s, f).any(func(x: String) -> bool: return CombatRules._intelligent(data, CombatRules.fighter(s, x))):
		return "COMBAT_NO_SURRENDER"
	return ""


func run(s: GameSession, _data: Dictionary, f: Dictionary, _to: String, _how: Dictionary) -> Array[String]:
	var bout := s.combat.has("arena")
	if not Sheet.is_hero(f):
		f["status"] = "surrendered"
	elif bout:  # v0.7.45: the bout is lost, nobody takes the hero
		s.combat["outcome"] = "arena_lost"
	else:
		s.combat["outcome"] = "captured"
		s.combat["surrendered"] = true
	return [("%s поднимает руку — сдаётся" if bout else "%s бросает оружие и сдаётся") % _name(s, f)]


## In a bout to surrender: at the HP the arena sets.
func worth(s: GameSession, data: Dictionary, f: Dictionary) -> float:
	var me := Sheet.holder(s, f)
	if not ArenaRules.yield_bout(s) or int(me["hp"]) * 100 > int(me["max_hp"]) * int(ArenaRules.cfg(data)["yield_hp_pct"]):
		return 0.0
	return 1.0
