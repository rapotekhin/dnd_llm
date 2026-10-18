class_name LevelUp
extends RefCounted
## Level-up by the SRD tables (roadmap v0.5.4): experience thresholds, what the next level brings and the
## player's picks for it, then the new level applied to the character. Pure: character + Catalog.data in.
##
## Experience comes only from the engine — combat by monster CR and quests of the pack (XpRules); the master
## cannot grant it. HP grow by the fixed average (CharacterRules.max_hp), spell slots come from the level row.
##
## `picks` for a level: subclass, options {feature id: [option ids]}, expertise [skills],
##   asi {ability: +n} (+2 to one or +1 to two, max 20), cantrips [ids], spells [ids] (known / spellbook),
##   prepared [ids] (prepared casters and the wizard's spellbook).


static func thresholds(data: Dictionary) -> Array:
	return data["rules"]["xp"]["thresholds"]


## The highest level the catalog has rows for (the SRD slice is levels 1–5).
static func max_level(c: Dictionary, data: Dictionary) -> int:
	return mini(int(data["rules"]["xp"]["max_level"]), CharacterRules.class_def(c, data).get("levels", {}).size())


## Experience needed for `level` (1 → 0).
static func xp_for(data: Dictionary, level: int) -> int:
	var t := thresholds(data)
	return int(t[clampi(level - 1, 0, t.size() - 1)])


static func can_level_up(c: Dictionary, data: Dictionary) -> bool:
	var level := int(c.get("level", 1))
	return level < max_level(c, data) and int(c.get("xp", 0)) >= xp_for(data, level + 1)


static func _row(c: Dictionary, data: Dictionary, level: int) -> Dictionary:
	return CharacterRules.class_def(c, data).get("levels", {}).get(str(level), {})


## Class and subclass features gained at `level` (subclass from `picks` when chosen at this level).
static func features_at(c: Dictionary, data: Dictionary, level: int, subclass: String) -> Array[String]:
	var out: Array[String] = []
	for f: Variant in _row(c, data, level).get("features", []):
		out.append(str(f))
	var sub: Dictionary = data["classes"]["subclasses"].get(subclass, {})
	for f: Variant in sub.get("features", {}).get(str(level), []):
		out.append(str(f))
	return out


static func _subclass(c: Dictionary, picks: Dictionary) -> String:
	var s := str(c.get("subclass", ""))
	return s if not s.is_empty() else str(picks.get("subclass", ""))


## The prepared-spell count of a prepared caster at `level` with these abilities (paladin: half the level).
static func prepared_count(c: Dictionary, data: Dictionary, level: int, abilities: Dictionary) -> int:
	var sc: Dictionary = CharacterRules.class_def(c, data).get("spellcasting", {})
	if sc.is_empty() or not bool(sc.get("prepared", false)) or level < int(sc.get("from_level", 1)):
		return 0
	var div := int(data["rules"]["spellcasting"].get("prepared_level_divisor", {}).get(str(c.get("class", "")), 1))
	return maxi(1, CharacterRules.mod(int(abilities.get(str(sc["ability"]), 10))) + level / div)


## Abilities after the ASI picks.
static func abilities_after(c: Dictionary, picks: Dictionary) -> Dictionary:
	var out: Dictionary = (c.get("abilities", {}) as Dictionary).duplicate()
	var asi: Dictionary = picks.get("asi", {})
	for a: String in asi:
		out[a] = int(out.get(a, 10)) + int(asi[a])
	return out


## What the next level brings: {"level", "hp_gain", "features" [ids], "subclass" (choose now), "subclasses" [ids],
## "options" [{id, name, choose, from}], "expertise" n, "asi" bool, "cantrips" n, "spells" n, "spell_mode",
## "prepared" n (new prepared picks), "max_spell_level", "cantrip_list", "spell_list", "prepared_list"}.
static func plan(c: Dictionary, data: Dictionary, picks: Dictionary = {}) -> Dictionary:
	var k := CharacterRules.class_def(c, data)
	var old := int(c.get("level", 1))
	var level := old + 1
	var row := _row(c, data, level)
	var prev := _row(c, data, old)
	var sub_now := str(c.get("subclass", "")).is_empty() and int(k.get("subclass_level", 3)) <= level
	var subclass := _subclass(c, picks)
	var feats: Dictionary = data["classes"]["features"]
	var grants: Dictionary = data["rules"].get("feature_grants", {})
	var out := {"level": level, "features": features_at(c, data, level, subclass), "subclass": sub_now,
		"subclasses": (k.get("subclasses", []) as Array).duplicate(), "options": [], "expertise": 0,
		"asi": int(row.get("asi", 0)) > int(prev.get("asi", 0)), "cantrips": 0, "spells": 0, "prepared": 0,
		"spell_mode": "", "max_spell_level": 0, "cantrip_list": [], "spell_list": [], "prepared_list": []}
	var bonus_cantrips := 0
	for f: String in out["features"]:
		var d: Dictionary = feats.get(f, {})
		if d.has("options"):
			(out["options"] as Array).append({"id": f, "name": d["name"], "choose": int(d["options"]["choose"]), "from": d["options"]["from"]})
		out["expertise"] = int(out["expertise"]) + int(d.get("expertise", 0))
		bonus_cantrips += int(grants.get(f, {}).get("cantrips", 0))

	var abilities := abilities_after(c, picks)
	var con_gain := CharacterRules.mod(int(abilities.get("con", 10))) - CharacterRules.mod(int(c["abilities"].get("con", 10)))
	var die := int(k.get("hit_die", 8))
	var per_level := 1 if CharacterRules.has_trait(c, "dwarven_toughness") or CharacterRules.has_feature(c, "draconic_resilience") else 0
	out["hp_gain"] = maxi(1, die / 2 + 1 + CharacterRules.mod(int(abilities.get("con", 10))) + per_level) + con_gain * old

	var sc: Dictionary = k.get("spellcasting", {})
	if not sc.is_empty() and level >= int(sc.get("from_level", 1)):
		var slots: Array = row.get("slots", [])
		for i in slots.size():
			if int(slots[i]) > 0:
				out["max_spell_level"] = i + 1
		out["cantrips"] = int(row.get("cantrips_known", 0)) - int(prev.get("cantrips_known", 0)) + bonus_cantrips
		var spells: Dictionary = c.get("spells", {})
		if row.has("spells_known"):
			out["spell_mode"] = "known"
			out["spells"] = int(row["spells_known"]) - int(prev.get("spells_known", 0))
		elif bool(sc.get("spellbook", false)):
			out["spell_mode"] = "spellbook"
			out["spells"] = int(data["rules"]["spellcasting"]["spellbook_per_level"])
		elif bool(sc.get("prepared", false)):
			out["spell_mode"] = "prepared"
		if bool(sc.get("prepared", false)):
			out["prepared"] = maxi(0, prepared_count(c, data, level, abilities) - (spells.get("prepared", []) as Array).size())
		var cls := str(c.get("class", ""))
		var known := _all_spells(c)
		for id: String in data["spells"]:
			var s: Dictionary = data["spells"][id]
			if not (s["classes"] as Array).has(cls) or known.has(id):
				continue
			var lv := int(s["level"])
			if lv == 0:
				(out["cantrip_list"] as Array).append(id)
			elif lv <= int(out["max_spell_level"]):
				(out["spell_list"] as Array).append(id)
		# Prepared picks: the class list (cleric, druid, paladin) or the spellbook with its new pages (wizard).
		var pool: Array = []
		if str(out["spell_mode"]) == "spellbook":
			pool = (spells.get("known", []) as Array).duplicate()
			for id: Variant in picks.get("spells", []):
				pool.append(str(id))
		elif str(out["spell_mode"]) == "prepared":
			pool = (out["spell_list"] as Array).duplicate()
		var prepared: Array = spells.get("prepared", [])
		out["prepared_list"] = pool.filter(func(id: Variant) -> bool: return not prepared.has(id))
	return out


static func _all_spells(c: Dictionary) -> Array:
	var out: Array = []
	var sp: Dictionary = c.get("spells", {})
	for list: String in ["cantrips", "known", "prepared", "always"]:
		for id: Variant in sp.get(list, []):
			if not out.has(id):
				out.append(id)
	return out


## Problems of the picks as localization keys; empty = the level can be applied.
static func errors(c: Dictionary, data: Dictionary, picks: Dictionary) -> Array[String]:
	var e: Array[String] = []
	if not can_level_up(c, data):
		return ["LVL_ERR_NOT_READY"]
	var p := plan(c, data, picks)
	if bool(p["subclass"]) and not (p["subclasses"] as Array).has(str(picks.get("subclass", ""))):
		e.append("LVL_ERR_SUBCLASS")
	var options: Dictionary = picks.get("options", {})
	for o: Dictionary in p["options"]:
		var chosen: Array = options.get(o["id"], [])
		if chosen.size() != int(o["choose"]) or chosen.any(func(x: Variant) -> bool: return not (o["from"] as Array).has(x)) \
				or _dupes(chosen):
			e.append("LVL_ERR_OPTIONS")
			break
	var exp: Array = picks.get("expertise", [])
	if exp.size() != int(p["expertise"]) or _dupes(exp) or exp.any(func(s: Variant) -> bool:
			return not (c.get("skill_profs", []) as Array).has(s) or (c.get("expertise", []) as Array).has(s)):
		e.append("LVL_ERR_EXPERTISE")
	if bool(p["asi"]):
		var asi: Dictionary = picks.get("asi", {})
		var total := 0
		var ok := true
		for a: String in asi:
			var n := int(asi[a])
			total += n
			if not CharacterRules.ABILITIES.has(a) or n < 1 or n > 2 or int(c["abilities"].get(a, 10)) + n > 20:
				ok = false
		if not ok or total != 2:
			e.append("LVL_ERR_ASI")
	elif not (picks.get("asi", {}) as Dictionary).is_empty():
		e.append("LVL_ERR_ASI")
	if not _picked(picks.get("cantrips", []), int(p["cantrips"]), p["cantrip_list"]):
		e.append("LVL_ERR_CANTRIPS")
	if not _picked(picks.get("spells", []), int(p["spells"]), p["spell_list"]):
		e.append("LVL_ERR_SPELLS")
	if not _picked(picks.get("prepared", []), mini(int(p["prepared"]), (p["prepared_list"] as Array).size()), p["prepared_list"]):
		e.append("LVL_ERR_PREPARED")
	return e


static func _picked(chosen: Variant, n: int, pool: Array) -> bool:
	var a: Array = chosen if chosen is Array else []
	return a.size() == maxi(0, n) and not _dupes(a) and a.all(func(x: Variant) -> bool: return pool.has(x))


static func _dupes(a: Array) -> bool:
	var seen := {}
	for x: Variant in a:
		if seen.has(x):
			return true
		seen[x] = true
	return false


## Applies the next level with valid picks (errors() empty). Returns the lines for the chat.
static func apply(c: Dictionary, data: Dictionary, picks: Dictionary, session_items: Dictionary = {}) -> Array[String]:
	assert(errors(c, data, picks).is_empty(), "apply() needs valid picks")
	var p := plan(c, data, picks)
	var feats: Dictionary = data["classes"]["features"]
	var hp_before := int(c.get("max_hp", 0))
	if bool(p["subclass"]):
		c["subclass"] = str(picks["subclass"])
	c["level"] = int(p["level"])
	c["abilities"] = abilities_after(c, picks)
	var features: Array = c.get("features", [])
	var grants: Dictionary = data["rules"].get("feature_grants", {})
	var options: Dictionary = picks.get("options", {})
	var gained: Array[String] = []
	for f: String in p["features"]:
		if not features.has(f):
			features.append(f)
			gained.append(str(feats.get(f, {}).get("name", f)))
		for o: Variant in options.get(f, []):
			features.append(str(o))
	for f: Variant in features:
		var g: Dictionary = grants.get(str(f), {})
		for pair: Array in [["armor", "armor_profs"], ["weapons", "weapon_profs"]]:
			var list: Array = c.get(pair[1], [])
			for x: Variant in g.get(pair[0], []):
				if not list.has(x):
					list.append(x)
			c[pair[1]] = list
	c["features"] = features
	var expertise: Array = c.get("expertise", [])
	expertise.append_array(picks.get("expertise", []))
	c["expertise"] = expertise
	var sp: Dictionary = c.get("spells", {"cantrips": [], "known": [], "prepared": [], "always": []})
	for list: String in ["cantrips", "known", "prepared", "always"]:
		if not sp.has(list):
			sp[list] = []
	(sp["cantrips"] as Array).append_array(picks.get("cantrips", []))
	(sp["known"] as Array).append_array(picks.get("spells", []))
	if str(p["spell_mode"]) == "known":
		(sp["prepared"] as Array).append_array(picks.get("spells", []))
	(sp["prepared"] as Array).append_array(picks.get("prepared", []))
	var sub: Dictionary = data["classes"]["subclasses"].get(str(c.get("subclass", "")), {})
	var ignored: Array = data["rules"]["spellcasting"].get("subclass_spells_ignored", [])
	for lv in range(1 if not ignored.has(str(c.get("subclass", ""))) else 99, int(p["level"]) + 1):
		for id: Variant in sub.get("spells", {}).get(str(lv), []):
			if not (sp["always"] as Array).has(str(id)):
				(sp["always"] as Array).append(str(id))
	c["spells"] = sp
	CharacterRules.refresh(c, data, session_items)
	var gain := int(c["max_hp"]) - hp_before
	c["hp"] = mini(int(c["max_hp"]), int(c.get("hp", 0)) + gain)
	var lines: Array[String] = ["Новый уровень: %d" % int(p["level"]), "+%d HP (максимум %d)" % [gain, int(c["max_hp"])]]
	if bool(p["subclass"]):
		lines.append(str(sub.get("name", c["subclass"])))
	if not gained.is_empty():
		lines.append(", ".join(gained))
	return lines


## Valid picks taking the first offers: the first subclass and options, +2 to the class's main ability (or +1 to
## the two highest that fit under 20), the first spells. For tests, playtests and a quick level-up.
static func default_picks(c: Dictionary, data: Dictionary) -> Dictionary:
	var picks := {}
	var p := plan(c, data, picks)
	if bool(p["subclass"]) and not (p["subclasses"] as Array).is_empty():
		picks["subclass"] = str(p["subclasses"][0])
		p = plan(c, data, picks)
	var options := {}
	for o: Dictionary in p["options"]:
		options[o["id"]] = (o["from"] as Array).slice(0, int(o["choose"]))
	if not options.is_empty():
		picks["options"] = options
	if int(p["expertise"]) > 0:
		var pool := (c.get("skill_profs", []) as Array).filter(func(s: Variant) -> bool: return not (c.get("expertise", []) as Array).has(s))
		picks["expertise"] = pool.slice(0, int(p["expertise"]))
	if bool(p["asi"]):
		var main := str(data["rules"]["creation"]["main_ability"].get(str(c.get("class", "")), "str"))
		var ab: Dictionary = c["abilities"]
		if int(ab.get(main, 10)) <= 18:
			picks["asi"] = {main: 2}
		else:
			var order := CharacterRules.ABILITIES.filter(func(a: String) -> bool: return int(ab.get(a, 10)) < 20)
			order.sort_custom(func(a: String, b: String) -> bool: return int(ab[a]) > int(ab[b]))
			picks["asi"] = {order[0]: 1, order[1]: 1}
	picks["cantrips"] = (p["cantrip_list"] as Array).slice(0, maxi(0, int(p["cantrips"])))
	picks["spells"] = (p["spell_list"] as Array).slice(0, maxi(0, int(p["spells"])))
	p = plan(c, data, picks)
	picks["prepared"] = (p["prepared_list"] as Array).slice(0, maxi(0, int(p["prepared"])))
	return picks
