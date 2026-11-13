extends Act
## Hide: Stealth against the best passive Perception of its foes; not with a foe beside it.


func title() -> String:
	return "Спрятаться"


func order() -> int:
	return 13


func tip() -> String:
	return "Скрытность против Внимательности врагов. Спрятанный атакует с преимуществом, по нему бьют с помехой; атака или заклинание выдают"


func when() -> String:
	return "last"


func why(s: GameSession, data: Dictionary, f: Dictionary, _to: String, _how: Dictionary) -> String:
	if bool(f.get("hidden", false)):
		return "COMBAT_ALREADY_HIDDEN"
	return "COMBAT_HIDE_SEEN" if CombatRules._foe_beside(s, data, f) and not _behind(s, data, f) else ""


## Naturally Stealthy (5e): hides obscured by any creature at least one size larger beside it — a foe or one of its own side
## (v0.8.4.43.46: an ally's back too).
func _behind(s: GameSession, data: Dictionary, f: Dictionary) -> bool:
	if not Sheet.has_trait(s, data, f, "naturally_stealthy"):
		return false
	var mine := CombatRules.SIZES.find(Sheet.size(s, data, f))
	for id: String in CombatRules.foes_of(s, f) + CombatRules.friends_of(s, f):
		var o := CombatRules.fighter(s, id)
		if id != str(f["id"]) and not o.is_empty() and Attack.up(s, o) and FightGrid.touching(o, f) and CombatRules.SIZES.find(Sheet.size(s, data, o)) > mine:
			return true
	return false


func run(s: GameSession, data: Dictionary, f: Dictionary, _to: String, _how: Dictionary) -> Array[String]:
	var roll := CombatRules.stealth_roll(s, data, f)
	var vs := WatchRules.against(s, data, CombatRules.foes_of(s, f).map(func(id: String) -> Dictionary: return CombatRules.fighter(s, id)), f, int(roll["total"]))
	var best := int(vs["best"])  # v0.8.4.29.1: the hider's own invisibility, not the hero's
	var ok := bool(vs["ok"])
	var lines: Array[String] = []
	var total := int(roll["total"])
	var cut := {"total": total, "ac": best, "nat20": false, "hit": ok, "what": "проверка"}
	if FeatureRules.cutting_words(s, data, f, cut, "roll", lines):  # a bard of the foes (v0.8.4.43.46)
		total = int(cut["total"])
		ok = bool(cut["hit"])
	if ok:
		f["hidden"] = true
	lines.append("%s прячется: Скрытность %d%s против Внимательности %d — %s" % [_name(s, f), total, roll["note"], best,
		"враги теряют из виду" if ok else "враги всё видят"])
	return lines


## The AI hides only when it costs no action: its action is for the fight.
func worth(s: GameSession, data: Dictionary, f: Dictionary) -> float:
	return _weight(data) if cost(s, data, f, {}) == "bonus" else 0.0
