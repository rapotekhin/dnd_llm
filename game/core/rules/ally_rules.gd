class_name AllyRules
extends RefCounted
## Allies in a fight (roadmap v0.7.22.22): fighters on the hero's side run by the engine's AI (CombatRules, side
## "ally"). Three sources, one concept: a follower (v0.7.20.3) joins the hero's fight unless the foes are the law's guard
## or the people of the follower's own location; a pack encounter brings its own `allies`; a summoning spell
## (rules.allies.summons) calls creatures that go with the hero (the part `summon` of a record in s.beings) until let go, their time runs out or the
## concentration ends. A follower at 0 HP falls unconscious and comes to after the fight; a summoned one vanishes.


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"]["allies"]


static func summon_spec(data: Dictionary, spell_id: String) -> Dictionary:
	return cfg(data)["summons"].get(spell_id, {})


## The name of what calls: a spell, or a thing whose row it is (v0.8.4.26: a Bag of Tricks).
static func source_name(data: Dictionary, key: String) -> String:
	return str(data["spells"].get(key, data["items"]["catalog"].get(key, {})).get("name", key))


## The creature a row calls: its `monster`, or one of `pick` by the session's dice (a Bag of Tricks).
static func monster_of(s: GameSession, sp: Dictionary) -> String:
	var pick: Array = sp.get("pick", [])
	return str(pick[s.rng.randi_range(0, pick.size() - 1)]) if not pick.is_empty() else str(sp.get("monster", ""))


## A row of the summons called by anybody (v0.8.4.26: one road for a spell and a thing): the hero's go with him, another's
## join its side of the fight.
static func summon_by(s: GameSession, data: Dictionary, who: Dictionary, key: String) -> Array[String]:
	return summon(s, data, key) if Sheet.is_hero(who) else CombatRules.summon_for(s, data, who, key)


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
			foe_homes.append(ReputationRules.home_of(data, str(f["npc_id"])))
	for id: String in Being.followers(s):
		if Being.dead(s, id) or s.held_as_creature(id):
			continue  # the dead do not fight, nor one lying knocked out
		var home := ReputationRules.home_of(data, id)
		if foe_npcs.has(id) or (foe_homes.has(home) and not home.is_empty()):
			continue  # not against the hero's own victim, nor against its own people
		var own := FactionRules.of_npc(s, data, id)
		if foes.any(func(f: Variant) -> bool: return f is Dictionary and not own.is_empty() and FactionRules.of_foe(data, {}, f) == own):
			continue  # nor against its own faction (v0.7.50)
		var n := world.npc(id)
		var mon := str(n.get("monster", CombatRules.cfg(data)["default_npc_monster"]))
		if data["monsters"].has(mon):
			var spec := {"monster": mon, "name": str(n.get("name", id)), "npc_id": id, "ally": "follower"}
			if Being.view(s, id).has("hp"):  # v0.7.50.1: the wounds of the last fight
				spec["hp"] = int(Being.of(s, id)["hp"])
			out.append(spec)
	for c: Dictionary in CreatureRules.here(s, s.room_id):
		if bool(c.get("ally", false)) and not foes.any(func(f: Variant) -> bool: return f is Dictionary and FactionRules.of_foe(data, {}, f) == str(c.get("faction", ""))):
			var spec := {"monster": str(c["monster"]), "name": str(c["name"]), "ally": "follower", "id": str(c["id"]), "creature_id": str(c["id"])}  # v0.7.50.1
			if c.has("hp"):
				spec["hp"] = int(c["hp"])
			out.append(spec)
	if data["rules"].has("property"):
		out.append_array(PropertyRules.fighting(s, data))  # v0.7.27: an own dog
	return out


## The location of the room an NPC of the pack lives in ("" for one the master made without a room).
## The creatures a spell called, still with the hero.
static func called(s: GameSession) -> Array[Dictionary]:
	return Being.parts(s, "summon")


## The summoned creatures still with the hero, as fighters' specs.
static func summon_specs(s: GameSession) -> Array:
	var out: Array = []
	for m: Dictionary in called(s):
		out.append({"id": str(m["id"]), "monster": str(m["monster"]), "name": str(m["name"]), "hp": int(m["hp"]), "ally": "summon", "summon_id": str(m["id"]),
			"helper": bool(m.get("helper", false)), "spell": str(m["spell"])})
	return out


## The spell calls its creatures: they go with the hero (and the fight, when there is one). Lines.
static func summon(s: GameSession, data: Dictionary, spell_id: String) -> Array[String]:
	var sp := summon_spec(data, spell_id)
	var mon := monster_of(s, sp)
	var m: Dictionary = data["monsters"].get(mon, {})
	if m.is_empty():
		return []
	if bool(sp.get("carrier", false)):
		return _carrier(s, data, spell_id, sp, m)
	var lines: Array[String] = []
	if bool(sp.get("helper", false)):  # one familiar at a time (5e): the new one replaces the old
		for x: Dictionary in called(s):
			if str(x["spell"]) == spell_id:
				Being.forget(s, str(x["id"]))
	var conc := bool(data["spells"].get(spell_id, {}).get("concentration", false))
	var until := TimeRules.abs_minute(s) + int(sp["minutes"]) if sp.has("minutes") else -1
	var count := int(sp.get("count", 1))
	var made: Array = []
	for i in count:
		var name := str(m["name"]) + (" %d" % (i + 1) if count > 1 else "")
		made.append(Being.made(s, "summon", {"spell": spell_id, "monster": mon, "name": name,
			"until": until, "concentration": conc, "hp": int(m["hp"]), "helper": bool(sp.get("helper", false))}))
	lines.append("Призваны: %s — идут с героем%s" % [", ".join(made.map(func(x: Dictionary) -> String: return str(x["name"]))),
		" до конца концентрации" if conc else " %s" % _left_text(until - TimeRules.abs_minute(s)) if until >= 0 else ", пока их не отпустят"])
	if CombatRules.active(s):
		var specs: Array = []
		for x: Dictionary in made:
			specs.append({"id": str(x["id"]), "monster": str(x["monster"]), "name": str(x["name"]), "ally": "summon", "summon_id": str(x["id"]),
				"helper": bool(x["helper"]), "spell": spell_id})
		CombatRules.add_allies(s, data, specs, true)
	return lines


static func _left_text(minutes: int) -> String:
	return "ещё %d ч" % ceili(minutes / 60.0) if minutes >= 60 else "ещё %d мин" % maxi(1, minutes)


## Summoned creatures whose time ran out or whose concentration ended go. Lines.
static func expire(s: GameSession, data: Dictionary = {}) -> Array[String]:
	var lines: Array[String] = []
	var now := TimeRules.abs_minute(s)
	var conc := str(s.character.get("concentration", ""))
	for cr: Dictionary in CreatureRules.all(s):
		if cr.has("until") and now >= int(cr["until"]) and not data.is_empty():
			lines.append("%s исчезает — время вышло" % cr["name"])
			_end_carrier(s, data, cr)
	for m: Dictionary in called(s):
		if (int(m["until"]) >= 0 and now >= int(m["until"])) or (bool(m["concentration"]) and conc != str(m["spell"])):
			lines.append("%s исчезает — %s" % [m["name"], "время вышло" if not bool(m["concentration"]) or conc == str(m["spell"]) else "концентрация прервана"])
			Being.forget(s, str(m["id"]))
	return lines


## A spell's carrier (v0.8.4.4, the author: no different from a horse): a creature of the hero, it walks with him and takes
## a pack (MountRules) until its time is out. A new casting replaces the old. Lines.
static func _carrier(s: GameSession, data: Dictionary, spell_id: String, sp: Dictionary, m: Dictionary) -> Array[String]:
	for cr: Dictionary in CreatureRules.all(s):
		if str(cr.get("spell", "")) == spell_id:
			_end_carrier(s, data, cr)
	var now := TimeRules.abs_minute(s)
	var name := source_name(data, spell_id)
	var c := {"name": name, "monster": str(sp["monster"]), "state": PropertyRules.TAME, "bound": false, "led": true, "owner": OwnerRules.HERO,
		"since": now, "hp": int(m["hp"]), "max_hp": int(m["hp"]), "xp_given": true, "fed_day": s.day, "spell": spell_id, "until": now + int(sp["minutes"])}
	if sp.has("carries_lb"):
		c["carries_lb"] = int(sp["carries_lb"])
	CreatureRules.add(s, s.room_id, c)
	return ["%s рядом с героем: идёт за ним и везёт вещи %s" % [name, _left_text(int(sp["minutes"]))]]


## Its load falls to the hero.
static func _end_carrier(s: GameSession, data: Dictionary, cr: Dictionary) -> void:
	MountRules.unload(s, data, cr)
	PropertyRules.remove_creature(s, str(cr["id"]))


## Lets a summoned creature go («Отпустить»). "" or a localization key.
static func dismiss(s: GameSession, summon_id: String) -> String:
	for m: Dictionary in called(s):
		if str(m["id"]) == summon_id:
			Being.forget(s, summon_id)
			return ""
	return "ALLY_NOT_HERE"


## An NPC's hit points now: its wounds, or the template's full ones (v0.7.50.1). {hp, max}.
static func npc_health(s: GameSession, data: Dictionary, npc_id: String) -> Dictionary:
	var mon := str(WorldView.new(data["world"]).npc(npc_id).get("monster", CombatRules.cfg(data)["default_npc_monster"]))
	var full := int(data["monsters"].get(mon, {}).get("hp", 1))
	return {"hp": mini(full, int(Being.view(s, npc_id).get("hp", full))), "max": full}


## A spell cast at an NPC out of a fight (v0.7.50.1): a heal now, or a boon that it carries into a fight until it ends.
static func cast_on_npc(s: GameSession, data: Dictionary, spell_id: String, slot: int, npc_id: String) -> Array[String]:
	var who := str(WorldView.new(data["world"]).npc_name(npc_id))
	var spell: Dictionary = data["spells"][spell_id]
	var invisible := (data["rules"]["invisibility"]["spells"] as Dictionary).has(spell_id)
	if SpellEffects.spec(data, spell_id).is_empty() and not invisible:
		var h := npc_health(s, data, npc_id)
		var after := mini(int(h["max"]), int(h["hp"]) + CombatRules.heal_roll(s, data, spell_id, slot))
		Being.drop(s, npc_id, "hp")
		if after < int(h["max"]):
			Being.of(s, npc_id)["hp"] = after
		return ["%s: +%d HP" % [who, after - int(h["hp"])]]
	var rounds := ConditionRules.spell_rounds(data, spell_id)
	var b := Being.of(s, npc_id)
	SpellEffects._end_spell_on(b, spell_id)
	ConditionRules.add_effect(b, {"source": {"kind": "spell", "id": spell_id, "name": str(spell["name"])}, "cast": slot, "keeps": true,
		"ends": {"at": ConditionRules.now(s) + rounds} if rounds > 0 else {}})
	return ["%s: %s" % [who, spell["name"]]]


## The spells cast on the followers out of a fight work as in a fight: what a spell gives is counted on the fighter.
static func buffs_into_fight(s: GameSession, data: Dictionary) -> void:
	for id: String in CombatRules.allies(s, false):
		var f := CombatRules.fighter(s, id)
		for e: Dictionary in ConditionRules.effects(f).duplicate():
			if e.has("cast"):
				ConditionRules.remove_effect(f, int(e["uid"]))
				SpellEffects.on_friend(s, data, str(e["source"]["id"]), int(e["cast"]), f, [] as Array[String])
				for laid: Dictionary in ConditionRules.effects(f):  # still the spell cast before: it outlives this fight
					if str(laid.get("source", {}).get("id", "")) == str(e["source"]["id"]):
						laid.merge({"cast": e["cast"], "keeps": true, "ends": e["ends"]}, true)


## The concentration on the spell ended: it leaves the NPCs.
static func drop_buffs(s: GameSession, spell_id: String) -> void:
	for id: String in Being.with(s, "effects"):
		SpellEffects._end_spell_on(Being.of(s, id), spell_id)
		ConditionRules.tidy(Being.of(s, id))


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
				PropertyRules.remove_creature(s, str(f["creature_id"]))
		else:
			if str(f.get("status")) == "down":
				lines.append("%s приходит в себя" % f["name"])
			if not str(f.get("npc_id", "")).is_empty():  # v0.7.50.1: a follower keeps its wounds
				Being.of(s, str(f["npc_id"]))["hp"] = maxi(1, int(f["hp"]))
				if int(f["hp"]) >= int(f["max_hp"]):
					Being.drop(s, str(f["npc_id"]), "hp")
	if not s.combat.has("arena"):
		for id: String in CombatRules.enemies(s, false):  # an NPC fought as a foe keeps its wounds too
			var f := CombatRules.fighter(s, id)
			if not str(f.get("npc_id", "")).is_empty() and str(f.get("status")) != "dead" and int(f["hp"]) < int(f["max_hp"]):
				Being.of(s, str(f["npc_id"]))["hp"] = maxi(1, int(f["hp"]))
	for id: String in hp:
		if int(hp[id]) > 0:
			Being.of(s, id)["summon"]["hp"] = int(hp[id])
		else:
			Being.forget(s, id)
	return lines


## For the master and the side panel: «Волк 1 (Призыв зверей, до конца концентрации)».
static func summon_lines(s: GameSession, data: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var now := TimeRules.abs_minute(s)
	for m: Dictionary in called(s):
		var left := "до конца концентрации" if bool(m["concentration"]) else _left_text(int(m["until"]) - now) if int(m["until"]) >= 0 else "пока не отпустят"
		out.append("%s (%s, %s)" % [m["name"], source_name(data, str(m["spell"])), left])
	return out
