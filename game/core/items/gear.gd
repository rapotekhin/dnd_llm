class_name Gear
extends RefCounted
## What a character has (v0.8.4.10, ADR-0016): `inventory` {item: qty}, `gold_cp`, `equipped` {slot: item} and `copies` — the form
## of the hero's sheet on anybody, so ItemRules and the acts need not ask whose they are. A person keeps them on its record,
## filled the first time anybody looks (`of`): its template's gear and `rules.creatures.kit`, what the pack gives it, a purse
## by `rules.theft.pockets`. One without a name has its template's gear and kit; the coins of a band are its encounter's
## treasure. In a fight they lie on the fighter, as its statuses do (`arm`), and go back to the record at its end (`back`).
## A trader's purse is this `gold_cp`: one till for the trade, the pockets and the stakes.

const KEYS: Array[String] = ["inventory", "gold_cp", "equipped", "copies", "stowed", "attuned"]


## The holder of what `id` has: the hero's sheet, the fighter in a fight, the record otherwise. For writing.
static func of(s: GameSession, data: Dictionary, id: String) -> Dictionary:
	if id == Being.HERO:
		return s.character
	var b := Being.of(s, id)
	if (b.get("fight", {}) as Dictionary).has("inventory"):
		return b["fight"]
	if not b.has("inventory"):
		_fill(s, data, id, b)
	_rearm(s, data, id, b)
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
	b["stowed"] = kit["stowed"]


static func _add(data: Dictionary, inv: Dictionary, item: String, qty: int) -> void:
	if data["items"]["catalog"].has(item):
		inv[item] = int(inv.get(item, 0)) + qty


## What a template comes with: its SRD gear with the ammunition for it and `rules.creatures.kit`. Its SRD gear is on it as
## the hero's kit would be (v0.8.4.40, CharacterRules.auto_equip): armour and a shield worn, a blade in the hands with a
## second light one in the other, a bow in the set put away — it strikes with what it holds, as anybody.
static func start(data: Dictionary, tid: String) -> Dictionary:
	var m: Dictionary = data["monsters"].get(tid, {})
	var inv := {}
	var ammo: Dictionary = ItemRules.cfg(data)["ammo"]
	var all: Array = (m.get("equipment", []) as Array) + (data["rules"]["creatures"]["kit"].get(tid, []) as Array)
	for v: Variant in all:
		var item := str(v)
		if not data["items"]["catalog"].has(item):
			continue
		_add(data, inv, item, 1)
		if ammo.has(item):  # what it shoots with
			_add(data, inv, str(ammo[item]), int(data["rules"]["creatures"]["foe_ammo"]))
	var own := {}
	for v: Variant in m.get("equipment", []):
		if inv.has(str(v)):
			own[str(v)] = int(inv[str(v)])
	var body := {"inventory": own, "armor_profs": ["light", "medium", "heavy", "shield"]}  # its own gear is what it is made to wear
	CharacterRules.auto_equip(body, data, true)
	return {"inventory": inv, "equipped": body["equipped"], "stowed": body["stowed"]}


## Where each of its weapons lay as it came: {"equipped.main_hand": item, "stowed.main_hand": item…}.
static func layout(data: Dictionary, tid: String) -> Dictionary:
	return _hand_slots(start(data, tid))


## The weapons in the hands of both sets: {"equipped.<slot>" or "stowed.<slot>": item}, the hands first.
static func _hand_slots(c: Dictionary) -> Dictionary:
	var out := {}
	for row: String in ["equipped", "stowed"]:
		for slot: String in ["main_hand", "off_hand"]:
			var item := str((c.get(row, {}) as Dictionary).get(slot, ""))
			if not item.is_empty():
				out[row + "." + slot] = item
	return out


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


## A thing into its hands; it goes on by itself where its place is free (Equip.fill: armour, a shield, a weapon, a ring).
static func give(s: GameSession, data: Dictionary, id: String, item: String, qty: int = 1) -> void:
	ItemRules.add(of(s, data, id), item, qty)
	Equip.fill(s, data, id, item)


## Takes up to `qty` of a thing (all of it when < 0): ItemRules.remove. How many.
static func take(s: GameSession, data: Dictionary, id: String, item: String, qty: int = -1) -> int:
	return ItemRules.remove(of(s, data, id), item, qty)


## What it carries loose (v0.8.4.43.6, the grid of the character window as in BG3): its things less what it wears or holds
## in either set and the stacks on its belt, which the doll and the belt show. {item: qty}.
static func loose(c: Dictionary, data: Dictionary, session_items: Dictionary) -> Dictionary:
	var out := {}
	var belt := ItemRules.belt(c, data, session_items)
	for item: String in c.get("inventory", {}):
		var n := int(c["inventory"][item]) - CharacterRules.held_copies(c, item)
		if n > 0 and not belt.has(item):
			out[item] = n
	return out


## What a weapon set strikes with (v0.8.4.43.6, under the doll as in BG3): the blow of its main hand — fists when it is
## empty — {name, to_hit, parts, damage, low, high}; `spare` — the set put away, counted as if it were in the hands.
## Anybody's on one road: the hero's by its sheet (CombatRules.weapon_profile), another's by what it holds (`actions`).
static func set_blow(s: GameSession, data: Dictionary, id: String, spare: bool) -> Dictionary:
	var c := of(s, data, id)
	var hands: Dictionary = CharacterRules.stowed(c) if spare else c.get("equipped", {})
	var main := str(hands.get("main_hand", ""))
	if id != Being.HERO:
		var tid := Sheet.template_id(data, Sheet.who(s, data, id))
		if not data["monsters"].has(tid):
			return {}
		var pick := {}
		for a: Dictionary in actions(s, data, tid, c):
			if bool(a.get("stowed", false)) != spare or not a.has("damage"):
				continue
			if pick.is_empty() or (not main.is_empty() and str(a.get("item", "")) == main):
				pick = a
		if pick.is_empty():
			return {}
		var low := 0
		var high := 0
		var dmg: Array[String] = []
		for d: Dictionary in pick.get("damage", []):
			var r := CombatRules.dice_range(str(d["dice"]))
			low += r[0]
			high += r[1]
			dmg.append("%s %s" % [str(d["dice"]).replace("d", "к"), data["misc"]["damage_types"].get(str(d["type"]), d["type"])])
		return {"name": str(pick.get("name", "")), "to_hit": int(pick.get("to_hit", 0)), "parts": [RollParts.part(str(pick.get("name", "")), int(pick.get("to_hit", 0)))],
			"damage": " + ".join(dmg), "low": maxi(1, low), "high": maxi(1, high)}
	var probe := c.duplicate()
	if spare:
		var eq: Dictionary = (c.get("equipped", {}) as Dictionary).duplicate()
		for slot: String in CharacterRules.HANDS:
			eq.erase(slot)
			if not str(hands.get(slot, "")).is_empty():
				eq[slot] = hands[slot]
		probe["equipped"] = eq
	var w := CombatRules.weapon_profile(probe, data, s.items, main)
	var r := CombatRules.dice_range(str(w["dice"]), 0)
	var low := r[0] + int(w["bonus"])
	var high := r[1] + int(w["bonus"])
	for el: Dictionary in ItemRules.elements(data, ItemRules.def_of(data["items"], s.items, main)):  # an elemental blade's fire
		var er := CombatRules.dice_range(str(el["dice"]))
		low += er[0]
		high += er[1]
	var parts: Array[Dictionary] = []
	parts.assign(w.get("hit_parts", []))
	RollParts.add(parts, RollParts.OTHER, int(w["to_hit"]) - RollParts.sum(parts))  # a spell on the weapon names itself in the fight's log
	return {"name": str(w["name"]), "to_hit": int(w["to_hit"]), "parts": parts,
		"damage": ItemInfo.damage(data, s.items, w), "low": maxi(1, low), "high": maxi(1, high)}


## Empties its pockets: {cp, items}; `keep_worn` — what it wears and its template's weapons stay on it.
static func strip(s: GameSession, data: Dictionary, id: String, keep_worn: bool) -> Dictionary:
	var c := of(s, data, id)
	var tid := Sheet.template_id(data, WorldView.new(data["world"]).npc(id))
	var out := {"cp": int(c.get("gold_cp", 0)), "items": {}}
	Ledger.purse(c, 0)
	var on: Array = (c.get("equipped", {}) as Dictionary).values() + CharacterRules.stowed(c).values()
	for item: String in (c["inventory"] as Dictionary).keys():
		if keep_worn and (on.has(item) or worn(data, tid, item)):
			continue
		out["items"][item] = take(s, data, id, item)
	return out


## A weapon stolen out of its hands comes back after `rules.theft.rearm_days` (v0.7.22.8): it bought a new one.
static func _rearm(s: GameSession, data: Dictionary, id: String, b: Dictionary) -> void:
	var gone: Dictionary = b.get("disarmed", {})
	var back: Array[String] = []
	for item: String in gone.keys():
		if s.day - int(gone[item]) >= int(TheftRules.cfg(data).get("rearm_days", 3)):
			if int(b["inventory"].get(item, 0)) <= 0:
				b["inventory"][item] = 1
			gone.erase(item)
			back.append(item)
	for item: String in back:  # the new one is in its hand (v0.8.4.40: it strikes only with what it holds)
		Equip.fill(s, data, id, item)


# --- a fight -------------------------------------------------------------------------------------------------------


## A fighter takes its things into the fight: a person's from its record, a searched foe what was left on it (`spec.gear`,
## v0.8.4.4), anyone else its template's. Its blows and its AC follow what it has.
static func arm(s: GameSession, data: Dictionary, f: Dictionary, spec: Dictionary) -> void:
	var id := str(f["id"])
	var tid := str(f["monster"])
	if spec.get("gear") is Dictionary:
		f["inventory"] = (spec["gear"] as Dictionary).duplicate()
		var kit := start(data, tid)
		for row: String in ["equipped", "stowed"]:
			var on := {}
			for slot: String in kit[row]:
				if f["inventory"].has(kit[row][slot]):
					on[slot] = kit[row][slot]
			f[row] = on
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


## Its blows by what it holds (v0.8.4.40, the author: no difference between a person, a monster and the hero): a template's
## action with a weapon only while that weapon is in the hands of one of its sets — one of the set put away is `stowed`,
## struck after a free swap (the act «Атака»); natural ones (a bite, a claw) always. A weapon in its hands the template
## does not know is a blow of its own (`_blow`); in the hand of a lost one it carries that one's name, so its Multiattack
## strikes with what is in the hand now (a scimitar swapped for a longsword: «Длинный меч ×2»). Nothing in the hands — fists.
static func actions(s: GameSession, data: Dictionary, tid: String, c: Dictionary) -> Array:
	var m: Dictionary = data["monsters"][tid]
	var ammo: Dictionary = ItemRules.cfg(data)["ammo"]
	var hands := _hand_slots(c)
	var where := {}  # item: "equipped" or "stowed", the hands first
	for key: String in hands:
		if not where.has(hands[key]):
			where[hands[key]] = key.get_slice(".", 0)
	var lost: Array[String] = []
	var held: Array[String] = []
	for a: Dictionary in m["actions"]:
		var item := str(a.get("item", ""))
		if item.is_empty():
			continue
		held.append(item)
		if not where.has(item) or (ammo.has(item) and ammo_left(data, c, str(ammo[item])) <= 0):
			lost.append(item)
	var out: Array = []
	for a: Dictionary in TheftRules.without(m["actions"], lost):
		if str(where.get(str(a.get("item", "")), "")) == "stowed":
			a = a.duplicate()
			a["stowed"] = true
		out.append(a)
	var named := {}  # the hand of a lost action: its name goes to what is there now
	var was := layout(data, tid)
	for a: Dictionary in m["actions"]:
		for key: String in was:
			if lost.has(str(a.get("item", ""))) and str(was[key]) == str(a["item"]) and not named.has(key):
				named[key] = str(a.get("name_en", ""))
	var fresh: Array = []
	var seen: Array[String] = []
	for key: String in hands:
		var item := str(hands[key])
		var w: Dictionary = ItemRules.def_of(data["items"], s.items, item).get("weapon", {})
		if w.is_empty() or held.has(item) or seen.has(item) or (ammo.has(item) and ammo_left(data, c, str(ammo[item])) <= 0):
			continue
		seen.append(item)
		var b := _blow(s, data, c, m, item)
		if named.has(key):
			b["name_en"] = named[key]
		if key.begins_with("stowed"):
			b["stowed"] = true
		fresh.append(b)
	if fresh.any(func(b: Dictionary) -> bool: return str(b["kind"]) == "melee"):
		out = out.filter(func(a: Dictionary) -> bool: return a.has("item") or m["actions"].has(a))  # a blade, not fists
	return out + fresh


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
		bare = CharacterRules.unarmored_ac(c, dex, CharacterRules.mod(int(ab.get("con", 10))), CharacterRules.mod(int(ab.get("wis", 10))), _shield(s, data, now) > 0)
	if _on(was, "armor") == _on(now, "armor") and CharacterRules.shield_in(was, data, s.items) == CharacterRules.shield_in(now, data, s.items):
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


## What the shield of its off hand adds (v0.8.4.43.13: a shield is held in the off hand), 0 — none.
static func _shield(s: GameSession, data: Dictionary, worn_now: Dictionary) -> int:
	var id := CharacterRules.shield_in(worn_now, data, s.items)
	return 0 if id.is_empty() else int(ItemRules.def_of(data["items"], s.items, id).get("armor", {}).get("base", 2))


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
## v0.8.4.42.1 (the author): only from the belt — the arrows laid in its cell, or a quiver whose kind is there; arrows
## in the pack are not shot. A record that never laid its belt carries them there by itself (ItemRules.belt).
static func quivers(data: Dictionary, holder: Dictionary, ammo: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var belt := ItemRules.belt(holder, data, {})
	if belt.has(ammo) and Thing.count(holder, ammo) > 0:
		out.append(holder)
	for b: Dictionary in (holder.get("bags", {}) as Dictionary).values():
		if bool(ContainerRules.kind(data, str(b["kind"])).get("at_hand", false)) and belt.has(str(b["kind"])) and Thing.count(b, ammo) > 0:
			out.append(b)
	return out


## What a weapon shoots ("" — it shoots nothing): rules.item_rules.ammo by its id or its base kind.
static func ammo_of(data: Dictionary, session_items: Dictionary, weapon_id: String) -> String:
	var def := ItemRules.def_of(data["items"], session_items, weapon_id)
	if not (def.get("properties", []) as Array).has("ammunition"):
		return ""
	var by: Dictionary = ItemRules.cfg(data)["ammo"]
	return str(by.get(ItemRules.real_id(weapon_id), by.get(ItemRules.plain_of(data["items"], session_items, weapon_id), "")))


## The weapons in either set of anybody that have nothing to shoot on the belt (v0.8.4.42.1, the author: a warning in the
## sheet) — their ids.
static func unfed(data: Dictionary, session_items: Dictionary, holder: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for row: String in ["equipped", "stowed"]:
		var slots: Dictionary = holder.get(row, {})
		for slot: String in ["main_hand", "off_hand"]:
			var id := str(slots.get(slot, ""))
			var ammo := ammo_of(data, session_items, id) if not id.is_empty() else ""
			if not ammo.is_empty() and ammo_left(data, holder, ammo) <= 0 and not out.has(id):
				out.append(id)
	return out


## Arrows, bolts or bullets at hand: loose and in a quiver.
static func ammo_left(data: Dictionary, holder: Dictionary, ammo: String) -> int:
	var n := 0
	for h: Dictionary in quivers(data, holder, ammo):
		n += Thing.count(h, ammo)
	return n


## The shots a weapon has at hand (v0.8.4.42.6, the author: seen without opening the quiver): its ammunition loose on
## the belt and in every quiver on the belt — a quiver of 15 and one of 5 are 20, a quiver of 20 and one arrow are 21.
## -1 — the weapon shoots nothing.
static func ready_shots(data: Dictionary, session_items: Dictionary, holder: Dictionary, weapon_id: String) -> int:
	var ammo := ammo_of(data, session_items, weapon_id)
	return -1 if ammo.is_empty() else ammo_left(data, holder, ammo)


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


## A weapon thrown by anybody (v0.8.4.31, the author's feedback): it leaves the hand and lies on the target's square
## (`s.combat.dropped`) until picked up — in the fight by «Подобрать», after it with the arrows. A template's action is
## not thrown twice (`f.thrown`); a weapon `returning` comes back to the hand.
static func throw_out(s: GameSession, data: Dictionary, f: Dictionary, b: Dictionary, at: Vector2i) -> void:
	var a: Dictionary = b.get("act", {})
	if not a.is_empty():
		var gone: Array = f.get("thrown", [])
		gone.append(str(a.get("name_en", "")))
		f["thrown"] = gone
	var item := str(b.get("id", a.get("item", "")))
	if item.is_empty() or returns(data, s.items, item):
		return
	var holder := owned(s, data, f)
	var slot := ""
	for sl: String in ["main_hand", "off_hand"]:
		if str(holder.get("equipped", {}).get(sl, "")) == item and slot.is_empty():
			slot = sl
	if ItemRules.remove(holder, item, 1) <= 0:
		return
	var dropped: Array = s.combat.get("dropped", [])
	dropped.append({"item": item, "x": at.x, "y": at.y, "slot": slot, "by": str(f.get("id", ""))})
	s.combat["dropped"] = dropped
	FightGrid.changed(s)


## The holder of a fighter's things for writing: a foe of its template's gear gets them as its own first.
static func owned(s: GameSession, data: Dictionary, f: Dictionary) -> Dictionary:
	var holder := Sheet.holder(s, f)
	if not holder.has("inventory"):  # a foe of its template's gear: what it has from now on is its own
		holder["inventory"] = (Gear.start(data, Sheet.template_id(data, f))["inventory"] as Dictionary).duplicate()
	return holder


## The missile of a blow that hit — a shot's arrow or bolt, a thrown weapon — caught out of the air by `t` (Deflect Missiles,
## Gloves of Missile Snaring, v0.8.4.43.46): no longer on the field nor among what `f` may gather after the fight, now in the
## catcher's things. Only one small enough for one hand (no heavy, two-handed thing) and only with a hand free. Its id, "" —
## nothing caught.
static func catch(s: GameSession, data: Dictionary, f: Dictionary, t: Dictionary, b: Dictionary) -> String:
	var ammo := str(b.get("ammo", ""))
	var item := ammo if not ammo.is_empty() else str(b.get("id", b.get("act", {}).get("item", "")))
	var def := ItemRules.def_of(data["items"], s.items, item) if not item.is_empty() else {}
	if def.is_empty():
		return ""  # a giant's rock, a spine of no thing
	var props: Array = def.get("properties", [])
	if props.has("heavy") or props.has("two_handed") or not CharacterRules.free_hand(Sheet.things(s, data, t), data, s.items):
		return ""
	if not ammo.is_empty():
		var spent: Dictionary = f.get("ammo_spent", {})
		if int(spent.get(ammo, 0)) > 0:
			spent[ammo] = int(spent[ammo]) - 1
	else:
		var list: Array = s.combat.get("dropped", [])
		var i := list.size() - 1
		while i >= 0 and not (str(list[i]["item"]) == item and str(list[i].get("by", "")) == str(f.get("id", ""))):
			i -= 1
		if i < 0:
			return ""  # a returning weapon is back in its hand already
		list.remove_at(i)
		FightGrid.changed(s)
	ItemRules.add(owned(s, data, t), item, 1)
	return item


static func returns(data: Dictionary, session_items: Dictionary, item: String) -> bool:
	return (ItemRules.def_of(data["items"], session_items, item).get("weapon", {}).get("properties", []) as Array).has("returning")


## What lies on the square `at` or beside it: indices of `s.combat.dropped`.
static func dropped_near(s: GameSession, f: Dictionary) -> Array[int]:
	var out: Array[int] = []
	var list: Array = s.combat.get("dropped", [])
	for i in list.size():
		if FightGrid.dist_to(f, Vector2i(int(list[i]["x"]), int(list[i]["y"]))) <= 1:
			out.append(i)
	return out


## Picks up what lies beside `f`: back into its things (the hero's hand when it is empty). Lines.
static func pick_up(s: GameSession, data: Dictionary, f: Dictionary, lines: Array[String]) -> void:
	var list: Array = s.combat.get("dropped", [])
	var near := dropped_near(s, f)
	near.reverse()
	var holder := Sheet.holder(s, f)
	for i: int in near:
		var item := str(list[i]["item"])
		var slot := str(list[i].get("slot", "")) if str(list[i].get("by", "")) == str(f.get("id", "")) else ""
		list.remove_at(i)
		ItemRules.add(holder, item, 1)
		var eq: Dictionary = holder.get("equipped", {})
		if not slot.is_empty() and str(eq.get(slot, "")).is_empty() and CharacterRules.can_equip(holder, data, s.items, item, slot).is_empty():
			eq[slot] = item  # back to the hand it was thrown from
			holder["equipped"] = eq
		lines.append("%s подбирает: %s" % [holder.get("name", ""), ItemRules.display_name(data["items"], s.items, item)])
	f.erase("thrown")  # what it threw is in its hand again
	FightGrid.changed(s)


## What lies on the field after the fight: {item: qty}.
static func left_on_field(s: GameSession) -> Dictionary:
	var out := {}
	for d: Dictionary in s.combat.get("dropped", []):
		out[str(d["item"])] = int(out.get(str(d["item"]), 0)) + 1
	return out


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
