class_name FaithRules
extends RefCounted
## Faith and the temple (roadmap v0.7.49): the gods are the pack's data (world.json `gods`, the master's in
## generated.faith.gods), a room's `shrine` {god, name} is where a faith is served (the master's in
## generated.faith.shrines), an NPC's `god` is whom it serves. The hero's faith is c.faith:
##   {god, favor {god: n}, vows [{id, since, broken}], lapsed (a day, -1 — none), served {god: day},
##    donated {god: [day, times]}, blessed {god: day}, converted (a day), last {deed, at}}.
## Everything breaks by facts of the engine (`deed`): a crime kind, a check of a skill (`check:<skill>`), a body
## searched (`rob_dead`), or a group of rules.faith.deeds. A vow broken loses its gift (RollParts.sheet reads
## `gift_parts`) until the atonement; the hero's god's commandment broken costs favor and the temple's blessing, and a
## cleric or a paladin lapses (spell DC and spell attack down, CharacterRules.refresh reads `lapse`). A deed of
## desecration in a shrine's room makes its god's favor the lowest: its priests refuse. Favor grows by a weekly
## service and donations; its steps give the blessing (Bless's die until the long rest), the priests' discount and
## a bed at the shrine.

const BLESS_ID := "temple_bless"


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"].get("faith", {})


static func on(data: Dictionary) -> bool:
	return data["rules"].has("faith") and (data["world"].get("gods", {}) as Dictionary).size() > 1


static func _gen(s: GameSession) -> Dictionary:
	var gen := WorldGen.generated(s)
	if not gen.has("faith"):
		gen["faith"] = {"gods": {}, "shrines": {}, "seq": 0}
	return gen["faith"]


## The gods of the pack and the master's: {id: def}.
static func gods(s: GameSession, data: Dictionary) -> Dictionary:
	var out := {}
	var pack: Dictionary = data["world"].get("gods", {})
	for id: String in pack:
		if not id.begins_with("_"):
			out[id] = pack[id]
	if s != null:
		out.merge(_gen(s)["gods"])
	return out


static func god(s: GameSession, data: Dictionary, id: String) -> Dictionary:
	return gods(s, data).get(id, {})


## «Чонтия» or «Чонтия (Светлая Мать)» with the title.
static func god_name(s: GameSession, data: Dictionary, id: String, title: bool = false) -> String:
	var g := god(s, data, id)
	if g.is_empty():
		return id
	return "%s (%s)" % [g["name"], g["title"]] if title and not str(g.get("title", "")).is_empty() else str(g["name"])


## The shrine of a room: {god, name} or {}.
static func shrine(s: GameSession, data: Dictionary, room_id: String) -> Dictionary:
	if s != null and (_gen(s)["shrines"] as Dictionary).has(room_id):
		return _gen(s)["shrines"][room_id]
	return data["world"].get("rooms", {}).get(room_id, {}).get("shrine", {})


## The gods' shrines the hero has seen: {god: [room ids]} (the faith window and the master).
static func shrines_known(s: GameSession, data: Dictionary) -> Dictionary:
	var out := {}
	var rooms: Array = data["world"].get("rooms", {}).keys() + (_gen(s)["shrines"] as Dictionary).keys()
	for r: Variant in rooms:
		var sh := shrine(s, data, str(r))
		if sh.is_empty() or not s.visited.has(str(r)):
			continue
		var list: Array = out.get(str(sh["god"]), [])
		if not list.has(str(r)):
			list.append(str(r))
		out[str(sh["god"])] = list
	return out


# --- the hero's faith ---------------------------------------------------------------------------------------


static func view(c: Dictionary) -> Dictionary:
	return c.get("faith", {})


static func _rw(c: Dictionary) -> Dictionary:
	if not c.get("faith") is Dictionary:
		c["faith"] = {}
	var f: Dictionary = c["faith"]
	for k: String in ["favor", "served", "donated", "blessed"]:
		if not f.get(k) is Dictionary:
			f[k] = {}
	if not f.get("vows") is Array:
		f["vows"] = []
	if not f.has("god"):
		f["god"] = ""
	if not f.has("lapsed"):
		f["lapsed"] = -1
	return f


static func hero_god(c: Dictionary) -> String:
	return str(view(c).get("god", ""))


static func favor(c: Dictionary, god_id: String) -> int:
	return int(view(c).get("favor", {}).get(god_id, 0))


static func add_favor(c: Dictionary, data: Dictionary, god_id: String, n: int) -> void:
	var f := _rw(c)
	var lim: Dictionary = cfg(data)["favor"]
	f["favor"][god_id] = clampi(favor(c, god_id) + n, int(lim["min"]), int(lim["max"]))


## The step of favor: the last of rules.faith.steps whose `at` is reached.
static func step(data: Dictionary, n: int) -> Dictionary:
	return Scale.step(cfg(data)["steps"], n)


static func step_of(c: Dictionary, data: Dictionary, god_id: String) -> Dictionary:
	return step(data, favor(c, god_id))


static func vow(data: Dictionary, id: String) -> Dictionary:
	return cfg(data).get("vows", {}).get(id, {})


static func vows(c: Dictionary) -> Array:
	return view(c).get("vows", [])


static func has_vow(c: Dictionary, id: String) -> bool:
	return vows(c).any(func(v: Dictionary) -> bool: return str(v["id"]) == id)


static func lapsed(c: Dictionary) -> bool:
	return int(view(c).get("lapsed", -1)) >= 0


## What waits for the atonement: the broken vows' names, «заповедь» when lapsed.
static func broken(c: Dictionary, data: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for v: Dictionary in vows(c):
		if int(v.get("broken", -1)) >= 0:
			out.append(str(vow(data, str(v["id"])).get("name", v["id"])))
	if lapsed(c):
		out.append("заповедь")
	return out


## The gifts of the kept vows for the sheet (RollParts.sheet): labelled parts of a skill or a save.
static func gift_parts(c: Dictionary, data: Dictionary, kind: String, id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not data["rules"].has("faith") or kind == "ability":
		return out
	var key := "skills" if kind == "skill" else "saves"
	for v: Dictionary in vows(c):
		if int(v.get("broken", -1)) >= 0:
			continue
		var g: Dictionary = vow(data, str(v["id"])).get("gift", {}).get(key, {})
		var n := int(g.get(id, g.get("*", 0)))
		if n != 0:
			out.append(RollParts.part("обет «%s»" % vow(data, str(v["id"]))["name"], n))
	return out


## The lapse of a cleric or a paladin (CharacterRules.refresh): the minus to spell_dc / spell_attack, 0 otherwise.
static func lapse(c: Dictionary, data: Dictionary, key: String) -> int:
	if data.is_empty() or not data["rules"].has("faith") or not lapsed(c):
		return 0
	var l: Dictionary = cfg(data)["lapse"]
	return int(l.get(key, 0)) if (l["classes"] as Array).has(str(c.get("class", ""))) else 0


# --- deeds --------------------------------------------------------------------------------------------------


## A forbidden deed `forbid` covers the deed `kind`: the same, a group of rules.faith.deeds, or «crime» for any crime.
static func covers(data: Dictionary, forbid: String, kind: String) -> bool:
	if forbid == kind:
		return true
	var group: Array = cfg(data).get("deeds", {}).get(forbid, [])
	if group.has(kind):
		return true
	return group.has("*") and data["rules"]["crime"].get("kinds", {}).has(kind) and not kind.begins_with("_")


static func deed_name(data: Dictionary, kind: String) -> String:
	var names: Dictionary = cfg(data).get("deed_names", {})
	if names.has(kind):
		return str(names[kind])
	return str(data["rules"]["crime"].get("kinds", {}).get(kind, {}).get("name", kind))


## A fact of the engine the faith may forbid (a crime kind, `check:<skill>`, `rob_dead`) done by the hero in
## `room_id`: the vows that forbid it break, the hero's god's commandment breaks, a deed of desecration in a shrine's
## room. Lines.
static func deed(s: GameSession, data: Dictionary, kind: String, room_id: String = "") -> Array[String]:
	var lines: Array[String] = []
	if not on(data):
		return lines
	var c := s.character
	var f := _rw(c)
	var at := TimeRules.abs_minute(s)
	var last: Dictionary = f.get("last", {})
	if str(last.get("deed", "")) == kind and int(last.get("at", -1)) == at:
		return lines  # one deed seen twice (a theft that is also the crime)
	f["last"] = {"deed": kind, "at": at}
	var changed := false
	for v: Dictionary in f["vows"]:
		if int(v.get("broken", -1)) >= 0:
			continue
		var d := vow(data, str(v["id"]))
		if (d.get("forbids", []) as Array).any(func(x: Variant) -> bool: return covers(data, str(x), kind)):
			v["broken"] = s.day
			changed = true
			lines.append("Обет «%s» нарушен (%s) — его дар ушёл до искупления" % [d["name"], deed_name(data, kind)])
	var mine := hero_god(c)
	var g := god(s, data, mine)
	if not g.is_empty() and (g.get("forbids", []) as Array).any(func(x: Variant) -> bool: return covers(data, str(x), kind)):
		add_favor(c, data, mine, int(cfg(data)["commandment_favor"]))
		lines.append("Заповедь нарушена (%s): %s — благосклонность падает" % [god_name(s, data, mine), str(g.get("commandment", deed_name(data, kind)))])
		lines.append_array(_unbless(c))
		if (cfg(data)["lapse"]["classes"] as Array).has(str(c.get("class", ""))) and not lapsed(c):
			f["lapsed"] = s.day
			lines.append("Связь с богом ослабла: заклинания слабее до искупления")
		changed = true
	var room := room_id if not room_id.is_empty() else s.room_id
	var sh := shrine(s, data, room)
	if not sh.is_empty() and (cfg(data)["desecration"]["deeds"] as Array).has(kind):
		var gid := str(sh["god"])
		f["favor"][gid] = int(cfg(data)["desecration"]["favor"])
		lines.append("Осквернение: %s — слуги бога (%s) отвернутся от вас" % [sh.get("name", "святилище"), god_name(s, data, gid)])
		if gid == mine:
			lines.append_array(_unbless(c))
		changed = true
	if changed:
		CharacterRules.refresh(c, data, s.items)
	return lines


static func _unbless(c: Dictionary) -> Array[String]:
	for e: Dictionary in ConditionRules.effects(c).duplicate():
		if str(e.get("source", {}).get("id", "")) == BLESS_ID:
			ConditionRules.remove_effect(c, int(e.get("uid", 0)))
			return ["Благословение храма ушло"] as Array[String]
	return []


# --- the shrine's acts --------------------------------------------------------------------------------------


static func _here(s: GameSession, data: Dictionary) -> Dictionary:
	if s.in_conversation() or CombatRules.active(s):
		return {}
	return shrine(s, data, s.room_id)


static func _cp(data: Dictionary, key: String) -> int:
	return int(cfg(data)[key]["cost_cp"])


## A service (once in service.every_days for a god): "" or a localization key.
static func service_why(s: GameSession, data: Dictionary) -> String:
	var sh := _here(s, data)
	if sh.is_empty():
		return "FAITH_NO_SHRINE"
	var gid := str(sh["god"])
	if bool(step_of(s.character, data, gid).get("refuse", false)):
		return "FAITH_REFUSED"
	var last := int(view(s.character).get("served", {}).get(gid, -999))
	if s.day - last < int(cfg(data)["service"]["every_days"]):
		return "FAITH_SERVED"
	return ""


## The god's festival is on: a service counts more.
static func festival(s: GameSession, data: Dictionary, god_id: String) -> String:
	var on_now := CalendarRules.active(s, data["world"])
	for fid: Variant in god(s, data, god_id).get("festivals", []):
		if on_now.has(str(fid)):
			return str(CalendarRules.all(s, data["world"]).get(str(fid), {}).get("name", fid))
	return ""


static func service(s: GameSession, data: Dictionary) -> Array[String]:
	var gid := str(_here(s, data)["god"])
	var n := int(cfg(data)["service"]["favor"])
	var fest := festival(s, data, gid)
	if not fest.is_empty():
		n *= int(cfg(data)["service"]["festival_mult"])
	_rw(s.character)["served"][gid] = s.day
	add_favor(s.character, data, gid, n)
	return ["Служба — %s%s: благосклонность +%d (%s)" % [god_name(s, data, gid), (" на празднике «%s»" % fest) if not fest.is_empty() else "", n, _favor_text(s.character, data, gid)]]


static func donate_why(s: GameSession, data: Dictionary) -> String:
	var sh := _here(s, data)
	if sh.is_empty():
		return "FAITH_NO_SHRINE"
	var gid := str(sh["god"])
	if bool(step_of(s.character, data, gid).get("refuse", false)):
		return "FAITH_REFUSED"
	if int(s.character.get("gold_cp", 0)) < _cp(data, "donation"):
		return "FAITH_NO_MONEY"
	var d: Array = view(s.character).get("donated", {}).get(gid, [-1, 0])
	if int(d[0]) == s.day and int(d[1]) >= int(cfg(data)["donation"]["per_day"]):
		return "FAITH_DONATED"
	if int(favor(s.character, gid)) >= int(cfg(data)["favor"]["max"]):
		return "FAITH_FAVOR_MAX"
	return ""


static func donate(s: GameSession, data: Dictionary) -> Array[String]:
	var c := s.character
	var gid := str(_here(s, data)["god"])
	Ledger.add(s, -_cp(data, "donation"), "faith:donate")
	var d: Array = view(c).get("donated", {}).get(gid, [-1, 0])
	_rw(c)["donated"][gid] = [s.day, (int(d[1]) if int(d[0]) == s.day else 0) + 1]
	var n := int(cfg(data)["donation"]["favor"])
	add_favor(c, data, gid, n)
	return ["Пожертвование — %s (%s): благосклонность +%d (%s)" % [god_name(s, data, gid), Money.format(_cp(data, "donation")), n, _favor_text(c, data, gid)]]


## The temple's blessing: the hero's own god, its step gives it, once a day, not while the commandment is broken.
static func bless_why(s: GameSession, data: Dictionary) -> String:
	var sh := _here(s, data)
	if sh.is_empty():
		return "FAITH_NO_SHRINE"
	var gid := str(sh["god"])
	if gid != hero_god(s.character):
		return "FAITH_NOT_YOUR_GOD"
	if lapsed(s.character):
		return "FAITH_LAPSED"
	if not bool(step_of(s.character, data, gid).get("blessing", false)):
		return "FAITH_LOW_FAVOR"
	if s.day - int(view(s.character).get("blessed", {}).get(gid, -999)) < int(cfg(data)["blessing"]["every_days"]):
		return "FAITH_BLESSED"
	return ""


static func bless(s: GameSession, data: Dictionary) -> Array[String]:
	var c := s.character
	var gid := str(_here(s, data)["god"])
	var b: Dictionary = cfg(data)["blessing"]
	_unbless(c)
	_rw(c)["blessed"][gid] = s.day
	var e := {"condition": "", "source": {"kind": "temple", "id": BLESS_ID, "name": "%s (%s)" % [b["name"], god_name(s, data, gid)]},
		"die": str(b["die"]), "on": (b["on"] as Array).duplicate(), "same_as": str(b.get("same_as", "")), "ends": {"rest": "long"}}
	ConditionRules.add_effect(c, e)
	return ["%s: +%s к атакам и спасброскам до долгого отдыха" % [e["source"]["name"], str(b["die"]).replace("d", "к")]]


## A vow at any shrine: "" or a localization key.
static func vow_why(s: GameSession, data: Dictionary, id: String) -> String:
	if _here(s, data).is_empty():
		return "FAITH_NO_SHRINE"
	return vow_ok(s, data, id)


## A vow may be taken (at a shrine or by the master's `vow`): known, not yet, within vows_max.
static func vow_ok(s: GameSession, data: Dictionary, id: String) -> String:
	if vow(data, id).is_empty():
		return "FAITH_NO_VOW"
	if has_vow(s.character, id):
		return "FAITH_VOW_TAKEN"
	if vows(s.character).size() >= int(cfg(data)["vows_max"]):
		return "FAITH_VOWS_MAX"
	return ""


static func take_vow(s: GameSession, data: Dictionary, id: String) -> Array[String]:
	(_rw(s.character)["vows"] as Array).append({"id": id, "since": s.day, "broken": -1})
	CharacterRules.refresh(s.character, data, s.items)
	var d := vow(data, id)
	return ["Обет «%s»: %s" % [d["name"], d.get("text", "")]]


## The atonement: at a shrine of the hero's god (or any, without one), for every broken thing.
static func atone_cost(c: Dictionary, data: Dictionary) -> int:
	return _cp(data, "atone") * broken(c, data).size()


static func atone_why(s: GameSession, data: Dictionary) -> String:
	var sh := _here(s, data)
	if sh.is_empty():
		return "FAITH_NO_SHRINE"
	if broken(s.character, data).is_empty():
		return "FAITH_NOTHING_BROKEN"
	if not hero_god(s.character).is_empty() and str(sh["god"]) != hero_god(s.character):
		return "FAITH_NOT_YOUR_GOD"
	if bool(step_of(s.character, data, str(sh["god"])).get("refuse", false)):
		return "FAITH_REFUSED"
	if int(s.character.get("gold_cp", 0)) < atone_cost(s.character, data):
		return "FAITH_NO_MONEY"
	return ""


static func atone(s: GameSession, data: Dictionary) -> Array[String]:
	var c := s.character
	var what := broken(c, data)
	Ledger.add(s, -atone_cost(c, data), "faith:atone")
	var f := _rw(c)
	for v: Dictionary in f["vows"]:
		if int(v.get("broken", -1)) >= 0:
			v["broken"] = -1
			v["since"] = s.day
	f["lapsed"] = -1
	CharacterRules.refresh(c, data, s.items)
	return ["Искупление (%s): %s — снова в силе" % [shrine(s, data, s.room_id).get("name", "святилище"), ", ".join(what)]]


## Taking the faith of this shrine's god: the first one free, a change — the cost and the cooldown.
static func convert_why(s: GameSession, data: Dictionary) -> String:
	var sh := _here(s, data)
	if sh.is_empty():
		return "FAITH_NO_SHRINE"
	var gid := str(sh["god"])
	var c := s.character
	if gid == hero_god(c):
		return "FAITH_ALREADY"
	if bool(step_of(c, data, gid).get("refuse", false)):
		return "FAITH_REFUSED"
	if hero_god(c).is_empty():
		return ""
	if s.day - int(view(c).get("converted", -999)) < int(cfg(data)["convert"]["cooldown_days"]):
		return "FAITH_CONVERT_SOON"
	if int(c.get("gold_cp", 0)) < _cp(data, "convert"):
		return "FAITH_NO_MONEY"
	return ""


static func convert_cost(c: Dictionary, data: Dictionary) -> int:
	return 0 if hero_god(c).is_empty() else _cp(data, "convert")


static func convert(s: GameSession, data: Dictionary) -> Array[String]:
	var c := s.character
	var gid := str(_here(s, data)["god"])
	var old := hero_god(c)
	Ledger.add(s, -convert_cost(c, data), "faith:convert")
	var f := _rw(c)
	f["god"] = gid
	f["converted"] = s.day
	f["lapsed"] = -1
	_unbless(c)
	CharacterRules.refresh(c, data, s.items)
	if old.is_empty():
		return ["Вы приняли веру: %s" % god_name(s, data, gid, true)]
	return ["Обращение: %s вместо %s" % [god_name(s, data, gid, true), god_name(s, data, old)]]


## Sets the hero's god at creation (CharacterBuilder) — no checks.
static func start(c: Dictionary, god_id: String) -> void:
	if god_id.is_empty():
		return
	_rw(c)["god"] = god_id


# --- what favor gives -----------------------------------------------------------------------------------------


## The discount of a priest of the hero's god on its services, percent.
static func discount_pct(s: GameSession, data: Dictionary, npc_id: String) -> int:
	if not on(data):
		return 0
	var gid := str(WorldView.new(data["world"]).npc(npc_id).get("god", ""))
	if gid.is_empty() or gid != hero_god(s.character):
		return 0
	return int(step_of(s.character, data, gid).get("discount_pct", 0))


## A servant of a god the hero desecrated will not serve: "" or the reason.
static func refuses(s: GameSession, data: Dictionary, npc_id: String) -> String:
	if not on(data):
		return ""
	var gid := str(WorldView.new(data["world"]).npc(npc_id).get("god", ""))
	if gid.is_empty() or not bool(step_of(s.character, data, gid).get("refuse", false)):
		return ""
	return "осквернитель святыни (%s)" % god_name(s, data, gid)


## A bed at a shrine of the hero's god for the chosen of it (ExplorationRules.rest_place).
static func shelter(s: GameSession, data: Dictionary, room_id: String) -> bool:
	if not on(data):
		return false
	var sh := shrine(s, data, room_id)
	return not sh.is_empty() and str(sh["god"]) == hero_god(s.character) and bool(step_of(s.character, data, str(sh["god"])).get("shelter", false))


# --- texts -------------------------------------------------------------------------------------------------


static func _favor_text(c: Dictionary, data: Dictionary, god_id: String) -> String:
	return "%s, %d" % [step_of(c, data, god_id).get("name", ""), favor(c, god_id)]


## The hero's faith for the master and the sheet: the god, the favor, the vows, what is broken.
static func text(s: GameSession, data: Dictionary) -> String:
	if not on(data):
		return ""
	var c := s.character
	var parts: Array[String] = []
	var mine := hero_god(c)
	if not mine.is_empty():
		var g := god(s, data, mine)
		parts.append("вера: %s — %s; заповедь: %s" % [god_name(s, data, mine, true), _favor_text(c, data, mine), g.get("commandment", "")])
	for v: Dictionary in vows(c):
		var d := vow(data, str(v["id"]))
		parts.append("обет «%s» (%s)%s" % [d.get("name", v["id"]), d.get("text", ""), " — нарушен" if int(v.get("broken", -1)) >= 0 else ""])
	if lapsed(c):
		parts.append("заповедь нарушена — нужно искупление")
	for gid: String in view(c).get("favor", {}):
		if gid != mine and favor(c, gid) != 0:
			parts.append("%s: %s" % [god_name(s, data, gid), _favor_text(c, data, gid)])
	return "; ".join(parts)


## The shrine of the scene for the master: whose it is, the god's word, the hero's standing there.
static func scene_text(s: GameSession, data: Dictionary) -> String:
	if not on(data):
		return ""
	var sh := shrine(s, data, s.room_id)
	if sh.is_empty():
		return ""
	var gid := str(sh["god"])
	var g := god(s, data, gid)
	var out := "%s — святилище, бог: %s — %s; заповедь: %s" % [sh.get("name", "святилище"), god_name(s, data, gid, true), g.get("text", ""), g.get("commandment", "")]
	var mine := hero_god(s.character)
	if gid == mine:
		out += "; бог героя (%s)" % _favor_text(s.character, data, gid)
	elif (g.get("enemies", []) as Array).has(mine):
		out += "; враг веры героя"
	if bool(step_of(s.character, data, gid).get("refuse", false)):
		out += "; герой — осквернитель этой святыни"
	return out


## An NPC's god for the master: «служит Чонтии (Светлая Мать)», with the enmity to the hero's god.
static func npc_text(s: GameSession, data: Dictionary, npc_id: String) -> String:
	if not on(data):
		return ""
	var gid := str(WorldView.new(data["world"]).npc(npc_id).get("god", ""))
	if gid.is_empty():
		return ""
	var out := "вера: %s" % god_name(s, data, gid, true)
	var mine := hero_god(s.character)
	if (god(s, data, gid).get("enemies", []) as Array).has(mine) or (god(s, data, mine).get("enemies", []) as Array).has(gid):
		out += ", враг веры героя"
	elif gid == mine:
		out += ", одной веры с героем"
	return out


# --- the master: `vow` and `god` -------------------------------------------------------------------------------


## `vow` {vow, cause}: the hero swears by words a vow of the list. A plan or {reason}.
static func plan_vow(s: GameSession, data: Dictionary, e: Dictionary) -> Dictionary:
	if not on(data):
		return {"reason": "веры в этих правилах нет"}
	var id := str(e.get("vow", "")) if e.get("vow") != null else ""
	var why := vow_ok(s, data, id)
	match why:
		"FAITH_NO_VOW":
			return {"reason": "vow — из %s" % ", ".join(cfg(data)["vows"].keys())}
		"FAITH_VOW_TAKEN":
			return {"reason": "этот обет у героя уже есть"}
		"FAITH_VOWS_MAX":
			return {"reason": "у героя уже %d обета — больше нельзя" % int(cfg(data)["vows_max"])}
	return {"plan": {"vow": id}, "summary": "Обет «%s»" % vow(data, id)["name"]}


static func apply_vow(s: GameSession, data: Dictionary, p: Dictionary) -> Array[String]:
	return take_vow(s, data, str(p["vow"]))


## `god` {god_id | new {name, title, domains, text, forbids, commandment, enemies}, shrine_name, cause}: a shrine
## in the hero's room to a god of the pack or a new one (a local cult, a forgotten spirit). A plan or {reason}.
static func plan_god(s: GameSession, data: Dictionary, e: Dictionary) -> Dictionary:
	if not on(data):
		return {"reason": "веры в этих правилах нет"}
	if not shrine(s, data, s.room_id).is_empty():
		return {"reason": "здесь уже святилище: " + str(shrine(s, data, s.room_id).get("name", ""))}
	var name := str(e.get("shrine_name", "")).strip_edges() if e.get("shrine_name") != null else ""
	if name.length() < 3:
		return {"reason": "нужно shrine_name — как выглядит святилище («камень с вырезанным ликом»)"}
	var gid := str(e.get("god_id", "")) if e.get("god_id") != null else ""
	var nw: Dictionary = e.get("new", {}) if e.get("new") is Dictionary else {}
	if not gid.is_empty():
		if god(s, data, gid).is_empty():
			return {"reason": "god_id — из %s, или new — новый бог" % ", ".join(gods(s, data).keys())}
		return {"plan": {"god_id": gid, "shrine": name.left(80)}, "summary": "Святилище %s" % god_name(s, data, gid)}
	if str(nw.get("name", "")).strip_edges().length() < 2:
		return {"reason": "нужен god_id бога пакета или new с name"}
	for g: Dictionary in gods(s, data).values():
		if str(g["name"]).to_lower() == str(nw["name"]).strip_edges().to_lower():
			return {"reason": "такой бог уже есть — дай его god_id"}
	var allowed: Array = cfg(data)["make"]["forbids"]
	var forbids: Array = []
	for x: Variant in nw.get("forbids", []):
		if not allowed.has(str(x)):
			return {"reason": "forbids — из %s" % ", ".join(allowed)}
		forbids.append(str(x))
	var enemies: Array = []
	for x: Variant in nw.get("enemies", []):
		if not god(s, data, str(x)).is_empty():
			enemies.append(str(x))
	var def := {"name": str(nw["name"]).strip_edges().left(40), "title": str(nw.get("title", "")).strip_edges().left(60),
		"domains": (nw.get("domains", []) as Array).map(func(x: Variant) -> String: return str(x).left(30)).slice(0, 3),
		"text": str(nw.get("text", "")).strip_edges().left(200), "forbids": forbids, "enemies": enemies, "festivals": [],
		"commandment": str(nw.get("commandment", "")).strip_edges().left(120), "made": true}
	return {"plan": {"new": def, "shrine": name.left(80)}, "summary": "Святилище нового бога: %s" % def["name"]}


static func apply_god(s: GameSession, data: Dictionary, p: Dictionary) -> Array[String]:
	var st := _gen(s)
	var gid := str(p.get("god_id", ""))
	if p.has("new"):
		st["seq"] = int(st["seq"]) + 1
		gid = "god_m%d" % int(st["seq"])
		st["gods"][gid] = p["new"]
	st["shrines"][s.room_id] = {"god": gid, "name": str(p["shrine"])}
	return ["Святилище: %s — %s" % [p["shrine"], god_name(s, data, gid, true)]]
