extends Act
## Parley: the action, a check of the skill `how.skill` against the parley DC, the outcome is the engine's. It is the player's
## way to end a fight by words: the roll, its card and the master's share are the game's, as for the master's own request_check.


func title() -> String:
	return "Переговоры"


func order() -> int:
	return 80


func shown(_s: GameSession, _data: Dictionary, f: Dictionary) -> bool:
	return Sheet.is_hero(f)


func buttons(s: GameSession, data: Dictionary, _f: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for skill: String in CombatRules.cfg(data)["parley"]["skills"]:
		out.append({"name": "Parley_" + skill, "text": TranslationServer.translate("COMBAT_PARLEY").format({"skill": TranslationServer.translate("SKILL_" + skill.to_upper())}), "how": {"skill": skill},
			"tip": "%s\n%s" % [TranslationServer.translate("COMBAT_PARLEY_TIP_" + skill.to_upper()),
				TranslationServer.translate("COMBAT_PARLEY_PROGRESS").format({"progress": CombatRules.parley_progress(s, data)})]})
	return out


func why(s: GameSession, data: Dictionary, _f: Dictionary, _to: String, how: Dictionary) -> String:
	return CombatRules.can_parley(s, data, str(how.get("skill", "")))


func check(how: Dictionary) -> Dictionary:
	return {"skill": str(how["skill"]), "dc_tier": "medium"}
