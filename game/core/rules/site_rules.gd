class_name SiteRules
extends RefCounted
## Sites (roadmap v0.7.22.24, the author's request): a location holds sites — a building, a yard, a cave — and a site
## holds rooms. A site gives its rooms an owner (an NPC), hours, tags of its kind and whether anyone may walk in
## (`public`, a room may say otherwise: a tavern's hall and rented rooms are public, its kitchen is not). Walking into a
## private room of someone else's site unasked, before eyes — the owner thinks worse of the hero and, where there is
## law, it is a light crime (`trespass`). Unseen (sneaking unnoticed, invisible), asked (the owner goes with the hero)
## or welcome (the owner's friend) — nothing. The author: the first time is a warning only (s.trespass_warned), the
## trespass is the next one; the exit button says a room is private. v0.7.39.2: the owner's leave (`s.permits`, asked by
## a Persuasion check or given by the master's `permit`) opens its private sites until a quarrel; an organization's
## hideout answers a stranger by itself (OrgRules.on_trespass: a warning, then its guards), not by the law; the
## warning comes again after the trespass is punished (CrimeRules._settle).


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"]["sites"]


## "" — the hero may be here; otherwise why not: the owner of this private room is alive and did not ask the hero in.
static func unwelcome(s: GameSession, data: Dictionary, room_id: String) -> String:
	var world := WorldView.new(data["world"])
	var h := DoorRules.hours(s, data, world.site_id(room_id))  # v0.7.22.25: a closed site is nobody's to walk in
	if world.is_public(room_id) and (h.is_empty() or bool(h["open"])):
		return ""
	var owner := str(world.site_of(room_id).get("owner", ""))
	if owner.is_empty() or owner == OwnerRules.HERO or s.dead_npcs.has(owner) or s.followers.has(owner):  # v0.7.27: own place
		return ""
	if s.attitude(owner) >= int(cfg(data)["welcome_attitude"]) or permitted(s, data, world.site_id(room_id)) or StudyRules.student_room(s, data, room_id) \
			or not OrgRules.hideout_of(s, data, room_id).is_empty() or FactionRules.welcome(s, data, owner):  # v0.7.30: own dorm; v0.7.33: own hideout; v0.7.50: its friends
		return ""
	return owner


## On entering `room_id` (GameState._step, after sneaking): who sees a trespass and what follows. Lines.
static func on_enter(s: GameSession, data: Dictionary, room_id: String) -> Array[String]:
	var owner := unwelcome(s, data, room_id)
	if owner.is_empty() or s.sneaking or ConditionRules.invisible(s.character, data):
		return []  # welcome, or nobody saw the hero come in
	var world := WorldView.new(data["world"])
	var site_id := world.site_id(room_id)
	var seen := s.npcs_here(world.world, room_id)
	for r: String in world.site_rooms(site_id):  # the owner anywhere in the site hears the door
		if r != room_id and s.npcs_here(world.world, r).has(owner):
			seen.append(owner)
	if seen.is_empty():
		return []
	var who := ", ".join(seen.map(func(id: String) -> String: return str(world.npc(id).get("name", id))))
	var org := OrgRules.hideout_org(s, data, site_id)
	if not org.is_empty():  # v0.7.39.2: the organization's own ground — its answer, not the law's
		return OrgRules.on_trespass(s, data, org, site_id, who)
	if not s.trespass_warned.has(site_id):  # the first time — a warning
		s.trespass_warned[site_id] = TimeRules.abs_minute(s)
		return ["%s: «Сюда посторонним нельзя — выйдите!» Предупреждение: войдёте сюда снова без спроса — это вторжение" % who]
	var today := TimeRules.abs_minute(s) / 1440
	if s.crimes.any(func(c: Dictionary) -> bool: return str(c.get("kind")) == "trespass" and str(c.get("site", "")) == site_id and int(c["at"]) / 1440 == today):
		return []  # once a day a site
	var lines: Array[String] = ["%s: «Сюда посторонним нельзя!» — вы вошли без спроса (%s)" % [who, world.room_short(room_id).to_lower()]]
	if seen.has(owner):
		s.shift_attitude(owner, int(cfg(data)["trespass_attitude"]), data)
		s.remember(owner, "герой без спроса вошёл ко мне: %s" % world.room_short(room_id))
	lines.append_array(CrimeRules.on_trespass(s, data, owner, room_id, seen))
	return lines


# --- the owner's leave (v0.7.39.2) ------------------------------------------------------------------------------


## The owner let the hero in and they have not quarrelled since (attitude not below `permit.min_attitude`).
static func permitted(s: GameSession, data: Dictionary, site_id: String) -> bool:
	var owner := str(s.permits.get(site_id, ""))
	if not owner.is_empty() and s.attitude(owner) >= int(cfg(data)["permit"]["min_attitude"]):
		return true
	var by := str(WorldView.new(data["world"]).site(site_id).get("owner", ""))  # v0.7.48: the owner's recommendation lets one in
	return not by.is_empty() and not LetterRules.recommender(s, data, [by]).is_empty() and s.attitude(by) >= int(cfg(data)["permit"]["min_attitude"])


## The private sites of `npc_id` the hero may not walk in yet.
static func closed_to_hero(s: GameSession, data: Dictionary, npc_id: String) -> Array[String]:
	var world := WorldView.new(data["world"])
	var out: Array[String] = []
	for sid: String in world.world.get("sites", {}):
		if str(world.site(sid).get("owner", "")) != npc_id or permitted(s, data, sid):
			continue
		if world.site_rooms(sid).any(func(r: String) -> bool: return not unwelcome(s, data, r).is_empty()):
			out.append(sid)
	return out


## Why the hero cannot ask `npc_id` to be let in now ("" — may): nothing of its is closed, asked in vain today.
static func ask_why(s: GameSession, data: Dictionary, npc_id: String) -> String:
	if closed_to_hero(s, data, npc_id).is_empty():
		return "SITE_NOTHING_TO_ASK"
	if int(s.permit_asked.get(npc_id, 0)) == s.day:
		return "SITE_ASKED_TODAY"
	return ""


static func ask_dc(s: GameSession, data: Dictionary, npc_id: String) -> int:
	var p: Dictionary = cfg(data)["permit"]
	var d := SocialRules.dc(s, data, npc_id, str(p["skill"]), str(p["tier"]))
	return int(d.get("dc", int(data["rules"]["dc_tiers"][str(p["tier"])])))


static func ask_bonus(s: GameSession, data: Dictionary) -> int:
	return CheckEngine.bonus_for(s.character, {"skill": str(cfg(data)["permit"]["skill"])}) + DifficultyRules.bonus(s, data)


static func ask_chance(s: GameSession, data: Dictionary, npc_id: String) -> int:
	return JobRules._chance(ask_bonus(s, data), ask_dc(s, data, npc_id), false)


## «Попросить впустить»: Persuasion against the owner; yes — all its private sites open until a quarrel, no — again
## tomorrow. Lines.
static func ask(s: GameSession, data: Dictionary, npc_id: String) -> Array[String]:
	var skill := str(cfg(data)["permit"]["skill"])
	var mods := ConditionRules.check_mods(s.character, data, {"skill": skill})
	var dis := not (mods["disadvantage"] as Array).is_empty()
	var rolls := FeatureRules.hero_d20(s, false, dis)
	var nat: int = rolls.min() if dis else rolls[0]
	var b := ask_bonus(s, data)
	var dc := ask_dc(s, data, npc_id)
	RollParts.note(s, "Просьба впустить", rolls, nat, RollParts.skill(s, data, skill), b, dc)
	var ok := nat == 20 or (nat != 1 and nat + b >= dc)
	var who := BondRules.npc_name(s, data, npc_id)
	var lines: Array[String] = ["Просьба впустить — %s: %s %d %s %d = %d против Сл %d — %s" % [who, CraftRules.tr_skill(data, skill), nat,
		"−" if b < 0 else "+", absi(b), nat + b, dc, "согласие" if ok else "отказ"]]
	if ok:
		lines.append_array(grant(s, data, npc_id))
	else:
		s.permit_asked[npc_id] = s.day
		lines.append("%s не пускает к себе — попросить снова можно завтра" % who)
	return lines


## The owner's leave (the ask, the master's `permit`, an organization's paid entry): `site_id` or every private site
## of the owner; v0.7.41: its hunting grounds too (a room id — WildsRules.closed_grounds). Lines.
static func grant(s: GameSession, data: Dictionary, npc_id: String, site_id: String = "") -> Array[String]:
	var sites: Array[String] = closed_to_hero(s, data, npc_id)
	sites.append_array(WildsRules.closed_grounds(s, data, npc_id))
	if not site_id.is_empty():
		sites = [site_id]
	if sites.is_empty():
		return []
	var world := WorldView.new(data["world"])
	var names := ", ".join(sites.map(func(sid: String) -> String:
		return str(world.site(sid).get("name", world.room(sid).get("name", sid)))))
	for sid: String in sites:
		s.permits[sid] = npc_id
	s.permit_asked.erase(npc_id)
	s.remember(npc_id, "пустил героя к себе: %s" % names)
	return ["%s разрешает входить: %s — пока вы не поссоритесь" % [BondRules.npc_name(s, data, npc_id), names]]


## The master's `permit` (v0.7.39.2, protocol 0.78.0): the owner of the scene agreed by words to let the hero in.
## {plan, summary} or {reason}.
static func make(s: GameSession, data: Dictionary, spec: Dictionary) -> Dictionary:
	var who := str(spec.get("npc_id", ""))
	if not s.npcs_here(data["world"], s.room_id).has(who):
		return {"reason": "%s не в сцене — впустить может только хозяин, который здесь" % who}
	var closed := closed_to_hero(s, data, who)
	closed.append_array(WildsRules.closed_grounds(s, data, who))  # v0.7.41: leave to hunt in its grounds
	if closed.is_empty():
		return {"reason": "у %s нет мест, закрытых для героя: впускать некуда" % BondRules.npc_name(s, data, who)}
	var site := str(spec.get("site_id", "")) if spec.get("site_id") != null else ""
	if not site.is_empty() and not closed.has(site):
		return {"reason": "site_id — одно из мест %s, закрытых для героя: %s" % [BondRules.npc_name(s, data, who), ", ".join(closed)]}
	return {"plan": {"npc_id": who, "site_id": site}, "summary": "%s впускает героя" % BondRules.npc_name(s, data, who)}
