class_name EffectEngine
extends RefCounted
## engine.validate and the turn transaction (ADR-0008 §3–4, ADR-0009 §5): a proposed effect is checked
## against the state and the budgets, then *reserved* under the turn; the world changes only when
## turn.result lists its id. Unlisted reserves, errors, cancels and drops burn every reserve of the turn.
##
## `data` = {"rules": rules.json, "items": items.json, "world": world.json}.

## effect_id -> {"turn_id", "kind", "plan": what apply() does, "summary"}
var reserves: Dictionary = {}
## turn_id -> true once the master searched items this turn (required before creating one).
var searched: Dictionary = {}
## Catalog.data of the last validate: apply() needs the rules of casts, feature uses and items.
var _data: Dictionary = {}


## Lines an applied effect adds after its summary (the owner of a taken thing reacts, v0.7.0).
var _extra_lines: Array[String] = []

func mark_searched(turn_id: String) -> void:
	searched[turn_id] = true


## Drops every reserve (and the search mark) of `turn_id`.
func discard(turn_id: String) -> void:
	for id: String in reserves.keys():
		if reserves[id]["turn_id"] == turn_id:
			reserves.erase(id)
	searched.erase(turn_id)


func _of_turn(turn_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: String in reserves:
		if reserves[id]["turn_id"] == turn_id:
			out.append(reserves[id])
	return out


## Returns the engine.validate result: {accepted, effect_id, summary, item_id} or {accepted: false, reason}.
func validate(s: GameSession, data: Dictionary, turn_id: String, effect: Dictionary) -> Dictionary:
	_data = data
	var rules: Dictionary = data["rules"]
	var pending := _of_turn(turn_id)
	if pending.size() >= int(rules["turn_limits"]["max_effects"]):
		return _reject("лимит эффектов на ход исчерпан")
	var res := _plan(s, data, turn_id, effect, pending)
	if res.has("reason"):
		return _reject(str(res["reason"]))
	var id := s.next_effect_id()
	reserves[id] = {"turn_id": turn_id, "kind": str(effect.get("kind", "")), "plan": res["plan"], "summary": res["summary"]}
	var out := {"accepted": true, "effect_id": id, "summary": res["summary"]}
	if res["plan"].has("new_item_id"):
		out["item_id"] = res["plan"]["new_item_id"]
	return out


## Applies the listed reserves of `turn_id` in order, burns the rest. Returns the summaries shown to the player.
func apply(s: GameSession, turn_id: String, ids: Array) -> Array[String]:
	var lines: Array[String] = []
	for id: Variant in ids:
		var r: Dictionary = reserves.get(str(id), {})
		if r.is_empty() or r["turn_id"] != turn_id:
			continue
		_extra_lines.clear()
		_apply_one(s, r["kind"], r["plan"])
		lines.append(str(r["summary"]))
		lines.append_array(_extra_lines)  # an owner's reaction to a taken thing (v0.7.0)
	discard(turn_id)
	return lines


func _reject(reason: String) -> Dictionary:
	return {"accepted": false, "reason": reason}


func _plan(s: GameSession, data: Dictionary, turn_id: String, e: Dictionary, pending: Array[Dictionary]) -> Dictionary:
	var rules: Dictionary = data["rules"]
	var items: Dictionary = data["items"]
	var world := WorldView.new(data["world"])
	var c := s.character
	var level := int(c.get("level", 1))
	if s.mode == GameSession.MODE_COMBAT:
		if str(e.get("kind", "")) in ["move", "coins", "give_item", "take_item", "npc_attitude", "advance_time", "furnish", "take_prop"]:
			return {"reason": "в бою это нельзя: исход боя, переходы и добычу ведёт движок; здесь — проверки, урон и состояния врагам (target_id), подкрепление (start_combat)"}
		var tid := str(e.get("target_id", "")) if e.get("target_id") != null else ""
		if not tid.is_empty():
			return _plan_on_foe(s, data, e, tid)
	if str(e.get("kind", "")) == "start_combat":
		return _plan_fight(s, data, e)
	if s.mode == GameSession.MODE_TRADE and str(e.get("kind", "")) in ["coins", "give_item", "take_item"]:
		return {"reason": "в торговле сделки проводит панель сделки: назови цену и предложи игроку положить товар в сделку"}
	if s.mode == GameSession.MODE_SOCIAL and str(e.get("kind", "")) == "give_item" and world.is_trader(s.npc_id) 			and TradeRules.pack_stock(world.npc(s.npc_id), rules).has(str(e.get("item_id", ""))):
		return {"reason": "это товар торговца — покупка идёт через торговлю: назови цену и открой её (next_mode trade); монеты не списывай"}
	match str(e.get("kind", "")):
		"move":
			var to := str(e.get("room_id", ""))
			if pending.any(func(p: Dictionary) -> bool: return p["kind"] == "move"):
				return {"reason": "переход уже предложен в этом ходе"}
			if not ExplorationRules.open_exits(s, data["world"], s.room_id).has(to):
				return {"reason": "из этой комнаты нет выхода в %s" % to}
			return {"plan": {"room_id": to}, "summary": "Переход: %s" % world.room(to).get("name", to)}
		"damage":
			var dice := _damage_dice(rules, level, str(e.get("severity", "")))
			if dice.is_empty():
				return {"reason": "неизвестная тяжесть урона"}
			var amount := _roll(s.rng, int(dice[0]), int(dice[1]), 0)
			return {"plan": {"amount": amount}, "summary": "−%d HP (%s)" % [amount, e.get("damage_type", "урон")]}
		"heal":
			var h: Array = rules["heal_dice"].get(str(e.get("tier", "")), [])
			if h.is_empty():
				return {"reason": "неизвестная сила лечения"}
			if int(c["hp"]) >= int(c["max_hp"]):
				return {"reason": "персонаж и так здоров"}
			var amount := _roll(s.rng, int(h[0]), int(h[1]), int(h[2]))
			return {"plan": {"amount": amount}, "summary": "+%d HP" % amount}
		"coins":
			var delta := int(e.get("delta_cp", 0))
			if delta == 0:
				return {"reason": "пустое изменение монет"}
			var gold := int(c["gold_cp"]) + _pending_coins(pending)
			if delta < 0 and gold + delta < 0:
				return {"reason": "у персонажа нет %s (есть %s)" % [Money.format(-delta), Money.format(gold)]}
			if delta > _reward_cap(rules, level):
				return {"reason": "награда больше бюджета для %d уровня (до %s)" % [level, Money.format(_reward_cap(rules, level))]}
			return {"plan": {"delta": delta}, "summary": ("+" if delta > 0 else "") + Money.format(delta)}
		"give_item":
			return _plan_give(s, items, rules, turn_id, e, level)
		"take_item":
			var id := str(e.get("item_id", ""))
			var qty := int(e.get("qty", 1))
			var have := int(c["inventory"].get(id, 0)) - _pending_taken(pending, id)
			if have < qty:
				return {"reason": "у персонажа нет %s ×%d" % [id, qty]}
			return {"plan": {"item_id": id, "qty": qty},
				"summary": "Отдано: %s%s" % [ItemRules.display_name(items, s.items, id), " ×%d" % qty if qty > 1 else ""]}
		"npc_attitude":
			var npc_id := str(e.get("npc_id", ""))
			if not s.npcs_alive(world.npcs_in(s.room_id)).has(npc_id):
				return {"reason": "NPC %s нет в этой комнате" % npc_id}
			var delta := clampi(int(e.get("delta", 0)), -2, 2)
			if delta == 0:
				return {"reason": "пустое изменение отношения"}
			return {"plan": {"npc_id": npc_id, "delta": delta},
				"summary": "%s: отношение %+d" % [world.npc(npc_id).get("name", npc_id), delta]}
		"cast":
			var slots := {}
			for p: Dictionary in pending:
				if p["kind"] == "cast" and int(p["plan"]["slot"]) > 0:
					slots[int(p["plan"]["slot"])] = int(slots.get(int(p["plan"]["slot"]), 0)) + 1
			var chk := SpellRules.check(c, data, str(e.get("spell", "")), int(e.get("slot_level", 0)) if e.get("slot_level") != null else 0, slots)
			if chk.has("reason"):
				return {"reason": chk["reason"]}
			return {"plan": {"spell_id": chk["spell_id"], "slot": chk["slot"]},
				"summary": "Заклинание: " + SpellRules.describe(data, chk["spell_id"], chk["slot"])}
		"condition":
			var cond := str(e.get("condition", ""))
			if not ConditionRules.known(data, cond):
				return {"reason": "неизвестное состояние %s; есть: %s" % [cond, ", ".join((rules["conditions"] as Dictionary).keys())]}
			var on := bool(e.get("on", true))
			if not on and not ConditionRules.has(c, cond):
				return {"reason": "у персонажа нет состояния %s" % cond}
			var until := str(e.get("until", "long_rest"))
			return {"plan": {"condition": cond, "on": on, "until": until},
				"summary": ("Состояние: %s" if on else "Снято: %s") % str(rules["conditions"][cond]).get_slice(":", 0)}
		"use_feature":
			var rid := FeatureUses.resolve(c, data, str(e.get("feature", "")))
			var amount := int(e.get("amount", 1))
			var spent := 0
			for p: Dictionary in pending:
				if p["kind"] == "use_feature" and p["plan"]["id"] == rid:
					spent += int(p["plan"]["amount"])
			var why := FeatureUses.can_use(c, data, rid, amount, spent)
			if not why.is_empty():
				return {"reason": why}
			var heals: bool = not (FeatureUses.table(data)[rid].get("on_use", {}) as Dictionary).is_empty()
			return {"plan": {"id": rid, "amount": amount}, "summary": "Умение: %s%s" % [FeatureUses.display_name(c, data, rid),
				" (лечение движок посчитает сам, heal не нужен)" if heals else ""]}
		"use_item":
			var iid := str(e.get("item_id", ""))
			var in_use := pending.filter(func(p: Dictionary) -> bool: return p["kind"] == "use_item" and p["plan"]["item_id"] == iid).size()
			var why := ItemRules.can_use(c, data, s.items, iid, _pending_taken(pending, iid) + in_use)
			if not why.is_empty():
				return {"reason": why}
			return {"plan": {"item_id": iid}, "summary": "Использовано: %s" % ItemRules.display_name(items, s.items, iid)}
		"furnish":
			if pending.any(func(p: Dictionary) -> bool: return p["kind"] == "furnish"):
				return {"reason": "комната уже обставляется в этом ходе"}
			return PropRules.plan_furnish(s, data, e)
		"take_prop":
			return PropRules.plan_take(s, data, e)
		"prop_state":
			return PropRules.plan_state(s, e)
		"advance_time":
			var mins := int(e.get("minutes", 0))
			var cap := int(TimeRules.cfg(data)["max_master_minutes"])
			if mins <= 0 or mins > cap:
				return {"reason": "время — от 1 до %d минут за ход" % cap}
			if pending.any(func(p: Dictionary) -> bool: return p["kind"] == "advance_time"):
				return {"reason": "время уже сдвинуто в этом ходе"}
			return {"plan": {"minutes": mins}, "summary": "Прошло: %s" % _duration(mins)}
		"flag":
			var flag := str(e.get("flag", ""))
			if flag.is_empty():
				return {"reason": "пустой флаг"}
			return {"plan": {"flag": flag, "value": bool(e.get("value", true))}, "summary": "Отмечено: %s" % flag}
	return {"reason": "движок не знает эффект %s" % e.get("kind", "?")}


## Effects on an enemy in a fight (the master's improvisation): damage by severity, a condition.
func _plan_on_foe(s: GameSession, data: Dictionary, e: Dictionary, tid: String) -> Dictionary:
	var f := CombatRules.fighter(s, tid)
	if f.is_empty() or str(f.get("side")) != "enemy" or str(f.get("status")) != "active":
		return {"reason": "в бою нет такого врага: %s (есть: %s)" % [tid, ", ".join(CombatRules.enemies(s))]}
	match str(e.get("kind", "")):
		"damage":
			var dice := _damage_dice(data["rules"], int(s.character.get("level", 1)), str(e.get("severity", "")))
			if dice.is_empty():
				return {"reason": "неизвестная тяжесть урона"}
			var amount := _roll(s.rng, int(dice[0]), int(dice[1]), 0)
			return {"plan": {"foe": tid, "amount": amount}, "summary": "%s: −%d HP" % [f["name"], amount]}
		"condition":
			var cond := str(e.get("condition", ""))
			if not ConditionRules.known(data, cond):
				return {"reason": "неизвестное состояние %s" % cond}
			return {"plan": {"foe": tid, "condition": cond, "on": bool(e.get("on", true))},
				"summary": "%s: %s" % [f["name"], str(data["rules"]["conditions"][cond]).get_slice(":", 0)]}
	return {"reason": "на врага в бою — только damage и condition"}


## The master starts a fight: SRD monsters within the hard XP budget of the character's level (DMG). In a fight it is
## a reinforcement (v0.6.2): the foes still fighting and on the way plus the new ones stay within the same budget;
## they come at the edge column after rules.combat.reinforce_delay rounds.
func _plan_fight(s: GameSession, data: Dictionary, e: Dictionary) -> Dictionary:
	var foes: Array = []
	var xp := 0
	for spec: Variant in e.get("enemies", []):
		if not (spec is Dictionary):
			continue
		var mid := str(spec.get("monster", ""))
		var m: Dictionary = data["monsters"].get(mid, {})
		if m.is_empty():
			return {"reason": "нет такого монстра SRD: %s" % mid}
		var n := clampi(int(spec.get("count", 1)), 1, 6)
		xp += int(m["xp"]) * n
		foes.append({"monster": mid, "count": n, "name": str(spec.get("name", m["name"]))})
	if foes.is_empty():
		return {"reason": "кого звать в бой? enemies: [{monster, count}]"}
	var cap := int(CombatRules.cfg(data)["xp_budget_hard"].get(str(int(s.character.get("level", 1))), 750))
	if CombatRules.active(s):
		var in_play := CombatRules.xp_in_play(s, data)
		if in_play + xp > cap:
			return {"reason": "подкрепление не по силам %d уровню: в бою и на подходе %d опыта врагов, с новыми %d при пределе %d" % [int(s.character.get("level", 1)), in_play, in_play + xp, cap]}
		var side := str(e.get("side", "")) if e.get("side") != null else ""
		if not side in ["left", "right"]:
			side = "left" if s.rng.randi_range(0, 1) == 0 else "right"
		return {"plan": {"foes": foes, "reinforce": true, "side": side}, "summary": "Подкрепление: " + ", ".join(foes.map(func(f: Dictionary) -> String: return "%s ×%d" % [f["name"], f["count"]]))}
	if xp > cap:
		return {"reason": "бой слишком тяжёл для %d уровня: %d опыта врагов при пределе %d — меньше врагов или слабее" % [int(s.character.get("level", 1)), xp, cap]}
	return {"plan": {"foes": foes}, "summary": "Бой: " + ", ".join(foes.map(func(f: Dictionary) -> String: return "%s ×%d" % [f["name"], f["count"]]))}


func _plan_give(s: GameSession, items: Dictionary, rules: Dictionary, turn_id: String, e: Dictionary, level: int) -> Dictionary:
	var qty := int(e.get("qty", 1))
	var id := str(e.get("item_id", "")) if e.get("item_id") != null else ""
	var new_def := {}
	if e.get("item") is Dictionary:
		if not searched.has(turn_id):
			return {"reason": "сначала найди похожие предметы через find_items"}
		var chk := ItemRules.check_generated(items, e["item"], level)
		if not bool(chk["ok"]):
			return {"reason": chk["reason"]}
		new_def = chk["def"]
		id = ItemRules.generated_id(new_def)
		if items["catalog"].has(id):
			return {"reason": "такой предмет уже есть в каталоге: %s" % id}
	var def := new_def if not new_def.is_empty() else ItemRules.def_of(items, s.items, id)
	if def.is_empty():
		return {"reason": "предмета %s нет ни в каталоге, ни в игре; найди его через find_items" % id}
	if qty > 1 and not bool(def.get("stack", false)):
		return {"reason": "%s не складывается в стопку, дай по одному" % def.get("name", id)}
	if int(def.get("value_cp", 0)) * qty > _reward_cap(rules, level):
		return {"reason": "предмет дороже бюджета награды для %d уровня" % level}
	var plan := {"item_id": id, "qty": qty}
	if not new_def.is_empty():
		plan["new_item_id"] = id
		plan["def"] = new_def
	return {"plan": plan, "summary": "Получено: %s%s" % [def.get("name", id), " ×%d" % qty if qty > 1 else ""]}


func _apply_one(s: GameSession, kind: String, plan: Dictionary) -> void:
	var c := s.character
	if plan.has("foe"):
		var f := CombatRules.fighter(s, str(plan["foe"]))
		if kind == "damage":
			var tmp: Array[String] = []
			CombatRules._hurt_enemy(s, _data, f, int(plan["amount"]), tmp)
		elif bool(plan.get("on", true)):
			(f["conditions"] as Array).append(str(plan["condition"]))
		else:
			(f["conditions"] as Array).erase(str(plan["condition"]))
		return
	match kind:
		"move":
			s.room_id = plan["room_id"]
		"damage":
			c["hp"] = maxi(0, int(c["hp"]) - int(plan["amount"]))
		"heal":
			c["hp"] = mini(int(c["max_hp"]), int(c["hp"]) + int(plan["amount"]))
		"coins":
			c["gold_cp"] = int(c["gold_cp"]) + int(plan["delta"])
		"give_item":
			if plan.has("def"):
				s.items[plan["item_id"]] = plan["def"]
			c["inventory"][plan["item_id"]] = int(c["inventory"].get(plan["item_id"], 0)) + int(plan["qty"])
		"take_item":
			var left := int(c["inventory"].get(plan["item_id"], 0)) - int(plan["qty"])
			if left > 0:
				c["inventory"][plan["item_id"]] = left
			else:
				c["inventory"].erase(plan["item_id"])
		"npc_attitude":
			s.attitudes[plan["npc_id"]] = clampi(s.attitude(plan["npc_id"]) + int(plan["delta"]), -3, 3)
		"start_combat":
			if bool(plan.get("reinforce", false)) and CombatRules.active(s):
				CombatRules.add_incoming(s, _data, plan["foes"], int(s.combat["round"]) + int(CombatRules.cfg(_data)["reinforce_delay"]), str(plan["side"]))
			else:
				s.pending_fight = plan["foes"]
		"cast":
			SpellRules.cast(c, _data, plan["spell_id"], int(plan["slot"]))
		"condition":
			if bool(plan["on"]):
				ConditionRules.add(c, plan["condition"], plan["until"])
			else:
				ConditionRules.remove(c, plan["condition"])
		"use_feature":
			FeatureUses.use(c, _data, plan["id"], int(plan["amount"]), s.rng)
		"use_item":
			ItemRules.use(c, _data, s.items, plan["item_id"], s.rng)
		"advance_time":
			TimeRules.advance(s, _data, int(plan["minutes"]))
		"furnish":
			PropRules.apply_furnish(s, plan)
		"take_prop":
			_extra_lines.append_array(PropRules.apply_take(s, _data, plan))
		"prop_state":
			PropRules.apply_state(s, plan)
		"flag":
			if bool(plan["value"]) and not s.flags.has(plan["flag"]):
				s.flags.append(plan["flag"])
			elif not bool(plan["value"]):
				s.flags.erase(plan["flag"])


static func _damage_dice(rules: Dictionary, level: int, severity: String) -> Array:
	for row: Dictionary in rules["damage_dice_by_level"]:
		if level <= int(row["max_level"]):
			return row.get(severity, [])
	return []


static func _reward_cap(rules: Dictionary, level: int) -> int:
	for row: Array in rules["reward_max_cp_by_level"]:
		if level <= int(row[0]):
			return int(row[1])
	return 0


static func _roll(rng: RandomNumberGenerator, count: int, sides: int, bonus: int) -> int:
	var total := bonus
	for i in count:
		total += rng.randi_range(1, sides)
	return total


static func _pending_coins(pending: Array[Dictionary]) -> int:
	var sum := 0
	for p: Dictionary in pending:
		if p["kind"] == "coins":
			sum += int(p["plan"]["delta"])
	return sum


static func _pending_taken(pending: Array[Dictionary], id: String) -> int:
	var sum := 0
	for p: Dictionary in pending:
		if p["kind"] == "take_item" and p["plan"]["item_id"] == id:
			sum += int(p["plan"]["qty"])
	return sum


static func _duration(mins: int) -> String:
	if mins < 60:
		return "%d мин" % mins
	return "%d ч%s" % [mins / 60, (" %d мин" % (mins % 60)) if mins % 60 > 0 else ""]

