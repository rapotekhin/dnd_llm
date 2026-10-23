class_name WorldGen
extends RefCounted
## People and places the master creates (roadmap v0.7.20, ADR-0008 «Новые NPC и места»; pillar 6): not invented in
## words but made by the engine from the pack's own schema, after a search, with its checks. What is made lives in the
## save of this game only (s.generated) — another game of the same world does not see it until the author moves it into
## the pack (tools/promote_world.py). The game merges it into its own copy of the pack's world (`merged`), so every rule
## that reads data["world"] treats a made NPC as one of the pack.
##
## s.generated = {"npcs": {id: def}, "npc_rooms": {id: room_id}, "rooms": {id: def}, "locations": {id: def},
## "edge_exits": {pack room: [made room]}, "edges_used": ["room:edge"]}. Places (v0.7.20.1) grow only from the open
## edges the pack marked (`open_edges` of a room).


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"]["world_gen"]


## The pack's world with what this game made, a deep copy (the pack itself is never touched).
static func merged(pack_world: Dictionary, gen: Dictionary) -> Dictionary:
	var w := _merge_places(pack_world.duplicate(true), gen)  # places first: made people may live in made rooms
	for id: String in gen.get("quests", {}):  # v0.7.21: quests the master made
		if not w.has("quests"):
			w["quests"] = {}
		w["quests"][id] = (gen["quests"][id] as Dictionary).duplicate(true)
	for id: String in gen.get("npcs", {}):
		w["npcs"][id] = (gen["npcs"][id] as Dictionary).duplicate(true)
		var room := str(gen.get("npc_rooms", {}).get(id, ""))
		if w["rooms"].has(room):
			var list: Array = w["rooms"][room].get("npcs", [])
			if not list.has(id):
				list.append(id)
			w["rooms"][room]["npcs"] = list
	return w


static func generated(s: GameSession) -> Dictionary:
	if s.generated.is_empty():
		s.generated = {"npcs": {}, "npc_rooms": {}}
	return s.generated


# --- people -----------------------------------------------------------------------------------------------------


## NPCs of the world (the pack and made) by a query in the name, the role or the location: [{npc_id, name, role, room,
## location, source}].
static func find_npcs(s: GameSession, data: Dictionary, query: String) -> Array[Dictionary]:
	var world := WorldView.new(data["world"])
	var words := query.to_lower().replace("ё", "е").split(" ", false)
	var out: Array[Dictionary] = []
	for id: String in data["world"]["npcs"]:
		var n: Dictionary = data["world"]["npcs"][id]
		var room := ReputationRules.home_room(data, id)
		var loc := world.location_id(room)
		var hay := ("%s %s %s %s" % [n.get("name", ""), n.get("role", ""), world.location(loc).get("name", loc), world.room(room).get("name", "")]).to_lower().replace("ё", "е")
		if not words.is_empty() and not Array(words).any(func(w: String) -> bool: return w.length() >= 3 and hay.contains(w.left(5))):
			continue
		out.append({"npc_id": id, "name": str(n.get("name", id)), "role": str(n.get("role", "")), "room": room,
			"location": str(world.location(loc).get("name", loc)), "source": "made" if generated(s)["npcs"].has(id) else "pack",
			"dead": s.dead_npcs.has(id)})
	return out


## Checks a `create_npc`: {plan, summary} or {reason}. `spec` — the schema of a pack NPC (NewNpc of the protocol).
static func plan_npc(s: GameSession, data: Dictionary, spec: Dictionary, searched: bool) -> Dictionary:
	var c := cfg(data)
	if not searched:
		return {"reason": "сначала find_npcs: может, такой человек уже есть в мире"}
	var world := WorldView.new(data["world"])
	var name := str(spec.get("name", "")).strip_edges()
	if name.length() < 2:
		return {"reason": "у человека нужно имя"}
	for id: String in data["world"]["npcs"]:
		if str(data["world"]["npcs"][id].get("name", "")).to_lower() == name.to_lower():
			return {"reason": "%s уже есть в мире [%s] — возьми его" % [name, id]}
	var role := str(spec.get("role", "")).strip_edges()
	if role.is_empty():
		return {"reason": "нужна роль: кто он (кузнец, стражник у ворот, путник)"}
	var room := str(spec.get("room_id", "")) if spec.get("room_id") != null and not str(spec.get("room_id", "")).is_empty() else s.room_id
	if not data["world"]["rooms"].has(room):
		return {"reason": "нет комнаты %s" % room}
	var loc := world.location_id(room)
	if loc != world.location_id(s.room_id):
		return {"reason": "новый человек — в этой локации (%s), а не в другой" % world.location(world.location_id(s.room_id)).get("name", "")}
	var made: Dictionary = generated(s)["npcs"]
	if made.size() >= int(c["max_per_session"]):
		return {"reason": "в этой игре создано уже %d человек — больше нельзя" % made.size()}
	var here := made.keys().filter(func(id: String) -> bool: return world.location_id(str(generated(s)["npc_rooms"].get(id, ""))) == loc)
	if here.size() >= int(c["max_per_location"]):
		return {"reason": "в %s уже %d новых людей — больше нельзя" % [world.location(loc).get("name", loc), here.size()]}
	var tpl := str(spec.get("monster", "commoner")) if spec.get("monster") != null else "commoner"
	if not (c["npc_templates"] as Array).has(tpl):
		return {"reason": "шаблон %s не из людских: %s" % [tpl, ", ".join(c["npc_templates"])]}
	if float(data["monsters"].get(tpl, {}).get("cr", 0)) > float(c["max_cr"]):
		return {"reason": "шаблон %s слишком силён для нового человека" % tpl}
	var race := str(spec.get("race", "")) if spec.get("race") != null else ""
	var races: Dictionary = data["races"]["races"]
	if not race.is_empty() and not races.has(race):
		return {"reason": "раса — id из SRD: %s" % ", ".join(races.keys())}
	var def := {"name": name.left(60), "role": role.left(60), "race": str(races.get(race, {}).get("name", "")) if not race.is_empty() else "",
		"gender": str(spec.get("gender", "other")) if spec.get("gender") != null else "other",
		"description": str(spec.get("description", "")).left(300), "personality": str(spec.get("personality", "")).left(300),
		"monster": tpl, "tags": [], "generated": true}
	if not race.is_empty():
		def["race_id"] = race
	var body := BodyRules.check(data, spec)  # v0.7.22.5: age, build, height
	if body.has("reason"):
		return {"reason": str(body["reason"])}
	def.merge(body)
	var links: Array = []
	for l: Variant in spec.get("links", []):
		if not (l is Dictionary):
			continue
		var other := str(l.get("npc_id", ""))
		var kind := str(l.get("kind", ""))
		if not data["world"]["npcs"].has(other) or not (c["link_kinds"] as Array).has(kind):
			return {"reason": "связь: npc_id из мира и kind из %s" % ", ".join(c["link_kinds"])}
		links.append({"npc_id": other, "kind": kind})
	def["links"] = links
	if bool(spec.get("trader", false)):
		var stock := {}
		for id: Variant in spec.get("stock", []):
			var item: Dictionary = data["items"]["catalog"].get(str(id), {})
			if item.is_empty():
				return {"reason": "товар %s — не из каталога (find_items)" % id}
			if int(item.get("value_cp", 0)) > int(c["stock_item_cap_cp"]):
				return {"reason": "%s слишком дорог для лавки нового торговца" % item.get("name", id)}
			stock[str(id)] = int(data["rules"]["trade"]["default_stock_qty"])
		if stock.is_empty():
			return {"reason": "у торговца нужен товар (stock — id каталога)"}
		def["trader"] = true
		def["stock"] = stock
		def["purse_cp"] = int(c["purse_cp"])
	return {"plan": {"npc": def, "room": room}, "summary": "Новый человек: %s — %s" % [def["name"], def["role"]]}


## Makes the NPC: in the save and in this game's world. Its id.
static func apply_npc(s: GameSession, data: Dictionary, plan: Dictionary) -> String:
	var gen := generated(s)
	var n := 1
	while data["world"]["npcs"].has("gen_npc_%d" % n):
		n += 1
	var id := "gen_npc_%d" % n
	gen["npcs"][id] = (plan["npc"] as Dictionary).duplicate(true)
	gen["npc_rooms"][id] = str(plan["room"])
	data["world"] = merged_into(data["world"], id, plan["npc"], str(plan["room"]))
	ReputationRules.refresh(s, data)
	return id


## The world with one more NPC (in place).
static func merged_into(world: Dictionary, id: String, def: Dictionary, room: String) -> Dictionary:
	world["npcs"][id] = def.duplicate(true)
	var list: Array = world["rooms"][room].get("npcs", [])
	list.append(id)
	world["rooms"][room]["npcs"] = list
	return world


# --- places (v0.7.20.1) -------------------------------------------------------------------------------------------


## The open edges of a room: where the pack lets the master draw the world on ([{text, terrain: [..], new_location,
## index}]); one used already is gone.
static func open_edges(s: GameSession, data: Dictionary, room_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var edges: Array = data["world"]["rooms"].get(room_id, {}).get("open_edges", [])
	for i in edges.size():
		if not (generated(s).get("edges_used", []) as Array).has("%s:%d" % [room_id, i]):
			var e: Dictionary = (edges[i] as Dictionary).duplicate()
			e["index"] = i
			out.append(e)
	return out


## Places of the world by a query (rooms and locations): [{room_id, name, location, source}].
static func find_places(s: GameSession, data: Dictionary, query: String) -> Array[Dictionary]:
	var world := WorldView.new(data["world"])
	var words := query.to_lower().replace("ё", "е").split(" ", false)
	var out: Array[Dictionary] = []
	for rid: String in data["world"]["rooms"]:
		var loc := world.location_id(rid)
		var hay := ("%s %s" % [world.room(rid).get("name", ""), world.location(loc).get("name", "")]).to_lower().replace("ё", "е")
		if not words.is_empty() and not Array(words).any(func(w: String) -> bool: return w.length() >= 3 and hay.contains(w.left(5))):
			continue
		out.append({"room_id": rid, "name": str(world.room(rid).get("name", rid)), "location": str(world.location(loc).get("name", loc)),
			"source": "made" if generated(s).get("rooms", {}).has(rid) else "pack"})
	return out


## Checks a `create_place`: one room or a small place (rules.world_gen.max_rooms) on an open edge of this room, by the
## pack's schema of a room. {plan, summary} or {reason}.
static func plan_place(s: GameSession, data: Dictionary, spec: Dictionary, searched: bool) -> Dictionary:
	var c := cfg(data)
	if not searched:
		return {"reason": "сначала find_places: может, такое место уже есть"}
	var world := WorldView.new(data["world"])
	var edges := open_edges(s, data, s.room_id)
	if edges.is_empty():
		return {"reason": "отсюда пакет не позволяет дорисовывать мир (нет открытых краёв); места — только по выходам сцены"}
	var idx := int(spec.get("edge", 0)) if spec.get("edge") != null else 0
	var edge: Dictionary = {}
	for e: Dictionary in edges:
		if int(e["index"]) == idx:
			edge = e
	if edge.is_empty():
		return {"reason": "края %d здесь нет; есть: %s" % [idx, ", ".join(edges.map(func(e: Dictionary) -> String: return "%d — %s" % [e["index"], e["text"]]))]}
	var made: Dictionary = generated(s).get("rooms", {})
	var rooms: Array = spec.get("rooms", [])
	if rooms.is_empty() or rooms.size() > int(c["max_rooms"]):
		return {"reason": "место — от 1 до %d комнат" % int(c["max_rooms"])}
	if made.size() + rooms.size() > int(c["max_rooms_per_session"]):
		return {"reason": "в этой игре создано уже %d комнат — больше нельзя" % made.size()}
	var new_loc := bool(spec.get("new_location", false))
	if new_loc and not bool(edge.get("new_location", false)):
		return {"reason": "с этого края — только продолжение %s, не новая локация" % world.location(world.location_id(s.room_id)).get("name", "")}
	var terrain := str(spec.get("terrain", "")) if spec.get("terrain") != null else ""
	if new_loc and not (edge.get("terrain", []) as Array).has(terrain):
		return {"reason": "местность новой локации — из %s (связность мира пакета)" % ", ".join(edge.get("terrain", []))}
	var names: Array = []
	for rid: String in data["world"]["rooms"]:
		names.append(str(data["world"]["rooms"][rid].get("name", "")).to_lower())
	var keys: Array = rooms.map(func(r: Variant) -> String: return str((r as Dictionary).get("key", "")) if r is Dictionary else "")
	var cap := int(CombatRules.cfg(data)["xp_budget_hard"].get(str(int(s.character.get("level", 1))), 750))
	var defs: Array = []
	for r: Variant in rooms:
		if not (r is Dictionary):
			return {"reason": "комната — объект схемы"}
		var key := str(r.get("key", ""))
		var name := str(r.get("name", "")).strip_edges()
		if key.is_empty() or keys.count(key) > 1:
			return {"reason": "у каждой комнаты свой key"}
		if name.length() < 2 or names.has(name.to_lower()):
			return {"reason": "комната «%s»: нужно новое имя, не как у мест мира" % name}
		for x: Variant in r.get("exits", []):
			if not keys.has(str(x)):
				return {"reason": "выходы комнаты %s — только к комнатам этого места (key); к миру ведёт только первая" % key}
		var secrets: Array = []
		for sec: Variant in r.get("secrets", []):
			var tier := str(sec.get("dc_tier", "medium"))
			if not (data["rules"]["dc_tiers"] as Dictionary).has(tier) or str(sec.get("text", "")).length() < 5:
				return {"reason": "тайна: text и dc_tier из %s" % ", ".join((data["rules"]["dc_tiers"] as Dictionary).keys())}
			secrets.append({"id": "s%d" % (secrets.size() + 1), "dc": int(data["rules"]["dc_tiers"][tier]), "text": str(sec["text"]).left(240),
				"skill": "investigation" if str(sec.get("skill", "")) == "investigation" else "perception"})
		var enc := {}
		if r.get("encounter") is Dictionary and not (r["encounter"].get("enemies", []) as Array).is_empty():
			var xp := 0
			var enemies: Array = []
			for f: Variant in r["encounter"]["enemies"]:
				var mid := str(f.get("monster", ""))
				if not data["monsters"].has(mid):
					return {"reason": "нет такого монстра SRD: %s" % mid}
				var n := clampi(int(f.get("count", 1)), 1, 6)
				xp += int(data["monsters"][mid]["xp"]) * n
				enemies.append({"monster": mid, "count": n, "name": str(f.get("name", data["monsters"][mid]["name"])), "desc": str(f.get("desc", "")).left(200), "col": 3})
			if xp > cap:
				return {"reason": "встреча в %s не по силам %d уровню: %d опыта врагов при пределе %d" % [name, int(s.character.get("level", 1)), xp, cap]}
			enc = {"enemies": enemies, "loot": {"coins_cp": 0, "items": {}}}
		defs.append({"key": key, "name": name.left(60), "description": str(r.get("description", "")).left(600),
			"indoor": bool(r.get("indoor", false)), "dark": bool(r.get("dark", false)),
			"hooks": (r.get("hooks", []) as Array).slice(0, 4).map(func(h: Variant) -> String: return str(h).left(160)),
			"exits": (r.get("exits", []) as Array).map(func(x: Variant) -> String: return str(x)), "secrets": secrets, "encounter": enc})
	# every room is reachable from the entry (the first one)
	var seen: Array = [keys[0]]
	var frontier: Array = [keys[0]]
	while not frontier.is_empty():
		var k: String = frontier.pop_back()
		for d: Dictionary in defs:
			if d["key"] != k and not (d["exits"] as Array).has(k):
				continue
			for x: Variant in [d["key"]] + d["exits"]:
				if not seen.has(x):
					seen.append(x)
					frontier.append(x)
	if seen.size() < keys.size():
		return {"reason": "все комнаты места должны быть связаны выходами с первой"}
	var place := {"from": s.room_id, "edge": idx, "rooms": defs, "new_location": new_loc, "location": {}}
	if new_loc:
		place["location"] = {"name": str(spec.get("name", "")).strip_edges().left(60), "description": str(spec.get("description", "")).left(400), "terrain": terrain}
		if str(place["location"]["name"]).length() < 2:
			return {"reason": "у новой локации нужно имя"}
	return {"plan": {"place": place}, "summary": "Новое место: %s" % ", ".join(defs.map(func(d: Dictionary) -> String: return d["name"]))}


## Makes the place: in the save and in this game's world. The id of its first room.
static func apply_place(s: GameSession, data: Dictionary, plan: Dictionary) -> String:
	var gen := generated(s)
	for k: String in ["rooms", "locations", "edge_exits"]:
		if not gen.has(k):
			gen[k] = {}
	if not gen.has("edges_used"):
		gen["edges_used"] = []
	var place: Dictionary = plan["place"]
	var world := WorldView.new(data["world"])
	var loc := world.location_id(str(place["from"]))
	if bool(place["new_location"]):
		var n := 1
		while data["world"]["locations"].has("gen_loc_%d" % n):
			n += 1
		loc = "gen_loc_%d" % n
		gen["locations"][loc] = place["location"]
	var ids := {}
	var next := 1
	for d: Dictionary in place["rooms"]:
		while data["world"]["rooms"].has("gen_room_%d" % next):
			next += 1
		ids[d["key"]] = "gen_room_%d" % next
		next += 1
	var first := ""
	for d: Dictionary in place["rooms"]:
		var id: String = ids[d["key"]]
		var exits: Array = (d["exits"] as Array).map(func(k: String) -> String: return ids[k])
		for other: Dictionary in place["rooms"]:  # exits both ways inside the place
			if (other["exits"] as Array).has(d["key"]) and not exits.has(ids[other["key"]]):
				exits.append(ids[other["key"]])
		if first.is_empty():
			first = id
			exits.append(str(place["from"]))
		var room := {"name": d["name"], "location_id": loc, "description": d["description"], "exits": exits, "npcs": [],
			"hooks": d["hooks"], "secrets": d["secrets"], "generated": true}
		if bool(d["indoor"]):
			room["indoor"] = true
		if bool(d["dark"]):
			room["dark"] = true
		if not (d["encounter"] as Dictionary).is_empty():
			room["encounter"] = (d["encounter"] as Dictionary).duplicate(true)
			room["encounter"]["id"] = id + "_enc"
		gen["rooms"][id] = room
	var edge_exits: Array = gen["edge_exits"].get(str(place["from"]), [])
	edge_exits.append(first)
	gen["edge_exits"][str(place["from"])] = edge_exits
	(gen["edges_used"] as Array).append("%s:%d" % [place["from"], int(place["edge"])])
	data["world"] = _merge_places(data["world"], gen)
	return first


static func _merge_places(w: Dictionary, gen: Dictionary) -> Dictionary:
	for loc: String in gen.get("locations", {}):
		w["locations"][loc] = (gen["locations"][loc] as Dictionary).duplicate(true)
	for rid: String in gen.get("rooms", {}):
		w["rooms"][rid] = (gen["rooms"][rid] as Dictionary).duplicate(true)
	for from: String in gen.get("edge_exits", {}):
		if not w["rooms"].has(from):
			continue
		var exits: Array = w["rooms"][from].get("exits", [])
		for to: Variant in gen["edge_exits"][from]:
			if not exits.has(str(to)):
				exits.append(str(to))
		w["rooms"][from]["exits"] = exits
	for rid: String in gen.get("room_secrets", {}):  # v0.7.21: the hiding places of quest things
		if not w["rooms"].has(rid):
			continue
		var secrets: Array = (w["rooms"][rid].get("secrets", []) as Array).duplicate(true)
		for sec: Dictionary in gen["room_secrets"][rid]:
			if not secrets.any(func(x: Dictionary) -> bool: return str(x.get("id", "")) == str(sec["id"])):
				secrets.append(sec.duplicate(true))
		w["rooms"][rid]["secrets"] = secrets
	return w
