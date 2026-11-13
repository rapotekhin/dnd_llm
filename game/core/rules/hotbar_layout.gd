class_name HotbarLayout
extends RefCounted
## Where each icon of the hotbar stands (v0.8.4.43, as in BG3): the bar is a grid of `rows` rows cut by dividers into
## sections; a section is a run of columns, `cols` of them seen; a slot holds the key of a cell (its node name:
## «Cast_fire_bolt», «Do_dash», «LookButton») or "" — empty. A cell the player never placed goes into the first empty slot
## in sight of its kind's section; one dragged elsewhere stays where it was put, in any section; one dragged off the bar is
## hidden until it is dragged back from the sheet. A slot keeps its key while the act is not offered (a spent scroll, a
## fight's act out of a fight), so it comes back to its place. Pure data: the state is a Dictionary the profile keeps
## (SaveManager.hotbar).
## {rows, modes: {<mode>: {sections: [{kind, cols, width, fixed, skip, grid: [[key|"" × MAX_ROWS], …]}], hidden: [key]}}}
## v0.8.4.43.14 (the author: «вся эта панель должна быть идентична как в бою, так и вне боя»): the bar has one layout, `BAR`,
## in a fight and out of it, and a section «Боевые» (`combat`) of the fight's acts. `cols` is what is drawn now, `width`
## what the player set by a divider: a bar too narrow for it draws less this time and never forgets it.
## v0.8.4.43.49 (the author: «группы как карты из колоды, как в BG3… иконка, оказавшаяся под соседней группой, прячется на
## своём месте, а не переезжает в другую клетку»): a section is a card of columns, its `grid` a list of columns of
## MAX_ROWS slots each, and the bar shows `cols` of them from `skip`. A divider moved right slides the next card under
## the one on its left (its first columns hidden, `skip` grows); moved left it shows them again — no icon ever changes its
## cell or its place on the screen. A row taken off by «−» only hides its icons; the bar never scrolls. A slot is told by
## `at(column, row)`.

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


## The number of a slot of a section: its column of the section's own card and its row — the same whatever is seen.
static func at(column: int, row: int) -> int:
	return column * MAX_ROWS + row


static func mode(state: Dictionary, m: String) -> Dictionary:
	if not state.has("modes"):
		state["modes"] = {}
	if not (state["modes"] as Dictionary).has(m):
		var sections: Array = []
		var hidden: Array = []
		var old: Dictionary = state["modes"].get("peace", {}) if m == BAR else {}
		for sec: Dictionary in old.get("sections", []):  # the bar of the days of two layouts: its peace's arrangement kept
			sections.append({"kind": str(sec["kind"]), "cols": int(sec.get("cols", 0)), "slots": (sec["slots"] as Array).map(func(k: Variant) -> String: return key_of(str(k)))})
		for k: Variant in old.get("hidden", []):
			hidden.append(key_of(str(k)))
		for k: String in KINDS.get(m, ["common"]):
			if not sections.any(func(sec: Dictionary) -> bool: return str(sec["kind"]) == k):
				sections.append({"kind": k, "cols": 0, "grid": []})
		state["modes"][m] = {"sections": sections, "hidden": hidden}
	for sec: Dictionary in state["modes"][m]["sections"]:
		_card(sec)
	return state["modes"][m]


## A section as a card of columns: one laid out in rows of its `cols` (the bar before v0.8.4.43.49) keeps each key in its
## column and row; a key past the last row goes back to the first free slot.
static func _card(sec: Dictionary) -> void:
	if sec.has("grid"):
		if not sec.has("skip"):
			sec["skip"] = 0
		return
	var grid: Array = []
	var wide := maxi(1, int(sec.get("cols", 0)))
	var slots: Array = sec.get("slots", [])
	for j in slots.size():
		var col := j % wide
		var row := j / wide
		if str(slots[j]) != "" and row < MAX_ROWS:
			_column(grid, col)[row] = str(slots[j])
	sec["grid"] = grid
	sec["skip"] = 0
	sec.erase("slots")


## Column `col` of `grid`, made with its empty slots when the card is not that wide yet.
static func _column(grid: Array, col: int) -> Array:
	while grid.size() <= col:
		var empty: Array = []
		empty.resize(MAX_ROWS)
		empty.fill("")
		grid.append(empty)
	return grid[col]


## The sections as they are to be drawn: each {kind, cols, skip, slots, index} — `slots` the keys seen in the order the
## grid is drawn (row by row, "" for an empty slot or a cell not offered now), `index` the number of each slot (`at`);
## `cells` — {key: kind} of what is offered, `total` — the columns the bar has room for. A section with no cell takes no
## column. `side` — "fight" or "peace" for the one bar of both (v0.8.4.43.14): a section is as wide as the larger of its two
## sides needs, so the dividers stand where they stood when a fight begins and ends.
static func place(state: Dictionary, m: String, cells: Dictionary, total: int, side := "") -> Array:
	var md := mode(state, m)
	var hidden: Array = md["hidden"]
	var sections: Array = md["sections"]
	var placed := {}
	for sec: Dictionary in sections:
		for col: Array in sec["grid"]:
			for k: Variant in col:
				if str(k) != "":
					placed[str(k)] = true
	var fresh := {}  # kind → [keys not placed yet], in the order offered
	for key: String in cells:
		if not placed.has(key) and not hidden.has(key):
			_section_of(sections, str(cells[key]))
			if not fresh.has(str(cells[key])):
				fresh[str(cells[key])] = []
			(fresh[str(cells[key])] as Array).append(key)
	_fit(state, sections, cells, fresh, total, side)
	var r := rows(state)
	for sec: Dictionary in sections:  # the new ones into the first free slot in sight (the author: «на видное место»)
		for key: String in fresh.get(str(sec["kind"]), []):
			_put_new(sec, key, r)
	var out: Array = []
	for sec: Dictionary in sections:
		if int(sec["cols"]) > 0:
			var seen := view(state, sec, int(sec["skip"]), int(sec["cols"]), cells)
			out.append({"kind": sec["kind"], "cols": sec["cols"], "skip": sec["skip"], "slots": seen["slots"], "index": seen["index"]})
	return out


## The slots of `sec` seen from its column `from`, `n` columns wide, row by row: {slots: [key|""], index: [at]} — the
## bar draws `place`'s window, a tab of one kind the card from its first column at the bar's whole width.
static func view(state: Dictionary, sec: Dictionary, from: int, n: int, cells: Dictionary) -> Dictionary:
	var keys: Array = []
	var index: Array = []
	var grid: Array = sec["grid"]
	for row in rows(state):
		for col in range(from, from + n):
			var k := str(grid[col][row]) if col >= 0 and col < grid.size() else ""
			keys.append(k if cells.has(k) else "")
			index.append(at(col, row))
	return {"slots": keys, "index": index}


## A new key into the first free slot in sight, column by column — the icons packed to the left, so a narrower section
## hides the fewest; with none, the first free one past the seen columns.
static func _put_new(sec: Dictionary, key: String, r: int) -> void:
	var grid: Array = sec["grid"]
	var from := int(sec["skip"])
	for col in range(from, from + maxi(1, int(sec["cols"]))):
		for row in r:
			if str(_column(grid, col)[row]) == "":
				grid[col][row] = key
				return
	var col := from + maxi(1, int(sec["cols"]))
	while true:
		var c := _column(grid, col)
		for row in r:
			if str(c[row]) == "":
				c[row] = key
				return
		col += 1


## The section `index` of the drawn ones: its record, {} — none.
static func drawn(state: Dictionary, m: String, index: int) -> Dictionary:
	var d := _drawn(mode(state, m)["sections"])
	return d[index] if index >= 0 and index < d.size() else {}


## Moves `key` into slot `index` (`at`) of section `to` (an index into the drawn sections): whatever stood there goes to
## where `key` was, a key from the hidden list takes its place on the bar again. `packed` — a drop on a tab of one kind,
## which shows the card from its first column (v0.8.4.43.14): a slot out of the bar's sight takes the first free one in it,
## or the last one in sight when none is free (its icon goes where `key` was), so it is not left out of sight of the bar.
static func move(state: Dictionary, m: String, key: String, to: int, index: int, packed := false) -> void:
	var md := mode(state, m)
	var sec := drawn(state, m, to)
	if sec.is_empty() or index < 0:
		return
	var col := index / MAX_ROWS
	var row := index % MAX_ROWS
	if packed and (col < int(sec["skip"]) or col >= int(sec["skip"]) + int(sec["cols"]) or row >= rows(state)):
		var free := _free_in_sight(state, sec)
		if free < 0:
			free = at(int(sec["skip"]) + int(sec["cols"]) - 1, rows(state) - 1)
		col = free / MAX_ROWS
		row = free % MAX_ROWS
	var target := _column(sec["grid"], col)
	var was := str(target[row])
	if was == key:
		return
	var from := _where(md["sections"], key)
	if not from.is_empty():
		(from[0] as Array)[from[1]] = was
	elif was != "":
		_put_new(sec, was, rows(state))
	(md["hidden"] as Array).erase(key)
	target[row] = key


## The first free slot in sight of `sec` (`at`), -1 — none.
static func _free_in_sight(state: Dictionary, sec: Dictionary) -> int:
	var grid: Array = sec["grid"]
	for col in range(int(sec["skip"]), int(sec["skip"]) + int(sec["cols"])):
		for row in rows(state):
			if col >= grid.size() or str(grid[col][row]) == "":
				return at(col, row)
	return -1


## Takes `key` off the bar: it stays off until dragged back.
static func hide(state: Dictionary, m: String, key: String) -> void:
	var md := mode(state, m)
	var at_ := _where(md["sections"], key)
	if not at_.is_empty():
		(at_[0] as Array)[at_[1]] = ""
	if not (md["hidden"] as Array).has(key):
		(md["hidden"] as Array).append(key)


## The divider after drawn section `i` moves by `delta` columns (v0.8.4.43.49, as a deck of cards): the section on its
## left shows as many more (or fewer) of its own columns, the one on its right hides as many of its first ones under it
## (or shows them again, with empty ones before its first when it had none hidden). No icon moves; each section keeps at
## least one column, and both keep the width the player gave them.
static func shift(state: Dictionary, m: String, i: int, delta: int) -> void:
	var sections := _drawn(mode(state, m)["sections"])
	if i < 0 or i + 1 >= sections.size() or delta == 0:
		return
	var a: Dictionary = sections[i]
	var b: Dictionary = sections[i + 1]
	var d := reach(state, m, i, delta)
	a["cols"] = int(a["cols"]) + d
	b["cols"] = int(b["cols"]) - d
	b["skip"] = int(b["skip"]) + d
	if int(b["skip"]) < 0:  # its card had nothing before: empty columns laid before it, its icons where they stood
		for n in -int(b["skip"]):
			var empty: Array = []
			empty.resize(MAX_ROWS)
			empty.fill("")
			(b["grid"] as Array).push_front(empty)
		b["skip"] = 0
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
	var sec := {"kind": kind, "cols": 0, "grid": [], "skip": 0}
	sections.append(sec)
	return sec


## [column, row] where `key` stands, [] — nowhere.
static func _where(sections: Array, key: String) -> Array:
	for sec: Dictionary in sections:
		for col: Array in sec["grid"]:
			var i := col.find(key)
			if i >= 0:
				return [col, i]
	return []


## The columns of each section: a section with something to show gets at least one; the rest of `total` goes by what
## each needs — its cells by rows and the furthest of them in sight, on the larger of the two `side`s it was last laid on
## — and a width the player set by a divider is kept while the bar's width allows. `fresh` — {kind: [keys]} not placed yet.
static func _fit(state: Dictionary, sections: Array, cells: Dictionary, fresh: Dictionary, total: int, side := "") -> void:
	var r := rows(state)
	var live: Array = []
	for sec: Dictionary in sections:
		var n: int = (fresh.get(str(sec["kind"]), []) as Array).size()
		var far := 0
		var grid: Array = sec["grid"]
		for col in grid.size():
			for row in r:
				if cells.has(str(grid[col][row])):
					n += 1
					far = maxi(far, col + 1 - int(sec["skip"]))
		var want := maxi(ceili(float(n) / r), far) if n > 0 else 0
		if want > 0:
			live.append(sec)
		else:
			sec["cols"] = 0
		if side != "":
			if not sec.has("need"):
				sec["need"] = {}
			sec["need"][side] = want
			for v: Variant in (sec["need"] as Dictionary).values():
				want = maxi(want, int(v)) if want > 0 else 0
		sec["_n"] = want
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
		need += maxi(1, int(sec["_n"]))
	var left := room
	for i in free.size():
		var sec: Dictionary = free[i]
		var want := maxi(1, int(sec["_n"]))
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
