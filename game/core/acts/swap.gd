extends Act
## The other weapon set to the hands, for nothing, as in BG3. Out of a fight too: the sheet has the same button.


func title() -> String:
	return "Сменить оружие"


func tab() -> String:
	return ""


func cost(_s: GameSession, _data: Dictionary, _f: Dictionary, _how: Dictionary) -> String:
	return "free"


func shown(_s: GameSession, _data: Dictionary, f: Dictionary) -> bool:
	return Sheet.is_hero(f)


func can(s: GameSession, data: Dictionary, f: Dictionary, to: String = "", how: Dictionary = {}) -> String:
	if CombatRules.active(s) and not CombatRules.player_can_act(s):
		return "COMBAT_NOT_YOUR_TURN"
	return why(s, data, f, to, how)


func why(s: GameSession, data: Dictionary, _f: Dictionary, _to: String, _how: Dictionary) -> String:
	if Guise.has_body(s.character):
		return "COMBAT_WILD_SHAPE"
	return CharacterRules.swap_why(s.character, data, s.items)


func go(s: GameSession, data: Dictionary, f: Dictionary, to: String = "", how: Dictionary = {}) -> Array[String]:
	return run(s, data, f, to, how)


func run(s: GameSession, data: Dictionary, _f: Dictionary, _to: String, _how: Dictionary) -> Array[String]:
	CharacterRules.swap_hands(s.character)
	CharacterRules.refresh(s.character, data, s.items)
	if not CombatRules.active(s):
		return []
	var w := str(s.character["equipped"].get("main_hand", ""))
	return ["%s берёт в руки: %s" % [s.character.get("name", ""), ItemRules.display_name(data["items"], s.items, w) if not w.is_empty() else "щит"]]
