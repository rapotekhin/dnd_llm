class_name HotbarLayout
extends RefCounted
## Where each icon of the hotbar stands (v0.8.4.43, as in BG3): the bar is a grid of `rows` rows cut by dividers into
## sections; a section is a run of slots, `cols` wide; a slot holds the key of a cell (its node name: «Cast_fire_bolt»,
## «Do_dash», «LookButton») or "" — empty. A cell the player never placed goes into the first empty slot of its kind's
## section; one dragged elsewhere stays where it was put, in any section; one dragged off the bar is hidden until it is
## dragged back from the sheet. A slot keeps its key while the act is not offered (a spent scroll, a fight's act out of
## a fight), so it comes back to its place. Pure data: the state is a Dictionary the profile keeps (SaveManager.hotbar).
## {rows, modes: {<mode>: {sections: [{kind, cols, width, fixed, slots: [key|""]}], hidden: [key]}}}
## v0.8.4.43.14 (the author: «вся эта панель должна быть идентична как в бою, так и вне боя»): the bar has one layout, `BAR`,
## in a fight and out of it, and a section «Боевые» (`combat`) of the fight's acts. `cols` is what is drawn now, `width`
## what the player set by a divider: a bar too narrow for it draws less this time and never forgets it.

const ROWS := 2
const MAX_ROWS := 4
const BAR := "bar"  ## the one layout of the bar, in a fight and out of it
const KINDS := {"bar": ["common", "combat", "class", "items", "deeds", "passive"],
	"peace": ["common", "class", "items", "deeds", "passive"], "fight": ["common", "class", "items", "passive"]}


## The key of a cell in the layout, one in a fight and out of it (v0.8.4.43.14): a spell is «spell:<id>» whether it is cast
## (Cast_) or pinned to the words (Pin_spell_), a use of a feature «feature:<id>», a thing «item:<id>»; any other cell
## is its node's name («Do_dash», «LookButton»). A key that is already one stays as it is.
static func key_of(name: String) -> String:
	for pair: Array in [["Pin_spell_", "spell:"], ["Cast_", "spell:"], ["Pin_feature_", "feature:"], ["Feature_", "feature:"],
			["Pin_item_", "item:"], ["Item_", "item:"]]:
		if name.begins_with(pair[0]):
			return str(pair[1]) + name.trim_prefix(pair[0])
	return name


static func rows(state: Dictionary) -> int:
	return clampi(int(state.get("rows", ROWS)), 1, MAX_ROWS)


static func set_rows(state: Dictionary, n: int) -> void:
	state["rows"] = clampi(n, 1, MAX_ROWS)


static func mode(state: Dictionary, m: String) -> Dictionary:
	if not state.has("modes"):
		state["modes"] = {}
	if not (state["modes"] as Dictionary).has(m):
		var sections: Array = []
		var hidden: Array = []
		var old: Dictionary = state["modes"].get("peace", {}) if m == BAR else {}
		for sec: Dictionary in old.get("sections", []):  # the bar of the days of two layouts: its peace's arrangement kept
			sections.append({"kind": str(sec["kind"]), "cols": 0, "slots": (sec["slots"] as Array).map(func(k: Variant) -> String: return key_of(str(k)))})
		for k: Variant in old.get("hidden", []):
			hidden.append(key_of(str(k)))
		for k: String in KINDS.get(m, ["common"]):
			if not sections.any(func(sec: Dictionary) -> bool: return str(sec["kind"]) == k):
				sections.append({"kind": k, "cols": 0, "slots": []})
		state["modes"][m] = {"sections": sections, "hidden": hidden}
	return state["modes"][m]


## The sections as they are to be drawn: each {kind, cols, slots} with the cells of `cells` ({key: kind}) in their
## slots; `total` — the columns the bar has room for. A section with no cell and no kept slot takes no column. `side` —
## "fight" or "peace" for the one bar of both (v0.8.4.43.14): a section is as wide as the larger of its two sides needs,
## so the dividers stand where they stood when a fight begins and ends.
static func place(state: Dictionary, m: String, cells: Dictionary, total: int, side := "") -> Array:
	var md := mode(state, m)
	var hidden: Array = md["hidden"]
	var sections: Array = md["sections"]
	var placed := {}
	for sec: Dictionary in sections:
		for k: Variant in sec["slots"]:
			if str(k) != "":
				placed[str(k)] = true
	for key: String in cells:
		if placed.has(key) or hidden.has(key):
			continue
		var sec := _section_of(sections, str(cells[key]))
		var slots: Array = sec["slots"]
		var free := slots.find("")
		if free >= 0:
			slots[free] = key
		else:
			slots.append(key)
	_fit(state, sections, cells, total, side)
	var out: Array = []
	for sec: Dictionary in sections:
		if int(sec["cols"]) > 0:
			var shown: Array = []
			for k: Variant in sec["slots"]:
				shown.append(str(k) if cells.has(str(k)) else "")
			var cap := rows(state) * int(sec["cols"])
			while shown.size() < cap or shown.size() % int(sec["cols"]) != 0:
				shown.append("")
			out.append({"kind": sec["kind"], "cols": sec["cols"], "slots": shown})
	return out


## Moves `key` into slot `index` of section `to` (an index into the drawn sections): whatever stood there goes to where
## `key` was, a key from the hidden list takes its place on the bar again. `packed` — a drop on a tab of one kind, which
## lays the section out at the bar's whole width (v0.8.4.43.14): past the section's last cell it goes right after it, so it
## is not left out of sight of the whole bar.
static func move(state: Dictionary, m: String, key: String, to: int, index: int, packed := false) -> void:
	var md := mode(state, m)
	var sections := _drawn(md["sections"])
	if to < 0 or to >= sections.size() or index < 0:
		return
	var target: Array = sections[to]["slots"]
	if packed:
		var last := -1
		for j in target.size():
			if str(target[j]) not in ["", key]:
				last = j
		index = mini(index, last + 1)
	while target.size() <= index:
		target.append("")
	var was := str(target[index])
	var from := _where(md["sections"], key)
	if not from.is_empty():
		(from[0] as Array)[from[1]] = was
	elif was != "":
		_section_of(md["sections"], _kind_guess(md["sections"], to)).get("slots", []).append(was)
	(md["hidden"] as Array).erase(key)
	target[index] = key


## Takes `key` off the bar: it stays off until dragged back.
static func hide(state: Dictionary, m: String, key: String) -> void:
	var md := mode(state, m)
	var at := _where(md["sections"], key)
	if not at.is_empty():
		(at[0] as Array)[at[1]] = ""
	if not (md["hidden"] as Array).has(key):
		(md["hidden"] as Array).append(key)


## The divider after drawn section `i` moves by `delta` columns: the section on its left takes them from the one on
## its right (each keeps at least one); both keep the width the player gave them.
static func shift(state: Dictionary, m: String, i: int, delta: int) -> void:
	var sections := _drawn(mode(state, m)["sections"])
	if i < 0 or i + 1 >= sections.size() or delta == 0:
		return
	var a: Dictionary = sections[i]
	var b: Dictionary = sections[i + 1]
	var d := reach(state, m, i, delta)
	a["cols"] = int(a["cols"]) + d
	b["cols"] = int(b["cols"]) - d
	for sec: Dictionary in [a, b]:
		sec["width"] = int(sec["cols"])
		sec["fixed"] = true


## How far the divider after drawn section `i` may go of `delta` columns: each side keeps one.
static func reach(state: Dictionary, m: String, i: int, delta: int) -> int:
	var sections := _drawn(mode(state, m)["sections"])
	if i < 0 or i + 1 >= sections.size():
		return 0
	return clampi(delta, 1 - int(sections[i]["cols"]), int(sections[i + 1]["cols"]) - 1)


static func _drawn(sections: Array) -> Array:
	return sections.filter(func(sec: Dictionary) -> bool: return int(sec["cols"]) > 0)


static func _section_of(sections: Array, kind: String) -> Dictionary:
	for sec: Dictionary in sections:
		if str(sec["kind"]) == kind:
			return sec
	var sec := {"kind": kind, "cols": 0, "slots": []}
	sections.append(sec)
	return sec


static func _kind_guess(sections: Array, drawn_i: int) -> String:
	var d := _drawn(sections)
	return str(d[drawn_i]["kind"]) if drawn_i < d.size() else "common"


## [slots, index] where `key` stands, [] — nowhere.
static func _where(sections: Array, key: String) -> Array:
	for sec: Dictionary in sections:
		var i := (sec["slots"] as Array).find(key)
		if i >= 0:
			return [sec["slots"], i]
	return []


## The columns of each section: a section with something to show gets at least one; the rest of `total` goes by how
## many cells each holds — on the larger of the two `side`s it was last laid on — and a width the player set by a
## divider is kept while the bar's width allows.
static func _fit(state: Dictionary, sections: Array, cells: Dictionary, total: int, side := "") -> void:
	var r := rows(state)
	var live: Array = []
	for sec: Dictionary in sections:
		var n := 0
		for k: Variant in sec["slots"]:
			if cells.has(str(k)):
				n += 1
		if n > 0:
			live.append(sec)
		else:
			sec["cols"] = 0
		if side != "":
			if not sec.has("need"):
				sec["need"] = {}
			sec["need"][side] = n
			for v: Variant in (sec["need"] as Dictionary).values():
				n = maxi(n, int(v)) if n > 0 else 0
		sec["_n"] = n
	if live.is_empty():
		return
	total = maxi(total, live.size())
	var fixed_sum := 0
	var fixed: Array = live.filter(func(sec: Dictionary) -> bool: return bool(sec.get("fixed", false)) and int(sec.get("width", 0)) > 0)
	for sec: Dictionary in fixed:
		fixed_sum += int(sec["width"])
	var free: Array = live.filter(func(sec: Dictionary) -> bool: return not fixed.has(sec))
	if fixed_sum + free.size() > total:  # the bar is narrower than the player's widths: by need this time, the widths kept
		free = live
		fixed_sum = 0
	else:
		for sec: Dictionary in fixed:
			sec["cols"] = int(sec["width"])
	var room := total - fixed_sum
	var need := 0
	for sec: Dictionary in free:
		need += maxi(1, ceili(float(int(sec["_n"])) / r))
	var left := room
	for i in free.size():
		var sec: Dictionary = free[i]
		var want := maxi(1, ceili(float(int(sec["_n"])) / r))
		var cols := want if need <= room else maxi(1, floori(float(want) * room / need))
		if i == free.size() - 1 and need > room:
			cols = maxi(1, left)
		sec["cols"] = cols
		left -= cols
	var i := 0
	while left > 0 and not free.is_empty():  # the rest of the bar as empty slots to drop into, spread over the sections
		free[i % free.size()]["cols"] = int(free[i % free.size()]["cols"]) + 1
		left -= 1
		i += 1
	for sec: Dictionary in sections:
		sec.erase("_n")
