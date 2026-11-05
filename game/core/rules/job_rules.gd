class_name JobRules
extends RefCounted
## Work (roadmap v0.7.26, rules.jobs): a job is data — an employer, the check of a shift, hours, a DC, the pay and
## ranks. The pack's jobs (world.json `jobs`) and the master's (effect `job`). Hired after a check against the
## employer; a shift goes only while the employer is here: the check sets the pay, the tips, the attitude and counts
## good shifts to a promotion. The hero keeps c["jobs"] {id: {rank, good, shifts}} and c["jobs_tried"] {id: day}.
## A job of an organization (v0.7.39.1): `requires.org` {id, rank} — a member of that rank; a good shift adds the
## organization's points (rules.underworld.orgs.job_points). `caught` {crime, room} — a bad shift is a crime known
## to the law (a pickpocket caught); `fight` {chance, foes} — a shift may end in a fight (bandits at a convoy).
## v0.7.39.5: a job is a place in the staff of an object (ObjectRules) — its `site`, else the object the employer lives in.


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"]["jobs"]


static func all(s: GameSession, data: Dictionary) -> Dictionary:
	return WorldGen.registry(s, data, "jobs")


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
	return WorldView.name_of(data, str(job(s, data, id).get("employer", "")))


## The object the job is a place of (v0.7.39.5): its `site`, else the site of the employer's home room.
static func site_of(s: GameSession, data: Dictionary, id: String) -> String:
	var j := job(s, data, id)
	if not str(j.get("site", "")).is_empty():
		return str(j["site"])
	return WorldView.new(data["world"]).site_id(ReputationRules.home_room(data, str(j.get("employer", ""))))


static func rank_name(s: GameSession, data: Dictionary, id: String, r: int) -> String:
	var names: Array = job(s, data, id).get("ranks", cfg(data)["rank_names"])
	return str(names[clampi(r, 0, names.size() - 1)])


static func top_rank(data: Dictionary) -> int:
	return (cfg(data)["ranks"] as Array).size() - 1


static func _rank_cfg(data: Dictionary, r: int) -> Dictionary:
	return cfg(data)["ranks"][clampi(r, 0, top_rank(data))]


## The pay of a shift at the hero's rank (the direction «Работа» counts).
static func pay(s: GameSession, data: Dictionary, id: String, r: int = -1, who: String = Being.HERO) -> int:
	var rr := rank(Life.of(s, who, data), id) if r < 0 else r
	var base := float(job(s, data, id).get("pay_cp", 0)) * float(_rank_cfg(data, rr)["pay"])
	return roundi(base * float(DevelopmentRules.effect(Life.of(s, who, data), data, "work", "pay_pct", 100.0)) / 100.0)


static func dc(s: GameSession, data: Dictionary, id: String, who: String = Being.HERO) -> int:
	return int(job(s, data, id).get("dc", 10)) + int(_rank_cfg(data, rank(Life.of(s, who, data), id))["dc"])


## Good shifts to the next rank.
static func promote_after(s: GameSession, data: Dictionary, who: String = Being.HERO) -> int:
	return maxi(1, roundi(int(cfg(data)["promote_after"]) * float(DevelopmentRules.effect(Life.of(s, who, data), data, "work", "promote_mult", 1.0))))


static func _skilled(c: Dictionary, skill: String) -> bool:
	return (c.get("skill_profs", []) as Array).has(skill) or CharacterRules.has_feature(c, "skill_prof_" + skill)


## What the job asks: [{text, ok}].
static func requirements(s: GameSession, data: Dictionary, id: String, who: String = Being.HERO) -> Array[Dictionary]:
	var j := job(s, data, id)
	var employer := str(j.get("employer", ""))
	return Require.rows(s, data, j.get("requires", {}), {"who": who, "npc": employer, "npc_word": "нанимателем", "tool": str(j.get("tool", "")),
		"skill": str(j.get("skill", "")), "location": ReputationRules.home_of(data, employer)})


static func employer_here(s: GameSession, data: Dictionary, id: String, who: String = Being.HERO) -> bool:
	return s.npcs_here(data["world"], Life.room(s, data, who)).has(str(job(s, data, id).get("employer", "")))


## "" when the hero may ask for the job now, else a localization key.
static func hire_why(s: GameSession, data: Dictionary, id: String, who: String = Being.HERO) -> String:
	if job(s, data, id).is_empty():
		return "JOB_UNKNOWN"
	if hired(Life.of(s, who, data), id):
		return "JOB_HIRED"
	if not employer_here(s, data, id, who):
		return "JOB_EMPLOYER_AWAY"
	var refused := SocialRules.service_why(s, data, str(job(s, data, id)["employer"]), who)
	if not refused.is_empty():
		return refused
	if requirements(s, data, id, who).any(func(r: Dictionary) -> bool: return not bool(r["ok"])):
		return "JOB_REQUIREMENTS"
	var tried: Dictionary = Life.of(s, who, data).get("jobs_tried", {})
	if tried.has(id) and s.day - int(tried[id]) < int(cfg(data)["hire"]["retry_days"]):
		return "JOB_TRIED"
	return ""


## The DC of the interview: the hire skill against the employer (SocialRules), or the tier's.
static func hire_dc(s: GameSession, data: Dictionary, id: String) -> int:
	var h: Dictionary = cfg(data)["hire"]
	var d := SocialRules.dc(s, data, str(job(s, data, id).get("employer", "")), str(h["skill"]), str(h["tier"]))
	return int(d["dc"]) if not d.is_empty() else int(data["rules"]["dc_tiers"][str(h["tier"])])


static func hire_auto(s: GameSession, data: Dictionary, who: String = Being.HERO) -> bool:
	return bool(DevelopmentRules.effect(Life.of(s, who, data), data, "work", "hire_auto", false))


static func hire_chance(s: GameSession, data: Dictionary, id: String, who: String = Being.HERO) -> int:
	if hire_auto(s, data, who):
		return 100
	return Roll.chance_of(s, data, Sheet.who(s, data, who), {"skill": str(cfg(data)["hire"]["skill"]), "dc": hire_dc(s, data, id),
		"target_id": str(job(s, data, id).get("employer", ""))})


## The interview (hire_why first). Lines.
static func hire(s: GameSession, data: Dictionary, id: String, who: String = Being.HERO) -> Array[String]:
	var c := Life.of(s, who, data)
	var name := str(job(s, data, id).get("name", id))
	var lines: Array[String] = []
	if hire_auto(s, data, who):
		lines.append("%s: берут без расспросов — добрая слава" % name)
	else:
		var r := EncounterRules.roll(s, data, str(cfg(data)["hire"]["skill"]), hire_dc(s, data, id), false, who, str(job(s, data, id).get("employer", "")))
		lines.append("%s: %s" % [name, r["line"]])
		if not bool(r["ok"]):
			if not (c.get("jobs_tried") is Dictionary):
				c["jobs_tried"] = {}
			c["jobs_tried"][id] = s.day
			lines.append("Не взяли — можно попробовать снова завтра")
			return lines
	state(c)[id] = {"rank": 0, "good": 0, "shifts": 0}
	lines.append("Нанят: %s — %s, %s за смену" % [rank_name(s, data, id, 0), name, Money.format(pay(s, data, id, -1, who))])
	return lines


static func quit(s: GameSession, data: Dictionary, id: String, who: String = Being.HERO) -> Array[String]:
	state(Life.of(s, who, data)).erase(id)
	return ["Ушёл с работы: %s" % job(s, data, id).get("name", id)]


## "" when a shift may go now, else a localization key.
static func shift_why(s: GameSession, data: Dictionary, id: String, who: String = Being.HERO) -> String:
	var unfree := EncounterRules.unfree_why(s)
	if not unfree.is_empty():
		return unfree
	if not hired(Life.of(s, who, data), id):
		return "JOB_NOT_HIRED"
	if not employer_here(s, data, id, who):
		return "JOB_EMPLOYER_AWAY"
	var org: Dictionary = job(s, data, id).get("requires", {}).get("org", {})
	if not org.is_empty() and not OrgRules.member(Life.of(s, who, data), str(org.get("id", ""))):
		return "JOB_NOT_MEMBER"  # left or expelled: the organization's work is not the hero's any more
	return ""


static func hours(s: GameSession, data: Dictionary, id: String) -> int:
	return int(job(s, data, id).get("hours", 4))


## The check of a shift: {bonus, parts, adv, label}.
static func _check(s: GameSession, data: Dictionary, id: String, who: String = Being.HERO) -> Dictionary:
	var j := job(s, data, id)
	var c := Life.of(s, who, data)
	var skill := str(j.get("skill", ""))
	var tool := str(j.get("tool", ""))
	var adv := bool(DevelopmentRules.effect(c, data, "work", "shift_adv", false))
	var parts: Array[Dictionary] = []
	var label := ""
	if skill.is_empty():
		parts = CraftRules.bonus_parts(s, data, tool, who)
		label = BackgroundRules.tool_name(data, tool)
	else:  # the tool goes by the check's own road (`tool` of the spec)
		parts = RollParts.skill(s, data, skill, who)
		label = CraftRules.tr_skill(data, skill)
	RollParts.development(c, data, "work", "shift_bonus", parts)
	return {"bonus": RollParts.sum(parts), "parts": parts, "adv": adv, "label": label}


## The shift's check for Activity.attempt and the window's chance.
static func shift_spec(s: GameSession, data: Dictionary, id: String, who: String = Being.HERO) -> Dictionary:
	var ch := _check(s, data, id, who)
	return {"what": str(job(s, data, id).get("name", id)), "label": ch["label"], "skill": str(job(s, data, id).get("skill", "craft")), "parts": ch["parts"],
		"bonus": ch["bonus"], "dc": dc(s, data, id, who), "adv": ch["adv"], "ladder": cfg(data)["outcomes"],
		"tool": "" if str(job(s, data, id).get("skill", "")).is_empty() else str(job(s, data, id).get("tool", ""))}


static func shift_chance(s: GameSession, data: Dictionary, id: String, who: String = Being.HERO) -> int:
	return Roll.chance_of(s, data, Sheet.who(s, data, who), shift_spec(s, data, id, who))


## The check of a shift of one's own (v0.8.4.29: a place, a stall — one spec for the roll and the chance it shows): `skill`
## against `dc` with the outcomes of `rules.jobs.outcomes`.
static func work_spec(data: Dictionary, what: String, skill: String, dc_: int) -> Dictionary:
	return {"what": what, "label": CraftRules.tr_skill(data, skill), "skill": skill, "dc": dc_, "ladder": cfg(data)["outcomes"]}


## What a shift's outcome `o` pays of `base` (v0.8.4.29: a job, a place, a stall alike): {pay, tips}; `tips_weight` — how
## much the tips weigh there (a stall's buyers twice); «Работа» may raise the tips.
static func earned(c: Dictionary, data: Dictionary, base: int, o: Dictionary, tips_weight: float = 1.0) -> Dictionary:
	return {"pay": roundi(base * float(o.get("pay", 1.0))),
		"tips": roundi(base * float(o.get("tips", 0.0)) * tips_weight * float(DevelopmentRules.effect(c, data, "work", "tips_mult", 1.0)))}


## The «Работа» experience of a shift's outcome.
static func work_xp(c: Dictionary, data: Dictionary, outcome: String) -> Array[String]:
	return DevelopmentRules.add_xp(c, data, "work", int((DevelopmentRules.direction(data, "work").get("sources", {}) as Dictionary).get(outcome, 0)))


## What a shift broken off pays (v0.8.4.17: a job, a place and a counter alike): its share by the minutes worked, with no
## check.
static func broken_off(full_pay: int, minutes: int, full: int) -> int:
	return roundi(full_pay * float(minutes) / float(maxi(1, full)))


## A shift worked for `minutes` (the time already passed). A shift broken off pays its share without a check.
## {lines, event, fight} — `event` for the master or "", `fight` — the foes of a shift that ends in a fight.
static func shift(s: GameSession, data: Dictionary, id: String, minutes: int, who: String = Being.HERO) -> Dictionary:
	var c := Life.of(s, who, data)
	var j := job(s, data, id)
	var st: Dictionary = state(c)[id]
	var full := hours(s, data, id) * 60
	var lines: Array[String] = []
	if minutes < full:
		var part := broken_off(pay(s, data, id, -1, who), minutes, full)
		Ledger.add(s, part, "job:shift", who)
		lines.append("Смена прервана: %s" % Money.format(part))
		return {"lines": lines, "event": "", "fight": []}
	var a := Activity.attempt(s, data, shift_spec(s, data, id, who), who)
	var o: Dictionary = a["step"]
	var e := earned(c, data, pay(s, data, id, -1, who), o)
	var got := int(e["pay"])
	var tips := int(e["tips"])
	Ledger.add(s, got + tips, "job:shift", who)
	st["shifts"] = int(st.get("shifts", 0)) + 1
	lines.append(str(a["line"]))
	lines.append("Плата: %s%s" % [Money.format(got), (", чаевые %s" % Money.format(tips)) if tips > 0 else ""])
	var employer := str(j.get("employer", ""))
	if int(o.get("attitude", 0)) < 0 and not bool(DevelopmentRules.effect(c, data, "work", "no_attitude_loss", false)):
		if who == Being.HERO:  # what the employer thinks is of the hero
			s.shift_attitude(employer, int(o["attitude"]), data)
		lines.append("%s недоволен" % employer_name(s, data, id))
	var dev := DevelopmentRules.direction(data, "work").get("sources", {}) as Dictionary
	lines.append_array(work_xp(c, data, str(o["id"])))
	if bool(o.get("good", false)):
		st["good"] = int(st.get("good", 0)) + 1
		if int(st["good"]) >= promote_after(s, data, who) and int(st["rank"]) < top_rank(data):
			st["rank"] = int(st["rank"]) + 1
			st["good"] = 0
			if who == Being.HERO:
				s.shift_attitude(employer, 1, data)
			lines.append("Повышение: %s — %s за смену" % [rank_name(s, data, id, int(st["rank"])), Money.format(pay(s, data, id, -1, who))])
			lines.append_array(DevelopmentRules.add_xp(c, data, "work", int(dev.get("promoted", 0))))
	lines.append_array(_org_points(s, data, id, bool(o.get("good", false)), who))
	var caught: Dictionary = j.get("caught", {})
	if not caught.is_empty() and str(o["id"]) == "bad":
		var room := str(caught.get("room", Life.room(s, data, who)))
		lines.append("Попался — крик «держи вора!»")
		lines.append_array(CrimeRules.on_job(s, data, str(caught["crime"]), "", room, WorldView.new(data["world"]).location_id(room), who))
	var fight: Array = []
	var f: Dictionary = j.get("fight", {})
	if not f.is_empty() and s.rng.randf() < float(f.get("chance", 0.0)):
		for i in (f.get("foes", []) as Array).size():
			var foe: Dictionary = (f["foes"][i] as Dictionary).duplicate()
			fight.append(foe)
		lines.append(str(f.get("line", "На смене — нападение!")))
	var event := ""
	var events: Array = j.get("events", cfg(data)["events"])
	if fight.is_empty() and not events.is_empty() and s.rng.randf() < float(cfg(data)["event_chance"]):
		event = str(events[s.rng.randi_range(0, events.size() - 1)])
	return {"lines": lines, "event": event, "fight": fight}


## A good shift of an organization's job counts to the hero's standing there.
static func _org_points(s: GameSession, data: Dictionary, id: String, good: bool, who: String = Being.HERO) -> Array[String]:
	var org := str(job(s, data, id).get("requires", {}).get("org", {}).get("id", ""))
	if org.is_empty() or who != Being.HERO or not OrgRules.member(Life.of(s, who, data), org):  # the points are the hero's
		return []
	var pts: Dictionary = OrgRules.cfg(data).get("job_points", {})
	return OrgRules.add_points(s, data, org, int(pts.get("good" if good else "bad", 0)))


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
	if not s.npcs_here(data["world"], s.room_id).has(employer):
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
