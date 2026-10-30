class_name ReputationRules
extends RefCounted
## Reputation in a settlement (roadmap v0.7.17 «Торговля 2.0», the author's decision: one per settlement, steps
## −3…+3 shown in words). A concept of the engine: a pack location with `settlement: true` keeps the hero's points
## (`s.reputation`); the step comes from rules.reputation.thresholds. Points come from the engine's facts — a quest
## of the place done, a murder known, a theft caught, a crime atoned — and from the master's effect `reputation`
## for deeds the place learned of. The step moves the prices of every trader there and sets the attitude of the
## people the hero has not dealt with yet (`s.attitude_base`).


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"]["reputation"]


static func is_settlement(data: Dictionary, loc: String) -> bool:
	return bool(data["world"]["locations"].get(loc, {}).get("settlement", false))


static func points(s: GameSession, loc: String) -> int:
	return int(s.reputation.get(loc, 0))


## −3…+3 by the thresholds of the points.
static func step(s: GameSession, data: Dictionary, loc: String) -> int:
	var p := points(s, loc)
	var out := 0
	for t: Variant in cfg(data)["thresholds"]:
		if p >= int(t):
			out += 1
		elif p <= -int(t):
			out -= 1
	return out


static func word(data: Dictionary, st: int) -> String:
	return str(cfg(data)["names"][str(st)])


## The room of an NPC in the world ("" — none).
static func home_room(data: Dictionary, npc_id: String) -> String:
	var rooms: Dictionary = data["world"]["rooms"]
	for rid: String in rooms:
		if (rooms[rid].get("npcs", []) as Array).has(npc_id):
			return rid
	return ""


## The pack location of an NPC ("" — none).
static func home_of(data: Dictionary, npc_id: String) -> String:
	var rooms: Dictionary = data["world"]["rooms"]
	for rid: String in rooms:
		if (rooms[rid].get("npcs", []) as Array).has(npc_id):
			return str(rooms[rid].get("location_id", ""))
	return ""


## Adds points in `loc` (a settlement; elsewhere nothing). Lines: «Ольховый Брод: о вас говорят хорошо — свой».
## v0.7.47: the deed goes on as a rumour (`spread`) — the neighbours learn of it only when it arrives.
static func add(s: GameSession, data: Dictionary, loc: String, delta: int, why: String, spread: bool = true) -> Array[String]:
	var lines: Array[String] = []
	if spread and delta != 0:
		RumorRules.on_fame(s, data, loc, delta, why)
	if delta == 0 or not is_settlement(data, loc):
		return lines
	var before := step(s, data, loc)
	s.reputation[loc] = points(s, loc) + delta
	var after := step(s, data, loc)
	var name := str(data["world"]["locations"][loc].get("name", loc))
	if after != before:
		lines.append("%s: репутация %s — теперь вы «%s»%s" % [name, "растёт" if delta > 0 else "падает", word(data, after),
			" (%s)" % why if not why.is_empty() else ""])
	refresh(s, data)
	return lines


## The attitude of the people not dealt with yet, by the reputation of their place.
static func refresh(s: GameSession, data: Dictionary) -> void:
	s.attitude_base.clear()
	var table: Dictionary = cfg(data)["stranger_attitude"]
	for id: String in data["world"]["npcs"]:
		var loc := home_of(data, id)
		if is_settlement(data, loc):
			var a := int(table[str(step(s, data, loc))])
			if a != 0:
				s.attitude_base[id] = a
		var f := FactionRules.attitude_bonus(s, data, id)  # v0.7.50
		if f != 0:
			s.attitude_base[id] = int(s.attitude_base.get(id, 0)) + f


## The price percent of the trader's place: `side` "buy" (the hero pays) or "sell" (the trader pays).
static func price_pct(s: GameSession, data: Dictionary, npc_id: String, side: String) -> int:
	var loc := home_of(data, npc_id)
	if not is_settlement(data, loc):
		return 100
	return int(cfg(data)["%s_pct" % side][str(step(s, data, loc))])


## For the master and the journal: «Ольховый Брод — свой (+1)», "" outside a settlement.
static func text(s: GameSession, data: Dictionary, loc: String) -> String:
	if not is_settlement(data, loc):
		return ""
	var st := step(s, data, loc)
	return "%s — %s (%+d)" % [data["world"]["locations"][loc].get("name", loc), word(data, st), st]


## The plan of the master's effect `reputation`: {plan, summary} or {reason}.
static func plan(s: GameSession, data: Dictionary, delta: int, why: String, pending: Array[Dictionary]) -> Dictionary:
	var loc := WorldView.new(data["world"]).location_id(s.room_id)
	if not is_settlement(data, loc):
		return {"reason": "здесь не поселение: репутация — только у поселений пакета"}
	var most := int(cfg(data)["master_max"])
	if delta == 0 or absi(delta) > most:
		return {"reason": "репутация за поступок — от −%d до +%d" % [most, most]}
	if why.strip_edges().length() < 5:
		return {"reason": "нужна причина: что сделал герой и кто об этом узнал"}
	if pending.any(func(p: Dictionary) -> bool: return p["kind"] == "reputation"):
		return {"reason": "репутация меняется не больше раза за ход"}
	return {"plan": {"reputation": loc, "delta": delta, "why": why.strip_edges().left(120)},
		"summary": "%s: %s" % [data["world"]["locations"][loc].get("name", loc), "о герое говорят лучше" if delta > 0 else "о герое говорят хуже"]}
