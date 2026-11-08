class_name ServiceRules
extends RefCounted
## A service (v0.8.4.35, pillar 6, concepts.md «Услуга»): a paid act a person does for the hero, a row of data over an
## operation of the engine (`op`). The rules' rows (item_rules.services), the pack's (world.services) and the master's
## (create:service, kept in gen.services) are one registry; a person offers the ids of its `services` — a trader or
## anybody. Ops: identify, lift_curse, cure_disease, teach_recipe, rumor, meal; enchant — a mark on one copy of a thing
## (a silvered sword stays the same sword, ItemRules.copy_def reads it); status — a status on the hero for hours or until
## the long rest. The master builds the last two; the engine sets their price (rules.services).

const MADE_OPS: Array[String] = ["status", "enchant"]
## The target of a status: the hero itself.
const HERO := "hero"


static func cfg(data: Dictionary) -> Dictionary:
	return data["rules"].get("services", {})


## A service by id: the pack's or the master's (world.services) over the rules'; {} — unknown.
static func def_of(data: Dictionary, id: String) -> Dictionary:
	var own: Dictionary = data["world"].get("services", {})
	return own.get(id, ItemRules.cfg(data)["services"].get(id, {}))


## The ids a person offers.
static func ids_of(data: Dictionary, npc_id: String) -> Array:
	return data["world"]["npcs"].get(npc_id, {}).get("services", [])


## The services of a person: [{id, name, cost_cp, why, targets}] — `why` "" when it can be bought now, otherwise a
## localization key; `targets` — what it would act on (things of the hero, or `hero`).
static func of(s: GameSession, data: Dictionary, npc_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: Variant in ids_of(data, npc_id):
		var def := def_of(data, str(id))
		if def.is_empty():
			continue
		var cost := BondRules.service_cost(s, data, npc_id, int(def["cost_cp"]))  # v0.7.31
		var on := targets(s, data, str(id))
		var why := SocialRules.service_why(s, data, npc_id)  # v0.7.22.18 (#30), v0.7.49: the wanted, a desecrator
		if why.is_empty() and Ledger.balance(s) < cost:
			why = "TRADE_ERR_NO_COINS"
		elif why.is_empty() and on.is_empty():
			why = _nothing(s, data, def)
		out.append({"id": str(id), "cost_cp": cost, "why": why, "name": str(def.get("name", id)), "targets": on, "op": str(def.get("op", ""))})
	return out


## Why a service has nothing to act on: a key.
static func _nothing(s: GameSession, data: Dictionary, def: Dictionary) -> String:
	match str(def.get("op", "")):
		"cure_disease":
			return "SERVICE_HERBS_CANNOT" if not DiseaseRules.curable(s, data, "magic").is_empty() else "SERVICE_NOTHING"
		"teach_recipe":
			return CraftRules.teach_why(s, data, def)
		"status":
			return "SERVICE_ACTIVE"
	return "SERVICE_NOTHING"


## What the service would act on now: the unknown things, the cursed ones, the copies it can mark, the hero.
static func targets(s: GameSession, data: Dictionary, id: String) -> Array[String]:
	var def := def_of(data, id)
	match str(def.get("op", "")):
		"identify":
			return ItemRules.unknown_ids(s.character)
		"lift_curse":
			return cursed_held(s, data)
		"cure_disease":  # v0.7.23.1: a healer sees a disease even before it shows
			return DiseaseRules.curable(s, data, str(def.get("power", "magic")))
		"enchant":
			return markable(s, data, def)
		"teach_recipe":  # v0.7.24
			return CraftRules.teachable(s, data, def)
		"rumor":  # v0.7.47: a rumour of the place the hero has not heard
			return RumorRules.for_sale(s, data)
		"meal":  # v0.7.23: only when the hero is hungry or thirsty
			var hungry := NeedRules.on(s) and (NeedRules.value(s, data, "food") < 75.0 or NeedRules.value(s, data, "water") < 75.0)
			var meal: Array[String] = []
			if hungry:
				meal.append("meal")
			return meal
		"status":  # not twice at once
			var on := ConditionRules.effects(s.character).any(func(e: Dictionary) -> bool: return str(e.get("source", {}).get("id", "")) == id and str(e.get("source", {}).get("kind", "")) == "service")
			var out: Array[String] = []
			if not on:
				out.append(HERO)
			return out
	return []


static func cursed_held(s: GameSession, data: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for id: String in s.character.get("inventory", {}):
		if ItemRules.held_by_curse(s.character, data, s.items, id):
			out.append(id)
	return out


## The hero's things an `enchant` takes: of its `needs` kind, a copy still without its `property`.
static func markable(s: GameSession, data: Dictionary, def: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var needs := str(def.get("needs", "any"))
	var prop := str(def.get("property", ""))
	var c := s.character
	for id: String in c.get("inventory", {}):
		var d := ItemRules.def_of(data["items"], s.items, id)
		if d.is_empty() or FeatureRules.pact_made(data, s.items, id) or str(d.get("item_type", "")) == "consumable":
			continue
		if not (needs == "any" or d.has(needs)) or (d.get("properties", []) as Array).has(prop):
			continue
		if range(Thing.count(c, id)).any(func(i: int) -> bool: return not ItemRules.marks(c, id, i).has(prop)):
			out.append(id)
	return out


## "" or why the hero cannot buy service `id` of `npc_id` on `item` now (a key).
static func why(s: GameSession, data: Dictionary, npc_id: String, id: String, item: String = "") -> String:
	if not s.npcs_here(data["world"], s.room_id).has(npc_id) or Being.dead(s, npc_id):
		return "SERVICE_NOT_HERE"
	for sv: Dictionary in of(s, data, npc_id):
		if str(sv["id"]) != id:
			continue
		if not str(sv["why"]).is_empty():
			return str(sv["why"])
		return "" if item.is_empty() or (sv["targets"] as Array).has(item) else "SERVICE_NOTHING"
	return "SERVICE_NOTHING"


## Buys a service (`item` — the thing it acts on, the first target by default; `free` — a favor by words, v0.7.15.2). Lines.
static func buy(s: GameSession, data: Dictionary, npc_id: String, id: String, item: String = "", free: bool = false) -> Array[String]:
	var c := s.character
	var sv := def_of(data, id)
	var cost := 0 if free else BondRules.service_cost(s, data, npc_id, int(sv["cost_cp"]))
	Ledger.add(s, -cost, "trade:buy_service")
	var lines: Array[String] = ["Услуга даром" if free else "Услуга: −%s" % Money.format(cost)]
	match str(sv["op"]):
		"meal":
			lines.append_array(NeedRules.meal(s, data))
		"rumor":
			lines.append_array(RumorRules.sell(s, data, npc_id))
		"identify":
			lines.append_array(ItemRules.identify(c, data, s.items))
		"lift_curse":
			lines.append_array(ItemRules.lift_curse(c, data, s.items))
		"cure_disease":
			lines.append_array(DiseaseRules.cure(s, data, str(sv.get("power", "magic"))))
		"teach_recipe":
			lines.append_array(CraftRules.learn(s, data, str(sv["recipe"])))
		"enchant":
			var thing := item if not item.is_empty() else _pick(c, markable(s, data, sv))
			ItemRules.mark(c, thing, str(sv["property"]), _held_first(c, thing))
			lines.append("%s: %s" % [sv.get("done", "готово"), ItemRules.display_name(data["items"], s.items, thing)])
		"status":
			var st := str(sv["status"])
			var ends := {"rest": "long"} if bool(sv.get("rest", false)) else {"at": ConditionRules.now(s) + int(sv.get("hours", 1)) * 60 * ConditionRules.ROUNDS_PER_MINUTE}
			var told := ConditionRules.impose(s, data, {"condition": st, "ends": ends, "source": {"kind": "service", "id": id, "name": str(sv.get("name", id)), "npc": npc_id}})
			lines.append_array(told)
			if told.is_empty():
				lines.append("%s: %s, %s" % [sv.get("done", "готово"), ConditionRules.name_of(data, st), _time_text(sv)])
	CharacterRules.refresh(c, data, s.items)
	return lines


## The first of `ids` the hero wears or holds, else the first.
static func _pick(c: Dictionary, ids: Array[String]) -> String:
	for id: String in ids:
		if CharacterRules.held_copies(c, id) > 0:
			return id
	return ids[0]


## The copies a hand holds go first: the mark lands on the sword in the hand, not on the one in the pack.
static func _held_first(c: Dictionary, id: String) -> Array[int]:
	var out: Array[int] = []
	for slot: String in CharacterRules.SLOTS:
		if str(c.get("equipped", {}).get(slot, "")) == id:
			out.append(CharacterRules.hold_index(c, id, slot))
	return out


static func _time_text(sv: Dictionary) -> String:
	return "до долгого отдыха" if bool(sv.get("rest", false)) else "на %d ч" % int(sv.get("hours", 1))


## What the service will do, told before it is done (a favor by words: the master narrates it, never invents it).
static func outcome(s: GameSession, data: Dictionary, id: String, item: String) -> Array[String]:
	var c: Dictionary = s.character.duplicate(true)
	var sv := def_of(data, id)
	match str(sv.get("op", "")):
		"meal":
			return ["Сыт и напоен"]
		"identify":
			return ItemRules.identify(c, data, s.items.duplicate(true))
		"lift_curse":
			return ItemRules.lift_curse(c, data, s.items)
		"cure_disease":
			return ["исцеление болезни"]
		"teach_recipe":
			return ["урок ремесла: %s" % CraftRules.recipe_name(s, data, str(sv.get("recipe", "")))]
		"enchant":
			var thing := item if not item.is_empty() else _pick(s.character, targets(s, data, id))
			return ["%s: %s" % [sv.get("done", "готово"), ItemRules.display_name(data["items"], s.items, thing)]]
		"status":
			return ["%s: %s, %s" % [sv.get("done", "готово"), ConditionRules.name_of(data, str(sv["status"])), _time_text(sv)]]
	return []


## A service's name for the lines and the master: «опознание вещей» (`short` of its data).
static func short(data: Dictionary, id: String) -> String:
	var sv := def_of(data, id)
	return str(sv.get("short", sv.get("name", id)))


## What a healer's services can cure: "magic", "herbs", "" — nothing. The op of a service, not a list of healers.
static func art(data: Dictionary, npc_id: String) -> String:
	var out := ""
	for id: Variant in ids_of(data, npc_id):
		var d := def_of(data, str(id))
		if str(d.get("op", "")) == "cure_disease":
			out = "magic" if str(d.get("power", "herbs")) == "magic" else out if not out.is_empty() else "herbs"
	return out


# --- the master's service (effect create:service) ------------------------------------------------------------------


## The price of a service the master builds, by the engine: a status by its points and time, a mark by its points.
static func price(data: Dictionary, sv: Dictionary) -> int:
	var m := cfg(data)
	if str(sv["op"]) == "status":
		var hours := int(m["rest_hours"]) if bool(sv.get("rest", false)) else int(sv["hours"])
		var row := Scale.up_to(m["durations"], hours, "hours")
		var mult := int(row.get("mult", (m["durations"] as Array)[-1]["mult"]))
		return int(m["status_point_cp"]) * maxi(1, int(MakeRules.def_of(data, str(sv["status"])).get("points", 1))) * mult
	return int(m["property_point_cp"]) * maxi(1, int(data["items"]["properties"].get(str(sv["property"]), 1)))


## The effect `create:service`: a service of a person of the scene (or `new` — the person of this turn). {plan, summary}
## or {reason}. `status` and `property` are already ids (a `new:<key>` of this turn's `make` resolved).
static func make(s: GameSession, data: Dictionary, spec: Dictionary) -> Dictionary:
	var m := cfg(data)
	var who := str(spec.get("npc_id", ""))
	if who != "new" and (not s.npcs_here(data["world"], s.room_id).has(who) or Being.dead(s, who)):
		return {"reason": "%s не в сцене — услугу заводят у того, кто здесь (или «new» — человек create:npc этого хода)" % who}
	if who != "new" and ids_of(data, who).size() >= int(m["per_npc"]):
		return {"reason": "у %s уже %d услуг — больше не бывает" % [WorldView.name_of(data, who), int(m["per_npc"])]}
	var op := str(spec.get("op", ""))
	if not MADE_OPS.has(op):
		return {"reason": "op — %s" % ", ".join(MADE_OPS)}
	var name := str(spec.get("name", "")).strip_edges().left(60)
	if name.is_empty():
		return {"reason": "нужно name: как услуга зовётся на кнопке"}
	var sv := {"op": op, "name": name, "short": name.to_lower(), "master": true}
	var done := str(spec.get("done", "")).strip_edges().left(40) if spec.get("done") != null else ""
	sv["done"] = done if not done.is_empty() else "готово"
	if op == "status":
		var st := str(spec.get("status", "")) if spec.get("status") != null else ""
		var made := MakeRules.def_of(data, st)
		if str(made.get("what", "")) != "status":
			return {"reason": "status — статус, собранный make (what=status) этого или прошлого хода: new:<key> или его id"}
		if bool(made.get("harm", false)):
			return {"reason": "«%s» вредит — услуга даёт пользу; вред ложится эффектом condition" % made.get("name", st)}
		sv["status"] = st
		if spec.get("rest") == true:
			sv["rest"] = true
		else:
			var hours := int(spec.get("hours", 0)) if spec.get("hours") != null else 0
			var bounds: Array = m["hours"]
			if hours < int(bounds[0]) or hours > int(bounds[1]):
				return {"reason": "hours — от %d до %d (или rest: до долгого отдыха)" % [int(bounds[0]), int(bounds[1])]}
			sv["hours"] = hours
	else:
		var prop := str(spec.get("property", "")) if spec.get("property") != null else ""
		var points: Variant = data["items"]["properties"].get(prop)
		if points == null or int(points) <= 0:
			return {"reason": "property — свойство вещи: токен (silvered, fire_damage, magic_plus1…) или собранное make (what=property)"}
		var rarity := ItemRules.rarity_for_points(data["items"], int(points))
		var level := int(s.character.get("level", 1))
		if level < ItemRules.rarity_level(data["items"], rarity):
			return {"reason": "«%s» — редкость %s, это от %d уровня героя, а герой %d" % [prop, rarity, ItemRules.rarity_level(data["items"], rarity), level]}
		var needs := str(spec.get("needs", "any")) if spec.get("needs") != null else "any"
		var built: Dictionary = data["rules"].get("made", {}).get(prop, {})
		if needs == "any" and not str(built.get("on", "")).is_empty():
			needs = str(built["on"])
		if not (m["needs"] as Array).has(needs):
			return {"reason": "needs — %s" % ", ".join(m["needs"])}
		sv["property"] = prop
		sv["needs"] = needs
	sv["cost_cp"] = price(data, sv)
	var id := "svc_" + ("%s|%s|%s" % [name, op, sv.get("status", sv.get("property", ""))]).md5_text().left(8)
	return {"plan": {"npc": who, "id": id, "def": sv},
		"summary": "Услуга «%s» у %s за %s" % [name, "нового человека" if who == "new" else WorldView.name_of(data, who), Money.format(int(sv["cost_cp"]))]}


static func apply_make(s: GameSession, data: Dictionary, plan: Dictionary, made_npc: String) -> Array[String]:
	var who := str(plan["npc"])
	if who == "new":
		if made_npc.is_empty():
			return ["Услуга не заведена: человек не создан"]
		who = made_npc
	var id := str(plan["id"])
	var gen := WorldGen.generated(s)
	var all: Dictionary = gen.get("services", {})
	all[id] = (plan["def"] as Dictionary).duplicate(true)
	gen["services"] = all
	if not data["world"].has("services"):
		data["world"]["services"] = {}
	data["world"]["services"][id] = (plan["def"] as Dictionary).duplicate(true)
	if not ids_of(data, who).has(id):
		Overlay.add(s, data, EntityRef.npc(who), "services", id)
	return ["%s: новая услуга «%s» за %s — кнопка «Услуги» в её действиях" % [WorldView.name_of(data, who), plan["def"]["name"], Money.format(int(plan["def"]["cost_cp"]))]]


## For the master: the services of the people of the scene, with their prices and what they do.
static func text(s: GameSession, data: Dictionary) -> String:
	var rows: Array[String] = []
	for npc: String in s.npcs_here(data["world"], s.room_id):
		var names: Array[String] = []
		for id: Variant in ids_of(data, npc):
			var sv := def_of(data, str(id))
			if not sv.is_empty():
				names.append("%s (%s, %s)" % [sv.get("name", id), str(id), Money.format(int(sv["cost_cp"]))])
		if not names.is_empty():
			rows.append("%s: %s" % [WorldView.name_of(data, npc), "; ".join(names)])
	return "\n".join(rows)
