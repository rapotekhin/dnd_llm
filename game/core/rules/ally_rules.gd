class_name AllyRules
extends RefCounted
## Allies in a fight (roadmap v0.7.22.22): fighters on the hero's side run by the engine's AI (CombatRules, side
## "ally"). Three sources, one concept: a follower (v0.7.20.3) joins the hero's fight unless the foes are the law's guard
## or the people of the follower's own location; a pack encounter brings its own `allies`; a summoning spell
## (rules.allies.summons) calls creatures that go with the hero (`s.summons`) until let go, their time runs out or the
## concentration ends. A follower at 0 HP falls unconscious and comes to after the fight; a summoned one vanishes.


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"]["allies"]


static func summon_spec(data: Dictionary, spell_id: String) -> Dictionary:
	return cfg(data)["summons"].get(spell_id, {})


## The fighters' specs of the followers who join this fight against `foes` (CombatRules.start's specs).
static func joining(s: GameSession, data: Dictionary, foes: Array) -> Array:
	var out: Array = []
	if not bool(cfg(data).get("followers_join", true)) or foes.any(func(f: Variant) -> bool: return f is Dictionary and bool(f.get("law", false))):
		return out
	var world := WorldView.new(data["world"])
	var foe_homes: Array[String] = []
	var foe_npcs: Array[String] = []
	for f: Variant in foes:
		if f is Dictionary and not str(f.get("npc_id", "")).is_empty():
			foe_npcs.append(str(f["npc_id"]))
			foe_homes.append(home_location(world, str(f["npc_id"])))
	for id: String in s.followers:
		if s.dead_npcs.has(id) or s.held_as_creature(id):
			continue  # the dead do not fight, nor one lying knocked out
		if foe_npcs.has(id) or (foe_homes.has(home_location(world, id)) and not home_location(world, id).is_empty()):
			continue  # not against the hero's own victim, nor against its own people
		var own := FactionRules.of_npc(s, data, id)
		if foes.any(func(f: Variant) -> bool: return f is Dictionary and not own.is_empty() and FactionRules.of_foe(data, {}, f) == own):
			continue  # nor against its own faction (v0.7.50)
		var n := world.npc(id)
		var mon := str(n.get("monster", CombatRules.cfg(data)["default_npc_monster"]))
		if data["monsters"].has(mon):
			var spec := {"monster": mon, "name": str(n.get("name", id)), "npc_id": id, "ally": "follower"}
			if s.npc_hp.has(id):  # v0.7.50.1: the wounds of the last fight
				spec["hp"] = int(s.npc_hp[id])
			out.append(spec)
	for c: Dictionary in CreatureRules.here(s, s.room_id):
		if bool(c.get("ally", false)) and not foes.any(func(f: Variant) -> bool: return f is Dictionary and FactionRules.of_foe(data, {}, f) == str(c.get("faction", ""))):
			var spec := {"monster": str(c["monster"]), "name": str(c["name"]), "ally": "follower", "creature_id": str(c["id"])}  # v0.7.50.1
			if c.has("hp"):
				spec["hp"] = int(c["hp"])
			out.append(spec)
	if data["rules"].has("property"):
		out.append_array(PropertyRules.fighting(s, data))  # v0.7.27: an own dog
	return out


## The location of the room an NPC of the pack lives in ("" for one the master made without a room).
static func home_location(world: WorldView, npc_id: String) -> String:
	for rid: String in world.world["rooms"]:
		if (world.room(rid).get("npcs", []) as Array).has(npc_id):
			return world.location_id(rid)
	return ""


## The summoned creatures still with the hero, as fighters' specs.
static func summon_specs(s: GameSession) -> Array:
	var out: Array = []
	for m: Dictionary in s.summons:
		out.append({"monster": str(m["monster"]), "name": str(m["name"]), "hp": int(m["hp"]), "ally": "summon", "summon_id": str(m["id"]),
			"helper": bool(m.get("helper", false)), "spell": str(m["spell"])})
	return out


## The spell calls its creatures: they join `s.summons` (and the fight, when there is one). Lines.
static func summon(s: GameSession, data: Dictionary, spell_id: String) -> Array[String]:
	var sp := summon_spec(data, spell_id)
	var m: Dictionary = data["monsters"].get(str(sp.get("monster", "")), {})
	if m.is_empty():
		return []
	var lines: Array[String] = []
	if bool(sp.get("helper", false)):  # one familiar at a time (5e): the new one replaces the old
		s.summons = s.summons.filter(func(x: Dictionary) -> bool: return str(x["spell"]) != spell_id)
	var conc := bool(data["spells"].get(spell_id, {}).get("concentration", false))
	var until := TimeRules.abs_minute(s) + int(sp["minutes"]) if sp.has("minutes") else -1
	var count := int(sp.get("count", 1))
	var made: Array = []
	for i in count:
		s.summon_counter += 1
		var name := str(m["name"]) + (" %d" % (i + 1) if count > 1 else "")
		var one := {"id": "sm%d" % s.summon_counter, "spell": spell_id, "monster": str(sp["monster"]), "name": name,
			"until": until, "concentration": conc, "hp": int(m["hp"]), "helper": bool(sp.get("helper", false))}
		s.summons.append(one)
		made.append(one)
	lines.append("Призваны: %s — идут с героем%s" % [", ".join(made.map(func(x: Dictionary) -> String: return str(x["name"]))),
		" до конца концентрации" if conc else " %s" % _left_text(until - TimeRules.abs_minute(s)) if until >= 0 else ", пока их не отпустят"])
	if CombatRules.active(s):
		var specs: Array = []
		for x: Dictionary in made:
			specs.append({"monster": str(x["monster"]), "name": str(x["name"]), "ally": "summon", "summon_id": str(x["id"]),
				"helper": bool(x["helper"]), "spell": spell_id})
		CombatRules.add_allies(s, data, specs, true)
	return lines


static func _left_text(minutes: int) -> String:
	return "ещё %d ч" % ceili(minutes / 60.0) if minutes >= 60 else "ещё %d мин" % maxi(1, minutes)


## Summoned creatures whose time ran out or whose concentration ended go. Lines.
static func expire(s: GameSession) -> Array[String]:
	var lines: Array[String] = []
	var now := TimeRules.abs_minute(s)
	var conc := str(s.character.get("concentration", ""))
	var kept: Array[Dictionary] = []
	for m: Dictionary in s.summons:
		if (int(m["until"]) >= 0 and now >= int(m["until"])) or (bool(m["concentration"]) and conc != str(m["spell"])):
			lines.append("%s исчезает — %s" % [m["name"], "время вышло" if not bool(m["concentration"]) or conc == str(m["spell"]) else "концентрация прервана"])
		else:
			kept.append(m)
	s.summons = kept
	return lines


## Lets a summoned creature go («Отпустить»). "" or a localization key.
static func dismiss(s: GameSession, summon_id: String) -> String:
	for m: Dictionary in s.summons:
		if str(m["id"]) == summon_id:
			s.summons.erase(m)
			return ""
	return "ALLY_NOT_HERE"


## An NPC's hit points now: its wounds, or the template's full ones (v0.7.50.1). {hp, max}.
static func npc_health(s: GameSession, data: Dictionary, npc_id: String) -> Dictionary:
	var mon := str(WorldView.new(data["world"]).npc(npc_id).get("monster", CombatRules.cfg(data)["default_npc_monster"]))
	var full := int(data["monsters"].get(mon, {}).get("hp", 1))
	return {"hp": mini(full, int(s.npc_hp.get(npc_id, full))), "max": full}


## A spell cast at an NPC out of a fight (v0.7.50.1): a heal now, or a boon that it carries into a fight until it ends.
static func cast_on_npc(s: GameSession, data: Dictionary, spell_id: String, slot: int, npc_id: String) -> Array[String]:
	var who := str(WorldView.new(data["world"]).npc(npc_id).get("name", npc_id))
	var spell: Dictionary = data["spells"][spell_id]
	var invisible := (data["rules"]["invisibility"]["spells"] as Dictionary).has(spell_id)
	if SpellEffects.spec(data, spell_id).is_empty() and not invisible:
		var h := npc_health(s, data, npc_id)
		var after := mini(int(h["max"]), int(h["hp"]) + CombatRules.heal_roll(s, data, spell_id, slot))
		s.npc_hp.erase(npc_id)
		if after < int(h["max"]):
			s.npc_hp[npc_id] = after
		return ["%s: +%d HP" % [who, after - int(h["hp"])]]
	var rounds := ConditionRules.spell_rounds(data, spell_id)
	var buffs: Array = s.npc_buffs.get(npc_id, [])
	buffs = buffs.filter(func(b: Dictionary) -> bool: return str(b["spell"]) != spell_id)
	buffs.append({"spell": spell_id, "slot": slot, "ends": ConditionRules.now(s) + rounds if rounds > 0 else -1})
	s.npc_buffs[npc_id] = buffs
	return ["%s: %s" % [who, spell["name"]]]


## The spells on the followers go into the fight with them.
static func buffs_into_fight(s: GameSession, data: Dictionary) -> void:
	var now := ConditionRules.now(s)
	for id: String in CombatRules.allies(s, false):
		var f := CombatRules.fighter(s, id)
		for b: Dictionary in s.npc_buffs.get(str(f.get("npc_id", "")), []):
			if int(b["ends"]) < 0 or int(b["ends"]) > now:
				SpellEffects.on_friend(s, data, str(b["spell"]), int(b["slot"]), f, [] as Array[String])


## The concentration on the spell ended: it leaves the NPCs.
static func drop_buffs(s: GameSession, spell_id: String) -> void:
	for id: String in s.npc_buffs.keys():
		s.npc_buffs[id] = (s.npc_buffs[id] as Array).filter(func(b: Dictionary) -> bool: return str(b["spell"]) != spell_id)
		if (s.npc_buffs[id] as Array).is_empty():
			s.npc_buffs.erase(id)


## A long rest heals the wounded NPCs.
static func rest(s: GameSession) -> void:
	s.npc_hp.clear()


## After the fight: the summoned keep their wounds (the fallen are gone); the followers who fell come to. Lines.
static func after_fight(s: GameSession) -> Array[String]:
	var lines: Array[String] = []
	var hp := {}
	for id: String in CombatRules.allies(s, false):
		var f := CombatRules.fighter(s, id)
		if not str(f.get("summon_id", "")).is_empty():
			hp[str(f["summon_id"])] = int(f["hp"]) if str(f["status"]) == "active" else 0
		elif not str(f.get("creature_id", "")).is_empty():  # v0.7.27: an own beast keeps its wounds or is lost
			var cr := CreatureRules.find(s, s.room_id, str(f["creature_id"]))
			if str(f["status"]) == "active":
				cr["hp"] = int(f["hp"])
			elif bool(cr.get("ally", false)):  # v0.7.50.1: one who came along falls and comes to
				cr["hp"] = 1
				lines.append("%s приходит в себя" % f["name"])
			elif not cr.is_empty():
				lines.append("%s погиб в бою" % cr["name"])
				PropertyRules._remove_creature(s, str(f["creature_id"]))
		else:
			if str(f.get("status")) == "down":
				lines.append("%s приходит в себя" % f["name"])
			if not str(f.get("npc_id", "")).is_empty():  # v0.7.50.1: a follower keeps its wounds
				s.npc_hp[str(f["npc_id"])] = maxi(1, int(f["hp"]))
				if int(f["hp"]) >= int(f["max_hp"]):
					s.npc_hp.erase(str(f["npc_id"]))
	if not s.combat.has("arena"):
		for id: String in CombatRules.enemies(s, false):  # an NPC fought as a foe keeps its wounds too
			var f := CombatRules.fighter(s, id)
			if not str(f.get("npc_id", "")).is_empty() and str(f.get("status")) != "dead" and int(f["hp"]) < int(f["max_hp"]):
				s.npc_hp[str(f["npc_id"])] = maxi(1, int(f["hp"]))
	var kept: Array[Dictionary] = []
	for m: Dictionary in s.summons:
		if not hp.has(str(m["id"])):
			kept.append(m)
		elif int(hp[str(m["id"])]) > 0:
			m["hp"] = int(hp[str(m["id"])])
			kept.append(m)
	s.summons = kept
	return lines


## For the master and the side panel: «Волк 1 (Призыв зверей, до конца концентрации)».
static func summon_lines(s: GameSession, data: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var now := TimeRules.abs_minute(s)
	for m: Dictionary in s.summons:
		var left := "до конца концентрации" if bool(m["concentration"]) else _left_text(int(m["until"]) - now) if int(m["until"]) >= 0 else "пока не отпустят"
		out.append("%s (%s, %s)" % [m["name"], data["spells"].get(str(m["spell"]), {}).get("name", m["spell"]), left])
	return out
