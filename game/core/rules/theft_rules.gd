class_name TheftRules
extends RefCounted
## Pockets of NPCs and what happens when the player is caught (roadmap v0.7.0, decision of the author: a pockets
## window like in BG3). The pockets are a view of what the NPC has (Gear, v0.8.4.10): a handful of its purse, small
## things, worn gear. Each entry has its DC:
## the NPC's passive Perception (at least 10) + the entry's modifiers (rules.theft.dc). A Sleight of Hand at least the
## DC takes it; a failure — the NPC reacts by its kind (rules.theft.reactions): a guard fights, a trader closes the
## shop for the day, others call the guard (a fine, or a fight with the guard when the player cannot pay).


const COINS := "coins"


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"]["theft"]


## The NPC's pockets (v0.8.4.10, a view of `Gear`): [{id, name, item_id, cp, qty, worn, dc}] — a handful of its coins
## (`rules.theft.handful_cp`, `id` "coins") and its things by id, what it wears on its back left out.
static func pockets(s: GameSession, data: Dictionary, npc_id: String) -> Array:
	var c := Gear.of(s, data, npc_id)
	var tid := Sheet.template_id(data, WorldView.new(data["world"]).npc(npc_id))
	var out: Array = []
	var cp := mini(int(c.get("gold_cp", 0)), int(cfg(data)["handful_cp"]))
	if cp > 0:
		out.append({"id": COINS, "name": "Кошель", "item_id": "", "cp": cp, "qty": 1, "worn": false})
	var on: Array = (c.get("equipped", {}) as Dictionary).values()
	var items: Array = (c["inventory"] as Dictionary).keys()
	items.sort()  # one order before and after a save
	for item: String in items:
		var qty := int(c["inventory"][item]) - (1 if on.has(item) else 0)
		if qty > 0:
			out.append({"id": item, "name": ItemRules.display_name(data["items"], s.items, item), "item_id": item, "cp": 0, "qty": qty,
				"worn": Gear.worn(data, tid, item)})
	for e: Dictionary in out:
		e["dc"] = dc(s, data, npc_id, e)
	return out


static func passive(s: GameSession, data: Dictionary, npc_id: String) -> int:
	return Sheet.passive(s, data, WorldView.new(data["world"]).npc(npc_id))


## DC of one entry: the NPC's passive Perception (at least 10) + coins / item / heavy / valuable / worn modifiers.
static func dc(s: GameSession, data: Dictionary, npc_id: String, e: Dictionary) -> int:
	var mods: Dictionary = cfg(data)["dc"]
	var d := maxi(10, passive(s, data, npc_id))
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


## The check of picking one entry (engine.check params): Sleight of Hand against its DC, with advantage while sneaking.
static func check_params(s: GameSession, _data: Dictionary, npc_id: String, e: Dictionary) -> Dictionary:
	return {"skill": "sleight_of_hand", "dc_tier": "medium", "dc": int(e["dc"]), "target_id": npc_id,
		"advantage_reason": TranslationServer.translate("THEFT_HIDDEN") if s.sneaking else ""}


## The chance in percent the window shows: the roll's own spec (CheckEngine.preview).
static func chance(s: GameSession, data: Dictionary, npc_id: String, e: Dictionary) -> int:
	return int(CheckEngine.preview(s, data, check_params(s, data, npc_id, e)).get("chance", 0))


## "" when the player can pick this NPC's pockets now: the NPC is here, the player is not caught by it today.
static func can_steal(s: GameSession, data: Dictionary, npc_id: String) -> String:
	if not s.npcs_here(WorldView.new(data["world"]).world, s.room_id).has(npc_id):
		return "THEFT_NOBODY"
	if int(Being.view(s, npc_id).get("caught", 0)) == s.day:
		return "THEFT_CAUGHT"
	if CombatRules.active(s):
		return "THEFT_NOBODY"
	return ""


## The outcome of a Sleight of Hand at one entry: success — it goes to the player; failure — the NPC reacts. Lines.
static func steal(s: GameSession, data: Dictionary, npc_id: String, entry_id: String, success: bool) -> Array[String]:
	var list: Array = pockets(s, data, npc_id)
	var who := str(WorldView.new(data["world"]).npc_name(npc_id))
	var lines: Array[String] = []
	for e: Dictionary in list:
		if str(e["id"]) != entry_id:
			continue
		if not success:
			Being.of(s, npc_id)["caught"] = s.day
			lines.append("%s замечает руку в кармане" % who)
			lines.append_array(react(s, data, npc_id))
			lines.append_array(WorldEvent.deed(s, data, "pickpocket"))  # v0.7.49
			return lines
		if int(e.get("cp", 0)) > 0:
			Gear.pay(s, data, npc_id, -int(e["cp"]))
			Ledger.add(s, int(e["cp"]), "theft:steal")
			lines.append("%s — украдено: %s" % [who, Money.format(int(e["cp"]))])
		else:
			var id := str(e["item_id"])
			var n := Gear.take(s, data, npc_id, id, int(e.get("qty", 1)))
			OwnerRules.mark(s, ItemRules.found(s.character, data, s.items, id, n), n, npc_id)
			lines.append("%s — украдено: %s" % [who, e["name"]])
			if bool(e.get("worn", false)) and ItemRules.def_of(data["items"], s.items, id).has("weapon"):
				var gone: Dictionary = Being.view(s, npc_id).get("disarmed", {})  # big test #3 (v0.7.22.8): not in its hands in a fight
				gone[id] = s.day
				Being.of(s, npc_id)["disarmed"] = gone
		lines.append_array(WorldEvent.deed(s, data, "pickpocket"))  # v0.7.49: unseen, still a theft
		return lines
	return lines


## The weapons stolen from an NPC it has not replaced yet (rules.theft.rearm_days): their catalog names.
static func lost_weapons(s: GameSession, data: Dictionary, npc_id: String) -> Array[String]:
	var out: Array[String] = []
	var gone: Dictionary = Being.view(s, npc_id).get("disarmed", {})
	for id: String in gone:
		if s.day - int(gone[id]) < int(cfg(data).get("rearm_days", 3)):
			out.append(id)
	return out


## An action says which thing it is struck with (`item`, tools/srd_import.py).
static func without(actions: Array, lost: Array[String]) -> Array:
	if lost.is_empty():
		return actions
	var kept := actions.filter(func(a: Dictionary) -> bool: return not lost.has(str(a.get("item", ""))))
	if not kept.any(func(a: Dictionary) -> bool: return str(a.get("kind", "")) == "melee"):
		var best := 0
		for a: Dictionary in actions:
			best = maxi(best, int(a.get("to_hit", 0)))
		kept.append({"name": "Безоружный удар", "kind": "melee", "to_hit": best, "damage": [{"dice": "1", "type": "bludgeoning"}]})
	return kept


## Coins by words (a Sleight of Hand at an NPC without the window): a handful of its purse, if any is left. cp.
static func take_purse(s: GameSession, data: Dictionary, npc_id: String) -> int:
	var cp := mini(Gear.coins(s, data, npc_id), int(cfg(data)["handful_cp"]))
	if cp > 0:
		Gear.pay(s, data, npc_id, -cp)
		Ledger.add(s, cp, "theft:take_purse")
	return cp


## What the NPC's kind does on a caught theft or a thing taken before its eyes (rules.theft.reactions). Lines.
static func reaction_kind(data: Dictionary, npc_id: String) -> String:
	var npc := WorldView.new(data["world"]).npc(npc_id)
	var r: Dictionary = cfg(data)["reactions"]
	if bool(npc.get("trader", false)):
		return "close_shop"
	return str(r.get(Sheet.template_id(data, npc), r["_default"]))


## `memory` (with %s for the NPC's gender ending), `rep_key`, `deed` and `why` name the caught act — a theft by default,
## cheating at a game (v0.7.40).
static func react(s: GameSession, data: Dictionary, npc_id: String, memory: String = "поймал%s героя на краже из своих карманов",
		rep_key: String = "theft_caught", deed: String = "theft_caught", why: String = "кража") -> Array[String]:
	var world := WorldView.new(data["world"])
	var npc := world.npc(npc_id)
	var who := str(npc.get("name", npc_id))
	var lines: Array[String] = []
	if not WatchRules.pierces(s, data, Sheet.who(s, data, npc_id), Sheet.HERO, -1):  # v0.7.5: felt, not seen — nobody to blame
		Being.drop(s, npc_id, "caught")
		lines.append("%s хватается за кошель и озирается — вора не видно" % who)
		return lines
	s.shift_attitude(npc_id, int(cfg(data)["caught_attitude"]), data)
	s.remember(npc_id, memory % CrimeRules._ending(data, npc_id))
	lines.append("%s: отношение хуже" % who)
	lines.append_array(WorldEvent.emit(s, data, "caught", {"npc": npc_id, "victim": npc_id, "crime": "theft", "location": world.location_id(s.room_id),
		"points": rep_key, "why": why, "bond_deed": deed, "bond_why": why}))
	match reaction_kind(data, npc_id):
		"fight":
			s.pending_fight = [{"monster": Sheet.template_id(data, npc), "name": who, "desc": str(npc.get("description", "")), "npc_id": npc_id}]
			lines.append("%s хватается за оружие" % who)
		"close_shop":
			s.shop_closed[npc_id] = s.day
			lines.append("%s захлопывает лавку для вас до завтра" % who)
		_:
			var fine := int(cfg(data)["fine_cp"])
			if Ledger.balance(s) >= fine:
				Ledger.add(s, -fine, "theft:react")
				lines.append("%s зовёт стражу — штраф %s" % [who, Money.format(fine)])
			else:
				var law := CrimeRules.law(data, world.location_id(s.room_id))  # v0.7.16: the guard of the place's law
				s.pending_fight = [{"monster": str(law.get("guard_monster", cfg(data)["guard_monster"])), "name": str(law.get("guard_name", "Стражник")),
					"desc": str(law.get("guard_desc", ""))}]
				lines.append("%s зовёт стражу — платить нечем, стражник идёт с дубинкой" % who)
	return lines


## Closed for this hero: caught stealing today, or wanted in the trader's location (v0.7.14).
static func shop_closed_for(s: GameSession, npc_id: String, data: Dictionary = {}) -> bool:
	return int(s.shop_closed.get(npc_id, 0)) == s.day or (not data.is_empty() and CrimeRules.shunned_by(s, data, npc_id))
