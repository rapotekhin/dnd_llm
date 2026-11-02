extends Act
## A thing thrown (`how.item`): a flask or a net at a foe, a flask on a square. An attack of the Attack action, of anybody who
## carries it (v0.8.4.10); the AI throws what does damage.


func title() -> String:
	return "Бросить"


func tab() -> String:
	return ""


func aim() -> String:
	return FOE


func cost(_s: GameSession, _data: Dictionary, _f: Dictionary, _how: Dictionary) -> String:
	return "attack"


func why(s: GameSession, data: Dictionary, f: Dictionary, to: String, how: Dictionary) -> String:
	var item := str(how.get("item", ""))
	var fx: Dictionary = ItemRules.consumable(data, item, s.items).get("throw", {})
	if fx.is_empty() or int(Sheet.holder(s, f).get("inventory", {}).get(item, 0)) <= 0:
		return "COMBAT_ITEM_CANT"
	var far := 60 if bool(fx.get("improvised", false)) else int(fx.get("range", 15))
	if FightGrid.is_aim(to):  # a flask on a square
		if not fx.has("oiled") and not fx.has("burning"):
			return "COMBAT_BAD_TARGET"
		var at := FightGrid.aim_of(to)
		if FightGrid.dist_to(f, at) * int(FightGrid.cfg(data)["ft"]) > far:
			return "COMBAT_OUT_OF_RANGE"
		return "" if FightGrid.clear(FightGrid.grid(s, data), FightGrid.cell(f), at) else "COMBAT_NO_LINE"
	var t := _foe(s, f, to)
	if t.is_empty():
		return "COMBAT_BAD_TARGET"
	if CombatRules._no_line(s, data, f, t):
		return "COMBAT_NO_LINE"
	return "COMBAT_OUT_OF_RANGE" if FightGrid.shown_dist(f, t) * int(FightGrid.cfg(data)["ft"]) > far else ""


func run(s: GameSession, data: Dictionary, f: Dictionary, to: String, how: Dictionary) -> Array[String]:
	return CombatRules.throw_item(s, data, f, str(how["item"]), to)


## A flask that burns or eats at a foe: worth its damage on one it works on.
func offers(s: GameSession, data: Dictionary, f: Dictionary, targets: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if Sheet.is_hero(f):
		return out
	for item: String in Sheet.holder(s, f).get("inventory", {}):
		var fx: Dictionary = ItemRules.consumable(data, item, s.items).get("throw", {})
		if not fx.has("damage"):
			continue
		var r := CombatRules.dice_range(str(fx["damage"][0]))
		var power := (r[0] + r[1]) / 2.0
		if fx.has("burning"):
			var b := CombatRules.dice_range(str(fx["burning"]))
			power += (b[0] + b[1]) / 2.0
		for t: Dictionary in targets:
			if not (fx.get("types", []) as Array).is_empty() and not (fx["types"] as Array).has(str(Sheet.template(data, t).get("type", ""))):
				continue
			out.append({"act": id, "to": str(t["id"]), "how": {"item": item}, "t": t, "kind": "throw", "power": power, "sight": true,
				"far": FightGrid.squares_of(data, int(fx.get("range", 20)))})
	return out
