class_name CreatureRules
extends RefCounted
## The creatures a fight leaves in the room (roadmap v0.7.22.11, big test #11, #13): a truce, a surrender or a
## knock-out no longer wipes the foes away — they stay as creatures of the room: the part `creature` of their record in
## s.beings (v0.7.62): {id, name, monster, state: truce | surrendered | unconscious, at, bound, led, since}. The hero ties up the beaten
## (`bind`), lets them go, leads a bound one along (it moves with the hero), talks to them (a master's turn) or
## attacks them again (a fight). Left alone they go: a knocked-out one wakes and slips away, a truce lasts its hours
## (rules.creatures).
## v0.7.22.16 (the author's fixes check #21, #34): a creature keeps its HP and `xp_given` — attacked again it fights
## with its wounds and gives no XP twice; the helpless one (knocked out or bound) is finished off without a fight
## (5e: a melee blow at the helpless is a critical hit). A pack NPC knocked out lies here as a creature with its
## `npc_id` (not a person of the scene till it wakes): bound, searched, led, let go or finished off; waking or let
## go it goes home, remembers the attack and the assault is known (CrimeRules, kind `assault`).
## v0.7.22.17 (#34, #7, #10): the prisoner's branch — the table in docs/design/concepts.md «Пленник». A bound one is
## the hero's (`owner`, OwnerRules): handed to the law's guard for a bounty, sold by the master's `owner`, executed
## (the NPCs who see it think worse of the hero); someone else's creature led away or let go before its owner — a
## theft. A truce is no captivity: its creatures are talked to as equals and are not bound.


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"]["creatures"]


static func all(s: GameSession) -> Array[Dictionary]:
	return Being.parts(s, "creature")


static func here(s: GameSession, room_id: String) -> Array:
	return all(s).filter(func(c: Dictionary) -> bool: return str(c.get("at", "")) == room_id)


## A new creature of a room.
static func add(s: GameSession, room_id: String, fields: Dictionary) -> Dictionary:
	var c := fields.duplicate(true)
	c["at"] = room_id
	return Being.made(s, "creature", c)


## It leaves the rooms: a person of the pack goes back to its life, anyone else is gone.
static func remove(s: GameSession, c: Dictionary) -> void:
	var id := str(c["id"])
	Being.drop(s, id, "creature")
	if str(c.get("npc_id", "")).is_empty() or Being.view(s, id).is_empty():
		Being.forget(s, id)


static func find(s: GameSession, room_id: String, id: String) -> Dictionary:
	for c: Dictionary in here(s, room_id):
		if str(c["id"]) == id:
			return c
	return {}


## After a fight that did not kill everyone: the foes that made a truce, surrendered or were knocked out stay. Lines.
static func after_fight(s: GameSession, data: Dictionary, room_id: String) -> Array[String]:
	var lines: Array[String] = []
	for fid: String in CombatRules.enemies(s, false):
		var f := CombatRules.fighter(s, fid)
		var state := str(f.get("status", ""))
		var npc := str(f.get("npc_id", ""))
		if not state in ["truce", "surrendered", "unconscious"] or (not npc.is_empty() and state != "unconscious"):
			continue  # a pack NPC who surrendered or made peace is a person of the scene, not a creature
		var c := Being.put(s, fid, "creature", {"name": str(f["name"]), "monster": str(f["monster"]), "state": state, "at": room_id,
			"bound": false, "led": false, "since": TimeRules.abs_minute(s), "hp": int(f.get("hp", 1)), "max_hp": int(f.get("max_hp", 1)),
			"xp_given": not bool(f.get("no_xp", false)) and str(s.combat.get("outcome", "")) in ["victory", "truce"]})
		if s.combat.has("parley_won") and state != "unconscious":  # v0.7.50.1: beaten by words — they stay and no longer fight
			c["kept"] = true
			c["faction"] = FactionRules.of_foe(data, SceneRules.room(s, data["world"], room_id).get("encounter", {}), f)
		if not npc.is_empty():
			c["npc_id"] = npc
		lines.append("%s — %s" % [f["name"], state_word(state)])
	return lines


## The hero ran from a creature of the room: it stays where it was, with its new wounds.
static func after_flight(s: GameSession) -> void:
	for fid: String in CombatRules.enemies(s):
		var b := Being.view(s, fid)
		if b.has("was"):
			var f := CombatRules.fighter(s, fid)
			var c: Dictionary = b["was"]
			c["hp"] = int(f["hp"])
			c["max_hp"] = int(f["max_hp"])
			b["creature"] = c


static func state_word(state: String) -> String:
	return {"truce": "перемирие", "surrendered": "сдался", "unconscious": "без сознания", "tame": "ваше животное", "wild": "дикий, не нападает"}.get(state, state)


## «Гоблин 2 — сдался, связан, идёт с героем» — for the side panel and the master.
static func text(c: Dictionary, data: Dictionary) -> String:
	var bits: Array[String] = [state_word(str(c["state"]))]
	if bool(c.get("bound", false)):
		bits.append("связан")
	if bool(c.get("led", false)):
		bits.append("идёт с героем" if str(c["state"]) == "tame" or bool(c.get("ally", false)) else "идёт с героем на привязи")
	if not str(c.get("owner", "")).is_empty() and str(c["state"]) != "tame":
		bits.append(OwnerRules.owner_word(data, str(c["owner"])))
	if not str(c.get("serf", "")).is_empty():
		bits.append("приставлен к работе")
	return "%s — %s" % [c["name"], ", ".join(bits)]


## A prisoner: surrendered or bound — not one of a truce (v0.7.22.17, #10).
static func captive(c: Dictionary) -> bool:
	return str(c.get("state", "")) == "surrendered" or bool(c.get("bound", false))


## Someone else's: an NPC owns it — leading it away or letting it go is a theft.
static func foreign(c: Dictionary) -> bool:
	return not str(c.get("owner", "")).is_empty() and str(c["owner"]) != OwnerRules.HERO


## Beaten by words (v0.7.50.1): stays in the room and may go with the hero, fighting beside.
static func joinable(c: Dictionary) -> bool:
	return bool(c.get("kept", false)) and not bool(c.get("bound", false))


## How many go with the hero by their own will: NPCs and the creatures beaten by words.
static func companions(s: GameSession) -> int:
	return Being.followers(s).size() + here(s, s.room_id).filter(func(c: Dictionary) -> bool: return bool(c.get("ally", false))).size()


## Helpless: knocked out or bound — finished off without a fight.
static func helpless(c: Dictionary) -> bool:
	return str(c.get("state", "")) == "unconscious" or bool(c.get("bound", false))


## "" when the hero can do `what` (bind, free, lead, attack, finish, search, hand_over) with this creature now, else a
## key.
static func can(s: GameSession, id: String, what: String, data: Dictionary = {}) -> String:
	var c := find(s, s.room_id, id)
	if c.is_empty():
		return "CREATURE_NONE"
	match what:
		"attack":
			if helpless(c):
				return "CREATURE_HELPLESS"
		"finish":
			if not helpless(c):
				return "CREATURE_NOT_HELPLESS"
		"search":
			if str(c.get("npc_id", "")).is_empty() or bool(c.get("searched", false)):
				return "CREATURE_NOTHING"
		"bind":
			if bool(c.get("bound", false)) or str(c["state"]) == "truce":
				return "CREATURE_CANNOT_BIND"
		"lead":
			if not bool(c.get("bound", false)) and str(c["state"]) != "tame":  # v0.7.27: an own beast
				return "CREATURE_NOT_BOUND"
		"join":
			if not joinable(c):
				return "CREATURE_CANNOT_JOIN"
			if not bool(c.get("ally", false)) and not data.is_empty() and companions(s) >= int(FollowRules.cfg(data)["max"]):
				return "CREATURE_TOO_MANY"
		"hand_over":
			if not bool(c.get("bound", false)) or foreign(c) or not str(c.get("npc_id", "")).is_empty():
				return "CREATURE_NOT_YOUR_PRISONER"
			if data.is_empty() or CrimeRules.law(data, WorldView.new(data["world"]).location_id(s.room_id)).is_empty():
				return "CREATURE_NO_LAW"
	return ""


## Does it (can first). Lines; an attack leaves s.pending_fight.
static func act(s: GameSession, data: Dictionary, id: String, what: String) -> Array[String]:
	var c := find(s, s.room_id, id)
	match what:
		"bind":
			c["bound"] = true
			c["owner"] = OwnerRules.HERO
			c.erase("ally")
			c["led"] = false
			return ["%s связан — ваш пленник" % c["name"]]
		"join":
			var going := not bool(c.get("ally", false))
			c["led"] = going
			c.erase("ally")
			if going:
				c["ally"] = true
			return ["%s %s" % [c["name"], "идёт с вами" if going else "остаётся здесь"]]
		"lead":
			var lines: Array[String] = _taken_from_owner(s, data, c)
			c["led"] = not bool(c.get("led", false))
			lines.push_front("%s %s" % [c["name"], "идёт за вами на верёвке" if bool(c["led"]) else "остаётся здесь, связанный"])
			return lines
		"free":
			var lines: Array[String] = _taken_from_owner(s, data, c)
			lines.push_front("%s отпущен и уходит" % c["name"])
			lines.append_array(_npc_back(s, data, c))
			remove(s, c)
			return lines
		"hand_over":  # the law takes the prisoner: a bounty by its XP, the settlement thinks better of the hero
			remove(s, c)
			var cp := int(cfg(data)["bounty_cp_per_xp"]) * OwnerRules.xp_of(data, c)
			Ledger.add(s, cp, "creature:act")
			var loc := WorldView.new(data["world"]).location_id(s.room_id)
			var law := CrimeRules.law(data, loc)
			var lines: Array[String] = ["%s передан: %s%s" % [c["name"], law.get("name", "стража"), ", награда +" + Money.format(cp) if cp > 0 else ""]]
			lines.append_array(ReputationRules.add(s, data, loc, int(cfg(data)["hand_over_reputation"]), "сдал страже пленника: %s" % c["name"]))
			return lines
		"attack":
			var spec := {"id": id, "monster": str(c["monster"]), "name": str(c["name"]), "col": 0, "by_hero": true,
				"no_xp": bool(c.get("xp_given", false))}
			if c.has("hp"):
				spec["hp"] = int(c["hp"])
			if c.has("npc_id"):
				spec["npc_id"] = str(c["npc_id"])
				remove(s, c)
			else:  # it stays this record: back in the room if the hero runs
				Being.of(s, id)["was"] = c
				Being.drop(s, id, "creature")
			s.pending_fight = [spec]
			return ["Вы нападаете: %s" % c["name"]]
		"finish":  # 5e: a blow at the helpless — the killing blow, no fight and no XP (it was given)
			remove(s, c)
			var lines: Array[String] = ["Вы добиваете: %s" % c["name"]]
			if c.has("npc_id"):
				lines.append_array(CrimeRules.on_death(s, data, str(c["npc_id"]), true, s.room_id))
			elif bool(c.get("bound", false)):
				lines.append_array(_executed(s, data, c))
			return lines
		"search":
			c["searched"] = true
			return _search(s, data, str(c["npc_id"]), str(c["name"]))
	return []


## A bound prisoner killed before NPCs of the room (v0.7.22.17): each who sees it thinks worse of the hero and
## remembers. Lines.
static func _executed(s: GameSession, data: Dictionary, c: Dictionary) -> Array[String]:
	if ConditionRules.invisible(s.character, data):
		return []
	var world := WorldView.new(data["world"])
	var seen := WatchRules.eyes(s, data, s.npcs_here(world.world, s.room_id))
	for npc: String in seen:
		s.shift_attitude(npc, int(cfg(data)["execute_attitude"]), data)
		s.remember(npc, "герой убил связанного пленника: %s" % c["name"])
	if seen.is_empty():
		return []
	return ["%s видят казнь связанного пленника: отношение хуже" % ", ".join(seen.map(func(n: String) -> String: return str(world.npc(n).get("name", n))))]


## Someone else's creature led away or let go (v0.7.22.17, #7): it is now the hero's; its owner here sees a theft.
static func _taken_from_owner(s: GameSession, data: Dictionary, c: Dictionary) -> Array[String]:
	if not foreign(c):
		return []
	var owner := str(c["owner"])
	c["owner"] = OwnerRules.HERO
	if WatchRules.sees_hero(s, data, owner) and not ConditionRules.invisible(s.character, data):
		return TheftRules.react(s, data, owner)
	return []


## A knocked-out pack NPC searched: what its pockets hold; whoever sees it — a theft before their eyes. Lines.
static func _search(s: GameSession, data: Dictionary, npc_id: String, name: String) -> Array[String]:
	var got: Array[String] = []
	for e: Dictionary in TheftRules.pockets(s, data, npc_id):
		if int(e.get("cp", 0)) > 0:
			Ledger.add(s, int(e["cp"]), "creature:search")
			got.append(Money.format(int(e["cp"])))
		elif not str(e.get("item_id", "")).is_empty() and not bool(e.get("worn", false)):
			OwnerRules.mark(s, ItemRules.found(s.character, data, s.items, str(e["item_id"]), int(e.get("qty", 1))), int(e.get("qty", 1)), npc_id)
			got.append(str(e["name"]))
	Being.of(s, npc_id)["pockets"] = (TheftRules.pockets(s, data, npc_id) as Array).filter(func(e: Dictionary) -> bool: return bool(e.get("worn", false)))
	var lines: Array[String] = ["Обыскан(а) %s: %s" % [name, ", ".join(got) if not got.is_empty() else "ничего"]]
	var world := WorldView.new(data["world"])
	var seen := WatchRules.eyes(s, data, s.npcs_here(world.world, s.room_id))
	if not seen.is_empty() and not ConditionRules.invisible(s.character, data):
		s.shift_attitude(seen[0], int(data["rules"]["theft"]["caught_attitude"]), data)
		lines.append("%s видит, как вы обираете беспомощного: отношение хуже" % world.npc(seen[0]).get("name", seen[0]))
	return lines


## A pack NPC that was a creature comes back to its life (woke up or let go): it goes home, remembers the attack,
## and the assault is known (v0.7.22.16). Lines.
static func _npc_back(s: GameSession, data: Dictionary, c: Dictionary) -> Array[String]:
	var npc := str(c.get("npc_id", ""))
	if npc.is_empty():
		return []
	Being.drop(s, npc, "at")
	Being.unfollow(s, npc)
	s.shift_attitude(npc, int(cfg(data)["woken_attitude"]), data)
	s.remember(npc, "герой напал на меня и оставил без сознания")
	return CrimeRules.assault_known(s, data, npc)


## The led ones go with the hero from `from` to `to`.
static func follow(s: GameSession, from: String, to: String) -> void:
	if from == to:
		return
	for c: Dictionary in here(s, from):
		if bool(c.get("led", false)):
			c["at"] = to


## Time passes: an unbound knocked-out one wakes and slips away, an unbound surrendered one runs, a truce ends —
## each after its rules.creatures minutes. Lines only for the hero's room.
static func tick(s: GameSession, data: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var now := TimeRules.abs_minute(s)
	var leave: Dictionary = cfg(data)["leave_minutes"]
	for c: Dictionary in all(s):
		var limit := int(leave.get(str(c["state"]), 0))
		if bool(c.get("bound", false)) or bool(c.get("kept", false)) or limit <= 0 or now - int(c["since"]) < limit:
			continue
		if str(c["at"]) == s.room_id:
			lines.append("%s %s" % [c["name"], "приходит в себя и уходит" if str(c["state"]) == "unconscious" else "уходит"])
		lines.append_array(_npc_back(s, data, c))
		remove(s, c)
	return lines


## For the master: [«Гоблин 2 [c3] — сдался, связан»]; a truce says it is no captivity (v0.7.22.17, #10).
static func snapshot(s: GameSession, data: Dictionary, room_id: String) -> Array[String]:
	var out: Array[String] = []
	for c: Dictionary in here(s, room_id):
		var extra := " — не пленник: свободен, не связан, при оружии, говорит на равных" if str(c["state"]) == "truce" else ""
		if bool(c.get("kept", false)) and str(c["state"]) != "truce":
			extra = " — запуган, больше не враждебен" + ("" if bool(c.get("bound", false)) else ", не связан")
		if bool(c.get("pet", false)):  # v0.7.43
			extra = " — питомец героя: " + PetRules.text(data, c)
		elif PetRules.tameable(data, str(c["monster"])) and str(c["state"]) in ["wild", "truce", "surrendered"]:
			extra += " — можно приручить (кнопка «Приручить»)"
		out.append("%s [%s]%s" % [text(c, data), c["id"], extra])
	return out
