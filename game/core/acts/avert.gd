extends Act
## Averting the eyes from a deadly gaze (a basilisk, v0.8.4.27.6), for nothing, until it looks again or the fight ends: one who
## averts does not see a foe with a `gaze` trait (FightGrid.veiled) — the gaze's aura passes it by, it strikes that foe with
## disadvantage and is struck with advantage, as any unseen one. The AI averts when such a foe is within its gaze.


func title() -> String:
	return "Отвести взгляд"


func tip() -> String:
	return "Не смотреть на того, чей взгляд опасен: взгляд не действует, но бить его — с помехой, а он бьёт с преимуществом"


func order() -> int:
	return 15


func buttons(s: GameSession, data: Dictionary, f: Dictionary) -> Array[Dictionary]:
	if _averts(s, data, f):
		return [{"name": "Do_" + id, "text": "Смотреть снова", "how": {}, "tip": "Снова смотреть на врагов — и снова рисковать под их взглядом"}]
	return super.buttons(s, data, f)


func cost(_s: GameSession, _data: Dictionary, _f: Dictionary, _how: Dictionary) -> String:
	return "free"


func shown(s: GameSession, data: Dictionary, f: Dictionary) -> bool:
	return _averts(s, data, f) or not _gazers(s, data, f, 1 << 20).is_empty()


func why(s: GameSession, data: Dictionary, f: Dictionary, _to: String, _how: Dictionary) -> String:
	return "" if shown(s, data, f) else "COMBAT_NO_GAZE"


func run(s: GameSession, data: Dictionary, f: Dictionary, _to: String, _how: Dictionary) -> Array[String]:
	var me := Sheet.holder(s, f)
	for e: Dictionary in ConditionRules.effects(me).duplicate():
		if bool(e.get("averts", false)):
			ConditionRules.remove_effect(me, int(e["uid"]))
			return ["%s снова смотрит на врагов" % _name(s, f)]
	# "turn" of nobody: it lasts the whole fight and goes with it (CombatRules.close ends what lasts until a turn)
	ConditionRules.add_effect(me, {"condition": "", "averts": true, "ends": {"turn": "fight"}, "source": {"kind": "engine", "name": title()}})
	return ["%s отводит взгляд" % _name(s, f)]


func worth(s: GameSession, data: Dictionary, f: Dictionary) -> float:
	return _weight(data) if not _averts(s, data, f) and not _gazers(s, data, f, -1).is_empty() else 0.0


func _averts(s: GameSession, data: Dictionary, f: Dictionary) -> bool:
	return ConditionRules.does(Sheet.holder(s, f), data, "averts")


## Its foes up with a deadly gaze within `ft` (-1 — within the gaze's own aura).
func _gazers(s: GameSession, data: Dictionary, f: Dictionary, ft: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for one: String in CombatRules.foes_of(s, f):
		var o := CombatRules.fighter(s, one)
		if o.is_empty() or not Attack.up(s, o):
			continue
		for e: Dictionary in ItemRules.born_effects(data, Sheet.holder(s, o)):
			if bool(e.get("gaze", false)) and FightGrid.feet(data, o, f) <= (int(e.get("aura", {}).get("ft", 30)) if ft < 0 else ft):
				out.append(o)
				break
	return out
