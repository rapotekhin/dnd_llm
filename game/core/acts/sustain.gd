extends Act
## A spell that goes on each turn: its next strike, its zone moved (v0.7.13.5). The numbers are the ones it was cast with. `how.spell`.


func title() -> String:
	return "Продолжить заклинание"


func tab() -> String:
	return ""


func cost(_s: GameSession, data: Dictionary, _f: Dictionary, how: Dictionary) -> String:
	return str(SpellEffects.sustained(data, str(how.get("spell", ""))).get("cost", "action"))


func shown(s: GameSession, data: Dictionary, f: Dictionary) -> bool:
	return not SpellEffects.actions(s, data, f).is_empty()


func why(s: GameSession, data: Dictionary, f: Dictionary, to: String, how: Dictionary) -> String:
	return SpellEffects.can_act(s, data, f, str(how.get("spell", "")), to)


func run(s: GameSession, data: Dictionary, f: Dictionary, to: String, how: Dictionary) -> Array[String]:
	var spell := str(how["spell"])
	var e := SpellEffects.effect_of(s, f, spell)
	s.combat["by"] = {"dc": int(e.get("dc", CombatRules.spell_dc(s))), "attack": int(e.get("attack", CombatRules.spell_attack(s))),
		"ability": str(e.get("ability", CombatRules.spell_ability(s))), "caster": str(f["id"])}
	var lines := SpellEffects.act(s, data, f, spell, to)
	s.combat.erase("by")
	return lines


func offers(s: GameSession, data: Dictionary, f: Dictionary, targets: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if Sheet.is_hero(f):
		return out
	var power := float(FightAI.cfg(data)["spells"]["sustained"]) * float(FightAI.role(data, f)["cast"]) / 6.0
	for a: Dictionary in SpellEffects.actions(s, data, f):
		var spell := str(a["id"]).trim_prefix("spell_")
		if not CombatRules.short_of(f, str(a["cost"]), 1).is_empty():
			continue
		for t: Dictionary in targets:
			out.append({"act": id, "to": str(t["id"]), "how": {"spell": spell}, "t": t, "kind": "sustain", "far": CombatRules._spell_squares(s, data, spell, f), "power": power})
	return out
