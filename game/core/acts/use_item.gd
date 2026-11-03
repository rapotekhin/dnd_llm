extends Act
## A thing used on oneself (`how.item`), by anybody who carries it (v0.8.4.10). A potion is a bonus action, as in BG3, when the
## rules say so; Fast Hands makes any a bonus. The AI drinks a healing potion when hurt (`rules.combat.ai.items`).


func title() -> String:
	return "Использовать"


func tab() -> String:
	return ""


func cost(s: GameSession, data: Dictionary, f: Dictionary, how: Dictionary) -> String:
	var quick := FeatureRules.has(Sheet.holder(s, f), "fast_hands") or (ItemRules.is_potion(data, s.items, str(how.get("item", "")))
		and str(CombatRules.cfg(data).get("potion_cost", "action")) == "bonus")
	return "bonus" if quick and int(CombatRules.points(s, data, f).get("bonus", 0)) > 0 else "action"


func why(s: GameSession, data: Dictionary, f: Dictionary, _to: String, how: Dictionary) -> String:
	if int(ItemRules.consumable(data, str(how.get("item", "")), s.items).get("minutes", 0)) > 0:
		return "COMBAT_ITEM_CANT"  # work of a while (a disguise) is not for a fight
	return ItemRules.can_use(Sheet.holder(s, f), data, s.items, str(how.get("item", "")))


func run(s: GameSession, data: Dictionary, f: Dictionary, _to: String, how: Dictionary) -> Array[String]:
	var lines := ItemRules.use(Sheet.holder(s, f), data, s.items, str(how["item"]), s.rng, s, f)
	if not Sheet.is_hero(f) and not lines.is_empty():
		lines[0] = "%s — %s" % [f["name"], lines[0].to_lower()]
	return lines


## A healing thing before it does anything else, when it is hurt enough.
func spare(s: GameSession, data: Dictionary, f: Dictionary, moment: String) -> Array[Dictionary]:
	var w: Dictionary = FightAI.cfg(data)["items"]
	if Sheet.is_hero(f) or moment != str(w["when"]) or float(f.get("hp", 0)) >= float(w["heal_below"]) * float(f.get("max_hp", 1)):
		return []
	var me := Sheet.holder(s, f)
	for item: String in ItemRules.at_hand(me, data, s.items):
		if ItemRules.consumable(data, item, s.items).has("heal") and ItemRules.can_use(me, data, s.items, item).is_empty():
			return [{"to": "", "how": {"item": item}}]
	return []
