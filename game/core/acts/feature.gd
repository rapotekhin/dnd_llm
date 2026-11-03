extends Act
## A class feature or a race trait of anybody who has it (v0.8.4.9, ADR-0016): `how.id` — a row of `rules.feature_actions`, `how.stock`
## — a use of `rules.resources`, `how.answer` — a reaction to a blow. The buttons are the features tab's own; what the AI makes of it
## is `rules.combat.ai.features`.


func title() -> String:
	return "Умение"


func tab() -> String:
	return ""


func shown(_s: GameSession, _data: Dictionary, _f: Dictionary) -> bool:
	return false


func cost(_s: GameSession, data: Dictionary, _f: Dictionary, how: Dictionary) -> String:
	if how.has("answer"):
		return "reaction"
	if how.has("stock"):
		return str(Stock.table(data).get(str(how["stock"]), {}).get("combat_cost", "action"))
	return FeatureRules.price(data, str(how.get("id", "")))


func why(s: GameSession, data: Dictionary, f: Dictionary, to: String, how: Dictionary) -> String:
	if how.has("stock"):
		return FeatureRules.why_stock(s, data, f, str(how["stock"]))
	return FeatureRules.why(s, data, f, str(how.get("id", "")), to)


func run(s: GameSession, data: Dictionary, f: Dictionary, to: String, how: Dictionary) -> Array[String]:
	if how.has("answer"):
		var lines: Array[String] = []
		FeatureRules.apply_reaction(s, data, f, CombatRules.fighter(s, to), str(how["answer"]), how["ctx"], lines)
		return lines
	if how.has("stock"):
		return FeatureRules.use_stock(s, data, f, str(how["stock"]))
	return FeatureRules.run(s, data, f, str(how.get("id", "")), to)


func reacts(s: GameSession, data: Dictionary, f: Dictionary, moment: String, ctx: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if moment != "hurt":
		return out
	var foe := CombatRules.fighter(s, str(ctx["foe"]))
	var b: Dictionary = ctx["blow"]
	for r: Dictionary in FeatureRules.reactions(s, data, f, foe, b.get("act", {}), Attack.shot(foe, f, b) and bool(b.get("weapon", false)), int(ctx["dmg"]), ctx):
		out.append({"act": id, "to": str(foe["id"]), "how": {"answer": str(r["id"]), "ctx": ctx}, "worth": 1.0})
	return out


func spare(s: GameSession, data: Dictionary, f: Dictionary, moment: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if Sheet.is_hero(f):
		return out
	var table: Dictionary = FightAI.cfg(data)["features"]
	for a: Dictionary in FeatureRules.actions(s, data, f):
		var w: Dictionary = table.get(str(a["id"]), {})
		if str(w.get("when", "")) == moment and _fits(s, data, f, w):
			out.append({"to": _beside(s, f) if bool(a["target"]) else "", "how": {"id": str(a["id"])}})
	for stock: String in FeatureRules.stocks(s, data, f):
		var w: Dictionary = table.get(stock, {})
		if str(w.get("when", "")) == moment and _fits(s, data, f, w):
			out.append({"to": "", "how": {"stock": stock}})
	return out


func offers(s: GameSession, data: Dictionary, f: Dictionary, targets: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if Sheet.is_hero(f):
		return out
	var table: Dictionary = FightAI.cfg(data)["features"]
	for a: Dictionary in FeatureRules.actions(s, data, f):
		var at := str(a["id"])
		var w: Dictionary = table.get(at, {})
		if not w.has("power") or not _fits(s, data, f, w) or not FeatureRules.payable(s, data, f, at).is_empty():
			continue
		var base := {"act": id, "how": {"id": at}, "kind": "feature", "power": float(w["power"])}
		if not bool(a["target"]):
			out.append(base.merged({"to": str(f["id"]), "t": f, "far": 0, "self": true}))
			continue
		var area := FeatureRules.aims(data, at)
		var far := FightGrid.squares_of(data, FeatureRules.aim_ft(s, data, f, at)) if area else 1
		for t: Dictionary in targets:
			out.append(base.merged({"to": str(t["id"]), "t": t, "far": far, "touch": not area}))
	return out


## Worth it now: wounded enough, the foes it is for are near.
func _fits(s: GameSession, data: Dictionary, f: Dictionary, w: Dictionary) -> bool:
	if w.has("below") and float(f.get("hp", 0)) >= float(w["below"]) * float(f.get("max_hp", 1)):
		return false
	if not w.has("foes"):
		return true
	for one: String in CombatRules.foes_of(s, f):
		var t := CombatRules.fighter(s, one)
		if (w["foes"] as Array).has(str(Sheet.template(data, t).get("type", ""))) and FightGrid.feet(data, t, f) <= 30:
			return true
	return false


## The foe beside it, "" — none.
func _beside(s: GameSession, f: Dictionary) -> String:
	for one: String in CombatRules.foes_of(s, f):
		if FightGrid.touching(f, CombatRules.fighter(s, one)) and Attack.up(s, CombatRules.fighter(s, one)):
			return one
	return ""
