class_name Sheet
extends RefCounted
## One sheet for everybody (v0.8.4.6, ADR-0016): the hero, a person of the pack, a foe, a summoned creature. `who` is any
## dictionary that names a character: a fighter, a record, an NPC of the pack, an encounter's head, or Sheet.HERO. The hero
## reads its own sheet, the others one made from their SRD template; the rules ask here and do not ask who it is. What
## belongs to the player, not to the character, stays behind `hero`: the game's difficulty and the roll's breakdown.

const HERO := {"id": Being.HERO}


static func is_hero(who: Dictionary) -> bool:
	return str(who.get("id")) == Being.HERO


## The id of its SRD template; "" for the hero. A fighter's or a look's own, a creature's of its part, a person's of the
## pack, else the default person.
static func template_id(data: Dictionary, who: Dictionary) -> String:
	if is_hero(who):
		return ""
	var m := str(Guise.body(who).get("monster", who.get("monster", "")))
	if m.is_empty():
		m = str((who.get("creature", {}) as Dictionary).get("monster", ""))
	if m.is_empty():
		m = str(data["world"].get("npcs", {}).get(str(who.get("npc_id", who.get("id", ""))), {}).get("monster", ""))
	return m if not m.is_empty() else str(CombatRules.cfg(data)["default_npc_monster"])


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
	var learned: Array = who.get("skill_profs", [])  # what a person learned (v0.8.4.20: a course, a book)
	for id: String in data["rules"]["skills"]:
		skills[id] = int(m.get("skills", {}).get(id, CharacterRules.mod(int(ab.get(str(data["rules"]["skills"][id]), 10)))))
		if learned.has(id):
			skills[id] = maxi(int(skills[id]), CharacterRules.mod(int(ab.get(str(data["rules"]["skills"][id]), 10))) + int(m.get("prof", 2)))
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


## `who` of an id for writing (v0.8.4.15): the hero, its fighter in a fight, else its record knowing its id.
static func own(s: GameSession, id: String) -> Dictionary:
	if id == Being.HERO:
		return HERO
	var h := Rest.holder(s, id)
	h["id"] = id
	return h


## Its hit point maximum now: the hero's sheet, a fighter's own (halved when exhaustion 4 came on it), a record's or its
## creature's, else its template's — a record's halved at exhaustion 4 (v0.8.4.15).
static func max_hp(s: GameSession, data: Dictionary, who: Dictionary) -> int:
	if is_hero(who):
		return int(s.character.get("max_hp", 1))
	var h := holder(s, who)
	if h.has("status"):
		return int(h.get("max_hp", 1))
	var top := int(h.get("max_hp", (h.get("creature", {}) as Dictionary).get("max_hp", template(data, who).get("hp", 1))))
	return maxi(1, top / 2) if ConditionRules.exhaustion(h) >= 4 else top


## The one it is: the hero's sheet, or the fighter or record itself. Statuses live on this.
static func holder(s: GameSession, who: Dictionary) -> Dictionary:
	return s.character if is_hero(who) else who


## What it has on it in the hero's form (v0.8.4.15): the hero's sheet, a fighter's own things, a record's, else its
## template's gear. Nothing is filled: a look does not roll a person's pockets.
static func things(s: GameSession, data: Dictionary, who: Dictionary) -> Dictionary:
	if is_hero(who):
		return s.character
	if who.has("inventory"):
		return who
	var id := str(who.get("npc_id", who.get("id", "")))
	if Being.view(s, id).has("inventory"):
		return Being.view(s, id)
	return Gear.start(data, template_id(data, who))


## The things that work on it now: worn, held, carried, attuned when they need it (CharacterRules.working).
static func working(s: GameSession, data: Dictionary, who: Dictionary) -> Array[Dictionary]:
	return CharacterRules.working(things(s, data, who), data, s.items)


## The properties its things give now: the hero's sheet keeps them, anybody else's are read off what it has.
static func props(s: GameSession, data: Dictionary, who: Dictionary) -> Array:
	if is_hero(who):
		return s.character.get("item_props", [])
	return CharacterRules.active_props(things(s, data, who), data, s.items)


## A thing on it gives `prop` now (adamantine against a critical hit, Gloves of Missile Snaring, Periapt of Health).
static func prop(s: GameSession, data: Dictionary, who: Dictionary, p: String) -> bool:
	return props(s, data, who).has(p)


## A score of an ability: the hero's with what its things raise it to, another's by its template.
static func ability(s: GameSession, data: Dictionary, who: Dictionary, id: String) -> int:
	if is_hero(who):
		return CharacterRules.ability(s.character, id)
	return int(of(s, data, who)["abilities"].get(id, 10))


## Its proficiency bonus.
static func prof(s: GameSession, data: Dictionary, who: Dictionary) -> int:
	return int(of(s, data, who).get("prof_bonus", 2))


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


## Its way in a turn in feet now, by the fastest of `Move`; a Slow halves it. Anybody's as the hero's sheet counts it
## (v0.8.4.15): Longstrider, Haste, grappled or restrained — 0, exhaustion 2 — half, 5 — 0.
static func speed(s: GameSession, data: Dictionary, who: Dictionary) -> int:
	var ft := int(s.character.get("speed", 30))
	var me := holder(s, who)
	if is_hero(who):
		ft -= int(CombatRules.player(s).get("slowed", 0)) if CombatRules.active(s) else 0
	else:
		ft = Move.feet(s, data, who) + ConditionRules.sum(who, "speed")
		if SpellEffects.has(me, "speed_x2"):
			ft *= 2
		var tired := ConditionRules.exhaustion(me)
		if tired >= 5 or ConditionRules.does(me, data, "no_move"):
			return 0
		ft = ft / 2 if tired >= 2 else ft
		ft -= int(who.get("slowed", 0))
	return ft / 2 if ConditionRules.has(me, "slowed_spell") else ft


## A saving throw of anyone: its bonus, the statuses, the advantages of its race, traits and spells against `tag` (the
## tags joined by a comma: «charm,magic»), cover on DEX, a spell's die. Natural 20 / 1 succeed / fail. `opts` — the
## caller's reasons `adv_why`, `dis_why`, `fail_why` (the master's save, Roll.check) and `quiet` (a card is its own breakdown).
## {"ok", "total", "nat", "rolls", "bonus", "parts", "adv", "dis", "fail": [why], "text"}:
## «Тел 14 против Сл 13, с преимуществом (Стойкость дварфа) — успех».
static func save(s: GameSession, data: Dictionary, who: Dictionary, ab: String, dc: int, tag: String = "", dis_extra := false, opts: Dictionary = {}) -> Dictionary:
	var hero := is_hero(who)
	var me := holder(s, who)
	var at := _save_situation(s, data, who, ab, tag, dis_extra, opts)
	var adv := not (at["adv"] as Array).is_empty()
	var dis := not (at["dis"] as Array).is_empty()
	var failed := not (at["fail"] as Array).is_empty()
	var rolls := Roll.of(s, who, adv, dis)
	var nat := Roll.kept(rolls, adv, dis)
	var die := SpellEffects.die(s, me, "save")  # Bless, Bane, Resistance (v0.7.13.1)
	var parts := _save_parts(s, data, who, ab)
	parts.append_array(die["parts"])
	var total := nat + RollParts.sum(parts)
	var ok := Roll.succeeds(nat, total, dc)
	var note := (" " + str(die["note"])) if not str(die["note"]).is_empty() else ""
	if hero and DifficultyRules.bonus(s, data) != 0:
		note += ", " + DifficultyRules.note(s, data)
	if not ok and nat != 1 and not failed:
		var insp := Roll.inspire(s, who)  # Bardic Inspiration on a failed save
		if int(insp["value"]) > 0:
			total += int(insp["value"])
			ok = total >= dc
			note += ", вдохновение +%d" % int(insp["value"])
			RollParts.add(parts, str(insp["label"]), int(insp["value"]))
	if failed:
		ok = false
		note += ", автопровал: " + ", ".join(at["fail"])
	elif adv and not dis:
		note += ", с преимуществом (%s)" % ", ".join(at["adv"])
	elif dis and not adv:
		note += ", с помехой (%s)" % ", ".join(at["dis"])
	if hero and not bool(opts.get("quiet", false)):
		RollParts.note(s, "Спасбросок: " + CombatRules.ab_name(ab), rolls, nat, parts, total - nat, dc)
	return {"ok": ok, "total": total, "nat": nat, "rolls": rolls, "bonus": total - nat, "parts": parts,
		"adv": at["adv"], "dis": at["dis"], "fail": at["fail"],
		"text": "%s %d против Сл %d%s — %s" % [CombatRules.ab_name(ab), total, dc, note, "успех" if ok else "провал"]}


## A save's bonus and what it rolls with, nothing rolled or spent (Roll.odds): {bonus, adv, dis, failed}.
static func save_odds(s: GameSession, data: Dictionary, who: Dictionary, ab: String, tag: String = "", opts: Dictionary = {}) -> Dictionary:
	var at := _save_situation(s, data, who, ab, tag, bool(opts.get("dis", false)), opts)
	var parts := _save_parts(s, data, who, ab)
	parts.append_array(SpellEffects.die(s, holder(s, who), "save", true)["parts"])
	return {"bonus": RollParts.sum(parts), "adv": not (at["adv"] as Array).is_empty(), "dis": not (at["dis"] as Array).is_empty(),
		"failed": not (at["fail"] as Array).is_empty()}


## What a save of `who` rolls with: {adv, dis, fail: [why]} of its statuses, traits and the caller's reasons.
static func _save_situation(s: GameSession, data: Dictionary, who: Dictionary, ab: String, tag: String, dis_extra: bool, opts: Dictionary) -> Dictionary:
	var mods := ConditionRules.check_mods(holder(s, who), data, {"save": ab})
	var adv := _advantages(s, data, who, ab, tag)
	var dis: Array[String] = []
	var fail: Array[String] = []
	for id: Variant in mods["disadvantage"]:
		dis.append(ConditionRules.why(data, str(id)))
	for id: Variant in mods["auto_fail"]:
		fail.append(ConditionRules.why(data, str(id)))
	if dis_extra:
		dis.append("обстоятельства")
	for k: String in ["adv_why", "dis_why", "fail_why"]:
		for x: String in CheckEngine.whys(opts.get(k)):  # a text or a list
			({"adv_why": adv, "dis_why": dis, "fail_why": fail}[k] as Array).append(x)
	return {"adv": adv, "dis": dis, "fail": fail}


## The labelled bonus of a save: the hero's sheet with the game's difficulty and the cover on DEX; another's number.
static func _save_parts(s: GameSession, data: Dictionary, who: Dictionary, ab: String) -> Array[Dictionary]:
	var parts: Array[Dictionary] = []
	if is_hero(who):
		parts = RollParts.cached(s.character, data, "save", ab, s.items)
		RollParts.difficulty(s, data, parts)  # the game's difficulty (v0.7.20.4)
	else:
		parts.append(RollParts.part(CombatRules.ab_name(ab), save_bonus(s, data, who, ab)))
	var fighter := CombatRules.player(s) if is_hero(who) and CombatRules.active(s) else who
	if ab == "dex":
		RollParts.add(parts, "укрытие", int(fighter.get("cover", 0)))  # v0.8.4
	return parts


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
