class_name BondRules
extends RefCounted
## Bonds with NPCs (roadmap v0.7.31, the author: friendship, romance, rivalry, a mentor — as in BG3 and Stardew).
## c.bonds {npc_id: {kind, points, gift_day, scene_day, confess_day, hide_day, known}} — points in rules.bonds.range.
## The kind names the steps: friend by default, romance after a confession the NPC accepts (only an NPC whose
## `romance` is open towards the hero's gender — the pack's or the master's), mentor after a course with its teacher.
## Points below zero make a rival and an enemy whatever the kind. Points come from gifts by the NPC's `likes` /
## `dislikes` (one a day), the master's scenes (`bond`, once a day) and deeds of the engine (a quest done, a theft
## caught, an assault). Perks go by points: a discount, cheaper services, a bed, a hiding place from the patrol,
## a word to the guard from an NPC of the law, a lower course fee from a mentor; a rival asks more, an enemy refuses.


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"]["bonds"]


## Read-only: never writes into the character (a read must not change the save).
static func view(c: Dictionary) -> Dictionary:
	return c.get("bonds", {})


static func entry(c: Dictionary, npc_id: String) -> Dictionary:
	return view(c).get(npc_id, {})


static func _rw(c: Dictionary, npc_id: String) -> Dictionary:
	if not c.has("bonds"):
		c["bonds"] = {}
	var all: Dictionary = c["bonds"]
	if not all.has(npc_id):
		all[npc_id] = {"kind": "friend", "points": 0}
	return all[npc_id]


static func points(c: Dictionary, npc_id: String) -> int:
	return int(entry(c, npc_id).get("points", 0))


static func kind(c: Dictionary, npc_id: String) -> String:
	return str(entry(c, npc_id).get("kind", "friend"))


static func npc_def(s: GameSession, data: Dictionary, npc_id: String) -> Dictionary:
	var n := WorldView.new(data["world"]).npc(npc_id)
	return n if not n.is_empty() else WorldGen.generated(s).get("npcs", {}).get(npc_id, {})


static func npc_name(s: GameSession, data: Dictionary, npc_id: String) -> String:
	return JobRules.npc_name(s, data, npc_id)


static func here(s: GameSession, data: Dictionary, npc_id: String) -> bool:
	return s.npcs_here(data["world"], s.room_id).has(npc_id)


# --- steps --------------------------------------------------------------------------------------------------------


## The step of the bond: {name, at, hostile} or {} under the first step.
static func step(c: Dictionary, data: Dictionary, npc_id: String) -> Dictionary:
	var p := points(c, npc_id)
	var out := {}
	if p < 0:
		for h: Dictionary in cfg(data)["hostile"]:
			if p <= int(h["at"]):
				out = {"name": str(h["name"]), "at": int(h["at"]), "hostile": true}
		return out
	for st: Dictionary in cfg(data)["kinds"][kind(c, npc_id)]["steps"]:
		if p >= int(st["at"]):
			out = {"name": str(st["name"]), "at": int(st["at"]), "hostile": false}
	return out


static func word(c: Dictionary, data: Dictionary, npc_id: String) -> String:
	return str(step(c, data, npc_id).get("name", ""))


## The points of the next step up, -1 at the top.
static func next_at(c: Dictionary, data: Dictionary, npc_id: String) -> int:
	var p := points(c, npc_id)
	if p < 0:
		return 0
	for st: Dictionary in cfg(data)["kinds"][kind(c, npc_id)]["steps"]:
		if int(st["at"]) > p:
			return int(st["at"])
	return -1


static func enemy(c: Dictionary, data: Dictionary, npc_id: String) -> bool:
	if entry(c, npc_id).is_empty():
		return false
	var h: Array = cfg(data)["hostile"]
	return points(c, npc_id) <= int(h[h.size() - 1]["at"])


static func rival(c: Dictionary, data: Dictionary, npc_id: String) -> bool:
	return not entry(c, npc_id).is_empty() and points(c, npc_id) <= int(cfg(data)["hostile"][0]["at"])


## Moves the bond by `delta` within the range. Lines: the change and a new step.
static func add(s: GameSession, data: Dictionary, npc_id: String, delta: int, why: String) -> Array[String]:
	if delta == 0 or npc_id.is_empty() or s.dead_npcs.has(npc_id):
		return []
	var c := s.character
	var before := word(c, data, npc_id)
	var e := _rw(c, npc_id)
	var r: Array = cfg(data)["range"]
	e["points"] = clampi(int(e["points"]) + delta, int(r[0]), int(r[1]))
	var who := npc_name(s, data, npc_id)
	var lines: Array[String] = ["%s: близость %s%d%s" % [who, "+" if delta > 0 else "−", absi(delta), (" (%s)" % why) if not why.is_empty() else ""]]
	if str(e["kind"]) == "romance" and int(e["points"]) < 0:
		e["kind"] = "friend"
		lines.append("%s: роман окончен" % who)
	var after := word(c, data, npc_id)
	if after != before and not after.is_empty():
		lines.append("%s: связь — %s" % [who, after])
	return lines


## A deed of the engine (rules.bonds.deeds): a quest done, a theft caught, an assault. Lines.
static func on_deed(s: GameSession, data: Dictionary, npc_id: String, deed: String, why: String) -> Array[String]:
	if not data["rules"].has("bonds"):
		return []
	return add(s, data, npc_id, int(cfg(data)["deeds"].get(deed, 0)), why)


## The hero finished a course of this teacher: a mentor, unless a romance already. Lines.
static func mentor(s: GameSession, data: Dictionary, npc_id: String) -> Array[String]:
	if npc_id.is_empty() or s.dead_npcs.has(npc_id):
		return []
	var e := _rw(s.character, npc_id)
	if str(e["kind"]) == "friend":
		e["kind"] = "mentor"
	return on_deed(s, data, npc_id, "graduate", "выпуск")


# --- tastes and gifts ---------------------------------------------------------------------------------------------


static func _matches(s: GameSession, data: Dictionary, taste: String, item_id: String) -> bool:
	if taste == item_id:
		return true
	var g: Dictionary = cfg(data)["tastes"].get(taste, {})
	if g.is_empty():
		return false
	var d := ItemRules.def_of(data["items"], s.items, item_id)
	if (g.get("ids", []) as Array).has(item_id) or (g.get("types", []) as Array).has(str(d.get("item_type", ""))):
		return true
	if g.has("has") and d.has(str(g["has"])):
		return true
	return bool(g.get("food", false)) and data["rules"]["hero_effects"]["camp"]["food"].has(item_id)


## "liked", "disliked" or "" and the taste that decided it.
static func taste_of(s: GameSession, data: Dictionary, npc_id: String, item_id: String) -> Dictionary:
	var n := npc_def(s, data, npc_id)
	for key: String in ["dislikes", "likes"]:
		for t: Variant in n.get(key, []):
			if _matches(s, data, str(t), item_id):
				return {"taste": "liked" if key == "likes" else "disliked", "by": str(t)}
	return {"taste": "", "by": ""}


static func taste_name(s: GameSession, data: Dictionary, taste: String) -> String:
	var g: Dictionary = cfg(data)["tastes"].get(taste, {})
	return str(g["name"]) if not g.is_empty() else ItemRules.display_name(data["items"], s.items, taste)


## The tastes the hero has learned from gifts: {likes: [..], dislikes: [..]}.
static func known(c: Dictionary, npc_id: String) -> Dictionary:
	var k: Dictionary = entry(c, npc_id).get("known", {})
	return {"likes": k.get("likes", []), "dislikes": k.get("dislikes", [])}


## The things the hero may give: owned, not worn, not held by a curse.
static func gifts(s: GameSession, data: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for id: String in s.character.get("inventory", {}):
		if TradeRules.sellable(s, id, data) > 0 and not ItemRules.held_by_curse(s.character, data, s.items, id):
			out.append(id)
	return out


static func gift_points(s: GameSession, data: Dictionary, npc_id: String, item_id: String) -> int:
	var g: Dictionary = cfg(data)["gift"]
	match str(taste_of(s, data, npc_id, item_id)["taste"]):
		"liked":
			return int(g["liked"])
		"disliked":
			return int(g["disliked"])
	var value := int(ItemRules.def_of(data["items"], s.items, item_id).get("value_cp", 0))
	var pts := 0
	for row: Dictionary in g["neutral"]:
		if value >= int(row["value_cp"]):
			pts = int(row["points"])
	return pts


## "" when the NPC takes a gift now (`item_id` "" — any), else a localization key.
static func gift_why(s: GameSession, data: Dictionary, npc_id: String, item_id: String = "") -> String:
	if not here(s, data, npc_id):
		return "BOND_NOT_HERE"
	if CombatRules.active(s):
		return "BOND_IN_COMBAT"
	if SocialRules.refuses(s, data, npc_id):
		return "BOND_REFUSES"
	if int(entry(s.character, npc_id).get("gift_day", -1)) == s.day:
		return "BOND_GIFT_TODAY"
	var all := gifts(s, data)
	if all.is_empty() or (not item_id.is_empty() and not all.has(item_id)):
		return "BOND_GIFT_NONE"
	return ""


## The gift goes into the NPC's pockets. Lines.
static func gift(s: GameSession, data: Dictionary, npc_id: String, item_id: String) -> Array[String]:
	var c := s.character
	var who := npc_name(s, data, npc_id)
	var name := ItemRules.display_name(data["items"], s.items, item_id)
	var pts := gift_points(s, data, npc_id, item_id)
	var t := taste_of(s, data, npc_id, item_id)
	ItemRules._remove_one(c, item_id)
	var pockets := TheftRules.pockets(s, data, npc_id)
	var e := {"id": "g%d" % (pockets.size() + 1), "name": name, "item_id": item_id, "cp": 0, "qty": 1, "worn": false}
	e["dc"] = TheftRules.dc(s, data, npc_id, e)
	pockets.append(e)
	var b := _rw(c, npc_id)
	b["gift_day"] = s.day
	var lines: Array[String] = ["Подарок — %s: «%s»" % [who, name]]
	if not str(t["taste"]).is_empty():
		var key := "likes" if t["taste"] == "liked" else "dislikes"
		var k: Dictionary = b.get("known", {})
		var list: Array = k.get(key, [])
		if not list.has(t["by"]):
			list.append(t["by"])
		k[key] = list
		b["known"] = k
		lines.append("%s: %s — %s" % [who, taste_name(s, data, str(t["by"])), "по душе" if key == "likes" else "не по душе"])
	if t["taste"] == "liked":
		s.shift_attitude(npc_id, int(cfg(data)["gift"]["attitude_liked"]), data)
	s.remember(npc_id, "герой подарил «%s»%s" % [name, " — по душе" if t["taste"] == "liked" else " — не по душе" if t["taste"] == "disliked" else ""])
	lines.append_array(add(s, data, npc_id, pts, "подарок"))
	return lines


# --- romance ------------------------------------------------------------------------------------------------------


## "" when the NPC is open to a romance with this hero, otherwise why not (for the hero and the master).
static func romance_closed(s: GameSession, data: Dictionary, npc_id: String) -> String:
	var n := npc_def(s, data, npc_id)
	var tags: Array = n.get("tags", [])
	if tags.any(func(t: Variant) -> bool: return (cfg(data)["romance"]["closed_tags"] as Array).has(t)):
		return str(n.get("romance", {}).get("why", "служитель храма"))
	var rom: Dictionary = n.get("romance", {})
	if not bool(rom.get("open", false)):
		return str(rom.get("why", "не ищет романа"))
	var g: Array = rom.get("genders", ["any"])
	if not (g.has("any") or g.has(str(s.character.get("gender", "other")))):
		return "не смотрит так на героя"
	return ""


## The NPC in a romance with the hero, "" — none.
static func partner(s: GameSession) -> String:
	var all := view(s.character)
	for id: String in all:
		if str(all[id].get("kind", "")) == "romance" and not s.dead_npcs.has(id):
			return id
	return ""


static func confess_why(s: GameSession, data: Dictionary, npc_id: String) -> String:
	var c := s.character
	if not here(s, data, npc_id):
		return "BOND_NOT_HERE"
	if CombatRules.active(s):
		return "BOND_IN_COMBAT"
	if kind(c, npc_id) == "romance":
		return "BOND_ROMANCE_ALREADY"
	if not romance_closed(s, data, npc_id).is_empty():
		return "BOND_ROMANCE_CLOSED"
	if not partner(s).is_empty():
		return "BOND_HAS_PARTNER"
	var k: Dictionary = cfg(data)["confess"]
	if points(c, npc_id) < int(k["at"]):
		return "BOND_TOO_EARLY"
	var last := int(entry(c, npc_id).get("confess_day", -999))
	if s.day - last < int(k["cooldown_days"]):
		return "BOND_CONFESS_COOLDOWN"
	return ""


static func confess_dc(s: GameSession, data: Dictionary, npc_id: String) -> int:
	var k: Dictionary = cfg(data)["confess"]
	var d := SocialRules.dc(s, data, npc_id, str(k["skill"]), str(k["tier"]))
	return int(d["dc"]) if not d.is_empty() else int(data["rules"]["dc_tiers"][str(k["tier"])])


static func _bonus(s: GameSession, data: Dictionary) -> int:
	return CheckEngine.bonus_for(s.character, {"skill": str(cfg(data)["confess"]["skill"])}) + DifficultyRules.bonus(s, data)


static func confess_chance(s: GameSession, data: Dictionary, npc_id: String) -> int:
	return JobRules._chance(_bonus(s, data), confess_dc(s, data, npc_id), false)


## A confession: a Persuasion check against the NPC; yes — a romance, no — a step back and a wait. Lines.
static func confess(s: GameSession, data: Dictionary, npc_id: String) -> Array[String]:
	var c := s.character
	var k: Dictionary = cfg(data)["confess"]
	var who := npc_name(s, data, npc_id)
	var mods := ConditionRules.check_mods(c, data, {"skill": str(k["skill"])})
	var dis := not (mods["disadvantage"] as Array).is_empty()
	var rolls := FeatureRules.hero_d20(s, false, dis)
	var nat: int = rolls.min() if dis else rolls[0]
	var b := _bonus(s, data)
	var dc := confess_dc(s, data, npc_id)
	var ok := nat == 20 or (nat != 1 and nat + b >= dc)
	var e := _rw(c, npc_id)
	e["confess_day"] = s.day
	var lines: Array[String] = ["Признание — %s: Убеждение %d %s %d = %d против Сл %d — %s" % [who, nat, "−" if b < 0 else "+", absi(b), nat + b, dc,
		"взаимно" if ok else "отказ"]]
	if ok:
		e["kind"] = "romance"
		s.remember(npc_id, "герой признался в чувствах — и это взаимно")
		lines.append_array(add(s, data, npc_id, int(k["success"]), "признание"))
		if not lines.any(func(l: String) -> bool: return l.contains("связь —")):
			lines.append("%s: связь — %s" % [who, word(c, data, npc_id)])
	else:
		s.remember(npc_id, "герой признался в чувствах — получил отказ")
		lines.append_array(add(s, data, npc_id, int(k["fail"]), "отказ"))
	return lines


static func break_why(s: GameSession, data: Dictionary, npc_id: String) -> String:
	if kind(s.character, npc_id) != "romance":
		return "BOND_NO_ROMANCE"
	return ""


## The hero ends the romance: a friend again, with a wound. Lines.
static func break_off(s: GameSession, data: Dictionary, npc_id: String) -> Array[String]:
	var e := _rw(s.character, npc_id)
	e["kind"] = "friend"
	s.remember(npc_id, "герой расстался с ним" if str(npc_def(s, data, npc_id).get("gender", "")) == "male" else "герой расстался с ней")
	var lines: Array[String] = ["%s: роман окончен" % npc_name(s, data, npc_id)]
	lines.append_array(add(s, data, npc_id, int(cfg(data)["break"]["points"]), "расставание"))
	return lines


# --- perks --------------------------------------------------------------------------------------------------------


static func _tier(table: Array, p: int, key: String, none: int) -> int:
	var out := none
	for row: Dictionary in table:
		if p >= int(row["at"]):
			out = int(row[key])
	return out


static func _alive(s: GameSession, npc_id: String) -> bool:
	return not s.dead_npcs.has(npc_id)


## The trader's discount for a friend, percent.
static func discount(s: GameSession, data: Dictionary, npc_id: String) -> int:
	return _tier(cfg(data)["perks"]["discount"], points(s.character, npc_id), "pct", 0)


## The buy price of this trader for the hero, percent: lower for a friend, higher for a rival.
static func buy_pct(s: GameSession, data: Dictionary, npc_id: String) -> int:
	if entry(s.character, npc_id).is_empty():
		return 100
	if rival(s.character, data, npc_id):
		return int(cfg(data)["perks"]["rival_buy_pct"])
	return 100 - discount(s, data, npc_id)


## What a service of this NPC costs a friend.
static func service_cost(s: GameSession, data: Dictionary, npc_id: String, cost: int) -> int:
	if entry(s.character, npc_id).is_empty():
		return cost
	var pct := _tier(cfg(data)["perks"]["service_pct"], points(s.character, npc_id), "pct", 100)
	return ceili(cost * pct / 100.0)


## Close enough to give a bed, to hide, to serve the wanted hero.
static func close(s: GameSession, data: Dictionary, npc_id: String) -> bool:
	return not entry(s.character, npc_id).is_empty() and _alive(s, npc_id) and points(s.character, npc_id) >= int(cfg(data)["perks"]["lodge_at"])


## The friend here who gives the hero a bed for the night; "" — none.
static func host(s: GameSession, data: Dictionary, room_id: String) -> String:
	if view(s.character).is_empty():
		return ""
	for id: String in s.npcs_here(data["world"], room_id):
		if close(s, data, id):
			return id
	return ""


static func hide_why(s: GameSession, data: Dictionary, npc_id: String) -> String:
	var h: Dictionary = cfg(data)["perks"]["hide"]
	if not here(s, data, npc_id):
		return "BOND_NOT_HERE"
	if points(s.character, npc_id) < int(h["at"]):
		return "BOND_NOT_CLOSE"
	if not CrimeRules.wanted_at(s, data, s.room_id):
		return "BOND_NOT_WANTED"
	if CrimeRules.held(s) or CombatRules.active(s):
		return "BOND_HELD"
	if s.day - int(entry(s.character, npc_id).get("hide_day", -999)) < int(h["cooldown_days"]):
		return "BOND_HIDE_COOLDOWN"
	return ""


## The friend hides the hero: no guard holds the hero in this location for a while. Lines.
static func hide(s: GameSession, data: Dictionary, npc_id: String) -> Array[String]:
	var h: Dictionary = cfg(data)["perks"]["hide"]
	var loc := WorldView.new(data["world"]).location_id(s.room_id)
	s.let_go[loc] = TimeRules.abs_minute(s) + int(h["minutes"])
	_rw(s.character, npc_id)["hide_day"] = s.day
	return ["%s прячет героя: стража не найдёт его здесь %d ч" % [npc_name(s, data, npc_id), int(h["minutes"]) / 60]]


## The NPC of the law of the location who speaks for the hero to the guard; "" — none.
static func intercessor(s: GameSession, data: Dictionary, loc: String) -> String:
	if view(s.character).is_empty():
		return ""
	var ic: Dictionary = cfg(data)["perks"]["intercede"]
	var victims := s.crimes.filter(func(cr: Dictionary) -> bool: return not bool(cr["settled"])).map(func(cr: Dictionary) -> String: return str(cr["victim"]))
	for id: String in CrimeRules.people_of(data, loc):
		if not _alive(s, id) or victims.has(id) or points(s.character, id) < int(ic["at"]):
			continue
		var tags: Array = WorldView.new(data["world"]).npc(id).get("tags", [])
		if tags.any(func(t: Variant) -> bool: return (ic["tags"] as Array).has(t)):
			return id
	return ""


## The course fee of a mentor, percent.
static func mentor_fee_pct(s: GameSession, data: Dictionary, npc_id: String) -> int:
	if kind(s.character, npc_id) != "mentor":
		return 100
	return _tier(cfg(data)["perks"]["mentor_fee"], points(s.character, npc_id), "pct", 100)


## What the bond gives now, in words.
static func perks_text(s: GameSession, data: Dictionary, npc_id: String) -> Array[String]:
	var c := s.character
	var out: Array[String] = []
	if enemy(c, data, npc_id):
		return ["не говорит и не торгует с героем"]
	if rival(c, data, npc_id):
		return ["цены на %d%% выше" % (int(cfg(data)["perks"]["rival_buy_pct"]) - 100)]
	var n := npc_def(s, data, npc_id)
	if discount(s, data, npc_id) > 0 and bool(n.get("trader", false)):
		out.append("скидка %d%%" % discount(s, data, npc_id))
	var sv := service_cost(s, data, npc_id, 100)
	if sv < 100 and not (n.get("services", []) as Array).is_empty():
		out.append("услуги даром" if sv == 0 else "услуги за %d%%" % sv)
	if close(s, data, npc_id):
		out.append("ночлег рядом")
		out.append("укроет от стражи")
		var tags: Array = npc_def(s, data, npc_id).get("tags", [])
		if tags.any(func(t: Variant) -> bool: return (cfg(data)["perks"]["intercede"]["tags"] as Array).has(t)):
			out.append("заступится перед стражей")
	if mentor_fee_pct(s, data, npc_id) < 100:
		out.append("плата за курс %d%%" % mentor_fee_pct(s, data, npc_id))
	return out


# --- the master's scenes ------------------------------------------------------------------------------------------


## The `bond` effect: a scene moved the bond with an NPC of the scene; for a made NPC also its romance and tastes.
## {plan, summary} or {reason}.
static func make(s: GameSession, data: Dictionary, spec: Dictionary) -> Dictionary:
	var m: Dictionary = cfg(data)["make"]
	var who := str(spec.get("npc_id", ""))
	if not here(s, data, who):
		return {"reason": "%s не в сцене — близость меняет только сцена с тем, кто здесь" % who}
	var delta := int(spec.get("delta", 0)) if spec.get("delta") != null else 0
	var mx := int(cfg(data)["scene"]["max_delta"])
	if absi(delta) > mx:
		return {"reason": "delta — от −%d до +%d за сцену" % [mx, mx]}
	if delta != 0 and int(entry(s.character, who).get("scene_day", -1)) == s.day:
		return {"reason": "сцена с %s сегодня уже сдвинула близость — завтра или подарок, дело" % npc_name(s, data, who)}
	var why := str(spec.get("reason", "")).strip_edges().left(80) if spec.get("reason") != null else ""
	if delta != 0 and why.is_empty():
		return {"reason": "нужно reason — чем сцена сблизила или оттолкнула"}
	var k := str(spec.get("bond_kind", "")) if spec.get("bond_kind") != null else ""
	if not k.is_empty() and not (m["kinds"] as Array).has(k):
		return {"reason": "bond_kind — из %s (романтика — только признанием игрока, кнопкой)" % ", ".join(m["kinds"])}
	if k == "friend" and kind(s.character, who) == "romance":
		return {"reason": "роман с %s кончает только игрок (кнопка «Расстаться»)" % npc_name(s, data, who)}
	var made := not WorldView.new(data["world"]).npc(who).has("name")
	var npc_patch := {}
	if spec.get("romance") is Dictionary:
		if not made:
			return {"reason": "romance пакетного NPC задаёт автор пакета, не мастер"}
		var rom: Dictionary = spec["romance"]
		var g: Array = rom.get("genders", ["any"]) if rom.get("genders") is Array else ["any"]
		if not g.all(func(x: Variant) -> bool: return (m["genders"] as Array).has(str(x))):
			return {"reason": "romance.genders — из %s" % ", ".join(m["genders"])}
		npc_patch["romance"] = {"open": bool(rom.get("open", false)), "genders": g, "why": str(rom.get("why", "")).left(60)}
	for key: String in ["likes", "dislikes"]:
		if spec.get(key) is Array and not (spec[key] as Array).is_empty():
			if not made:
				return {"reason": "%s пакетного NPC задаёт автор пакета" % key}
			for t: Variant in spec[key]:
				if not cfg(data)["tastes"].has(str(t)) and not data["items"]["catalog"].has(str(t)):
					return {"reason": "%s — группы %s или предметы каталога" % [key, ", ".join(cfg(data)["tastes"].keys())]}
			npc_patch[key] = (spec[key] as Array).map(func(x: Variant) -> String: return str(x))
	if delta == 0 and k.is_empty() and npc_patch.is_empty():
		return {"reason": "нечего менять: delta, bond_kind, romance или likes / dislikes"}
	var parts: Array[String] = []
	if delta != 0:
		parts.append("близость %+d (%s)" % [delta, why])
	if not k.is_empty():
		parts.append(str(cfg(data)["kinds"][k]["name"]))
	if npc_patch.has("romance"):
		parts.append("роман %s" % ("возможен" if npc_patch["romance"]["open"] else "невозможен"))
	return {"plan": {"npc_id": who, "delta": delta, "why": why, "kind": k, "npc": npc_patch},
		"summary": "Связь — %s: %s" % [npc_name(s, data, who), ", ".join(parts)]}


static func apply_make(s: GameSession, data: Dictionary, plan: Dictionary) -> Array[String]:
	var who := str(plan["npc_id"])
	var patch: Dictionary = plan.get("npc", {})
	if not patch.is_empty():
		var n: Dictionary = WorldGen.generated(s).get("npcs", {}).get(who, {})
		for key: String in patch:
			n[key] = patch[key]
	var e := _rw(s.character, who)
	var lines: Array[String] = []
	if not str(plan.get("kind", "")).is_empty() and str(plan["kind"]) != str(e["kind"]):
		e["kind"] = str(plan["kind"])
		lines.append("%s: %s" % [npc_name(s, data, who), cfg(data)["kinds"][e["kind"]]["name"]])
	if int(plan["delta"]) != 0:
		e["scene_day"] = s.day
		lines.append_array(add(s, data, who, int(plan["delta"]), str(plan["why"])))
	return lines


# --- for the master -----------------------------------------------------------------------------------------------


## The bonds of the hero and the romance of the scene's people, for the snapshot.
static func text(s: GameSession, data: Dictionary) -> String:
	var c := s.character
	var parts: Array[String] = []
	var all := view(c)
	for id: String in all:
		if s.dead_npcs.has(id) or (points(c, id) == 0 and kind(c, id) == "friend"):
			continue
		var w := word(c, data, id)
		var line := "%s — %s, %s %d" % [npc_name(s, data, id), cfg(data)["kinds"][kind(c, id)]["name"], w if not w.is_empty() else "без ступени", points(c, id)]
		var perks := perks_text(s, data, id)
		if not perks.is_empty():
			line += " (%s)" % ", ".join(perks)
		parts.append(line)
	var scene: Array[String] = []
	for id: String in s.npcs_here(data["world"], s.room_id):
		var why := romance_closed(s, data, id)
		scene.append("%s: роман %s; сегодня %s" % [npc_name(s, data, id), "возможен" if why.is_empty() else "невозможен — " + why,
			"сцена уже была" if int(entry(c, id).get("scene_day", -1)) == s.day else "сцена свободна"])
	var out := "; ".join(parts) if not parts.is_empty() else "связей нет"
	if not scene.is_empty():
		out += ". В сцене — " + "; ".join(scene)
	return out
