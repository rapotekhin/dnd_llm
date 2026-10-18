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
	var catalog: Dictionary = data["items"]["catalog"]
	for id: String in w["npcs"]:
		var n: Dictionary = w["npcs"][id]
		if str(n.get("name", "")).is_empty() or str(n.get("role", "")).is_empty():
			e.append("NPC %s: нужны name и role" % id)
		if not GENDERS.has(str(n.get("gender", ""))):
			e.append("NPC %s: gender — одно из %s" % [id, ", ".join(GENDERS)])
		for item: Variant in n.get("stock", []):
			if not catalog.has(str(item)):
				e.append("NPC %s: в каталоге нет предмета %s" % [id, item])
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
