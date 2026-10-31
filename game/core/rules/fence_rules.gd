class_name FenceRules
extends RefCounted
## Fences (roadmap v0.7.33, the author: a fence of the pack and the master's). A trader with `fence` {buy_pct} (pack NPC
## or the master's effect in generated.fences) buys stolen things — the hero's foreign ones (OwnerRules) — at buy_pct
## of the value and sells rules.underworld.fence.stock, but only to those who know it: a background tied to its tags
## (a criminal's contact), a member of the organization it fences for, or the hero it was revealed to (c.fences_known).
## An honest trader of the owner's location knows a stolen thing and does not buy it.


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"]["underworld"]


static func spec(s: GameSession, data: Dictionary, npc_id: String) -> Dictionary:
	var made: Dictionary = WorldGen.generated(s).get("fences", {})
	if made.has(npc_id):
		return made[npc_id]
	var f: Variant = BondRules.npc_def(s, data, npc_id).get("fence")
	return f if f is Dictionary else {}


static func is_fence(s: GameSession, data: Dictionary, npc_id: String) -> bool:
	return not spec(s, data, npc_id).is_empty() and not s.dead_npcs.has(npc_id)


static func known(s: GameSession, data: Dictionary, npc_id: String) -> bool:
	if not is_fence(s, data, npc_id):
		return false
	if (s.character.get("fences_known", []) as Array).has(npc_id):
		return true
	var tie := str(BackgroundRules.spec(s.character, data).get("ties", ""))
	if not tie.is_empty() and (BondRules.npc_def(s, data, npc_id).get("tags", []) as Array).has(tie):
		return true
	return not OrgRules.fencing_for(s, data, npc_id).is_empty()


static func buy_pct(s: GameSession, data: Dictionary, npc_id: String) -> int:
	var pct := int(spec(s, data, npc_id).get("buy_pct", cfg(data)["fence"]["buy_pct"]))
	if OrgRules.fence_perk(s, data, npc_id):
		pct = maxi(pct, int(cfg(data)["fence"]["buy_pct_member"]))
	return pct


## How many of `item_id` the hero carries that are someone else's (any owner).
static func stolen_qty(s: GameSession, item_id: String) -> int:
	var n := 0
	for owner: String in OwnerRules.foreign(s).get(item_id, {}):
		n += int(OwnerRules.foreign(s)[item_id][owner])
	return n


## How many of `item_id` an honest trader recognizes as stolen: owners of its own location.
static func recognized(s: GameSession, data: Dictionary, npc_id: String, item_id: String) -> int:
	if known(s, data, npc_id):
		return 0
	var loc := home_location(data, npc_id)
	if loc.is_empty():
		return 0
	var n := 0
	var by: Dictionary = OwnerRules.foreign(s).get(item_id, {})
	for owner: String in by:
		if home_location(data, owner) == loc:
			n += int(by[owner])
	return n


## The location of the room an NPC belongs to ("" — none).
static func home_location(data: Dictionary, npc_id: String) -> String:
	var rooms: Dictionary = data["world"]["rooms"]
	for r: String in rooms:
		if (rooms[r].get("npcs", []) as Array).has(npc_id):
			return str(rooms[r].get("location_id", ""))
	return ""


## What a known fence pays for one stolen unit.
static func unit_price(s: GameSession, data: Dictionary, npc_id: String, item_id: String) -> int:
	return Price.floored(Price.mod(Price.start(int(ItemRules.def_of(data["items"], s.items, item_id).get("value_cp", 0))), "скупщик", buy_pct(s, data, npc_id)))


## The fence's own goods join its stock once a day for those who know it.
static func restock(s: GameSession, data: Dictionary, npc_id: String, m: Dictionary) -> void:
	if int(m.get("fence_day", -1)) == s.day or not known(s, data, npc_id):
		return
	m["fence_day"] = s.day
	var stock: Dictionary = m["stock"]
	var goods: Dictionary = cfg(data)["fence"]["stock"]
	for id: String in goods:
		stock[id] = maxi(int(stock.get(id, 0)), int(goods[id]))


static func reveal(s: GameSession, npc_id: String) -> void:
	var list: Array = s.character.get("fences_known", [])
	if not list.has(npc_id):
		list.append(npc_id)
	s.character["fences_known"] = list


# --- the master's `fence` -----------------------------------------------------------------------------------------


## A trader of the scene buys stolen goods (or a fence of the pack confides in the hero): {npc_id, buy_pct, reveal}.
static func make(s: GameSession, data: Dictionary, e: Dictionary) -> Dictionary:
	var who := str(e.get("npc_id", ""))
	if not BondRules.here(s, data, who):
		return {"reason": "%s не в сцене — скупщиком делают торговца сцены" % who}
	if not WorldView.new(data["world"]).is_trader(who):
		return {"reason": "%s не торгует — скупщик только из торговцев (create_npc с trader)" % BondRules.npc_name(s, data, who)}
	var r: Array = cfg(data)["make_fence"]["buy_pct"]
	var pct := int(e.get("buy_pct", 0)) if e.get("buy_pct") != null else 0
	if is_fence(s, data, who):
		pct = 0
	elif pct < int(r[0]) or pct > int(r[1]):
		return {"reason": "buy_pct — от %d до %d%% цены" % [int(r[0]), int(r[1])]}
	return {"plan": {"npc": who, "buy_pct": pct}, "summary": "Скупщик: %s%s" % [BondRules.npc_name(s, data, who),
		" — берёт краденое за %d%%" % pct if pct > 0 else " открылся герою"]}


static func apply_make(s: GameSession, data: Dictionary, plan: Dictionary) -> Array[String]:
	var who := str(plan["npc"])
	if int(plan["buy_pct"]) > 0:
		var gen := WorldGen.generated(s)
		var all: Dictionary = gen.get("fences", {})
		all[who] = {"buy_pct": int(plan["buy_pct"])}
		gen["fences"] = all
	reveal(s, who)
	return ["%s скупает краденое: %d%% цены — в торговле с ним" % [BondRules.npc_name(s, data, who), buy_pct(s, data, who)]]


static func text(s: GameSession, data: Dictionary) -> String:
	var parts: Array[String] = []
	for npc: String in SceneRules.npcs(s, data["world"], s.room_id):
		if known(s, data, npc):
			parts.append("%s — скупщик: краденое за %d%%" % [BondRules.npc_name(s, data, npc), buy_pct(s, data, npc)])
	var stolen: Array[String] = []
	for id: String in OwnerRules.foreign(s):
		stolen.append(ItemRules.display_name(data["items"], s.items, id))
	if not stolen.is_empty():
		parts.append("у героя краденое: " + ", ".join(stolen))
	return "; ".join(parts)


## Where the fence trades, in words (v0.7.39.3): its room's name.
static func where(s: GameSession, data: Dictionary, npc_id: String) -> String:
	var w := WorldView.new(data["world"])
	var room := str(s.npc_at.get(npc_id, BondRules.npc_def(s, data, npc_id).get("room_id", "")))
	return str(w.room(room).get("name", room)).to_lower() if not room.is_empty() else "в городе"


## Where to get a thing the hero lacks (v0.7.39.3, the author: no picks to be found): the fences the hero knows that
## sell it and the recipe that makes it. "" — nowhere known.
static func tool_hint(s: GameSession, data: Dictionary, item_id: String) -> String:
	var ways: Array[String] = []
	if (cfg(data)["fence"]["stock"] as Dictionary).has(item_id):
		for id: String in data["world"]["npcs"]:
			if known(s, data, id):
				ways.append("у скупщика %s (%s)" % [BondRules.npc_name(s, data, id), where(s, data, id)])
	var r: Dictionary = data["rules"].get("craft", {}).get("recipes", {}).get(item_id, {})
	if not r.is_empty():
		var at := CraftRules.station_name(data, str(r["station"])).to_lower() if not str(r.get("station", "")).is_empty() else ""
		ways.append("сделать самому%s%s" % [" у: " + at if not at.is_empty() else "",
			" (%s)" % BackgroundRules.tool_name(data, str(r["tool"])).to_lower() if not str(r.get("tool", "")).is_empty() else ""])
	if ways.is_empty():
		return ""
	return " или ".join(ways)
