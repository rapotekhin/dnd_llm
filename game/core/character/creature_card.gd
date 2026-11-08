class_name CreatureCard
extends RefCounted
## The card of any creature (v0.8.4.41, the author: as in BG3 and Pathfinder) — a person of the pack or the master's, a
## monster, a follower, a summoned ally, the hero, in a fight and out of it. One reader over the rules' own roads: the
## numbers by `Sheet`, the statuses by `ConditionRules.shown`, the things by `Sheet.things` (the reading face of `Gear.of`:
## a look rolls no pockets), the defenses by `Sheet.defenses` and `HeroDefense.immune`, the blows by what it holds now
## (`Gear.actions`). What the hero does not know of its kind stays hidden: one road of knowledge — the check
## `CombatRules.look_over` opens a kind for good (`Knows.MONSTER`), one of the hero's side is seen whole (`CombatRules.known`).
## Data, not nodes: the window `CreatureCardPanel` draws it, `text` makes the lines of a fight's hover.

## What a hidden number shows.
const HIDDEN := "?"


## The card of `who` (a fighter, a record by `Sheet.who`, an encounter's head, `Sheet.HERO`). Always seen: the name, its size
## and kind, its health in a word, what it wears and the statuses on it. Known: the numbers, the blows, the abilities, the
## spells and the defenses; else `lore` — the knowledge check that would open them.
static func of(s: GameSession, data: Dictionary, who: Dictionary) -> Dictionary:
	var m := Sheet.template(data, who)
	var hp := Sheet.hp(s, data, who)
	var top := Sheet.max_hp(s, data, who)
	var known := CombatRules.known(s, who)
	var out := {"id": str(who.get("id", "")), "name": name_of(s, data, who), "known": known, "size": Sheet.size(s, data, who),
		"type": str(m.get("type", "humanoid")), "health": CombatRules.health_key({"status": _state(who), "hp": hp, "max_hp": top}),
		"worn": worn(s, data, who), "statuses": ConditionRules.shown(s, data, who)}
	if not known:
		out["lore"] = {"skill": CombatRules.lore_skill(data, who), "dc": CombatRules.lore_dc(data, who)}
		return out
	var me := _holder(s, data, who)
	out.merge({"hp": hp, "max_hp": top, "temp_hp": int(Sheet.holder(s, who).get("temp_hp", 0)), "ac": Sheet.ac(s, who, data),
		"speed": Sheet.speed(s, data, who), "ways": ways(s, data, who), "passive": Sheet.passive(s, data, who), "prof": Sheet.prof(s, data, who),
		"cr": m.get("cr", null), "abilities": abilities(s, data, who), "saves": saves(s, data, who), "skills": skills(s, data, who),
		"languages": LanguageRules.of(s, data, who).map(func(l: String) -> String: return LanguageRules.name_of(data, l)),
		"blows": blows(s, data, who).map(func(a: Dictionary) -> Dictionary:
			return {"name": str(a.get("name", "")), "text": blow_text(data, a), "stowed": bool(a.get("stowed", false))}),
		"reactions": reactions(m), "features": features(data, m, me), "resources": Stock.lines(me, data),
		"spells": spells(data, m, me), "defenses": defenses(s, data, who)})
	return out


## The lines of a known card for a fight's hover (the list of a fight, the foe before it): its numbers, blows, spells,
## reactions, defenses and traits. "" for one not known.
static func text(s: GameSession, data: Dictionary, who: Dictionary) -> String:
	if not CombatRules.known(s, who):
		return ""
	var c := of(s, data, who)
	var lines: Array[String] = ["%s · HP %d/%d · КД %d · скорость %s" % [c["name"], int(c["hp"]), int(c["max_hp"]), int(c["ac"]), speed_text(c)]]
	for b: Dictionary in c["blows"]:
		lines.append("%s: %s" % [b["name"], b["text"]])
	var sp: Dictionary = c["spells"]
	if not (sp["list"] as Array).is_empty():
		lines.append("Заклинания%s: %s" % [(" (Сл %d)" % int(sp["dc"])) if int(sp["dc"]) > 0 else "", ", ".join(sp["list"])])
	if not (sp["slots"] as Array).is_empty():  # what is left of its slots (big test #21, v0.7.22.4)
		lines.append("Ячейки: " + " · ".join((sp["slots"] as Array).map(func(x: Dictionary) -> String:
			return "%d круг %d/%d" % [int(x["circle"]), int(x["left"]), int(x["max"])])))
	for r: String in c["reactions"]:
		lines.append("Реакция: " + r)
	for d: Dictionary in c["defenses"]:
		lines.append("%s: %s" % [d["word"], d["what"]])
	for f: Dictionary in c["features"]:
		if str(f["kind"]) == "trait":
			lines.append("%s: %s" % [f["name"], str(f["text"]).left(160)])
	return "\n".join(lines)


## Its name: a fighter's or a record's own, a creature's, a person's of the world, else its template's.
static func name_of(s: GameSession, data: Dictionary, who: Dictionary) -> String:
	if Sheet.is_hero(who):
		return str(s.character.get("name", ""))
	if not str(who.get("name", "")).is_empty():
		return str(who["name"])
	var cr: Dictionary = who.get("creature", {})
	if not str(cr.get("name", "")).is_empty():
		return str(cr["name"])
	var id := str(who.get("npc_id", who.get("id", "")))
	var named := WorldView.name_of(data, id)
	return named if named != id else str(Sheet.template(data, who).get("name", id))


## The state that names its health: a fighter's status, a creature's state, else active.
static func _state(who: Dictionary) -> String:
	if who.has("status"):
		return str(who["status"])
	var st := str((who.get("creature", {}) as Dictionary).get("state", ""))
	return st if st in [CreatureRules.DEAD, "surrendered", "truce", "unconscious"] else "active"


## The holder of its features, charges and slots: its own when it has a class laid (the hero, a fighter), else a copy
## with what its class and race would give it in a fight (FeatureRules.give_class) — nothing is written.
static func _holder(s: GameSession, data: Dictionary, who: Dictionary) -> Dictionary:
	var me := Sheet.holder(s, who)
	if Sheet.is_hero(who) or who.has("side") or me.has("features") or me.has("traits") or not who.has("monster"):
		return me
	var probe := who.duplicate(true)
	FeatureRules.give_class(data, probe, {"npc_id": str(who.get("npc_id", who.get("id", "")))})
	return probe


# --- the numbers ----------------------------------------------------------------------------------------------------


## [{id, score, mod}] of the six abilities.
static func abilities(s: GameSession, data: Dictionary, who: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for ab: String in CharacterRules.ABILITIES:
		out.append({"id": ab, "score": Sheet.ability(s, data, who, ab), "mod": Sheet.ability_mod(s, data, who, ab)})
	return out


## [{id, bonus, adv, dis, failed}] of the six saves: what a save would roll with now (Sheet.save_odds).
static func saves(s: GameSession, data: Dictionary, who: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for ab: String in CharacterRules.ABILITIES:
		out.append(Sheet.save_odds(s, data, who, ab).merged({"id": ab}))
	return out


## [{id, bonus}] of the skills it is better at than its ability alone: its proficiencies and what lifts them.
static func skills(s: GameSession, data: Dictionary, who: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: String in data["rules"]["skills"]:
		var bonus := Sheet.skill(s, data, who, id)
		if bonus != Sheet.ability_mod(s, data, who, str(data["rules"]["skills"][id])):
			out.append({"id": id, "bonus": bonus})
	return out


## «плавание 40 фт» — its other ways of moving now (Move).
static func ways(s: GameSession, data: Dictionary, who: Dictionary) -> String:
	var rows := Move.table(data)
	var by := Move.speeds(s, data, who)
	var out: Array[String] = []
	for id: String in by:
		if rows[id].has("word"):
			out.append("%s %d фт" % [rows[id]["word"], int(by[id])])
	return ", ".join(out)


static func speed_text(c: Dictionary) -> String:
	return "%d фт%s" % [int(c["speed"]), (", " + str(c["ways"])) if not str(c["ways"]).is_empty() else ""]


# --- what it does ---------------------------------------------------------------------------------------------------


## Its blows as they are now: a fighter's own, a record's by what it holds (Gear.actions), a form's of its template.
static func blows(s: GameSession, data: Dictionary, who: Dictionary) -> Array:
	var m := Sheet.template(data, who)
	if m.is_empty() or who.has("actions") or Guise.has_body(who) or not data["monsters"].has(Sheet.template_id(data, who)):
		return m.get("actions", [])
	return Gear.actions(s, data, Sheet.template_id(data, who), Sheet.things(s, data, who))


## «+4, 1к6+2 колющий; сбивает с ног» or «спасбросок Лов Сл 12, 4к6 огонь» — a blow's numbers and what it does besides.
static func blow_text(data: Dictionary, a: Dictionary) -> String:
	var dtypes: Dictionary = data["misc"]["damage_types"]
	var dmg: Array[String] = []
	for d: Dictionary in a.get("damage", []):
		dmg.append("%s %s" % [str(d["dice"]).replace("d", "к"), dtypes.get(str(d["type"]), d["type"])])
	var fx := MonsterRules.effect_text(data, a)  # v0.7.9: what it does besides the damage
	var head := "спасбросок %s Сл %d" % [CombatRules.ab_name(str(a["save"]["ability"])), int(a["save"]["dc"])] if a.has("save") \
		else "%+d" % int(a.get("to_hit", 0))
	return "%s%s%s%s" % [head, (", " + ", ".join(dmg)) if not dmg.is_empty() else "", ("; " + fx) if not fx.is_empty() else "",
		" (в запасном наборе)" if bool(a.get("stowed", false)) else ""]


## Its reactions: a parry with what it adds, any other by its name.
static func reactions(m: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for r: Dictionary in m.get("reactions", []):
		out.append("парирование (+%d КД против удара вплотную)" % int(r["ac"]) if r.has("ac") else str(r.get("name", "")))
	return out


## [{name, text, kind}]: its template's traits («trait»), the features of its class («feature») and the traits of its race
## («race») — a person's as its class and race give them in a fight.
static func features(data: Dictionary, m: Dictionary, me: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for t: Dictionary in m.get("traits", []):
		out.append({"name": str(t.get("name", "")), "text": str(t.get("desc", "")), "kind": "trait"})
	for pair: Array in [["features", data["classes"]["features"], "feature"], ["traits", data["races"]["traits"], "race"]]:
		var pool: Dictionary = pair[1]
		var seen: Array[String] = []
		for id: Variant in me.get(pair[0], []):
			var row: Dictionary = pool.get(str(id), {})
			if row.is_empty() or seen.has(str(row.get("name", ""))):
				continue
			seen.append(str(row.get("name", "")))
			out.append({"name": str(row.get("name", id)), "text": str(row.get("desc", "")), "kind": pair[2]})
	return out


## {dc, list: [names], slots: [{circle, left, max}]}: its template's spells with what is left of «N/день», the spells of
## a sheet in the hero's form, what is left of its slots.
static func spells(data: Dictionary, m: Dictionary, me: Dictionary) -> Dictionary:
	var sc: Dictionary = m.get("spellcasting", {})
	var names: Array[String] = []
	for x: Dictionary in sc.get("spells", []):
		var id := str(x["id"])
		if data["spells"].has(id):
			var per := int(x.get("per_day", 0))
			names.append(str(data["spells"][id]["name"]) + (" (%d/%d в день)" % [per - int(me.get("used", {}).get("spell:" + id, 0)), per] if per > 0 else ""))
	for id: Variant in SpellRules.ready(me):
		var name := str(data["spells"].get(str(id), {}).get("name", ""))
		if not name.is_empty() and not names.has(name):
			names.append(name)
	var slots: Array[Dictionary] = []
	var full: Dictionary = sc.get("slots", {})
	for k in range(1, 6):
		var own := (me.get("slots_max", []) as Array).size() >= k
		var most := int(me["slots_max"][k - 1]) if own else int(full.get(str(k), 0))
		if most > 0:
			slots.append({"circle": k, "left": SpellRules.slots_left(me, k) if own else most, "max": most})
	return {"dc": int(sc.get("dc", 0)), "list": names, "slots": slots}


# --- what guards it -------------------------------------------------------------------------------------------------


## [{word, what, source}]: the damage it takes none of, half of or twice (Sheet.defenses, type by type), what halves all of
## it, the conditions that do not hold on it — each with where it comes from.
static func defenses(s: GameSession, data: Dictionary, who: Dictionary) -> Array[Dictionary]:
	var dtypes: Dictionary = data["misc"]["damage_types"]
	var m := Sheet.template(data, who)
	var own: Array = (m.get("immunities", []) as Array) + (m.get("resistances", []) as Array) + (m.get("vulnerabilities", []) as Array)
	var groups := {}  # "kind|source": [what]
	for dtype: String in dtypes:
		var d := Sheet.defenses(s, data, who, dtype, false, false)
		for key: String in ["immune", "resist", "vulnerable"]:
			if d.has(key):
				var src := str(d[key])
				if own.has(src):  # its nature: a template's line
					src = "природа" + (" (немагическое оружие)" if src.contains("nonmagical") else "")
				elif src == str(dtypes[dtype]):  # a status's resistance is named by its type in a damage line: the card names its source
					src = _resist_source(Sheet.holder(s, who), dtype, src)
				_group(groups, key, src, str(dtypes[dtype]))
	var all := ConditionRules.flag_of(Sheet.holder(s, who), data, "resist_all")
	if not all.is_empty():
		_group(groups, "resist", all, "весь урон")
	for cond: String in data["rules"]["conditions"]:
		var why := "природа" if CombatRules.immune_to(data, who, cond) else HeroDefense.immune(s, data, who, cond, "")
		if not why.is_empty():
			_group(groups, "no_condition", why, ConditionRules.name_of(data, cond).to_lower())
	var words := {"immune": "Иммунитет", "resist": "Сопротивление", "vulnerable": "Уязвимость", "no_condition": "Не бывает"}
	var out: Array[Dictionary] = []
	for key: String in groups:
		var kind := key.get_slice("|", 0)
		out.append({"kind": kind, "word": words[kind], "what": ", ".join(groups[key]), "source": key.get_slice("|", 1)})
	return out


## The name of the status that halves `dtype` on `h` (ConditionRules.resisted), `fallback` when none names itself.
static func _resist_source(h: Dictionary, dtype: String, fallback: String) -> String:
	for e: Dictionary in ConditionRules.effects(h):
		if (e.get("resist", []) as Array).has(dtype) and not str(e.get("source", {}).get("name", "")).is_empty():
			return str(e["source"]["name"])
	return fallback


static func _group(groups: Dictionary, kind: String, source: String, what: String) -> void:
	var key := "%s|%s" % [kind, source]
	if not groups.has(key):
		groups[key] = [] as Array[String]
	(groups[key] as Array).append(what)


# --- what it wears --------------------------------------------------------------------------------------------------


## [{slot, item, name, kind, spare}]: what it wears and holds, then the weapon set put away. What a worn thing lays is a
## status of the card with the thing for its source.
static func worn(s: GameSession, data: Dictionary, who: Dictionary) -> Array[Dictionary]:
	var c := Sheet.things(s, data, who)
	var out: Array[Dictionary] = []
	for spare: bool in [false, true]:
		var row: Dictionary = CharacterRules.stowed(c) if spare else c.get("equipped", {})
		for slot: String in CharacterRules.HANDS if spare else CharacterRules.SLOTS:
			var id := str(row.get(slot, ""))
			if id.is_empty():
				continue
			var def := ItemRules.def_of(data["items"], s.items, id)
			out.append({"slot": slot, "item": id, "name": ItemRules.display_name(data["items"], s.items, id), "kind": ItemInfo.kind_line(data, def),
				"spare": spare})
	return out
