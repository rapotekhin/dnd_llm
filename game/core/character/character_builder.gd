class_name CharacterBuilder
extends RefCounted
## Character creation at level 1 (roadmap v0.5.0): what each step offers, what is still wrong, the final
## character Dictionary (CharacterRules), and a random pick. Pure: choices + Catalog.data in, data out.
##
## `choices` — what the player picked so far:
##   name, gender, race, subrace, class, subclass, background,
##   base_abilities {str..cha} (point buy), ability_choice [abilities for a racial +1 choice],
##   skills [class skills], extra_skills [race skill choice], expertise [skills],
##   options {feature/trait id: [chosen option ids]}, cantrips, spells, race_cantrips,
##   equipment [{"alt": int, "picks": [item ids]} per class choice], languages, story (optional backstory text).

const STEP_RACE := "race"
const STEP_SUBRACE := "subrace"
const STEP_CLASS := "class"
const STEP_SUBCLASS := "subclass"
const STEP_BACKGROUND := "background"
const STEP_ABILITIES := "abilities"
const STEP_SKILLS := "skills"
const STEP_FEATURES := "features"
const STEP_SPELLS := "spells"
const STEP_EQUIPMENT := "equipment"
const STEP_DETAILS := "details"


static func empty_choices() -> Dictionary:
	var base := {}
	for a: String in CharacterRules.ABILITIES:
		base[a] = 8
	return {"name": "", "gender": "male", "race": "", "subrace": "", "class": "", "subclass": "", "background": "",
		"base_abilities": base, "ability_choice": [], "skills": [], "extra_skills": [], "expertise": [], "options": {},
		"cantrips": [], "spells": [], "race_cantrips": [], "equipment": [], "languages": []}


# --- what is offered -----------------------------------------------------------------


static func race(ch: Dictionary, data: Dictionary) -> Dictionary:
	return data["races"]["races"].get(str(ch.get("race", "")), {})


static func subrace(ch: Dictionary, data: Dictionary) -> Dictionary:
	return data["races"]["subraces"].get(str(ch.get("subrace", "")), {})


static func klass(ch: Dictionary, data: Dictionary) -> Dictionary:
	return data["classes"]["classes"].get(str(ch.get("class", "")), {})


static func background(ch: Dictionary, data: Dictionary) -> Dictionary:
	return data["backgrounds"].get(str(ch.get("background", "")), {})


static func subclass_now(ch: Dictionary, data: Dictionary) -> bool:
	return int(klass(ch, data).get("subclass_level", 3)) <= 1


static func steps(ch: Dictionary, data: Dictionary) -> Array[String]:
	var out: Array[String] = [STEP_RACE]
	if not (race(ch, data).get("subraces", []) as Array).is_empty():
		out.append(STEP_SUBRACE)
	out.append(STEP_CLASS)
	if subclass_now(ch, data):
		out.append(STEP_SUBCLASS)
	out.append_array([STEP_BACKGROUND, STEP_ABILITIES, STEP_SKILLS])
	if not feature_choices(ch, data).is_empty() or expertise_count(ch, data) > 0:
		out.append(STEP_FEATURES)
	var sp := spell_choices(ch, data)
	if int(sp["cantrips"]) + int(sp["spells"]) + int(sp["race_cantrips"]) > 0:
		out.append(STEP_SPELLS)
	out.append_array([STEP_EQUIPMENT, STEP_DETAILS])
	return out


## Traits of the race and subrace (ids).
static func race_traits(ch: Dictionary, data: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for t: Variant in race(ch, data).get("traits", []):
		out.append(str(t))
	for t: Variant in subrace(ch, data).get("traits", []):
		out.append(str(t))
	return out


## Level-1 class and subclass features (ids), without chosen options.
static func level1_features(ch: Dictionary, data: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for f: Variant in klass(ch, data).get("levels", {}).get("1", {}).get("features", []):
		out.append(str(f))
	var sub: Dictionary = data["classes"]["subclasses"].get(str(ch.get("subclass", "")), {})
	for f: Variant in sub.get("features", {}).get("1", []):
		out.append(str(f))
	return out


## Fixed skill proficiencies: background and race traits.
static func fixed_skills(ch: Dictionary, data: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for s: Variant in background(ch, data).get("skills", []):
		out.append(str(s))
	var traits: Dictionary = data["races"]["traits"]
	for t: String in race_traits(ch, data):
		for s: Variant in traits.get(t, {}).get("skills", []):
			if not out.has(str(s)):
				out.append(str(s))
	return out


## {"choose": n, "from": [skills]} of the class, without skills already fixed.
static func class_skill_choice(ch: Dictionary, data: Dictionary) -> Dictionary:
	var sc: Variant = klass(ch, data).get("skill_choice")
	if not (sc is Dictionary):
		return {"choose": 0, "from": []}
	var fixed := fixed_skills(ch, data)
	return {"choose": int(sc["choose"]), "from": (sc["from"] as Array).filter(func(s: Variant) -> bool: return not fixed.has(s))}


## A race skill choice (Half-Elf Skill Versatility): {"choose": n, "from": [...]}.
static func race_skill_choice(ch: Dictionary, data: Dictionary) -> Dictionary:
	var traits: Dictionary = data["races"]["traits"]
	for t: String in race_traits(ch, data):
		var sc: Variant = traits.get(t, {}).get("skill_choice")
		if sc is Dictionary:
			var taken := fixed_skills(ch, data) + Array(ch.get("skills", []))
			return {"choose": int(sc["choose"]), "from": (sc["from"] as Array).filter(func(s: Variant) -> bool: return not taken.has(s))}
	return {"choose": 0, "from": []}


## Choices of a feature or trait option at level 1: [{"id", "name", "choose", "from"}].
static func feature_choices(ch: Dictionary, data: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var feats: Dictionary = data["classes"]["features"]
	for f: String in level1_features(ch, data):
		var d: Dictionary = feats.get(f, {})
		if d.has("options"):
			out.append({"id": f, "name": d["name"], "choose": int(d["options"]["choose"]), "from": d["options"]["from"], "kind": "feature"})
	var traits: Dictionary = data["races"]["traits"]
	for t: String in race_traits(ch, data):
		var d: Dictionary = traits.get(t, {})
		if d.has("options"):
			out.append({"id": t, "name": d["name"], "choose": int(d["options"]["choose"]), "from": d["options"]["from"], "kind": "trait"})
	return out


static func expertise_count(ch: Dictionary, data: Dictionary) -> int:
	var feats: Dictionary = data["classes"]["features"]
	var n := 0
	for f: String in level1_features(ch, data):
		n += int(feats.get(f, {}).get("expertise", 0))
	return n


static func all_skills(ch: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for key: String in ["skills", "extra_skills"]:
		for s: Variant in ch.get(key, []):
			out.append(str(s))
	return out


static func final_abilities(ch: Dictionary, data: Dictionary) -> Dictionary:
	var out := {}
	var base: Dictionary = ch.get("base_abilities", {})
	for a: String in CharacterRules.ABILITIES:
		out[a] = int(base.get(a, 8)) + int(race(ch, data).get("ability_bonuses", {}).get(a, 0)) \
			+ int(subrace(ch, data).get("ability_bonuses", {}).get(a, 0))
	var choice: Variant = race(ch, data).get("ability_choice")
	if choice is Dictionary:
		for a: Variant in ch.get("ability_choice", []):
			out[str(a)] = int(out[str(a)]) + int(choice["bonus"])
	return out


static func point_cost(ch: Dictionary, data: Dictionary) -> int:
	var pb: Dictionary = data["rules"]["point_buy"]
	var spent := 0
	for a: String in CharacterRules.ABILITIES:
		spent += int(pb["cost"].get(str(int(ch["base_abilities"].get(a, 8))), 99))
	return spent


## Spells to pick: counts and the lists (spell ids) at level 1.
static func spell_choices(ch: Dictionary, data: Dictionary) -> Dictionary:
	var k := klass(ch, data)
	var row: Dictionary = k.get("levels", {}).get("1", {})
	var sc: Dictionary = k.get("spellcasting", {})
	var out := {"cantrips": 0, "spells": 0, "race_cantrips": 0, "cantrip_list": [], "spell_list": [], "race_list": [], "mode": ""}
	var spells: Dictionary = data["spells"]
	if not sc.is_empty() and int(sc.get("from_level", 1)) <= 1:
		var cls := str(ch.get("class", ""))
		out["cantrips"] = int(row.get("cantrips_known", 0))
		var rules: Dictionary = data["rules"]["spellcasting"]
		if row.has("spells_known"):
			out["spells"] = int(row["spells_known"])
			out["mode"] = "known"
		elif bool(sc.get("spellbook", false)):
			out["spells"] = int(rules["spellbook_start"])
			out["mode"] = "spellbook"
		elif bool(sc.get("prepared", false)):
			var score := int(final_abilities(ch, data).get(str(sc["ability"]), 10))
			out["spells"] = maxi(1, CharacterRules.mod(score) + 1)
			out["mode"] = "prepared"
		for id: String in spells:
			var s: Dictionary = spells[id]
			if not (s["classes"] as Array).has(cls):
				continue
			if int(s["level"]) == 0:
				(out["cantrip_list"] as Array).append(id)
			elif int(s["level"]) == 1:
				(out["spell_list"] as Array).append(id)
	var traits: Dictionary = data["races"]["traits"]
	for t: String in race_traits(ch, data):
		var spc: Variant = traits.get(t, {}).get("spell_choice")
		if spc is Dictionary:
			out["race_cantrips"] = int(spc["choose"])
			out["race_list"] = spc["from"]
	return out


static func language_count(ch: Dictionary, data: Dictionary) -> int:
	var n := int(race(ch, data).get("language_choice", 0)) + int(background(ch, data).get("language_choice", 0))
	var traits: Dictionary = data["races"]["traits"]
	for t: String in race_traits(ch, data):
		n += int(traits.get(t, {}).get("language_choice", 0))
	return n


static func language_options(ch: Dictionary, data: Dictionary) -> Array[String]:
	var known: Array = race(ch, data).get("languages", [])
	var out: Array[String] = []
	for id: String in data["misc"]["languages"]:
		if not known.has(id):
			out.append(id)
	return out


## Items a category pick offers ({"category": id} or {"items": [...]}).
static func pick_options(data: Dictionary, pick: Dictionary) -> Array:
	if pick.has("items"):
		return pick["items"]
	return data["misc"]["categories"].get(str(pick.get("category", "")), {}).get("items", [])


# --- validation ----------------------------------------------------------------------


## Problems of a step as localization keys; empty = the step is done.
static func errors(ch: Dictionary, data: Dictionary, step: String) -> Array[String]:
	var out: Array[String] = []
	if step in [STEP_SKILLS, STEP_FEATURES, STEP_SPELLS, STEP_EQUIPMENT] and klass(ch, data).is_empty():
		return ["CC_ERR_PICK_CLASS"]
	match step:
		STEP_RACE:
			if race(ch, data).is_empty():
				out.append("CC_ERR_PICK_RACE")
		STEP_SUBRACE:
			if str(subrace(ch, data).get("race", "")) != str(ch.get("race", "")):
				out.append("CC_ERR_PICK_SUBRACE")
		STEP_CLASS:
			if klass(ch, data).is_empty():
				out.append("CC_ERR_PICK_CLASS")
		STEP_SUBCLASS:
			if not (klass(ch, data).get("subclasses", []) as Array).has(ch.get("subclass", "")):
				out.append("CC_ERR_PICK_SUBCLASS")
		STEP_BACKGROUND:
			if background(ch, data).is_empty():
				out.append("CC_ERR_PICK_BACKGROUND")
		STEP_ABILITIES:
			var pb: Dictionary = data["rules"]["point_buy"]
			for a: String in CharacterRules.ABILITIES:
				var v := int(ch["base_abilities"].get(a, 0))
				if v < int(pb["min"]) or v > int(pb["max"]):
					out.append("CC_ERR_ABILITY_RANGE")
					break
			if point_cost(ch, data) > int(pb["budget"]):
				out.append("CC_ERR_POINTS_OVER")
			elif point_cost(ch, data) < int(pb["budget"]):
				out.append("CC_ERR_POINTS_LEFT")
			var choice: Variant = race(ch, data).get("ability_choice")
			if choice is Dictionary:
				var picked: Array = ch.get("ability_choice", [])
				if picked.size() != int(choice["choose"]) or not picked.all(func(a: Variant) -> bool: return (choice["from"] as Array).has(a)) \
						or _has_duplicates(picked):
					out.append("CC_ERR_ABILITY_CHOICE")
		STEP_SKILLS:
			var sc := class_skill_choice(ch, data)
			if not _picked_ok(ch.get("skills", []), sc):
				out.append("CC_ERR_SKILLS")
			var rc := race_skill_choice(ch, data)
			if int(rc["choose"]) > 0 and not _picked_ok(ch.get("extra_skills", []), rc):
				out.append("CC_ERR_SKILLS")
		STEP_FEATURES:
			for fc: Dictionary in feature_choices(ch, data):
				if not _picked_ok(ch.get("options", {}).get(fc["id"], []), fc):
					out.append("CC_ERR_FEATURES")
					break
			var n := expertise_count(ch, data)
			if n > 0:
				var pool := fixed_skills(ch, data) + all_skills(ch)
				if not _picked_ok(ch.get("expertise", []), {"choose": n, "from": pool}):
					out.append("CC_ERR_EXPERTISE")
		STEP_SPELLS:
			var sp := spell_choices(ch, data)
			if not _picked_ok(ch.get("cantrips", []), {"choose": sp["cantrips"], "from": sp["cantrip_list"]}) \
					or not _picked_ok(ch.get("spells", []), {"choose": mini(int(sp["spells"]), (sp["spell_list"] as Array).size()), "from": sp["spell_list"]}) \
					or not _picked_ok(ch.get("race_cantrips", []), {"choose": sp["race_cantrips"], "from": sp["race_list"]}):
				out.append("CC_ERR_SPELLS")
		STEP_EQUIPMENT:
			var sets: Array = klass(ch, data).get("equipment_choices", [])
			var picked: Array = ch.get("equipment", [])
			if picked.size() != sets.size():
				out.append("CC_ERR_EQUIPMENT")
			else:
				for i in sets.size():
					var alts: Array = sets[i]["alternatives"]
					var p: Dictionary = picked[i] if picked[i] is Dictionary else {}
					var alt := int(p.get("alt", -1))
					if alt < 0 or alt >= alts.size() or not _picks_ok(data, alts[alt]["picks"], p.get("picks", [])):
						out.append("CC_ERR_EQUIPMENT")
						break
		STEP_DETAILS:
			if str(ch.get("name", "")).strip_edges().is_empty():
				out.append("CC_ERR_NAME")
			if not _picked_ok(ch.get("languages", []), {"choose": language_count(ch, data), "from": language_options(ch, data)}):
				out.append("CC_ERR_LANGUAGES")
	return out


## All steps done: the character can be built.
static func complete(ch: Dictionary, data: Dictionary) -> bool:
	for s: String in steps(ch, data):
		if not errors(ch, data, s).is_empty():
			return false
	return true


static func _picked_ok(picked: Variant, choice: Dictionary) -> bool:
	var p: Array = picked if picked is Array else []
	return p.size() == int(choice["choose"]) and not _has_duplicates(p) \
		and p.all(func(x: Variant) -> bool: return (choice["from"] as Array).has(x))


static func _picks_ok(data: Dictionary, picks: Array, chosen: Variant) -> bool:
	var c: Array = chosen if chosen is Array else []
	var need := 0
	for p: Dictionary in picks:
		need += int(p["count"])
	if c.size() != need:
		return false
	var i := 0
	for p: Dictionary in picks:
		var opts := pick_options(data, p)
		for n in int(p["count"]):
			if not opts.has(c[i]):
				return false
			i += 1
	return true


static func _has_duplicates(a: Array) -> bool:
	var seen := {}
	for x: Variant in a:
		if seen.has(x):
			return true
		seen[x] = true
	return false


# --- build ---------------------------------------------------------------------------


## The level-1 character (CharacterRules layout) from complete choices.
static func build(ch: Dictionary, data: Dictionary) -> Dictionary:
	var k := klass(ch, data)
	var traits_data: Dictionary = data["races"]["traits"]
	var c := {
		"name": str(ch["name"]).strip_edges(), "gender": str(ch.get("gender", "other")),
		"race": str(ch["race"]), "subrace": str(ch.get("subrace", "")), "class": str(ch["class"]),
		"subclass": str(ch.get("subclass", "")), "background": str(ch["background"]), "level": 1, "xp": 0,
		"abilities": final_abilities(ch, data), "save_profs": (k["saves"] as Array).duplicate(),
		"conditions": [], "slots_used": [0, 0, 0, 0, 0], "hit_dice_used": 0,
		"resources_used": {}, "effects": [], "next_effect": 1, "exhaustion": 0, "concentration": "", "concentration_ends": -1, "prepared_day": 1,
		"story": str(ch.get("story", "")).strip_edges(),
	}
	# Age, build, height (v0.7.22.5): what the player chose (v0.7.22.15), the rest the engine picks.
	c["body"] = BodyRules.make(data, c["gender"], BodyRules.fit(data, ch.get("body", {}) if ch.get("body") is Dictionary else {}, c["gender"]), "hero:" + str(c["name"]), true)
	var skills := fixed_skills(ch, data)
	for s: String in all_skills(ch):
		if not skills.has(s):
			skills.append(s)
	c["skill_profs"] = skills
	c["expertise"] = (ch.get("expertise", []) as Array).duplicate()

	var armor: Array = (k.get("armor", []) as Array).duplicate()
	var weapons: Array = (k.get("weapons", []) as Array).duplicate()
	var tools: Array = (k.get("tools", []) as Array).duplicate()
	var traits := race_traits(ch, data)
	var options: Dictionary = ch.get("options", {})
	for t: String in race_traits(ch, data):
		for o: Variant in options.get(t, []):
			traits.append(str(o))
	for t: String in traits:
		var td: Dictionary = traits_data.get(t, {})
		_merge(armor, td.get("armor", []))
		_merge(weapons, td.get("weapons", []))
		_merge(tools, td.get("tools", []))
		var tc: Variant = td.get("tool_choice")
		if tc is Dictionary:  # a tool of choice (Dwarf): the first one, tools do not affect checks yet
			_merge(tools, (tc["from"] as Array).slice(0, int(tc["choose"])))
	var features := level1_features(ch, data)
	for f: String in level1_features(ch, data):
		for o: Variant in options.get(f, []):
			features.append(str(o))
	var grants: Dictionary = data["rules"].get("feature_grants", {})
	for f: String in features:
		_merge(armor, grants.get(f, {}).get("armor", []))
		_merge(weapons, grants.get(f, {}).get("weapons", []))
	_merge(tools, background(ch, data).get("tools", []))
	c["armor_profs"] = armor
	c["weapon_profs"] = weapons
	c["tools"] = tools
	c["traits"] = traits
	c["features"] = features
	var langs: Array = (race(ch, data).get("languages", []) as Array).duplicate()
	_merge(langs, ch.get("languages", []))
	c["languages"] = langs

	var sp := spell_choices(ch, data)
	var cantrips: Array = (ch.get("cantrips", []) as Array).duplicate()
	_merge(cantrips, ch.get("race_cantrips", []))
	var picked: Array = (ch.get("spells", []) as Array).duplicate()
	var spells := {"cantrips": cantrips, "known": [], "prepared": [], "always": []}
	match str(sp["mode"]):
		"known":
			spells["known"] = picked
			spells["prepared"] = picked.duplicate()
		"spellbook":
			spells["known"] = picked
			var n := maxi(1, CharacterRules.mod(int(c["abilities"]["int"])) + 1)
			spells["prepared"] = picked.slice(0, n)
		"prepared":
			spells["prepared"] = picked
	var sub: Dictionary = data["classes"]["subclasses"].get(str(ch.get("subclass", "")), {})
	for id: Variant in sub.get("spells", {}).get("1", []):
		(spells["always"] as Array).append(str(id))
	c["spells"] = spells

	var inv := {}
	for e: Dictionary in k.get("equipment", []):
		_add_item(inv, str(e["id"]), int(e["qty"]))
	var sets: Array = k.get("equipment_choices", [])
	var eq: Array = ch.get("equipment", [])
	for i in sets.size():
		var alt: Dictionary = sets[i]["alternatives"][int(eq[i]["alt"])]
		for e: Dictionary in alt["items"]:
			_add_item(inv, str(e["id"]), int(e["qty"]))
		for id: Variant in eq[i].get("picks", []):
			_add_item(inv, str(id), 1)
	for e: Dictionary in background(ch, data).get("equipment", []):
		_add_item(inv, str(e["id"]), int(e["qty"]))
	c["inventory"] = inv
	c["gold_cp"] = int(background(ch, data).get("gold_cp", 0))
	CharacterRules.auto_equip(c, data)
	c.erase("hp")
	CharacterRules.refresh(c, data)
	return c


## Choices of a world's ready-made character (characters.json), with its story.
static func preset_choices(preset: Dictionary) -> Dictionary:
	var ch := empty_choices()
	ch.merge((preset.get("choices", {}) as Dictionary).duplicate(true), true)
	ch["story"] = str(preset.get("story", ""))
	return ch


static func build_preset(preset: Dictionary, data: Dictionary) -> Dictionary:
	return build(preset_choices(preset), data)


static func _merge(into: Array, more: Variant) -> void:
	if more is Array:
		for x: Variant in more:
			if not into.has(x):
				into.append(x)


static func _add_item(inv: Dictionary, id: String, qty: int) -> void:
	inv[id] = int(inv.get(id, 0)) + qty


# --- random --------------------------------------------------------------------------


## A complete random character (seeded): race, class, background, a sensible point buy, all picks.
static func random_choices(data: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var ch := empty_choices()
	ch["race"] = _pick(rng, data["races"]["races"].keys())
	var subs: Array = race(ch, data).get("subraces", [])
	ch["subrace"] = _pick(rng, subs) if not subs.is_empty() else ""
	ch["class"] = _pick(rng, data["classes"]["classes"].keys())
	if subclass_now(ch, data):
		ch["subclass"] = _pick(rng, klass(ch, data)["subclasses"])
	ch["background"] = _pick(rng, data["backgrounds"].keys())
	ch["base_abilities"] = _standard_spread(data, str(ch["class"]))
	var choice: Variant = race(ch, data).get("ability_choice")
	if choice is Dictionary:
		ch["ability_choice"] = _sample(rng, choice["from"], int(choice["choose"]))
	var sc := class_skill_choice(ch, data)
	ch["skills"] = _sample(rng, sc["from"], int(sc["choose"]))
	var rc := race_skill_choice(ch, data)
	ch["extra_skills"] = _sample(rng, rc["from"], int(rc["choose"]))
	var opts := {}
	for fc: Dictionary in feature_choices(ch, data):
		opts[fc["id"]] = _sample(rng, fc["from"], int(fc["choose"]))
	ch["options"] = opts
	var n := expertise_count(ch, data)
	if n > 0:
		ch["expertise"] = _sample(rng, fixed_skills(ch, data) + all_skills(ch), n)
	var sp := spell_choices(ch, data)
	ch["cantrips"] = _sample(rng, sp["cantrip_list"], int(sp["cantrips"]))
	ch["spells"] = _sample(rng, sp["spell_list"], int(sp["spells"]))
	ch["race_cantrips"] = _sample(rng, sp["race_list"], int(sp["race_cantrips"]))
	var eq: Array = []
	for set: Dictionary in klass(ch, data).get("equipment_choices", []):
		var alt := rng.randi_range(0, (set["alternatives"] as Array).size() - 1)
		var picks: Array = []
		for p: Dictionary in set["alternatives"][alt]["picks"]:
			for i in int(p["count"]):
				picks.append(_pick(rng, pick_options(data, p)))
		eq.append({"alt": alt, "picks": picks})
	ch["equipment"] = eq
	ch["languages"] = _sample(rng, language_options(ch, data), language_count(ch, data))
	ch["gender"] = _pick(rng, ["male", "female"])
	ch["name"] = _pick(rng, data.get("names", data["game"]["creation"]["names"])[ch["gender"]])
	return ch


## 15, 14, 13, 12, 10, 8 by point buy (27 points): the class's spell ability and CON high, the rest in order.
static func _standard_spread(data: Dictionary, class_id: String) -> Dictionary:
	var order: Array[String] = []
	var main := str(data["rules"]["creation"]["main_ability"].get(class_id, "str"))
	order.append(main)
	if main != "con":
		order.append("con")
	for a: String in ["dex", "str", "wis", "int", "cha"]:
		if not order.has(a):
			order.append(a)
	var values := [15, 14, 13, 12, 10, 8]
	var out := {}
	for i in 6:
		out[order[i]] = values[i]
	return out


static func _pick(rng: RandomNumberGenerator, from: Array) -> Variant:
	return from[rng.randi_range(0, from.size() - 1)] if not from.is_empty() else ""


static func _sample(rng: RandomNumberGenerator, from: Array, n: int) -> Array:
	var pool := from.duplicate()
	var out: Array = []
	for i in mini(n, pool.size()):
		out.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
	return out
