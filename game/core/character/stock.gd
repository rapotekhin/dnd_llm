class_name Stock
extends RefCounted
## What a character spends and gets back (v0.7.63, from the feature uses of v0.6.0): Second Wind, Rage, Ki and the other
## limited uses, spell slots `slot_<circle>`, hit dice `hit_dice`. Who has it, how many and when it comes back are data
## (rules.json `resources`); the character keeps only `spent` {id: n}. A feature's use goes through the engine (effect
## use:feature or the sheet button). A thing's charges join this with the item's instance (v0.7.65).


static func table(data: Dictionary, c: Dictionary = {}) -> Dictionary:
	var out := {}
	var all: Dictionary = data["rules"].get("resources", {})
	for id: String in all:
		if not id.begins_with("_"):
			out[id] = all[id]
	out.merge(c.get("item_stock", {}))  # the spells of the things it holds (v0.8.4.36, ItemRules.wear)
	return out


## Resource ids the character has (through one of its features).
static func owned(c: Dictionary, data: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var all := table(data, c)
	for id: String in all:
		if all[id].has("item"):  # a thing's spell: its holder has it while the thing works
			out.append(id)
			continue
		if int(all[id].get("level", 0)) > int(c.get("level", 1)):  # a race's spell from its level (v0.8.4.33)
			continue
		if all[id].has("spell") and not all[id].has("features") and not all[id].has("traits") and SpellRules.ready(c).has(str(all[id]["spell"])):  # an ability of parts: v0.7.64
			out.append(id)
			continue
		for f: Variant in all[id].get("features", []):  # with `spell` too: the charges of a feature's spell (v0.8.4.26.1)
			if CharacterRules.has_feature(c, str(f)):
				out.append(id)
				break
		if not out.has(id) and (all[id].get("traits", []) as Array).any(func(t: Variant) -> bool: return MonsterRules.has_trait(data, c, str(t))):
			out.append(id)  # a monster's trait: a priest's Divine Eminence (v0.8.4.27.5)
	return out


## How much of `id` is spent.
static func spent(c: Dictionary, id: String) -> int:
	return int(c.get("spent", {}).get(id, 0))


## Spends `n` of `id`; what `use` adds to it is the feature's.
static func spend(c: Dictionary, id: String, n: int = 1) -> void:
	if id.begins_with("slot_") and Cheats.on(c, "slots"):  # the dev console's endless slots
		return
	if ItemRules.unstore(c, id):  # a spell kept in a thing is gone once cast (v0.8.4.36)
		return
	var used: Dictionary = c.get("spent", {})
	used[id] = int(used.get(id, 0)) + n
	c["spent"] = used


## Gives back `n` of `id`.
static func give(c: Dictionary, id: String, n: int = 1) -> void:
	var used: Dictionary = c.get("spent", {})
	var rest := int(used.get(id, 0)) - n
	if rest > 0:
		used[id] = rest
	else:
		used.erase(id)
	c["spent"] = used


## Every spell slot back.
static func fill_slots(c: Dictionary) -> void:
	for n in range(1, 6):
		give(c, "slot_%d" % n, spent(c, "slot_%d" % n))


static func max_uses(c: Dictionary, data: Dictionary, id: String) -> int:
	var spec: Dictionary = table(data, c).get(id, {}).get("max", {})
	if spec.has("fixed"):
		return int(spec["fixed"])
	if spec.has("class_specific"):
		var row := CharacterRules.level_row(c, data).get("class_specific", {}) as Dictionary
		return int(row.get(str(spec["class_specific"]), spec.get("default", 0)))
	if spec.has("ability_mod"):
		var m := CharacterRules.mod(CharacterRules.ability(c, str(spec["ability_mod"]))) + int(spec.get("plus", 0))
		return maxi(int(spec.get("min", 0)), m)
	if spec.has("per_level"):
		return int(spec["per_level"]) * int(c.get("level", 1))
	if spec.has("slots"):
		return int(c.get("slots_max", [0, 0, 0, 0, 0])[int(spec["slots"]) - 1])
	if spec.has("slot_any"):  # paid by any spell slot (Primeval Awareness, v0.8.4.26.1)
		return (c.get("slots_max", []) as Array).reduce(func(a: int, n: Variant) -> int: return a + int(n), 0)
	return 0


static func left(c: Dictionary, data: Dictionary, id: String) -> int:
	if table(data, c).get(id, {}).get("max", {}).has("slot_any"):
		return range(1, 6).reduce(func(a: int, n: int) -> int: return a + SpellRules.slots_left(c, n), 0)
	return maxi(0, max_uses(c, data, id) - spent(c, id))


## A resource id by its id, one of its feature ids, or the Russian name of the feature; "" if none.
static func resolve(c: Dictionary, data: Dictionary, name: String) -> String:
	var key := name.strip_edges().to_lower()
	var feats: Dictionary = data["classes"]["features"]
	var all := table(data, c)
	for id: String in owned(c, data):
		if id == key:
			return id
		for f: Variant in all[id].get("features", []):
			if str(f) == key or str(feats.get(str(f), {}).get("name", "")).to_lower() == key:
				return id
	return ""


## The display name: the name of the character's feature that grants it.
static func display_name(c: Dictionary, data: Dictionary, id: String) -> String:
	if table(data, c).get(id, {}).has("name"):
		return str(table(data, c)[id]["name"])
	var feats: Dictionary = data["classes"]["features"]
	for f: Variant in table(data, c).get(id, {}).get("features", []):
		if CharacterRules.has_feature(c, str(f)):
			return str(feats.get(str(f), {}).get("name", id))
	return id


## "" when `amount` uses can be spent now, otherwise the reason (for the master) — use can_use_key for the UI.
static func can_use(c: Dictionary, data: Dictionary, id: String, amount: int, pending: int = 0) -> String:
	if id.is_empty() or not owned(c, data).has(id):
		return "у персонажа нет такого умения с ограниченными использованиями"
	if amount < 1:
		return "нужно потратить хотя бы одно использование"
	if left(c, data, id) - pending < amount:
		return "%s: осталось %d из %d — восстановится после %s отдыха" % [display_name(c, data, id), left(c, data, id) - pending,
			max_uses(c, data, id), "короткого" if recharge(c, data, id) == "short" else "долгого"]
	return ""


static func recharge(c: Dictionary, data: Dictionary, id: String) -> String:
	var spec: Dictionary = table(data, c).get(id, {})
	var quick: Variant = spec.get("short_with", [])
	if (quick if quick is Array else [quick]).any(func(f: Variant) -> bool: return CharacterRules.has_feature(c, str(f))):
		return "short"
	return str(spec.get("recharge", "long"))


## Spends `amount` uses (can_use first) and does what the data says (heals; `sense` with the game `s`). Returns the chat lines.
static func use(c: Dictionary, data: Dictionary, id: String, amount: int, rng: RandomNumberGenerator, s: GameSession = null) -> Array[String]:
	if table(data, c)[id].get("max", {}).has("slot_any"):  # the lowest slot left pays
		for n in range(1, 6):
			if amount > 0 and SpellRules.slots_left(c, n) > 0:
				spend(c, "slot_%d" % n)
				amount -= 1
		amount = 1
	else:
		spend(c, id, amount)
	var lines: Array[String] = ["%s%s (осталось %d)" % [display_name(c, data, id), " ×%d" % amount if amount > 1 else "", left(c, data, id)]]
	var on_use: Dictionary = table(data, c)[id].get("on_use", {})
	var heal := 0
	if on_use.has("heal"):
		heal = CombatRules.roll_dice(rng, CombatRules.dice_of(on_use["heal"], int(c.get("level", 1))))
	elif bool(on_use.get("heal_amount", false)):
		heal = amount
		var cost := int(on_use.get("cure_disease", 0))  # Lay on Hands: 5 points cure a disease first (v0.7.23.1)
		if cost > 0 and amount >= cost and DiseaseRules.cure_all(c, data):
			heal -= cost
			lines.append("болезнь исцелена")
	if heal > 0:
		lines.append("+%d HP" % (Harm.mend(s, data, Sheet.HERO if is_same(c, s.character) else c, heal) if s != null else Harm.heal(data, c, heal)))
	if bool(on_use.get("inspire", false)):  # a solo bard inspires themself (house rule, ADR-0010 §6в, v0.7.10)
		var die := int(CharacterRules.level_row(c, data).get("class_specific", {}).get("bardic_inspiration_die", 6))
		for e: Dictionary in ConditionRules.effects(c).duplicate():
			if int(e.get("inspiration", 0)) > 0:
				ConditionRules.remove_effect(c, int(e["uid"]))
		ConditionRules.add_effect(c, {"condition": "", "inspiration": die, "ends": {"rest": "short"},
			"source": {"kind": "feature", "id": id, "name": "Вдохновение (к%d)" % die}})
		lines.append("к%d добавится к следующему проваленному броску" % die)
	if on_use.has("sense") and s != null:  # Primeval Awareness: the kinds of creatures around (v0.8.4.26.1)
		var kinds := EncounterRules.sense(s, data, on_use["sense"]["types"], int(on_use["sense"].get("depth", 1)))
		lines.append(("рядом есть: " + ", ".join(kinds)) if not kinds.is_empty() else "рядом никого из этих существ")
	if str(on_use.get("recover_slots", "")) == "half_level":  # Arcane / Natural Recovery: the highest slots first
		var budget := ceili(int(c.get("level", 1)) / 2.0)
		var back: Array[String] = []
		for lv in range(mini(5, budget), 0, -1):
			while spent(c, "slot_%d" % lv) > 0 and budget >= lv:
				give(c, "slot_%d" % lv)
				budget -= lv
				back.append(str(lv))
		lines.append(("ячейки назад: круг " + ", ".join(back)) if not back.is_empty() else "потраченных ячеек нет")
	return lines


## Gives back what a rest returns: "short" — what comes back on a short rest, "long" — everything.
static func recharge_all(c: Dictionary, data: Dictionary, rest: String) -> void:
	for id: String in c.get("spent", {}).keys():
		if recharge(c, data, id) == "never":
			continue
		if rest == "long" or recharge(c, data, id) == "short":
			var half := str(table(data, c).get(id, {}).get("back", "")) == "half_level"
			give(c, id, maxi(1, int(c.get("level", 1)) / 2) if half else spent(c, id))


## For the snapshot and the sheet: [{id, name, left, max, recharge}].
static func lines(c: Dictionary, data: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: String in owned(c, data):
		var m := max_uses(c, data, id)
		if m > 0:
			out.append({"id": id, "name": display_name(c, data, id), "left": left(c, data, id), "max": m, "recharge": recharge(c, data, id)})
	return out
