class_name RollParts
extends RefCounted
## The parts of a hero's roll (v0.7.39.5, the author: «разбор броска при наведении — весь функционал игры»): every
## modifier of a check or a save as a labelled part {label, value}, the sheet's own (the ability, proficiency,
## expertise, Jack of All Trades, items, spells) and the roll's extras (the game's difficulty, a tool, a terrain, a
## spell die, a direction of development). The sheet's numbers are the sums of these parts (CharacterRules.refresh),
## so the breakdown never lies; a sum that does not match its total gets a part «прочее» and is counted in
## `unlabeled` — the guard test keeps it at zero.
##
## A roll of a rule (a shift, a lesson, a permit…) is noted into s.roll_notes; GameState puts the notes on the next
## chat line of effects, and the chat shows them on hover. A check card carries its own `parts`.

const OTHER := "прочее"

## Rolls whose parts did not add up since the start (the guard test and the bot read it).
static var unlabeled := 0


static func part(label: String, value: int) -> Dictionary:
	return {"label": label, "value": value}


## Appends a part, skipping a zero.
static func add(parts: Array[Dictionary], label: String, value: int) -> void:
	if value != 0:
		parts.append(part(label, value))


static func sum(parts: Array) -> int:
	var n := 0
	for p: Variant in parts:
		n += int((p as Dictionary)["value"])
	return n


static func ability_name(ab: String) -> String:
	return TranslationServer.translate("ABILITY_" + ab.to_upper())


## The sheet's parts of a check or a save: `kind` "skill" | "save" | "ability". The ability's modifier is always in,
## even at zero, so the card names what was rolled.
static func sheet(c: Dictionary, data: Dictionary, kind: String, id: String, session_items: Dictionary = {}) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var ab := id if kind != "skill" else str(data["rules"]["skills"].get(id, "int"))
	out.append(part(ability_name(ab), CharacterRules.mod(CharacterRules.ability(c, ab))))
	var pb := CharacterRules.prof_bonus(c, data)
	match kind:
		"skill":
			if (c.get("expertise", []) as Array).has(id):
				add(out, "компетентность (двойное владение)", pb * 2)
			elif (c.get("skill_profs", []) as Array).has(id) or CharacterRules.has_feature(c, "skill_prof_" + id):
				add(out, "владение навыком", pb)
			elif id in ["deception", "persuasion"] and CharacterRules.has_feature(c, "eldritch_invocation_beguiling_influence"):
				add(out, "владение (Чарующее влияние)", pb)
			elif CharacterRules.has_feature(c, "jack_of_all_trades"):
				add(out, "мастер на все руки (½ владения)", pb / 2)
		"ability":
			if CharacterRules.has_feature(c, "jack_of_all_trades"):
				add(out, "мастер на все руки (½ владения)", pb / 2)
		"save":
			if (c.get("save_profs", []) as Array).has(id):
				add(out, "владение спасброском", pb)
	if kind != "save" and CharacterRules.item_prop(c, "checks_plus1"):  # Stone of Good Luck (v0.7.12); its saves are `saves_plus1`
		add(out, _item(c, data, session_items, "checks_plus1"), 1)
	if kind == "save":
		for d: Dictionary in CharacterRules.carried(c, data, session_items):
			add(out, str(d.get("name", "предмет")), ItemRules.plus(d, ["saves_plus"]))
	if kind == "skill":
		for e: Dictionary in SpellEffects.hero_effects(c, "skill_bonus"):  # Pass without Trace (v0.7.13.3)
			add(out, str(e.get("source", {}).get("name", "заклинание")), int(e["skill_bonus"].get(id, 0)))
	out.append_array(FaithRules.gift_parts(c, data, kind, id))  # v0.7.49: a kept vow's gift
	return out


## The sheet's parts made to add up to the sheet's own number (c.skills / c.saves — what the rolls add): the cache
## stays the bonus, the parts explain it.
static func cached(c: Dictionary, data: Dictionary, kind: String, id: String, session_items: Dictionary = {}) -> Array[Dictionary]:
	var parts := sheet(c, data, kind, id, session_items)
	var key := {"skill": "skills", "save": "saves"}.get(kind, "") as String
	if key.is_empty() or not (c.get(key, {}) as Dictionary).has(id):
		return parts
	return fit(parts, int(c[key][id]))


## The sheet's parts for engine.check params (skill, save or a bare ability).
static func of_params(c: Dictionary, data: Dictionary, params: Dictionary, session_items: Dictionary = {}) -> Array[Dictionary]:
	for kind: String in ["skill", "save", "ability"]:
		var id := str(params.get(kind, "")) if params.get(kind) != null else ""
		if not id.is_empty():
			return cached(c, data, kind, id, session_items)
	return []


## A skill check of a rule: the sheet's parts and the game's difficulty (= bonus_for + DifficultyRules.bonus).
static func skill(s: GameSession, data: Dictionary, skill_id: String) -> Array[Dictionary]:
	var out := cached(s.character, data, "skill", skill_id, s.items)
	difficulty(s, data, out)
	return out


static func difficulty(s: GameSession, data: Dictionary, parts: Array[Dictionary]) -> void:
	if data["rules"].has("difficulty"):
		add(parts, "сложность «%s»" % DifficultyRules.cfg(data)["levels"][DifficultyRules.level(s, data)]["name"], DifficultyRules.bonus(s, data))


## A bonus of a direction's skill (DevelopmentRules.effect takes the best one): named by that skill.
static func development(c: Dictionary, data: Dictionary, dir: String, key: String, parts: Array[Dictionary]) -> void:
	var v := int(DevelopmentRules.effect(c, data, dir, key, 0.0))
	if v == 0:
		return
	var d := DevelopmentRules.direction(data, dir)
	var label := str(d.get("name", dir))
	for id: Variant in DevelopmentRules.skills(c, dir):
		var sk: Dictionary = d.get("skills", {}).get(str(id), {})
		if int(float(sk.get("effect", {}).get(key, 0.0))) == v:
			label = str(sk.get("name", label))
	add(parts, label, v)


## A tool's check: the tool's ability, the proficiency with it, the game's difficulty (CraftRules.bonus).
static func tool(s: GameSession, data: Dictionary, tool_id: String, ab: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = [part(ability_name(ab), CharacterRules.mod(CharacterRules.ability(s.character, ab)))]
	if CraftRules.proficient(s.character, tool_id):
		add(out, "владение: " + BackgroundRules.tool_name(data, tool_id), CharacterRules.prof_bonus(s.character, data))
	difficulty(s, data, out)
	return out


## The parts made to add up to `bonus`: a remainder becomes «прочее» and is counted.
static func fit(parts: Array[Dictionary], bonus: int) -> Array[Dictionary]:
	var out := parts.duplicate()
	var rest := bonus - sum(parts)
	if rest != 0:
		out.append(part(OTHER, rest))
		unlabeled += 1
		push_warning("RollParts: %+d without a label in %s" % [rest, str(parts)])
	return out


## A rule's roll for the chat: what, the dice, the parts, the total and the DC (0 — none).
static func note(s: GameSession, what: String, rolls: Array, nat: int, parts: Array[Dictionary], bonus: int, dc: int = 0) -> void:
	if CombatRules.active(s):
		return  # a fight has its own log (the author: the breakdown only in the chat)
	s.roll_notes.append({"what": what, "rolls": rolls.duplicate(), "nat": nat, "parts": fit(parts, bonus), "total": nat + bonus, "dc": dc})


## The hover text of one roll: «Убеждение: к20 14 (14, 7)\n+3 Харизма\n+2 владение навыком\n= 19 против Сл 15».
static func text(r: Dictionary) -> String:
	var rolls: Array = r.get("rolls", [])
	var dice := "к20 %d" % int(r.get("nat", 0))
	if rolls.size() > 1:
		dice += " (%s)" % ", ".join(rolls.map(func(x: Variant) -> String: return str(int(x))))
	var lines: Array[String] = [("%s: " % r["what"] if not str(r.get("what", "")).is_empty() else "") + dice]
	for p: Variant in r.get("parts", []):
		lines.append("%+d %s" % [int(p["value"]), p["label"]])
	var end := "= %d" % int(r.get("total", 0))
	if int(r.get("dc", 0)) > 0:
		end += " против Сл %d" % int(r["dc"])
	lines.append(end)
	return "\n".join(lines)


## The hover text of a chat line of effects: its rolls one after another.
static func entry_text(e: Dictionary) -> String:
	return "\n\n".join((e.get("rolls", []) as Array).map(func(r: Variant) -> String: return text(r as Dictionary)))


static func _item(c: Dictionary, data: Dictionary, session_items: Dictionary, prop: String) -> String:
	var n := CharacterRules.carried_with(c, data, session_items, prop)
	if not n.is_empty():
		return n
	for slot: Variant in c.get("equipped", {}):
		var d := ItemRules.def_of(data["items"], session_items, str(c["equipped"][slot]))
		if (d.get("properties", []) as Array).has(prop):
			return str(d.get("name", "предмет"))
	return "предмет"
