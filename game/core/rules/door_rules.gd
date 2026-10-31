class_name DoorRules
extends RefCounted
## Doors (roadmap v0.7.22.25, the author's request) — a concept of the engine, not a list. A way between two rooms may
## have a door: one the pack names (a room's `doors` {to: {material, lock, key, locked}}) or the way into a site with
## hours (its entrance, a door by default). Its state lives in s.doors {"a|b": {...}}: unlocked until, locked by the
## hero or the master, broken, its HP and effects with a cause and a time (burning, an arcane lock, knocked open). A
## door outside its site's hours is locked. Its body, material and statuses are ThingRules' (v0.7.65). It opens by a key, thieves' tools (Sleight of Hand), force (Athletics — it
## breaks), blows of a weapon (its AC and HP), Knock; Arcane Lock locks it harder; fire burns a wooden one through.
## Forcing, hacking or burning a way into a closed or private site before eyes is a trespass at once.


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"]["doors"]


static func key(a: String, b: String) -> String:
	return "%s|%s" % ([a, b] if a < b else [b, a])


## The door between `a` and `b` by the pack: its own, or the entrance of a site with hours; {} — no door.
static func def(data: Dictionary, a: String, b: String) -> Dictionary:
	var rooms: Dictionary = data["world"]["rooms"]
	var own: Variant = rooms.get(a, {}).get("doors", {}).get(b, rooms.get(b, {}).get("doors", {}).get(a))
	var d: Dictionary = (cfg(data)["default"] as Dictionary).duplicate()
	var w := WorldView.new(data["world"])
	for sid: String in [w.site_id(b), w.site_id(a)]:
		if w.site_id(a) != w.site_id(b) and w.site(sid).has("hours"):
			d["site"] = sid
			break
	if own is Dictionary:
		d.merge(own, true)
		return d
	return d if d.has("site") else {}


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
	if not s.doors.has(k):
		s.doors[k] = {}
	return s.doors[k]


static func max_hp(data: Dictionary, d: Dictionary) -> int:
	return int(ThingRules.material(data, d).get("door_hp", 18))


static func hp(s: GameSession, data: Dictionary, a: String, b: String) -> int:
	return maxi(0, max_hp(data, def(data, a, b)) - int(s.doors.get(key(a, b), {}).get("dmg", 0)))


static func has_effect(s: GameSession, a: String, b: String, kind: String) -> bool:
	return ThingRules.has(s, s.doors.get(key(a, b), {}), kind)


## "" — the hero passes from `a` to `b`; else why not (a localization key): DOOR_BURNING, DOOR_ARCANE, DOOR_LOCKED,
## DOOR_CLOSED_HOURS (only from outside the site).
static func blocked(s: GameSession, data: Dictionary, a: String, b: String) -> String:
	var d := def(data, a, b)
	if d.is_empty():
		return ""
	var st: Dictionary = s.doors.get(key(a, b), {})
	if bool(st.get("broken", false)):
		return "DOOR_BURNING" if has_effect(s, a, b, "burning") else ""
	if has_effect(s, a, b, "burning"):
		return "DOOR_BURNING"
	if has_effect(s, a, b, "arcane_lock") and not has_effect(s, a, b, "knocked") and not bool(st.get("arcane_by_hero", false)):
		return "DOOR_ARCANE"
	var now := TimeRules.abs_minute(s)
	if int(st.get("unlocked_until", -1)) > now:
		return ""
	if bool(st.get("locked", bool(d.get("locked", false)))):
		return "DOOR_LOCKED"
	var h := hours(s, data, str(d.get("site", "")))
	var w := WorldView.new(data["world"])
	if not h.is_empty() and not bool(h["open"]) and w.site_id(a) != str(d["site"]):  # from inside the latch opens
		return "DOOR_CLOSED_HOURS"
	return ""


## The word on the exit button: «· заперто до 08:00», «· горит», «· выбита», «· дверь».
static func label(s: GameSession, data: Dictionary, a: String, b: String) -> String:
	var d := def(data, a, b)
	if d.is_empty():
		return ""
	var why := blocked(s, data, a, b)
	if why == "DOOR_CLOSED_HOURS":
		return TranslationServer.translate("DOOR_LABEL_HOURS").format({"time": "%02d:00" % int(hours(s, data, str(d["site"]))["from"])})
	if not why.is_empty():
		return TranslationServer.translate("DOOR_LABEL_" + why.trim_prefix("DOOR_"))
	if bool(s.doors.get(key(a, b), {}).get("broken", false)):
		return TranslationServer.translate("DOOR_LABEL_BROKEN")
	return ""


## For the master: «дверь (дерево) заперта до 08:00 — часы объекта» and the effects on it.
static func describe(s: GameSession, data: Dictionary, a: String, b: String) -> String:
	var d := def(data, a, b)
	if d.is_empty():
		return ""
	var bits: Array[String] = ["дверь (%s)" % str(ThingRules.material(data, d).get("name", d.get("material", "")))]
	var why := blocked(s, data, a, b)
	if bool(s.doors.get(key(a, b), {}).get("broken", false)):
		bits.append("выбита")
	match why:
		"DOOR_CLOSED_HOURS":
			bits.append("заперта до %02d:00 — часы объекта" % int(hours(s, data, str(d["site"]))["from"]))
		"DOOR_LOCKED":
			bits.append("заперта")
		"DOOR_ARCANE":
			bits.append("запечатана «Волшебным замком»")
		"DOOR_BURNING":
			bits.append("горит")
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
## hero's spells by their data (`door` of rules.spell_effects, fire by the spell's damage type), a torch, waiting.
static func ways(s: GameSession, data: Dictionary, a: String, b: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var d := def(data, a, b)
	if d.is_empty():
		return out
	var c := s.character
	var why := blocked(s, data, a, b)
	var inv: Dictionary = c.get("inventory", {})
	var shut := why in ["DOOR_LOCKED", "DOOR_CLOSED_HOURS", "DOOR_ARCANE"]
	if shut and not str(d.get("key", "")).is_empty() and int(inv.get(str(d["key"]), 0)) > 0 and why != "DOOR_ARCANE":
		out.append({"how": "key"})
	if shut and int(inv.get("thieves_tools", 0)) > 0:
		out.append({"how": "pick"})
	if shut:
		out.append({"how": "force"})
	var broken := bool(s.doors.get(key(a, b), {}).get("broken", false))
	if shut and not str(c.get("equipped", {}).get("main_hand", "")).is_empty():
		out.append({"how": "hit"})
	var burns := ThingRules.burns(s, data, s.doors.get(key(a, b), {}), d)
	for id: Variant in SpellRules.ready(c):
		var sp: Dictionary = data["rules"]["spell_effects"].get(str(id), {})
		var door := str(sp.get("door", ""))
		if (door == "unlock" and shut) or (door == "lock" and not broken and not has_effect(s, a, b, "arcane_lock")):
			out.append({"how": "spell", "spell": str(id)})
		elif burns and not broken and why != "DOOR_BURNING" and str(data["spells"].get(str(id), {}).get("damage_type", "")) == "fire":
			out.append({"how": "spell", "spell": str(id)})
	if burns and not broken and why != "DOOR_BURNING" and int(inv.get(str(cfg(data)["torch"]), 0)) > 0:
		out.append({"how": "torch"})
	if why == "DOOR_CLOSED_HOURS":
		out.append({"how": "wait"})
	return out


## The door opens by a key or a picked lock: unlocked until its site's next closing (or for good, a lock of its own).
static func unlock(s: GameSession, data: Dictionary, a: String, b: String) -> void:
	var st := _st(s, a, b)
	st["locked"] = false
	var h := hours(s, data, str(def(data, a, b).get("site", "")))
	st["unlocked_until"] = int(h["opens"]) if not h.is_empty() else -1


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
		return ["%s: %d урона — дверь разбита" % [w["name"], dmg]]
	return ["%s: %d урона — двери осталось %d из %d" % [w["name"], dmg, hp(s, data, a, b), max_hp(data, def(data, a, b))]]


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


## A way into a closed or private site of someone else, forced before eyes: who saw it ([] — nobody).
static func witnesses(s: GameSession, data: Dictionary, a: String, b: String) -> Array[String]:
	var w := WorldView.new(data["world"])
	var into := b if s.room_id == a else a
	if SiteRules.unwelcome(s, data, into).is_empty() or ConditionRules.invisible(s.character, data):
		return []
	var seen: Array[String] = s.npcs_here(w.world, s.room_id)
	seen.append_array(s.npcs_here(w.world, into))
	return seen


static func _hit_parts(w: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.assign(w.get("hit_parts", []))
	return out
