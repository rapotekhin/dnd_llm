class_name JobRules
extends RefCounted
## Work (roadmap v0.7.26, rules.jobs): a job is data — an employer, the check of a shift, hours, a DC, the pay and
## ranks. The pack's jobs (world.json `jobs`) and the master's (effect `job`). Hired after a check against the
## employer; a shift goes only while the employer is here: the check sets the pay, the tips, the attitude and counts
## good shifts to a promotion. The hero keeps c["jobs"] {id: {rank, good, shifts}} and c["jobs_tried"] {id: day}.


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"]["jobs"]


static func all(s: GameSession, data: Dictionary) -> Dictionary:
	var out: Dictionary = (data["world"].get("jobs", {}) as Dictionary).duplicate()
	if s != null:
		out.merge(WorldGen.generated(s).get("jobs", {}), true)
	return out


static func job(s: GameSession, data: Dictionary, id: String) -> Dictionary:
	return all(s, data).get(id, {})


## The jobs an NPC gives.
static func of(s: GameSession, data: Dictionary, npc_id: String) -> Array[String]:
	var out: Array[String] = []
	var jobs := all(s, data)
	for id: String in jobs:
		if str(jobs[id].get("employer", "")) == npc_id:
			out.append(id)
	return out


static func state(c: Dictionary) -> Dictionary:
	if not (c.get("jobs") is Dictionary):
		c["jobs"] = {}
	return c["jobs"]


static func hired(c: Dictionary, id: String) -> bool:
	return state(c).has(id)


static func rank(c: Dictionary, id: String) -> int:
	return int(state(c).get(id, {}).get("rank", 0))


static func employer_name(s: GameSession, data: Dictionary, id: String) -> String:
	return npc_name(s, data, str(job(s, data, id).get("employer", "")))


## A pack's or a made NPC's name.
static func npc_name(s: GameSession, data: Dictionary, npc_id: String) -> String:
	var n := WorldView.new(data["world"]).npc(npc_id)
	if n.is_empty():
		n = WorldGen.generated(s).get("npcs", {}).get(npc_id, {})
	return str(n.get("name", npc_id))


static func rank_name(s: GameSession, data: Dictionary, id: String, r: int) -> String:
	var names: Array = job(s, data, id).get("ranks", cfg(data)["rank_names"])
	return str(names[clampi(r, 0, names.size() - 1)])


static func top_rank(data: Dictionary) -> int:
	return (cfg(data)["ranks"] as Array).size() - 1


static func _rank_cfg(data: Dictionary, r: int) -> Dictionary:
	return cfg(data)["ranks"][clampi(r, 0, top_rank(data))]


## The pay of a shift at the hero's rank (the direction «Работа» counts).
static func pay(s: GameSession, data: Dictionary, id: String, r: int = -1) -> int:
	var rr := rank(s.character, id) if r < 0 else r
	var base := float(job(s, data, id).get("pay_cp", 0)) * float(_rank_cfg(data, rr)["pay"])
	return roundi(base * float(DevelopmentRules.effect(s.character, data, "work", "pay_pct", 100.0)) / 100.0)


static func dc(s: GameSession, data: Dictionary, id: String) -> int:
	return int(job(s, data, id).get("dc", 10)) + int(_rank_cfg(data, rank(s.character, id))["dc"])


## Good shifts to the next rank.
static func promote_after(s: GameSession, data: Dictionary) -> int:
	return maxi(1, roundi(int(cfg(data)["promote_after"]) * float(DevelopmentRules.effect(s.character, data, "work", "promote_mult", 1.0))))


static func _skilled(c: Dictionary, skill: String) -> bool:
	return (c.get("skill_profs", []) as Array).has(skill) or CharacterRules.has_feature(c, "skill_prof_" + skill)


## What the job asks: [{text, ok}].
static func requirements(s: GameSession, data: Dictionary, id: String) -> Array[Dictionary]:
	var j := job(s, data, id)
	var c := s.character
	var req: Dictionary = j.get("requires", {})
	var out: Array[Dictionary] = []
	var n := WorldView.new(data["world"]).npc(str(j.get("employer", "")))
	if not n.is_empty() and not LanguageRules.npc_understands(c, data, n):
		out.append({"text": "общий язык с нанимателем", "ok": false})
	if bool(req.get("tool", false)):
		var tool := str(j.get("tool", ""))
		out.append({"text": "владение: " + BackgroundRules.tool_name(data, tool), "ok": CraftRules.proficient(c, tool)})
	if bool(req.get("skill", false)):
		var skill := str(j.get("skill", ""))
		out.append({"text": "владение навыком: " + CraftRules.tr_skill(data, skill), "ok": _skilled(c, skill)})
	if req.has("language"):
		var lang := str(req["language"])
		out.append({"text": "язык: " + LanguageRules.name_of(data, lang), "ok": LanguageRules.hero(c).has(lang)})
	if req.has("diploma"):  # v0.7.30
		out.append({"text": "грамота выпускника: " + StudyRules.name_of(s, data, str(req["diploma"])), "ok": StudyRules.has_diploma(c, str(req["diploma"]))})
	if req.has("reputation"):
		var loc := ReputationRules.home_of(data, str(j.get("employer", "")))
		out.append({"text": "слава в поселении не ниже «%s»" % ReputationRules.word(data, int(req["reputation"])),
			"ok": not ReputationRules.is_settlement(data, loc) or ReputationRules.step(s, data, loc) >= int(req["reputation"])})
	return out


static func employer_here(s: GameSession, data: Dictionary, id: String) -> bool:
	return SceneRules.npcs(s, data["world"], s.room_id).has(str(job(s, data, id).get("employer", "")))


## "" when the hero may ask for the job now, else a localization key.
static func hire_why(s: GameSession, data: Dictionary, id: String) -> String:
	if job(s, data, id).is_empty():
		return "JOB_UNKNOWN"
	if hired(s.character, id):
		return "JOB_HIRED"
	if not employer_here(s, data, id):
		return "JOB_EMPLOYER_AWAY"
	if SocialRules.refuses(s, data, str(job(s, data, id)["employer"])):
		return "TALK_REFUSED"
	if requirements(s, data, id).any(func(r: Dictionary) -> bool: return not bool(r["ok"])):
		return "JOB_REQUIREMENTS"
	var tried: Dictionary = s.character.get("jobs_tried", {})
	if tried.has(id) and s.day - int(tried[id]) < int(cfg(data)["hire"]["retry_days"]):
		return "JOB_TRIED"
	return ""


## The DC of the interview: the hire skill against the employer (SocialRules), or the tier's.
static func hire_dc(s: GameSession, data: Dictionary, id: String) -> int:
	var h: Dictionary = cfg(data)["hire"]
	var d := SocialRules.dc(s, data, str(job(s, data, id).get("employer", "")), str(h["skill"]), str(h["tier"]))
	return int(d["dc"]) if not d.is_empty() else int(data["rules"]["dc_tiers"][str(h["tier"])])


static func hire_auto(s: GameSession, data: Dictionary) -> bool:
	return bool(DevelopmentRules.effect(s.character, data, "work", "hire_auto", false))


static func hire_chance(s: GameSession, data: Dictionary, id: String) -> int:
	if hire_auto(s, data):
		return 100
	var b := CheckEngine.bonus_for(s.character, {"skill": str(cfg(data)["hire"]["skill"])}) + DifficultyRules.bonus(s, data)
	return _chance(b, hire_dc(s, data, id), false)


static func _chance(b: int, need: int, adv: bool) -> int:
	var wins := 0
	for nat in range(1, 21):
		if nat == 20 or (nat != 1 and nat + b >= need):
			wins += 1
	var p := wins / 20.0
	return roundi((1.0 - (1.0 - p) * (1.0 - p) if adv else p) * 100.0)


## The interview (hire_why first). Lines.
static func hire(s: GameSession, data: Dictionary, id: String) -> Array[String]:
	var c := s.character
	var name := str(job(s, data, id).get("name", id))
	var lines: Array[String] = []
	if hire_auto(s, data):
		lines.append("%s: берут без расспросов — добрая слава" % name)
	else:
		var r := EncounterRules.roll(s, data, str(cfg(data)["hire"]["skill"]), hire_dc(s, data, id))
		lines.append("%s: %s" % [name, r["line"]])
		if not bool(r["ok"]):
			if not (c.get("jobs_tried") is Dictionary):
				c["jobs_tried"] = {}
			c["jobs_tried"][id] = s.day
			lines.append("Не взяли — можно попробовать снова завтра")
			return lines
	state(c)[id] = {"rank": 0, "good": 0, "shifts": 0}
	lines.append("Нанят: %s — %s, %s за смену" % [rank_name(s, data, id, 0), name, Money.format(pay(s, data, id))])
	return lines


static func quit(s: GameSession, data: Dictionary, id: String) -> Array[String]:
	state(s.character).erase(id)
	return ["Ушёл с работы: %s" % job(s, data, id).get("name", id)]


## "" when a shift may go now, else a localization key.
static func shift_why(s: GameSession, data: Dictionary, id: String) -> String:
	if not hired(s.character, id):
		return "JOB_NOT_HIRED"
	if not employer_here(s, data, id):
		return "JOB_EMPLOYER_AWAY"
	return ""


static func hours(s: GameSession, data: Dictionary, id: String) -> int:
	return int(job(s, data, id).get("hours", 4))


## The check of a shift: {bonus, adv, label}.
static func _check(s: GameSession, data: Dictionary, id: String) -> Dictionary:
	var j := job(s, data, id)
	var c := s.character
	var skill := str(j.get("skill", ""))
	var tool := str(j.get("tool", ""))
	var extra := int(DevelopmentRules.effect(c, data, "work", "shift_bonus", 0.0))
	var adv := bool(DevelopmentRules.effect(c, data, "work", "shift_adv", false))
	if skill.is_empty():
		return {"bonus": CraftRules.bonus(s, data, tool) + extra, "adv": adv, "label": BackgroundRules.tool_name(data, tool)}
	var t := BackgroundRules.tool_check(c, data, tool, skill)
	return {"bonus": CheckEngine.bonus_for(c, {"skill": skill}) + int(t["bonus"]) + DifficultyRules.bonus(s, data) + extra,
		"adv": adv or not str(t["advantage"]).is_empty(), "label": CraftRules.tr_skill(data, skill)}


static func shift_chance(s: GameSession, data: Dictionary, id: String) -> int:
	var ch := _check(s, data, id)
	return _chance(int(ch["bonus"]), dc(s, data, id), bool(ch["adv"]))


static func outcome_for(data: Dictionary, margin: int) -> Dictionary:
	var out: Dictionary = cfg(data)["outcomes"][0]
	for o: Dictionary in cfg(data)["outcomes"]:
		if margin >= int(o["from"]):
			out = o
	return out


## A shift worked for `minutes` (the time already passed). A shift broken off pays its share without a check.
## {lines, event} — `event` for the master or "".
static func shift(s: GameSession, data: Dictionary, id: String, minutes: int) -> Dictionary:
	var c := s.character
	var j := job(s, data, id)
	var st: Dictionary = state(c)[id]
	var full := hours(s, data, id) * 60
	var lines: Array[String] = []
	if minutes < full:
		var part := roundi(pay(s, data, id) * float(minutes) / float(full))
		c["gold_cp"] = int(c.get("gold_cp", 0)) + part
		lines.append("Смена прервана: %s" % Money.format(part))
		return {"lines": lines, "event": ""}
	var ch := _check(s, data, id)
	var mods := ConditionRules.check_mods(c, data, {"skill": str(j.get("skill", "craft"))})
	var dis := not (mods["disadvantage"] as Array).is_empty()
	var rolls := FeatureRules.hero_d20(s, bool(ch["adv"]), dis)
	var nat: int = rolls.max() if bool(ch["adv"]) and not dis else rolls.min() if dis and not bool(ch["adv"]) else rolls[0]
	var d := dc(s, data, id)
	var total := nat + int(ch["bonus"])
	var margin := 5 if nat == 20 else -5 if nat == 1 else total - d
	var o := outcome_for(data, margin)
	var got := roundi(pay(s, data, id) * float(o.get("pay", 1.0)))
	var tips := roundi(pay(s, data, id) * float(o.get("tips", 0.0)) * float(DevelopmentRules.effect(c, data, "work", "tips_mult", 1.0)))
	c["gold_cp"] = int(c.get("gold_cp", 0)) + got + tips
	st["shifts"] = int(st.get("shifts", 0)) + 1
	lines.append("%s: %s %d + %d = %d против Сл %d — %s" % [j.get("name", id), ch["label"], nat, total - nat, total, d, o["name"]])
	lines.append("Плата: %s%s" % [Money.format(got), (", чаевые %s" % Money.format(tips)) if tips > 0 else ""])
	var employer := str(j.get("employer", ""))
	if int(o.get("attitude", 0)) < 0 and not bool(DevelopmentRules.effect(c, data, "work", "no_attitude_loss", false)):
		s.shift_attitude(employer, int(o["attitude"]), data)
		lines.append("%s недоволен" % employer_name(s, data, id))
	var dev := DevelopmentRules.direction(data, "work").get("sources", {}) as Dictionary
	lines.append_array(DevelopmentRules.add_xp(c, data, "work", int(dev.get(str(o["id"]), 0))))
	if bool(o.get("good", false)):
		st["good"] = int(st.get("good", 0)) + 1
		if int(st["good"]) >= promote_after(s, data) and int(st["rank"]) < top_rank(data):
			st["rank"] = int(st["rank"]) + 1
			st["good"] = 0
			s.shift_attitude(employer, 1, data)
			lines.append("Повышение: %s — %s за смену" % [rank_name(s, data, id, int(st["rank"])), Money.format(pay(s, data, id))])
			lines.append_array(DevelopmentRules.add_xp(c, data, "work", int(dev.get("promoted", 0))))
	var event := ""
	var events: Array = j.get("events", cfg(data)["events"])
	if not events.is_empty() and s.rng.randf() < float(cfg(data)["event_chance"]):
		event = str(events[s.rng.randi_range(0, events.size() - 1)])
	return {"lines": lines, "event": event}


## For the master: «Работа (…): Подавальщик в «Хромом олене» — подавальщик, наниматель Бруно Хмель, смен 3».
static func text(s: GameSession, data: Dictionary) -> String:
	var parts: Array[String] = []
	for id: String in state(s.character):
		if job(s, data, id).is_empty():
			continue
		var st: Dictionary = state(s.character)[id]
		parts.append("%s — %s, наниматель %s, смен %d" % [job(s, data, id).get("name", id), rank_name(s, data, id, int(st["rank"])),
			employer_name(s, data, id), int(st.get("shifts", 0))])
	return ("Работа (кнопка «Смена» на панели, когда наниматель рядом): " + "; ".join(parts)) if not parts.is_empty() else ""


# --- the master's jobs ------------------------------------------------------------------------------------------


## A job the master makes at an employer of the scene: checked against rules.jobs.make. {id, def} or {reason}.
static func make(s: GameSession, data: Dictionary, spec: Dictionary) -> Dictionary:
	var m: Dictionary = cfg(data)["make"]
	var employer := str(spec.get("employer_id", ""))
	if not SceneRules.npcs(s, data["world"], s.room_id).has(employer):
		return {"reason": "наниматель %s не в сцене — работу даёт только тот, кто здесь" % employer}
	var skill := str(spec.get("skill", "")) if spec.get("skill") != null else ""
	var tool := str(spec.get("tool", "")) if spec.get("tool") != null else ""
	if skill.is_empty() and tool.is_empty():
		return {"reason": "нужен skill (проверка смены) или tool"}
	if not skill.is_empty() and not (s.character.get("skills", {}) as Dictionary).has(skill):
		return {"reason": "навыка %s нет; можно: %s" % [skill, ", ".join((s.character.get("skills", {}) as Dictionary).keys())]}
	if not tool.is_empty() and not CraftRules.cfg(data)["tools"].has(tool):
		return {"reason": "инструмент %s движку неизвестен; можно: %s" % [tool, ", ".join(CraftRules.cfg(data)["tools"].keys())]}
	var h := int(spec.get("hours", 4))
	if h < int(m["hours"][0]) or h > int(m["hours"][1]):
		return {"reason": "hours — от %d до %d" % [m["hours"][0], m["hours"][1]]}
	var tier := str(spec.get("dc_tier", "easy"))
	if not (m["dc_tiers"] as Array).has(tier):
		return {"reason": "dc_tier — из %s" % ", ".join(m["dc_tiers"])}
	var cap := int(m["pay_cp_hour"][tier]) * h
	var p := int(spec.get("pay_cp", 0))
	if p <= 0 or p > cap:
		return {"reason": "pay_cp — от 1 до %s за смену (%d ч, %s)" % [Money.format(cap), h, tier]}
	var name := str(spec.get("name", "")).strip_edges().left(60)
	if name.is_empty():
		return {"reason": "нужно name — как называется работа"}
	var id := "gen_j_" + ("%s|%s" % [employer, name]).md5_text().left(8)
	if all(s, data).has(id):
		return {"reason": "такая работа у этого нанимателя уже есть"}
	for other: String in of(s, data, employer):
		if str(job(s, data, other).get("name", "")) == name:
			return {"reason": "такая работа у этого нанимателя уже есть: " + other}
	var def := {"employer": employer, "name": name, "hours": h, "dc": int(data["rules"]["dc_tiers"][tier]), "pay_cp": p, "generated": true}
	if not skill.is_empty():
		def["skill"] = skill
	if not tool.is_empty():
		def["tool"] = tool
	if bool(spec.get("requires_tool", false)) and not tool.is_empty():
		def["requires"] = {"tool": true}
	var ranks: Variant = spec.get("ranks")
	if ranks is Array and (ranks as Array).size() == (cfg(data)["ranks"] as Array).size():
		def["ranks"] = (ranks as Array).map(func(r: Variant) -> String: return str(r).left(40))
	return {"id": id, "def": def}


static func apply_make(s: GameSession, _data: Dictionary, plan: Dictionary) -> Array[String]:
	var gen := WorldGen.generated(s)
	var jobs: Dictionary = gen.get("jobs", {})
	jobs[str(plan["id"])] = plan["def"]
	gen["jobs"] = jobs
	return ["Новая работа: %s — наймитесь у нанимателя (кнопка «Работа»)" % plan["def"]["name"]]
