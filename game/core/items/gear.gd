class_name Gear
extends RefCounted
## What a character has (v0.8.4.10, ADR-0016): `inventory` {item: qty}, `gold_cp`, `equipped` {slot: item} and `copies` — the form
## of the hero's sheet on anybody, so ItemRules and the acts need not ask whose they are. A person keeps them on its record,
## filled the first time anybody looks (`of`): its template's gear and `rules.creatures.kit`, what the pack gives it, a purse
## by `rules.theft.pockets`. One without a name has its template's gear and kit; the coins of a band are its encounter's
## treasure. In a fight they lie on the fighter, as its statuses do (`arm`), and go back to the record at its end (`back`).
## A trader's purse is this `gold_cp`: one till for the trade, the pockets and the stakes.

const KEYS: Array[String] = ["inventory", "gold_cp", "equipped", "copies"]


## The holder of what `id` has: the hero's sheet, the fighter in a fight, the record otherwise. For writing.
static func of(s: GameSession, data: Dictionary, id: String) -> Dictionary:
	if id == Being.HERO:
		return s.character
	var b := Being.of(s, id)
	if (b.get("fight", {}) as Dictionary).has("inventory"):
		return b["fight"]
	if not b.has("inventory"):
		_fill(s, data, id, b)
	_rearm(s, data, b)
	return b


## A person's things the first time: the purse first, what the pack says it carries, a few small things, its template's gear.
static func _fill(s: GameSession, data: Dictionary, id: String, b: Dictionary) -> void:
	var npc := WorldView.new(data["world"]).npc(id)
	var tid := Sheet.template_id(data, npc)
	var table: Dictionary = TheftRules.cfg(data)["pockets"]
	var spec: Dictionary = table.get(tid, table["_default"])
	var till := int(npc.get("purse_cp", 0))  # a trader's purse is its till, the pack's
	var cp := till if till > 0 else CombatRules.roll_dice(s.rng, str(spec["coins_dice"])) * int(spec["unit_cp"])
	Ledger.purse(b, int(b.get("gold_cp", 0)) + cp)
	var inv := {}
	for item: Variant in npc.get("carries", []):  # v0.7.48: what it always has on it — a letter, a ledger
		_add(data, inv, str(item), 1)
	var pool: Array = (npc.get("pockets", spec.get("items", [])) as Array).duplicate()
	for i in mini(pool.size(), int(spec.get("item_count", 2))):
		_add(data, inv, str(pool.pop_at(s.rng.randi_range(0, pool.size() - 1))), 1)
	var kit := start(data, tid)
	for item: String in kit["inventory"]:
		_add(data, inv, item, int(kit["inventory"][item]))
	b["inventory"] = inv
	b["equipped"] = kit["equipped"]


static func _add(data: Dictionary, inv: Dictionary, item: String, qty: int) -> void:
	if data["items"]["catalog"].has(item):
		inv[item] = int(inv.get(item, 0)) + qty


## What a template comes with: its SRD gear with the ammunition for it and `rules.creatures.kit`; armour and a shield are worn.
static func start(data: Dictionary, tid: String) -> Dictionary:
	var m: Dictionary = data["monsters"].get(tid, {})
	var inv := {}
	var worn := {}
	var ammo: Dictionary = ItemRules.cfg(data)["ammo"]
	var all: Array = (m.get("equipment", []) as Array) + (data["rules"]["creatures"]["kit"].get(tid, []) as Array)
	for v: Variant in all:
		var item := str(v)
		if not data["items"]["catalog"].has(item):
			continue
		_add(data, inv, item, 1)
		if ammo.has(item):  # what it shoots with
			_add(data, inv, str(ammo[item]), int(data["rules"]["creatures"]["foe_ammo"]))
		var slot := _slot(data["items"]["catalog"][item])
		if not slot.is_empty() and not worn.has(slot):
			worn[slot] = item
	return {"inventory": inv, "equipped": worn}


## The slot armour or a shield is worn in; "" for anything else.
static func _slot(def: Dictionary) -> String:
	if not def.has("armor"):
		return ""
	return "shield" if str(def["armor"].get("category", "")) == "shield" else "armor"


## The things it took from its template are worn: picked from its pockets at a harder DC.
static func worn(data: Dictionary, tid: String, item: String) -> bool:
	return (data["monsters"].get(tid, {}).get("equipment", []) as Array).has(item)


static func coins(s: GameSession, data: Dictionary, id: String) -> int:
	return int(of(s, data, id).get("gold_cp", 0))


## Coins in (`delta` > 0) or out of its purse, never under nothing; the hero's go through its book.
static func pay(s: GameSession, data: Dictionary, id: String, delta: int) -> void:
	if id == Being.HERO:
		Ledger.add(s, maxi(delta, -Ledger.balance(s)), "gear")
		return
	var c := of(s, data, id)
	Ledger.purse(c, int(c.get("gold_cp", 0)) + delta)


## A trader's purse is at least the pack's after a new day.
static func keep(s: GameSession, data: Dictionary, id: String, cp: int) -> void:
	var c := of(s, data, id)
	Ledger.purse(c, maxi(int(c.get("gold_cp", 0)), cp))


static func count(s: GameSession, data: Dictionary, id: String, item: String) -> int:
	return int(of(s, data, id)["inventory"].get(item, 0))


## A thing into its hands; armour or a shield is put on when it wears none.
static func give(s: GameSession, data: Dictionary, id: String, item: String, qty: int = 1) -> void:
	var c := of(s, data, id)
	ItemRules.add(c, item, qty)
	var slot := _slot(ItemRules.def_of(data["items"], s.items, item))
	var worn_now: Dictionary = c.get("equipped", {})
	if not slot.is_empty() and str(worn_now.get(slot, "")).is_empty():
		worn_now[slot] = item
		c["equipped"] = worn_now


## Takes up to `qty` of a thing (all of it when < 0): ItemRules.remove. How many.
static func take(s: GameSession, data: Dictionary, id: String, item: String, qty: int = -1) -> int:
	return ItemRules.remove(of(s, data, id), item, qty)


## Empties its pockets: {cp, items}; `keep_worn` — what it wears and its template's weapons stay on it.
static func strip(s: GameSession, data: Dictionary, id: String, keep_worn: bool) -> Dictionary:
	var c := of(s, data, id)
	var tid := Sheet.template_id(data, WorldView.new(data["world"]).npc(id))
	var out := {"cp": int(c.get("gold_cp", 0)), "items": {}}
	Ledger.purse(c, 0)
	var on: Array = (c.get("equipped", {}) as Dictionary).values()
	for item: String in (c["inventory"] as Dictionary).keys():
		if keep_worn and (on.has(item) or worn(data, tid, item)):
			continue
		out["items"][item] = take(s, data, id, item)
	return out


## A weapon stolen out of its hands comes back after `rules.theft.rearm_days` (v0.7.22.8): it bought a new one.
static func _rearm(s: GameSession, data: Dictionary, b: Dictionary) -> void:
	var gone: Dictionary = b.get("disarmed", {})
	for item: String in gone.keys():
		if s.day - int(gone[item]) >= int(TheftRules.cfg(data).get("rearm_days", 3)):
			if int(b["inventory"].get(item, 0)) <= 0:
				b["inventory"][item] = 1
			gone.erase(item)


# --- a fight -------------------------------------------------------------------------------------------------------


## A fighter takes its things into the fight: a person's from its record, a searched foe what was left on it (`spec.gear`,
## v0.8.4.4), anyone else its template's. Its blows and its AC follow what it has.
static func arm(s: GameSession, data: Dictionary, f: Dictionary, spec: Dictionary) -> void:
	var id := str(f["id"])
	var tid := str(f["monster"])
	if spec.get("gear") is Dictionary:
		f["inventory"] = (spec["gear"] as Dictionary).duplicate()
		var was: Dictionary = start(data, tid)["equipped"]
		var on := {}
		for slot: String in was:
			if f["inventory"].has(was[slot]):
				on[slot] = was[slot]
		f["equipped"] = on
	elif Being.view(s, id).has("inventory") or not str(f.get("npc_id", "")).is_empty():
		var mine := of(s, data, id)
		for k: String in KEYS:
			if mine.has(k):
				f[k] = mine[k]
				mine.erase(k)
	else:
		f.merge(start(data, tid))
	follow(s, data, f)


## Its blows and AC by what it has now: the template's without the weapons it lost or has nothing to shoot with, and with
## the weapons it got; what its worn things lay (v0.8.4.26).
static func follow(s: GameSession, data: Dictionary, f: Dictionary) -> void:
	var tid := str(f.get("monster", ""))
	var m: Dictionary = data["monsters"].get(tid, {})
	if m.is_empty() or not f.has("inventory"):
		return
	ItemRules.wear(f, data, s.items)  # v0.8.4.26: what its worn things lay, as on the hero
	if Guise.has_body(f):  # a form: its template's blows as they are, its gear is not transformed (5e, v0.8.4.27.2)
		f.erase("actions")
		return
	var acts := actions(s, data, tid, f)
	if acts != m["actions"]:
		f["actions"] = acts
	else:
		f.erase("actions")
	f["ac"] = ac(s, data, tid, f)


static func actions(s: GameSession, data: Dictionary, tid: String, c: Dictionary) -> Array:
	var m: Dictionary = data["monsters"][tid]
	var inv: Dictionary = c.get("inventory", {})
	var ammo: Dictionary = ItemRules.cfg(data)["ammo"]
	var lost: Array[String] = []
	var held: Array[String] = []
	for a: Dictionary in m["actions"]:
		var item := str(a.get("item", ""))
		if item.is_empty():
			continue
		held.append(item)
		if not inv.has(item) or (ammo.has(item) and ammo_left(data, c, str(ammo[item])) <= 0):
			lost.append(item)
	var out: Array = TheftRules.without(m["actions"], lost)
	for item: String in inv:
		var w: Dictionary = ItemRules.def_of(data["items"], s.items, item).get("weapon", {})
		if not w.is_empty() and not held.has(item) and (not ammo.has(item) or ammo_left(data, c, str(ammo[item])) > 0):
			out = out + [_blow(s, data, c, m, item)]
	return out


## A blow with a weapon its template does not know, as the hero's hands would have it (v0.8.4.15): CombatRules.weapon_profile
## of its sheet — its abilities and proficiency, a +N, the workmanship, a versatile grip, a fighting style, Shillelagh —
## and the weapon's magic and silver against a resistance.
static func _blow(s: GameSession, data: Dictionary, c: Dictionary, m: Dictionary, item: String) -> Dictionary:
	var me := c.duplicate()
	me["abilities"] = Sheet.of(s, data, c)["abilities"]
	me["prof_bonus"] = int(m.get("prof", 2))
	me["weapon_profs"] = ["simple", "martial"]  # 5e: a creature is proficient with what it wields
	me["item_props"] = Sheet.props(s, data, c)
	var eq: Dictionary = (c.get("equipped", {}) as Dictionary).duplicate()
	eq["main_hand"] = item
	me["equipped"] = eq
	var w := CombatRules.weapon_profile(me, data, s.items, item)
	var dice := str(w["dice"]) + ("%+d" % int(w["bonus"]) if int(w["bonus"]) != 0 else "")
	var out := {"name": str(w["name"]), "name_en": item, "item": item, "kind": "melee" if bool(w["melee"]) else "ranged", "to_hit": int(w["to_hit"]),
		"damage": [{"dice": dice, "type": str(w["type"])}], "magical": bool(w["magical"]), "silvered": bool(w["silvered"])}
	if not bool(w["melee"]):
		out["range"] = w["range"] if not (w["range"] as Array).is_empty() else [80, 320]
	elif bool(w["reach"]):
		out["reach"] = 10
	return out


## Its AC by what it wears: the template's as it came; armour off — 10 + DEX under what was natural; other armour — its
## own with the Defense style; what its things add (CharacterRules.gear_ac: a +N, the workmanship, a Cloak of Protection).
static func ac(s: GameSession, data: Dictionary, tid: String, c: Dictionary) -> int:
	var m: Dictionary = data["monsters"][tid]
	var was: Dictionary = start(data, tid)["equipped"]
	var now: Dictionary = c.get("equipped", {})
	var extra := CharacterRules.gear_ac(c, data, s.items)
	var ab: Dictionary = m.get("abilities", {})
	var dex := CharacterRules.mod(int(ab.get("dex", 10)))
	var bare := 0  # a class's Unarmored Defense of a person who wears none (v0.8.4.29.4)
	if _on(now, "armor").is_empty():
		bare = CharacterRules.unarmored_ac(c, dex, CharacterRules.mod(int(ab.get("con", 10))), CharacterRules.mod(int(ab.get("wis", 10))), not _on(now, "shield").is_empty())
	if _on(was, "armor") == _on(now, "armor") and _on(was, "shield") == _on(now, "shield"):
		return maxi(int(m["ac"]), bare + _shield(s, data, now)) + extra
	var base := int(m["ac"]) - _shield(s, data, was)
	if not _on(was, "armor").is_empty():
		base = 10 + dex
	if not _on(now, "armor").is_empty():
		var armor: Dictionary = ItemRules.def_of(data["items"], s.items, _on(now, "armor")).get("armor", {})
		base = maxi(base, CharacterRules.armored(armor, dex) + (1 if CharacterRules.style(c, "defense") else 0))
	return maxi(base, bare) + _shield(s, data, now) + extra


static func _on(worn_now: Dictionary, slot: String) -> String:
	return str(worn_now.get(slot, ""))


static func _shield(s: GameSession, data: Dictionary, worn_now: Dictionary) -> int:
	if _on(worn_now, "shield").is_empty():
		return 0
	return int(ItemRules.def_of(data["items"], s.items, _on(worn_now, "shield")).get("armor", {}).get("base", 2))


## The fight is over for it: what it has goes back to its record.
static func back(b: Dictionary, f: Dictionary) -> void:
	for k: String in KEYS:
		if f.has(k):
			b[k] = f[k]


## One arrow, bolt or bullet is gone (v0.7.12, PHB): half the spent come back after the fight. With none left a foe's bow is
## out of its blows.
static func spend_ammo(s: GameSession, data: Dictionary, f: Dictionary, ammo: String) -> void:
	if ammo.is_empty():
		return
	var me := Sheet.holder(s, f)
	var from := quivers(data, me, ammo)
	if from.is_empty():
		return
	Thing.take(from[0], ammo, 1)
	var spent: Dictionary = f.get("ammo_spent", {})
	spent[ammo] = int(spent.get(ammo, 0)) + 1
	f["ammo_spent"] = spent
	if ammo_left(data, me, ammo) <= 0:
		follow(s, data, f)


## Where a shot takes `ammo` from (v0.8.4.27): the holder's loose things first, then a quiver or a case of
## `rules.containers` with `at_hand` — those with some. Anybody's: a foe's record has no bags, only its things.
static func quivers(data: Dictionary, holder: Dictionary, ammo: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if Thing.count(holder, ammo) > 0:
		out.append(holder)
	for b: Dictionary in (holder.get("bags", {}) as Dictionary).values():
		if bool(ContainerRules.kind(data, str(b["kind"])).get("at_hand", false)) and Thing.count(b, ammo) > 0:
			out.append(b)
	return out


## Arrows, bolts or bullets at hand: loose and in a quiver.
static func ammo_left(data: Dictionary, holder: Dictionary, ammo: String) -> int:
	var n := 0
	for h: Dictionary in quivers(data, holder, ammo):
		n += Thing.count(h, ammo)
	return n


## Ammunition picked up after a fight: into a quiver that takes it while there is room, the rest loose.
static func stow_ammo(s: GameSession, data: Dictionary, holder: Dictionary, ammo: String, qty: int) -> void:
	for id: String in (holder.get("bags", {}) as Dictionary):
		var b: Dictionary = holder["bags"][id]
		if qty > 0 and bool(ContainerRules.kind(data, str(b["kind"])).get("at_hand", false)):
			var n := mini(qty, ContainerRules.room_for(data, s.items, {"container": b["kind"], "contents": b["contents"]}, ammo))
			Thing.add(b, ammo, n)
			qty -= n
	if qty > 0:
		Thing.add(holder, ammo, qty)


## What may be picked up of what it shot: {ammo: qty}.
static func shot_back(data: Dictionary, f: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var out := {}
	var chance := float(ItemRules.cfg(data)["recover"])
	for ammo: String in f.get("ammo_spent", {}):
		var n := 0
		for i in int(f["ammo_spent"][ammo]):  # each shot whole or broken on its own (v0.8.4.30, the author's feedback)
			if rng.randf() < chance:
				n += 1
		if n > 0:
			out[ammo] = n
	return out
