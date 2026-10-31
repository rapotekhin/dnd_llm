class_name Thing
extends RefCounted
## A thing and its copies (v0.7.65). A template is a row of the catalog or of s.items; a store counts copies {id: qty}, so
## identical things are one number. What sets a copy apart — its owner, the charges spent, its water, when it was got,
## the damage and statuses it took — lies beside the count: h["copies"] {id: [state]}, one state per copy that differs,
## oldest first; the rest of the count are plain. `h` is anything that holds a store: the hero (`inventory`), a bag, a
## container (`contents`). A move takes the states with it, so nothing is lost on the way. Code that only spends a thing
## lowers the count, and `trim` drops the oldest states past it.


static func _key(h: Dictionary) -> String:
	return "inventory" if h.has("inventory") else "contents"


static func store(h: Dictionary) -> Dictionary:
	var key := _key(h)
	if not (h.get(key) is Dictionary):
		h[key] = {}
	return h[key]


static func count(h: Dictionary, id: String) -> int:
	return int(h.get(_key(h), {}).get(id, 0))


## The states of `id`, read only.
static func states(h: Dictionary, id: String) -> Array:
	return h.get("copies", {}).get(id, [])


static func _list(h: Dictionary, id: String) -> Array:
	if not (h.get("copies") is Dictionary):
		h["copies"] = {}
	if not (h["copies"] as Dictionary).has(id):
		h["copies"][id] = []
	return h["copies"][id]


static func _tidy(h: Dictionary, id: String) -> void:
	if h.has("copies"):
		if (h["copies"].get(id, []) as Array).is_empty():
			(h["copies"] as Dictionary).erase(id)
		if (h["copies"] as Dictionary).is_empty():
			h.erase("copies")


## `qty` more of `id`, the first of them with these `had` states.
static func add(h: Dictionary, id: String, qty: int, had: Array = []) -> void:
	var st := store(h)
	st[id] = int(st.get(id, 0)) + qty
	lay(h, id, had)


## States of copies that are already counted (a thing that came in by ItemRules.found).
static func lay(h: Dictionary, id: String, had: Array) -> void:
	var useful := had.filter(func(x: Dictionary) -> bool: return not x.is_empty())
	if not useful.is_empty():
		_list(h, id).append_array(useful)
		(h["copies"][id] as Array).sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("got", 0)) < int(b.get("got", 0)))


## `qty` of `id` leave `h`: plain copies first, then the oldest. Their states.
static func take(h: Dictionary, id: String, qty: int) -> Array:
	var st := store(h)
	var have := int(st.get(id, 0))
	var list: Array = states(h, id)
	var marked := maxi(0, qty - maxi(0, have - list.size()))
	var gone := list.slice(0, marked)
	if not list.is_empty():
		h["copies"][id] = list.slice(marked)
		_tidy(h, id)
	if have - qty > 0:
		st[id] = have - qty
	else:
		st.erase(id)
	return gone


## `qty` of `id` go from one holder to another, as `as_id` when the name changes on the way.
static func move(from: Dictionary, to: Dictionary, id: String, qty: int, as_id: String = "") -> void:
	var had := take(from, id, qty)
	add(to, id if as_id.is_empty() else as_id, qty, had)


## The whole stack is known by another id now.
static func rename(h: Dictionary, old: String, new: String) -> void:
	if states(h, old).is_empty():
		return
	var had: Array = h["copies"][old]
	(h["copies"] as Dictionary).erase(old)
	h.erase("copies") if (h["copies"] as Dictionary).is_empty() else null
	lay(h, new, had)


## The state of copy `i`, made if it is plain so far.
static func nth(h: Dictionary, id: String, i: int) -> Dictionary:
	var list := _list(h, id)
	while list.size() <= i:
		list.append({})
	return list[i]


## One copy is gone, not the oldest: the one at `i`.
static func drop_at(h: Dictionary, id: String, i: int) -> void:
	if i < states(h, id).size():
		(h["copies"][id] as Array).remove_at(i)
		_tidy(h, id)
	take(h, id, 1) if states(h, id).size() < count(h, id) or states(h, id).is_empty() else _spent(h, id)


static func _spent(h: Dictionary, id: String) -> void:
	var st := store(h)
	st[id] = int(st.get(id, 0)) - 1
	if int(st[id]) <= 0:
		st.erase(id)


## Up to `qty` copies of `id` get `field`; those that have it keep theirs.
static func stamp(h: Dictionary, id: String, qty: int, field: String, value: Variant) -> void:
	if qty <= 0 or count(h, id) <= 0:
		return
	var list := _list(h, id)
	var left := qty
	for st: Dictionary in list:
		if left > 0 and not st.has(field):
			st[field] = value
			left -= 1
	while left > 0 and list.size() < count(h, id):
		list.append({field: value})
		left -= 1
	_tidy(h, id)


## A field off every copy of `id` that has it with this value.
static func clear(h: Dictionary, id: String, field: String, value: Variant) -> void:
	var list: Array = states(h, id)
	for st: Dictionary in list.duplicate():
		if st.get(field) == value:
			st.erase(field)
			if st.is_empty():
				list.erase(st)
	_tidy(h, id)


## States past the count go: what was spent took the oldest.
static func trim(h: Dictionary) -> void:
	for id: String in h.get("copies", {}).keys():
		var list: Array = h["copies"][id]
		var n := count(h, id)
		while list.size() > n:
			list.pop_front()
		_tidy(h, id)


## The hero and the hero's bags: everything that goes with the hero.
static func holders(c: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = [c]
	for b: Dictionary in c.get("bags", {}).values():
		out.append(b)
	return out
