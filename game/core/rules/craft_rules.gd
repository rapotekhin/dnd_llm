class_name CraftRules
extends RefCounted
## Crafting (roadmap v0.7.24, rules.craft): a recipe is data — a tool, a station (a room tag), hours, a DC, materials
## and an output. The hero knows the recipes of the tools it is proficient with; a `learn` one comes from a lesson
## (service op teach_recipe), a carried book (item `teaches`) or the master (effect `recipe`). One project at a time
## (c.craft {recipe, done, total}): the materials go at the start, the work goes in shifts, the check at the end sets
## the quality. Salvage gives materials back; gathering takes raw ones from the world's room tags.


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"]["craft"]


## Every recipe the game knows: the rules', the pack's (world.json `recipes`), the master's made ones.
static func all(s: GameSession, data: Dictionary) -> Dictionary:
	var out: Dictionary = (cfg(data)["recipes"] as Dictionary).duplicate()
	out.merge(data["world"].get("recipes", {}), true)
	if s != null:
		out.merge(WorldGen.generated(s).get("recipes", {}), true)
	return out


static func recipe(s: GameSession, data: Dictionary, id: String) -> Dictionary:
	return all(s, data).get(id, {})


static func recipe_name(s: GameSession, data: Dictionary, id: String) -> String:
	var r := recipe(s, data, id)
	if r.has("name"):
		return str(r["name"])
	return ItemRules.display_name(data["items"], s.items if s != null else {}, str(r.get("output", id)))


static func tool_of(r: Dictionary) -> String:
	return str(r.get("tool", ""))


static func proficient(c: Dictionary, tool: String) -> bool:
	return (c.get("tools", []) as Array).has(tool)


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
		if not proficient(s.character, tool_of(r)):
			continue
		if bool(r.get("learn", false)) and not learned(s.character).has(id) and not books.has(id):
			continue
		out.append(id)
	return out


static func station_name(data: Dictionary, station: String) -> String:
	return str(cfg(data)["stations"].get(station, {}).get("name", station))


static func station_here(s: GameSession, data: Dictionary, station: String) -> bool:
	return station.is_empty() or (SceneRules.room(s, data["world"], s.room_id).get("tags", []) as Array).has(station)


## The trader of the room who owns the station and takes rent per hour: {npc, cp} or {} (free).
static func rent(s: GameSession, data: Dictionary, station: String) -> Dictionary:
	var cp := int(cfg(data)["stations"].get(station, {}).get("rent_cp_hour", 0))
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
	var r := recipe(s, data, id)
	if r.is_empty() or not known(s, data).has(id):
		return "CRAFT_UNKNOWN"
	if not project(s.character).is_empty():
		return "CRAFT_BUSY"
	if int(s.character.get("inventory", {}).get(tool_of(r), 0)) <= 0:
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
	s.character["craft"] = {"recipe": id, "done": 0, "total": int(r.get("hours", 1)) * 60}
	return ["Начата работа: %s (%s); ушло: %s" % [recipe_name(s, data, id), TimeRules.span(int(r.get("hours", 1)) * 60), ", ".join(spent)]]


## "" when a shift of work may go here, else a localization key.
static func can_work(s: GameSession, data: Dictionary) -> String:
	var p := project(s.character)
	if p.is_empty():
		return "CRAFT_NO_PROJECT"
	var r := recipe(s, data, str(p["recipe"]))
	if int(s.character.get("inventory", {}).get(tool_of(r), 0)) <= 0:
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


## The bonus of the craft check with `tool`: its ability, the proficiency, the game's difficulty.
static func bonus(s: GameSession, data: Dictionary, tool: String) -> int:
	var ab := str(cfg(data)["tools"].get(tool, "int"))
	return CharacterRules.mod(int(s.character.get("abilities", {}).get(ab, 10))) + CharacterRules.prof_bonus(s.character, data) \
		+ DifficultyRules.bonus(s, data)


## The chance in % of at least the normal quality (a margin of the normal tier).
static func chance(s: GameSession, data: Dictionary, id: String) -> int:
	var r := recipe(s, data, id)
	var need := int(r.get("dc", 10)) + int(tier_by_id(data, "normal").get("from", 0))
	var wins := 0
	for nat in range(1, 21):
		if nat == 20 or (nat != 1 and nat + bonus(s, data, tool_of(r)) >= need):
			wins += 1
	return wins * 5


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
	var tool := tool_of(r)
	var mods := ConditionRules.check_mods(c, data, {"skill": "craft"})
	var rolls := FeatureRules.hero_d20(s, false, not (mods["disadvantage"] as Array).is_empty())
	var nat: int = rolls.min()
	var total := nat + bonus(s, data, tool)
	var dc := int(r.get("dc", 10))
	var margin := 10 if nat == 20 else -10 if nat == 1 else total - dc
	var tier := tier_for(data, margin)
	c.erase("craft")
	var made := make_output(s, data, str(r["output"]), int(r.get("qty", 1)), tier)
	var inv: Dictionary = c["inventory"]
	inv[str(made["id"])] = int(inv.get(str(made["id"]), 0)) + int(made["qty"])
	CharacterRules.refresh(c, data, s.items)
	var made_as := str(tier["name"]) if not str(tier["name"]).is_empty() else "обычная работа"
	var line := "%s: %d + %d = %d против Сл %d — %s" % [BackgroundRules.tool_name(data, tool), nat, total - nat, total, dc, made_as]
	var what := ItemRules.display_name(data["items"], s.items, str(made["id"]))
	return [line, "Готово: %s%s" % [what, " ×%d" % int(made["qty"]) if int(made["qty"]) > 1 else ""]]


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


## The materials a thing gives back: a recipe's `share` (floor, at least 1 of the first) or salvage.extra. {} — none.
static func salvage_yield(s: GameSession, data: Dictionary, item_id: String) -> Dictionary:
	var def := ItemRules.def_of(data["items"], s.items, item_id)
	var base := str(def.get("base", "")) if not str(def.get("base", "")).is_empty() else item_id
	var sv: Dictionary = cfg(data)["salvage"]
	var recipes := all(s, data)
	for rid: String in recipes:
		var r: Dictionary = recipes[rid]
		if str(r.get("output", "")) != base or int(r.get("qty", 1)) != 1:
			continue
		var out := {}
		for m: String in r.get("materials", {}):
			var n := int(floor(int(r["materials"][m]) * float(sv["share"])))
			if n > 0:
				out[m] = n
		if out.is_empty() and not (r.get("materials", {}) as Dictionary).is_empty():
			out[(r["materials"] as Dictionary).keys()[0]] = 1
		return out
	var extra := {}
	for m: String in sv["extra"].get(base, {}):
		extra[m] = int(sv["extra"][base][m])
	return extra


## The hero's things that can be broken down (not worn or in hand, not raw material, not a bag).
static func salvageable(s: GameSession, data: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var worn: Array = (s.character.get("equipped", {}) as Dictionary).values()
	for id: String in s.character.get("inventory", {}):
		if worn.has(id) or salvage_yield(s, data, id).is_empty() or ItemRules.held_by_curse(s.character, data, s.items, id):
			continue
		if bool(ItemRules.def_of(data["items"], s.items, id).get("material", false)) or ContainerRules.is_carried_kind(data, id):
			continue  # raw stuff stays raw; a bag may hold things
		out.append(id)
	return out


## One thing broken into its materials. Lines.
static func salvage(s: GameSession, data: Dictionary, item_id: String) -> Array[String]:
	var got := salvage_yield(s, data, item_id)
	var name := ItemRules.display_name(data["items"], s.items, item_id)
	ItemRules._remove_one(s.character, item_id)
	var inv: Dictionary = s.character["inventory"]
	var parts: Array[String] = []
	for m: String in got:
		inv[m] = int(inv.get(m, 0)) + int(got[m])
		parts.append("%s ×%d" % [ItemRules.display_name(data["items"], s.items, m), int(got[m])])
	CharacterRules.refresh(s.character, data, s.items)
	return ["Разобрано: %s → %s" % [name, ", ".join(parts)]]


## Raw hides of a dead beast (into the fight's loot): by its size, rules.craft.hides.
static func hides(data: Dictionary, monster: Dictionary) -> int:
	if str(monster.get("type", "")) != "beast":
		return 0
	return int(cfg(data)["hides"].get(str(monster.get("size", "medium")), 0))


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
	var ok := nat == 20 or (nat != 1 and nat + b >= dc)
	var lines: Array[String] = ["%s: %s %d + %d = %d против Сл %d — %s" % [g["name"], tr_skill(data, skill), nat, b, nat + b, dc, "успех" if ok else "провал"]]
	if not ok:
		lines.append("Ничего толкового не нашлось")
		return lines
	var qty := s.rng.randi_range(int(g["qty"][0]), int(g["qty"][1]))
	var inv: Dictionary = s.character["inventory"]
	inv[str(g["item"])] = int(inv.get(str(g["item"]), 0)) + qty
	CharacterRules.refresh(s.character, data, s.items)
	lines.append("Добыто: %s ×%d" % [ItemRules.display_name(data["items"], s.items, str(g["item"])), qty])
	return lines


static func tr_skill(_data: Dictionary, skill: String) -> String:
	return TranslationServer.translate("SKILL_" + skill.to_upper())


# --- learning and the master's recipes ----------------------------------------------------------------------------


## What a teach_recipe service would teach now: its recipe when the hero has the tool's proficiency and lacks it.
static func teachable(s: GameSession, data: Dictionary, sv: Dictionary) -> Array[String]:
	var id := str(sv.get("recipe", ""))
	var r := recipe(s, data, id)
	if r.is_empty() or not proficient(s.character, tool_of(r)) or learned(s.character).has(id):
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
	if not proficient(s.character, tool):
		return {"reason": "герой не владеет: %s — такой рецепт ему не по руке" % BackgroundRules.tool_name(data, tool)}
	var station := str(spec.get("station", "")) if spec.get("station") != null else ""
	if not station.is_empty() and not cfg(data)["stations"].has(station):
		return {"reason": "станции %s нет; можно: %s или без станции" % [station, ", ".join(cfg(data)["stations"].keys())]}
	var hours := int(spec.get("hours", 1))
	if hours < int(m["hours"][0]) or hours > int(m["hours"][1]):
		return {"reason": "hours — от %d до %d" % [m["hours"][0], m["hours"][1]]}
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
	var out_cp := int((item if not item.is_empty() else ItemRules.def_of(data["items"], s.items, out_id)).get("value_cp", 0)) * qty
	var cap := mats_cp + hours * int(m["labor_cp_hour"])
	if out_cp > cap:
		return {"reason": "выход дороже сырья и труда (%s > %s): больше материалов или часов" % [Money.format(out_cp), Money.format(cap)]}
	var name := str(spec.get("name", "")).strip_edges().left(60)
	var def := {"tool": tool, "station": station, "hours": hours, "dc": int(data["rules"]["dc_tiers"][tier]), "materials": mats.duplicate(),
		"output": out_id, "qty": qty, "learn": true, "generated": true}
	if not name.is_empty():
		def["name"] = name
	var id := "gen_r_" + ("%s|%s|%s" % [tool, out_id, JSON.stringify(mats)]).md5_text().left(8)
	if learned(s.character).has(id):
		return {"reason": "этот рецепт герой уже знает"}
	return {"id": id, "def": def, "item": item}


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
