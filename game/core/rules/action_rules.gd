class_name ActionRules
extends RefCounted
## One action (v0.7.64, ADR-0012): what it costs, at whom, what it does. A spell of the SRD, a spell or an ability the
## master built of parts (MakeRules), a scroll and a wand all go through `run`: the hero pays, then the spell's way lands.
## The way comes from the tables of the rules, so a built spell reads like an SRD one: its own row in `spells`, and
## `combat.condition_spells`, `combat.riders`, `spell_effects`, `combat.spell_targets` for what it lays.
## The special spells of 5e keep their hooks; this is one road to them. A monster's spell at the hero is still
## MonsterRules._cast: it rolls against the hero, and no monster has a built spell yet.


## The way of a spell at a target: the first that fits. "" — the spell does nothing in a fight by itself.
static func way(data: Dictionary, id: String, aimed: bool) -> String:
	var fx := SpellEffects.spec(data, id)
	if not AllyRules.summon_spec(data, id).is_empty():
		return "summon"
	if CombatRules.cfg(data)["condition_spells"].has(id) and aimed:
		return "condition"
	if bool(fx.get("dispel", false)):
		return "dispel"
	if not SpellEffects.curse(data, id).is_empty() and aimed:
		return "curse"
	if not SpellEffects.sustained(data, id).is_empty():
		return "sustained"
	if bool(fx.get("foe_target", false)):
		return "mark"
	if int(fx.get("teleport", 0)) > 0:
		return "teleport"
	if SpellEffects.foe_spell(data, id) and aimed:
		return "bane"
	if data["spells"][id].has("heal_at_slot"):
		return "heal"
	return "damage" if CombatRules.is_engine_spell(data, id) and aimed else ""


## The spell lands (its cost is paid): chosen targets first, then its way. Lines into `lines`.
static func run(s: GameSession, data: Dictionary, id: String, slot: int, target_id: String, lines: Array[String]) -> void:
	if not SpellEffects.picks(data, id).is_empty():  # v0.7.50.1: the first target; the others picked as darts
		CombatRules._start_picks(s, data, id, slot, target_id)
		if SpellEffects.picks_side(data, id) == "any" and str(CombatRules.fighter(s, target_id).get("side")) == "enemy":
			SpellEffects.reduce_foe(s, data, id, CombatRules.fighter(s, target_id), lines)
			return
		if SpellEffects.picks_side(data, id) != "foe":
			if not target_id in ["", CombatRules.PLAYER]:
				if (data["rules"]["invisibility"]["spells"] as Dictionary).has(id):
					s.character["invisible_others"] = true  # the concentration holds an ally's, not the hero's
				SpellEffects.on_friend(s, data, id, slot, CombatRules.fighter(s, target_id), lines)
				return
			target_id = ""
	var t := CombatRules.aimed(s, target_id) if not target_id.is_empty() else {}
	match way(data, id, not target_id.is_empty()):
		"summon":  # v0.7.22.22: the summoned fight on the hero's side
			lines.append_array(AllyRules.summon(s, data, id))
		"condition":
			CombatRules._cast_condition(s, data, id, slot, t, lines)
		"dispel":  # Dispel Magic (v0.7.13.7)
			lines.append_array(SpellEffects.dispel(s, data, target_id))
		"curse":  # v0.7.13.6: Faerie Fire, Slow…
			SpellEffects.cast_curse(s, data, id, slot, t, lines)
		"sustained":  # v0.7.13.5: zones and strikes each turn
			SpellEffects.start_sustained(s, data, id, slot, target_id, lines)
		"mark":  # Hunter's Mark (v0.7.13.4)
			lines.append_array(SpellEffects.apply_self(s, data, id, slot))
			if not target_id.is_empty():
				SpellEffects.mark(s.character, target_id)
				lines.append("%s отмечен" % t["name"])
		"teleport":  # Misty Step (v0.7.13.3)
			var to := FightGrid.aim_of(target_id) if FightGrid.is_aim(target_id) else FightGrid.NONE
			lines.append_array(CombatRules._teleport(s, data, int(SpellEffects.spec(data, id)["teleport"]), to))
		"bane":  # Bane (v0.7.13.1)
			SpellEffects.curse_foes(s, data, id, slot, t, lines)
		"heal":
			CombatRules._heal_hero(s, data, id, slot, lines)
		"damage":
			CombatRules._spell_damage(s, data, id, slot, target_id, lines)


## What a spell lays on a hit or a failed save (rules.combat.riders): a status for rounds, a mark held on the fighter, a
## value set, a push by columns. A row may ask a creature type or a size; `hook` — what stays code.
static func riders(s: GameSession, data: Dictionary, id: String, slot: int, t: Dictionary, landed: bool, lines: Array[String]) -> void:
	if str(t.get("status")) != "active":
		return
	for r: Dictionary in CombatRules.cfg(data)["riders"].get(id, []):
		if str(r.get("hook", "")) == "acid":
			CombatRules._acid_rider(s, data, slot, t, landed, lines)
			continue
		var m: Dictionary = CombatRules._monster(data, t)
		if not landed or (r.has("if_type") and str(m.get("type", "")) != str(r["if_type"])):
			continue
		if r.has("max_size") and CombatRules.SIZES.find(str(m.get("size", "medium"))) > int(r["max_size"]):
			continue
		if r.has("status"):
			CombatRules._add_condition(s, t, str(r["status"]), {"rounds": int(r.get("rounds", 1)), "spell": id})
		if r.has("hold"):
			CombatRules._hold(t, str(r["hold"]))
		for k: String in r.get("set", {}):
			t[k] = r["set"][k]
		if r.has("push"):
			CombatRules.push_away(s, data, t, int(r["push"]))
		if r.has("line"):
			lines.append(str(r["line"]) % t["name"])


## The numbers of an action not paid by the hero's own magic: {dc, attack, ability}. An ability the master built works
## for anyone: 8 + proficiency + its ability.
static func numbers(s: GameSession, data: Dictionary, id: String) -> Dictionary:
	var ab := str(data["spells"].get(id, {}).get("ability", ""))
	if ab.is_empty():
		return {}
	var c := s.character
	var m := CharacterRules.mod(CharacterRules.ability(c, ab))
	var prof := CharacterRules.prof_bonus(c, data)
	return {"dc": 8 + prof + m, "attack": prof + m, "ability": ab}
