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
	var inv: Dictionary = c["inventory"]
	inv[item] = int(inv.get(item, 0)) + qty
	var slot := _slot(ItemRules.def_of(data["items"], s.items, item))
	var worn_now: Dictionary = c.get("equipped", {})
	if not slot.is_empty() and str(worn_now.get(slot, "")).is_empty():
		worn_now[slot] = item
		c["equipped"] = worn_now


## Takes up to `qty` of a thing (all of it when < 0); what it wore of it is off. How many.
static func take(s: GameSession, data: Dictionary, id: String, item: String, qty: int = -1) -> int:
	var c := of(s, data, id)
	var inv: Dictionary = c["inventory"]
	var have := int(inv.get(item, 0))
	var n := have if qty < 0 else mini(qty, have)
	if have - n > 0:
		inv[item] = have - n
	else:
		inv.erase(item)
		var worn_now: Dictionary = c.get("equipped", {})
		for slot: String in worn_now.keys():
			if str(worn_now[slot]) == item:
				worn_now.erase(slot)
	return n


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
## the weapons it got.
static func follow(s: GameSession, data: Dictionary, f: Dictionary) -> void:
	var tid := str(f.get("monster", ""))
	var m: Dictionary = data["monsters"].get(tid, {})
	if m.is_empty() or not f.has("inventory"):
		return
	var acts := actions(s, data, tid, f)
	if acts != m["actions"]:
		f["actions"] = acts
	else:
		f.erase("actions")
	f["ac"] = ac(data, tid, f)


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
		if not inv.has(item) or (ammo.has(item) and not inv.has(str(ammo[item]))):
			lost.append(item)
	var out: Array = TheftRules.without(m["actions"], lost)
	for item: String in inv:
		var w: Dictionary = ItemRules.def_of(data["items"], s.items, item).get("weapon", {})
		if not w.is_empty() and not held.has(item) and (not ammo.has(item) or inv.has(str(ammo[item]))):
			out = out + [_blow(s, data, m, item)]
	return out


## A blow with a weapon its template does not know: the weapon's dice, its ability and the template's proficiency.
static func _blow(s: GameSession, data: Dictionary, m: Dictionary, item: String) -> Dictionary:
	var def := ItemRules.def_of(data["items"], s.items, item)
	var w: Dictionary = def["weapon"]
	var ab: Dictionary = m.get("abilities", {})
	var ranged := str(w.get("range", "melee")) == "ranged"
	var str_mod := CharacterRules.mod(int(ab.get("str", 10)))
	var dex_mod := CharacterRules.mod(int(ab.get("dex", 10)))
	var mod := dex_mod if ranged else maxi(str_mod, dex_mod) if (def.get("properties", []) as Array).has("finesse") else str_mod
	var dice := str(w.get("damage", "1"))
	if mod != 0:
		dice += "%+d" % mod
	var out := {"name": str(def.get("name", item)), "name_en": item, "item": item, "kind": "ranged" if ranged else "melee",
		"to_hit": mod + int(m.get("prof", 2)), "damage": [{"dice": dice, "type": str(w.get("damage_type", "bludgeoning"))}]}
	if ranged:
		out["range"] = w.get("reach_ft", [80, 320])
	elif (def.get("properties", []) as Array).has("reach"):
		out["reach"] = 10
	return out


## Its AC by what it wears: the template's as it came; armour off — 10 + DEX under what was natural; other armour — its own.
static func ac(data: Dictionary, tid: String, c: Dictionary) -> int:
	var m: Dictionary = data["monsters"][tid]
	var was: Dictionary = start(data, tid)["equipped"]
	var now: Dictionary = c.get("equipped", {})
	if str(was.get("armor", "")) == str(now.get("armor", "")) and str(was.get("shield", "")) == str(now.get("shield", "")):
		return int(m["ac"])
	var cat: Dictionary = data["items"]["catalog"]
	var dex := CharacterRules.mod(int(m.get("abilities", {}).get("dex", 10)))
	var base := int(m["ac"]) - _shield(cat, was)
	if was.has("armor"):
		base = 10 + dex
	if now.has("armor"):
		base = maxi(base, CharacterRules.armored(cat.get(str(now["armor"]), {}).get("armor", {}), dex))
	return base + _shield(cat, now)


static func _shield(cat: Dictionary, worn_now: Dictionary) -> int:
	return int(cat.get(str(worn_now.get("shield", "")), {}).get("armor", {}).get("base", 2)) if worn_now.has("shield") else 0


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
	var inv: Dictionary = Sheet.holder(s, f).get("inventory", {})
	var left := int(inv.get(ammo, 0)) - 1
	if left > 0:
		inv[ammo] = left
	else:
		inv.erase(ammo)
	var spent: Dictionary = f.get("ammo_spent", {})
	spent[ammo] = int(spent.get(ammo, 0)) + 1
	f["ammo_spent"] = spent
	if left <= 0:
		follow(s, data, f)


## What may be picked up of what it shot: {ammo: qty}.
static func shot_back(data: Dictionary, f: Dictionary) -> Dictionary:
	var out := {}
	for ammo: String in f.get("ammo_spent", {}):
		var n := int(floor(int(f["ammo_spent"][ammo]) * float(ItemRules.cfg(data)["recover"])))
		if n > 0:
			out[ammo] = n
	return out
