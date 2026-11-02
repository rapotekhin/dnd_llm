extends Act
## A blow: of the hand of one with hands (`how.hand`: main, off, fists, stowed, frenzy), or an action of an SRD template
## (`how.action`). What is struck with comes from `Attack.way`, the rest is one for anybody. A template's Multiattack is one
## Attack action. The buttons are the tab's own: they carry the weapon's numbers.


func title() -> String:
	return "Атака"


func tab() -> String:
	return ""


func aim() -> String:
	return FOE


func cost(_s: GameSession, _data: Dictionary, _f: Dictionary, how: Dictionary) -> String:
	return "bonus" if str(how.get("hand", "")) in ["off", "frenzy"] else "attack"


func why(s: GameSession, data: Dictionary, f: Dictionary, to: String, how: Dictionary) -> String:
	var hand := str(how.get("hand", ""))
	if hand == "off" and bool(CombatRules.cfg(data).get("offhand_needs_attack", true)) and not bool(CombatRules.points(s, data, f).get("attacked", false)):
		return "COMBAT_NO_BONUS"  # as in BG3 (v0.7.22.3): no main-hand attack needed first, unless the rules ask for it
	if hand == "frenzy" and not bool(f.get("frenzy", false)):
		return "COMBAT_NO_FRENZY"
	if hand == "stowed":
		var stop := Acts.one("swap").can(s, data, f)
		if not stop.is_empty():
			return stop
		return str(CombatRules.as_stowed(s, func() -> String: return why(s, data, f, to, {})))
	var t := _foe(s, f, to)
	if t.is_empty():
		return "COMBAT_BAD_TARGET"
	if CombatRules.charmed_by(s, f, t):
		return "COMBAT_CHARMED"
	var b := Attack.way(s, data, f, how)
	if b.is_empty():
		return "COMBAT_BAD_TARGET"
	if not str(b.get("ammo", "")).is_empty() and int(s.character.get("inventory", {}).get(str(b["ammo"]), 0)) <= 0:
		return "COMBAT_NO_AMMO"  # v0.7.12: arrows and bolts are spent
	if str((b.get("act", {}) as Dictionary).get("kind", "")) == "save":
		return ""
	var seen := CombatRules._as_seen(t)
	if FightGrid.cover(s, data, f, seen) >= FightGrid.FULL_COVER:
		return "COMBAT_NO_LINE"
	if bool(b["melee"]) and CombatRules.blade_reaches(s, data, f, seen, int(b.get("reach", 1))):
		return ""
	if (b.get("range", []) as Array).is_empty():
		return "COMBAT_OUT_OF_REACH"
	return "COMBAT_OUT_OF_RANGE" if FightGrid.shown_dist(f, t) * int(FightGrid.cfg(data)["ft"]) > int(b["range"][1]) else ""


func run(s: GameSession, data: Dictionary, f: Dictionary, to: String, how: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	if str(how.get("hand", "")) == "stowed":
		lines = Acts.one("swap").go(s, data, f)
		lines.append_array(run(s, data, f, to, {}))
		return lines
	var t := CombatRules.fighter(s, to)
	var b := Attack.way(s, data, f, how)
	CombatRules.points(s, data, f)["attacked"] = true
	if bool(b["melee"]) and Move.air(s, data, f):
		f["swooped"] = true  # Fly (v0.7.63): down at arm's length, in reach until its next turn
	if b.has("act") and str(how.get("hand", "")) != "frenzy":
		var a: Dictionary = b["act"]
		if str(a.get("kind")) == "save":
			Attack.breath(s, data, f, t, a, lines)
		else:
			Attack.full(s, data, f, t, a, lines)
		return lines
	s.combat["melee_strike"] = bool(b["melee"]) and CombatRules.blade_reaches(s, data, f, t, int(b.get("reach", 1)))  # nonlethal needs a melee blow (5e)
	Attack.swing(s, data, f, t, b, lines)
	s.combat.erase("melee_strike")
	CombatRules.spend_ammo(s, str(b.get("ammo", "")))
	return lines


## A frenzied one's blow as its bonus action, at the foe beside it.
func spare(s: GameSession, _data: Dictionary, f: Dictionary, moment: String) -> Array[Dictionary]:
	if moment == "last" and bool(f.get("frenzy", false)):
		for one: String in CombatRules.foes_of(s, f):
			if FightGrid.touching(f, CombatRules.fighter(s, one)) and Attack.up(s, CombatRules.fighter(s, one)):
				return [{"to": one, "how": {"hand": "frenzy"}}]
	return []


func offers(s: GameSession, data: Dictionary, f: Dictionary, targets: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if Sheet.is_hero(f):
		return out
	var control := float(FightAI.role(data, f)["control"])
	for t: Dictionary in targets:
		var to := str(t["id"])
		var melee := MonsterRules.pick(s, data, f, t, "melee")
		if not melee.is_empty():
			out.append({"act": id, "to": to, "how": {"action": str(melee["name_en"])}, "t": t, "kind": "melee", "blow": melee, "touch": true,
				"far": CombatRules.reach_of(data, f), "power": FightAI.avg(melee) * FightAI.blows(data, f, melee)})
		var ranged := MonsterRules.pick(s, data, f, t, "ranged")
		if not ranged.is_empty():
			out.append({"act": id, "to": to, "how": {"action": str(ranged["name_en"])}, "t": t, "kind": "ranged", "blow": ranged,
				"far": FightGrid.squares_of(data, int(ranged["range"][1])), "short": FightGrid.squares_of(data, int(ranged["range"][0])),
				"power": FightAI.avg(ranged) * FightAI.blows(data, f, ranged)})
		var special := MonsterRules.save_action(s, data, f, t, 0)
		if not special.is_empty():
			out.append({"act": id, "to": to, "how": {"action": str(special["name_en"])}, "t": t, "kind": "save", "blow": special,
				"far": FightGrid.squares_of(data, int(special.get("effect", {}).get("area", {}).get("ft", 5))), "power": FightAI.avg(special) + control})
	return out
