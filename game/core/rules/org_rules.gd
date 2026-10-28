class_name OrgRules
extends RefCounted
## Organizations (roadmap v0.7.33, the author: joining and ranks, jobs and a cut, a hideout, founding one's own; the
## guard never learns of a membership). An organization — world.json `orgs` or generated.orgs (the master's `org`, the
## hero's own): {name, kind, head (an NPC or "hero"), hideout (a site), fence, cut_pct, trial, heists, ranks, members,
## place}. c.orgs {id: {points, joined, candidate, owed_cp, owed_day, expelled_day}}. Joining at the head: the trial
## job first when there is one. A job of the organization moves the points (rules.underworld.rep) and owes the cut of
## its money to the head; unpaid past owe_days — expelled and the head an enemy. Ranks by points (`ranks` or
## default_ranks); perks by rank index: rest in the hideout, the guard does not look there, the fence pays more.
## The hero founds one in an owned place (`found_fee_cp`); friends of the hero join it and bring member_income_cp a day
## into the place's till — each may be caught by the guard and leave.


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"]["underworld"]["orgs"]


static func all(s: GameSession, data: Dictionary) -> Dictionary:
	var out: Dictionary = (data["world"].get("orgs", {}) as Dictionary).duplicate()
	out.merge(WorldGen.generated(s).get("orgs", {}))
	return out


static func def(s: GameSession, data: Dictionary, id: String) -> Dictionary:
	return all(s, data).get(id, {})


static func view(c: Dictionary) -> Dictionary:
	return c.get("orgs", {})


static func _st(c: Dictionary, id: String) -> Dictionary:
	if not (c.get("orgs") is Dictionary):
		c["orgs"] = {}
	if not c["orgs"].has(id):
		c["orgs"][id] = {"points": 0, "owed_cp": 0}
	return c["orgs"][id]


static func of_head(s: GameSession, data: Dictionary, npc_id: String) -> Array[String]:
	var out: Array[String] = []
	var orgs := all(s, data)
	for id: String in orgs:
		if str(orgs[id].get("head", "")) == npc_id:
			out.append(id)
	return out


static func own(s: GameSession, data: Dictionary) -> String:
	return of_head(s, data, OwnerRules.HERO)[0] if not of_head(s, data, OwnerRules.HERO).is_empty() else ""


static func member(c: Dictionary, id: String) -> bool:
	var st: Dictionary = view(c).get(id, {})
	return st.has("joined") and not st.has("expelled_day")


static func candidate(c: Dictionary, id: String) -> bool:
	var st: Dictionary = view(c).get(id, {})
	return bool(st.get("candidate", false)) and not st.has("expelled_day")


## The organizations the hero belongs to (own one too).
static func mine(s: GameSession, data: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for id: String in all(s, data):
		if member(s.character, id) or candidate(s.character, id) or str(def(s, data, id).get("head", "")) == OwnerRules.HERO:
			out.append(id)
	return out


static func ranks(s: GameSession, data: Dictionary, id: String) -> Array:
	return def(s, data, id).get("ranks", cfg(data)["default_ranks"])


static func rank(s: GameSession, data: Dictionary, id: String) -> int:
	var pts := int(view(s.character).get(id, {}).get("points", 0))
	var r := 0
	var list := ranks(s, data, id)
	for i in list.size():
		if pts >= int(list[i]["at"]):
			r = i
	return r


static func rank_name(s: GameSession, data: Dictionary, id: String) -> String:
	if str(def(s, data, id).get("head", "")) == OwnerRules.HERO:
		return "глава"
	return str(ranks(s, data, id)[rank(s, data, id)]["name"])


static func next_at(s: GameSession, data: Dictionary, id: String) -> int:
	var list := ranks(s, data, id)
	var r := rank(s, data, id)
	return int(list[r + 1]["at"]) if r + 1 < list.size() else 0


static func perk(s: GameSession, data: Dictionary, id: String, name: String) -> bool:
	if str(def(s, data, id).get("head", "")) == OwnerRules.HERO:
		return true
	return member(s.character, id) and rank(s, data, id) >= int(cfg(data)["perks"].get(name, 99))


static func org_name(s: GameSession, data: Dictionary, id: String) -> String:
	return str(def(s, data, id).get("name", id))


## What the organization is called in the lines: its `word` (v0.7.39.1: «артель»), a band by default — in the
## cases the lines use: {nom, gen, dat, prep}.
static func word(s: GameSession, data: Dictionary, id: String) -> Dictionary:
	var w: Variant = def(s, data, id).get("word")
	if w is Dictionary:
		return w
	return {"nom": "братство", "gen": "братства", "dat": "братству", "prep": "братстве", "acc": "братство"}


## The jobs (JobRules) that ask a membership of the organization (v0.7.39.1).
static func jobs_of(s: GameSession, data: Dictionary, id: String) -> Array[String]:
	var out: Array[String] = []
	var jobs := JobRules.all(s, data)
	for j: String in jobs:
		if str(jobs[j].get("requires", {}).get("org", {}).get("id", "")) == id:
			out.append(j)
	return out


## Points of standing moved by a deed outside the jobs of HeistRules (a shift of the organization's work). Lines.
static func add_points(s: GameSession, data: Dictionary, id: String, pts: int) -> Array[String]:
	if pts == 0 or not member(s.character, id):
		return []
	var st := _st(s.character, id)
	var before := rank(s, data, id)
	st["points"] = maxi(0, int(st.get("points", 0)) + pts)
	if rank(s, data, id) > before:
		return ["%s «%s»: вы теперь — %s" % [str(word(s, data, id)["nom"]).capitalize(), org_name(s, data, id), rank_name(s, data, id)]]
	return []


static func head_name(s: GameSession, data: Dictionary, id: String) -> String:
	var h := str(def(s, data, id).get("head", ""))
	return "вы" if h == OwnerRules.HERO else BondRules.npc_name(s, data, h)


# --- the hideout and the fence ------------------------------------------------------------------------------------


static func hideout_site(s: GameSession, data: Dictionary, id: String) -> String:
	var d := def(s, data, id)
	if d.has("place"):
		return str(PropertyRules.prop(s, data, str(d["place"])).get("site", ""))
	return str(d.get("hideout", ""))


## The organization whose hideout the room is and the hero may use it with `perk_name` ("" — none).
static func hideout_of(s: GameSession, data: Dictionary, room_id: String, perk_name: String = "") -> String:
	var site := WorldView.new(data["world"]).site_id(room_id)
	if site.is_empty():
		return ""
	for id: String in mine(s, data):
		if hideout_site(s, data, id) == site and (member(s.character, id) or str(def(s, data, id).get("head", "")) == OwnerRules.HERO) \
				and (perk_name.is_empty() or perk(s, data, id, perk_name)):
			return id
	return ""


## The organization whose hideout `site_id` is, the hero's or not ("" — none). v0.7.39.2
static func hideout_org(s: GameSession, data: Dictionary, site_id: String) -> String:
	if site_id.is_empty():
		return ""
	for id: String in all(s, data):
		if hideout_site(s, data, id) == site_id:
			return id
	return ""


## The organization whose hideout the hero may pay to walk into from this room — the hideout itself or a room with
## a way into it ("" — none). v0.7.39.2
static func entry_here(s: GameSession, data: Dictionary) -> String:
	var world := WorldView.new(data["world"])
	var rooms: Array[String] = [s.room_id]
	for e: Variant in world.room(s.room_id).get("exits", []):
		rooms.append(str(e.get("to", "")) if e is Dictionary else str(e))
	for r: String in rooms:
		var id := hideout_org(s, data, world.site_id(r))
		if not id.is_empty() and def(s, data, id).has("entry_cp"):
			return id
	return ""


## Why the hero cannot pay the hideout's entry ("" — may).
static func entry_why(s: GameSession, data: Dictionary, id: String) -> String:
	var d := def(s, data, id)
	if not d.has("entry_cp"):
		return "ORG_NO_ENTRY"
	if member(s.character, id) or SiteRules.permitted(s, data, hideout_site(s, data, id)):
		return "ORG_ENTRY_OPEN"
	if view(s.character).get(id, {}).has("expelled_day"):
		return "ORG_ENTRY_REFUSED"
	if int(s.character.get("gold_cp", 0)) < int(d["entry_cp"]):
		return "MSG_NO_MONEY"
	return ""


## The entry paid: the head's leave to walk into the hideout until a quarrel (SiteRules.grant). Lines.
static func pay_entry(s: GameSession, data: Dictionary, id: String) -> Array[String]:
	var d := def(s, data, id)
	var fee := int(d["entry_cp"])
	s.character["gold_cp"] = int(s.character.get("gold_cp", 0)) - fee
	var lines: Array[String] = ["%s: вход оплачен — %s" % [org_name(s, data, id), Money.format(fee)]]
	lines.append_array(SiteRules.grant(s, data, str(d.get("head", "")), hideout_site(s, data, id)))
	return lines


## A stranger in the hideout before eyes (SiteRules.on_enter): the organization answers, not the law — the first time
## a warning, then its `guards` fall on the hero (s.pending_fight); the head thinks worse each time. Lines.
static func on_trespass(s: GameSession, data: Dictionary, id: String, site_id: String, who: String) -> Array[String]:
	var d := def(s, data, id)
	var head := str(d.get("head", ""))
	if not head.is_empty() and head != OwnerRules.HERO:
		s.shift_attitude(head, int(SiteRules.cfg(data)["trespass_attitude"]), data)
		s.remember(head, "герой без спроса влез в наше логово")
	var fee := " — вход за плату: %s" % Money.format(int(d["entry_cp"])) if d.has("entry_cp") else ""
	if not s.trespass_warned.has(site_id):
		s.trespass_warned[site_id] = TimeRules.abs_minute(s)
		return ["%s: «Чужим тут не место%s. Уходи — второй раз так не отпустим»" % [who, fee]]
	var foes: Array = []
	for g: Dictionary in d.get("guards", []):
		for i in int(g.get("count", 1)):
			var foe := {"monster": str(g["monster"]), "col": 0}
			if g.has("name"):
				foe["name"] = str(g["name"])
			foes.append(foe)
	if foes.is_empty():
		return ["%s: «Опять ты? Пошёл вон!»" % who]
	s.pending_fight = foes
	var names := {}
	for f: Dictionary in foes:
		var n := str(f.get("name", data["monsters"].get(str(f["monster"]), {}).get("name", f["monster"])))
		names[n] = int(names.get(n, 0)) + 1
	return ["%s: «Предупреждали!» — на вас бросаются: %s" % [who, ", ".join(names.keys().map(func(n: String) -> String:
		return n + (" ×%d" % int(names[n]) if int(names[n]) > 1 else "")))]]


## The organizations the fence works for that the hero belongs to.
static func fencing_for(s: GameSession, data: Dictionary, npc_id: String) -> Array[String]:
	var out: Array[String] = []
	for id: String in mine(s, data):
		if str(def(s, data, id).get("fence", "")) == npc_id and member(s.character, id):
			out.append(id)
	return out


static func fence_perk(s: GameSession, data: Dictionary, npc_id: String) -> bool:
	return fencing_for(s, data, npc_id).any(func(id: String) -> bool: return perk(s, data, id, "fence_member"))


# --- joining ------------------------------------------------------------------------------------------------------


static func join_why(s: GameSession, data: Dictionary, id: String) -> String:
	var d := def(s, data, id)
	if d.is_empty() or str(d.get("head", "")) == OwnerRules.HERO:
		return "ORG_NONE"
	if not BondRules.here(s, data, str(d["head"])):
		return "BOND_NOT_HERE"
	if member(s.character, id):
		return "ORG_MEMBER"
	if candidate(s.character, id):
		return "ORG_TRIAL_ACTIVE"
	var st: Dictionary = view(s.character).get(id, {})
	if st.has("expelled_day") and s.day - int(st["expelled_day"]) < int(cfg(data)["rejoin_days"]):
		return "ORG_EXPELLED"
	if SocialRules.refuses(s, data, str(d["head"])):
		return "BOND_REFUSES"
	return ""


## Joining: the trial job first when the organization has one. Lines.
static func join(s: GameSession, data: Dictionary, id: String) -> Array[String]:
	var d := def(s, data, id)
	var st := _st(s.character, id)
	st.erase("expelled_day")
	var trial := str(d.get("trial", ""))
	if not trial.is_empty() and HeistRules.status(s.character, trial) != "done":
		st["candidate"] = true
		var lines: Array[String] = ["%s: «Сперва покажи себя» — испытание: «%s»" % [head_name(s, data, id), HeistRules.def(s, data, trial)["name"]]]
		if HeistRules.status(s.character, trial) == "failed":
			HeistRules.view(s.character).erase(trial)
		lines.append_array(HeistRules.take(s, data, trial))
		return lines
	return _accept(s, data, id)


static func _accept(s: GameSession, data: Dictionary, id: String) -> Array[String]:
	var st := _st(s.character, id)
	st["joined"] = s.day
	st.erase("candidate")
	var w := word(s, data, id)
	s.remember(str(def(s, data, id)["head"]), "принял героя в %s «%s»" % [w["acc"], org_name(s, data, id)])
	var cut := int(def(s, data, id).get("cut_pct", 0))
	var lines: Array[String] = ["Вы приняты в %s «%s»: %s%s" % [w["acc"], org_name(s, data, id), rank_name(s, data, id),
		(", доля с дел — %d%%" % cut) if not (def(s, data, id).get("heists", []) as Array).is_empty() else ""]]
	return lines


static func leave(s: GameSession, data: Dictionary, id: String) -> Array[String]:
	var st := _st(s.character, id)
	st.erase("joined")
	st.erase("candidate")
	st["expelled_day"] = s.day
	return ["Вы ушли из %s «%s»" % [word(s, data, id)["gen"], org_name(s, data, id)]]


## The jobs the organization offers the hero now.
static func offered(s: GameSession, data: Dictionary, id: String) -> Array[String]:
	var out: Array[String] = []
	if not member(s.character, id):
		return out
	for h: Variant in def(s, data, id).get("heists", []):
		if HeistRules.status(s.character, str(h)).is_empty() and not HeistRules.def(s, data, str(h)).is_empty():
			out.append(str(h))
	for h: String in WorldGen.generated(s).get("heists", {}):
		if str(WorldGen.generated(s)["heists"][h].get("org", "")) == id and HeistRules.status(s.character, h).is_empty():
			out.append(h)
	return out


static func take_why(s: GameSession, data: Dictionary, id: String, heist: String) -> String:
	if not BondRules.here(s, data, str(def(s, data, id).get("head", ""))):
		return "BOND_NOT_HERE"
	if not offered(s, data, id).has(heist):
		return "HEIST_TAKEN"
	return ""


## A job of the organization ended: the trial accepts, the points move, the cut is owed. Lines.
static func on_heist(s: GameSession, data: Dictionary, heist: String, outcome: String, money_cp: int) -> Array[String]:
	var id := str(HeistRules.def(s, data, heist).get("org", ""))
	if id.is_empty() or def(s, data, id).is_empty() or str(def(s, data, id).get("head", "")) == OwnerRules.HERO:
		return []
	var lines: Array[String] = []
	var st := _st(s.character, id)
	if bool(st.get("candidate", false)) and str(def(s, data, id).get("trial", "")) == heist:
		if outcome == "fail":
			st.erase("candidate")
			return ["Испытание братства «%s» провалено — глава ждёт другого раза" % org_name(s, data, id)]
		lines.append_array(_accept(s, data, id))
	if not member(s.character, id):
		return lines
	var before := rank(s, data, id)
	st["points"] = maxi(0, int(st.get("points", 0)) + int(data["rules"]["underworld"]["rep"].get(outcome, 0)))
	var cut := money_cp * int(def(s, data, id).get("cut_pct", 0)) / 100
	if cut > 0:
		if int(st.get("owed_cp", 0)) == 0:
			st["owed_day"] = s.day
		st["owed_cp"] = int(st.get("owed_cp", 0)) + cut
		lines.append("Доля братству «%s»: %s — отдать главе за %d дн." % [org_name(s, data, id), Money.format(cut), int(cfg(data)["owe_days"])])
	if rank(s, data, id) > before:
		lines.append("%s «%s»: вы теперь — %s" % [str(word(s, data, id)["nom"]).capitalize(), org_name(s, data, id), rank_name(s, data, id)])
	return lines


static func pay_why(s: GameSession, data: Dictionary, id: String) -> String:
	var owed := int(view(s.character).get(id, {}).get("owed_cp", 0))
	if owed <= 0:
		return "ORG_NOTHING_OWED"
	if not BondRules.here(s, data, str(def(s, data, id).get("head", ""))):
		return "BOND_NOT_HERE"
	if int(s.character.get("gold_cp", 0)) < owed:
		return "TRADE_ERR_NO_COINS"
	return ""


static func pay(s: GameSession, data: Dictionary, id: String) -> Array[String]:
	var st := _st(s.character, id)
	var owed := int(st["owed_cp"])
	s.character["gold_cp"] = int(s.character["gold_cp"]) - owed
	st["owed_cp"] = 0
	st.erase("owed_day")
	return ["Доля отдана главе (%s): %s" % [head_name(s, data, id), Money.format(owed)]]


# --- one's own ----------------------------------------------------------------------------------------------------


## The hero's places that may be a hideout: owned places not a hideout yet.
static func places(s: GameSession, data: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for id: String in s.character.get("property", {}):
		out.append(id)
	return out


static func found_why(s: GameSession, data: Dictionary, name: String, place: String) -> String:
	if not own(s, data).is_empty():
		return "ORG_HAS_OWN"
	if not places(s, data).has(place):
		return "ORG_NO_PLACE"
	if name.strip_edges().is_empty():
		return "ORG_BAD_NAME"
	if int(s.character.get("gold_cp", 0)) < int(cfg(data)["found_fee_cp"]):
		return "TRADE_ERR_NO_COINS"
	return ""


static func found(s: GameSession, data: Dictionary, name: String, place: String) -> Array[String]:
	var gen := WorldGen.generated(s)
	var orgs: Dictionary = gen.get("orgs", {})
	var nm := name.strip_edges().left(40)
	orgs["own"] = {"name": nm, "kind": "criminal", "head": OwnerRules.HERO, "place": place, "members": [], "cut_pct": 0, "generated": true}
	gen["orgs"] = orgs
	s.character["gold_cp"] = int(s.character["gold_cp"]) - int(cfg(data)["found_fee_cp"])
	return ["Основано братство «%s» — логово в «%s», %s на обзаведение" % [nm, PropertyRules.name_of(s, data, place), Money.format(int(cfg(data)["found_fee_cp"]))],
		"Зовите друзей в братство — кнопка «В братство» у NPC"]


static func members(s: GameSession, data: Dictionary, id: String) -> Array[String]:
	var out: Array[String] = []
	for m: Variant in def(s, data, id).get("members", []):
		if not s.dead_npcs.has(str(m)):
			out.append(str(m))
	return out


static func recruit_why(s: GameSession, data: Dictionary, npc_id: String) -> String:
	var id := own(s, data)
	if id.is_empty():
		return "ORG_NONE"
	if not BondRules.here(s, data, npc_id):
		return "BOND_NOT_HERE"
	if members(s, data, id).has(npc_id):
		return "ORG_MEMBER"
	if members(s, data, id).size() >= int(cfg(data)["max_members"]):
		return "ORG_FULL"
	var tags: Array = BondRules.npc_def(s, data, npc_id).get("tags", [])
	if (cfg(data)["law_tags"] as Array).any(func(t: Variant) -> bool: return tags.has(t)) or not of_head(s, data, npc_id).is_empty():
		return "ORG_NOT_FOR_HIM"
	if BondRules.points(s.character, npc_id) < int(cfg(data)["recruit_bond"]):
		return "ORG_NOT_CLOSE"
	return ""


static func recruit(s: GameSession, data: Dictionary, npc_id: String) -> Array[String]:
	var id := own(s, data)
	var d: Dictionary = WorldGen.generated(s)["orgs"][id]
	(d["members"] as Array).append(npc_id)
	s.remember(npc_id, "вступил в братство героя «%s»" % d["name"])
	return ["%s — в братстве «%s»: доход %s в день в кассу логова" % [BondRules.npc_name(s, data, npc_id), d["name"], Money.format(int(cfg(data)["member_income_cp"]))]]


# --- days ---------------------------------------------------------------------------------------------------------


## Unpaid cuts past owe_days expel; the hero's own members bring their income or get caught. Lines.
static func tick(s: GameSession, data: Dictionary) -> Array[String]:
	if not data["rules"].has("underworld"):
		return []
	var lines: Array[String] = []
	var c := s.character
	for id: String in view(c):
		var st: Dictionary = view(c)[id]
		if member(c, id) and int(st.get("owed_cp", 0)) > 0 and s.day - int(st.get("owed_day", s.day)) > int(cfg(data)["owe_days"]):
			st.erase("joined")
			st["expelled_day"] = s.day
			st["owed_cp"] = 0
			var head := str(def(s, data, id).get("head", ""))
			lines.append("Братство «%s» изгоняет вас: доля не отдана" % org_name(s, data, id))
			lines.append_array(BondRules.add(s, data, head, int(cfg(data)["expel_bond"]), "не отдал долю"))
	var own_id := own(s, data)
	if own_id.is_empty():
		return lines
	var d: Dictionary = WorldGen.generated(s)["orgs"][own_id]
	var place := str(d.get("place", ""))
	var owned: Dictionary = c.get("property", {})
	if not owned.has(place):
		return lines
	var last := int(d.get("last_day", s.day - 1))
	d["last_day"] = s.day
	for day in range(last + 1, s.day + 1):
		for m: String in members(s, data, own_id):
			if s.rng.randf() < float(cfg(data)["member_caught_chance"]):
				(d["members"] as Array).erase(m)
				lines.append("%s схвачен стражей на деле и уходит из братства «%s»" % [BondRules.npc_name(s, data, m), d["name"]])
				continue
			owned[place]["cash"] = int(owned[place].get("cash", 0)) + int(cfg(data)["member_income_cp"])
	return lines


# --- the master's `org` -------------------------------------------------------------------------------------------


## An organization around an NPC of the scene: {npc_id (head), name, org_kind (criminal | guild), cut_pct}.
static func make(s: GameSession, data: Dictionary, e: Dictionary) -> Dictionary:
	var head := str(e.get("npc_id", ""))
	if not BondRules.here(s, data, head):
		return {"reason": "%s не в сцене — главой делают NPC сцены" % head}
	if not of_head(s, data, head).is_empty():
		return {"reason": "%s уже глава %s" % [BondRules.npc_name(s, data, head), org_name(s, data, of_head(s, data, head)[0])]}
	var name := str(e.get("name", "")).strip_edges().left(40)
	if name.is_empty():
		return {"reason": "нужно name — как зовётся организация"}
	var k := str(e.get("org_kind", "criminal"))
	if not ["criminal", "guild"].has(k):
		return {"reason": "org_kind — criminal или guild"}
	var cut := int(e.get("cut_pct", 20)) if e.get("cut_pct") != null else 20
	var r: Array = cfg(data)["cut_pct"]
	if cut < int(r[0]) or cut > int(r[1]):
		return {"reason": "cut_pct — от %d до %d" % [int(r[0]), int(r[1])]}
	var site := WorldView.new(data["world"]).site_id(s.room_id)
	var id := "gen_o_" + ("%s|%s" % [head, name]).md5_text().left(8)
	return {"plan": {"id": id, "def": {"name": name, "kind": k, "head": head, "hideout": site if not WorldView.new(data["world"]).is_public(s.room_id) else "",
		"cut_pct": cut, "heists": [], "generated": true}}, "summary": "Организация: %s — глава %s" % [name, BondRules.npc_name(s, data, head)]}


static func apply_make(s: GameSession, data: Dictionary, plan: Dictionary) -> Array[String]:
	var gen := WorldGen.generated(s)
	var orgs: Dictionary = gen.get("orgs", {})
	orgs[str(plan["id"])] = (plan["def"] as Dictionary).duplicate(true)
	gen["orgs"] = orgs
	return ["%s — глава %s: «Братство» в его действиях" % [plan["def"]["name"], BondRules.npc_name(s, data, str(plan["def"]["head"]))]]


# --- for the master -----------------------------------------------------------------------------------------------


static func text(s: GameSession, data: Dictionary) -> String:
	var parts: Array[String] = []
	for id: String in mine(s, data):
		var st: Dictionary = view(s.character).get(id, {})
		if str(def(s, data, id).get("head", "")) == OwnerRules.HERO:
			parts.append("своё братство «%s»: %s" % [org_name(s, data, id), ", ".join(members(s, data, id).map(func(m: String) -> String: return BondRules.npc_name(s, data, m))) if not members(s, data, id).is_empty() else "без людей"])
		elif candidate(s.character, id):
			parts.append("«%s» — испытание у %s" % [org_name(s, data, id), head_name(s, data, id)])
		else:
			parts.append("«%s» — %s (%d очков)%s" % [org_name(s, data, id), rank_name(s, data, id), int(st.get("points", 0)),
				", должен долю %s" % Money.format(int(st["owed_cp"])) if int(st.get("owed_cp", 0)) > 0 else ""])
	for npc: String in SceneRules.npcs(s, data["world"], s.room_id):
		for id: String in of_head(s, data, npc):
			if not mine(s, data).has(id):
				parts.append("%s — глава братства «%s» (вступить — кнопка «Братство»)" % [BondRules.npc_name(s, data, npc), org_name(s, data, id)])
	if parts.is_empty():
		return ""
	return "Братства (стража о них не знает; окно «Братство» — кнопки): " + "; ".join(parts)
