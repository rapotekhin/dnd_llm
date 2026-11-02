class_name Rest
extends RefCounted
## The rest of anybody (v0.8.4.11, ADR-0016): the hero, a follower, a person of the pack, a creature of a room. A long rest
## gives back the hit points, what a long rest recharges and the exhaustion, and ends what ends at a rest; a short one
## spends hit dice and gives back what a short rest recharges. The hero rests by its button with the ones who walk with it;
## the rest of the world rests by the clock, a night each (`tick`): the hero's sleep no longer heals the world.

## What a fighter of a person keeps on its record after the fight until it rests: spent uses and slots, its exhaustion.
const KEPT: Array[String] = ["spent", "exhaustion"]


## The one whose state rests: the hero's sheet, the fighter in a fight, the record otherwise. For writing.
static func holder(s: GameSession, id: String) -> Dictionary:
	if id == Being.HERO:
		return s.character
	var b := Being.of(s, id)
	return b["fight"] if b.has("fight") else b


## A long rest of `id`. Lines: what went (conditions, exhaustion).
static func long(s: GameSession, data: Dictionary, id: String) -> Array[String]:
	var h := holder(s, id)
	if id == Being.HERO:
		h["hp"] = int(h.get("max_hp", h.get("hp", 1)))
	else:
		h.erase("hp")  # whole again: a record's hit points are its template's when it has none of its own
		var cr: Dictionary = h.get("creature", {})
		if cr.has("max_hp"):
			cr["hp"] = int(cr["max_hp"])
		h.erase("rested")
	Stock.recharge_all(h, data, "long")
	return ends(h, data, "long", id == Being.HERO)


## A short rest of anybody but the hero (its own has the window of dice): up to `dice` hit dice of its template, what
## a short rest recharges. A creature's wounds are on its own part (v0.8.4.15). Lines.
static func short(s: GameSession, data: Dictionary, id: String, dice: int) -> Array[String]:
	var h := holder(s, id)
	var me := Sheet.who(s, data, id)
	var lines: Array[String] = []
	var cr: Dictionary = h.get("creature", {})
	var body := cr if cr.has("max_hp") else h
	var top := Sheet.max_hp(s, data, me)
	var wounds := int(body.get("hp", top if body == cr else -1))
	if wounds >= 0 and wounds < top:
		var hd := _hit_dice(data, me)
		var n := clampi(dice, 0, int(hd["count"]) - Stock.spent(h, "hit_dice"))
		var con := Sheet.ability_mod(s, data, me, "con")
		var healed := 0
		for i in n:
			healed += maxi(0, s.rng.randi_range(1, int(hd["die"])) + con)
		if n > 0:
			body["hp"] = mini(top, wounds + healed)
			Stock.spend(h, "hit_dice", n)
			lines.append("%s: кости хитов %d — +%d HP" % [name_of(s, data, id), n, int(body["hp"]) - wounds])
			if int(body["hp"]) >= top and body == h:
				h.erase("hp")
	Stock.recharge_all(h, data, "short")
	lines.append_array(ends(h, data, "short"))
	return lines


## The hit dice of a template: {count, die} from its SRD «hit_dice» («4d8»), a class's die for a classed one.
static func _hit_dice(data: Dictionary, who: Dictionary) -> Dictionary:
	var m := Sheet.template(data, who)
	var parts := str(m.get("hit_dice", "1d8")).split("d")
	return {"count": maxi(1, int(parts[0])), "die": maxi(4, int(parts[1]) if parts.size() > 1 else 8)}


## Conditions and concentration a rest ends; a long rest also takes all exhaustion away (decision of the author,
## v0.7.8, ADR-0010) and gives Relentless Endurance back. Lines.
static func ends(c: Dictionary, data: Dictionary, rest: String, hero := false) -> Array[String]:
	var lines: Array[String] = []
	var gone := ConditionRules.clear_on_rest(c, rest)
	if not gone.is_empty():
		lines.append("прошло: " + ", ".join(gone.map(func(id: String) -> String: return ConditionRules.name_of(data, id))))
	if not str(c.get("concentration", "")).is_empty():
		c["concentration"] = ""
		c["concentration_ends"] = -1
	_reset(c, "breath_used", false, hero)  # the dragonborn's breath comes back with any rest (v0.7.10)
	if rest == "long":
		if ConditionRules.exhaustion(c) > 0:
			lines.append("истощение снято")
		_reset(c, "exhaustion", 0, hero)
		_reset(c, "relentless_used", false, hero)
		_reset(c, "temp_hp", 0, hero)
	return lines


## A field back to nothing: the hero's sheet keeps its key, a record has none when nothing happened.
static func _reset(c: Dictionary, key: String, none: Variant, hero: bool) -> void:
	if hero:
		c[key] = none
	else:
		c.erase(key)


## The hero's company rests with it: the followers here. Lines.
static func company(s: GameSession, data: Dictionary, rest: String, dice: int = 0) -> Array[String]:
	var lines: Array[String] = []
	for id: String in Being.followers(s):
		if Being.view(s, id).has("at") and str(Being.view(s, id)["at"]) != s.room_id:
			continue  # left to wait elsewhere
		var gone := long(s, data, id) if rest == "long" else short(s, data, id, dice)
		if rest == "long" and not gone.is_empty():
			lines.append("%s: %s" % [name_of(s, data, id), "; ".join(gone)])
		elif rest == "short":
			lines.append_array(gone)
	return lines


## After time passed: who is not with the hero rests a night each — tired today (`rested` marks the day it was first seen
## so), whole in the morning of a later day. Followers rest with the hero; a fighter in a fight does not rest. Silent: the world heals out of sight.
static func tick(s: GameSession, data: Dictionary) -> Array[String]:
	if TimeRules.abs_minute(s) - TimeRules.day_start(s.day) < int(TimeRules.cfg(data)["wake_minute"]):
		return []
	for id: String in s.beings.keys():
		var b: Dictionary = s.beings[id]
		if id == Being.HERO or b.has("fight") or Being.follows(s, id) and not b.has("at") or bool(b.get("dead", false)):
			continue
		if not _tired(b):
			b.erase("rested")
		elif not b.has("rested"):
			b["rested"] = s.day
		elif int(b["rested"]) < s.day:
			long(s, data, id)
	return []


## Something a night's rest gives back: wounds, a spent use, exhaustion, a status that ends at a rest.
static func _tired(b: Dictionary) -> bool:
	if b.has("hp") or ConditionRules.exhaustion(b) > 0 or not (b.get("spent", {}) as Dictionary).is_empty():
		return true
	var cr: Dictionary = b.get("creature", {})
	if cr.has("max_hp") and int(cr.get("hp", cr["max_hp"])) < int(cr["max_hp"]):
		return true
	return (b.get("effects", []) as Array).any(func(e: Dictionary) -> bool: return not str(e.get("ends", {}).get("rest", "")).is_empty())


static func name_of(s: GameSession, data: Dictionary, id: String) -> String:
	if id == Being.HERO:
		return str(s.character.get("name", ""))
	var b := Being.view(s, id)
	return str(b.get("name", WorldView.name_of(data, id)))
