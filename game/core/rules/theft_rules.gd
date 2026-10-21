class_name TheftRules
extends RefCounted
## Pockets of NPCs and what happens when the player is caught (roadmap v0.7.0, decision of the author: a pockets
## window like in BG3). The engine fills the pockets once (s.pockets) from the pack (`pockets` of the NPC) or by the
## NPC's monster template (rules.theft.pockets): a purse of coins, small things, worn gear. Each entry has its DC:
## the NPC's passive Perception (at least 10) + the entry's modifiers (rules.theft.dc). A Sleight of Hand at least the
## DC takes it; a failure — the NPC reacts by its kind (rules.theft.reactions): a guard fights, a trader closes the
## shop for the day, others call the guard (a fine, or a fight with the guard when the player cannot pay).


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"]["theft"]


static func _template(data: Dictionary, npc: Dictionary) -> String:
	return str(npc.get("monster", CombatRules.cfg(data)["default_npc_monster"]))


## The NPC's pockets, filled on the first look: [{id, name, item_id, cp, qty, worn, dc}].
static func pockets(s: GameSession, data: Dictionary, npc_id: String) -> Array:
	if s.pockets.has(npc_id):
		return s.pockets[npc_id]
	var npc := WorldView.new(data["world"]).npc(npc_id)
	var table: Dictionary = cfg(data)["pockets"]
	var spec: Dictionary = table.get(_template(data, npc), table["_default"])
	var out: Array = []
	var cp := CombatRules.roll_dice(s.rng, str(spec["coins_dice"])) * int(spec["unit_cp"])
	if cp > 0:
		out.append({"name": "Кошель", "item_id": "", "cp": cp, "qty": 1, "worn": false})
	var pool: Array = npc.get("pockets", spec.get("items", []))
	var n := mini(pool.size(), int(spec.get("item_count", 2)))
	var picked: Array = pool.duplicate()
	for i in n:
		var id := str(picked.pop_at(s.rng.randi_range(0, picked.size() - 1)))
		if data["items"]["catalog"].has(id):
			out.append({"name": ItemRules.display_name(data["items"], s.items, id), "item_id": id, "cp": 0, "qty": 1, "worn": false})
	for id: Variant in data["monsters"].get(_template(data, npc), {}).get("equipment", []):
		if data["items"]["catalog"].has(str(id)) and not data["items"]["catalog"][str(id)].has("armor"):  # no armor off a back
			out.append({"name": ItemRules.display_name(data["items"], s.items, str(id)), "item_id": str(id), "cp": 0, "qty": 1, "worn": true})
	var i := 0
	for e: Dictionary in out:
		i += 1
		e["id"] = "k%d" % i
		e["dc"] = dc(s, data, npc_id, e)
	s.pockets[npc_id] = out
	return out


static func passive(data: Dictionary, npc_id: String) -> int:
	var npc := WorldView.new(data["world"]).npc(npc_id)
	return int(data["monsters"].get(_template(data, npc), {}).get("passive_perception", 10))


## DC of one entry: the NPC's passive Perception (at least 10) + coins / item / heavy / valuable / worn modifiers.
static func dc(s: GameSession, data: Dictionary, npc_id: String, e: Dictionary) -> int:
	var mods: Dictionary = cfg(data)["dc"]
	var d := maxi(10, passive(data, npc_id))
	if str(e.get("item_id", "")).is_empty():
		return d + int(mods["coins"])
	var def := ItemRules.def_of(data["items"], s.items, str(e["item_id"]))
	d += int(mods["item"])
	if float(def.get("weight", 0)) > float(mods["heavy_weight"]):
		d += int(mods["heavy"])
	if int(def.get("value_cp", 0)) >= int(mods["valuable_cp"]):
		d += int(mods["valuable"])
	if bool(e.get("worn", false)):
		d += int(mods["worn"])
	return d


## "" when the player can pick this NPC's pockets now: the NPC is here, the player is not caught by it today.
static func can_steal(s: GameSession, data: Dictionary, npc_id: String) -> String:
	if not s.npcs_here(WorldView.new(data["world"]).world, s.room_id).has(npc_id):
		return "THEFT_NOBODY"
	if int(s.caught_by.get(npc_id, 0)) == s.day:
		return "THEFT_CAUGHT"
	if CombatRules.active(s):
		return "THEFT_NOBODY"
	return ""


## The outcome of a Sleight of Hand at one entry: success — it goes to the player; failure — the NPC reacts. Lines.
static func steal(s: GameSession, data: Dictionary, npc_id: String, entry_id: String, success: bool) -> Array[String]:
	var list: Array = pockets(s, data, npc_id)
	var who := str(WorldView.new(data["world"]).npc(npc_id).get("name", npc_id))
	var lines: Array[String] = []
	for e: Dictionary in list:
		if str(e["id"]) != entry_id:
			continue
		if not success:
			s.caught_by[npc_id] = s.day
			lines.append("%s замечает руку в кармане" % who)
			lines.append_array(react(s, data, npc_id))
			return lines
		list.erase(e)
		if int(e.get("cp", 0)) > 0:
			s.character["gold_cp"] = int(s.character["gold_cp"]) + int(e["cp"])
			lines.append("%s — украдено: %s" % [who, Money.format(int(e["cp"]))])
		else:
			var id := str(e["item_id"])
			ItemRules.found(s.character, data, s.items, id, int(e.get("qty", 1)))
			lines.append("%s — украдено: %s" % [who, e["name"]])
		return lines
	return lines


## Coins by words (a Sleight of Hand at an NPC without the window): the purse of the pockets, if any is left. cp.
static func take_purse(s: GameSession, data: Dictionary, npc_id: String) -> int:
	for e: Dictionary in pockets(s, data, npc_id):
		if int(e.get("cp", 0)) > 0:
			var cp := int(e["cp"])
			(s.pockets[npc_id] as Array).erase(e)
			s.character["gold_cp"] = int(s.character["gold_cp"]) + cp
			return cp
	return 0


## What the NPC's kind does on a caught theft or a thing taken before its eyes (rules.theft.reactions). Lines.
static func reaction_kind(data: Dictionary, npc_id: String) -> String:
	var npc := WorldView.new(data["world"]).npc(npc_id)
	var r: Dictionary = cfg(data)["reactions"]
	if bool(npc.get("trader", false)):
		return "close_shop"
	return str(r.get(_template(data, npc), r["_default"]))


static func react(s: GameSession, data: Dictionary, npc_id: String) -> Array[String]:
	var world := WorldView.new(data["world"])
	var npc := world.npc(npc_id)
	var who := str(npc.get("name", npc_id))
	var lines: Array[String] = []
	if ConditionRules.invisible(s.character, data):  # v0.7.5: felt, not seen — nobody to blame
		s.caught_by.erase(npc_id)
		lines.append("%s хватается за кошель и озирается — вора не видно" % who)
		return lines
	s.shift_attitude(npc_id, int(cfg(data)["caught_attitude"]), data)
	lines.append("%s: отношение хуже" % who)
	match reaction_kind(data, npc_id):
		"fight":
			s.pending_fight = [{"monster": _template(data, npc), "name": who, "desc": str(npc.get("description", "")), "npc_id": npc_id, "col": 0}]
			lines.append("%s хватается за оружие" % who)
		"close_shop":
			s.shop_closed[npc_id] = s.day
			lines.append("%s захлопывает лавку для вас до завтра" % who)
		_:
			var fine := int(cfg(data)["fine_cp"])
			if int(s.character["gold_cp"]) >= fine:
				s.character["gold_cp"] = int(s.character["gold_cp"]) - fine
				lines.append("%s зовёт стражу — штраф %s" % [who, Money.format(fine)])
			else:
				s.pending_fight = [{"monster": str(cfg(data)["guard_monster"]), "name": "Стражник", "desc": "Стражник Ольхового Брода с дубинкой.", "col": 1}]
				lines.append("%s зовёт стражу — платить нечем, стражник идёт с дубинкой" % who)
	return lines


## Closed for this hero: caught stealing today, or wanted in the trader's location (v0.7.14).
static func shop_closed_for(s: GameSession, npc_id: String, data: Dictionary = {}) -> bool:
	return int(s.shop_closed.get(npc_id, 0)) == s.day or (not data.is_empty() and CrimeRules.shunned_by(s, data, npc_id))
