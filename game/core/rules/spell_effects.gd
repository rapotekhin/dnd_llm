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
	return not sp.is_empty() and not bool(sp.get("foe", false)) and not bool(sp.get("foe_target", false)) and not sp.has("sustained")


static func foe_spell(data: Dictionary, spell_id: String) -> bool:
	return bool(spec(data, spell_id).get("foe", false))


## The spell lands on the hero: the effect for its duration (the concentration's end comes with it). Lines.
static func apply_self(s: GameSession, data: Dictionary, spell_id: String, slot: int = 0) -> Array[String]:
	var c := s.character
	var sp := spec(data, spell_id)
	var spell: Dictionary = data["spells"][spell_id]
	if sp.has("teleport"):  # an instant spell: the fight moves the hero (Misty Step)
		return []
	for e: Dictionary in ConditionRules.effects(c).duplicate():  # cast again: the new one replaces the old
		if str(e.get("source", {}).get("id", "")) == spell_id:
			ConditionRules.remove_effect(c, int(e.get("uid", 0)))
	var rounds := ConditionRules.spell_rounds(data, spell_id)
	var e := {"condition": "", "source": {"kind": "spell", "id": spell_id, "name": str(spell["name"])},
		"concentration": bool(spell.get("concentration", false)), "ends": {"at": ConditionRules.now(s) + rounds} if rounds > 0 else {}}
	for k: String in sp:
		if not k in ["foe", "targets", "save", "temp_dice", "temp_per_slot", "per_slot", "resist_auto", "remove", "max_hp_plus", "plus_at_slot",
				"next_dice", "blade_dice", "foe_target"]:
			e[k] = sp[k]
	var lines: Array[String] = []
	var slot_up := maxi(0, slot - maxi(1, int(spell["level"])))
	if sp.has("resist_auto"):  # Protection from Energy: the type the foes deal most (v0.7.13.2)
		var dtype := _likely_type(s, data, sp["resist_auto"])
		e["resist"] = [dtype]
	if sp.has("plus_at_slot"):  # Magic Weapon: +2 from the 4th circle
		for k: String in sp["plus_at_slot"]:
			if slot >= int(k):
				e["weapon_plus"] = int(sp["plus_at_slot"][k])
	if sp.has("next_dice"):  # Branding Smite: the dice by the slot
		e["next_dice"] = str(sp["next_dice"].get(str(maxi(slot, int(spell["level"]))), sp["next_dice"].values()[0]))
	if sp.has("blade_dice"):  # Flame Blade
		e["blade_dice"] = str(sp["blade_dice"].get(str(maxi(slot, int(spell["level"]))), sp["blade_dice"].values()[0]))
	if str(sp.get("ability_adv", "")) == "best":  # Enhance Ability: the hero's strongest side
		var best := "str"
		for ab: String in CharacterRules.ABILITIES:
			if int(c.get("abilities", {}).get(ab, 10)) > int(c.get("abilities", {}).get(best, 10)):
				best = ab
		e["ability_adv"] = best
	if sp.has("max_hp_plus"):  # Aid: the maximum and the hit points up
		e["max_hp"] = int(sp["max_hp_plus"]) + int(sp.get("per_slot", 0)) * slot_up
	ConditionRules.add_effect(c, e)
	lines.append("%s: %s" % [spell["name"], text(data, e)])
	if sp.has("remove"):
		lines.append_array(ConditionRules.cure(s, data, {"remove": sp["remove"]}, e["source"]))
	if sp.has("temp_dice"):  # False Life
		var n := CombatRules.roll_dice(s.rng, str(sp["temp_dice"])) + int(sp.get("temp_per_slot", 0)) * slot_up
		if n > int(c.get("temp_hp", 0)):
			c["temp_hp"] = n
		lines.append("временные хиты: %d" % int(c["temp_hp"]))
	if sp.has("temp_hp"):
		lines.append_array(turn_start(s, data))
	CharacterRules.refresh(c, data, s.items)
	if e.has("max_hp"):
		c["hp"] = mini(int(c["max_hp"]), int(c["hp"]) + int(e["max_hp"]))
	return lines


## The damage type the foes of this fight deal most (of `types`), the first of them otherwise.
static func _likely_type(s: GameSession, data: Dictionary, types: Array) -> String:
	var count := {}
	if CombatRules.active(s):
		for id: String in CombatRules.enemies(s):
			for a: Dictionary in CombatRules._monster(data, CombatRules.fighter(s, id)).get("actions", []):
				for d: Variant in a.get("damage", []):
					var t := str((d as Dictionary).get("type", ""))
					if types.has(t):
						count[t] = int(count.get(t, 0)) + 1
	var best := str(types[types.find("fire")] if types.has("fire") else types[0])
	for t: String in count:
		if int(count[t]) > int(count.get(best, 0)):
			best = t
	return best


## The effects of the hero's spells with this key (a sum or a flag of the defenses).
static func hero_effects(c: Dictionary, key: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Dictionary in ConditionRules.effects(c):
		if e.has(key):
			out.append(e)
	return out


## Armor Class by the spells (v0.7.13.2): Mage Armor's base without armor, Shield of Faith's plus, Barkskin's floor.
static func armor_class(c: Dictionary, ac: int, unarmored: bool, dex: int) -> int:
	for e: Dictionary in hero_effects(c, "ac_base"):
		if unarmored:
			ac = maxi(ac, int(e["ac_base"]) + dex)
	for e: Dictionary in hero_effects(c, "ac_plus"):
		ac += int(e["ac_plus"])
	for e: Dictionary in hero_effects(c, "ac_min"):
		ac = maxi(ac, int(e["ac_min"]))
	return ac


## A foe's attack meets the hero's defenses (v0.7.13.2): {"dis": reasons, "stop": a line when the attack never lands
## on the hero (Sanctuary held it back, an image of Mirror Image took it)}.
static func against_attack(s: GameSession, data: Dictionary, f: Dictionary, total: int, hit: bool) -> Dictionary:
	var c := s.character
	var out := {"stop": ""}
	for e: Dictionary in hero_effects(c, "images"):
		var n := int(e["images"])
		if n <= 0:
			continue
		var need: int = {3: 6, 2: 8, 1: 11}.get(n, 11)
		if s.rng.randi_range(1, 20) >= need:
			var image_ac := 10 + CharacterRules.mod(CharacterRules.ability(c, "dex"))
			if total >= image_ac:
				e["images"] = n - 1
				out["stop"] = "удар приходится в иллюзорного двойника — он исчезает (осталось %d)" % (n - 1)
				if n - 1 <= 0:
					ConditionRules.remove_effect(c, int(e["uid"]))
			else:
				out["stop"] = "удар по иллюзорному двойнику — мимо"
			return out
	return out


## Sanctuary: the foe must pass a WIS save against the hero's spell DC or lose the attack. A line, or "".
static func sanctuary_holds(s: GameSession, data: Dictionary, f: Dictionary) -> String:
	if hero_effects(s.character, "sanctuary").is_empty():
		return ""
	var dc := maxi(int(s.character.get("spell_dc", 10)), 10)
	if CombatRules._monster_save(s, data, f, "wis", dc, ["magic"]):
		return ""
	return "%s не решается ударить — Святилище" % f["name"]


## The hero attacks or casts at a foe: Sanctuary ends (5e).
static func break_sanctuary(c: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	for e: Dictionary in hero_effects(c, "sanctuary"):
		ConditionRules.remove_effect(c, int(e["uid"]))
		lines.append("Святилище развеялось")
	return lines


## Why a foe attacks the hero with disadvantage by the hero's spells: Blur, Protection from Evil and Good.
static func attack_dis(s: GameSession, data: Dictionary, f: Dictionary) -> Array[String]:
	var c := s.character
	var out: Array[String] = []
	for e: Dictionary in hero_effects(c, "attackers_dis"):
		out.append(str(e.get("source", {}).get("name", "")))
	var t := str(CombatRules._monster(data, f).get("type", ""))
	for e: Dictionary in hero_effects(c, "foe_types_dis"):
		if (e["foe_types_dis"] as Array).has(t):
			out.append(str(e.get("source", {}).get("name", "")))
	return out


static func has(c: Dictionary, key: String) -> bool:
	return not hero_effects(c, key).is_empty()


static func max_heal(c: Dictionary) -> bool:
	return not hero_effects(c, "max_heal").is_empty()


static func save_adv(c: Dictionary, ability: String) -> String:
	for e: Dictionary in hero_effects(c, "save_adv"):
		if (e["save_adv"] as Array).has(ability):
			return str(e.get("source", {}).get("name", ""))
	return ""


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
	if sp.has("ac_base"):
		parts.append("КД %d + Ловкость без доспеха" % int(sp["ac_base"]))
	if sp.has("ac_plus"):
		parts.append("КД +%d" % int(sp["ac_plus"]))
	if sp.has("ac_min"):
		parts.append("КД не ниже %d" % int(sp["ac_min"]))
	if bool(sp.get("attackers_dis", false)):
		parts.append("атаки по герою с помехой")
	if sp.has("images"):
		parts.append("иллюзорных двойников: %d" % int(sp["images"]))
	if bool(sp.get("sanctuary", false)):
		parts.append("враг бьёт, только пройдя спасбросок Мудрости")
	if sp.has("max_hp"):
		parts.append("максимум хитов +%d" % int(sp["max_hp"]))
	for t: Variant in sp.get("resist", []):
		parts.append("сопротивление: %s" % str(data["misc"]["damage_types"].get(str(t), t)))
	if sp.has("foe_types_dis"):
		parts.append("нежить, исчадия, феи и подобные бьют с помехой")
	if sp.has("save_adv") and bool(sp.get("death_adv", false)):
		parts.append("преимущество на спасброски Мудрости и от смерти, лечение по максимуму")
	if bool(sp.get("haste", false)):
		parts.append("КД +2, скорость вдвое, ещё одно действие; потом ход вялости")
	if bool(sp.get("flying", false)):
		parts.append("полёт: враги без дальних атак не достают")
	if bool(sp.get("blink", false)):
		parts.append("в конце хода к20 11+ — герой исчезает до своего хода")
	if sp.has("speed_plus"):
		parts.append("скорость +%d фт" % int(sp["speed_plus"]))
	if bool(sp.get("bonus_dash", false)):
		parts.append("Рывок бонусным действием")
	if bool(sp.get("enlarged", false)):
		parts.append("+1к4 к урону оружием, преимущество на проверки Силы")
	if bool(sp.get("darkvision", false)):
		parts.append("тёмное зрение")
	if bool(sp.get("see_invisible", false)):
		parts.append("видит невидимое")
	for k: Variant in sp.get("skill_bonus", {}):
		parts.append("+%d к %s" % [int(sp["skill_bonus"][k]), TranslationServer.translate("SKILL_" + str(k).to_upper())])
	if sp.has("ability_adv"):
		parts.append("преимущество на проверки одной характеристики")
	if sp.has("shillelagh"):
		parts.append("дубинка или посох бьют к8 характеристикой заклинаний, магически")
	if sp.has("weapon_plus"):
		parts.append("оружие +%d, магическое" % int(sp["weapon_plus"]))
	if sp.has("weapon_extra"):
		parts.append("+%s излучением при каждом попадании" % str(sp["weapon_extra"][0]).replace("d", "к"))
	if sp.has("next_hit"):
		parts.append("следующее попадание — ещё урон излучением, невидимый становится видимым")
	if sp.has("mark"):
		parts.append("+%s по отмеченному врагу" % str(sp["mark"]).replace("d", "к"))
	if sp.has("blade"):
		parts.append("огненный клинок: рукопашная атака заклинанием")
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


# --- on the weapon (v0.7.13.4) -------------------------------------------------------------------------


## The weapon profile under the hero's spells: Shillelagh (the spellcasting ability, d8, magic), Magic Weapon (+N).
static func weapon(c: Dictionary, w: Dictionary, kind: String) -> Dictionary:
	if w.is_empty():
		return w
	var out := w
	for e: Dictionary in hero_effects(c, "shillelagh"):
		if (e["shillelagh"] as Array).has(kind):
			out = out.duplicate()
			var ab := CharacterRules.mod(CharacterRules.ability(c, str(c.get("spell_ability", "wis"))))
			var old := CharacterRules.mod(CharacterRules.ability(c, "str"))
			if ab > old:
				out["to_hit"] = int(out["to_hit"]) - old + ab
				out["bonus"] = int(out["bonus"]) - old + ab
			if CombatRules.dice_range(str(out["dice"]))[1] < 8:
				out["dice"] = "1d8"
			out["magical"] = true
	for e: Dictionary in hero_effects(c, "weapon_plus"):
		if not str(c.get("equipped", {}).get("main_hand", "")).is_empty() and kind != "":
			out = out.duplicate()
			out["to_hit"] = int(out["to_hit"]) + int(e["weapon_plus"])
			out["bonus"] = int(out["bonus"]) + int(e["weapon_plus"])
			out["magical"] = true
	return out


## The extra damage of the hero's spells on a weapon hit at `t`: [{dice, type, name}]; Branding Smite's is spent.
static func hit_extras(c: Dictionary, t: Dictionary, weapon_type: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Dictionary in hero_effects(c, "weapon_extra"):
		out.append({"dice": str(e["weapon_extra"][0]), "type": str(e["weapon_extra"][1]), "name": str(e.get("source", {}).get("name", ""))})
	for e: Dictionary in hero_effects(c, "mark"):
		if str(e.get("target", "")) == str(t.get("id", "")):
			out.append({"dice": str(e["mark"]), "type": weapon_type, "name": str(e.get("source", {}).get("name", ""))})
	for e: Dictionary in hero_effects(c, "next_dice"):
		out.append({"dice": str(e["next_dice"]), "type": str(e.get("next_hit", "radiant")), "name": str(e.get("source", {}).get("name", "")),
			"reveal": true})
		e.erase("next_dice")  # once (the concentration keeps nothing more)
	return out


## Hunter's Mark lands on a foe (or moves to another).
static func mark(c: Dictionary, target_id: String) -> void:
	for e: Dictionary in hero_effects(c, "mark"):
		e["target"] = target_id


## The marked foe has fallen: the mark can move (a bonus action).
static func mark_free(s: GameSession) -> bool:
	for e: Dictionary in hero_effects(s.character, "mark"):
		var t := CombatRules.fighter(s, str(e.get("target", "")))
		if t.is_empty() or str(t.get("status")) != "active":
			return true
	return false


## Flame Blade's attack: a melee spell attack, the blade's dice of fire. {} without the blade.
static func blade_profile(c: Dictionary) -> Dictionary:
	for e: Dictionary in hero_effects(c, "blade_dice"):
		return {"name": str(e.get("source", {}).get("name", "Огненный клинок")), "to_hit": int(c.get("spell_attack", 0)), "dice": str(e["blade_dice"]),
			"bonus": 0, "type": str(e.get("blade", "fire")), "melee": true, "range": [], "light": false, "id": "", "magical": true,
			"silvered": false, "crit_min": 20, "str_based": false}
	return {}


# --- sustained damage (v0.7.13.5) ----------------------------------------------------------------------


static func sustained(data: Dictionary, spell_id: String) -> Dictionary:
	return spec(data, spell_id).get("sustained", {})


static func _dice(data: Dictionary, spell_id: String, slot: int) -> String:
	var sus := sustained(data, spell_id)
	var spell: Dictionary = data["spells"][spell_id]
	if sus.has("dice"):
		var best := ""
		for k: String in sus["dice"]:
			if slot >= int(k) or best.is_empty():
				best = str(sus["dice"][k])
		return best
	return CombatRules._spell_dice(spell, maxi(slot, int(spell["level"])), 1)


static func zones(s: GameSession) -> Array:
	return s.combat.get("zones", [])


## The column a zone stands on now (Spirit Guardians follow the hero).
static func zone_col(s: GameSession, z: Dictionary) -> int:
	return int(CombatRules.player(s)["col"]) if bool(z.get("follow", false)) else int(z["col"])


## The names of the zones on a column, for the field.
static func zone_names(s: GameSession, col: int) -> Array[String]:
	var out: Array[String] = []
	for z: Dictionary in zones(s):
		if zone_col(s, z) == col:
			out.append(str(z["name"]))
	return out


## The spell comes into the fight: a zone, or the first strike and the button for the next ones. Lines.
static func start_sustained(s: GameSession, data: Dictionary, spell_id: String, slot: int, target_id: String, lines: Array[String]) -> void:
	var c := s.character
	var sus := sustained(data, spell_id)
	var spell: Dictionary = data["spells"][spell_id]
	var dice := _dice(data, spell_id, slot)
	var t := CombatRules.fighter(s, target_id)
	if t.is_empty() and str(sus["kind"]) in ["attack", "heat"]:  # a touch: the nearest foe in the hero's column
		for id: String in CombatRules.enemies(s):
			if CombatRules.cols_between(CombatRules.fighter(s, id), CombatRules.player(s)) == 0:
				t = CombatRules.fighter(s, id)
				break
	var rounds := ConditionRules.spell_rounds(data, spell_id)
	var e := {"condition": "", "source": {"kind": "spell", "id": spell_id, "name": str(spell["name"])},
		"concentration": bool(spell.get("concentration", false)), "ends": {"at": ConditionRules.now(s) + rounds} if rounds > 0 else {},
		"sustained": spell_id, "dice": dice, "target": str(t.get("id", ""))}
	if str(sus["kind"]) == "zone":
		if not s.combat.has("zones"):
			s.combat["zones"] = []
		var col := int(CombatRules.player(s)["col"]) if bool(sus.get("follow", false)) or t.is_empty() else int(t["col"])
		(s.combat["zones"] as Array).append({"spell": spell_id, "name": str(spell["name"]), "col": col, "follow": bool(sus.get("follow", false)),
			"dice": dice, "type": str(sus["type"]), "save": str(sus.get("save", "")), "on": sus.get("on", []), "dc": int(c.get("spell_dc", 10)),
			"slow": bool(sus.get("slow", false))})
		lines.append("%s: %s" % [spell["name"], "вокруг героя" if bool(sus.get("follow", false)) else "встаёт на поле"])
	if sus.has("cost"):
		ConditionRules.add_effect(c, e)
	if bool(sus.get("now", false)) and not t.is_empty():
		lines.append_array(_hit(s, data, spell_id, e, t))


## The buttons of the spells that go on each turn: [{id, name, cost, target, tip}].
static func actions(s: GameSession, data: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Dictionary in hero_effects(s.character, "sustained"):
		var sus := sustained(data, str(e["sustained"]))
		if not sus.has("cost"):
			continue
		var fixed := str(sus["kind"]) == "heat"
		out.append({"id": "spell_" + str(e["sustained"]), "name": "%s: %s" % [e["source"]["name"], sus.get("label", "")], "cost": str(sus["cost"]),
			"target": not fixed, "tip": text(data, spec(data, str(e["sustained"])))})
	return out


static func _effect_of(s: GameSession, spell_id: String) -> Dictionary:
	for e: Dictionary in hero_effects(s.character, "sustained"):
		if str(e["sustained"]) == spell_id:
			return e
	return {}


## "" when the sustained spell's button can go at `target_id` now.
static func can_act(s: GameSession, data: Dictionary, id: String, target_id: String) -> String:
	var spell_id := id.trim_prefix("spell_")
	var e := _effect_of(s, spell_id)
	if e.is_empty():
		return "COMBAT_NO_FEATURE"
	var sus := sustained(data, spell_id)
	var t := CombatRules.fighter(s, target_id if str(sus["kind"]) != "heat" else str(e.get("target", "")))
	if t.is_empty() or str(t.get("status")) != "active":
		return "COMBAT_BAD_TARGET"
	var reach := 0 if str(sus["kind"]) == "attack" and spell_id == "vampiric_touch" else CombatRules.range_cols(data, int(data["spells"][spell_id].get("range_ft", 60)))
	if str(sus["kind"]) == "zone":
		reach = int(sus.get("move", 1))
		if absi(int(t["col"]) - _zone_of(s, spell_id)) > reach and not bool(sus.get("ram", false)):
			return "COMBAT_OUT_OF_RANGE"
		return ""
	if CombatRules.cols_between(t, CombatRules.player(s)) > reach:
		return "COMBAT_OUT_OF_RANGE"
	return ""


static func _zone_of(s: GameSession, spell_id: String) -> int:
	for z: Dictionary in zones(s):
		if str(z["spell"]) == spell_id:
			return zone_col(s, z)
	return 0


## The button: the next strike, or the zone moved toward the target (the sphere strikes where it comes). Lines.
static func act(s: GameSession, data: Dictionary, id: String, target_id: String) -> Array[String]:
	var spell_id := id.trim_prefix("spell_")
	var e := _effect_of(s, spell_id)
	var sus := sustained(data, spell_id)
	var econ := CombatRules.economy(s)
	econ[str(sus["cost"])] = int(econ[str(sus["cost"])]) - 1
	var lines: Array[String] = []
	if str(sus["kind"]) == "zone":
		for z: Dictionary in zones(s):
			if str(z["spell"]) != spell_id:
				continue
			var to := int(CombatRules.fighter(s, target_id)["col"])
			var step := clampi(to - int(z["col"]), -int(sus.get("move", 1)), int(sus.get("move", 1)))
			z["col"] = int(z["col"]) + step
			lines.append("%s сдвигается" % z["name"])
			if bool(sus.get("ram", false)):
				for fid: String in CombatRules.enemies(s):
					var f := CombatRules.fighter(s, fid)
					if int(f["col"]) == int(z["col"]):
						lines.append_array(_zone_hit(s, data, z, f))
			else:
				for fid: String in CombatRules.enemies(s):
					var f := CombatRules.fighter(s, fid)
					if int(f["col"]) == int(z["col"]) and (z["on"] as Array).has("enter"):
						lines.append_array(_zone_hit(s, data, z, f))
		return lines
	var t := CombatRules.fighter(s, target_id if str(sus["kind"]) != "heat" else str(e.get("target", "")))
	if str(sus["kind"]) == "strike":
		for fid: String in CombatRules.enemies(s):
			var f := CombatRules.fighter(s, fid)
			if int(f["col"]) == int(t["col"]):
				lines.append_array(_save_hit(s, data, str(e["source"]["name"]), str(sus["type"]), str(sus.get("save", "dex")), str(e["dice"]),
					int(s.character.get("spell_dc", 10)), f, true))
		return lines
	return _hit(s, data, spell_id, e, t)


## A strike of an attack / heat / strike spell at `t`. Lines.
static func _hit(s: GameSession, data: Dictionary, spell_id: String, e: Dictionary, t: Dictionary) -> Array[String]:
	var c := s.character
	var sus := sustained(data, spell_id)
	var name := str(e["source"]["name"])
	var lines: Array[String] = []
	match str(sus["kind"]):
		"attack":
			var ab := CharacterRules.mod(CharacterRules.ability(c, str(c.get("spell_ability", "wis"))))
			var res := CombatRules._attack(s, data, str(c["name"]), name, int(c.get("spell_attack", 0)), false,
				not CombatRules.hero_attack_dis(s, data, t).is_empty(), t, str(e["dice"]).replace("+MOD", ""), ab if str(e["dice"]).contains("MOD") else 0,
				str(sus["type"]), lines)
			if bool(res["hit"]) and bool(sus.get("drain", false)):
				var back := int(res["damage"]) / 2
				var was := int(c["hp"])
				c["hp"] = mini(int(c["max_hp"]), was + back)
				lines.append("%s: +%d HP" % [name, int(c["hp"]) - was])
		"heat":
			var dmg := CombatRules._resist(data, t, str(sus["type"]), CombatRules.roll_dice(s.rng, str(e["dice"])))
			lines.append("%s: %s — %d (огонь)" % [name, t["name"], dmg])
			CombatRules._hurt_enemy(s, data, t, dmg, lines, str(sus["type"]))
			if str(t.get("status")) == "active" and not CombatRules._monster_save(s, data, t, "con", int(c.get("spell_dc", 10)), ["magic"]):
				t["mocked"] = true  # the burning metal: disadvantage on its next attack
				lines.append("%s едва держит раскалённое — атака с помехой" % t["name"])
		"strike":
			for fid: String in CombatRules.enemies(s):
				var f := CombatRules.fighter(s, fid)
				if int(f["col"]) == int(t["col"]):
					lines.append_array(_save_hit(s, data, name, str(sus["type"]), str(sus.get("save", "dex")), str(e["dice"]), int(c.get("spell_dc", 10)), f, true))
	return lines


static func _save_hit(s: GameSession, data: Dictionary, name: String, dtype: String, save: String, dice: String, dc: int, f: Dictionary, half: bool) -> Array[String]:
	var lines: Array[String] = []
	if str(f.get("status")) != "active":
		return lines
	var dmg := CombatRules.roll_dice(s.rng, dice)
	var ok := not save.is_empty() and CombatRules._monster_save(s, data, f, save, dc, ["magic"])
	if ok:
		dmg = dmg / 2 if half else 0
	dmg = CombatRules._resist(data, f, dtype, dmg)
	lines.append("%s: %s — %s%d (%s)" % [name, f["name"], ("спасбросок %s %s, " % [CombatRules.ab_name(save), "успех" if ok else "провал"]) if not save.is_empty() else "",
		dmg, data["misc"]["damage_types"].get(dtype, dtype)])
	if dmg > 0:
		CombatRules._hurt_enemy(s, data, f, dmg, lines, dtype)
	return lines


static func _zone_hit(s: GameSession, data: Dictionary, z: Dictionary, f: Dictionary) -> Array[String]:
	return _save_hit(s, data, str(z["name"]), str(z["type"]), str(z["save"]), str(z["dice"]), int(z["dc"]), f, true)


## A foe and the zones: `when` — start (of its turn), enter (a column it moves into; once a turn a zone), end. Lines.
static func zone_tick(s: GameSession, data: Dictionary, f: Dictionary, when: String) -> Array[String]:
	var lines: Array[String] = []
	if when == "start":
		f["zoned"] = []
	for z: Dictionary in zones(s):
		if str(f.get("status")) != "active" or zone_col(s, z) != int(f["col"]) or not (z["on"] as Array).has(when):
			continue
		if when == "enter" and (f.get("zoned", []) as Array).has(str(z["spell"])):
			continue
		if not f.has("zoned"):
			f["zoned"] = []
		(f["zoned"] as Array).append(str(z["spell"]))
		lines.append_array(_zone_hit(s, data, z, f))
	return lines


## A foe that starts its turn in a slowing zone (Spirit Guardians, Spike Growth) moves half: one column less, at least 0.
static func slowed(s: GameSession, f: Dictionary) -> bool:
	for z: Dictionary in zones(s):
		if bool(z.get("slow", false)) and zone_col(s, z) == int(f["col"]):
			return true
	return false


## The concentration (or the time) ends: the zones of the spell go.
static func end_zones(s: GameSession, spell_id: String) -> Array[String]:
	var lines: Array[String] = []
	for z: Dictionary in zones(s).duplicate():
		if str(z["spell"]) == spell_id:
			zones(s).erase(z)
			lines.append("%s гаснет" % z["name"])
	return lines
