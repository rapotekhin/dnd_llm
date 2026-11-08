class_name MakeRules
extends RefCounted
## The master builds what neither the pack nor 5e has (v0.7.63, the author's principle: roadmap «Мастер собирает новое
## из частей»): a status, a skill, a passive trait, out of the parts of rules.make. The engine prices the parts: their
## sum is a tier, the tier asks a level of the hero and sets the DC, so a thing cannot be priced below what it does. What
## the parts do not cover is refused, and the master says so in the story and leaves a `missing_concept`.
## A made thing lives in its game (`generated.made` {id: def}) and is installed into the game's rules, so it reads like
## any other: a status in `conditions` and `condition_effects`, a skill in `skills`. A trait is a status with no end.
## To the hero a thing comes only through the world: a status is laid by `condition`, a skill and a trait are taught by a
## course or a book; `new:<key>` of the same turn stands for its id, `new:book:<key>` for its book.
## v0.7.64: a spell and an ability with charges, of the parts of rules.make.act. They compile into the tables an SRD spell
## lives in, so nothing else in the engine knows who made them: the row in `spells`, its status, its riders. The circle
## comes out of the sum and is not asked; an ability is a spell of no circle that spends its own stock. To the hero: a
## course, a book, a scroll (`new:scroll:<key>`), a quest's reward.
## v0.7.65: a property of a thing, of the tokens the engine reads (rules.make.property); it is priced by those tokens, and
## the artificer who learned it lays it on a thing (the template `imbue`), or the master's own item carries it.
## v0.8.4.28.5: a liquid of parts (rules.make.liquid) — a row of rules.liquids.kinds and its ready thing in its vessel under
## the same id, given as `new:<key>`; drunk, on a blade or thrown by the roads of any liquid, its effect a monster's attack's.

const PREFIX := "gen_"
const IDS := {"status": "st", "skill": "sk", "trait": "tr", "spell": "sp", "ability": "ab", "property": "pr", "liquid": "lq"}
const ACTS: Array[String] = ["spell", "ability"]


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"]["make"]


## What the words of a made spell or thing promise and its numbers lack (v0.8.4.30, the author's feedback: «Огненный
## удар» told of fire and dealt none): "" or a reason for the master. A sentence that speaks of damage and names a type by
## one of the stems of rules.make.told; `types` are the damage types its numbers deal.
static func told_damage(data: Dictionary, text: String, types: Array) -> String:
	var cf: Dictionary = cfg(data)["told"]
	var missing: Array[String] = []
	for sentence: String in text.to_lower().replace("!", ".").replace("?", ".").replace(";", ".").split("."):
		if not (cf["damage"] as Array).any(func(w: String) -> bool: return sentence.contains(w)):
			continue
		for t: String in cf["types"]:
			if not types.has(t) and not missing.has(t) and (cf["types"][t] as Array).any(func(w: String) -> bool: return sentence.contains(w)):
				missing.append(t)
	if missing.is_empty():
		return ""
	var names := missing.map(func(t: String) -> String: return str(data["misc"]["damage_types"][t]))
	return "в описании урон (%s), а в числах его нет: добавь его частью или свойством (%s) или убери из описания" % [
		", ".join(names), ", ".join(missing.map(func(t: String) -> String: return t + "_damage"))]


## What was made in this game goes into the game's rules; what another game made leaves them.
static func install(data: Dictionary, gen: Dictionary) -> void:
	var rules: Dictionary = data["rules"]
	for table: String in ["skills", "conditions", "condition_effects", "made"]:
		if not rules.has(table):
			rules[table] = {}
		for id: String in (rules[table] as Dictionary).keys():
			if id.begins_with(PREFIX):
				(rules[table] as Dictionary).erase(id)
	var tables := _tables(data)
	if not data["items"].has("built"):
		data["items"]["built"] = {}
	tables["built"] = data["items"]["built"]
	tables["properties"] = data["items"]["properties"]
	for name: String in tables:
		for id: String in (tables[name] as Dictionary).keys():
			if id.begins_with(PREFIX):
				(tables[name] as Dictionary).erase(id)
	for pool: Dictionary in [rules["liquids"]["kinds"], data["items"]["catalog"]]:
		for id: String in pool.keys():
			if id.begins_with(PREFIX):
				pool.erase(id)
	var engine: Array = rules["combat"]["engine_spells"]
	rules["combat"]["engine_spells"] = engine.filter(func(id: Variant) -> bool: return not str(id).begins_with(PREFIX))
	var made: Dictionary = gen.get("made", {})
	for id: String in made:
		_put(data, id, made[id])


static func _put(data: Dictionary, id: String, def: Dictionary) -> void:
	var rules: Dictionary = data["rules"]
	if not rules.has("made"):
		rules["made"] = {}
	rules["made"][id] = def
	if str(def["what"]) == "property":
		if not data["items"].has("built"):
			data["items"]["built"] = {}
		data["items"]["built"][id] = {"tokens": def["tokens"], "name": str(def["name"])}
		data["items"]["properties"][id] = int(def["points"])
		return
	if str(def["what"]) == "liquid":
		rules["liquids"]["kinds"][id] = def["row"]
		data["items"]["catalog"][id] = def["item"]
		return
	if ACTS.has(str(def["what"])):
		var tables := _tables(data)
		for name: String in tables:
			if (def["act"] as Dictionary).has(name):
				tables[name][id] = def["act"][name]
		if not (rules["combat"]["engine_spells"] as Array).has(id):
			(rules["combat"]["engine_spells"] as Array).append(id)
		return
	if str(def["what"]) == "skill":
		rules["skills"][id] = str(def["ability"])
		name_skill(id, str(def["name"]))
		return
	rules["conditions"][id] = "%s: %s" % [def["name"], def["text"]]
	rules["condition_effects"][id] = (def["row"] as Dictionary).merged({"name": str(def["name"])})


## The tables an action's rows live in.
static func _tables(data: Dictionary) -> Dictionary:
	var fight: Dictionary = data["rules"]["combat"]
	return {"spells": data["spells"], "resources": data["rules"]["resources"], "spell_effects": data["rules"]["spell_effects"],
		"riders": fight["riders"], "condition_spells": fight["condition_spells"], "multi": fight["multi"], "spell_targets": fight["spell_targets"]}


## The skill's name for every tr("SKILL_…") of the interface.
static func name_skill(id: String, name: String) -> void:
	var t := Translation.new()
	t.locale = TranslationServer.get_locale()
	t.add_message("SKILL_" + id.to_upper(), name)
	TranslationServer.add_translation(t)


static func def_of(data: Dictionary, id: String) -> Dictionary:
	return data["rules"].get("made", {}).get(id, {})


## What a made status lays beside its row: numbers, dice, a look. {} for any other status.
static func fx(s: GameSession, id: String) -> Dictionary:
	return s.generated.get("made", {}).get(id, {}).get("fx", {})


## `new:<key>` of this turn's `make` as an id, `new:book:<key>` as its book; anything else as it is.
static func resolve(pending: Array[Dictionary], value: String) -> String:
	if not value.begins_with("new:"):
		return value
	var of := value.get_slice(":", 1) if value.begins_with("new:book:") or value.begins_with("new:scroll:") else ""
	var key := value.trim_prefix("new:%s:" % of) if not of.is_empty() else value.trim_prefix("new:")
	for p: Dictionary in pending:
		if p["kind"] in ["make", "create:recipe"] and str(p["plan"].get("key", "")) == key:
			if of.is_empty():
				return str(p["plan"]["id"])
			return str(p["plan"][of]["id"]) if p["plan"].has(of) else value
	return value


## A master's item with `new:<key>` of this turn's `make` among its properties, its `use.spell`, its `spells` or `stored`
## (v0.8.4.36: a wand of a spell made in the same turn): the real ids.
static func resolved_item(item: Dictionary, pending: Array[Dictionary]) -> Dictionary:
	var out := item.duplicate(true)
	out["properties"] = (item.get("properties", []) as Array).map(func(p: Variant) -> String: return resolve(pending, str(p)))
	if out.get("use") is Dictionary and out["use"].get("spell") is String:
		out["use"]["spell"] = resolve(pending, str(out["use"]["spell"]))
	for key: String in ["spells", "stored"]:
		if out.get(key) is Array:
			for r: Variant in out[key]:
				if r is Dictionary and (r as Dictionary).get("spell") is String:
					r["spell"] = resolve(pending, str(r["spell"]))
	return out


## A property of parts: {tokens, on, points, tier, rarity} or {reason}. Its price is the price of what it adds.
static func _property(s: GameSession, data: Dictionary, name: String, parts: Variant) -> Dictionary:
	var table: Dictionary = cfg(data)["property"]["parts"]
	if not (parts is Array) or (parts as Array).is_empty():
		return {"reason": "нужны parts: из чего собрано; есть: %s" % ", ".join(table.keys())}
	var costs: Dictionary = data["items"]["properties"]
	var tokens: Array = []
	var on := ""
	var points := 0
	for p: Variant in parts:
		var id := str((p as Dictionary).get("part", ""))
		if not table.has(id):
			return {"reason": "части %s нет; есть: %s" % [id, ", ".join(table.keys())]}
		var spec: Dictionary = table[id]
		var value := str(p.get("value", "")) if p.get("value") != null else ""
		var amount := int(p.get("amount", 0)) if p.get("amount") != null else 0
		var why := _valid(data, spec, id, value, amount)
		if not why.is_empty():
			return {"reason": why}
		var token := str(spec["token"]) % value if spec.has("of") else (str(spec["token"]) % amount if spec.has("number") else str(spec["token"]))
		if not costs.has(token):
			return {"reason": "%s — такого свойства движок не читает" % token}
		var part_on := str(spec.get("on", ""))
		if not part_on.is_empty() and not on.is_empty() and part_on != on:
			return {"reason": "одна вещь — либо оружие, либо доспех"}
		on = part_on if not part_on.is_empty() else on
		tokens.append(token)
		points += int(costs[token])
	var rarity := ItemRules.rarity_for_points(data["items"], points)
	var level := int(s.character.get("level", 1))
	if level < ItemRules.rarity_level(data["items"], rarity):  # the threshold of check_generated (v0.8.4.29.5)
		return {"reason": "«%s» — редкость %s: %d очков, это от %d уровня героя, а герой %d" % [name, rarity, points, ItemRules.rarity_level(data["items"], rarity), level]}
	return {"tokens": tokens, "on": on, "points": points, "tier": rarity, "rarity": rarity}


## What the parts cost and do: {points, harm, boon, row, fx} or {reason}.
static func price(data: Dictionary, name: String, parts: Array) -> Dictionary:
	var table: Dictionary = cfg(data)["parts"]
	var out := {"points": 0, "harm": false, "boon": false, "row": {}, "fx": {}}
	for p: Variant in parts:
		var id := str((p as Dictionary).get("part", ""))
		if not table.has(id):
			return {"reason": "части %s нет; есть: %s" % [id, ", ".join(table.keys())]}
		var spec: Dictionary = table[id]
		var value := str(p.get("value", "")) if p.get("value") != null else ""
		var amount := int(p.get("amount", 0)) if p.get("amount") != null else 0
		var why := _valid(data, spec, id, value, amount)
		if not why.is_empty():
			return {"reason": why}
		var harm := _harm(spec, value, amount)
		out["harm"] = bool(out["harm"]) or harm
		out["boon"] = bool(out["boon"]) or not harm
		out["points"] = int(out["points"]) + _cost(spec, amount)
		_lay(out, id, value, amount, name)
	return out


static func _valid(data: Dictionary, spec: Dictionary, id: String, value: String, amount: int) -> String:
	if spec.has("number"):
		var range_of: Array = spec["number"]
		if amount == 0 or amount < int(range_of[0]) or amount > int(range_of[1]) or amount % int(spec.get("step", 1)) != 0:
			return "%s: amount от %d до %d, кратно %d, не 0" % [id, int(range_of[0]), int(range_of[1]), int(spec.get("step", 1))]
	if spec.has("values") and not (spec["values"] as Array).has(value):
		return "%s: value из %s" % [id, ", ".join(spec["values"])]
	var known: Array = []
	match str(spec.get("of", "")):
		"skill":
			known = (data["rules"]["skills"] as Dictionary).keys()
		"ability":
			known = data["rules"]["saves"]
		"damage":
			known = (data["misc"]["damage_types"] as Dictionary).keys()
		"condition":
			return "" if not value.is_empty() and ConditionRules.known(data, value) else "%s: статус из 5e или собранный: %s" % [id, value]
		_:
			return ""
	return "" if known.has(value) else "%s: value из %s" % [id, ", ".join(known)]


static func _harm(spec: Dictionary, value: String, amount: int) -> bool:
	if spec.has("harm"):
		return str(spec["harm"]) == value if spec["harm"] is String else bool(spec["harm"])
	return amount < 0


static func _cost(spec: Dictionary, amount: int, value: String = "") -> int:
	if spec.has("costs"):
		return int(spec["costs"].get(value, 0))
	if spec.has("number"):
		return int(spec["cost"]) * absi(amount) / int(spec.get("step", 1))
	return int(spec["cost"])


## One part into the status's row (read by ConditionRules) or its effect (read by the rules of numbers).
static func _lay(out: Dictionary, id: String, value: String, amount: int, name: String) -> void:
	var row: Dictionary = out["row"]
	var f: Dictionary = out["fx"]
	match id:
		"attack", "attacked":
			row[id] = value
			row[id + "_why"] = name
		"checks":
			row["checks"] = value
		"no_move":
			row["no_move"] = true
		"skill_dis":
			row["skills"] = (row.get("skills", {}) as Dictionary).merged({value: "disadvantage"})
		"save_dis":
			row["saves"] = (row.get("saves", {}) as Dictionary).merged({value: "disadvantage"})
		"save_adv":
			f["save_adv"] = (f.get("save_adv", []) as Array) + [value]
		"skill_bonus":
			f["skill_bonus"] = (f.get("skill_bonus", {}) as Dictionary).merged({value: amount})
		"ac":
			f["ac_plus"] = int(f.get("ac_plus", 0)) + amount
		"speed":
			f["speed_plus"] = int(f.get("speed_plus", 0)) + amount
		"resist":
			f["resist"] = (f.get("resist", []) as Array) + [value]
		"die":
			f["die"] = "1d4"
			f["on"] = (f.get("on", []) as Array) + [value]
			f["minus"] = amount < 0
		"guise":
			f["guise"] = {"name": value}


## The shape of a made spell's area (rules.make.act.shapes, v0.8.4.36): {area {type, size}, mult, extra} or {reason}; size 0 —
## the shape's default.
static func _shape(cf: Dictionary, type: String, size: int) -> Dictionary:
	var shapes: Dictionary = cf.get("shapes", {})
	if not shapes.has(type) or type.begins_with("_"):
		return {"reason": "shape — %s" % ", ".join(shapes.keys().filter(func(k: Variant) -> bool: return not str(k).begins_with("_")))}
	var row: Dictionary = shapes[type]
	var ft := size if size > 0 else int(row["default"])
	if ft < int(row["size"][0]) or ft > int(row["size"][1]):
		return {"reason": "size у %s — от %d до %d футов" % [type, int(row["size"][0]), int(row["size"][1])]}
	return {"area": {"type": type, "size": ft}, "mult": float(row["mult"]), "extra": maxi(0, ft - int(row["default"])) / int(shapes.get("per_ft", 20))}


## The tier of `points`: its row, or {} past the last one.
static func tier(data: Dictionary, points: int) -> Dictionary:
	return Scale.up_to(cfg(data)["tiers"], points)


## The effect `make`: {plan, summary} or {reason}.
static func plan(s: GameSession, data: Dictionary, e: Dictionary, pending: Array[Dictionary] = []) -> Dictionary:
	var what := str(e.get("what", ""))
	var key := str(e.get("key", "")).strip_edges()
	var name := str(e.get("name", "")).strip_edges().left(40)
	var text := str(e.get("text", "")).strip_edges().left(300)
	var title := str(e.get("book", "")).strip_edges().left(60) if e.get("book") != null else ""
	if not IDS.has(what):
		return {"reason": "what — %s" % ", ".join(IDS.keys())}
	var scroll := str(e.get("scroll", "")).strip_edges().left(60) if e.get("scroll") != null else ""
	if what == "status" and not title.is_empty():
		return {"reason": "книга учит навыку или черте; статус ложится эффектом condition"}
	if what != "spell" and not scroll.is_empty():
		return {"reason": "свиток бывает только у заклинания"}
	if key.is_empty() or name.is_empty() or text.is_empty():
		return {"reason": "нужны key, name и text: как зовётся и что игрок прочтёт"}
	var def := {"what": what, "name": name, "text": text}
	var id := "%s%s_%s" % [PREFIX, IDS[what], name.md5_text().left(8)]
	var summary := ""
	if what == "skill":
		var ab := str(e.get("ability", "")) if e.get("ability") != null else ""
		if not (data["rules"]["saves"] as Array).has(ab):
			return {"reason": "ability навыка — из %s" % ", ".join(data["rules"]["saves"])}
		def["ability"] = ab
		summary = "Новый навык: %s" % name
	elif what == "property":
		var built := _property(s, data, name, e.get("parts", []))
		if built.has("reason"):
			return built
		def.merge(built)
		summary = "Новое свойство: «%s» (%d очк., %s)" % [name, int(def["points"]), def["rarity"]]
	elif what == "liquid":
		var built := _liquid(s, data, id, name, text, e.get("parts", []), pending)
		if built.has("reason"):
			return built
		def.merge(built)
		summary = "Новая жидкость: «%s» (%d очк., %s)" % [name, int(def["points"]), def["tier"]]
	elif ACTS.has(what):
		var built := _acted(s, data, what, id, name, text, e, pending)
		if built.has("reason"):
			return built
		def.merge(built)
		summary = "Новое: «%s» (%d очк., %s)" % [name, int(def["points"]), def["tier"]]
	else:
		var built := _built(s, data, what, name, e.get("parts", []))
		if built.has("reason"):
			return built
		def.merge(built)
		summary = "Новое: «%s» (%d очк., %s)" % [name, int(def["points"]), def["tier"]]
	if e.get("learn") == true:
		var why := _not_alone(s, data, what, def)
		if not why.is_empty():
			return {"reason": why}
		summary += ", герой вывел его сам"
	_put(data, id, def)  # a condition or a course of this same turn reads it; a game that drops it never lays it
	var made := {"key": key, "id": id, "def": def, "learn": e.get("learn") == true}
	if not title.is_empty():
		made["book"] = _book(data, id, def, title)
		s.items[str(made["book"]["id"])] = made["book"]["item"]  # the library of the game: `give_item` of this turn finds it
		summary += ", книга «%s»" % title
	if not scroll.is_empty():
		made["scroll"] = _scroll(data, id, def, scroll)
		if made["scroll"].is_empty():
			return {"reason": "свиток держит заклинание не выше 3 круга, а это — %d круга" % int(def["circle"])}
		s.items[str(made["scroll"]["id"])] = made["scroll"]["item"]
		summary += ", свиток «%s»" % scroll
	return {"plan": made, "summary": summary}


## "" or why the hero cannot work this out alone, by rules.make.self_taught.
static func _not_alone(s: GameSession, data: Dictionary, what: String, def: Dictionary) -> String:
	var rule: Dictionary = cfg(data).get("self_taught", {}).get(what, {})
	if rule.is_empty():
		return "сам герой выводит только заклинание; остальное приходит через учителя, книгу или мир"
	var top := StudyRules.max_circle(s.character)
	if top < 1:
		return "герой не заклинатель: заклинание ему не вывести"
	var limit := top - int(rule["below_top"])
	if int(def["circle"]) > limit:
		return "герой сам не выведет заклинание %d круга: его высший круг %d, а сам он выводит не выше %d. Дальше — учитель, книга, свиток или задание" % [int(def["circle"]), top, maxi(limit, 0)]
	return ""


static func _built(s: GameSession, data: Dictionary, what: String, name: String, parts: Variant) -> Dictionary:
	if not (parts is Array) or (parts as Array).is_empty():
		return {"reason": "нужны parts: из чего собрано; есть: %s" % ", ".join((cfg(data)["parts"] as Dictionary).keys())}
	var p := price(data, name, parts)
	if p.has("reason"):
		return p
	if what == "trait" and not bool(p["boon"]):
		return {"reason": "черта без пользы не черта: это статус"}
	if what == "trait" and (p["fx"] as Dictionary).has("guise"):
		return {"reason": "облик не бывает постоянной чертой"}
	var points := int(p["points"]) * (int(cfg(data)["trait_mult"]) if what == "trait" else 1)
	var t := tier(data, points)
	if t.is_empty():
		var top: Dictionary = (cfg(data)["tiers"] as Array)[-1]
		return {"reason": "%d очков — движок так сильно не собирает (предел %d)" % [points, int(top["points"])]}
	var level := int(s.character.get("level", 1))
	if level < int(t["level"]):
		return {"reason": "«%s» — %s: %d очков, это от %d уровня героя, а герой %d" % [name, t["name"], points, int(t["level"]), level]}
	var dc := int(data["rules"]["dc_tiers"][str(t["dc"])])
	if (p["fx"] as Dictionary).has("guise"):
		p["fx"]["guise"]["dc"] = dc
	return {"row": p["row"], "fx": p["fx"], "points": points, "tier": str(t["name"]), "dc": dc, "harm": p["harm"]}


static func _book(data: Dictionary, id: String, def: Dictionary, title: String) -> Dictionary:
	var b: Dictionary = cfg(data)["book"]
	var item_id := "gen_book_" + id.md5_text().left(8)
	var kind := str(def["what"])
	if kind == "property":  # known while it is carried, as a recipe's book
		return {"id": item_id, "item": {"name": title, "item_type": "gear", "value_cp": int(b["value_cp"]), "weight": 1, "properties": [],
			"description": str(def["text"]), "generated": true, "teaches": [CraftRules.imbue_formula(id)]}}
	var skill := str(cfg(data)["act"]["book_skill"]) if ACTS.has(kind) else str(b["skill"])
	return {"id": item_id, "course": "gen_c_" + item_id.md5_text().left(8),
		"item": {"name": title, "item_type": "gear", "value_cp": int(b["value_cp"]), "weight": 1, "properties": [],
			"description": str(def["text"]), "generated": true},
		"def": {"name": title, "book": item_id, "teaches": {"kind": kind, "id": id}, "lessons": int(b["lessons"]),
			"skill": id if kind == "skill" else skill, "dc": int(def.get("dc", data["rules"]["dc_tiers"][str(b["dc"])])),
			"fee_cp": 0, "generated": true}}


## A scroll of a built spell, {} past the 3rd circle.
static func _scroll(data: Dictionary, id: String, def: Dictionary, title: String) -> Dictionary:
	var cost: Array = cfg(data)["act"]["scroll_cp"]
	var circle := int(def["circle"])
	if circle >= cost.size():
		return {}
	return {"id": "gen_scroll_" + id.md5_text().left(8), "item": {"name": title, "item_type": "consumable", "value_cp": int(cost[circle]), "weight": 0,
		"properties": [], "description": str(def["text"]), "generated": true, "use": {"spell": id, "level": circle, "scroll": true}}}


## An action of parts: {act {rows by table}, points, tier, circle, dc} or {reason}. The rules of its shape are here, the
## numbers in rules.make.act.
static func _acted(s: GameSession, data: Dictionary, what: String, id: String, name: String, text: String, e: Dictionary, pending: Array[Dictionary]) -> Dictionary:
	var cf: Dictionary = cfg(data)["act"]
	var table: Dictionary = cf["parts"]
	var parts: Variant = e.get("parts", [])
	if not (parts is Array) or (parts as Array).is_empty():
		return {"reason": "нужны parts: из чего собрано; есть: %s" % ", ".join(table.keys())}
	var got := {}
	var points := 0
	var charges := 0  # not multiplied by an area
	for p: Variant in parts:
		var part := str((p as Dictionary).get("part", ""))
		if not table.has(part):
			return {"reason": "части %s нет; есть: %s" % [part, ", ".join(table.keys())]}
		var value := str(p.get("value", "")) if p.get("value") != null else ""
		var amount := int(p.get("amount", 0)) if p.get("amount") != null else 0
		if part == "lay":
			value = resolve(pending, value)
		var why := _valid(data, table[part], part, value, amount)
		if not why.is_empty():
			return {"reason": why}
		got[part] = {"value": value, "amount": amount}
		if part in ["uses", "recharge"]:
			charges += _cost(table[part], amount, value)
		else:
			points += _cost(table[part], amount, value)
	var val := func(part: String, fallback: String) -> String: return str(got.get(part, {}).get("value", fallback))
	var num := func(part: String) -> int: return int(got.get(part, {}).get("amount", 0))
	var cast: String = val.call("cast", "action")
	var target: String = val.call("target", "one")
	var roll: String = val.call("roll", "")
	var lay: String = val.call("lay", "")
	var dmg: int = num.call("damage")
	var heal: int = num.call("heal")
	if not lay.is_empty():
		var lay_points := _lay_cost(data, lay)
		if lay_points < 0:
			return {"reason": "%s так не положить; можно: %s или статус, собранный в этой игре" % [lay, ", ".join(cf["lay_cost"].keys())]}
		points += lay_points
	if dmg == 0 and heal == 0 and lay.is_empty():
		return {"reason": "действию нужен эффект: damage, heal или lay"}
	if heal > 0 and (dmg > 0 or not lay.is_empty()):
		return {"reason": "лечение идёт отдельным действием: без damage и lay"}
	var harm := lay.begins_with(PREFIX) and bool(def_of(data, lay).get("harm", false)) or (not lay.is_empty() and not lay.begins_with(PREFIX))
	if dmg > 0 or harm:
		if target == "self":
			return {"reason": "вред на себя не собирают: target one или area"}
		if roll.is_empty():
			return {"reason": "вреду нужен roll: attack, auto или характеристика спасброска"}
		if dmg == 0 and roll in ["attack", "auto"]:
			return {"reason": "статус без урона идёт через спасбросок: roll — характеристика"}
		if roll == "attack" and target == "area":
			return {"reason": "по области нет броска атаки: roll — характеристика"}
	if got.has("half") and (dmg == 0 or roll in ["attack", "auto", ""]):
		return {"reason": "half — половина урона при спасброске"}
	if got.has("push") and (dmg == 0 or roll == ""):
		return {"reason": "push идёт с уроном по броску"}
	if cast == "reaction" and (what != "spell" or dmg == 0 or roll in ["attack", "auto", ""] or target != "one"):
		return {"reason": "реакция — только заклинание: урон обидчику со спасброском, target one"}
	if what != "ability" and (got.has("uses") or got.has("recharge")):
		return {"reason": "uses и recharge — только у ability"}
	var area: Dictionary = cf["area"]
	if (got.has("shape") or got.has("size")) and target != "area":
		return {"reason": "shape и size — у target area"}
	if target == "area":
		var shape := _shape(cf, val.call("shape", str(area["type"])), num.call("size"))
		if shape.has("reason"):
			return shape
		area = shape["area"]
		points = ceili(points * float(shape["mult"])) + int(shape["extra"])
	points = maxi(1, points) + charges
	var rank := _rank(cf, points)
	if rank.is_empty():
		var top: Dictionary = (cf["circles"] as Array)[-1]
		return {"reason": "%d очков — движок так сильно не собирает (предел %d)" % [points, int(top["points"])]}
	var told := told_damage(data, text, [val.call("damage", "force")] if dmg > 0 else [])
	if not told.is_empty():
		return {"reason": told}
	var circle := int(rank["circle"])
	if circle == 0 and (heal > 0 or not lay.is_empty() or cast == "reaction"):
		circle = 1
	var key: String = val.call("range", "touch" if target == "self" else "60")
	var from_self := target == "area" and bool(cf.get("shapes", {}).get(str(area["type"]), {}).get("from_self", false))
	var lasts: Array = cf["lasts"][val.call("lasts", "round")]
	var conc := got.has("concentration")
	var row := {"name": name, "name_en": "", "level": circle, "school": "Собрано мастером", "school_id": "", "casting_time": cf["casting"][cast],
		"range": "На себя" if target == "self" or from_self else ("Касание" if key == "touch" else "%s футов" % key), "duration": lasts[0], "components": ["V", "S"],
		"concentration": conc, "ritual": false, "classes": [], "subclasses": [], "desc": text, "generated": true,
		"range_ft": 5 if key == "touch" and not from_self else (0 if target == "self" or from_self else int(key))}
	var act := {"spells": row}
	var tier_name := "%d круг" % circle if circle > 0 else "заговор"
	var dc := int(data["rules"]["dc_tiers"][str(cf["dc_by_circle"][circle])])
	if what == "ability":
		var ab := str(e.get("ability", "")) if e.get("ability") != null else ""
		if not (data["rules"]["saves"] as Array).has(ab):
			return {"reason": "ability способности — её характеристика, из %s" % ", ".join(data["rules"]["saves"])}
		var t := tier(data, points)
		if t.is_empty():
			var top: Dictionary = (cfg(data)["tiers"] as Array)[-1]
			return {"reason": "%d очков — движок так сильно не собирает (предел %d)" % [points, int(top["points"])]}
		var level := int(s.character.get("level", 1))
		if level < int(t["level"]):
			return {"reason": "«%s» — %s: %d очков, это от %d уровня героя, а герой %d" % [name, t["name"], points, int(t["level"]), level]}
		circle = 0
		row["level"] = 0
		row["ability"] = ab
		row["stock"] = id
		tier_name = str(t["name"])
		act["resources"] = {"spell": id, "name": name, "max": {"fixed": maxi(1, num.call("uses"))}, "recharge": val.call("recharge", "long"), "combat_cost": "never"}
	var by_circle := func(dice: String) -> Dictionary:
		var out := {}
		var from := maxi(1, circle)
		if what == "ability":
			return {"0": dice, "1": dice}
		var n := int(dice.get_slice("d", 0))
		for k in range(from, 6):
			out[str(k)] = "%dd6%s" % [n + k - from, "+MOD" if dice.ends_with("+MOD") else ""]
		return out
	if roll == "attack":
		row["attack"] = "melee" if key == "touch" else "ranged"
	elif roll == "auto":
		act["multi"] = {"auto_hit": true, "base": 1}
	elif not roll.is_empty():
		row["save"] = {"ability": roll, "success": "half" if got.has("half") else "none"}
	if target == "area":
		row["area"] = area
	if dmg > 0:
		row["damage_type"] = val.call("damage", "force")
		if circle == 0 and what == "spell":
			row["damage_at_level"] = {"1": "%dd6" % dmg, "5": "%dd6" % (dmg * 2), "11": "%dd6" % (dmg * 3), "17": "%dd6" % (dmg * 4)}
		else:
			row["damage_at_slot"] = by_circle.call("%dd6" % dmg)
		var riders: Array = []
		if not lay.is_empty():
			riders.append({"status": lay, "rounds": int(lasts[1]), "line": "%s: " + ConditionRules.name_of(data, lay).to_lower().replace("%", "")})
		if got.has("push"):
			riders.append({"push": int(got["push"]["amount"]), "line": "%s отброшен"})
		if not riders.is_empty():
			act["riders"] = riders
		if cast == "reaction":
			act["spell_effects"] = {"reaction": "damage", "label": "%s: %s" % [name, text.left(60)]}
	elif heal > 0:
		row["heal_at_slot"] = by_circle.call("%dd6+MOD" % heal)
		if target != "self":
			act["spell_targets"] = {"side": "friend", "n": 1}
	elif harm:
		act["condition_spells"] = {"conditions": [lay], "rounds": int(lasts[1]), "repeat_save": got.has("repeat")}
	else:  # a boon: on the hero, or on the one they touch
		act["spell_effects"] = {"self_status": lay}
		if target != "self":
			act["spell_targets"] = {"side": "friend", "n": 1}
	return {"act": act, "points": points, "tier": tier_name, "circle": circle, "dc": dc, "harm": dmg > 0 or harm}


## A liquid of parts: {row, item, points, tier} or {reason}. The row is read by LiquidRules like any other; on a blade and
## thrown its `effect` is a monster's attack's (MonsterRules.apply_effect).
static func _liquid(s: GameSession, data: Dictionary, id: String, name: String, text: String, parts: Variant, pending: Array[Dictionary]) -> Dictionary:
	var cf: Dictionary = cfg(data)["liquid"]
	var table: Dictionary = cf["parts"]
	if not (parts is Array) or (parts as Array).is_empty():
		return {"reason": "нужны parts: из чего собрана жидкость; есть: %s" % ", ".join(table.keys())}
	var got := {}
	var points := 0
	for p: Variant in parts:
		var part := str((p as Dictionary).get("part", ""))
		if not table.has(part):
			return {"reason": "части %s нет; есть: %s" % [part, ", ".join(table.keys())]}
		var value := str(p.get("value", "")) if p.get("value") != null else ""
		var amount := int(p.get("amount", 0)) if p.get("amount") != null else 0
		if part in ["lay", "also"]:
			value = resolve(pending, value)
		var why := _valid(data, table[part], part, value, amount)
		if not why.is_empty():
			return {"reason": why}
		got[part] = {"value": value, "amount": amount}
		points += (amount - 1) * int(table[part]["cost"]) if part == "area" else _cost(table[part], amount, value)
	var val := func(part: String) -> String: return str(got.get(part, {}).get("value", ""))
	var num := func(part: String) -> int: return int(got.get(part, {}).get("amount", 0))
	var drinks := got.has("quench") or got.has("drunk") or got.has("food")
	var way := "blade" if got.has("blade") else ("throw" if got.has("throw") else "")
	if got.has("blade") and got.has("throw"):
		return {"reason": "жидкость идёт либо на клинок (blade), либо в бросок (throw)"}
	if not drinks and way.is_empty():
		return {"reason": "как ею пользуются: пьют (quench, drunk, food), на клинок (blade) или бросают (throw)"}
	var acts := got.has("damage") or got.has("lay")
	if acts and way.is_empty():
		return {"reason": "урон и статус — у клинка (blade) или броска (throw); выпитое действует только питьём"}
	if not way.is_empty() and not acts:
		return {"reason": "%s без действия: нужны damage или lay" % way}
	if (got.has("also") or got.has("lasts") or got.has("wake")) and not got.has("lay"):
		return {"reason": "also, lasts и wake — у статуса lay"}
	if got.has("area") and way != "throw":
		return {"reason": "область (area) — только у броска"}
	var effect := {}
	if got.has("lay"):
		for st: String in [val.call("lay"), val.call("also")]:
			if st.is_empty():
				continue
			var c := _lay_cost(data, st)
			if c < 0:
				return {"reason": "статус %s жидкостью не ложится" % st}
			points += c
		effect["condition"] = val.call("lay")
		if got.has("also"):
			effect["also"] = val.call("also")
		if got.has("lasts"):
			effect["duration"] = val.call("lasts")
		if got.has("wake"):
			effect["wake"] = true
	if got.has("damage"):
		effect["damage"] = {"dice": "%dd6" % num.call("damage"), "type": val.call("damage")}
	var dcf: Dictionary = cf["dc_cost"]
	if got.has("save"):
		points += maxi(0, num.call("save") - int(dcf["from"])) / int(dcf["per"])
	points = ceili(points * float(cf["mult"]))
	var t := tier(data, points)
	if t.is_empty():
		return {"reason": "%d очков — движок так сильно не собирает" % points}
	var level := int(s.character.get("level", 1))
	if level < int(t["level"]):
		return {"reason": "«%s» — %s: %d очков, это от %d уровня героя, а герой %d" % [name, t["name"], points, int(t["level"]), level]}
	if acts and (got.has("lay") or got.has("save")):
		effect["save"] = {"ability": val.call("save") if got.has("save") else "con",
			"dc": num.call("save") if got.has("save") else int(data["rules"]["dc_tiers"][str(t["dc"])])}
	var vessel: String = val.call("vessel") if got.has("vessel") else str(cf["vessels"][way if not way.is_empty() else "drink"])
	if LiquidRules.holds(data, vessel) <= 0.0 or not data["items"]["catalog"].has(vessel):
		return {"reason": "vessel — сосуд из rules.liquids.vessels: %s" % ", ".join((LiquidRules.cfg(data)["vessels"] as Dictionary).keys())}
	var pints := LiquidRules.holds(data, vessel)
	var row := {"name": name, "made": true, "item": id, "vessel": vessel, "pints": pints}
	if drinks:
		var drink := {}
		if got.has("quench"):
			drink["water"] = 1
			row["quench"] = true
		if got.has("drunk"):
			drink["drunk"] = num.call("drunk")
		if got.has("food"):
			drink["food"] = num.call("food")
		row["drink"] = drink
	if way == "blade":
		row["blade"] = (cf["blade"] as Dictionary).merged({"effect": effect})
	elif way == "throw":
		row["throw"] = (cf["throw"] as Dictionary).merged({"effect": effect, "area": maxi(1, num.call("area"))})
	if not way.is_empty():
		row["needs"] = str(cf["needs"][way])
	var told := MonsterRules.effect_text(data, {"effect": effect}) if not effect.is_empty() else ""
	var lb := float(data["items"]["catalog"][vessel].get("weight", 0)) + pints * float(LiquidRules.cfg(data).get("lb_per_pint", 1))
	var item := {"name": name, "item_type": "consumable" if way == "throw" else "gear", "weight": snappedf(lb, 0.1), "properties": [],
		"stack": true, "value_cp": maxi(points * int(cf["cp_per_point"]), ceili(pints * int(cf["drink_cp_pint"]))),
		"description": text + ((" " + _way_text(way, row, told)) if not way.is_empty() else ""), "made": true}
	return {"row": row, "item": item, "points": points, "tier": str(t["name"]), "dc": int(effect.get("save", {}).get("dc", 0))}


static func _way_text(way: String, row: Dictionary, told: String) -> String:
	if way == "blade":
		return "Смазать клинок (рубящий или колющий): при попадании — %s." % told
	return "Бросить на 20 фт: %s, область %d×%d клеток." % [told, int(row["throw"]["area"]), int(row["throw"]["area"])]


## What a status laid by an action costs: a made one its points, one of 5e by the table; -1 — it cannot be laid.
static func _lay_cost(data: Dictionary, cond: String) -> int:
	if cond.begins_with(PREFIX):
		return int(def_of(data, cond).get("points", -1)) if str(def_of(data, cond).get("what", "")) == "status" else -1
	return int(cfg(data)["act"]["lay_cost"].get(cond, -1))


## The first row of `circles` that holds `points`.
static func _rank(cf: Dictionary, points: int) -> Dictionary:
	return Scale.up_to(cf["circles"], points)


## The plan of `make` applied. Lines.
static func apply(s: GameSession, data: Dictionary, p: Dictionary) -> Array[String]:
	var gen := WorldGen.generated(s)
	if not (gen.get("made") is Dictionary):
		gen["made"] = {}
	var id := str(p["id"])
	var def: Dictionary = p["def"]
	gen["made"][id] = def.duplicate(true)
	_put(data, id, def)
	if p.has("scroll"):
		s.items[str(p["scroll"]["id"])] = p["scroll"]["item"]
	if p.has("book"):
		var book: Dictionary = p["book"]
		s.items[str(book["id"])] = book["item"]
		if book.has("course"):
			var all: Dictionary = gen.get("courses", {})
			all[str(book["course"])] = (book["def"] as Dictionary).duplicate(true)
			gen["courses"] = all
	if bool(p.get("learn", false)):
		StudyRules.learn_spell(s.character, id)
		CharacterRules.refresh(s.character, data, s.items)
		return ["Герой сам вывел заклинание: «%s»" % str(def["name"])]
	CharacterRules.refresh(s.character, data, s.items)
	return []


## A trait comes to the hero (a course, a book): a status with no end.
static func grant_trait(s: GameSession, data: Dictionary, id: String) -> void:
	var def := def_of(data, id)
	ConditionRules.add_effect(s.character, (def["fx"] as Dictionary).merged({"condition": id, "ends": {},
		"source": {"kind": "trait", "id": id, "name": str(def["name"])}}))
	CharacterRules.refresh(s.character, data, s.items)


static func is_trait(data: Dictionary, id: String) -> bool:
	return str(def_of(data, id).get("what", "")) == "trait"


static func is_ability(data: Dictionary, id: String) -> bool:
	return str(def_of(data, id).get("what", "")) == "ability"


static func is_property(data: Dictionary, id: String) -> bool:
	return str(def_of(data, id).get("what", "")) == "property"


## For the master: what was made in this game and can be used again.
static func text(s: GameSession, data: Dictionary) -> String:
	var names := {"status": "статус", "skill": "навык", "trait": "черта", "spell": "заклинание", "ability": "способность", "property": "свойство вещи"}
	var parts: Array[String] = []
	var made: Dictionary = s.generated.get("made", {})
	for id: String in made:
		parts.append("%s «%s» [%s]" % [names[str(made[id]["what"])], made[id]["name"], id])
	return "Собрано в этой игре: " + ", ".join(parts) if not parts.is_empty() else ""
