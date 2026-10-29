class_name CraftRules
extends RefCounted
## Crafting (roadmap v0.7.24, rules.craft): a recipe is data — a tool, a station (a room tag), hours, a DC, materials
## and an output. The hero knows the recipes of the tools it is proficient with; a `learn` one comes from a lesson
## (service op teach_recipe), a carried book (item `teaches`) or the master (effect `recipe`). One project at a time
## (c.craft {recipe, done, total}): the materials go at the start, the work goes in shifts, the check at the end sets
## the quality. Salvage gives materials back; gathering takes raw ones from the world's room tags.


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"]["craft"]


## Every recipe the game knows: the rules', the pack's (world.json `recipes`), the master's made ones, and the
## template recipes the hero may see now (v0.7.39.1).
static func all(s: GameSession, data: Dictionary) -> Dictionary:
	var out := _plain(s, data)
	if s != null:
		out.merge(templated(s, data), true)
	return out


static func _plain(s: GameSession, data: Dictionary) -> Dictionary:
	var out: Dictionary = (cfg(data)["recipes"] as Dictionary).duplicate()
	out.merge(data["world"].get("recipes", {}), true)
	if s != null:
		out.merge(WorldGen.generated(s).get("recipes", {}), true)
	return out


static func recipe(s: GameSession, data: Dictionary, id: String) -> Dictionary:
	if id.begins_with(TPL):
		var parts := id.split(":")
		return template_recipe(s, data, parts[1], parts[2] if parts.size() > 2 else "", parts[3] if parts.size() > 3 else "")
	return _plain(s, data).get(id, {})


# --- skills of the peaceful directions (v0.7.39.1) ----------------------------------------------------------------


## The direction a recipe grows: `dir`, «Артефакция» for a template, «Ремесло» otherwise.
static func dir_of(r: Dictionary) -> String:
	return str(r.get("dir", "craft"))


## The skills a recipe asks that the hero has not taken: [«Ковка одноручного оружия»].
static func skills_missing(c: Dictionary, data: Dictionary, r: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for need: Variant in r.get("skills", []):
		var bits := str(need).split(":")
		if bits.size() < 2 or DevelopmentRules.skills(c, bits[0]).has(bits[1]):
			continue
		var d := DevelopmentRules.direction(data, bits[0])
		out.append("%s (%s)" % [str(d.get("skills", {}).get(bits[1], {}).get("name", bits[1])), str(d.get("name", bits[0]))])
	return out


static func _fx(c: Dictionary, data: Dictionary, r: Dictionary, key: String, default: Variant) -> Variant:
	return DevelopmentRules.effect(c, data, dir_of(r), key, default)


## The minutes of the work for this hero: the recipe's, faster by the direction's skills.
static func work_minutes(c: Dictionary, data: Dictionary, r: Dictionary) -> int:
	return maxi(1, roundi(minutes_of(r) * float(_fx(c, data, r, "hours_mult", 1.0))))


## The experience of a finished recipe in its direction: hours × per_hour + the output's gold × per_gp, up to max.
static func xp_for(s: GameSession, data: Dictionary, r: Dictionary) -> int:
	var src: Dictionary = DevelopmentRules.direction(data, dir_of(r)).get("sources", {})
	var gp := int(ItemRules.def_of(data["items"], s.items, str(r.get("output", ""))).get("value_cp", 0)) * int(r.get("qty", 1)) / 100
	var xp := minutes_of(r) * float(src.get("per_hour", 0)) / 60.0 + gp * float(src.get("per_gp", 0))
	return mini(int(src.get("max", 0)), maxi(1, roundi(xp)))


# --- templates: «Артефакция» (v0.7.39.1) ---------------------------------------------------------------------------


const TPL := "tpl:"


static func _templates(data: Dictionary) -> Dictionary:
	return cfg(data).get("templates", {})


## A catalog item fits a template's `match`: its type, a property, an id prefix, a scroll, a plain weapon.
static func _fits(data: Dictionary, t: Dictionary, item_id: String) -> bool:
	var d: Dictionary = data["items"]["catalog"].get(item_id, {})
	if d.is_empty() or bool(d.get("master", false)):
		return false
	var m: Dictionary = t.get("match", {})
	if m.has("item_type") and str(d.get("item_type", "")) != str(m["item_type"]):
		return false
	if m.has("prop") and not (d.get("properties", []) as Array).has(str(m["prop"])):
		return false
	if m.has("prefix") and not item_id.begins_with(str(m["prefix"])):
		return false
	if bool(m.get("scroll", false)) and not bool(d.get("use", {}).get("scroll", false)):
		return false
	if bool(m.get("plain", false)) and (not d.has("weapon") or d.has("rarity") or d.has("base")):
		return false
	if not bool(m.get("plain", false)) and not cfg(data)["by_rarity"].has(str(d.get("rarity", ""))):
		return false
	if bool(t.get("from_base", false)) and str(d.get("base", "")).is_empty():
		return false
	return bool(t.get("from_self", false)) or not _made_by_plain(data, item_id)  # a new thing is made of a plain one


## A thing an ordinary recipe already makes (the healing potion) is no template's.
static func _made_by_plain(data: Dictionary, item_id: String) -> bool:
	for r: Dictionary in (cfg(data)["recipes"] as Dictionary).values():
		if str(r.get("output", "")) == item_id:
			return true
	return false


## The ordinary recipe of a thing (one at a time): its tool, station and skills a template takes over.
static func _base_recipe(s: GameSession, data: Dictionary, item_id: String) -> Dictionary:
	for r: Dictionary in _plain(s, data).values():
		if str(r.get("output", "")) == item_id and int(r.get("qty", 1)) == 1:
			return r
	return {}


## A template's recipe for `item_id` (and the variant of `from_self`): {} when it does not fit.
static func template_recipe(s: GameSession, data: Dictionary, tid: String, item_id: String, variant: String = "") -> Dictionary:
	var t: Dictionary = _templates(data).get(tid, {})
	if t.is_empty() or not _fits(data, t, item_id):
		return {}
	var catalog: Dictionary = data["items"]["catalog"]
	var d: Dictionary = catalog[item_id]
	var base := item_id if bool(t.get("from_self", false)) else str(d.get("base", ""))
	var br := _base_recipe(s, data, base) if not base.is_empty() else {}
	var rarity := str(t.get("rarity", d.get("rarity", "common")))
	var by: Dictionary = cfg(data)["by_rarity"].get(rarity, {})
	var c: Dictionary = s.character if s != null else {}
	var r := {"dir": "artifice", "template": tid, "dc": int(by.get("dc", 12)), "hours": int(by.get("hours", 8)), "output": item_id, "qty": 1}
	r["tool"] = str(br.get("tool", t.get("tool_default", ""))) if str(t.get("tool", "")) == "$base" else str(t.get("tool", ""))
	r["station"] = str(br.get("station", t.get("station_default", ""))) if str(t.get("station", "")) == "$base" else str(t.get("station", ""))
	if t.has("check"):
		r["check"] = str(t["check"])
	var skills: Array = (t.get("skills", []) as Array).duplicate()
	for sk: Variant in br.get("skills", []):
		if not skills.has(sk):
			skills.append(sk)
	r["skills"] = skills
	var mats: Dictionary = (t.get("materials", {}) as Dictionary).duplicate()
	if not base.is_empty():
		mats[base] = int(mats.get(base, 0)) + 1
	var dust := int(ceil(int(by.get("dust", 0)) * float(DevelopmentRules.effect(c, data, "artifice", "dust_mult", 1.0))))
	if dust > 0:
		mats[str(cfg(data)["dust"])] = dust
	r["materials"] = mats
	if bool(t.get("learn", false)):
		r["learn"] = true
	if bool(t.get("from_self", false)):
		var variants: Dictionary = t.get("variants", {})
		if not variants.has(variant):
			return {}
		var base_def := ItemRules.def_of(data["items"], {}, item_id)
		var props: Array = (base_def.get("properties", []) as Array).duplicate()
		props.append(variant)
		var def := {"name": "%s (%s)" % [base_def.get("name", item_id), variants[variant]], "item_type": str(base_def.get("item_type", "weapon")),
			"base": item_id, "rarity": rarity, "value_cp": int(t.get("value_cp", 0)), "properties": props,
			"description": str(base_def.get("description", "")), "generated": true}
		r["output"] = ItemRules.generated_id(def)
		r["output_def"] = def
		r["name"] = str(def["name"])
	else:
		r["name"] = str(d.get("name", item_id))
	return r


## The template recipes shown now: of a base the hero carries, a spell it knows, a learned formula, or any for a
## template without a base — only when the hero has the template's own skills (a learned formula always).
static func templated(s: GameSession, data: Dictionary) -> Dictionary:
	var out := {}
	var c := s.character
	var inv: Dictionary = c.get("inventory", {})
	var catalog: Dictionary = data["items"]["catalog"]
	var formulas: Array = learned(c).duplicate()
	formulas.append_array(from_books(s, data))
	for f: Variant in formulas:
		var parts := str(f).split(":")
		if str(f).begins_with(TPL) and parts.size() >= 3:
			var r := template_recipe(s, data, parts[1], parts[2], parts[3] if parts.size() > 3 else "")
			if not r.is_empty():
				out[str(f)] = r
	for tid: String in _templates(data):
		var t: Dictionary = _templates(data)[tid]
		if bool(t.get("learn", false)) or not skills_missing(c, data, {"skills": t.get("skills", [])}).is_empty():
			continue
		if bool(t.get("from_self", false)):
			for id: String in inv:
				for v: String in t.get("variants", {}):
					var r := template_recipe(s, data, tid, id, v)
					if not r.is_empty():
						out["%s%s:%s:%s" % [TPL, tid, id, v]] = r
			continue
		for id: String in catalog:
			if not _fits(data, t, id):
				continue
			if bool(t.get("from_base", false)) and int(inv.get(str(catalog[id]["base"]), 0)) <= 0:
				continue
			if bool(t.get("spell_known", false)) and not StudyRules._knows_spell(c, str(catalog[id].get("use", {}).get("spell", ""))):
				continue
			out["%s%s:%s" % [TPL, tid, id]] = template_recipe(s, data, tid, id)
	return out


static func recipe_name(s: GameSession, data: Dictionary, id: String) -> String:
	var r := recipe(s, data, id)
	if r.has("name"):
		return str(r["name"])
	return ItemRules.display_name(data["items"], s.items if s != null else {}, str(r.get("output", id)))


static func tool_of(r: Dictionary) -> String:
	return str(r.get("tool", ""))


## A simple recipe (v0.7.25, a roast, a stew): anyone knows it and cooks without the tool.
static func simple(r: Dictionary) -> bool:
	return bool(r.get("simple", false))


## The work of a recipe in minutes: `minutes` (dishes) or `hours`.
static func minutes_of(r: Dictionary) -> int:
	return int(r["minutes"]) if r.has("minutes") else int(r.get("hours", 1)) * 60


static func proficient(c: Dictionary, tool: String) -> bool:
	return (c.get("tools", []) as Array).has(tool)


## The recipe needs its tool in hand: not a simple dish, not a tool-less template (a scroll, a wondrous thing).
static func needs_tool(r: Dictionary) -> bool:
	return not simple(r) and not tool_of(r).is_empty()


static func learned(c: Dictionary) -> Array:
	if not (c.get("recipes") is Array):
		c["recipes"] = []
	return c["recipes"]


## The recipes a carried book teaches.
static func from_books(s: GameSession, data: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for id: String in s.character.get("inventory", {}):
		for r: Variant in ItemRules.def_of(data["items"], s.items, id).get("teaches", []):
			if not out.has(str(r)):
				out.append(str(r))
	return out


## The recipes the hero can make now or later: by the proficiency of the tool, `learn` ones only learned or in a book.
static func known(s: GameSession, data: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var books := from_books(s, data)
	var recipes := all(s, data)
	for id: String in recipes:
		var r: Dictionary = recipes[id]
		if needs_tool(r) and not proficient(s.character, tool_of(r)):
			continue
		if bool(r.get("learn", false)) and not learned(s.character).has(id) and not books.has(id):
			continue
		out.append(id)
	return out


static func station_name(data: Dictionary, station: String) -> String:
	return str(cfg(data)["stations"].get(station, {}).get("name", station))


## A station's `tags` count as it (v0.7.25), a `wild` one is anywhere outside a settlement (a campfire).
static func station_here(s: GameSession, data: Dictionary, station: String) -> bool:
	if station.is_empty():
		return true
	var st: Dictionary = cfg(data)["stations"].get(station, {})
	var tags: Array = SceneRules.room(s, data["world"], s.room_id).get("tags", [])
	if tags.has(station) or (st.get("tags", []) as Array).any(func(t: Variant) -> bool: return tags.has(t)):
		return true
	return bool(st.get("wild", false)) and not ReputationRules.is_settlement(data, WorldView.new(data["world"]).location_id(s.room_id))


## The trader of the room who owns the station and takes rent per hour: {npc, cp} or {} (free).
static func rent(s: GameSession, data: Dictionary, station: String) -> Dictionary:
	var pct := float(DevelopmentRules.effect(s.character, data, "craft", "rent_pct", 100.0))
	var cp := roundi(int(cfg(data)["stations"].get(station, {}).get("rent_cp_hour", 0)) * pct / 100.0)
	if station.is_empty() or cp <= 0:
		return {}
	for npc_id: String in SceneRules.npcs(s, data["world"], s.room_id):
		if bool(data["world"]["npcs"].get(npc_id, {}).get("trader", false)):
			return {"npc": npc_id, "cp": cp}
	return {}


## What is missing for `r` (materials): {item: missing qty}.
static func missing(s: GameSession, r: Dictionary) -> Dictionary:
	var out := {}
	var inv: Dictionary = s.character.get("inventory", {})
	for m: String in r.get("materials", {}):
		var need := int(r["materials"][m])
		if int(inv.get(m, 0)) < need:
			out[m] = need - int(inv.get(m, 0))
	return out


## "" when the recipe can be started here, else a localization key.
static func why_not(s: GameSession, data: Dictionary, id: String) -> String:
	var unfree := EncounterRules.unfree_why(s)
	if not unfree.is_empty():
		return unfree
	var r := recipe(s, data, id)
	if r.is_empty() or not known(s, data).has(id):
		return "CRAFT_UNKNOWN"
	if not project(s.character).is_empty():
		return "CRAFT_BUSY"
	if not skills_missing(s.character, data, r).is_empty():
		return "CRAFT_NO_SKILL"
	if needs_tool(r) and int(s.character.get("inventory", {}).get(tool_of(r), 0)) <= 0:
		return "CRAFT_NO_TOOL"
	if not station_here(s, data, str(r.get("station", ""))):
		return "CRAFT_NO_STATION"
	if not missing(s, r).is_empty():
		return "CRAFT_NO_MATERIALS"
	return ""


static func project(c: Dictionary) -> Dictionary:
	return c.get("craft", {}) if c.get("craft") is Dictionary else {}


## The materials go, the project starts. Lines.
static func start(s: GameSession, data: Dictionary, id: String) -> Array[String]:
	var r := recipe(s, data, id)
	var spent: Array[String] = []
	for m: String in r.get("materials", {}):
		var n := int(r["materials"][m])
		for i in n:
			ItemRules._remove_one(s.character, m)
		spent.append("%s ×%d" % [ItemRules.display_name(data["items"], s.items, m), n])
	var total := work_minutes(s.character, data, r)
	if r.has("output_def"):  # a new thing of a template (an elemental blade): known to the session from the start
		s.items[str(r["output"])] = r["output_def"]
	s.character["craft"] = {"recipe": id, "done": 0, "total": total}
	return ["Начата работа: %s (%s); ушло: %s" % [recipe_name(s, data, id), TimeRules.span(total), ", ".join(spent)]]


## "" when a shift of work may go here, else a localization key.
static func can_work(s: GameSession, data: Dictionary) -> String:
	var unfree := EncounterRules.unfree_why(s)
	if not unfree.is_empty():
		return unfree
	var p := project(s.character)
	if p.is_empty():
		return "CRAFT_NO_PROJECT"
	var r := recipe(s, data, str(p["recipe"]))
	if needs_tool(r) and int(s.character.get("inventory", {}).get(tool_of(r), 0)) <= 0:
		return "CRAFT_NO_TOOL"
	if not station_here(s, data, str(r.get("station", ""))):
		return "CRAFT_NO_STATION"
	var rent_now := rent(s, data, str(r.get("station", "")))
	if not rent_now.is_empty() and int(s.character.get("gold_cp", 0)) < int(rent_now["cp"]):
		return "CRAFT_NO_RENT"
	return ""


## Minutes of the next shift of up to `hours`: what is left of the work, the rent the hero can pay.
static func shift_minutes(s: GameSession, data: Dictionary, hours: int) -> int:
	var p := project(s.character)
	if p.is_empty():
		return 0
	var mins := mini(hours * 60, int(p["total"]) - int(p["done"]))
	var r := recipe(s, data, str(p["recipe"]))
	var rent_now := rent(s, data, str(r.get("station", "")))
	if not rent_now.is_empty():
		var can_hours := int(s.character.get("gold_cp", 0)) / int(rent_now["cp"])
		mins = mini(mins, can_hours * 60)
	return maxi(0, mins)


## A shift done (the time already passed): the progress, the rent, the end of the work. Lines.
static func worked(s: GameSession, data: Dictionary, minutes: int) -> Array[String]:
	var p := project(s.character)
	var r := recipe(s, data, str(p["recipe"]))
	var lines: Array[String] = []
	var rent_now := rent(s, data, str(r.get("station", "")))
	if not rent_now.is_empty() and minutes > 0:
		var cp := int(ceil(minutes / 60.0)) * int(rent_now["cp"])
		s.character["gold_cp"] = int(s.character["gold_cp"]) - cp
		lines.append("Плата за %s: −%s" % [station_name(data, str(r["station"])).to_lower(), Money.format(cp)])
	p["done"] = int(p["done"]) + minutes
	if int(p["done"]) >= int(p["total"]):
		lines.append_array(finish(s, data))
	else:
		lines.append("Работа: %s — %d%%, осталось %s" % [recipe_name(s, data, str(p["recipe"])), progress(s.character), TimeRules.span(int(p["total"]) - int(p["done"]))])
	return lines


static func progress(c: Dictionary) -> int:
	var p := project(c)
	return 0 if p.is_empty() else int(100.0 * int(p["done"]) / maxf(1.0, float(p["total"])))


## The bonus of the craft check with `tool`: its ability, the proficiency (when proficient), the game's difficulty.
static func bonus(s: GameSession, data: Dictionary, tool: String) -> int:
	return RollParts.sum(bonus_parts(s, data, tool))


static func bonus_parts(s: GameSession, data: Dictionary, tool: String) -> Array[Dictionary]:
	return RollParts.tool(s, data, tool, str(cfg(data)["tools"].get(tool, "int")))


## The bonus of a recipe's check: its tool's, or a tool-less template's skill (`check`), with the direction's skills.
static func recipe_bonus(s: GameSession, data: Dictionary, r: Dictionary) -> int:
	return RollParts.sum(recipe_parts(s, data, r))


static func recipe_parts(s: GameSession, data: Dictionary, r: Dictionary) -> Array[Dictionary]:
	var out := RollParts.skill(s, data, str(r["check"])) if tool_of(r).is_empty() and r.has("check") else bonus_parts(s, data, tool_of(r))
	RollParts.development(s.character, data, dir_of(r), "quality_bonus", out)
	return out


## The label of a recipe's check: the tool or the skill.
static func check_label(data: Dictionary, r: Dictionary) -> String:
	if tool_of(r).is_empty() and r.has("check"):
		return tr_skill(data, str(r["check"]))
	return BackgroundRules.tool_name(data, tool_of(r))


## The chance in % of at least the normal quality (a margin of the normal tier).
static func chance(s: GameSession, data: Dictionary, id: String) -> int:
	var r := recipe(s, data, id)
	var need := int(r.get("dc", 10)) + int(tier_by_id(data, "normal").get("from", 0))
	var wins := 0
	for nat in range(1, 21):
		if nat == 20 or (nat != 1 and nat + recipe_bonus(s, data, r) >= need):
			wins += 1
	var p := wins / 20.0
	if bool(_fx(s.character, data, r, "quality_adv", false)):
		p = 1.0 - (1.0 - p) * (1.0 - p)
	return roundi(p * 100.0)


static func tier_by_id(data: Dictionary, id: String) -> Dictionary:
	for t: Dictionary in cfg(data)["quality"]:
		if str(t["id"]) == id:
			return t
	return {}


## The tier of a margin (the total minus the DC): the last one whose `from` is reached.
static func tier_for(data: Dictionary, margin: int) -> Dictionary:
	var out: Dictionary = cfg(data)["quality"][0]
	for t: Dictionary in cfg(data)["quality"]:
		if margin >= int(t["from"]):
			out = t
	return out


## The check at the end of the work and the thing it makes. Lines.
static func finish(s: GameSession, data: Dictionary) -> Array[String]:
	var c := s.character
	var p := project(c)
	var id := str(p["recipe"])
	var r := recipe(s, data, id)
	var mods := ConditionRules.check_mods(c, data, {"skill": "craft"})
	var adv := bool(_fx(c, data, r, "quality_adv", false))
	var dis := not (mods["disadvantage"] as Array).is_empty()
	var rolls := FeatureRules.hero_d20(s, adv, dis)
	var nat: int = rolls.max() if adv and not dis else rolls.min()
	var parts := recipe_parts(s, data, r)
	var total := nat + RollParts.sum(parts)
	var dc := int(r.get("dc", 10))
	RollParts.note(s, check_label(data, r), rolls, nat, parts, total - nat, dc)
	var margin := 10 if nat == 20 else -10 if nat == 1 else total - dc
	var tier := tier_for(data, margin)
	c.erase("craft")
	if r.has("output_def") and not s.items.has(str(r["output"])):
		s.items[str(r["output"])] = r["output_def"]
	var made := make_output(s, data, str(r["output"]), int(r.get("qty", 1)), tier)
	var inv: Dictionary = c["inventory"]
	inv[str(made["id"])] = int(inv.get(str(made["id"]), 0)) + int(made["qty"])
	CharacterRules.refresh(c, data, s.items)
	var made_as := str(tier["name"]) if not str(tier["name"]).is_empty() else "обычная работа"
	var line := "%s: %d + %d = %d против Сл %d — %s" % [check_label(data, r), nat, total - nat, total, dc, made_as]
	var what := ItemRules.display_name(data["items"], s.items, str(made["id"]))
	var lines: Array[String] = [line, "Готово: %s%s" % [what, " ×%d" % int(made["qty"]) if int(made["qty"]) > 1 else ""]]
	lines.append_array(DevelopmentRules.add_xp(c, data, dir_of(r), xp_for(s, data, r)))
	return lines


## The output of `tier`: a stack changes its qty; a single thing of another quality is a thing of the session with
## the tier's suffix, value and properties. {id, qty}.
static func make_output(s: GameSession, data: Dictionary, out_id: String, qty: int, tier: Dictionary) -> Dictionary:
	var base := ItemRules.def_of(data["items"], s.items, out_id)
	if str(tier.get("id", "normal")) == "normal":
		return {"id": out_id, "qty": qty}
	if bool(base.get("stack", false)) or qty > 1:
		return {"id": out_id, "qty": maxi(1, int(floor(qty * float(tier.get("qty", 1.0)))))}
	var props: Array = []
	var by_type: Dictionary = tier.get("props", {})
	var kind := "weapon" if base.has("weapon") else "armor" if base.has("armor") else str(base.get("item_type", ""))
	for prop: Variant in by_type.get(kind, []):
		props.append(str(prop))
	var def := {"name": "%s (%s)" % [base.get("name", out_id), tier["name"]], "item_type": str(base.get("item_type", "gear")), "base": out_id,
		"rarity": str(base.get("rarity", "common")), "value_cp": int(round(int(base.get("value_cp", 0)) * float(tier.get("value", 1.0)))),
		"properties": props, "description": str(base.get("description", "")), "generated": true, "quality": str(tier["id"])}
	var new_id := ItemRules.generated_id(def)
	s.items[new_id] = def
	return {"id": new_id, "qty": 1}


## Drops the project (the materials are gone). Lines.
static func abandon(s: GameSession, data: Dictionary) -> Array[String]:
	var p := project(s.character)
	if p.is_empty():
		return []
	s.character.erase("craft")
	return ["Работа брошена: %s" % recipe_name(s, data, str(p["recipe"]))]


# --- salvage ------------------------------------------------------------------------------------------------------


## The materials a thing gives back: a recipe's `share` (floor, at least 1 of the first; «Бережливый» — all) or
## salvage.extra; a magic thing adds arcane dust by its rarity (v0.7.39.1). {} — none.
static func salvage_yield(s: GameSession, data: Dictionary, item_id: String) -> Dictionary:
	var def := ItemRules.def_of(data["items"], s.items, item_id)
	var base := _root_base(data, s, item_id)
	var out := _base_yield(s, data, base)
	var dust := magic_dust(s, data, item_id)
	if dust > 0:
		var key := str(cfg(data)["dust"])
		out[key] = int(out.get(key, 0)) + dust
	return out if not def.is_empty() else {}


## The mundane thing under a made or magic one: a +1 sword's, an elemental blade's, a fine dagger's base.
static func _root_base(data: Dictionary, s: GameSession, item_id: String) -> String:
	var id := item_id
	for i in 3:
		var d := ItemRules.def_of(data["items"], s.items, id)
		if str(d.get("base", "")).is_empty():
			return id
		id = str(d["base"])
	return id


static func _base_yield(s: GameSession, data: Dictionary, base: String) -> Dictionary:
	var sv: Dictionary = cfg(data)["salvage"]
	var share := float(DevelopmentRules.effect(s.character, data, "craft", "salvage_share", float(sv["share"])))
	for r: Dictionary in _plain(s, data).values():
		if str(r.get("output", "")) != base or int(r.get("qty", 1)) != 1:
			continue
		var out := {}
		for m: String in r.get("materials", {}):
			var n := int(floor(int(r["materials"][m]) * share))
			if n > 0:
				out[m] = n
		if out.is_empty() and not (r.get("materials", {}) as Dictionary).is_empty():
			out[(r["materials"] as Dictionary).keys()[0]] = 1
		return out
	var extra := {}
	for m: String in sv["extra"].get(base, {}):
		extra[m] = int(sv["extra"][base][m])
	return extra


## The arcane dust of a magic thing (a rarity of salvage.dust; the catalog's own or a made thing's), 0 — none.
static func magic_dust(s: GameSession, data: Dictionary, item_id: String) -> int:
	var id := ItemRules.real_id(item_id)
	var raw: Dictionary = data["items"]["catalog"].get(id, s.items.get(id, {}))
	var rarity := str(raw.get("rarity", ""))
	var magic_props := (raw.get("properties", []) as Array).filter(func(p: Variant) -> bool: return not ["masterwork", "crude"].has(str(p)))
	if rarity.is_empty() or (rarity == "common" and magic_props.is_empty()):  # a mundane thing, a fine or crude make
		return 0
	return int(cfg(data)["salvage"].get("dust", {}).get(rarity, 0))


## The hero's things that can be broken down (not worn or in hand, not raw material, not a bag).
static func salvageable(s: GameSession, data: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var worn: Array = (s.character.get("equipped", {}) as Dictionary).values()
	for id: String in s.character.get("inventory", {}):
		if worn.has(id) or salvage_yield(s, data, id).is_empty() or ItemRules.held_by_curse(s.character, data, s.items, id):
			continue
		var d := ItemRules.def_of(data["items"], s.items, id)
		if bool(d.get("material", false)) or str(d.get("item_type", "")) == "consumable" or ContainerRules.is_carried_kind(data, id):
			continue  # raw stuff stays raw; a dish or a potion is not taken apart; a bag may hold things
		out.append(id)
	return out


## One thing broken into its materials. Lines.
static func salvage(s: GameSession, data: Dictionary, item_id: String) -> Array[String]:
	var got := salvage_yield(s, data, item_id)
	var name := ItemRules.display_name(data["items"], s.items, item_id)
	var magic := magic_dust(s, data, item_id) > 0
	ItemRules._remove_one(s.character, item_id)
	var inv: Dictionary = s.character["inventory"]
	var parts: Array[String] = []
	for m: String in got:
		inv[m] = int(inv.get(m, 0)) + int(got[m])
		parts.append("%s ×%d" % [ItemRules.display_name(data["items"], s.items, m), int(got[m])])
	CharacterRules.refresh(s.character, data, s.items)
	var lines: Array[String] = ["Разобрано: %s → %s" % [name, ", ".join(parts)]]
	if magic:
		lines.append_array(DevelopmentRules.add_xp(s.character, data, "artifice", int(DevelopmentRules.direction(data, "artifice").get("sources", {}).get("salvage", 0))))
	return lines


## Raw hides of a dead beast (into the fight's loot): by its size, rules.craft.hides.
static func hides(data: Dictionary, monster: Dictionary) -> int:
	if str(monster.get("type", "")) != "beast":
		return 0
	return int(cfg(data)["hides"].get(str(monster.get("size", "medium")), 0))


## Raw meat from a dead beast by its size (v0.7.25).
static func meat(data: Dictionary, monster: Dictionary) -> int:
	if str(monster.get("type", "")) != "beast":
		return 0
	return int(cfg(data).get("meat", {}).get(str(monster.get("size", "medium")), 0))


# --- gathering ----------------------------------------------------------------------------------------------------


## The gathering spots of the room: the room tags of rules.craft.gather.
static func gather_here(s: GameSession, data: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var g: Dictionary = cfg(data)["gather"]
	for t: Variant in SceneRules.room(s, data["world"], s.room_id).get("tags", []):
		if g.has(str(t)):
			out.append(str(t))
	return out


static func _gathered(s: GameSession) -> Dictionary:
	if not (s.character.get("gathered") is Dictionary):
		s.character["gathered"] = {}
	return s.character["gathered"]


## "" or a localization key: the spot is spent for today.
static func gather_why(s: GameSession, data: Dictionary, tag: String) -> String:
	var unfree := EncounterRules.unfree_why(s)
	if not unfree.is_empty():
		return unfree
	var g: Dictionary = cfg(data)["gather"].get(tag, {})
	if g.is_empty() or not gather_here(s, data).has(tag):
		return "GATHER_NONE"
	var rec: Dictionary = _gathered(s).get("%s:%s" % [s.room_id, tag], {})
	if int(rec.get("day", -1)) == s.day and int(rec.get("n", 0)) >= int(g.get("per_day", 1)):
		return "GATHER_SPENT"
	return ""


## A gathering try (the caller passes the time): the check, the raw material on a success. Lines.
static func gather(s: GameSession, data: Dictionary, tag: String) -> Array[String]:
	var g: Dictionary = cfg(data)["gather"][tag]
	var key := "%s:%s" % [s.room_id, tag]
	var rec: Dictionary = _gathered(s).get(key, {})
	if int(rec.get("day", -1)) != s.day:
		rec = {"day": s.day, "n": 0}
	rec["n"] = int(rec["n"]) + 1
	_gathered(s)[key] = rec
	var skill := str(g["skill"])
	var t := BackgroundRules.tool_check(s.character, data, str(g.get("tool", "")), skill)
	var mods := ConditionRules.check_mods(s.character, data, {"skill": skill})
	var adv := not str(t["advantage"]).is_empty()
	var dis := not (mods["disadvantage"] as Array).is_empty()
	var rolls := FeatureRules.hero_d20(s, adv, dis)
	var nat: int = rolls.max() if adv and not dis else rolls.min() if dis and not adv else rolls[0]
	var b := int(s.character.get("skills", {}).get(skill, 0)) + int(t["bonus"]) + DifficultyRules.bonus(s, data)
	var dc := int(g["dc"])
	var parts := RollParts.skill(s, data, skill)
	RollParts.add(parts, str(t["note"]), int(t["bonus"]))
	RollParts.note(s, str(g["name"]), rolls, nat, parts, b, dc)
	var ok := nat == 20 or (nat != 1 and nat + b >= dc)
	var lines: Array[String] = ["%s: %s %d + %d = %d против Сл %d — %s" % [g["name"], tr_skill(data, skill), nat, b, nat + b, dc, "успех" if ok else "провал"]]
	if not ok:
		lines.append("Ничего толкового не нашлось")
		return lines
	var qty := s.rng.randi_range(int(g["qty"][0]), int(g["qty"][1]))
	var pool: Array = g.get("items", [g.get("item", "")])
	var item := str(pool[s.rng.randi_range(0, pool.size() - 1)])
	var inv: Dictionary = s.character["inventory"]
	inv[item] = int(inv.get(item, 0)) + qty
	CharacterRules.refresh(s.character, data, s.items)
	lines.append("Добыто: %s ×%d" % [ItemRules.display_name(data["items"], s.items, item), qty])
	return lines


static func tr_skill(_data: Dictionary, skill: String) -> String:
	return TranslationServer.translate("SKILL_" + skill.to_upper())


# --- learning and the master's recipes ----------------------------------------------------------------------------


## What a teach_recipe service would teach now: its recipe when the hero has the tool's proficiency and lacks it.
static func teachable(s: GameSession, data: Dictionary, sv: Dictionary) -> Array[String]:
	var id := str(sv.get("recipe", ""))
	var r := recipe(s, data, id)
	if r.is_empty() or (needs_tool(r) and not proficient(s.character, tool_of(r))) or learned(s.character).has(id):
		return []
	return [id]


static func learn(s: GameSession, data: Dictionary, id: String) -> Array[String]:
	if not learned(s.character).has(id):
		learned(s.character).append(id)
	return ["Выучен рецепт: %s" % recipe_name(s, data, id)]


## The master's recipe (effect `recipe`): checked against rules.craft.make; the output is a catalog or library item or
## a new one (ItemRules.check_generated). {id, def, item?} or {reason}.
static func make(s: GameSession, data: Dictionary, spec: Dictionary) -> Dictionary:
	var m: Dictionary = cfg(data)["make"]
	var tool := str(spec.get("tool", ""))
	if not cfg(data)["tools"].has(tool):
		return {"reason": "инструмент %s движку неизвестен; можно: %s" % [tool, ", ".join(cfg(data)["tools"].keys())]}
	if not proficient(s.character, tool) and not bool(spec.get("for_course", false)):
		return {"reason": "герой не владеет: %s — такой рецепт ему не по руке" % BackgroundRules.tool_name(data, tool)}
	var station := str(spec.get("station", "")) if spec.get("station") != null else ""
	if not station.is_empty() and not cfg(data)["stations"].has(station):
		return {"reason": "станции %s нет; можно: %s или без станции" % [station, ", ".join(cfg(data)["stations"].keys())]}
	var hours := maxi(int(spec.get("hours", 1)), int(m["hours"][0]))
	var tier := str(spec.get("dc_tier", "medium"))
	if not (m["dc_tiers"] as Array).has(tier):
		return {"reason": "dc_tier — из %s" % ", ".join(m["dc_tiers"])}
	var mats: Dictionary = spec.get("materials", {})
	if mats.is_empty() or mats.size() > int(m["materials_max"]):
		return {"reason": "materials — от 1 до %d вещей" % int(m["materials_max"])}
	var mats_cp := 0
	for id: String in mats:
		var d := ItemRules.def_of(data["items"], s.items, id)
		if d.is_empty():
			return {"reason": "материала %s нет в каталоге — найди его через find_items" % id}
		mats_cp += int(d.get("value_cp", 0)) * int(mats[id])
	var qty := clampi(int(spec.get("qty", 1)), 1, int(m["qty_max"]))
	var out_id := str(spec.get("output_id", "")) if spec.get("output_id") != null else ""
	var item := {}
	if out_id.is_empty():
		var gen: Variant = spec.get("output")
		if not (gen is Dictionary):
			return {"reason": "нужен output_id (вещь каталога) или output (новая вещь)"}
		var chk := ItemRules.check_generated(data["items"], gen, int(s.character.get("level", 1)), data.get("spells", {}))
		if not bool(chk["ok"]):
			return {"reason": str(chk["reason"])}
		item = chk["def"]
		out_id = ItemRules.generated_id(item)
	else:
		var od := ItemRules.def_of(data["items"], s.items, out_id)
		if od.is_empty():
			return {"reason": "вещи %s нет в каталоге" % out_id}
		var why := ItemRules.rarity_ok(data, od, int(s.character.get("level", 1)))
		if not why.is_empty():
			return {"reason": why}
	var out_def := item if not item.is_empty() else ItemRules.def_of(data["items"], s.items, out_id)
	hours = maxi(hours, labor_hours(data, int(out_def.get("value_cp", 0)) * qty, mats_cp))
	if hours > int(m["hours"][1]):
		return {"reason": "такая работа — %d ч, больше %d: дороже материалы (сейчас на %s) или меньше qty" % [hours, int(m["hours"][1]), Money.format(mats_cp)]}
	var name := str(spec.get("name", "")).strip_edges().left(60)
	var def := {"tool": tool, "station": station, "hours": hours, "dc": int(data["rules"]["dc_tiers"][tier]), "materials": mats.duplicate(),
		"output": out_id, "qty": qty, "learn": true, "generated": true}
	var skills := skills_for(data, tool, out_def)
	if not skills.is_empty():
		def["skills"] = skills
	if not name.is_empty():
		def["name"] = name
	var id := "gen_r_" + ("%s|%s|%s" % [tool, out_id, JSON.stringify(mats)]).md5_text().left(8)
	if learned(s.character).has(id) and not bool(spec.get("for_course", false)):
		return {"reason": "этот рецепт герой уже знает"}
	return {"id": id, "def": def, "item": item}


## A recipe spec of the protocol: `materials` [{item_id, qty}] as {item: qty}.
static func spec_of(e: Dictionary) -> Dictionary:
	var spec := e.duplicate()
	var mats := {}
	for m: Variant in e.get("materials", []):
		if m is Dictionary:
			mats[str(m.get("item_id", ""))] = int(mats.get(str(m.get("item_id", "")), 0)) + int(m.get("qty", 1))
	spec["materials"] = mats
	return spec


## The hours the work pays for an output the materials do not (v0.7.39.4, 5e: 5 gp a day of 8 hours).
static func labor_hours(data: Dictionary, out_cp: int, mats_cp: int) -> int:
	return ceili(float(maxi(0, out_cp - mats_cp)) / float(cfg(data)["make"]["labor_cp_hour"]))


## The «Ремесло» skills a recipe of this tool and output asks, by rules.craft.make.skills (the first match).
static func skills_for(data: Dictionary, tool: String, item: Dictionary) -> Array:
	for rule: Dictionary in cfg(data)["make"].get("skills", []):
		var m: Dictionary = rule["match"]
		if m.has("tool") and str(m["tool"]) != tool:
			continue
		if m.has("item_type") and str(item.get("item_type", "")) != str(m["item_type"]):
			continue
		var cat := str(item.get(str(item.get("item_type", "")), {}).get("category", "")) if item.get(str(item.get("item_type", ""))) is Dictionary else ""
		if m.has("category") and not (m["category"] as Array).has(cat):
			continue
		return (rule["skills"] as Array).duplicate()
	return []


## A recipe of the game that makes this item (the first), "" — none (v0.7.39.4: a course teaches it by the item).
static func for_item(s: GameSession, data: Dictionary, item_id: String) -> String:
	var plain := _plain(s, data)
	for id: String in plain:
		if str(plain[id].get("output", "")) == item_id:
			return id
	return ""


## The name of a recipe not stored yet (the master's, before it is applied).
static func recipe_name_of(s: GameSession, data: Dictionary, def: Dictionary, item: Dictionary) -> String:
	if def.has("name"):
		return str(def["name"])
	return str(item.get("name", "")) if not item.is_empty() else ItemRules.display_name(data["items"], s.items, str(def["output"]))


static func apply_make(s: GameSession, data: Dictionary, plan: Dictionary) -> Array[String]:
	var gen := WorldGen.generated(s)
	if not (gen.get("recipes") is Dictionary):
		gen["recipes"] = {}
	gen["recipes"][str(plan["id"])] = plan["def"]
	if not (plan.get("item", {}) as Dictionary).is_empty():
		s.items[str(plan["def"]["output"])] = plan["item"]
	return learn(s, data, str(plan["id"]))


## For the master's snapshot: what the hero can craft, the project. "" — no craft at all.
static func snapshot(s: GameSession, data: Dictionary) -> String:
	var ids := known(s, data)
	var p := project(s.character)
	if ids.is_empty() and p.is_empty():
		return ""
	var names: Array[String] = []
	for id: String in ids.slice(0, 12):
		names.append(recipe_name(s, data, id))
	var line := "Ремесло (окно «Ремесло»): %s" % ", ".join(names)
	if not p.is_empty():
		line += "; в работе: %s, %d%%" % [recipe_name(s, data, str(p["recipe"])), progress(s.character)]
	return line


## The attack of a weapon by its make: +1 masterwork, −1 crude (armor uses only the minus, on AC).
static func quality_mod(def: Dictionary) -> int:
	var props: Array = def.get("properties", [])
	return (1 if props.has("masterwork") else 0) - (1 if props.has("crude") else 0)


## Why a lesson teaches nothing now: already learned, or no proficiency with its tool.
static func teach_why(s: GameSession, data: Dictionary, sv: Dictionary) -> String:
	var id := str(sv.get("recipe", ""))
	if learned(s.character).has(id):
		return "SERVICE_LEARNED"
	return "SERVICE_NO_TOOL_PROF"
