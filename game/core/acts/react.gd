extends Act
## A spell cast as a reaction by one who is not the hero (the hero has its window, `FeatureRules.reactions`): a row of
## `rules.spell_effects` says when: «hit» before a blow lands, «damage» after it, «spell» at a foe's spell. `how`: spell, slot,
## per_day, ctx: what happened, which the answer changes.


func title() -> String:
	return "Заклинание реакцией"


func tab() -> String:
	return ""


func cost(_s: GameSession, _data: Dictionary, _f: Dictionary, _how: Dictionary) -> String:
	return "reaction"


func shown(_s: GameSession, _data: Dictionary, _f: Dictionary) -> bool:
	return false


func reacts(s: GameSession, data: Dictionary, f: Dictionary, when: String, ctx: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if SpellEffects.silenced(s, data, f):
		return out
	for o: Dictionary in MonsterRules.castable(data, f):
		var spell := str(o["id"])
		if str(SpellEffects.spec(data, spell).get("reaction", "")) == when and _fits(s, data, f, spell, when, ctx):
			out.append({"act": id, "to": str(ctx["foe"]), "how": {"spell": spell, "slot": int(o["slot"]), "per_day": bool(o.get("per_day", false)), "ctx": ctx}, "worth": 1.0})
	return out


## Worth a slot and within reach.
func _fits(s: GameSession, data: Dictionary, f: Dictionary, spell: String, when: String, ctx: Dictionary) -> bool:
	if when == "hit":
		return int(ctx["total"]) < CombatRules.ac_of(f) + int(SpellEffects.spec(data, spell).get("ac_plus", 0))
	if when == "spell" and int(ctx["circle"]) < int(FightAI.cfg(data)["spells"]["counter_from"]):
		return false
	return FightGrid.feet(data, f, CombatRules.fighter(s, str(ctx["foe"]))) <= int(data["spells"][spell].get("range_ft", 0))


func run(s: GameSession, data: Dictionary, f: Dictionary, to: String, how: Dictionary) -> Array[String]:
	var spell := str(how["spell"])
	var slot := int(how["slot"])
	var ctx: Dictionary = how["ctx"]
	var sp: Dictionary = data["spells"][spell]
	var row := SpellEffects.spec(data, spell)
	var lines: Array[String] = []
	MonsterRules.pay_spell(f, spell, how)
	var was: Dictionary = s.combat.get("by", {})
	s.combat["by"] = ActionRules.scope(s, data, f, spell)
	match str(row["reaction"]):
		"hit":
			ConditionRules.add_effect(f, GameSession.whole(SpellEffects._effect(s, data, spell, slot, f)))
			lines.append("%s: %s" % [f["name"], sp["name"]])
		"damage":
			SpellEffects.rebuke(s, data, CombatRules.fighter(s, to), spell, slot, lines, s.combat["by"])
		"spell":
			ctx["stopped"] = _stops(s, data, f, spell, slot, ctx, lines)
	s.combat.erase("by")
	if not was.is_empty():
		s.combat["by"] = was
	return lines


## A spell no higher than the slot fails; a higher one by a check of the spellcasting ability against 10 + its circle.
func _stops(s: GameSession, data: Dictionary, f: Dictionary, spell: String, slot: int, ctx: Dictionary, lines: Array[String]) -> bool:
	var name := str(data["spells"][str(ctx["spell"])]["name"])
	var what := str(data["spells"][spell]["name"])
	var circle := int(ctx["circle"])
	if circle <= slot:
		lines.append("%s: %s — «%s» срывается" % [f["name"], what, name])
		return true
	var mod := Sheet.ability_mod(s, data, f, CombatRules.spell_ability(s))
	var total := Roll.d20(s.rng) + mod
	var ok := total >= 10 + circle
	lines.append("%s: %s — проверка %d против Сл %d — %s" % [f["name"], what, total, 10 + circle, "«%s» срывается" % name if ok else "не вышло"])
	return ok
