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
	var built: Dictionary = items_data.get("built", {})
	if not built.is_empty():  # a property of parts (v0.7.65) adds the engine's own tokens
		var all: Array = (d.get("properties", []) as Array).duplicate()
		for p: Variant in d.get("properties", []):
			if built.has(p):
				all.append_array(built[p]["tokens"])
				d["built"] = (d.get("built", []) as Array) + [str(built[p]["name"])]
		d["properties"] = all
	var props: Array = d.get("properties", [])
	if (props.has("mithral") or props.has("masterwork")) and d.has("armor"):  # no Strength need, no stealth trouble
		var a: Dictionary = (d["armor"] as Dictionary).duplicate()
		a["str_min"] = 0
		a["stealth_disadvantage"] = false
		d["armor"] = a
	return d


## «Плащ, свойства неизвестны» — what an unidentified thing is called.
static func unknown_name(items_data: Dictionary, d: Dictionary) -> String:
	var look := str(d.get("look", ""))
	if look.is_empty():
		look = str(def_of(items_data, {}, str(d.get("base", ""))).get("name", "вещь")) if not str(d.get("base", "")).is_empty() else "вещь"
	return look.left(1).to_upper() + look.substr(1) + str(items_data.get("unknown_suffix", ", свойства неизвестны"))


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
	var inv: Dictionary = c["inventory"]
	inv[key] = int(inv.get(key, 0)) + qty
	return key


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


## A thing for the belt: one used by an act — a potion, a scroll, a wand, a flask — or a light. Food is eaten from the pack; a
## worn thing with a use (a hat, a circlet) is used where it is worn (`at_hand`, v0.8.4.26).
static func belt_fits(data: Dictionary, session_items: Dictionary, id: String) -> bool:
	var d := def_of(data["items"], session_items, real_id(id))
	if not CharacterRules.wear_slot(d, data).is_empty():
		return false
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
	for id: String in inv:
		if out.size() < size and int(inv[id]) > 0 and belt_fits(data, session_items, id):
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


static func needs_attunement(d: Dictionary) -> bool:
	return bool(d.get("attunement", false)) or ((d.get("properties", []) as Array).has("cursed") and str(d.get("item_type", "")) == "wondrous")


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


## A cursed thing the hero wears, wields or is attuned to: it does not come off (v0.7.12).
static func held_by_curse(c: Dictionary, data: Dictionary, session_items: Dictionary, id: String) -> bool:
	if id.is_empty() or not cursed(def_of(data["items"], session_items, id)):
		return false
	return attuned(c).has(id) or CharacterRules.held_copies(c, id) > 0


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
		out[k] = walk_of(c, data) if str(v) == "walk" else maxi(0, CharacterRules.mod(int(c.get("abilities", {}).get(str(v), 10)))) \
			if (data["rules"]["saves"] as Array).has(str(v)) else v  # an ability: its modifier (Second-Story Work's jump)
	return out


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
	var lit := belt(c, data, session_items)
	for id: String in CharacterRules.working_ids(c, data, session_items):
		var d := def_of(data["items"], session_items, id)
		if not (d.get("wear") is Dictionary) or ((d.get("properties", []) as Array).has("light_source") and not lit.has(id)):
			continue
		var e := wear_spec(c, data, d)
		e.merge({"condition": "", "ends": {}, "source": {"kind": WORN, "id": real_id(id), "name": str(d.get("name", ""))}})
		ConditionRules.add_effect(c, e)


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
	return born_effects(data, who).any(func(e: Dictionary) -> bool: return e.has(key) and str(e.get("source", {}).get("kind", "")) == BORN)


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
	var rarity := "common"
	for step: Array in items_data["rarity_by_points"]:
		if points >= int(step[0]):
			rarity = str(step[1])
	return rarity


## Deterministic id, so the same item made twice (or taken from the backend library) keeps one id.
static func generated_id(item: Dictionary) -> String:
	var props: Array = item.get("properties", []).duplicate()
	props.sort()
	return "gen_" + ("%s|%s|%s" % [item.get("name", ""), item.get("base", ""), ",".join(props)]).md5_text().left(10)


## {"ok": true, "def": normalized definition} or {"ok": false, "reason": text for the master}.
static func check_generated(items_data: Dictionary, item: Dictionary, level: int, spells: Dictionary = {}) -> Dictionary:
	var costs: Dictionary = items_data["properties"]
	var points := 0
	for p: Variant in item.get("properties", []):
		if not costs.has(p):
			return {"ok": false, "reason": "свойство %s движку неизвестно" % p}
		points += int(costs[p])
	var base := str(item.get("base", ""))
	if not base.is_empty() and not items_data["catalog"].has(base):
		return {"ok": false, "reason": "базового предмета %s нет в каталоге" % base}
	var use := _generated_use(items_data, item, spells)  # v0.7.18: what the thing does when used
	if use.has("reason"):
		return {"ok": false, "reason": use["reason"]}
	points += int(use.get("points", 0))
	if points == 0 and not str(item.get("rarity", "common")) in ["common", ""]:  # big test #16 (v0.7.22.2)
		return {"ok": false, "reason": ("магическая вещь (%s) без механики станет простой безделушкой — движок не опознает её и ничего ей не даст. " +
			"Дай ей свойства (`properties` из словаря движка) или `use` (заряды заклинания, зелье), либо возьми готовую магическую вещь " +
			"каталога через find_items (кольцо, плащ, амулет, очки…). Если это и правда простая вещь — rarity common") % item.get("rarity", "")}
	var rarity := rarity_for_points(items_data, points)
	if level < int(items_data["rarity_min_level"][rarity]):
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
	if use.has("use"):
		def["use"] = use["use"]
		if use.has("charges"):
			def["charges"] = use["charges"]
		if use.has("look"):
			def["look"] = use["look"]
	if def["name"].is_empty():
		return {"ok": false, "reason": "у предмета нет названия"}
	return {"ok": true, "def": def}


## The `use` of a generated thing (v0.7.18, by the catalog's own shapes): a spell of the engine's book with charges
## (a wand) or once (a scroll), healing, a resistance or an advantage once (a potion). {} — none; {reason}; or
## {use, charges?, look?, points}. Points by items.json `use_points`.
static func _generated_use(items_data: Dictionary, item: Dictionary, spells: Dictionary) -> Dictionary:
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
	else:
		return {"reason": "use: spell, heal, resist или check_adv"}
	if not once:
		if not out["use"].has("spell"):
			return {"reason": "заряды — только у предмета с заклинанием (жезл); зелья и свитки одноразовые"}
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
## A thrown thing that lands on a square (its `throw`): oil, fire, caltrops strewn (v0.8.4.27).
static func spills(throw: Dictionary) -> bool:
	return throw.has("oiled") or throw.has("burning") or throw.has("strew")


static func consumable(data: Dictionary, id: String, session_items: Dictionary = {}) -> Dictionary:
	id = real_id(id)
	if id.begins_with("_"):
		return {}
	var all: Dictionary = data["rules"].get("consumables", {})
	if all.has(id):
		return all[id]
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
		lines.append_array(AllyRules.summon_by(s, data, who, str(fx["summon"])))
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
		ConditionRules.add_effect(c, {"condition": "invisible", "ends": {"at": ConditionRules.now(s) + minutes * 10},
			"source": {"kind": "item", "id": real_id(id), "name": str(d.get("name", ""))}})
		lines.append("невидимость на %d мин" % minutes)
		return lines
	if fx.has("heal"):
		var h: Array = fx["heal"]
		var amount := int(h[2])
		for i in int(h[0]):
			amount += rng.randi_range(1, int(h[1]))
		lines.append("+%d HP" % Harm.heal(data, c, amount))
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
		landed = SpellRules.heal_self(c, data, sp_id, level, rng)
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
