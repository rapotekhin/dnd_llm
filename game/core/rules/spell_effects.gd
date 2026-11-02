class_name SpellEffects
extends RefCounted
## Spells that change the numbers of anyone (roadmap v0.7.13, «Правила 5e: заклинания»), table rules.spell_effects. `CombatRules.caster`
## is who casts. A spell leaves an effect (ConditionRules) with its source, `by` — who laid it, and for the hero's own
## concentration spell `concentration`; it goes when the concentration ends:
##   die — a bonus die to the rolls of `on` (attack, save, check), `once` — for one roll (Guidance, Resistance);
##   next_attack_adv — the next attack roll with advantage (True Strike); immune — conditions; temp_hp — at the start
##   of each of the hero's turns (Heroism: the spellcasting modifier).
## A spell on foes (`foe`): a save (`save`) of each foe picked (rules.combat.spell_targets);
## a failed one keeps a minus die to its attacks and saves (Bane) until the concentration ends.


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"].get("spell_effects", {})


static func spec(data: Dictionary, spell_id: String) -> Dictionary:
	return cfg(data).get(spell_id, {}) if not spell_id.begins_with("_") else {}


## A spell the hero casts on themselves (no target to pick).
static func self_spell(data: Dictionary, spell_id: String) -> bool:
	var sp := spec(data, spell_id)
	return not sp.is_empty() and not bool(sp.get("foe", false)) and not bool(sp.get("foe_target", false)) and not sp.has("sustained") \
		and not sp.has("curse") and not sp.has("reaction") and not sp.has("npc_save")


static func foe_spell(data: Dictionary, spell_id: String) -> bool:
	return bool(spec(data, spell_id).get("foe", false))


## The chosen targets of a spell (v0.7.50.1, rules.combat.spell_targets): {side, n, per_slot} or {}.
static func picks(data: Dictionary, spell_id: String) -> Dictionary:
	return CombatRules.cfg(data)["spell_targets"].get(spell_id, {}) if not spell_id.begins_with("_") else {}


static func picks_side(data: Dictionary, spell_id: String) -> String:
	return str(picks(data, spell_id).get("side", ""))


## How many targets the spell takes at this slot.
static func picks_count(data: Dictionary, spell_id: String, slot: int) -> int:
	var p := picks(data, spell_id)
	return int(p.get("n", 1)) + int(p.get("per_slot", 0)) * maxi(0, slot - maxi(1, int(data["spells"][spell_id]["level"])))


## Reduce on a foe (v0.7.50.1): a CON save or its blows weaken by 1d4 until the concentration ends.
static func reduce_foe(s: GameSession, data: Dictionary, spell_id: String, f: Dictionary, lines: Array[String]) -> void:
	var ok := Sheet.saved(s, data, f, "con", CombatRules.spell_dc(s), "magic")
	lines.append("%s: %s — спасбросок Тел %s" % [data["spells"][spell_id]["name"], f["name"], "успех" if ok else "провал, уменьшается"])
	if not ok:
		ConditionRules.add_effect(Sheet.holder(s, f), {"source": {"kind": "spell", "id": spell_id, "name": str(data["spells"][spell_id]["name"])}, "reduced": true, "by": str(CombatRules.caster(s)["id"])})


## The spell lands on one of the caster's side (v0.7.50.1): a heal, or a boon that goes with the concentration. The hero
## takes it as its own; a fighter's numbers are read from what the effect gives.
static func on_friend(s: GameSession, data: Dictionary, spell_id: String, slot: int, f: Dictionary, lines: Array[String]) -> void:
	var sp := spec(data, spell_id)
	var spell: Dictionary = data["spells"][spell_id]
	if (data["rules"]["invisibility"]["spells"] as Dictionary).has(spell_id):
		lines.append_array(CombatRules._add_condition(s, data, f, "invisible", {"rounds": 100, "spell": spell_id}))
		ConditionRules.effects_of(Sheet.holder(s, f), "invisible")[0]["ends_on_attack"] = bool(data["rules"]["invisibility"]["spells"][spell_id].get("ends_on_attack", true))
		lines.append("%s: %s" % [f["name"], spell["name"]])
		return
	if sp.is_empty():
		CombatRules.heal(s, data, spell_id, slot, f, lines)
		return
	if Sheet.is_hero(f):
		lines.append_array(apply_self(s, data, spell_id, slot))
		return
	if NOT_ON_A_BODY.any(func(k: String) -> bool: return sp.has(k)):
		return
	_end_spell_on(f, spell_id, str(CombatRules.caster(s)["id"]))
	var boon := _effect(s, data, spell_id, slot, f)
	var speed := int(sp.get("speed_plus", 0))
	if bool(sp.get("speed_x2", false)):
		speed = Move.feet_of(data, Sheet.template(data, f))
	if speed > 0:
		boon["speed"] = speed
	for cond: Variant in sp.get("remove", []):
		CombatRules._remove_condition(f, str(cond))
	if sp.has("ac_min"):
		boon["ac"] = maxi(0, int(sp["ac_min"]) - CombatRules.ac_of(f))
	elif sp.has("ac_base"):
		boon["ac"] = maxi(0, int(sp["ac_base"]) + Sheet.ability_mod(s, data, f, "dex") - CombatRules.ac_of(f))
	if boon.has("max_hp"):
		f["max_hp"] = int(f["max_hp"]) + int(boon["max_hp"])
		f["hp"] = int(f["hp"]) + int(boon["max_hp"])
	ConditionRules.add_effect(f, GameSession.whole(boon))
	lines.append("%s: %s" % [f["name"], spell["name"]])
	_temp_points(s, sp, slot - maxi(1, int(spell["level"])), f, lines)
	if sp.has("temp_hp"):
		lines.append_array(turn_start(s, data, f))


## What is done in the world, not to a body: only the hero's table of apply_self reads these.
const NOT_ON_A_BODY: Array[String] = ["teleport", "lift_curse", "reveal", "knock", "make", "dispel"]


## What the spells on a fighter give, by a key of its statuses: the first value (`fallback` — none).
static func boon(f: Dictionary, key: String, fallback: Variant = null) -> Variant:
	for e: Dictionary in f.get("effects", []):
		if e.has(key):
			return e[key]
	return fallback


## Advantage on a save from the spells on a fighter: Enhance Ability, Haste (DEX), Beacon of Hope (WIS).
static func boon_save_adv(f: Dictionary, ab: String) -> bool:
	return boon(f, "ability_adv") != null or (boon(f, "save_adv", []) as Array).has(ab)


## It strikes or casts at a foe: what ends then (Sanctuary, Invisibility on anybody). Lines.
static func end_on_attack(c: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	for e: Dictionary in ConditionRules.effects(c).duplicate():
		if e.has("sanctuary") or bool(e.get("ends_on_attack", false)):
			ConditionRules.remove_effect(c, int(e["uid"]))
			if e.has("sanctuary"):
				lines.append("Святилище развеялось")
	return lines


## The spell lands on the hero: the effect for its duration (the concentration's end comes with it). Lines.
static func apply_self(s: GameSession, data: Dictionary, spell_id: String, slot: int = 0) -> Array[String]:
	var c := s.character
	var sp := spec(data, spell_id)
	var spell: Dictionary = data["spells"][spell_id]
	var lines_before: Array[String] = []
	if sp.has("teleport"):  # an instant spell: the fight moves the hero (Misty Step)
		return []
	if bool(sp.get("lift_curse", false)):  # Remove Curse (v0.7.13.7)
		var lifted := ItemRules.lift_curse(c, data, s.items)
		return lifted if not lifted.is_empty() else ["проклятых вещей на герое нет"] as Array[String]
	if sp.has("reveal") or sp.has("knock"):  # Find Traps, Detect Magic, Knock (v0.7.13.8)
		var found := world_spell(s, data, spell_id)
		if not bool(spell.get("concentration", false)):
			return found
		lines_before = found
	if sp.has("make"):  # Goodberry, Create Food and Water
		var made: Array[String] = []
		for id: String in sp["make"]:
			c["inventory"][id] = int(c["inventory"].get(id, 0)) + int(sp["make"][id])
			made.append("%s ×%d" % [ItemRules.display_name(data["items"], s.items, id), int(sp["make"][id])])
		return ["Сотворено: " + ", ".join(made)]
	for e: Dictionary in ConditionRules.effects(c).duplicate():  # cast again: the new one replaces the old
		if str(e.get("source", {}).get("id", "")) == spell_id:
			ConditionRules.remove_effect(c, int(e.get("uid", 0)))
	var e := _effect(s, data, spell_id, slot, Sheet.HERO)
	var lines: Array[String] = []
	ConditionRules.add_effect(c, GameSession.whole(e))  # the table's numbers come as floats from JSON
	lines.append_array(lines_before)
	lines.append("%s: %s" % [spell["name"], text(data, e)])
	if sp.has("remove"):
		lines.append_array(ConditionRules.cure(s, data, {"remove": sp["remove"]}, e["source"]))
	_temp_points(s, sp, slot - maxi(1, int(spell["level"])), Sheet.HERO, lines)
	if sp.has("temp_hp"):
		lines.append_array(turn_start(s, data))
	CharacterRules.refresh(c, data, s.items)
	if e.has("max_hp"):
		c["hp"] = mini(int(c["max_hp"]), int(c["hp"]) + int(e["max_hp"]))
	return lines


## False Life: temporary hit points by its dice.
static func _temp_points(s: GameSession, sp: Dictionary, slot_up: int, who: Dictionary, lines: Array[String]) -> void:
	if not sp.has("temp_dice"):
		return
	var it := Sheet.holder(s, who)
	var n := CombatRules.roll_dice(s.rng, str(sp["temp_dice"])) + int(sp.get("temp_per_slot", 0)) * maxi(0, slot_up)
	if n > int(it.get("temp_hp", 0)):
		it["temp_hp"] = n
	lines.append("временные хиты: %d" % int(it["temp_hp"]))


## The effect of a spell by its row on `who`: its source, who laid it, its time and what the row gives.
static func _effect(s: GameSession, data: Dictionary, spell_id: String, slot: int, who: Dictionary) -> Dictionary:
	var sp := spec(data, spell_id)
	var spell: Dictionary = data["spells"][spell_id]
	var me := CombatRules.caster(s)
	var rounds := ConditionRules.spell_rounds(data, spell_id)
	var e := {"condition": "", "source": {"kind": "spell", "id": spell_id, "name": str(spell["name"])}, "by": str(me["id"]),
		"concentration": bool(spell.get("concentration", false)) and Sheet.is_hero(me) and Sheet.is_hero(who), "ends": {"at": ConditionRules.now(s) + rounds} if rounds > 0 else {}}
	for k: String in sp:
		if not k in ["foe", "targets", "save", "temp_dice", "temp_per_slot", "per_slot", "resist_auto", "remove", "max_hp_plus", "plus_at_slot",
				"next_dice", "blade_dice", "foe_target"]:
			e[k] = sp[k]
	var slot_up := maxi(0, slot - maxi(1, int(spell["level"])))
	if sp.has("self_status"):  # a spell the master built: its status with what it lays
		e["condition"] = str(sp["self_status"])
		e.merge(MakeRules.fx(s, str(sp["self_status"])))
	if sp.has("guise"):  # Disguise Self (v0.7.63): the master names the look; the spell's DC is what a viewer must beat
		e["guise"] = {"name": "", "faction": "", "dc": CombatRules.spell_dc(s), "seen": {}}
	if sp.has("resist_auto"):  # Protection from Energy: the type the foes deal most (v0.7.13.2)
		e["resist"] = (sp.get("resist", []) as Array) + [_likely_type(s, data, sp["resist_auto"])]
	if sp.has("plus_at_slot"):  # Magic Weapon: +2 from the 4th circle
		for k: String in sp["plus_at_slot"]:
			if slot >= int(k):
				e["weapon_plus"] = int(sp["plus_at_slot"][k])
	if sp.has("next_dice"):  # Branding Smite: the dice by the slot
		e["next_dice"] = str(sp["next_dice"].get(str(maxi(slot, int(spell["level"]))), sp["next_dice"].values()[0]))
	if sp.has("blade_dice"):  # Flame Blade
		e["blade_dice"] = str(sp["blade_dice"].get(str(maxi(slot, int(spell["level"]))), sp["blade_dice"].values()[0]))
	if str(sp.get("ability_adv", "")) == "best":  # Enhance Ability: its strongest side
		var ab: Dictionary = Sheet.of(s, data, who)["abilities"]
		var best := "str"
		for id: String in CharacterRules.ABILITIES:
			if int(ab.get(id, 10)) > int(ab.get(best, 10)):
				best = id
		e["ability_adv"] = best
	if sp.has("max_hp_plus"):  # Aid: the maximum and the hit points up
		e["max_hp"] = int(sp["max_hp_plus"]) + int(sp.get("per_slot", 0)) * slot_up
	if str(sp.get("temp_hp", "")) == "MOD":  # Heroism: the caster's modifier, each turn
		e["temp_hp"] = Sheet.ability_mod(s, data, me, CombatRules.spell_ability(s))
	if sp.has("sanctuary"):
		e["dc"] = maxi(CombatRules.spell_dc(s), 10)
	return e


## The damage type the caster's foes deal most (of `types`), the first of them otherwise.
static func _likely_type(s: GameSession, data: Dictionary, types: Array) -> String:
	var count := {}
	if CombatRules.active(s):
		for id: String in CombatRules.foes_of(s, CombatRules.caster(s)):
			for a: Dictionary in Sheet.template(data, CombatRules.fighter(s, id)).get("actions", []):
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


## A hit meets Mirror Image on `t` (v0.7.13.2): a line when an image took it, "" otherwise.
static func against_attack(s: GameSession, data: Dictionary, f: Dictionary, t: Dictionary, total: int) -> String:
	var c := Sheet.holder(s, t)
	for e: Dictionary in hero_effects(c, "images"):
		var n := int(e["images"])
		if n <= 0:
			continue
		var need: int = {3: 6, 2: 8, 1: 11}.get(n, 11)
		if Roll.d20(s.rng) >= need:
			if total >= 10 + Sheet.ability_mod(s, data, t, "dex"):
				e["images"] = n - 1
				if n - 1 <= 0:
					ConditionRules.remove_effect(c, int(e["uid"]))
				return "удар приходится в иллюзорного двойника — он исчезает (осталось %d)" % (n - 1)
			return "удар по иллюзорному двойнику — мимо"
	return ""


## Sanctuary on `t`: `f` passes a WIS save against its caster's DC or loses the blow. A line, or "".
static func sanctuary(s: GameSession, data: Dictionary, f: Dictionary, t: Dictionary) -> String:
	var it := Sheet.holder(s, t)
	var on := hero_effects(it, "sanctuary")
	if on.is_empty() or Sheet.saved(s, data, f, "wis", int(on[0].get("dc", 10)), "magic"):
		return ""
	return "%s не решается ударить %s — Святилище" % [Sheet.holder(s, f).get("name", ""), it.get("name", "")]


## Why `f` strikes `t` with disadvantage by the spells on `t`: Blur, Protection from Evil and Good.
static func attack_dis(s: GameSession, data: Dictionary, f: Dictionary, t: Dictionary) -> Array[String]:
	var c := Sheet.holder(s, t)
	var out: Array[String] = []
	for e: Dictionary in hero_effects(c, "attackers_dis"):
		out.append(str(e.get("source", {}).get("name", "")))
	var type := str(Sheet.template(data, f).get("type", ""))
	for e: Dictionary in hero_effects(c, "foe_types_dis"):
		if (e["foe_types_dis"] as Array).has(type):
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
		parts.append("полёт: враги без дальних атак не достают, пока герой не ударит вблизи")
	if sp.has("guise"):
		parts.append("чужой облик: скажите мастеру, кем выглядите")
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
	if bool(sp.get("light", false)):
		parts.append("свет вокруг героя")
	if str(sp.get("reveal", "")) == "magic":
		parts.append("чувствует магию рядом")
	if sp.has("immune"):
		parts.append("не испугать")
	if sp.has("temp_hp"):
		parts.append("временные хиты каждый ход")
	return ", ".join(parts)


## The bonus dice of the hero's effects for a roll of `kind` (attack, save, check): {"bonus", "note"}; the `once` ones
## are spent (and their concentration ends).
static func die(s: GameSession, h: Dictionary, kind: String) -> Dictionary:
	var total := 0
	var notes: Array[String] = []
	var parts: Array[Dictionary] = []  # for the roll's breakdown (v0.7.39.5)
	for e: Dictionary in ConditionRules.effects(h).duplicate():
		if not e.has("die") or not (e.get("on", []) as Array).has(kind):
			continue
		var same := str(e.get("same_as", ""))  # v0.7.49: the temple's blessing is Bless — not twice
		if not same.is_empty() and ConditionRules.effects(h).any(func(o: Dictionary) -> bool: return str(o.get("source", {}).get("id", "")) == same):
			continue
		var n := CombatRules.roll_dice(s.rng, str(e["die"])) * (-1 if bool(e.get("minus", false)) else 1)
		var name := str(e.get("source", {}).get("name", ""))
		total += n
		notes.append("%s%d (%s)" % ["−" if n < 0 else "+", absi(n), name])
		parts.append(RollParts.part("%s (%s)" % [name, str(e["die"]).replace("d", "к")], n))
		if bool(e.get("once", false)):
			ConditionRules.remove_effect(h, int(e.get("uid", 0)))
			if str(h.get("concentration", "")) == str(e.get("source", {}).get("id", "")):
				h["concentration"] = ""
				h["concentration_ends"] = -1
	return {"bonus": total, "note": " ".join(notes), "parts": parts}


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


## The start of its turn: Heroism gives its temporary hit points again. Lines.
static func turn_start(s: GameSession, _data: Dictionary, who: Dictionary = Sheet.HERO) -> Array[String]:
	var c := Sheet.holder(s, who)
	var lines: Array[String] = []
	for e: Dictionary in ConditionRules.effects(c):
		if not e.has("temp_hp"):
			continue
		var n := int(e["temp_hp"])
		if n > int(c.get("temp_hp", 0)):
			c["temp_hp"] = n
			lines.append("%s: %d временных хитов" % [e.get("source", {}).get("name", ""), n])
	return lines


# --- on foes -------------------------------------------------------------------------------------------


## Bane on one chosen foe (the others are picked one by one, v0.7.50.1): it saves or keeps the minus die.
static func curse_foes(s: GameSession, data: Dictionary, spell_id: String, slot: int, target: Dictionary, lines: Array[String]) -> void:
	var sp := spec(data, spell_id)
	var spell: Dictionary = data["spells"][spell_id]
	var dc := CombatRules.spell_dc(s)
	var ok := Sheet.saved(s, data, target, str(sp.get("save", "cha")), dc, "magic")
	lines.append("%s: %s — спасбросок %s против Сл %d %s" % [spell["name"], target["name"], CombatRules.ab_name(str(sp.get("save", "cha"))), dc,
		"успех" if ok else "провал, %s" % text(data, sp)])
	if not ok:
		ConditionRules.add_effect(Sheet.holder(s, target), {"source": {"kind": "spell", "id": spell_id, "name": str(spell["name"])}, "die": str(sp["die"]), "on": ["attack", "save"], "minus": true,
			"by": str(CombatRules.caster(s)["id"])})


## The concentration of `by` ends: what the spell left on anyone goes. Lines.
static func end_on_fighters(s: GameSession, data: Dictionary, spell_id: String, by: String = CombatRules.PLAYER) -> Array[String]:
	var lines: Array[String] = []
	var fall := str(spec(data, spell_id).get("fall", ""))
	for id: String in CombatRules.enemies(s, false) + CombatRules.allies(s, false):
		var f := CombatRules.fighter(s, id)
		var gone := _end_spell_on(f, spell_id, by)
		_gone_lines(data, str(f["name"]), gone, lines)
		if not fall.is_empty() and not gone.is_empty() and str(f.get("status")) == "active":
			CombatRules._fall(s, data, f, spell_id, fall, lines)
	if by != CombatRules.PLAYER:  # what one's spell left on the hero; the hero's own goes by ConditionRules
		var gone := _end_spell_on(s.character, spell_id, by)
		_gone_lines(data, str(s.character.get("name", "")), gone, lines)
		CharacterRules.refresh(s.character, data, s.items)
		if not fall.is_empty() and not gone.is_empty():
			CombatRules._fall(s, data, CombatRules.player(s), spell_id, fall, lines)
	return lines


static func _gone_lines(data: Dictionary, who: String, gone: Array[Dictionary], lines: Array[String]) -> void:
	for e: Dictionary in gone:
		if not str(e.get("condition", "")).is_empty():
			lines.append("%s: %s проходит — концентрация прервана" % [who, CombatRules.cond_name(data, str(e["condition"]))])
		elif bool(e.get("minus", false)):
			lines.append("%s: %s проходит" % [who, e["source"]["name"]])


## What this spell left on the fighter goes (of `by`, when named); the statuses that went.
static func _end_spell_on(f: Dictionary, spell_id: String, by: String = "") -> Array[Dictionary]:
	var gone: Array[Dictionary] = []
	for e: Dictionary in ConditionRules.effects(f).duplicate():
		if str(e.get("source", {}).get("id", "")) == spell_id and (by.is_empty() or str(e.get("by", CombatRules.PLAYER)) == by):
			ConditionRules.remove_effect(f, int(e["uid"]))
			gone.append(e)
			if e.has("haste"):
				f["lethargy"] = true
	return gone


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
				var parts: Array[Dictionary] = []
				parts.assign(out.get("hit_parts", []))
				parts.append(RollParts.part("%s: %s вместо Силы" % [e.get("source", {}).get("name", ""), RollParts.ability_name(str(c.get("spell_ability", "wis")))], ab - old))
				out["hit_parts"] = parts
			if CombatRules.dice_range(str(out["dice"]))[1] < 8:
				out["dice"] = "1d8"
			out["magical"] = true
	for e: Dictionary in hero_effects(c, "weapon_plus"):
		if not str(c.get("equipped", {}).get("main_hand", "")).is_empty() and kind != "":
			out = out.duplicate()
			out["to_hit"] = int(out["to_hit"]) + int(e["weapon_plus"])
			var plus: Array[Dictionary] = []
			plus.assign(out.get("hit_parts", []))
			plus.append(RollParts.part(str(e.get("source", {}).get("name", "заклинание")), int(e["weapon_plus"])))
			out["hit_parts"] = plus
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
	if not spell.has("damage_at_slot") and not spell.has("damage_at_level"):
		return ""  # Grease, Fog Cloud: no damage of their own (v0.7.13.6)
	return CombatRules._spell_dice(spell, maxi(slot, int(spell["level"])), 1)


static func zones(s: GameSession) -> Array:
	return s.combat.get("zones", [])


## The zones as the map draws them: [{name, cells: Array[Vector2i], kind}].
static func zone_view(s: GameSession, data: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for z: Dictionary in zones(s):
		out.append({"name": str(z["name"]), "cells": FightGrid.zone_cells(s, data, z), "hurts": not str(z.get("dice", "")).is_empty()})
	return out


## The squares of a zone laid with its centre at `at`.
static func _lay(s: GameSession, data: Dictionary, z: Dictionary, at: Vector2i) -> void:
	z["x"] = at.x
	z["y"] = at.y
	var from_me := int(data["spells"].get(str(z["spell"]), {}).get("range_ft", 0)) <= 0
	var me := CombatRules.fighter(s, str(z.get("by", CombatRules.PLAYER)))
	z["cells"] = FightGrid.pack_cells(FightGrid.area(s, data, z["shape"], FightGrid.cell(me), at, from_me))


## Darkness over the light of a spell of `circle` or lower ends that spell: the light of the hero's spell reaches the zone.
static func _douse(s: GameSession, data: Dictionary, zone: Dictionary, circle: int) -> Array[String]:
	var lines: Array[String] = []
	var c := s.character
	var far := int(SightRules.cfg(data)["lights"]["light"])
	var at := FightGrid.cell(CombatRules.player(s))
	if not FightGrid.zone_cells(s, data, zone).any(func(z: Vector2i) -> bool: return WalkRules.distance(z, at) <= far):
		return lines
	for e: Dictionary in ConditionRules.effects(c).duplicate():
		var id := str(e.get("source", {}).get("id", ""))
		if str(e.get("source", {}).get("kind", "")) == "spell" and bool(spec(data, id).get("light", false)) and int(data["spells"].get(id, {}).get("level", 9)) <= circle:
			ConditionRules.remove_effect(c, int(e["uid"]))
			lines.append("%s гаснет" % e["source"].get("name", ""))
	return lines


## The spell comes into the fight: a zone, or the first strike and the button for the next ones. Lines.
static func start_sustained(s: GameSession, data: Dictionary, spell_id: String, slot: int, target_id: String, lines: Array[String]) -> void:
	var me := CombatRules.caster(s)
	var sus := sustained(data, spell_id)
	var spell: Dictionary = data["spells"][spell_id]
	var dice := _dice(data, spell_id, slot)
	var t := CombatRules.aimed(s, target_id)
	if t.is_empty() and str(sus["kind"]) in ["attack", "heat"]:  # a touch: the foe beside the caster
		for id: String in CombatRules.foes_of(s, me):
			if FightGrid.touching(CombatRules.fighter(s, id), me):
				t = CombatRules.fighter(s, id)
				break
	var rounds := ConditionRules.spell_rounds(data, spell_id)
	var e := {"condition": "", "source": {"kind": "spell", "id": spell_id, "name": str(spell["name"])}, "by": str(me["id"]),
		"concentration": bool(spell.get("concentration", false)) and Sheet.is_hero(me), "ends": {"at": ConditionRules.now(s) + rounds} if rounds > 0 else {},
		"sustained": spell_id, "dice": dice, "target": str(t.get("id", "")), "dc": CombatRules.spell_dc(s), "attack": CombatRules.spell_attack(s),
		"ability": CombatRules.spell_ability(s)}
	if str(sus["kind"]) == "zone":
		if not s.combat.has("zones"):
			s.combat["zones"] = []
		var at := FightGrid.cell(me) if bool(sus.get("follow", false)) or t.is_empty() else CombatRules._aim_square(s, t)
		var shape: Dictionary = (sus.get("shape", spell.get("area", {"type": "sphere", "size": 5})) as Dictionary).duplicate()
		shape["size"] = int(shape.get("size", 5)) + int(sus.get("grow", 0)) * maxi(0, slot - int(spell["level"]))  # Fog Cloud: 20 ft a slot
		var zone := {"spell": spell_id, "name": str(spell["name"]), "shape": shape, "follow": bool(sus.get("follow", false)), "by": str(me["id"]), "side": str(me.get("side", "player")),
			"dice": dice, "type": str(sus.get("type", "")), "save": str(sus.get("save", "")), "on": sus.get("on", []), "dc": CombatRules.spell_dc(s),
			"slow": bool(sus.get("slow", false))}
		for k: String in ["cond", "obscure", "veil", "silence", "retch", "block_ranged", "spares_friends"]:
			if sus.has(k):
				zone[k] = sus[k]
		if not bool(spell.get("concentration", false)) and rounds > 0:  # Grease: a minute on the field
			zone["until_round"] = int(s.combat.get("round", 1)) + rounds
		_lay(s, data, zone, at)
		(s.combat["zones"] as Array).append(GameSession.whole(zone))
		lines.append("%s: %s" % [spell["name"], ("вокруг: " + str(me["name"])) if bool(sus.get("follow", false)) and not Sheet.is_hero(me) else "вокруг героя" if bool(sus.get("follow", false)) else "встаёт на поле"])
		if sus.has("douses"):
			lines.append_array(_douse(s, data, zone, int(sus["douses"])))
		if (zone["on"] as Array).has("now"):
			for fid: String in CombatRules.foes_of(s, me):
				if FightGrid.in_cells(CombatRules.fighter(s, fid), FightGrid.zone_cells(s, data, zone)):
					lines.append_array(_zone_hit(s, data, zone, CombatRules.fighter(s, fid)))
	if sus.has("cost"):
		ConditionRules.add_effect(Sheet.holder(s, me), GameSession.whole(e))
	if bool(sus.get("now", false)) and not t.is_empty():
		lines.append_array(_hit(s, data, spell_id, e, t))


## The buttons of the spells that go on each turn: [{id, name, cost, target, tip}].
static func actions(s: GameSession, data: Dictionary, f: Dictionary = Sheet.HERO) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Dictionary in hero_effects(Sheet.holder(s, f), "sustained"):
		var sus := sustained(data, str(e["sustained"]))
		if not sus.has("cost"):
			continue
		var fixed := str(sus["kind"]) == "heat"
		out.append({"id": "spell_" + str(e["sustained"]), "name": "%s: %s" % [e["source"]["name"], sus.get("label", "")], "cost": str(sus["cost"]),
			"target": not fixed, "tip": text(data, spec(data, str(e["sustained"])))})
	return out


## What keeps a spell going on `f`: the effect with its numbers, {} — none.
static func effect_of(s: GameSession, f: Dictionary, spell_id: String) -> Dictionary:
	for e: Dictionary in hero_effects(Sheet.holder(s, f), "sustained"):
		if str(e["sustained"]) == spell_id:
			return e
	return {}


## "" when `f` can go on with the sustained spell at `target_id` now.
static func can_act(s: GameSession, data: Dictionary, f: Dictionary, spell_id: String, target_id: String) -> String:
	var e := effect_of(s, f, spell_id)
	if e.is_empty():
		return "COMBAT_NO_FEATURE"
	var sus := sustained(data, spell_id)
	var t := CombatRules.fighter(s, target_id if str(sus["kind"]) != "heat" else str(e.get("target", "")))
	if t.is_empty() or str(t.get("status")) != "active":
		return "COMBAT_BAD_TARGET"
	var reach := 1 if str(sus["kind"]) == "attack" and spell_id == "vampiric_touch" else FightGrid.squares_of(data, int(data["spells"][spell_id].get("range_ft", 60)))
	if str(sus["kind"]) == "zone":
		reach = FightGrid.squares_of(data, int(sus.get("move", 30)))
		if WalkRules.distance(FightGrid.cell(t), _zone_of(s, spell_id, str(f["id"]))) > reach and not bool(sus.get("ram", false)):
			return "COMBAT_OUT_OF_RANGE"
		return ""
	if FightGrid.dist(t, f) > reach:
		return "COMBAT_OUT_OF_RANGE"
	return ""


static func _zone_of(s: GameSession, spell_id: String, by: String) -> Vector2i:
	for z: Dictionary in zones(s):
		if str(z["spell"]) == spell_id and str(z.get("by", CombatRules.PLAYER)) == by:
			return Vector2i(int(z["x"]), int(z["y"]))
	return Vector2i.ZERO


## The next strike, or the zone moved toward the target (the sphere strikes where it comes). Lines.
static func act(s: GameSession, data: Dictionary, f: Dictionary, spell_id: String, target_id: String) -> Array[String]:
	var e := effect_of(s, f, spell_id)
	var sus := sustained(data, spell_id)
	var lines: Array[String] = []
	var by := str(f["id"])
	if str(sus["kind"]) == "zone":
		for z: Dictionary in zones(s):
			if str(z["spell"]) != spell_id or str(z.get("by", CombatRules.PLAYER)) != by:
				continue
			var n := FightGrid.squares_of(data, int(sus.get("move", 30)))
			var from := Vector2i(int(z["x"]), int(z["y"]))
			var d := FightGrid.cell(CombatRules.fighter(s, target_id)) - from
			_lay(s, data, z, from + Vector2i(clampi(d.x, -n, n), clampi(d.y, -n, n)))
			lines.append("%s сдвигается" % z["name"])
			if bool(sus.get("ram", false)) or (z["on"] as Array).has("enter"):
				for fid: String in CombatRules.foes_of(s, f):
					var o := CombatRules.fighter(s, fid)
					if FightGrid.in_cells(o, FightGrid.zone_cells(s, data, z)):
						lines.append_array(_zone_hit(s, data, z, o))
		return lines
	var t := CombatRules.fighter(s, target_id if str(sus["kind"]) != "heat" else str(e.get("target", "")))
	if str(sus["kind"]) == "push":
		return _hit(s, data, spell_id, e, t)
	if str(sus["kind"]) == "strike":
		for fid: String in CombatRules.foes_of(s, f):
			var o := CombatRules.fighter(s, fid)
			if FightGrid.touching(o, t):
				lines.append_array(_save_hit(s, data, str(e["source"]["name"]), str(sus["type"]), str(sus.get("save", "dex")), str(e["dice"]),
					CombatRules.spell_dc(s), o, true, Sheet.is_hero(f)))
		return lines
	return _hit(s, data, spell_id, e, t)


## A strike of an attack / heat / strike spell of the caster at `t`. Lines.
static func _hit(s: GameSession, data: Dictionary, spell_id: String, e: Dictionary, t: Dictionary) -> Array[String]:
	var me := CombatRules.caster(s)
	var by_hero := Sheet.is_hero(me)
	var sus := sustained(data, spell_id)
	var name := str(e["source"]["name"])
	var lines: Array[String] = []
	match str(sus["kind"]):
		"attack":
			var ab := Sheet.ability_mod(s, data, me, CombatRules.spell_ability(s))
			var res := Attack.swing(s, data, me, t, Attack.of_spell(name, CombatRules.spell_attack(s), str(e["dice"]).replace("+MOD", ""),
				ab if str(e["dice"]).contains("MOD") else 0, str(sus["type"]), false, 5), lines)
			if bool(res["hit"]) and bool(sus.get("drain", false)):
				var it := Sheet.holder(s, me)
				var back := int(res["damage"]) / 2
				var was := int(it["hp"])
				it["hp"] = mini(int(it["max_hp"]), was + back)
				lines.append("%s: +%d HP" % [name, int(it["hp"]) - was])
		"heat":
			var dmg := Sheet.taken(s, data, t, str(sus["type"]), CombatRules.roll_dice(s.rng, str(e["dice"])))
			lines.append("%s: %s — %d (огонь)" % [name, t["name"], dmg])
			Harm.take(s, data, t, dmg, lines, str(sus["type"]), false, by_hero)
			if str(t.get("status")) == "active" and not Sheet.saved(s, data, t, "con", CombatRules.spell_dc(s), "magic"):
				CombatRules._hold(Sheet.holder(s, t), "mocked")  # the burning metal: disadvantage on its next attack
				lines.append("%s едва держит раскалённое — атака с помехой" % t["name"])
		"strike":
			for fid: String in CombatRules.foes_of(s, me):
				var f := CombatRules.fighter(s, fid)
				if FightGrid.touching(f, t):
					lines.append_array(_save_hit(s, data, name, str(sus["type"]), str(sus.get("save", "dex")), str(e["dice"]), CombatRules.spell_dc(s), f, true, by_hero))
		"push":  # Gust of Wind: the line toward the target, a STR save or 15 ft away
			var from := FightGrid.cell(me)
			var cells := FightGrid.area(s, data, {"type": "line", "size": int(sus.get("reach", 60))}, from, FightGrid.cell(t), true)
			for fid: String in CombatRules.foes_of(s, me):
				var f := CombatRules.fighter(s, fid)
				if not FightGrid.in_cells(f, cells):
					continue
				if Sheet.saved(s, data, f, str(sus.get("save", "str")), CombatRules.spell_dc(s), "magic"):
					lines.append("%s: %s устоял" % [name, f["name"]])
				else:
					FightField.thrust(s, data, f, FightGrid.cell(t) - from, 3, lines)
					lines.append("%s: %s отброшен на 15 фт" % [name, f["name"]])
	return lines


static func _save_hit(s: GameSession, data: Dictionary, name: String, dtype: String, save: String, dice: String, dc: int, f: Dictionary, half: bool, by_hero: bool = true) -> Array[String]:
	var lines: Array[String] = []
	if str(f.get("status")) != "active":
		return lines
	var dmg := CombatRules.roll_dice(s.rng, dice)
	var ok := not save.is_empty() and Sheet.saved(s, data, f, save, dc, "magic")
	if ok:
		dmg = dmg / 2 if half else 0
	dmg = Sheet.taken(s, data, f, dtype, dmg)
	lines.append("%s: %s — %s%d (%s)" % [name, f["name"], ("спасбросок %s %s, " % [CombatRules.ab_name(save), "успех" if ok else "провал"]) if not save.is_empty() else "",
		dmg, data["misc"]["damage_types"].get(dtype, dtype)])
	if dmg > 0:
		Harm.take(s, data, f, dmg, lines, dtype, false, by_hero)
	return lines


static func _zone_hit(s: GameSession, data: Dictionary, z: Dictionary, f: Dictionary) -> Array[String]:
	if not str(z["dice"]).is_empty():
		return _save_hit(s, data, str(z["name"]), str(z["type"]), str(z["save"]), str(z["dice"]), int(z["dc"]), f, true, str(z.get("by", CombatRules.PLAYER)) == CombatRules.PLAYER)
	var lines: Array[String] = []
	if str(f.get("status")) != "active" or str(z["save"]).is_empty():
		return lines
	var ok := Sheet.saved(s, data, f, str(z["save"]), int(z["dc"]), "magic")
	if ok:
		lines.append("%s: %s — спасбросок %s успех" % [z["name"], f["name"], CombatRules.ab_name(str(z["save"]))])
		return lines
	if z.has("cond") and not ConditionRules.has(Sheet.holder(s, f), str(z["cond"])):
		lines.append_array(CombatRules._add_condition(s, data, f, str(z["cond"]), {"name": str(z["name"]), "by": str(z.get("by", CombatRules.PLAYER))}))
		lines.append("%s: %s — %s" % [z["name"], f["name"], CombatRules.cond_name(data, str(z["cond"]))])
	if bool(z.get("retch", false)):
		f["retching"] = true  # its next start of a turn takes the action and says so (CombatRules._begin_turn)
	return lines


## `f` stands under Fog Cloud or Darkness: those inside see nothing out, nobody sees in.
static func obscured(s: GameSession, data: Dictionary, f: Dictionary) -> String:
	for z: Dictionary in zones(s):
		if bool(z.get("obscure", false)) and FightGrid.in_cells(f, FightGrid.zone_cells(s, data, z)):
			return str(z["name"])
	return ""


static func silenced(s: GameSession, data: Dictionary, f: Dictionary) -> bool:
	return zones(s).any(func(z: Dictionary) -> bool: return bool(z.get("silence", false)) and FightGrid.in_cells(f, FightGrid.zone_cells(s, data, z)))


## Wind Wall between a shooter and its target: the arrow misses. Its name, or "".
static func wall_between(s: GameSession, data: Dictionary, a: Dictionary, b: Dictionary) -> String:
	for z: Dictionary in zones(s):
		if bool(z.get("block_ranged", false)) and FightGrid.crosses(FightGrid.cell(a), FightGrid.cell(b), FightGrid.zone_cells(s, data, z)):
			return str(z["name"])
	return ""


## A minute of Grease is over: its zones leave the field. Lines.
static func zones_expire(s: GameSession) -> Array[String]:
	var lines: Array[String] = []
	for z: Dictionary in zones(s).duplicate():
		if z.has("until_round") and int(s.combat.get("round", 1)) > int(z["until_round"]):
			zones(s).erase(z)
			lines.append("%s исчезает" % z["name"])
	return lines


# --- curses on foes (v0.7.13.6) ------------------------------------------------------------------------


static func curse(data: Dictionary, spell_id: String) -> Dictionary:
	return spec(data, spell_id).get("curse", {})


## Faerie Fire, Ray of Enfeeblement, Bestow Curse, Slow: a save (or the ray's attack) and the flag on who failed. Lines.
static func cast_curse(s: GameSession, data: Dictionary, spell_id: String, slot: int, target: Dictionary, lines: Array[String]) -> void:
	var me := CombatRules.caster(s)
	var cu := curse(data, spell_id)
	var spell: Dictionary = data["spells"][spell_id]
	var name := str(spell["name"])
	var dc := CombatRules.spell_dc(s)
	var foes: Array[Dictionary] = [target]
	if bool(cu.get("area", false)) and picks(data, spell_id).is_empty():
		foes = []
		var cells := CombatRules.area_cells(s, data, spell, target)
		for id: String in CombatRules.foes_of(s, me):
			var f := CombatRules.fighter(s, id)
			if FightGrid.in_cells(f, cells) and foes.size() < int(cu.get("targets", 99)):
				foes.append(f)
	for f: Dictionary in foes:
		var it := Sheet.holder(s, f)
		var landed := false
		if bool(cu.get("attack", false)):
			var res := Attack.swing(s, data, me, f, Attack.of_spell(name, CombatRules.spell_attack(s), "0", 0, "force", false, int(spell.get("range_ft", 5))), lines)
			landed = bool(res["hit"])
		else:
			var ok := Sheet.saved(s, data, f, str(cu["save"]), dc, "magic")
			lines.append("%s: %s — спасбросок %s %s" % [name, f["name"], CombatRules.ab_name(str(cu["save"])), "успех" if ok else "провал"])
			landed = not ok
		if not landed:
			continue
		var flag := str(cu["flag"])
		if flag == "calmed" and Sheet.is_hero(f):  # the hero is no one's to stand down: charmed, by 5e it cannot strike its caster
			lines.append_array(CombatRules._add_condition(s, data, f, "charmed", {"rounds": ConditionRules.spell_rounds(data, spell_id), "spell": spell_id}))
			lines.append("%s опускает оружие — %s" % [f["name"], name])
			continue
		if flag == "calmed":  # Calm Emotions: no more fight in it (5e: indifferent)
			f["status"] = "truce"
			lines.append("%s опускает оружие — %s" % [f["name"], name])
			continue
		var e := {"condition": flag, "source": {"kind": "spell", "id": spell_id, "name": name}, "by": str(me["id"])}
		if not str(cu.get("repeat", "")).is_empty():
			e["save"] = {"ability": str(cu["repeat"]), "dc": dc, "repeat": true}
		if flag == "slowed_spell":
			e["ac_plus"] = -2
		ConditionRules.add_effect(it, e)
		if Sheet.is_hero(f):
			CharacterRules.refresh(it, data, s.items)
		lines.append("%s: %s" % [f["name"], FLAG_TEXT.get(flag, name)])


const FLAG_TEXT := {"outlined": "светится — атаки по нему с преимуществом", "enfeebled": "ослаблен — оружием вполсилы",
	"cursed_dis": "проклят — бьёт героя с помехой", "slowed_spell": "замедлен: КД −2, вдвое медленнее, одна атака, без реакций"}

## Anyone and the zones: `when` — start (of its turn), enter (a square it steps on; once a turn a zone), end. Lines.
static func zone_tick(s: GameSession, data: Dictionary, f: Dictionary, when: String) -> Array[String]:
	var lines: Array[String] = []
	if when == "start":
		f["zoned"] = []
	for z: Dictionary in zones(s):
		if str(f.get("status")) != "active" or not (z["on"] as Array).has(when) or not FightGrid.in_cells(f, FightGrid.zone_cells(s, data, z)):
			continue
		var friend := (str(f.get("side")) == "enemy") == (str(z.get("side", "player")) == "enemy")
		if friend and (bool(z.get("spares_friends", false)) or not bool(CombatRules.cfg(data)["friendly_fire"]["on"])):
			continue  # Spirit Guardians: the caster names who is spared (v0.7.50.1)
		if when == "enter" and (f.get("zoned", []) as Array).has(str(z["spell"])):
			continue
		if not f.has("zoned"):
			f["zoned"] = []
		(f["zoned"] as Array).append(str(z["spell"]))
		lines.append_array(_zone_hit(s, data, z, f))
	return lines


## The concentration (or the time) of `by` ends: the zones of the spell go.
static func end_zones(s: GameSession, spell_id: String, by: String = CombatRules.PLAYER) -> Array[String]:
	var lines: Array[String] = []
	for z: Dictionary in zones(s).duplicate():
		if str(z["spell"]) == spell_id and str(z.get("by", CombatRules.PLAYER)) == by:
			zones(s).erase(z)
			lines.append("%s гаснет" % z["name"])
	return lines


# --- reactions, dispel, charms (v0.7.13.7) ----------------------------------------------------------------


## A reaction spell the hero has ready with a slot for it: its lowest slot, 0 — none.
static func reaction_slot(c: Dictionary, data: Dictionary, spell_id: String) -> int:
	if not SpellRules.ready(c).has(spell_id):
		return 0
	return SpellRules.lowest_slot(c, data, spell_id)


## The reaction spells of the hero at a foe's hit (`when`: hit — before the damage, damage — after it).
static func hit_reactions(s: GameSession, data: Dictionary, ctx: Dictionary) -> Array[Dictionary]:
	var c := s.character
	var out: Array[Dictionary] = []
	if reaction_slot(c, data, "shield") > 0:
		var miss := int(ctx.get("total", 0)) < int(ctx.get("ac", 10)) + 5 and not bool(ctx.get("nat20", false))
		out.append({"id": "spell_shield", "label": "Щит: КД +5 до вашего хода%s" % (" — удар мимо" if miss else " (удар всё равно попадёт)")})
	for id: String in SpellRules.ready(c):
		if str(spec(data, id).get("reaction", "")) == "damage" and reaction_slot(c, data, id) > 0 and int(ctx.get("dmg", 0)) > 0:
			out.append({"id": "spell_" + id, "label": str(spec(data, id).get("label", data["spells"][id]["name"]))})
	return out


## Uses a reaction spell on a hit (the slot spent). Lines.
static func apply_hit_reaction(s: GameSession, data: Dictionary, f: Dictionary, id: String, ctx: Dictionary, lines: Array[String]) -> void:
	var c := s.character
	var spell_id := id.trim_prefix("spell_")
	var slot := reaction_slot(c, data, spell_id)
	SpellRules.cast(c, data, spell_id, slot, null, false)
	match spell_id:
		"shield":
			ConditionRules.add_effect(c, {"condition": "", "ac_plus": 5, "until_turn": true, "ends": {},
				"source": {"kind": "spell", "id": "shield", "name": str(data["spells"]["shield"]["name"])}})
			CharacterRules.refresh(c, data, s.items)
			ctx["ac"] = int(ctx["ac"]) + 5
			var still := int(ctx["total"]) >= int(ctx["ac"]) or bool(ctx.get("nat20", false))
			ctx["hit"] = still
			lines.append("%s: Щит — КД %d, %s" % [c.get("name", ""), int(c["ac"]), "удар всё же попадает" if still else "удар отскакивает"])
		_:
			ctx["rebuke"] = slot
			ctx["rebuke_spell"] = spell_id


## Hellish Rebuke after the damage: the attacker takes fire, a DEX save for half; `by`: one who is not the hero, with its numbers. Lines.
static func rebuke(s: GameSession, data: Dictionary, f: Dictionary, spell_id: String, slot: int, lines: Array[String], by: Dictionary = {}) -> void:
	var sp: Dictionary = data["spells"][spell_id]
	var hero := by.is_empty()
	var dice := CombatRules._spell_dice(sp, slot, int(s.character.get("level", 1)) if hero else int(by["level"]))
	var dc := int(s.character.get("spell_dc", 10)) if hero else int(by["dc"])  # its own DC: a foe's spell may be landing around this
	lines.append_array(_save_hit(s, data, str(sp["name"]), str(sp["damage_type"]), str(sp["save"]["ability"]), dice, dc, f,
		str(sp["save"].get("success", "half")) == "half", hero))


## The start of its turn: Shield's AC goes.
static func end_until_turn(s: GameSession, data: Dictionary, who: Dictionary = Sheet.HERO) -> void:
	var c := Sheet.holder(s, who)
	var gone := false
	for e: Dictionary in hero_effects(c, "until_turn").duplicate():
		ConditionRules.remove_effect(c, int(e["uid"]))
		gone = true
	if gone and Sheet.is_hero(who):
		CharacterRules.refresh(c, data, s.items)


## Counterspell at a foe's spell: "" when the hero cannot, else the option label.
static func counter_option(s: GameSession, data: Dictionary, f: Dictionary, spell_id: String) -> String:
	var c := s.character
	if bool(CombatRules.player(s).get("reacted", false)) or ConditionRules.incapacitated(c) or int(c.get("hp", 0)) <= 0:
		return ""
	if reaction_slot(c, data, "counterspell") <= 0 or FightGrid.feet(data, f, CombatRules.player(s)) > 60:
		return ""
	return "Контрзаклинание: сорвать «%s»" % data["spells"][spell_id]["name"]


## Counterspell: a spell of circle 3 or less fails; higher — the hero's check of the spellcasting ability, DC 10 +
## circle. True when the spell is stopped.
static func counter(s: GameSession, data: Dictionary, f: Dictionary, spell_id: String, circle: int, lines: Array[String]) -> bool:
	var c := s.character
	var slot := reaction_slot(c, data, "counterspell")
	SpellRules.cast(c, data, "counterspell", slot, null, false)
	CombatRules.player(s)["reacted"] = true
	var name := str(data["spells"][spell_id]["name"])
	if circle <= slot:
		lines.append("%s: Контрзаклинание — «%s» срывается" % [c.get("name", ""), name])
		return true
	var ab := str(c.get("spell_ability", "int"))
	var r := Roll.hero(s, data, {"what": "Контрзаклинание", "ability": ab, "dc": 10 + circle,
		"parts": [RollParts.part(RollParts.ability_name(ab), CharacterRules.mod(CharacterRules.ability(c, ab)))]})
	var ok := bool(r["ok"])
	lines.append("%s: Контрзаклинание — проверка %d против Сл %d — %s" % [c.get("name", ""), int(r["total"]), 10 + circle, "«%s» срывается" % name if ok else "не вышло"])
	return ok


## Dispel Magic: what the caster's foes laid on its side ends (only what `target_id` laid, when it names one of them).
static func dispel(s: GameSession, data: Dictionary, target_id: String) -> Array[String]:
	var me := CombatRules.caster(s)
	var lines: Array[String] = []
	for e: Dictionary in dispellable(s, me):
		if not CombatRules.foes_of(s, me).has(target_id) or str(e.get("by", "")) == target_id:
			ConditionRules.remove_effect(e["on"] as Dictionary, int(e["uid"]))
			lines.append("развеяно: %s" % e["source"].get("name", ""))
	if lines.is_empty():
		lines.append("развеивать нечего")
	CharacterRules.refresh(s.character, data, s.items)
	return lines


## The spells of `f`'s foes on its side: each effect with `on`, who carries it.
static func dispellable(s: GameSession, f: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var own := CombatRules.friends_of(s, f)
	for id: String in own:
		var h := Sheet.holder(s, CombatRules.fighter(s, id))
		for e: Dictionary in ConditionRules.effects(h):
			var by := str(e.get("by", ""))
			if str(e.get("source", {}).get("kind", "")) == "spell" and not by.is_empty() and not own.has(by):
				out.append(e.merged({"on": h}))
	return out


## Out of a fight: the NPC's save against the hero's spell (Suggestion, Charm Person…). {"ok": the spell holds,
## "line"} or {} when the spell is not of this kind.
static func npc_save(s: GameSession, data: Dictionary, spell_id: String, npc: Dictionary) -> Dictionary:
	var sp := spec(data, spell_id)
	if not bool(sp.get("npc_save", false)) or npc.is_empty():
		return {}
	var spell: Dictionary = data["spells"][spell_id]
	var tmpl: Dictionary = data["monsters"].get(str(npc.get("monster", data["rules"]["combat"]["default_npc_monster"])), {})
	var name := str(npc.get("name", ""))
	if sp.has("types") and not (sp["types"] as Array).has(str(tmpl.get("type", "humanoid"))):
		return {"ok": false, "line": "%s: на %s не действует" % [spell["name"], name]}
	var ab := str(spell.get("save", {}).get("ability", "wis"))
	var bonus := int(tmpl.get("saves", {}).get(ab, CharacterRules.mod(int(tmpl.get("abilities", {}).get(ab, 10)))))
	var roll := Roll.d20(s.rng)
	var dc := CombatRules.spell_dc(s)
	var saved := roll + bonus >= dc
	var save_parts: Array[Dictionary] = [RollParts.part("спасбросок %s (%s)" % [CombatRules.ab_name(ab), name], bonus)]
	RollParts.note(s, "%s: %s" % [spell["name"], name], [roll], roll, save_parts, bonus, dc)
	return {"ok": not saved, "line": "%s: %s — спасбросок %s %d против Сл %d — %s" % [spell["name"], name, CombatRules.ab_name(ab), roll + bonus, dc,
		"устоял" if saved else "поддался"]}


## The hero's charms on an NPC (v0.7.22.3, the author's request: Charm Person must end).
static func npc_spells(s: GameSession, npc_id: String) -> Array:
	return (Being.view(s, npc_id).get("effects", []) as Array).filter(func(e: Dictionary) -> bool: return e.has("charm"))


## A spell that held on the NPC (npc_save ok): it stays for its `minutes`.
static func charm_npc(s: GameSession, data: Dictionary, spell_id: String, npc_id: String) -> void:
	var b := Being.of(s, npc_id)
	_end_spell_on(b, spell_id)
	ConditionRules.add_effect(b, {"source": {"kind": "spell", "id": spell_id, "name": str(data["spells"][spell_id]["name"])}, "charm": true,
		"conc": bool(data["spells"][spell_id].get("concentration", false)),
		"ends": {"at": ConditionRules.now(s) + int(spec(data, spell_id).get("minutes", 60)) * ConditionRules.ROUNDS_PER_MINUTE}})


## The hero's charms on NPCs whose time is up or whose concentration is gone end; the NPC knows it was charmed
## (`aftermath` attitude). Runs before the statuses' own time out: called as time passes. Lines.
static func npc_expire(s: GameSession, data: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var now := ConditionRules.now(s)
	for npc_id: String in Being.with(s, "effects"):
		for e: Dictionary in npc_spells(s, npc_id):
			var spell_id := str(e["source"]["id"])
			var held := not bool(e.get("conc", false)) or str(s.character.get("concentration", "")) == spell_id
			if now < int(e["ends"]["at"]) and held and not Being.dead(s, npc_id):
				continue
			ConditionRules.remove_effect(Being.of(s, npc_id), int(e["uid"]))
			var who := str(data["world"]["npcs"].get(npc_id, {}).get("name", npc_id))
			var after := int(spec(data, spell_id).get("aftermath", 0))
			lines.append("«%s» спадает с %s%s" % [e["source"]["name"], who, " — понимает, что был(а) очарован(а)" if after != 0 else ""])
			if after != 0:
				s.shift_attitude(npc_id, after, data)
				s.remember(npc_id, "понял(а), что герой очаровал(а) его/её заклинанием «%s»" % e["source"]["name"])
		ConditionRules.tidy(Being.of(s, npc_id))
	return lines


## For the snapshot: «Очарование личности — до 10:35».
static func npc_spell_text(s: GameSession, npc_id: String) -> String:
	return ", ".join(npc_spells(s, npc_id).map(func(e: Dictionary) -> String:
		var m := (int(e["ends"]["at"]) / ConditionRules.ROUNDS_PER_MINUTE) % 1440
		return "%s — до %02d:%02d" % [e["source"]["name"], m / 60, m % 60]))


# --- the world (v0.7.13.8) -----------------------------------------------------------------------------


## Find Traps, Detect Magic, Knock in the hero's room: what they find or open. Lines.
static func world_spell(s: GameSession, data: Dictionary, spell_id: String) -> Array[String]:
	var sp := spec(data, spell_id)
	var world: Dictionary = data["world"]
	var lines: Array[String] = []
	var room := s.room_id
	match str(sp.get("reveal", "knock" if sp.has("knock") else "")):
		"trap":
			for sec: Dictionary in ExplorationRules.secrets(world, room):
				if sec.get("trap") is Dictionary and ExplorationRules._reveal(s, room, sec):
					lines.append("ловушка: " + str(sec["text"]))
			if lines.is_empty():
				lines.append("ловушек здесь нет")
		"magic":
			for sec: Dictionary in ExplorationRules.secrets(world, room):
				var magic := (sec.get("loot", {}).get("items", {}) as Dictionary).keys().any(func(id: Variant) -> bool:
					return ItemRules.needs_identify(ItemRules.def_of(data["items"], s.items, str(id))))
				if magic and ExplorationRules._reveal(s, room, sec):
					lines.append("аура магии: " + str(sec["text"]))
			lines.append_array(ExplorationRules.take_caches(s, data, room))
			for id: String in ItemRules.unknown_ids(s.character):
				lines.append("от «%s» веет магией" % ItemRules.display_name(data["items"], s.items, id))
			if lines.is_empty():
				lines.append("магии рядом не чувствуется")
		"knock":
			for p: Dictionary in PropRules.room_props(s, room):
				if str(p.get("state", "")) == "closed":
					p["state"] = "open"
					lines.append("открылось: %s" % p.get("name", ""))
			for e: String in WayRules.open_exits(s, world, room):  # the doors of the room too (v0.7.22.25)
				if WayRules.blocked(s, data, room, e) in ["DOOR_LOCKED", "DOOR_CLOSED_HOURS", "DOOR_ARCANE", "DOOR_PRIVATE"]:
					WayRules.spell(s, data, room, e, spell_id)
					lines.append("открылась дверь: %s" % WorldView.new(world).room(e).get("name", e))
			lines.append("громкий стук разносится вокруг" if not lines.is_empty() else "запертого рядом нет — только громкий стук")
	return lines
