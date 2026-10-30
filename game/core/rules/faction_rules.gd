class_name FactionRules
extends RefCounted
## Factions (roadmap v0.7.50, the author's idea): every NPC and every foe belongs to one — the wild beasts of the whole
## world, a cave's kobolds, the Night Rats, the people of Brod, a wizard's household. A faction is data: of the pack
## (`world.factions`), of the master (`generated.factions`), or an organization (each org is a faction of its id).
## The hero's standing (s.factions {id: {pts, met_day, rest, why}}) moves by the engine's facts (rules.factions.sources)
## and by a share of the bond with a member; a settlement's faction keeps no counter of its own — it is the
## location's reputation (ReputationRules), `settlement_scale` points of standing to one of reputation.
## Friendly: its foes do not fight the hero (a truce at the meeting, a quest's fight step passed unless `defeat`), its
## private places are open, an org's hideout free. Its members think better of a stranger. An enemy is not talked to.


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"]["factions"]


## All factions: the pack's, every organization, the master's.
static func all(s: GameSession, data: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for id: String in OrgRules.all(s, data):
		var o: Dictionary = OrgRules.all(s, data)[id]
		out[id] = {"name": str(o.get("name", id)), "kind": "org", "scope": "global", "description": str(o.get("description", "")), "hostile": false, "head": str(o.get("head", ""))}
	out.merge(data["world"].get("factions", {}), true)
	out.merge(WorldGen.generated(s).get("factions", {}), true)
	return out


static func def(s: GameSession, data: Dictionary, id: String) -> Dictionary:
	return all(s, data).get(id, {})


## The faction of an NPC: its own, or the folk of its home location (a person made before v0.7.50).
static func of_npc(s: GameSession, data: Dictionary, npc_id: String) -> String:
	var own := str(data["world"]["npcs"].get(npc_id, {}).get("faction", ""))
	if not own.is_empty():
		return own
	return folk_of(s, data, ReputationRules.home_of(data, npc_id))


## The faction of the people of a location: the settlement's, or the wild folk (rules.factions.folk).
static func folk_of(s: GameSession, data: Dictionary, loc: String) -> String:
	var all_f := all(s, data)
	for id: String in all_f:
		if str(all_f[id].get("kind", "")) == "settlement" and str(all_f[id].get("location", "")) == loc:
			return id
	return str(cfg(data).get("folk", ""))


## The faction of a foe: the enemy's own, the encounter's, or by the monster's SRD type (rules.factions.by_type).
static func of_foe(data: Dictionary, enc: Dictionary, e: Dictionary) -> String:
	var own := str(e.get("faction", enc.get("faction", "")))
	if not own.is_empty():
		return own
	var type := str(data["monsters"].get(str(e.get("monster", "")), {}).get("type", ""))
	return str(cfg(data)["by_type"].get(type, ""))


## The standing −100…100: a settlement's by its reputation, an org's member is at least an ally.
static func points(s: GameSession, data: Dictionary, id: String) -> int:
	var d := def(s, data, id)
	if str(d.get("kind", "")) == "settlement":
		return clampi(ReputationRules.points(s, str(d.get("location", ""))) * int(cfg(data)["settlement_scale"]), -100, 100)
	var pts := int(s.factions.get(id, {}).get("pts", int(d.get("start", 0))))
	if OrgRules.member(s.character, id):
		pts = maxi(pts, _step_at(data, "allied"))
	return pts


static func _step_at(data: Dictionary, step_id: String) -> int:
	for st: Dictionary in cfg(data)["steps"]:
		if str(st["id"]) == step_id:
			return int(st["at"])
	return 0


## The step of the standing: {id, at, name}.
static func step(s: GameSession, data: Dictionary, id: String) -> Dictionary:
	var pts := points(s, data, id)
	var out: Dictionary = cfg(data)["steps"][0]
	for st: Dictionary in cfg(data)["steps"]:
		if pts >= int(st["at"]):
			out = st
	return out


static func friendly(s: GameSession, data: Dictionary, id: String) -> bool:
	return not id.is_empty() and has(s, data, id) and points(s, data, id) >= _step_at(data, "friendly")


static func enemy(s: GameSession, data: Dictionary, id: String) -> bool:
	return not id.is_empty() and has(s, data, id) and str(step(s, data, id)["id"]) == "enemy"


static func has(s: GameSession, data: Dictionary, id: String) -> bool:
	return all(s, data).has(id)


## The hero has now seen this faction: it goes to the journal.
static func meet(s: GameSession, data: Dictionary, id: String) -> void:
	if not has(s, data, id):
		return
	var e: Dictionary = s.factions.get(id, {})
	if not e.has("met_day"):
		e["met_day"] = s.day
		s.factions[id] = e


## Moves the standing. A settlement's goes into its reputation, what is less than a point of it stays in `rest`.
## Lines: only a new step.
static func add(s: GameSession, data: Dictionary, id: String, delta: int, why: String) -> Array[String]:
	var d := def(s, data, id)
	if d.is_empty() or delta == 0 or (delta > 0 and not bool(d.get("friendable", true))):
		return []
	var before := str(step(s, data, id)["id"])
	var e: Dictionary = s.factions.get(id, {"pts": int(d.get("start", 0))})
	var lines: Array[String] = []
	if str(d.get("kind", "")) == "settlement":
		var scale := int(cfg(data)["settlement_scale"])
		var rest := int(e.get("rest", 0)) + delta
		var whole := int(float(rest) / scale)
		e["rest"] = rest - whole * scale
		if whole != 0:
			lines.append_array(ReputationRules.add(s, data, str(d.get("location", "")), whole, why, false))
	else:
		e["pts"] = clampi(int(e.get("pts", 0)) + delta, -100, 100)
	if not e.has("met_day"):
		e["met_day"] = s.day
	if not why.is_empty():
		var w: Array = e.get("why", [])
		w.append("%s%d: %s" % ["+" if delta > 0 else "−", absi(delta), why])
		e["why"] = w.slice(maxi(0, w.size() - int(cfg(data)["why_kept"])))
	s.factions[id] = e
	ReputationRules.refresh(s, data)
	if str(step(s, data, id)["id"]) != before:
		lines.append("%s: %s" % [str(d["name"]), str(step(s, data, id)["name"])])
	return lines


## A fact of the engine by its name in rules.factions.sources. Lines.
static func on_source(s: GameSession, data: Dictionary, id: String, source: String, why: String) -> Array[String]:
	if str(def(s, data, id).get("kind", "")) == "settlement":
		return []  # its reputation counts these facts by itself
	return add(s, data, id, int(cfg(data)["sources"].get(source, 0)), why)


## A share of a bond's change goes to the member's faction; its head counts more. Lines.
static func on_bond(s: GameSession, data: Dictionary, npc_id: String, delta: int) -> Array[String]:
	var id := of_npc(s, data, npc_id)
	if id.is_empty() or str(def(s, data, id).get("kind", "")) == "settlement":
		return []  # a settlement's standing is its reputation: one person's friendship does not make a town's
	var share := float(cfg(data)["bond_share"])
	if str(def(s, data, id).get("head", "")) == npc_id:
		share *= float(cfg(data)["head_factor"])
	return add(s, data, id, int(delta * share), BondRules.npc_name(s, data, npc_id))


## A crime became known, or a theft was caught: its victim's faction learns of it. Lines.
static func on_crime(s: GameSession, data: Dictionary, victim: String, kind: String) -> Array[String]:
	if victim.is_empty() or not data["world"]["npcs"].has(victim):
		return []
	return on_source(s, data, of_npc(s, data, victim), kind, BondRules.npc_name(s, data, victim))


## A fight won: the factions of the foes think worse of the hero, wild beasts do not mind a fair fight. Foes who
## were friends and fell: the encounter is beaten after all (a quest's `defeat` step). Lines.
static func after_fight(s: GameSession, data: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var seen: Array[String] = []
	var enc: Dictionary = SceneRules.room(s, data["world"], s.room_id).get("encounter", {})
	for fid: String in CombatRules.enemies(s, false):
		var id := of_foe(data, enc, CombatRules.fighter(s, fid))
		if id.is_empty() or seen.has(id) or (cfg(data)["no_fight_minus"] as Array).has(str(def(s, data, id).get("kind", ""))):
			continue
		seen.append(id)
		lines.append_array(on_source(s, data, id, "fight", "бой"))
	if str(s.combat.get("encounter", "")).is_empty() and s.encounters_peace.has(str(enc.get("id", ""))) and not s.encounters_done.has(str(enc["id"])):
		s.encounters_done.append(str(enc["id"]))
	return lines


## Whether the foes of an encounter let the hero be: each is of a friendly faction, or of one that attacks only
## its enemies (`hostile` false) while the hero is not.
static func peaceful(s: GameSession, data: Dictionary, enc: Dictionary) -> bool:
	var foes: Array = enc.get("enemies", [])
	if foes.is_empty():
		return false
	for e: Dictionary in foes:
		var id := of_foe(data, enc, e)
		if not has(s, data, id):
			return false
		var bad := bool(def(s, data, id).get("hostile", true)) or str(step(s, data, id)["id"]) in ["enemy", "unfriendly"]
		if bad and not friendly(s, data, id):
			return false
	return true


## The hero comes among the foes of a friendly faction: they stand by as a truce; a quest's step passes unless it
## says `defeat`. The line.
static func keep_peace(s: GameSession, data: Dictionary, room_id: String, enc: Dictionary) -> String:
	var id := str(enc["id"])
	s.encounters_peace.append(id)
	if not s.encounters_passed.has(id):
		s.encounters_passed.append(id)
	EncounterRules.as_creatures(s, room_id, enc["enemies"], "truce")
	var names: Array = []
	for e: Dictionary in enc["enemies"]:
		var n := str(def(s, data, of_foe(data, enc, e)).get("name", ""))
		meet(s, data, of_foe(data, enc, e))
		if not n.is_empty() and not names.has(n):
			names.append(n)
	return "Вас не трогают: %s — свои" % ", ".join(names)


## Whether the owner's private places are open to the hero: its faction is friendly and of a kind that opens them.
static func welcome(s: GameSession, data: Dictionary, npc_id: String) -> bool:
	var id := of_npc(s, data, npc_id)
	return friendly(s, data, id) and not (cfg(data)["no_private"] as Array).has(str(def(s, data, id).get("kind", "")))


## The attitude a member of the NPC's faction starts with (ReputationRules.refresh); a settlement's is its reputation.
static func attitude_bonus(s: GameSession, data: Dictionary, npc_id: String) -> int:
	var id := of_npc(s, data, npc_id)
	if id.is_empty() or str(def(s, data, id).get("kind", "")) == "settlement":
		return 0
	return int(step(s, data, id).get("attitude", 0))


## The factions the hero met, for the journal and the master: [{id, name, kind, step, pts, description, why, members}].
static func met(s: GameSession, data: Dictionary, known: Array = []) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: String in s.factions:
		if s.factions[id].has("met_day") and has(s, data, id):
			out.append(card(s, data, id, known))
	return out


static func card(s: GameSession, data: Dictionary, id: String, known: Array = []) -> Dictionary:
	var d := def(s, data, id)
	var people: Array[String] = []
	for npc: String in data["world"]["npcs"]:
		if str(data["world"]["npcs"][npc].get("faction", "")) == id and known.has(npc):
			people.append(BondRules.npc_name(s, data, npc))
	var st := step(s, data, id)
	return {"id": id, "name": str(d.get("name", id)), "kind": str(d.get("kind", "")), "step": str(st["name"]), "step_id": str(st["id"]), "pts": points(s, data, id),
		"description": str(d.get("description", "")), "why": s.factions.get(id, {}).get("why", []), "members": people}


# --- the master ---------------------------------------------------------------------------------------------------


## The master's `faction`: a new one (`create`) or the standing for a deed (`faction_id`, `delta`, `why`; once a day
## per faction, within rules.factions.master_max). {plan, summary} or {reason}.
static func make(s: GameSession, data: Dictionary, e: Dictionary) -> Dictionary:
	if e.get("create") is Dictionary:
		return _plan_create(s, data, e["create"])
	var id := str(e.get("faction_id", ""))
	if not has(s, data, id):
		return {"reason": "нет фракции %s — возьми id из списка или создай её (`create`)" % id}
	var delta := int(e.get("delta", 0))
	var most := int(cfg(data)["master_max"])
	if delta == 0 or absi(delta) > most:
		return {"reason": "delta — от −%d до +%d, не ноль" % [most, most]}
	if str(e.get("why", "")).strip_edges().is_empty():
		return {"reason": "нужно why — за какой поступок"}
	if int(s.factions.get(id, {}).get("master_day", -1)) == s.day:
		return {"reason": "отношение %s уже менялось сегодня" % str(def(s, data, id)["name"])}
	return {"plan": {"id": id, "delta": delta, "why": str(e["why"]).left(80)}, "summary": "%s: отношение %+d" % [str(def(s, data, id)["name"]), delta]}


static func _plan_create(s: GameSession, data: Dictionary, c: Dictionary) -> Dictionary:
	var name := str(c.get("name", "")).strip_edges().left(40)
	if name.is_empty():
		return {"reason": "нужно create.name — как зовётся фракция"}
	var kind := str(c.get("kind", "people"))
	if not (cfg(data)["kinds"] as Array).has(kind):
		return {"reason": "create.kind — одно из %s" % ", ".join(cfg(data)["kinds"])}
	var all_f := all(s, data)
	for id: String in all_f:
		if str(all_f[id].get("name", "")).to_lower() == name.to_lower():
			return {"reason": "фракция «%s» уже есть: %s — возьми её" % [name, id]}
	var scope := str(c.get("scope", "here"))
	var world := WorldView.new(data["world"])
	var d := {"name": name, "kind": kind, "description": str(c.get("description", "")).left(240), "hostile": bool(c.get("hostile", true)), "generated": true,
		"scope": "global" if scope == "global" else [world.location_id(s.room_id)]}
	return {"plan": {"create": "gen_f_" + name.to_lower().md5_text().left(8), "def": d}, "summary": "Фракция: %s" % name}


static func apply_make(s: GameSession, data: Dictionary, plan: Dictionary) -> Array[String]:
	if plan.has("create"):
		var gen := WorldGen.generated(s)
		var list: Dictionary = gen.get("factions", {})
		list[str(plan["create"])] = (plan["def"] as Dictionary).duplicate(true)
		gen["factions"] = list
		return []
	var id := str(plan["id"])
	var lines := add(s, data, id, int(plan["delta"]), str(plan["why"]))
	(s.factions[id] as Dictionary)["master_day"] = s.day
	return lines


## The faction the master named for a person or foes: a known id or name; a new name is a new local faction there and
## then (an empty one, if its turn is dropped, is never met). "" — none named.
static func ensure(s: GameSession, data: Dictionary, name: String, kind: String, hostile: bool) -> String:
	var n := name.strip_edges()
	if n.is_empty() or has(s, data, n):
		return n
	var all_f := all(s, data)
	for id: String in all_f:
		if str(all_f[id].get("name", "")).to_lower() == n.to_lower():
			return id
	var plan := _plan_create(s, data, {"name": n, "kind": kind, "hostile": hostile})
	apply_make(s, data, plan["plan"])
	return str(plan["plan"]["create"])


## The master's frame: the factions of the people and foes here and those the hero met.
static func snapshot(s: GameSession, data: Dictionary, room_id: String) -> Array[String]:
	var ids: Array[String] = []
	for npc: String in s.npcs_here(data["world"], room_id):
		var f := of_npc(s, data, npc)
		if not f.is_empty() and not ids.has(f):
			ids.append(f)
	for id: String in s.factions:
		if s.factions[id].has("met_day") and not ids.has(id):
			ids.append(id)
	var out: Array[String] = []
	for id: String in ids:
		if has(s, data, id):
			out.append("%s (%s, %s): %s" % [str(def(s, data, id)["name"]), id, str(def(s, data, id).get("kind", "")), str(step(s, data, id)["name"])])
	return out
