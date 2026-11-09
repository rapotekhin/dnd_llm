class_name ItemRules
extends RefCounted
## Item catalog queries and the power check of master-made items (ADR-0008 §6): every property costs rarity
## points, the sum sets the rarity, the rarity is limited by character level and caps the value.
## v0.7.12 (5e items): an unidentified thing lives in the pack under `unk_<id>` — it works, but its name and properties
## are hidden until a short rest, an attunement, Identify or a trader's service; attunement (up to three, an hour);
## charges with a regain at dawn (the long rest); a catalog item's own `use` (potions, scrolls, wands, the pearl).

const UNKNOWN := "unk_"
const WORN := "worn"  # the source kind of what a worn thing lays (v0.8.4.26)
## The source kind of what a feature or a trait lays for good by `rules.feature_wear` (v0.8.4.26.1).
const BORN := "born"


## Definition of an item: catalog first, then items generated in this session. {} if unknown. An item on a `base`
## (a magic sword on a longsword, v0.6.3) takes the base's weapon / armor block, weight, type and properties.
static func def_of(items_data: Dictionary, session_items: Dictionary, id: String) -> Dictionary:
	if id.begins_with(UNKNOWN):  # an unidentified thing: the real item under a plain name (v0.7.12)
		var real := def_of(items_data, session_items, id.trim_prefix(UNKNOWN))
		if real.is_empty():
			return {}
		real["unknown_of"] = id.trim_prefix(UNKNOWN)
		real["name"] = unknown_name(items_data, real)
		real.erase("description")
		return real
	var d: Dictionary
	if items_data["catalog"].has(id):
		d = items_data["catalog"][id].duplicate()
		d["rarity"] = str(d.get("rarity", "common"))
	elif session_items.has(id):
		d = (session_items[id] as Dictionary).duplicate()
	else:
		return {}
	var base := str(d.get("base", ""))
	if not base.is_empty() and (items_data["catalog"].has(base) or session_items.has(base)):
		var b := def_of(items_data, session_items, base)  # a base on a base: a silvered +1 sword (v0.7.12), a fine imbued one
		for k: String in ["weapon", "armor", "weight"]:
			if not d.has(k) and b.has(k):
				d[k] = b[k]
		if b.has("weapon") or b.has("armor"):
			d["item_type"] = str(b.get("item_type", d.get("item_type", "gear")))
		var props: Array = (b.get("properties", []) as Array).duplicate()
		for p: Variant in d.get("properties", []):
			if not props.has(p):
				props.append(p)
		d["properties"] = props
	_expand(items_data, d, d.get("properties", []))
	var props: Array = d.get("properties", [])
	if (props.has("mithral") or props.has("masterwork")) and d.has("armor"):  # no Strength need, no stealth trouble
		var a: Dictionary = (d["armor"] as Dictionary).duplicate()
		a["str_min"] = 0
		a["stealth_disadvantage"] = false
		d["armor"] = a
	return d


## The plain thing under a made, magic or fine one (v0.8.4.42.14, one place): a fine storm longsword stands on a storm
## longsword that stands on `longsword` — its kind for what is read by id: a sprite, a shot, ammunition, a proficiency,
## Shillelagh. `id` itself when it has no base.
static func plain_of(items_data: Dictionary, session_items: Dictionary, id: String) -> String:
	var at := real_id(id)
	for i in 8:
		var d: Dictionary = items_data["catalog"].get(at, session_items.get(at, {}))
		var base := real_id(str(d.get("base", "")))
		if base.is_empty() or base == at or not (items_data["catalog"].has(base) or session_items.has(base)):
			return at
		at = base
	return at


## A property of parts (v0.7.65) among `added` adds the engine's own tokens to `d`; the rest are tokens themselves.
static func _expand(items_data: Dictionary, d: Dictionary, added: Array) -> void:
	var built: Dictionary = items_data.get("built", {})
	var all: Array = (d.get("properties", []) as Array).duplicate()
	for p: Variant in added:
		if not all.has(p):
			all.append(p)
		if built.has(p):
			all.append_array(built[p]["tokens"])
			d["built"] = (d.get("built", []) as Array) + [str(built[p]["name"])]
	d["properties"] = all


## What a service or a hand laid on one copy of a thing (v0.8.4.35): property tokens or made properties in its `props`.
static func marks(h: Dictionary, id: String, i: int = 0) -> Array:
	var list := Thing.states(h, id)
	return ((list[i] as Dictionary).get("props", []) as Array) if i >= 0 and i < list.size() else []


## The def of copy `i` of `id` that `h` holds: its template with the marks of that copy (a silvered sword is still a
## sword, v0.8.4.35). Anybody's things: the hero, a bag, a fighter in the hero's form.
static func copy_def(items_data: Dictionary, session_items: Dictionary, h: Dictionary, id: String, i: int = 0) -> Dictionary:
	var d := def_of(items_data, session_items, id)
	var extra := marks(h, id, i)
	if d.is_empty() or extra.is_empty():
		return d
	_expand(items_data, d, extra)
	d["marks"] = extra.duplicate()
	return d


## Lays a mark on a copy of `id` in `h` that lacks it, the indices of `first` tried first; the copy's index or -1.
static func mark(h: Dictionary, id: String, prop: String, first: Array[int] = []) -> int:
	var order: Array[int] = first.duplicate()
	for i in Thing.count(h, id):
		if not order.has(i):
			order.append(i)
	for i: int in order:
		if i < Thing.count(h, id) and not marks(h, id, i).has(prop):
			var st := Thing.nth(h, id, i)
			st["props"] = (st.get("props", []) as Array) + [prop]
			return i
	return -1


## «Плащ, свойства неизвестны» — what an unidentified thing is called.
static func unknown_name(items_data: Dictionary, d: Dictionary) -> String:
	var look := str(d.get("look", ""))
	if look.is_empty():
		look = str(def_of(items_data, {}, str(d.get("base", ""))).get("name", "вещь")) if not str(d.get("base", "")).is_empty() else "вещь"
	return look.left(1).to_upper() + look.substr(1) + str(items_data.get("unknown_suffix", ", свойства неизвестны"))


## The key a thing's `use.summon` is read by (AllyRules.summon_spec): the row's name in rules.allies.summons, or the thing's
## own id when it carries its row (a thing the master made, v0.8.4.28.7).
static func summon_key(id: String, fx: Dictionary) -> String:
	return real_id(id) if fx.get("summon") is Dictionary else str(fx.get("summon", ""))


static func real_id(id: String) -> String:
	return id.trim_prefix(UNKNOWN)


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"]["item_rules"]


# --- identification (v0.7.12) ----------------------------------------------------------------------


## A found magic thing (rarity above common, not one the master made) comes unidentified.
static func needs_identify(d: Dictionary) -> bool:
	return not d.is_empty() and not bool(d.get("generated", false)) and str(d.get("rarity", "common")) not in ["common", ""]


## The hero finds `qty` of `id` (a cache, a body, a thing in the room, the master's gift, a theft): a magic one comes
## unidentified. Returns the id it lies under.
static func found(c: Dictionary, data: Dictionary, session_items: Dictionary, id: String, qty: int = 1) -> String:
	var key := id
	if not id.begins_with(UNKNOWN) and needs_identify(def_of(data["items"], session_items, id)):
		key = UNKNOWN + id
	return add(c, key, qty)


## `qty` of a thing known for what it is into anybody's things (v0.8.4.29: the one road of «+N»): bought, made, a prize or a
## parcel named by who gives it. Returns its id. A thing found is `found`, a thing gone is `remove`.
static func add(c: Dictionary, id: String, qty: int = 1) -> String:
	var inv: Dictionary = c["inventory"]
	inv[id] = int(inv.get(id, 0)) + qty
	return id


## The trade tags of an item (v0.7.17.1, demand): its item_type, magic, scroll, tool and the item's own `tags`.
static func trade_tags(def: Dictionary) -> Array[String]:
	var out: Array[String] = [str(def.get("item_type", "gear"))]
	if not str(def.get("rarity", "common")) in ["common", ""]:
		out.append("magic")
	if bool(def.get("use", {}).get("scroll", false)):
		out.append("scroll")
	if def.has("tool"):
		out.append("tool")
	for t: Variant in def.get("tags", []):
		out.append(str(t))
	return out


static func unknown_ids(c: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for id: String in c.get("inventory", {}):
		if id.begins_with(UNKNOWN):
			out.append(id)
	return out


## Identifies the hero's unknown things (all, or `only`): the stack, the slot, the attunement and the charges move to
## the real id. Lines «опознано: Плащ защиты».
static func identify(c: Dictionary, data: Dictionary, session_items: Dictionary, only: Array = []) -> Array[String]:
	var lines: Array[String] = []
	var inv: Dictionary = c["inventory"]
	for key: String in unknown_ids(c):
		if not only.is_empty() and not only.has(key) and not only.has(real_id(key)):
			continue
		var real := real_id(key)
		inv[real] = int(inv.get(real, 0)) + int(inv[key])
		inv.erase(key)
		for eq: Dictionary in [c.get("equipped", {}), CharacterRules.stowed(c)]:
			for slot: String in eq:
				if str(eq[slot]) == key:
					eq[slot] = real
		var att: Array = c.get("attuned", [])
		if att.has(key):
			att[att.find(key)] = real
		var belt_ids: Array = c.get("belt", [])
		if belt_ids.has(key):
			belt_ids[belt_ids.find(key)] = real
		Thing.rename(c, key, real)
		lines.append("опознано: %s" % display_name(data["items"], session_items, real))
	if not lines.is_empty():  # «Артефакция» learns from the things it sees through (v0.7.39.1)
		lines.append_array(DevelopmentRules.add_xp(c, data, "artifice", lines.size() * _artifice_xp(data, "identify")))
	return lines


static func _artifice_xp(data: Dictionary, source: String) -> int:
	return int(DevelopmentRules.direction(data, "artifice").get("sources", {}).get(source, 0))


# --- the belt under the doll (v0.8.4.24, as in Pathfinder) -----------------------------------------------------------


## A thing for the belt: one used by an act — a potion, a scroll, a wand, a flask — or a light; ammunition and its quiver
## (v0.8.4.42.1). Food is eaten from the pack; a worn thing with a use (a hat, a circlet) is used where it is worn
## (`at_hand`, v0.8.4.26).
static func belt_fits(data: Dictionary, session_items: Dictionary, id: String) -> bool:
	var d := def_of(data["items"], session_items, real_id(id))
	if not CharacterRules.wear_slot(d, data).is_empty():
		return false
	if ContainerRules.at_hand_thing(data, session_items, id):
		return true
	var fx := consumable(data, id, session_items)
	if not fx.is_empty() and not fx.has("meal"):
		return true
	return (d.get("properties", []) as Array).has("light_source")


## The belt's cells of anybody, "" — empty: only these things are used, and a light here lights the way. A record that has
## not laid its own belt (a foe of the engine) carries the first things that fit, in the order of its pack.
static func belt(c: Dictionary, data: Dictionary, session_items: Dictionary) -> Array[String]:
	var size := int(data["rules"]["belt"]["size"])
	var inv: Dictionary = c.get("inventory", {})
	var out: Array[String] = []
	if c.get("belt") is Array:
		for i: int in size:
			var id := str((c["belt"] as Array)[i]) if i < (c["belt"] as Array).size() else ""
			out.append(id if int(inv.get(id, 0)) > 0 else "")
		return out
	for at_hand: bool in [false, true]:  # what is used first, then the arrows and their quiver in the cells left
		for id: String in inv:
			if out.size() < size and int(inv[id]) > 0 and belt_fits(data, session_items, id) 					and ContainerRules.at_hand_thing(data, session_items, id) == at_hand:
				out.append(id)
	while out.size() < size:
		out.append("")
	return out


static func on_belt(c: Dictionary, data: Dictionary, session_items: Dictionary, id: String) -> bool:
	return not id.is_empty() and belt(c, data, session_items).has(id)


## What is at hand to use (v0.8.4.26): the belt's things and the worn ones with a use of their own — a circlet, a hat, lenses
## are used where they are worn.
static func at_hand(c: Dictionary, data: Dictionary, session_items: Dictionary) -> Array[String]:
	var out := belt(c, data, session_items).filter(func(id: String) -> bool: return not id.is_empty())
	for id: String in CharacterRules.carried_ids(c, data, session_items):
		if not out.has(id) and not CharacterRules.wear_slot(def_of(data["items"], session_items, id), data).is_empty() and not consumable(data, id, session_items).is_empty():
			out.append(id)
	return out


## "" when the thing can go to the belt (the first empty cell, or `at`), otherwise the reason (localization key).
static func belt_why(c: Dictionary, data: Dictionary, session_items: Dictionary, id: String, at: int = -1) -> String:
	if int(c.get("inventory", {}).get(id, 0)) <= 0:
		return "EQUIP_NOT_OWNED"
	if not belt_fits(data, session_items, id):
		return "BELT_NOT_FOR"
	var cells := belt(c, data, session_items)
	if cells.has(id):
		return "BELT_ALREADY"
	return "" if (at >= 0 and at < cells.size()) or cells.has("") else "BELT_FULL"


## Lays the thing on the belt (belt_why first): the cell `at`, or the first empty one.
static func belt_put(c: Dictionary, data: Dictionary, session_items: Dictionary, id: String, at: int = -1) -> void:
	var cells := belt(c, data, session_items)
	cells[at if at >= 0 else cells.find("")] = id
	c["belt"] = cells


static func belt_take(c: Dictionary, data: Dictionary, session_items: Dictionary, at: int) -> void:
	var cells := belt(c, data, session_items)
	if at >= 0 and at < cells.size():
		cells[at] = ""
	c["belt"] = cells


# --- attunement (v0.7.12) --------------------------------------------------------------------------


## A cursed wondrous thing of the SRD bites on attunement; one whose `wear` lays a status bites as soon as it is put on
## (v0.8.4.39, the author: «на того, кто его надел») unless it asks for attunement itself.
static func needs_attunement(d: Dictionary) -> bool:
	var bites_worn: bool = d.get("wear") is Dictionary and (d["wear"] as Dictionary).has(STATUS)
	return bool(d.get("attunement", false)) or ((d.get("properties", []) as Array).has("cursed") and str(d.get("item_type", "")) == "wondrous" and not bites_worn)


static func attuned(c: Dictionary) -> Array:
	return c.get("attuned", [])


## An item works: no attunement needed, or the hero is attuned to it.
static func active(c: Dictionary, d: Dictionary, id: String) -> bool:
	return not needs_attunement(d) or attuned(c).has(id) or attuned(c).has(real_id(id))


static func cursed(d: Dictionary) -> bool:
	return (d.get("properties", []) as Array).has("cursed")


## "" when the hero can attune to the item now, otherwise a localization key.
static func can_attune(c: Dictionary, data: Dictionary, session_items: Dictionary, id: String) -> String:
	var d := def_of(data["items"], session_items, id)
	if int(c.get("inventory", {}).get(id, 0)) <= 0:
		return "EQUIP_NOT_OWNED"
	if not needs_attunement(d):
		return "ATTUNE_NOT_NEEDED"
	if attuned(c).has(id) or attuned(c).has(real_id(id)):
		return "ATTUNE_ALREADY"
	if attuned(c).size() >= int(cfg(data)["attune_max"]):
		return "ATTUNE_FULL"
	if bool(d.get("caster", false)) and str(c.get("spell_ability", "")).is_empty():
		return "ATTUNE_CASTER_ONLY"
	return ""


## An hour with the thing (the caller moves the clock): it is identified and bound. Lines.
static func attune(c: Dictionary, data: Dictionary, session_items: Dictionary, id: String) -> Array[String]:
	var lines: Array[String] = []
	if id.begins_with(UNKNOWN):
		lines = identify(c, data, session_items, [id])
	var real := real_id(id)
	if not c.has("attuned"):
		c["attuned"] = []
	(c["attuned"] as Array).append(real)
	var d := def_of(data["items"], session_items, real)
	lines.append("настройка: %s" % d.get("name", real))
	if cursed(d):
		lines.append("вещь проклята — снять её теперь нельзя")
	lines.append_array(DevelopmentRules.add_xp(c, data, "artifice", _artifice_xp(data, "attune")))
	return lines


## "" when the hero can end the attunement (a cursed thing holds on), otherwise a localization key.
static func can_unattune(c: Dictionary, data: Dictionary, session_items: Dictionary, id: String) -> String:
	if not attuned(c).has(id):
		return "ATTUNE_NOT_ATTUNED"
	if cursed(def_of(data["items"], session_items, id)):
		return "ITEM_CURSED"
	return ""


## A cursed thing on the body — worn or in the hands: it does not come off (v0.7.12). The author (v0.8.4.39): only the body
## holds it — one in the pockets, attuned or not, is given, sold, pawned or put away like any thing.
static func held_by_curse(c: Dictionary, data: Dictionary, session_items: Dictionary, id: String) -> bool:
	if id.is_empty() or not cursed(def_of(data["items"], session_items, id)):
		return false
	return CharacterRules.held_copies(c, id) > 0


## Remove Curse (the spell or the priestess): the cursed things come off and lose the attunement; they stay cursed.
static func lift_curse(c: Dictionary, data: Dictionary, session_items: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	for thing: String in (c.get("inventory", {}) as Dictionary).keys():
		if not held_by_curse(c, data, session_items, thing):
			continue
		unattune(c, thing)
		for eq: Dictionary in [c.get("equipped", {}), CharacterRules.stowed(c)]:
			for slot: String in eq:
				if str(eq[slot]) == thing:
					eq[slot] = ""
		lines.append("проклятие отпустило: %s (сама вещь проклята по-прежнему)" % display_name(data["items"], session_items, thing))
	return lines


static func unattune(c: Dictionary, id: String) -> void:
	(c.get("attuned", []) as Array).erase(id)


# --- charges (v0.7.12) -----------------------------------------------------------------------------


static func charges_max(d: Dictionary) -> int:
	return int(d.get("charges", {}).get("max", 0))


## All the charges of a stack: `_copies` × the item's; the copies are spent one after another.
static func charges_all(c: Dictionary, d: Dictionary, id: String) -> int:
	return charges_max(d) * _copies(c, id)


static func _copies(c: Dictionary, id: String) -> int:
	var inv: Dictionary = c.get("inventory", {})
	return maxi(1, int(inv.get(id, inv.get(real_id(id), 1))))


static func charges_left(c: Dictionary, d: Dictionary, id: String) -> int:
	var spent := 0
	var key := id if not Thing.states(c, id).is_empty() else real_id(id)
	for st: Dictionary in Thing.states(c, key):
		spent += int(st.get("used", 0))
	return maxi(0, charges_all(c, d, id) - spent)


## Spends a charge of the first copy that has one; the last one of a wand may turn it to dust (1 on a d20, DMG). Lines.
static func spend_charge(c: Dictionary, data: Dictionary, session_items: Dictionary, id: String, rng: RandomNumberGenerator) -> Array[String]:
	var d := def_of(data["items"], session_items, id)
	var most := charges_max(d)
	var i := 0
	while i < _copies(c, id) - 1 and int(Thing.nth(c, id, i).get("used", 0)) >= most:
		i += 1
	var st := Thing.nth(c, id, i)
	st["used"] = int(st.get("used", 0)) + 1
	var lines: Array[String] = ["зарядов: %d из %d" % [charges_left(c, d, id), charges_all(c, d, id)]]
	var empty := int(st["used"]) >= most
	if empty and bool(d.get("charges", {}).get("crumble", false)) and Roll.d20(rng) == 1:
		Thing.drop_at(c, id, i)
		lines.append("%s рассыпается в пыль" % d.get("name", id))
	elif empty and not d.get("charges", {}).has("regain"):
		Thing.drop_at(c, id, i)
		lines.append("%s закончилась" % d.get("name", id))
	return lines


## Dawn (the long rest): charges come back by the item's dice, copy by copy. Lines.
static func dawn(c: Dictionary, data: Dictionary, session_items: Dictionary, rng: RandomNumberGenerator) -> Array[String]:
	var lines: Array[String] = []
	for id: String in c.get("copies", {}):
		var d := def_of(data["items"], session_items, id)
		var regain := str(d.get("charges", {}).get("regain", ""))
		var back := 0
		for st: Dictionary in Thing.states(c, id):
			if regain.is_empty() or int(st.get("used", 0)) <= 0:
				continue
			var got := mini(int(st["used"]), CombatRules.roll_dice(rng, regain))
			st["used"] = int(st["used"]) - got
			back += got
		if back > 0:
			lines.append("%s: +%d %s" % [d.get("name", id), back, "заряд" if back == 1 else "заряда" if back < 5 else "зарядов"])
	return lines


## One use of the thing: a charge, or the thing itself. Lines.
static func consume(c: Dictionary, data: Dictionary, session_items: Dictionary, id: String, rng: RandomNumberGenerator) -> Array[String]:
	if bool(consumable(data, id, session_items).get("at_will", false)):  # v0.8.4.26: a Hat of Disguise casts with no end
		return []
	if charges_max(def_of(data["items"], session_items, id)) > 0:
		return spend_charge(c, data, session_items, id, rng)
	if not LiquidRules.blade_of(data, id).is_empty():  # its vial is left (v0.8.4.28.3)
		LiquidRules.empty_one(c, data, id)
		return []
	remove(c, id)
	return []


## Takes `qty` of a thing (all of it when < 0) from anybody's things: the hero's sheet or a bag, a fighter, a record (v0.8.4.15:
## the one road of «убрать N вещей»). When none is left it is off its slots and its weapon set and out of the attunement;
## the copies that set it apart go with it. How many.
static func remove(c: Dictionary, id: String, qty: int = 1) -> int:
	var inv: Dictionary = c.get("inventory", {})
	var have := int(inv.get(id, 0))
	var n := have if qty < 0 else mini(qty, have)
	if have - n > 0:
		inv[id] = have - n
	else:
		inv.erase(id)
		CharacterRules.sanitize_equipped(c)
	Thing.trim(c)
	return n


# --- what a worn thing lays (v0.8.4.26) ------------------------------------------------------------


## What a thing lays on its wearer while it works: its `wear` in the words of a spell's effect (swim_speed, climb_speed,
## fly_speed, see_invisible…), "walk" read as the wearer's walking speed.
static func wear_spec(c: Dictionary, data: Dictionary, d: Dictionary) -> Dictionary:
	var out := {}
	var spec: Dictionary = d.get("wear", {})
	for k: String in spec:
		var v: Variant = spec[k]
		if k == STATUS:  # any status while it works (v0.8.4.39): a condition, a spell's, a made one
			out.merge(status_fields(data, c, str(v)))
			continue
		out[k] = walk_of(c, data) if str(v) == "walk" else maxi(0, CharacterRules.mod(CharacterRules.ability(c, str(v)))) \
			if (data["rules"]["saves"] as Array).has(str(v)) else v  # an ability: its modifier (Second-Story Work's jump)
	return out


## The word of `wear` that lays a status (v0.8.4.39).
const STATUS := "status"


## What the status of a worn thing lays on `c`: an engine condition, `spell:<id>` — what the spell lays on its target,
## a made status (gen_st_…) with its numbers. {} — none, or `c` is immune to the condition (ConditionRules.impose's gate).
static func status_fields(data: Dictionary, c: Dictionary, status: String) -> Dictionary:
	var got := status_of(data, c, status)
	if got.has("reason"):
		return {}
	var f: Dictionary = got["fields"]
	if not str(f.get("condition", "")).is_empty() and CombatRules.immune_to(data, c, str(f["condition"])):
		return {}
	return f


## A status a thing may lay on its wearer: {fields, harm, points} or {reason}. The points of a boon by items.json
## wear_points.status: a condition's own, a spell's by its circle, a made one's parts; a harm — the curse's own points.
static func status_of(data: Dictionary, c: Dictionary, status: String) -> Dictionary:
	var row: Dictionary = data["items"]["wear_points"][STATUS]
	if status.begins_with("spell:"):
		var sp := status.trim_prefix("spell:")
		if not data["spells"].has(sp):
			return {"reason": "wear.status: заклинания %s нет в книге движка" % sp}
		var w := SpellEffects.worn(data, sp, c)
		if w.has("reason"):
			return w
		return {"fields": w["fields"], "harm": w["harm"], "points": int(row["by_circle"][clampi(int(data["spells"][sp].get("level", 0)), 0, 5)])}
	if status.begins_with(MakeRules.PREFIX):
		var def := MakeRules.def_of(data, status)
		if str(def.get("what", "")) != "status":
			return {"reason": "wear.status: %s — не статус мастера (make с what: status)" % status}
		return {"fields": ({"condition": status} as Dictionary).merged(def.get("fx", {})), "harm": bool(def.get("harm", false)),
			"points": int(def.get("points", 0)) + int(row["made_plus"])}
	var good: Dictionary = row["conditions"]
	if good.has(status):
		return {"fields": {"condition": status}, "harm": false, "points": int(good[status])}
	if (data["rules"]["make"]["act"]["lay_cost"] as Dictionary).has(status) or (data["rules"]["condition_effects"] as Dictionary).has(status):
		return {"fields": {"condition": status}, "harm": true, "points": 0}
	return {"reason": "wear.status — состояние движка (%s…), spell:<id> заклинания или статус мастера (new:<key> / gen_st_…)" % ", ".join(
		(data["rules"]["make"]["act"]["lay_cost"] as Dictionary).keys().slice(0, 6))}


## The walking speed of its race or its template.
static func walk_of(c: Dictionary, data: Dictionary) -> int:
	var race: Dictionary = data["races"]["races"].get(str(c.get("race", "")), {})
	return int(race.get("speed", data["monsters"].get(str(c.get("monster", "")), {}).get("speed", 30)))


## The things that work now lay their `wear` on anybody who has them: one status each with the source kind `worn`, read by
## the same rules as a spell's (Move, SightRules, WatchRules); a light lays its own only lit on the belt. Called by the sheet's
## refresh and the fighter's gear (Gear.follow).
static func wear(c: Dictionary, data: Dictionary, session_items: Dictionary) -> void:
	for e: Dictionary in ConditionRules.effects(c).duplicate():
		if str(e.get("source", {}).get("kind", "")) in [WORN, BORN]:
			ConditionRules.remove_effect(c, int(e["uid"]))
	var born := born_rows(c, data, data["monsters"].get(str(c.get("monster", "")), {}))
	for fid: String in born:  # a feature's or a trait's own (v0.8.4.26.1)
		var own := wear_spec(c, data, {"wear": born[fid]["row"]})
		own.merge({"condition": "", "ends": {}, "source": {"kind": BORN, "id": fid, "name": str(born[fid]["name"])}})
		ConditionRules.add_effect(c, own)
	_thing_spells(c, data, session_items)
	var lit := belt(c, data, session_items)
	for id: String in CharacterRules.working_ids(c, data, session_items):
		var d := def_of(data["items"], session_items, id)
		if not (d.get("wear") is Dictionary) or ((d.get("properties", []) as Array).has("light_source") and not (lit.has(id) and LiquidRules.fuelled(c, data, id))):
			continue
		var e := wear_spec(c, data, d)
		e.merge({"condition": "", "ends": {}, "source": {"kind": WORN, "id": real_id(id), "name": str(d.get("name", ""))}})
		ConditionRules.add_effect(c, e)


## Regeneration (v0.8.4.36): a thing with the property heals its holder — in a fight at the start of its turn, `f` its fighter.
static func regenerate(s: GameSession, data: Dictionary, f: Dictionary, lines: Array[String]) -> void:
	var me := Sheet.holder(s, f)
	if not Sheet.prop(s, data, f, "regeneration") or int(me.get("hp", 0)) <= 0 or int(me.get("hp", 0)) >= int(me.get("max_hp", 0)):
		return
	var got := Harm.mend(s, data, f, CombatRules.roll_dice(s.rng, str(data["rules"]["item_props"]["regeneration"]["dice"])))
	if got > 0:
		lines.append("%s: регенерация, +%d хитов" % [me.get("name", ""), got])


## Out of a fight: the hero's regeneration every `every` minutes that passed (a TimeRules hook).
static func regenerate_hero(s: GameSession, data: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var c := s.character
	var row: Dictionary = data["rules"]["item_props"].get("regeneration", {})
	var n := TimeRules.periods(c, "regen_at", TimeRules.abs_minute(s), int(row.get("every", 10)))
	if row.is_empty() or CombatRules.active(s) or not Sheet.prop(s, data, Sheet.HERO, "regeneration") or int(c.get("hp", 0)) <= 0:
		return lines
	var got := 0
	for i in mini(n, 60):
		got += CombatRules.roll_dice(s.rng, str(row["dice"]))
	got = Harm.mend(s, data, Sheet.HERO, got)
	if got > 0:
		lines.append("Регенерация: +%d хитов" % got)
	return lines


## The spells of the things that work now (v0.8.4.36): a row of the holder's stock each (Stock.table with `c`) — a thing's
## `spells` a long rest each, the spells kept in a thing's copy once; cast without a slot (spells.items), by the thing's
## numbers when its holder casts by no ability of its own (spells.item_numbers).
static func _thing_spells(c: Dictionary, data: Dictionary, session_items: Dictionary) -> void:
	var stock := {}
	var free: Array = []
	var nums := {}
	var add := func(rid: String, row: Dictionary, spell: String, circle: int, dc: int, attack: int) -> void:
		stock[rid] = row
		if not free.has(spell):
			free.append(spell)
		nums[spell] = {"dc": dc, "attack": attack, "ability": "int"}
	var seen := {}
	for id: String in CharacterRules.working_ids(c, data, session_items):
		if seen.has(id):
			continue
		seen[id] = true
		var d := def_of(data["items"], session_items, id)
		for r: Dictionary in d.get("spells", []):
			var sp := str(r["spell"])
			var lv := maxi(1, int(data["spells"].get(sp, {}).get("level", 1)))
			var n := scroll_numbers(data, lv)
			add.call("item:%s:%s" % [real_id(id), sp], {"spell": sp, "max": {"fixed": int(r.get("uses", 1))}, "recharge": "long", "circle": lv,
				"item": id, "name": "%s — %s" % [data["spells"].get(sp, {}).get("name", sp), d.get("name", id)], "combat_cost": "never"}, sp, lv, int(n[0]), int(n[1]))
		var kept := stored(c, id, d)
		for i in kept.size():
			var k: Dictionary = kept[i]
			var sp := str(k["spell"])
			add.call("store:%s:%d" % [id, i], {"spell": sp, "max": {"fixed": 1}, "recharge": "never", "circle": int(k["circle"]), "item": id, "store": i,
				"name": "%s — в вещи «%s»" % [data["spells"].get(sp, {}).get("name", sp), d.get("name", id)], "combat_cost": "never", "kept": kept}, sp, int(k["circle"]),
				int(k["dc"]), int(k["attack"]))
	if stock.is_empty():
		c.erase("item_stock")
		if c.get("spells") is Dictionary:
			(c["spells"] as Dictionary).erase("items")
			(c["spells"] as Dictionary).erase("item_numbers")
		return
	c["item_stock"] = stock
	if not (c.get("spells") is Dictionary):
		c["spells"] = {}
	c["spells"]["items"] = free
	c["spells"]["item_numbers"] = nums


## The spells kept in the first copy of a thing that keeps spells (a Ring of Spell Storing): [{spell, circle, dc, attack}];
## a copy not yet touched holds what the thing was made with.
static func stored(h: Dictionary, id: String, d: Dictionary) -> Array:
	if int(d.get("store", 0)) <= 0:
		return []
	var list := Thing.states(h, id)
	return (list[0] as Dictionary).get("stored", d.get("stored", [])) if not list.is_empty() and (list[0] as Dictionary).has("stored") else d.get("stored", [])


## A kept spell cast: it leaves its thing. True when `rid` was one (Stock.spend calls it).
static func unstore(c: Dictionary, rid: String) -> bool:
	if not rid.begins_with("store:"):
		return false
	var row: Dictionary = c.get("item_stock", {}).get(rid, {})
	if row.is_empty():
		return true
	var copy := Thing.nth(c, str(row["item"]), 0)
	var kept: Array = (copy.get("stored", row["kept"]) as Array).duplicate(true)  # the live list: another kept spell may be gone already
	for i in kept.size():
		if str(kept[i]["spell"]) == str(row["spell"]) and int(kept[i]["circle"]) == int(row["circle"]):
			kept.remove_at(i)
			break
	copy["stored"] = kept
	(c["item_stock"] as Dictionary).erase(rid)
	return true


## "" or why the hero cannot put `spell` into the thing `id` at `circle` now (a key or a line).
static func store_why(s: GameSession, data: Dictionary, id: String, spell: String, circle: int) -> String:
	var c := s.character
	var d := def_of(data["items"], s.items, id)
	var room := int(d.get("store", 0))
	if room <= 0 or Thing.count(c, id) <= 0:
		return "ITEM_STORE_NONE"
	if not SpellRules.ready(c).has(spell) or SpellRules.level_of(data, spell) < 1 or circle < SpellRules.level_of(data, spell):
		return "ITEM_STORE_SPELL"
	if SpellRules.slots_left(c, circle) <= 0:
		return "ITEM_STORE_SLOT"
	var full: int = stored(c, id, d).reduce(func(a: int, k: Dictionary) -> int: return a + int(k["circle"]), 0)
	if full + circle > room:
		return "ITEM_STORE_FULL"
	return ""


## The hero casts `spell` into the thing at `circle`: the slot spent, the spell kept with the hero's DC and attack. Lines.
static func store_spell(s: GameSession, data: Dictionary, id: String, spell: String, circle: int) -> Array[String]:
	var c := s.character
	var d := def_of(data["items"], s.items, id)
	var kept: Array = stored(c, id, d).duplicate(true)
	var n := ActionRules.numbers(s, data, spell)
	var ab := str(c.get("spell_ability", "int"))
	kept.append({"spell": spell, "circle": circle, "dc": int(n.get("dc", Sheet.dc(s, data, Sheet.HERO, ab))),
		"attack": int(n.get("attack", Sheet.prof(s, data, Sheet.HERO) + Sheet.ability_mod(s, data, Sheet.HERO, ab)))})
	Stock.spend(c, "slot_%d" % circle)
	Thing.nth(c, id, 0)["stored"] = kept
	CharacterRules.refresh(c, data, s.items)
	return ["%s: в вещи «%s» — %s (%d круг)" % [c.get("name", ""), d.get("name", id), data["spells"].get(spell, {}).get("name", spell), circle]]


## What the hero could put into a thing that keeps spells now: [{spell, circle, name}].
static func storable(s: GameSession, data: Dictionary, id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if int(def_of(data["items"], s.items, id).get("store", 0)) <= 0:
		return out
	for sp: Variant in SpellRules.ready(s.character):
		var lv := SpellRules.level_of(data, str(sp))
		if lv >= 1 and not SpellRules.is_free(s.character, str(sp)):
			var at := SpellRules.lowest_slot(s.character, data, str(sp))
			if at > 0 and store_why(s, data, id, str(sp), at).is_empty():
				out.append({"spell": str(sp), "circle": at, "name": str(data["spells"][str(sp)].get("name", sp))})
	return out


## What its features and traits lay for good by `rules.feature_wear`: {id: {row, name}} — its own features and race traits,
## and the traits of `m`, its monster template (a swarm shares a square, v0.8.4.27.1).
static func born_rows(c: Dictionary, data: Dictionary, m: Dictionary) -> Dictionary:
	var rows: Dictionary = data["rules"].get("feature_wear", {})
	var names := {}
	for t: Dictionary in m.get("traits", []):
		names[str(t["id"])] = str(t["name"])
	var out := {}
	for fid: Variant in (c.get("features", []) as Array) + (c.get("traits", []) as Array) + names.keys():
		var id := str(fid)
		if rows.has(id):
			out[id] = {"row": rows[id], "name": str(data["classes"]["features"].get(id, data["races"]["traits"].get(id, {})).get("name", names.get(id, id)))}
	return out


## Some feature or trait of `who` lays `key` for good — read off its template when it holds no statuses (a head of an
## encounter not yet in a fight).
static func born(data: Dictionary, who: Dictionary, key: String) -> bool:
	return not born_name(data, who, key).is_empty()


## The name of its feature or trait that lays `key` for good, "" when none (v0.8.4.27.5: Grappler, Rampage).
static func born_name(data: Dictionary, who: Dictionary, key: String) -> String:
	for e: Dictionary in born_effects(data, who):
		if e.has(key) and str(e.get("source", {}).get("kind", "")) == BORN:
			return str(e["source"].get("name", key))
	return ""


## What its features and traits lay, as statuses: those it holds, or — when it holds none of them yet (a head of an
## encounter at a meeting) — the rows of its template in their form (v0.8.4.27.4). Read as `ConditionRules.effects`.
static func born_effects(data: Dictionary, who: Dictionary) -> Array:
	var held := ConditionRules.effects(who)
	if held.any(func(e: Dictionary) -> bool: return str(e.get("source", {}).get("kind", "")) == BORN):
		return held
	var out: Array = held.duplicate()
	var rows := born_rows(who, data, Sheet.template(data, who))
	for fid: String in rows:
		out.append((rows[fid]["row"] as Dictionary).merged({"source": {"kind": BORN, "id": fid, "name": str(rows[fid]["name"])}}))
	return out


# --- what a found thing may be (v0.7.12) -----------------------------------------------------------


## "" when the master may hand this catalog item to a hero of `level` (not rarer than max_found_rarity at levels
## 1-5), otherwise the reason for the master.
static func rarity_ok(data: Dictionary, d: Dictionary, level: int) -> String:
	var order: Array = cfg(data)["rarity_order"]
	var r := str(d.get("rarity", "common"))
	if level <= 5 and order.find(r) > order.find(str(cfg(data)["max_found_rarity"])):
		return "«%s» — редкость %s: на 1–5 уровне мастер такое не выдаёт (только награды заданий мира)" % [d.get("name", ""), r]
	return ""


## The sum of «+N» properties of an item ("magic_plus1", "ac_plus2"…) for the given prefixes.
## The damage a weapon's own properties add to each hit (fire_damage — +1d6 fire, v0.7.12): [{dice, type}]. One list for the
## blow and for every line that tells the weapon's damage (v0.8.4.30).
static func elements(data: Dictionary, def: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p: Variant in def.get("properties", []):
		var dtype := str(p).trim_suffix("_damage")
		if str(p).ends_with("_damage") and data["misc"]["damage_types"].has(dtype):
			out.append({"dice": str(cfg(data)["element_dice"]), "type": dtype})
	return out


static func plus(def: Dictionary, prefixes: Array) -> int:
	var n := 0
	for p: Variant in def.get("properties", []):
		for pre: String in prefixes:
			if str(p).begins_with(pre) and str(p).trim_prefix(pre).is_valid_int():
				n += int(str(p).trim_prefix(pre))
	return n


static func display_name(items_data: Dictionary, session_items: Dictionary, id: String) -> String:
	return str(def_of(items_data, session_items, id).get("name", id))


## Catalog + session items matching a free-text query (Russian name or id), a base id and required properties.
static func find(items_data: Dictionary, session_items: Dictionary, query: String, base: String, properties: Array) -> Array[Dictionary]:
	var q := query.to_lower().strip_edges()
	var stems := word_stems(q)
	var out: Array[Dictionary] = []
	var loose: Array[Dictionary] = []  # a word of the query, not the whole of it: after the exact hits (v0.7.34.4)
	var pools: Array[Dictionary] = [items_data["catalog"], session_items]
	for pool: Dictionary in pools:
		for id: String in pool:
			var d: Dictionary = pool[id]
			var props: Array = d.get("properties", [])
			var name_l := str(d.get("name", "")).to_lower()
			var hit := q.is_empty() or q in name_l or q in id or q == str(d.get("item_type", ""))
			if not base.is_empty() and (id == base or str(d.get("base", "")) == base):
				hit = true
			var near := not hit and (stems.size() > 1 and stems.any(func(w: String) -> bool: return w in name_l)
				or q.length() >= 4 and q in str(d.get("description", "")).to_lower())
			if not (hit or near) or not properties.all(func(p: Variant) -> bool: return props.has(p)):
				continue
			(out if hit else loose).append({"item_id": id, "name": d.get("name", id), "item_type": d.get("item_type", ""),
				"rarity": d.get("rarity", "common"), "value_cp": int(d.get("value_cp", 0)), "properties": props,
				"source": "catalog" if pool == items_data["catalog"] else "session"})
	out.append_array(loose)
	return out


## The first five letters of each word of three letters or more: «кувшин глиняный» finds «Кувшин».
static func word_stems(q: String) -> Array[String]:
	var out: Array[String] = []
	for w: String in q.split(" ", false):
		if w.length() >= 3:
			out.append(w.left(5))
	return out


static func rarity_for_points(items_data: Dictionary, points: int) -> String:
	var r := Scale.row(items_data["rarity_by_points"], points)
	return str(r[1]) if not r.is_empty() else "common"


## The least level of the hero a rarity is open at (one threshold for a made thing and a built property).
static func rarity_level(items_data: Dictionary, rarity: String) -> int:
	return int(items_data["rarity_min_level"].get(rarity, 1))


## The numbers a scroll or a wand casts its spell with (v0.8.4.29.6: the cast and its window alike): a scroll by its circle
## (DMG), a wand its own; {dc, attack, ability, level}.
static func spell_numbers(c: Dictionary, data: Dictionary, session_items: Dictionary, item: String) -> Dictionary:
	var fx := consumable(data, item, session_items)
	var level := int(fx.get("level", 1))
	var nums := scroll_numbers(data, level)
	var ab := str(c.get("spell_ability", ""))
	return {"dc": int(fx.get("dc", nums[0])), "attack": int(fx.get("attack", nums[1])), "ability": "int" if ab.is_empty() else ab, "level": level}


## Deterministic id, so the same item made twice (or taken from the backend library) keeps one id.
static func generated_id(item: Dictionary) -> String:
	var props: Array = item.get("properties", []).duplicate()
	props.sort()
	return "gen_" + ("%s|%s|%s" % [item.get("name", ""), item.get("base", ""), ",".join(props)]).md5_text().left(10)


## {"ok": true, "def": normalized definition} or {"ok": false, "reason": text for the master}. What it lays while it works
## (`wear`, v0.8.4.28.7) and what it calls (`use.summon`) are priced as its properties are.
static func check_generated(data: Dictionary, item: Dictionary, level: int) -> Dictionary:
	var items_data: Dictionary = data["items"]
	var costs: Dictionary = items_data["properties"]
	var points := 0
	for p: Variant in item.get("properties", []):
		if not costs.has(p):
			return {"ok": false, "reason": "свойство %s движку неизвестно" % p}
		points += int(costs[p])
	var base := str(item.get("base", ""))
	if not base.is_empty() and not items_data["catalog"].has(base):
		return {"ok": false, "reason": "базового предмета %s нет в каталоге" % base}
	var use := _generated_use(data, item)  # v0.7.18: what the thing does when used
	if use.has("reason"):
		return {"ok": false, "reason": use["reason"]}
	points += int(use.get("points", 0))
	var wear := _generated_wear(items_data, item, data)  # v0.8.4.28.7: what it lays while it works
	if wear.has("reason"):
		return {"ok": false, "reason": wear["reason"]}
	points += int(wear.get("points", 0))
	var hit := _generated_hit(data, item)  # v0.8.4.36: what it lays on the one it strikes
	if hit.has("reason"):
		return {"ok": false, "reason": hit["reason"]}
	points += int(hit.get("points", 0))
	var spells := _generated_spells(data, item)  # v0.8.4.36: spells a long rest, spells kept in it
	if spells.has("reason"):
		return {"ok": false, "reason": spells["reason"]}
	points += int(spells.get("points", 0))
	var dealt: Array = elements(data, item).map(func(el: Dictionary) -> String: return str(el["type"]))
	var base_def: Dictionary = items_data["catalog"].get(base, {})
	dealt.append(str(base_def.get("weapon", {}).get("damage_type", "")))
	var told := MakeRules.told_damage(data, "%s. %s" % [item.get("name", ""), item.get("description", "")], dealt)
	if not told.is_empty():  # v0.8.4.30: the card must deal what the words promise
		return {"ok": false, "reason": told}
	if points == 0 and not str(item.get("rarity", "common")) in ["common", ""]:  # big test #16 (v0.7.22.2)
		return {"ok": false, "reason": ("магическая вещь (%s) без механики станет простой безделушкой — движок не опознает её и ничего ей не даст. " +
			"Дай ей свойства (`properties` из словаря движка) или `use` (заряды заклинания, зелье), либо возьми готовую магическую вещь " +
			"каталога через find_items (кольцо, плащ, амулет, очки…). Если это и правда простая вещь — rarity common") % item.get("rarity", "")}
	var rarity := rarity_for_points(items_data, points)
	if level < rarity_level(items_data, rarity):
		return {"ok": false, "reason": "предмет редкости %s недоступен на %d уровне" % [rarity, level]}
	var value := mini(int(item.get("value_cp", 0)), int(items_data["rarity_max_value_cp"][rarity]))
	var def := {
		"name": str(item.get("name", "")), "item_type": str(item.get("item_type", "gear")), "base": base,
		"rarity": rarity, "value_cp": value, "properties": item.get("properties", []),
		"description": str(item.get("description", "")), "generated": true,
	}
	if not str(item.get("text", "")).strip_edges().is_empty():  # what is written on it (a letter, a diary), v0.7.18
		def["text"] = str(item["text"]).strip_edges().left(1000)
	if not str(item.get("evidence", "")).is_empty():  # a letter or a ledger that shows an NPC's crime (v0.7.48, LetterRules)
		def["evidence"] = str(item["evidence"])
	if not (wear.get("wear", {}) as Dictionary).is_empty():
		def["wear"] = wear["wear"]
	if hit.has("hit"):
		def["hit"] = hit["hit"]
	for k: String in ["spells", "store", "stored"]:
		if spells.has(k) and not (spells[k] is Array and (spells[k] as Array).is_empty() and k != "stored"):
			def[k] = spells[k]
	if use.has("use"):
		def["use"] = use["use"]
		if use.has("charges"):
			def["charges"] = use["charges"]
		if use.has("look"):
			def["look"] = use["look"]
	if def["name"].is_empty():
		return {"ok": false, "reason": "у предмета нет названия"}
	return {"ok": true, "def": def}


## The `wear` of a generated thing (v0.8.4.28.7): the words of items.json `wear_points`, each a speed (feet or "walk")
## or a flag, with what the word brings along. {} — none; {reason}; or {wear, points}.
static func _generated_wear(items_data: Dictionary, item: Dictionary, data: Dictionary = {}) -> Dictionary:
	var w: Variant = item.get("wear")
	if w == null or not (w is Dictionary) or (w as Dictionary).is_empty():
		return {}
	var table: Dictionary = items_data["wear_points"]
	var words := table.keys().filter(func(k: Variant) -> bool: return not str(k).begins_with("_"))
	var out := {"wear": {}, "points": 0}
	for k: String in w:
		if not table.has(k) or k.begins_with("_"):
			return {"reason": "wear: %s движок не читает; есть: %s" % [k, ", ".join(words)]}
		var row: Dictionary = table[k]
		var v: Variant = w[k]
		if str(row["value"]) == STATUS:  # v0.8.4.39: any status while it works; a harm only on a cursed thing
			var st := status_of(data, {}, str(v))
			if st.has("reason"):
				return st
			if bool(st["harm"]) and not (item.get("properties", []) as Array).has("cursed"):
				return {"reason": "wear.status %s вредит носящему — такое держит только проклятая вещь: добавь properties \"cursed\" (её не снять, пока проклятие не снимут)" % v}
			out["wear"][k] = str(v)
			out["points"] = int(out["points"]) + (int(row["cursed_points"]) if bool(st["harm"]) else int(st["points"]))
			continue
		if str(row["value"]) == "aura":  # v0.8.4.35: an aura of the field around the wearer
			var aura := _aura(data, row, v)
			if aura.has("reason"):
				return aura
			out["wear"][k] = aura["aura"]
			out["points"] = int(out["points"]) + int(aura["points"])
			continue
		if str(row["value"]) == "speed":
			if str(v) == "walk":
				v = "walk"
			elif (v is int or v is float) and int(v) >= 5 and int(v) <= 60:
				v = int(v)
			else:
				return {"reason": "wear.%s — скорость в футах 5–60 или \"walk\" (скорость ходьбы)" % k}
		else:
			v = true
		out["wear"][k] = v
		out["wear"].merge(row.get("with", {}), true)
		out["points"] = int(out["points"]) + int(row["points"])
	return out


## The aura a made thing lays around its wearer (v0.8.4.35), in the form of a monster trait's (rules.feature_wear
## `aura`): {aura, points} or {reason}. Its points: the word's own, each 10 ft begun, the status laid, sparing friends.
static func _aura(data: Dictionary, row: Dictionary, v: Variant) -> Dictionary:
	if not (v is Dictionary) or data.is_empty():
		return {"reason": "wear.aura — объект: ft, cond, save, rounds?, spares_friends?"}
	var a: Dictionary = v
	var ft := int(a.get("ft", 0)) if a.get("ft") != null else 0
	if ft < int(row["ft"][0]) or ft > int(row["ft"][1]) or ft % 5 != 0:
		return {"reason": "wear.aura.ft — от %d до %d футов, кратно 5" % [int(row["ft"][0]), int(row["ft"][1])]}
	var spares: bool = a.get("spares_friends") == true
	var laid := _laid(data, a, "wear.aura", int(row["points"]) + ceili(ft / 10.0) * int(row["per_10ft"]) + (int(row["spares_points"]) if spares else 0))
	if laid.has("reason"):
		return laid
	var aura := {"ft": ft, "on": ["start"], "save": laid["save"], "dc": laid["dc"], "tag": "", "cond": laid["cond"],
		"for": {"rounds": laid["rounds"], "save": laid["save"], "dc": laid["dc"], "tag": ""}}
	if spares:
		aura["spares_friends"] = true
	return {"aura": aura, "points": laid["points"]}


## A status a made thing lays on another (items.json laid): {cond, save, rounds, dc, points} or {reason}; `base` — the
## points of the rest of it, the DC is by the whole.
static func _laid(data: Dictionary, a: Dictionary, field: String, base: int) -> Dictionary:
	var row: Dictionary = data["items"]["laid"]
	var cond := str(a.get("cond", "")) if a.get("cond") != null else ""
	var costs: Dictionary = data["rules"]["make"]["act"]["lay_cost"]
	if not costs.has(cond):
		return {"reason": "%s.cond — состояние из %s" % [field, ", ".join(costs.keys())]}
	var save := str(a.get("save", "")) if a.get("save") != null else ""
	if not (data["rules"]["saves"] as Array).has(save):
		return {"reason": "%s.save — характеристика спасброска: %s" % [field, ", ".join(data["rules"]["saves"])]}
	var rounds := int(a.get("rounds", 1)) if a.get("rounds") != null else 1
	if rounds < int(row["rounds"][0]) or rounds > int(row["rounds"][1]):
		return {"reason": "%s.rounds — от %d до %d" % [field, int(row["rounds"][0]), int(row["rounds"][1])]}
	var points := base + int(costs[cond])
	return {"cond": cond, "save": save, "rounds": rounds, "dc": int(Scale.up_to(row["dc"], points).get("dc", 17)), "points": points}


## The spells of a made thing (v0.8.4.36, items.json spells_points): {spells, store, stored, points} or {reason}; {} — none.
static func _generated_spells(data: Dictionary, item: Dictionary) -> Dictionary:
	var row: Dictionary = data["items"]["spells_points"]
	var list: Variant = item.get("spells")
	var room := int(item.get("store", 0)) if item.get("store") != null else 0
	if (list == null or not (list is Array) or (list as Array).is_empty()) and room <= 0:
		return {}
	var out := {"spells": [], "points": 0}
	for r: Variant in (list if list is Array else []):
		var sp := str((r as Dictionary).get("spell", ""))
		if not data["spells"].has(sp):
			return {"reason": "spells: заклинания %s нет в книге движка" % sp}
		var lv := int(data["spells"][sp].get("level", 0))
		if lv > int(row["circle_max"]):
			return {"reason": "spells: не выше %d круга" % int(row["circle_max"])}
		var uses := int(r.get("uses", 1)) if r.get("uses") != null else 1
		if uses < int(row["uses"][0]) or uses > int(row["uses"][1]):
			return {"reason": "spells.uses — от %d до %d за долгий отдых" % [int(row["uses"][0]), int(row["uses"][1])]}
		out["spells"].append({"spell": sp, "uses": uses})
		out["points"] = int(out["points"]) + int(row["by_circle"][lv]) + (uses - 1) / int(row["per_uses"])
	if room > 0:
		if room > int(row["store_max"]):
			return {"reason": "store — не больше %d кругов" % int(row["store_max"])}
		out["store"] = room
		out["points"] = int(out["points"]) + room * int(row["store_per_circle"])
		var kept: Array = []
		var full := 0
		for r: Variant in (item.get("stored", []) if item.get("stored") is Array else []):
			var sp := str((r as Dictionary).get("spell", ""))
			var lv := maxi(1, int(data["spells"].get(sp, {}).get("level", 0)))
			if not data["spells"].has(sp) or int(data["spells"][sp].get("level", 0)) < 1:
				return {"reason": "stored: заклинания %s (1 круга и выше) нет в книге движка" % sp}
			full += lv
			var n := scroll_numbers(data, lv)
			kept.append({"spell": sp, "circle": lv, "dc": int(n[0]), "attack": int(n[1])})
		if full > room:
			return {"reason": "stored: вложено %d кругов, а вещь держит %d" % [full, room]}
		out["stored"] = kept
	return out


## A made weapon's `hit` (v0.8.4.36): {hit, points} or {reason}; {} — none.
static func _generated_hit(data: Dictionary, item: Dictionary) -> Dictionary:
	var h: Variant = item.get("hit")
	if h == null or not (h is Dictionary) or (h as Dictionary).is_empty():
		return {}
	if str(item.get("item_type", "")) != "weapon" and not data["items"]["catalog"].get(str(item.get("base", "")), {}).has("weapon"):
		return {"reason": "hit — только у оружия (item_type weapon или base — оружие каталога)"}
	var laid := _laid(data, h, "hit", int(data["items"]["hit_points"]["points"]))
	if laid.has("reason"):
		return laid
	return {"hit": {"cond": laid["cond"], "save": laid["save"], "dc": laid["dc"], "rounds": laid["rounds"]}, "points": laid["points"]}


## What a weapon's `hit` lays on the one it strikes, as a monster attack's effect (MonsterRules.apply_effect).
static func hit_effect(def: Dictionary) -> Dictionary:
	var h: Dictionary = def.get("hit", {})
	if h.is_empty():
		return {}
	var rounds := int(h.get("rounds", 1))
	return {"condition": str(h["cond"]), "save": {"ability": str(h["save"]), "dc": int(h["dc"])}, "duration": "round" if rounds <= 1 else "minute",
		"repeat": rounds > 1}


## What a generated `use.summon` calls (v0.8.4.28.7): a row in the shape of rules.allies.summons — an SRD `monster` or a
## `pick` of them, `count`, `minutes` — and its points: base + the CR of all it calls, rounded up (the strongest of a pick).
## {reason} or {row, points}.
static func _summon_row(data: Dictionary, u: Dictionary, once: bool) -> Dictionary:
	var cost: Dictionary = data["items"]["use_points"]["summon"]
	var pick: Array = (u.get("pick", []) if u.get("pick") is Array else []).map(func(x: Variant) -> String: return str(x))
	var monster := str(u.get("monster", "")) if u.get("monster") != null else ""
	if pick.is_empty() and monster.is_empty():
		return {"reason": "use.summon: monster (id шаблона SRD) или pick — из кого выбрать"}
	var cr := 0.0
	for m: String in (pick if not pick.is_empty() else [monster]):
		if not data["monsters"].has(m):  # a monster out of the game (rules.off) is not loaded either
			return {"reason": "use.summon: существа %s нет в бестиарии движка (find_monster)" % m}
		cr = maxf(cr, float(data["monsters"][m].get("cr", 0)))
	var count := clampi(int(u.get("count", 1)) if u.get("count") != null else 1, 1, int(cost["count_max"]))
	var minutes := clampi(int(u.get("minutes", 60)) if u.get("minutes") != null else 60, 1, int(cost["minutes_max"]))
	var row := {"count": count, "minutes": minutes}
	if pick.is_empty():
		row["monster"] = monster
	else:
		row["pick"] = pick
	return {"row": row, "points": maxi(0, int(cost["base"]) + ceili(cr * count) + (int(cost["once"]) if once else 0))}


## The `use` of a generated thing (v0.7.18, by the catalog's own shapes): a spell of the engine's book with charges
## (a wand) or once (a scroll), healing, a resistance or an advantage once (a potion), creatures it calls (v0.8.4.28.7,
## with charges or once). {} — none; {reason}; or {use, charges?, look?, points}. Points by items.json `use_points`.
static func _generated_use(data: Dictionary, item: Dictionary) -> Dictionary:
	var items_data: Dictionary = data["items"]
	var spells: Dictionary = data.get("spells", {})
	var u: Variant = item.get("use")
	if u == null or not (u is Dictionary) or (u as Dictionary).is_empty():
		return {}
	var cost: Dictionary = items_data["use_points"]
	var charges := int(u.get("charges", 0)) if u.get("charges") != null else 0
	var once := charges <= 0
	var out := {"points": 0}
	if u.get("spell") != null and not str(u["spell"]).is_empty():
		var sp := str(u["spell"])
		var spell: Dictionary = spells.get(sp, {})
		if spell.is_empty():
			return {"reason": "заклинания %s нет в книге движка" % sp}
		var lvl := maxi(int(spell.get("level", 0)), int(u.get("level", 0)) if u.get("level") != null else 0)
		if lvl > 3:
			return {"reason": "заклинание в предмете — не выше 3 круга"}
		out["use"] = {"spell": sp, "level": lvl}
		if once:
			out["use"]["scroll"] = true
			out["look"] = "свиток"
			out["points"] = int(cost["scroll"][lvl])
		else:
			out["look"] = "волшебная палочка"
			out["points"] = int(cost["wand"][lvl])
	elif u.get("heal") != null and not str(u["heal"]).is_empty():
		var h: Dictionary = cost["heal"].get(str(u["heal"]), {})
		if h.is_empty():
			return {"reason": "лечение: light, medium или strong"}
		out["use"] = {"heal": (h["dice"] as Array).map(func(x: Variant) -> int: return int(x))}
		out["points"] = int(h["points"])
		out["look"] = "зелье"
	elif u.get("resist") != null and not str(u["resist"]).is_empty():
		out["use"] = {"resist": str(u["resist"]), "duration": "hour"}
		out["points"] = int(cost["resist"])
		out["look"] = "зелье"
	elif u.get("check_adv") != null and not str(u["check_adv"]).is_empty():
		out["use"] = {"check_adv": str(u["check_adv"]), "duration": "hour"}
		out["points"] = int(cost["check_adv"])
		out["look"] = "зелье"
	elif u.get("summon") is Dictionary:
		var sm := _summon_row(data, u["summon"], once)
		if sm.has("reason"):
			return sm
		out["use"] = {"summon": sm["row"]}
		out["points"] = int(sm["points"])
	else:
		return {"reason": "use: spell, heal, resist, check_adv или summon"}
	if not once:
		if not out["use"].has("spell") and not out["use"].has("summon"):
			return {"reason": "заряды — только у предмета с заклинанием (жезл) или с призывом; зелья и свитки одноразовые"}
		var most := int(cost["charges_max"])
		if charges > most:
			return {"reason": "зарядов не больше %d" % most}
		out["charges"] = {"max": charges, "regain": "1d%d" % maxi(1, charges - 1), "crumble": true}
		if str(item.get("item_type", "")) not in ["wondrous", "weapon", "gear"]:
			return {"reason": "предмет с зарядами — wondrous (жезл, посох), оружие или снаряжение"}
	elif str(item.get("item_type", "")) != "consumable":
		return {"reason": "одноразовый предмет (зелье, свиток) — item_type consumable"}
	return out


## What using an item does (rules.json `consumables`): {"heal": [n, sides, bonus], "remove": [conditions]}; {} = not usable.
## `session_items` — the generated things of the game: a thing the master made has its own `use` too (v0.7.18).
## A thrown thing that lands on a square (its `throw`): a liquid with a puddle (oil, fire, water), caltrops strewn (v0.8.4.27).
static func spills(throw: Dictionary) -> bool:
	return bool(throw.get("spills", false)) or throw.has("strew")


static func consumable(data: Dictionary, id: String, session_items: Dictionary = {}) -> Dictionary:
	id = real_id(id)
	if id.begins_with("_"):
		return {}
	var all: Dictionary = data["rules"].get("consumables", {})
	if all.has(id):
		return all[id]
	var flask := LiquidRules.throw_of(data, id)  # a flask is thrown by its liquid (v0.8.4.28.2)
	if not flask.is_empty():
		return {"throw": flask}
	var blade := LiquidRules.blade_of(data, id)  # a vial of poison coats a blade by its liquid (v0.8.4.28.3)
	if not blade.is_empty():
		return blade
	if session_items.has(id):
		return session_items[id].get("use", {})
	return data["items"]["catalog"].get(id, {}).get("use", {})  # potions, scrolls, wands, the pearl (v0.7.12)


## A potion (v0.7.22.3: drunk as a bonus action in a fight): a catalog potion or a made one with a potion's `use`.
static func is_potion(data: Dictionary, session_items: Dictionary, id: String) -> bool:
	var real := real_id(id)
	var d := def_of(data["items"], session_items, real)
	if real.contains("potion") or str(d.get("look", "")) == "зелье":
		return true
	var use: Dictionary = d.get("use", {}) if d.get("use") is Dictionary else {}
	return use.has("heal") or use.has("resist") or use.has("check_adv")


## "" when the character can use the item now, otherwise the reason (for the master).
static func can_use(c: Dictionary, data: Dictionary, session_items: Dictionary, id: String, pending: int = 0) -> String:
	if int(c.get("inventory", {}).get(id, 0)) - pending <= 0:
		return "у персонажа нет %s" % display_name(data["items"], session_items, id)
	var fx := consumable(data, id, session_items)
	if fx.is_empty():
		return "%s нельзя использовать так — это не расходник с действием движка" % display_name(data["items"], session_items, id)
	var d := def_of(data["items"], session_items, id)
	if not fx.has("meal") and not at_hand(c, data, session_items).has(id):  # only the belt's and the worn things are at hand (v0.8.4.24)
		if not CharacterRules.wear_slot(d, data).is_empty():
			return "%s не надета: сначала наденьте" % display_name(data["items"], session_items, id)
		return "%s не на поясе: сначала положите на пояс под куклой" % display_name(data["items"], session_items, id)
	if not active(c, d, id):
		return "%s не работает без настройки" % d.get("name", id)
	if charges_max(d) > 0 and charges_left(c, d, id) <= 0:
		return "у %s не осталось зарядов — они вернутся на рассвете" % d.get("name", id)
	if fx.has("recover_slot") and not range(1, 6).any(func(n: int) -> bool: return Stock.spent(c, "slot_%d" % n) > 0):
		return "все ячейки заклинаний и так целы"
	return ""


## Uses one item (can_use first): removes it, heals, lifts conditions; with the session (v0.7.8) it also leaves its
## boon for a while (antitoxin — advantage on saves against poison for an hour). Returns the chat lines.
static func use(c: Dictionary, data: Dictionary, session_items: Dictionary, id: String, rng: RandomNumberGenerator, s: GameSession = null,
		who: Dictionary = Sheet.HERO) -> Array[String]:
	var fx := consumable(data, id, session_items)
	var d := def_of(data["items"], session_items, real_id(id))
	var lines: Array[String] = ["Использовано: %s" % d.get("name", id)]
	lines.append_array(consume(c, data, session_items, id, rng))
	if s != null and int(fx.get("minutes", 0)) > 0:  # work of a while: a disguise (v0.8.4.26.4)
		lines.append_array(TimeRules.advance(s, data, int(fx["minutes"])))
	if fx.has("throw"):  # out of a fight: thrown at a thing, the master narrates (v0.7.12)
		lines[0] = "Брошено: %s" % d.get("name", id)
		return lines
	if fx.has("spell"):
		var own := fx
		if s != null and fx.has("check"):  # a kit lays the spell's effect, its DC by the user's check with the kit (a disguise, v0.8.4.26.4)
			var r := Roll.check(s, data, who, {"what": str(d.get("name", id)), "skill": str(fx["check"].get("skill", "deception")), "tool": real_id(id)})
			own = fx.merged({"dc": int(r["total"])}, true)
		lines.append_array(_spell_use(c, data, session_items, own, rng, s, who))
		if own.has("dc") and not Guise.of(Sheet.holder(s, who)).is_empty():
			Guise.of(Sheet.holder(s, who))["dc"] = int(own["dc"])
		return lines
	if s != null and fx.has("summon"):  # v0.8.4.26: a Bag of Tricks, the Pipes of the Sewers — a row of rules.allies.summons
		lines.append_array(AllyRules.summon_by(s, data, who, summon_key(id, fx)))
		return lines
	if fx.has("recover_slot"):
		for lv in range(mini(int(fx["recover_slot"]), 5), 0, -1):
			if Stock.spent(c, "slot_%d" % lv) > 0:
				Stock.give(c, "slot_%d" % lv)
				lines.append("ячейка %d круга восстановлена" % lv)
				break
		return lines
	if s != null and fx.has("poison"):  # a Potion of Poison drunk for a healing one
		var p: Dictionary = fx["poison"]
		var dmg := CombatRules.roll_dice(rng, str(p["dice"]))
		var r := Sheet.save(s, data, who, str(p["save"]), int(p["dc"]), "poison")
		if bool(r["ok"]):
			dmg /= 2
		if not bool(r["ok"]):
			lines.append_array(ConditionRules.impose(s, data, {"condition": "poisoned", "ends": ConditionRules.ends_for(s, data, "hour"),
				"source": {"kind": "item", "id": real_id(id), "name": str(d.get("name", ""))}}, who))
		Harm.typed(s, data, who, dmg, "poison", lines, "яд! −{hp} HP ({words}), спасбросок " + str(r["text"]))
		return lines
	if s != null and fx.has("meal"):  # a dish (v0.7.25), of whoever eats it (v0.8.4.15)
		lines.append_array(FoodRules.eat_one(s, data, id, who))
		return lines
	if s != null and fx.has("invisible_minutes"):
		var minutes := CombatRules.roll_dice(rng, str(fx["invisible_minutes"]))
		ConditionRules.add_effect(Sheet.holder(s, who), {"condition": "invisible", "ends": {"at": ConditionRules.now(s) + minutes * ConditionRules.ROUNDS_PER_MINUTE},
			"source": {"kind": "item", "id": real_id(id), "name": str(d.get("name", ""))}})
		lines.append("невидимость на %d мин" % minutes)
		return lines
	if fx.has("heal"):
		var amount := CombatRules.roll_dice(rng, CombatRules.dice_of(fx["heal"], int(c.get("level", 1))))
		lines.append("+%d HP" % (Harm.mend(s, data, who, amount) if s != null else Harm.heal(data, c, amount)))
	if s != null and (fx.has("cure") or ConditionRules.BOONS.any(func(k: String) -> bool: return fx.has(k))):
		lines.append_array(ConditionRules.cure(s, data, fx, {"kind": "item", "id": real_id(id), "name": str(d.get("name", ""))}, who))
		return lines
	for cond: Variant in fx.get("remove", []):
		if ConditionRules.has(c, str(cond)):
			ConditionRules.remove(c, str(cond))
			lines.append("снято: %s" % str(data["rules"]["conditions"].get(str(cond), cond)).get_slice(":", 0))
	return lines


## A scroll read or a wand used out of a fight: a scroll of the hero's own class within their power needs no check,
## otherwise Arcana DC 10 + the circle (BG3: anyone may try). The hero's goes the road of the sheet's spell with no slot
## (SpellRules.cast, v0.8.4.26): healing, Identify, a spell on oneself and the world's spells land; the rest is the master's
## to narrate. Lines.
static func _spell_use(c: Dictionary, data: Dictionary, session_items: Dictionary, fx: Dictionary, rng: RandomNumberGenerator, s: GameSession,
		who: Dictionary = Sheet.HERO) -> Array[String]:
	var sp_id := str(fx["spell"])
	var sp: Dictionary = data["spells"].get(sp_id, {})
	var lines: Array[String] = []
	if bool(fx.get("scroll", false)):
		var read := read_scroll(s, data, sp_id, int(fx.get("level", 1)), who)  # its reader's Arcana, not the hero's
		lines.append(str(read["line"]))
		if not bool(read["ok"]):
			return lines
	var level := int(fx.get("level", 1))
	var landed: Array[String] = []
	if s != null and Sheet.is_hero(who):  # v0.8.4.26: one road with the sheet's spell — Detect Magic finds, Disguise Self changes the look
		landed.assign(SpellRules.cast(c, data, sp_id, level, s, true, true).slice(1))
	elif sp_id == "identify":
		landed = identify(c, data, session_items)
	else:
		landed = SpellRules.heal_self(c, data, sp_id, level, rng, s)
	if sp_id == "identify" and landed.is_empty():
		landed.append("неопознанных вещей нет")
	if sp_id != "identify" and not sp.has("heal_at_slot"):
		lines.append("%s (Сл %d)" % [sp.get("name", sp_id), int(fx.get("dc", scroll_numbers(data, level)[0]))])
	lines.append_array(landed)
	return lines


## DC and attack bonus of a scroll's spell by the circle (DMG).
static func scroll_numbers(data: Dictionary, level: int) -> Array:
	return cfg(data)["scrolls"].get(str(clampi(level, 0, 3)), [13, 5])


## Reading a scroll: {"ok", "line"}. A spell of the reader's class list and within the slots it has — no check;
## otherwise Arcana DC 10 + circle, a failure wastes the scroll. Anybody's (v0.8.4.10).
static func read_scroll(s: GameSession, data: Dictionary, spell_id: String, level: int, who: Dictionary = Sheet.HERO) -> Dictionary:
	var c := Sheet.holder(s, who)
	var sp: Dictionary = data["spells"].get(spell_id, {})
	var name := str(sp.get("name", spell_id))
	var own := (sp.get("classes", []) as Array).has(str(c.get("class", ""))) and (level == 0 or int(c.get("slots_max", [0, 0, 0, 0, 0])[maxi(0, level - 1)]) > 0)
	if own:
		return {"ok": true, "line": "свиток прочитан: %s" % name}
	var dc := 10 + level
	var r := Roll.check(s, data, who, {"what": "Свиток", "skill": "arcana", "dc": dc})
	var ok := bool(r["ok"])
	return {"ok": ok, "line": "Магия %d + %d против Сл %d: %s" % [int(r["nat"]), int(r["total"]) - int(r["nat"]), dc,
		("свиток прочитан: " + name) if ok else "слова не даются, свиток рассыпается впустую"]}
