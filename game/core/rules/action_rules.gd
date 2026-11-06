class_name ActionRules
extends RefCounted
## One action (v0.7.64, ADR-0012): what it costs, at whom, what it does. A spell of the SRD, a spell or an ability the
## master built of parts (MakeRules), a scroll and a wand all go through `run`: the hero pays, then the spell's way lands.
## The way comes from the tables of the rules, so a built spell reads like an SRD one: its own row in `spells`, and
## `combat.condition_spells`, `combat.riders`, `spell_effects`, `combat.spell_targets` for what it lays.
## The special spells of 5e keep their hooks; this is one road to them, for anyone (ADR-0016): the caster stands in
## `s.combat.by` while the spell lands, its numbers with it, and the rules read `CombatRules.caster`.


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


## The spell lands (its cost is paid) and, twinned, on a second creature. Lines into `lines`.
static func run(s: GameSession, data: Dictionary, id: String, slot: int, target_id: String, lines: Array[String]) -> void:
	land(s, data, id, slot, target_id, lines)
	if str(s.combat.get("meta_now", "")) == "twinned_spell":
		twin(s, data, id, slot, target_id, lines)


## Twinned Spell (v0.8.4.33): the same spell at a second creature of the first one's side, in range. The hero picks it as a
## chosen target (a volley with `side`), one who is not the hero takes the nearest at once.
static func twin(s: GameSession, data: Dictionary, id: String, slot: int, first: String, lines: Array[String]) -> void:
	var me := CombatRules.caster(s)
	var mine := str(me["id"])
	var on := mine if first.is_empty() or first == CombatRules.PLAYER and Sheet.is_hero(me) else first
	var side := "foe" if CombatRules.foes_of(s, me).has(on) else "friend"
	lines.append("Удвоенное заклинание: вторая цель")
	if Sheet.is_hero(me):
		s.combat["volley"] = {"spell": id, "slot": slot, "left": 1, "last": on, "picks": [on], "side": side, "by": s.combat.get("by", {}).duplicate()}
		if not CombatRules._can_pick_more(s, data):
			s.combat.erase("volley")
			lines.append("…но второй цели в пределах дистанции нет")
		return
	var ids: Array[String] = CombatRules.foes_of(s, me) if side == "foe" else CombatRules.friends_of(s, me)
	if side == "friend":
		ids.append(mine)
	ids.sort_custom(func(a: String, b: String) -> bool: return FightGrid.dist(me, CombatRules.fighter(s, a)) < FightGrid.dist(me, CombatRules.fighter(s, b)))
	for to: String in ids:
		var t := CombatRules.fighter(s, to)
		if to == on or not Attack.up(s, t) or FightGrid.dist(me, t) > CombatRules._spell_squares(s, data, id, me) or CombatRules._no_line(s, data, me, t):
			continue
		land(s, data, id, slot, to, lines)
		return


## The spell lands on one target: chosen targets first, then its way. Lines into `lines`.
static func land(s: GameSession, data: Dictionary, id: String, slot: int, target_id: String, lines: Array[String]) -> void:
	var me := CombatRules.caster(s)
	var hero := Sheet.is_hero(me)
	var chosen := not SpellEffects.picks(data, id).is_empty()
	if chosen:  # v0.7.50.1: the first target; the others picked as darts, by the hero's clicks or by the caster at once
		if hero:
			CombatRules._start_picks(s, data, id, slot, target_id)
		if SpellEffects.picks_side(data, id) == "any" and CombatRules.foes_of(s, me).has(target_id):
			SpellEffects.reduce_foe(s, data, id, CombatRules.fighter(s, target_id), lines)
			return
		if SpellEffects.picks_side(data, id) != "foe":
			if not target_id in ["", str(me["id"])]:
				if hero and (data["rules"]["invisibility"]["spells"] as Dictionary).has(id):
					s.character["invisible_others"] = true  # the concentration holds an ally's, not the hero's
				SpellEffects.on_friend(s, data, id, slot, CombatRules.fighter(s, target_id), lines)
				if not hero:
					more_picks(s, data, id, slot, target_id, lines)
				return
			if not hero:
				more_picks(s, data, id, slot, str(me["id"]), lines)
			target_id = ""
	var t := CombatRules.aimed(s, target_id) if not target_id.is_empty() else {}
	match way(data, id, not target_id.is_empty()):
		"summon":  # v0.7.22.22: the summoned fight on the hero's side, or on the side of one who is not the hero
			lines.append_array(AllyRules.summon_by(s, data, me, id))
		"condition":
			CombatRules._cast_condition(s, data, id, slot, t, lines)
		"dispel":  # Dispel Magic (v0.7.13.7)
			lines.append_array(SpellEffects.dispel(s, data, target_id))
		"curse":  # v0.7.13.6: Faerie Fire, Slow…
			SpellEffects.cast_curse(s, data, id, slot, t, lines)
		"sustained":  # v0.7.13.5: zones and strikes each turn
			SpellEffects.start_sustained(s, data, id, slot, target_id, lines)
		"mark":  # Hunter's Mark (v0.7.13.4)
			if hero:
				lines.append_array(SpellEffects.apply_self(s, data, id, slot))
			else:
				SpellEffects.on_friend(s, data, id, slot, me, lines)
			if not target_id.is_empty():
				SpellEffects.mark(Sheet.holder(s, me), target_id)
				lines.append("%s отмечен" % t["name"])
		"teleport":  # Misty Step (v0.7.13.3)
			var to := FightGrid.aim_of(target_id) if FightGrid.is_aim(target_id) else FightGrid.NONE
			lines.append_array(CombatRules._teleport(s, data, int(SpellEffects.spec(data, id)["teleport"]), to))
		"bane":  # Bane (v0.7.13.1)
			SpellEffects.curse_foes(s, data, id, slot, t, lines)
		"heal":
			CombatRules.heal(s, data, id, slot, me if t.is_empty() else t, lines)
		"damage":
			CombatRules._spell_damage(s, data, id, slot, target_id, lines)
	if chosen and not hero and SpellEffects.picks_side(data, id) == "foe":
		more_picks(s, data, id, slot, target_id, lines)


## The caster who is not the hero picks the other targets of a spell at once: the nearest it can reach, each one once.
static func more_picks(s: GameSession, data: Dictionary, id: String, slot: int, first: String, lines: Array[String]) -> void:
	var me := CombatRules.caster(s)
	var left := SpellEffects.picks_count(data, id, slot) - 1
	var picks: Array = [first]
	var v := {"spell": id, "slot": slot, "left": left, "last": first, "picks": picks}
	var near := bool(SpellEffects.picks(data, id).get("near", false))
	var ids: Array[String] = CombatRules.foes_of(s, me) if SpellEffects.picks_side(data, id) == "foe" else CombatRules.friends_of(s, me)
	ids.sort_custom(func(a: String, b: String) -> bool: return FightGrid.dist(me, CombatRules.fighter(s, a)) < FightGrid.dist(me, CombatRules.fighter(s, b)))
	for to: String in ids:
		var t := CombatRules.fighter(s, to)
		if left <= 0 or str(s.combat.get("outcome", "")) != "":
			break
		if picks.has(to) or FightGrid.dist(me, t) > CombatRules._spell_squares(s, data, id, me) or CombatRules._no_line(s, data, me, t):
			continue
		if near and not FightGrid.touching(t, CombatRules.fighter(s, first)):
			continue
		CombatRules._pick_shot(s, data, v, to, lines)
		left -= 1


## What a spell lays on a hit or a failed save (rules.combat.riders): a status for rounds, a mark held on the fighter, a
## value set, a push by columns. A row may ask a creature type or a size; `hook` — what stays code.
static func riders(s: GameSession, data: Dictionary, id: String, slot: int, t: Dictionary, landed: bool, lines: Array[String]) -> void:
	if str(t.get("status")) != "active":
		return
	var by := str(CombatRules.caster(s)["id"])
	for r: Dictionary in CombatRules.cfg(data)["riders"].get(id, []):
		if str(r.get("hook", "")) == "acid":
			CombatRules._acid_rider(s, data, slot, t, landed, lines)
			continue
		var m: Dictionary = Sheet.template(data, t)
		if not landed or (r.has("if_type") and str(m.get("type", "")) != str(r["if_type"])):
			continue
		if r.has("max_size") and CombatRules.SIZES.find(Sheet.size(s, data, t)) > int(r["max_size"]):
			continue
		if r.has("status"):
			lines.append_array(CombatRules._add_condition(s, data, t, str(r["status"]), {"rounds": int(r.get("rounds", 1)), "spell": id}))
		if r.has("hold") or r.has("wear"):  # a status until the start of the caster's next turn (`ends.turn`, v0.8.4.27.2)
			var me := Sheet.holder(s, t)
			ConditionRules.add_effect(me, (r.get("wear", {}) as Dictionary).merged({"condition": str(r.get("hold", "")), "by": by,
				"ends": {"turn": by}, "source": {"kind": "spell", "id": id, "name": str(data["spells"].get(id, {}).get("name", id))}}))
			if Sheet.is_hero(t):
				CharacterRules.refresh(me, data, s.items)
		for k: String in r.get("set", {}):  # the fighter's own state: a reaction spent
			t[k] = r["set"][k]
		if r.has("push"):
			CombatRules.push_away(s, data, t, int(r["push"]))
		if r.has("line"):
			lines.append(str(r["line"]) % t["name"])


## The numbers of an action not paid by one's own magic: {dc, attack, ability}. An ability the master built works for
## anyone: 8 + proficiency + its ability.
static func numbers(s: GameSession, data: Dictionary, id: String, f: Dictionary = Sheet.HERO) -> Dictionary:
	var ab := str(data["spells"].get(id, {}).get("ability", ""))
	if ab.is_empty():
		return {}
	return {"dc": Sheet.dc(s, data, f, ab), "attack": Sheet.prof(s, data, f) + Sheet.ability_mod(s, data, f, ab), "ability": ab}


## `fn` read with `f` casting `id` by `by` (a thing's numbers) as the cast lands, and the scope taken back (v0.8.4.29.6: the window
## of a scroll shows the chance of its own DC and attack).
static func as_by(s: GameSession, data: Dictionary, f: Dictionary, id: String, by: Dictionary, fn: Callable) -> Variant:
	var had: Variant = s.combat.get("by")
	s.combat["by"] = scope(s, data, f, id, by)
	var out: Variant = fn.call()
	if had == null:
		s.combat.erase("by")
	else:
		s.combat["by"] = had
	return out


## What `f` casts with: its numbers by the template, the thing's in `by`, and it named.
static func scope(s: GameSession, data: Dictionary, f: Dictionary, id: String, by: Dictionary = {}) -> Dictionary:
	var out := by.duplicate() if not by.is_empty() else numbers(s, data, id, f)
	if not Sheet.is_hero(f):
		var sc: Dictionary = Sheet.template(data, f).get("spellcasting", {})
		if out.is_empty():
			out = {"dc": int(sc.get("dc", 10)), "attack": int(sc.get("attack", 0)), "ability": str(sc.get("ability", "wis"))}
		out["level"] = MonsterRules._caster_level(data, f)
	out["caster"] = str(f["id"])
	return out


## `f` casts (the points are paid): the slot or the thing's numbers, its concentration, the spell lands. Lines.
static func cast(s: GameSession, data: Dictionary, f: Dictionary, id: String, slot: int, to: String, by: Dictionary = {}) -> Array[String]:
	s.combat["by"] = scope(s, data, f, id, by)
	AnimRules.cast(s, data, f, id, to)  # v0.8.4.23: the delivery, before what it does
	var lines: Array[String] = []
	if Sheet.is_hero(f):
		var c := s.character
		var chk := {"spell_id": id, "slot": slot} if not by.is_empty() else SpellRules.check(c, data, id, slot)
		s.combat["meta_now"] = FeatureRules.pay_metamagic(s, data, Sheet.HERO, id, int(chk.get("slot", slot)))
		var held := str(c.get("concentration", ""))
		lines = SpellRules.cast(c, data, chk["spell_id"], int(chk["slot"]), s, to in ["", CombatRules.PLAYER], not by.is_empty())
		slot = int(chk["slot"])
		if held != str(c.get("concentration", "")):
			lines.append_array(CombatRules.end_spell(s, data, held))
		if countered(s, data, f, id, slot, lines):
			if str(c.get("concentration", "")) == id:
				c["concentration"] = ""
		else:
			run(s, data, id, slot, to, lines)
	else:
		s.combat["meta_now"] = FeatureRules.pay_metamagic(s, data, f, id, slot)
		lines = _by_other(s, data, f, id, slot, to)
	s.combat.erase("by")
	return lines


## One who is not the hero casts: the concentration it moves on from, what lies on itself, what lands. Lines.
static func _by_other(s: GameSession, data: Dictionary, f: Dictionary, id: String, slot: int, to: String) -> Array[String]:
	var sp: Dictionary = data["spells"][id]
	var mine := str(f["id"])
	var lines: Array[String] = ["%s колдует «%s»" % [f["name"], sp["name"]]]
	if countered(s, data, f, id, slot, lines):
		return lines
	if not (data["rules"]["invisibility"]["spells"] as Dictionary).has(id):
		lines.append_array(ConditionRules.end_invisibility_on_attack(f, data))
	var held := str(f.get("concentration", ""))
	if bool(sp.get("concentration", false)):
		if not held.is_empty():
			lines.append_array(CombatRules.end_spell(s, data, held, mine))
		f["concentration"] = id
	f["last_spell"] = id
	var on_self := to in ["", mine]
	if on_self and (SpellEffects.self_spell(data, id) or (data["rules"]["invisibility"]["spells"] as Dictionary).has(id)):
		SpellEffects.on_friend(s, data, id, slot, f, lines)
	run(s, data, id, slot, to, lines)
	if bool(sp.get("concentration", false)) and not _holds(s, id, mine):
		f.erase("concentration")  # nothing took: it has nothing to keep up
	return lines


## Its foes answer the spell with Counterspell (the hero's is in the cast's window). True when it does not land.
static func countered(s: GameSession, data: Dictionary, f: Dictionary, id: String, slot: int, lines: Array[String]) -> bool:
	var ctx := {"foe": str(f["id"]), "spell": id, "circle": maxi(int(data["spells"][id]["level"]), slot), "stopped": false}
	for o: String in CombatRules.foes_of(s, f):
		if Acts.react(s, data, CombatRules.fighter(s, o), "spell", ctx, lines) and bool(ctx["stopped"]):
			return true
	return false


## Something of the spell of `by` is still in the fight: a status, a zone, a creature.
static func _holds(s: GameSession, id: String, by: String) -> bool:
	if SpellEffects.zones(s).any(func(z: Dictionary) -> bool: return str(z["spell"]) == id and str(z.get("by", "")) == by):
		return true
	for o: String in s.combat["order"]:
		var x := CombatRules.fighter(s, o)
		if str(x.get("spell", "")) == id and str(x.get("called_by", "")) == by and str(x.get("status")) == "active":
			return true
		for e: Dictionary in ConditionRules.effects(Sheet.holder(s, x)):
			if str(e.get("source", {}).get("id", "")) == id and str(e.get("by", "")) == by:
				return true
	return false
