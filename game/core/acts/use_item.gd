extends Act
## A thing used on oneself (`how.item`). A potion is a bonus action, as in BG3, when the rules say so; Fast Hands makes any a bonus.


func title() -> String:
	return "Использовать"


func tab() -> String:
	return ""


func shown(_s: GameSession, _data: Dictionary, f: Dictionary) -> bool:
	return Sheet.is_hero(f)


func cost(s: GameSession, data: Dictionary, f: Dictionary, how: Dictionary) -> String:
	var quick := FeatureRules.has(s.character, "fast_hands") or (ItemRules.is_potion(data, s.items, str(how.get("item", "")))
		and str(CombatRules.cfg(data).get("potion_cost", "action")) == "bonus")
	return "bonus" if quick and int(CombatRules.points(s, data, f).get("bonus", 0)) > 0 else "action"


func why(s: GameSession, data: Dictionary, _f: Dictionary, _to: String, how: Dictionary) -> String:
	return ItemRules.can_use(s.character, data, s.items, str(how.get("item", "")))


func run(s: GameSession, data: Dictionary, _f: Dictionary, _to: String, how: Dictionary) -> Array[String]:
	return ItemRules.use(s.character, data, s.items, str(how["item"]), s.rng, s)
