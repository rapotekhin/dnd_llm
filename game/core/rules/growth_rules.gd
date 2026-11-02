class_name GrowthRules
extends RefCounted
## A person of a class grows beside the hero (v0.8.4.11, ADR-0016): the experience of a fight it stood in and of a quest it
## walked to the end is its own too; past the next threshold of the hero's table (LevelUp.xp_for) its class level rises,
## with the hit points of its class's die, up to rules.xp.max_level. Its record keeps `xp` and `level`; a fight gives it
## the features of that level (FeatureRules.give_class) and the hit points (`apply`). One without a class does not grow.


## Its class: the pack's own row, else the one of its SRD template (rules.combat.classed). {} — none.
static func row(data: Dictionary, npc_id: String) -> Dictionary:
	var npc: Dictionary = data["world"]["npcs"].get(npc_id, {})
	if npc.has("class"):
		return npc
	return CombatRules.cfg(data)["classed"].get(str(npc.get("monster", CombatRules.cfg(data)["default_npc_monster"])), {})


static func level(s: GameSession, data: Dictionary, npc_id: String) -> int:
	return int(Being.view(s, npc_id).get("level", int(row(data, npc_id).get("level", 0))))


## `amount` of experience to a person. Lines: when it grows.
static func gain(s: GameSession, data: Dictionary, npc_id: String, amount: int) -> Array[String]:
	var lines: Array[String] = []
	var r := row(data, npc_id)
	if amount <= 0 or not r.has("class"):
		return lines
	var b := Being.of(s, npc_id)
	var lv := level(s, data, npc_id)
	if not b.has("xp"):
		b["xp"] = LevelUp.xp_for(data, lv)  # it starts where its level does
	b["xp"] = int(b["xp"]) + amount
	while lv < int(data["rules"]["xp"]["max_level"]) and int(b["xp"]) >= LevelUp.xp_for(data, lv + 1):
		lv += 1
		b["level"] = lv
		lines.append("%s растёт: %d уровень (%s)" % [Rest.name_of(s, data, npc_id), lv,
			data["classes"]["classes"].get(str(r["class"]), {}).get("name", r["class"])])
	return lines


## The same experience to each of them. Lines.
static func share(s: GameSession, data: Dictionary, ids: Array, amount: int) -> Array[String]:
	var lines: Array[String] = []
	for id: Variant in ids:
		lines.append_array(gain(s, data, str(id), amount))
	return lines


## The people who stood on the hero's side in this fight and are on their feet or came to.
static func fought(s: GameSession) -> Array[String]:
	var out: Array[String] = []
	for id: String in CombatRules.allies(s, false):
		var f := CombatRules.fighter(s, id)
		if not str(f.get("npc_id", "")).is_empty() and str(f.get("status")) != "dead":
			out.append(str(f["npc_id"]))
	return out


## The followers here, for a quest's reward.
static func company(s: GameSession) -> Array[String]:
	var out: Array[String] = []
	for id: String in Being.followers(s):
		if not Being.view(s, id).has("at") or str(Being.view(s, id)["at"]) == s.room_id:
			out.append(id)
	return out


## A fighter of a grown person: the features of its level and the hit points of the levels above its template's.
static func apply(s: GameSession, data: Dictionary, f: Dictionary) -> void:
	var id := str(f.get("npc_id", ""))
	if id.is_empty():
		return
	var r := row(data, id)
	var lv := int(Being.view(s, id).get("level", 0))
	var was := int(f.get("level", 0))
	if not r.has("class") or lv <= was:
		return
	FeatureRules.give_class(data, f, {"class": str(r["class"]), "level": lv, "subclass": str(r.get("subclass", "")), "npc_id": id})
	var die := int(CharacterRules.class_def(f, data).get("hit_die", 8))
	var more := (lv - was) * CharacterRules.hp_step(f, die, Sheet.ability_mod(s, data, f, "con"))  # Dwarven Toughness too
	f["max_hp"] = int(f["max_hp"]) + more
	f["hp"] = int(f["hp"]) + more
