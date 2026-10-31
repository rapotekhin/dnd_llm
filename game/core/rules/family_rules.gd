class_name FamilyRules
extends RefCounted
## Family (roadmap v0.7.32, the author: marriage and children, upkeep, the family's help, an heir).
## c.family {engaged, spouse, married_day, home, home_room, hours, children: [npc_id], pregnant {bearer, due},
## tried_day, hungry, kin: [{npc, rel}]}. A proposal to the partner of a romance (BondRules) at rules.family.propose_at
## with a home of the hero (an owned place whose upgrades give `rest`); the wedding at an officiant — an NPC with a tag
## of `officiants` — for its fee. The spouse stays a person of the pack: at work by day, at home in `hours`. Children
## are NPCs the engine makes in the home's room; a year of theirs is `days_per_year` days. The adult child is the heir.


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"]["family"]


## Read-only: never writes into the character.
static func view(c: Dictionary) -> Dictionary:
	return c.get("family", {})


static func _rw(c: Dictionary) -> Dictionary:
	if not (c.get("family") is Dictionary):
		c["family"] = {}
	var f: Dictionary = c["family"]
	if not f.has("children"):
		f["children"] = []
	return f


static func _name(s: GameSession, data: Dictionary, npc_id: String) -> String:
	return JobRules.npc_name(s, data, npc_id)


## The living spouse, "" — none.
static func spouse(s: GameSession) -> String:
	var id := str(view(s.character).get("spouse", ""))
	return id if not id.is_empty() and not s.dead_npcs.has(id) else ""


static func engaged(s: GameSession) -> String:
	var id := str(view(s.character).get("engaged", ""))
	return id if not id.is_empty() and not s.dead_npcs.has(id) else ""


static func children(s: GameSession) -> Array[String]:
	var out: Array[String] = []
	for id: Variant in view(s.character).get("children", []):
		if not s.dead_npcs.has(str(id)):
			out.append(str(id))
	return out


## The hero's home: an owned place whose upgrades give a bed; "" — none.
static func home(s: GameSession, data: Dictionary) -> String:
	var owned: Dictionary = s.character.get("property", {}) if s.character.get("property") is Dictionary else {}
	for id: String in owned:
		if PropertyRules._gives(s, data, id, "rest", 0.0) > 0.0:
			return id
	return ""


## Where the spouse or a kin of the heir is at this hour: the home's room in `hours`, else null (the pack decides).
static func home_at(s: GameSession, npc_id: String) -> Variant:
	var f := view(s.character)
	if f.is_empty() or str(f.get("home_room", "")).is_empty():
		return null
	if str(f.get("spouse", "")) != npc_id and not (f.get("kin", []) as Array).any(func(k: Variant) -> bool: return str(k["npc"]) == npc_id):
		return null
	var h: Array = f.get("hours", [20, 7])
	var hour := s.minute / 60
	var a := int(h[0])
	var b := int(h[1])
	if (a <= b and hour >= a and hour < b) or (a > b and (hour >= a or hour < b)):
		return str(f["home_room"])
	return null


# --- the wedding --------------------------------------------------------------------------------------------------


static func propose_why(s: GameSession, data: Dictionary, npc_id: String) -> String:
	if not BondRules.here(s, data, npc_id):
		return "BOND_NOT_HERE"
	if not spouse(s).is_empty():
		return "FAMILY_MARRIED"
	if engaged(s) == npc_id:
		return "FAMILY_ENGAGED"
	if BondRules.kind(s.character, npc_id) != "romance" or BondRules.points(s.character, npc_id) < int(cfg(data)["propose_at"]):
		return "FAMILY_NOT_YET"
	if home(s, data).is_empty():
		return "FAMILY_NO_HOME"
	return ""


static func propose(s: GameSession, data: Dictionary, npc_id: String) -> Array[String]:
	_rw(s.character)["engaged"] = npc_id
	s.remember(npc_id, "герой сделал предложение — и получил согласие")
	return ["%s: «Да!» — помолвка. Свадьба — у жреца или писаря" % _name(s, data, npc_id)]


## The officiant's kind of this NPC (a key of `officiants`), "" — not one.
static func officiant(s: GameSession, data: Dictionary, npc_id: String) -> String:
	var tags: Array = BondRules.npc_def(s, data, npc_id).get("tags", [])
	for k: String in cfg(data)["officiants"]:
		if tags.has(k):
			return k
	return ""


static func fee(data: Dictionary, kind: String) -> int:
	return int(cfg(data)["officiants"][kind]["fee_cp"])


static func wedding_why(s: GameSession, data: Dictionary, npc_id: String) -> String:
	var k := officiant(s, data, npc_id)
	if k.is_empty() or not BondRules.here(s, data, npc_id):
		return "FAMILY_NO_OFFICIANT"
	if not spouse(s).is_empty():
		return "FAMILY_MARRIED"
	if engaged(s).is_empty():
		return "FAMILY_NOT_ENGAGED"
	if home(s, data).is_empty():
		return "FAMILY_NO_HOME"
	if int(s.character.get("gold_cp", 0)) < fee(data, k):
		return "TRADE_ERR_NO_COINS"
	return ""


static func wedding(s: GameSession, data: Dictionary, npc_id: String) -> Array[String]:
	var c := s.character
	var f := _rw(c)
	var k := officiant(s, data, npc_id)
	var who := str(f["engaged"])
	c["gold_cp"] = int(c["gold_cp"]) - fee(data, k)
	var h := home(s, data)
	f["spouse"] = who
	f["married_day"] = s.day
	f["last_day"] = s.day
	f["home"] = h
	f["home_room"] = PropertyRules.main_room(s, data, h)
	f["hours"] = (cfg(data)["home_hours"] as Array).duplicate()
	f.erase("engaged")
	s.remember(who, "стал(а) супругом героя")
	s.remember(npc_id, "провёл свадьбу героя и %s" % _name(s, data, who))
	var lines: Array[String] = ["Свадьба: %s — %s, %s" % [_name(s, data, who), str(cfg(data)["officiants"][k]["name"]), Money.format(fee(data, k))],
		"%s живёт в вашем доме: %s" % [_name(s, data, who), PropertyRules.name_of(s, data, h)]]
	lines.append_array(BondRules.add(s, data, who, 10, "свадьба"))
	return lines


# --- children -----------------------------------------------------------------------------------------------------


static func _bears(data: Dictionary, gender: String) -> bool:
	return (cfg(data)["conceive"]["bears"] as Array).has(gender)


## Who of the two would bear: "hero", the spouse's id, or "" — neither can.
static func bearer(s: GameSession, data: Dictionary) -> String:
	var sp := spouse(s)
	var hg := str(s.character.get("gender", "other"))
	var sg := str(BondRules.npc_def(s, data, sp).get("gender", "other"))
	if _bears(data, hg) == _bears(data, sg):
		return ""
	return "hero" if _bears(data, hg) else sp


static func at_home(s: GameSession, data: Dictionary) -> bool:
	var h := str(view(s.character).get("home", ""))
	return not h.is_empty() and PropertyRules.at(s, data, s.room_id) == h


static func child_why(s: GameSession, data: Dictionary) -> String:
	var f := view(s.character)
	if spouse(s).is_empty():
		return "FAMILY_NOT_MARRIED"
	if not at_home(s, data) or not BondRules.here(s, data, spouse(s)):
		return "FAMILY_NOT_TOGETHER"
	if bearer(s, data).is_empty():
		return "FAMILY_NO_BEARER"
	if f.has("pregnant"):
		return "FAMILY_EXPECTING"
	if int(f.get("tried_day", -1)) == s.day:
		return "FAMILY_TRIED_TODAY"
	return ""


static func try_child(s: GameSession, data: Dictionary) -> Array[String]:
	var f := _rw(s.character)
	var k: Dictionary = cfg(data)["conceive"]
	f["tried_day"] = s.day
	if s.rng.randf() >= float(k["chance"]):
		return ["Ночь вдвоём — ребёнка пока нет"]
	var b := bearer(s, data)
	f["pregnant"] = {"bearer": b, "due": s.day + int(k["days"])}
	return ["Вы ждёте ребёнка: %s, роды — через %d дней" % ["носит героиня" if b == "hero" else "носит " + _name(s, data, b), int(k["days"])]]


static func years(s: GameSession, data: Dictionary, npc_id: String) -> int:
	var born := int(BondRules.npc_def(s, data, npc_id).get("child", {}).get("born", s.day))
	return (s.day - born) / int(cfg(data)["days_per_year"])


static func stage(s: GameSession, data: Dictionary, npc_id: String) -> Dictionary:
	var y := years(s, data, npc_id)
	var out: Dictionary = cfg(data)["stages"][0]
	for st: Dictionary in cfg(data)["stages"]:
		if y >= int(st["years"]):
			out = st
	return out


static func _role(data: Dictionary, gender: String, st: Dictionary) -> String:
	return "%s героя, %s" % ["дочь" if gender == "female" else "сын", st["name"]]


## A child is born at home: an NPC of the engine. Lines.
static func _birth(s: GameSession, data: Dictionary, day: int) -> Array[String]:
	var c := s.character
	var f := _rw(c)
	f.erase("pregnant")
	var gender := "female" if s.rng.randf() < 0.5 else "male"
	var used := children(s).map(func(id: String) -> String: return BondRules.npc_def(s, data, id).get("name", ""))
	var pool: Array = (cfg(data)["names"][gender] as Array).filter(func(n: Variant) -> bool: return not used.has(n))
	if pool.is_empty():
		pool = cfg(data)["names"][gender]
	var name := str(pool[s.rng.randi_range(0, pool.size() - 1)])
	var st: Dictionary = cfg(data)["stages"][0]
	var def := {"name": name, "role": _role(data, gender, st), "gender": gender, "race": str(c.get("race_name", "")),
		"monster": "commoner", "tags": ["commoner"], "description": "Ребёнок героя и %s." % _name(s, data, spouse(s)),
		"child": {"born": day, "parents": ["hero", spouse(s)]}}
	var gen := WorldGen.generated(s)
	var n := 1
	while data["world"]["npcs"].has("kin_%d" % n):
		n += 1
	var id := "kin_%d" % n
	var room := str(f.get("home_room", s.room_id))
	gen["npcs"][id] = def.duplicate(true)
	gen["npc_rooms"][id] = room
	data["world"] = WorldGen.merged_into(data["world"], id, def, room)
	(f["children"] as Array).append(id)
	return ["Родил%s %s: %s" % ["ась дочь" if gender == "female" else "ся сын", "в доме", name]]


## The player names the child anew. Lines.
static func rename(s: GameSession, data: Dictionary, npc_id: String, name: String) -> Array[String]:
	var nm := name.strip_edges().left(30)
	if nm.is_empty() or not children(s).has(npc_id):
		return []
	WorldGen.generated(s)["npcs"][npc_id]["name"] = nm
	data["world"]["npcs"][npc_id]["name"] = nm
	return ["Имя ребёнка: %s" % nm]


static func _grow(s: GameSession, data: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	for id: String in children(s):
		var n: Dictionary = WorldGen.generated(s)["npcs"].get(id, {})
		var role := _role(data, str(n.get("gender", "male")), stage(s, data, id))
		if n.is_empty() or str(n.get("role", "")) == role:
			continue
		n["role"] = role
		data["world"]["npcs"][id]["role"] = role
		lines.append("%s подрос%s: %s" % [n["name"], "ла" if str(n.get("gender", "")) == "female" else "", stage(s, data, id)["name"]])
	return lines


# --- the household ------------------------------------------------------------------------------------------------


## Who eats and helps: [{npc, kind}] — kind spouse or a stage id.
static func household(s: GameSession, data: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not spouse(s).is_empty():
		out.append({"npc": spouse(s), "kind": "spouse"})
	for id: String in children(s):
		out.append({"npc": id, "kind": str(stage(s, data, id)["id"])})
	for k: Variant in view(s.character).get("kin", []):
		var id := str((k as Dictionary)["npc"])
		if not s.dead_npcs.has(id) and not out.any(func(e: Dictionary) -> bool: return e["npc"] == id):
			out.append({"npc": id, "kind": "spouse" if str(k.get("rel", "")) in ["мать", "отец"] else str(stage(s, data, id)["id"])})
	return out


static func upkeep(s: GameSession, data: Dictionary) -> int:
	var total := 0
	for e: Dictionary in household(s, data):
		total += int(cfg(data)["upkeep_cp"].get(e["kind"], 0))
	return total


static func help(s: GameSession, data: Dictionary) -> int:
	var total := 0
	for e: Dictionary in household(s, data):
		total += int(cfg(data)["help_cp"].get(e["kind"], 0))
	return total


## The days of the family since the last (from TimeRules, before the property's tax): births, growth, the help into
## the till, the upkeep from it or the purse, hunger and the spouse leaving. Lines.
static func tick(s: GameSession, data: Dictionary) -> Array[String]:
	var f := view(s.character)
	if f.is_empty() or not data["rules"].has("family"):
		return []
	var lines: Array[String] = []
	var last := int(f.get("last_day", s.day - 1))
	f["last_day"] = s.day
	for d in range(last + 1, s.day + 1):
		lines.append_array(_day(s, data, d))
	return lines


static func _day(s: GameSession, data: Dictionary, day: int) -> Array[String]:
	var f := view(s.character)
	var lines: Array[String] = []
	if f.has("pregnant") and int(f["pregnant"]["due"]) <= day:
		lines.append_array(_birth(s, data, day))
	lines.append_array(_grow(s, data))
	var h := str(f.get("home", ""))
	var owned: Dictionary = s.character.get("property", {}) if s.character.get("property") is Dictionary else {}
	if not h.is_empty() and not owned.has(h):  # the home was lost
		f["home"] = ""
		f["home_room"] = ""
		lines.append("Семье негде жить — дом потерян")
	var till: Dictionary = owned.get(str(f.get("home", "")), {})
	var c := s.character
	if till.is_empty():
		c["gold_cp"] = int(c["gold_cp"]) + help(s, data)
	else:
		till["cash"] = int(till.get("cash", 0)) + help(s, data)
	var need := upkeep(s, data)
	if need <= 0:
		return lines
	var from_till := mini(need, int(till.get("cash", 0))) if not till.is_empty() else 0
	if from_till > 0:
		till["cash"] = int(till["cash"]) - from_till
	var rest := need - from_till
	if rest <= int(c.get("gold_cp", 0)):
		c["gold_cp"] = int(c["gold_cp"]) - rest
		f["hungry"] = 0
		return lines
	f["hungry"] = int(f.get("hungry", 0)) + 1
	lines.append("Семье не хватает на еду (%s в день)" % Money.format(need))
	var sp := spouse(s)
	if sp.is_empty():
		return lines
	lines.append_array(BondRules.add(s, data, sp, int(cfg(data)["hunger"]["bond"]), "голод в доме"))
	if int(f["hungry"]) >= int(cfg(data)["hunger"]["leave_days"]):
		f["spouse"] = ""
		f["home_room"] = ""
		f["hungry"] = 0
		s.remember(sp, "ушёл(ушла) от героя: семья голодала")
		lines.append("%s уходит из дома: семья голодала" % _name(s, data, sp))
	return lines


# --- the heir -----------------------------------------------------------------------------------------------------


## The eldest adult child, "" — none.
static func heir(s: GameSession, data: Dictionary) -> String:
	for id: String in children(s):
		if str(stage(s, data, id)["id"]) == str(cfg(data)["stages"][-1]["id"]):
			return id
	return ""


## The choices the creation screen starts with for the heir: its name, gender and the parent's race.
static func heir_choices(s: GameSession, data: Dictionary) -> Dictionary:
	var h := heir(s, data)
	var n := BondRules.npc_def(s, data, h)
	var ch := CharacterBuilder.empty_choices()
	ch["name"] = str(n.get("name", ""))
	ch["gender"] = str(n.get("gender", "male"))
	ch["race"] = str(s.character.get("race", ""))
	ch["subrace"] = str(s.character.get("subrace", ""))
	return ch


## The heir takes the dead hero's place: coins, things, `heir.keep`, the family as kin; the heir leaves the world as
## an NPC and stands at home. Lines.
static func inherit(s: GameSession, data: Dictionary, heir_c: Dictionary) -> Array[String]:
	var old := s.character
	var h := heir(s, data)
	var f := view(old)
	heir_c["gold_cp"] = int(heir_c.get("gold_cp", 0)) + int(old.get("gold_cp", 0))
	var inv: Dictionary = heir_c["inventory"]
	for id: String in old.get("inventory", {}):
		inv[id] = int(inv.get(id, 0)) + int(old["inventory"][id])
	for k: Variant in cfg(data)["heir"]["keep"]:
		var v: Variant = old.get(str(k))
		if v is Dictionary:
			heir_c[str(k)] = (v as Dictionary).duplicate(true)
	var kin: Array = []
	if not spouse(s).is_empty():
		kin.append({"npc": spouse(s), "rel": "мать" if str(BondRules.npc_def(s, data, spouse(s)).get("gender", "")) == "female" else "отец"})
	for id: String in children(s):
		if id != h:
			kin.append({"npc": id, "rel": "сестра" if str(BondRules.npc_def(s, data, id).get("gender", "")) == "female" else "брат"})
	heir_c["family"] = {"children": [], "kin": kin, "home": str(f.get("home", "")), "home_room": str(f.get("home_room", "")),
		"parent": str(old.get("name", "")), "last_day": s.day}
	for id: String in OrgRules.of_head(s, data, h):  # the organization it led goes on with it as the hero
		var made: Dictionary = WorldGen.generated(s).get("orgs", {})
		if made.has(id):
			made[id]["head"] = OwnerRules.HERO
	var lines: Array[String] = ["%s, наследник рода %s, принимает дом и добро" % [heir_c["name"], old.get("name", "")]]
	_leave_world(s, data, h)  # the NPC is gone from the world: now the hero
	return lines


static func _leave_world(s: GameSession, data: Dictionary, npc_id: String) -> void:
	var gen := WorldGen.generated(s)
	var room := str(gen["npc_rooms"].get(npc_id, ""))
	gen["npcs"].erase(npc_id)
	gen["npc_rooms"].erase(npc_id)
	data["world"]["npcs"].erase(npc_id)
	if data["world"]["rooms"].has(room):
		(data["world"]["rooms"][room].get("npcs", []) as Array).erase(npc_id)


# --- for the master -----------------------------------------------------------------------------------------------


static func text(s: GameSession, data: Dictionary) -> String:
	var f := view(s.character)
	if f.is_empty() or not data["rules"].has("family"):
		return ""
	var parts: Array[String] = []
	if not engaged(s).is_empty():
		parts.append("помолвка с %s — свадьба кнопкой у жреца или писаря" % _name(s, data, engaged(s)))
	if not spouse(s).is_empty():
		parts.append("супруг(а) %s с дня %d, дом: %s; дома с %d:00 до %d:00" % [_name(s, data, spouse(s)), int(f.get("married_day", 0)),
			PropertyRules.name_of(s, data, str(f.get("home", ""))) if not str(f.get("home", "")).is_empty() else "нет",
			int(f.get("hours", [20, 7])[0]), int(f.get("hours", [20, 7])[1])])
	for id: String in children(s):
		parts.append("%s — %s, %d лет" % [_name(s, data, id), BondRules.npc_def(s, data, id).get("role", ""), years(s, data, id)])
	for k: Variant in f.get("kin", []):
		parts.append("%s — %s героя" % [_name(s, data, str(k["npc"])), k["rel"]])
	if f.has("pregnant"):
		parts.append("ждут ребёнка — роды через %d дн." % maxi(0, int(f["pregnant"]["due"]) - s.day))
	if not household(s, data).is_empty():
		parts.append("содержание %s в день, помощь семьи %s" % [Money.format(upkeep(s, data)), Money.format(help(s, data))])
	if int(f.get("hungry", 0)) > 0:
		parts.append("семья голодает %d дн." % int(f["hungry"]))
	if not heir(s, data).is_empty():
		parts.append("наследник: %s" % _name(s, data, heir(s, data)))
	if parts.is_empty():
		return ""
	return "Семья (окно «Семья», свадьба, дети и имена — кнопки): " + "; ".join(parts)
