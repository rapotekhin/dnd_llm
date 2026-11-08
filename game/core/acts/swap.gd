extends Act
## The other weapon set to the hands, for nothing, as in BG3 — anybody's (v0.8.4.40: a foe with a bow put away takes it up
## to shoot, the act «Атака» does it on the way). Out of a fight too: the sheet has the same button.


func title() -> String:
	return "Сменить оружие"


func tab() -> String:
	return ""


func cost(_s: GameSession, _data: Dictionary, _f: Dictionary, _how: Dictionary) -> String:
	return "free"


func shown(s: GameSession, data: Dictionary, f: Dictionary) -> bool:
	return Sheet.is_hero(f) or not CharacterRules.hands_kind(CharacterRules.stowed(Gear.of(s, data, _id(f))), data, s.items).is_empty()


func can(s: GameSession, data: Dictionary, f: Dictionary, to: String = "", how: Dictionary = {}) -> String:
	if Sheet.is_hero(f) and CombatRules.active(s) and not CombatRules.player_can_act(s):
		return "COMBAT_NOT_YOUR_TURN"
	return why(s, data, f, to, how)


func why(s: GameSession, data: Dictionary, f: Dictionary, _to: String, _how: Dictionary) -> String:
	return Equip.swap_why(s, data, _id(f))


## Whose: a fighter's id, the hero for its sheet.
static func _id(f: Dictionary) -> String:
	return str(f["id"]) if f.has("id") else Being.HERO


func go(s: GameSession, data: Dictionary, f: Dictionary, to: String = "", how: Dictionary = {}) -> Array[String]:
	return run(s, data, f, to, how)


func run(s: GameSession, data: Dictionary, f: Dictionary, _to: String, _how: Dictionary) -> Array[String]:
	var id := _id(f)
	Equip.swap(s, data, id)
	if not CombatRules.active(s):
		return []
	var c := Gear.of(s, data, id)
	var w := str(c.get("equipped", {}).get("main_hand", ""))
	return ["%s берёт в руки: %s" % [Sheet.holder(s, f).get("name", c.get("name", "")), ItemRules.display_name(data["items"], s.items, w) if not w.is_empty() else "щит"]]
