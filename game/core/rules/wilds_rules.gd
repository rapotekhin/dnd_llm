class_name WildsRules
extends RefCounted
## Hunting grounds and fishing waters (roadmap v0.7.41 «Охота и рыбалка: угодья»). A room with a tag of
## rules.wilds.kinds (`game`, `fish`) has a stock of beasts or fish: spent by the catch, grown back by days
## (`regen_per_day` up to `stock`); the stock lives in `generated.wilds` {"room|kind": {stock, day}}. «Охотиться» and
## «Рыбачить» take hours: a Survival check (gear of the kind gives advantage, the needed one — or disadvantage
## without), each `units_per_margin` over the DC one more unit, × the tries of the hours, within the stock. A unit of
## fishing is its `yield`; of hunting — a beast of the location's terrain (rules.wilds.terrain): a small one gives its
## yield at once, a monster its meat and hide by size (CraftRules), a `fight` one comes out to fight. A failure may
## bring a predator of the terrain (`predator_pct`). A ground with an owner (`owner` of the room or its site) is
## poaching without its leave: seen by the people here or by chance (`poach.seen_pct`) — the crime `poaching`.
## The master tags its rooms with `wilds` in create_place and moves a stock by the effect `wilds` with a cause.


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"]["wilds"]


static func kind(data: Dictionary, k: String) -> Dictionary:
	return cfg(data)["kinds"].get(k, {})


static func _room(s: GameSession, data: Dictionary, room_id: String = "") -> Dictionary:
	return SceneRules.room(s, data["world"], s.room_id if room_id.is_empty() else room_id)


## The grounds of the room: its tags among the kinds.
static func here(s: GameSession, data: Dictionary, room_id: String = "") -> Array[String]:
	var out: Array[String] = []
	if not data["rules"].has("wilds"):
		return out
	for t: Variant in _room(s, data, room_id).get("tags", []):
		if cfg(data)["kinds"].has(str(t)):
			out.append(str(t))
	return out


static func _state(s: GameSession) -> Dictionary:
	var gen := WorldGen.generated(s)
	if not gen.has("wilds"):
		gen["wilds"] = {}
	return gen["wilds"]


## The stock of the ground now, grown back by the days since it was last touched.
static func stock(s: GameSession, data: Dictionary, k: String, room_id: String = "") -> int:
	var rid := s.room_id if room_id.is_empty() else room_id
	var d := kind(data, k)
	var rec: Dictionary = _state(s).get("%s|%s" % [rid, k], {})
	if rec.is_empty():
		return int(d["stock"])
	return mini(int(d["stock"]), int(rec["stock"]) + (s.day - int(rec["day"])) * int(d["regen_per_day"]))


static func _put_stock(s: GameSession, k: String, rid: String, n: int) -> void:
	_state(s)["%s|%s" % [rid, k]] = {"stock": maxi(0, n), "day": s.day}


## The room's grounds for the master's scene: «Охота: запас 4 из 6; угодья Ивана — без позволения браконьерство».
static func lines(s: GameSession, data: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for k: String in here(s, data):
		var d := kind(data, k)
		var line := "%s (кнопка «%s»): запас %d из %d" % [d["name"], d["act"], stock(s, data, k), int(d["stock"])]
		if poaching(s, data):
			line += "; угодья %s — без позволения браконьерство" % BondRules.npc_name(s, data, owner(s, data))
		out.append(line)
	return out


## Who owns the ground: the room's `wilds_owner`, else its site's owner (not the hero) — "" for a free one.
static func owner(s: GameSession, data: Dictionary) -> String:
	var o := str(_room(s, data).get("wilds_owner", ""))
	if o.is_empty():
		var world := WorldView.new(data["world"])
		var sid := world.site_id(s.room_id)
		if not sid.is_empty():
			o = str(world.site(sid).get("owner", ""))
	return "" if o == "hero" else o


## A ground the hero would poach: owned, and the owner has not let the hero in (its site or this room).
static func poaching(s: GameSession, data: Dictionary) -> bool:
	var o := owner(s, data)
	if o.is_empty():
		return false
	var sid := WorldView.new(data["world"]).site_id(s.room_id)
	if not sid.is_empty() and SiteRules.permitted(s, data, sid):
		return false
	return str(s.permits.get(s.room_id, "")) != o or s.attitude(o) < int(SiteRules.cfg(data)["permit"]["min_attitude"])


## The rooms of `npc_id`'s grounds the hero has no leave to hunt in yet (`permit` gives it, as to a private site).
static func closed_grounds(s: GameSession, data: Dictionary, npc_id: String) -> Array[String]:
	var out: Array[String] = []
	if not data["rules"].has("wilds"):
		return out
	for rid: String in data["world"]["rooms"]:
		var room: Dictionary = data["world"]["rooms"][rid]
		if str(room.get("wilds_owner", "")) == npc_id and str(s.permits.get(rid, "")) != npc_id:
			out.append(rid)
	return out


## "" or why the hero cannot go at this ground now.
static func why_not(s: GameSession, data: Dictionary, k: String) -> String:
	var unfree := EncounterRules.unfree_why(s)
	if not unfree.is_empty():
		return TranslationServer.translate(unfree)
	if not here(s, data).has(k):
		return "здесь нет угодий"
	if CombatRules.active(s):
		return "в бою не до того"
	if stock(s, data, k) <= 0:
		return "%s: всё выбито — дайте месту отдохнуть" % kind(data, k)["name"]
	return ""


static func _has(s: GameSession, ids: Array) -> String:
	for id: Variant in ids:
		if int(s.character.get("inventory", {}).get(str(id), 0)) > 0:
			return str(id)
	return ""


## The gear of the kind: {adv: the item's name or "", dis: "" or why}.
static func gear(s: GameSession, data: Dictionary, k: String) -> Dictionary:
	var d := kind(data, k)
	var out := {"adv": "", "dis": ""}
	var a := _has(s, d.get("gear_adv", []))
	if not a.is_empty():
		out["adv"] = ItemRules.display_name(data["items"], s.items, a)
	var need: Array = d.get("gear_needed", [])
	if not need.is_empty() and _has(s, need).is_empty():
		out["dis"] = "без снастей"
	return out


static func _terrain(s: GameSession, data: Dictionary) -> Dictionary:
	var world := WorldView.new(data["world"])
	var terr := str(world.location(world.location_id(s.room_id)).get("terrain", ""))
	return cfg(data)["terrain"].get(terr, cfg(data)["terrain"]["_default"])


## One beast of the location's terrain by weight.
static func _beast(s: GameSession, data: Dictionary) -> Dictionary:
	var list: Array = _terrain(s, data)["game"]
	var total := 0
	for b: Dictionary in list:
		total += int(b.get("weight", 1))
	var roll := s.rng.randi_range(1, maxi(1, total))
	for b: Dictionary in list:
		roll -= int(b.get("weight", 1))
		if roll <= 0:
			return b
	return list[0]


static func _predator(s: GameSession, data: Dictionary) -> String:
	var list: Array = _terrain(s, data).get("predators", [])
	return "" if list.is_empty() else str(list[s.rng.randi_range(0, list.size() - 1)])


static func _give(s: GameSession, data: Dictionary, got: Dictionary, item: String, qty: int) -> void:
	if qty <= 0 or not data["items"]["catalog"].has(item):
		return
	var inv: Dictionary = s.character["inventory"]
	inv[item] = int(inv.get(item, 0)) + qty
	got[item] = int(got.get(item, 0)) + qty


## The foe of a fight out of the hunt.
static func _foe(data: Dictionary, monster: String, desc: String) -> Dictionary:
	return {"monster": monster, "name": str(data["monsters"].get(monster, {}).get("name", monster)), "desc": desc, "col": 2}


## A hunt or a fishing of `hours` (the caller passes the time): the Survival check rolled here, the catch by its margin
## and the tries of the hours within the stock. {lines, fight: [foes], crime: bool}.
static func go(s: GameSession, data: Dictionary, k: String, hours: int) -> Dictionary:
	var d := kind(data, k)
	var c := cfg(data)
	var skill := str(d["skill"])
	var g := gear(s, data, k)
	var pet := PetRules.helper(s, data, skill)  # v0.7.43: a dog on the trail
	if str(g["adv"]).is_empty() and not pet.is_empty():
		g["adv"] = pet
	var adv := not str(g["adv"]).is_empty()
	var dc := int(d["dc"])
	var r := Roll.hero(s, data, {"what": str(d["name"]), "skill": skill, "dc": dc, "adv": adv, "dis": not str(g["dis"]).is_empty()})
	var nat := int(r["nat"])
	var b := int(r["bonus"])
	var ok := bool(r["ok"])
	var out := {"lines": [] as Array[String], "fight": [], "crime": false}
	var lines: Array[String] = out["lines"]
	var how: Array[String] = []
	if adv:
		how.append(str(g["adv"]))
	if not str(g["dis"]).is_empty():
		how.append(str(g["dis"]))
	lines.append("%s, %d ч: %s %d + %d = %d против Сл %d%s — %s" % [d["name"], hours, CraftRules.tr_skill(data, skill), nat, b, nat + b, dc,
		" (%s)" % ", ".join(how) if not how.is_empty() else "", "успех" if ok else "провал"])
	var left := stock(s, data, k)
	if ok:
		var per := clampi(1 + (nat + b - dc) / int(c["units_per_margin"]), 1, int(c["max_per_try"]))
		var tries := maxi(1, hours / int(d["hours_per_try"]))
		var pct := WeatherRules.wilds_pct(s, data, k)  # rain brings the fish, snow shows the tracks (v0.7.46)
		var units := mini(left, maxi(0 if pct <= 0 else 1, per * tries * pct / 100))
		if pct != 100:
			lines.append("Погода: %s — улов %s" % [WeatherRules.kind_name(data, WeatherRules.here(s, data)), "лучше" if pct > 100 else "хуже"])
		var got := {}
		var spent := 0
		for i in units:
			spent += 1
			if not d.has("yield"):
				var beast := _beast(s, data)
				if bool(beast.get("fight", false)):
					out["fight"] = [_foe(data, str(beast["monster"]), "добыча, что дала отпор")]
					lines.append("Выслежен крупный зверь: %s — и он не бежит, а бросается навстречу" % _foe(data, str(beast["monster"]), "")["name"])
					break
				if beast.has("monster"):
					var m: Dictionary = data["monsters"].get(str(beast["monster"]), {})
					_give(s, data, got, "raw_meat", CraftRules.meat(data, m))
					_give(s, data, got, "raw_hide", CraftRules.hides(data, m))
				for item: String in beast.get("yield", {}):
					_give(s, data, got, item, int(beast["yield"][item]))
			else:
				for item: String in d["yield"]:
					_give(s, data, got, item, int(d["yield"][item]))
		_put_stock(s, k, s.room_id, left - spent)
		var got_parts: Array[String] = []
		for item: String in got:
			got_parts.append("%s ×%d" % [ItemRules.display_name(data["items"], s.items, item), int(got[item])])
		if not got_parts.is_empty():
			lines.append("Добыто: %s" % ", ".join(got_parts))
		CharacterRules.refresh(s.character, data, s.items)
		if k == "hunt" and FactionRules.friendly(s, data, str(FactionRules.cfg(data)["by_type"]["beast"])):  # v0.7.50: a friend of the beasts hunts them
			lines.append_array(FactionRules.on_source(s, data, str(FactionRules.cfg(data)["by_type"]["beast"]), "hunt", "охота"))
	else:
		lines.append("%s: ни следа удачи" % d["name"])
		if nat == 1 or s.rng.randi_range(1, 100) <= int(d.get("predator_pct", 0)):
			var p := _predator(s, data)
			if not p.is_empty():
				out["fight"] = [_foe(data, p, "хищник вышел на запах охотника")]
				lines.append("Из чащи выходит хищник: %s" % _foe(data, p, "")["name"])
	if poaching(s, data):
		var o := owner(s, data)
		var npcs := s.npcs_here(data["world"], s.room_id).filter(func(n: String) -> bool: return not s.followers.has(n))
		if not npcs.is_empty() or s.rng.randi_range(1, 100) <= int(c["poach"]["seen_pct"]):
			out["crime"] = true
			lines.append("Браконьерство в угодьях %s замечено" % BondRules.npc_name(s, data, o))
			lines.append_array(CrimeRules.on_job(s, data, str(c["poach"]["crime"]), o, s.room_id, WorldView.new(data["world"]).location_id(s.room_id)))
	return out


# --- the master's `wilds` ------------------------------------------------------------------------------------------


## The plan of `wilds` {ground: game | fish, op: deplete | restore | add, cause, room_id?}: {plan, summary} or {reason}.
static func plan(s: GameSession, data: Dictionary, e: Dictionary) -> Dictionary:
	var k := str(e.get("ground", "")) if e.get("ground") != null else ""
	if kind(data, k).is_empty():
		return {"reason": "ground — одно из %s" % ", ".join(cfg(data)["kinds"].keys())}
	var rid := str(e.get("room_id", "")) if e.get("room_id") != null else ""
	if rid.is_empty() or rid == "here":
		rid = s.room_id
	if SceneRules.room(s, data["world"], rid).is_empty():
		return {"reason": "нет комнаты %s" % rid}
	var cause := str(e.get("cause", "")).strip_edges() if e.get("cause") != null else ""
	if cause.length() < 8:
		return {"reason": "угодья меняются только по причине в мире — cause"}
	var op := str(e.get("op", "")) if e.get("op") != null else ""
	if not op in ["deplete", "restore", "add"]:
		return {"reason": "op — deplete (зверь ушёл, рыба ушла), restore (вернулся) или add (новые угодья в комнате)"}
	if op != "add" and not here(s, data, rid).has(k):
		return {"reason": "в %s нет угодий %s — op add" % [SceneRules.room(s, data["world"], rid).get("name", rid), k]}
	if op == "add" and bool(SceneRules.room(s, data["world"], rid).get("indoor", false)):
		return {"reason": "угодья — не под крышей"}
	var name := str(kind(data, k)["name"])
	return {"plan": {"ground": k, "room_id": rid, "op": op, "cause": cause.left(160)},
		"summary": "%s: %s (%s)" % [name, {"deplete": "опустели", "restore": "снова полны", "add": "появились"}[op], cause.left(80)]}


static func apply(s: GameSession, data: Dictionary, p: Dictionary) -> Array[String]:
	var k := str(p["ground"])
	var rid := str(p["room_id"])
	match str(p["op"]):
		"deplete":
			_put_stock(s, k, rid, 0)
		"restore":
			_put_stock(s, k, rid, int(kind(data, k)["stock"]))
		"add":
			PropertyRules._add_tag(s, data, rid, k)
			_put_stock(s, k, rid, int(kind(data, k)["stock"]))
	return ["%s — %s" % [kind(data, k)["name"], p["cause"]]]
