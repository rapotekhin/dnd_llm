extends Act
## A reaction to a fall (v0.8.4.26.1): Slow Fall takes off the damage by the level, `rules.combat.grid.slow_fall` (a feature →
## per level); a spell with the reaction `fall` (Feather Fall, v0.8.4.26.2) takes it all for a slot. Anybody's; the hero's
## goes by itself (Acts.react, moment `fall`). `how.ctx` — the fall's {dmg, cut}.


func title() -> String:
	return "Смягчить падение"


func tab() -> String:
	return ""


func cost(_s: GameSession, _data: Dictionary, _f: Dictionary, _how: Dictionary) -> String:
	return "reaction"


func shown(_s: GameSession, _data: Dictionary, _f: Dictionary) -> bool:
	return false


func reacts(s: GameSession, data: Dictionary, f: Dictionary, when: String, ctx: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if when != "fall":
		return out
	var me := Sheet.holder(s, f)
	var table: Dictionary = FightGrid.cfg(data).get("slow_fall", {})
	for fid: String in table:
		if not fid.begins_with("_") and FeatureRules.has(me, fid):
			out.append({"act": id, "to": "", "how": {"ctx": ctx, "cut": int(table[fid]) * FeatureRules.level(me)}, "worth": 1.0})
	for sid: String in SpellRules.ready(me):
		var chk := SpellRules.check(me, data, sid, 0)
		if str(SpellEffects.spec(data, sid).get("reaction", "")) == "fall" and not chk.has("reason"):
			out.append({"act": id, "to": "", "how": {"ctx": ctx, "cut": int(ctx["dmg"]), "spell": sid, "slot": int(chk["slot"])}, "worth": 2.0})
	return out


func run(s: GameSession, data: Dictionary, f: Dictionary, _to: String, how: Dictionary) -> Array[String]:
	how["ctx"]["cut"] = int(how["cut"])
	var me := Sheet.holder(s, f)
	if how.has("spell"):
		var lines := SpellRules.cast(me, data, str(how["spell"]), int(how["slot"]), s)
		lines.append("%s опускается плавно, как пёрышко" % me.get("name", ""))
		return lines
	return ["%s замедляет падение: −%d" % [me.get("name", ""), int(how["cut"])]]
