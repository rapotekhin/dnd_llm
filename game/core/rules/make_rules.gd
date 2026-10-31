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

const PREFIX := "gen_"
const IDS := {"status": "st", "skill": "sk", "trait": "tr"}


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"]["make"]


## What was made in this game goes into the game's rules; what another game made leaves them.
static func install(data: Dictionary, gen: Dictionary) -> void:
	var rules: Dictionary = data["rules"]
	for table: String in ["skills", "conditions", "condition_effects", "made"]:
		if not rules.has(table):
			rules[table] = {}
		for id: String in (rules[table] as Dictionary).keys():
			if id.begins_with(PREFIX):
				(rules[table] as Dictionary).erase(id)
	var made: Dictionary = gen.get("made", {})
	for id: String in made:
		_put(data, id, made[id])


static func _put(data: Dictionary, id: String, def: Dictionary) -> void:
	var rules: Dictionary = data["rules"]
	if not rules.has("made"):
		rules["made"] = {}
	rules["made"][id] = def
	if str(def["what"]) == "skill":
		rules["skills"][id] = str(def["ability"])
		name_skill(id, str(def["name"]))
		return
	rules["conditions"][id] = "%s: %s" % [def["name"], def["text"]]
	rules["condition_effects"][id] = (def["row"] as Dictionary).merged({"name": str(def["name"])})


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
	var book := value.begins_with("new:book:")
	var key := value.trim_prefix("new:book:" if book else "new:")
	for p: Dictionary in pending:
		if p["kind"] == "make" and str(p["plan"]["key"]) == key:
			return str(p["plan"]["book"]["id"]) if book and p["plan"].has("book") else str(p["plan"]["id"])
	return value


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
		_:
			return ""
	return "" if known.has(value) else "%s: value из %s" % [id, ", ".join(known)]


static func _harm(spec: Dictionary, value: String, amount: int) -> bool:
	if spec.has("harm"):
		return str(spec["harm"]) == value if spec["harm"] is String else bool(spec["harm"])
	return amount < 0


static func _cost(spec: Dictionary, amount: int) -> int:
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


## The tier of `points`: its row, or {} past the last one.
static func tier(data: Dictionary, points: int) -> Dictionary:
	for t: Dictionary in cfg(data)["tiers"]:
		if points <= int(t["points"]):
			return t
	return {}


## The effect `make`: {plan, summary} or {reason}.
static func plan(s: GameSession, data: Dictionary, e: Dictionary) -> Dictionary:
	var what := str(e.get("what", ""))
	var key := str(e.get("key", "")).strip_edges()
	var name := str(e.get("name", "")).strip_edges().left(40)
	var text := str(e.get("text", "")).strip_edges().left(300)
	var title := str(e.get("book", "")).strip_edges().left(60) if e.get("book") != null else ""
	if not IDS.has(what):
		return {"reason": "what — %s" % ", ".join(IDS.keys())}
	if what == "status" and not title.is_empty():
		return {"reason": "книга учит навыку или черте; статус ложится эффектом condition"}
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
	else:
		var built := _built(s, data, what, name, e.get("parts", []))
		if built.has("reason"):
			return built
		def.merge(built)
		summary = "Новое: «%s» (%d очк., %s)" % [name, int(def["points"]), def["tier"]]
	_put(data, id, def)  # a condition or a course of this same turn reads it; a game that drops it never lays it
	var made := {"key": key, "id": id, "def": def}
	if not title.is_empty():
		made["book"] = _book(data, id, def, title)
		s.items[str(made["book"]["id"])] = made["book"]["item"]  # the library of the game: `give_item` of this turn finds it
		summary += ", книга «%s»" % title
	return {"plan": made, "summary": summary}


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
	return {"id": item_id, "course": "gen_c_" + item_id.md5_text().left(8),
		"item": {"name": title, "item_type": "gear", "value_cp": int(b["value_cp"]), "weight": 1, "properties": [],
			"description": str(def["text"]), "generated": true},
		"def": {"name": title, "book": item_id, "teaches": {"kind": kind, "id": id}, "lessons": int(b["lessons"]),
			"skill": id if kind == "skill" else str(b["skill"]), "dc": int(def.get("dc", data["rules"]["dc_tiers"][str(b["dc"])])),
			"fee_cp": 0, "generated": true}}


## The plan of `make` applied. Lines.
static func apply(s: GameSession, data: Dictionary, p: Dictionary) -> Array[String]:
	var gen := WorldGen.generated(s)
	if not (gen.get("made") is Dictionary):
		gen["made"] = {}
	var id := str(p["id"])
	var def: Dictionary = p["def"]
	gen["made"][id] = def.duplicate(true)
	_put(data, id, def)
	if p.has("book"):
		var book: Dictionary = p["book"]
		var all: Dictionary = gen.get("courses", {})
		all[str(book["course"])] = (book["def"] as Dictionary).duplicate(true)
		gen["courses"] = all
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


## For the master: what was made in this game and can be used again.
static func text(s: GameSession, data: Dictionary) -> String:
	var names := {"status": "статус", "skill": "навык", "trait": "черта"}
	var parts: Array[String] = []
	var made: Dictionary = s.generated.get("made", {})
	for id: String in made:
		parts.append("%s «%s» [%s]" % [names[str(made[id]["what"])], made[id]["name"], id])
	return "Собрано в этой игре: " + ", ".join(parts) if not parts.is_empty() else ""
