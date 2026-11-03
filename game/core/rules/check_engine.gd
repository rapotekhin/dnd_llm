class_name CheckEngine
extends RefCounted
## What a check of anybody has beside its sheet (v0.8.4.14, ADR-0016): the statuses, the light and the weather, a Rage,
## armour and things, spells, a pet, a tool, a terrain, the listener of the words. Roll.check rolls by it and
## Roll.chance_of shows the chance by it, so a window and the roll cannot part ways.
## The engine.check card of the hero (ADR-0008 §2): the engine owns the DC number, the roll and the result; the LLM only
## names the skill and a DC tier. Locks of failed checks — ExplorationRules.


## What this moment gives a check of `who` by `spec` (a skill or a bare ability; `adv_why`, `dis_why`, `fail_why` — the
## caller's reasons, a text or a list; `tool`, `target_id`, `sense`, `about` — a creature type or a subject): {adv, dis, fail: [why], parts: [{label, value}]}.
## `peek` — a chance shown before the roll: a spell's die counts by its mean and is not spent.
static func situation(s: GameSession, data: Dictionary, who: Dictionary, spec: Dictionary, peek := false) -> Dictionary:
	var me := Sheet.holder(s, who)
	var skill := str(spec.get("skill", "")) if spec.get("skill") != null else ""
	var adv := whys(spec.get("adv_why"))
	var dis := whys(spec.get("dis_why"))
	var fail := whys(spec.get("fail_why"))
	var parts: Array[Dictionary] = []
	var mods := ConditionRules.check_mods(me, data, spec)
	dis.append_array((mods["disadvantage"] as Array).map(func(id: Variant) -> String: return ConditionRules.why(data, str(id))))
	fail.append_array((mods["auto_fail"] as Array).map(func(id: Variant) -> String: return ConditionRules.why(data, str(id))))
	match skill:
		"perception":
			if TimeRules.dark(s, data, who):
				dis.append("темнота")
			elif not WeatherRules.obscure_why(s, data).is_empty():
				dis.append(WeatherRules.obscure_why(s, data))  # fog, a downpour (v0.7.46)
			_add(adv, CharacterRules.carried_with(me, data, s.items, "perception_advantage"))  # v0.7.12
		"investigation":
			_add(adv, CharacterRules.carried_with(me, data, s.items, "investigation_advantage"))
		"stealth":
			if bool(ItemRules.def_of(data["items"], s.items, str(me.get("equipped", {}).get("armor", ""))).get("armor", {}).get("stealth_disadvantage", false)):
				dis.append("доспех")
			_add(adv, CharacterRules.carried_with(me, data, s.items, "stealth_advantage"))
			_add(adv, SightRules.in_dark(s, data, who))  # the author's rule for the dark, v0.8.4.1
		"athletics":
			if Sheet.raging(s, who):
				adv.append("ярость")
	var ab := str(data["rules"]["skills"].get(skill, spec.get("ability", "")))
	for e: Dictionary in ConditionRules.effects(me):
		if str(e.get("ability_adv", "")) == ab and not ab.is_empty():  # Enhance Ability (v0.7.13.3)
			_add(adv, str(e.get("source", {}).get("name", "")))
		if not skill.is_empty() and (str(e.get("check_adv", "")) == skill or (bool(e.get("enlarged", false)) and skill == "athletics")):
			_add(adv, str(e.get("source", {}).get("name", "зелье")))
	if Sheet.is_hero(who):
		_add(adv, PetRules.helper(s, data, skill))  # v0.7.43: a dog's nose, a hawk's eye — the hero's pets
	var tool := str(spec.get("tool", "")) if spec.get("tool") != null else ""
	var t := BackgroundRules.tool_check(me, data, tool, skill)
	_add(fail, str(t["auto_fail"]))
	_add(adv, str(t["advantage"]))
	RollParts.add(parts, str(t["note"]), int(t["bonus"]))
	RollParts.add(parts, "исследователь природы", _terrain(s, data, me, skill))
	var about := _about(s, data, me, spec, skill)
	_add(adv, str(about["adv"]))
	RollParts.add(parts, str(about["label"]), int(about["bonus"]))
	var listener := listener(s, data, spec)
	if not listener.is_empty() and Sheet.is_hero(who):  # v0.7.11: the words reach only who understands them
		var gate := LanguageRules.check_gate(me, data, skill, LanguageRules.npc_understands(me, data, data["world"]["npcs"][listener]))
		_add(fail, str(gate.get("auto_fail", "")))
		_add(dis, str(gate.get("disadvantage", "")))
		var charm := SpellEffects.npc_spells(s, listener).filter(func(e: Dictionary) -> bool: return (e.get("skills", ExplorationRules.SOCIAL_SKILLS) as Array).has(skill))
		if not charm.is_empty():  # Charm Person and the like (v0.7.22.3), Zone of Truth on Insight (v0.8.4.26.3)
			adv.append("%s: %s" % [charm[0].get("word", "очарован"), charm[0]["source"]["name"]])
	var die := SpellEffects.die(s, me, "check", peek)  # Guidance (v0.7.13.1)
	parts.append_array(die["parts"])
	return {"adv": adv, "dis": dis, "fail": fail, "parts": parts}


## The NPC a check speaks to: its target, or the one the hero talks with ("" — none, or a dead one).
static func listener(s: GameSession, data: Dictionary, spec: Dictionary) -> String:
	var tid := str(spec.get("target_id", "")) if spec.get("target_id") != null else ""
	if tid.is_empty() and s.in_conversation():
		tid = s.npc_id
	return tid if (data["world"].get("npcs", {}) as Dictionary).has(tid) and not Being.dead(s, tid) else ""


## Natural Explorer (v0.7.10): in the ranger's favored terrain (`terrain` of the location) a proficient INT or WIS skill
## gets the proficiency bonus twice.
static func _terrain(s: GameSession, data: Dictionary, me: Dictionary, skill: String) -> int:
	if skill.is_empty() or not str(data["rules"]["skills"].get(skill, "")) in ["int", "wis"]:
		return 0
	var w := WorldView.new(data["world"])
	var terrain := str(w.location(w.location_id(s.room_id)).get("terrain", ""))
	if terrain.is_empty() or not CharacterRules.has_feature(me, "natural_explorer_" + terrain):
		return 0
	var proficient := (me.get("skill_profs", []) as Array).has(skill) or CharacterRules.has_feature(me, "skill_prof_" + skill)
	return CharacterRules.prof_bonus(me, data) if proficient else 0


## What a check is about: `about` of the spec (the master's word or the caller's: a creature type or a subject of
## `rules.check_about`), else the type of the template of its target or listener; "" when none.
static func about_of(s: GameSession, data: Dictionary, spec: Dictionary) -> String:
	var said := str(spec.get("about", "")) if spec.get("about") != null else ""
	if not said.is_empty():
		return said
	var tid := str(spec.get("target_id", "")) if spec.get("target_id") != null else ""
	if tid.is_empty() and s.in_conversation():
		tid = s.npc_id
	return "" if tid.is_empty() or tid == Being.HERO else str(Sheet.template(data, Sheet.who(s, data, tid)).get("type", ""))


## A row of `rules.check_about` of a feature (by its `parent`), a trait of `me` or a thing it carries (`item`) that fits
## the check's subject and its skill or ability (v0.8.4.26.1): Favored Enemy gives advantage, Dragon Ancestor, Artificer's
## Lore and Stonecunning the proficiency twice (`proficient` — counted as proficient), a crowbar advantage on forcing,
## a portable ram +4 (v0.8.4.27). {adv: why, label, bonus}.
static func _about(s: GameSession, data: Dictionary, me: Dictionary, spec: Dictionary, skill: String) -> Dictionary:
	var out := {"adv": "", "label": "", "bonus": 0}
	var about := about_of(s, data, spec)
	if about.is_empty():
		return out
	var ab := str(data["rules"]["skills"].get(skill, spec.get("ability", "")))
	var feats: Dictionary = data["classes"]["features"]
	for key: String in data["rules"].get("check_about", {}):
		var row: Variant = data["rules"]["check_about"][key]
		if not row is Dictionary or not ((row.get("skills", []) as Array).has(skill) or (row.get("abilities", []) as Array).has(ab)):
			continue
		var name := ""
		if row.has("trait") and CharacterRules.has_trait(me, str(row["trait"])):
			name = str(data["races"]["traits"].get(str(row["trait"]), {}).get("name", row["trait"]))
		if row.has("item") and Thing.count(me, str(row["item"])) > 0:  # a crowbar, a ram, a magnifying glass (v0.8.4.27)
			name = ItemRules.display_name(data["items"], s.items, str(row["item"]))
		for f: Variant in me.get("features", []):
			var d: Dictionary = feats.get(str(f), {})
			if row.has("parent") and str(d.get("parent", "")) == str(row["parent"]) and (str(row.get("about", "")) != "creature_type" or str(d.get("creature_type", "")) == about):
				name = str(d.get("name", f))
		if name.is_empty() or (row.get("about", "") is Array and not (row["about"] as Array).has(about)):
			continue
		if str(row["gives"]) == "advantage":
			out["adv"] = name
			continue
		if str(row["gives"]) == "plus":
			out["label"] = name
			out["bonus"] = int(out["bonus"]) + int(row["n"])
			continue
		var pb := CharacterRules.prof_bonus(me, data)
		var proficient := not skill.is_empty() and ((me.get("skill_profs", []) as Array).has(skill) or CharacterRules.has_feature(me, "skill_prof_" + skill))
		if (me.get("expertise", []) as Array).has(skill):
			continue
		out["label"] = name
		out["bonus"] = pb if proficient else (2 * pb if bool(row.get("proficient", false)) else 0)
	return out


## Reasons as a list: a text joined by «, », or a list.
static func whys(v: Variant) -> Array[String]:
	var out: Array[String] = []
	if v is Array:
		for x: Variant in v:
			_add(out, str(x))
	elif v != null:
		for x: String in str(v).split(", ", false):
			_add(out, x)
	return out


static func _add(out: Array[String], why: String) -> void:
	if not why.is_empty() and not out.has(why):
		out.append(why)


# --- the engine.check card ---------------------------------------------------------------------------------------


## The hero's check by engine.check `params` (skill, save or a bare ability, dc_tier; an engine-set `dc`; the reasons
## `advantage_reason` — the master's, with a reason the card shows —, `disadvantage_reason`, `auto_fail_reason`; `tool`,
## `target_id`, `sense`): {spec, dc_reason} for Roll.check, or {error}. `parts` — the bonus's labelled parts when the
## rule has its own (thieves' tools); the game's difficulty is added to them.
static func spec(s: GameSession, data: Dictionary, params: Dictionary, parts: Array[Dictionary] = []) -> Dictionary:
	var rules: Dictionary = data["rules"]
	var tiers: Dictionary = rules["dc_tiers"]
	var tier := str(params.get("dc_tier", ""))
	if not tiers.has(tier):
		return {"error": "unknown dc_tier: %s" % tier}
	var skill := str(params.get("skill", "")) if params.get("skill") != null else ""
	var save := str(params.get("save", "")) if params.get("save") != null else ""
	var ability := str(params.get("ability", ""))  # a bare ability check, the player's pick (v0.7.36)
	if [skill, save, ability].filter(func(x: String) -> bool: return not x.is_empty()).size() != 1:
		return {"error": "exactly one of skill or save is required"}
	if not ability.is_empty() and not (rules["saves"] as Array).has(ability):
		return {"error": "unknown ability: %s" % ability}
	if not skill.is_empty() and not (rules["skills"] as Dictionary).has(skill):
		return {"error": "unknown skill: %s" % skill}
	if not save.is_empty() and not (rules["saves"] as Array).has(save):
		return {"error": "unknown save: %s" % save}
	var out := {"quiet": true}  # the card is its own breakdown
	for k: String in ["skill", "save", "ability", "tool", "target_id", "sense", "about"]:
		if params.get(k) != null and not str(params.get(k, "")).is_empty():
			out[k] = str(params[k])
	out["adv_why"] = params.get("advantage_reason")
	out["dis_why"] = params.get("disadvantage_reason")
	out["fail_why"] = params.get("auto_fail_reason")
	var dc_reason := str(params.get("dc_reason", ""))
	out["dc"] = int(params["dc"]) if params.has("dc") else int(tiers[tier])
	if not params.has("dc"):
		var by_npc := SocialRules.dc(s, data, listener(s, data, params), skill, tier)  # v0.7.15.1: the listener's template
		if not by_npc.is_empty():
			out["dc"] = int(by_npc["dc"])
			dc_reason = str(by_npc["reason"])
	if not parts.is_empty():
		var all := parts.duplicate()
		RollParts.difficulty(s, data, all)
		out["parts"] = all
	return {"spec": out, "dc_reason": dc_reason}


## The engine.check result of the hero, by `params` as in `spec`: {check_id, rolls, nat, bonus, total, dc, success,
## blocked, parts} and the reasons and notes the card shows, or {error}.
static func card(s: GameSession, data: Dictionary, params: Dictionary, parts: Array[Dictionary] = []) -> Dictionary:
	var sp := spec(s, data, params, parts)
	if sp.has("error"):
		return sp
	var r := Roll.check(s, data, Sheet.HERO, sp["spec"])
	var out := {"check_id": s.next_check_id(), "rolls": r["rolls"], "bonus": r["bonus"], "total": r["total"], "dc": r["dc"],
		"success": r["ok"], "nat": r["nat"], "blocked": false, "parts": r["parts"]}
	for k: String in ["adv", "dis", "fail"]:
		if not (r[k] as Array).is_empty():
			out[{"adv": "advantage_reason", "dis": "disadvantage_reason", "fail": "auto_fail_reason"}[k]] = ", ".join(r[k])
	if not str(sp["dc_reason"]).is_empty():
		out["dc_reason"] = sp["dc_reason"]
	if DifficultyRules.bonus(s, data) != 0:
		out["difficulty_note"] = DifficultyRules.note(s, data)
	return out


## What the engine would roll for `params`: {dc, bonus, chance (%), dc_reason}, or {error}. Nothing is rolled or spent.
static func preview(s: GameSession, data: Dictionary, params: Dictionary) -> Dictionary:
	var sp := spec(s, data, params)
	if sp.has("error"):
		return sp
	var odds := Roll.odds(s, data, Sheet.HERO, sp["spec"])
	return {"dc": int(sp["spec"]["dc"]), "bonus": odds["bonus"], "chance": odds["chance"], "dc_reason": sp["dc_reason"]}
