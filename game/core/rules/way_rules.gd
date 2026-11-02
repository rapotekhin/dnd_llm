class_name WayRules
extends RefCounted
## Ways (v0.7.66, the audit's «Проход»): any way between two places — a door, a gate, a crawl, a ford, a road, a breach —
## one row of data, read here. The room's `exits` stay its list of neighbours; a way with something to say has a row in
## the room's `ways` {to: {kind, ...}} over `rules.ways.kinds`, a way without one is plain (a road between locations).
## Each side has its own row: a way one side knows is written there, a way with one direction stands in one `exits`.
## `when` shuts that side until the fact is true. A leaf (a door by the pack, the way into a site with hours) is a thing:
## its state lives in s.ways {"a|b": {...}} — unlocked until, locked, broken, its HP and effects with a cause and a time;
## its body, material and statuses are ThingRules' (v0.7.65). It opens by a key, thieves' tools (Sleight of Hand), force
## (Athletics — it breaks), blows of a weapon (its AC and HP), Knock, the latch from its own side; Arcane Lock locks it
## harder; fire burns a wooden one through. A `solid` leaf (a rotten partition, a blocked passage) has no lock: it only
## breaks. Forcing, hacking or burning a way into a closed or private site before eyes is a trespass at once.
## v0.8.4.2: the way into a private room of someone else from a public room or from another site is a door shut to the
## hero (`private`, DOOR_PRIVATE): the owner's leave opens it, so does a picked lock or a broken leaf.


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"]["ways"]


static func key(a: String, b: String) -> String:
	return "%s|%s" % ([a, b] if a < b else [b, a])


## The way from `a` to `b`: its own row, the other side's when it has none, over its kind. Always a `kind`.
static func row(data: Dictionary, a: String, b: String) -> Dictionary:
	var rooms: Dictionary = data["world"]["rooms"]
	var own: Variant = rooms.get(a, {}).get("ways", {}).get(b, rooms.get(b, {}).get("ways", {}).get(a))
	var w := WorldView.new(data["world"])
	var kind := str(own.get("kind", "")) if own is Dictionary else ""
	if kind.is_empty():
		kind = "plain" if w.location_id(a) == w.location_id(b) else "road"
	var out: Dictionary = (cfg(data)["kinds"].get(kind, {}) as Dictionary).duplicate()
	if own is Dictionary:
		out.merge(own, true)
	out["kind"] = kind
	for sid: String in [w.site_id(b), w.site_id(a)]:
		if w.site_id(a) != w.site_id(b) and w.site(sid).has("hours"):
			out["site"] = sid
			break
	for side: Array in [[b, a], [a, b]]:
		if not w.is_public(side[0]) and (w.is_public(side[1]) or w.site_id(a) != w.site_id(b)) and not str(w.inherit(side[0], "owner", "")).is_empty():
			out["private"] = side[0]
			break
	return out


## The leaf of the way: {} — nothing that shuts it. The way into a site with hours has a door whatever its kind.
static func def(data: Dictionary, a: String, b: String) -> Dictionary:
	var r := row(data, a, b)
	if not bool(r.get("leaf", false)) and not r.has("site") and not r.has("private"):
		return {}
	if not bool(r.get("leaf", false)):
		r.merge(cfg(data)["kinds"]["door"])
		r["kind"] = "door"
	r.merge(cfg(data)["default"])
	return r


## The exits of a room the player can take now: the side's own row with `when` opens the way only when its fact is true
## (Cond; the burrow under the hollow).
static func open_exits(s: GameSession, world: Dictionary, room_id: String) -> Array[String]:
	var out: Array[String] = []
	var own: Dictionary = world["rooms"].get(room_id, {}).get("ways", {})
	for e: Variant in world["rooms"].get(room_id, {}).get("exits", []):
		if Cond.holds(s, own.get(str(e), {})):
			out.append(str(e))
	return out


## The known ways a state of the world shuts now (`when` by `not_flag` — a ford a downpour flooded, v0.7.46):
## [{to, text}]. The ways a search must find stay unseen.
static func shut_exits(s: GameSession, world: Dictionary, room_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var own: Dictionary = world["rooms"].get(room_id, {}).get("ways", {})
	for to: String in own:
		var when: Dictionary = own[to].get("when", {})
		if when.has("not_flag") and not Cond.met(s, when):
			out.append({"to": to, "text": str(own[to].get("text", ""))})
	return out


## The ways this side keeps shut now: their `text` («лаз под корнями ещё надо найти»), never where they lead.
static func closed_texts(s: GameSession, world: Dictionary, room_id: String) -> Array[String]:
	var out: Array[String] = []
	var own: Dictionary = world["rooms"].get(room_id, {}).get("ways", {})
	var open := open_exits(s, world, room_id)
	for to: String in own:
		if own[to].has("when") and not open.has(to):
			out.append(str(own[to].get("text", "закрытый путь")))
	return out


## Does a body of `size` go through the way?
static func fits(r: Dictionary, size: String) -> bool:
	return not r.has("max_size") or CombatRules.SIZES.find(size) <= CombatRules.SIZES.find(str(r["max_size"]))


## "" or why a beast of the monster `id` does not go from `a` to `b` (a crawl, a ladder, too narrow).
static func beast_why(data: Dictionary, a: String, b: String, id: String) -> String:
	var r := row(data, a, b)
	var how: Dictionary = cfg(data)["how"].get(str(r.get("how", "walk")), {})
	if bool(how.get("beasts", true)) and fits(r, str(data["monsters"].get(id, {}).get("size", "medium"))):
		return ""
	return "%s: животному не пройти" % str(r.get("name", "проход"))


## The minutes of a step: the way's own, else a step or a journey by the time rules; its manner adds.
static func minutes(data: Dictionary, a: String, b: String) -> int:
	var r := row(data, a, b)
	var w := WorldView.new(data["world"])
	var base := int(r.get("minutes", data["rules"]["time"]["move_minutes" if w.location_id(a) == w.location_id(b) else "travel_minutes"]))
	return base + int(cfg(data)["how"].get(str(r.get("how", "walk")), {}).get("minutes", 0))


## Does sight, a shot or a sound go through the way now? An open way lets all through, a shut leaf what it `passes`.
static func passes(s: GameSession, data: Dictionary, a: String, b: String, what: String) -> bool:
	var d := def(data, a, b)
	if d.is_empty() or bool(s.ways.get(key(a, b), {}).get("broken", false)):
		return true
	return (d.get("passes", []) as Array).has(what)


## The step `a` → `b` is made: a way with `drop` is a fall by 5e, 1d6 for 10 feet up to 20d6, unless the hero flies. Lines.
static func on_pass(s: GameSession, data: Dictionary, a: String, b: String) -> Array[String]:
	var feet := int(row(data, a, b).get("drop", 0))
	if feet < 10 or Move.air(s, data, Sheet.HERO):
		return []
	var dmg := Sheet.taken(s, data, Sheet.HERO, "bludgeoning", CombatRules.roll_dice(s.rng, "%dd6" % mini(feet / 10, 20)))
	var lines: Array[String] = ["Падение с %d футов: −%d HP" % [feet, dmg]]
	Harm.take(s, data, Sheet.HERO, dmg, lines, "bludgeoning")
	return lines


## The site's hours now: {} — always open; else {open: bool, opens: abs minute of the next opening}.
static func hours(s: GameSession, data: Dictionary, site_id: String) -> Dictionary:
	var h: Dictionary = WorldView.new(data["world"]).site(site_id).get("hours", {})
	if h.is_empty():
		return {}
	var from := int(h["from"])
	var to := int(h["to"])
	var hour := s.minute / 60
	var open := (hour >= from and hour < to) if from < to else (hour >= from or hour < to)
	var opens := (s.day - 1) * 1440 + from * 60
	if opens <= TimeRules.abs_minute(s):
		opens += 1440
	return {"open": open, "opens": opens, "from": from, "to": to}


static func _st(s: GameSession, a: String, b: String) -> Dictionary:
	var k := key(a, b)
	if not s.ways.has(k):
		s.ways[k] = {}
	return s.ways[k]


static func max_hp(data: Dictionary, d: Dictionary) -> int:
	return int(ThingRules.material(data, d).get("door_hp", 18))


static func hp(s: GameSession, data: Dictionary, a: String, b: String) -> int:
	return maxi(0, max_hp(data, def(data, a, b)) - int(s.ways.get(key(a, b), {}).get("dmg", 0)))


static func has_effect(s: GameSession, a: String, b: String, kind: String) -> bool:
	return ThingRules.has(s, s.ways.get(key(a, b), {}), kind)


## "" — the hero passes from `a` to `b`; else why not (a localization key): DOOR_BURNING, DOOR_ARCANE, DOOR_LOCKED,
## DOOR_CLOSED_HOURS (only from outside the site), DOOR_PRIVATE (into a stranger's private room), DOOR_SOLID (a wall),
## DOOR_TOO_SMALL.
static func blocked(s: GameSession, data: Dictionary, a: String, b: String) -> String:
	if not fits(row(data, a, b), CombatRules.hero_size(s, data)):
		return "DOOR_TOO_SMALL"
	var d := def(data, a, b)
	if d.is_empty():
		return ""
	var st: Dictionary = s.ways.get(key(a, b), {})
	if bool(st.get("broken", false)):
		return "DOOR_BURNING" if has_effect(s, a, b, "burning") else ""
	if has_effect(s, a, b, "burning"):
		return "DOOR_BURNING"
	if has_effect(s, a, b, "arcane_lock") and not has_effect(s, a, b, "knocked") and not bool(st.get("arcane_by_hero", false)):
		return "DOOR_ARCANE"
	if bool(d.get("solid", false)):
		return "DOOR_SOLID"
	var now := TimeRules.abs_minute(s)
	if int(st.get("unlocked_until", -1)) > now:
		return ""
	if bool(st.get("locked", bool(d.get("locked", false)))):
		return "DOOR_LOCKED"
	var h := hours(s, data, str(d.get("site", "")))
	var w := WorldView.new(data["world"])
	if not h.is_empty() and not bool(h["open"]) and w.site_id(a) != str(d["site"]):  # from inside the latch opens
		return "DOOR_CLOSED_HOURS"
	if str(d.get("private", "")) == b and not SiteRules.unwelcome(s, data, b).is_empty():
		return "DOOR_PRIVATE"
	return ""


## The word on the exit button: «· заперто до 08:00», «· горит», «· выбита», «· дверь».
static func label(s: GameSession, data: Dictionary, a: String, b: String) -> String:
	var d := def(data, a, b)
	var why := blocked(s, data, a, b)
	if d.is_empty() and why.is_empty():
		var word := str(row(data, a, b).get("name", ""))
		return "" if word.is_empty() else " · " + word
	if why == "DOOR_CLOSED_HOURS":
		return TranslationServer.translate("DOOR_LABEL_HOURS").format({"time": "%02d:00" % int(hours(s, data, str(d["site"]))["from"])})
	if not why.is_empty():
		return TranslationServer.translate("DOOR_LABEL_" + why.trim_prefix("DOOR_"))
	if bool(s.ways.get(key(a, b), {}).get("broken", false)):
		return TranslationServer.translate("DOOR_LABEL_BROKEN")
	return "" if str(d.get("kind", "door")) == "door" else " · " + str(d.get("name", ""))


## For the master: «дверь (дерево) заперта до 08:00 — часы объекта» and the effects on it.
static func describe(s: GameSession, data: Dictionary, a: String, b: String) -> String:
	var d := def(data, a, b)
	if d.is_empty():
		var r := row(data, a, b)
		var open: Array[String] = [str(r.get("name", "")), str(r.get("note", ""))]
		return " · ".join(open.filter(func(x: String) -> bool: return not x.is_empty()))
	var bits: Array[String] = ["%s (%s)" % [str(d.get("name", "дверь")), str(ThingRules.material(data, d).get("name", d.get("material", "")))]]
	var why := blocked(s, data, a, b)
	if bool(s.ways.get(key(a, b), {}).get("broken", false)):
		bits.append("выбита")
	match why:
		"DOOR_CLOSED_HOURS":
			bits.append("заперта до %02d:00 — часы объекта" % int(hours(s, data, str(d["site"]))["from"]))
		"DOOR_LOCKED":
			bits.append("заперта")
		"DOOR_PRIVATE":
			bits.append("заперта для посторонних: впустить может хозяин")
		"DOOR_ARCANE":
			bits.append("запечатана «Волшебным замком»")
		"DOOR_BURNING":
			bits.append("горит")
		"DOOR_TOO_SMALL":
			bits.append("герою не пролезть")
		"DOOR_SOLID":
			bits.append(str(d.get("note", "сплошная")))
		"":
			bits.append("открыта")
	return " · ".join(bits)


## The DC to pick the lock (Sleight of Hand) and to force the door (Athletics); an arcane lock adds its own.
static func dcs(s: GameSession, data: Dictionary, a: String, b: String) -> Dictionary:
	var d := def(data, a, b)
	var out := ThingRules.lock_dcs(data, int(data["rules"]["containers"]["lock_dc"].get(str(d.get("lock", "simple")), 10)), d)
	if has_effect(s, a, b, "arcane_lock") and not has_effect(s, a, b, "knocked"):
		out["pick"] = int(out["pick"]) + int(cfg(data)["arcane_plus"])
		out["force"] = int(out["force"]) + int(cfg(data)["arcane_plus"])
	return out


## The ways the hero has with this door now: [{how, spell?, item?}] — key, pick, force, hit (a weapon in hand), the
## hero's spells by their data (`door` of rules.spell_effects, fire by the spell's damage type), a torch, waiting,
## the latch from its own side, a knock at a private door. A solid leaf only breaks.
static func ways(s: GameSession, data: Dictionary, a: String, b: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var d := def(data, a, b)
	if d.is_empty():
		return out
	var c := s.character
	var why := blocked(s, data, a, b)
	var inv: Dictionary = c.get("inventory", {})
	var solid := why == "DOOR_SOLID"
	var locks := why in ["DOOR_LOCKED", "DOOR_CLOSED_HOURS", "DOOR_ARCANE", "DOOR_PRIVATE"]
	var shut := locks or solid
	if why == "DOOR_PRIVATE" and _knock_heard(s, data, a, b):
		out.append({"how": "ask"})
	if why == "DOOR_LOCKED" and str(d.get("latch", "")) == a:
		out.append({"how": "latch"})
	if locks and not str(d.get("key", "")).is_empty() and int(inv.get(str(d["key"]), 0)) > 0 and why != "DOOR_ARCANE":
		out.append({"how": "key"})
	if locks and int(inv.get("thieves_tools", 0)) > 0:
		out.append({"how": "pick"})
	if shut:
		out.append({"how": "force"})
	var broken := bool(s.ways.get(key(a, b), {}).get("broken", false))
	if shut and not str(c.get("equipped", {}).get("main_hand", "")).is_empty():
		out.append({"how": "hit"})
	var burns := ThingRules.burns(s, data, s.ways.get(key(a, b), {}), d)
	for id: Variant in SpellRules.ready(c):
		var sp: Dictionary = data["rules"]["spell_effects"].get(str(id), {})
		var door := str(sp.get("door", ""))
		if (door == "unlock" and locks) or (door == "lock" and not solid and not broken and not has_effect(s, a, b, "arcane_lock")):
			out.append({"how": "spell", "spell": str(id)})
		elif burns and not broken and why != "DOOR_BURNING" and str(data["spells"].get(str(id), {}).get("damage_type", "")) == "fire":
			out.append({"how": "spell", "spell": str(id)})
	if burns and not broken and why != "DOOR_BURNING" and int(inv.get(str(cfg(data)["torch"]), 0)) > 0:
		out.append({"how": "torch"})
	if why == "DOOR_CLOSED_HOURS":
		out.append({"how": "wait"})
	return out


## The owner is by the door and may still be asked to let the hero in.
static func _knock_heard(s: GameSession, data: Dictionary, a: String, b: String) -> bool:
	var owner := SiteRules.unwelcome(s, data, b)
	var w := WorldView.new(data["world"])
	var near: Array[String] = w.site_rooms(w.site_id(b))
	near.append(a)
	return SiteRules.ask_why(s, data, owner).is_empty() and near.any(func(r: String) -> bool: return s.npcs_here(w.world, r).has(owner))


## The door opens by a key or a picked lock: unlocked until its site's next closing, a private one for
## `private_open_minutes` (the owner shuts it again), or for good, a lock of its own.
static func unlock(s: GameSession, data: Dictionary, a: String, b: String) -> void:
	var st := _st(s, a, b)
	st["locked"] = false
	var d := def(data, a, b)
	var h := hours(s, data, str(d.get("site", "")))
	st["unlocked_until"] = int(h["opens"]) if not h.is_empty() else TimeRules.abs_minute(s) + int(cfg(data)["private_open_minutes"]) if d.has("private") else -1


## The owner or the hero locks it again.
static func lock(s: GameSession, a: String, b: String) -> void:
	var st := _st(s, a, b)
	st["locked"] = true
	st["unlocked_until"] = -1


## The door is broken: by force, by blows or burnt through. It stays open for good.
static func break_down(s: GameSession, a: String, b: String) -> void:
	var st := _st(s, a, b)
	st["broken"] = true


## A blow of `damage` at the door: its HP goes down, at 0 it is broken. True when it broke.
static func hurt(s: GameSession, data: Dictionary, a: String, b: String, damage: int) -> bool:
	var d := def(data, a, b)
	if bool(ThingRules.hurt(data, _st(s, a, b), d.merged({"hp": max_hp(data, d)}), damage)["broke"]):
		break_down(s, a, b)
		return true
	return false


## A blow of the weapon in hand at the door: an attack against the material's AC, damage off its HP. Lines.
static func hit(s: GameSession, data: Dictionary, a: String, b: String) -> Array[String]:
	var c := s.character
	var mat := ThingRules.material(data, def(data, a, b))
	var w := CombatRules.weapon_profile(c, data, s.items, str(c.get("equipped", {}).get("main_hand", "")))
	var r := Roll.hero(s, data, {"what": "Удар по двери", "parts": _hit_parts(w), "bonus": w["to_hit"], "dc": int(mat.get("ac", 15))})
	if not bool(r["ok"]):
		return ["%s: удар по двери — %d против КД %d, без толку" % [w["name"], int(r["total"]), int(mat.get("ac", 15))]]
	var dmg := maxi(1, CombatRules.roll_dice(s.rng, str(w["dice"]), int(r["nat"]) == 20) + int(w["bonus"]))
	if hurt(s, data, a, b, dmg):
		return ["%s: %d урона — %s" % [w["name"], dmg, break_line(data, a, b).to_lower()]]
	return ["%s: %d урона — осталось %d из %d" % [w["name"], dmg, hp(s, data, a, b), max_hp(data, def(data, a, b))]]


## What is said when the leaf breaks.
static func break_line(data: Dictionary, a: String, b: String) -> String:
	return str(def(data, a, b).get("broke", "Дверь выбита"))


## An effect on the door with its cause and its end (minutes from now; −1 — until removed).
static func add_effect(s: GameSession, a: String, b: String, kind: String, minutes: int, cause: String) -> void:
	ThingRules.lay(s, _st(s, a, b), kind, minutes, cause)


## A door spell of the hero by its data: Knock opens (and quiets an arcane lock for a while), Arcane Lock seals it
## (the hero passes), fire sets a wooden door burning. Lines.
static func spell(s: GameSession, data: Dictionary, a: String, b: String, spell_id: String) -> Array[String]:
	var name := str(data["spells"][spell_id]["name"])
	var door := str(data["rules"]["spell_effects"].get(spell_id, {}).get("door", ""))
	if door == "unlock":
		if has_effect(s, a, b, "arcane_lock"):
			add_effect(s, a, b, "knocked", int(cfg(data)["knock_minutes"]), name)
		unlock(s, data, a, b)
		return ["«%s»: дверь отпирается с гулким стуком" % name]
	if door == "lock":
		add_effect(s, a, b, "arcane_lock", -1, name)
		_st(s, a, b)["arcane_by_hero"] = true
		return ["«%s»: дверь запечатана — вы проходите, другие нет" % name]
	return ignite(s, data, a, b, name)


static func ignite(s: GameSession, data: Dictionary, a: String, b: String, cause: String) -> Array[String]:
	ThingRules.ignite(s, data, _st(s, a, b), def(data, a, b), cause)
	return ["Дверь загорается (%s): через %d мин прогорит насквозь" % [cause, int(ThingRules.cfg(data)["burn_minutes"])]]


## Whose door it is: who does not want the hero on either side, else the owner of either side (a door broken from inside
## or in open hours is damage all the same, v0.8.4.4). "" — nobody's.
static func victim(s: GameSession, data: Dictionary, a: String, b: String) -> String:
	var w := WorldView.new(data["world"])
	for room: String in [b if s.room_id == a else a, s.room_id]:
		if not SiteRules.unwelcome(s, data, room).is_empty():
			return SiteRules.unwelcome(s, data, room)
	for room: String in [a, b]:
		var owner := str(w.inherit(room, "owner", ""))
		if not owner.is_empty() and owner != OwnerRules.HERO and not Being.dead(s, owner):
			return owner
	return ""


## A door of someone else forced before eyes: who saw it ([] — nobody).
static func witnesses(s: GameSession, data: Dictionary, a: String, b: String) -> Array[String]:
	var w := WorldView.new(data["world"])
	var into := b if s.room_id == a else a
	if victim(s, data, a, b).is_empty() or ConditionRules.invisible(s.character, data):
		return []
	var seen: Array[String] = []
	seen.assign(WatchRules.eyes(s, data, s.npcs_here(w.world, s.room_id)))
	seen.append_array(s.npcs_here(w.world, into))
	return seen


static func _hit_parts(w: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.assign(w.get("hit_parts", []))
	return out


# --- the master's way -------------------------------------------------------------------------------------------


## The master's `way` (protocol 0.100.0): a way from the hero's room to a room of this location that has none: a crawl,
## a breach, a secret door the story found. It may not open what the pack shuts: a room behind a `when` stays behind it.
## {plan, summary} or {reason}.
static func plan_make(s: GameSession, data: Dictionary, e: Dictionary) -> Dictionary:
	var world: Dictionary = data["world"]
	var w := WorldView.new(world)
	var to := str(e.get("to_room", ""))
	var kind := str(e.get("way_kind", ""))
	var kinds: Dictionary = cfg(data)["kinds"]
	if not world["rooms"].has(to) or to == s.room_id:
		return {"reason": "нет такой комнаты: %s" % to}
	if w.location_id(to) != w.location_id(s.room_id):
		return {"reason": "проход ведёт только внутри этой локации: дороги между локациями — create:place на открытом крае"}
	if w.exits(s.room_id).has(to):
		return {"reason": "выход в %s уже есть" % to}
	var full := LayoutRules.no_way(s, data, s.room_id, LayoutRules.is_open(s, data, to))
	if full.is_empty() and not bool(e.get("one_way", false)):
		full = LayoutRules.no_way(s, data, to, LayoutRules.is_open(s, data, s.room_id))
	if not full.is_empty():
		return {"reason": full}
	if not kinds.has(kind) or not bool(kinds[kind].get("master", true)):
		return {"reason": "way_kind — один из: %s" % ", ".join(kinds.keys().filter(func(k: String) -> bool: return bool(kinds[k].get("master", true))))}
	for r: String in world["rooms"]:  # what the pack hides stays hidden
		if (world["rooms"][r].get("ways", {}).get(to, {}) as Dictionary).has("when") and not WayRules.open_exits(s, world, r).has(to):
			return {"reason": "в %s пока не попасть: путь туда открывает мир, не новый проход" % to}
	var gen := WorldGen.generated(s)
	if int(gen.get("way_day", -1)) == s.day and int(gen.get("ways_today", 0)) >= int(cfg(data)["make"]["per_day"]):
		return {"reason": "сегодня новых проходов уже хватит"}
	var row_out := {"kind": kind}
	for k: String in ["material", "lock", "locked", "text"]:
		if e.get(k) != null:
			row_out[k] = e[k]
	if e.has("material") and e["material"] != null and not ThingRules.cfg(data)["materials"].has(str(e["material"])):
		return {"reason": "материал — один из: %s" % ", ".join(ThingRules.cfg(data)["materials"].keys())}
	return {"plan": {"from": s.room_id, "to": to, "row": row_out, "one_way": bool(e.get("one_way", false))},
		"summary": "Новый проход: %s в «%s»" % [str(kinds[kind]["name"]), w.room(to).get("name", to)]}


static func apply_make(s: GameSession, data: Dictionary, plan: Dictionary) -> Array[String]:
	var gen := WorldGen.generated(s)
	gen["ways_today"] = (int(gen.get("ways_today", 0)) if int(gen.get("way_day", -1)) == s.day else 0) + 1
	gen["way_day"] = s.day
	var from := str(plan["from"])
	var to := str(plan["to"])
	var made: Dictionary = gen.get("ways", {})
	var side: Dictionary = made.get(from, {})
	side[to] = plan["row"]
	made[from] = side
	gen["ways"] = made
	var edge: Dictionary = gen.get("edge_exits", {})
	gen["edge_exits"] = edge
	var ends: Array = [[from, to]] if bool(plan["one_way"]) else [[from, to], [to, from]]
	for pair: Array in ends:
		var list: Array = edge.get(pair[0], [])
		list.append(pair[1])
		edge[pair[0]] = list
	WorldGen.lay_ways(data["world"], gen)
	return ["Появился путь: %s" % str(data["world"]["rooms"][to].get("name", to))]
