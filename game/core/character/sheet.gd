class_name Sheet
extends RefCounted
## One sheet for everybody (v0.8.4.6, ADR-0016): the hero, a person of the pack, a foe, a summoned creature. `who` is any
## dictionary that names a character: a fighter, a record, an NPC of the pack, an encounter's head, or Sheet.HERO. The hero
## reads its own sheet, the others one made from their SRD template; the rules ask here and do not ask who it is. What
## belongs to the player, not to the character, stays behind `hero`: the game's difficulty and the roll's breakdown.

const HERO := {"id": Being.HERO}


static func is_hero(who: Dictionary) -> bool:
	return str(who.get("id")) == Being.HERO


## The id of its SRD template; "" for the hero.
static func template_id(data: Dictionary, who: Dictionary) -> String:
	if is_hero(who):
		return ""
	return str(Guise.body(who).get("monster", who.get("monster", CombatRules.cfg(data)["default_npc_monster"])))


## Its SRD template, {} for the hero; a fighter that lost its weapon has only the actions left to it (v0.7.22.8).
static func template(data: Dictionary, who: Dictionary) -> Dictionary:
	var m: Dictionary = data["monsters"].get(template_id(data, who), {})
	if who.has("actions") and not m.is_empty():
		m = m.duplicate()
		m["actions"] = who["actions"]
	return m


## Its sheet in the hero's form: abilities, saves, skills, passive_perception, prof_bonus. For reading: only the hero's
## is kept, the others come from the template.
static func of(s: GameSession, data: Dictionary, who: Dictionary) -> Dictionary:
	if is_hero(who):
		return s.character
	var m := template(data, who)
	var ab: Dictionary = m.get("abilities", {})
	var saves := {}
	for id: String in CharacterRules.ABILITIES:
		saves[id] = int(m.get("saves", {}).get(id, CharacterRules.mod(int(ab.get(id, 10)))))
	var skills := {}
	for id: String in data["rules"]["skills"]:
		skills[id] = int(m.get("skills", {}).get(id, CharacterRules.mod(int(ab.get(str(data["rules"]["skills"][id]), 10)))))
	return {"abilities": ab, "saves": saves, "skills": skills, "prof_bonus": int(m.get("prof", 2)),
		"passive_perception": int(m.get("passive_perception", 10 + int(skills["perception"])))}


## `who` of an id, for reading (v0.8.4.12): the hero, its fighter in a fight, else its record with the id and the template
## it is of (a creature's, a person's of the pack). Nothing is written.
static func who(s: GameSession, data: Dictionary, id: String) -> Dictionary:
	if id == Being.HERO:
		return HERO
	var b := Being.view(s, id)
	if b.has("fight"):
		return b["fight"]
	var out := b.duplicate()
	out["id"] = id
	if not out.has("monster"):
		var cr: Dictionary = b.get("creature", {})
		out["monster"] = str(cr.get("monster", data["world"]["npcs"].get(id, {}).get("monster", CombatRules.cfg(data)["default_npc_monster"])))
	return out


## The one it is: the hero's sheet, or the fighter or record itself. Statuses live on this.
static func holder(s: GameSession, who: Dictionary) -> Dictionary:
	return s.character if is_hero(who) else who


static func skill(s: GameSession, data: Dictionary, who: Dictionary, id: String) -> int:
	return int(of(s, data, who)["skills"].get(id, 0))


static func ability_mod(s: GameSession, data: Dictionary, who: Dictionary, id: String) -> int:
	if is_hero(who):
		return CharacterRules.mod(CharacterRules.ability(s.character, id))
	return CharacterRules.mod(int(of(s, data, who)["abilities"].get(id, 10)))


static func save_bonus(s: GameSession, data: Dictionary, who: Dictionary, ab: String) -> int:
	return int(of(s, data, who)["saves"].get(ab, 0))


## What it notices without looking: keen senses count, the hero's sneaking, darkness it does not see in and the weather
## too (one road, v0.8.4.12).
static func passive(s: GameSession, data: Dictionary, who: Dictionary) -> int:
	var v := int(of(s, data, who)["passive_perception"]) - TimeRules.passive_penalty(s, data, who)
	return v if is_hero(who) else v + MonsterRules.passive_bonus(data, who)


## The AC it stands with now: its armour, its statuses, the cover of this moment.
static func ac(s: GameSession, who: Dictionary) -> int:
	if is_hero(who):
		return int(s.character.get("ac", 10)) + (int(CombatRules.player(s).get("cover", 0)) if CombatRules.active(s) else 0)
	return CombatRules.ac_of(who)


## A feature of a class, a trait of a race or of a template: what it has whoever it is.
static func has_trait(s: GameSession, data: Dictionary, who: Dictionary, id: String) -> bool:
	if is_hero(who):
		return CharacterRules.has_feature(s.character, id) or CharacterRules.has_trait(s.character, id)
	return MonsterRules.has_trait(data, who, id)


static func size(s: GameSession, data: Dictionary, who: Dictionary) -> String:
	return CombatRules.hero_size(s, data) if is_hero(who) else str(template(data, who).get("size", "medium"))


## Its way in a turn in feet now, by the fastest of `Move`; a Slow halves it.
static func speed(s: GameSession, data: Dictionary, who: Dictionary) -> int:
	var ft := int(s.character.get("speed", 30))
	if is_hero(who):
		ft -= int(CombatRules.player(s).get("slowed", 0)) if CombatRules.active(s) else 0
	else:
		ft = Move.feet(s, data, who) - int(who.get("slowed", 0)) + ConditionRules.sum(who, "speed")
	return ft / 2 if ConditionRules.has(holder(s, who), "slowed_spell") else ft


## A saving throw of anyone: its bonus, the statuses, the advantages of its race, traits and spells against `tag` (the
## tags joined by a comma: «charm,magic»), cover on DEX, a spell's die. Natural 20 / 1 succeed / fail.
## {"ok", "total", "nat", "text"}: «Тел 14 против Сл 13, с преимуществом (Стойкость дварфа) — успех».
static func save(s: GameSession, data: Dictionary, who: Dictionary, ab: String, dc: int, tag: String = "", dis_extra := false) -> Dictionary:
	var hero := is_hero(who)
	var me := holder(s, who)
	var mods := ConditionRules.check_mods(me, data, {"save": ab})
	var why := _advantages(s, data, who, ab, tag)
	var adv := not why.is_empty()
	var dis := not (mods["disadvantage"] as Array).is_empty() or dis_extra
	var rolls := Roll.of(s, who, adv, dis)
	var nat := Roll.kept(rolls, adv, dis)
	var die := SpellEffects.die(s, me, "save")  # Bless, Bane, Resistance (v0.7.13.1)
	var fighter := CombatRules.player(s) if hero and CombatRules.active(s) else who
	var total := nat + save_bonus(s, data, who, ab) + int(die["bonus"])
	if ab == "dex":
		total += int(fighter.get("cover", 0))  # v0.8.4
	var parts: Array[Dictionary] = []
	if hero:
		parts = RollParts.cached(me, data, "save", ab, s.items)
	parts.append_array(die["parts"])
	if hero:
		total += DifficultyRules.bonus(s, data)  # the game's difficulty (v0.7.20.4)
		RollParts.difficulty(s, data, parts)
	var ok := Roll.succeeds(nat, total, dc)
	var note := (" " + str(die["note"])) if not str(die["note"]).is_empty() else ""
	if hero and DifficultyRules.bonus(s, data) != 0:
		note += ", " + DifficultyRules.note(s, data)
	if hero and not ok and nat != 1 and (mods["auto_fail"] as Array).is_empty():
		var insp := Roll.inspire(s)  # Bardic Inspiration on a failed save
		if int(insp["value"]) > 0:
			total += int(insp["value"])
			ok = total >= dc
			note += ", вдохновение +%d" % int(insp["value"])
			RollParts.add(parts, str(insp["label"]), int(insp["value"]))
	if not (mods["auto_fail"] as Array).is_empty():
		ok = false
		note += ", автопровал: " + ", ".join((mods["auto_fail"] as Array).map(func(x: Variant) -> String: return ConditionRules.name_of(data, str(x)).to_lower()))
	elif adv and not dis:
		note += ", с преимуществом (%s)" % ", ".join(why)
	elif dis and not adv:
		note += ", с помехой (%s)" % ", ".join((mods["disadvantage"] as Array).map(func(x: Variant) -> String:
			return "истощение" if str(x) == "exhaustion" else ConditionRules.name_of(data, str(x)).to_lower()))
	if hero:
		RollParts.note(s, "Спасбросок: " + CombatRules.ab_name(ab), rolls, nat, parts, total - nat, dc)
	return {"ok": ok, "total": total, "nat": nat,
		"text": "%s %d против Сл %d%s — %s" % [CombatRules.ab_name(ab), total, dc, note, "успех" if ok else "провал"]}


static func saved(s: GameSession, data: Dictionary, who: Dictionary, ab: String, dc: int, tag: String = "", dis_extra := false) -> bool:
	return bool(save(s, data, who, ab, dc, tag, dis_extra)["ok"])


## Why it has advantage on this save: names for the line, an empty list when none.
static func _advantages(s: GameSession, data: Dictionary, who: Dictionary, ab: String, tag: String) -> Array[String]:
	var me := holder(s, who)
	var out := HeroDefense.save_advantages(me, data, ab, tag, raging(s, who))
	if MonsterRules.save_advantage(data, me, ab, Array(tag.split(",", false))) or (not is_hero(who) and SpellEffects.boon_save_adv(who, ab)):
		out.append("черта")
	return out


## In a Rage now.
static func raging(s: GameSession, who: Dictionary) -> bool:
	return CombatRules.active(s) and bool((CombatRules.player(s) if is_hero(who) else who).get("raging", false))


## What of `dtype` it takes: {"immune": why, "resist": why, "vulnerable": why}, a key only when it holds.
static func defenses(s: GameSession, data: Dictionary, who: Dictionary, dtype: String, magical: bool, silvered: bool) -> Dictionary:
	var out := {}
	var res := HeroDefense.resistances(s, data, who)
	if res.has(dtype):
		out["resist"] = str(res[dtype])
	if is_hero(who):
		return out
	var m := template(data, who)
	for list: String in ["immunities", "resistances", "vulnerabilities"]:
		for x: Variant in m.get(list, []):
			var text := str(x).to_lower()
			if text.contains(dtype) and not (text.contains("nonmagical") and magical) and not (text.contains("silvered") and silvered):
				out[{"immunities": "immune", "resistances": "resist", "vulnerabilities": "vulnerable"}[list]] = str(x)
	if ConditionRules.resisted(who, dtype):  # the spells on it (v0.7.50.1)
		out["resist"] = dtype
	return out


## Damage of one type after its defenses: {"damage", "note"} («сопротивление: Ярость» or "").
static func damage(s: GameSession, data: Dictionary, who: Dictionary, dtype: String, dmg: int, magical := true, silvered := false) -> Dictionary:
	if dmg <= 0:
		return {"damage": maxi(0, dmg), "note": ""}
	var d := defenses(s, data, who, dtype, magical, silvered) if not dtype.is_empty() else {}
	if d.has("immune"):
		return {"damage": 0, "note": "иммунитет"}
	if ConditionRules.does(holder(s, who), data, "resist_all"):
		return {"damage": dmg / 2, "note": "сопротивление: окаменение"}
	if d.has("resist"):
		return {"damage": dmg / 2, "note": "сопротивление: %s" % d["resist"]}
	if d.has("vulnerable"):
		return {"damage": dmg * 2, "note": "уязвимость"}
	return {"damage": dmg, "note": ""}


static func taken(s: GameSession, data: Dictionary, who: Dictionary, dtype: String, dmg: int, magical := true, silvered := false) -> int:
	return int(damage(s, data, who, dtype, dmg, magical, silvered)["damage"])
