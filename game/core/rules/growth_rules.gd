class_name GrowthRules
extends RefCounted
## A follower of a class grows beside the hero (v0.8.4.11, ADR-0016; v0.8.4.42.2 — the party's share): its share of a fight
## it stood in and of a quest it walked to the end; past the next threshold of the hero's table (LevelUp.xp_for) the
## player raises its class level by a button, with the hit points of its class's die, up to rules.xp.max_level. Its record keeps `xp` and `level`; a fight gives it
## the features of that level (FeatureRules.give_class) and the hit points (`apply`). One without a class does not grow.


## Its class: the pack's own row, else the one of its SRD template (rules.combat.classed). {} — none.
static func row(data: Dictionary, npc_id: String) -> Dictionary:
	var npc: Dictionary = data["world"]["npcs"].get(npc_id, {})
	if npc.has("class"):
		return npc
	return CombatRules.cfg(data)["classed"].get(str(npc.get("monster", CombatRules.cfg(data)["default_npc_monster"])), {})


static func level(s: GameSession, data: Dictionary, npc_id: String) -> int:
	return int(Being.view(s, npc_id).get("level", int(row(data, npc_id).get("level", 0))))


## `amount` of experience to a person. Its level rises by the player's button (`grow`, v0.8.4.42.2, the author: as the
## hero's); one line when it is ready for the next.
static func gain(s: GameSession, data: Dictionary, npc_id: String, amount: int) -> Array[String]:
	var lines: Array[String] = []
	if amount <= 0 or not row(data, npc_id).has("class"):
		return lines
	var b := Being.of(s, npc_id)
	if not b.has("xp"):
		b["xp"] = LevelUp.xp_for(data, level(s, data, npc_id))  # it starts where its level does
	var was := ready(s, data, npc_id)
	b["xp"] = int(b["xp"]) + amount
	if ready(s, data, npc_id) and not was:
		lines.append("%s готов к новому уровню" % Rest.name_of(s, data, npc_id))
	return lines


## Its experience past the next threshold of the hero's table, below rules.xp.max_level.
static func ready(s: GameSession, data: Dictionary, npc_id: String) -> bool:
	var lv := level(s, data, npc_id)
	return row(data, npc_id).has("class") and lv < int(data["rules"]["xp"]["max_level"]) 		and int(Being.view(s, npc_id).get("xp", 0)) >= LevelUp.xp_for(data, lv + 1)


## "" when the player may raise the follower's level now, else the reason's key.
static func grow_why(s: GameSession, data: Dictionary, npc_id: String) -> String:
	if not Being.follows(s, npc_id):
		return "ALLY_NOT_HERE"
	if CombatRules.active(s):
		return "WAIT_NOT_NOW"
	return "" if ready(s, data, npc_id) else "GROW_NOT_READY"


## One level up (grow_why first): the hit points of its class's die and the features of the level come with the next
## fighter it becomes (`apply`). Lines.
static func grow(s: GameSession, data: Dictionary, npc_id: String) -> Array[String]:
	var lv := level(s, data, npc_id) + 1
	Being.of(s, npc_id)["level"] = lv
	var cls := str(row(data, npc_id)["class"])
	var lines: Array[String] = ["%s: %d уровень (%s)" % [Rest.name_of(s, data, npc_id), lv, data["classes"]["classes"].get(cls, {}).get("name", cls)]]
	if ready(s, data, npc_id):
		lines.append("%s готов и к следующему" % Rest.name_of(s, data, npc_id))
	return lines


## The same experience to each of them. Lines.
static func share(s: GameSession, data: Dictionary, ids: Array, amount: int) -> Array[String]:
	var lines: Array[String] = []
	for id: Variant in ids:
		lines.append_array(gain(s, data, str(id), amount))
	return lines


## The members of the hero's party who stood in this fight and are on their feet or came to: its followers (v0.8.4.42.2 —
## an ally of an encounter or a summoned creature is not of the party and takes no share).
static func fought(s: GameSession) -> Array[String]:
	var out: Array[String] = []
	for id: String in CombatRules.allies(s, false):
		var f := CombatRules.fighter(s, id)
		if not str(f.get("npc_id", "")).is_empty() and str(f.get("status")) != "dead" and Being.follows(s, str(f["npc_id"])) and not out.has(str(f["npc_id"])):
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
