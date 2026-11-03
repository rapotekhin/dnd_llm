extends Act
## Slow Fall (v0.8.4.26.1): a reaction to a fall takes off the damage by the level, `rules.combat.grid.slow_fall` (a feature →
## per level). Anybody's; the hero's goes by itself (Acts.react, moment `fall`). `how.ctx` — the fall's {dmg, cut}.


func title() -> String:
	return "Медленное падение"


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
	return out


func run(s: GameSession, _data: Dictionary, f: Dictionary, _to: String, how: Dictionary) -> Array[String]:
	how["ctx"]["cut"] = int(how["cut"])
	return ["%s замедляет падение: −%d" % [Sheet.holder(s, f).get("name", ""), int(how["cut"])]]
