class_name ConditionRules
extends RefCounted
## Conditions and effects on the hero (roadmap v0.6.0, rebuilt in v0.7.8 «Правила 5e: состояния»).
## - An effect (`c.effects`) is a condition or a boon with its source {kind, id, name}, its end — `{"at": round}` of
##   the game clock (now()), `{"rest": "short" | "long"}` or `{}` (until removed) — and optionally a save the hero
##   repeats at the end of each own turn in a fight (`save` {ability, dc, tag, repeat}), the one who caused it
##   (`by`: an npc or a fighter id — the source of fear, the grappler, the charmer), waking on damage (`wake`), the DC
##   of breaking free (`escape_dc`), advantage on saves of a tag (`adv_tag`) and resistances (`resist`).
## - `c.conditions` is the list of condition ids of the effects, kept in sync: the sheet, the snapshot and the checks
##   read it. Exhaustion is a level `c.exhaustion` (0–6, rules.conditions.exhaustion).
## - The hero's concentration (`c.concentration` — a spell id) ends at `c.concentration_ends` (a round, −1 — never),
##   on a failed CON save after damage (HeroDefense), when the hero is incapacitated and with a rest.
## What conditions do to checks — rules.json `condition_effects`; to a fight — CombatRules; to damage and saves —
## HeroDefense.

## The kinds of an effect's end the master and the engine name (rules.hero_effects.durations + these three).
const ENDS: Array[String] = ["short_rest", "long_rest", "until_removed"]
const INCAPACITATING: Array[String] = ["unconscious", "paralyzed", "stunned", "incapacitated", "petrified"]
const ROUNDS_PER_MINUTE := 10


static func known(data: Dictionary, id: String) -> bool:
	return (data["rules"]["conditions"] as Dictionary).has(id)


static func has(c: Dictionary, id: String) -> bool:
	return (c.get("conditions", []) as Array).has(id)


static func name_of(data: Dictionary, id: String) -> String:
	return str(data["rules"]["conditions"].get(id, id)).get_slice(":", 0)


# --- the clock ------------------------------------------------------------------------------------


## The game clock in rounds (10 a minute): the day and minute, plus the rounds of the fight in progress.
static func now(s: GameSession) -> int:
	var t := ((s.day - 1) * 1440 + s.minute) * ROUNDS_PER_MINUTE
	if CombatRules.active(s):
		t += int(s.combat.get("round", 1)) - 1
	return t


## The end of an effect lasting `duration` (rules.hero_effects.durations or ENDS) from now.
static func ends_for(s: GameSession, data: Dictionary, duration: String) -> Dictionary:
	var table: Dictionary = data["rules"]["hero_effects"]["durations"]
	if table.has(duration):
		return {"at": now(s) + int(table[duration])}
	match duration:
		"short_rest":
			return {"rest": "short"}
		"long_rest":
			return {"rest": "long"}
	return {}


static func durations(data: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for k: String in data["rules"]["hero_effects"]["durations"]:
		out.append(k)
	out.append_array(ENDS)
	return out


## Rounds of a spell's duration («Концентрация, вплоть до 1 минуты» → 10); −1 when it has no end in time.
static func spell_rounds(data: Dictionary, spell_id: String) -> int:
	var text := str(data["spells"].get(spell_id, {}).get("duration", "")).to_lower()
	var rx := RegEx.create_from_string("(\\d+)\\s*(раунд|минут|час|дн|день)")
	var m := rx.search(text)
	if m == null:
		return -1
	var n := int(m.get_string(1))
	match m.get_string(2):
		"раунд":
			return n
		"минут":
			return n * ROUNDS_PER_MINUTE
		"час":
			return n * 60 * ROUNDS_PER_MINUTE
	return n * 1440 * ROUNDS_PER_MINUTE


## Rounds left of an effect, −1 when it does not end in time.
static func rounds_left(s: GameSession, e: Dictionary) -> int:
	if not e.get("ends", {}).has("at"):
		return -1
	return maxi(0, int(e["ends"]["at"]) - now(s))


## «54 мин», «3 р.», «до долгого отдыха» — what the chips and the master see.
static func left_text(s: GameSession, e: Dictionary) -> String:
	var ends: Dictionary = e.get("ends", {})
	if ends.has("at"):
		var r := rounds_left(s, e)
		if CombatRules.active(s) and r <= ROUNDS_PER_MINUTE:
			return "%d р." % maxi(1, r)
		var mins := ceili(r / float(ROUNDS_PER_MINUTE))
		return "%d ч %d мин" % [mins / 60, mins % 60] if mins >= 60 else "%d мин" % maxi(1, mins)
	match str(ends.get("rest", "")):
		"short":
			return "до короткого отдыха"
		"long":
			return "до долгого отдыха"
	return "пока не снимут"


# --- effects ----------------------------------------------------------------------------------------


static func effects(c: Dictionary) -> Array:
	if not (c.get("effects") is Array):
		c["effects"] = []
	return c["effects"]


## Adds an effect (see the header); the same condition from the same source is replaced. Returns its uid.
static func add_effect(c: Dictionary, e: Dictionary) -> int:
	var list := effects(c)
	var cond := str(e.get("condition", ""))
	var src := str(e.get("source", {}).get("name", ""))
	for old: Dictionary in list.duplicate():
		if not cond.is_empty() and str(old.get("condition", "")) == cond and str(old.get("source", {}).get("name", "")) == src:
			list.erase(old)
	var uid := int(c.get("next_effect", 1))
	c["next_effect"] = uid + 1
	var added := e.duplicate(true)
	added["uid"] = uid
	if not added.has("ends"):
		added["ends"] = {}
	if not added.has("source"):
		added["source"] = {"kind": "engine", "name": ""}
	list.append(added)
	_sync(c)
	return uid


## A condition by the engine itself (0 HP, the old API): until a rest.
static func add(c: Dictionary, id: String, until: String = "long_rest") -> void:
	add_effect(c, {"condition": id, "ends": {"rest": "short" if until == "short_rest" else "long"}, "source": {"kind": "engine", "name": ""}})


## Lifts a condition from every source.
static func remove(c: Dictionary, id: String) -> void:
	var list := effects(c)
	for e: Dictionary in list.duplicate():
		if str(e.get("condition", "")) == id:
			list.erase(e)
	_sync(c)


static func remove_effect(c: Dictionary, uid: int) -> void:
	var list := effects(c)
	for e: Dictionary in list.duplicate():
		if int(e.get("uid", 0)) == uid:
			list.erase(e)
	_sync(c)


## The effects of one condition (the longest first is not promised).
static func effects_of(c: Dictionary, id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Dictionary in effects(c):
		if str(e.get("condition", "")) == id:
			out.append(e)
	return out


static func _sync(c: Dictionary) -> void:
	var ids: Array = []
	for e: Dictionary in effects(c):
		var id := str(e.get("condition", ""))
		if not id.is_empty() and not ids.has(id):
			ids.append(id)
	c["conditions"] = ids


## The hero lays down a condition with everything it brings (v0.7.8): an incapacitating one breaks concentration,
## unconscious also lays the hero prone. Returns the lines.
static func impose(s: GameSession, data: Dictionary, e: Dictionary) -> Array[String]:
	var c := s.character
	var cond := str(e.get("condition", ""))
	var lines: Array[String] = []
	if cond == "exhaustion":
		return add_exhaustion(s, data, 1, str(e.get("source", {}).get("name", "")))
	add_effect(c, e)
	if cond == "unconscious" and not has(c, "prone"):
		add_effect(c, {"condition": "prone", "ends": {}, "source": e.get("source", {})})
	if INCAPACITATING.has(cond) and not str(c.get("concentration", "")).is_empty():
		lines.append_array(end_concentration(s, data, "недееспособность"))
	return lines


static func incapacitated(c: Dictionary) -> bool:
	return INCAPACITATING.any(func(x: String) -> bool: return has(c, x))


## The fighter or NPC id that caused the hero's condition (`by`), "" when nobody.
static func caused_by(c: Dictionary, id: String) -> String:
	for e: Dictionary in effects_of(c, id):
		if not str(e.get("by", "")).is_empty():
			return str(e["by"])
	return ""


## Clears what a rest ends: a short rest — short-rest effects; a long rest — every rest-bound one. Removed ids.
static func clear_on_rest(c: Dictionary, rest: String) -> Array[String]:
	var out: Array[String] = []
	var list := effects(c)
	for e: Dictionary in list.duplicate():
		var r := str(e.get("ends", {}).get("rest", ""))
		if r.is_empty() or (rest == "short" and r != "short"):
			continue
		list.erase(e)
		var id := str(e.get("condition", ""))
		if not id.is_empty() and not out.has(id):
			out.append(id)
	_sync(c)
	return out


## Effects whose time is up go, and so does a concentration past its end. Returns the lines.
static func expire(s: GameSession, data: Dictionary) -> Array[String]:
	var c := s.character
	var t := now(s)
	var gone: Array[String] = []
	var list := effects(c)
	for e: Dictionary in list.duplicate():
		if e.get("ends", {}).has("at") and int(e["ends"]["at"]) <= t:
			list.erase(e)
			var id := str(e.get("condition", ""))
			var what := name_of(data, id).to_lower() if not id.is_empty() else str(e.get("source", {}).get("name", ""))
			if not what.is_empty() and not gone.has(what):
				gone.append(what)
	_sync(c)
	var lines: Array[String] = []
	if not gone.is_empty():
		lines.append("прошло: " + ", ".join(gone))
	var ends := int(c.get("concentration_ends", -1))
	if not str(c.get("concentration", "")).is_empty() and ends >= 0 and ends <= t:
		lines.append_array(end_concentration(s, data, "время вышло"))
	return lines


## The end of the hero's own turn in a fight: repeat saves shake conditions off, then time runs out. Lines.
static func end_of_turn(s: GameSession, data: Dictionary) -> Array[String]:
	var c := s.character
	var lines: Array[String] = []
	for e: Dictionary in effects(c).duplicate():
		var sv: Dictionary = e.get("save", {})
		if not bool(sv.get("repeat", false)) or str(sv.get("ability", "")).is_empty():
			continue
		var r := HeroDefense.save(s, data, str(sv["ability"]), int(sv.get("dc", 10)), str(sv.get("tag", "")))
		var what := name_of(data, str(e.get("condition", ""))).to_lower()
		if bool(r["ok"]):
			remove_effect(c, int(e["uid"]))
			lines.append("%s стряхивает: %s (%s)" % [c.get("name", ""), what, r["text"]])
		else:
			lines.append("%s: %s держится (%s)" % [c.get("name", ""), what, r["text"]])
	lines.append_array(expire(s, data))
	return lines


# --- concentration ----------------------------------------------------------------------------------


## Ends the hero's concentration: the spell's conditions leave the foes, its own effects on the hero go. Lines.
static func end_concentration(s: GameSession, data: Dictionary, why: String) -> Array[String]:
	var c := s.character
	var spell := str(c.get("concentration", ""))
	if spell.is_empty():
		return []
	c["concentration"] = ""
	c["concentration_ends"] = -1
	var list := effects(c)
	for e: Dictionary in list.duplicate():
		if str(e.get("source", {}).get("kind", "")) == "spell" and str(e["source"].get("id", "")) == spell and bool(e.get("concentration", false)):
			list.erase(e)
	_sync(c)
	var lines: Array[String] = ["концентрация на «%s» прервана: %s" % [data["spells"].get(spell, {}).get("name", spell), why]]
	lines.append_array(CombatRules.end_spell(s, data, spell))
	return lines


# --- exhaustion (5e: six levels) ----------------------------------------------------------------------


static func exhaustion(c: Dictionary) -> int:
	return int(c.get("exhaustion", 0))


## +n levels of exhaustion (clamped 0–6). The sixth is death: the caller ends the game (dead()). Lines.
static func add_exhaustion(s: GameSession, data: Dictionary, n: int, why: String) -> Array[String]:
	var c := s.character
	var before := exhaustion(c)
	var after := clampi(before + n, 0, 6)
	if after == before:
		return []
	c["exhaustion"] = after
	CharacterRules.refresh(c, data, s.items)  # speed and max HP depend on it
	if after < before:
		return ["истощение %d → %d" % [before, after]]
	if after >= 6 and CombatRules.active(s) and str(s.combat.get("outcome", "")).is_empty():
		s.combat["outcome"] = "dead"
	var line := "Истощение %d%s" % [after, (" (%s)" % why) if not why.is_empty() else ""]
	return [line + (" — смерть" if after >= 6 else " — " + exhaustion_text(after))]


## What the current level does, short: «помеха на проверки, скорость вдвое меньше».
static func exhaustion_text(level: int) -> String:
	var parts: Array[String] = []
	if level >= 1:
		parts.append("помеха на проверки")
	if level >= 5:
		parts.append("скорость 0")
	elif level >= 2:
		parts.append("скорость вдвое меньше")
	if level >= 3:
		parts.append("помеха на атаки и спасброски")
	if level >= 4:
		parts.append("максимум хитов вдвое меньше")
	return ", ".join(parts)


static func dead(c: Dictionary) -> bool:
	return exhaustion(c) >= 6


# --- checks ---------------------------------------------------------------------------------------


## What the conditions do to a check: {"disadvantage": [condition ids], "auto_fail": [condition ids]}.
## `params.sense` — "sight" / "hearing" when the check needs it (the master's flag, v0.7.8).
static func check_mods(c: Dictionary, data: Dictionary, params: Dictionary) -> Dictionary:
	var out := {"disadvantage": [], "auto_fail": []}
	var skill := str(params.get("skill", "")) if params.get("skill") != null else ""
	var save := str(params.get("save", "")) if params.get("save") != null else ""
	var sense := str(params.get("sense", "")) if params.get("sense") != null else ""
	var table: Dictionary = data["rules"].get("condition_effects", {})
	for id: Variant in c.get("conditions", []):
		var fx: Dictionary = table.get(str(id), {})
		var modes: Array[String] = []
		if not skill.is_empty():
			modes.append(str(fx.get("skills", {}).get(skill, fx.get("checks", ""))))
		elif not save.is_empty():
			modes.append(str(fx.get("saves", {}).get(save, "")))
		if not sense.is_empty():
			modes.append(str(fx.get("senses", {}).get(sense, "")))
		var mode := "auto_fail" if modes.has("auto_fail") else "disadvantage" if modes.has("disadvantage") else ""
		if not mode.is_empty() and not (out[mode] as Array).has(str(id)):
			(out[mode] as Array).append(str(id))
	var lv := exhaustion(c)
	if (lv >= 1 and not skill.is_empty()) or (lv >= 3 and not save.is_empty()):
		(out["disadvantage"] as Array).append("exhaustion")
	return out


# --- invisibility (v0.7.5) ---------------------------------------------------------------------------


## The hero is invisible (v0.7.5): the condition, or concentration on an invisibility spell (rules.invisibility).
static func invisible(c: Dictionary, data: Dictionary) -> bool:
	if has(c, "invisible"):
		return true
	return (data["rules"].get("invisibility", {}).get("spells", {}) as Dictionary).has(str(c.get("concentration", "")))


## −passive Perception for those who would see the hero (5e disadvantage on a passive check), 0 when visible.
static func unseen_penalty(c: Dictionary, data: Dictionary) -> int:
	return int(data["rules"].get("invisibility", {}).get("passive_penalty", 5)) if invisible(c, data) else 0


## An attack or a spell ends 5e Invisibility (not Greater): its concentration and the condition go. Lines.
static func end_invisibility_on_attack(c: Dictionary, data: Dictionary) -> Array[String]:
	var spells: Dictionary = data["rules"].get("invisibility", {}).get("spells", {})
	var conc := str(c.get("concentration", ""))
	var lines: Array[String] = []
	if spells.has(conc) and bool(spells[conc].get("ends_on_attack", true)):
		c["concentration"] = ""
		c["concentration_ends"] = -1
		lines.append("Невидимость спадает")
	if has(c, "invisible") and lines.is_empty() and not (spells.has(conc) and not bool(spells[conc].get("ends_on_attack", true))):
		remove(c, "invisible")
		lines.append("Невидимость спадает")
	elif has(c, "invisible") and not lines.is_empty():
		remove(c, "invisible")
	return lines


# --- cures (v0.7.8) ---------------------------------------------------------------------------------


## A spell cast on the hero or a consumable used (`spec` from rules.hero_effects.spell_cures or consumables):
## lifts its conditions, takes exhaustion away, leaves a boon (advantage on saves of a tag, resistances). Lines.
static func cure(s: GameSession, data: Dictionary, spec: Dictionary, source: Dictionary) -> Array[String]:
	var c := s.character
	var lines: Array[String] = []
	for cond: Variant in spec.get("remove", []):
		if has(c, str(cond)):
			remove(c, str(cond))
			lines.append("снято: %s" % name_of(data, str(cond)))
	if int(spec.get("exhaustion", 0)) > 0 and exhaustion(c) > 0:
		lines.append_array(add_exhaustion(s, data, -int(spec["exhaustion"]), ""))
	if spec.has("adv_tag") or spec.has("resist"):
		var boon := {"condition": "", "source": source, "ends": ends_for(s, data, str(spec.get("duration", "hour")))}
		if spec.has("adv_tag"):
			boon["adv_tag"] = str(spec["adv_tag"])
		if spec.has("resist"):
			boon["resist"] = (spec["resist"] as Array).duplicate()
		add_effect(c, boon)
		lines.append("%s: %s" % [source.get("name", ""), boon_text(data, boon)])
	return lines


## «преимущество на спасброски от яда, сопротивление яду (1 ч)» — what a boon gives.
static func boon_text(data: Dictionary, e: Dictionary) -> String:
	var parts: Array[String] = []
	if e.has("adv_tag"):
		parts.append("преимущество на спасброски: %s" % HeroDefense.tag_name(str(e["adv_tag"])))
	for t: Variant in e.get("resist", []):
		parts.append("сопротивление: %s" % str(data["misc"]["damage_types"].get(str(t), t)))
	return ", ".join(parts)


## The hero's effects for the chips and the master: [{name, left, source, text, condition}].
static func shown(s: GameSession, data: Dictionary) -> Array[Dictionary]:
	var c := s.character
	var out: Array[Dictionary] = []
	for e: Dictionary in effects(c):
		var id := str(e.get("condition", ""))
		var title := name_of(data, id) if not id.is_empty() else str(e.get("source", {}).get("name", ""))
		var text := str(data["rules"]["conditions"].get(id, "")) if not id.is_empty() else boon_text(data, e)
		out.append({"condition": id, "name": title, "left": left_text(s, e), "source": str(e.get("source", {}).get("name", "")), "text": text})
	if exhaustion(c) > 0:
		out.append({"condition": "exhaustion", "name": "Истощение %d" % exhaustion(c), "left": "до долгого отдыха", "source": "",
			"text": exhaustion_text(exhaustion(c))})
	if not str(c.get("concentration", "")).is_empty():
		var sp := str(c["concentration"])
		var ends := int(c.get("concentration_ends", -1))
		out.append({"condition": "concentration", "name": "Концентрация: %s" % data["spells"].get(sp, {}).get("name", sp),
			"left": left_text(s, {"ends": {"at": ends}} if ends >= 0 else {"ends": {}}).replace("пока не снимут", "пока держится"),
			"source": "", "text": "Урон — спасбросок Телосложения (Сл 10 или половина урона), иначе заклинание прервётся."})
	return out
