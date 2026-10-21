class_name LanguageRules
extends RefCounted
## Languages by 5e (roadmap v0.7.11): who understands the hero. The hero speaks the languages of the sheet, a rogue
## also knows Thieves' Cant, a druid — Druidic; «Понимание языков» (effect `understand_all`) lets the hero understand
## everyone for an hour. NPCs of the pack speak `languages` (by default Common and the language of their people —
## rules.languages.by_race); monsters — the SRD line («Common, Goblin», «understands Common but can't speak», telepathy).
## Without a common tongue there is no talking someone round: Persuasion and Deception by words fail, Intimidation goes
## with disadvantage (gestures and steel), a parley by Persuasion is closed; the master answers in a strange speech.


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"]["languages"]


static func name_of(data: Dictionary, id: String) -> String:
	return str(data["misc"]["languages"].get(id, {}).get("name", cfg(data).get("secret", {}).get(id, id)))


## The hero's languages: the sheet's, plus the secret ones of the class.
static func hero(c: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for l: Variant in c.get("languages", []):
		out.append(str(l))
	if not out.has("common"):
		out.append("common")
	if CharacterRules.has_feature(c, "thieves_cant"):
		out.append("thieves_cant")
	if CharacterRules.has_feature(c, "druidic"):
		out.append("druidic")
	return out


## An NPC of the pack: its `languages`, or Common and the language of its people.
static func npc(data: Dictionary, n: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for l: Variant in n.get("languages", []):
		out.append(str(l))
	if not out.is_empty():
		return out
	out.append("common")
	var race := str(n.get("race", "")).to_lower()
	var by_race: Dictionary = cfg(data)["by_race"]
	for prefix: String in by_race:
		if race.begins_with(prefix) or race.contains(prefix):
			if not out.has(str(by_race[prefix])):
				out.append(str(by_race[prefix]))
	return out


## A monster of the SRD: {"speaks": [ids], "telepathy": bool} from its languages line. «Any one language» and «the
## languages it knew in life» — Common; no line — none (beasts).
static func monster(data: Dictionary, monster_id: String) -> Dictionary:
	var text := str(data["monsters"].get(monster_id, {}).get("languages", "")).to_lower()
	var out: Array[String] = []
	var ids: Array = data["misc"]["languages"].keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return a.length() > b.length())  # Undercommon before Common
	for id: String in ids:
		var en := id.replace("_", " ")
		if text.contains(en):
			out.append(id)
			text = text.replace(en, "")
	if text.contains("any one language") or text.contains("knew in life") or text.contains("any languages"):
		if not out.has("common"):
			out.append("common")
	return {"speaks": out, "telepathy": text.contains("telepathy")}


## The hero understands everyone now («Понимание языков»).
static func understands_all(c: Dictionary) -> bool:
	if CharacterRules.item_prop(c, "understand_all"):  # Helm of Comprehending Languages (v0.7.12)
		return true
	return ConditionRules.effects(c).any(func(e: Dictionary) -> bool: return bool(e.get("understand_all", false)))


## Whether an NPC of the pack and the hero have a tongue in common (or a spell or telepathy bridges it).
static func npc_understands(c: Dictionary, data: Dictionary, n: Dictionary) -> bool:
	if understands_all(c):
		return true
	var mine := hero(c)
	return npc(data, n).any(func(l: String) -> bool: return mine.has(l))


## Whether a foe of the fight understands the hero.
static func foe_understands(c: Dictionary, data: Dictionary, f: Dictionary) -> bool:
	if understands_all(c):
		return true
	var m := monster(data, str(f.get("monster", "")))
	if bool(m["telepathy"]):
		return true
	var mine := hero(c)
	return (m["speaks"] as Array).any(func(l: Variant) -> bool: return mine.has(str(l)))


## «гоблинский, общий» — what a foe speaks, for the master and the card; «без речи» for beasts.
static func foe_speech(data: Dictionary, f: Dictionary) -> String:
	var m := monster(data, str(f.get("monster", "")))
	var names: Array = (m["speaks"] as Array).map(func(l: Variant) -> String: return name_of(data, str(l)).to_lower())
	if bool(m["telepathy"]):
		names.append("телепатия")
	return ", ".join(names) if not names.is_empty() else "без речи"


## What a social check by words loses when the target does not understand: {"auto_fail": reason} for Persuasion,
## Deception and Performance, {"disadvantage": reason} for Intimidation, {} otherwise or when they understand.
static func check_gate(c: Dictionary, data: Dictionary, skill: String, understands: bool) -> Dictionary:
	if understands:
		return {}
	if skill in ["persuasion", "deception", "performance"]:
		return {"auto_fail": "не понимает языка"}
	if skill == "intimidation":
		return {"disadvantage": "без общего языка — жесты и оружие"}
	return {}
