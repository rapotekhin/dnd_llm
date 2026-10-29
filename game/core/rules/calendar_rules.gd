class_name CalendarRules
extends RefCounted
## The calendar and festivals (roadmap v0.7.44). A pack's `calendar` {start {month, day, weekday}, week [day names],
## seasons {id: name}, months [{id, name, of, days, season}], festivals {id: {name, month?, day?, weekday?, days,
## location, flags, guests {npc: room}, trade {buy_pct, sell_pct, tags}, text}}} turns the game's day count into a
## date. A festival recurs: `month` + `day` — once a year, `day` alone — every month, `weekday` — every week. While it
## is on, its `flags` are world flags (rooms' and traders' variants, pack quests with `festival`), its `guests` stand
## in their rooms (SceneRules.npcs), and the traders of its location sell and buy at its `trade` percents (TradeRules);
## when it ends the flags it set are taken off. The master's `festival` effect adds one of its own — a feast, a fair
## announced — with a cause, days and trade within rules.calendar.make; it has no flags and no guests.

static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"].get("calendar", {})


static func cal(world: Dictionary) -> Dictionary:
	return world.get("calendar", {})


static func on(world: Dictionary) -> bool:
	return not (cal(world).get("months", []) as Array).is_empty()


static func _state(s: GameSession) -> Dictionary:
	var gen := WorldGen.generated(s)
	if not gen.has("calendar"):
		gen["calendar"] = {"on": {}, "made": {}}
	return gen["calendar"]


static func year_days(world: Dictionary) -> int:
	var n := 0
	for m: Dictionary in cal(world)["months"]:
		n += int(m["days"])
	return n


## The date of a game day: {year, month (index), day, weekday (index), season}.
static func date(world: Dictionary, game_day: int) -> Dictionary:
	var c := cal(world)
	var months: Array = c["months"]
	var start: Dictionary = c.get("start", {})
	var offset := 0
	for i in months.size():
		if str(months[i]["id"]) == str(start.get("month", months[0]["id"])):
			break
		offset += int(months[i]["days"])
	offset += int(start.get("day", 1)) - 1 + game_day - 1
	var len := year_days(world)
	var year := int(start.get("year", 1)) + floori(float(offset) / len)
	var rest := posmod(offset, len)
	var mi := 0
	while rest >= int(months[mi]["days"]):
		rest -= int(months[mi]["days"])
		mi += 1
	var week: Array = c.get("week", [])
	return {"year": year, "month": mi, "day": rest + 1, "season": str(months[mi].get("season", "")),
		"weekday": posmod(int(start.get("weekday", 0)) + game_day - 1, maxi(1, week.size()))}


## «3 Жатвеня, день Торга» — the date of a game day in words; «день N» without a calendar.
static func text(world: Dictionary, game_day: int) -> String:
	if not on(world):
		return "день %d" % game_day
	var d := date(world, game_day)
	var m: Dictionary = cal(world)["months"][int(d["month"])]
	var week: Array = cal(world).get("week", [])
	return "%d %s%s" % [int(d["day"]), m.get("of", m["name"]), (", " + str(week[int(d["weekday"])])) if not week.is_empty() else ""]


## «лето, 412 год» — the season and the year.
static func season_text(world: Dictionary, game_day: int) -> String:
	if not on(world):
		return ""
	var d := date(world, game_day)
	var season := str(cal(world).get("seasons", {}).get(str(d["season"]), d["season"]))
	return "%s, %d год" % [season, int(d["year"])] if not season.is_empty() else "%d год" % int(d["year"])


## Does a pack festival start on this game day?
static func _starts(world: Dictionary, f: Dictionary, game_day: int) -> bool:
	var d := date(world, game_day)
	if f.has("weekday"):
		return int(d["weekday"]) == int(f["weekday"])
	if f.has("month") and str(cal(world)["months"][int(d["month"])]["id"]) != str(f["month"]):
		return false
	return f.has("day") and int(d["day"]) == int(f["day"])


## Every festival, the pack's and the master's: {id: def} (a master's one carries `start_day`).
static func all(s: GameSession, world: Dictionary) -> Dictionary:
	var out: Dictionary = cal(world).get("festivals", {}).duplicate()
	if s != null:
		var made: Dictionary = _state(s)["made"]
		for id: String in made:
			out[id] = made[id]
	return out


## The game day a festival's current run began (it is on today), or -1.
static func began(world: Dictionary, f: Dictionary, game_day: int) -> int:
	if f.has("start_day"):
		var b := int(f["start_day"])
		return b if game_day >= b and game_day < b + int(f.get("days", 1)) else -1
	if not on(world):
		return -1
	for k in int(f.get("days", 1)):
		if game_day - k >= 1 - year_days(world) and _starts(world, f, game_day - k):
			return game_day - k
	return -1


## The next game day it begins after today (the run on now does not count), or -1 within a year.
static func next_start(world: Dictionary, f: Dictionary, game_day: int) -> int:
	if f.has("start_day"):
		return int(f["start_day"]) if int(f["start_day"]) > game_day else -1
	if not on(world):
		return -1
	for k in range(1, year_days(world) + 1):
		if _starts(world, f, game_day + k):
			return game_day + k
	return -1


## The festivals on today: [id].
static func active(s: GameSession, world: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var fs := all(s, world)
	for id: String in fs:
		if began(world, fs[id], s.day) >= 0:
			out.append(id)
	return out


## The world's flags of the pack's festivals follow the calendar: on for their days, off when they end. Lines.
static func sync(s: GameSession, world: Dictionary) -> Array[String]:
	if not on(world):
		return []
	var st := _state(s)
	var was: Dictionary = st["on"]
	var now := active(s, world)
	var fs := all(s, world)
	var lines: Array[String] = []
	for id: String in was.keys():
		if now.has(id):
			continue
		for f: Variant in was[id]:
			s.flags.erase(str(f))
		was.erase(id)
		if fs.has(id):
			lines.append("Праздник кончился: %s" % fs[id]["name"])
	for id: String in now:
		if was.has(id):
			continue
		var set: Array = []
		for f: Variant in fs[id].get("flags", []):
			if not s.flags.has(str(f)):
				s.flags.append(str(f))
				set.append(str(f))
		was[id] = set
		lines.append("Праздник: %s — %s" % [fs[id]["name"], days_word(int(fs[id].get("days", 1)) - (s.day - began(world, fs[id], s.day)))])
	return lines


## «ещё 2 дня» / «последний день».
static func days_word(left: int) -> String:
	return "последний день" if left <= 1 else "ещё %d %s" % [left, _plural(left)]


static func _plural(n: int) -> String:
	var m := n % 100
	if m >= 11 and m <= 14:
		return "дней"
	match n % 10:
		1: return "день"
		2, 3, 4: return "дня"
	return "дней"


## The location of a festival's name: «Ольховый Брод».
static func _where(world: Dictionary, f: Dictionary) -> String:
	return str(WorldView.new(world).location(str(f.get("location", ""))).get("name", f.get("location", "")))


## The festivals on now and ahead within rules.calendar.near_days, nearest first: [{id, name, where, text, on, left,
## in, day}] — `left` days to its end when on, `in` days to its start when ahead.
static func upcoming(s: GameSession, data: Dictionary, world: Dictionary, near: int = -1) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var horizon := near if near >= 0 else int(cfg(data).get("near_days", 14))
	var fs := all(s, world)
	for id: String in fs:
		var f: Dictionary = fs[id]
		var b := began(world, f, s.day)
		var e := {"id": id, "name": str(f["name"]), "where": _where(world, f), "text": str(f.get("text", "")), "made": f.has("start_day")}
		if b >= 0:
			e.merge({"on": true, "left": int(f.get("days", 1)) - (s.day - b), "in": 0, "day": b})
			out.append(e)
		var n := next_start(world, f, s.day)
		if n > 0 and n - s.day <= horizon:
			var e2 := e.duplicate()
			e2.merge({"on": false, "left": 0, "in": n - s.day, "day": n}, true)
			out.append(e2)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["in"]) < int(b["in"]) if int(a["in"]) != int(b["in"]) else str(a["name"]) < str(b["name"]))
	return out


## A line of a festival for the panel, the journal and the master: «Ярмарка (Ольховый Брод) — через 5 дней, 8 Жатвеня».
static func line(world: Dictionary, e: Dictionary, with_text: bool = false) -> String:
	var when := ("идёт, " + days_word(int(e["left"]))) if bool(e["on"]) else "через %d %s, %s" % [int(e["in"]), _plural(int(e["in"])), text(world, int(e["day"]))]
	return "%s (%s) — %s%s" % [e["name"], e["where"], when, (": " + str(e["text"])) if with_text and not str(e["text"]).is_empty() else ""]


## The master's lines: the festivals on and near with what they bring.
static func snapshot(s: GameSession, data: Dictionary, world: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for e: Dictionary in upcoming(s, data, world):
		out.append(line(world, e, true))
	return out


## The guests of the festivals on now in this room: [npc ids].
static func guests(s: GameSession, world: Dictionary, room_id: String) -> Array[String]:
	var out: Array[String] = []
	if s == null:
		return out
	var fs := all(s, world)
	for id: String in active(s, world):
		var g: Dictionary = fs[id].get("guests", {})
		for npc: String in g:
			if str(g[npc]) == room_id and not out.has(npc):
				out.append(npc)
	return out


## The trade percent of the festivals on now where the hero trades (`kind` "buy" — what the hero pays, "sell" — what he
## gets) for an item: the product of their `trade.<kind>_pct`; `trade.tags` limits it to items of those trade tags
## ("food" — the camp's food).
static func price_pct(s: GameSession, data: Dictionary, item_id: String, kind: String) -> float:
	var world: Dictionary = data["world"]
	var loc := WorldView.new(world).location_id(s.room_id)
	var fs := all(s, world)
	var pct := 1.0
	for id: String in active(s, world):
		var f: Dictionary = fs[id]
		var t: Dictionary = f.get("trade", {})
		if str(f.get("location", "")) != loc or not t.has(kind + "_pct"):
			continue
		if t.has("tags") and not _tagged(s, data, item_id, t["tags"]):
			continue
		pct *= float(t[kind + "_pct"]) / 100.0
	return pct


static func _tagged(s: GameSession, data: Dictionary, item_id: String, tags: Array) -> bool:
	var have := ItemRules.trade_tags(ItemRules.def_of(data["items"], s.items, item_id))
	if data["rules"].get("hero_effects", {}).get("camp", {}).get("food", {}).has(ItemRules.real_id(item_id)):
		have.append("food")
	return tags.any(func(t: Variant) -> bool: return have.has(str(t)))


## Pack quests of a festival (`festival`) are offered only while it is on.
static func quest_open(s: GameSession, world: Dictionary, q: Dictionary) -> bool:
	return not q.has("festival") or active(s, world).has(str(q["festival"]))


# --- the master's festival -------------------------------------------------------------------------------------


## The master's `festival` {name, cause, location?, starts_in, days, buy_pct?, sell_pct?, tags?}: within
## rules.calendar.make, one of its own at a time in a location. {plan, summary} or {reason}.
static func plan_festival(s: GameSession, data: Dictionary, e: Dictionary) -> Dictionary:
	var mk: Dictionary = cfg(data).get("make", {})
	if mk.is_empty():
		return {"reason": "праздников мастера в этом мире нет"}
	var name := str(e.get("name", "")).strip_edges() if e.get("name") != null else ""
	if name.length() < 3:
		return {"reason": "name — как праздник зовут люди"}
	var cause := str(e.get("cause", "")).strip_edges() if e.get("cause") != null else ""
	if cause.length() < 8:
		return {"reason": "нужна cause — по какому поводу праздник (от 8 знаков)"}
	var world := WorldGen.merged(data["world"], WorldGen.generated(s))
	var loc := str(e.get("location_id", "")) if e.get("location_id") != null else ""
	if loc.is_empty():
		loc = WorldView.new(world).location_id(s.room_id)
	if not world["locations"].has(loc):
		return {"reason": "location_id — локация мира"}
	var ahead := int(e.get("starts_in", 0)) if e.get("starts_in") != null else 0
	if ahead < 0 or ahead > int(mk["max_ahead"]):
		return {"reason": "starts_in — от 0 до %d дней" % int(mk["max_ahead"])}
	var days := int(e.get("days", 1)) if e.get("days") != null else 1
	if days < 1 or days > int(mk["max_days"]):
		return {"reason": "days — от 1 до %d" % int(mk["max_days"])}
	var trade := {}
	for k: String in ["buy", "sell"]:
		var v: Variant = e.get(k + "_pct")
		if v == null or int(v) == 100:
			continue
		var lim: Array = mk[k + "_pct"]
		if int(v) < int(lim[0]) or int(v) > int(lim[1]):
			return {"reason": "%s_pct — от %d до %d" % [k, int(lim[0]), int(lim[1])]}
		trade[k + "_pct"] = int(v)
	if not trade.is_empty() and e.get("tags") is Array and not (e["tags"] as Array).is_empty():
		trade["tags"] = (e["tags"] as Array).map(func(t: Variant) -> String: return str(t))
	var start := s.day + ahead
	for id: String in _state(s)["made"]:
		var f: Dictionary = _state(s)["made"][id]
		if str(f["location"]) == loc and int(f["start_day"]) + int(f["days"]) > s.day:
			return {"reason": "в %s уже назначен праздник мастера «%s» — один за раз" % [world["locations"][loc].get("name", loc), f["name"]]}
	var f := {"name": name.left(40), "location": loc, "start_day": start, "days": days, "trade": trade, "cause": cause.left(120)}  # not `text`: a plan with text is a note
	return {"plan": f, "summary": "Праздник «%s» — %s" % [f["name"], "сегодня" if ahead == 0 else "через %d %s" % [ahead, _plural(ahead)]]}


static func apply_festival(s: GameSession, data: Dictionary, plan: Dictionary) -> Array[String]:
	var made: Dictionary = _state(s)["made"]
	var id := "made_%d" % (made.size() + 1)
	while made.has(id):
		id += "_"
	made[id] = plan.duplicate(true)
	made[id]["text"] = made[id]["cause"]
	var world: Dictionary = data["world"]
	var lines: Array[String] = ["Праздник «%s»: %s, %d %s" % [plan["name"], "сегодня" if int(plan["start_day"]) == s.day else text(world, int(plan["start_day"])), int(plan["days"]), _plural(int(plan["days"]))]]
	lines.append_array(sync(s, world))
	return lines
