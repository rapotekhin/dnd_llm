extends Act
## «Вырваться»: grappled, or restrained by something with a DC to break (a net, a web). Athletics or Acrobatics, the better,
## against the hold's DC or the grappler's Athletics (5e).


func title() -> String:
	return "Вырваться"


func tip() -> String:
	return "Действие: Атлетика или Акробатика против хватки или пут"


func order() -> int:
	return 27


func shown(s: GameSession, _data: Dictionary, f: Dictionary) -> bool:
	var me := Sheet.holder(s, f)
	return ConditionRules.has(me, "grappled") or ConditionRules.has(me, "restrained")


func why(s: GameSession, _data: Dictionary, f: Dictionary, _to: String, _how: Dictionary) -> String:
	return "COMBAT_NOT_HELD" if _hold(s, f).is_empty() else ""


## The effect that holds it and can be broken: grappled (by a fighter or a DC), restrained with escape_dc.
func _hold(s: GameSession, f: Dictionary) -> Dictionary:
	var me := Sheet.holder(s, f)
	for cond: String in ["grappled", "restrained"]:
		for e: Dictionary in ConditionRules.effects_of(me, cond):
			if cond == "grappled" or e.has("escape_dc"):
				return e
	return {}


func run(s: GameSession, data: Dictionary, f: Dictionary, _to: String, _how: Dictionary) -> Array[String]:
	var me := Sheet.holder(s, f)
	var hold := _hold(s, f)
	var skill := CombatRules.better(s, data, f, ["athletics", "acrobatics"])
	var dc := int(hold.get("escape_dc", 0))
	var mine := 0
	var against := "Сл %d" % dc
	var ok := false
	if dc > 0:
		var r := Roll.check(s, data, f, {"skill": skill, "dc": dc, "quiet": true})
		mine = int(r["total"])
		ok = bool(r["ok"])
	else:  # the grappler's Athletics: the same contest as the grapple (CombatRules.contest)
		var g := CombatRules.fighter(s, str(hold.get("by", "")))
		if g.is_empty():
			g = CombatRules.fighter(s, CombatRules.fighter_of_npc(s, str(hold.get("by", ""))))
		var c := CombatRules.contest(s, data, f, skill, g, ["athletics"])
		mine = int(c["mine"])
		ok = bool(c["won"])
		against = "%d (%s)" % [int(c["theirs"]), Sheet.holder(s, g).get("name", "хватка") if not g.is_empty() else "хватка"]
	var what := ConditionRules.name_of(data, str(hold.get("condition", ""))).to_lower()
	if ok:
		ConditionRules.remove_effect(me, int(hold["uid"]))
		if Sheet.is_hero(f):
			CharacterRules.refresh(me, data, s.items)
		CombatRules.points(s, data, f)["move"] = Move.steps(s, data, f)
	return ["%s вырывается: %s %d против %s — %s" % [_name(s, f), "Атлетика" if skill == "athletics" else "Акробатика", mine, against,
		("больше не " + what) if ok else "не выходит"]]


func worth(s: GameSession, data: Dictionary, f: Dictionary) -> float:
	return _weight(data) if not _hold(s, f).is_empty() else 0.0
