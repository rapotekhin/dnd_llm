class_name PortraitRules
extends RefCounted
## The one place a face is chosen (v0.8.4.43.5.2, the author: portraits drawn by Anima instead of a token's letter), as
## IconRules is for an icon: the token on the map, a body of a fight, the queue, the party's portraits and the creature's
## card all ask here and only show the picture. `who` is anybody (Sheet): the hero, a fighter, a record, a person.
## - A body not its own (Wild Shape, a werewolf's form) — that template's face.
## - A record's own `look.portrait` (a pack's person drawn by hand).
## - A person of a race of the game — people/<race>/<male|female>/<age>__<n>: the race by CharacterRules.race_id, the age
##   by BodyRules (a pack person's own, else picked by its id), n by its id, so one person keeps one face; a child grown
##   keeps its number in its new age. The hero — its own pick at creation (`portrait`), else by its name.
## - Anybody else — its template's monsters/<template>__<n>, n by its id.
## A missing variant gives way to another of the same; nothing at all — "" and the letter is drawn. Numbers and the root
## are `portraits` of data/icons.json.

static var _exists := {}  # path → bool: a file is looked for once a run


static func cfg(data: Dictionary) -> Dictionary:
	return data.get("icons", {}).get("portraits", {})


static func root(data: Dictionary) -> String:
	return str(cfg(data).get("root", "res://assets/portraits/"))


## The face of anybody: a res:// path, "" — none.
static func of(s: GameSession, data: Dictionary, who: Dictionary) -> String:
	if who.is_empty():
		return ""
	var h := Sheet.holder(s, who)
	var body := Guise.body(h)
	if not body.is_empty():
		return monster(data, str(body["monster"]), str(who.get("id", "")))
	var own := str(Look.of(h).get("portrait", ""))
	if has_file(own):
		return own
	if Sheet.is_hero(who):
		var c := s.character
		return person(data, CharacterRules.race_id(data, c), str(c.get("gender", "")), str((c.get("body", {}) as Dictionary).get("age", "")),
			hero_variant(data, c))
	var npc_id := person_id(data, who)
	if not npc_id.is_empty():
		var n := WorldView.new(data["world"]).npc(npc_id)
		var mine := str(Look.of(n).get("portrait", ""))
		if has_file(mine):
			return mine
		var age := str(BodyRules.npc(data, npc_id, n).get("age", ""))
		var face := person(data, CharacterRules.race_id(data, n), str(n.get("gender", "")), age, variant_of(data, age, EntityRef.npc(npc_id)))
		if not face.is_empty():
			return face
	return monster(data, Sheet.template_id(data, who), str(who.get("id", "")))


## The face of an id (the hero, a fighter, a record, a person): of(Sheet.who).
static func of_id(s: GameSession, data: Dictionary, id: String) -> String:
	return of(s, data, Sheet.who(s, data, id))


## The person a `who` is: its `npc_id`, or its id when the world knows such a person; "" — not a person.
static func person_id(data: Dictionary, who: Dictionary) -> String:
	var id := str(who.get("npc_id", ""))
	if id.is_empty() and data["world"].get("npcs", {}).has(str(who.get("id", ""))):
		id = str(who["id"])
	return id


## A person's face of a race, a sex and an age: variant `n`, else another of them; "" — none drawn (or no race of the game).
static func person(data: Dictionary, race: String, gender: String, age: String, n: int) -> String:
	if race.is_empty():
		return ""
	return _first(variants(data, race, gender, age), n)


## The paths of every variant of a race, a sex and an age, in order (drawn or not): the creation screen's picks.
static func variants(data: Dictionary, race: String, gender: String, age: String) -> Array[String]:
	var out: Array[String] = []
	if race.is_empty():
		return out
	var a := age if not age.is_empty() else "adult"
	var at := "%speople/%s/%s/%s__" % [root(data), race, "female" if gender == "female" else "male", a]
	for i in count(data, "people", a):
		out.append(at + str(i + 1) + ".webp")
	return out


## A template's face: variant by `seed_text`, else another; "" — none drawn.
static func monster(data: Dictionary, template: String, seed_text: String) -> String:
	if template.is_empty():
		return ""
	var paths: Array[String] = []
	for i in count(data, "monsters", ""):
		paths.append("%smonsters/%s__%d.webp" % [root(data), template, i + 1])
	return _first(paths, pick(paths.size(), template + "|" + seed_text))


## How many variants a kind has («people» by its age's `by_age`).
static func count(data: Dictionary, kind: String, age: String) -> int:
	var c: Dictionary = cfg(data).get(kind, {})
	return maxi(1, int((c.get("by_age", {}) as Dictionary).get(age, c.get("variants", 1))))


## A person's number of its age by its seed, from 1.
static func variant_of(data: Dictionary, age: String, seed_text: String) -> int:
	return pick(count(data, "people", age if not age.is_empty() else "adult"), seed_text)


## The hero's number: its pick at creation, else by its name.
static func hero_variant(data: Dictionary, c: Dictionary) -> int:
	var own := int(c.get("portrait", 0))
	if own > 0:
		return own
	return variant_of(data, str((c.get("body", {}) as Dictionary).get("age", "")), "hero:" + str(c.get("name", "")))


static func pick(n: int, seed_text: String) -> int:
	return posmod(hash(seed_text), maxi(1, n)) + 1


static func has_file(path: String) -> bool:
	if path.is_empty():
		return false
	if not _exists.has(path):
		_exists[path] = ResourceLoader.exists(path)
	return _exists[path]


## Files put in while the game runs (a test) are seen again.
static func forget() -> void:
	_exists.clear()


## Variant `n` (from 1) of `paths` when drawn, else the first drawn after it; "" — none.
static func _first(paths: Array[String], n: int) -> String:
	if paths.is_empty():
		return ""
	var from := clampi(n, 1, paths.size()) - 1
	for k in paths.size():
		var p := paths[(from + k) % paths.size()]
		if has_file(p):
			return p
	return ""
