class_name FeatureUses
extends RefCounted
## Limited uses of class features (roadmap v0.6.0): Second Wind, Action Surge, Rage, Bardic Inspiration,
## Channel Divinity, Wild Shape, Ki, Lay on Hands, Divine Sense, Sorcery Points, Arcane Recovery. Who has them,
## how many and when they come back are data (rules.json `resources`); the character keeps only
## `resources_used` {resource id: spent}. A use goes through the engine (effect use_feature or the sheet button).


static func table(data: Dictionary) -> Dictionary:
	var out := {}
	var all: Dictionary = data["rules"].get("resources", {})
	for id: String in all:
		if not id.begins_with("_"):
			out[id] = all[id]
	return out


## Resource ids the character has (through one of its features).
static func owned(c: Dictionary, data: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var all := table(data)
	for id: String in all:
		for f: Variant in all[id]["features"]:
			if CharacterRules.has_feature(c, str(f)):
				out.append(id)
				break
	return out


static func max_uses(c: Dictionary, data: Dictionary, id: String) -> int:
	var spec: Dictionary = table(data).get(id, {}).get("max", {})
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
	return 0


static func left(c: Dictionary, data: Dictionary, id: String) -> int:
	return maxi(0, max_uses(c, data, id) - int(c.get("resources_used", {}).get(id, 0)))


## A resource id by its id, one of its feature ids, or the Russian name of the feature; "" if none.
static func resolve(c: Dictionary, data: Dictionary, name: String) -> String:
	var key := name.strip_edges().to_lower()
	var feats: Dictionary = data["classes"]["features"]
	var all := table(data)
	for id: String in owned(c, data):
		if id == key:
			return id
		for f: Variant in all[id]["features"]:
			if str(f) == key or str(feats.get(str(f), {}).get("name", "")).to_lower() == key:
				return id
	return ""


## The display name: the name of the character's feature that grants it.
static func display_name(c: Dictionary, data: Dictionary, id: String) -> String:
	var feats: Dictionary = data["classes"]["features"]
	for f: Variant in table(data).get(id, {}).get("features", []):
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
	var spec: Dictionary = table(data).get(id, {})
	if spec.has("short_with") and CharacterRules.has_feature(c, str(spec["short_with"])):
		return "short"
	return str(spec.get("recharge", "long"))


## Spends `amount` uses (can_use first) and does what the data says (heals). Returns the chat lines.
static func use(c: Dictionary, data: Dictionary, id: String, amount: int, rng: RandomNumberGenerator) -> Array[String]:
	var used: Dictionary = c.get("resources_used", {})
	used[id] = int(used.get(id, 0)) + amount
	c["resources_used"] = used
	var lines: Array[String] = ["%s%s (осталось %d)" % [display_name(c, data, id), " ×%d" % amount if amount > 1 else "", left(c, data, id)]]
	var on_use: Dictionary = table(data)[id].get("on_use", {})
	var heal := 0
	if on_use.has("heal"):
		var h: Array = on_use["heal"]
		heal = int(c.get("level", 1)) if str(h[2]) == "level" else int(h[2])
		for i in int(h[0]):
			heal += rng.randi_range(1, int(h[1]))
	elif bool(on_use.get("heal_amount", false)):
		heal = amount
		var cost := int(on_use.get("cure_disease", 0))  # Lay on Hands: 5 points cure a disease first (v0.7.23.1)
		if cost > 0 and amount >= cost and DiseaseRules.cure_all(c):
			heal -= cost
			lines.append("болезнь исцелена")
	if heal > 0:
		var before := int(c["hp"])
		c["hp"] = mini(int(c["max_hp"]), before + heal)
		lines.append("+%d HP" % (int(c["hp"]) - before))
	if bool(on_use.get("inspire", false)):  # a solo bard inspires themself (house rule, ADR-0010 §6в, v0.7.10)
		var die := int(CharacterRules.level_row(c, data).get("class_specific", {}).get("bardic_inspiration_die", 6))
		for e: Dictionary in ConditionRules.effects(c).duplicate():
			if int(e.get("inspiration", 0)) > 0:
				ConditionRules.remove_effect(c, int(e["uid"]))
		ConditionRules.add_effect(c, {"condition": "", "inspiration": die, "ends": {"rest": "short"},
			"source": {"kind": "feature", "id": id, "name": "Вдохновение (к%d)" % die}})
		lines.append("к%d добавится к следующему проваленному броску" % die)
	if str(on_use.get("recover_slots", "")) == "half_level":  # Arcane / Natural Recovery: the highest slots first
		var budget := ceili(int(c.get("level", 1)) / 2.0)
		var slots: Array = (c.get("slots_used", [0, 0, 0, 0, 0]) as Array).duplicate()
		var back: Array[String] = []
		for lv in range(mini(5, budget), 0, -1):
			while int(slots[lv - 1]) > 0 and budget >= lv:
				slots[lv - 1] = int(slots[lv - 1]) - 1
				budget -= lv
				back.append(str(lv))
		c["slots_used"] = slots
		lines.append(("ячейки назад: круг " + ", ".join(back)) if not back.is_empty() else "потраченных ячеек нет")
	return lines


## Gives back the uses of a rest: "short" restores short-rest resources, "long" restores all.
static func recharge_all(c: Dictionary, data: Dictionary, rest: String) -> void:
	var used: Dictionary = c.get("resources_used", {})
	for id: String in used.keys():
		if rest == "long" or recharge(c, data, id) == "short":
			used.erase(id)
	c["resources_used"] = used


## For the snapshot and the sheet: [{id, name, left, max, recharge}].
static func lines(c: Dictionary, data: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: String in owned(c, data):
		var m := max_uses(c, data, id)
		if m > 0:
			out.append({"id": id, "name": display_name(c, data, id), "left": left(c, data, id), "max": m, "recharge": recharge(c, data, id)})
	return out
