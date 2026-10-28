class_name DiseaseRules
extends RefCounted
## Diseases of the hero (roadmap v0.7.23.1, rules.diseases): caught on a failed CON save (a bite, foul water or food,
## a sick NPC, the master), hidden while incubating (c["diseases"]: [{id, onset}] — absolute minutes), then shown
## for `days` as effects of the tag `disease` with one «Болезнь: …» effect carrying `disease` (the chip, the max HP,
## the hampered saves) and passing by the clock. Herbs cure the diseases marked `herbs`, magic cures any.

const DAY_ROUNDS := 1440 * ConditionRules.ROUNDS_PER_MINUTE


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"]["diseases"]


## Every disease the game knows: the rules', the pack's (world.json `diseases`), the master's made ones.
static func all(s: GameSession, data: Dictionary) -> Dictionary:
	var out: Dictionary = (cfg(data)["catalog"] as Dictionary).duplicate()
	out.merge(data["world"].get("diseases", {}), true)
	if s != null:
		out.merge(WorldGen.generated(s).get("diseases", {}), true)
	return out


static func def_of(s: GameSession, data: Dictionary, id: String) -> Dictionary:
	return all(s, data).get(id, {})


## A disease by its id or Russian name ("" — none).
static func find(s: GameSession, data: Dictionary, key: String) -> String:
	var known := all(s, data)
	var k := key.strip_edges().to_lower()
	if known.has(k):
		return k
	for id: String in known:
		if str(known[id].get("name", "")).to_lower() == k:
			return id
	return ""


static func incubating(c: Dictionary) -> Array:
	if not (c.get("diseases") is Array):
		c["diseases"] = []
	return c["diseases"]


## The ids of the diseases showing now.
static func active(c: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for e: Dictionary in ConditionRules.effects(c):
		if e.has("disease") and not out.has(str(e["disease"])):
			out.append(str(e["disease"]))
	return out


static func sick(c: Dictionary, id: String) -> bool:
	return active(c).has(id) or incubating(c).any(func(d: Dictionary) -> bool: return str(d.get("id", "")) == id)


## A save against catching `id` (DC `dc`); a failure starts its incubation. `why` names what threatened. Lines —
## the save, never the disease: the player learns it when it shows.
static func expose(s: GameSession, data: Dictionary, id: String, dc: int, why: String) -> Array[String]:
	var c := s.character
	if def_of(s, data, id).is_empty() or sick(c, id):
		return []
	var immune := HeroDefense.immune(c, data, "", "disease")
	if not immune.is_empty():
		return ["%s: зараза не берёт — %s" % [why, immune]]
	var r := HeroDefense.save(s, data, str(cfg(data).get("save", "con")), dc, "disease")
	if bool(r["ok"]):
		return ["%s: спасбросок %s" % [why, r["text"]]]
	var lines: Array[String] = ["%s: спасбросок %s" % [why, r["text"]]]
	lines.append_array(contract(s, data, id))
	return lines


## The hero has caught `id` (the save already failed): its incubation starts. Lines (only when it shows at once).
static func contract(s: GameSession, data: Dictionary, id: String) -> Array[String]:
	var c := s.character
	var d := def_of(s, data, id)
	if d.is_empty() or sick(c, id) or not HeroDefense.immune(c, data, "", "disease").is_empty():
		return []
	incubating(c).append({"id": id, "onset": TimeRules.abs_minute(s) + int(d.get("incubation_hours", 0)) * 60})
	return tick(s, data)


## After time passed: the incubated diseases show. Lines.
static func tick(s: GameSession, data: Dictionary) -> Array[String]:
	var c := s.character
	var lines: Array[String] = []
	var now := TimeRules.abs_minute(s)
	for d: Dictionary in incubating(c).duplicate():
		if now >= int(d.get("onset", 0)):
			incubating(c).erase(d)
			lines.append_array(_show(s, data, str(d["id"])))
	_npc_tick(s, data)
	return lines


# --- sick NPCs (v0.7.39) ------------------------------------------------------------------------------------------


## The disease an NPC has now: its own course in the session, else the pack's `sick`. "" — healthy.
static func npc_disease(s: GameSession, data: Dictionary, npc_id: String) -> String:
	if s.npc_sick.has(npc_id):
		return str(s.npc_sick[npc_id].get("id", ""))
	return str(data["world"]["npcs"].get(npc_id, {}).get("sick", ""))


## A pack's sick NPC starts its course (the disease's `days` from now); a course run out heals it. Silent: the hero
## sees a healthy NPC when they meet.
static func _npc_tick(s: GameSession, data: Dictionary) -> void:
	for npc_id: String in data["world"]["npcs"]:
		var id := str(data["world"]["npcs"][npc_id].get("sick", ""))
		if not id.is_empty() and not s.npc_sick.has(npc_id):
			s.npc_sick[npc_id] = {"id": id, "until": s.day + maxi(1, int(def_of(s, data, id).get("days", 1)))}
	for npc_id: String in s.npc_sick:
		var ns: Dictionary = s.npc_sick[npc_id]
		if not str(ns.get("id", "")).is_empty() and s.day >= int(ns.get("until", 0)):
			ns["id"] = ""


## Whether `power` ("magic" — any, "herbs" — those marked `herbs`) cures the NPC's disease.
static func npc_curable(s: GameSession, data: Dictionary, npc_id: String, power: String) -> bool:
	var id := npc_disease(s, data, npc_id)
	return not id.is_empty() and (power == "magic" or bool(def_of(s, data, id).get("herbs", false)))


## The hero cures a sick NPC: a spell cast at them, a remedy given. Lines.
static func cure_npc(s: GameSession, data: Dictionary, npc_id: String, power: String) -> Array[String]:
	var id := npc_disease(s, data, npc_id)
	if id.is_empty():
		return []
	var who := str(WorldView.new(data["world"]).npc(npc_id).get("name", npc_id))
	if not npc_curable(s, data, npc_id, power):
		return ["%s: травы не берут — %s" % [who, def_of(s, data, id).get("name", id)]]
	s.npc_sick[npc_id] = {"id": "", "until": s.day}
	return ["%s исцелён: %s" % [who, def_of(s, data, id).get("name", id)]]


static func _show(s: GameSession, data: Dictionary, id: String) -> Array[String]:
	var c := s.character
	var d := def_of(s, data, id)
	var source := {"kind": "disease", "id": id, "name": "Болезнь: " + str(d.get("name", id))}
	var ends := {"at": ConditionRules.now(s) + int(d.get("days", 1)) * DAY_ROUNDS}
	var main := {"condition": "", "disease": id, "tag": "disease", "source": source, "ends": ends}
	if int(d.get("max_hp", 0)) != 0:
		main["max_hp"] = int(d["max_hp"])
	if d.get("saves") is Dictionary and not (d["saves"] as Dictionary).is_empty():
		main["saves"] = (d["saves"] as Dictionary).duplicate()
	ConditionRules.add_effect(c, main)
	var lines: Array[String] = ["Проявилась болезнь: %s (%d дн.)" % [d.get("name", id), int(d.get("days", 1))]]
	for cond: Variant in d.get("conditions", []):
		lines.append_array(ConditionRules.impose(s, data, {"condition": str(cond), "tag": "disease", "source": source, "ends": ends}))
	if NeedRules.on(s) and data["rules"].has("needs"):
		for need: String in d.get("needs", {}):
			NeedRules.set_value(s, data, need, NeedRules.value(s, data, need) + float(d["needs"][need]))
	CharacterRules.refresh(c, data, s.items)
	c["hp"] = mini(int(c["hp"]), int(c["max_hp"]))
	return lines


## The diseases (incubating or showing) that `power` cures: "magic" — any, "herbs" — those marked `herbs`.
static func curable(s: GameSession, data: Dictionary, power: String) -> Array[String]:
	var out: Array[String] = []
	var ids: Array[String] = active(s.character)
	for d: Dictionary in incubating(s.character):
		ids.append(str(d["id"]))
	for id: String in ids:
		if not out.has(id) and (power == "magic" or bool(def_of(s, data, id).get("herbs", false))):
			out.append(id)
	return out


## Cures what `power` can. Lines: what went, and what herbs could not take.
static func cure(s: GameSession, data: Dictionary, power: String) -> Array[String]:
	var c := s.character
	var lines: Array[String] = []
	var ids := curable(s, data, power)
	for id: String in ids:
		_drop(c, id)
		lines.append("исцелено: %s" % def_of(s, data, id).get("name", id))
	for id: String in active(c):
		lines.append("травы не берут: %s" % def_of(s, data, id).get("name", id))
	CharacterRules.refresh(c, data, s.items)
	return lines


## Magic without the session (Lay on Hands from FeatureUses): every disease goes. Whether there was one.
static func cure_all(c: Dictionary) -> bool:
	var had := not active(c).is_empty() or not incubating(c).is_empty()
	for id: String in active(c):
		_drop(c, id)
	c["diseases"] = []
	return had


static func _drop(c: Dictionary, id: String) -> void:
	for d: Dictionary in incubating(c).duplicate():
		if str(d["id"]) == id:
			incubating(c).erase(d)
	for e: Dictionary in ConditionRules.effects(c).duplicate():
		if str(e.get("source", {}).get("kind", "")) == "disease" and str(e["source"].get("id", "")) == id:
			ConditionRules.remove_effect(c, int(e["uid"]))


## A sick NPC of the room passes its contagious disease on, once a day per NPC. Lines.
static func contagion(s: GameSession, data: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var met: Dictionary = s.character.get("disease_met", {})
	for npc_id: String in SceneRules.npcs(s, data["world"], s.room_id):
		var npc: Dictionary = data["world"]["npcs"].get(npc_id, {})
		var id := npc_disease(s, data, npc_id)
		if id.is_empty() or not bool(def_of(s, data, id).get("contagious", false)) or int(met.get(npc_id, 0)) == s.day:
			continue
		met[npc_id] = s.day
		lines.append_array(expose(s, data, id, int(cfg(data).get("contagion_dc", 10)), "Зараза от %s" % npc.get("name", npc_id)))
	s.character["disease_met"] = met
	return lines


## The master's new disease (`disease` effect with `make`): checked against rules.diseases.make. {def} or {reason}.
static func make(data: Dictionary, name: String, spec: Dictionary) -> Dictionary:
	var m: Dictionary = cfg(data)["make"]
	var days := int(spec.get("days", 0))
	var inc := int(spec.get("incubation_hours", 24))
	if name.strip_edges().is_empty():
		return {"reason": "у новой болезни нужно имя (disease)"}
	if days < int(m["days"][0]) or days > int(m["days"][1]):
		return {"reason": "days новой болезни — от %d до %d" % [m["days"][0], m["days"][1]]}
	if inc < int(m["incubation_hours"][0]) or inc > int(m["incubation_hours"][1]):
		return {"reason": "incubation_hours — от %d до %d" % [m["incubation_hours"][0], m["incubation_hours"][1]]}
	var conds: Array = []
	for cond: Variant in spec.get("symptoms", []):
		if not (m["conditions"] as Array).has(str(cond)):
			return {"reason": "симптом %s нельзя; можно: %s" % [cond, ", ".join(m["conditions"])]}
		conds.append(str(cond))
	var saves := {}
	for ab: Variant in spec.get("weak_saves", []):
		if not (m["saves"] as Array).has(str(ab)):
			return {"reason": "weak_saves — из %s" % ", ".join(m["saves"])}
		saves[str(ab)] = "disadvantage"
	var d := {"name": name.strip_edges(), "line": "болен: " + name.strip_edges().to_lower(), "incubation_hours": inc, "days": days,
		"conditions": conds, "saves": saves, "herbs": bool(spec.get("herbs", true)), "contagious": bool(spec.get("contagious", false)),
		"text": str(spec.get("text", "")).strip_edges().left(240), "generated": true}
	return {"def": d}
