extends Act
## A spell of anyone (ADR-0016): the hero's from its sheet, a foe's or an ally's from its template. `how`: `spell`, `slot`
## and, for one who is not the hero, what `MonsterRules.castable` said it spends. What the AI weighs is `rules.combat.ai.spells`,
## in the units of a blow's damage.


func title() -> String:
	return "Заклинание"


func tab() -> String:
	return ""


func cost(s: GameSession, data: Dictionary, f: Dictionary, how: Dictionary) -> String:
	if FeatureRules.active_metamagic(s, data, f) == "quickened_spell":
		return "bonus"
	return CombatRules.spell_cost(data, str(how.get("spell", "")))


func shown(_s: GameSession, data: Dictionary, f: Dictionary) -> bool:
	return Sheet.is_hero(f) or not MonsterRules.castable(data, f).is_empty()


func why(s: GameSession, data: Dictionary, f: Dictionary, to: String, how: Dictionary) -> String:
	var spell := str(how.get("spell", ""))
	if not Sheet.is_hero(f):
		if not MonsterRules.castable(data, f).any(func(o: Dictionary) -> bool: return str(o["id"]) == spell):
			return "COMBAT_NO_FEATURE"
	elif Guise.has_body(s.character):
		return "COMBAT_WILD_SHAPE"
	else:
		var chk := SpellRules.check(s.character, data, spell, int(how.get("slot", 0)))
		if chk.has("reason"):
			return str(chk["reason"])
	return target_why(s, data, f, to, spell)


## Whether the spell goes at `to` now, whatever gives it — a slot, a template, a scroll or a wand.
func target_why(s: GameSession, data: Dictionary, f: Dictionary, to: String, spell: String) -> String:
	var sp: Dictionary = data["spells"][spell]
	if SpellRules.long_cast(sp):
		return "COMBAT_SPELL_TOO_LONG"  # v0.7.13: minutes to cast — not in a fight (Prayer of Healing)
	if SpellEffects.spec(data, spell).has("reaction"):
		return "COMBAT_REACTION_SPELL"  # Shield, Counterspell: cast in the window of a foe's turn (v0.7.13.7)
	if (sp.get("components", []) as Array).has("V") and SpellEffects.silenced(s, data, f):
		return "COMBAT_SILENCED"  # v0.7.13.6
	if FightGrid.is_aim(to):  # a square, for what covers an area
		return CombatRules._can_aim(s, data, spell, FightGrid.aim_of(to), f)
	var side := SpellEffects.picks_side(data, spell)
	if not to.is_empty() and (side == "friend" or (side == "any" and not CombatRules.foes_of(s, f).has(to))):
		return CombatRules._can_friend(s, data, spell, to, f)
	if to.is_empty() and bool(SpellEffects.spec(data, spell).get("other", false)):
		return "COMBAT_BAD_TARGET"
	if sp.has("heal_at_slot") or to.is_empty():
		return ""
	var t := _foe(s, f, to)
	if t.is_empty():
		return "COMBAT_BAD_TARGET"
	if CombatRules.charmed_by(s, f, t) and (sp.has("attack") or sp.has("save") or CombatRules.is_engine_spell(data, spell)):
		return "COMBAT_CHARMED"
	var reach := CombatRules._spell_squares(s, data, spell, f)
	var touch := reach <= 1 and FightGrid.dist(f, t) <= 1 and FightGrid.cover(s, data, f, t) < FightGrid.FULL_COVER
	if (CombatRules._no_line(s, data, f, t) or CombatRules._blind_aim(s, data, spell, t, f)) and not touch:
		return "COMBAT_NO_LINE"  # an area on a square reaches it all the same (_can_aim)
	return "COMBAT_OUT_OF_RANGE" if FightGrid.shown_dist(f, t) > reach else ""


func run(s: GameSession, data: Dictionary, f: Dictionary, to: String, how: Dictionary) -> Array[String]:
	var spell := str(how["spell"])
	var slot := int(how.get("slot", 0))
	var lines: Array[String] = []
	if not Sheet.is_hero(f) and not bool(how.get("asked", false)):
		MonsterRules.pay_spell(f, spell, how)
		if str(f.get("side")) == "enemy" and _countered(s, data, f, to, how, lines):
			return lines
	CombatRules.fx(s, to if not to.is_empty() else str(f["id"]), "spell")  # v0.7.22.14
	lines.append_array(ActionRules.cast(s, data, f, spell, slot, to))
	f["hidden"] = false  # casting gives it away
	return lines


## Counterspell of the hero (v0.7.13.7): its window, or its policy decides. True when the spell does not land now.
func _countered(s: GameSession, data: Dictionary, f: Dictionary, to: String, how: Dictionary, lines: Array[String]) -> bool:
	var spell := str(how["spell"])
	var label := SpellEffects.counter_option(s, data, f, spell)
	if label.is_empty():
		return false
	var name := str(data["spells"][spell]["name"])
	var circle := maxi(int(data["spells"][spell]["level"]), int(how.get("slot", 0)))
	var pol := FeatureRules.policy(s)
	if pol == "ask":
		lines.append("%s начинает колдовать «%s»…" % [f["name"], name])
		s.combat["pending"] = {"kind": "counter", "foe": str(f["id"]), "to": to, "how": how, "circle": circle,
			"options": [{"id": "counterspell", "label": label}], "line": "%s колдует «%s»" % [f["name"], name], "dmg": 0}
		s.combat["halt"] = true
		return true
	return pol == "always" and SpellEffects.counter(s, data, f, spell, circle, lines)


func offers(s: GameSession, data: Dictionary, f: Dictionary, targets: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if Sheet.is_hero(f) or SpellEffects.silenced(s, data, f):
		return out
	var held := not str(f.get("concentration", "")).is_empty()
	for o: Dictionary in MonsterRules.castable(data, f):
		var spell := str(o["id"])
		var sp: Dictionary = data["spells"][spell]
		var how := {"spell": spell, "slot": int(o["slot"]), "per_day": bool(o.get("per_day", false))}
		if SpellRules.long_cast(sp) or SpellEffects.spec(data, spell).has("reaction") or (held and bool(sp.get("concentration", false))):
			continue
		if CombatRules.short_of(f, cost(s, data, f, how), 1).is_empty():
			out.append_array(_ways(s, data, f, how, targets))
	return out


## What one spell can do from here, by its way.
func _ways(s: GameSession, data: Dictionary, f: Dictionary, how: Dictionary, targets: Array[Dictionary]) -> Array[Dictionary]:
	var spell := str(how["spell"])
	var sp: Dictionary = data["spells"][spell]
	var w: Dictionary = FightAI.cfg(data)["spells"]
	var scale := float(FightAI.role(data, f)["cast"]) / 6.0
	var me := Sheet.holder(s, f)
	var has_it := func(h: Dictionary) -> bool: return ConditionRules.effects(h).any(func(e: Dictionary) -> bool: return str(e.get("source", {}).get("id", "")) == spell)
	var way := ActionRules.way(data, spell, true)
	match way:
		"summon":
			var called := CombatRules.enemies(s).any(func(id: String) -> bool: return str(CombatRules.fighter(s, id).get("called_by", "")) == str(f["id"])) \
				or CombatRules.allies(s).any(func(id: String) -> bool: return str(CombatRules.fighter(s, id).get("called_by", "")) == str(f["id"]))
			return [] if called or bool(AllyRules.summon_spec(data, spell).get("carrier", false)) else [_self(f, how, float(w["summon"]) * scale)]
		"dispel":
			return [_self(f, how, float(w["dispel"]) * scale)] if not SpellEffects.dispellable(s, f).is_empty() else []
		"teleport":
			var touched := CombatRules.foes_of(s, f).any(func(id: String) -> bool: return FightGrid.touching(f, CombatRules.fighter(s, id)))
			return [_self(f, how, float(w["teleport"]) * scale)] if touched else []
		"heal":
			return _heals(s, data, f, how, w, scale)
		"sustained":
			if bool(SpellEffects.sustained(data, spell).get("follow", false)):
				return [] if has_it.call(me) else [_self(f, how, float(w["sustained"]) * scale)]
			return [] if not SpellEffects.effect_of(s, f, spell).is_empty() else _at(s, data, f, how, targets, float(w["sustained"]) * scale)
		"mark":
			return [] if has_it.call(me) else _at(s, data, f, how, targets, float(w["mark"]) * scale)
		"condition":
			var spec: Dictionary = CombatRules.cfg(data)["condition_spells"][spell]
			if str(f.get("last_spell", "")) == spell and not bool(sp.get("concentration", false)):
				return []  # not the same Command every turn (#14): a spell that holds by itself waits a turn
			var pool := CombatRules.dice_range(str(spec.get("pool", "0")))
			var fit := targets.filter(func(t: Dictionary) -> bool:
				var it := Sheet.holder(s, t)
				return not (spec["conditions"] as Array).all(func(x: String) -> bool: return ConditionRules.has(it, x)) \
					and CombatRules._resists(s, data, t, spec, spec["conditions"], "magic").is_empty() \
					and (not spec.has("pool") or int(it["hp"]) <= (pool[0] + pool[1]) / 2))
			return _at(s, data, f, how, fit, float(w["condition"]) * scale)
		"curse", "bane":
			var fit := targets.filter(func(t: Dictionary) -> bool: return not has_it.call(Sheet.holder(s, t)))
			return _at(s, data, f, how, fit, float(w["curse"]) * scale)
	if SpellEffects.spec(data, spell).has("stabilize"):
		return _fallen(s, data, f, how, float(w["stabilize"]) * scale)
	if SpellEffects.picks_side(data, spell) in ["friend", "any"]:
		return _boons(s, data, f, how, float(w["buff"]) * scale, has_it) if _boon(data, spell) else []
	if SpellEffects.self_spell(data, spell) or (data["rules"]["invisibility"]["spells"] as Dictionary).has(spell):
		return [] if has_it.call(me) or not _boon(data, spell) else [_self(f, how, float(w["buff"]) * scale)]
	return _damage(s, data, f, how, targets, w, scale)


## A row of the spell's table the AI knows the worth of.
func _boon(data: Dictionary, spell: String) -> bool:
	if (data["rules"]["invisibility"]["spells"] as Dictionary).has(spell):
		return true
	var row := SpellEffects.spec(data, spell)
	return (FightAI.cfg(data)["spells"]["boon_keys"] as Array).any(func(k: String) -> bool: return row.has(k))


func _self(f: Dictionary, how: Dictionary, power: float) -> Dictionary:
	return {"act": id, "to": "", "how": how, "t": f, "kind": "cast", "far": 0, "power": power, "self": true}


## One of its side within reach that does not have it yet.
func _boons(s: GameSession, data: Dictionary, f: Dictionary, how: Dictionary, power: float, has_it: Callable) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var reach := CombatRules._spell_squares(s, data, str(how["spell"]), f)
	var other := bool(SpellEffects.spec(data, str(how["spell"])).get("other", false))
	for one: String in CombatRules.friends_of(s, f):
		var t := CombatRules.fighter(s, one)
		if not has_it.call(Sheet.holder(s, t)) and not (other and one == str(f["id"])):
			out.append({"act": id, "to": one, "how": how, "t": t, "kind": "cast", "far": reach, "power": power, "kindly": true, "touch": reach <= 1, "self": one == str(f["id"])})
	return out


## One of its side who lies dying (CombatRules.dying_of): Spare the Dying.
func _fallen(s: GameSession, data: Dictionary, f: Dictionary, how: Dictionary, power: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var reach := CombatRules._spell_squares(s, data, str(how["spell"]), f)
	for one: String in CombatRules.dying_of(s, f):
		out.append({"act": id, "to": one, "how": how, "t": CombatRules.fighter(s, one), "kind": "cast", "far": reach, "power": power, "kindly": true, "touch": reach <= 1})
	return out


## The wounded of its side within the spell's reach, the worst off worth the most.
func _heals(s: GameSession, data: Dictionary, f: Dictionary, how: Dictionary, w: Dictionary, scale: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var reach := CombatRules._spell_squares(s, data, str(how["spell"]), f)
	for one: String in CombatRules.friends_of(s, f):
		var t := CombatRules.fighter(s, one)
		var it := Sheet.holder(s, t)
		var part := float(it["hp"]) / maxf(1.0, float(it["max_hp"]))
		if part <= float(w["heal_below"]):
			out.append({"act": id, "to": one, "how": how, "t": t, "kind": "cast", "far": reach, "power": float(w["heal"]) * scale * (1.5 - part), "kindly": true, "touch": reach <= 1, "self": one == str(f["id"])})
	return out


## Aimed at each of `targets`: a body, or the square under it for what covers an area; an area is worth those it takes.
func _at(s: GameSession, data: Dictionary, f: Dictionary, how: Dictionary, targets: Array, power: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var spell := str(how["spell"])
	var sp: Dictionary = data["spells"][spell]
	var area := sp.has("area") and not sp.has("attack")
	var reach := CombatRules._spell_squares(s, data, spell, f)
	if area and CombatRules.from_self(data, spell):
		reach = maxi(1, FightGrid.squares_of(data, int(sp["area"].get("size", 5))))
	for t: Dictionary in targets:
		var worth := power * (_taken(s, data, f, sp, t) if area else 1.0)
		if worth > 0.0:
			out.append({"act": id, "to": FightGrid.aim_id(FightGrid.cell(t)) if area else str(t["id"]), "how": how, "t": t, "kind": "cast", "far": reach, "power": worth,
				"touch": reach <= 1 and not area, "sight": not area or bool(sp.get("needs_sight", false))})
	return out


## Foes around `t` less the friends an area would catch.
func _taken(s: GameSession, data: Dictionary, f: Dictionary, sp: Dictionary, t: Dictionary) -> float:
	var r := FightGrid.squares_of(data, int(sp["area"].get("size", 5)))
	var n := 0
	for one: String in CombatRules.foes_of(s, f):
		n += 1 if FightGrid.dist(CombatRules.fighter(s, one), t) <= r else 0
	if bool(CombatRules.cfg(data)["friendly_fire"]["on"]):
		for one: String in CombatRules.friends_of(s, f):
			n -= 1 if FightGrid.dist(CombatRules.fighter(s, one), t) <= r and (one != str(f["id"]) or not CombatRules.from_self(data, str(sp.get("id", "")))) else 0
	return float(n)


## The damage it should deal: its dice, the chance, what the target takes of it, less the slot.
func _damage(s: GameSession, data: Dictionary, f: Dictionary, how: Dictionary, targets: Array[Dictionary], w: Dictionary, scale: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var spell := str(how["spell"])
	var sp: Dictionary = data["spells"][spell]
	if not sp.has("damage_at_slot") and not sp.has("damage_at_level"):
		return out
	var slot := int(how.get("slot", 0))
	var r := CombatRules.dice_range(CombatRules._spell_dice(sp, maxi(slot, int(sp.get("level", 0))), MonsterRules._caster_level(data, f)))
	var multi: Dictionary = CombatRules.cfg(data)["multi"].get(spell, {})
	var n := int(multi.get("base", 1)) + int(multi.get("per_slot", 0)) * maxi(0, slot - maxi(1, int(sp["level"])))
	for k: String in multi.get("by_level", {}):
		if MonsterRules._caster_level(data, f) >= int(k):
			n = int(multi["by_level"][k])
	var attack := int(ActionRules.scope(s, data, f, spell)["attack"])
	for t: Dictionary in targets:
		var chance := float(w["hit"])
		if bool(multi.get("auto_hit", false)):
			chance = 1.0
		elif sp.has("attack"):
			chance = clampf((21.0 + attack - Sheet.ac(s, t)) / 20.0, 0.05, 0.95)
		var part := Sheet.taken(s, data, t, str(sp.get("damage_type", "")), 100) / 100.0
		var worth := (r[0] + r[1]) / 2.0 * n * chance * part * scale - float(w["slot"]) * slot
		if worth > 0.0:
			out.append_array(_at(s, data, f, how, [t], worth))
	return out
