class_name WorldGen
extends RefCounted
## People and places the master creates (roadmap v0.7.20, ADR-0008 «Новые NPC и места»; pillar 6): not invented in
## words but made by the engine from the pack's own schema, after a search, with its checks. What is made lives in the
## save of this game only (s.generated) — another game of the same world does not see it until the author moves it into
## the pack (tools/promote_world.py). The game merges it into its own copy of the pack's world (`merged`), so every rule
## that reads data["world"] treats a made NPC as one of the pack.
##
## s.generated = {"npcs": {id: def}, "npc_rooms": {id: room_id}}.


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"]["world_gen"]


## The pack's world with what this game made, a deep copy (the pack itself is never touched).
static func merged(pack_world: Dictionary, gen: Dictionary) -> Dictionary:
	var w := pack_world.duplicate(true)
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
