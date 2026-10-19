class_name WorldPack
extends RefCounted
## World packs (ADR-0010 §1, roadmap v0.5.1): a folder with pack.json (manifest, lore, master defaults, rule
## filters and renames, names), world.json (locations, rooms, NPCs) and characters.json (ready-made characters).
## Built-in packs live in res://data/worlds/, player mods in user://mods/worlds/ in the same format.
## tools/validate_data.py checks the repo packs with the same rules in CI (keep them in sync).
##
## A bundle = {"id", "dir", "source": "builtin" | "mod", "pack", "world", "characters", "errors": [text]}.

const FORMAT_VERSION := 1
const BUILTIN_DIR := "res://data/worlds"
const MODS_DIR := "user://mods/worlds"
const DM_STYLES: Array[String] = ["classic", "literary", "dry", "ironic"]
const VIOLENCE: Array[String] = ["mild", "medium", "graphic"]
const GENDERS: Array[String] = ["male", "female", "other"]
const RULE_LISTS: Dictionary = {"races": ["races", "races"], "classes": ["classes", "classes"], "backgrounds": ["backgrounds", ""]}


## Every pack folder in `dirs` (built-in first). A mod with a built-in pack's id is reported, not loaded.
static func scan(dirs: Array[String], base: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen := {}
	for i in dirs.size():
		var dir := dirs[i]
		for name in DirAccess.get_directories_at(dir):
			var b := load_bundle(dir.path_join(name), "builtin" if dir == BUILTIN_DIR else "mod")
			if b["errors"].is_empty():
				b["errors"] = validate(b, base)
			if seen.has(b["id"]):
				b["errors"] = ["пакет с id «%s» уже есть" % b["id"]]
			seen[b["id"]] = true
			out.append(b)
	return out


static func load_bundle(dir: String, source: String) -> Dictionary:
	var b := {"id": dir.get_file(), "dir": dir, "source": source, "pack": {}, "world": {}, "characters": {}, "errors": []}
	var pack: Variant = _json(dir.path_join("pack.json"))
	if not (pack is Dictionary):
		b["errors"].append("pack.json не читается")
		return b
	b["pack"] = pack
	b["id"] = str(pack.get("id", b["id"]))
	for key: String in ["world", "characters"]:
		var file := str(pack.get(key, key + ".json"))
		var d: Variant = _json(dir.path_join(file))
		if not (d is Dictionary):
			b["errors"].append("%s не читается" % file)
		else:
			b[key] = d
	return b


static func _json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


# --- validation ----------------------------------------------------------------------


## Problems of a loaded bundle (texts for the pack author); [] = the pack can be played.
static func validate(b: Dictionary, base: Dictionary) -> Array[String]:
	var e: Array[String] = []
	var p: Dictionary = b["pack"]
	if int(p.get("format_version", 0)) != FORMAT_VERSION:
		e.append("format_version %s не поддерживается (нужна %d)" % [p.get("format_version"), FORMAT_VERSION])
		return e
	for key: String in ["id", "version", "name", "description", "lore", "tone"]:
		if not (p.get(key) is String) or str(p[key]).strip_edges().is_empty():
			e.append("pack.%s: нужна непустая строка" % key)
	if not DM_STYLES.has(str(p.get("dm_style", ""))):
		e.append("pack.dm_style: одно из %s" % ", ".join(DM_STYLES))
	var content: Variant = p.get("content")
	if not (content is Dictionary) or not VIOLENCE.has(str(content.get("violence", ""))):
		e.append("pack.content.violence: одно из %s" % ", ".join(VIOLENCE))
	elif not _strings(content.get("lines", [])) or not _strings(content.get("veils", [])):
		e.append("pack.content.lines / veils: списки строк")
	var names: Variant = p.get("names")
	if not (names is Dictionary) or not _strings(names.get("male")) or not _strings(names.get("female")) \
			or (names["male"] as Array).is_empty() or (names["female"] as Array).is_empty():
		e.append("pack.names: непустые списки male и female")
	e.append_array(_validate_rules(p.get("rules", {}), base))
	if not e.is_empty():
		return e
	var data := apply_rules(base, b)
	e.append_array(_validate_world(b["world"], data))
	e.append_array(_validate_characters(b["characters"], data))
	return e


static func _strings(v: Variant) -> bool:
	return v is Array and (v as Array).all(func(x: Variant) -> bool: return x is String)


static func _known(base: Dictionary, kind: String) -> Dictionary:
	match kind:
		"races":
			return base["races"]["races"]
		"classes":
			return base["classes"]["classes"]
		"backgrounds":
			return base["backgrounds"]
		"items":
			return base["items"]["catalog"]
	return {}


static func _validate_rules(rules: Variant, base: Dictionary) -> Array[String]:
	var e: Array[String] = []
	if not (rules is Dictionary):
		return ["pack.rules: объект"]
	for kind: String in ["races", "classes", "backgrounds"]:
		var list: Variant = rules.get(kind, [])
		if not _strings(list):
			e.append("pack.rules.%s: список id" % kind)
			continue
		for id: String in list:
			if not _known(base, kind).has(id):
				e.append("pack.rules.%s: неизвестный id %s" % [kind, id])
	for id: Variant in rules.get("items_exclude", []):
		if not _known(base, "items").has(str(id)):
			e.append("pack.rules.items_exclude: неизвестный предмет %s" % id)
	var rename: Variant = rules.get("rename", {})
	if not (rename is Dictionary):
		return e + ["pack.rules.rename: объект"]
	for kind: String in rename:
		if not kind in ["races", "classes", "backgrounds", "items"]:
			e.append("pack.rules.rename.%s: можно races, classes, backgrounds, items" % kind)
			continue
		for id: String in rename[kind]:
			var r: Variant = rename[kind][id]
			if not _known(base, kind).has(id):
				e.append("pack.rules.rename.%s: неизвестный id %s" % [kind, id])
			elif not (r is Dictionary) or not (r as Dictionary).keys().all(func(k: Variant) -> bool: return k in ["name", "desc"]):
				e.append("pack.rules.rename.%s.%s: только name и desc" % [kind, id])
	return e


static func _validate_world(w: Dictionary, data: Dictionary) -> Array[String]:
	var e: Array[String] = []
	for key: String in ["locations", "rooms", "npcs"]:
		if not (w.get(key) is Dictionary):
			return ["world.%s: объект" % key]
	var rooms: Dictionary = w["rooms"]
	if not rooms.has(str(w.get("start_room", ""))):
		e.append("world.start_room: нет комнаты %s" % w.get("start_room"))
	var quests: Variant = w.get("quests", {})
	if not (quests is Dictionary):
		e.append("world.quests: объект")
	else:
		for qid: String in quests:
			var q: Variant = quests[qid]
			if not (q is Dictionary) or str(q.get("title", "")).is_empty():
				e.append("задание %s: нужен title" % qid)
			elif not q.has("steps"):
				if str(q.get("action", "")).is_empty() or str(q.get("done_text", "")).is_empty() or not rooms.has(str(q.get("room", ""))):
					e.append("задание %s: title, action, done_text и room из комнат пакета" % qid)
			elif not w["npcs"].has(str(q.get("giver", ""))) or not (q["steps"] is Array) or (q["steps"] as Array).is_empty():
				e.append("задание %s: giver — NPC пакета, steps — непустой список" % qid)
			else:
				for st: Variant in q["steps"]:
					var when: Variant = st.get("when") if st is Dictionary else null
					if not (when is Dictionary) or str(st.get("text", "")).is_empty() or not _when_ok(when, true):
						e.append("задание %s: шаг — text и when с одним условием (encounter | secret | room | flag | talk | choice | all | any)" % qid)
					elif (when as Dictionary).has("choice") != (st as Dictionary).has("choices"):
						e.append("задание %s: when.choice и choices — только вместе" % qid)
	var placed := {}
	for id: String in rooms:
		var r: Dictionary = rooms[id]
		if str(r.get("name", "")).is_empty():
			e.append("комната %s: нет name" % id)
		if not w["locations"].has(str(r.get("location_id", ""))):
			e.append("комната %s: нет локации %s" % [id, r.get("location_id")])
		for x: Variant in r.get("exits", []):
			if not rooms.has(str(x)):
				e.append("комната %s: выход в несуществующую %s" % [id, x])
		for n: Variant in r.get("npcs", []):
			if not w["npcs"].has(str(n)):
				e.append("комната %s: нет NPC %s" % [id, n])
			elif placed.has(n):
				e.append("NPC %s стоит в двух комнатах" % n)
			placed[n] = true
		if not _strings(r.get("hooks", [])):
			e.append("комната %s: hooks — список строк" % id)
		var closed: Variant = r.get("closed_exits", {})
		if closed is Dictionary:
			for to: String in closed:
				if not (r.get("exits", []) as Array).has(to) or not (closed[to] is Dictionary) or not _when_ok(closed[to].get("when"), false):
					e.append("комната %s: closed_exits %s — выход комнаты и {when}" % [id, to])
		var ids := {}
		for sec: Variant in r.get("secrets", []):
			if sec is Dictionary and sec.get("trap") is Dictionary and not (r.get("exits", []) as Array).has(str(sec["trap"].get("guards", ""))):
				e.append("комната %s: ловушка %s стережёт не выход комнаты" % [id, sec.get("id")])
			if not (sec is Dictionary) or str(sec.get("id", "")).is_empty() or str(sec.get("text", "")).is_empty() \
					or not (sec.get("dc") is float or sec.get("dc") is int) or ids.has(sec.get("id")) \
					or not str(sec.get("skill", "perception")) in ExplorationRules.SEARCH_SKILLS:
				e.append("комната %s: секрет — уникальный id, dc (число), text, skill perception | investigation" % id)
			else:
				ids[sec["id"]] = true
		var enc: Variant = r.get("encounter")
		if enc != null:
			if not (enc is Dictionary) or str(enc.get("id", "")).is_empty() or not (enc.get("enemies") is Array) or (enc["enemies"] as Array).is_empty():
				e.append("комната %s: encounter — {id, enemies: [{monster, count}]}" % id)
			else:
				var foes: Array = (enc["enemies"] as Array).duplicate()
				for wave: Variant in enc.get("waves", []):
					if not (wave is Dictionary) or not (wave.get("enemies") is Array) or int(wave.get("round", 0)) < 2:
						e.append("комната %s: встреча %s — волна {round ≥ 2, side, enemies}" % [id, enc["id"]])
					else:
						foes.append_array(wave["enemies"])
				var help: Variant = enc.get("help")
				if help != null:
					if not (help is Dictionary) or not (help.get("enemies") is Array):
						e.append("комната %s: встреча %s — help {enemies, side, delay}" % [id, enc["id"]])
					else:
						foes.append_array(help["enemies"])
				for foe: Variant in foes:
					if not (foe is Dictionary) or not data.get("monsters", {}).has(str(foe.get("monster", ""))):
						e.append("комната %s: встреча %s — нет монстра %s" % [id, enc["id"], foe.get("monster") if foe is Dictionary else foe])
		var safe: Variant = r.get("safe")
		if safe != null and (not (safe is Dictionary) or int(safe.get("rest_cost_cp", -1)) < 0):
			e.append("комната %s: safe — {rest_cost_cp: число ≥ 0}" % id)
	var catalog: Dictionary = data["items"]["catalog"]
	for id: String in w["npcs"]:
		var n: Dictionary = w["npcs"][id]
		if str(n.get("name", "")).is_empty() or str(n.get("role", "")).is_empty():
			e.append("NPC %s: нужны name и role" % id)
		if not GENDERS.has(str(n.get("gender", ""))):
			e.append("NPC %s: gender — одно из %s" % [id, ", ".join(GENDERS)])
		var stock: Variant = n.get("stock", [])
		if not (stock is Array or stock is Dictionary):
			e.append("NPC %s: stock — список id или {id: количество}" % id)
			continue
		for item: Variant in stock:
			if not catalog.has(str(item)):
				e.append("NPC %s: в каталоге нет предмета %s" % [id, item])
		var has_stock: bool = (stock as Array).size() > 0 if stock is Array else (stock as Dictionary).size() > 0
		if has_stock and not bool(n.get("trader", false)):
			e.append("NPC %s: есть stock, но нет trader: true" % id)
	return e


static func _validate_characters(c: Dictionary, data: Dictionary) -> Array[String]:
	var e: Array[String] = []
	var presets: Variant = c.get("presets")
	if not (presets is Array):
		return ["characters.presets: список"]
	var ids := {}
	for p: Variant in presets:
		if not (p is Dictionary) or not (p.get("choices") is Dictionary):
			e.append("готовый персонаж без choices")
			continue
		var id := str(p.get("id", ""))
		if id.is_empty() or ids.has(id):
			e.append("готовый персонаж: id пустой или повторяется (%s)" % id)
		ids[id] = true
		for key: String in ["summary", "story"]:
			if str(p.get(key, "")).is_empty():
				e.append("готовый персонаж %s: нет %s" % [id, key])
		var ch: Dictionary = CharacterBuilder.empty_choices()
		ch.merge(p["choices"], true)
		for step: String in CharacterBuilder.steps(ch, data):
			for err: String in CharacterBuilder.errors(ch, data, step):
				e.append("готовый персонаж %s, шаг %s: %s" % [id, step, err])
	return e


# --- applying ------------------------------------------------------------------------


## The game data for a pack: base SRD data filtered and renamed by pack.rules, plus "world", "pack",
## "presets" and "names". The base stays untouched.
static func apply_rules(base: Dictionary, b: Dictionary) -> Dictionary:
	var d := base.duplicate(true)
	var p: Dictionary = b["pack"]
	var rules: Dictionary = p.get("rules", {})
	for kind: String in ["races", "classes", "backgrounds"]:
		var keep: Array = rules.get(kind, [])
		if keep.is_empty():
			continue
		var pool := _known(d, kind)
		for id: String in pool.keys():
			if not keep.has(id):
				pool.erase(id)
	var catalog: Dictionary = d["items"]["catalog"]
	for id: Variant in rules.get("items_exclude", []):
		catalog.erase(str(id))
	var rename: Dictionary = rules.get("rename", {})
	for kind: String in rename:
		var pool := _known(d, kind)
		for id: String in rename[kind]:
			if pool.has(id):
				pool[id].merge(rename[kind][id], true)
	d["world"] = b["world"]
	d["pack"] = p
	d["presets"] = b["characters"].get("presets", [])
	d["names"] = p.get("names", d["game"]["creation"]["names"])
	return d


## Master defaults of a pack for the new game screen.
static func default_settings(p: Dictionary) -> Dictionary:
	var content: Dictionary = p.get("content", {})
	return {"world": str(p.get("id", "")), "dm_style": str(p.get("dm_style", "classic")), "death_mode": "story",
		"violence": str(content.get("violence", "medium")), "lines": (content.get("lines", []) as Array).duplicate(),
		"veils": (content.get("veils", []) as Array).duplicate()}


## A quest or exit condition has one fact (a button — talk / choice — only on a quest step), all / any recursively.
static func _when_ok(when: Variant, top: bool) -> bool:
	if not (when is Dictionary):
		return false
	var keys: Array = (when as Dictionary).keys().filter(func(k: String) -> bool: return k != "item")
	if keys.size() != 1:
		return false
	var k := str(keys[0])
	if k in ["talk", "choice"]:
		return top
	if k in ["all", "any"]:
		return when[k] is Array and not (when[k] as Array).is_empty() and (when[k] as Array).all(func(w: Variant) -> bool: return _when_ok(w, false))
	return k in ["encounter", "secret", "room", "flag"]

