class_name SpellEffects
extends RefCounted
## Spells that change the hero's numbers or a foe's (roadmap v0.7.13, «Правила 5e: заклинания»), table
## rules.spell_effects. A spell on the hero leaves an effect (ConditionRules) with its source and, for a concentration
## spell, `concentration` — it goes when the concentration ends:
##   die — a bonus die to the rolls of `on` (attack, save, check), `once` — for one roll (Guidance, Resistance);
##   next_attack_adv — the next attack roll with advantage (True Strike); immune — conditions; temp_hp — at the start
##   of each of the hero's turns (Heroism: the spellcasting modifier).
## A spell on foes (`foe`): a save (`save`) of up to `targets` foes, the first is the target; the others are the nearest;
## a failed one keeps a minus die to its attacks and saves (Bane) until the concentration ends.


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"].get("spell_effects", {})


static func spec(data: Dictionary, spell_id: String) -> Dictionary:
	return cfg(data).get(spell_id, {}) if not spell_id.begins_with("_") else {}


## A spell the hero casts on themselves (no target to pick).
static func self_spell(data: Dictionary, spell_id: String) -> bool:
	var sp := spec(data, spell_id)
	return not sp.is_empty() and not bool(sp.get("foe", false))


static func foe_spell(data: Dictionary, spell_id: String) -> bool:
	return bool(spec(data, spell_id).get("foe", false))


## The spell lands on the hero: the effect for its duration (the concentration's end comes with it). Lines.
static func apply_self(s: GameSession, data: Dictionary, spell_id: String) -> Array[String]:
	var c := s.character
	var sp := spec(data, spell_id)
	var spell: Dictionary = data["spells"][spell_id]
	for e: Dictionary in ConditionRules.effects(c).duplicate():  # cast again: the new one replaces the old
		if str(e.get("source", {}).get("id", "")) == spell_id:
			ConditionRules.remove_effect(c, int(e.get("uid", 0)))
	var rounds := ConditionRules.spell_rounds(data, spell_id)
	var e := {"condition": "", "source": {"kind": "spell", "id": spell_id, "name": str(spell["name"])},
		"concentration": bool(spell.get("concentration", false)), "ends": {"at": ConditionRules.now(s) + rounds} if rounds > 0 else {}}
	for k: String in ["die", "on", "once", "next_attack_adv", "immune", "temp_hp"]:
		if sp.has(k):
			e[k] = sp[k]
	ConditionRules.add_effect(c, e)
	var lines: Array[String] = ["%s: %s" % [spell["name"], text(data, sp)]]
	if sp.has("temp_hp"):
		lines.append_array(turn_start(s, data))
	return lines


## «+к4 к атакам и спасброскам» — what the effect gives, for the chip and the line.
static func text(data: Dictionary, sp: Dictionary) -> String:
	var parts: Array[String] = []
	if sp.has("die"):
		var names := {"attack": "атакам", "save": "спасброскам", "check": "проверкам"}
		var on: Array = (sp.get("on", []) as Array).map(func(x: Variant) -> String: return str(names.get(str(x), x)))
		parts.append("%s%s к %s%s" % ["−" if bool(sp.get("foe", false)) else "+", str(sp["die"]).replace("1d", "к"), " и ".join(on),
			" (один раз)" if bool(sp.get("once", false)) else ""])
	if bool(sp.get("next_attack_adv", false)):
		parts.append("следующая атака с преимуществом")
	if sp.has("immune"):
		parts.append("не испугать")
	if sp.has("temp_hp"):
		parts.append("временные хиты каждый ход")
	return ", ".join(parts)


## The bonus dice of the hero's effects for a roll of `kind` (attack, save, check): {"bonus", "note"}; the `once` ones
## are spent (and their concentration ends).
static func hero_die(s: GameSession, data: Dictionary, kind: String) -> Dictionary:
	var c := s.character
	var total := 0
	var notes: Array[String] = []
	for e: Dictionary in ConditionRules.effects(c).duplicate():
		if not e.has("die") or not (e.get("on", []) as Array).has(kind):
			continue
		var n := CombatRules.roll_dice(s.rng, str(e["die"]))
		total += n
		notes.append("+%d (%s)" % [n, e.get("source", {}).get("name", "")])
		if bool(e.get("once", false)):
			ConditionRules.remove_effect(c, int(e.get("uid", 0)))
			if str(c.get("concentration", "")) == str(e.get("source", {}).get("id", "")):
				c["concentration"] = ""
				c["concentration_ends"] = -1
	return {"bonus": total, "note": " ".join(notes)}


## True Strike: the hero's next attack roll has advantage; the effect goes with that roll. True when it was there.
static func take_next_attack_adv(c: Dictionary) -> bool:
	for e: Dictionary in ConditionRules.effects(c):
		if bool(e.get("next_attack_adv", false)):
			ConditionRules.remove_effect(c, int(e.get("uid", 0)))
			return true
	return false


static func has_next_attack_adv(c: Dictionary) -> bool:
	return ConditionRules.effects(c).any(func(e: Dictionary) -> bool: return bool(e.get("next_attack_adv", false)))


## A condition an effect of a spell keeps away (Heroism — frightened): its name, or "".
static func immune(c: Dictionary, cond: String) -> String:
	for e: Dictionary in ConditionRules.effects(c):
		if (e.get("immune", []) as Array).has(cond):
			return str(e.get("source", {}).get("name", ""))
	return ""


## The start of the hero's turn: Heroism gives its temporary hit points again. Lines.
static func turn_start(s: GameSession, data: Dictionary) -> Array[String]:
	var c := s.character
	var lines: Array[String] = []
	for e: Dictionary in ConditionRules.effects(c):
		if not e.has("temp_hp"):
			continue
		var n := CharacterRules.mod(CharacterRules.ability(c, str(c.get("spell_ability", "cha")))) if str(e["temp_hp"]) == "MOD" else int(e["temp_hp"])
		if n > int(c.get("temp_hp", 0)):
			c["temp_hp"] = n
			lines.append("%s: %d временных хитов" % [e.get("source", {}).get("name", ""), n])
	return lines


# --- on foes -------------------------------------------------------------------------------------------


## Bane: up to `targets` foes (the target first, then the nearest) save or keep the minus die. Lines.
static func curse_foes(s: GameSession, data: Dictionary, spell_id: String, slot: int, target: Dictionary, lines: Array[String]) -> void:
	var sp := spec(data, spell_id)
	var spell: Dictionary = data["spells"][spell_id]
	var dc := int(s.character.get("spell_dc", 10))
	var count := int(sp.get("targets", 1)) + maxi(0, slot - maxi(1, int(spell["level"])))
	var foes: Array[Dictionary] = [target]
	var others := CombatRules.enemies(s).map(func(id: String) -> Dictionary: return CombatRules.fighter(s, id)).filter(
		func(f: Dictionary) -> bool: return str(f["id"]) != str(target["id"]))
	others.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return CombatRules.cols_between(a, CombatRules.player(s)) < CombatRules.cols_between(b, CombatRules.player(s)))
	for f: Variant in others:
		if foes.size() >= count:
			break
		foes.append(f)
	for f: Dictionary in foes:
		var ok := CombatRules._monster_save(s, data, f, str(sp.get("save", "cha")), dc, ["magic"])
		lines.append("%s: %s — спасбросок %s против Сл %d %s" % [spell["name"], f["name"], CombatRules.ab_name(str(sp.get("save", "cha"))), dc,
			"успех" if ok else "провал, %s" % text(data, sp)])
		if not ok:
			f["minus_die"] = {"die": str(sp["die"]), "spell": spell_id, "name": str(spell["name"])}


## The minus die of a cursed foe for its attack or save: the number to take away (0 — none) and the note.
static func foe_die(s: GameSession, f: Dictionary) -> Dictionary:
	if not f.has("minus_die"):
		return {"minus": 0, "note": ""}
	var n := CombatRules.roll_dice(s.rng, str(f["minus_die"]["die"]))
	return {"minus": n, "note": " −%d (%s)" % [n, f["minus_die"]["name"]]}


## The concentration on a foe spell ends: its dice go. Lines.
static func end_on_foes(s: GameSession, spell_id: String) -> Array[String]:
	var lines: Array[String] = []
	for id: String in CombatRules.enemies(s, false):
		var f := CombatRules.fighter(s, id)
		if f.has("minus_die") and str(f["minus_die"].get("spell", "")) == spell_id:
			lines.append("%s: %s проходит" % [f["name"], data_name(f)])
			f.erase("minus_die")
	return lines


static func data_name(f: Dictionary) -> String:
	return str(f.get("minus_die", {}).get("name", "заклинание"))
