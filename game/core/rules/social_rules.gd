class_name SocialRules
extends RefCounted
## Social checks by the NPC's SRD template (roadmap v0.7.15.1, «Социальный режим 2.0»): the DC of Deception,
## Intimidation, Persuasion and Insight against a pack NPC comes from what the NPC is, not only from the master.
## - against: 5e contests — a lie meets the NPC's Insight, a threat its Wisdom save, a plea its Wisdom (how set
##   in its ways), reading it — its Deception (rules.social.contests);
## - DC = 10 + the NPC's bonus + how big the ask is: the master's tier counts from `tier_base` (easy — a bare
##   contest, medium +5, hard +10…);
## - attitude: a friendly NPC is easier to persuade and to fool, a hostile one harder (`attitude_step` a step);
## - the DC stays within [dc_min, dc_max]. The master never sends a number (ADR-0008 §2).


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"]["social"]


static func _mod(score: int) -> int:
	return floori((score - 10) / 2.0)


## The NPC's bonus against `skill` and its name: {bonus, why}, or {} when the skill is not a social one.
static func resistance(data: Dictionary, npc: Dictionary, skill: String) -> Dictionary:
	var against := str(cfg(data)["contests"].get(skill, ""))
	if against.is_empty():
		return {}
	var m: Dictionary = data["monsters"].get(str(npc.get("monster", CombatRules.cfg(data)["default_npc_monster"])), {})
	var ab: Dictionary = m.get("abilities", {})
	var sk: Dictionary = m.get("skills", {})
	match against:
		"insight":
			return {"bonus": int(sk.get("insight", _mod(int(ab.get("wis", 10))))), "why": "Проницательность"}
		"deception":
			return {"bonus": int(sk.get("deception", _mod(int(ab.get("cha", 10))))), "why": "Обман"}
		"wis_save":
			return {"bonus": int(m.get("saves", {}).get("wis", _mod(int(ab.get("wis", 10))))), "why": "спасбросок Мудрости"}
	return {"bonus": _mod(int(ab.get("wis", 10))), "why": "Мудрость"}


## The engine's DC for a social check against `npc_id`: {dc, reason}, or {} when the engine's tier stays.
static func dc(s: GameSession, data: Dictionary, npc_id: String, skill: String, tier: String) -> Dictionary:
	var npc: Dictionary = data["world"]["npcs"].get(npc_id, {})
	if npc.is_empty() or not (data["rules"]["dc_tiers"] as Dictionary).has(tier):
		return {}
	var r := resistance(data, npc, skill)
	if r.is_empty():
		return {}
	var c := cfg(data)
	var ask := int(data["rules"]["dc_tiers"][tier]) - int(data["rules"]["dc_tiers"][str(c["tier_base"])])
	var d := 10 + int(r["bonus"]) + ask
	var parts: Array[String] = ["%s %s %+d" % [r["why"], npc.get("name", npc_id), int(r["bonus"])]]
	if ask != 0:
		parts.append("просьба %+d" % ask)
	if (c["attitude_skills"] as Array).has(skill) and s.attitude(npc_id) != 0:
		var shift := -s.attitude(npc_id) * int(c["attitude_step"])
		d += shift
		parts.append("отношение %+d" % shift)
	return {"dc": clampi(d, int(c["dc_min"]), int(c["dc_max"])), "reason": ", ".join(parts)}
