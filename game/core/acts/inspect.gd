extends Act
## Looking a foe over: a bonus action, a knowledge check by its kind; a success opens the kind's numbers for good. What a player
## learns: nobody else has a bestiary to fill.


func title() -> String:
	return "Осмотреть"


func tip() -> String:
	return "Бонусное действие: проверка знаний по виду врага (Природа, Религия, Магия, Проницательность). Успех открывает хиты, КД, атаки и сопротивления таких врагов насовсем"


func order() -> int:
	return 24


func aim() -> String:
	return FOE


func shown(_s: GameSession, _data: Dictionary, f: Dictionary) -> bool:
	return Sheet.is_hero(f)


func cost(_s: GameSession, _data: Dictionary, _f: Dictionary, _how: Dictionary) -> String:
	return "bonus"


func why(s: GameSession, _data: Dictionary, f: Dictionary, to: String, _how: Dictionary) -> String:
	var t := _foe(s, f, to)
	if t.is_empty():
		return "COMBAT_BAD_TARGET"
	return "COMBAT_ALREADY_KNOWN" if CombatRules.known(s, t) else ""


func run(s: GameSession, data: Dictionary, _f: Dictionary, to: String, _how: Dictionary) -> Array[String]:
	var t := CombatRules.fighter(s, to)
	var skill := CombatRules.lore_skill(data, t)
	var dc := CombatRules.lore_dc(data, t)
	var favored := FeatureRules.has(s.character, "favored_enemy_" + str(Sheet.template(data, t).get("type", "")))  # Favored Enemy (v0.7.10)
	var r := Roll.hero(s, data, {"what": "Присмотреться", "skill": skill, "dc": dc, "adv": favored})
	if bool(r["ok"]):
		Knows.add(s, Knows.MONSTER, str(t["monster"]))
	return ["%s присматривается: %s — %s %d против Сл %d — %s" % [s.character["name"], t["name"], TranslationServer.translate("SKILL_" + skill.to_upper()),
		int(r["total"]), dc, "теперь ясно, на что способны такие враги" if bool(r["ok"]) else "ничего толкового"]]
