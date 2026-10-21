class_name SpellRules
extends RefCounted
## Casting (roadmap v0.6.0, ADR-0008): the spell must be a cantrip of the character or prepared (known casters:
## known; subclass spells are always prepared); a spell of circle 1+ spends a slot of its circle or higher;
## a concentration spell replaces the previous one. Both ways go through here: the master's effect `cast` and
## the «Колдовать» button. The master only narrates an accepted cast.


## A spell id the character has ready, by id or Russian / English name; "" if none.
static func resolve(c: Dictionary, data: Dictionary, name: String) -> String:
	var id := Lookup._resolve(data["spells"], name)
	return id if not id.is_empty() and ready(c).has(id) else ""


## Spell ids the character can cast now: cantrips, prepared and always-prepared.
static func ready(c: Dictionary) -> Array:
	var out: Array = []
	var sp: Dictionary = c.get("spells", {})
	for list: String in ["cantrips", "prepared", "always"]:
		for id: Variant in sp.get(list, []):
			if not out.has(str(id)):
				out.append(str(id))
	return out


static func level_of(data: Dictionary, spell_id: String) -> int:
	return int(data["spells"].get(spell_id, {}).get("level", 0))


## The lowest slot circle ≥ the spell's with a slot left (after `pending` [circle → spent this turn]); 0 if none.
static func lowest_slot(c: Dictionary, data: Dictionary, spell_id: String, pending: Dictionary = {}) -> int:
	for lv in range(maxi(1, level_of(data, spell_id)), 6):
		if slots_left(c, lv) - int(pending.get(lv, 0)) > 0:
			return lv
	return 0


static func slots_left(c: Dictionary, circle: int) -> int:
	if circle < 1 or circle > 5:
		return 0
	return int(c.get("slots_max", [0, 0, 0, 0, 0])[circle - 1]) - int(c.get("slots_used", [0, 0, 0, 0, 0])[circle - 1])


## {"spell_id", "slot"} when the cast can go (slot 0 = a cantrip), or {"reason"} for the master.
## `slot` 0 picks the lowest fitting one.
static func check(c: Dictionary, data: Dictionary, name: String, slot: int, pending: Dictionary = {}) -> Dictionary:
	var any_id := Lookup._resolve(data["spells"], name)
	if any_id.is_empty():
		return {"reason": "нет такого заклинания: %s" % name}
	var id := resolve(c, data, name)
	var sname := str(data["spells"][any_id]["name"])
	if id.is_empty():
		return {"reason": "«%s» не подготовлено у персонажа — он не может его сотворить" % sname}
	var lv := level_of(data, id)
	if lv == 0:
		return {"spell_id": id, "slot": 0}
	if slot == 0:
		slot = lowest_slot(c, data, id, pending)
		if slot == 0:
			return {"reason": "для «%s» не осталось ячеек %d круга и выше — нужен отдых" % [sname, lv]}
	if slot < lv:
		return {"reason": "«%s» — заклинание %d круга, ячейка %d круга не подходит" % [sname, lv, slot]}
	if slots_left(c, slot) - int(pending.get(slot, 0)) <= 0:
		return {"reason": "ячеек %d круга не осталось" % slot}
	return {"spell_id": id, "slot": slot}


## Spends the slot (check first) and keeps concentration. With the session (v0.7.8) the concentration gets its end
## by the spell's duration on the game clock, and a spell cast on the hero (`on_self`) lifts what it cures
## (rules.hero_effects.spell_cures). Returns the chat lines.
static func cast(c: Dictionary, data: Dictionary, spell_id: String, slot: int, session: GameSession = null, on_self: bool = false) -> Array[String]:
	var s: Dictionary = data["spells"][spell_id]
	var line := "Заклинание: %s" % s["name"]
	if slot > 0:
		var used: Array = (c.get("slots_used", [0, 0, 0, 0, 0]) as Array).duplicate()
		used[slot - 1] = int(used[slot - 1]) + 1
		c["slots_used"] = used
		line += " (ячейка %d круга, осталось %d)" % [slot, slots_left(c, slot)]
	var lines: Array[String] = [line]
	if not (data["rules"].get("invisibility", {}).get("spells", {}) as Dictionary).has(spell_id):
		lines.append_array(ConditionRules.end_invisibility_on_attack(c, data))  # a spell gives the caster away (v0.7.5)
	if bool(s.get("concentration", false)):
		var prev := str(c.get("concentration", ""))
		if not prev.is_empty() and prev != spell_id:
			lines.append("концентрация на «%s» прервана" % data["spells"].get(prev, {}).get("name", prev))
		c["concentration"] = spell_id
		var rounds := ConditionRules.spell_rounds(data, spell_id)
		c["concentration_ends"] = ConditionRules.now(session) + rounds if session != null and rounds >= 0 else -1
		lines.append("концентрация")
	if session != null and spell_id == "identify":  # v0.7.12: every unknown thing the hero carries
		lines.append_array(ItemRules.identify(c, data, session.items))
	if session != null and (data["rules"]["languages"]["understand_spells"] as Array).has(spell_id):  # v0.7.11
		ConditionRules.add_effect(c, {"condition": "", "understand_all": true, "ends": ConditionRules.ends_for(session, data, "hour"),
			"source": {"kind": "spell", "id": spell_id, "name": s_name(data, spell_id)}})
		lines.append("понимает любой язык — час")
	if session != null and on_self and SpellEffects.self_spell(data, spell_id):  # v0.7.13.1: Bless, Guidance, Heroism…
		lines.append_array(SpellEffects.apply_self(session, data, spell_id))
	if session != null and on_self and not CombatRules.active(session):  # v0.7.13: the engine heals out of a fight too
		lines.append_array(heal_self(c, data, spell_id, slot, session.rng))
	if session != null and on_self:
		var cure: Dictionary = data["rules"]["hero_effects"]["spell_cures"].get(spell_id, {})
		if not cure.is_empty():
			lines.append_array(ConditionRules.cure(session, data, cure, {"kind": "spell", "id": spell_id, "name": s_name(data, spell_id)}))
	return lines


## A spell cast over minutes (Prayer of Healing, rituals): not in a fight (v0.7.13).
static func long_cast(sp: Dictionary) -> bool:
	var t := str(sp.get("casting_time", ""))
	return t.contains("мин") or t.contains("час")


## Healing the hero out of a fight (v0.7.13): a healing spell cast on themselves rolls its dice (Disciple of Life too).
static func heal_self(c: Dictionary, data: Dictionary, spell_id: String, slot: int, rng: RandomNumberGenerator) -> Array[String]:
	var sp: Dictionary = data["spells"].get(spell_id, {})
	if not sp.has("heal_at_slot"):
		return []
	var ab := CharacterRules.mod(CharacterRules.ability(c, str(c.get("spell_ability", "wis"))))
	var heal := CombatRules.roll_dice(rng, str(sp["heal_at_slot"].get(str(maxi(1, slot)), "1d8+MOD")), false, ab)
	if CharacterRules.has_feature(c, "disciple_of_life") and slot > 0:
		heal += 2 + slot
	var before := int(c["hp"])
	c["hp"] = mini(int(c["max_hp"]), before + heal)
	return ["+%d HP" % (int(c["hp"]) - before)]


static func s_name(data: Dictionary, spell_id: String) -> String:
	return str(data["spells"].get(spell_id, {}).get("name", spell_id))


## A spell that does something to the hero when cast on them (a cure).
static func cures(data: Dictionary, spell_id: String) -> bool:
	return data["rules"]["hero_effects"]["spell_cures"].has(spell_id)


## The facts of a cast for the master (turn input of kind ability, effect summary).
static func describe(data: Dictionary, spell_id: String, slot: int) -> String:
	var s: Dictionary = data["spells"][spell_id]
	return "«%s»%s%s; время %s, дистанция %s, длительность %s" % [s["name"], " ячейкой %d круга" % slot if slot > 0 else " (заговор)",
		", концентрация" if bool(s.get("concentration", false)) else "", s.get("casting_time", ""), s.get("range", ""), s.get("duration", "")]


## Prepared casters (cleric, druid, paladin, wizard) change their prepared spells after a long rest (once a day).
static func prepares(c: Dictionary, data: Dictionary) -> bool:
	var sc: Dictionary = CharacterRules.class_def(c, data).get("spellcasting", {})
	return bool(sc.get("prepared", false)) and int(c.get("level", 1)) >= int(sc.get("from_level", 1))


## "" when the character may change the prepared list today, otherwise a localization key.
static func can_prepare(c: Dictionary, data: Dictionary, day: int) -> String:
	if not prepares(c, data):
		return "PREP_NOT_PREPARER"
	if int(c.get("prepared_day", 1)) >= day:
		return "PREP_ALREADY_TODAY"
	return ""


## How many spells to prepare and from what: the class list up to the highest slot circle, or the spellbook.
static func prepare_pool(c: Dictionary, data: Dictionary) -> Dictionary:
	var max_circle := 0
	for i in 5:
		if int(c.get("slots_max", [0, 0, 0, 0, 0])[i]) > 0:
			max_circle = i + 1
	var pool: Array = []
	var sp: Dictionary = c.get("spells", {})
	var always: Array = sp.get("always", [])
	if bool(CharacterRules.class_def(c, data).get("spellcasting", {}).get("spellbook", false)):
		pool = (sp.get("known", []) as Array).filter(func(id: Variant) -> bool: return not always.has(id))
	else:
		var cls := str(c.get("class", ""))
		for id: String in data["spells"]:
			var s: Dictionary = data["spells"][id]
			if (s["classes"] as Array).has(cls) and int(s["level"]) >= 1 and int(s["level"]) <= max_circle and not always.has(id):
				pool.append(id)
	return {"count": LevelUp.prepared_count(c, data, int(c.get("level", 1)), c.get("abilities", {})), "pool": pool}


## "" or a localization key for a new prepared list.
static func prepare_error(c: Dictionary, data: Dictionary, day: int, ids: Array) -> String:
	var why := can_prepare(c, data, day)
	if not why.is_empty():
		return why
	var p := prepare_pool(c, data)
	var seen := {}
	for id: Variant in ids:
		if not (p["pool"] as Array).has(id) or seen.has(id):
			return "PREP_ERR_PICKS"
		seen[id] = true
	return "" if ids.size() == mini(int(p["count"]), (p["pool"] as Array).size()) else "PREP_ERR_COUNT"


static func prepare(c: Dictionary, ids: Array, day: int) -> void:
	c["spells"]["prepared"] = ids.duplicate()
	c["prepared_day"] = day
