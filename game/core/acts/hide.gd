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


## Naturally Stealthy: hides behind a foe at least one size larger.
func _behind(s: GameSession, data: Dictionary, f: Dictionary) -> bool:
	if not Sheet.has_trait(s, data, f, "naturally_stealthy"):
		return false
	for id: String in CombatRules.foes_of(s, f):
		var o := CombatRules.fighter(s, id)
		if FightGrid.touching(o, f) and CombatRules.SIZES.find(Sheet.size(s, data, o)) > CombatRules.SIZES.find(Sheet.size(s, data, f)):
			return true
	return false


func run(s: GameSession, data: Dictionary, f: Dictionary, _to: String, _how: Dictionary) -> Array[String]:
	var roll := CombatRules.stealth_roll(s, data, f)
	var best := 0
	for id: String in CombatRules.foes_of(s, f):
		best = maxi(best, Sheet.passive(s, data, CombatRules.fighter(s, id)) - WeatherRules.unseen(s, data))
	var ok := int(roll["total"]) >= best
	if ok:
		f["hidden"] = true
	return ["%s прячется: Скрытность %d%s против Внимательности %d — %s" % [_name(s, f), int(roll["total"]), roll["note"], best,
		"враги теряют из виду" if ok else "враги всё видят"]]


## The AI hides only when it costs no action: its action is for the fight.
func worth(s: GameSession, data: Dictionary, f: Dictionary) -> float:
	return _weight(data) if cost(s, data, f, {}) == "bonus" else 0.0
