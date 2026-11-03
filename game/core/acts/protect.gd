extends Act
## Fighting Style: Protection (v0.8.4.26.1): a fighter with the style and a shield in hand imposes disadvantage on an attack
## it sees at a friend within 5 ft of it. A reaction of anybody; the hero's goes by itself unless reactions are «never»
## (Acts.react, moment `attacked`).


func title() -> String:
	return "Защита союзника"


func tab() -> String:
	return ""


func cost(_s: GameSession, _data: Dictionary, _f: Dictionary, _how: Dictionary) -> String:
	return "reaction"


func shown(_s: GameSession, _data: Dictionary, _f: Dictionary) -> bool:
	return false


func reacts(s: GameSession, data: Dictionary, f: Dictionary, when: String, ctx: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if when != "attacked" or str(ctx["target"]) == str(f["id"]):
		return out
	var me := Sheet.holder(s, f)
	var foe := CombatRules.fighter(s, str(ctx["foe"]))
	var t := CombatRules.fighter(s, str(ctx["target"]))
	if not CharacterRules.style(me, "protection") or CharacterRules.item_def(me, data, s.items, "shield").is_empty() \
			or not CombatRules.friends_of(s, f).has(str(t["id"])) or FightGrid.feet(data, f, t) > 5 or not FightGrid.sees(s, data, f, foe):
		return out
	out.append({"act": id, "to": str(ctx["target"]), "how": {}, "worth": 1.5})
	return out


func run(s: GameSession, _data: Dictionary, f: Dictionary, to: String, _how: Dictionary) -> Array[String]:
	return ["%s прикрывает щитом %s: атака с помехой" % [Sheet.holder(s, f).get("name", ""), Sheet.holder(s, CombatRules.fighter(s, to)).get("name", "")]]
