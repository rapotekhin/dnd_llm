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
## v0.7.22.24 (location → site → room): a made place is one site of its rooms (s.generated "sites"), named by the
## master or by its first room; `inside` grows a site within a location of reach without an open edge — the bathhouse
## the innkeeper spoke of — entered from the room it is built at; v0.7.22.26.2: the world is endless — no limit of rooms or sites.


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"]["world_gen"]


## The pack's world with what this game made, a deep copy (the pack itself is never touched).
static func merged(pack_world: Dictionary, gen: Dictionary) -> Dictionary:
	var w := _merge_places(pack_world.duplicate(true), gen)  # places first: made people may live in made rooms
	for sid: String in gen.get("site_patch", {}):  # v0.7.27: what the hero owns and changed
		if w.get("sites", {}).has(sid):
			w["sites"][sid].merge(gen["site_patch"][sid], true)
	for rid: String in gen.get("room_patch", {}):
		if w["rooms"].has(rid):
			w["rooms"][rid].merge(gen["room_patch"][rid], true)
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
## `new_rooms` — {key: location id} of the place made in this turn: `room_id` «new:<key>» puts the person there.
## `any_loc` (v0.7.39.6) — a person of a quest's act may live in any known place, not only in the hero's location.
static func plan_npc(s: GameSession, data: Dictionary, spec: Dictionary, searched: bool, new_rooms: Dictionary = {}, any_loc: bool = false) -> Dictionary:
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
	if not data["world"]["rooms"].has(room) and new_rooms.has(room):
		room = "new:" + room  # the bare key of this turn's new room
	var fresh := room.begins_with("new:")
	if fresh and not new_rooms.has(room.trim_prefix("new:")):
		return {"reason": "нет комнаты %s: «new:<key>» — комната места, созданного в этом ходе (%s)" % [room,
			", ".join(new_rooms.keys().map(func(k: String) -> String: return "new:" + k)) if not new_rooms.is_empty() else "его нет — сначала create_place"]}
	if not fresh and not data["world"]["rooms"].has(room):
		return {"reason": "нет комнаты %s; новое место этого хода — «new:<key>» его комнаты" % room}
	var loc := str(new_rooms[room.trim_prefix("new:")]) if fresh else world.location_id(room)
	if not fresh and not any_loc and loc != world.location_id(s.room_id):
		return {"reason": "новый человек — в этой локации (%s), а не в другой" % world.location(world.location_id(s.room_id)).get("name", "")}
	var made: Dictionary = generated(s)["npcs"]
	var here := made.keys().filter(func(id: String) -> bool: return world.location_id(str(generated(s)["npc_rooms"].get(id, ""))) == loc)
	if here.size() >= int(world.location(loc).get("people_cap", c["max_per_location"])):
		return {"reason": "в %s уже %d новых людей — больше нельзя" % [world.location(loc).get("name", loc), here.size()]}
	var tpl := str(spec.get("monster", "commoner")) if spec.get("monster") != null else "commoner"
	if not (c["npc_templates"] as Array).has(tpl):
		return {"reason": "шаблон %s не из людских: %s" % [tpl, ", ".join(c["npc_templates"])]}
	if float(data["monsters"].get(tpl, {}).get("cr", 0)) > float(c["max_cr"]) and not (c.get("max_cr_except", []) as Array).has(tpl):  # a mage teaches, not fights
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
	# v0.7.22.5: age, build, height — fixed now, so the summary tells the master what the engine picked
	def.merge(BodyRules.make(data, str(def["gender"]), BodyRules.check(data, spec), "npc:" + name))
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
	var teaches: Variant = spec.get("teaches")
	if teaches is Dictionary and not (teaches as Dictionary).is_empty():  # v0.7.39.7: what it teaches beside its trade
		var t := {}
		for k: String in ["tools", "skills"]:
			var known: Dictionary = CraftRules.cfg(data)["tools"] if k == "tools" else data["rules"]["skills"]
			var ids: Array = []
			for x: Variant in teaches.get(k, []) if teaches.get(k) is Array else []:
				if not known.has(str(x)):
					return {"reason": "teaches.%s — из %s" % [k, ", ".join(known.keys())]}
				ids.append(str(x))
			if not ids.is_empty():
				t[k] = ids
		if str(teaches.get("languages", "")) == "own":
			t["languages"] = "own"
		if teaches.get("spells") != null:
			return {"reason": "teaches: заклинаниям учит шаблон (monster: mage — волшебник до 5 круга, archmage — выше, priest — жрец до 3, druid), не поле"}
		if not t.is_empty():
			def["teaches"] = t
	var made_items := {}
	var notes: Array[String] = []
	if bool(spec.get("trader", false)):
		# v0.7.22.26: the goods come from the shop kind; the master's own are extras, a bad one is skipped, not refused
		var kind := TradeRules.kind_of(data["rules"], {"trade_kind": spec.get("trade_kind"), "role": role})
		if kind.is_empty():
			return {"reason": "вид лавки trade_kind — один из: %s" % TradeRules.kind_list(data["rules"])}
		var k: Dictionary = TradeRules.kinds(data["rules"])[kind]
		var stock := TradeRules.pack_stock({"stock": k["stock"]}, data["rules"])
		notes.append("лавка «%s»: %d товаров своих и каждый день новые" % [k.get("name", kind), stock.size()])
		var goods: Array = []
		for id: Variant in spec.get("stock", []) if spec.get("stock") is Array else []:
			var item: Dictionary = ItemRules.def_of(data["items"], s.items, str(id))
			if item.is_empty():
				notes.append("не взят товар %s — его нет в каталоге" % id)
				continue
			goods.append([str(id), item])
		for g: Variant in spec.get("stock_new", []) if spec.get("stock_new") is Array else []:
			if not (g is Dictionary):
				continue
			var chk := ItemRules.check_generated(data["items"], g, int(s.character.get("level", 1)), data.get("spells", {}))
			if not bool(chk["ok"]):
				notes.append("не взят новый товар «%s»: %s" % [g.get("name", ""), chk["reason"]])
				continue
			goods.append([ItemRules.generated_id(chk["def"]), chk["def"], true])
		for g: Array in goods:
			if stock.has(g[0]):
				continue
			if int(g[1].get("value_cp", 0)) > int(c["stock_item_cap_cp"]):
				notes.append("не взят %s — слишком дорог для новой лавки" % g[1].get("name", g[0]))
				continue
			if g.size() > 2:
				made_items[g[0]] = g[1]
			stock[g[0]] = int(data["rules"]["trade"]["default_stock_qty"])
		def["trader"] = true
		def["trade_kind"] = kind
		def["stock"] = stock
		def["purse_cp"] = int(k.get("purse_cp", c["purse_cp"]))
	return {"plan": {"npc": def, "room": room, "items": made_items}, "summary": "Новый человек: %s — %s (%s)%s" % [def["name"], def["role"],
		BodyRules.text(data, def, str(def["gender"])), ("" if made_items.is_empty() else "; новый товар: " + ", ".join(made_items.values().map(func(d: Dictionary) -> String: return str(d["name"]))))
		+ ("" if notes.is_empty() else "; " + "; ".join(notes))]}


## Makes the NPC: in the save and in this game's world. Its id.
static func apply_npc(s: GameSession, data: Dictionary, plan: Dictionary) -> String:
	var gen := generated(s)
	var n := 1
	while data["world"]["npcs"].has("gen_npc_%d" % n):
		n += 1
	var id := "gen_npc_%d" % n
	for iid: String in plan.get("items", {}):
		s.items[iid] = (plan["items"][iid] as Dictionary).duplicate(true)
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


## The open edges of a room: where the pack — or the master on a place it made (v0.7.39.4) — lets the world grow on
## ([{text, terrain: [..], new_location, index}]). An edge is not used up (roads fork); "edges_used" of older saves
## counts only while rules.world_gen.edges_once.
static func open_edges(s: GameSession, data: Dictionary, room_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var edges: Array = data["world"]["rooms"].get(room_id, {}).get("open_edges", [])
	var once := bool(cfg(data).get("edges_once", false))
	for i in edges.size():
		if not once or not (generated(s).get("edges_used", []) as Array).has("%s:%d" % [room_id, i]):
			var e: Dictionary = (edges[i] as Dictionary).duplicate()
			e["index"] = i
			out.append(e)
	return out


## The locations where the master may grow a place (rules.world_gen.edge_reach): the hero's, the ones one exit away
## and the ones the hero has been to — the author: a bakery «outside the town» asked of the innkeeper is built at the
## North Gate, not only where the hero stands.
static func reach_locations(s: GameSession, data: Dictionary) -> Array[String]:
	var world := WorldView.new(data["world"])
	var reach: Dictionary = cfg(data).get("edge_reach", {})
	var here := world.location_id(s.room_id)
	var out: Array[String] = [here]
	var rooms: Dictionary = data["world"]["rooms"]
	if bool(reach.get("neighbours", true)):
		for rid: String in rooms:
			if world.location_id(rid) != here:
				continue
			for x: Variant in rooms[rid].get("exits", []):
				var loc := world.location_id(str(x))
				if not loc.is_empty() and not out.has(loc):
					out.append(loc)
	if bool(reach.get("visited", true)):
		for rid: String in s.visited:
			var loc := world.location_id(rid)
			if not loc.is_empty() and not out.has(loc):
				out.append(loc)
	return out


## The open edges the master may build on now: [{room_id, room, location, edge, text, terrain, new_location}], the
## hero's room first, then its location, then the rest.
static func reach_edges(s: GameSession, data: Dictionary) -> Array[Dictionary]:
	var world := WorldView.new(data["world"])
	var locs := reach_locations(s, data)
	var rooms: Array = data["world"]["rooms"].keys().filter(func(rid: String) -> bool: return locs.has(world.location_id(rid)))
	rooms.sort_custom(func(a: String, b: String) -> bool:
		return (a == s.room_id and b != s.room_id) or (a != s.room_id and b != s.room_id and locs.find(world.location_id(a)) < locs.find(world.location_id(b))))
	var out: Array[Dictionary] = []
	for rid: String in rooms:
		for e: Dictionary in open_edges(s, data, rid):
			out.append({"room_id": rid, "room": str(world.room(rid).get("name", rid)), "location": str(world.location(world.location_id(rid)).get("name", "")),
				"edge": int(e["index"]), "text": str(e.get("text", "")), "terrain": e.get("terrain", []), "new_location": bool(e.get("new_location", false))})
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
	var at := str(spec.get("room_id", "")) if spec.get("room_id") != null and not str(spec.get("room_id", "")).is_empty() else s.room_id
	var inside := bool(spec.get("inside", false)) if spec.get("inside") != null else false
	var reach: Array = reach_edges(s, data).map(func(e: Dictionary) -> String: return str(e["room_id"]))
	if inside:
		var loc_at := world.location_id(at)
		if not world.room(at).has("location_id") or not reach_locations(s, data).has(loc_at):
			return {"reason": "объект внутри локации строят у комнаты, куда герой может дойти: его локация, соседние, где он бывал"}
		if bool(spec.get("new_location", false)):
			return {"reason": "объект внутри локации — не новая локация"}
	elif not reach.has(at):
		var known := reach_edges(s, data).map(func(e: Dictionary) -> String: return "%s [%s] край %d" % [e["room"], e["room_id"], int(e["edge"])])
		return {"reason": ("у %s нет открытых краёв в досягаемости" % world.room(at).get("name", at)) +
			("; края известного мира: %s — create_place с их room_id и edge" % "; ".join(known) if not known.is_empty() else "; места — только по выходам сцены")}
	var edges := open_edges(s, data, at)
	var idx := -1 if inside else (int(spec.get("edge", 0)) if spec.get("edge") != null else 0)
	var edge: Dictionary = {"new_location": false, "terrain": []} if inside else {}
	for e: Dictionary in edges:
		if int(e["index"]) == idx:
			edge = e
	if edge.is_empty():
		return {"reason": "края %d здесь нет; есть: %s" % [idx, ", ".join(edges.map(func(e: Dictionary) -> String: return "%d — %s" % [e["index"], e["text"]]))]}
	var rooms: Array = spec.get("rooms", [])
	if rooms.is_empty() or rooms.size() > int(c["max_rooms"]):
		return {"reason": "место — от 1 до %d комнат" % int(c["max_rooms"])}
	var new_loc := bool(spec.get("new_location", false))
	if new_loc and not bool(edge.get("new_location", false)):
		return {"reason": "с этого края — только продолжение %s, не новая локация" % world.location(world.location_id(at)).get("name", "")}
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
		var room_edges: Array = []
		for ed: Variant in r.get("open_edges", []) if r.get("open_edges") is Array else []:
			if not (ed is Dictionary) or str(ed.get("text", "")).strip_edges().length() < 3:
				return {"reason": "край комнаты %s: text — куда ведёт" % key}
			var terr: Array = (ed.get("terrain", []) as Array).map(func(t: Variant) -> String: return str(t))
			if terr.is_empty() or terr.any(func(t: String) -> bool: return not (c["terrains"] as Array).has(t)):
				return {"reason": "край комнаты %s: terrain — из %s" % [key, ", ".join(c["terrains"])]}
			room_edges.append({"text": str(ed["text"]).strip_edges().left(160), "terrain": terr,
				"new_location": bool(ed.get("new_location", true)) if ed.get("new_location") != null else true})
		if room_edges.size() > 2:
			return {"reason": "у комнаты %s — не больше 2 краёв" % key}
		defs.append({"key": key, "name": name.left(60), "description": str(r.get("description", "")).left(600),
			"site": str(r.get("site", "")) if r.get("site") != null else "", "open_edges": room_edges,
			"indoor": bool(r.get("indoor", false)), "dark": bool(r.get("dark", false)),
			"public": bool(r.get("public", true)) if r.get("public") != null else true,
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
	# v0.7.39.4: the place's people, made with it («new:<key>»)
	var new_rooms := {}
	for k: Variant in keys:
		new_rooms[str(k)] = "" if new_loc else world.location_id(at)
	var people: Array = []
	var npc_keys: Array = []
	var specs: Array = spec.get("npcs", []) if spec.get("npcs") is Array else []
	if specs.size() > int(c["place_npcs_max"]):
		return {"reason": "людей места — не больше %d за ход" % int(c["place_npcs_max"])}
	for n: Variant in specs:
		if not (n is Dictionary):
			return {"reason": "человек места — объект схемы create_npc с key"}
		var nk := str(n.get("key", ""))
		if nk.is_empty() or npc_keys.has(nk) or keys.has(nk):
			return {"reason": "у каждого человека места свой key, не как у комнат"}
		npc_keys.append(nk)
		var spec_n := (n as Dictionary).duplicate(true)
		var room_n := str(spec_n.get("room_id", "")) if spec_n.get("room_id") != null else ""
		if not room_n.begins_with("new:"):
			room_n = "new:" + (room_n if keys.has(room_n) else str(keys[0]))
		spec_n["room_id"] = room_n
		var nname := str(spec_n.get("name", "")).strip_edges().to_lower()
		if people.any(func(p: Dictionary) -> bool: return str(p["plan"]["npc"]["name"]).to_lower() == nname):
			return {"reason": "два человека места с одним именем: %s" % spec_n.get("name", "")}
		var p := plan_npc(s, data, spec_n, true, new_rooms)
		if p.has("reason"):
			return {"reason": "человек места %s: %s" % [nk, p["reason"]]}
		people.append({"key": nk, "plan": p["plan"], "room": room_n.trim_prefix("new:")})
	# the sites: the place's `site` and the keyed `sites` its rooms name
	var site_spec: Dictionary = spec.get("site", {}) if spec.get("site") is Dictionary else {}
	var sites := {}
	var main := _site_of(data, site_spec, npc_keys)
	if main.has("reason"):
		return main
	for st: Variant in spec.get("sites", []) if spec.get("sites") is Array else []:
		if not (st is Dictionary) or str(st.get("key", "")).is_empty() or sites.has(str(st["key"])):
			return {"reason": "у каждого объекта из sites свой key — его называют комнаты в site"}
		var made := _site_of(data, st, npc_keys)
		if made.has("reason"):
			return made
		sites[str(st["key"])] = made
	for d: Dictionary in defs:
		if not str(d["site"]).is_empty() and not sites.has(str(d["site"])):
			return {"reason": "комната %s: объекта %s нет в sites (%s)" % [d["key"], d["site"], ", ".join(sites.keys())]}
	var kind := str(spec.get("settlement", "")) if spec.get("settlement") != null else ""
	var law := bool(spec.get("law", false)) if spec.get("law") != null else false
	if not kind.is_empty():
		var why := _settlement_why(c, kind, defs, sites, main, people, new_loc)
		if not why.is_empty():
			return {"reason": why}
		law = law or bool(c["settlements"][kind].get("law", false))
	if law and not new_loc:
		return {"reason": "law — у новой локации: в этой уже свой закон или его нет по пакету"}
	var place := {"from": at, "edge": idx, "rooms": defs, "new_location": new_loc, "location": {}, "site": main, "sites": sites, "inside": inside,
		"npcs": people, "law": law, "settlement": kind}
	if new_loc:
		place["location"] = {"name": str(spec.get("name", "")).strip_edges().left(60), "description": str(spec.get("description", "")).left(400), "terrain": terrain}
		if str(place["location"]["name"]).length() < 2:
			return {"reason": "у новой локации нужно имя"}
	var extra := ""
	if not people.is_empty():
		extra += "; люди: " + ", ".join(people.map(func(p: Dictionary) -> String: return "%s — %s [new:%s]" % [p["plan"]["npc"]["name"], p["plan"]["npc"]["role"], p["key"]]))
	if not kind.is_empty():
		extra += "; %s%s" % [c["settlements"][kind]["name"], ", со стражей" if law else ""]
	return {"plan": {"place": place}, "summary": "Новое место: %s%s%s" % [", ".join(defs.map(func(d: Dictionary) -> String: return "%s [new:%s]" % [d["name"], d["key"]])),
		"" if at == s.room_id else " — у %s" % world.room(at).get("name", at), extra]}


## A site of a spec (NewSite): {name, description, tags, public, owner?} | {reason}. The owner — an NPC of the world,
## «new» (create_npc of this turn) or «new:<key>» of the place's people.
static func _site_of(data: Dictionary, st: Dictionary, npc_keys: Array) -> Dictionary:
	var site := {"name": str(st.get("name", "")).strip_edges().left(60), "description": str(st.get("description", "")).left(400),
		"tags": (st.get("tags", []) as Array).slice(0, 4).map(func(x: Variant) -> String: return str(x).left(24)),
		"public": bool(st.get("public", true)) if st.get("public") != null else true}
	var owner := str(st.get("owner_id", "")) if st.get("owner_id") != null else ""
	if not owner.is_empty():
		if owner.begins_with("new:"):
			if not npc_keys.has(owner.trim_prefix("new:")):
				return {"reason": "хозяин объекта %s — нет такого человека в npcs места" % owner}
		elif owner != "new" and not data["world"]["npcs"].has(owner):
			return {"reason": "хозяин объекта %s — не человек мира: id из find_npcs, «new:<key>» человека места или «new» — create_npc этого хода" % owner}
		site["owner"] = owner  # "new" / "new:<key>": linked on apply
	return _object_of(data, st, npc_keys, site)


## v0.7.39.5 — the object of a site (ObjectRules): its kind, owner's role, staff, upgrades and hours, checked
## against rules.property; people as the owner — a world NPC, «new» or «new:<key>».
static func _object_of(data: Dictionary, st: Dictionary, npc_keys: Array, site: Dictionary) -> Dictionary:
	if not data["rules"].has("property"):
		return site
	var pc: Dictionary = data["rules"]["property"]
	var who_ok := func(ref: String) -> bool:
		return (ref.begins_with("new:") and npc_keys.has(ref.trim_prefix("new:"))) or ref == "new" or data["world"]["npcs"].has(ref)
	var k := str(st.get("kind", "")) if st.get("kind") != null else ""
	if not k.is_empty():
		if not pc["kinds"].has(k):
			return {"reason": "kind объекта — из %s" % ", ".join(pc["kinds"].keys())}
		site["kind"] = k
	if st.get("owner_role") != null and not str(st["owner_role"]).strip_edges().is_empty():
		site["owner_role"] = str(st["owner_role"]).strip_edges().left(40)
	var staff: Array = []
	for h: Variant in st.get("staff", []) if st.get("staff") is Array else []:
		var ref := str((h as Dictionary).get("npc_id", ""))
		if not who_ok.call(ref):
			return {"reason": "штат объекта: %s — не человек мира и не «new:<key>» человека места" % ref}
		var role := str((h as Dictionary).get("role", "")).strip_edges().left(40)
		if role.is_empty():
			return {"reason": "у человека штата %s нужна role" % ref}
		staff.append({"npc": ref, "role": role})
	if not staff.is_empty():
		site["staff"] = staff
	var ups: Array = []
	for u: Variant in st.get("upgrades", []) if st.get("upgrades") is Array else []:
		if not pc["upgrades"].has(str(u)):
			return {"reason": "улучшение %s — из %s" % [u, ", ".join(pc["upgrades"].keys())]}
		ups.append(str(u))
	if not ups.is_empty():
		site["upgrades"] = ups
	var h: Variant = st.get("hours")
	if h is Dictionary:
		var a := int((h as Dictionary).get("opens", -1))
		var b := int((h as Dictionary).get("closes", -1))
		if a < 0 or a > 23 or b < 1 or b > 24 or a == b:
			return {"reason": "hours объекта — {opens, closes}, часы от 0 до 24"}
		site["hours"] = {"from": a, "to": b}
	return site


## What a settlement of this kind lacks (rules.world_gen.settlements), "" — nothing.
static func _settlement_why(c: Dictionary, kind: String, defs: Array, sites: Dictionary, main: Dictionary, people: Array, new_loc: bool) -> String:
	if not c["settlements"].has(kind):
		return "settlement — из %s" % ", ".join(c["settlements"].keys())
	var k: Dictionary = c["settlements"][kind]
	if not new_loc:
		return "%s — новая локация (new_location на крае, что это позволяет)" % k["name"]
	if defs.size() < int(k["rooms"][0]) or defs.size() > int(k["rooms"][1]):
		return "%s — от %d до %d комнат" % [k["name"], int(k["rooms"][0]), int(k["rooms"][1])]
	var tags: Array = (main.get("tags", []) as Array).duplicate()
	for sk: String in sites:
		tags.append_array(sites[sk].get("tags", []))
	var lacks: Array[String] = []
	for group: Variant in k["needs"]:
		if not (group as Array).any(func(t: Variant) -> bool: return tags.has(str(t))):
			lacks.append(" или ".join(group))
	if not lacks.is_empty():
		return "в %s всегда есть: %s — объект с таким тегом в sites" % [k["name"], "; ".join(lacks)]
	if people.size() < int(k["people"]):
		return "в %s нужны люди — не меньше %d в npcs (хозяева, торговцы, староста)" % [k["name"], int(k["people"])]
	return ""


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
		if not bool(d.get("public", true)):
			room["public"] = false
		if not (d["encounter"] as Dictionary).is_empty():
			room["encounter"] = (d["encounter"] as Dictionary).duplicate(true)
			room["encounter"]["id"] = id + "_enc"
		if not (d.get("open_edges", []) as Array).is_empty():
			room["open_edges"] = (d["open_edges"] as Array).duplicate(true)
		gen["rooms"][id] = room
	if not gen.has("sites"):
		gen["sites"] = {}
	# the place's own site holds the rooms that name no other; the keyed ones — theirs (v0.7.39.4)
	var site_ids := {}
	var keyed: Dictionary = place.get("sites", {})
	var sid := ""
	for key: Variant in [""] + keyed.keys():
		var members: Array = (place["rooms"] as Array).filter(func(d: Dictionary) -> bool: return str(d.get("site", "")) == str(key))
		if members.is_empty():
			continue
		var sn := 1
		while data["world"].get("sites", {}).has("gen_site_%d" % sn) or gen["sites"].has("gen_site_%d" % sn):
			sn += 1
		var this_id := "gen_site_%d" % sn
		var site: Dictionary = ((place.get("site", {}) if str(key).is_empty() else keyed[key]) as Dictionary).duplicate(true)
		var entry: String = ids[members[0]["key"]]
		if str(site.get("name", "")).is_empty():
			site["name"] = str(gen["rooms"][entry]["name"])
		site["location_id"] = loc
		site["entry"] = entry
		if bool(place.get("inside", false)):
			site["inside"] = true
		gen["sites"][this_id] = site
		site_ids[str(key)] = this_id
		for d: Dictionary in members:
			gen["rooms"][ids[d["key"]]]["site_id"] = this_id
		if gen["rooms"][first].get("site_id", "") == this_id:
			sid = this_id
	var edge_exits: Array = gen["edge_exits"].get(str(place["from"]), [])
	edge_exits.append(first)
	gen["edge_exits"][str(place["from"])] = edge_exits
	if bool(place["new_location"]) and (bool(place.get("law", false)) or not (place.get("npcs", []) as Array).is_empty()):
		gen["locations"][loc]["people_cap"] = int(cfg(data)["people_cap"])
	if bool(place["new_location"]) and (not str(place.get("settlement", "")).is_empty() or bool(place.get("law", false))):
		gen["locations"][loc]["settlement"] = true  # people live here: reputation, the outskirts of a settlement
		if not str(place.get("settlement", "")).is_empty():
			gen["locations"][loc]["settlement_kind"] = str(place["settlement"])
	data["world"] = _merge_places(data["world"], gen)
	# the place's people, then the owners and the guard that name them
	var npc_ids := {}
	for n: Dictionary in place.get("npcs", []):
		npc_ids[str(n["key"])] = apply_npc(s, data, {"npc": n["plan"]["npc"], "room": str(ids.get(str(n["room"]), first)), "items": n["plan"].get("items", {})})
	for key: String in site_ids:
		var gs: Dictionary = gen["sites"][site_ids[key]]
		var owner := str(gs.get("owner", ""))
		if owner.begins_with("new:"):
			gs["owner"] = str(npc_ids.get(owner.trim_prefix("new:"), ""))
		for h: Dictionary in gs.get("staff", []):  # v0.7.39.5: the object's people
			if str(h["npc"]).begins_with("new:"):
				h["npc"] = str(npc_ids.get(str(h["npc"]).trim_prefix("new:"), ""))
		data["world"]["sites"][site_ids[key]] = gs.duplicate(true)
	if bool(place.get("law", false)) and bool(place["new_location"]):
		var law: Dictionary = (cfg(data)["guard"] as Dictionary).duplicate(true)
		law["name"] = "стража: %s" % place["location"]["name"]
		law["guards"] = npc_ids.values().filter(func(id: String) -> bool: return str(data["world"]["npcs"].get(id, {}).get("monster", "")) == "guard")
		law["prison"] = ""
		gen["locations"][loc]["law"] = law
		data["world"]["locations"][loc]["law"] = law.duplicate(true)
	plan["ids"] = ids  # key -> room id, for the refs «new:<key>» of the same turn
	plan["site_id"] = sid
	plan["npc_ids"] = npc_ids
	return first



static func _merge_places(w: Dictionary, gen: Dictionary) -> Dictionary:
	for loc: String in gen.get("locations", {}):
		w["locations"][loc] = (gen["locations"][loc] as Dictionary).duplicate(true)
	if not w.has("sites"):
		w["sites"] = {}
	for sid: String in gen.get("sites", {}):
		w["sites"][sid] = (gen["sites"][sid] as Dictionary).duplicate(true)
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
	for rid: String in gen.get("room_variants", {}):  # v0.7.39.6: a quest's fight in a known room, a choice's change
		if not w["rooms"].has(rid):
			continue
		var variants: Array = (w["rooms"][rid].get("variants", []) as Array).duplicate(true)
		for v: Dictionary in gen["room_variants"][rid]:
			if not variants.any(func(x: Dictionary) -> bool: return str(x.get("vid", "")) == str(v.get("vid", "")) and not str(v.get("vid", "")).is_empty()):
				variants.append(v.duplicate(true))
		w["rooms"][rid]["variants"] = variants
	return w
