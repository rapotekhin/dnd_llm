class_name MountRules
extends RefCounted
## Mounts, pack animals and vehicles (roadmap v0.7.42). A beast of the hero (PropertyRules: a creature of the room,
## `tame`, owned by the hero) with `pack` carries a pack — `cr["pack"]` {item_id: qty}, its capacity by 5e: Strength
## × 15 × the size's multiplier (`burden` — a size larger); what lies in it does not weigh on the hero. A vehicle
## (rules.mounts.vehicles) is hitched to a beast that pulls enough (`pull`) and goes with it: `cr["cart"]` {vehicle,
## contents}. Both are containers of the room while the beast stands here: «pack:<id>», «cart:<id>» (ContainerRules).
## Where a beast cannot go (an indoor room without `stable` / `mounts`, `no_mounts`, a terrain of no_mount_terrains;
## a vehicle — also off the roads) it waits at the entrance (`waiting`) and goes on with the hero when he comes back.
## Left alone away from an own place it is not fed and may be stolen with its load (`steal_pct_day`); the stolen ones
## are remembered in c["stolen_animals"] for the master's quest. A dealer (an NPC with `animals`) rents a beast for
## days (`rent_day`, it goes back by itself), buys the hero's own and sells vehicles (its `vehicles`). The master
## puts a beast at a dealer by `stock` with `animal`: an SRD beast whose kind the engine derives (price by size, the
## way by speed, the pack by Strength).

const PACK := "pack:"
const CART := "cart:"


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"]["mounts"]


static func on(data: Dictionary) -> bool:
	return data["rules"].has("mounts") and data["rules"].has("property")


## The pack's capacity in lb of a beast (0 — it carries none).
static func capacity(data: Dictionary, cr: Dictionary) -> float:
	var a := PropertyRules.animal_cfg(data, str(cr.get("monster", "")))
	if not bool(a.get("pack", false)):
		return 0.0
	var m: Dictionary = data["monsters"].get(str(cr["monster"]), {})
	var size := str(m.get("size", "medium"))
	if bool(a.get("burden", false)):
		size = str(cfg(data)["size_up"].get(size, size))
	return float(m.get("abilities", {}).get("str", 10)) * 15.0 * float(cfg(data)["size_mult"].get(size, 1))


static func vehicle(data: Dictionary, id: String) -> Dictionary:
	return cfg(data)["vehicles"].get(id, {})


## The hero's beasts in a room.
static func beasts(s: GameSession, room_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for cr: Dictionary in CreatureRules.here(s, room_id):
		if str(cr.get("state", "")) == PropertyRules.TAME and str(cr.get("owner", "")) == OwnerRules.HERO:
			out.append(cr)
	return out


static func _beast(s: GameSession, cid: String) -> Dictionary:
	for cr: Dictionary in beasts(s, s.room_id):
		if str(cr["id"]) == cid:
			return cr
	return {}


## A pack or a cart of a beast here as a container ({} — none): ContainerRules.target's shape with its capacity.
static func container(s: GameSession, data: Dictionary, id: String) -> Dictionary:
	if not on(data) or not (id.begins_with(PACK) or id.begins_with(CART)):
		return {}
	var cart := id.begins_with(CART)
	var cr := _beast(s, id.substr(5))
	if cr.is_empty():
		return {}
	if cart:
		if not (cr.get("cart") is Dictionary):
			return {}
		var v := vehicle(data, str(cr["cart"]["vehicle"]))
		return {"name": "%s (%s)" % [v.get("name", "Повозка"), cr["name"]], "container": "vehicle", "contents": cr["cart"]["contents"],
			"capacity_lb": float(v.get("capacity_lb", 0)), "owner": ""}
	var cap := capacity(data, cr)
	if cap <= 0:
		return {}
	if not (cr.get("pack") is Dictionary):
		cr["pack"] = {}
	return {"name": "Вьюк: %s" % cr["name"], "container": "pack", "contents": cr["pack"], "capacity_lb": cap, "owner": ""}


## «Мул — вьюк 40 из 420 фнт; телега 120 из 800 фнт» — the loads of a beast.
static func load_text(s: GameSession, data: Dictionary, cr: Dictionary) -> String:
	var bits: Array[String] = []
	if capacity(data, cr) > 0:
		bits.append("вьюк %s из %s фнт" % [_lb(ContainerRules.weight(data, s.items, cr.get("pack", {}))), _lb(capacity(data, cr))])
	if cr.get("cart") is Dictionary:
		var v := vehicle(data, str(cr["cart"]["vehicle"]))
		bits.append("%s %s из %s фнт" % [str(v.get("name", "")).to_lower(), _lb(ContainerRules.weight(data, s.items, cr["cart"]["contents"])), _lb(float(v.get("capacity_lb", 0)))])
	if cr.has("rent_day"):
		bits.append("в аренде до дня %d" % int(cr["rent_day"]))
	return "; ".join(bits)


static func _lb(x: float) -> String:
	return str(snappedf(x, 0.1)).trim_suffix(".0")


# --- where a beast goes ---------------------------------------------------------------------------------------------


## "" or why this beast cannot step into `room_id`.
static func blocked(s: GameSession, data: Dictionary, room_id: String, cr: Dictionary) -> String:
	if not on(data):
		return ""
	var room := SceneRules.room(s, data["world"], room_id)
	var tags: Array = room.get("tags", [])
	var world := WorldView.new(data["world"])
	var terr := str(world.location(world.location_id(room_id)).get("terrain", ""))
	if not bool(PropertyRules.animal_cfg(data, str(cr["monster"])).get("anywhere", false)):
		if tags.has("no_mounts"):
			return "сюда животным хода нет"
		if bool(room.get("indoor", false)) and not tags.has("stable") and not tags.has("mounts"):
			return "под крышу не заведёшь"
		if (cfg(data)["no_mount_terrains"] as Array).has(terr) and not tags.has("mounts"):
			return "в такие ходы не пройдёт"
	if cr.get("cart") is Dictionary and not tags.has("road") and not (cfg(data)["cart_terrains"] as Array).has(terr):
		return "%s не пройдёт — здесь нет дороги" % str(vehicle(data, str(cr["cart"]["vehicle"])).get("name", "повозка")).to_lower()
	return ""


## A step `from` → `to` (before CreatureRules.follow): a led beast that cannot go waits at `from`; the hero's beasts
## waiting at `to` go on with him. Lines.
static func on_move(s: GameSession, data: Dictionary, from: String, to: String) -> Array[String]:
	var lines: Array[String] = []
	if not on(data) or from == to:
		return lines
	for cr: Dictionary in beasts(s, from):
		if not bool(cr.get("led", false)):
			continue
		var why := blocked(s, data, to, cr)
		if not why.is_empty():
			cr["led"] = false
			cr["waiting"] = true
			lines.append("%s — ждёт у входа: %s" % [cr["name"], why])
	for cr: Dictionary in beasts(s, to):
		if bool(cr.get("waiting", false)):
			cr["waiting"] = false
			cr["led"] = true
			lines.append("%s снова с вами" % cr["name"])
	return lines


# --- the day --------------------------------------------------------------------------------------------------------


## A beast left alone away from an own place (not led, not at an own place).
static func unattended(s: GameSession, data: Dictionary, cr: Dictionary) -> bool:
	if bool(cr.get("led", false)):
		return false
	var pid := PropertyRules.at(s, data, PropertyRules.room_of(s, str(cr["id"])))
	return pid.is_empty() or not PropertyRules.owned(s.character, pid)


## Each new day (from PropertyRules' day): a rented beast past its days goes back to its owner; one left alone may be
## stolen with its loads. Lines.
static func day(s: GameSession, data: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	if not on(data):
		return lines
	for cr: Dictionary in PropertyRules.animals(s):
		var room := PropertyRules.room_of(s, str(cr["id"]))
		if cr.has("rent_day") and s.day > int(cr["rent_day"]):
			if bool(cr.get("led", false)) and room == s.room_id:
				_unload(s, data, cr)
			lines.append("%s — срок аренды вышел, животное ушло к хозяину (%s)" % [cr["name"], PropertyRules.npc_name(data, str(cr.get("rent_from", "")))])
			PropertyRules._remove_creature(s, str(cr["id"]))
			continue
		if unattended(s, data, cr) and s.rng.randi_range(1, 100) <= int(cfg(data)["steal_pct_day"]):
			var where := WorldView.new(data["world"]).room_short(room)
			var stolen: Array = s.character.get("stolen_animals", [])
			stolen.append({"name": str(cr["name"]), "monster": str(cr["monster"]), "room": room, "day": s.day,
				"load": ContainerRules.contents_text(data, s.items, _all_load(cr))})
			s.character["stolen_animals"] = stolen
			lines.append("%s больше нет — увели, пока не было присмотра (%s)" % [cr["name"], where])
			PropertyRules._remove_creature(s, str(cr["id"]))
	return lines


static func _all_load(cr: Dictionary) -> Dictionary:
	var out: Dictionary = (cr.get("pack", {}) as Dictionary).duplicate()
	if cr.get("cart") is Dictionary:
		for id: String in cr["cart"]["contents"]:
			out[id] = int(out.get(id, 0)) + int(cr["cart"]["contents"][id])
	return out


## The loads of a beast into the hero's hands (it is going away while he stands by).
static func _unload(s: GameSession, data: Dictionary, cr: Dictionary) -> void:
	var load := _all_load(cr)
	for id: String in load:
		ItemRules.found(s.character, data, s.items, id, int(load[id]))
	cr["pack"] = {}
	if cr.get("cart") is Dictionary:
		cr["cart"]["contents"] = {}
	CharacterRules.refresh(s.character, data, s.items)


## A beast fed by the hero's purse only when it is with him or at an own place (PropertyRules._animals).
static func fed_by_purse(s: GameSession, data: Dictionary, cr: Dictionary) -> bool:
	return not on(data) or not unattended(s, data, cr)


# --- the dealer -----------------------------------------------------------------------------------------------------


static func rent_price(data: Dictionary, monster: String, days: int) -> int:
	return maxi(1, Price.share(int(PropertyRules.animal_cfg(data, monster).get("price_cp", 0)), float(cfg(data)["rent_pct_day"])) * days)


static func rent_why(s: GameSession, data: Dictionary, npc_id: String, monster: String, days: int) -> String:
	var why := PropertyRules.animal_why(s, data, npc_id, monster)
	if not why.is_empty() and why != "PROPERTY_NO_MONEY":
		return why
	var span: Array = cfg(data)["rent_days"]
	if days < int(span[0]) or days > int(span[1]):
		return "MOUNT_RENT_DAYS"
	if int(s.character.get("gold_cp", 0)) < rent_price(data, monster, days):
		return "PROPERTY_NO_MONEY"
	return ""


static func rent(s: GameSession, data: Dictionary, npc_id: String, monster: String, days: int) -> Array[String]:
	var price := rent_price(data, monster, days)
	PropertyRules.buy_animal(s, data, npc_id, monster, price)
	var cr: Dictionary = CreatureRules.here(s, s.room_id).back()
	cr["rent_day"] = s.day + days - 1
	cr["rent_from"] = npc_id
	s.remember(npc_id, "сдал герою в аренду: %s до дня %d" % [cr["name"], int(cr["rent_day"])])
	return ["Взято в аренду: %s на %d дн. за %s — вернётся к хозяину сам после дня %d" % [cr["name"], days, Money.format(price), int(cr["rent_day"])]]


## The hero's beasts here a dealer would buy: own ones (not rented).
static func sellable(s: GameSession, data: Dictionary, npc_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if PropertyRules.animals_of(data, npc_id).is_empty():
		return out
	for cr: Dictionary in beasts(s, s.room_id):
		if not cr.has("rent_day") and not bool(cr.get("pet", false)) and int(PropertyRules.animal_cfg(data, str(cr["monster"])).get("price_cp", 0)) > 0:
			out.append(cr)
	return out


static func sell_price(data: Dictionary, cr: Dictionary) -> int:
	var p := int(PropertyRules.animal_cfg(data, str(cr["monster"])).get("price_cp", 0))
	if cr.get("cart") is Dictionary:
		p += int(vehicle(data, str(cr["cart"]["vehicle"])).get("price_cp", 0))
	return Price.share(p, float(cfg(data)["sell_pct"]))


static func sell_why(s: GameSession, data: Dictionary, npc_id: String, cid: String) -> String:
	var cr := _beast(s, cid)
	if cr.is_empty() or not sellable(s, data, npc_id).has(cr):
		return "MOUNT_NOT_SELLABLE"
	if not PropertyRules._present(s, data, npc_id):
		return "PROPERTY_SELLER_AWAY"
	if not _all_load(cr).is_empty():
		return "MOUNT_LOADED"
	return ""


static func sell(s: GameSession, data: Dictionary, npc_id: String, cid: String) -> Array[String]:
	var cr := _beast(s, cid)
	var price := sell_price(data, cr)
	Ledger.add(s, price, "mount:sell")
	PropertyRules._remove_creature(s, cid)
	s.remember(npc_id, "купил у героя: %s" % cr["name"])
	return ["Продано %s: %s за %s" % [PropertyRules.npc_name(data, npc_id), cr["name"], Money.format(price)]]


static func vehicles_of(data: Dictionary, npc_id: String) -> Array[String]:
	var out: Array[String] = []
	for v: Variant in WorldView.new(data["world"]).npc(npc_id).get("vehicles", []):
		if not vehicle(data, str(v)).is_empty():
			out.append(str(v))
	return out


## The hero's led beast here that would pull `vid` and has none yet ({} — none).
static func puller(s: GameSession, data: Dictionary, vid: String) -> Dictionary:
	for cr: Dictionary in beasts(s, s.room_id):
		if bool(cr.get("led", false)) and not (cr.get("cart") is Dictionary) and int(PropertyRules.animal_cfg(data, str(cr["monster"])).get("pull", 0)) >= int(vehicle(data, vid).get("pull", 1)):
			return cr
	return {}


static func vehicle_why(s: GameSession, data: Dictionary, npc_id: String, vid: String) -> String:
	if not vehicles_of(data, npc_id).has(vid):
		return "MOUNT_NO_VEHICLE"
	if not PropertyRules._present(s, data, npc_id):
		return "PROPERTY_SELLER_AWAY"
	if puller(s, data, vid).is_empty():
		return "MOUNT_NO_PULLER"
	if int(s.character.get("gold_cp", 0)) < int(vehicle(data, vid)["price_cp"]):
		return "PROPERTY_NO_MONEY"
	return ""


static func buy_vehicle(s: GameSession, data: Dictionary, npc_id: String, vid: String) -> Array[String]:
	var v := vehicle(data, vid)
	var cr := puller(s, data, vid)
	Ledger.add(s, -int(v["price_cp"]), "mount:buy_vehicle")
	cr["cart"] = {"vehicle": vid, "contents": {}}
	s.remember(npc_id, "продал герою: %s" % v["name"])
	return ["Куплено: %s за %s — упряжка: %s, везёт до %s фнт" % [v["name"], Money.format(int(v["price_cp"])), cr["name"], _lb(float(v["capacity_lb"]))]]


# --- the master's beast at a dealer ---------------------------------------------------------------------------------


## The kind of an SRD beast the engine derives for a dealer: price and feed by size, the way by speed, a pack and a
## pull by Strength. {} — not a beast for a dealer.
static func derive(data: Dictionary, monster: String) -> Dictionary:
	var m: Dictionary = data["monsters"].get(monster, {})
	var mk: Dictionary = cfg(data)["make"]
	var size := str(m.get("size", ""))
	if str(m.get("type", "")) != "beast" or not (mk["sizes"] as Array).has(size) or float(m.get("cr", 99)) > float(mk["max_cr"]):
		return {}
	var speed := int(m.get("speed", 30))
	var mult := 1.0
	for pair: Array in mk["travel_mult_by_speed"]:
		if speed >= int(pair[0]):
			mult = float(pair[1])
			break
	var st := int(m.get("abilities", {}).get("str", 10))
	var out := {"price_cp": int(mk["price_cp"][size]), "feed_cp_day": int(mk["feed_cp_day"][size]), "travel_mult": mult,
		"pack": st >= 14, "pull": 2 if st >= 18 else 1 if st >= 14 else 0,
		"text": "Путь %s; %s" % ["вдвое короче" if mult <= 0.5 else "на четверть короче" if mult < 1.0 else "не короче", "несёт вьюк" if st >= 14 else "вьюк не несёт"]}
	return out


## The master's `stock` with `animal` (v0.7.42): {plan, summary} or {reason}.
static func plan_stock(s: GameSession, data: Dictionary, spec: Dictionary) -> Dictionary:
	var who := str(spec.get("npc_id", ""))
	var monster := str(spec.get("animal", ""))
	if not s.npcs_here(data["world"], s.room_id).has(who):
		return {"reason": "%s не в сцене — животное ставят тому, кто здесь" % who}
	if PropertyRules.animals_of(data, who).has(monster):
		return {"reason": "%s уже продаёт %s — кнопка «Животные»" % [PropertyRules.npc_name(data, who), data["monsters"].get(monster, {}).get("name", monster)]}
	var known := not PropertyRules.animal_cfg(data, monster).is_empty()
	var kind := {} if known else derive(data, monster)
	if not known and kind.is_empty():
		var mk: Dictionary = cfg(data)["make"]
		return {"reason": "animal — зверь SRD (type beast) размера %s и CR до %s" % [", ".join(mk["sizes"]), mk["max_cr"]]}
	var gen := WorldGen.generated(s)
	if int(gen.get("animal_day", -1)) == s.day and int(gen.get("animal_today", 0)) >= int(cfg(data)["make"]["per_day"]):
		return {"reason": "сегодня уже хватит новых животных — завтра"}
	var name := str(data["monsters"][monster].get("name", monster))
	return {"plan": {"npc_id": who, "animal": monster, "kind": kind}, "summary": "%s продаёт: %s (%s)" % [PropertyRules.npc_name(data, who), name,
		Money.format(int((kind if not known else PropertyRules.animal_cfg(data, monster))["price_cp"]))]}


static func apply_stock(s: GameSession, data: Dictionary, plan: Dictionary) -> Array[String]:
	var gen := WorldGen.generated(s)
	var monster := str(plan["animal"])
	if not (plan["kind"] as Dictionary).is_empty():
		if not gen.has("animal_kinds"):
			gen["animal_kinds"] = {}
		gen["animal_kinds"][monster] = (plan["kind"] as Dictionary).duplicate()
		if not data["world"].has("animal_kinds"):
			data["world"]["animal_kinds"] = {}
		data["world"]["animal_kinds"][monster] = (plan["kind"] as Dictionary).duplicate()
	var who := str(plan["npc_id"])
	var list: Array = (WorldView.new(data["world"]).npc(who).get("animals", []) as Array).duplicate()
	list.append(monster)
	Overlay.put(s, data, EntityRef.npc(who), "animals", list)
	if int(gen.get("animal_day", -1)) != s.day:
		gen["animal_day"] = s.day
		gen["animal_today"] = 0
	gen["animal_today"] = int(gen["animal_today"]) + 1
	return ["%s теперь продаёт: %s" % [PropertyRules.npc_name(data, who), data["monsters"][monster].get("name", monster)]]
